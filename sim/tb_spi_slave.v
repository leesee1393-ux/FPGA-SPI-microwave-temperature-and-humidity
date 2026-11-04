`timescale 1ns/1ps
module tb_spi_slave;
reg clk=0, reset=1, sck=0, cs=1, mosi=0;
reg [15:0] t=16'h1903,h=16'h3c00,d=16'h1234;
reg valid=0,dv=0;
wire miso;
wire [7:0] debug_rx_data;
wire debug_write_toggle, debug_read_toggle;
wire debug_valid, debug_error, debug_test;
reg [7:0] result;
reg write_before, read_before;
integer i;
always #5 clk=~clk;
spi_slave dut(
    .clk(clk), .reset(reset), .spi_sck(sck), .spi_cs_n(cs),
    .spi_mosi(mosi), .spi_miso(miso),
    .debug_rx_data(debug_rx_data),
    .debug_write_toggle(debug_write_toggle),
    .debug_read_toggle(debug_read_toggle),
    .debug_valid(debug_valid), .debug_error(debug_error), .debug_test(debug_test),
    .temperature(t), .humidity(h), .data_valid(valid),
    .distance_cm(d), .distance_valid(dv)
);
task bit_cycle;
input b;
begin
mosi=b; #503; sck=1; #503; sck=0;
end
endtask
task read_byte;
input [7:0] addr, expected;
begin
write_before=debug_write_toggle;
read_before=debug_read_toggle;
cs=0; #137;
for(i=7;i>=0;i=i-1) bit_cycle(addr[i]);
for(i=7;i>=0;i=i-1) begin
    mosi=0; #503; sck=1; #1; result[i]=miso; #502; sck=0;
end
if(result!==expected) $fatal(1,"address %h got %h expected %h",addr,result,expected);
if(debug_rx_data!==addr) $fatal(1,"debug RX got %h expected %h",debug_rx_data,addr);
if(debug_write_toggle===write_before) $fatal(1,"write toggle missing for %h",addr);
if(debug_read_toggle===read_before) $fatal(1,"read toggle missing for %h",addr);
if(addr<=8'h03 || addr==8'hF0 || addr==8'hF1) begin
    if(!debug_valid || debug_error) $fatal(1,"valid status wrong for %h",addr);
end else if(debug_valid || !debug_error) $fatal(1,"invalid status wrong for %h",addr);
if(debug_test !== (addr==8'hF0 || addr==8'hF1))
    $fatal(1,"test status wrong for %h",addr);
bit_cycle(0); bit_cycle(0);
#137; cs=1; #1;
if(miso!==1'bz) $fatal(1,"MISO not released");
#137;
end
endtask
initial begin
#27; reset=0;
// Self-test must work before any sensor valid pulse.
read_byte(8'hF0,8'hA5); read_byte(8'hF1,8'h5A);
@(negedge clk); valid=1;dv=1;
@(negedge clk); valid=0;dv=0;
#100;
read_byte(0,25); read_byte(1,60); read_byte(2,8'h34); read_byte(3,8'h12);
read_byte(8'hff,0);
// Aborted address must not contaminate the next transaction.
cs=0; #137; bit_cycle(1); bit_cycle(1); cs=1; #137;
if(!debug_error || debug_valid || debug_test) $fatal(1,"abort status wrong");
read_byte(0,25);
// Sensor update during a transaction must not alter its snapshot.
cs=0; #137;
@(negedge clk); t=16'h2a00; valid=1;
@(negedge clk); valid=0;
for(i=7;i>=0;i=i-1) bit_cycle(0);
for(i=7;i>=0;i=i-1) begin #503; sck=1; #1; result[i]=miso; #502; sck=0; end
if(result!==25) $fatal(1,"snapshot changed mid-frame");
#137; cs=1; #137;
read_byte(0,42);
reset=1; #20;
if(miso!==1'bz) $fatal(1,"reset output");
$display("PASS: SPI self-test, sensor map, debug status/toggles, abort, snapshot, Hi-Z, reset");
$finish;
end
initial begin #1000000; $fatal(1,"watchdog"); end
endmodule
