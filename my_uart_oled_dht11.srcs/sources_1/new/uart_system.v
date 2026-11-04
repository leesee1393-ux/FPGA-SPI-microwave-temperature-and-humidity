`timescale 1ns / 1ps

module uart_system (
    input clk,
    input reset,
    input RsRx,

    input [15:0] temperature,
    input [15:0] humidity,
    input data_valid,

    // 초음파 센서
    input [15:0] distance_cm,
    input distance_valid,
    output RsTx,
    output [2:0] led,
    output UartTx,
    output UartRx
);

wire [7:0] w_rx_data;
    wire w_rx_done;

wire [7:0] w_fifo_data;
    wire w_fifo_full;
    wire w_fifo_empty;
    wire [4:0] w_fifo_count;

wire w_fifo_read;
    wire [2:0] w_led;

// UART RX/TX
    uart_controller u_uart_controller (
        .clk(clk),
        .reset(reset),
            // 온도 센서
        .temperature(temperature),
        .humidity(humidity),
        .data_valid(data_valid),
        
        // 초음파 센서 
        .distance_cm(distance_cm),
        .distance_valid(distance_valid),

        .rx(RsRx),
        .tx(RsTx),
        .rx_data(w_rx_data),
        .rx_done(w_rx_done)
    );

// FIFO Read
    assign w_fifo_read = !w_fifo_empty;

uart_fifo u_uart_fifo (
        .clk(clk),
        .reset(reset),
        .wr_data(w_rx_data),
        .wr_en(w_rx_done),
        .rd_en(w_fifo_read),
        .rd_data(w_fifo_data),
        .full(w_fifo_full),
        .empty(w_fifo_empty),
        .count(w_fifo_count)
    );

control_tower u_control_tower (
        .clk(clk),
        .reset(reset),
        .rx_data(w_fifo_data),
        .rx_done(w_fifo_read),
        .led(w_led)
    );

    assign led = w_led;

assign UartTx = RsTx;
    assign UartRx = RsRx;

endmodule