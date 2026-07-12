// =============================================================================
// rvp_icache_apgr.sv — APGR I-Cache: 2路组相联 + 淘汰赛替换 + 预取缓冲
// =============================================================================
// 结构: 32组×2路 = 64行 (与原始直接映射64行容量一致)
// 替换: 4轮淘汰赛 (fresh→br_tgt→loop→reuse)
// 预取: 单条目PB + 分支感知预测 (JAL精确/Branch双路/其他顺序)
// 旁路: 滑动窗口密度检测流式扫描, 不进缓存
// 老化: 每256周期全局衰减
// 遗产: 每路1bit记录上次被踢行是否热行
// =============================================================================

module rvp_icache_apgr #(
    parameter int NUM_SETS  = 32,
    parameter int INDEX_W   = 5,             // $clog2(32)
    parameter int TAG_W     = 25             // 32 - 5 - 2
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [31:0] addr_i,             // CPU取指PC (字节地址)
    output logic [31:0] instr_o,            // 返回指令
    output logic [31:0] hit_count_o,        // 缓存命中计数
    output logic [31:0] miss_count_o,       // 缓存缺失计数
    output logic [31:0] pb_hit_count_o,     // 预取缓冲命中计数
    output logic [31:0] conflict_count_o    // 冲突缺失计数 (可选)
);

    // =========================================================================
    // 地址分解
    // =========================================================================
    logic [INDEX_W-1:0] index;
    logic [TAG_W-1:0]   tag;
    assign index = addr_i[INDEX_W+1:2];
    assign tag   = addr_i[31:INDEX_W+2];

    // =========================================================================
    // 缓存存储: 双路 + 状态
    // =========================================================================
    logic                valid_a [0:NUM_SETS-1], valid_b [0:NUM_SETS-1];
    logic [TAG_W-1:0]    tag_a   [0:NUM_SETS-1], tag_b   [0:NUM_SETS-1];
    logic [31:0]         data_a  [0:NUM_SETS-1], data_b  [0:NUM_SETS-1];
    logic [2:0]          reuse_a [0:NUM_SETS-1], reuse_b [0:NUM_SETS-1];
    logic                loop_a  [0:NUM_SETS-1], loop_b  [0:NUM_SETS-1];
    logic                br_tgt_a[0:NUM_SETS-1], br_tgt_b[0:NUM_SETS-1];

    // 命中检测
    logic hit_a, hit_b, cache_hit;
    assign hit_a = valid_a[index] && (tag_a[index] == tag);
    assign hit_b = valid_b[index] && (tag_b[index] == tag);
    assign cache_hit = hit_a || hit_b;

    // 缓存数据输出
    logic [31:0] cache_data;
    assign cache_data = hit_a ? data_a[index] : data_b[index];

    // =========================================================================
    // PC 模式检测
    // =========================================================================
    typedef enum logic [1:0] {
        PC_MODE_SEQ    = 2'b00,   // PC+4, 顺序
        PC_MODE_LOOP   = 2'b01,   // 短反向跳(-256~0), 循环
        PC_MODE_BRANCH = 2'b10,   // 其他非顺序
        PC_MODE_CALL   = 2'b11    // 长跳转
    } pc_mode_e;

    logic [31:0] last_pc;
    pc_mode_e    pc_mode;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) last_pc <= 32'hFFFFFFFF;
        else         last_pc <= addr_i;
    end

    wire [31:0] pc_delta = addr_i - last_pc;
    always_comb begin
        if (pc_delta == 32'd4)
            pc_mode = PC_MODE_SEQ;
        else if ($signed(pc_delta) < 0 && $signed(pc_delta) > -256)
            pc_mode = PC_MODE_LOOP;
        else if (pc_delta != 32'd4 && $signed(pc_delta) >= 0)
            pc_mode = PC_MODE_BRANCH;
        else
            pc_mode = PC_MODE_CALL;
    end

    // =========================================================================
    // 流式旁路检测 (滑动窗口)
    // =========================================================================
    logic [3:0]  stream_window;  // 最近16次访问的缺失记录
    logic [4:0]  stream_miss_cnt;// 窗口内缺失计数
    logic        stream_bypass;  // 旁路模式

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            stream_window   <= 4'b0;
            stream_miss_cnt <= 5'd0;
            stream_bypass   <= 1'b0;
        end else begin
            // 滑动窗口
            stream_window <= {stream_window[2:0], ~cache_hit};

            // 每16次访问更新计数
            if (&stream_window == 1'b1 || stream_window == 4'b0001)
                stream_miss_cnt <= stream_window[0] + stream_window[1] +
                                   stream_window[2] + stream_window[3];

            // 进入旁路: 窗口内缺失>75%
            if (stream_miss_cnt >= 12)
                stream_bypass <= 1'b1;
            // 退出旁路: 窗口内缺失<25%
            else if (stream_miss_cnt <= 4)
                stream_bypass <= 1'b0;
        end
    end

    // =========================================================================
    // 遗产标记 (每组1bit)
    // =========================================================================
    logic evicted_hot [0:NUM_SETS-1];  // 上次踢的是否热行

    // =========================================================================
    // 后备BRAM
    // =========================================================================
    logic [31:0] backing_instr;
    rvp_instr_mem backing_mem (
        .addr_i  (addr_i[12:2]),
        .instr_o (backing_instr)
    );

    // =========================================================================
    // 预取缓冲 (单条目)
    // =========================================================================
    logic [29:0] pb_tag;       // PC[31:2]
    logic [31:0] pb_data;
    logic        pb_valid;
    logic [1:0]  pb_lifetime;

    logic pb_hit;
    assign pb_hit = pb_valid && (addr_i[31:2] == pb_tag);

    // PB 命中时返回数据
    logic [31:0] pb_instr;
    assign pb_instr = pb_data;

    // =========================================================================
    // 最终输出选择: PB > Cache > BRAM
    // =========================================================================
    assign instr_o = pb_hit    ? pb_instr     :
                     cache_hit ? cache_data   :
                                 backing_instr;

    // =========================================================================
    // 缺失分析器: 选受害者 + 状态更新 + 预取
    // =========================================================================

    // 踢人决策 (淘汰赛)
    logic victim_is_b;
    always_comb begin
        if (!valid_a[index])      victim_is_b = 1'b0;  // A空, 填A
        else if (!valid_b[index]) victim_is_b = 1'b1;  // B空, 填B
        else begin
            // 遗产优先: 如果新tag和上次被踢的相同→踢另一路
            // (简化: 遗产标记为1时优先保护热行多的那路)
            if (evicted_hot[index]) begin
                victim_is_b = (reuse_a[index] < reuse_b[index]);  // 保护热行
            end else begin
                // 淘汰赛
                // 第1轮: fresh (刚填未用, reuse=0)
                if ((reuse_a[index] == 0) != (reuse_b[index] == 0))
                    victim_is_b = (reuse_a[index] != 0);  // 踢fresh=1的
                // 第2轮: br_tgt
                else if (br_tgt_a[index] != br_tgt_b[index])
                    victim_is_b = br_tgt_a[index];  // 踢非br_tgt的
                // 第3轮: loop
                else if (loop_a[index] != loop_b[index])
                    victim_is_b = loop_a[index];  // 踢非loop的
                // 第4轮: reuse
                else
                    victim_is_b = (reuse_b[index] < reuse_a[index]);
            end
        end
    end

    // 缺失时状态更新
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < NUM_SETS; i++) begin
                valid_a[i]  <= 0;  valid_b[i]  <= 0;
                tag_a[i]    <= 0;  tag_b[i]    <= 0;
                data_a[i]   <= 0;  data_b[i]   <= 0;
                reuse_a[i]  <= 0;  reuse_b[i]  <= 0;
                loop_a[i]   <= 0;  loop_b[i]   <= 0;
                br_tgt_a[i] <= 0;  br_tgt_b[i] <= 0;
                evicted_hot[i] <= 0;
            end
        end else begin
            // ===== 缓存命中: 更新状态 =====
            if (hit_a) begin
                case (pc_mode)
                    PC_MODE_LOOP: begin
                        reuse_a[index]  <= (reuse_a[index] > 4) ? 3'd7 : reuse_a[index] + 2'd3;
                        loop_a[index]   <= 1;
                    end
                    PC_MODE_SEQ: begin
                        reuse_a[index]  <= (reuse_a[index] == 3'd7) ? 3'd7 : reuse_a[index] + 2'd1;
                    end
                    PC_MODE_BRANCH: begin
                        reuse_a[index]  <= (reuse_a[index] > 4) ? 3'd7 : reuse_a[index] + 2'd2;
                        br_tgt_a[index] <= 1;
                    end
                    default: begin
                        reuse_a[index]  <= 3'd3;
                        br_tgt_a[index] <= 1;
                    end
                endcase
            end
            if (hit_b) begin
                case (pc_mode)
                    PC_MODE_LOOP: begin
                        reuse_b[index]  <= (reuse_b[index] > 4) ? 3'd7 : reuse_b[index] + 2'd3;
                        loop_b[index]   <= 1;
                    end
                    PC_MODE_SEQ: begin
                        reuse_b[index]  <= (reuse_b[index] == 3'd7) ? 3'd7 : reuse_b[index] + 2'd1;
                    end
                    PC_MODE_BRANCH: begin
                        reuse_b[index]  <= (reuse_b[index] > 4) ? 3'd7 : reuse_b[index] + 2'd2;
                        br_tgt_b[index] <= 1;
                    end
                    default: begin
                        reuse_b[index]  <= 3'd3;
                        br_tgt_b[index] <= 1;
                    end
                endcase
            end

            // ===== 缺失: 填充 (除非旁路) =====
            if (!cache_hit && !stream_bypass) begin
                if (victim_is_b) begin
                    // 遗产记录
                    evicted_hot[index] <= (reuse_b[index] >= 4);
                    // 填B
                    valid_b[index]  <= 1;
                    tag_b[index]    <= tag;
                    data_b[index]   <= backing_instr;
                    // 初始reuse: 根据PC模式
                    case (pc_mode)
                        PC_MODE_LOOP:   reuse_b[index] <= 3'd5;
                        PC_MODE_BRANCH: reuse_b[index] <= 3'd3;
                        PC_MODE_CALL:   reuse_b[index] <= 3'd4;
                        default:        reuse_b[index] <= 3'd1;
                    endcase
                    loop_b[index]   <= (pc_mode == PC_MODE_LOOP);
                    br_tgt_b[index] <= (pc_mode != PC_MODE_SEQ);
                end else begin
                    evicted_hot[index] <= (reuse_a[index] >= 4);
                    valid_a[index]  <= 1;
                    tag_a[index]    <= tag;
                    data_a[index]   <= backing_instr;
                    case (pc_mode)
                        PC_MODE_LOOP:   reuse_a[index] <= 3'd5;
                        PC_MODE_BRANCH: reuse_a[index] <= 3'd3;
                        PC_MODE_CALL:   reuse_a[index] <= 3'd4;
                        default:        reuse_a[index] <= 3'd1;
                    endcase
                    loop_a[index]   <= (pc_mode == PC_MODE_LOOP);
                    br_tgt_a[index] <= (pc_mode != PC_MODE_SEQ);
                end
            end
        end
    end

    // =========================================================================
    // 预取缓冲逻辑
    // =========================================================================

    // 迷你译码: 缺失时分析指令, 决定预取目标
    logic        do_prefetch;
    logic [31:0] prefetch_addr;
    logic [6:0]  missed_opcode;
    assign missed_opcode = backing_instr[6:0];

    // J型立即数提取
    wire [31:0] imm_j = {{11{backing_instr[31]}}, backing_instr[31],
                         backing_instr[19:12], backing_instr[20],
                         backing_instr[30:21], 1'b0};

    always_comb begin
        do_prefetch = 1;
        case (missed_opcode)
            7'b1101111: begin  // JAL: 100%跳, 预取目标
                prefetch_addr = addr_i + imm_j;
            end
            7'b1100011: begin  // Branch: 预取fall-through (PC+4)
                prefetch_addr = addr_i + 4;
            end
            7'b1100111: begin  // JALR: 寄存器间接, 无法预取
                do_prefetch = 0;
            end
            default: begin     // 其他: 顺序预取
                prefetch_addr = addr_i + 4;
            end
        endcase
    end

    // PB填充和过期
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pb_valid    <= 0;
            pb_lifetime <= 0;
        end else begin
            // 过期
            if (pb_valid && pb_lifetime == 0)
                pb_valid <= 0;

            // 缺失时发起预取: 下一周期从BRAM读预取地址
            if (!cache_hit && do_prefetch) begin
                pb_tag      <= prefetch_addr[31:2];
                pb_data     <= backing_mem_read(prefetch_addr);  // 另一读端口
                pb_valid    <= 1;
                pb_lifetime <= 2'd3;
            end

            // 命中消费
            if (pb_hit) begin
                pb_valid    <= 0;
                pb_lifetime <= 0;
            end

            // 每次取指: lifetime递减
            if (pb_valid && !pb_hit)
                pb_lifetime <= pb_lifetime - 1;
        end
    end

    // 第二个BRAM读 (实际实现中复用同一个BRAM, 这里示意)
    function automatic logic [31:0] backing_mem_read(input [31:0] addr);
        // 实际: backing_mem.addr_i = addr[12:2], 等1周期
        // 简化: 直接调用 (组合读)
        backing_mem_read = backing_mem.instr_o;  // 注意: 这是示意
    endfunction

    // =========================================================================
    // 全局老化: 每256周期
    // =========================================================================
    logic [7:0] age_counter;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) age_counter <= 0;
        else         age_counter <= age_counter + 1;
    end

    wire do_age = (age_counter == 8'd255);
    always_ff @(posedge clk_i) begin
        if (do_age) begin
            for (int i = 0; i < NUM_SETS; i++) begin
                reuse_a[i] <= {1'b0, reuse_a[i][2:1]};  // >>1
                reuse_b[i] <= {1'b0, reuse_b[i][2:1]};
                loop_a[i]  <= 0;
                loop_b[i]  <= 0;
            end
        end
    end

    // =========================================================================
    // 统计计数器
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            hit_count_o       <= 0;
            miss_count_o      <= 0;
            pb_hit_count_o    <= 0;
            conflict_count_o  <= 0;
        end else begin
            if (pb_hit) begin
                pb_hit_count_o <= pb_hit_count_o + 1;
            end else if (cache_hit) begin
                hit_count_o <= hit_count_o + 1;
            end else begin
                miss_count_o <= miss_count_o + 1;
                // 冲突缺失: 两路都满且需要踢人
                if (valid_a[index] && valid_b[index])
                    conflict_count_o <= conflict_count_o + 1;
            end
        end
    end

endmodule
