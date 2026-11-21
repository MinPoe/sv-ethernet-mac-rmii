typedef enum {ERR_NONE, ERR_BAD_CRC, ERR_RUNT, ERR_OVERSIZE, ERR_TRUNC} err_e;
typedef enum {OUT_GOOD, OUT_CRC, OUT_RUNT, OUT_OVER, OUT_IGNORED} outcome_e;
typedef enum {BP_NONE, BP_RAND50, BP_RAND10, BP_BURSTY} bp_e;

// register word addresses (byte_addr >> 2)
localparam bit [4:0] A_CTRL = 5'h00, A_MAC_L = 5'h01, A_MAC_H = 5'h02,
                     A_TX_FRAMES = 5'h04, A_RX_FRAMES = 5'h05,
                     A_RX_FCS = 5'h06, A_RX_DROP = 5'h07,
                     A_RX_OVF = 5'h08, A_CLR = 5'h09;

// CRC-32 reference (normal form, reflected output)
// credits : https://github.com/Michaelangel007/crc32
function automatic bit [31:0] ref_crc32(byte unsigned data[$]);
  bit [31:0] crc;
  bit [31:0] r;
  bit top;
  crc = 32'hFFFF_FFFF;

  foreach (data[k]) begin
    for (int i = 0; i < 8; i++) begin
      top = crc[31] ^ data[k][i];
      crc = crc << 1;

      if (top) begin
        crc = crc ^ 32'h04C1_1DB7;
      end
    end
  end

  for (int i = 0; i < 32; i++) begin
    r[i] = crc[31 - i];
  end

  return ~r;
endfunction

