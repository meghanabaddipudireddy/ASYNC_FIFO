module async_fifo_tb;

    parameter FIFO_DEPTH = 8;
    parameter DATA_WIDTH = 32;

    logic                  wr_clk, wr_rst;
    logic                  rd_clk, rd_rst;
    logic                  wr_en, rd_en;
    logic [DATA_WIDTH-1:0] wr_data;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  full, empty;

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

    initial wr_clk = 0;
    always #5 wr_clk = ~wr_clk;

    initial rd_clk = 0;
    always #7 rd_clk = ~rd_clk;

    task write_one(input [DATA_WIDTH-1:0] data);
        @(negedge wr_clk);
        wr_en   = 1;
        wr_data = data;
        @(posedge wr_clk); #1;
        wr_en   = 0;
    endtask

    task read_one(output [DATA_WIDTH-1:0] data);
        @(negedge rd_clk);
        rd_en = 1;
        @(posedge rd_clk); #1;
        data  = rd_data;
        rd_en = 0;
    endtask

    logic [DATA_WIDTH-1:0] captured;

    initial begin
        wr_en   = 0;
        rd_en   = 0;
        wr_data = 0;

        wr_rst = 0;
        rd_rst = 0;
        #40;
        wr_rst = 1;
        rd_rst = 1;
        #40;

        // reset check
        assert (empty)  else $error("FAIL: should be empty after reset");
        assert (!full)  else $error("FAIL: should not be full after reset");
        $display("RESET OK");

        // ── TEST 1: write 3 items ──
        write_one(32'hAAAA_AAAA);
        write_one(32'hBBBB_BBBB);
        write_one(32'hCCCC_CCCC);
        repeat(50) @(posedge rd_clk); #1;
        assert (!empty) else $error("FAIL: should not be empty after 3 writes");
        $display("TEST 1 PASSED: not empty after writes");

        // ── TEST 2: read back in order ──
        #1;
        assert (rd_data == 32'hAAAA_AAAA)
            else $error("FAIL: item 0 expected 0xAAAAAAAA got 0x%h", rd_data);

        read_one(captured);
        assert (captured == 32'hBBBB_BBBB)
            else $error("FAIL: item 1 expected 0xBBBBBBBB got 0x%h", captured);

        read_one(captured);
        assert (captured == 32'hCCCC_CCCC)
            else $error("FAIL: item 2 expected 0xCCCCCCCC got 0x%h", captured);

        read_one(captured);
        $display("TEST 2 PASSED: data read in correct order");

        repeat(50) @(posedge rd_clk); #1;
        assert (empty) else $error("FAIL: should be empty after reading all items");
        $display("TEST 3 PASSED: empty after drain");

        // ── TEST 3: fill to full ──
        repeat(FIFO_DEPTH) begin
            write_one($random);
        end
        repeat(50) @(posedge wr_clk); #1;
        assert (full)   else $error("FAIL: should be full after DEPTH writes");
        assert (!empty) else $error("FAIL: should not be empty when full");
        $display("TEST 4 PASSED: full asserted correctly");

        // ── TEST 4: write when full ignored ──
        write_one(32'hDEAD_BEEF);
        repeat(10) @(posedge wr_clk); #1;
        assert (full) else $error("FAIL: should still be full");
        $display("TEST 5 PASSED: write when full correctly ignored");

        // ── TEST 5: drain completely ──
        repeat(FIFO_DEPTH) begin
            read_one(captured);
        end
        repeat(50) @(posedge rd_clk); #1;
        assert (empty) else $error("FAIL: should be empty after full drain");
        assert (!full)  else $error("FAIL: should not be full when empty");
        $display("TEST 6 PASSED: empty after full drain");

        // ── TEST 6: simultaneous read and write ──
        write_one(32'h1111_1111);
        write_one(32'h2222_2222);
        repeat(50) @(posedge rd_clk); #1;
        fork
            write_one(32'h3333_3333);
            read_one(captured);
        join
        repeat(50) @(posedge wr_clk); #1;
        assert (!(full && empty))
            else $error("FAIL: full and empty both high after simultaneous R/W");
        $display("TEST 7 PASSED: simultaneous read/write ok");

        $display("ALL TESTS PASSED");
        $finish;
    end

    always @(posedge wr_clk) begin
        assert (!(full && empty))
            else $error("CONCURRENT FAIL: full and empty both high on wr_clk");
    end

    always @(posedge rd_clk) begin
        assert (!(full && empty))
            else $error("CONCURRENT FAIL: full and empty both high on rd_clk");
    end

endmodule
