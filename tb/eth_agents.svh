// All drivers act on negedge clk, all monitors sample on posedge clk

/* RMII RX driver (sends frames into DUT RX) */
class rmii_rx_driver extends uvm_driver #(rx_frame);
  `uvm_component_utils(rmii_rx_driver)
  virtual rmii_if vif;
  uvm_analysis_port #(rx_frame) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rmii_if)::get(this, "", "rmii_vif", vif))
      `uvm_fatal("NOVIF", "rmii_vif not set")
  endfunction

  // serialize one byte into 4 dibits on rxd
  task drive_byte(byte unsigned b);
    for (int i = 0; i < 4; i++) begin
      @(negedge vif.clk);
      vif.crs_dv = 1'b1;
      vif.rxd = b[1:0];
      b = b >> 2;
    end
  endtask

  task run_phase(uvm_phase phase);
    vif.rxd = 2'd0;
    vif.crs_dv = 1'b0;
    forever begin
      seq_item_port.get_next_item(req);
      req.build();

      // drive frame bytes as RMII dibits
      foreach (req.wbytes[i]) begin
        drive_byte(req.wbytes[i]);
      end

      ap.write(req); // notify model before IFG so expected frame is queued first

      // IFG
      @(negedge vif.clk);
      vif.crs_dv = 1'b0;
      vif.rxd = 2'd0;
      repeat (req.ifg * 4 - 1) @(negedge vif.clk);

      seq_item_port.item_done();
    end
  endtask
endclass


