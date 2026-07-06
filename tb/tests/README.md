# RVP 测试固件 (Test Firmware)

本目录包含用于验证 RVP 处理器功能正确性的 RISC-V 汇编测试程序。

测试用例来源于 [riscv-tests](https://github.com/riscv/riscv-tests) 项目（与
picorv32 的 `tests/` 目录一致），涵盖 RV32I 基础指令集和 RV32M 乘除法扩展。

## 目录结构

```
tb/tests/
├── Makefile          # 测试编译脚本
├── README.md         # 本文件
├── link.ld           # 链接脚本（自动生成）
├── riscv_test.h      # 测试环境头文件（需从 picorv32 拷贝）
├── test_macros.h     # 测试宏定义（需从 picorv32 拷贝）
├── *.S               # 测试汇编源文件
└── build/            # 编译输出目录
    ├── *.hex         # Verilog hex 文件（用于 $readmemh 加载到 BRAM）
    ├── *.elf         # ELF 可执行文件
    └── *.dis         # 反汇编列表（调试用）
```

## 前置条件

### 安装 RISC-V 工具链

需要安装 `riscv-gnu-toolchain`（支持 `rv32im` 架构）：

```bash
# Ubuntu / Debian
sudo apt install gcc-riscv32-unknown-elf

# 或从源码编译（推荐，版本更新）
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain
./configure --prefix=/opt/riscv --with-arch=rv32im --with-abi=ilp32
make
export PATH=$PATH:/opt/riscv/bin
```

验证安装：

```bash
riscv32-unknown-elf-gcc --version
```

### 拷贝测试文件

如果本目录没有 `.S` 测试文件，可以从 picorv32 参考目录拷贝：

```bash
make copy-tests
```

这会将以下文件从 `document/references/picorv32/tests/` 拷贝到当前目录：
- 所有 `.S` 测试文件
- `riscv_test.h` - 测试环境头文件
- `test_macros.h` - 测试宏定义

## 编译测试

### 编译所有测试

```bash
make all
```

编译成功后，`build/` 目录下会生成每个测试的 `.hex`、`.elf` 和 `.dis` 文件。

### 编译单个测试

```bash
make test_add       # 编译 add.S
make test_lw        # 编译 lw.S
make test_mul       # 编译 mul.S
```

### 列出所有测试

```bash
make list
```

### 清理

```bash
make clean
```

## 运行测试

### 在仿真中运行

从项目根目录执行：

```bash
# 使用默认配置运行仿真
make sim

# 指定配置
make sim CONFIG=phase2_full_rv32i

# 使用 Verilator
make sim SIMULATOR=verilator CONFIG=phase3_full
```

仿真时，Testbench 会通过 `$readmemh` 将 `.hex` 文件加载到指令存储器中，
处理器执行测试程序。测试通过时输出 "OK"，失败时输出 "ERROR"。

### 批量运行所有测试

```bash
make test
```

这会编译所有测试固件，然后逐个运行仿真。

## 测试用例列表

以下测试用例源自 riscv-tests 项目的 `rv32ui` 和 `rv32um` 测试套件。

### RV32I - 算术逻辑指令

| 测试文件   | 指令   | 说明               | 对应配置        |
|------------|--------|--------------------|-----------------|
| `add.S`    | add    | 加法               | phase1_basic+   |
| `addi.S`   | addi   | 立即数加法         | phase1_basic+   |
| `sub.S`    | sub    | 减法               | phase1_basic+   |
| `and.S`    | and    | 按位与             | phase1_basic+   |
| `andi.S`   | andi   | 立即数按位与       | phase1_basic+   |
| `or.S`     | or     | 按位或             | phase1_basic+   |
| `ori.S`    | ori    | 立即数按位或       | phase1_basic+   |
| `xor.S`    | xor    | 按位异或           | phase1_basic+   |
| `xori.S`   | xori   | 立即数按位异或     | phase1_basic+   |

### RV32I - 移位指令

| 测试文件   | 指令   | 说明               |
|------------|--------|--------------------|
| `sll.S`    | sll    | 逻辑左移           |
| `slli.S`   | slli   | 立即数逻辑左移     |
| `sra.S`    | sra    | 算术右移           |
| `srai.S`   | srai   | 立即数算术右移     |
| `srl.S`    | srl    | 逻辑右移           |
| `srli.S`   | srli   | 立即数逻辑右移     |

### RV32I - 比较指令

| 测试文件   | 指令   | 说明               |
|------------|--------|--------------------|
| `slt.S`    | slt    | 小于则置位（有符号）|
| `slti.S`   | slti   | 立即数小于则置位   |

### RV32I - 控制流指令

| 测试文件   | 指令   | 说明               |
|------------|--------|--------------------|
| `beq.S`    | beq    | 相等则跳转         |
| `bne.S`    | bne    | 不等则跳转         |
| `blt.S`    | blt    | 小于则跳转（有符号）|
| `bltu.S`   | bltu   | 小于则跳转（无符号）|
| `bge.S`    | bge    | 大于等于则跳转     |
| `bgeu.S`   | bgeu   | 大于等于则跳转（无符号）|
| `j.S`      | jal    | 无条件跳转         |
| `jal.S`    | jal    | 跳转并链接         |
| `jalr.S`   | jalr   | 寄存器跳转并链接   |

### RV32I - 加载/存储指令

| 测试文件   | 指令   | 说明               |
|------------|--------|--------------------|
| `lb.S`     | lb     | 加载字节（有符号） |
| `lbu.S`    | lbu    | 加载字节（无符号） |
| `lh.S`     | lh     | 加载半字（有符号） |
| `lhu.S`    | lhu    | 加载半字（无符号） |
| `lw.S`     | lw     | 加载字             |
| `sb.S`     | sb     | 存储字节           |
| `sh.S`     | sh     | 存储半字           |
| `sw.S`     | sw     | 存储字             |

### RV32I - 上层立即数指令

| 测试文件   | 指令   | 说明               |
|------------|--------|--------------------|
| `lui.S`    | lui    | 加载上层立即数     |
| `auipc.S`  | auipc | PC相对上层立即数   |

### RV32M - 乘除法扩展

> 需要 `RV32M=1` 配置（phase2_full_rv32i 及以上）

| 测试文件   | 指令    | 说明                 |
|------------|---------|----------------------|
| `mul.S`    | mul     | 乘法                 |
| `mulh.S`   | mulh    | 有符号高半乘法       |
| `mulhsu.S` | mulhsu  | 有符号×无符号高半乘法 |
| `mulhu.S`  | mulhu   | 无符号高半乘法       |
| `div.S`    | div     | 有符号除法           |
| `divu.S`   | divu    | 无符号除法           |
| `rem.S`    | rem     | 有符号取余           |
| `remu.S`   | remu    | 无符号取余           |

### 其他

| 测试文件   | 说明               |
|------------|--------------------|
| `simple.S` | 简单综合测试       |

## 测试框架说明

### riscv_test.h

测试环境头文件，定义了以下宏：

- `RVTEST_CODE_BEGIN` - 测试代码起始标记
- `RVTEST_PASS` - 测试通过（输出 "OK"）
- `RVTEST_FAIL` - 测试失败（输出 "ERROR"）
- `RVTEST_DATA_BEGIN` / `RVTEST_DATA_END` - 数据段标记

picorv32 版本的 `riscv_test.h` 通过向地址 `0x10000000` 写入字符来输出
测试结果。如果 RVP 处理器的内存映射不同，需要修改此头文件中的输出地址。

### test_macros.h

测试宏定义，提供了简化测试编写的宏：

- `TEST_RR_OP(n, inst, result, val1, val2)` - 寄存器-寄存器操作测试
- `TEST_IMM_OP(n, inst, result, val1, imm)` - 寄存器-立即数操作测试
- `TEST_LDST_OP(n, inst, result, addr)` - 加载/存储操作测试
- `TEST_CASE(n, reg, val, code)` - 通用测试用例

## 编译流程

每个测试的编译流程如下：

```
test.S  ──[riscv-gcc]──>  test.elf  ──[objcopy -O verilog]──>  test.hex
                              │
                              └──[objdump -d]──>  test.dis
```

1. **汇编/编译**：`riscv32-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib
   -T link.ld test.S -o test.elf`
2. **生成 hex**：`riscv32-unknown-elf-objcopy -O verilog test.elf test.hex`
3. **生成反汇编**：`riscv32-unknown-elf-objdump -d test.elf > test.dis`

## 配置与架构对应关系

| 配置               | 架构     | 适用测试                          |
|--------------------|----------|-----------------------------------|
| `phase1_basic`     | rv32i    | 基础指令（无 M 扩展）             |
| `phase2_full_rv32i`| rv32im   | 全部 RV32I + RV32M 测试           |
| `phase3_icache_*`  | rv32im   | 全部测试（验证 I-Cache 正确性）   |
| `phase3_full`      | rv32imc  | 全部测试 + 压缩指令测试           |

> 注意：使用 `phase1_basic` 配置时，RV32M 测试（mul, div 等）会编译失败，
> 因为该配置不包含 M 扩展。可以通过 `make ARCH=rv32i` 来只编译基础指令测试。

## 内存映射

测试程序使用的内存映射（需与 RVP 处理器/SoC 的地址映射一致）：

| 地址范围              | 用途               |
|-----------------------|--------------------|
| `0x00000000 - 0x00007FFF` | 指令存储器 (32KB)  |
| `0x00008000 - 0x0000FFFF` | 数据存储器 (32KB)  |
| `0x10000000`           | UART 输出（测试结果）|

如需修改内存映射，请更新 `link.ld` 链接脚本和 `riscv_test.h` 中的输出地址。
