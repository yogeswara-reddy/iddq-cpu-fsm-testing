## Clock - 125 MHz
set_property PACKAGE_PIN L16 [get_ports clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
create_clock -period 8.000 -name sys_clk [get_ports clk_i]

## Reset - BTN0
set_property PACKAGE_PIN R18 [get_ports rst_i]
set_property IOSTANDARD LVCMOS33 [get_ports rst_i]

## SW0 - load_pending
set_property PACKAGE_PIN G15 [get_ports load_pending_i]
set_property IOSTANDARD LVCMOS33 [get_ports load_pending_i]

## SW1 - iddq_measure
set_property PACKAGE_PIN P15 [get_ports iddq_measure_i]
set_property IOSTANDARD LVCMOS33 [get_ports iddq_measure_i]

## LED0 - fetch0
set_property PACKAGE_PIN M14 [get_ports fetch0_o]
set_property IOSTANDARD LVCMOS33 [get_ports fetch0_o]

## LED1 - fetch1
set_property PACKAGE_PIN M15 [get_ports fetch1_o]
set_property IOSTANDARD LVCMOS33 [get_ports fetch1_o]

## LED2 - exec
set_property PACKAGE_PIN G14 [get_ports exec_o]
set_property IOSTANDARD LVCMOS33 [get_ports exec_o]

## LED3 - execld
set_property PACKAGE_PIN D18 [get_ports execld_o]
set_property IOSTANDARD LVCMOS33 [get_ports execld_o]

## PMOD JA[0] - state bit 0
set_property PACKAGE_PIN N15 [get_ports {state_obs_o[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {state_obs_o[0]}]

## PMOD JA[1] - state bit 1
set_property PACKAGE_PIN L14 [get_ports {state_obs_o[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {state_obs_o[1]}]

## False path on static IDDQ control
set_false_path -from [get_ports iddq_measure_i]