`timescale 1ns/1ps

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = 4
)(
    input                       wr_clk,
    input                       wr_rst,
    input                       wr_en,
    input  [DATA_WIDTH-1:0]     wr_data,
    output                      full,

    input                       rd_clk,
    input                       rd_rst,
    input                       rd_en,
    output reg [DATA_WIDTH-1:0] rd_data,
    output                      empty
);

    // -------------------------------------------------------------------------
    // Memory
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Pointers (ADDR_WIDTH+1 bits - MSB used for full/empty distinction)
    // -------------------------------------------------------------------------
    reg  [ADDR_WIDTH:0] wr_bin,  wr_gray;
    reg  [ADDR_WIDTH:0] rd_bin,  rd_gray;

    // Next-state: simple unconditional +1  (NO feedback from full/empty)
    wire [ADDR_WIDTH:0] wr_bin_next  = wr_bin + 1'b1;
    wire [ADDR_WIDTH:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;

    wire [ADDR_WIDTH:0] rd_bin_next  = rd_bin + 1'b1;
    wire [ADDR_WIDTH:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    // -------------------------------------------------------------------------
    // Synchronizers
    // -------------------------------------------------------------------------
    reg [ADDR_WIDTH:0] rd_gray_sync1, rd_gray_sync2;   // rd_gray  ? wr_clk domain
    reg [ADDR_WIDTH:0] wr_gray_sync1, wr_gray_sync2;   // wr_gray  ? rd_clk domain

    // -------------------------------------------------------------------------
    // EMPTY flag  (read-clock domain)
    //   Compare CURRENT rd_gray with the synchronised wr_gray.
    //   Using the current pointer (not _next) avoids asserting empty one beat early.
    // -------------------------------------------------------------------------
    assign empty = (rd_gray == wr_gray_sync2);

    // -------------------------------------------------------------------------
    // FULL flag  (write-clock domain)
    //   The FIFO is full when the next write pointer equals the synchronised
    //   read pointer with the two MSBs inverted (standard Gray-code full check).
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH:0] rd_gray_full_cmp =
        { ~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
           rd_gray_sync2[ADDR_WIDTH-2:0] };

    assign full = (wr_gray_next == rd_gray_full_cmp);

    // -------------------------------------------------------------------------
    // Write pointer registers  (wr_clk domain)
    //   The enable guard lives HERE - not inside the combinational next-pointer.
    // -------------------------------------------------------------------------
    always @(posedge wr_clk) begin
        if (wr_rst) begin
            wr_bin  <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray <= {(ADDR_WIDTH+1){1'b0}};
        end else if (wr_en && !full) begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    // -------------------------------------------------------------------------
    // Read pointer registers  (rd_clk domain)
    // -------------------------------------------------------------------------
    always @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_bin  <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray <= {(ADDR_WIDTH+1){1'b0}};
        end else if (rd_en && !empty) begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    // -------------------------------------------------------------------------
    // Synchronise rd_gray into wr_clk domain  (2-FF synchroniser)
    // -------------------------------------------------------------------------
    always @(posedge wr_clk) begin
        if (wr_rst) begin
            rd_gray_sync1 <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray_sync2 <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // Synchronise wr_gray into rd_clk domain  (2-FF synchroniser)
    // -------------------------------------------------------------------------
    always @(posedge rd_clk) begin
        if (rd_rst) begin
            wr_gray_sync1 <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray_sync2 <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // Memory write  (wr_clk domain)
    // -------------------------------------------------------------------------
    always @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // -------------------------------------------------------------------------
    // Memory read - registered output  (rd_clk domain)
    // -------------------------------------------------------------------------
    always @(posedge rd_clk) begin
        if (rd_rst)
            rd_data <= {DATA_WIDTH{1'b0}};
        else if (rd_en && !empty)
            rd_data <= mem[rd_bin[ADDR_WIDTH-1:0]];
    end

endmodule