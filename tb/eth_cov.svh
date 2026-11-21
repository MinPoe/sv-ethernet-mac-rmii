class eth_cov extends uvm_subscriber #(rx_frame);
  `uvm_component_utils(eth_cov)

  covergroup cg_rx_frame with function sample(err_e err, int unsigned blen, bp_e bp);
    cp_err : coverpoint err;
    cp_len : coverpoint blen {
      bins l_0 = {0};
      bins l_1_17 = {[1:17]};
      bins l_18_62 = {[18:62]};
      bins l_63 = {63};
      bins l_64 = {64};
      bins l_65_127 = {[65:127]};
      bins l_mid = {[128:1023]};
      bins l_big = {[1024:1517]};
      bins l_1518 = {1518};
      bins l_over = {[1519:$]};
    }
    cp_bp : coverpoint bp;
    x_len_err : cross cp_len, cp_err;
    x_bp_err : cross cp_bp, cp_err;
  endgroup

  eth_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_rx_frame = new();
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(eth_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "eth_cfg not set")
  endfunction

  function void write(rx_frame t);
    int unsigned body_len = 0;
    int unsigned k = 0;
    while (k < t.wbytes.size() && t.wbytes[k] == 8'h55) k++;
    if (k < t.wbytes.size() && t.wbytes[k] == 8'hD5)
      body_len = t.wbytes.size() - k - 1;
    cg_rx_frame.sample(t.err, body_len, cfg.bp_mode);
  endfunction
endclass
