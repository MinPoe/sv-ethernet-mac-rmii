`uvm_analysis_imp_decl(_rmii_rx)
`uvm_analysis_imp_decl(_tx_in)
`uvm_analysis_imp_decl(_reg)

// Reference model: predicts DUT behavior for both RX and TX paths
class eth_refmodel extends uvm_component;
  `uvm_component_utils(eth_refmodel)
  uvm_analysis_imp_rmii_rx #(rx_frame, eth_refmodel) rx_imp;
  uvm_analysis_imp_tx_in #(tx_frame, eth_refmodel) tx_imp;
  uvm_analysis_imp_reg #(reg_item, eth_refmodel) reg_imp;
  uvm_analysis_port #(axis_frame) rx_exp_ap; // expected RX AXI-Stream output
  uvm_analysis_port #(rmii_tx_frame) tx_exp_ap; // expected TX RMII output

  // modelled DUT state
  bit tx_enable = 0, rx_enable = 0, promisc = 0;
  bit [47:0] mac_addr = 0;
  int unsigned n_tx, n_rx_good, n_rx_crc, n_rx_runt, n_rx_over;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    byte unsigned v[$];
    string s = "123456789";
    rx_imp = new("rx_imp", this);
    tx_imp = new("tx_imp", this);
    reg_imp = new("reg_imp", this);
    rx_exp_ap = new("rx_exp_ap", this);
    tx_exp_ap = new("tx_exp_ap", this);

    // CRC self-check
    for (int i = 0; i < s.len(); i++) v.push_back(s[i]);
    if (ref_crc32(v) != 32'hCBF4_3926)
      `uvm_fatal("CRCSELF", "reference CRC32 fails the standard check vector")
  endfunction

  function void write_reg(reg_item t);
    if (!t.write) return;
    case (t.addr)
      A_CTRL: begin
        tx_enable = t.wdata[0];
        rx_enable = t.wdata[1];
        promisc = t.wdata[2];
      end

      A_MAC_L: mac_addr[31:0] = t.wdata;
      A_MAC_H: mac_addr[47:32] = t.wdata[15:0];
      A_CLR: begin
        n_tx = 0;
        n_rx_good = 0;
        n_rx_crc = 0;
        n_rx_runt = 0;
        n_rx_over = 0;
      end

      default: ;
    endcase
  endfunction

  // predict RX output from an RMII input frame
  function void write_rmii_rx(rx_frame f);
    byte unsigned body[$];
    int unsigned k = 0;
    int unsigned L;
    bit [31:0] fcs, got;
    byte unsigned msg[$];
    bit [47:0] da;
    bit da_ok;

    // skip preamble
    while (k < f.wbytes.size() && f.wbytes[k] == 8'h55) k++;
    if (!rx_enable) return;
    if (k == 0 || k >= f.wbytes.size() || f.wbytes[k] != 8'hD5) return;

    for (int i = k + 1; i < f.wbytes.size(); i++) body.push_back(f.wbytes[i]);
    L = body.size();

    if (L < 64) begin
      n_rx_runt++;
      return;
    end

    if (L > 1518) begin
      n_rx_over++;
      return;
    end

    // address filter
    for (int i = 0; i < 6; i++) da[8*(5-i) +: 8] = body[i];
    da_ok = promisc || (da == mac_addr) || (da == 48'hFFFF_FFFF_FFFF);

    // CRC check
    for (int i = 0; i < L - 4; i++) msg.push_back(body[i]);
    fcs = ref_crc32(msg);
    got = {body[L-1], body[L-2], body[L-3], body[L-4]};

    if (fcs != got) begin
      n_rx_crc++;
      // bad FCS frames still forwarded with tuser=1
      if (da_ok) begin
        axis_frame e = new("rx_exp");
        for (int i = 14; i < L - 4; i++) e.data.push_back(body[i]);
        e.user = 1;
        rx_exp_ap.write(e);
      end

      return;
    end

    if (!da_ok) return;

    n_rx_good++;
    begin
      axis_frame e = new("rx_exp");
      for (int i = 14; i < L - 4; i++) e.data.push_back(body[i]);
      e.user = 0;
      rx_exp_ap.write(e);
    end
  endfunction

  // predict TX output from an AXI-Stream input frame
  function void write_tx_in(tx_frame f);
    byte unsigned bytes[$];
    byte unsigned body[$];
    byte unsigned padded[$];
    bit [31:0] fcs;
    rmii_tx_frame e;

    if (!tx_enable) return;

    f.get_axis_bytes(bytes);

    // pad to 60 bytes (before FCS)
    padded = bytes;
    while (padded.size() < 60) padded.push_back(8'h00);

    fcs = ref_crc32(padded);

    e = new("tx_exp");
    foreach (padded[i]) e.bytes.push_back(padded[i]);
    for (int i = 0; i < 4; i++) e.bytes.push_back(fcs[8*i +: 8]);

    n_tx++;
    tx_exp_ap.write(e);
  endfunction

  function bit [31:0] expected_reg(bit [4:0] a);
    case (a)
      A_CTRL: return {29'd0, promisc, rx_enable, tx_enable};
      A_MAC_L: return mac_addr[31:0];
      A_MAC_H: return {16'd0, mac_addr[47:32]};
      A_TX_FRAMES: return n_tx;
      A_RX_FRAMES: return n_rx_good;
      A_RX_FCS: return n_rx_crc;
      A_RX_DROP: return n_rx_runt + n_rx_over;
      A_RX_OVF: return 0; // simplified for now
      default: return 0;
    endcase
  endfunction
endclass
