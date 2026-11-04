`timescale 1ns / 1ps

module tb_sensor_ascii;
    reg [5:0] index;
    reg [15:0] temperature = 16'h1900;
    reg [15:0] humidity = 16'h3c00;
    reg [15:0] distance_cm = 16'd123;
    wire [7:0] data;
    integer i;
    integer failures = 0;
    reg [7:0] expected [0:40];

    ascii_string_table dut (
        .index(index), .temperature(temperature), .humidity(humidity),
        .distance_cm(distance_cm), .data(data)
    );

    initial begin
        expected[0]="T"; expected[1]="E"; expected[2]="M"; expected[3]="P";
        expected[4]=":"; expected[5]=" "; expected[6]="2"; expected[7]="5";
        expected[8]="."; expected[9]="0"; expected[10]="0"; expected[11]=8'h0d; expected[12]=8'h0a;
        expected[13]="H"; expected[14]="U"; expected[15]="M"; expected[16]=" "; expected[17]=":"; expected[18]=" ";
        expected[19]="6"; expected[20]="0"; expected[21]="."; expected[22]="0"; expected[23]="0"; expected[24]=8'h0d; expected[25]=8'h0a;
        expected[26]="D"; expected[27]="I"; expected[28]="S"; expected[29]="T"; expected[30]=":"; expected[31]=" ";
        expected[32]="0"; expected[33]="1"; expected[34]="2"; expected[35]="3"; expected[36]=" "; expected[37]="c"; expected[38]="m"; expected[39]=8'h0d; expected[40]=8'h0a;
        for (i = 0; i <= 40; i = i + 1) begin
            index = i;
            #1;
            if (data !== expected[i]) begin
                $display("FAIL: index %0d got %h expected %h", i, data, expected[i]);
                failures = failures + 1;
            end
        end
        if (failures == 0) $display("PASS: TEMP/HUM/DIST ASCII frame");
        else $display("FAIL: ASCII failures=%0d", failures);
        $finish;
    end
endmodule
