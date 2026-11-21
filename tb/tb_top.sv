`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  import eth_pkg::*;

  logic clk = 1'b0;
  logic rst_n;
  always #10 clk = ~clk; // 50 MHz

  rmii_if rmii_i (clk);
  axis_if axis_tx_i (clk); // user -> MAC TX input
  axis_if axis_rx_i (clk); // MAC RX output -> user
  reg_if reg_i (clk);

  initial begin
    rst_n = 1'b1;
    #1 rst_n = 1'b0;
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
  end

  eth_mac_top dut (
    .clk, .rst_n,

    // RMII
    .txd(rmii_i.txd), .tx_en(rmii_i.tx_en),
    .rxd(rmii_i.rxd), .crs_dv(rmii_i.crs_dv),

    // AXI-Stream TX input
    .s_tdata(axis_tx_i.tdata), .s_tvalid(axis_tx_i.tvalid),
    .s_tready(axis_tx_i.tready), .s_tlast(axis_tx_i.tlast),

    // AXI-Stream RX output
    .m_tdata(axis_rx_i.tdata), .m_tvalid(axis_rx_i.tvalid),
    .m_tready(axis_rx_i.tready), .m_tlast(axis_rx_i.tlast),
    .m_tuser(axis_rx_i.tuser),

    // registers
    .reg_wr(reg_i.wr), .reg_rd(reg_i.rd),
    .reg_addr(reg_i.addr), .reg_wdata(reg_i.wdata),
    .reg_rdata(reg_i.rdata), .reg_rvalid(reg_i.rvalid)
  );

  initial begin
    uvm_config_db#(virtual rmii_if)::set(null, "*", "rmii_vif", rmii_i);
    uvm_config_db#(virtual axis_if)::set(null, "*", "axis_tx_vif", axis_tx_i);
    uvm_config_db#(virtual axis_if)::set(null, "*", "axis_rx_vif", axis_rx_i);
    uvm_config_db#(virtual reg_if)::set(null, "*", "reg_vif", reg_i);
    run_test();
  end

  initial begin
    #80ms;
    $display("WATCHDOG_TIMEOUT");
    $fatal(1, "simulation watchdog expired");
  end
endmodule
