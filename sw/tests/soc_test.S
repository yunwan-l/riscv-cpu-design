// =============================================================================
// soc_test.S — SoC 外设测试程序
// =============================================================================
// 测试内容：
//   1. GPIO: 写 OUTPUT 寄存器点亮 LED
//   2. GPIO: 读 INPUT 寄存器获取开关值
//   3. UART: 写 TXDATA 发送字符 'H'
//   4. Timer: 启动计数器，读取计数值
//
// 地址映射：
//   GPIO OUTPUT = 0x10010000
//   GPIO INPUT  = 0x10010004
//   UART TXDATA = 0x10000000
//   UART TXSTAT = 0x10000004
//   TIMER COUNT = 0x10020000
//   TIMER CTRL  = 0x10020004
// =============================================================================

.text
.globl _start
_start:
    # ===== 1. GPIO: 写 0x1234 到 OUTPUT =====
    li   t0, 0x10010000      # GPIO 基地址
    li   t1, 0x1234          # 要写入的值
    sw   t1, 0(t0)           # GPIO_OUTPUT = 0x1234

    # ===== 2. GPIO: 读 INPUT =====
    lw   t2, 4(t0)           # t2 = GPIO_INPUT (开关值)

    # ===== 3. Timer: 启动计数 =====
    li   t3, 0x10020000      # Timer 基地址
    li   t4, 1               # enable=1
    sw   t4, 4(t3)           # TIMER_CTRL = 1 (启动)

    # 等待几个周期让计数器跑
    nop
    nop
    nop
    nop

    # 读计数器值
    lw   t5, 0(t3)           # t5 = TIMER_COUNT

    # ===== 4. UART: 发送字符 'H' (0x48) =====
    li   t6, 0x10000000      # UART 基地址
    li   a0, 0x48            # 'H'
    sb   a0, 0(t6)           # UART_TXDATA = 'H'

    # ===== 5. 把开关值写到 LED =====
    sw   t2, 0(t0)           # GPIO_OUTPUT = 开关值

    # ===== 结束：死循环 =====
loop:
    j    loop
