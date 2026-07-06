// =============================================================================
// rvp_data_mem.sv — RVP 数据存储器
// =============================================================================
// 功能：支持字节/半字/字的读写，带符号/零扩展。
//
// 接口：
//   clk_i        : 时钟（写操作在时钟沿）
//   addr_i       : 字节地址（来自 ALU 计算的 rs1+imm）
//   write_data_i : 要写入的数据（来自 rs2）
//   mem_read_i   : 读使能
//   mem_write_i  : 写使能
//   mem_size_i   : 访问大小（B/H/W）
//   mem_unsigned_i: 1=无符号读（lbu/lhu），0=有符号读（lb/lh）
//   read_data_o  : 读出的数据（已扩展到 32 位）
//
// 设计要点：
//   1. 异步读 + 同步写（和寄存器堆一致，单周期标准做法）
//   2. 字节寻址：用 addr[1:0] 决定访问字内的哪个字节/半字
//   3. 子字访问的读：先从字里取出需要的字节/半字，再按 unsigned 做符号/零扩展
//   4. 子字访问的写：只写对应字节，其它字节保持不变（用 byte enable）
//   5. 容量：16K 字 = 64KB（仿真够用，FPGA 上用 BRAM）
// =============================================================================

module rvp_data_mem #(
  parameter int DEPTH = 16384  // 16K 字 = 64KB
) (
  input  logic                    clk_i,
  input  logic [31:0]             addr_i,
  input  logic [31:0]             write_data_i,
  input  logic                    mem_read_i,
  input  logic                    mem_write_i,
  input  rvp_pkg::mem_size_e      mem_size_i,
  input  logic                    mem_unsigned_i,
  output logic [31:0]             read_data_o
);

  import rvp_pkg::*;

  // 存储阵列
  logic [31:0] mem [0:DEPTH-1];

  // 字索引和字内偏移
  logic [31:2] word_addr;
  logic [1:0]  byte_offset;
  assign word_addr   = addr_i[31:2];
  assign byte_offset = addr_i[1:0];

  // 读出的原始字
  logic [31:0] raw_word;
  assign raw_word = mem[word_addr];

  // -------------------------------------------------------------------------
  // 读：从字中提取字节/半字，做符号/零扩展
  // -------------------------------------------------------------------------
  always_comb begin
    if (!mem_read_i) begin
      read_data_o = 32'b0;
    end else begin
      unique case (mem_size_i)
        SIZE_W: begin
          // 字读取：直接用整个字，无需扩展
          read_data_o = raw_word;
        end
        SIZE_H: begin
          // 半字读取：根据 addr[1] 选高/低半字
          logic [15:0] half;
          half = (byte_offset[1]) ? raw_word[31:16] : raw_word[15:0];
          // 符号/零扩展
          read_data_o = mem_unsigned_i ? {16'b0, half}
                                       : {{16{half[15]}}, half};
        end
        SIZE_B: begin
          // 字节读取：根据 addr[1:0] 选 4 个字节之一
          logic [7:0] byte_sel;
          unique case (byte_offset)
            2'b00:   byte_sel = raw_word[7:0];
            2'b01:   byte_sel = raw_word[15:8];
            2'b10:   byte_sel = raw_word[23:16];
            2'b11:   byte_sel = raw_word[31:24];
            default: byte_sel = 8'b0;
          endcase
          // 符号/零扩展
          read_data_o = mem_unsigned_i ? {24'b0, byte_sel}
                                       : {{24{byte_sel[7]}}, byte_sel};
        end
        default: read_data_o = 32'b0;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // 写：按大小写入对应字节/半字/字
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (mem_write_i) begin
      unique case (mem_size_i)
        SIZE_W: begin
          // 字写入：直接写整个字
          mem[word_addr] <= write_data_i;
        end
        SIZE_H: begin
          // 半字写入：根据 addr[1] 写高/低半字，另一半保持
          if (byte_offset[1]) begin
            mem[word_addr] <= {write_data_i[15:0], mem[word_addr][15:0]};
          end else begin
            mem[word_addr] <= {mem[word_addr][31:16], write_data_i[15:0]};
          end
        end
        SIZE_B: begin
          // 字节写入：根据 addr[1:0] 写 4 个字节之一，其余保持
          unique case (byte_offset)
            2'b00:   mem[word_addr] <= {mem[word_addr][31:8],  write_data_i[7:0]};
            2'b01:   mem[word_addr] <= {mem[word_addr][31:16], write_data_i[7:0], mem[word_addr][7:0]};
            2'b10:   mem[word_addr] <= {mem[word_addr][31:24], write_data_i[7:0], mem[word_addr][15:0]};
            2'b11:   mem[word_addr] <= {write_data_i[7:0], mem[word_addr][23:0]};
            default: ; // 不写
          endcase
        end
        default: ;
      endcase
    end
  end

endmodule : rvp_data_mem
