/**
 * rvp_test_utils.svh - Test Utility Macros for RVP Testbench
 *
 * RVP测试平台使用的宏定义文件，提供测试通过/失败标志和
 * 指令测试模式宏。参考picorv32 test_macros.h设计。
 *
 * 参考: picorv32 test_macros.h
 *
 * 包含内容:
 *   1. 测试结果标志定义 (PASS/FAIL)
 *   2. 测试通过/失败地址宏
 *   3. 测试通过/失败检查宏
 *   4. R-type指令测试宏 (TEST_RR_OP)
 *   5. I-type指令测试宏 (TEST_I_OP)
 *   6. 加载/存储指令测试宏
 *   7. 分支指令测试宏
 *
 * 使用方法:
 *   在测试程序(汇编)中使用这些宏定义测试向量:
 *     TEST_RR_OP( 1, add, 0x00000003, 0x00000001, 0x00000002 )
 *     TEST_I_OP ( 2, addi, 0x00000003, 0x00000001, 0x00000002 )
 *
 * 测试结果输出:
 *   测试通过: 向0x2000_0000写入123456789 (0x123456789...实际为32位)
 *   测试失败: 向0x2000_0000写入失败码 (非123456789)
 */

`ifndef RVP_TEST_UTILS_SVH
`define RVP_TEST_UTILS_SVH

// ==========================================================================
// 测试结果标志
// ==========================================================================

// 测试通过标志值 (写入0x2000_0000表示通过)
`define RVP_TEST_PASS    32'h123456789
// 注意: 32位系统中实际使用 32'h75BCD15 (123456789 & 0xFFFFFFFF)
// 但picorv32使用123456789，这里保持一致
`define RVP_TEST_PASS_VAL 123456789

// 测试地址 (内存映射I/O)
`define RVP_TEST_RESULT_ADDR  32'h2000_0000  // 测试结果地址
`define RVP_TEST_CHAR_ADDR    32'h1000_0000  // 字符输出地址 (UART THR)

// ==========================================================================
// 测试通过/失败宏 (用于汇编测试程序)
// ==========================================================================

// 标记测试通过: 向结果地址写入通过标志
`define RVP_TEST_PASS_WRITE \
    li  a0, `RVP_TEST_RESULT_ADDR; \
    li  a1, `RVP_TEST_PASS_VAL; \
    sw  a1, 0(a0); \
    j   rvvp_finish

// 标记测试失败: 向结果地址写入失败码
`define RVP_TEST_FAIL_WRITE(failcode) \
    li  a0, `RVP_TEST_RESULT_ADDR; \
    li  a1, failcode; \
    sw  a1, 0(a0); \
    j   rvvp_finish

// ==========================================================================
// R-type指令测试宏 (参考picorv32 TEST_RR_OP)
// ==========================================================================

// TEST_RR_OP(testnum, inst, result, rs1, rs2)
//   testnum : 测试编号 (用于标识不同测试用例)
//   inst    : 被测试的指令 (如add, sub, sll等)
//   result  : 期望结果
//   rs1     : 源操作数1
//   rs2     : 源操作数2
//
// 逻辑:
//   1. 将rs1和rs2加载到寄存器
//   2. 执行inst指令
//   3. 将结果与期望值比较
//   4. 不匹配则跳转到失败处理

`define TEST_RR_OP(testnum, inst, result, rs1_val, rs2_val) \
    li  t0, rs1_val;      \
    li  t1, rs2_val;      \
    inst t2, t0, t1;      \
    li  t3, result;       \
    bne t2, t3, rvvp_fail; \

// ==========================================================================
// I-type指令测试宏 (参考picorv32 TEST_I_OP)
// ==========================================================================

// TEST_I_OP(testnum, inst, result, rs1, imm)
//   testnum : 测试编号
//   inst    : 被测试的指令 (如addi, andi, ori等)
//   result  : 期望结果
//   rs1     : 源操作数
//   imm     : 立即数

`define TEST_I_OP(testnum, inst, result, rs1_val, imm_val) \
    li  t0, rs1_val;      \
    inst t2, t0, imm_val;  \
    li  t3, result;       \
    bne t2, t3, rvvp_fail; \

// ==========================================================================
// 加载/存储指令测试宏
// ==========================================================================

// TEST_LD_OP(testnum, inst, result, addr, testreg)
//   测试加载指令 (lb, lh, lw, lbu, lhu)
`define TEST_LD_OP(testnum, inst, result, store_inst, base_val, store_val) \
    li  t0, base_val;     \
    li  t1, store_val;    \
    store_inst t1, 0(t0);  \
    inst t2, 0(t0);        \
    li  t3, result;       \
    bne t2, t3, rvvp_fail; \

