// `timescale 1ns / 1ps



// module uart_rx #(
//     parameter BPS = 9600
// )(
//     input clk,
//     input reset,
//     input rx,  // UART rx
//     output tx, // Uart tx
//     output reg [7:0] rx_data,
//     output reg rx_done

//     );
//     parameter S_IDLE = 2'b00;
//     parameter S_START_BIT = 2'b01;
//     parameter S_DATA_8BITS = 2'b10;
//     parameter S_STOP_BIT = 2'b11;


//     // 9600 * 16 = 153,600
//     // 100_000_000Hz / 153,600 = 651ns (651ns 주기로 sampling)
//     // 9600Hz(651ns * 16 = 10416ns) *9600 ==> 100_000_000Hz
//     parameter integer DIVIDER_CNT = 100_000_000 / (BPS *16);
//     reg [1:0] r_state; // state S_IDLE -->S_START_BIT->S_DATA_8BITS->S_STOP_BIT
//     reg [3:0] r_bit_cnt; // r_date_reg 에 저장할 index값
//     reg[7:0] r_date_reg; // rx 포트로 부터 들어온 bit를 담을 그릇 (8bits)
//     reg[15:0] r_baud_cnt; // 651ns : 9600bps * 16 (sampling 구간 ) count 변수
//     reg r_baud_tick; // 651ns 마다 tick 발생
//     reg [3:0] r_baud_tick_cnt; // 16개 오버 샘픙링 count
//     reg data_out;
    
//     // 1. 651ns tick을 생성 하는 logic
//     always @(posedge clk , posedge reset ) begin
//         if(reset) begin
//             r_baud_cnt <=0;
//             r_baud_tick<=0;
//         end else begin // clk
//             if(r_baud_cnt>= DIVIDER_CNT-1) begin
//                 r_baud_cnt<=0;
//                 r_baud_tick<=1;
//             end else begin
//                 r_baud_cnt<=r_baud_cnt+ 1;
//                 r_baud_tick<=0;
//             end

//         end
//     end    
// // 2. rx bit를 수신하는 FSM 
//     always @(posedge clk , posedge reset ) begin
//         if(reset) begin
//              r_state <=S_IDLE;
//              r_bit_cnt <=  4'd0;
//              r_date_reg <= 8'b0;
//              r_baud_cnt <= 4'd0; // 16개 오버 샘플링 count
//              r_baud_tick <= 8'd0;
//              r_baud_tick_cnt <= 1'b0;
//         end else begin
//             case(r_state)
//             S_IDLE: begin
//                 rx_done <= 1'b0; // 수신 완료
//                 if(!rx) begin  // start bit 수신
//                     r_state <= S_START_BIT; //
//                     r_baud_tick_cnt<= 4'd0;
//                 end
//             end
//             S_START_BIT: begin
//                 if(r_baud_tick) begin
//                     r_baud_tick_cnt<=r_baud_tick_cnt+1;
//                     if(r_baud_tick_cnt>= 4'd7) begin
//                         r_state<= S_START_BIT;
//                         r_baud_tick_cnt<=4'd0; 
//                         r_bit_cnt <= 4'd0; // r_date_reg에 저장할 index값 저장 
//                     end
//                 end
//             end
//             S_DATA_8BITS : begin
               
//                  if(r_baud_tick) begin
//                     r_baud_tick_cnt<=r_baud_tick_cnt+1;
//                     if(r_baud_tick_cnt>= 4'd15) begin
//                         r_date_reg[r_bit_cnt] <= rx;
//                         r_baud_tick_cnt<=4'd0; 
//                         if(r_bit_cnt>= 4'd7)begin
//                             r_state <= S_STOP_BIT; 
//                         end else begin
//                             r_bit_cnt<=r_bit_cnt+1;
//                         end
//                         r_bit_cnt <= 4'd0; // r_date_reg에 저장할 index값 저장 
                   
