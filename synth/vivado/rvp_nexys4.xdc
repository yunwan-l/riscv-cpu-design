## =============================================================================
## rvp_nexys4.xdc - RVP Processor Constraints for NEXYS4 / NEXYS4 DDR
## =============================================================================
## Target board: Digilent NEXYS4 DDR (Artix-7 XC7A100T)
## Reference: Digilent Nexys-4-DDR-Master.xdc
##
## Pin assignments:
##   - Clock:       100 MHz on pin E3
##   - Reset:       CPU reset button on pin C12 (CPU_RESETN, active-low)
##   - UART:        USB-UART TX=D4 (UART_RXD_OUT)
##   - GPIO LEDs:   16 user LEDs
##   - GPIO Switch: 16 slide switches
##   - 7-segment:   8-digit seven-segment display
##
## Adjust port names in [get_ports {...}] to match your top-level module.
## =============================================================================

## ---------------------------------------------------------------------------
## Clock signal - 100 MHz crystal oscillator on pin E3
## 板载晶振 100MHz，通过 3 位计数器 8 分频得到 12.5MHz 给 SoC
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { clk }];

## 分频时钟约束：clk_soc = clk / 8 = 12.5MHz (80ns period)
## clk_cnt[2] 寄存器的 Q 引脚输出即为 12.5MHz 时钟
create_generated_clock -name clk_soc -source [get_ports { clk }] -divide_by 8 [get_pins -hier -filter {NAME =~ *clk_cnt_reg[2]/Q}]

## 跨时钟域约束：SoC(12.5MHz) → 数码管(100MHz)，pc_dbg 是慢变信号，设 false path
set_false_path -from [get_clocks clk_soc] -to [get_clocks sys_clk_pin]
set_false_path -from [get_clocks sys_clk_pin] -to [get_clocks clk_soc]

## ---------------------------------------------------------------------------
## Reset - CPU reset button (active-low on the board)
## Pin C12 = CPU_RESETN on the Nexys4 DDR schematic
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { rst_n }];
#set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { cpu_resetn }];

## ---------------------------------------------------------------------------
## Buttons (optional - for user interaction / debug)
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { btn_center }];
#set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { btn_up     }];
#set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { btn_left   }];
#set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { btn_right  }];
#set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { btn_down   }];

## ---------------------------------------------------------------------------
## UART - USB-UART bridge (FTDI FT2232HQ)
## FPGA TX = D4 (UART_RXD_OUT on Nexys4 DDR schematic)
## FPGA RX = C4 (UART_TXD_IN) — 当前 SoC 无 RX 功能，暂不约束
## 参考: Digilent Nexys-4-DDR-Master.xdc
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

## ---------------------------------------------------------------------------
## GPIO LEDs - 16 discrete LEDs
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led[0]  }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led[1]  }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led[2]  }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led[3]  }];
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { led[4]  }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { led[5]  }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { led[6]  }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led[7]  }];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led[8]  }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { led[9]  }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { led[10] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { led[11] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { led[12] }];
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { led[13] }];
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { led[14] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { led[15] }];

## ---------------------------------------------------------------------------
## GPIO Switches - 16 slide switches
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { sw[0]   }];
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { sw[1]   }];
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { sw[2]   }];
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { sw[3]   }];
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { sw[4]   }];
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { sw[5]   }];
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { sw[6]   }];
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { sw[7]   }];
set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS18 } [get_ports { sw[8]   }];
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS18 } [get_ports { sw[9]   }];
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { sw[10]  }];
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { sw[11]  }];
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { sw[12]  }];
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { sw[13]  }];
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { sw[14]  }];
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { sw[15]  }];

## ---------------------------------------------------------------------------
## Seven-segment display - 8 digits
## Segment cathodes (active-low): CA-CG + DP
## Digit anodes (active-low): AN[0]-AN[7]
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { seg_ca }];
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { seg_cb }];
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { seg_cc }];
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { seg_cd }];
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { seg_ce }];
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { seg_cf }];
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { seg_cg }];
#set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { seg_dp }];

set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { an[0]  }];
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { an[1]  }];
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { an[2]  }];
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { an[3]  }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { an[4]  }];
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { an[5]  }];
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { an[6]  }];
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { an[7]  }];

## ---------------------------------------------------------------------------
## Configuration options
## ---------------------------------------------------------------------------
## Enable the configuration voltage select bit (required for Artix-7)
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO         [current_design]

## Bitstream configuration
set_property BITSTREAM.GENERAL.COMPRESS      TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE    50    [current_design]

## ---------------------------------------------------------------------------
## Timing constraints (optional - for external I/O)
## ---------------------------------------------------------------------------
## Set false path from async reset to all registers
set_false_path -from [get_ports { rst_n }] -to [all_registers]

## Slow down the I/O timing for buttons/switches (async inputs)
set_input_delay  -clock sys_clk_pin -max  5.0 [get_ports { sw[*] btn_center }]
set_input_delay  -clock sys_clk_pin -min  1.0 [get_ports { sw[*] btn_center }]

## LED 和 UART 输出延迟约束（保留，这些路径未违例）
set_output_delay -clock sys_clk_pin -max  5.0 [get_ports { led[*] uart_tx }]
set_output_delay -clock sys_clk_pin -min  1.0 [get_ports { led[*] uart_tx }]

## 数码管是慢速 LED 显示设备（刷新率 1kHz），不需要纳秒级时序约束
## 段码和位选信号每 1ms 才变化一次，人眼无法分辨纳秒级延迟
## 设为 false_path 避免 Vivado 对这些路径做时序分析
set_false_path -to [get_ports { seg_ca seg_cb seg_cc seg_cd seg_ce seg_cf seg_cg an[*] }]
