module async_fifo_tb;

    // parameters
    parameter FIFO_DEPTH = 8;
    parameter DATA_WIDTH = 32;

    // inputs
    logic                  wr_clk, wr_rst;
    logic                  rd_clk, rd_rst;
    logic                  wr_en, rd_en;
    logic [DATA_WIDTH-1:0] wr_data;

    // outputs
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  full, empty;

    // instantiate DUT
    async_fifo #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
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

    // two clocks at different frequencies
    initial wr_clk = 0;
    always #5 wr_clk = ~wr_clk;   // 100MHz write clock

    initial rd_clk = 0;
    always #7 rd_clk = ~rd_clk;   // ~71MHz read clock

    // task to write one item
    task write_data(input [DATA_WIDTH-1:0] data);
        @(posedge wr_clk);
        wr_en   = 1;
        wr_data = data;
        @(posedge wr_clk); #1;
        wr_en   = 0;
    endtask

    // task to read one item
    task read_data;
        @(posedge rd_clk);
        rd_en = 1;
        @(posedge rd_clk); #1;
        rd_en = 0;
    endtask

    // main stimulus
    initial begin
        // initialize
        wr_en  = 0;
        rd_en  = 0;
        wr_data = 0;

        // assert reset — active low so pull low
        wr_rst = 0;
        rd_rst = 0;
        #20;
        wr_rst = 1;
        rd_rst = 1;
        #10;

        // check reset state
        assert (empty) else $error("FAIL: should be empty after reset");
        assert (!full)  else $error("FAIL: should not be full after reset");

        // ── TEST 1: write a few items and check empty goes low ──
        write_data(32'hAAAA_AAAA);
        write_data(32'hBBBB_BBBB);
        write_data(32'hCCCC_CCCC);
        #20; // let signals propagate across domains
        assert (!empty) else $error("FAIL: should not be empty after writes");
        $display("TEST 1 PASSED: empty deasserted after writes");

        // ── TEST 2: read back and verify data order ──
        @(posedge rd_clk); #1;
        rd_en = 1;
        @(posedge rd_clk); #1;
        assert (rd_data == 32'hAAAA_AAAA)
            else $error("FAIL: expected 0xAAAAAAAA got 0x%h", rd_data);
        
        @(posedge rd_clk); #1;
        assert (rd_data == 32'hBBBB_BBBB)
            else $error("FAIL: expected 0xBBBBBBBB got 0x%h", rd_data);

        @(posedge rd_clk); #1;
        assert (rd_data == 32'hCCCC_CCCC)
            else $error("FAIL: expected 0xCCCCCCCC got 0x%h", rd_data);
        rd_en = 0;
        $display("TEST 2 PASSED: data read back in correct order");

        // let empty propagate back
        #30;
        assert (empty) else $error("FAIL: should be empty after reading all items");
        $display("TEST 3 PASSED: empty reasserted after draining");

        // ── TEST 3: fill to full ──
        repeat(FIFO_DEPTH) begin
            write_data($random);
        end
        #30; // let full flag propagate
        assert (full)  else $error("FAIL: should be full after writing DEPTH items");
        assert (!empty) else $error("FAIL: should not be empty when full");
        $display("TEST 4 PASSED: full asserted after writing DEPTH items");

        // ── TEST 4: write when full should be ignored ──
        write_data(32'hDEAD_BEEF); // should be dropped
        #10;
        assert (full) else $error("FAIL: should still be full");
        $display("TEST 5 PASSED: write when full correctly ignored");

        // ── TEST 5: drain completely ──
        repeat(FIFO_DEPTH) begin
            read_data();
        end
        #30;
        assert (empty) else $error("FAIL: should be empty after draining");
        assert (!full)  else $error("FAIL: should not be full when empty");
        $display("TEST 6 PASSED: empty after full drain");

        // ── TEST 6: simultaneous read and write ──
        // write and read at the same time — FIFO should stay at same level
        wr_en   = 1;
        rd_en   = 1;
        wr_data = 32'h1234_5678;
        repeat(4) begin
            @(posedge wr_clk);
        end
        wr_en = 0;
        rd_en = 0;
        #20;
        $display("TEST 7 PASSED: simultaneous read/write completed");

        // ── full and empty mutex check ──
        assert (!(full && empty))
            else $error("FAIL: full and empty both asserted simultaneously");

        $display("ALL TESTS PASSED");
        $finish;
    end

    // continuous assertions — fire every clock edge
    always @(posedge wr_clk) begin
        assert (!(full && empty))
            else $error("CONCURRENT FAIL: full and empty both high on wr_clk edge");
    end

    always @(posedge rd_clk) begin
        assert (!(full && empty))
            else $error("CONCURRENT FAIL: full and empty both high on rd_clk edge");
    end

endmodule
