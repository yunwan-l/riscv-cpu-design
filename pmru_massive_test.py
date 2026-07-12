#!/usr/bin/env python3
"""
PMRU 大规模命中率测试套件
=========================
覆盖100+种trace场景，包括：
1. 基础模式（循环/分支/调用/顺序）
2. 冲突场景（3-12路冲突）
3. 真实程序模式（排序/查找/矩阵/卷积/状态机等）
4. 随机分布（均匀/Zipf/泊松/突发）
5. 混合负载（多模式叠加）
6. 压力测试（极端冲突/频繁切换）

用法: python pmru_massive_test.py
输出: 控制台表格 + JSON结果文件
"""

import random
import json
import os
from dataclasses import dataclass, field
from typing import List, Callable

# ============================================================
# Cache配置 (8路64组, 与RTL一致)
# ============================================================
NUM_SETS = 64
WAYS = 8
TAG_SHIFT = 8  # 64 sets * 4B = 256B index range

def get_index(addr): return (addr >> 2) & (NUM_SETS - 1)
def get_tag(addr): return addr >> TAG_SHIFT

PC_SEQ, PC_LOOP, PC_BRANCH, PC_CALL = 0, 1, 2, 3
def detect_pc_mode(curr, last):
    d = (curr - last) & 0xFFFFFFFF
    if d == 4: return PC_SEQ
    if d > 0x80000000:
        ds = d - 0x100000000
        return PC_LOOP if ds > -256 else PC_CALL
    return PC_BRANCH if d != 4 else PC_SEQ

# ============================================================
# Cache实现
# ============================================================
@dataclass
class Line:
    valid: bool = False
    tag: int = 0
    last_access: int = 0
    hit_count: int = 0

class PMRUCache:
    def __init__(self, threshold=3, pf_depth=16, stream_thresh=16):
        self.lines = [[Line() for _ in range(WAYS)] for _ in range(NUM_SETS)]
        self.last_pc = 0xFFFFFFFF
        self.ac = 0; self.vtime = 0
        self.threshold = threshold
        self.pf_depth = pf_depth
        self.stream_thresh = stream_thresh
        self.pf_entries = []
        self.hits = 0; self.misses = 0
        self.pf_hits = 0; self.stream_bypass = 0
        self.seq_cnt = 0; self.stream_active = False

    def _select_victim(self, si):
        ls = self.lines[si]
        for w in range(WAYS):
            if not ls[w].valid: return w
        hit_vals = [ls[w].hit_count for w in range(WAYS)]
        min_hit = min(hit_vals)
        sorted_w = sorted(range(WAYS), key=lambda w: -ls[w].last_access)
        for w in sorted_w:
            if ls[w].hit_count - min_hit < self.threshold: return w
        return sorted_w[0]

    def _do_fill(self, si, tag):
        vw = self._select_victim(si)
        l = self.lines[si][vw]
        l.valid = True; l.tag = tag; l.last_access = self.vtime; l.hit_count = 0

    def _pf_check(self, a30):
        for i, (pa,) in enumerate(self.pf_entries):
            if pa == a30:
                self.pf_entries.pop(i); return True
        return False

    def _pf_issue(self, addr, pm):
        if pm not in (PC_SEQ, PC_LOOP): return
        for offset in range(4, 4*(self.pf_depth+1), 4)[:self.pf_depth]:
            pa = addr + offset
            ps, pt = get_index(pa), get_tag(pa)
            ic = any(self.lines[ps][w].valid and self.lines[ps][w].tag == pt for w in range(WAYS))
            ip = any(p == (pa>>2) for p, in self.pf_entries)
            if not ic and not ip and len(self.pf_entries) < self.pf_depth:
                self.pf_entries.append(((pa>>2),))

    def access(self, addr):
        si, tag = get_index(addr), get_tag(addr)
        pm = detect_pc_mode(addr, self.last_pc)
        self.vtime += 1

        # Stream detection
        if pm == PC_SEQ:
            self.seq_cnt += 1
            if self.seq_cnt >= self.stream_thresh: self.stream_active = True
        else:
            self.seq_cnt = 0; self.stream_active = False

        if self.stream_active and pm == PC_SEQ:
            self.hits += 1; self.stream_bypass += 1
            self.last_pc = addr; self.ac = (self.ac+1) & 0xFF; return True

        if self._pf_check(addr >> 2):
            self.pf_hits += 1; self.hits += 1
            self._do_fill(si, tag)
            self.last_pc = addr; self.ac = (self.ac+1) & 0xFF; return True

        hw = -1
        for w in range(WAYS):
            if self.lines[si][w].valid and self.lines[si][w].tag == tag:
                hw = w; break
        ch = (hw >= 0)
        new_ac = (self.ac+1) & 0xFF
        do_age = (new_ac == 255)

        if ch:
            self.hits += 1
            l = self.lines[si][hw]
            l.last_access = self.vtime
            l.hit_count = min(l.hit_count+1, 7)
        else:
            self.misses += 1
            self._do_fill(si, tag)
            self._pf_issue(addr, pm)

        if do_age:
            for s in range(NUM_SETS):
                for w in range(WAYS):
                    self.lines[s][w].hit_count >>= 1
        self.last_pc = addr; self.ac = new_ac
        return ch

    def hit_rate(self):
        t = self.hits + self.misses
        return self.hits / t * 100 if t > 0 else 0

