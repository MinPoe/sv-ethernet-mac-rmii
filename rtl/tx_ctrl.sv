// TX control
// Accepts frames on AXI-Stream (no FCS), prepends preamble/SFD,
// pads to 64 bytes, appends CRC-32 FCS, enforces IFG
// Feeds byte stream to rmii_tx

module tx_ctrl (
  input logic clk,
  input logic rst_n,
  input logic enable,

  // AXI-Stream input (user side)
  input logic [7:0] s_tdata,
  input logic s_tvalid,
  output logic s_tready,
  input logic s_tlast,

  // byte stream to rmii_tx
  output logic [7:0] tx_data,
  output logic tx_valid,
  output logic tx_last,
  input logic tx_ready,

  // event pulse
  output logic ev_tx_done
);

  localparam logic [31:0] CRC_XOR = 32'hFFFF_FFFF;
  localparam int PRE_LEN = 7; // preamble bytes (0x55)
  localparam int MIN_BODY = 60; // min frame before FCS (DA+SA+type+payload)
  localparam int IFG_CLKS = 51; // 96 bit times on pins (48 clocks + 3 for rmii_tx pipeline)

  typedef enum logic [2:0] {
    S_IDLE, S_PRE, S_SFD, S_BODY, S_PAD, S_FCS, S_IFG
  } st_e;

  st_e st;
  logic [5:0] cnt; // general counter (preamble, IFG)
  logic [10:0] blen; // body bytes sent
  logic [1:0] fcs_idx; // FCS byte index 0..3

  // CRC instance
  logic crc_init, crc_valid;
  logic [7:0] crc_data;
  logic [31:0] crc_reg;

  crc32 u_crc (
    .clk, .rst_n,
    .init(crc_init),
    .valid(crc_valid),
    .data(crc_data),
    .crc(crc_reg)
  );

  // FCS bytes (reflected register XORed)
  logic [31:0] fcs;
  assign fcs = crc_reg ^ CRC_XOR;


  /* fsm */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st      <= S_IDLE;
      cnt     <= 6'd0;
      blen    <= 11'd0;
      fcs_idx <= 2'd0;
    end

    else begin
      case (st)
        S_IDLE: begin
          if (enable && s_tvalid) begin
            st  <= S_PRE;
            cnt <= 6'd0;
          end
        end

        S_PRE: begin
          if (tx_ready) begin
            if (cnt == PRE_LEN[5:0] - 6'd1)
              st <= S_SFD;
            else
              cnt <= cnt + 6'd1;
          end
        end

        S_SFD: begin
          if (tx_ready)
            st <= S_BODY;
        end

        S_BODY: begin
          if (tx_ready && s_tvalid) begin
            blen <= blen + 11'd1;
            if (s_tlast) begin
              // frame ended, check if padding needed
              if (blen + 11'd1 < MIN_BODY[10:0])
                st <= S_PAD;
              else begin
                st      <= S_FCS;
                fcs_idx <= 2'd0;
              end
            end
          end
        end

        S_PAD: begin
          if (tx_ready) begin
            blen <= blen + 11'd1;
            if (blen + 11'd1 == MIN_BODY[10:0]) begin
              st      <= S_FCS;
              fcs_idx <= 2'd0;
            end
          end
        end

        S_FCS: begin
          if (tx_ready) begin
            if (fcs_idx == 2'd3) begin
              st  <= S_IFG;
              cnt <= 6'd0;
            end

            else
              fcs_idx <= fcs_idx + 2'd1;
          end
        end

        S_IFG: begin
          cnt <= cnt + 6'd1;
          if (cnt == IFG_CLKS[5:0] - 6'd1) begin
            st   <= S_IDLE;
            blen <= 11'd0;
          end
        end

        default: st <= S_IDLE;
      endcase
    end

  end


  /* output mux */
  always_comb begin
    tx_data   = 8'd0;
    tx_valid  = 1'b0;
    tx_last   = 1'b0;
    s_tready  = 1'b0;
    crc_init  = 1'b0;
    crc_valid = 1'b0;
    crc_data  = 8'd0;
    ev_tx_done = 1'b0;

    case (st)
      S_IDLE: begin
        crc_init = enable && s_tvalid; // prep CRC for new frame
      end

      S_PRE: begin
        tx_data  = 8'h55;
        tx_valid = 1'b1;
      end

      S_SFD: begin
        tx_data  = 8'hD5;
        tx_valid = 1'b1;
      end

      S_BODY: begin
        tx_data   = s_tdata;
        tx_valid  = s_tvalid;
        s_tready  = tx_ready;
        crc_valid = tx_ready && s_tvalid;
        crc_data  = s_tdata;
      end

      S_PAD: begin
        tx_data   = 8'h00;
        tx_valid  = 1'b1;
        crc_valid = tx_ready;
        crc_data  = 8'h00;
      end

      S_FCS: begin
        tx_valid = 1'b1;
        tx_last  = (fcs_idx == 2'd3);
        case (fcs_idx)
          2'd0: tx_data = fcs[7:0];
          2'd1: tx_data = fcs[15:8];
          2'd2: tx_data = fcs[23:16];
          2'd3: tx_data = fcs[31:24];
        endcase
      end

      S_IFG: begin
        ev_tx_done = (cnt == 6'd0); // pulse once at start of IFG
      end

      default: ;
    endcase
  end

endmodule
