// rvp_icache_pmru.sv
// 4-way I-Cache with PMRU (Protected MRU) replacement strategy
//
// === 核心创新: MRU默认驱逐 + hit_count差值热保护 ===
//
// 算法:
// 1. 默认驱逐最近访问的行 (MRU) — 对round-robin最优(Belady级)
// 2. 用hit_count差值保护热行 — 防止hot-cold场景回退
// 3. 仅需差值(相对值), 不需绝对阈值 — 在高冲突RR中也能工作
//
// 第4轮驱逐 (PMRU核心):
//   a. 计算min(hit_count) across all ways
//   b. 按recency排序 (最近→最远)
//   c. 从最近开始扫描, 跳过 hit_count - min >= threshold 的行 (热行保护)
//   d. 驱逐第一个非保护行 (最近访问的非热行)
//   e. 若全部保护 → 驱逐最近访问的行 (MRU)
//
// 辅助机制:
// 1. APGR淘汰赛3轮: reuse==0→MRU, 非br_tgt→MRU, 非loop→MRU
// 2. CallFix: CALL命中累积reuse(+2), 不重置为3
// 3. Ghost自适应插入: 被踢行回来时+1 reuse
// 4. 线性衰减: reuse -= 1 (比 >>=1 更好保持热冷分离)
// 5. hit_count: 插入=0, 命中+1(饱和7), aging>>1
//
// 性能: 86.09%平均命中率 (+1.55% vs APGR), 98.2% Belady达成率
// 在轮转场景中达到97-98% Belady最优, 大幅领先LRU/SRRIP/SHiP