class eth_cfg extends uvm_object;
  `uvm_object_utils(eth_cfg)
  bp_e bp_mode = BP_NONE;

  function new(string name = "eth_cfg");
    super.new(name);
  endfunction
endclass


// frame for RX stimulus (driven into RMII RX pins)
class rx_frame extends uvm_sequence_item;
  `uvm_object_utils(rx_frame)
  rand bit [47:0] dst, src;
  rand bit [15:0] etype;
  rand int unsigned payload_len;
  rand int unsigned bucket;
  rand int unsigned rbucket;
  rand err_e err;
  rand int unsigned ifg;
  rand int unsigned pre_len;
  rand int unsigned runt_len;
  rand bit [31:0] fcs_flip;

  int unsigned max_len = 1518;

  byte unsigned payload[$];
  byte unsigned wbytes[$]; // bytes on the wire (preamble + SFD + body + FCS)

  constraint c_err { err dist {ERR_NONE := 60, ERR_BAD_CRC := 10, ERR_RUNT := 10, ERR_OVERSIZE := 10, ERR_TRUNC := 10}; }
  constraint c_bucket { bucket inside {[0:9]}; rbucket inside {[0:9]}; }
  constraint c_len {
    payload_len <= 2000;
    if (err == ERR_OVERSIZE) {
      payload_len >= max_len - 17;
      payload_len <= max_len + 400;
    } else {
      payload_len + 18 <= max_len;
      (bucket == 0) -> payload_len == 0;
      (bucket inside {1, 2, 3}) -> payload_len inside {[1:45]};
      (bucket == 4) -> payload_len == 46;
      (bucket inside {5, 6, 7}) -> payload_len inside {[47:1499]};
      (bucket inside {8, 9}) -> payload_len inside {[1000:1500]};
    }
  }
  constraint c_runt { (rbucket < 3) -> runt_len == 63;
                      (rbucket inside {3, 4}) -> runt_len inside {[0:17]};
                      (rbucket >= 5) -> runt_len inside {[18:62]}; }
  constraint c_pre { (bucket < 7) -> pre_len == 7; pre_len inside {[1:7]}; }
  constraint c_ifg { ifg inside {[12:24]}; } // at least IFG worth of idle
  constraint c_flip { fcs_flip != 0; }

  function new(string name = "rx_frame");
    super.new(name);
  endfunction

  function void build();
    byte unsigned body[$];
    byte unsigned padded[$];
    bit [31:0] fcs;
    byte unsigned all_body[$];

    payload.delete();

    for (int i = 0; i < payload_len; i++) begin
      payload.push_back($urandom_range(255, 0));
    end

    padded = payload;
    while (padded.size() < 46) begin
      padded.push_back(8'h00);
    end

    for (int i = 5; i >= 0; i--) begin
      body.push_back(dst[8*i +: 8]);
    end

    for (int i = 5; i >= 0; i--) begin
      body.push_back(src[8*i +: 8]);
    end

    body.push_back(etype[15:8]);
    body.push_back(etype[7:0]);

    foreach (padded[i]) begin
      body.push_back(padded[i]);
    end

    fcs = ref_crc32(body);
    if (err == ERR_BAD_CRC) fcs = fcs ^ fcs_flip;

    all_body = body;
    for (int i = 0; i < 4; i++) begin
      all_body.push_back(fcs[8*i +: 8]);
    end

    wbytes.delete();
    for (int i = 0; i < pre_len; i++) begin
      wbytes.push_back(8'h55);
    end

    if (err == ERR_TRUNC) begin
      wbytes.push_back(8'hAA); // garbage instead of SFD
    end

    else begin
      wbytes.push_back(8'hD5);
      if (err == ERR_RUNT) begin
        for (int i = 0; i < runt_len; i++) begin
          wbytes.push_back(all_body[i]);
        end
      end

      else begin
        foreach (all_body[i]) begin
          wbytes.push_back(all_body[i]);
        end
      end
    end
  endfunction

  function string convert2string();
    return $sformatf("err=%s plen=%0d runt=%0d ifg=%0d pre=%0d wire=%0d",
                     err.name(), payload_len, runt_len, ifg, pre_len, wbytes.size());
  endfunction
endclass


// frame for TX stimulus (driven into AXI-Stream TX input)
class tx_frame extends uvm_sequence_item;
  `uvm_object_utils(tx_frame)
  rand bit [47:0] dst, src;
  rand bit [15:0] etype;
  rand int unsigned payload_len;
  rand int unsigned bucket;

  byte unsigned payload[$];

  constraint c_bucket { bucket inside {[0:9]}; }
  constraint c_len {
    payload_len <= 1500;
    (bucket == 0) -> payload_len == 0;
    (bucket inside {1, 2, 3}) -> payload_len inside {[1:45]};
    (bucket == 4) -> payload_len == 46;
    (bucket inside {5, 6, 7}) -> payload_len inside {[47:999]};
    (bucket inside {8, 9}) -> payload_len inside {[1000:1500]};
  }

  function new(string name = "tx_frame");
    super.new(name);
  endfunction

  function void build();
    payload.delete();
    for (int i = 0; i < payload_len; i++) begin
      payload.push_back($urandom_range(255, 0));
    end
  endfunction

  // expected bytes on AXI-Stream (DA + SA + EtherType + payload, no FCS, no padding)
  function void get_axis_bytes(output byte unsigned bytes[$]);
    bytes.delete();
    for (int i = 5; i >= 0; i--) bytes.push_back(dst[8*i +: 8]);
    for (int i = 5; i >= 0; i--) bytes.push_back(src[8*i +: 8]);
    bytes.push_back(etype[15:8]);
    bytes.push_back(etype[7:0]);
    foreach (payload[i]) bytes.push_back(payload[i]);
  endfunction

  function string convert2string();
    return $sformatf("plen=%0d", payload_len);
  endfunction
endclass


// captured AXI-Stream output frame
class axis_frame extends uvm_object;
  `uvm_object_utils(axis_frame)
  byte unsigned data[$];
  bit user;

  function new(string name = "axis_frame");
    super.new(name);
  endfunction
endclass

// captured RMII TX frame (deserialized bytes)
class rmii_tx_frame extends uvm_object;
  `uvm_object_utils(rmii_tx_frame)
  byte unsigned bytes[$]; // everything after SFD: body + FCS

  function new(string name = "rmii_tx_frame");
    super.new(name);
  endfunction
endclass

// register bus item
class reg_item extends uvm_sequence_item;
  `uvm_object_utils(reg_item)
  rand bit write;
  rand bit [4:0] addr;
  rand bit [31:0] wdata;
  bit [31:0] rdata;

  function new(string name = "reg_item");
    super.new(name);
  endfunction
endclass
