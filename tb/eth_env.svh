class eth_env extends uvm_env;
  `uvm_component_utils(eth_env)
  rmii_agent rmii;
  axis_tx_agent tx;
  axis_rx_agent rx;
  reg_agent regs;
  eth_refmodel model;
  eth_scb scb;
  eth_cov cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    rmii = rmii_agent::type_id::create("rmii", this);
    tx = axis_tx_agent::type_id::create("tx", this);
    rx = axis_rx_agent::type_id::create("rx", this);
    regs = reg_agent::type_id::create("regs", this);
    model = eth_refmodel::type_id::create("model", this);
    scb = eth_scb::type_id::create("scb", this);
    cov = eth_cov::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // register bus -> model + scb
    regs.mon.ap.connect(model.reg_imp);
    regs.mon.ap.connect(scb.reg_imp);

    // RX path: RMII input -> model -> scb expected; AXI-Stream output -> scb actual
    rmii.drv.ap.connect(model.rx_imp);
    model.rx_exp_ap.connect(scb.rx_exp_imp);
    rx.mon.ap.connect(scb.rx_act_imp);

    // TX path: AXI-Stream input -> model -> scb expected; RMII output -> scb actual
    tx.drv.ap.connect(model.tx_imp);
    model.tx_exp_ap.connect(scb.tx_exp_imp);
    rmii.tx_mon.ap.connect(scb.tx_act_imp);

    scb.model = model;
  endfunction
endclass
