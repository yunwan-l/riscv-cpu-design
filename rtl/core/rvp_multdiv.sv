// =============================================================================
// rvp_multdiv.sv — RVP M 扩展乘除法单元（多周期）
// =============================================================================
// 功能：执行 RISC-V M 扩展的 8 条指令（MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU）
//
// 接口：
//   clk_i       : 时钟
//   rst_ni      : 异步复位（低有效）
//   flush_i     : 冲刷信号（分支/跳转时取消当前计算）
//   start_i     : 启动信号（use_multdiv=1 且 multdiv 空闲时拉高 1 拍）
//   op_i        : 乘除法操作类型（multdiv_op_e）
//   operand_a_i : rs1（32 位）
//   operand_b_i : rs2（32 位）
//   result_o    : 运算结果（32 位，done_o=1 时有效）
//   done_o      : 完成信号（结果有效时拉高 1 拍）
//
// 设计要点：
//   1. 乘法：1 周期完成。使用 * 操作符，FPGA 上映射到 DSP48E1，组合延迟约 5ns。
//   2. 除法/取余：32 周期迭代恢复除法（Restoring Division）。
//      每周期处理 1 位，使用比较+减法，逻辑延迟约 5ns，远小于 40ns 时钟周期。
//   3. 特殊情况（RISC-V 规范）：
//      - 除以 0：DIV → -1（全1），DIVU → 0xFFFFFFFF，REM/REMU → 被除数 rs1
//      - 有符号溢出（-2^31 / -1）：DIV → -2^31，REM → 0
//   4. 有符号除法先取绝对值做无符号迭代，最后根据符号修正结果。
//
// 时序：
//   IDLE → (start) → MUL_DONE (乘法, 1拍) / DIV_CALC (除法, 32拍) → IDLE
//   done_o 在结果有效时拉高 1 拍
// =============================================================================

