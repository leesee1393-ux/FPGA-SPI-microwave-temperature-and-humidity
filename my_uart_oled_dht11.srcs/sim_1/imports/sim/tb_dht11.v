`timescale 1ns / 1ps

module tb_dht11;
    reg clk = 0;
    reg reset = 1;
    reg start = 0;
    reg sensor_low = 0;
    tri dht11_data;
    wire i_data;
    wire [15:0] humidity;
    wire [15:0] temperature;
    wire [7:0] checksum;
    wire data_valid;
    integer failures = 0;

    always #500 clk = ~clk; // 1 MHz; DHT timing parameters below are clock cycles/us.
    assign dht11_data = sensor_low ? 1'b0 : 1'bz;
    pullup(dht11_data);

    dht11 #(
        .LOW_18MS(18_000), .RELEASE_30US(30),
        .HIGH_THRESHOLD(40), .TIMEOUT_100US(100)
    ) dut (
        .clk(clk), .reset(reset), .start(start), .io_mode(1'b1), .o_data(1'b0),
        .i_data(i_data), .dht11_data(dht11_data), .humidity(humidity),
        .temperature(temperature), .checksum(checksum), .data_valid(data_valid)
    );

    task pulse_start;
        begin
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
        end
    endtask

    task send_frame(input [39:0] frame);
        integer bit_index;
        begin
            wait (dht11_data === 1'b0); // FPGA 18 ms start pulse
            wait (dht11_data === 1'b1);
            #(30_000); sensor_low = 1'b1;  #(80_000);
                         sensor_low = 1'b0;  #(80_000);
                         sensor_low = 1'b1;
            for (bit_index = 39; bit_index >= 0; bit_index = bit_index - 1) begin
                #(50_000); sensor_low = 1'b0;
                if (frame[bit_index]) #(70_000); else #(27_000);
                sensor_low = 1'b1;
            end
            #(10_000); sensor_low = 1'b0;
        end
    endtask

    task expect_valid(input [39:0] frame, input [15:0] expected_h, input [15:0] expected_t);
        begin
            pulse_start;
            fork
                send_frame(frame);
                begin
                    wait (data_valid === 1'b1);
                    #1;
                    if (humidity !== expected_h || temperature !== expected_t || checksum !== frame[7:0]) begin
                        $display("FAIL: frame %h decoded as H=%h T=%h C=%h", frame, humidity, temperature, checksum);
                        failures = failures + 1;
                    end
                end
            join
        end
    endtask

    task send_bit_low_timeout;
        begin
            pulse_start;
            wait (dht11_data === 1'b0);
            wait (dht11_data === 1'b1);
            #(30_000); sensor_low = 1'b1; #(80_000);
                         sensor_low = 1'b0; #(80_000);
                         sensor_low = 1'b1; #(150_000);
                         sensor_low = 1'b0;
        end
    endtask

    initial begin
        #2_000; reset = 0;

        // Valid frames exercise 0/1 timings and both values of the final bit.
        expect_valid({8'd60, 8'd0, 8'd26, 8'd0, 8'd86}, 16'h3c00, 16'h1a00); // final bit 0
        expect_valid({8'd60, 8'd0, 8'd25, 8'd0, 8'd85}, 16'h3c00, 16'h1900); // final bit 1

        pulse_start;
        send_frame({8'd60, 8'd0, 8'd25, 8'd0, 8'd86}); // bad checksum
        repeat (20) @(posedge clk);
        if (dut.r_checksum_fail_count != 1 || data_valid !== 1'b0) begin
            $display("FAIL: checksum error was not counted"); failures = failures + 1;
        end

        pulse_start;                         // no response
        repeat (18_500) @(posedge clk);
        if (dut.r_timeout_count != 1) begin
            $display("FAIL: no-response timeout was not counted"); failures = failures + 1;
        end

        send_bit_low_timeout;                // response starts, then data phase stalls
        repeat (30) @(posedge clk);
        if (dut.r_timeout_count != 2) begin
            $display("FAIL: data-phase timeout was not counted"); failures = failures + 1;
        end

        expect_valid({8'd61, 8'd0, 8'd24, 8'd0, 8'd85}, 16'h3d00, 16'h1800); // recovery
        if (dut.r_done_count != 4) begin
            $display("FAIL: expected four completed frames, got %0d", dut.r_done_count);
            failures = failures + 1;
        end

        if (failures == 0) $display("PASS: DHT11 normal, checksum, timeout, and recovery tests");
        else $display("FAIL: DHT11 test failures=%0d", failures);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: DHT11 test watchdog, state=%0d bit=%0d counter=%0d", dut.r_state, dut.r_bit_count, dut.r_counter);
        $finish;
    end
endmodule
