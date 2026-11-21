`uvm_analysis_imp_decl(_rx_exp)
`uvm_analysis_imp_decl(_rx_act)
`uvm_analysis_imp_decl(_tx_exp)
`uvm_analysis_imp_decl(_tx_act)
`uvm_analysis_imp_decl(_sreg)

class eth_scb extends uvm_component;
  `uvm_component_utils(eth_scb)
  uvm_analysis_imp_rx_exp #(axis_frame, eth_scb) rx_exp_imp;
  uvm_analysis_imp_rx_act #(axis_frame, eth_scb) rx_act_imp;
  uvm_analysis_imp_tx_exp #(rmii_tx_frame, eth_scb) tx_exp_imp;
  uvm_analysis_imp_tx_act #(rmii_tx_frame, eth_scb) tx_act_imp;
  uvm_analysis_imp_sreg #(reg_item, eth_scb) reg_imp;
  eth_refmodel model;

  axis_frame rx_exp_q[$];
  rmii_tx_frame tx_exp_q[$];
  int unsigned n_rx_exp, n_rx_seen, n_rx_match, n_rx_mismatch;
  int unsigned n_tx_exp, n_tx_seen, n_tx_match, n_tx_mismatch;
  int unsigned n_reg_reads;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    rx_exp_imp = new("rx_exp_imp", this);
    rx_act_imp = new("rx_act_imp", this);
    tx_exp_imp = new("tx_exp_imp", this);
    tx_act_imp = new("tx_act_imp", this);
    reg_imp = new("reg_imp", this);
  endfunction

  // RX path checking
  function void write_rx_exp(axis_frame e);
    rx_exp_q.push_back(e);
    n_rx_exp++;
  endfunction

  function void write_rx_act(axis_frame f);
    n_rx_seen++;
    if (rx_exp_q.size() == 0) begin
      n_rx_mismatch++;
      `uvm_error("SCB_RX", $sformatf("unexpected RX output frame (len=%0d)", f.data.size()))
      return;
    end

    begin
      axis_frame e = rx_exp_q.pop_front();
      if (e.data.size() != f.data.size() || e.user != f.user) begin
        n_rx_mismatch++;
        `uvm_error("SCB_RX", $sformatf("RX mismatch: exp len=%0d user=%0b, got len=%0d user=%0b",
                   e.data.size(), e.user, f.data.size(), f.user))
      end

      else begin
        bit ok = 1;
        foreach (e.data[i]) begin
          if (e.data[i] != f.data[i]) begin
            `uvm_error("SCB_RX", $sformatf("RX data mismatch at byte %0d: exp %02x got %02x", i, e.data[i], f.data[i]))
            ok = 0;
            break;
          end
        end

        if (ok) n_rx_match++;
        else n_rx_mismatch++;
      end
    end
  endfunction

  // TX path checking
  function void write_tx_exp(rmii_tx_frame e);
    tx_exp_q.push_back(e);
    n_tx_exp++;
  endfunction

  function void write_tx_act(rmii_tx_frame f);
    n_tx_seen++;
    if (tx_exp_q.size() == 0) begin
      n_tx_mismatch++;
      `uvm_error("SCB_TX", $sformatf("unexpected TX frame on RMII (len=%0d)", f.bytes.size()))
      return;
    end

    begin
      rmii_tx_frame e = tx_exp_q.pop_front();
      if (e.bytes.size() != f.bytes.size()) begin
        n_tx_mismatch++;
        `uvm_error("SCB_TX", $sformatf("TX length mismatch: exp %0d got %0d", e.bytes.size(), f.bytes.size()))
      end

      else begin
        bit ok = 1;
        foreach (e.bytes[i]) begin
          if (e.bytes[i] != f.bytes[i]) begin
            `uvm_error("SCB_TX", $sformatf("TX data mismatch at byte %0d: exp %02x got %02x", i, e.bytes[i], f.bytes[i]))
            ok = 0;
            break;
          end
        end

        if (ok) n_tx_match++;
        else n_tx_mismatch++;
      end
    end
  endfunction

  // register checking
  function void write_sreg(reg_item t);
    if (t.write) begin
      if (t.addr == A_CLR) begin
        rx_exp_q.delete();
        tx_exp_q.delete();
      end

      return;
    end

    n_reg_reads++;
    begin
      bit [31:0] want = model.expected_reg(t.addr);
      if (t.rdata != want)
        `uvm_error("REG", $sformatf("read of addr %0d: expected 0x%08x got 0x%08x", t.addr, want, t.rdata))
    end
  endfunction

  function void check_phase(uvm_phase phase);
    if (rx_exp_q.size() != 0)
      `uvm_error("SCB_RX", $sformatf("%0d expected RX frame(s) never delivered", rx_exp_q.size()))
    if (tx_exp_q.size() != 0)
      `uvm_error("SCB_TX", $sformatf("%0d expected TX frame(s) never seen on RMII", tx_exp_q.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB_SUMMARY", $sformatf(
      "RX: exp=%0d seen=%0d match=%0d err=%0d | TX: exp=%0d seen=%0d match=%0d err=%0d | reg_reads=%0d",
      n_rx_exp, n_rx_seen, n_rx_match, n_rx_mismatch,
      n_tx_exp, n_tx_seen, n_tx_match, n_tx_mismatch,
      n_reg_reads), UVM_NONE)
  endfunction
endclass
