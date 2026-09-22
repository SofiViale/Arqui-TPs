
## Clock de 100 MHz
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# Reset
set_property PACKAGE_PIN U17 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]

# Uart Rx
set_property PACKAGE_PIN A18 [get_ports serial_rx]
set_property IOSTANDARD LVCMOS33 [get_ports serial_rx]

# Uart Tx
set_property PACKAGE_PIN B18 [get_ports serial_tx]
set_property IOSTANDARD LVCMOS33 [get_ports serial_tx]

# Frame error
set_property PACKAGE_PIN L1 [get_ports frame_error]
set_property IOSTANDARD LVCMOS33 [get_ports frame_error]

# Protocol error
set_property PACKAGE_PIN P1 [get_ports protocol_error]
set_property IOSTANDARD LVCMOS33 [get_ports protocol_error]