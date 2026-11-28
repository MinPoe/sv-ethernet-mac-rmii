interface rmii_if (input logic clk);
  logic [1:0] txd;
  logic       tx_en;
  logic [1:0] rxd;
  logic       crs_dv;

  // IFG: 96 bit times = 48 RMII clocks between frames
  // $fell counts as cycle 1, |=> [*47] checks the next 47 = 48 total
  ap_tx_ifg : assert property (
    @(posedge clk) $fell(tx_en) |=> !tx_en [*47]
  );
endinterface

interface axis_if (input logic clk);
  logic [7:0] tdata;
  logic       tvalid;
  logic       tready;
  logic       tlast;
  logic       tuser;

  // AXI-Stream handshake: source must hold tvalid until accepted
  ap_tvalid_hold : assert property (
    @(posedge clk) (tvalid && !tready) |=> tvalid
  );

  // data, tlast, tuser must not change while waiting for tready
  ap_tdata_stable : assert property (
    @(posedge clk) (tvalid && !tready) |=> $stable(tdata)
  );

  ap_tlast_stable : assert property (
    @(posedge clk) (tvalid && !tready) |=> $stable(tlast)
  );

  ap_tuser_stable : assert property (
    @(posedge clk) (tvalid && !tready) |=> $stable(tuser)
  );

  // tlast only meaningful with tvalid
  ap_tlast_with_valid : assert property (
    @(posedge clk) tlast |-> tvalid
  );
endinterface

interface reg_if (input logic clk);
  logic        wr;
  logic        rd;
  logic [4:0]  addr;
  logic [31:0] wdata;
  logic [31:0] rdata;
  logic        rvalid;
endinterface
