用户想了解在 Cache 基础功能已实现并可运行的前提下，有哪些可以作为"拓展点"的改进建议。这是一个偏向技术讨论和建议的问题，不需要读取文件（我已经在前几轮对话中充分了解了项目结构）。

让我从课程项目的角度，结合 RISC-V 处理器 Cache 设计，给出有实际意义、可量化对比、且有学术价值的拓展方向。重点是"拓展"——即在基础 Cache 之上能做什么有意思、有深度的工作。

我应该考虑：
1. 替换策略优化（这是项目原本的拓展重点）
2. 预取技术
3. Cache 一致性
4. 分区/着色 Cache
5. 自适应策略
6. 性能监控增强
7.功耗优化
7. 安全相关（侧信道防护）
8. 非阻塞 Cache
9. Victim Cache

让我给出多个方案，每个都说清楚：做什么、怎么做、怎么对比评估、难度和亮点。用中文回答。
假设基础 Cache 已经可运行，以下是真正有"拓展深度"的改进方向。我按**学术价值 + 实现可行性 + 课程报告可写性**三个维度组织。

---

## 一、替换策略深度拓展（项目主线）

这是项目原本设定的拓展方向，但当前只做到"6 种策略并存对比"。可以进一步深化：

### 1.1 自适应替换策略（DIP / DRRIP）

**做什么**：不是固定选一种策略，而是让 Cache **自己学习**哪种策略对当前程序更优。

**DIP（Dynamic Insertion Policy）原理**：
- 把所有 set 分成两组：A 组用 LRU 策略，B 组用 BIP（bimodal insertion，大部分新行插到 LRU 位置，少数插到 MRU 位置）
- 用一个 2-bit 饱和计数器 `PSEL` 跟踪两组的 miss 数
- 哪组 miss 少，就把所有 set 都切到那组的策略
- 对扫描型工作负载（streaming）效果显著，能避免 thrashing

**怎么对比**：
- 跑 riscv-tests 中的循环密集型 vs 顺序访问型测试
- 对比固定 LRU vs DIP 的 miss rate 曲线
- 画图：横轴访问数，纵轴累计 miss

**亮点**：这是 ISCA 2007 的经典论文，课程报告可以引用，体现理论深度。

### 1.2 RRIP 家族完整实现

**做什么**：把当前占位的 SRRIP/DRRIP 真正实现，并加入 RRIP 的变种对比。

**RRIP 核心思想**：给每个 cache 行一个 RRPV（Re-Reference Prediction Value），表示"预测多久后会被再次访问"。RRPV 越大 = 越久不被访问 = 越该被替换。

| 策略 | 新行 RRPV 初值 | Hit 时 RRPV | 替换选择 |
|------|----------------|-------------|----------|
| SRRIP | 固定 2 | 归 0 | 找 RRPV=max，没有则全局+1 |
| DRRIP | 动态（DIP 选择） | 归 0 | 同上 |
| DIP-RRIP | 结合 DIP 采样 | 归 0 | 同上 |

**对比实验设计**：
- 固定 2-way 4KB，跑同一组 benchmark
- 画 5 种策略（RR/LRU/PLRU/SRRIP/DRRIP）的 miss rate 柱状图
- 分析哪种策略对哪种访问模式最优

---

## 二、预取技术（Prefetching）

### 2.1 顺序预取器（Next-Line Prefetch）

**做什么**：I-Cache 命中 line N 时，自动预取 line N+1。

**实现要点**：
- 命中时检查 `(pc + line_size)` 对应的 set/tag 是否在 cache 中
- 不在则用空闲总线周期发起 refill，不阻塞正常取指
- 加一个 `prefetch_pending` 标志防止重复预取

**对比**：开启 vs 关闭预取的 I-Cache miss rate，预期循环代码降低 30-50%。

### 2.2 跨步预取器（Stride Prefetcher）

**做什么**：D-Cache 的访问模式往往有固定步长（数组遍历），学习这个步长提前预取。

**实现要点**：
- 每个 set 维护一个"上次访问地址 + 步长"寄存器
- 检测到稳定步长后，预取 `当前地址 + 步长`
- 用置信度计数器避免误预取

**对比**：跑矩阵乘法 / 数组求和 benchmark，对比 miss rate。

**亮点**：这是工业界真实使用的预取技术，报告里可以讲现代 CPU 的预取器设计。

---

## 三、非阻塞 Cache（Non-blocking / Hit-Under-Miss）

**做什么**：当前 Cache miss 时会 stall 整个流水线。非阻塞 Cache 允许 miss 期间的后续命中请求继续服务。

**实现要点**：
- 增加 Miss Status Holding Register（MSHR），记录未完成的 miss
- Miss 发生后，Cache 进入"miss pending"状态但继续接收请求
- 后续请求如果命中其他行 → 正常返回（hit-under-miss）
- 后续请求如果也 miss 且 MSHR 有空位 → 排队（multiple outstanding miss）

**对比**：
- 阻塞 vs 非阻塞的 CPI（Cycles Per Instruction）对比
- 在 Load 密集型程序上改善明显

**难度**：中等偏高，需要改 Cache 控制器状态机 + 增加 MSHR。但课程报告价值很大。

---

## 四、Victim Cache

**做什么**：在 L1 Cache 和下一级存储之间加一个小的全相联 Cache，存放被替换出去的行。

**实现要点**：
- 增加 4-8 项的全相联 victim cache（用寄存器阵列实现）
- L1 miss 时先查 victim cache，命中则交换数据（L1 取回该行，victim cache 存被替换的行）
- L1 + Victim 都 miss 才访问下一级

