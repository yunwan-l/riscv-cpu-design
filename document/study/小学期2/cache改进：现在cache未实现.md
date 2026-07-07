
## 当前 Cache 实现状态诊断

| 模块                         | 状态          | 问题                                                               |
| -------------------------- | ----------- | ---------------------------------------------------------------- |
| `rvp_icache.sv`            | **空壳 stub** | 所有输出接死值，无命中/缺失/refill 逻辑                                         |
| `rvp_dcache.sv`            | **空壳 stub** | 同上，无 write-back 逻辑                                               |
| `rvp_cache_replacement.sv` | 部分实现        | PLRU path-flip 未实现(占位符)、SRRIP/DRRIP 退化为 RR、LRU/FIFO 是全局非 per-set |
| `rvp_cache_tag_array.sv`   | 可用          | 异步读时序紧张、无 BRAM 属性、for-loop reset fanout 大                        |
| `rvp_cache_data_array.sv`  | 可用          | **无 byte-enable 写端口**，D-Cache write-back 无法正确工作                  |
| `rvp_cache_stats.sv`       | 可用          | snapshot 寄存器未实现，软件读到不一致数据                                        |
| `rvp_cache_flush.sv`       | 可用          | D-Cache writeback-before-flush 未实现                               |

**最致命的问题**：I-Cache 和 D-Cache 控制器是空壳——意味着所有替换策略的对比实验目前**根本无法运行**。

---

## 改进方案

### 方案一：补全 Cache 控制器核心逻辑（最高优先级）

这是让整个 Cache 子系统"活起来"的前提。需要实现的内容：

**I-Cache 控制器**（`rvp_icache.sv`）：
- 实现 `CACHE_IDLE → CACHE_LOOKUP → CACHE_MISS → CACHE_REFILL` 状态机
- 命中路径：Tag 比较命中 → 直接从 data array 选字输出，1 周期响应
- 缺失路径：通过总线接口发起 refill 请求 → 等待 `gnt_i`/`rvalid_i` → 写入 tag+data array → 返回数据
- 分支时清空 prefetch buffer（`branch_i` 信号已预留）

**D-Cache 控制器**（`rvp_dcache.sv`）：
- 在 I-Cache 基础上增加写路径：Write-Through 或 Write-Back
- Write-Back 需要 dirty bit 管理（tag 结构体已预留 `dirty` 字段）
- 缺失且 victim 行 dirty 时：先写回脏行 → 再 refill 新行
- Store 指令需要 byte-enable 写入 data array（当前 data array 缺这个端口）

**工作量**：约 300-400 行 SystemVerilog，是整个拓展的核心。

---

### 方案二：修复替换策略中的未完成项

当前替换策略模块有 3 个策略是坏的或占位的：

**修复 PLRU path-flip**（当前 `plru_q <= plru_q` 是死代码）：
```
// 访问命中某 way 后，从根到该叶子的路径上翻转 bit
// bit 指向"远离"最近使用叶子的方向
function automatic plru_update(tree, way_onehot):
    node = 0
    for lvl from TREE_DEPTH-1 downto 0:
        dir = way_idx[lvl]       // 0=左, 1=右
        tree[node] = ~dir        // 指向相反方向
        node = dir ? 2*node+2 : 2*node+1
    return tree
```

**实现 SRRIP**（当前退化为 RR）：
- 每个 way 加 2-bit RRPV 寄存器
- Fill 时初始化为 `RRPV_INIT=2`
- Hit 时 RRPV 归零
- Victim 选择：找 RRPV==3 的 way；没有则所有 way 的 RRPV 加 1，重复直到找到

**将 LRU/FIFO 改为 per-set**：
- 当前是全局 timestamp，不同 set 之间会互相干扰比较结果
- 改为 `logic [LRU_W-1:0] lru_age_q [NUM_LINES][NUM_WAYS]`，用 `set_index_i` 索引
- 这是保证命中率对比实验科学性的必要条件

---

### 方案三：Data Array 增加 Byte-Enable 写端口

当前 data array 只能整行写入（refill 时），但 D-Cache 的 store 指令（sb/sh/sw）需要修改已缓存行中的部分字节。不改这个，Write-Back D-Cache 会丢失数据。

