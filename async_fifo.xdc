create_clock -period 10.000 -name wr_clk [get_ports wr_clk]
create_clock -period 14.000 -name rd_clk [get_ports rd_clk]
set_clock_groups -asynchronous -group [get_clocks wr_clk] -group [get_clocks rd_clk]