**对比**：
- 对比 2-way 直接映射 L1 vs 2-way L1 + 4 项 victim cache
- 冲突缺失（conflict miss）场景下效果显著
- 可以画出"等效相联度"分析：2-way + 4-entry victim ≈ 4-way 的命中率

**亮点**：Norman Jouppi 的经典论文（ISCA 1990），用极小硬件代价解决冲突缺失，报告好写。

---

## 五、Cache 分区与着色（Cache Partitioning / Coloring）

### 5.1 Way Partitioning

**做什么**：把 Cache 的 way 分配给不同任务，避免互相驱逐。

**实现要点**：
- 增加 way mask 寄存器，限制每个任务只能使用哪些 way
- 适合多任务场景（如果后续做多 hart 或 DMA）

**对比**：对比分区 vs 不分区时的 miss rate 抖动。

### 5.2 Page Coloring（软件配合）

**做什么**：操作系统分配物理页时，让特定进程的页映射到特定 Cache set。

**注意**：这需要修改软件（页分配器），硬件层面只需提供 set index 位数信息。可作为"软硬件协同"拓展点写进报告。

---

## 六、Write Policy 对比拓展

当前 D-Cache 计划用 Write-Back。可以做成可切换对比：

| 策略 | Write Hit | Write Miss | 优点 | 缺点 |
|------|-----------|------------|------|------|
| Write-Through | 写穿到下级 | Write-Allocate 或 No-Write-Allocate | 简单、一致性好 | 写带宽高 |
| Write-Back | 只写 Cache，标 dirty | Write-Allocate | 写带宽低 | 需要 dirty 回写逻辑 |
| Write-Around | 直接写下级，不进 Cache | — | 避免写污染 | 读 miss 时才加载 |

**对比实验**：
- Store 密集型 benchmark 下三种策略的总线带宽占用
- Dirty eviction 数量对比
- AMAT（平均访存时间）对比

**实现**：用参数 `WRITE_POLICY` 编译期切换，或用 CSR 运行时切换。

---

## 七、性能监控增强（PMU 拓展）

当前 `rvp_cache_stats.sv` 只统计 hits/misses。可以拓展为完整的性能监控单元：

**新增统计项**：
- **AMAT 计算**：硬件除法器算出 `hit_time + miss_rate × miss_penalty`，软件直接读
- **Per-set miss 分布**：找出热点 set（conflict 高发区）
- **Miss 分类**：Compulsory（冷启动）/ Capacity / Conflict 三类缺失统计
  - Compulsory：第一次访问该地址
  - Capacity：全相联也会 miss 的（总容量不够）
  - Conflict：直接映射会 miss 但全相联不会的
- **时间窗口采样**：每隔 N 周期自动 snapshot，画出"miss rate 随时间变化曲线"

**报告价值**：这些数据能让报告的"分析"部分非常扎实，而不只是给一个总 miss rate 数字。

---

## 八、功耗优化拓展

### 8.1 Way Prediction

**做什么**：预测下一次访问会命中哪个 way，只激活那个 way 的 tag/data 读，其他 way 不翻转。

**实现**：用一个小的 MRU 寄存器记录上次命中的 way，下次优先查它。

**收益**：节省 N-1 个 way 的读功耗（N=相联度）。

**对比**：预测准确率 vs 功耗节省（用翻转计数器估算）。

### 8.2 Drowsy Cache / Gated Vdd

**做什么**：长时间未访问的 cache 行进入低功耗模式。

**实现**：每个 way 加一个"最后访问时间"计数器，超过阈值则 gate clock。

**注意**：FPGA 上功耗测量困难，可以用翻转计数近似。报告里讲原理即可。

---

## 九、安全性拓展（侧信道防护）

### 9.1 随机化替换

**做什么**：用真随机替换（当前已有 LFSR Random）来抵抗 Cache 时序攻击。

**原理**：固定策略（LRU/RR）下，攻击者可以通过观察命中/缺失时间推断其他进程的访问模式。随机化替换打破这种可预测性。

**对比**：随机替换的安全强度 vs 命中率损失。

**报告亮点**：结合 Spectre/Meltdown 背景，课程报告能体现对安全问题的理解。

### 9.2 Cache 划分隔离

**做什么**：为不同特权级或不同任务分配独占的 Cache set，物理隔离。

**实现**：根据 `hart_id` 或特权级，限制可访问的 set 范围。

---

## 推荐组合方案

针对课程项目（需要展示深度 + 有对比数据 + 报告好写），推荐以下组合：

| 组合 | 内容 | 工作量 | 报告亮点 |
|------|------|--------|----------|
| **A（推荐）** | DIP 自适应 + 完整 RRIP 家族 + PMU 增强 | 中 | 策略对比 + 数据分析扎实 |
| **B** | 顺序预取 + Stride 预取 + 非阻塞 Cache | 中高 | 性能提升明显，CPI 对比 |
| **C** | Victim Cache + Write Policy 对比 | 低中 | 经典论文引用，实验清晰 |
| **D** | Way Prediction + 随机化替换 + 安全分析 | 中 | 跨功耗/安全两个维度 |

**组合 A 最契合项目原始设定**（替换策略优化），且 DIP 和 RRIP 都是 ISCA 论文级别的工作，课程报告的理论深度和实验对比都能做得很扎实。

如果想做"有性能数字"的拓展，组合 B 最直接——预取和非阻塞都能跑出明显的 CPI 改善。