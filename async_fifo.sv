module async_fifo #(parameter FIFO_DEPTH = 8, parameter DATA_WIDTH = 32) (
  input logic wr_en,
  input logic [DATA_WIDTH-1:0] wr_data,
  input logic wr_clk, 
  input logic wr_rst,
  input logic rd_en,
  input logic rd_clk,
  input logic rd_rst,
  output logic [DATA_WIDTH-1:0] rd_data,
  output logic full,
  output logic empty
);
  localparam FIFO_DEPTH_LOG = $clog2(FIFO_DEPTH);
  
  logic [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH - 1];
  
  logic [FIFO_DEPTH_LOG:0] write_pointer;
  logic [FIFO_DEPTH_LOG:0] read_pointer;
  
  always_ff @(posedge wr_clk or negedge wr_rst) begin
    if(!wr_rst)
      write_pointer <= 0;
    else if(wr_en && !full) begin
      mem[write_pointer[FIFO_DEPTH_LOG-1:0]] <= wr_data;
      write_pointer <= write_pointer + 1'b1;
    end
  end
  
  always_ff @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst)
      read_pointer <= 0;
    else if(rd_en && !empty) begin
      read_pointer <= read_pointer + 1'b1;
    end
  end
  
  assign rd_data = mem [read_pointer[FIFO_DEPTH_LOG-1:0]];
  
  logic [FIFO_DEPTH_LOG:0] write_gray_pointer;
  logic [FIFO_DEPTH_LOG:0] read_gray_pointer;
  
  assign write_gray_pointer = write_pointer ^ (write_pointer >> 1);
  assign read_gray_pointer = read_pointer ^ (read_pointer >> 1);
  
  logic [FIFO_DEPTH_LOG:0] wq1_rptr, wq2_rptr;
  
  always_ff @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst) begin
      wq1_rptr <= 0;
      wq2_rptr <= 0;
    else begin
      wq1_rptr <= write_gray_pointer; 
      wq2_rptr <= wq1_rptr;
    end
  end
  
  logic [FIFO_DEPTH_LOG:0] rq1_wptr, rq2_wptr;
  
  always_ff @(posedge wr_clk or negedge wr_rst) begin
    if(!wr_rst) begin
      rq1_wptr <= 0;
      rq2_wptr <= 0;
    else begin
      rq1_wptr <= read_gray_pointer; 
      rq2_wptr <= rq1_wptr;
    end
  end
  
  assign empty = (wq2_rptr == read_gray_pointer);
  assign full  = (rq2_wptr == {~write_gray_pointer[FIFO_DEPTH_LOG], 
                               write_gray_pointer[FIFO_DEPTH_LOG-1:0]});

endmodule
