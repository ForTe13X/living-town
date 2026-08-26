import sys, json
sys.stdout.reconfigure(encoding='utf-8')

# E5a #40 R1 upper-arm ("缺货绝迹" / glut) probe, per seed, both arms (docs/171).
# R1 (Invariants.gd ~929-949): a seed trips the upper arm when the count of gated goods that were
# never short all year satisfies  never_short * 2 > gated_n  (strict town-wide majority not short).
# At N=12 seeds 1-12 the clean tree has margin = 1 good (max never_short = 3, threshold = 4).
# The mechanic keeps ① (the shortage EVENT) so 糕点 still shorts -> 糕点 is NOT the casualty;
# the trip comes from OTHER goods (屋瓦...) whose consumption shifts once 糕点's reputation churn
# is removed. #40 is a SOFT invariant with a fixed >=11/12 gate, independent of golden rebake.
# Usage: python inv40.py <base.jsonl> <with.jsonl> [lo] [hi]

def load(p):
    d={}
    for l in open(p,encoding='utf-8'):
        l=l.strip()
        if l.startswith('[SCALE]'): l=l[8:]
        if l:
            try:
                r=json.loads(l); d[r['seed']]=r
            except: pass
    return d

def r1(rec):
    goods=rec['final']['goods']
    gated=[g for g,v in goods.items() if v.get('gated')]
    ns=sorted(g for g in gated if goods[g].get('shortage_days',0)==0)
    return len(gated), ns, (len(ns)*2 > len(gated))

base=load(sys.argv[1]); after=load(sys.argv[2])
lo=int(sys.argv[3]) if len(sys.argv)>3 else 1
hi=int(sys.argv[4]) if len(sys.argv)>4 else 12
seeds=[s for s in sorted(set(base)&set(after)) if lo<=s<=hi]
print("=== E5a #40 upper-arm (缺货绝迹) seeds %d-%d ===" % (lo,hi))
bt=wt=0
for sd in seeds:
    gb,nb,tb=r1(base[sd]); gw,nw,tw=r1(after[sd])
    bt+=tb; wt+=tw
    print("seed %2d | BASE gated=%d never_short=%d %-28s %s | WITH gated=%d never_short=%d %-28s %s"%(
        sd, gb, len(nb), '['+','.join(nb)+']', 'TRIP' if tb else 'ok',
        gw, len(nw), '['+','.join(nw)+']', 'TRIP' if tw else 'ok'))
print("--- #40 [soft] pass:  BASE %d/%d   WITH %d/%d   (soft gate needs >=11/12) ---"%(
    len(seeds)-bt,len(seeds), len(seeds)-wt,len(seeds)))
# confirm ① preserved: 糕点 still shorts in both arms
bad=[sd for sd in seeds if after[sd]['final']['goods'].get('糕点',{}).get('shortage_days',0)==0]
print("--- ① check: 糕点 shortage_days==0 (would be a dropped-event bug) in WITH seeds: %s ---"%(bad or 'none'))
