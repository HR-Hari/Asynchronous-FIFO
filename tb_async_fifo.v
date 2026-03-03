`timescale 1ns/1ps

module async_fifo_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter DATA_WIDTH = 8;
    parameter DEPTH      = 16;
    parameter ADDR_WIDTH = 4;

    parameter WR_CLK_PERIOD = 10;  // 100 MHz write clock
    parameter RD_CLK_PERIOD = 17;  // ~59 MHz read clock (intentionally different)

    // -------------------------------------------------------------------------
    // DUT Ports
    // -------------------------------------------------------------------------
    reg                   wr_clk, wr_rst, wr_en;
    reg  [DATA_WIDTH-1:0] wr_data;
    wire                  full;

    reg                   rd_clk, rd_rst, rd_en;
    wire [DATA_WIDTH-1:0] rd_data;
    wire                  empty;

    // -------------------------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk  (wr_clk),
        .wr_rst  (wr_rst),
        .wr_en   (wr_en),
        .wr_data (wr_data),
        .full    (full),
        .rd_clk  (rd_clk),
        .rd_rst  (rd_rst),
        .rd_en   (rd_en),
        .rd_data (rd_data),
        .empty   (empty)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial wr_clk = 0;
    always #(WR_CLK_PERIOD/2) wr_clk = ~wr_clk;

    initial rd_clk = 0;
    always #(RD_CLK_PERIOD/2) rd_clk = ~rd_clk;

    // -------------------------------------------------------------------------
    // Scoreboard / Tracking
    // -------------------------------------------------------------------------
    integer errors     = 0;
    integer wr_count   = 0;
    integer rd_count   = 0;

    // Reference queue (simple shift-register model, max DEPTH entries)
    reg [DATA_WIDTH-1:0] ref_queue [0:DEPTH-1];
    integer              ref_head  = 0;   // next read index
    integer              ref_tail  = 0;   // next write index
    integer              ref_count = 0;   // items in queue

    // -------------------------------------------------------------------------
    // Task: Apply Reset (both domains)
    // -------------------------------------------------------------------------
    task apply_reset;
        begin
            wr_rst = 1; rd_rst = 1;
            wr_en  = 0; rd_en  = 0;
            wr_data = 0;
            repeat(4) @(posedge wr_clk);
            repeat(4) @(posedge rd_clk);
            @(posedge wr_clk); wr_rst = 0;
            @(posedge rd_clk); rd_rst = 0;
            $display("[%0t] Reset de-asserted.", $time);
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: Write one word (write-clock domain)
    // -------------------------------------------------------------------------
    task write_word;
        input [DATA_WIDTH-1:0] data;
        begin
            @(posedge wr_clk);
            if (!full) begin
                wr_en   = 1;
                wr_data = data;
                // Push to reference model
                ref_queue[ref_tail] = data;
                ref_tail  = (ref_tail + 1) % DEPTH;
                ref_count = ref_count + 1;
                wr_count  = wr_count  + 1;
                @(posedge wr_clk);
                wr_en = 0;
            end else begin
                $display("[%0t] WARN: write_word called but FIFO is full - skipping.", $time);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: Read one word and check against reference model (read-clock domain)
    // -------------------------------------------------------------------------
    task read_and_check;
        reg [DATA_WIDTH-1:0] expected;
        begin
            @(posedge rd_clk);
            if (!empty) begin
                rd_en = 1;
                @(posedge rd_clk);   // data registered on this edge
                rd_en = 0;
                #1;                  // tiny settle time

                expected  = ref_queue[ref_head];
                ref_head  = (ref_head + 1) % DEPTH;
                ref_count = ref_count - 1;
                rd_count  = rd_count  + 1;

                if (rd_data !== expected) begin
                    $display("[%0t] MISMATCH: rd_data=0x%0h  expected=0x%0h",
                             $time, rd_data, expected);
                    errors = errors + 1;
                end else begin
                    $display("[%0t] OK  read 0x%0h", $time, rd_data);
                end
            end else begin
                $display("[%0t] WARN: read_and_check called but FIFO is empty - skipping.", $time);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    integer i;

    initial begin
        $dumpfile("async_fifo_tb.vcd");
        $dumpvars(0, async_fifo_tb);

        // ---- 0. Initialise -----------------------------------------------
        wr_clk = 0; rd_clk = 0;
        wr_rst = 1; rd_rst = 1;
        wr_en  = 0; rd_en  = 0;
        wr_data = 0;

        // ---- 1. Reset -------------------------------------------------------
        $display("\n=== TEST 1: Reset behaviour ===");
        apply_reset;
        if (!empty)
            begin $display("FAIL: empty should be 1 after reset"); errors=errors+1; end
        else
            $display("PASS: empty asserted after reset");
        if (full)
            begin $display("FAIL: full should be 0 after reset"); errors=errors+1; end
        else
            $display("PASS: full de-asserted after reset");

        // ---- 2. Basic Write then Read ---------------------------------------
        $display("\n=== TEST 2: Basic write-then-read ===");
        write_word(8'hA5);
        write_word(8'h3C);
        write_word(8'h7F);
        // Allow Gray-code sync to propagate (2 rd_clk cycles)
        repeat(4) @(posedge rd_clk);
        read_and_check;
        read_and_check;
        read_and_check;
        repeat(4) @(posedge rd_clk);
        if (!empty)
            begin $display("FAIL: FIFO should be empty after draining"); errors=errors+1; end
        else
            $display("PASS: FIFO empty after draining");

        // ---- 3. Fill to full ------------------------------------------------
        $display("\n=== TEST 3: Fill FIFO to full ===");
        for (i = 0; i < DEPTH; i = i + 1)
            write_word(i[DATA_WIDTH-1:0]);
        // Allow sync to propagate
        repeat(4) @(posedge wr_clk);
        if (!full)
            begin $display("FAIL: FIFO should be full"); errors=errors+1; end
        else
            $display("PASS: full asserted after %0d writes", DEPTH);

        // ---- 4. Write while full (should be dropped) -----------------------
        $display("\n=== TEST 4: Write while full ===");
        @(posedge wr_clk);
        wr_en   = 1;
        wr_data = 8'hFF;
        @(posedge wr_clk);
        wr_en = 0;
        $display("Write-while-full attempted (should be silently discarded by DUT).");

        // ---- 5. Drain the FIFO --------------------------------------------
        $display("\n=== TEST 5: Drain full FIFO ===");
        repeat(4) @(posedge rd_clk);
        for (i = 0; i < DEPTH; i = i + 1)
            read_and_check;
        repeat(6) @(posedge rd_clk);
        if (!empty)
            begin $display("FAIL: FIFO should be empty after full drain"); errors=errors+1; end
        else
            $display("PASS: FIFO empty after full drain");

        // ---- 6. Read while empty ------------------------------------------
        $display("\n=== TEST 6: Read while empty ===");
        @(posedge rd_clk);
        rd_en = 1;
        @(posedge rd_clk);
        rd_en = 0;
        $display("Read-while-empty attempted (rd_data should hold previous value).");

        // ---- 7. Simultaneous Write and Read (streaming) -------------------
        $display("\n=== TEST 7: Concurrent write & read (streaming) ===");
        fork
            begin : write_stream
                for (i = 0; i < 32; i = i + 1) begin
                    @(posedge wr_clk);
                    if (!full) begin
                        wr_en   = 1;
                        wr_data = (8'h10 + i[DATA_WIDTH-1:0]);
                        ref_queue[ref_tail] = wr_data;
                        ref_tail  = (ref_tail + 1) % DEPTH;
                        ref_count = ref_count + 1;
                        wr_count  = wr_count  + 1;
                        @(posedge wr_clk);
                        wr_en = 0;
                    end
                end
            end
            begin : read_stream
                // Let a few writes complete first so FIFO isn't empty
                repeat(8) @(posedge rd_clk);
                for (i = 0; i < 32; i = i + 1) begin
                    repeat(2) @(posedge rd_clk);
                    if (!empty) begin
                        rd_en = 1;
                        @(posedge rd_clk);
                        rd_en = 0;
                        #1;
                        if (ref_count > 0) begin
                            if (rd_data !== ref_queue[ref_head]) begin
                                $display("[%0t] MISMATCH (stream): rd_data=0x%0h expected=0x%0h",
                                         $time, rd_data, ref_queue[ref_head]);
                                errors = errors + 1;
                            end else begin
                                $display("[%0t] OK  stream read 0x%0h", $time, rd_data);
                            end
                            ref_head  = (ref_head + 1) % DEPTH;
                            ref_count = ref_count - 1;
                            rd_count  = rd_count  + 1;
                        end
                    end
                end
            end
        join

        // Drain any leftovers
        repeat(6) @(posedge rd_clk);
        while (!empty) begin
            read_and_check;
            repeat(2) @(posedge rd_clk);
        end

        // ---- 8. Pointer wrap-around (write > DEPTH times total) -----------
        $display("\n=== TEST 8: Pointer wrap-around ===");
        for (i = 0; i < DEPTH; i = i + 1)
            write_word((8'hC0 + i[DATA_WIDTH-1:0]));
        repeat(4) @(posedge rd_clk);
        for (i = 0; i < DEPTH; i = i + 1)
            read_and_check;
        repeat(4) @(posedge rd_clk);
        if (!empty)
            begin $display("FAIL: FIFO should be empty after wrap-around drain"); errors=errors+1; end
        else
            $display("PASS: Wrap-around drain OK");

        // ---- 9. Summary ----------------------------------------------------
        $display("\n========================================");
        $display("  Total writes : %0d", wr_count);
        $display("  Total reads  : %0d", rd_count);
        $display("  Errors       : %0d", errors);
        if (errors == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TEST(S) FAILED ***", errors);
        $display("========================================\n");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #500000;
        $display("TIMEOUT: simulation exceeded 500 us");
        $finish;
    end

endmodule