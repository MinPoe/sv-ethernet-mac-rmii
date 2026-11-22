// RX control
// Accepts byte stream from rmii_rx (line_valid/line_data),
// detects preamble/SFD, checks FCS, filters by address,
// drops runt/oversize, outputs good frames on AXI-Stream
// Based on the existing eth_rx from eth-uvm-tb

module rx_ctrl (
  input logic clk,
  input logic rst_n,

  // byte stream from rmii_rx
  input logic line_valid,
  input logic [7:0] line_data,
  input logic line_active, // high for entire frame

  // AXI-Stream output (user side)
  output logic [7:0] m_tdata,
  output logic m_tvalid,
  input logic m_tready,
  output logic m_tlast,
  output logic m_tuser, // 1 = bad FCS

  // config
  input logic enable,
  input logic promisc,
  input logic [47:0] mac_addr,

  // event pulses
  output logic ev_good,
  output logic ev_crc,
  output logic ev_runt,
  output logic ev_over,
  output logic ev_ovfl
);

  localparam int BUF_BYTES = 2048;
  localparam logic [31:0] CRC_RESIDUE = 32'hDEBB_20E3;
  localparam logic [31:0] CRC_INIT = 32'hFFFF_FFFF;
  localparam int MAX_FRAME = 1518;
  localparam int MIN_FRAME = 64;

  // CRC
  function automatic logic [31:0] crc_byte(
    input logic [31:0] c,
    input logic [7:0] b
  );
    logic [31:0] r;
    r = c ^ {24'b0, b};

    for (int i = 0; i < 8; i++) begin
      r = r[0] ? (r >> 1) ^ 32'hEDB8_8320 : (r >> 1);
    end

    return r;

  endfunction

  typedef enum logic [1:0] {S_IDLE, S_PRE, S_BODY, S_IGN} st_e;

  st_e st;
  logic line_active_d;
  logic [12:0] blen; // body bytes seen
  logic [31:0] crc;
  logic store_ok;
  logic [2:0] wr_ptr, rd_ptr;
  logic [3:0] cnt; // committed unread buffers

  logic [7:0] mem [0:7][0:BUF_BYTES-1];
  logic [10:0] plen [0:7];
  logic ubit [0:7];

  // address match
  logic [47:0] rx_da;
  logic da_match;
  assign da_match = promisc ||
                    (rx_da == mac_addr) ||
                    (rx_da == 48'hFFFF_FFFF_FFFF);

  logic eof;
  assign eof = line_active_d && !line_active;


  /* end-of-frame decision */
  logic runt_f, over_f, crc_bad, good_f, fwd_f;

  always_comb begin
    runt_f = (blen < MIN_FRAME[12:0]);
    over_f = !runt_f && (blen > MAX_FRAME[12:0]);
    crc_bad = !runt_f && !over_f && (crc != CRC_RESIDUE);
    good_f = !runt_f && !over_f && !crc_bad && da_match;
    fwd_f = good_f || (!runt_f && !over_f && crc_bad); // bad FCS forwarded with tuser=1
  end

  logic eof_body, commit_now;
  assign eof_body = eof && (st == S_BODY);
  assign commit_now = eof_body && fwd_f && store_ok;


  /* commit */
  logic commit;
  logic [10:0] commit_len;
  logic commit_user;

  assign commit = commit_now;
  assign commit_len = blen[10:0] - 11'd18; // strip DA(6)+SA(6)+type(2)+FCS(4)
  assign commit_user = (crc != CRC_RESIDUE);


  /* reader */
  logic out_busy;
  logic [10:0] idx;
  logic release_buf;

  assign m_tvalid = out_busy;
  assign m_tdata = mem[rd_ptr][idx];
  assign m_tuser = ubit[rd_ptr];
  assign m_tlast = out_busy && (idx == plen[rd_ptr] - 11'd1);

  logic advance;
  assign advance = out_busy && m_tready;

  logic last_beat;
  assign last_beat = advance && (idx == plen[rd_ptr] - 11'd1);
  assign release_buf = last_beat;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_busy <= 1'b0;
      idx <= 11'd0;
      rd_ptr <= 3'd0;
    end

    else if (!out_busy) begin
      if (cnt != 4'd0) begin
        out_busy <= 1'b1;
        idx <= 11'd0;
      end
    end

    else if (advance) begin
      if (last_beat) begin
        out_busy <= 1'b0;
        rd_ptr <= rd_ptr + 3'd1;
      end

      else
        idx <= idx + 11'd1;
    end

  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cnt <= 4'd0;
    else
      cnt <= cnt + {3'b0, commit} - {3'b0, release_buf};
  end


  /* writer / parser */
  logic [12:0] waddr_full;
  logic [10:0] waddr;
  assign waddr_full = blen - 13'd14;
  assign waddr = waddr_full[10:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= S_IDLE;
      line_active_d <= 1'b0;
      blen <= 13'd0;
      crc <= CRC_INIT;
      store_ok <= 1'b0;
      wr_ptr <= 3'd0;
      rx_da <= 48'd0;
    end

    else begin
      line_active_d <= line_active;
      if (commit) wr_ptr <= wr_ptr + 3'd1;
      if (eof) st <= S_IDLE;

      if (line_valid) begin
        case (st)
          S_IDLE: begin
            if (enable && line_data == 8'h55) begin
              st <= S_PRE;
              blen <= 13'd0;
              crc <= CRC_INIT;
              store_ok <= (cnt != 4'd8);
              rx_da <= 48'd0;
            end

            else
              st <= S_IGN;
          end

          S_PRE: begin
            if (line_data == 8'hD5)
              st <= S_BODY;
            else if (line_data != 8'h55)
              st <= S_IGN;
          end

          S_BODY: begin
            crc <= crc_byte(crc, line_data);
            if (blen != 13'h1FFF) blen <= blen + 13'd1;

            // capture DA (first 6 bytes)
            if (blen < 13'd6)
              rx_da <= {line_data, rx_da[47:8]};

            if (store_ok && blen >= 13'd14 && waddr_full < BUF_BYTES[12:0])
              mem[wr_ptr][waddr] <= line_data;
          end

          default: ;
        endcase
      end
    end

  end

  always_ff @(posedge clk) begin
    if (commit) begin
      plen[wr_ptr] <= commit_len;
      ubit[wr_ptr] <= commit_user;
    end

  end


  /* event pulses */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ev_good <= 1'b0;
      ev_crc <= 1'b0;
      ev_runt <= 1'b0;
      ev_over <= 1'b0;
      ev_ovfl <= 1'b0;
    end

    else begin
      ev_good <= eof_body && good_f;
      ev_crc <= eof_body && crc_bad;
      ev_runt <= eof_body && runt_f;
      ev_over <= eof_body && over_f;
      ev_ovfl <= eof_body && fwd_f && !store_ok;
    end

  end

endmodule
