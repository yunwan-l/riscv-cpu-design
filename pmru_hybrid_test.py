#!/usr/bin/env python3
"""
PMRU Hybrid: PF16 + Stream Bypass Detection
当检测到流式访问(连续8+ SEQ)时切换为旁路模式, 否则用PF16预取
"""
import random
from dataclasses import dataclass
from typing import List

NUM_SETS = 64; WAYS = 8; TAG_SHIFT = 8

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

@dataclass
class Line:
    valid: bool = False; tag: int = 0
    last_access: int = 0; hit_count: int = 0

class PMRUHybrid:
    def __init__(self, threshold=3, pf_depth=16, stream_threshold=8):
        self.lines = [[Line() for _ in range(WAYS)] for _ in range(NUM_SETS)]
        self.last_pc = 0xFFFFFFFF; self.ac = 0; self.vtime = 0
        self.threshold = threshold
        self.pf_depth = pf_depth
        self.stream_threshold = stream_threshold
        self.pf_entries = []
        self.hits = 0; self.misses = 0; self.pf_hits = 0
        self.stream_bypass = 0
        # stream detection
        self.seq_count = 0; self.stream_active = False

    def _select_victim(self, set_idx):
        ls = self.lines[set_idx]
        for w in range(WAYS):
            if not ls[w].valid: return w
        hit_vals = [ls[w].hit_count for w in range(WAYS)]
        min_hit = min(hit_vals)
        sorted_ways = sorted(range(WAYS), key=lambda w: -ls[w].last_access)
        for w in sorted_ways:
            if ls[w].hit_count - min_hit < self.threshold: return w
        return sorted_ways[0]

    def _do_fill(self, set_idx, tag, pm):
        vw = self._select_victim(set_idx)
        l = self.lines[set_idx][vw]
        l.valid = True; l.tag = tag; l.last_access = self.vtime; l.hit_count = 0

    def _pf_check(self, addr30):
        for i, (pa,) in enumerate(self.pf_entries):
            if pa == addr30:
                self.pf_entries.pop(i)
                return True
        return False

    def _pf_issue(self, addr, pm):
        if pm not in (PC_SEQ, PC_LOOP): return
        for offset in range(4, 4 * (self.pf_depth + 1), 4)[:self.pf_depth]:
            pf_addr = addr + offset
            pf_set = get_index(pf_addr); pf_tag = get_tag(pf_addr)
            in_cache = any(self.lines[pf_set][w].valid and self.lines[pf_set][w].tag == pf_tag for w in range(WAYS))
            in_pf = any(pa == (pf_addr >> 2) for pa, in self.pf_entries)
            if not in_cache and not in_pf and len(self.pf_entries) < self.pf_depth:
                self.pf_entries.append(((pf_addr >> 2),))

    def access(self, addr):
        set_idx = get_index(addr); tag = get_tag(addr)
        pm = detect_pc_mode(addr, self.last_pc)
        self.vtime += 1

        # Stream detection
        if pm == PC_SEQ:
            self.seq_count += 1
            if self.seq_count >= self.stream_threshold:
                self.stream_active = True
        else:
            self.seq_count = 0; self.stream_active = False

        # Stream bypass: don't access cache, just count as hit (BRAM direct)
        if self.stream_active and pm == PC_SEQ:
            self.hits += 1; self.stream_bypass += 1
            self.last_pc = addr; self.ac = (self.ac + 1) & 0xFF
            return True

        # PF hit check
        if self._pf_check(addr >> 2):
            self.pf_hits += 1; self.hits += 1
            self._do_fill(set_idx, tag, pm)
            self.last_pc = addr; self.ac = (self.ac + 1) & 0xFF
            return True

        # Main cache hit
        hit_way = -1
        for w in range(WAYS):
            if self.lines[set_idx][w].valid and self.lines[set_idx][w].tag == tag:
                hit_way = w; break
        ch = (hit_way >= 0)
        new_ac = (self.ac + 1) & 0xFF
        do_age = (new_ac == 255)

        if ch:
            self.hits += 1
            l = self.lines[set_idx][hit_way]
            l.last_access = self.vtime
            l.hit_count = min(l.hit_count + 1, 7)
        else:
            self.misses += 1
            self._do_fill(set_idx, tag, pm)
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

# === Traces (same) ===
def t_seq(n=2000): return [i*4 for i in range(n)]
def t_tight(n=5000): return [0,4,8]*n
def t_nested(o=30,i=15):
    r=[]
    for _ in range(o):
        r+=[0,4]
        for _ in range(i): r+=[8,12,16]
        r+=[20,24,28]
    return r
