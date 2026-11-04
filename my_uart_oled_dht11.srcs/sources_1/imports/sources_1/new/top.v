
`timescale 1ns / 1ps

module top (
    input clk,
    input reset,
    input RsRx,
    input spi_sck,
    input spi_cs_n,
    input spi_mosi,
    output spi_miso,
    input [2:0] sw,


    inout dht11_data,
    input  hcsr04_echo,
    output hcsr04_trig,
    output RsTx,
    output [15:0] led,
    output UartTx,
    output UartRx,

    output [3:0] an,
    output [7:0] seg
);


    // dht11 
    wire [15:0] w_temperature;
    wire [15:0] w_humidity;
    wire w_data_valid;


    // 초음파 
    wire [15:0] w_distance_cm;
    wire w_distance_valid;
    wire w_distance_timeout;
    wire [2:0] w_uart_led;
    wire [7:0] w_spi_rx_data;
    wire w_spi_write_toggle;
    wire w_spi_read_toggle;
    wire w_spi_valid;
    wire w_spi_error;
    wire w_spi_test;

    spi_slave u_spi_slave (
        .clk(clk), .reset(reset), .spi_sck(spi_sck),
        .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .debug_rx_data(w_spi_rx_data),
        .debug_write_toggle(w_spi_write_toggle),
        .debug_read_toggle(w_spi_read_toggle),
        .debug_valid(w_spi_valid),
        .debug_error(w_spi_error), .debug_test(w_spi_test),
        .temperature(w_temperature), .humidity(w_humidity), .data_valid(w_data_valid),
        .distance_cm(w_distance_cm), .distance_valid(w_distance_valid)
    );

    assign led[7:0] = w_spi_rx_data;
    assign led[8] = w_spi_write_toggle;
    assign led[9] = w_spi_read_toggle;
    assign led[10] = w_spi_valid;
    assign led[11] = w_spi_error;
    assign led[12] = w_spi_test;
    assign led[14:13] = 2'b00;
    assign led[15] = ~spi_cs_n;

    // hcsr04 시스템
    hcsr04_controller u_hcsr04(
        .clk(clk),
        .reset(reset),
        .start(1'b1),

        .echo(hcsr04_echo),
        .trig(hcsr04_trig),

        .distance_cm(w_distance_cm),
        .data_valid(w_distance_valid),
        .timeout_error(w_distance_timeout)
    
    );
        // UART 시스템
    uart_system u_uart_system (
        .clk(clk),
        .reset(reset),
        .RsRx(RsRx),

        .temperature(w_temperature),
        .humidity(w_humidity),
        .data_valid(w_data_valid),

        // HC-SR04 -> UART
        .distance_cm(w_distance_cm),
        .distance_valid(w_distance_valid),

        .RsTx(RsTx),
        .led(w_uart_led),
        .UartTx(UartTx),
        .UartRx(UartRx)
    );

    // DHT11 + FND 시스템
    dht11_fnd_controller u_dht11_fnd (
        .clk(clk),
        .reset(reset),
        .sw(sw),
        .distance_cm(w_distance_cm),
        .dht11_data(dht11_data),

        .uart_temperature(w_temperature),
        .uart_humidity(w_humidity),
        .uart_data_valid(w_data_valid),
        .an(an),
        .seg(seg)
    );

endmodule
























