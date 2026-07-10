// =============================================================================
// rvp_icache.sv - RVP 指令缓存（直接映射 I-Cache）
// =============================================================================
// 功能：在 CPU 取指阶段与指令存储器之间增加一级缓存。
//       采用直接映射结构，命中时从缓存寄存器组合读出（零延迟），
//       未命中时从后备 BRAM 组合读出并同步填充缓存行。
//
// 缓存结构：
//   - 直接映射（Direct-Mapped）
//   - 64 个缓存行，每行 1 个字（4 字节），总容量 256 字节
//   - 地址分解：Tag[31:8] | Index[7:2] | Offset[1:0]=00
//   - 每行包含：Valid(1bit) + Tag(24bit) + Data(32bit)
//
// 工作原理：
//   1. 取指时，用 PC[7:2] 作为索引读取 Tag 阵列和 Data 阵列（异步读）
//   2. 比较 Tag：若 Valid=1 且 Tag 匹配 → 命中，返回缓存数据
//   3. 若未命中 → 从后备 BRAM 读取指令（异步读），返回该指令，
//      同时在时钟上升沿将指令写入缓存行（同步填充）
//   4. 复位时所有 Valid 位清零
//
// 设计特点：
//   - 命中和未命中均在同一周期返回数据（后备 BRAM 也是异步读）
//   - 不改变流水线时序（无需 stall），对流水线透明
//   - 循环体中的重复取指会命中缓存，减少 BRAM 读端口竞争
//   - 统计计数器记录命中/未命中次数，可用于命中率分析
// =============================================================================

module rvp_icache #(
  parameter int NUM_LINES = 64,           // 缓存行数
  parameter int INDEX_W   = 6             // 索引位宽（$clog2(64)=6，显式指定避免 Vivado 2018.3 bug）
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [31:0] addr_i,     // PC（字节地址）
  output logic [31:0] instr_o,    // 指令输出
  output logic        hit_o,      // 命中信号（统计用）
  output logic        miss_o,     // 未命中信号（统计用）
  output logic [31:0] hit_count_o,  // 命中计数
  output logic [31:0] miss_count_o  // 未命中计数
);

  // -------------------------------------------------------------------------
  // 地址字段分解
  // -------------------------------------------------------------------------
  // Index = addr[7:2]（字地址的低 6 位）
  // Tag   = addr[31:8]
  localparam int TAG_W = 24;  // 32 - 6 - 2 = 24 bits

  logic [INDEX_W-1:0] index;
  logic [TAG_W-1:0]   tag;

  assign index = addr_i[INDEX_W+1:2];
  assign tag   = addr_i[31:INDEX_W+2];

  // 消费未使用的字节偏移位，避免 Vivado 综合警告
  logic _unused_addr_bits;
  assign _unused_addr_bits = |addr_i[1:0];

  // -------------------------------------------------------------------------
  // Tag 阵列：Valid + Tag
  // -------------------------------------------------------------------------
  logic                  valid_array [0:NUM_LINES-1];
  logic [TAG_W-1:0]      tag_array   [0:NUM_LINES-1];

  // -------------------------------------------------------------------------
  // Data 阵列：缓存指令
  // -------------------------------------------------------------------------
  logic [31:0]           data_array  [0:NUM_LINES-1];

  // -------------------------------------------------------------------------
  // 后备存储器（BRAM）
  // -------------------------------------------------------------------------
  logic [31:0] backing_instr;
  logic [10:0] backing_addr;  // 2048-depth word address (11 bits, $clog2(2048)=11)

  // PC 的字地址截取到 BRAM 地址范围（8KB = 2048 字 = 11 位字地址）
  assign backing_addr = addr_i[12:2];

  rvp_instr_mem backing_mem (
    .addr_i  (backing_addr),
    .instr_o (backing_instr)
  );

  // -------------------------------------------------------------------------
  // Tag 比较（组合逻辑）
  // -------------------------------------------------------------------------
  logic cache_hit;
  assign cache_hit = valid_array[index] && (tag_array[index] == tag);

  assign hit_o  = cache_hit;
  assign miss_o = ~cache_hit;

  // -------------------------------------------------------------------------
  // 指令输出选择
  //   命中 → 从缓存读
  //   未命中 → 从后备 BRAM 读（同为异步读，同一周期返回）
  // -------------------------------------------------------------------------
  assign instr_o = cache_hit ? data_array[index] : backing_instr;

  // -------------------------------------------------------------------------
  // 缓存填充（同步写）：未命中时在时钟上升沿更新缓存行
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // 复位：所有 Valid 位清零
      for (int i = 0; i < NUM_LINES; i++) begin
        valid_array[i] <= 1'b0;
        tag_array[i]   <= '0;
        data_array[i]  <= 32'b0;
      end
    end else if (!cache_hit) begin
      // 未命中：填充缓存行
      valid_array[index] <= 1'b1;
      tag_array[index]   <= tag;
      data_array[index]  <= backing_instr;
    end
  end

  // -------------------------------------------------------------------------
  // 统计计数器
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      hit_count_o  <= 32'b0;
      miss_count_o <= 32'b0;
    end else begin
      if (cache_hit)
        hit_count_o <= hit_count_o + 32'd1;
      else
        miss_count_o <= miss_count_o + 32'd1;
    end
  end

endmodule : rvp_icache
