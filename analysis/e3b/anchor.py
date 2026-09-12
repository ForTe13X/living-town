import sys, json, statistics
sys.stdout.reconfigure(encoding='utf-8')

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
print("=== CORE-THREE ANCHOR: %d held-out seeds %s ===" % (len(seeds), sys.argv[3] if len(sys.argv)>3 else ''))
print("base=%s  after=%s"%(sys.argv[1], sys.argv[2]))
for good in ['口粮','柴薪','屋瓦']:
    deltas=[]; downs=0; ups=0; flat=0
    br=[]; ar=[]
    for sd in seeds:
        b=base[sd]['final']['goods'][good]['rate']
        a=after[sd]['final']['goods'][good]['rate']
        d=a-b
        deltas.append(d); br.append(b); ar.append(a)
        if d<-0.001: downs+=1
        elif d>0.001: ups+=1
        else: flat+=1
    med=statistics.median(deltas)
    mean=statistics.mean(deltas)
    bmed=statistics.median(br); amed=statistics.median(ar)
    print("%s: median Δrate=%+.4f  mean Δ=%+.4f | base med=%.3f after med=%.3f | down/up/flat = %d/%d/%d of %d" % (
        good, med, mean, bmed, amed, downs, ups, flat, len(seeds)))
# per-seed core-3 combined direction
print("--- per-seed Δ (口粮/柴薪/屋瓦) ---")
for sd in seeds:
    ds=[after[sd]['final']['goods'][g]['rate']-base[sd]['final']['goods'][g]['rate'] for g in ['口粮','柴薪','屋瓦']]
    print("  seed %2d: %+.3f %+.3f %+.3f" % (sd, ds[0], ds[1], ds[2]))
