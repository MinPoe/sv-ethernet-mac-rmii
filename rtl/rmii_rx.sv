// RMII RX deserializer
// Samples RXD[1:0] when CRS_DV is high, assembles bytes
// Outputs byte-serial stream (line_valid/line_data) to rx_ctrl

module rmii_rx (
  input logic clk,
  input logic rst_n,

  // RMII pins
  input logic [1:0] rxd,
  input logic crs_dv,

  // byte stream to rx_ctrl
  output logic [7:0] line_data,
  output logic line_valid,
  output logic line_active // high for entire frame
);

  logic [7:0] sr;
  logic [1:0] cnt; // dibit counter 0..3

  assign line_active = active;
  logic active;


  /* fsm */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sr         <= 8'd0;
      cnt        <= 2'd0;
      active     <= 1'b0;
      line_data  <= 8'd0;
      line_valid <= 1'b0;
    end

    else if (crs_dv) begin
      active <= 1'b1;
      sr <= {rxd, sr[7:2]}; // shift in from MSB, LSB first
      cnt <= cnt + 2'd1;

      if (cnt == 2'd3) begin
        line_data  <= {rxd, sr[7:2]};
        line_valid <= 1'b1;
      end

      else begin
        line_valid <= 1'b0;
      end
    end

    else begin
      // CRS_DV dropped
      if (active) begin
        line_valid <= 1'b0;
        active     <= 1'b0;
      end

      else begin
        line_valid <= 1'b0;
      end

      cnt <= 2'd0;
    end

  end

endmodule