module rvp_multdiv (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   flush_i,
  input  logic                   start_i,
  input  rvp_pkg::multdiv_op_e   op_i,
  input  logic [31:0]            operand_a_i,
  input  logic [31:0]            operand_b_i,
  output logic [31:0]            result_o,
  output logic                   done_o,
  output logic                   idle_o
);

  import rvp_pkg::*;

  // -------------------------------------------------------------------------
  // 状态机
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    IDLE,
    DIV_CALC,
    DONE
  } state_t;

  state_t state_r;

  // 除法迭代计数器（0~31）
  logic [5:0] div_cnt_r;

  // 锁存的操作数和操作类型
  rvp_pkg::multdiv_op_e op_r;
  logic [31:0] a_r, b_r;

  // -------------------------------------------------------------------------
  // 判断是否为除法指令
  // -------------------------------------------------------------------------
  function automatic logic is_div_op(input rvp_pkg::multdiv_op_e op);
    return (op == MD_DIV) || (op == MD_DIVU) ||
           (op == MD_REM) || (op == MD_REMU);
  endfunction

  // -------------------------------------------------------------------------
  // 乘法（组合逻辑，使用 DSP）
  // -------------------------------------------------------------------------
  logic signed [63:0] a_s, b_s;
  logic        [63:0] a_u, b_u;

  assign a_s = $signed(operand_a_i);
  assign b_s = $signed(operand_b_i);
  assign a_u = {32'b0, operand_a_i};
  assign b_u = {32'b0, operand_b_i};

  logic signed [63:0] prod_ss;
  logic signed [63:0] prod_su;
  logic        [63:0] prod_uu;

  assign prod_ss = a_s * b_s;
  assign prod_su = a_s * $signed(b_u);
  assign prod_uu = a_u * b_u;

  // 乘法结果（基于当前输入，组合逻辑）
  function automatic [31:0] get_mul_result(input rvp_pkg::multdiv_op_e op);
    unique case (op)
      MD_MUL:    get_mul_result = prod_ss[31:0];
      MD_MULH:   get_mul_result = prod_ss[63:32];
      MD_MULHSU: get_mul_result = prod_su[63:32];
      MD_MULHU:  get_mul_result = prod_uu[63:32];
      default:   get_mul_result = 32'b0;
    endcase
  endfunction

  // -------------------------------------------------------------------------
  // 除法：符号处理
  // -------------------------------------------------------------------------
  // 基于锁存的操作数判断符号
  logic a_is_neg, b_is_neg;
  assign a_is_neg = (op_r == MD_DIV || op_r == MD_REM) && a_r[31];
  assign b_is_neg = (op_r == MD_DIV || op_r == MD_REM) && b_r[31];

  // 基于当前输入的绝对值（启动时使用）
  logic a_is_neg_in, b_is_neg_in;
  assign a_is_neg_in = (op_i == MD_DIV || op_i == MD_REM) && operand_a_i[31];
  assign b_is_neg_in = (op_i == MD_DIV || op_i == MD_REM) && operand_b_i[31];

  logic [31:0] dividend_abs_in, divisor_abs_in;
  assign dividend_abs_in = a_is_neg_in ? (~operand_a_i + 1'b1) : operand_a_i;
  assign divisor_abs_in  = b_is_neg_in ? (~operand_b_i + 1'b1) : operand_b_i;

  // -------------------------------------------------------------------------
  // 除法：迭代恢复除法工作寄存器
  // -------------------------------------------------------------------------
  logic [31:0] rem_r;       // 余数寄存器
  logic [31:0] quot_r;      // 商寄存器（初始装载被除数）
  logic [31:0] divisor_r;   // 存储除数

  // 迭代步骤（组合逻辑，1周期执行1步）
  // 1. 将 {rem, quot} 左移 1 位（quot 的 MSB 进入 rem 的 LSB）
  // 2. 用移位后的 rem 减去除数
  // 3. 若结果 >= 0：商位 = 1，保留减法结果
  //    若结果 < 0：商位 = 0，恢复原值
  logic [31:0] shifted_rem;
  logic        borrow;
  logic [31:0] sub_result;

  assign shifted_rem = {rem_r[30:0], quot_r[31]};
  assign {borrow, sub_result} = {1'b0, shifted_rem} - {1'b0, divisor_r};
  // borrow=1 表示不够减（结果为负）

  // -------------------------------------------------------------------------
  // 特殊情况标志
  // -------------------------------------------------------------------------
  logic div_by_zero, div_overflow;
  assign div_by_zero  = (b_r == 32'b0);
  assign div_overflow = (op_r == MD_DIV) && (a_r == 32'h80000000) && (b_r == 32'hFFFFFFFF);

  // -------------------------------------------------------------------------
  // 结果输出
  // -------------------------------------------------------------------------
  // 乘法结果锁存
  logic [31:0] mul_result_r;

  always_comb begin
    unique case (op_r)
      MD_MUL, MD_MULH, MD_MULHSU, MD_MULHU:
        result_o = mul_result_r;
      MD_DIV: begin
        if (div_by_zero)
          result_o = 32'hFFFFFFFF;
        else if (div_overflow)
          result_o = 32'h80000000;
        else
          result_o = (a_is_neg ^ b_is_neg) ? (~quot_r + 1'b1) : quot_r;
      end
      MD_DIVU: begin
        if (div_by_zero)
          result_o = 32'hFFFFFFFF;
        else
          result_o = quot_r;
      end
      MD_REM: begin
        if (div_by_zero)
          result_o = a_r;
        else if (div_overflow)
          result_o = 32'h00000000;
        else
          result_o = a_is_neg ? (~rem_r + 1'b1) : rem_r;
      end
      MD_REMU: begin
        if (div_by_zero)
          result_o = a_r;
        else
          result_o = rem_r;
      end
      default:
        result_o = 32'b0;
    endcase
  end

  // -------------------------------------------------------------------------
  // 完成信号
  // -------------------------------------------------------------------------
  assign done_o = (state_r == DONE);
  assign idle_o = (state_r == IDLE);

  // -------------------------------------------------------------------------
  // 状态机
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_r      <= IDLE;
      div_cnt_r    <= 6'd0;
      op_r         <= MD_MUL;
      a_r          <= 32'b0;
      b_r          <= 32'b0;
      rem_r        <= 32'b0;
      quot_r       <= 32'b0;
      divisor_r    <= 32'b0;
      mul_result_r <= 32'b0;
    end else if (flush_i) begin
      // 分支/跳转冲刷：取消当前计算
      state_r   <= IDLE;
      div_cnt_r <= 6'd0;
    end else begin
      case (state_r)
        // ---------------------------------------------------------------
        IDLE: begin
          if (start_i) begin
            op_r <= op_i;
            a_r  <= operand_a_i;
            b_r  <= operand_b_i;

            if (is_div_op(op_i)) begin
              // 除法：初始化迭代寄存器
              rem_r     <= 32'b0;
              quot_r    <= dividend_abs_in;
              divisor_r <= divisor_abs_in;
              div_cnt_r <= 6'd0;
              state_r   <= DIV_CALC;
            end else begin
              // 乘法：1 周期完成，锁存结果
              mul_result_r <= get_mul_result(op_i);
              state_r      <= DONE;
            end
          end
        end

        // ---------------------------------------------------------------
        DIV_CALC: begin
          // 迭代恢复除法：每周期处理 1 位
          if (!borrow) begin
            // 够减：商位 = 1，保留减法结果
            rem_r  <= sub_result;
            quot_r <= {quot_r[30:0], 1'b1};
          end else begin
            // 不够减：商位 = 0，恢复余数
            rem_r  <= shifted_rem;
            quot_r <= {quot_r[30:0], 1'b0};
          end

          div_cnt_r <= div_cnt_r + 6'd1;

          if (div_cnt_r == 6'd31) begin
            // 32 次迭代完成
            state_r <= DONE;
          end
        end

        // ---------------------------------------------------------------
        DONE: begin
          // 结果已输出，返回空闲
          state_r <= IDLE;
        end

        // ---------------------------------------------------------------
        default: state_r <= IDLE;
      endcase
    end
  end

endmodule : rvp_multdiv