def t_chain(n=500):
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
def t_conflict3(o=30):
    r=[];A,B,C=0,0x80,0x100
    for _ in range(o):
        for _ in range(10):r+=[A,A+4,A+8]
        r+=[A+12,A+16]
        for _ in range(5):r+=[C,C+4,C+8]
        r+=[C+12,A+20,A+24]
        for _ in range(5):r+=[B,B+4,B+8]
        r+=[B+12,A+28,A+32,A+36]
    return r
def t_conflict4(o=20):
    r=[];blks=[i*0x80 for i in range(4)]
    for _ in range(o):
        for b in blks:
            for _ in range(5):r+=[b,b+4,b+8]
            r+=[b+12]
    return r
def t_conflict5(o=15):
    r=[];blks=[i*0x80 for i in range(5)]
    for _ in range(o):
        for b in blks:
            for _ in range(3):r+=[b,b+4,b+8]
            r+=[b+12]
    return r
def t_conflict6(o=10):
    r=[];blks=[i*0x80 for i in range(6)]
    for _ in range(o):
        for b in blks:
            for _ in range(3):r+=[b,b+4,b+8]
            r+=[b+12]
    return r
def t_ws_change(phases=5,ws=20,it=100):
    r=[]
    for p in range(phases):
        b=p*0x200
        for _ in range(it):r+=[b+i*4 for i in range(ws)]
    return r
