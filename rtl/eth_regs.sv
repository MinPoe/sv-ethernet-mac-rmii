// Config registers + event counters (TX + RX)
// Simple bus: 1-cycle write, 1-cycle read, reg_rvalid one cycle after reg_rd
//
// Word addresses (byte addr = word << 2):
//   0x00 CTRL       [0] tx_en  [1] rx_en  [2] promisc
//   0x04 MAC_ADDR_L [31:0]  lower 4 bytes
//   0x08 MAC_ADDR_H [15:0]  upper 2 bytes
//   0x10 TX_FRAMES  RO
//   0x14 RX_FRAMES  RO
//   0x18 RX_FCS_ERR RO
//   0x1C RX_DROPPED RO (runt + oversize + filter)
//   0x20 RX_FIFO_OVF RO
//   0x24 CLEAR      write 1 clears all counters

module eth_regs (
  input logic clk,
  input logic rst_n,

  // register bus
  input logic reg_wr,
  input logic reg_rd,
  input logic [4:0] reg_addr, // byte address [6:2]
  input logic [31:0] reg_wdata,
  output logic [31:0] reg_rdata,
  output logic reg_rvalid,

  // TX events
  input logic ev_tx_done,

  // RX events
  input logic ev_good,
  input logic ev_crc,
  input logic ev_runt,
  input logic ev_over,
  input logic ev_ovfl,

  // config outputs
  output logic tx_enable,
  output logic rx_enable,
  output logic promisc,
  output logic [47:0] mac_addr
);

  logic [31:0] tx_frames, rx_frames, rx_fcs_err, rx_dropped, rx_fifo_ovf;
  logic clr;
  assign clr = reg_wr && (reg_addr == 5'h09); // 0x24 >> 2 = 9

  /* ctrl + mac addr */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_enable <= 1'b0;
      rx_enable <= 1'b0;
      promisc <= 1'b0;
      mac_addr <= 48'd0;
    end

    else if (reg_wr) begin
      case (reg_addr)
        5'h00: begin
          tx_enable <= reg_wdata[0];
          rx_enable <= reg_wdata[1];
          promisc <= reg_wdata[2];
        end

        5'h01: mac_addr[31:0] <= reg_wdata;
        5'h02: mac_addr[47:32] <= reg_wdata[15:0];
        default: ;
      endcase
    end

  end


  /* counters */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_frames <= 32'd0;
      rx_frames <= 32'd0;
      rx_fcs_err <= 32'd0;
      rx_dropped <= 32'd0;
      rx_fifo_ovf <= 32'd0;
    end

    else if (clr) begin
      tx_frames <= 32'd0;
      rx_frames <= 32'd0;
      rx_fcs_err <= 32'd0;
      rx_dropped <= 32'd0;
      rx_fifo_ovf <= 32'd0;
    end

    else begin
      if (ev_tx_done) tx_frames <= tx_frames + 32'd1;
      if (ev_good) rx_frames <= rx_frames + 32'd1;
      if (ev_crc) rx_fcs_err <= rx_fcs_err + 32'd1;
      if (ev_runt || ev_over) rx_dropped <= rx_dropped + 32'd1;
      if (ev_ovfl) rx_fifo_ovf <= rx_fifo_ovf + 32'd1;
    end

  end


  /* read mux */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_rdata <= 32'd0;
      reg_rvalid <= 1'b0;
    end

    else begin
      reg_rvalid <= reg_rd;
      case (reg_addr)
        5'h00: reg_rdata <= {29'd0, promisc, rx_enable, tx_enable};
        5'h01: reg_rdata <= mac_addr[31:0];
        5'h02: reg_rdata <= {16'd0, mac_addr[47:32]};
        5'h04: reg_rdata <= tx_frames;
        5'h05: reg_rdata <= rx_frames;
        5'h06: reg_rdata <= rx_fcs_err;
        5'h07: reg_rdata <= rx_dropped;
        5'h08: reg_rdata <= rx_fifo_ovf;
        default: reg_rdata <= 32'd0;
      endcase
    end

  end

endmodule
