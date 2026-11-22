// Ethernet MAC top level
// Wires together TX path, RX path, and register block
// Two build modes: loopback (PLL clock) and PHY (external REF_CLK)

module eth_mac_top (
  input logic clk, // 50 MHz REF_CLK
  input logic rst_n,

  // RMII PHY interface
  output logic [1:0] txd,
  output logic tx_en,
  input logic [1:0] rxd,
  input logic crs_dv,

  // AXI-Stream TX input (user side, no FCS)
  input logic [7:0] s_tdata,
  input logic s_tvalid,
  output logic s_tready,
  input logic s_tlast,

  // AXI-Stream RX output (user side, FCS stripped)
  output logic [7:0] m_tdata,
  output logic m_tvalid,
  input logic m_tready,
  output logic m_tlast,
  output logic m_tuser,

  // register bus
  input logic reg_wr,
  input logic reg_rd,
  input logic [4:0] reg_addr,
  input logic [31:0] reg_wdata,
  output logic [31:0] reg_rdata,
  output logic reg_rvalid
);

  // config wires
  logic tx_enable, rx_enable, promisc;
  logic [47:0] mac_addr;

  // event wires
  logic ev_tx_done;
  logic ev_good, ev_crc, ev_runt, ev_over, ev_ovfl;

  // internal TX byte stream
  logic [7:0] tx_byte_data;
  logic tx_byte_valid, tx_byte_last, tx_byte_ready;

  // internal RX byte stream
  logic [7:0] rx_line_data;
  logic rx_line_valid;
  logic rx_line_active;


  /* registers */
  eth_regs u_regs (
    .clk, .rst_n,
    .reg_wr, .reg_rd, .reg_addr, .reg_wdata, .reg_rdata, .reg_rvalid,
    .ev_tx_done,
    .ev_good, .ev_crc, .ev_runt, .ev_over, .ev_ovfl,
    .tx_enable, .rx_enable, .promisc, .mac_addr
  );


  /* TX path */
  tx_ctrl u_tx_ctrl (
    .clk, .rst_n,
    .enable(tx_enable),
    .s_tdata, .s_tvalid, .s_tready, .s_tlast,
    .tx_data(tx_byte_data),
    .tx_valid(tx_byte_valid),
    .tx_last(tx_byte_last),
    .tx_ready(tx_byte_ready),
    .ev_tx_done
  );

  rmii_tx u_rmii_tx (
    .clk, .rst_n,
    .tx_data(tx_byte_data),
    .tx_valid(tx_byte_valid),
    .tx_last(tx_byte_last),
    .tx_ready(tx_byte_ready),
    .txd, .tx_en
  );


  /* RX path */
  rmii_rx u_rmii_rx (
    .clk, .rst_n,
    .rxd, .crs_dv,
    .line_data(rx_line_data),
    .line_valid(rx_line_valid),
    .line_active(rx_line_active)
  );

  rx_ctrl u_rx_ctrl (
    .clk, .rst_n,
    .line_valid(rx_line_valid),
    .line_data(rx_line_data),
    .line_active(rx_line_active),
    .m_tdata, .m_tvalid, .m_tready, .m_tlast, .m_tuser,
    .enable(rx_enable),
    .promisc,
    .mac_addr,
    .ev_good, .ev_crc, .ev_runt, .ev_over, .ev_ovfl
  );

endmodule