//                     end
//                  end
//             end
//             S_STOP_BIT: begin
//                 if(r_baud_tick) begin
//                     r_baud_tick_cnt<=r_baud_tick_cnt+1;
//                     if(r_baud_tick_cnt>= 4'd15) begin
//                         r_state<= S_IDLE;
//                         data_out <=r_date_reg;
//                         r_bit_cnt <= 1'd1; // r_date_reg에 저장할 index값 저장 
//                     end
//                 end
//             end
//             default : r_state <= S_IDLE; 
//             endcase
//         end
//     end

// endmodule

`timescale 1ns / 1ps

module uart_rx #(
    parameter BPS = 9600
)(
    input clk,
    input reset,
    input rx,
    output reg [7:0] rx_data,
    output reg rx_done
);

    parameter S_IDLE       = 2'b00;
    parameter S_START_BIT  = 2'b01;
    parameter S_DATA_8BITS = 2'b10;
    parameter S_STOP_BIT   = 2'b11;

    // 100MHz / (9600 * 16) = 651 clocks
    // 651 * 10ns = 6.51us
    parameter integer DIVIDER_CNT =
        100_000_000 / (BPS * 16);

    reg [1:0] r_state;
    reg [3:0] r_bit_cnt;
    reg [7:0] r_date_reg;
    reg [15:0] r_baud_cnt;
    reg r_baud_tick;
    reg [3:0] r_baud_tick_cnt;

    // RX 입력 동기화
    reg rx_meta;
    reg rx_sync;

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    // 1. Baud Tick 생성
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            r_baud_cnt <= 0;
            r_baud_tick <= 0;
        end else begin
            if(r_baud_cnt >= DIVIDER_CNT - 1) begin
                r_baud_cnt <= 0;
                r_baud_tick <= 1'b1;
            end else begin
                r_baud_cnt <= r_baud_cnt + 1'b1;
                r_baud_tick <= 1'b0;
            end
        end
    end

    // 2. UART RX FSM
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            r_state <= S_IDLE;
            r_bit_cnt <= 0;
            r_date_reg <= 0;
            r_baud_tick_cnt <= 0;
            rx_data <= 0;
            rx_done <= 0;
        end else begin

            rx_done <= 1'b0;

            case(r_state)

                S_IDLE: begin
                    r_baud_tick_cnt <= 0;

                    if(!rx_sync) begin
                        r_state <= S_START_BIT;
                    end
                end

                S_START_BIT: begin
                    if(r_baud_tick) begin
                        if(r_baud_tick_cnt >= 4'd7) begin
                            r_baud_tick_cnt <= 0;
                            r_bit_cnt <= 0;

                            if(!rx_sync)
                                r_state <= S_DATA_8BITS;
                            else
                                r_state <= S_IDLE;
                        end else begin
                            r_baud_tick_cnt <=
                                r_baud_tick_cnt + 1'b1;
                        end
                    end
                end

                S_DATA_8BITS: begin
                    if(r_baud_tick) begin
                        if(r_baud_tick_cnt >= 4'd15) begin
                            r_date_reg[r_bit_cnt] <= rx_sync;
                            r_baud_tick_cnt <= 0;

                            if(r_bit_cnt >= 4'd7) begin
                                r_state <= S_STOP_BIT;
                                r_bit_cnt <= 0;
                            end else begin
                                r_bit_cnt <= r_bit_cnt + 1'b1;
                            end
                        end else begin
                            r_baud_tick_cnt <=
                                r_baud_tick_cnt + 1'b1;
                        end
                    end
                end

                S_STOP_BIT: begin
                    if(r_baud_tick) begin
                        if(r_baud_tick_cnt >= 4'd15) begin
                            r_baud_tick_cnt <= 0;
                            r_state <= S_IDLE;

                            if(rx_sync) begin
                                rx_data <= r_date_reg;
                                rx_done <= 1'b1;
                            end
                        end else begin
                            r_baud_tick_cnt <=
                                r_baud_tick_cnt + 1'b1;
                        end
                    end
                end

                default: r_state <= S_IDLE;

            endcase
        end
    end

endmodule
