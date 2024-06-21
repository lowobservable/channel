# Information on the buses is arranged so that bit position 7 of a bus always
# carries the low-order bit within an eight-bit byte. The highest-order bit is
# in position 0 and intervening bits are in descending order from position 1
# to position 6.
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_N[7] }]; # Bus In 0
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT[7] }]; # Bus Out 0
set_property -dict { PACKAGE_PIN B19 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_N[6] }]; # Bus In 1
set_property -dict { PACKAGE_PIN F20 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT[6] }]; # Bus Out 1
set_property -dict { PACKAGE_PIN B20 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_N[5] }]; # Bus In 2
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT[5] }]; # Bus Out 2
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_N[4] }]; # Bus In 3
set_property -dict { PACKAGE_PIN F19 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT[4] }]; # Bus Out 3
set_property -dict { PACKAGE_PIN C20 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_N[3] }]; # Bus In 4
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT[3] }]; # Bus Out 4
set_property -dict { PACKAGE_PIN D20 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_N[2] }]; # Bus In 5
set_property -dict { PACKAGE_PIN G20 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT[2] }]; # Bus Out 5
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_N[1] }]; # Bus In 6
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT[1] }]; # Bus Out 6
set_property -dict { PACKAGE_PIN G19 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_N[0] }]; # Bus In 7
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT[0] }]; # Bus Out 7
set_property -dict { PACKAGE_PIN A20 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_IN_PARITY_N }]; # Bus In P
set_property -dict { PACKAGE_PIN H18 IOSTANDARD LVCMOS33 } [get_ports { A_BUS_OUT_PARITY }]; # Bus Out P
set_property -dict { PACKAGE_PIN H20 IOSTANDARD LVCMOS33 } [get_ports { A_MARK_0_IN_N }]; # Mark 0 In
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports { A_MARK_0_OUT }]; # Mark 0 Out

set_property -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports { A_OPERATIONAL_OUT }]; # Operational Out
set_property -dict { PACKAGE_PIN U20 IOSTANDARD LVCMOS33 } [get_ports { A_SERVICE_OUT }]; # Service Out
set_property -dict { PACKAGE_PIN V20 IOSTANDARD LVCMOS33 } [get_ports { A_HOLD_OUT }]; # Hold Out
set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports { A_SUPPRESS_OUT }]; # Suppress Out
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { A_DISCONNECT_IN_N }]; # Disconnect In
set_property -dict { PACKAGE_PIN P19 IOSTANDARD LVCMOS33 } [get_ports { A_COMMAND_OUT }]; # Command Out
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports { A_DATA_OUT }]; # Data Out
set_property -dict { PACKAGE_PIN N20 IOSTANDARD LVCMOS33 } [get_ports { A_ADDRESS_OUT }]; # Address Out
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { A_SELECT_OUT }]; # Select Out
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { A_DATA_IN_N }]; # Data In
set_property -dict { PACKAGE_PIN P20 IOSTANDARD LVCMOS33 } [get_ports { A_SELECT_IN_N }]; # Select In
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { A_REQUEST_IN_N }]; # Request In
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { A_SERVICE_IN_N }]; # Service In
set_property -dict { PACKAGE_PIN J20 IOSTANDARD LVCMOS33 } [get_ports { A_METERING_IN_N }]; # Metering In
set_property -dict { PACKAGE_PIN K19 IOSTANDARD LVCMOS33 } [get_ports { A_ADDRESS_IN_N }]; # Address In
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports { A_METERING_OUT }]; # Metering Out
set_property -dict { PACKAGE_PIN J19 IOSTANDARD LVCMOS33 } [get_ports { A_STATUS_IN_N }]; # Status In
set_property -dict { PACKAGE_PIN L20 IOSTANDARD LVCMOS33 } [get_ports { A_CLOCK_OUT }]; # Clock Out
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports { A_OPERATIONAL_IN_N }]; # Operational In

set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { DRIVER_ENABLE }]; # Driver Enable

set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports { GPIO_0 }]; # GPIO 0
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports { GPIO_1 }]; # GPIO 1