**修改 `rvp_cache_data_array.sv`**：
- 新增 `input logic [LINE_SIZE/8-1:0] wbe_i`（write byte enable）
- 写逻辑改为：
```systemverilog
for (int b = 0; b < LINE_SIZE/8; b++) begin
    if (wbe_i[b] && req_i[w])
        data_storage[w][addr][b*8 +: 8] <= wdata_i[b*8 +: 8];
end
```
- Refill 时 `wbe_i = '1`（全写），Store 时 `wbe_i` 由 MEM 级的 `byte_enable` + 地址偏移生成

---

### 方案四：Tag/Data Array 改为同步读 + BRAM 推断

当前异步读（组合逻辑 mux）在 FPGA 上会推断为分布式 RAM（LUTRAM），消耗大量 LUT 而非 BRAM。对于 4KB/2-way 的 cache，256 行 × 22-bit tag = 5632 bit，用 LUTRAM 会浪费 ~170 个 LUT。

**修改方案**：
- Tag/Data array 的读改为同步读（注册输出）
- 添加 `(* ram_style = "block" *)` 属性强制推断 BRAM
- 代价：命中路径增加 1 周期延迟，需要流水线中插入一个 LOOKUP 状态
- 收益：FPGA 资源占用大幅降低，时序更宽松，能跑到更高频率

```
当前：  req → 组合读 → tag比较 → 命中输出  (0周期延迟)
改后：  req → 注册读 → tag比较 → 命中输出  (1周期延迟，但省BRAM)
```

---

### 方案五：增加 Cache Prefetch（预取）

针对 I-Cache 的顺序取指特性，可以加一个简单的 Next-Line Prefetcher：

- 当命中 line N 时，预取 line N+1 到 cache（如果不在 cache 中）
- 用一个 1-bit 的 prefetch pending 标志避免重复预取
- 总线空闲时发起 prefetch，不阻塞正常请求

**预期收益**：循环和顺序代码的 I-Cache miss rate 降低 30-50%。

**风险**：预取错误会浪费总线带宽和污染 cache，需要配合合理的替换策略。

---

### 方案六：完善统计模块的 Snapshot 功能

当前 `rvp_cache_stats.sv` 的 `sample_i` 输入是空脚。软件逐个读 7 个 32-bit 计数器时，计数器仍在变化，导致 `hits + misses != total_accesses` 的不一致。

**实现方案**：
```systemverilog
cache_stats_t snapshot_q;
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)       snapshot_q <= '0;
    else if (sample_i) snapshot_q <= stats_o;  // 原子快照
end
// 软件流程：写 sample CSR → 读 snapshot CSRs → 写 clear CSR
```

同时可以在硬件中直接计算 AMAT（Average Memory Access Time）：
```
AMAT = hit_time + (misses/total) * miss_penalty
```
用组合除法器或查找表实现，避免软件浮点运算。

---

### 方案七：增加 Cache 配置参数化与运行时切换

当前替换策略是**编译期**通过参数选择，比较 6 种策略需要综合 6 次。可以改为运行时切换：

**方案 A（简单）**：用 CSR 寄存器选择策略
- 新增一个 `cache_policy_csr`，低 3 位选择当前激活的替换策略
- 所有策略同时例化，用 `case` 语句根据 CSR 选择 `replace_way_o`
- 代价：面积增大（6 套状态机），但一次综合即可运行所有对比

**方案 B（折中）**：每 N 条指令自动切换策略
- 统计模块每 10000 次访问后切换到下一个策略并清零计数器
- 适合自动化 benchmark，不需要软件干预

---

## 建议的实施优先级

| 优先级 | 方案 | 理由 |
|--------|------|------|
| P0 | 方案一：补全控制器 | 没有它，整个 cache 拓展无法运行 |
| P0 | 方案二：修复替换策略 | PLRU/SRRIP 坏的，对比实验不科学 |
| P1 | 方案三：Byte-Enable | D-Cache write-back 的必要条件 |
| P1 | 方案六：Snapshot | 对比实验数据可信的前提 |
| P2 | 方案四：BRAM 推断 | FPGA 资源优化，非功能必需 |
| P3 | 方案七：运行时切换 | 便于实验，但不影响正确性 |
| P3 | 方案五：Prefetch | 锦上添花，可作为额外拓展点 |

建议从方案一开始，先把 I-Cache 控制器跑通（只做命中+缺失+refill），验证 riscv-tests 能通过，再逐步推进 D-Cache 和替换策略修复。