// TEST_ST_OP(testnum, inst, result, base_val, store_val)
//   测试存储指令 (sb, sh, sw)
`define TEST_ST_OP(testnum, inst, result, base_val, store_val) \
    li  t0, base_val;     \
    li  t1, store_val;    \
    inst t1, 0(t0);       \
    lw  t2, 0(t0);        \
    li  t3, result;       \
    bne t2, t3, rvvp_fail; \

// ==========================================================================
// 分支指令测试宏
// ==========================================================================

// TEST_BRANCH_OP(testnum, inst, result, rs1_val, rs2_val)
//   测试分支指令 (beq, bne, blt, bge等)
//   result=1表示应跳转, result=0表示不应跳转
`define TEST_BRANCH_OP(testnum, inst, taken, rs1_val, rs2_val) \
    li  t0, rs1_val;      \
    li  t1, rs2_val;      \
    inst t0, t1, 1f;       \
    li  t2, 0;             \
    j 2f;                  \
1:  li  t2, 1;             \
2:  li  t3, taken;        \
    bne t2, t3, rvvp_fail; \

// ==========================================================================
// 跳转指令测试宏
// ==========================================================================

// TEST_JAL(testnum, offset)
//   测试JAL指令跳转
`define TEST_JAL(testnum, offset) \
    jal t0, 1f;            \
    j rvvp_fail;            \
1:  j 2f;                  \
2:  \

// TEST_JALR(testnum, offset)
//   测试JALR指令跳转
`define TEST_JALR(testnum, offset) \
    la  t0, 1f;            \
    jalr t1, offset(t0);   \
    j rvvp_fail;            \
1:  j 2f;                  \
2:  \

// ==========================================================================
// CSR指令测试宏
// ==========================================================================

// TEST_CSR_OP(testnum, inst, result, csr_addr, rs1_val)
//   测试CSR指令 (csrrw, csrrs, csrrc等)
`define TEST_CSR_OP(testnum, inst, result, csr_addr, rs1_val) \
    li  t0, rs1_val;      \
    inst t1, t0, csr_addr; \
    li  t3, result;       \
    bne t1, t3, rvvp_fail; \

// ==========================================================================
// M-extension指令测试宏
// ==========================================================================

// TEST_MUL_OP(testnum, inst, result, rs1_val, rs2_val)
//   测试乘法指令 (mul, mulh, mulhsu, mulhu)
`define TEST_MUL_OP(testnum, inst, result, rs1_val, rs2_val) \
    li  t0, rs1_val;      \
    li  t1, rs2_val;      \
    inst t2, t0, t1;      \
    li  t3, result;       \
    bne t2, t3, rvvp_fail; \

// TEST_DIV_OP(testnum, inst, result, rs1_val, rs2_val)
//   测试除法指令 (div, divu, rem, remu)
`define TEST_DIV_OP(testnum, inst, result, rs1_val, rs2_val) \
    li  t0, rs1_val;      \
    li  t1, rs2_val;      \
    inst t2, t0, t1;      \
    li  t3, result;       \
    bne t2, t3, rvvp_fail; \

// ==========================================================================
// SystemVerilog仿真测试宏 (用于TB文件)
// ==========================================================================

// 检查通过: 在测试平台中使用
`define RVP_CHECK_PASS(signal) \
    if (signal !== `RVP_TEST_PASS) begin \
        $display("FAIL: Expected %0h, got %0h at time %0t", `RVP_TEST_PASS, signal, $time); \
        $finish; \
    end

// 检查超时: 在测试平台中使用
`define RVP_CHECK_TIMEOUT(cycles, max_cycles) \
    if (cycles > max_cycles) begin \
        $display("FAIL: Timeout at %0d cycles (max %0d)", cycles, max_cycles); \
        $finish; \
    end

// 打印测试信息
`define RVP_TEST_INFO(msg) \
    $display("[%0t] INFO: %s", $time, msg)

// 打印测试警告
`define RVP_TEST_WARN(msg) \
    $display("[%0t] WARN: %s", $time, msg)

// 打印测试错误
`define RVP_TEST_ERROR(msg) \
    $display("[%0t] ERROR: %s", $time, msg)

// ==========================================================================
// 汇编测试程序框架宏 (用于构建测试固件)
// ==========================================================================

// 测试程序入口
`define RVP_TEST_BEGIN \
    .section .text; \
    .global _start; \
_start: \
    /* 设置栈指针 */ \
    li  sp, 0x00018000; \
    /* 跳转到主测试 */ \
    j rvvp_main_test

// 测试程序结束
`define RVP_TEST_END \
rvvp_finish: \
    /* 等待UART发送完成 */ \
    wfi; \
    j rvvp_finish

// 测试失败处理
`define RVP_TEST_FAIL_HANDLER \
rvvp_fail: \
    li  a0, `RVP_TEST_RESULT_ADDR; \
    li  a1, 0xDEAD_BEEF; \
    sw  a1, 0(a0); \
    j rvvp_finish

// 主测试函数框架
`define RVP_TEST_MAIN \
rvvp_main_test: \

// ==========================================================================
// TODO: 添加更多测试宏
// ==========================================================================

// TODO: 添加压缩指令(C扩展)测试宏
// TODO: 添加异常处理测试宏 (ECALL, EBREAK)
// TODO: 添加中断测试宏
// TODO: 添加内存边界测试宏
// TODO: 添加性能计数器测试宏

`endif // RVP_TEST_UTILS_SVH
