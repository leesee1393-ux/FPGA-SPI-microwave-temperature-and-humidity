`timescale 1ns / 1ps

module tb_hcsr04_controller;
    reg clk = 0;
    reg reset = 1;
    reg echo = 0;
    wire trig;
    wire [15:0] distance_cm;
    wire data_valid;
    wire timeout_error;
    integer failures = 0;

    always #500 clk = ~clk; // 1 MHz scaled clock

    hcsr04_controller #(
        .CLK_FREQ_HZ(1_000_000), .TIMEOUT_MS(5), .INTERVAL_MS(60)
    ) dut (
        .clk(clk), .reset(reset), .start(1'b1), .echo(echo), .trig(trig),
        .distance_cm(distance_cm), .data_valid(data_valid), .timeout_error(timeout_error)
    );

    initial begin
        #2_000; reset = 0;
        wait (trig === 1'b1);
        #1;
        if (trig !== 1'b1) begin
            $display("FAIL: trigger did not assert"); failures = failures + 1;
        end
        wait (trig === 1'b0);
        #10_000; echo = 1'b1; // 1 cm delay after trigger
        #290_000; echo = 1'b0; // 5 cm: 5 * 58 us
        wait (data_valid === 1'b1);
        #1;
        if (distance_cm !== 16'd5 || timeout_error !== 1'b0) begin
            $display("FAIL: expected 5 cm, got %0d timeout=%b", distance_cm, timeout_error);
            failures = failures + 1;
        end

        wait (trig === 1'b1);
        wait (trig === 1'b0);
        wait (timeout_error === 1'b1);

        // After timeout, the next interval must recover and trigger again.
        wait (trig === 1'b1);
        if (failures == 0) $display("PASS: HC-SR04 trigger, distance, timeout, and recovery");
        else $display("FAIL: HC-SR04 failures=%0d", failures);
        $finish;
    end
endmodule
