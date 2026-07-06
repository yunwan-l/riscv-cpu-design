// RVP (RISC-V Pipeline) RTL File List
//
// Lists all SystemVerilog source files in compilation order.
// Reference: ibex_core.f (lowRISC Ibex)
//
// Compilation order:
//   1. Packages            (rvp_pkg, rvp_cache_pkg)
//   2. Core modules        (leaf modules first, top last)
//   3. Cache modules       (sub-system, depends on core)
//   4. Memory modules      (rtl/mem/)
//   5. Peripheral modules  (rtl/periph/)
//   6. SoC top modules     (soc/)
//
// Paths are relative to the project root directory.
// Usage:
//   iverilog -f config/rvp_core.f ...
//   vivado:  read into project via create_project.tcl

// ============================================================================
// 1. Packages
// ============================================================================
rtl/rvp_pkg.sv
rtl/cache/rvp_cache_pkg.sv

// ============================================================================
// 2. Core Pipeline Modules
//    Order: leaf modules (no sub-instances) first, then composite stages,
//    then rvp_core top. This satisfies SystemVerilog elaboration order.
// ============================================================================

// --- ALU and data-path leaf cells ---
rtl/core/rvp_alu.sv
rtl/core/rvp_imm_generator.sv
rtl/core/rvp_register_file.sv

// --- Control and decode leaf cells ---
rtl/core/rvp_branch_unit.sv
rtl/core/rvp_decoder.sv
rtl/core/rvp_controller.sv

// --- Hazard handling leaf cells ---
rtl/core/rvp_hazard_unit.sv
rtl/core/rvp_forward_unit.sv

// --- Pipeline stages (instantiate above leaf cells) ---
rtl/core/rvp_if_stage.sv
rtl/core/rvp_id_stage.sv
rtl/core/rvp_ex_stage.sv
rtl/core/rvp_mem_stage.sv
rtl/core/rvp_wb_stage.sv

// --- Core top (instantiates all stages + hazard/forward units) ---
rtl/core/rvp_core.sv

// ============================================================================
// 3. Cache Subsystem Modules
//    Depends on rvp_cache_pkg. Order: arrays -> replacement -> stats ->
//    flush -> icache/dcache top.
// ============================================================================
rtl/cache/rvp_cache_tag_array.sv
rtl/cache/rvp_cache_data_array.sv
rtl/cache/rvp_cache_replacement.sv
rtl/cache/rvp_cache_stats.sv
rtl/cache/rvp_cache_flush.sv
rtl/cache/rvp_icache.sv
rtl/cache/rvp_dcache.sv

// ============================================================================
// 4. Memory Modules (rtl/mem/)
// ============================================================================
rtl/mem/rvp_ram_1p.sv
rtl/mem/rvp_ram_2p.sv
rtl/mem/rvp_instr_mem.sv
rtl/mem/rvp_data_mem.sv

// ============================================================================
// 5. Peripheral Modules (rtl/periph/)
// ============================================================================
rtl/periph/rvp_uart.sv
rtl/periph/rvp_gpio.sv
rtl/periph/rvp_timer.sv

// ============================================================================
// 6. SoC Top-Level Modules (soc/)
// ============================================================================
soc/rvp_bus_interconnect.sv
soc/rvp_soc_top.sv