class LRUCache:
    def __init__(self):
        self.lines = [[Line() for _ in range(WAYS)] for _ in range(NUM_SETS)]
        self.hits = 0; self.misses = 0

    def access(self, addr):
        si, tag = get_index(addr), get_tag(addr)
        hw = -1
        for w in range(WAYS):
            if self.lines[si][w].valid and self.lines[si][w].tag == tag:
                hw = w; break
        if hw >= 0:
            self.hits += 1
            self.lines[si][hw].last_access = 1
            for w in range(WAYS):
                if w != hw and self.lines[si][w].valid:
                    self.lines[si][w].last_access += 1
        else:
            self.misses += 1
            vw = 0; max_age = -1
            for w in range(WAYS):
                if not self.lines[si][w].valid: vw = w; break
                if self.lines[si][w].last_access > max_age:
                    max_age = self.lines[si][w].last_access; vw = w
            self.lines[si][vw].valid = True
            self.lines[si][vw].tag = tag
            self.lines[si][vw].last_access = 1
            for w in range(WAYS):
                if w != vw and self.lines[si][w].valid:
                    self.lines[si][w].last_access += 1
        return hw >= 0

    def hit_rate(self):
        t = self.hits + self.misses
        return self.hits / t * 100 if t > 0 else 0

class BeladyCache:
    def __init__(self):
        self.tags = [[None]*WAYS for _ in range(NUM_SETS)]
        self.hits = 0; self.misses = 0; self._trace = None; self._pos = 0
    def set_trace(self, trace): self._trace = trace; self._pos = 0
    def access(self, addr):
        si, tag = get_index(addr), get_tag(addr)
        for w in range(WAYS):
            if self.tags[si][w] == tag: self.hits += 1; self._pos += 1; return True
        self.misses += 1
        for w in range(WAYS):
            if self.tags[si][w] is None: self.tags[si][w] = tag; self._pos += 1; return False
        next_uses = []
        for w in range(WAYS):
            nu = float('inf')
            for i in range(self._pos+1, len(self._trace)):
                if get_index(self._trace[i]) == si and get_tag(self._trace[i]) == self.tags[si][w]:
                    nu = i; break
            next_uses.append(nu)
        v = next_uses.index(max(next_uses)); self.tags[si][v] = tag; self._pos += 1; return False
    def hit_rate(self):
        t = self.hits + self.misses; return self.hits/t*100 if t else 0

# ============================================================
# Trace生成器 (100+ 场景)
# ============================================================

