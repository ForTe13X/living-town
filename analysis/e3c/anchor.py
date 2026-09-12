import sys, json, statistics
sys.stdout.reconfigure(encoding='utf-8')

# Core-goods held-out anchor for E3c. Since E3b is now baseline, 糕点 joins the
# core three (口粮/柴薪/屋瓦) as a "must stay basically flat" good.
CORE = ['口粮','柴薪','屋瓦','糕点']

def load(p):
    r=[]
    for l in open(p,encoding='utf-8'):
        l=l.strip()
        if l.startswith('[SCALE]'): l=l[8:]
        if l:
            try: r.append(json.loads(l))
            except: pass
    return {x['seed']:x for x in r}

base=load(sys.argv[1])
after=load(sys.argv[2])
seeds=sorted(set(base)&set(after))
print("=== CORE-GOODS ANCHOR: %d held-out seeds %s ===" % (len(seeds), sys.argv[3] if len(sys.argv)>3 else ''))
print("base=%s  after=%s"%(sys.argv[1], sys.argv[2]))
for good in CORE:
    deltas=[]; downs=0; ups=0; flat=0
    br=[]; ar=[]
    for sd in seeds:
        gb=base[sd]['final']['goods'].get(good); ga=after[sd]['final']['goods'].get(good)
        if gb is None or ga is None: continue
        b=gb['rate']; a=ga['rate']; d=a-b
        deltas.append(d); br.append(b); ar.append(a)
        if d<-0.001: downs+=1
        elif d>0.001: ups+=1
        else: flat+=1
    if not deltas:
        print("%s: (no data)"%good); continue
    med=statistics.median(deltas); mean=statistics.mean(deltas)
    bmed=statistics.median(br); amed=statistics.median(ar)
    print("%s: median dRate=%+.4f  mean d=%+.4f | base med=%.3f after med=%.3f | down/up/flat = %d/%d/%d of %d" % (
        good, med, mean, bmed, amed, downs, ups, flat, len(deltas)))
print("--- per-seed d (口粮/柴薪/屋瓦/糕点) ---")
for sd in seeds:
    ds=[]
    for g in CORE:
        gb=base[sd]['final']['goods'].get(g); ga=after[sd]['final']['goods'].get(g)
        ds.append((ga['rate']-gb['rate']) if (gb and ga) else float('nan'))
    print("  seed %2d: %+.3f %+.3f %+.3f %+.3f" % (sd, ds[0], ds[1], ds[2], ds[3]))
