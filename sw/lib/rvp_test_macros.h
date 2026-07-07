// =============================================================================
// rvp_test_macros.h — RVP 测试宏定义
// =============================================================================
// 参考 riscv-tests 的自检测试风格。
// 约定：gp(x3) = 测试结果（1=通过，其他=失败编号）
// =============================================================================

#ifndef RVP_TEST_MACROS_H
#define RVP_TEST_MACROS_H

// 测试初始化
#define INIT_TESTS              \
    li  gp, 0

// 单个测试用例：如果 reg != val，跳到失败
#define TEST_CASE(testnum, reg, val)  \
    li  t0, val;                      \
    bne reg, t0, fail;                \
    j 2f;                             \
2:

// 通过：gp=1，跳到 PASS
#define TEST_PASS              \
    li  gp, 1;                 \
    j   pass

#endif
