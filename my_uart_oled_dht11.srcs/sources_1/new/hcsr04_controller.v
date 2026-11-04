`timescale 1ns / 1ps


module hcsr04_controller#(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer TRIG_US = 10,
    parameter integer TIMEOUT_MS = 30,
    parameter integer INTERVAL_MS = 60
)(
    input clk,
    input reset,
    input start,
    input echo,
    output reg trig,
    output reg [15:0] distance_cm,
    output reg data_valid,
    output reg timeout_error
    );

 localparam integer CYCLES_PER_US = CLK_FREQ_HZ / 1_000_000;
    localparam integer TRIG_CYCLES =
        CYCLES_PER_US * TRIG_US;
    localparam integer TIMEOUT_CYCLES =
        (CLK_FREQ_HZ / 1000) * TIMEOUT_MS;
    localparam integer INTERVAL_CYCLES =
        (CLK_FREQ_HZ / 1000) * INTERVAL_MS;

    // 거리 1cm당 약 58us (왕복 시간)
    localparam integer CYCLES_PER_CM =
        CYCLES_PER_US * 58;

    localparam [2:0]
        IDLE      = 3'd0,
        TRIGGER   = 3'd1,
        WAIT_RISE = 3'd2,
        MEASURE   = 3'd3,
        CALC      = 3'd4,
        DONE      = 3'd5,
        ERROR     = 3'd6;

    reg [2:0] state;
    reg [31:0] counter;
    reg [31:0] echo_counter;
    reg [31:0] calc_remainder;
    reg [15:0] calc_quotient;

    // 비동기 ECHO 입력 2단 동기화
    (* ASYNC_REG = "TRUE" *) reg echo_meta;
    (* ASYNC_REG = "TRUE" *) reg echo_sync;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            echo_meta <= 1'b0;
            echo_sync <= 1'b0;
        end
        else begin
            echo_meta <= echo;
            echo_sync <= echo_meta;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= IDLE;
            counter       <= 0;
            echo_counter  <= 0;
            calc_remainder <= 0;
            calc_quotient  <= 0;
            trig          <= 0;
            distance_cm   <= 0;
            data_valid    <= 0;
            timeout_error <= 0;
        end
        else begin
            data_valid <= 0;

            case (state)

                IDLE: begin
                    trig <= 0;

                    if (start && counter >= INTERVAL_CYCLES - 1) begin
                        counter <= 0;
                        timeout_error <= 0;
                        state <= TRIGGER;
                    end
                    else
                        counter <= counter + 1'b1;
                end

                TRIGGER: begin
                    trig <= 1;

                    if (counter >= TRIG_CYCLES - 1) begin
                        trig <= 0;
                        counter <= 0;
                        state <= WAIT_RISE;
                    end
                    else
                        counter <= counter + 1'b1;
                end

                WAIT_RISE: begin
                    if (echo_sync) begin
                        counter <= 0;
                        echo_counter <= 0;
                        state <= MEASURE;
                    end
                    else if (counter >= TIMEOUT_CYCLES - 1) begin
                        counter <= 0;
                        state <= ERROR;
                    end
                    else
                        counter <= counter + 1'b1;
                end

                MEASURE: begin
                    if (!echo_sync) begin
                        // Division is performed over multiple clocks to avoid a long 100 MHz path.
                        calc_remainder <= echo_counter + CYCLES_PER_CM / 2;
                        calc_quotient  <= 0;
                        counter <= 0;
                        state <= CALC;
                    end
                    else if (echo_counter >= TIMEOUT_CYCLES - 1) begin
                        counter <= 0;
                        state <= ERROR;
                    end
                    else
                        echo_counter <= echo_counter + 1'b1;
                end

                CALC: begin
                    if (calc_remainder >= CYCLES_PER_CM) begin
                        calc_remainder <= calc_remainder - CYCLES_PER_CM;
                        calc_quotient  <= calc_quotient + 1'b1;
                    end
                    else begin
                        distance_cm <= calc_quotient;
                        state <= DONE;
                    end
                end

                DONE: begin
                    data_valid <= 1;
                    timeout_error <= 0;
                    counter <= 0;
                    state <= IDLE;
                end

                ERROR: begin
                    timeout_error <= 1;
                    counter <= 0;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    counter <= 0;
                end
            endcase
        end
    end
endmodule
