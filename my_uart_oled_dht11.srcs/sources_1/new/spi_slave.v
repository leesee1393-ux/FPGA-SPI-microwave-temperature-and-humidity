`timescale 1ns / 1ps
// Mode 0, MSB first. At 100 MHz use SCK <= 1 MHz,
// CS setup/hold/high >= 100 ns. Inputs are oversampled in clk domain.
module spi_slave (
    input clk, input reset,
    input spi_sck, input spi_cs_n, input spi_mosi,
    output spi_miso,
    output reg [7:0] debug_rx_data,
    output reg debug_write_toggle,
    output reg debug_read_toggle,
    output reg debug_valid,
    output reg debug_error,
    output reg debug_test,
    input [15:0] temperature, input [15:0] humidity,
    input data_valid,
    input [15:0] distance_cm, input distance_valid
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] sck_sync, cs_sync, mosi_sync;
    reg sck_prev;
    reg [7:0] latest_t, latest_h;
    reg [15:0] latest_d;
    reg [7:0] frame_t, frame_h;
    reg [15:0] frame_d;
    reg [7:0] index_shift, response;
    reg [3:0] count;
    reg miso_bit;
    localparam WAIT_SELECT=0, RX_INDEX=1, LOAD_DATA=2, TX_DATA=3, WAIT_RELEASE=4;
    reg [2:0] state;
    wire rising = sck_sync[1] && !sck_prev;
    wire falling = !sck_sync[1] && sck_prev;
    wire [7:0] address = {index_shift[6:0], mosi_sync[1]};
    // Raw CS gates the output immediately, even before synchronization.
    assign spi_miso = (spi_cs_n || reset) ? 1'bz : miso_bit;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sck_sync<=0; cs_sync<=3; mosi_sync<=0; sck_prev<=0;
            latest_t<=0; latest_h<=0; latest_d<=0;
            frame_t<=0; frame_h<=0; frame_d<=0;
            state<=WAIT_SELECT; count<=0; index_shift<=0; response<=0; miso_bit<=0;
            debug_rx_data<=0; debug_write_toggle<=0; debug_read_toggle<=0;
            debug_valid<=0; debug_error<=0; debug_test<=0;
        end else begin
            sck_sync<={sck_sync[0],spi_sck};
            cs_sync<={cs_sync[0],spi_cs_n};
            mosi_sync<={mosi_sync[0],spi_mosi};
            sck_prev<=sck_sync[1];
            if (data_valid) begin latest_t<=temperature[15:8]; latest_h<=humidity[15:8]; end
            if (distance_valid) latest_d<=distance_cm;
            if (cs_sync[1]) begin
                if (state!=WAIT_SELECT && state!=WAIT_RELEASE) begin
                    debug_valid<=0; debug_error<=1; debug_test<=0;
                end
                state<=WAIT_SELECT; count<=0; index_shift<=0; miso_bit<=0;
            end else case (state)
                WAIT_SELECT: begin
                    frame_t<=latest_t; frame_h<=latest_h; frame_d<=latest_d;
                    count<=0; index_shift<=0; state<=RX_INDEX;
                end
                RX_INDEX: if (rising) begin
                    index_shift<=address;
                    if (count==7) begin
                        debug_rx_data<=address;
                        debug_write_toggle<=~debug_write_toggle;
                        case(address)
                            8'h00: begin response<=frame_t;       debug_valid<=1; debug_error<=0; debug_test<=0; end
                            8'h01: begin response<=frame_h;       debug_valid<=1; debug_error<=0; debug_test<=0; end
                            8'h02: begin response<=frame_d[7:0];  debug_valid<=1; debug_error<=0; debug_test<=0; end
                            8'h03: begin response<=frame_d[15:8]; debug_valid<=1; debug_error<=0; debug_test<=0; end
                            8'hF0: begin response<=8'hA5;         debug_valid<=1; debug_error<=0; debug_test<=1; end
                            8'hF1: begin response<=8'h5A;         debug_valid<=1; debug_error<=0; debug_test<=1; end
                            default: begin response<=0;           debug_valid<=0; debug_error<=1; debug_test<=0; end
                        endcase
                        state<=LOAD_DATA; count<=0;
                    end else count<=count+1'b1;
                end
                LOAD_DATA: if (falling) begin
                    miso_bit<=response[7]; response<={response[6:0],1'b0}; state<=TX_DATA;
                end
                TX_DATA: begin
                    if (rising) begin
                        if (count==7) begin
                            debug_read_toggle<=~debug_read_toggle;
                            state<=WAIT_RELEASE;
                        end
                        else count<=count+1'b1;
                    end
                    if (falling) begin miso_bit<=response[7]; response<={response[6:0],1'b0}; end
                end
                WAIT_RELEASE: begin end // Ignore excess clocks until CS goes high.
                default: state<=WAIT_SELECT;
            endcase
        end
    end
endmodule
