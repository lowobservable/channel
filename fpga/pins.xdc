# MDIO
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W15} [get_ports MDIO_ETHERNET_0_0_mdc]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y14} [get_ports MDIO_ETHERNET_0_0_mdio_io]

# RMII clock
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U18} [get_ports FCLK_CLK3_0]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U15} [get_ports GMII_ETHERNET_0_0_tx_clk]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U14} [get_ports GMII_ETHERNET_0_0_rx_clk]

# RMII TX
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y19} [get_ports GMII_ETHERNET_0_0_txd[3]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V18} [get_ports GMII_ETHERNET_0_0_txd[2]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y18} [get_ports GMII_ETHERNET_0_0_txd[1]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W18} [get_ports GMII_ETHERNET_0_0_txd[0]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W19} [get_ports GMII_ETHERNET_0_0_tx_en[0]]

# RMII RX
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y17} [get_ports GMII_ETHERNET_0_0_rxd[3]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V17} [get_ports GMII_ETHERNET_0_0_rxd[2]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V16} [get_ports GMII_ETHERNET_0_0_rxd[1]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y16} [get_ports GMII_ETHERNET_0_0_rxd[0]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W16} [get_ports GMII_ETHERNET_0_0_rx_dv]

# RMII NC
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN R17} [get_ports GMII_ETHERNET_0_0_col]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN F16} [get_ports GMII_ETHERNET_0_0_crs]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN G17} [get_ports GMII_ETHERNET_0_0_rx_er]
set_property PULLDOWN TRUE [get_ports GMII_ETHERNET_0_0_rx_er]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN G18} [get_ports GMII_ETHERNET_0_0_tx_er[0]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN H15} [get_ports GMII_ETHERNET_0_0_txd[7]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN M14} [get_ports GMII_ETHERNET_0_0_txd[6]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN M15} [get_ports GMII_ETHERNET_0_0_txd[5]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN P14} [get_ports GMII_ETHERNET_0_0_txd[4]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN P15} [get_ports GMII_ETHERNET_0_0_rxd[7]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN P16} [get_ports GMII_ETHERNET_0_0_rxd[6]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN R16} [get_ports GMII_ETHERNET_0_0_rxd[5]]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN T10} [get_ports GMII_ETHERNET_0_0_rxd[4]]
