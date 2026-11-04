
`timescale 1ns / 1ps

module uart_controller(
    input clk,
    input reset,

    // DHT11 데이터
    input [15:0] temperature,
    input [15:0] humidity,
    input data_valid,
    input [15:0] distance_cm,
    input distance_valid,

    // UART
    input rx,
    output tx,
    output [7:0] rx_data,
    output rx_done
);

    wire w_tx_busy;
    wire w_tx_start;
    wire [7:0] w_tx_data;

    // DHT11 데이터 -> ASCII 문자열
    data_sender u_data_sender(
        .clk(clk),
        .reset(reset),

        .temperature(temperature),
        .humidity(humidity),

        .distance_cm(distance_cm),
        .distance_valid(distance_valid),

        .start_trigger(data_valid),
        .tx_busy(w_tx_busy),

        .tx_start(w_tx_start),
        .tx_data(w_tx_data)
    );

    // 기존 UART TX 재사용
    uart_tx #(
        .BPS(9600)
    ) u_uart_tx(
        .clk(clk),
        .reset(reset),
        .tx_data(w_tx_data),
        .tx_start(w_tx_start),
        .tx(tx),
        .tx_busy(w_tx_busy)
    );

    // 기존 UART RX 재사용
    uart_rx #(
        .BPS(9600)
    ) u_uart_rx(
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

endmodule
