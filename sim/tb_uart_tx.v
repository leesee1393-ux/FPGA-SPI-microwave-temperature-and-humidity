`timescale 1ns / 1ps

module tb_uart_tx;
    localparam integer DIVIDER = 100_000_000 / 9600;
    reg clk = 0;
    reg reset = 1;
    wire [7:0] tx_data;
    wire tx_start;
    wire tx;
    wire tx_busy;
    integer failures = 0;
    integer byte_count = 0;

    always #5 clk = ~clk;

    reg start_trigger = 0;
    reg distance_valid = 0;

    data_sender sender (
        .clk(clk), .reset(reset), .temperature(16'h1900), .humidity(16'h3c00),
        .distance_cm(16'd123), .distance_valid(distance_valid),
        .start_trigger(start_trigger), .tx_busy(tx_busy), .tx_start(tx_start), .tx_data(tx_data)
    );
    uart_tx #(.BPS(9600)) tx_dut (
        .clk(clk), .reset(reset), .tx_data(tx_data), .tx_start(tx_start), .tx(tx), .tx_busy(tx_busy)
    );

    function [7:0] expected_byte(input integer index);
        begin
            case (index)
                0: expected_byte = "T";  1: expected_byte = "E";
                2: expected_byte = "M";  3: expected_byte = "P";
                4: expected_byte = ":";  5: expected_byte = " ";
                6: expected_byte = "2";  7: expected_byte = "5";
                8: expected_byte = ".";  9: expected_byte = "0";
               10: expected_byte = "0"; 11: expected_byte = 8'h0d;
               12: expected_byte = 8'h0a; 13: expected_byte = "H";
               14: expected_byte = "U"; 15: expected_byte = "M";
               16: expected_byte = " "; 17: expected_byte = ":";
               18: expected_byte = " "; 19: expected_byte = "6";
               20: expected_byte = "0"; 21: expected_byte = ".";
               22: expected_byte = "0"; 23: expected_byte = "0";
               24: expected_byte = 8'h0d;
               default: expected_byte = 8'h0a;
            endcase
        end
    endfunction

    task receive_byte(output [7:0] data);
        integer bit_index;
        begin
            @(negedge tx);
            #(DIVIDER * 10 + DIVIDER / 2); // first data-bit centre (start began on a clk edge)
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                data[bit_index] = tx;
                #(DIVIDER * 10);
            end
            if (tx !== 1'b1) begin
                $display("FAIL: stop bit %0d", byte_count); failures = failures + 1;
            end
        end
    endtask

    initial begin
        reg [7:0] received;
        #100; reset = 0;
        repeat (1) begin
            @(negedge clk); start_trigger = 1;
            @(negedge clk); start_trigger = 0;
            repeat (26) begin
                receive_byte(received);
                if (received !== expected_byte(byte_count % 26)) begin
                    $display("FAIL: byte %0d got %h expected %h", byte_count, received, expected_byte(byte_count % 26));
                    failures = failures + 1;
                end
                byte_count = byte_count + 1;
            end
        end
        if (failures == 0) $display("PASS: UART 9600 8N1 ASCII frame and busy handshake");
        else $display("FAIL: UART test failures=%0d", failures);
        $finish;
    end
endmodule