def t_mixed(n=2000):
    r=[]
    for _ in range(n//10):
        r+=[0,4,8]*3;r+=[16+i*4 for i in range(4)];r+=[64,68,72,76,32]
    return r
def t_random(n=5000,seed=42):
    rng=random.Random(seed);return[rng.randrange(0,0x800)&~3 for _ in range(n)]
def t_loop_call(n=500):
    r=[]
    for _ in range(n):r+=[0,4,64,68,72,76,8,12]
    return r
def t_stream_loop(sl=40,li=200):
    r=list(range(0,sl*4,4));b=sl*4
    for _ in range(li):r+=[b,b+4,b+8]
    return r
def t_hot_cold(n=100):
    r=[]
    for i in range(n):
        r+=[0,4,8,12]
        if i%10==0:r+=[0x200+i*4%20 for _ in range(5)]
    return r
def t_big_code(blocks=8,outer=20):
    r=[]
    for _ in range(outer):
        for b in range(blocks):
            base=b*48
            for _ in range(100):r+=[base,base+4,base+8]
            r+=[base+12,base+16,base+20,base+24]
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
        r+=[0,4,8]*5
        r+=[0x100+i*4 for i in range(8)]
        r+=[0x200,0x204,0x208]*5
    return r
def t_zipf(n=2000,seed=42):
    rng=random.Random(seed)
    addrs=list(range(0,0x400,4));weights=[1.0/(i+1) for i in range(len(addrs))]
    tw=sum(weights);cum=[];s=0
    for w in weights: s+=w/tw; cum.append(s)
    r=[]
    for _ in range(n):
        v=rng.random()
        for i,c in enumerate(cum):
            if v<=c: r.append(addrs[i]); break
    return r
def t_repetitive_conflict(n=200):
    r=[];blocks=[i*0x80 for i in range(5)]
    for _ in range(n):
        for b in blocks: r+=[b,b+4,b+8]
    return r
def t_eviction_aware(n=300):
    r=[]
    for _ in range(n):
        r+=[0,4,8]*10
        r+=[0x100+i*4 for i in range(20)]
        r+=[0,4,8]*10
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
        for _ in range(per):
            r += [base+i*4 for i in range(4)]
    return r
def t_pingpong(n=500):
    r=[];A=[i*4 for i in range(5)];B=[0x80+i*4 for i in range(5)]
    for _ in range(n):
        r += A[:3] + B[:3]
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
        r += [0,4,8]*3
        r += [0x80*i for i in range(5)]
    return r
def t_alt_phases(n=100):
    r=[]
    for _ in range(n):
        r += [0,4,8]*10
        r += [0x80*i for i in range(5)]*3
    return r

TRACES = {
    '顺序扫描': t_seq,'紧循环': t_tight,'嵌套循环': t_nested,'调用链': t_chain,
    '分支密集': t_branchy,'3路冲突': t_conflict3,'4路冲突': t_conflict4,'5路冲突': t_conflict5,
    '6路冲突': t_conflict6,'工作集切换': t_ws_change,'混合负载': t_mixed,'随机访问': t_random,
    '循环含调用': t_loop_call,'流式后循环': t_stream_loop,'热冷混合': t_hot_cold,'大代码块': t_big_code,
    '中断模拟': t_irq_like,'相位循环': t_phased_loop,'Zipf分布': t_zipf,
    '重复冲突': t_repetitive_conflict,'驱逐学习': t_eviction_aware,
    '深度轮转': t_rr_deep,'阶梯访问': t_staircase,'乒乓冲突': t_pingpong,'混合轮转': t_mixed_rr,
    '纯轮转': t_rr_single,'热+轮转': t_hot_rr,'交替相位': t_alt_phases,
}

def main():
    configs = [
        ('PF4 (baseline)',     4,  999),  # no stream bypass
        ('PF8',                8,  999),
        ('PF16',              16,  999),
        ('PF16+Stream(8)',    16,    8),  # stream bypass after 8 SEQ
        ('PF16+Stream(4)',    16,    4),  # stream bypass after 4 SEQ
        ('PF16+Stream(16)',   16,   16),  # stream bypass after 16 SEQ
        ('PF8+Stream(8)',      8,    8),  # PF8 + stream
        ('PF32',             32,  999),  # extreme prefetch
        ('PF16+Stream(8) best',16,  8),  # duplicate for emphasis
    ]

    print("=" * 120)
    print("PMRU Hybrid: PF + Stream Bypass")
    print("=" * 120)

    all_results = {}
    for name, pf_depth, stream_thresh in configs:
        results = {}
        for tname, tfunc in TRACES.items():
            trace = tfunc()
            c = PMRUHybrid(threshold=3, pf_depth=pf_depth, stream_threshold=stream_thresh)
            for addr in trace:
                c.access(addr)
            results[tname] = {
                'hit_rate': c.hit_rate(),
                'pf_hits': c.pf_hits,
                'stream_bypass': c.stream_bypass,
            }
        avg = sum(r['hit_rate'] for r in results.values()) / len(results)
        all_results[name] = (avg, results)

    # Summary
    print(f"\n{'Config':<25} {'Avg HR':>8} {'Δ':>8}  {'PF_hits':>8} {'Stream':>8}")
    print("-" * 65)
    base_avg = all_results['PF4 (baseline)'][0]
    for name, _, _ in configs:
        avg, results = all_results[name]
        total_pf = sum(results[t]['pf_hits'] for t in TRACES)
        total_stream = sum(results[t]['stream_bypass'] for t in TRACES)
        diff = avg - base_avg
        flag = '+' if diff > 0.01 else ('' if abs(diff) <= 0.01 else '-')
        print(f"  {name:<23} {avg:>7.2f}% {flag}{diff:>+7.2f}%  {total_pf:>8d} {total_stream:>8d}")

    # Per-trace for best configs
    print(f"\n{'='*120}")
    print("Per-Trace (key configs)")
    print(f"{'='*120}")
    key = ['PF4 (baseline)', 'PF16', 'PF16+Stream(8)', 'PF16+Stream(4)', 'PF8+Stream(8)']
    header = f"{'Trace':<12}"
    for cn in key:
        header += f" | {cn:>18}"
    print(header)
    print("-" * len(header))
    for tname in TRACES:
        row = f"{tname:<12}"
        for cn in key:
            hr = all_results[cn][1][tname]['hit_rate']
            row += f" | {hr:>17.2f}%"
        print(row)
    print("-" * len(header))
    avg_row = f"{'平均':<12}"
    for cn in key:
        avg_row += f" | {all_results[cn][0]:>17.2f}%"
    print(avg_row)

    # Best config detail
    best_name = max(all_results.keys(), key=lambda k: all_results[k][0])
    best_avg, best_results = all_results[best_name]
    print(f"\n{'='*80}")
    print(f"最优配置: {best_name}")
    print(f"平均命中率: {best_avg:.2f}%  (vs baseline {base_avg:.2f}%, +{best_avg-base_avg:.2f}%)")
    print(f"{'='*80}")
    print(f"  {'Trace':<12} {'HR':>8} {'PF_hits':>8} {'Stream':>8}")
    for tname in TRACES:
        r = best_results[tname]
        print(f"  {tname:<12} {r['hit_rate']:>7.2f}% {r['pf_hits']:>8d} {r['stream_bypass']:>8d}")

if __name__ == '__main__':
    main()
