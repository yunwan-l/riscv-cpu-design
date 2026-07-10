// RVP (RISC-V Pipeline) RTL File List
//
// Lists all SystemVerilog source files in compilation order.
// Updated for current SoC architecture (rvp_core_pipeline + rvp_soc).
//
// Compilation order:
//   1. Packages
//   2. Core leaf modules (ALU, decoder, register file, etc.)
//   3. Memory modules (instruction + data)
//   4. Core top (pipeline)
//   5. Peripheral modules
//   6. SoC top
//   7. FPGA top wrapper
//
// Paths are relative to the project root directory.
// Usage:
//   iverilog -f config/rvp_core.f ...
//   vivado:  read into project via create_project.tcl

// ============================================================================
// 1. Packages
// ============================================================================
rtl/rvp_pkg.sv

// ============================================================================
// 2. Core Pipeline Leaf Modules
//    Order: leaf modules (no sub-instances) first.
//    rvp_core_pipeline instantiates all of these directly.
// ============================================================================

// --- ALU and data-path leaf cells ---
rtl/core/rvp_alu.sv
rtl/core/rvp_imm_generator.sv
rtl/core/rvp_register_file.sv

// --- Control and decode leaf cells ---
rtl/core/rvp_branch_unit.sv
rtl/core/rvp_decoder.sv

// --- Hazard handling leaf cells ---
rtl/core/rvp_hazard_unit.sv
rtl/core/rvp_forward_unit.sv

// --- Multiply/Divide unit (M extension) ---
rtl/core/rvp_multdiv.sv

// --- Pipeline registers ---
rtl/core/rvp_pipeline_regs.sv

// ============================================================================
// 3. Memory Modules
//    rvp_instr_mem: backing store for I-Cache (BRAM with $readmemh init)
//    rvp_data_mem:  data RAM (async read, sync write, sub-word support)
// ============================================================================
rtl/core/rvp_instr_mem.sv
rtl/core/rvp_data_mem.sv

// ============================================================================
// 3b. I-Cache (Direct-mapped instruction cache)
//     rvp_core_pipeline instantiates rvp_icache, which wraps rvp_instr_mem
// ============================================================================
rtl/cache/rvp_icache.sv

// ============================================================================
// 4. Core Top (5-stage pipeline CPU, with I-Cache)
// ============================================================================
rtl/core/rvp_core_pipeline.sv

// ============================================================================
// 5. Peripheral Modules
// ============================================================================
rtl/periph/rvp_uart.sv
rtl/periph/rvp_gpio.sv
rtl/periph/rvp_timer.sv

// ============================================================================
// 6. SoC Top-Level
// ============================================================================
rtl/rvp_soc.sv

// ============================================================================
// 7. FPGA Top Wrapper (Nexys4 DDR)
//    Only needed for FPGA synthesis, not for simulation.
//    Testbenches use rvp_soc as top directly.
// ============================================================================
rtl/rvp_fpga_top.sv
