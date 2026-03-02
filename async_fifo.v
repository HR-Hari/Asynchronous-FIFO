`timescale 1ns/1ps

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = 4
)(
    input                     wr_clk,
    input                     wr_rst,
    input                     wr_en,
    input  [DATA_WIDTH-1:0]   wr_data,
    output                    full,

    input                     rd_clk,
    input                     rd_rst,
    input                     rd_en,
    output reg [DATA_WIDTH-1:0] rd_data,
    output                    empty
);

    // -----------------------------
    // Memory (modeled as true dual-port)
    // -----------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // -----------------------------
    // Pointers (ADDR_WIDTH+1 bits)
    // -----------------------------
    reg  [ADDR_WIDTH:0] wr_bin, wr_gray;
    reg  [ADDR_WIDTH:0] rd_bin, rd_gray;

    wire [ADDR_WIDTH:0] wr_bin_next, wr_gray_next;
    wire [ADDR_WIDTH:0] rd_bin_next, rd_gray_next;

    // -----------------------------
    // Synchronizers (Gray pointers crossing domains)
    // -----------------------------
    reg [ADDR_WIDTH:0] rd_gray_sync1, rd_gray_sync2; // into wr_clk domain
    reg [ADDR_WIDTH:0] wr_gray_sync1, wr_gray_sync2; // into rd_clk domain

    // -----------------------------
    // FULL / EMPTY combinational logic
    // -----------------------------

    // Empty (read domain): empty after a potential read
    assign rd_bin_next  = (rd_en && !empty) ? (rd_bin + 1'b1) : rd_bin;
    assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    assign empty = (rd_gray_next == wr_gray_sync2);

    // Full (write domain): full after a potential write
    assign wr_bin_next  = (wr_en && !full) ? (wr_bin + 1'b1) : wr_bin;
    assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;

    wire [ADDR_WIDTH:0] rd_gray_full_cmp;
    assign rd_gray_full_cmp =
        {~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
          rd_gray_sync2[ADDR_WIDTH-2:0]};

    assign full = (wr_gray_next == rd_gray_full_cmp);

    // -----------------------------
    // Write pointer registers (wr_clk domain)
    // -----------------------------
    always @(posedge wr_clk) begin
        if (wr_rst) begin
            wr_bin  <= 0;
            wr_gray <= 0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    // -----------------------------
    // Read pointer registers (rd_clk domain)
    // -----------------------------
    always @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_bin  <= 0;
            rd_gray <= 0;
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    // -----------------------------
    // Synchronize rd_gray into write domain
    // -----------------------------
    always @(posedge wr_clk) begin
        if (wr_rst) begin
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // -----------------------------
    // Synchronize wr_gray into read domain
    // -----------------------------
    always @(posedge rd_clk) begin
        if (rd_rst) begin
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    // -----------------------------
    // Memory write (wr_clk domain)
    // -----------------------------
    always @(posedge wr_clk) begin
        if (!wr_rst && wr_en && !full) begin
            mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    // -----------------------------
    // Memory read (rd_clk domain) - registered output
    // -----------------------------
    always @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_data <= 0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_bin[ADDR_WIDTH-1:0]];
        end
    end

endmodule