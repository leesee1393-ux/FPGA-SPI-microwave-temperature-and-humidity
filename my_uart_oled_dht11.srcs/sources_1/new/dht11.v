`timescale 1ns / 1ps

module dht11 #(
    parameter integer LOW_18MS       = 1_800_000,
    parameter integer RELEASE_30US   = 3_000,
    parameter integer HIGH_THRESHOLD = 5_000,
    parameter integer TIMEOUT_100US  = 10_000
) (
    input clk,
    input reset,
    input start,

    input io_mode,       // 1: 입력 모드, 0: 출력 모드
    input o_data,        // 출력할 데이터
    output i_data,       // 읽은 데이터
    inout dht11_data,    // 실제 DHT11 DATA 핀

    output reg [15:0] humidity,
    output reg [15:0] temperature,
    output reg [7:0] checksum,
    output reg data_valid
);


    reg [7:0] r_done_count;
    reg [7:0] r_checksum_fail_count;
    reg [7:0] r_timeout_count;
    // FSM 상태
    localparam IDLE          = 4'd0;
    localparam START_LOW     = 4'd1;
    localparam START_RELEASE = 4'd2;
    localparam RESP_WAIT_LOW = 4'd3;
    localparam RESP_LOW      = 4'd4;
    localparam RESP_HIGH     = 4'd5;
    localparam BIT_LOW       = 4'd6;
    localparam BIT_HIGH      = 4'd7;
    localparam DONE          = 4'd8;
    localparam ERROR         = 4'd9;
    localparam VALID         = 4'd10;

    reg [3:0] r_state;
    reg [$clog2(5_500_000)-1:0] r_counter;
    reg [5:0] r_bit_count;
    reg [39:0] r_data;

    reg r_io_mode;
    reg r_o_data;
    reg r_i_data_meta;
    reg r_i_data_sync;

    // FSM 동작 중에는 내부 io_mode가 우선
    wire w_io_mode =
        (r_state == IDLE) ? io_mode : r_io_mode;

    wire w_o_data =
        (r_state == IDLE) ? o_data : r_o_data;

    // DHT11은 LOW만 구동하고 HIGH는 풀업으로 생성
    assign dht11_data =
        (w_io_mode == 1'b0 && w_o_data == 1'b0)
        ? 1'b0 : 1'bz;

    // DHT11 DATA is asynchronous to clk; two flip-flops add only 20 ns at 100 MHz.
    assign i_data = r_i_data_sync;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_i_data_meta <= 1'b1;
            r_i_data_sync <= 1'b1;
        end
        else begin
            r_i_data_meta <= dht11_data;
            r_i_data_sync <= r_i_data_meta;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_state     <= IDLE;
            r_counter   <= 0;
            r_bit_count <= 0;
            r_data      <= 0;

            r_io_mode   <= 1'b1;
            r_o_data    <= 1'b0;

            humidity    <= 0;
            temperature <= 0;
            checksum    <= 0;
            data_valid  <= 0;

                r_done_count          <= 0;
                r_checksum_fail_count <= 0;
                r_timeout_count       <= 0;
        end
        else begin
            data_valid <= 0;

            case (r_state)

                // 측정 시작 대기
                IDLE: begin
                    r_counter   <= 0;
                    r_bit_count <= 0;
                    r_io_mode   <= 1'b1;
                    r_o_data    <= 1'b0;

                    if (start && io_mode) begin
                        r_data  <= 0;
                        r_state <= START_LOW;
                    end
                end

                // FPGA가 DATA를 18ms LOW로 유지
                START_LOW: begin
                    r_io_mode <= 1'b0;
                    r_o_data  <= 1'b0;

                    if (r_counter == LOW_18MS - 1) begin
                        r_counter <= 0;
                        r_io_mode <= 1'b1;
                        r_state   <= START_RELEASE;
                    end
                    else begin
                        r_counter <= r_counter + 1'b1;
                    end
                end

                // DATA 해제 후 센서 응답 대기
                START_RELEASE: begin
                    r_io_mode <= 1'b1;

                    if (r_counter == RELEASE_30US - 1) begin
                        r_counter <= 0;
                        r_state   <= RESP_WAIT_LOW;
                    end
                    else begin
                        r_counter <= r_counter + 1'b1;
                    end
                end

                // 센서의 LOW 응답 확인
                RESP_WAIT_LOW: begin
                    if (i_data == 1'b0) begin
                        r_counter <= 0;
                        r_state   <= RESP_LOW;
                    end
                    else if (r_counter >= TIMEOUT_100US) begin
                        r_state <= ERROR;
                    end
                    else begin
                        r_counter <= r_counter + 1'b1;
                    end
                end

                // 약 80us LOW 응답 종료 대기
                RESP_LOW: begin
                    if (i_data == 1'b1) begin
                        r_counter <= 0;
                        r_state   <= RESP_HIGH;
                    end
                    else if (r_counter >= TIMEOUT_100US) begin
                        r_state <= ERROR;
                    end
                    else begin
                        r_counter <= r_counter + 1'b1;
                    end
                end

                // 약 80us HIGH 응답 종료 대기
                RESP_HIGH: begin
                    if (i_data == 1'b0) begin
                        r_counter <= 0;
                        r_state   <= BIT_LOW;
                    end
                    else if (r_counter >= TIMEOUT_100US) begin
                        r_state <= ERROR;
                    end
                    else begin
                        r_counter <= r_counter + 1'b1;
                    end
                end

                // 데이터 비트의 LOW 구간
                BIT_LOW: begin
                    if (i_data == 1'b1) begin
                        r_counter <= 0;
                        r_state   <= BIT_HIGH;
                    end
                    else if (r_counter >= TIMEOUT_100US) begin
                        r_state <= ERROR;
                    end
                    else begin
                        r_counter <= r_counter + 1'b1;
                    end
                end

                // HIGH 구간 길이로 0과 1 구분
                BIT_HIGH: begin
                    if (i_data == 1'b0) begin

                        r_data <= {
                            r_data[38:0],
                            (r_counter >= HIGH_THRESHOLD)
                        };

                        r_counter <= 0;

                        if (r_bit_count == 39)
                            r_state <= DONE;
                        else begin
                            r_bit_count <= r_bit_count + 1'b1;
                            r_state <= BIT_LOW;
                        end
                    end
                    else if (r_counter >= TIMEOUT_100US) begin
                        r_counter<=0;
                        r_state <= ERROR;
                    end
                    else begin
                        r_counter <= r_counter + 1'b1;
                    end
                end

                // 40비트 데이터 검증
                DONE: begin

                    // 40비트 수신 완료 횟수
                    r_done_count <= r_done_count + 1'b1;

                    if (r_data[7:0] ==
                        ((r_data[39:32] +
                        r_data[31:24] +
                        r_data[23:16] +
                        r_data[15:8]) & 8'hFF)) begin

                        humidity    <= r_data[39:24];
                        temperature <= r_data[23:8];
                        checksum    <= r_data[7:0];
                        // VALID is one clock later so consumers see the new registers.
                        r_state <= VALID;
                    end
                    else begin
                        // 체크섬 실패 횟수 증가
                        r_checksum_fail_count <=
                            r_checksum_fail_count + 1'b1;
                        r_state <= IDLE;
                    end
                end

                VALID: begin
                    data_valid <= 1'b1;
                    r_state    <= IDLE;
                end

                ERROR: begin
                    r_timeout_count <= r_timeout_count + 1'b1;
                    r_io_mode <= 1'b1;
                    r_counter <= 0;
                    r_state   <= IDLE;
                end

                default: begin
                    r_state <= IDLE;
                end

            endcase
        end
    end

endmodule