/* RMII TX monitor (captures DUT TX output) */
class rmii_tx_monitor extends uvm_monitor;
  `uvm_component_utils(rmii_tx_monitor)
  virtual rmii_if vif;
  uvm_analysis_port #(rmii_tx_frame) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rmii_if)::get(this, "", "rmii_vif", vif))
      `uvm_fatal("NOVIF", "rmii_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    byte unsigned cur_byte;
    int cnt;
    rmii_tx_frame frm;
    bit in_pre, past_sfd;

    forever begin
      @(posedge vif.clk);
      if (vif.tx_en) begin
        cur_byte = {vif.txd, cur_byte[7:2]};
        cnt++;

        if (cnt == 4) begin
          cnt = 0;
          if (!in_pre && !past_sfd) begin
            // first byte, should be preamble
            if (cur_byte == 8'h55) in_pre = 1;
          end

          else if (in_pre) begin
            if (cur_byte == 8'hD5) begin
              in_pre = 0;
              past_sfd = 1;
              frm = new("tx_frm");
            end

            else if (cur_byte != 8'h55) begin
              // bad preamble, ignore
              in_pre = 0;
            end
          end

          else if (past_sfd) begin
            frm.bytes.push_back(cur_byte);
          end
        end
      end

      else begin
        if (past_sfd && frm != null) begin
          ap.write(frm);
        end

        cnt = 0;
        in_pre = 0;
        past_sfd = 0;
        frm = null;
      end
    end
  endtask
endclass


/* RMII agent */
class rmii_agent extends uvm_agent;
  `uvm_component_utils(rmii_agent)
  uvm_sequencer #(rx_frame) sqr;
  rmii_rx_driver drv;
  rmii_tx_monitor tx_mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    sqr = uvm_sequencer#(rx_frame)::type_id::create("sqr", this);
    drv = rmii_rx_driver::type_id::create("drv", this);
    tx_mon = rmii_tx_monitor::type_id::create("tx_mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass


/* AXI-Stream TX source driver */
class axis_tx_driver extends uvm_driver #(tx_frame);
  `uvm_component_utils(axis_tx_driver)
  virtual axis_if vif;
  uvm_analysis_port #(tx_frame) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual axis_if)::get(this, "", "axis_tx_vif", vif))
      `uvm_fatal("NOVIF", "axis_tx_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    byte unsigned bytes[$];
    vif.tvalid = 1'b0;
    vif.tdata = 8'd0;
    vif.tlast = 1'b0;
    vif.tuser = 1'b0;

    forever begin
      seq_item_port.get_next_item(req);
      req.build();
      req.get_axis_bytes(bytes);

      foreach (bytes[i]) begin
        @(negedge vif.clk);
        vif.tdata = bytes[i];
        vif.tvalid = 1'b1;
        vif.tlast = (i == bytes.size() - 1);
        do @(posedge vif.clk); while (!vif.tready);
      end

      @(negedge vif.clk);
      vif.tvalid = 1'b0;
      vif.tlast = 1'b0;
      ap.write(req);
      seq_item_port.item_done();
    end
  endtask
endclass


/* AXI-Stream TX source agent */
class axis_tx_agent extends uvm_agent;
  `uvm_component_utils(axis_tx_agent)
  uvm_sequencer #(tx_frame) sqr;
  axis_tx_driver drv;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    sqr = uvm_sequencer#(tx_frame)::type_id::create("sqr", this);
    drv = axis_tx_driver::type_id::create("drv", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass


/* AXI-Stream RX sink driver (backpressure) */
class axis_rx_driver extends uvm_component;
  `uvm_component_utils(axis_rx_driver)
  virtual axis_if vif;
  eth_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual axis_if)::get(this, "", "axis_rx_vif", vif))
      `uvm_fatal("NOVIF", "axis_rx_vif not set")
    if (!uvm_config_db#(eth_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "eth_cfg not set")
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned phase_left = 0;
    bit phase_ready = 1'b1;
    vif.tready = 1'b0;
    forever begin
      @(negedge vif.clk);
      case (cfg.bp_mode)
        BP_NONE: vif.tready = 1'b1;
        BP_RAND50: vif.tready = ($urandom_range(1, 0) == 1);
        BP_RAND10: vif.tready = ($urandom_range(9, 0) == 0);
        BP_BURSTY: begin
          if (phase_left == 0) begin
            phase_ready = ~phase_ready;
            phase_left = $urandom_range(40, 1);
          end
          phase_left--;
          vif.tready = phase_ready;
        end
      endcase
    end
  endtask
endclass


/* AXI-Stream RX monitor */
class axis_rx_monitor extends uvm_monitor;
  `uvm_component_utils(axis_rx_monitor)
  virtual axis_if vif;
  uvm_analysis_port #(axis_frame) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual axis_if)::get(this, "", "axis_rx_vif", vif))
      `uvm_fatal("NOVIF", "axis_rx_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    axis_frame cur;
    forever begin
      @(posedge vif.clk);
      if (vif.tvalid && vif.tready) begin
        if (cur == null) cur = new("axis_frame");
        cur.data.push_back(vif.tdata);
        if (vif.tlast) begin
          cur.user = vif.tuser;
          ap.write(cur);
          cur = null;
        end
      end
    end
  endtask
endclass


/* AXI-Stream RX agent */
class axis_rx_agent extends uvm_agent;
  `uvm_component_utils(axis_rx_agent)
  axis_rx_driver drv;
  axis_rx_monitor mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    drv = axis_rx_driver::type_id::create("drv", this);
    mon = axis_rx_monitor::type_id::create("mon", this);
  endfunction
endclass


/* register agent */
class reg_driver extends uvm_driver #(reg_item);
  `uvm_component_utils(reg_driver)
  virtual reg_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual reg_if)::get(this, "", "reg_vif", vif))
      `uvm_fatal("NOVIF", "reg_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    vif.wr = 1'b0;
    vif.rd = 1'b0;
    vif.addr = '0;
    vif.wdata = '0;
    forever begin
      seq_item_port.get_next_item(req);
      @(negedge vif.clk);
      vif.addr = req.addr;
      vif.wdata = req.wdata;
      vif.wr = req.write;
      vif.rd = !req.write;
      @(negedge vif.clk);
      vif.wr = 1'b0;
      vif.rd = 1'b0;
      if (!req.write) @(negedge vif.clk);
      seq_item_port.item_done();
    end
  endtask
endclass

class reg_monitor extends uvm_monitor;
  `uvm_component_utils(reg_monitor)
  virtual reg_if vif;
  uvm_analysis_port #(reg_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual reg_if)::get(this, "", "reg_vif", vif))
      `uvm_fatal("NOVIF", "reg_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    bit [4:0] rd_addr;
    reg_item t;
    forever begin
      @(posedge vif.clk);
      if (vif.rvalid) begin
        t = new("rd");
        t.write = 1'b0;
        t.addr = rd_addr;
        t.rdata = vif.rdata;
        ap.write(t);
      end

      if (vif.wr) begin
        t = new("wr");
        t.write = 1'b1;
        t.addr = vif.addr;
        t.wdata = vif.wdata;
        ap.write(t);
      end

      if (vif.rd) rd_addr = vif.addr;
    end
  endtask
endclass

class reg_agent extends uvm_agent;
  `uvm_component_utils(reg_agent)
  uvm_sequencer #(reg_item) sqr;
  reg_driver drv;
  reg_monitor mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    sqr = uvm_sequencer#(reg_item)::type_id::create("sqr", this);
    drv = reg_driver::type_id::create("drv", this);
    mon = reg_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
