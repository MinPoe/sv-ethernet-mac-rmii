// RMII TX serializer
// Takes byte-stream (valid/data/last) and shifts out 2 bits per REF_CLK
// TX_EN held high for the duration of the frame

module rmii_tx (
  input logic clk,
  input logic rst_n,

  // byte interface from tx_ctrl
  input logic [7:0] tx_data,
  input logic tx_valid,
  input logic tx_last,
  output logic tx_ready,

  // RMII pins
  output logic [1:0] txd,
  output logic tx_en
);

  logic [7:0] sr;
  logic [1:0] cnt; // dibit counter 0..3
  logic sending;
  logic last_r;


  /* fsm */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sr      <= 8'd0;
      cnt     <= 2'd0;
      sending <= 1'b0;
      last_r  <= 1'b0;
      txd     <= 2'd0;
      tx_en   <= 1'b0;
    end

    else if (!sending) begin
      if (tx_valid) begin
        txd     <= tx_data[1:0];
        sr      <= {2'b0, tx_data[7:2]};
        cnt     <= 2'd1;
        sending <= 1'b1;
        last_r  <= tx_last;
        tx_en   <= 1'b1;
      end

      else begin
        txd   <= 2'd0;
        tx_en <= 1'b0;
      end
    end

    else begin
      txd <= sr[1:0];
      sr  <= {2'b0, sr[7:2]};
      cnt <= cnt + 2'd1;

      if (cnt == 2'd3) begin
        if (last_r) begin
          sending <= 1'b0;
        end

        else if (tx_valid) begin
          sr     <= tx_data;
          cnt    <= 2'd0;
          last_r <= tx_last;
        end

        else begin
          // underrun, shouldn't happen
          sending <= 1'b0;
        end
      end
    end

  end

  // accept next byte at last dibit of current byte, or when idle
  assign tx_ready = !sending || (cnt == 2'd3 && !last_r);

endmodule
