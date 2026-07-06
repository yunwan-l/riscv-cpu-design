/**
 * RVP (RISC-V Pipeline) Configuration Header
 *
 * Global compile-time configuration for the RVP processor.
 * Override defaults via +define+<PARAM_NAME>=<value> on the command line.
 *
 * Reference: ibex_configs.yaml (lowRISC Ibex)
 */

`ifndef RVP_CONFIG_SVH
`define RVP_CONFIG_SVH

// ============================================================================
// ISA Configuration
// ============================================================================

// Base instruction set: RV32I (full) or RV32E (embedded, 16 registers)
`ifndef RVP_RV32E
  `define RVP_RV32E  0        // 0 = RV32I (32 registers), 1 = RV32E (16)
`endif

// M extension: Integer multiplication & division
`ifndef RVP_RV32M
  `define RVP_RV32M  1        // 1 = enable MUL/DIV/REM instructions
`endif

// C extension: Compressed instructions (16-bit)
`ifndef RVP_RV32C
  `define RVP_RV32C  0        // 0 = disable for Phase 1, enable in Phase 2
`endif

// ============================================================================
// Pipeline Configuration
// ============================================================================

// Pipeline depth: 5-stage (IF → ID → EX → MEM → WB)
`ifndef RVP_PIPELINE_STAGES
  `define RVP_PIPELINE_STAGES 5
`endif

// Writeback stage: 0 = 4-stage (WB combined with MEM), 1 = 5-stage
`ifndef RVP_WRITEBACK_STAGE
  `define RVP_WRITEBACK_STAGE 1
`endif

// Branch target ALU: 0 = use main ALU, 1 = dedicated branch target adder
`ifndef RVP_BRANCH_TARGET_ALU
  `define RVP_BRANCH_TARGET_ALU 0
`endif

// ============================================================================
// Hazard Handling
// ============================================================================

// Forwarding unit: 0 = stall-only (Phase 1), 1 = enable forwarding (Phase 3)
`ifndef RVP_FORWARDING
  `define RVP_FORWARDING 0
`endif

// Branch prediction: 0 = none (flush on branch), 1 = predict-not-taken
// 2 = 2-bit saturating counter, 3 = BTB-based
`ifndef RVP_BRANCH_PREDICT
  `define RVP_BRANCH_PREDICT 0
`endif

// ============================================================================
// Cache Configuration (Extension - Phase 3)
// ============================================================================

// I-Cache enable: 0 = direct fetch from BRAM, 1 = use instruction cache
`ifndef RVP_ICACHE_ENABLE
  `define RVP_ICACHE_ENABLE 0
`endif

// D-Cache enable: 0 = direct data access, 1 = use data cache
`ifndef RVP_DCACHE_ENABLE
  `define RVP_DCACHE_ENABLE 0
`endif

// I-Cache parameters
`ifndef RVP_ICACHE_SIZE_BYTES
  `define RVP_ICACHE_SIZE_BYTES 4096     // 4KB total
`endif

`ifndef RVP_ICACHE_NUM_WAYS
  `define RVP_ICACHE_NUM_WAYS 2           // 2-way set-associative
`endif

`ifndef RVP_ICACHE_LINE_SIZE
  `define RVP_ICACHE_LINE_SIZE 64        // 64 bits = 8 bytes per line
`endif

// D-Cache parameters (same defaults)
`ifndef RVP_DCACHE_SIZE_BYTES
  `define RVP_DCACHE_SIZE_BYTES 4096
`endif

`ifndef RVP_DCACHE_NUM_WAYS
  `define RVP_DCACHE_NUM_WAYS 2
`endif

`ifndef RVP_DCACHE_LINE_SIZE
  `define RVP_DCACHE_LINE_SIZE 64
`endif

// Cache replacement policy:
// 0 = Round-Robin (ibex default, simplest)
// 1 = LRU (True LRU, good hit rate, more logic)
// 2 = Pseudo-LRU (Tree-PLRU, good trade-off)
// 3 = FIFO (Simplest after round-robin)
// 4 = Random (LFSR-based, zero overhead but non-deterministic)
`ifndef RVP_ICACHE_REPLACE_POLICY
  `define RVP_ICACHE_REPLACE_POLICY 0    // Default: Round-Robin (baseline)
`endif

`ifndef RVP_DCACHE_REPLACE_POLICY
  `define RVP_DCACHE_REPLACE_POLICY 0
`endif

// Cache statistics collection (for hit-rate analysis)
`ifndef RVP_CACHE_STATS_ENABLE
  `define RVP_CACHE_STATS_ENABLE 1       // 1 = count hits/misses/evictions
`endif

// ============================================================================
// Memory Configuration
// ============================================================================

`ifndef RVP_INSTR_MEM_SIZE
  `define RVP_INSTR_MEM_SIZE 32768       // 32KB instruction BRAM
`endif

`ifndef RVP_DATA_MEM_SIZE
  `define RVP_DATA_MEM_SIZE 32768        // 32KB data BRAM
`endif

`ifndef RVP_DATA_WIDTH
  `define RVP_DATA_WIDTH 32
`endif

`ifndef RVP_ADDR_WIDTH
  `define RVP_ADDR_WIDTH 32
`endif

// ============================================================================
// SoC Peripheral Configuration
// ============================================================================

`ifndef RVP_UART_ENABLE
  `define RVP_UART_ENABLE 1
`endif

`ifndef RVP_UART_BAUD
  `define RVP_UART_BAUD 115200
`endif

`ifndef RVP_GPIO_ENABLE
  `define RVP_GPIO_ENABLE 1
`endif

`ifndef RVP_GPIO_WIDTH
  `define RVP_GPIO_WIDTH 16
`endif

// ============================================================================
// Debug / Verification
// ============================================================================

`ifndef RVP_DEBUG
  `define RVP_DEBUG 0                   // 1 = enable debug trace output
`endif

`ifndef RVP_RVFI
  `define RVP_RVFI 0                    // 1 = enable RISC-V Formal Interface
`endif

`endif // RVP_CONFIG_SVH
