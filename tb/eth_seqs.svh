/* RX sequences (drive RMII input) */
class rx_base_seq extends uvm_sequence #(rx_frame);
  `uvm_object_utils(rx_base_seq)
  int unsigned n = 50;
  int unsigned max_len = 1518;

  function new(string name = "rx_base_seq");
    super.new(name);
  endfunction

  virtual function bit gen(rx_frame f);
    return f.randomize();
  endfunction

  task body();
    repeat (n) begin
      req = rx_frame::type_id::create("req");
      req.max_len = max_len;
      start_item(req);
      if (!gen(req)) `uvm_fatal("RAND", "rx frame randomization failed")
      finish_item(req);
    end
  endtask
endclass

class rx_rand_seq extends rx_base_seq;
  `uvm_object_utils(rx_rand_seq)
  function new(string name = "rx_rand_seq"); super.new(name); endfunction
endclass

class rx_err_seq extends rx_base_seq;
  `uvm_object_utils(rx_err_seq)
  function new(string name = "rx_err_seq"); super.new(name); endfunction

  virtual function bit gen(rx_frame f);
    return f.randomize() with {
      err dist {ERR_NONE := 2, ERR_BAD_CRC := 3, ERR_RUNT := 3, ERR_OVERSIZE := 3, ERR_TRUNC := 1};
    };
  endfunction
endclass

class rx_corner_seq extends rx_base_seq;
  `uvm_object_utils(rx_corner_seq)
  function new(string name = "rx_corner_seq"); super.new(name); endfunction

  task send(err_e e, int unsigned plen, int unsigned rlen = 0);
    req = rx_frame::type_id::create("req");
    req.max_len = max_len;
    start_item(req);
    if (!req.randomize() with { err == e; payload_len == plen; runt_len == rlen; ifg inside {[12:24]}; })
      `uvm_fatal("RAND", "corner randomization failed")
    finish_item(req);
  endtask

  task body();
    send(ERR_NONE, 0);
    send(ERR_NONE, 1);
    send(ERR_NONE, 45);
    send(ERR_NONE, 46);
    send(ERR_NONE, 47);
    send(ERR_RUNT, 0, 0);
    send(ERR_RUNT, 10, 17);
    send(ERR_RUNT, 10, 63);
    send(ERR_NONE, 46); // exactly 64 bytes, must pass
    send(ERR_NONE, max_len - 18); // max legal
    send(ERR_OVERSIZE, max_len - 17);
    send(ERR_BAD_CRC, max_len - 18);
    send(ERR_TRUNC, 0);
    send(ERR_NONE, 100);
  endtask
endclass


/* TX sequences (drive AXI-Stream TX input) */
class tx_base_seq extends uvm_sequence #(tx_frame);
  `uvm_object_utils(tx_base_seq)
  int unsigned n = 20;

  function new(string name = "tx_base_seq");
    super.new(name);
  endfunction

  task body();
    repeat (n) begin
      req = tx_frame::type_id::create("req");
      start_item(req);
      if (!req.randomize()) `uvm_fatal("RAND", "tx frame randomization failed")
      finish_item(req);
    end
  endtask
endclass

class tx_corner_seq extends uvm_sequence #(tx_frame);
  `uvm_object_utils(tx_corner_seq)
  function new(string name = "tx_corner_seq"); super.new(name); endfunction

  task send(int unsigned plen);
    req = tx_frame::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { payload_len == plen; })
      `uvm_fatal("RAND", "tx corner randomization failed")
    finish_item(req);
  endtask

  task body();
    send(0);   // min frame, needs padding
    send(1);
    send(45);
    send(46);  // exactly 60 bytes, no padding needed
    send(47);
    send(100);
    send(1000);
    send(1500); // max payload
  endtask
endclass


/* register sequences */
class reg_cfg_seq extends uvm_sequence #(reg_item);
  `uvm_object_utils(reg_cfg_seq)
  bit tx_en = 1, rx_en = 1, promisc_en = 0;
  bit [47:0] mac = 48'h0200_0000_0001;

  function new(string name = "reg_cfg_seq");
    super.new(name);
  endfunction

  task wr(bit [4:0] a, bit [31:0] d);
    req = reg_item::type_id::create("req");
    start_item(req);
    req.write = 1;
    req.addr = a;
    req.wdata = d;
    finish_item(req);
  endtask

  task body();
    wr(A_MAC_L, mac[31:0]);
    wr(A_MAC_H, {16'd0, mac[47:32]});
    wr(A_CTRL, {29'd0, promisc_en, rx_en, tx_en});
  endtask
endclass

class reg_clear_seq extends uvm_sequence #(reg_item);
  `uvm_object_utils(reg_clear_seq)
  function new(string name = "reg_clear_seq"); super.new(name); endfunction

  task body();
    req = reg_item::type_id::create("req");
    start_item(req);
    req.write = 1;
    req.addr = A_CLR;
    req.wdata = 32'h1;
    finish_item(req);
  endtask
endclass

class reg_read_all_seq extends uvm_sequence #(reg_item);
  `uvm_object_utils(reg_read_all_seq)
  function new(string name = "reg_read_all_seq"); super.new(name); endfunction

  task body();
    for (int a = 0; a < 10; a++) begin
      req = reg_item::type_id::create("req");
      start_item(req);
      req.write = 0;
      req.addr = a[4:0];
      req.wdata = 0;
      finish_item(req);
    end
  endtask
endclass
