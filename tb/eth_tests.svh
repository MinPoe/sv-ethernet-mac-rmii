class eth_base_test extends uvm_test;
  `uvm_component_utils(eth_base_test)
  eth_env env;
  eth_cfg cfg;
  virtual rmii_if rmii_vif;
  virtual axis_if axis_rx_vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    cfg = eth_cfg::type_id::create("cfg");
    uvm_config_db#(eth_cfg)::set(this, "*", "cfg", cfg);
    env = eth_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual rmii_if)::get(this, "", "rmii_vif", rmii_vif))
      `uvm_fatal("NOVIF", "rmii_vif")
    if (!uvm_config_db#(virtual axis_if)::get(this, "", "axis_rx_vif", axis_rx_vif))
      `uvm_fatal("NOVIF", "axis_rx_vif")
  endfunction

  task cfg_regs(bit tx_en, bit rx_en, bit promisc = 0);
    reg_cfg_seq s = reg_cfg_seq::type_id::create("cfg_seq");
    s.tx_en = tx_en;
    s.rx_en = rx_en;
    s.promisc_en = promisc;
    s.start(env.regs.sqr);
  endtask

  task read_all();
    reg_read_all_seq s = reg_read_all_seq::type_id::create("rd_seq");
    s.start(env.regs.sqr);
  endtask

  task clear_counters();
    reg_clear_seq s = reg_clear_seq::type_id::create("clr_seq");
    s.start(env.regs.sqr);
  endtask

  task wait_idle();
    int unsigned quiet = 0;
    while (quiet < 200) begin
      @(posedge rmii_vif.clk);
      if (rmii_vif.tx_en || rmii_vif.crs_dv || axis_rx_vif.tvalid) quiet = 0;
      else quiet++;
    end
  endtask

  virtual task traffic();
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #200ns;
    read_all();
    traffic();
    wait_idle();
    read_all();
    #100ns;
    phase.drop_objection(this);
  endtask
endclass


// RX random test
class eth_rx_rand_test extends eth_base_test;
  `uvm_component_utils(eth_rx_rand_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task traffic();
    rx_rand_seq s = rx_rand_seq::type_id::create("s");
    cfg_regs(0, 1, 1); // RX only, promisc
    s.n = 100;
    s.start(env.rmii.sqr);
  endtask
endclass


// RX directed corners
class eth_rx_corner_test extends eth_base_test;
  `uvm_component_utils(eth_rx_corner_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task traffic();
    rx_corner_seq c = rx_corner_seq::type_id::create("c");
    cfg_regs(0, 1, 1);
    c.start(env.rmii.sqr);
  endtask
endclass


// RX error injection
class eth_rx_err_test extends eth_base_test;
  `uvm_component_utils(eth_rx_err_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task traffic();
    rx_err_seq s = rx_err_seq::type_id::create("s");
    cfg_regs(0, 1, 1);
    s.n = 80;
    s.start(env.rmii.sqr);
  endtask
endclass


// TX random test
class eth_tx_rand_test extends eth_base_test;
  `uvm_component_utils(eth_tx_rand_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task traffic();
    tx_base_seq s = tx_base_seq::type_id::create("s");
    cfg_regs(1, 0);
    s.n = 50;
    s.start(env.tx.sqr);
  endtask
endclass


// TX directed corners
class eth_tx_corner_test extends eth_base_test;
  `uvm_component_utils(eth_tx_corner_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task traffic();
    tx_corner_seq c = tx_corner_seq::type_id::create("c");
    cfg_regs(1, 0);
    c.start(env.tx.sqr);
  endtask
endclass


// RX backpressure stress
class eth_rx_bp_test extends eth_base_test;
  `uvm_component_utils(eth_rx_bp_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task traffic();
    rx_rand_seq s;
    cfg_regs(0, 1, 1);

    cfg.bp_mode = BP_RAND50;
    s = rx_rand_seq::type_id::create("s1");
    s.n = 40;
    s.start(env.rmii.sqr);
    wait_idle();

    cfg.bp_mode = BP_BURSTY;
    s = rx_rand_seq::type_id::create("s2");
    s.n = 40;
    s.start(env.rmii.sqr);
  endtask
endclass


// combined TX + RX
class eth_full_test extends eth_base_test;
  `uvm_component_utils(eth_full_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task traffic();
    cfg_regs(1, 1, 1);

    fork
      begin
        tx_base_seq s = tx_base_seq::type_id::create("tx_s");
        s.n = 30;
        s.start(env.tx.sqr);
      end

      begin
        rx_rand_seq s = rx_rand_seq::type_id::create("rx_s");
        s.n = 30;
        s.start(env.rmii.sqr);
      end
    join
  endtask
endclass
