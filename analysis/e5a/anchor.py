import sys, json, statistics, math
sys.stdout.reconfigure(encoding='utf-8')

# E5a core-goods held-out anchor — THE verdict on the shortage-gossip gate (docs/171).
# Mechanic: goods with `no_shortage_gossip:true` still write the #40 shortage EVENT (①) and the
# actor's private memory (②), but skip the SH:<good> belief insertion (③) and the standing dent
# on the producer (④). Baton 1 flags 糕点 ONLY.
#   Prediction (from docs/170's reading): suppressing a churn source should keep core FLAT-or-UP
#   (口粮 was +0.041 WITH gossip in E3b). Require >= neutral, NOT E4d-B's -0.045.
# STOP-CLAUSE: if core DEGRADES (leans below neutral) -> the cut-point OUTCOME prediction is wrong,
#   report/escalate. (Also a hard #40 12/12 constraint lives in analysis/e5a/inv40.py.)
CORE = ['口粮','柴薪','屋瓦','糕点','整洁']

def load(p):
    r={}
    for l in open(p,encoding='utf-8'):
        l=l.strip()
        if l.startswith('[SCALE]'): l=l[8:]
        if l:
            try:
                x=json.loads(l); r[x['seed']]=x
            except: pass
    return r

base=load(sys.argv[1]); after=load(sys.argv[2])
lo=int(sys.argv[3]) if len(sys.argv)>3 else 13
hi=int(sys.argv[4]) if len(sys.argv)>4 else 30
seeds=[s for s in sorted(set(base)&set(after)) if lo<=s<=hi]
# two-sided t critical for df up to ~30
TCRIT={9:2.262,10:2.228,11:2.201,12:2.179,15:2.131,17:2.110,18:2.101,19:2.093,20:2.086,25:2.060,29:2.045}
print("=== E5a CORE-GOODS ANCHOR: %d held-out seeds %d-%d ===" % (len(seeds),lo,hi))
print("base=%s  after(flag ON 糕点)=%s" % (sys.argv[1], sys.argv[2]))
print("good | mean d | 95%% CI(t) | median | down/up/flat | |down|/|up| avg | verdict")
for good in CORE:
    ds=[]
    for sd in seeds:
        gb=base[sd]['final']['goods'].get(good); ga=after[sd]['final']['goods'].get(good)
        if gb and ga: ds.append(ga['rate']-gb['rate'])
    if not ds:
        print("%s: (no data)"%good); continue
    n=len(ds); m=statistics.mean(ds); md=statistics.median(ds)
    sd_=statistics.stdev(ds) if n>1 else 0.0
    tc=TCRIT.get(n-1, 2.1); ci=tc*sd_/math.sqrt(n)
    downs=[x for x in ds if x<-0.001]; ups=[x for x in ds if x>0.001]; flat=n-len(downs)-len(ups)
    dmag=statistics.mean([abs(x) for x in downs]) if downs else 0.0
    umag=statistics.mean(ups) if ups else 0.0
    if (m-ci)>0: v="SIG UP"
    elif (m+ci)<0: v="SIG DOWN"
    elif m<-0.001: v="n.s.(leans down)"
    elif m>0.001: v="n.s.(leans up)"
    else: v="flat"
    print("%-3s | %+.4f | [%+.4f,%+.4f] | %+.4f | %d/%d/%d | %.3f/%.3f | %s" % (
        good,m,m-ci,m+ci,md,len(downs),len(ups),flat,dmag,umag,v))
print("--- per-seed d (口粮/柴薪/屋瓦/糕点/整洁) ---")
for sd in seeds:
    ds=[]
    for g in CORE:
        gb=base[sd]['final']['goods'].get(g); ga=after[sd]['final']['goods'].get(g)
        ds.append((ga['rate']-gb['rate']) if (gb and ga) else float('nan'))
    print("  seed %2d: %+.3f %+.3f %+.3f %+.3f %+.3f" % (sd, ds[0],ds[1],ds[2],ds[3],ds[4]))
