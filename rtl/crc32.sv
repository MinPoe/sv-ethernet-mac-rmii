// CRC-32 (Ethernet FCS), byte-serial
// Reflected algorithm, poly 0xEDB88320
// Residue 0xDEBB_20E3 after good frame + FCS
// Caller applies final XOR

module crc32 (
  input logic clk,
  input logic rst_n,
  input logic init,
  input logic valid,
  input logic [7:0] data,
  output logic [31:0] crc
);

  localparam logic [31:0] CRC_INIT = 32'hFFFF_FFFF;

  /* byte-fold function */
  // reflected form: XOR byte into low 8 bits, shift right, poly 0xEDB88320
  function automatic logic [31:0] crc_byte(
    input logic [31:0] r,
    input logic [7:0] b
  );
    logic [31:0] tmp;
    tmp = r ^ {24'b0, b};

    for (int i = 0; i < 8; i++) begin
      tmp = tmp[0] ? (tmp >> 1) ^ 32'hEDB8_8320 : (tmp >> 1);
    end
    
    return tmp;

  endfunction


  /* register */
  logic [31:0] reg_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      reg_r <= CRC_INIT;
    else if (init)
      reg_r <= CRC_INIT;
    else if (valid)
      reg_r <= crc_byte(reg_r, data);

  end

  assign crc = reg_r;

endmodule
