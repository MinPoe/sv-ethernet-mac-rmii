interface rmii_if (input logic clk);
  logic [1:0] txd;
  logic       tx_en;
  logic [1:0] rxd;
  logic       crs_dv;
endinterface

interface axis_if (input logic clk);
  logic [7:0] tdata;
  logic       tvalid;
  logic       tready;
  logic       tlast;
  logic       tuser;
endinterface

interface reg_if (input logic clk);
  logic        wr;
  logic        rd;
  logic [4:0]  addr;
  logic [31:0] wdata;
  logic [31:0] rdata;
  logic        rvalid;
endinterface
