/**
 * rvp_cache_replacement.sv - Cache Replacement Policy Module (EXTENSION CORE)
 *
 * =================================================================================
 * THIS IS THE CENTRAL EXTENSION FILE OF THE PROJECT.
 * =================================================================================
 * It implements a parameterized, policy-selectable replacement algorithm for
 * set-associative caches. The active policy is chosen at compile time via
 * the POLICY parameter (type replacement_policy_e from rvp_cache_pkg).
 *
 * Supported policies:
 *   REPL_RR         Round-Robin (ibex default, lines 525-531 of ibex_icache.sv)
 *   REPL_LRU        True LRU with per-way usage counters
 *   REPL_PLRU_TREE  Tree-based pseudo-LRU (PULP platform style)
 *   REPL_FIFO       First-In-First-Out with insertion timestamps
 *   REPL_RANDOM     LFSR-based pseudo-random selection
 *   REPL_SRRIP      (RESERVED) Starvation-aware RRIP - advanced
 *   REPL_DRRIP      (RESERVED) Dynamic RRIP with set-level sampling (DIP)
 *
 * Interface contract:
 *   - On every lookup, the controller presents the lookup result (hit/miss +
 *     way hit). On a miss that requires allocation, the controller reads
 *     replace_way_o to pick the victim way.
 *   - On a hit or fill, the controller pulses update_i so this module can
 *     refresh its internal state (LRU counters, FIFO pointers, RRIP tags).
 *
 * All policies share the same external interface so the cache controller
 * is policy-agnostic - this is what enables the comparative hit-rate study.
 *
 * Reference:
 *   - ibex_icache.sv lines 515-534 (round-robin way selection)
 *   - PULP platform plru_tree.sv (tree-PLRU bit layout)
 *   - Jaleel et al., "High Performance Cache Replacement Using Re-Reference
 *     Interval Prediction (RRIP)" ISCA 2010 (SRRIP / DRRIP)
 */

