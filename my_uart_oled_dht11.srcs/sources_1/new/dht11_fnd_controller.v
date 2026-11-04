
`timescale 1ns / 1ps

module dht11_fnd_controller (
    input clk,
    input reset,
    input [2:0] sw,                // 0: 온도, 1: 습도 2: 초음파
    
    input [15:0] distance_cm,
    inout dht11_data,

    output [3:0] an,
    output [7:0] seg,

    // UART로 전달할 DHT11 데이터
    output [15:0] uart_temperature,
    output [15:0] uart_humidity,
    output uart_data_valid
);

    // ====================================
    // 1. Tick Generator
    // ====================================
    wire w_tick_1ms;
    wire w_tick_1s;

    tick_generator #(
        .INPUT_FREQ(100_000_000),
        .TICK_Hz(1000)
    ) u_tick_generator (
        .clk(clk),
        .reset(reset),
        .tick(w_tick_1ms)
    );

    reg [9:0] r_ms_counter;
    reg r_sec_toggle;
    reg r_dht_start;

    // 1초 Tick: 조합 Clock Enable
    assign w_tick_1s =
        w_tick_1ms && (r_ms_counter == 999);

    // 2초마다 DHT11 Start Pulse
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_ms_counter <= 0;
            r_sec_toggle <= 0;
            r_dht_start  <= 0;
        end
        else begin
            r_dht_start <= 0;

            if (w_tick_1ms) begin
                if (r_ms_counter == 999) begin
                    r_ms_counter <= 0;
                    r_sec_toggle <= ~r_sec_toggle;

                    if (r_sec_toggle)
                        r_dht_start <= 1'b1;
                end
                else begin
                    r_ms_counter <= r_ms_counter + 1'b1;
                end
            end
        end
    end

    // ====================================
    // 2. DHT11
    // ====================================
    wire [15:0] w_temperature;
    wire [15:0] w_humidity;
    wire [7:0] w_checksum;
    wire w_data_valid;
    wire w_i_data;

    dht11 u_dht11 (
        .clk(clk),
        .reset(reset),
        .start(r_dht_start),

        .io_mode(1'b1),
        .o_data(1'b0),
        .i_data(w_i_data),
        .dht11_data(dht11_data),

        .humidity(w_humidity),
        .temperature(w_temperature),
        .checksum(w_checksum),
        .data_valid(w_data_valid)
    );

    // ====================================
    // 3. 측정 데이터 저장
    // ====================================
    reg [15:0] r_temperature;
    reg [15:0] r_humidity;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_temperature <= 0;
            r_humidity    <= 0;
        end
        else if (w_data_valid) begin
            r_temperature <= w_temperature;
            r_humidity    <= w_humidity;
        end
    end

    // ====================================
    // 4. 온도 / 습도 선택
    // ====================================
    wire [15:0] w_sensor_data;

    assign w_sensor_data =
        sw ? r_humidity : r_temperature;

    wire [7:0] w_integer;
    wire [7:0] w_decimal;

    assign w_integer = w_sensor_data[15:8];
    assign w_decimal = w_sensor_data[7:0];

    // 온도/습도
    
    wire [13:0] w_dht_fnd_data;

    assign w_dht_fnd_data =
        (w_integer * 100) + (w_decimal * 10);

    wire [13:0] w_fnd_data;

    assign w_fnd_data = sw[2] ? distance_cm[13:0] : w_dht_fnd_data;
    // ====================================
    // 5. 기존 FND Controller
    // r_temperature/r_humidity change only after a valid DHT11 frame.
    // ====================================
    fnd_controller u_fnd_controller (
        .clk(clk),
        .reset(reset),
        .tick(w_tick_1ms),
        .in_data(w_fnd_data),
        .dp_enable(!sw[2]),
        .an(an),
        .seg(seg)
    );

    assign uart_temperature = w_temperature;
    assign uart_humidity    = w_humidity;
    assign uart_data_valid  = w_data_valid;

endmodule