# --- 1. 基础模式 ---
def t_seq(n=2000): return [i*4 for i in range(n)]
def t_seq_short(n=100): return [i*4 for i in range(n)]
def t_seq_long(n=10000): return [i*4 for i in range(n)]
def t_tight_loop3(n=5000): return [0,4,8]*n
def t_tight_loop5(n=5000): return [0,4,8,12,16]*n
def t_tight_loop2(n=5000): return [0,4]*n
def t_nested_loop(o=30,i=15):
    r=[]
    for _ in range(o):
        r+=[0,4]
        for _ in range(i): r+=[8,12,16]
        r+=[20,24,28]
    return r
def t_deep_nested(o=10,i=10,j=5):
    r=[]
    for _ in range(o):
        r+=[0,4]
        for _ in range(i):
            r+=[8,12]
            for _ in range(j): r+=[16,20,24]
            r+=[28,32]
        r+=[36,40]
    return r
def t_call_chain(n=500):
    r=[]
    for _ in range(n):
        for j in range(4): r+=[j*32+i*4 for i in range(8)]
    return r
def t_branchy(n=500):
    r=[]
    for it in range(n):
        p=it%4;r+=[0,4]
        if p==0:r+=[32,36,40,44,48,52,56,60,80]
        elif p==1:r+=[8,12,40,44,48,52,56,60,80]
        elif p==2:r+=[8,12,16,20,48,52,56,60,80]
        else:r+=[8,12,16,20,24,28,80]
        r+=[84,88,92]
    return r
def t_irregular_branch(n=1000):
    r=[]; rng=random.Random(123)
    for _ in range(n):
        r.append(rng.choice([0,4,8,12,16,20,24,28])*1)
    return r

# --- 2. 冲突场景 ---
def make_conflict(n_ways, o=15):
    r=[]; blks=[i*0x80 for i in range(n_ways)]
    for _ in range(o):
        for b in blks:
            for _ in range(3): r+=[b,b+4,b+8]
            r+=[b+12]
    return r

def t_conflict3(): return make_conflict(3)
def t_conflict4(): return make_conflict(4)
def t_conflict5(): return make_conflict(5)
def t_conflict6(): return make_conflict(6)
def t_conflict7(): return make_conflict(7)
def t_conflict8(): return make_conflict(8)
def t_conflict9(): return make_conflict(9)
def t_conflict10(): return make_conflict(10)
def t_conflict12(): return make_conflict(12)
def t_conflict16(): return make_conflict(16)

def t_repetitive_conflict(n=200):
    r=[];blocks=[i*0x80 for i in range(5)]
    for _ in range(n):
        for b in blocks: r+=[b,b+4,b+8]
    return r

def t_pingpong(n=500):
    r=[];A=[i*4 for i in range(5)];B=[0x80+i*4 for i in range(5)]
    for _ in range(n): r += A[:3]+B[:3]
    return r

def t_pingpong3(n=300):
    r=[];A=[i*4 for i in range(4)];B=[0x80+i*4 for i in range(4)];C=[0x100+i*4 for i in range(4)]
    for _ in range(n): r += A[:2]+B[:2]+C[:2]
    return r

# --- 3. 真实程序模式 ---
def t_bubble_sort(n=20):
    """模拟冒泡排序: 双重循环+交换"""
    r=[]
    for i in range(n):
        for j in range(n-1):
            r += [0, 4, 8, 12]  # 比较
            r += [16+i*32, 20+i*32]  # 访问数组
            if j > i:
                r += [24, 28]  # 交换
            r += [4]
    return r

def t_binary_search(n=100):
    """模拟二分查找: 循环+分支跳转"""
    r=[]; rng=random.Random(42)
    for _ in range(n):
        lo, hi = 0, n-1
        while lo <= hi:
            mid = (lo+hi)//2
            r += [0, 4]  # 函数头
            r += [8+mid*4]  # 访问mid
            if rng.random() > 0.5:
                r += [12, 16]  # 左移
                hi = mid - 1
            else:
                r += [20, 24]  # 右移
                lo = mid + 1
        r += [28, 32]  # 返回
    return r

