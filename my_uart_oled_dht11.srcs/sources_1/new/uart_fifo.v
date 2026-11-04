
`timescale 1ns / 1ps

module uart_fifo (
    input clk,
    input reset,

    input [7:0] wr_data,  // UART RX 데이터
    input wr_en,         // 쓰기 요청

    input rd_en,         // 읽기 요청
    output [7:0] rd_data,

    output full,
    output empty,
    output [4:0] count
);

    // 16 x 8bit FIFO Memory
    reg [7:0] mem [0:15];

    reg [3:0] wr_ptr;
    reg [3:0] rd_ptr;
    reg [4:0] r_count;

    // 실제 읽기/쓰기 허용 조건
    wire w_write;
    wire w_read;

    assign w_read  = rd_en && !empty;
    assign w_write = wr_en && (!full || w_read);

    // FIFO Status
    assign full  = (r_count == 16);
    assign empty = (r_count == 0);
    assign count = r_count;

    // 현재 읽기 포인터의 데이터 출력
    assign rd_data = mem[rd_ptr];

    // FIFO Memory Write
    always @(posedge clk) begin
        if (w_write)
            mem[wr_ptr] <= wr_data;
    end

    // Read / Write Pointer
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end
        else begin
            if (w_write)
                wr_ptr <= wr_ptr + 1'b1;

            if (w_read)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // FIFO Count
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_count <= 0;
        end
        else begin
            case ({w_write, w_read})
                2'b10: r_count <= r_count + 1'b1;
                2'b01: r_count <= r_count - 1'b1;
                default: r_count <= r_count;
            endcase
        end
    end

endmodule
