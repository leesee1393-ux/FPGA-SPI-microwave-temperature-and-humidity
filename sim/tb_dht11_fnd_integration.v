`timescale 1ns / 1ps

module tb_dht11_fnd_integration;
    reg clk = 0;
    reg reset = 1;
    reg sw = 0;
    tri dht11_data;
    wire [3:0] an;
    wire [7:0] seg;
    wire [15:0] uart_temperature;
    wire [15:0] uart_humidity;
    wire uart_data_valid;
    integer failures = 0;

    always #5 clk = ~clk;
    pullup(dht11_data);

    dht11_fnd_controller dut (
        .clk(clk), .reset(reset), .sw(sw), .dht11_data(dht11_data), .an(an), .seg(seg),
        .uart_temperature(uart_temperature), .uart_humidity(uart_humidity),
        .uart_data_valid(uart_data_valid)
    );

    initial begin
        #20; reset = 0;
        @(negedge clk);
        force dut.w_temperature = 16'h1903; // 25.3 C
        force dut.w_humidity    = 16'h3c00; // 60.0 %
        force dut.w_data_valid  = 1'b1;
        @(posedge clk); #1;
        if (uart_data_valid !== 1'b1 || uart_temperature !== 16'h1903 ||
            uart_humidity !== 16'h3c00 || dut.r_temperature !== 16'h1903 ||
            dut.r_humidity !== 16'h3c00 || dut.w_fnd_data !== 14'd2530) begin
            $display("FAIL: valid DHT data did not reach UART/FND immediately");
            failures = failures + 1;
        end
        sw = 1'b1; #1;
        if (dut.w_fnd_data !== 14'd6000) begin
            $display("FAIL: SW0 humidity selection did not update FND data");
            failures = failures + 1;
        end
        release dut.w_temperature;
        release dut.w_humidity;
        release dut.w_data_valid;
        if (failures == 0) $display("PASS: data_valid fans out to UART and FND without a 1 s wait");
        else $display("FAIL: integration test failures=%0d", failures);
        $finish;
    end
endmodule