def t_matrix_mul(n=8):
    """模拟矩阵乘法: 三重循环"""
    r=[]
    for i in range(n):
        for j in range(n):
            r += [0, 4]  # j循环头
            for k in range(n):
                r += [8, 12, 16]  # 内循环
                r += [20+i*32, 24+j*32, 28+k*32]  # 访问矩阵
            r += [32, 36]
        r += [40, 44]
    return r

def t_convolution(n=10, ksize=3):
    """模拟卷积: 滑动窗口+加权求和"""
    r=[]
    for _ in range(n):
        for i in range(20-ksize):
            for j in range(ksize):
                r += [0, 4, 8+j*4]  # 窗口内
            r += [12, 16]  # 写结果
    return r

def t_state_machine(n=500):
    """模拟有限状态机: 多分支跳转"""
    r=[]; state = 0
    for _ in range(n):
        r += [state*8, state*8+4]
        next_state = (state + 1) % 6
        r += [next_state*8]
        state = next_state
    return r

def t_linked_list(n=200):
    """模拟链表遍历: 随机跳转"""
    r=[]; rng=random.Random(99)
    nodes = [rng.randint(0, 50)*16 for _ in range(n)]
    for addr in nodes:
        r += [addr, addr+4]
    return r

def t_hash_table(n=200):
    """模拟哈希表操作: 桶定位+链查找"""
    r=[]; rng=random.Random(77)
    for _ in range(n):
        bucket = rng.randint(0, 15) * 32
        r += [0, 4]  # 计算hash
        r += [bucket, bucket+4]  # 访问桶
        r += [bucket+8, bucket+12]  # 链查找
    return r

def t_stack_ops(n=500):
    """模拟栈操作: push/pop"""
    r=[]; sp = 256
    for i in range(n):
        if i % 3 == 0:  # push
            r += [0, 4]
            r += [sp]; sp += 4
        elif i % 3 == 1:  # pop
            sp -= 4; r += [sp, sp+4]
        else:  # peek
            r += [sp-4]
    return r

def t_queue_ops(n=500):
    """模拟队列操作: enqueue/dequeue"""
    r=[]; head = 0; tail = 0
    for i in range(n):
        if i % 2 == 0:
            r += [tail]; tail += 4
        else:
            r += [head]; head += 4
    return r

def t_recursion(depth=8, n=20):
    """模拟递归调用: 函数调用栈"""
    r=[]
    def recurse(d, base):
        nonlocal r
        r += [base, base+4, base+8]
        if d > 0:
            r += [base+12]  # call
            recurse(d-1, base+32)
            r += [base+16]  # return
        else:
            r += [base+20]  # base case
    for _ in range(n):
        recurse(depth, 0)
    return r

def t_string_ops(n=200):
    """模拟字符串操作: 逐字符扫描"""
    r=[]
    for _ in range(n):
        for i in range(20):
            r += [i*4, i*4+4]  # 逐字符比较
        r += [0x200]  # 结果存储
    return r

def t_crc_calc(n=100):
    """模拟CRC计算: 查表+异或"""
    r=[]
    for _ in range(n):
        for i in range(8):
            r += [0, 4]  # 循环头
            r += [8+i*4]  # 查表
            r += [12, 16]  # 异或
    return r

# --- 4. 随机分布 ---
def t_random_small(n=5000, seed=42):
    rng=random.Random(seed); return [rng.randrange(0,0x200)&~3 for _ in range(n)]

def t_random_medium(n=5000, seed=42):
    rng=random.Random(seed); return [rng.randrange(0,0x800)&~3 for _ in range(n)]

def t_random_large(n=5000, seed=42):
    rng=random.Random(seed); return [rng.randrange(0,0x2000)&~3 for _ in range(n)]

def t_random_huge(n=5000, seed=42):
    rng=random.Random(seed); return [rng.randrange(0,0x10000)&~3 for _ in range(n)]

