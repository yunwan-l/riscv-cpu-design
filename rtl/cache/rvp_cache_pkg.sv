/**
 * rvp_cache_pkg.sv - Cache Subsystem Package
 *
 * All type definitions, parameters, and enums for the I-Cache and D-Cache.
 * Separated from rvp_pkg.sv so the cache subsystem can be developed
 * independently (the extension focuses on cache replacement strategies).
 *
 * Reference: ibex_pkg.sv lines 381-401 (ICache parameters)
 */

package rvp_cache_pkg;

  import rvp_pkg::*;

  // ==========================================================================
  // I-Cache Parameters (derived from config macros)
  // ==========================================================================

  // Total cache size in bytes
  parameter int unsigned IC_SIZE_BYTES  = `RVP_ICACHE_SIZE_BYTES;   // 4096
  // Associativity (number of ways)
  parameter int unsigned IC_NUM_WAYS     = `RVP_ICACHE_NUM_WAYS;      // 2
  // Line size in bits
  parameter int unsigned IC_LINE_SIZE     = `RVP_ICACHE_LINE_SIZE;     // 64
  // Line size in bytes
  parameter int unsigned IC_LINE_BYTES    = IC_LINE_SIZE / 8;          // 8
  // Line offset bits
  parameter int unsigned IC_LINE_W        = $clog2(IC_LINE_BYTES);    // 3
  // Number of lines per way
  parameter int unsigned IC_NUM_LINES     = IC_SIZE_BYTES / IC_NUM_WAYS / IC_LINE_BYTES; // 256
  // Index width (bits for set addressing)
  parameter int unsigned IC_INDEX_W       = $clog2(IC_NUM_LINES);     // 8
  // Index high bit position in address
  parameter int unsigned IC_INDEX_HI      = IC_INDEX_W + IC_LINE_W - 1; // 10
  // Tag width (including 1-bit valid flag)
  parameter int unsigned IC_TAG_SIZE       = ADDR_W - IC_INDEX_W - IC_LINE_W + 1; // 22

  // ==========================================================================
  // D-Cache Parameters
  // ==========================================================================

  parameter int unsigned DC_SIZE_BYTES  = `RVP_DCACHE_SIZE_BYTES;
  parameter int unsigned DC_NUM_WAYS     = `RVP_DCACHE_NUM_WAYS;
  parameter int unsigned DC_LINE_SIZE     = `RVP_DCACHE_LINE_SIZE;
  parameter int unsigned DC_LINE_BYTES    = DC_LINE_SIZE / 8;
  parameter int unsigned DC_LINE_W        = $clog2(DC_LINE_BYTES);
  parameter int unsigned DC_NUM_LINES     = DC_SIZE_BYTES / DC_NUM_WAYS / DC_LINE_BYTES;
  parameter int unsigned DC_INDEX_W       = $clog2(DC_NUM_LINES);
  parameter int unsigned DC_INDEX_HI      = DC_INDEX_W + DC_LINE_W - 1;
  parameter int unsigned DC_TAG_SIZE       = ADDR_W - DC_INDEX_W - DC_LINE_W + 1;

  // ==========================================================================
  // Replacement Policy Enum
  // ==========================================================================

  typedef enum logic [2:0] {
    REPL_RR        = 3'd0,  // Round-Robin (ibex default, simplest)
    REPL_LRU       = 3'd1,  // True LRU (exact, most logic)
    REPL_PLRU_TREE = 3'd2,  // Pseudo-LRU tree (good trade-off)
    REPL_FIFO      = 3'd3,  // First-In-First-Out (simple)
    REPL_RANDOM    = 3'd4,  // LFSR-based random (zero overhead)
    REPL_SRRIP     = 3'd5,   // SRRIP (Starvation-based RRIP, advanced)
    REPL_DRRIP     = 3'd6    // DRRIP (Re-reference Interval Prediction, dynamic)
  } replacement_policy_e;

  // Active replacement policy (from config)
  parameter replacement_policy_e IC_REPLACE_POLICY = replacement_policy_e'(`RVP_ICACHE_REPLACE_POLICY);
  parameter replacement_policy_e DC_REPLACE_POLICY = replacement_policy_e'(`RVP_DCACHE_REPLACE_POLICY);

  // ==========================================================================
  // Cache Request Type (for bus interface)
  // ==========================================================================

  typedef enum logic [1:0] {
    CACHE_REQ_FETCH  = 2'd0,  // Normal instruction fetch
    CACHE_REQ_FILL   = 2'd1,  // Cache line fill (after miss)
    CACHE_REQ_FLUSH  = 2'd2,  // Cache flush request
    CACHE_REQ_INVAL  = 2'd3   // Cache invalidation
  } cache_req_type_e;

  // ==========================================================================
  // Cache State Machine (for miss handling)
  // ==========================================================================

  typedef enum logic [2:0] {
    CACHE_IDLE       = 3'd0,  // Idle, waiting for request
    CACHE_LOOKUP     = 3'd1,  // Tag comparison in progress
    CACHE_MISS       = 3'd2,  // Miss detected, requesting bus
    CACHE_REFILL     = 3'd3,  // Refilling from next-level memory
    CACHE_WB         = 3'd4,  // Writeback (D-Cache dirty line only)
    CACHE_FLUSHING   = 3'd5,  // Flushing all entries
    CACHE_ERROR      = 3'd6   // Error state
  } cache_state_e;

  // ==========================================================================
  // Cache Statistics Structure (for hit-rate analysis)
  // ==========================================================================

  typedef struct packed {
    logic [31:0] total_accesses;   // Total cache lookups
    logic [31:0] cache_hits;        // Number of hits
    logic [31:0] cache_misses;      // Number of misses
    logic [31:0] evictions;         // Lines evicted
    logic [31:0] dirty_evictions;   // Dirty lines written back (D-Cache only)
    logic [31:0] read_accesses;    // Read requests
    logic [31:0] write_accesses;   // Write requests (D-Cache only)
  } cache_stats_t;

  // ==========================================================================
  // Tag Entry Format
  // ==========================================================================

  // Tag entry: [valid] [tag bits from address]
  typedef struct packed {
    logic                  valid;    // Valid bit (1 = entry contains valid data)
    logic [ADDR_W-IC_INDEX_W-IC_LINE_W-1:0] tag;  // Address tag bits
  } cache_tag_t;

  // D-Cache tag entry (adds dirty bit)
  typedef struct packed {
    logic                  valid;
    logic                  dirty;   // Modified, needs writeback on eviction
    logic [ADDR_W-DC_INDEX_W-DC_LINE_W-1:0] tag;
  } dcache_tag_t;

  // ==========================================================================
  // Utility Functions
  // ==========================================================================

  // Calculate hit rate as percentage (for stats reporting)
  function automatic logic [15:0] calc_hit_rate(
    input logic [31:0] hits,
    input logic [31:0] accesses
  );
    if (accesses == 0) return 16'd0;
    return (hits * 100) / accesses;
  endfunction

  // Check if address falls within a cache line range
  function automatic logic addr_in_line(
    input logic [ADDR_W-1:0] addr,
    input logic [ADDR_W-1:0] line_addr
  );
    return (addr >> IC_LINE_W) == (line_addr >> IC_LINE_W);
  endfunction

endpackage
