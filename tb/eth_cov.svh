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

    x_len_err : cross cp_len, cp_err {
      // good/bad-CRC frames always have body 64-1518 (padded + FCS)
      ignore_bins i_good_low = binsof(cp_err) intersect {ERR_NONE, ERR_BAD_CRC} &&
                               binsof(cp_len) intersect {[0:63]};
      ignore_bins i_good_over = binsof(cp_err) intersect {ERR_NONE, ERR_BAD_CRC} &&
                                binsof(cp_len) intersect {[1519:$]};

      // runts are < 64 bytes on the wire by definition
      ignore_bins i_runt_big = binsof(cp_err) intersect {ERR_RUNT} &&
                               binsof(cp_len) intersect {[64:$]};

      // oversize is > 1518 bytes on the wire
      ignore_bins i_over_small = binsof(cp_err) intersect {ERR_OVERSIZE} &&
                                 binsof(cp_len) intersect {[0:1518]};

      // truncated frames have no SFD so body_len is always 0
      ignore_bins i_trunc_nz = binsof(cp_err) intersect {ERR_TRUNC} &&
                               binsof(cp_len) intersect {[1:$]};
    }

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