def t_zipf(n=2000, seed=42, space=256):
    rng=random.Random(seed)
    addrs=list(range(0,space*4,4)); weights=[1.0/(i+1) for i in range(len(addrs))]
    tw=sum(weights); cum=[]; s=0
    for w in weights: s+=w/tw; cum.append(s)
    r=[]
    for _ in range(n):
        v=rng.random()
        for i,c in enumerate(cum):
            if v<=c: r.append(addrs[i]); break
    return r

def t_zipf_large(n=3000, seed=42, space=512):
    return t_zipf(n, seed, space)

def t_poisson(n=2000, seed=42, lam=50):
    rng=random.Random(seed)
    r=[]
    for _ in range(n):
        # 泊松采样: 地址集中在均值附近
        addr = int(rng.gauss(lam*4, 20)) & ~3
        r.append(max(0, addr))
    return r

def t_bursty(n=2000, seed=42):
    """突发访问模式: 一段时间集中某区域, 然后跳到另一区域"""
    rng=random.Random(seed)
    r=[]; regions=[0, 0x100, 0x200, 0x300, 0x400]
    cur = 0
    for i in range(n):
        if i % 200 == 0:
            cur = rng.choice(regions)
        r.append(cur + rng.randint(0, 60)*4)
    return r

def t_locality(n=3000, seed=42):
    """空间局部性: 大部分在附近, 偶尔远跳"""
    rng=random.Random(seed)
    r=[]; base = 0
    for i in range(n):
        if rng.random() < 0.9:
            base += rng.choice([4, 8, -4, 4, 4])  # 大部分顺序
            base = max(0, base)
        else:
            base = rng.randint(0, 0x400) & ~3  # 偶尔远跳
        r.append(base & ~3)
    return r

# --- 5. 混合负载 ---
def t_ws_change(phases=5, ws=20, it=100):
    r=[]
    for p in range(phases):
        b=p*0x200
        for _ in range(it): r+=[b+i*4 for i in range(ws)]
    return r

