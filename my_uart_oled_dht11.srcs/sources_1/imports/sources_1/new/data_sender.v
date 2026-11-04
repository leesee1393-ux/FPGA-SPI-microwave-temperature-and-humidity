
`timescale 1ns / 1ps

module data_sender(
    input clk,
    input reset,

    input [15:0] temperature,
    input [15:0] humidity,
    input [15:0] distance_cm,

    input start_trigger,
    input distance_valid,
    input tx_busy,

    output reg tx_start,
    output reg [7:0] tx_data
);

    // "TEMP: 25.30\r\nHUM : 60.00\r\nDIST: 0123 cm\r\n"
    localparam [5:0] STR_LEN = 6'd41;

    localparam IDLE      = 2'd0;
    localparam SEND      = 2'd1;
    localparam WAIT_BUSY = 2'd2;
    localparam WAIT_DONE = 2'd3;

    reg [1:0] r_state;
    reg [5:0] r_send_cnt;

    // 전송 중 값 변경 방지를 위해 저장
    reg [15:0] r_temperature;
    reg [15:0] r_humidity;
    reg [15:0] r_distance_cm;
    reg r_pending;

    wire w_new_data = start_trigger || distance_valid;

    wire [7:0] w_char;

    ascii_string_table u_ascii_string_table(
        .index(r_send_cnt),
        .temperature(r_temperature),
        .humidity(r_humidity),
        .distance_cm(r_distance_cm),
        .data(w_char)
    );

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            r_state       <= IDLE;
            r_send_cnt    <= 0;
            r_temperature <= 0;
            r_humidity    <= 0;
            r_distance_cm <= 0;
            r_pending     <= 0;

            tx_start <= 0;
            tx_data  <= 0;
        end
        else begin
            tx_start <= 0;

            if (w_new_data) begin
                r_temperature <= temperature;
                r_humidity    <= humidity;
                r_distance_cm <= distance_cm;
                if (r_state != IDLE)
                    r_pending <= 1'b1;
            end

            case(r_state)

                IDLE: begin
                    if(w_new_data) begin
                        r_send_cnt    <= 0;
                        r_state       <= SEND;
                    end
                end

                // 다음 ASCII 문자 송신 요청
                SEND: begin
                    if(r_send_cnt == STR_LEN) begin
                        r_state <= IDLE;
                    end
                    else if(!tx_busy) begin
                        tx_data  <= w_char;
                        tx_start <= 1'b1;
                        r_state  <= WAIT_BUSY;
                    end
                end

                // UART TX가 전송을 시작할 때까지 대기
                WAIT_BUSY: begin
                    if(tx_busy) begin
                        r_state <= WAIT_DONE;
                    end
                end

                // UART TX 전송 완료 대기
                WAIT_DONE: begin
                    if(!tx_busy) begin
                        if (r_pending || w_new_data) begin
                            r_pending  <= 1'b0;
                            r_send_cnt <= 0;
                            r_state    <= SEND;
                        end
                        else begin
                            r_send_cnt <= r_send_cnt + 1'b1;
                            r_state    <= SEND;
                        end
                    end
                end

                default: begin
                    r_state <= IDLE;
                end

            endcase
        end
    end

endmodule


// ============================================
// ASCII 문자열 변환 테이블
// ============================================

module ascii_string_table(
    input [5:0] index,
    input [15:0] temperature,
    input [15:0] humidity,
    input [15:0] distance_cm,
    output reg [7:0] data
);

    // 온도
    wire [7:0] t_int  = temperature[15:8];
    wire [7:0] t_frac = temperature[7:0];

    // 습도
    wire [7:0] h_int  = humidity[15:8];
    wire [7:0] h_frac = humidity[7:0];

    // 소수 바이트가 0~9의 첫째 자리일 때
    // 3 -> 30 (화면 표시 0.30)
    wire [7:0] t_frac100 = t_frac * 10;
    wire [7:0] h_frac100 = h_frac * 10;

    // ASCII 숫자로 변환
    wire [7:0] t10 = 8'h30 + (t_int / 10);
    wire [7:0] t1  = 8'h30 + (t_int % 10);

    wire [7:0] tf10 = 8'h30 + (t_frac100 / 10);
    wire [7:0] tf1  = 8'h30 + (t_frac100 % 10);

    wire [7:0] h10 = 8'h30 + (h_int / 10);
    wire [7:0] h1  = 8'h30 + (h_int % 10);

    wire [7:0] hf10 = 8'h30 + (h_frac100 / 10);
    wire [7:0] hf1  = 8'h30 + (h_frac100 % 10);

    function [15:0] to_bcd4(input [15:0] value);
        reg [15:0] v;
        reg [29:0] bcd;
        integer i;
        begin
            v = (value > 16'd9999) ? 16'd9999 : value;
            bcd = 0;
            for (i = 13; i >= 0; i = i - 1) begin
                if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
                if (bcd[11:8]  >= 5) bcd[11:8]  = bcd[11:8]  + 3;
                if (bcd[7:4]   >= 5) bcd[7:4]   = bcd[7:4]   + 3;
                if (bcd[3:0]   >= 5) bcd[3:0]   = bcd[3:0]   + 3;
                bcd = {bcd[28:0], v[i]};
            end
            to_bcd4 = bcd[15:0];
        end
    endfunction

    wire [15:0] d_bcd = to_bcd4(distance_cm);
    wire [7:0] d1000 = 8'h30 + d_bcd[15:12];
    wire [7:0] d100  = 8'h30 + d_bcd[11:8];
    wire [7:0] d10   = 8'h30 + d_bcd[7:4];
    wire [7:0] d1    = 8'h30 + d_bcd[3:0];

    always @(*) begin
        case(index)

            // "TEMP: 25.30\r\n"
            6'd0:  data = "T";
            6'd1:  data = "E";
            6'd2:  data = "M";
            6'd3:  data = "P";
            6'd4:  data = ":";
            6'd5:  data = " ";

            6'd6:  data = t10;
            6'd7:  data = t1;
            6'd8:  data = ".";
            6'd9:  data = tf10;
            6'd10: data = tf1;

            6'd11: data = 8'h0D; // CR
            6'd12: data = 8'h0A; // LF

            // "HUM : 60.00\r\n"
            6'd13: data = "H";
            6'd14: data = "U";
            6'd15: data = "M";
            6'd16: data = " ";
            6'd17: data = ":";
            6'd18: data = " ";

            6'd19: data = h10;
            6'd20: data = h1;
            6'd21: data = ".";
            6'd22: data = hf10;
            6'd23: data = hf1;

            6'd24: data = 8'h0D; // CR
            6'd25: data = 8'h0A; // LF

            // "DIST: 0123 cm\r\n"
            6'd26: data = "D";
            6'd27: data = "I";
            6'd28: data = "S";
            6'd29: data = "T";
            6'd30: data = ":";
            6'd31: data = " ";
            6'd32: data = d1000;
            6'd33: data = d100;
            6'd34: data = d10;
            6'd35: data = d1;
            6'd36: data = " ";
            6'd37: data = "c";
            6'd38: data = "m";
            6'd39: data = 8'h0D;
            6'd40: data = 8'h0A;

            default: data = 8'h20;

        endcase
    end

endmodule
