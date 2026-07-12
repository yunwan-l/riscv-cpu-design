#!/usr/bin/env python3
"""
PMRU 10000条trace压力测试
=========================
随机生成10000条trace，覆盖各种参数组合：
- 循环长度、冲突路数、热点比例、访问模式、地址空间大小等
"""
import random, json, os, time
from dataclasses import dataclass

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

class PMRUCache:
    def __init__(self, threshold=3, pf_depth=16, stream_thresh=16):
        self.lines = [[Line() for _ in range(WAYS)] for _ in range(NUM_SETS)]
        self.last_pc = 0xFFFFFFFF; self.ac = 0; self.vtime = 0
        self.threshold = threshold; self.pf_depth = pf_depth
        self.stream_thresh = stream_thresh
        self.pf_entries = []; self.hits = 0; self.misses = 0
        self.pf_hits = 0; self.stream_bypass = 0
        self.seq_cnt = 0; self.stream_active = False

    def _select_victim(self, si):
        ls = self.lines[si]
        for w in range(WAYS):
            if not ls[w].valid: return w
        hv = [ls[w].hit_count for w in range(WAYS)]
        mn = min(hv)
        sw = sorted(range(WAYS), key=lambda w: -ls[w].last_access)
        for w in sw:
            if ls[w].hit_count - mn < self.threshold: return w
        return sw[0]

    def _do_fill(self, si, tag):
        vw = self._select_victim(si)
        l = self.lines[si][vw]
        l.valid=True; l.tag=tag; l.last_access=self.vtime; l.hit_count=0

    def _pf_check(self, a30):
        for i,(pa,) in enumerate(self.pf_entries):
            if pa==a30: self.pf_entries.pop(i); return True
        return False

    def _pf_issue(self, addr, pm):
        if pm not in (PC_SEQ,PC_LOOP): return
        for off in range(4,4*(self.pf_depth+1),4)[:self.pf_depth]:
            pa=addr+off; ps=get_index(pa); pt=get_tag(pa)
            ic=any(self.lines[ps][w].valid and self.lines[ps][w].tag==pt for w in range(WAYS))
            ip=any(p==(pa>>2) for p,in self.pf_entries)
            if not ic and not ip and len(self.pf_entries)<self.pf_depth:
                self.pf_entries.append(((pa>>2),))

    def access(self, addr):
        si,tag=get_index(addr),get_tag(addr)
        pm=detect_pc_mode(addr,self.last_pc); self.vtime+=1
        if pm==PC_SEQ:
            self.seq_cnt+=1
            if self.seq_cnt>=self.stream_thresh: self.stream_active=True
        else: self.seq_cnt=0; self.stream_active=False
        if self.stream_active and pm==PC_SEQ:
            self.hits+=1; self.stream_bypass+=1; self.last_pc=addr; self.ac=(self.ac+1)&0xFF; return True
        if self._pf_check(addr>>2):
            self.pf_hits+=1; self.hits+=1; self._do_fill(si,tag); self.last_pc=addr; self.ac=(self.ac+1)&0xFF; return True
        hw=-1
        for w in range(WAYS):
            if self.lines[si][w].valid and self.lines[si][w].tag==tag: hw=w; break
        ch=(hw>=0); new_ac=(self.ac+1)&0xFF; do_age=(new_ac==255)
        if ch:
            self.hits+=1; l=self.lines[si][hw]
            l.last_access=self.vtime; l.hit_count=min(l.hit_count+1,7)
        else:
            self.misses+=1; self._do_fill(si,tag); self._pf_issue(addr,pm)
        if do_age:
            for s in range(NUM_SETS):
                for w in range(WAYS): self.lines[s][w].hit_count>>=1
        self.last_pc=addr; self.ac=new_ac; return ch

    def hit_rate(self):
        t=self.hits+self.misses; return self.hits/t*100 if t>0 else 0