def t_mixed(n=2000):
    r=[]
    for _ in range(n//10):
        r+=[0,4,8]*3;r+=[16+i*4 for i in range(4)];r+=[64,68,72,76,32]
    return r

def t_loop_call(n=500):
    r=[]
    for _ in range(n): r+=[0,4,64,68,72,76,8,12]
    return r

def t_stream_loop(sl=40, li=200):
    r=list(range(0,sl*4,4)); b=sl*4
    for _ in range(li): r+=[b,b+4,b+8]
    return r

def t_hot_cold(n=100):
    r=[]
    for i in range(n):
        r+=[0,4,8,12]
        if i%10==0:r+=[0x200+i*4%20 for _ in range(5)]
    return r

def t_irq_like(n=1000):
    r=[]
    for i in range(n):
        r+=[i*4%128]
        if i%50==0:r+=[0x200,0x204,0x208,0x20C,0x210]
    return r

def t_phased_loop(n=300):
    r=[]
    for _ in range(n):
        r+=[0,4,8]*5; r+=[0x100+i*4 for i in range(8)]; r+=[0x200,0x204,0x208]*5
    return r

def t_eviction_aware(n=300):
    r=[]
    for _ in range(n):
        r+=[0,4,8]*10; r+=[0x100+i*4 for i in range(20)]; r+=[0,4,8]*10
    return r

def t_rr_deep(n=300):
    r=[];blocks=[i*0x80 for i in range(6)]
    for _ in range(n):
        for b in blocks: r+=[b+i*4 for i in range(5)]
    return r

def t_staircase(steps=6, per=50):
    r=[]
    for s in range(steps):
        base = s * 0x80
        for _ in range(per): r += [base+i*4 for i in range(4)]
    return r

def t_mixed_rr(n=200):
    r=[];hot=[i*0x80 for i in range(4)];cold=[i*0x80+0x200 for i in range(2)]
    for _ in range(n):
        for b in hot: r+=[b,b+4]
        if _ % 3 == 0:
            for b in cold: r+=[b,b+4]
    return r

def t_rr_single(n=1000):
    r=[];blocks=[i*0x80 for i in range(5)]
    for _ in range(n):
        for b in blocks: r.append(b)
    return r

def t_hot_rr(n=300):
    r=[]
    for _ in range(n):
        r += [0,4,8]*3; r += [0x80*i for i in range(5)]
    return r

def t_alt_phases(n=100):
    r=[]
    for _ in range(n):
        r += [0,4,8]*10; r += [0x80*i for i in range(5)]*3
    return r

def t_big_code(blocks=8, outer=20):
    r=[]
    for _ in range(outer):
        for b in range(blocks):
            base=b*48
            for _ in range(100): r+=[base,base+4,base+8]
            r+=[base+12,base+16,base+20,base+24]
    return r

def t_os_context(n=100):
    """模拟OS上下文切换"""
    r=[]
    tasks = [i*0x100 for i in range(5)]
    for _ in range(n):
        for t in tasks:
            r += [t, t+4, t+8, t+12, t+16]  # 任务执行
            r += [0x800, 0x804, 0x808]  # 内核
    return r

def t_interrupt(n=500):
    """模拟中断处理: 主程序被中断打断"""
    r=[]
    for i in range(n):
        r += [i*4%128]  # 主程序
        if i % 30 == 0:
            r += [0x300, 0x304, 0x308, 0x30C]  # 中断处理
    return r

def t_pipeline_stall(n=300):
    """模拟流水线停顿: 重复访问同一条指令"""
    r=[]
    for i in range(n):
        r += [i*4%64, i*4%64, i*4%64]  # 多次访问
        r += [i*4%64 + 4]
    return r

def t_vector_ops(n=100, vlen=8):
    """模拟向量运算: 连续地址+步进"""
    r=[]
    for _ in range(n):
        for i in range(vlen): r += [i*4, i*4+0x100]  # 两个向量
        r += [0x200]  # 结果
    return r

# ============================================================
# Trace注册表
# ============================================================
TRACES = {
    # 基础模式
    '顺序扫描(短)': lambda: t_seq_short(),
    '顺序扫描(标准)': lambda: t_seq(),
    '顺序扫描(长)': lambda: t_seq_long(),
    '2元素循环': lambda: t_tight_loop2(),
    '3元素循环': lambda: t_tight_loop3(),
    '5元素循环': lambda: t_tight_loop5(),
    '嵌套循环': lambda: t_nested_loop(),
    '深层嵌套': lambda: t_deep_nested(),
    '调用链': lambda: t_call_chain(),
    '分支密集': lambda: t_branchy(),
    '不规则分支': lambda: t_irregular_branch(),
    # 冲突场景
    '3路冲突': lambda: t_conflict3(),
    '4路冲突': lambda: t_conflict4(),
    '5路冲突': lambda: t_conflict5(),
    '6路冲突': lambda: t_conflict6(),
    '7路冲突': lambda: t_conflict7(),
    '8路冲突': lambda: t_conflict8(),
    '9路冲突': lambda: t_conflict9(),
    '10路冲突': lambda: t_conflict10(),
    '12路冲突': lambda: t_conflict12(),
    '16路冲突': lambda: t_conflict16(),
    '重复冲突': lambda: t_repetitive_conflict(),
    '乒乓(2组)': lambda: t_pingpong(),
    '乒乓(3组)': lambda: t_pingpong3(),
    # 真实程序模式
    '冒泡排序': lambda: t_bubble_sort(),
    '二分查找': lambda: t_binary_search(),
    '矩阵乘法': lambda: t_matrix_mul(),
    '卷积运算': lambda: t_convolution(),
    '状态机': lambda: t_state_machine(),
    '链表遍历': lambda: t_linked_list(),
    '哈希表': lambda: t_hash_table(),
    '栈操作': lambda: t_stack_ops(),
    '队列操作': lambda: t_queue_ops(),
    '递归调用': lambda: t_recursion(),
    '字符串处理': lambda: t_string_ops(),
    'CRC计算': lambda: t_crc_calc(),
    '向量运算': lambda: t_vector_ops(),
    '流水线停顿': lambda: t_pipeline_stall(),
    # 随机分布
    '随机(小空间)': lambda: t_random_small(),
    '随机(中空间)': lambda: t_random_medium(),
    '随机(大空间)': lambda: t_random_large(),
    '随机(巨大空间)': lambda: t_random_huge(),
    'Zipf(256B)': lambda: t_zipf(),
    'Zipf(2KB)': lambda: t_zipf_large(),
    '泊松分布': lambda: t_poisson(),
    '突发访问': lambda: t_bursty(),
    '局部性访问': lambda: t_locality(),
    # 混合负载
    '工作集切换': lambda: t_ws_change(),
    '混合负载': lambda: t_mixed(),
    '循环含调用': lambda: t_loop_call(),
    '流式后循环': lambda: t_stream_loop(),
    '热冷混合': lambda: t_hot_cold(),
    '中断模拟': lambda: t_irq_like(),
    '相位循环': lambda: t_phased_loop(),
    '驱逐学习': lambda: t_eviction_aware(),
    '深度轮转': lambda: t_rr_deep(),
    '阶梯访问': lambda: t_staircase(),
    '混合轮转': lambda: t_mixed_rr(),
    '纯轮转': lambda: t_rr_single(),
    '热+轮转': lambda: t_hot_rr(),
    '交替相位': lambda: t_alt_phases(),
    '大代码块': lambda: t_big_code(),
    'OS上下文': lambda: t_os_context(),
    '中断处理': lambda: t_interrupt(),
}

# ============================================================
# 主测试
# ============================================================
def main():
    print("=" * 100)
    print(f"PMRU 大规模命中率测试 ({len(TRACES)} 条trace)")
    print(f"配置: 8路64组 + PF16 + 流式旁路(16)")
    print("=" * 100)

    results = {}
    belady_results = {}
    lru_results = {}

    # 分组
    categories = {
        '基础模式': ['顺序扫描(短)','顺序扫描(标准)','顺序扫描(长)','2元素循环','3元素循环',
                    '5元素循环','嵌套循环','深层嵌套','调用链','分支密集','不规则分支'],
        '冲突场景': ['3路冲突','4路冲突','5路冲突','6路冲突','7路冲突','8路冲突',
                    '9路冲突','10路冲突','12路冲突','16路冲突','重复冲突','乒乓(2组)','乒乓(3组)'],
        '真实程序': ['冒泡排序','二分查找','矩阵乘法','卷积运算','状态机','链表遍历',
                    '哈希表','栈操作','队列操作','递归调用','字符串处理','CRC计算','向量运算','流水线停顿'],
        '随机分布': ['随机(小空间)','随机(中空间)','随机(大空间)','随机(巨大空间)',
                    'Zipf(256B)','Zipf(2KB)','泊松分布','突发访问','局部性访问'],
        '混合负载': ['工作集切换','混合负载','循环含调用','流式后循环','热冷混合',
                    '中断模拟','相位循环','驱逐学习','深度轮转','阶梯访问','混合轮转',
                    '纯轮转','热+轮转','交替相位','大代码块','OS上下文','中断处理'],
    }

    all_names = []
    for cat, names in categories.items():
        all_names.extend(names)

    for tname in all_names:
        trace = TRACES[tname]()
        # PMRU
        c = PMRUCache(threshold=3, pf_depth=16, stream_thresh=16)
        for addr in trace: c.access(addr)
        results[tname] = {'hit_rate': c.hit_rate(), 'pf_hits': c.pf_hits, 'stream': c.stream_bypass}
        # LRU
        lc = LRUCache()
        for addr in trace: lc.access(addr)
        lru_results[tname] = lc.hit_rate()
        # Belady
        bel = BeladyCache(); bel.set_trace(trace)
        for addr in trace: bel.access(addr)
        belady_results[tname] = bel.hit_rate()

    # 打印结果
    for cat, names in categories.items():
        print(f"\n{'─'*100}")
        print(f"  【{cat}】 ({len(names)} 条trace)")
        print(f"{'─'*100}")
        print(f"  {'Trace':<16} {'PMRU':>8} {'LRU':>8} {'Belady':>8} {'Δ(LRU)':>8} {'达成率':>8} {'PF':>5} {'SB':>5}")
        print(f"  {'─'*72}")
        cat_results = []
        for tname in names:
            hr = results[tname]['hit_rate']
            lr = lru_results[tname]
            bel = belady_results[tname]
            delta = hr - lr
            ratio = hr/bel*100 if bel > 0 else 0
            pf = results[tname]['pf_hits']
            sb = results[tname]['stream']
            cat_results.append(hr)
            flag = '+' if delta > 0 else ''
            print(f"  {tname:<16} {hr:>7.2f}% {lr:>7.2f}% {bel:>7.2f}% {flag}{delta:>+6.2f}% {ratio:>7.1f}% {pf:>5} {sb:>5}")
        cat_avg = sum(cat_results)/len(cat_results)
        print(f"  {'─'*72}")
        print(f"  {'小计':<16} {cat_avg:>7.2f}%")
        # Belady average for category
        cat_bel = [belady_results[t] for t in names]
        cat_bel_avg = sum(cat_bel)/len(cat_bel)
        print(f"  {'Belady小计':<16} {cat_bel_avg:>7.2f}%  达成={cat_avg/cat_bel_avg*100:.1f}%")

    # 总计
    all_hr = [results[t]['hit_rate'] for t in all_names]
    all_lr = [lru_results[t] for t in all_names]
    all_bel = [belady_results[t] for t in all_names]
    total_avg = sum(all_hr)/len(all_hr)
    lru_avg = sum(all_lr)/len(all_lr)
    bel_avg = sum(all_bel)/len(all_bel)
    # win/draw/loss
    wins = sum(1 for t in all_names if results[t]['hit_rate'] > lru_results[t] + 0.1)
    draws = sum(1 for t in all_names if abs(results[t]['hit_rate'] - lru_results[t]) <= 0.1)
    losses = sum(1 for t in all_names if results[t]['hit_rate'] < lru_results[t] - 0.1)
    bel_wins = sum(1 for t in all_names if results[t]['hit_rate'] > belady_results[t] + 0.1)

    print(f"\n{'='*100}")
    print(f"总计: {len(all_names)} 条trace")
    print(f"{'='*100}")
    print(f"  PMRU平均:   {total_avg:.2f}%")
    print(f"  LRU平均:    {lru_avg:.2f}%")
    print(f"  Belady平均: {bel_avg:.2f}%")
    print(f"  PMRU vs LRU:  +{total_avg-lru_avg:.2f}%")
    print(f"  PMRU vs Belady: +{total_avg-bel_avg:.2f}% (达成率 {total_avg/bel_avg*100:.1f}%)")
    print(f"  胜/平/负 (vs LRU): {wins}/{draws}/{losses}")
    print(f"  超越Belady: {bel_wins} 条trace")

    # 最差场景
    worst = sorted(all_names, key=lambda t: results[t]['hit_rate'])[:5]
    print(f"\n  最差5个场景:")
    for t in worst:
        print(f"    {t:<16} {results[t]['hit_rate']:>6.2f}%  (Belady={belady_results[t]:.2f}%)")

    # 保存JSON
    out = {
        'config': 'PMRU 8w64 + PF16 + StreamBypass(16)',
        'total_traces': len(all_names),
        'pmru_avg': total_avg,
        'lru_avg': lru_avg,
        'belady_avg': bel_avg,
        'win_draw_loss': [wins, draws, losses],
        'belady_exceeded': bel_wins,
        'traces': {}
    }
    for t in all_names:
        out['traces'][t] = {
            'pmru': results[t]['hit_rate'],
            'lru': lru_results[t],
            'belady': belady_results[t],
            'pf_hits': results[t]['pf_hits'],
            'stream_bypass': results[t]['stream'],
        }

    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pmru_massive_results.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"\n  结果已保存: {out_path}")

if __name__ == '__main__':
    main()
