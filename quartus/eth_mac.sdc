# 50 MHz RMII reference clock
create_clock -name clk -period 20.000 [get_ports clk]

# input/output delays for RMII (conservative estimates)
set_input_delay -clock clk -max 10.0 [get_ports {rxd[*] crs_dv}]
set_input_delay -clock clk -min 0.0 [get_ports {rxd[*] crs_dv}]
set_output_delay -clock clk -max 10.0 [get_ports {txd[*] tx_en}]
set_output_delay -clock clk -min 0.0 [get_ports {txd[*] tx_en}]
