`timescale 1ns/1ps

module tb_async_fifo;

    parameter DATA_WIDTH = 8;
    parameter DEPTH      = 16;
    parameter ADDR_WIDTH = 4;

    // DUT signals
    reg  wr_clk, wr_rst, wr_en;
    reg  [DATA_WIDTH-1:0] wr_data;
    wire full;

    reg  rd_clk, rd_rst, rd_en;
    wire [DATA_WIDTH-1:0] rd_data;
    wire empty;

    // Instantiate DUT
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk(wr_clk),
        .wr_rst(wr_rst),
        .wr_en (wr_en),
        .wr_data(wr_data),
        .full(full),

        .rd_clk(rd_clk),
        .rd_rst(rd_rst),
        .rd_en (rd_en),
        .rd_data(rd_data),
        .empty(empty)
    );

    // -----------------------------
    // Clocks: 50 MHz and ~38 MHz
    // -----------------------------
    initial begin
        wr_clk = 0;
        forever #10 wr_clk = ~wr_clk; // 20ns period
    end

    initial begin
        rd_clk = 0;
        forever #13 rd_clk = ~rd_clk; // 26ns period (async-ish)
    end

    // -----------------------------
    // Scoreboard model (fixed array)
    // -----------------------------
    reg [DATA_WIDTH-1:0] model_mem [0:DEPTH-1];
    integer head, tail;
    integer count;

    // For 1-cycle-late read check
    reg pending_check;
    reg [DATA_WIDTH-1:0] expected_d;

    function integer wrap_inc;
        input integer idx;
        begin
            if (idx == DEPTH-1) wrap_inc = 0;
            else                wrap_inc = idx + 1;
        end
    endfunction

    // -----------------------------
    // Reset + init
    // -----------------------------
    initial begin
        $display("TB START T=%0t", $time);

        wr_rst  = 1;
        rd_rst  = 1;
        wr_en   = 0;
        rd_en   = 0;
        wr_data = 0;

        head = 0;
        tail = 0;
        count = 0;

        pending_check = 0;
        expected_d = 0;

        // deassert resets at different times
        #55  wr_rst = 0;  $display("wr_rst deassert T=%0t", $time);
        #37  rd_rst = 0;  $display("rd_rst deassert T=%0t", $time);
    end

    // -----------------------------
    // WRITE DRIVER (drive on negedge wr_clk)
    // -----------------------------
    always @(negedge wr_clk) begin
        if (wr_rst) begin
            wr_en   <= 0;
            wr_data <= 0;
        end else begin
            // ~75% chance to try writing if not full
            if (!full && (($random & 3) != 0)) begin
                wr_en   <= 1;
                wr_data <= $random; // truncates to DATA_WIDTH automatically
            end else begin
                wr_en <= 0;
            end
        end
    end

    // Scoreboard push on successful write
    always @(posedge wr_clk) begin
        if (!wr_rst && wr_en && !full) begin
            if (count >= DEPTH) begin
                $display("TB FAIL (OVERFLOW) T=%0t count=%0d empty=%b full=%b",
                         $time, count, empty, full);
                $finish;
            end
            model_mem[tail] <= wr_data;
            tail <= wrap_inc(tail);
            count <= count + 1;
        end
    end

    // -----------------------------
    // READ DRIVER (drive on negedge rd_clk)
    // -----------------------------
    always @(negedge rd_clk) begin
        if (rd_rst) begin
            rd_en <= 0;
        end else begin
            // ~50% chance to try reading if not empty
            if (!empty && (($random & 1) == 0)) begin
                rd_en <= 1;
            end else begin
                rd_en <= 0;
            end
        end
    end

    // -----------------------------
    // READ SCOREBOARD (1-cycle-late compare)
    // - When a read is accepted, we record expected data
    // - On the NEXT rd_clk edge, we compare rd_data to expected
    // -----------------------------
    always @(posedge rd_clk) begin
        if (rd_rst) begin
            pending_check <= 0;
        end else begin
            // Compare result of previous accepted read
            if (pending_check) begin
                if (rd_data !== expected_d) begin
                    $display("TB FAIL (MISMATCH) T=%0t exp=%0h got=%0h head=%0d tail=%0d count=%0d empty=%b full=%b",
                             $time, expected_d, rd_data, head, tail, count, empty, full);
                    $finish;
                end
                pending_check <= 0;
            end

            // Launch a new expected value on accepted read
            if (rd_en && !empty) begin
                if (count <= 0) begin
                    $display("TB FAIL (UNDERFLOW) T=%0t count=%0d empty=%b full=%b",
                             $time, count, empty, full);
                    $finish;
                end
                expected_d <= model_mem[head];
                head <= wrap_inc(head);
                count <= count - 1;
                pending_check <= 1;
            end
        end
    end

    // -----------------------------
    // End simulation after timeout
    // -----------------------------
    initial begin
        #5000;
        $display("SIM DONE T=%0t final_count=%0d empty=%b full=%b", $time, count, empty, full);
        $finish;
    end

endmodule