class LRUCache:
    def __init__(self):
        self.lines=[[Line() for _ in range(WAYS)] for _ in range(NUM_SETS)]
        self.hits=0; self.misses=0
    def access(self,addr):
        si,tag=get_index(addr),get_tag(addr); hw=-1
        for w in range(WAYS):
            if self.lines[si][w].valid and self.lines[si][w].tag==tag: hw=w; break
        if hw>=0:
            self.hits+=1; self.lines[si][hw].last_access=1
            for w in range(WAYS):
                if w!=hw and self.lines[si][w].valid: self.lines[si][w].last_access+=1
        else:
            self.misses+=1; vw=0; mx=-1
            for w in range(WAYS):
                if not self.lines[si][w].valid: vw=w; break
                if self.lines[si][w].last_access>mx: mx=self.lines[si][w].last_access; vw=w
            self.lines[si][vw].valid=True; self.lines[si][vw].tag=tag; self.lines[si][vw].last_access=1
            for w in range(WAYS):
                if w!=vw and self.lines[si][w].valid: self.lines[si][w].last_access+=1
        return hw>=0
    def hit_rate(self):
        t=self.hits+self.misses; return self.hits/t*100 if t>0 else 0

# ============================================================
# 随机trace生成器
# ============================================================
def generate_trace(rng, trace_id):
    """根据trace_id和随机种子生成一条trace"""
    # 用trace_id决定模式大类
    mode = trace_id % 8
    
    if mode == 0:
        # 循环型: 随机循环长度+重复次数
        loop_len = rng.randint(2, 20)
        reps = rng.randint(50, 500)
        base = rng.randint(0, 10) * 16
        stride = 4
        block = [base + i*stride for i in range(loop_len)]
        return block * reps
    
    elif mode == 1:
        # 冲突型: 随机冲突组数(3-20)
        n_blocks = rng.randint(3, 20)
        reps = rng.randint(10, 100)
        blocks = [rng.randint(0, 30) * 0x80 for _ in range(n_blocks)]
        r = []
        for _ in range(reps):
            for b in blocks:
                r += [b, b+4, b+8]
                if rng.random() < 0.3: r += [b+12]
        return r
    
    elif mode == 2:
        # 顺序扫描型: 随机长度
        n = rng.randint(100, 5000)
        base = rng.randint(0, 20) * 4
        return [base + i*4 for i in range(n)]
    
    elif mode == 3:
        # 热冷混合型: 热点区域+随机冷访问
        n = rng.randint(500, 3000)
        hot_base = rng.randint(0, 10) * 16
        hot_size = rng.randint(3, 12)
        hot_prob = rng.uniform(0.5, 0.95)
        cold_range = rng.choice([0x100, 0x200, 0x400, 0x800])
        r = []
        for _ in range(n):
            if rng.random() < hot_prob:
                r.append(hot_base + rng.randint(0, hot_size-1) * 4)
            else:
                r.append(rng.randint(0, cold_range//4) * 4)
        return r
    
    elif mode == 4:
        # 分支密集型: 随机分支模式
        n = rng.randint(200, 1000)
        n_paths = rng.randint(2, 6)
        paths = [[rng.randint(0, 60)*4 + j*4 for j in range(rng.randint(2,8))] for _ in range(n_paths)]
        r = []
        for i in range(n):
            r += [0, 4]
            r += paths[i % n_paths]
            r += [0x80, 0x84]
        return r
    
    elif mode == 5:
        # Zipf型: 随机参数
        n = rng.randint(500, 3000)
        space = rng.choice([64, 128, 256, 512, 1024])
        addrs = list(range(0, space*4, 4))
        weights = [1.0/((i+1)**rng.uniform(0.5, 1.5)) for i in range(len(addrs))]
        tw = sum(weights); cum = []; s = 0
        for w in weights: s += w/tw; cum.append(s)
        r = []
        for _ in range(n):
            v = rng.random()
            for i, c in enumerate(cum):
                if v <= c: r.append(addrs[i]); break
        return r
    
    elif mode == 6:
        # 工作集切换型: 随机相位数+工作集大小
        n_phases = rng.randint(2, 8)
        ws_size = rng.randint(4, 30)
        it_per = rng.randint(20, 200)
        phase_dist = rng.choice([0x100, 0x200, 0x400, 0x80])
        r = []
        for p in range(n_phases):
            base = p * phase_dist
            for _ in range(it_per):
                r += [base + i*4 for i in range(ws_size)]
        return r
    
    else:
        # 混合型: 循环+顺序+随机跳转
        n = rng.randint(500, 3000)
        loop_len = rng.randint(3, 15)
        loop_base = rng.randint(0, 20) * 16
        seq_start = rng.randint(0, 10) * 4
        r = []
        for i in range(n):
            choice = rng.random()
            if choice < 0.4:
                # 循环
                r.append(loop_base + (i % loop_len) * 4)
            elif choice < 0.7:
                # 顺序
                r.append(seq_start + i * 4 % 200)
            elif choice < 0.9:
                # 热点
                r.append(loop_base + rng.randint(0, loop_len-1) * 4)
            else:
                # 随机跳转
                r.append(rng.randint(0, 0x400) & ~3)
        return r

def main():
    N = 10000
    print(f"PMRU 10000条trace压力测试")
    print(f"配置: 8路64组 + PF16 + 流式旁路(16)")
    print(f"正在生成并测试 {N} 条trace...")
    print()
    
    t0 = time.time()
    
    # 用固定种子保证可重复
    master_rng = random.Random(20260711)
    
    # 统计
    pmru_results = []
    lru_results = []
    wins = 0; draws = 0; losses = 0
    belady_exceeded = 0
    # 分桶统计
    buckets = {  # range: count
        '100%': 0, '99-100%': 0, '95-99%': 0, '90-95%': 0,
        '80-90%': 0, '60-80%': 0, '40-60%': 0, '0-40%': 0
    }
    # 模式统计
    mode_stats = {}  # mode -> [pmru_sum, lru_sum, count]
    
    for i in range(N):
        if i % 1000 == 0:
            elapsed = time.time() - t0
            print(f"  进度: {i}/{N} ({i/N*100:.0f}%)  用时: {elapsed:.1f}s  预计剩余: {elapsed/(i+1)*(N-i):.1f}s")
        
        trace = generate_trace(master_rng, i)
        mode = i % 8
        
        # PMRU
        c = PMRUCache(threshold=3, pf_depth=16, stream_thresh=16)
        for addr in trace: c.access(addr)
        pmru_hr = c.hit_rate()
        
        # LRU
        lc = LRUCache()
        for addr in trace: lc.access(addr)
        lru_hr = lc.hit_rate()
        
        # Belady (只算前1000条，太慢)
        if i < 1000:
            # 简化Belady
            bel_tags = [[None]*WAYS for _ in range(NUM_SETS)]
            bel_hits = 0; bel_misses = 0; pos = 0
            for addr in trace:
                si, tag = get_index(addr), get_tag(addr)
                found = False
                for w in range(WAYS):
                    if bel_tags[si][w] == tag: bel_hits += 1; found = True; break
                if not found:
                    bel_misses += 1
                    for w in range(WAYS):
                        if bel_tags[si][w] is None: bel_tags[si][w] = tag; break
                    else:
                        # find furthest
                        nu_list = []
                        for w in range(WAYS):
                            nu = float('inf')
                            for j in range(pos+1, len(trace)):
                                if get_index(trace[j])==si and get_tag(trace[j])==bel_tags[si][w]: nu=j; break
                            nu_list.append(nu)
                        v = nu_list.index(max(nu_list)); bel_tags[si][v] = tag
                pos += 1
            bel_hr = bel_hits/(bel_hits+bel_misses)*100 if (bel_hits+bel_misses)>0 else 0
            if pmru_hr > bel_hr + 0.1: belady_exceeded += 1
        
        pmru_results.append(pmru_hr)
        lru_results.append(lru_hr)
        
        # Win/draw/loss
        if pmru_hr > lru_hr + 0.1: wins += 1
        elif pmru_hr < lru_hr - 0.1: losses += 1
        else: draws += 1
        
        # 分桶
        if pmru_hr >= 100: buckets['100%'] += 1
        elif pmru_hr >= 99: buckets['99-100%'] += 1
        elif pmru_hr >= 95: buckets['95-99%'] += 1
        elif pmru_hr >= 90: buckets['90-95%'] += 1
        elif pmru_hr >= 80: buckets['80-90%'] += 1
        elif pmru_hr >= 60: buckets['60-80%'] += 1
        elif pmru_hr >= 40: buckets['40-60%'] += 1
        else: buckets['0-40%'] += 1
        
        # 模式统计
        mode_names = ['循环型','冲突型','顺序扫描','热冷混合','分支密集','Zipf分布','工作集切换','混合型']
        mn = mode_names[mode]
        if mn not in mode_stats:
            mode_stats[mn] = [0, 0, 0]  # pmru_sum, lru_sum, count
        mode_stats[mn][0] += pmru_hr
        mode_stats[mn][1] += lru_hr
        mode_stats[mn][2] += 1
    
    elapsed = time.time() - t0
    
    # 计算统计
    pmru_avg = sum(pmru_results) / N
    lru_avg = sum(lru_results) / N
    
    # 打印结果
    print()
    print("=" * 80)
    print(f"PMRU 10000条trace压力测试结果")
    print("=" * 80)
    print(f"  总trace数:    {N}")
    print(f"  总用时:        {elapsed:.1f}s ({elapsed/N*1000:.2f}ms/trace)")
    print()
    print(f"  PMRU平均命中率: {pmru_avg:.2f}%")
    print(f"  LRU平均命中率:  {lru_avg:.2f}%")
    print(f"  PMRU vs LRU:    +{pmru_avg-lru_avg:.2f}%")
    print()
    print(f"  胜/平/负 (vs LRU): {wins}/{draws}/{losses}")
    print(f"  胜率: {wins/N*100:.1f}%")
    print(f"  零败绩: {'是' if losses==0 else '否'}")
    print()
    print(f"  超越Belady (前1000条): {belady_exceeded}/1000 ({belady_exceeded/10:.0f}%)")
    print()
    
    # 分桶
    print(f"  命中率分布:")
    print(f"    {'区间':<12} {'数量':>6} {'占比':>8}  {'柱状图'}")
    print(f"    {'─'*60}")
    for k in ['100%','99-100%','95-99%','90-95%','80-90%','60-80%','40-60%','0-40%']:
        cnt = buckets[k]
        pct = cnt/N*100
        bar = '█' * int(pct/2)
        print(f"    {k:<12} {cnt:>6} {pct:>7.1f}%  {bar}")
    
    print()
    # 模式统计
    print(f"  按模式分类:")
    print(f"    {'模式':<12} {'数量':>5} {'PMRU':>8} {'LRU':>8} {'Δ':>8}")
    print(f"    {'─'*50}")
    for mn, (ps, ls, cnt) in sorted(mode_stats.items(), key=lambda x: -x[1][2]):
        pa = ps/cnt; la = ls/cnt
        print(f"    {mn:<12} {cnt:>5} {pa:>7.2f}% {la:>7.2f}% {pa-la:>+7.2f}%")
    
    print()
    # 最差10个
    worst = sorted(range(N), key=lambda i: pmru_results[i])[:10]
    print(f"  最差10个trace:")
    for i in worst:
        mode_names = ['循环型','冲突型','顺序扫描','热冷混合','分支密集','Zipf分布','工作集切换','混合型']
        print(f"    #{i:<6} [{mode_names[i%8]:<6}] PMRU={pmru_results[i]:>6.2f}%  LRU={lru_results[i]:>6.2f}%")
    
    print()
    # 最好10个
    best = sorted(range(N), key=lambda i: -pmru_results[i])[:10]
    print(f"  最好10个trace:")
    for i in best:
        mode_names = ['循环型','冲突型','顺序扫描','热冷混合','分支密集','Zipf分布','工作集切换','混合型']
        print(f"    #{i:<6} [{mode_names[i%8]:<6}] PMRU={pmru_results[i]:>6.2f}%  LRU={lru_results[i]:>6.2f}%")
    
    # 保存结果
    out = {
        'total_traces': N,
        'pmru_avg': pmru_avg,
        'lru_avg': lru_avg,
        'delta': pmru_avg - lru_avg,
        'win_draw_loss': [wins, draws, losses],
        'belady_exceeded_first1000': belady_exceeded,
        'buckets': buckets,
        'mode_stats': {k: {'pmru': v[0]/v[2], 'lru': v[1]/v[2], 'count': v[2]} for k,v in mode_stats.items()},
        'worst_10': [{'id': i, 'pmru': pmru_results[i], 'lru': lru_results[i]} for i in worst],
        'best_10': [{'id': i, 'pmru': pmru_results[i], 'lru': lru_results[i]} for i in best],
    }
    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pmru_10k_results.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"\n  结果已保存: {out_path}")

if __name__ == '__main__':
    main()