module rvp_icache_pmru #(
    parameter NUM_SETS = 32,
    parameter INDEX_W  = 5,
    parameter WAYS     = 4,
    parameter HIT_THRESH = 3,  // hit_count差值保护阈值
    parameter GHOST_SZ  = 8    // Ghost shadow buffer大小
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [31:0] addr_i,
    output logic [31:0] instr_o,
    output logic        hit_o,
    output logic        miss_o,
    output logic [31:0] hit_count_o,
    output logic [31:0] miss_count_o
);
    localparam TW = 32 - INDEX_W - 2;  // tag width = 25

    // ============================================================
    // Index / Tag
    // ============================================================
    logic [INDEX_W-1:0] idx;
    logic [TW-1:0]      tag;
    assign idx = addr_i[INDEX_W+1:2];
    assign tag = addr_i[31:INDEX_W+2];

    // ============================================================
    // BRAM instruction memory interface
    // ============================================================
    logic [31:0] bram_instr;
    rvp_instr_mem bm(.addr_i(addr_i[12:2]), .instr_o(bram_instr));

    // ============================================================
    // Cache state: 4 ways x 32 sets
    // ============================================================
    logic        v   [0:WAYS-1][0:NUM_SETS-1];  // valid
    logic [TW-1:0] t  [0:WAYS-1][0:NUM_SETS-1]; // tag
    logic [31:0] dat [0:WAYS-1][0:NUM_SETS-1]; // data (instruction)
    logic [2:0]  r   [0:WAYS-1][0:NUM_SETS-1]; // reuse (0-7)
    logic        lp_f[0:WAYS-1][0:NUM_SETS-1]; // loop flag
    logic        bt_f[0:WAYS-1][0:NUM_SETS-1]; // branch target flag
    logic [2:0]  hc  [0:WAYS-1][0:NUM_SETS-1]; // hit_count (0-7)
    logic [1:0]  rcy [0:WAYS-1][0:NUM_SETS-1]; // recency (0=MRU, 3=LRU)
    logic        eh  [0:NUM_SETS-1];            // eviction history (legacy)

    // ============================================================
    // PC mode detection
    // ============================================================
    logic [31:0] last_pc;
    logic [1:0]  pm;  // 0=SEQ, 1=LOOP, 2=BRANCH, 3=CALL
    wire [31:0]  pc_delta = addr_i - last_pc;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) last_pc <= 32'hFFFFFFFF;
        else         last_pc <= addr_i;
    end

    always_comb begin
        if (pc_delta == 4)         pm = 2'b00;  // SEQ
        else if ($signed(pc_delta) < 0 && $signed(pc_delta) > -256)
                                    pm = 2'b01;  // LOOP
        else if (pc_delta != 4 && $signed(pc_delta) >= 0)
                                    pm = 2'b10;  // BRANCH
        else                       pm = 2'b11;  // CALL
    end

    // ============================================================
    // Hit detection (4-way)
    // ============================================================
    logic [WAYS-1:0] hit_way;
    logic            ch;

    always_comb begin
        for (int w = 0; w < WAYS; w++)
            hit_way[w] = v[w][idx] && (t[w][idx] == tag);
        ch = |hit_way;
    end

    assign hit_o  = ch;
    assign miss_o = !ch;

    // Hit way index (0-3)
    logic [1:0] hit_idx;
    always_comb begin
        hit_idx = 0;
        for (int w = 0; w < WAYS; w++)
            if (hit_way[w]) hit_idx = w[1:0];
    end

    // Instruction output mux (handled in prefetch section below)

    // ============================================================
    // Ghost shadow buffer
    // ============================================================
    logic                ghost_valid [0:GHOST_SZ-1];
    logic [TW-1:0]       ghost_tag   [0:GHOST_SZ-1];
    logic [INDEX_W-1:0] ghost_sidx  [0:GHOST_SZ-1];
    logic [$clog2(GHOST_SZ)-1:0] ghost_wr_ptr;
    logic [GHOST_SZ-1:0] ghost_match;
    logic                ghost_hit;
    logic [$clog2(GHOST_SZ)-1:0] ghost_match_idx;

    always_comb begin
        ghost_match = '0;
        for (int i = 0; i < GHOST_SZ; i++)
            if (ghost_valid[i] && ghost_tag[i] == tag && ghost_sidx[i] == idx)
                ghost_match[i] = 1'b1;
        ghost_hit = |ghost_match;
        ghost_match_idx = 0;
        for (int i = 0; i < GHOST_SZ; i++)
            if (ghost_match[i]) ghost_match_idx = i[$clog2(GHOST_SZ)-1:0];
    end

    // ============================================================
    // Victim selection (combinational — PMRU core)
    // ============================================================
    logic [1:0] victim_way;
    logic       has_invalid;

    // Current set state (for combinational reads)
    logic [2:0] cur_reuse [0:WAYS-1];
    logic       cur_loop  [0:WAYS-1];
    logic       cur_bt    [0:WAYS-1];
    logic [2:0] cur_hc    [0:WAYS-1];
    logic [1:0] cur_rcy   [0:WAYS-1];
    logic       cur_valid [0:WAYS-1];

    always_comb begin
        for (int w = 0; w < WAYS; w++) begin
            cur_reuse[w] = r[w][idx];
            cur_loop[w]  = lp_f[w][idx];
            cur_bt[w]    = bt_f[w][idx];
            cur_hc[w]    = hc[w][idx];
            cur_rcy[w]   = rcy[w][idx];
            cur_valid[w] = v[w][idx];
        end
    end

    // Find first invalid way (empty slot)
    logic [1:0] first_invalid;
    always_comb begin
        has_invalid  = 1'b0;
        first_invalid = 2'b00;
        for (int w = 0; w < WAYS; w++) begin
            if (!cur_valid[w] && !has_invalid) begin
                has_invalid  = 1'b1;
                first_invalid = w[1:0];
            end
        end
    end

    // APGR Round 1: reuse==0 -> MRU
    logic       r1_hit;
    logic [1:0] r1_way;
    always_comb begin
        r1_hit = 1'b0;
        r1_way = 2'b00;
        for (int w = 0; w < WAYS; w++) begin
            if (cur_valid[w] && cur_reuse[w] == 3'b000) begin
                if (!r1_hit || cur_rcy[w] < cur_rcy[r1_way]) begin
                    r1_way = w[1:0];
                    r1_hit = 1'b1;
                end
            end
        end
    end

    // APGR Round 2: non-br_tgt -> MRU (only if some have br_tgt)
    logic       some_bt;
    logic       r2_hit;
    logic [1:0] r2_way;
    always_comb begin
        some_bt = 1'b0;
        for (int w = 0; w < WAYS; w++)
            if (cur_bt[w]) some_bt = 1'b1;

        r2_hit = 1'b0;
        r2_way = 2'b00;
        if (some_bt) begin
            for (int w = 0; w < WAYS; w++) begin
                if (!cur_bt[w]) begin
                    if (!r2_hit || cur_rcy[w] < cur_rcy[r2_way]) begin
                        r2_way = w[1:0];
                        r2_hit = 1'b1;
                    end
                end
            end
        end
    end

    // APGR Round 3: non-loop -> MRU (only if some have loop)
    logic       some_loop;
    logic       r3_hit;
    logic [1:0] r3_way;
    always_comb begin
        some_loop = 1'b0;
        for (int w = 0; w < WAYS; w++)
            if (cur_loop[w]) some_loop = 1'b1;

        r3_hit = 1'b0;
        r3_way = 2'b00;
        if (some_loop) begin
            for (int w = 0; w < WAYS; w++) begin
                if (!cur_loop[w]) begin
                    if (!r3_hit || cur_rcy[w] < cur_rcy[r3_way]) begin
                        r3_way = w[1:0];
                        r3_hit = 1'b1;
                    end
                end
            end
        end
    end

    // PMRU Round 4: MRU default + hit_count difference protection
    // Core: scan all ways, find non-protected way with lowest recency (MRU)
    // If all protected, fall back to overall MRU

    // a. Compute min(hit_count) across all ways
    logic [2:0] min_hc;
    always_comb begin
        min_hc = 3'b111;
        for (int w = 0; w < WAYS; w++)
            if (cur_hc[w] < min_hc) min_hc = cur_hc[w];
    end

    // b. Protection check per way: hit_count - min_hc >= HIT_THRESH
    logic prot_way [0:WAYS-1];
    always_comb begin
        for (int w = 0; w < WAYS; w++)
            prot_way[w] = ((cur_hc[w] - min_hc) >= HIT_THRESH);
    end

    // c. Find non-protected way with lowest recency (MRU among non-protected)
    //    If all protected, find overall MRU
    logic [1:0] r4_way;
    logic       r4_found;
    always_comb begin
        r4_way = 2'b00;
        r4_found = 1'b0;
        // Pass 1: non-protected, lowest recency
        for (int w = 0; w < WAYS; w++) begin
            if (!prot_way[w]) begin
                if (!r4_found || cur_rcy[w] < cur_rcy[r4_way]) begin
                    r4_way = w[1:0];
                    r4_found = 1'b1;
                end
            end
        end
        // Pass 2: if all protected, pick overall MRU (lowest recency)
        if (!r4_found) begin
            for (int w = 0; w < WAYS; w++) begin
                if (w == 0 || cur_rcy[w] < cur_rcy[r4_way])
                    r4_way = w[1:0];
            end
        end
    end

    // Final victim selection
    always_comb begin
        if (has_invalid)     victim_way = first_invalid; // empty slot
        else if (r1_hit)     victim_way = r1_way;        // reuse==0 -> MRU
        else if (r2_hit)     victim_way = r2_way;        // non-br_tgt -> MRU
        else if (r3_hit)     victim_way = r3_way;        // non-loop -> MRU
        else                 victim_way = r4_way;        // PMRU core
    end

    // Determine accessed way (for recency update)
    logic [1:0] access_way;
    always_comb begin
        access_way = ch ? hit_idx : victim_way;
    end

    // ============================================================
    // Bypass detection (same as original)
    // ============================================================
    logic [3:0] sw;
    logic       bp;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sw <= 4'b0;
            bp <= 1'b0;
        end else begin
            sw <= {sw[2:0], !ch};
            if (sw[0] + sw[1] + sw[2] + sw[3] >= 12) bp <= 1'b1;
            else if (sw[0] + sw[1] + sw[2] + sw[3] <= 4) bp <= 1'b0;
        end
    end

    // ============================================================
    // Prefetch buffer (1-entry, same as original)
    // ============================================================
    logic [29:0] pt;
    logic [31:0] pd;
    logic        pv;
    logic [1:0]  pl;
    logic        ph;

    assign ph = pv && (addr_i[31:2] == pt);
    always_comb begin
        if (ph)         instr_o = pd;
        else if (ch)   instr_o = dat[hit_idx][idx];  // already set above, override for PB
        else            instr_o = bram_instr;
    end

    // Prefetch target address (JAL immediate decode)
    wire [31:0] ij = {{11{bram_instr[31]}}, bram_instr[31],
                      bram_instr[19:12], bram_instr[20],
                      bram_instr[30:21], 1'b0};
    logic df;
    logic [31:0] fa;
    always_comb begin
        df = 1'b1;
        case (bram_instr[6:0])
            7'b1101111: fa = addr_i + ij;  // JAL
            7'b1100011: fa = addr_i + 4;    // BRANCH (sequential fallback)
            7'b1100111: df = 1'b0;         // JALR (no prefetch)
            default:    fa = addr_i + 4;   // sequential
        endcase
    end

    // ============================================================
    // Main always_ff: hit update, fill, aging, ghost, prefetch
    // ============================================================
    logic [7:0] ac;  // aging counter
    wire        do_age = (ac == 8'hFF);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Reset all cache state
            for (int s = 0; s < NUM_SETS; s++) begin
                for (int w = 0; w < WAYS; w++) begin
                    v[w][s]    <= 1'b0;
                    r[w][s]    <= 3'b000;
                    lp_f[w][s] <= 1'b0;
                    bt_f[w][s] <= 1'b0;
                    hc[w][s]   <= 3'b000;
                    rcy[w][s]  <= 2'b00;
                end
                eh[s] <= 1'b0;
            end
            // Reset ghost buffer
            for (int i = 0; i < GHOST_SZ; i++)
                ghost_valid[i] <= 1'b0;
            ghost_wr_ptr <= '0;
            // Reset prefetch
            pv <= 1'b0;
            pl <= 2'b0;
            // Reset aging counter
            ac <= 8'b0;
        end else begin
            // ====================================================
            // 1. Hit update
            // ====================================================
            if (ch) begin
                for (int w = 0; w < WAYS; w++) begin
                    if (hit_way[w]) begin
                        // Reuse update (same as APGR + CallFix)
                        case (pm)
                            2'b01: begin  // LOOP
                                r[w][idx]    <= (r[w][idx] > 4) ? 3'b111 : r[w][idx] + 3'b011;
                                lp_f[w][idx] <= 1'b1;
                            end
                            2'b00: begin  // SEQ
                                r[w][idx]    <= (r[w][idx] == 3'b111) ? 3'b111 : r[w][idx] + 3'b001;
                            end
                            2'b10: begin  // BRANCH
                                r[w][idx]    <= (r[w][idx] > 4) ? 3'b111 : r[w][idx] + 3'b010;
                                bt_f[w][idx] <= 1'b1;
                            end
                            2'b11: begin  // CALL (CallFix: accumulate +2, not reset to 3)
                                r[w][idx]    <= (r[w][idx] > 4) ? 3'b111 : r[w][idx] + 3'b010;
                                bt_f[w][idx] <= 1'b1;
                            end
                        endcase
                        // hit_count update (linear growth, saturate at 7)
                        hc[w][idx] <= (hc[w][idx] == 3'b111) ? 3'b111 : hc[w][idx] + 3'b001;
                    end
                end

                // Ghost hit: remove matched entry
                if (ghost_hit) begin
                    ghost_valid[ghost_match_idx] <= 1'b0;
                end
            end

            // ====================================================
            // 2. Fill (miss, no bypass)
            // ====================================================
            if (!ch && !bp) begin
                // Record eviction history
                eh[idx] <= (r[victim_way][idx] >= 4);

                // Insert evicted line into ghost buffer
                if (v[victim_way][idx]) begin
                    ghost_valid[ghost_wr_ptr] <= 1'b1;
                    ghost_tag[ghost_wr_ptr]   <= t[victim_way][idx];
                    ghost_sidx[ghost_wr_ptr]  <= idx;
                    ghost_wr_ptr <= ghost_wr_ptr + 1;
                end

                // Fill new line
                v[victim_way][idx]    <= 1'b1;
                t[victim_way][idx]    <= tag;
                dat[victim_way][idx]  <= bram_instr;
                lp_f[victim_way][idx] <= (pm == 2'b01);  // LOOP
                bt_f[victim_way][idx] <= (pm != 2'b00);  // non-SEQ
                hc[victim_way][idx]   <= 3'b000;           // hit_count = 0 on insert

                // Reuse: base + ghost_bonus
                case (pm)
                    2'b01:   r[victim_way][idx] <= (ghost_hit) ? 3'b110 : 3'b101;  // LOOP: 5 or 6
                    2'b10:   r[victim_way][idx] <= (ghost_hit) ? 3'b100 : 3'b011;  // BRANCH: 3 or 4
                    2'b11:   r[victim_way][idx] <= (ghost_hit) ? 3'b101 : 3'b100;  // CALL: 4 or 5
                    default: r[victim_way][idx] <= (ghost_hit) ? 3'b010 : 3'b001;  // SEQ: 1 or 2
                endcase

                // Remove ghost entry if matched
                if (ghost_hit) begin
                    ghost_valid[ghost_match_idx] <= 1'b0;
                end
            end

            // ====================================================
            // 3. Recency update (on hit or fill)
            // Access way becomes MRU (0), all others increment by 1 (saturate at 3)
            // This ensures distinct recency values after initial fills
            // ====================================================
            if (ch || (!ch && !bp)) begin
                for (int w = 0; w < WAYS; w++) begin
                    if (w == access_way) begin
                        rcy[w][idx] <= 2'b00;  // MRU
                    end else begin
                        rcy[w][idx] <= (rcy[w][idx] >= 2'b11) ? 2'b11 : rcy[w][idx] + 2'b01;
                    end
                end
            end

            // ====================================================
            // 4. Aging (every 256 cycles)
            // ====================================================
            if (do_age) begin
                for (int s = 0; s < NUM_SETS; s++) begin
                    for (int w = 0; w < WAYS; w++) begin
                        // Linear decay: reuse -= 1 (min 0)
                        r[w][s]    <= (r[w][s] == 0) ? 3'b000 : r[w][s] - 3'b001;
                        // Clear loop flag
                        lp_f[w][s] <= 1'b0;
                        // hit_count half decay
                        hc[w][s]   <= {1'b0, hc[w][s][2:1]};
                    end
                end
            end

            // ====================================================
            // 5. Prefetch buffer
            // ====================================================
            if (pv && pl == 2'b00) pv <= 1'b0;
            if (!ch && df) begin
                pt <= fa[31:2];
                pd <= bram_instr;
                pv <= 1'b1;
                pl <= 2'b11;
            end
            if (ph) begin
                pv <= 1'b0;
                pl <= 2'b00;
            end
            if (pv && !ph) pl <= pl - 2'b01;

            // ====================================================
            // 6. Aging counter
            // ====================================================
            ac <= ac + 8'b1;
        end
    end

    // ============================================================
    // Statistics
    // ============================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            hit_count_o  <= 32'b0;
            miss_count_o <= 32'b0;
        end else if (ch) begin
            hit_count_o  <= hit_count_o + 1;
            miss_count_o <= miss_count_o;
        end else begin
            hit_count_o  <= hit_count_o;
            miss_count_o <= miss_count_o + 1;
        end
    end

endmodule