module rvp_cache_replacement
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  // Number of ways (associativity). Must be a power of two for tree-PLRU.
  parameter int unsigned             NUM_WAYS = 2,
  // Active replacement policy (compile-time selectable).
  parameter replacement_policy_e    POLICY   = REPL_RR
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  // --------------------------------------------------------------------------
  // Lookup interface (asserted on the cycle the cache performs tag compare)
  // --------------------------------------------------------------------------
  // High when a lookup is being performed this cycle.
  input  logic                    lookup_valid_i,
  // 1 = hit, 0 = miss (valid for the cycle lookup_valid_i is high)
  input  logic                    lookup_hit_i,
  // One-hot way that hit (valid only when lookup_hit_i=1)
  input  logic [NUM_WAYS-1:0]    lookup_way_i,

  // --------------------------------------------------------------------------
  // Victim selection (combinational - valid whenever a miss is being handled)
  // --------------------------------------------------------------------------
  // One-hot way to evict on the next allocation.
  output logic [NUM_WAYS-1:0]    replace_way_o,

  // --------------------------------------------------------------------------
  // State update interface (pulse on hit or fill completion)
  // --------------------------------------------------------------------------
  // Pulse to update the policy state for the addressed set / way.
  // update_way_i selects which way to mark as recently-used.
  input  logic                    update_i,
  input  logic [NUM_WAYS-1:0]    update_way_i,

  // (Optional) index of the set being updated. For per-set LRU/FIFO/RRIP,
  // this selects which state bank to update. Unused for global RR/Random.
  // TODO: wire per-set state arrays when per-set policy is enabled.
  input  logic [31:0]            set_index_i
);

  // ==========================================================================
  // Local helpers
  // ==========================================================================

  // Width needed to count accesses up to NUM_WAYS
  localparam int unsigned WAY_W = $clog2(NUM_WAYS);

  // One-hot constant for way 0 (used in RR reset)
  logic [NUM_WAYS-1:0] way_oh_first;
  assign way_oh_first = {{(NUM_WAYS-1){1'b0}}, 1'b1};

  // ==========================================================================
  // Default output (safe tie-off)
  // ==========================================================================
  logic [NUM_WAYS-1:0] replace_way_internal;
  assign replace_way_o = replace_way_internal;

  // ==========================================================================
  // POLICY: REPL_RR - Round-Robin
  // ==========================================================================
  // Implementation matches ibex_icache.sv (lines 525-531). A one-hot rotating
  // pointer advances on every allocation. The next victim is the pointer's
  // current position.
  //
  // NOTE: ibex also prefers an invalid way over the RR pointer when any way
  // is still invalid. That selection logic lives in the cache controller
  // (it has visibility of the valid bits); this module only exposes the
  // pure RR pointer so the policy comparison is apples-to-apples.

  if (POLICY == REPL_RR) begin : gen_rr

    logic [NUM_WAYS-1:0] rr_ptr_q, rr_ptr_d;

    // Next pointer = rotate current pointer left by one
    assign rr_ptr_d = {rr_ptr_q[NUM_WAYS-2:0], rr_ptr_q[NUM_WAYS-1]};

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rr_ptr_q <= way_oh_first;
      end else if (update_i) begin
        // Advance pointer on every fill / allocation
        rr_ptr_q <= rr_ptr_d;
      end
    end

    // Victim = current pointer position
    assign replace_way_internal = rr_ptr_q;

    // synthesis translate_off
    // TODO: add formal property: rr_ptr_q is always one-hot
    // synthesis translate_on

  end

  // ==========================================================================
  // POLICY: REPL_LRU - True LRU (per-way usage timestamp)
  // ==========================================================================
  // Each way carries a counter that records the time of its last use. The
  // way with the smallest counter (least recently used) is evicted. The
  // counter is bumped on every hit / fill.
  //
  // Cost: NUM_WAYS * log2(NUM_ACCESSES_BEFORE_WRAP) bits per set.
  //       For 4 ways and 8-bit counters -> 32 bits/set.
  // TODO: add per-set storage when set_index_i is wired (currently global).
  //       A global LRU approximates per-set LRU and is acceptable as a
  //       baseline; per-set is needed for accurate hit-rate comparison.

  else if (POLICY == REPL_LRU) begin : gen_lru

    // Counter width - large enough that the oldest is uniquely identifiable
    // within the LRU window. 8 bits is plenty for <=16 ways.
    localparam int unsigned LRU_W = 8;
    logic [LRU_W-1:0] lru_age_q [NUM_WAYS];

    // A global tick that increments on every update - used as "newest" stamp
    logic [LRU_W-1:0] tick_q, tick_d;
    assign tick_d = tick_q + 1'b1;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        tick_q <= '0;
        for (int w = 0; w < NUM_WAYS; w++) lru_age_q[w] <= '0;
      end else if (update_i) begin
        tick_q <= tick_d;
        for (int w = 0; w < NUM_WAYS; w++) begin
          if (update_way_i[w]) lru_age_q[w] <= tick_q;
          else                 lru_age_q[w] <= lru_age_q[w];
        end
      end
    end

    // Combinational victim selection: find the way with minimum age.
    // Implemented as a priority tree for clarity; a real implementation
    // would use a wider comparator tree.
    always_comb begin
      logic [LRU_W-1:0] min_age;
      logic [NUM_WAYS-1:0] victim;
      min_age = lru_age_q[0];
      victim  = way_oh_first;
      for (int w = 1; w < NUM_WAYS; w++) begin
        if (lru_age_q[w] < min_age) begin
          min_age = lru_age_q[w];
          victim  = '0;
          victim[w] = 1'b1;
        end
      end
      replace_way_internal = victim;
    end

    // TODO: when per-set LRU is added, instantiate NUM_LINES copies of this
    //       block indexed by set_index_i, OR use a memory array of width
    //       NUM_WAYS*LRU_W.

  end

  // ==========================================================================
  // POLICY: REPL_PLRU_TREE - Tree-based pseudo-LRU
  // ==========================================================================
  // Uses a binary tree of "direction" bits (one per internal node). On access
  // the bits along the path to the accessed leaf are flipped. The victim is
  // found by walking from the root following the bit directions.
  //
  // Cost: NUM_WAYS-1 bits per set. This is the most storage-efficient
  //       LRU approximation in common use.
  //
  // Reference: PULP platform plru_tree.sv; Wikipedia "Pseudo-LRU".
  //
  // Limitation: requires NUM_WAYS to be a power of two.

  else if (POLICY == REPL_PLRU_TREE) begin : gen_plru

    // Number of tree bits = NUM_WAYS - 1
    localparam int unsigned TREE_BITS = NUM_WAYS - 1;
    localparam int unsigned TREE_DEPTH = $clog2(NUM_WAYS);
    logic [TREE_BITS-1:0] plru_q;
    // plru_d will be needed once the path-flip TODO is implemented.
    // logic [TREE_BITS-1:0] plru_d;

    // Walk the tree to find the victim. The bit at each node points to the
    // subtree that was NOT recently used (i.e. the candidate for eviction).
    //
    // Node numbering (0-indexed, root=0): for node i, left child=2i+1, right=2i+2.
    // Leaf nodes (indices NUM_WAYS-1 .. 2*NUM_WAYS-2) correspond to ways
    // 0..NUM_WAYS-1 in left-to-right order.
    //
    // Function returns a one-hot way mask for the victim.
    function automatic logic [NUM_WAYS-1:0] plru_victim_way(
      input logic [TREE_BITS-1:0] tree
    );
      logic [31:0] node;       // current node index (0-indexed)
      logic [31:0] next_node;
      logic [NUM_WAYS-1:0] way;
      way  = '0;
      node = 0;
      // Descend TREE_DEPTH levels to a leaf
      for (int lvl = 0; lvl < TREE_DEPTH; lvl++) begin
        // If bit==0 go left, if bit==1 go right
        if (tree[node] == 1'b0) begin
          next_node = 2*node + 1;   // left child
        end else begin
          next_node = 2*node + 2;   // right child
        end
        node = next_node;
      end
      // node is now a leaf index. Leaf i corresponds to way (i - (NUM_WAYS-1)).
      // TODO: the leaf->way mapping below assumes a specific layout; verify
      //       against the chosen bit ordering and add an assertion.
      way[node - (NUM_WAYS - 1)] = 1'b1;
      return way;
    endfunction

    // Compute the victim way combinationally
    always_comb begin
      replace_way_internal = plru_victim_way(plru_q);
    end

    // On update, flip the bits along the path from root to the accessed leaf.
    // TODO: implement path-flip. For each update_way_i[w], walk the tree
    //       from root to leaf w and set plru_d[node] to point AWAY from the
    //       accessed leaf (so the accessed leaf becomes "recently used").
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        plru_q <= '0;
      end else if (update_i) begin
        // Placeholder: hold current value. Replace with proper path-flip.
        // A correct implementation needs the index of the way being updated
        // (derived from update_way_i as a binary index) and then walks the
        // tree from the root, setting plru_q[node] at each level to direct
        // AWAY from the accessed leaf.
        plru_q <= plru_q;
      end
    end

    // TODO: implement the path-flip function correctly. Suggested structure:
    //   function automatic logic [TREE_BITS-1:0] plru_update(
    //     input logic [TREE_BITS-1:0] tree,
    //     input logic [NUM_WAYS-1:0]  way_onehot
    //   );
    //     logic [31:0] node; node = 0;
    //     logic [WAY_W-1:0] way_idx;
    //     // one-hot to binary
    //     way_idx = ...;
    //     for (int lvl = TREE_DEPTH-1; lvl >= 0; lvl--) begin
    //       // bit direction toward the target leaf at this level
    //       logic dir;
    //       dir = way_idx[lvl];
    //       tree[node] = ~dir;  // point AWAY from recently-used leaf
    //       node = dir ? 2*node+2 : 2*node+1;
    //     end
    //     return tree;
    //   endfunction

  end

  // ==========================================================================
  // POLICY: REPL_FIFO - First-In-First-Out (insertion timestamp)
  // ==========================================================================
  // Each way stores an insertion order. The oldest-inserted way is evicted.
  // Unlike LRU, a hit does NOT refresh the timestamp - only insertions do.
  // This makes FIFO cheaper than LRU but worse hit rate on recency-skewed
  // workloads.

  else if (POLICY == REPL_FIFO) begin : gen_fifo

    localparam int unsigned TS_W = 8;
    logic [TS_W-1:0] insert_ts_q [NUM_WAYS];
    logic [TS_W-1:0] tick_q, tick_d;
    assign tick_d = tick_q + 1'b1;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        tick_q <= '0;
        for (int w = 0; w < NUM_WAYS; w++) insert_ts_q[w] <= '0;
      end else if (update_i) begin
        tick_q <= tick_d;
        for (int w = 0; w < NUM_WAYS; w++) begin
          // Only update timestamp on FILL (miss path), not on hit.
          // Distinguish via lookup_hit_i: when lookup_hit_i=0 it's a fill.
          if (update_way_i[w] && !lookup_hit_i) begin
            insert_ts_q[w] <= tick_q;
          end
        end
      end
    end

    // Victim = oldest timestamp
    always_comb begin
      logic [TS_W-1:0] min_ts;
      logic [NUM_WAYS-1:0] victim;
      min_ts = insert_ts_q[0];
      victim = way_oh_first;
      for (int w = 1; w < NUM_WAYS; w++) begin
        if (insert_ts_q[w] < min_ts) begin
          min_ts = insert_ts_q[w];
          victim = '0;
          victim[w] = 1'b1;
        end
      end
      replace_way_internal = victim;
    end

    // TODO: add per-set insertion timestamp storage.

  end

  // ==========================================================================
  // POLICY: REPL_RANDOM - LFSR-based pseudo-random
  // ==========================================================================
  // Uses a maximal-length LFSR to generate a pseudo-random way index.
  // Zero storage overhead per set, non-deterministic hit rate.
  //
  // Reference: ibex uses a similar approach for its random way allocation.

  else if (POLICY == REPL_RANDOM) begin : gen_random

    // 16-bit LFSR (Galois form). Pick a maximal polynomial for 16 bits:
    //   x^16 + x^14 + x^13 + x^11 + 1
    localparam int unsigned LFSR_W = 16;
    logic [LFSR_W-1:0] lfsr_q, lfsr_d;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        lfsr_q <= 16'hFFFF;   // non-zero seed (all-zero is a fixed point)
      end else begin
        lfsr_q <= lfsr_d;
      end
    end

    // Galois LFSR update
    always_comb begin
      logic feedback;
      feedback = lfsr_q[0];
      lfsr_d = lfsr_q >> 1;
      if (feedback) begin
        lfsr_d[LFSR_W-1] ^= 1'b1;
        lfsr_d[LFSR_W-3] ^= 1'b1;
        lfsr_d[LFSR_W-4] ^= 1'b1;
        lfsr_d[LFSR_W-6] ^= 1'b1;
      end
    end

    // Decode the low WAY_W bits of the LFSR to a one-hot way
    always_comb begin
      logic [WAY_W-1:0] idx;
      idx = lfsr_q[WAY_W-1:0];
      replace_way_internal = '0;
      replace_way_internal[idx] = 1'b1;
    end

    // TODO: provide a parameter to seed the LFSR from a true entropy source
    //       for security-sensitive use cases.

  end

  // ==========================================================================
  // POLICY: REPL_SRRIP - Static Re-Reference Interval Prediction (RESERVED)
  // ==========================================================================
  // RRIP assigns each line a Re-Reference Prediction Value (RRPV) indicating
  // how far in the future it is expected to be re-used. SRRIP initializes
  // all new lines to a fixed RRPV (typically 2 in a 3-level scheme: near,
  // intermediate, far). Eviction picks the line with the highest RRPV
  // ("farthest re-reference"). On a hit the RRPV is reset to 0.
  //
  // Reference: Jaleel et al. ISCA 2010.
  //
  // TODO: implement. Sketch:
  //   - per-way RRPV register of width RRPV_W (2 bits -> 4 levels)
  //   - on fill:    rrpv[way] <= INITIAL_RRPV (parameter, default 2)
  //   - on hit:     rrpv[way] <= 0
  //   - victim:     first way with rrpv == MAX; if none, increment all by 1
  //                 until at least one reaches MAX (this is the "RRIP aging"
  //                 mechanism that distinguishes RRIP from LFU).
  //
  // TODO: parameter RRPV_W and INITIAL_RRPV.

  else if (POLICY == REPL_SRRIP) begin : gen_srrip

    localparam int unsigned RRPV_W = 2;
    localparam logic [RRPV_W-1:0] RRPV_MAX = {RRPV_W{1'b1}};
    localparam logic [RRPV_W-1:0] RRPV_INIT = 2'd2;

    logic [RRPV_W-1:0] rrpv_q [NUM_WAYS];

    // TODO: full SRRIP implementation. Placeholder: behave like RR so the
    //       module remains synthesizable while the policy is being developed.
    logic [NUM_WAYS-1:0] rr_ptr_q, rr_ptr_d;
    assign rr_ptr_d = {rr_ptr_q[NUM_WAYS-2:0], rr_ptr_q[NUM_WAYS-1]};
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rr_ptr_q <= way_oh_first;
        for (int w = 0; w < NUM_WAYS; w++) rrpv_q[w] <= RRPV_INIT;
      end else if (update_i) begin
        rr_ptr_q <= rr_ptr_d;
        // TODO: implement proper RRPV update on hit / fill
        for (int w = 0; w < NUM_WAYS; w++) begin
          if (update_way_i[w]) rrpv_q[w] <= '0;   // reset on access (hit)
        end
      end
    end
    assign replace_way_internal = rr_ptr_q;

    // TODO: replace placeholder with proper SRRIP victim selection:
    //   1) find first way with rrpv_q[w] == RRPV_MAX
    //   2) if none, increment all rrpv_q by 1 (aging) and retry (iterate)
    //      In hardware this is unrolled as a combinational loop-breaker:
    //      compute the maximum rrpv, victim = first way with max rrpv.

  end

  // ==========================================================================
  // POLICY: REPL_DRRIP - Dynamic RRIP (RESERVED)
  // ==========================================================================
  // DRRIP augments SRRIP with the DIP (Dynamic Insertion Policy) mechanism:
  // a fraction of sets use SRRIP with INIT=2 (bimodal insertion) while the
  // remaining sets use a different INIT. A global "policy selector" tracks
  // miss counts and dynamically picks the better init policy, like a 2-bit
  // saturating counter.
  //
  // Reference: Jaleel et al. ISCA 2010, Section 5.
  //
  // TODO: implement on top of gen_srrip. Requires:
  //   - per-set INIT bank (1 bit per set to choose INIT value)
  //   - global PSEL counter (2-bit saturating)
  //   - dedicated "leader" sets that are pinned to each policy for sampling
  //
  // This is the most advanced policy in the project; reserved for later.

  else if (POLICY == REPL_DRRIP) begin : gen_drrip

    // TODO: full DRRIP. Placeholder: reuse RR.
    logic [NUM_WAYS-1:0] rr_ptr_q, rr_ptr_d;
    assign rr_ptr_d = {rr_ptr_q[NUM_WAYS-2:0], rr_ptr_q[NUM_WAYS-1]};
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni)                       rr_ptr_q <= way_oh_first;
      else if (update_i)                 rr_ptr_q <= rr_ptr_d;
    end
    assign replace_way_internal = rr_ptr_q;

    // TODO: DRRIP full implementation (see gen_srrip TODO + DIP sampling).

  end

  // ==========================================================================
  // Fallback (unknown policy)
  // ==========================================================================
  else begin : gen_unknown
    // Should never happen with a valid POLICY parameter. Tie off to way 0
    // so linting/synthesis does not fail.
    assign replace_way_internal = way_oh_first;
    // TODO: elaborate a compile-time error via $error in an initial block
    //       when an unsupported POLICY is selected.
  end

  // ==========================================================================
  // Coverage / debug hooks
  // ==========================================================================
  // TODO: add cover properties to verify each policy is exercised:
  //   - replace_way_internal is always one-hot
  //   - update_way_i is always one-hot when update_i=1
  // TODO: add a debug counter of how many times each way was evicted, for
  //       statistical comparison between policies. The cache_stats module
  //       already counts aggregate evictions; per-way counts would let us
  //       see whether the policy balances utilization across ways.

`ifndef SYNTHESIS
  // synthesis translate_off
  // Invariant: victim is always one-hot
  always @(posedge clk_i) begin
    if ($countones(replace_way_o) != 1) begin
      $error("rvp_cache_replacement: replace_way_o not one-hot: %b", replace_way_o);
    end
  end
  // synthesis translate_on
`endif

endmodule
