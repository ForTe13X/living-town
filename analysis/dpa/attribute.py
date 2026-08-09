import sys, json, statistics, math
sys.stdout.reconfigure(encoding='utf-8')
# DP-A attribution: reads clean/with/dpa run jsonls, computes CORE held-out Δ vs CLEAN, and the paired
# per-seed recovery of DP-A vs WITH. Prediction (E7 docs/174): DP-A reroutes the ④ standing leak into a
# decision-inert grievance field, so DP-A should reproduce arm1's ≈-0.0001 core-neutral 口粮 and recover
# +~0.048 vs WITH (SIG UP). Usage: python attribute.py <clean.jsonl> <with.jsonl> <dpa.jsonl> [lo] [hi]
CORE=['口粮','柴薪','屋瓦','糕点','整洁']
TCRIT={8:2.306,9:2.262,10:2.228,11:2.201,12:2.179,13:2.160,14:2.145,15:2.131,16:2.120,
       17:2.110,18:2.101,19:2.093,20:2.086,24:2.064,25:2.060,29:2.045,30:2.042}
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
clean=load(sys.argv[1]); with_=load(sys.argv[2]); dpa=load(sys.argv[3])
lo=int(sys.argv[4]) if len(sys.argv)>4 else 13
hi=int(sys.argv[5]) if len(sys.argv)>5 else 30
def dser(base,arm,good):
    seeds=[s for s in sorted(set(base)&set(arm)) if lo<=s<=hi]
    out=[]
    for sd in seeds:
        gb=base[sd]['final']['goods'].get(good); ga=arm[sd]['final']['goods'].get(good)
        if gb and ga: out.append((sd,ga['rate']-gb['rate']))
    return out
def stat(xs):
    n=len(xs); m=statistics.mean(xs); md=statistics.median(xs)
    s=statistics.stdev(xs) if n>1 else 0.0; tc=TCRIT.get(n-1,2.1); ci=tc*s/math.sqrt(n) if n>1 else 0.0
    dn=sum(1 for x in xs if x<-0.001); up=sum(1 for x in xs if x>0.001); fl=n-dn-up
    return m,md,ci,dn,up,fl,n
def verdict(m,ci):
    if (m-ci)>0: return "SIG UP"
    if (m+ci)<0: return "SIG DOWN"
    if m<-0.001: return "n.s.(leans dn)"
    if m>0.001: return "n.s.(leans up)"
    return "flat"
print("=== DP-A ATTRIBUTION (held-out %d-%d, base=CLEAN committed batons no-饼干) ===\n" % (lo,hi))
for good in CORE:
    print("--- %s ---"%good)
    print("%-6s | mean d(vs CLEAN) | 95%%CI | median | dn/up/fl | verdict"%"arm")
    dW=[d for _,d in dser(clean,with_,good)]; mW=statistics.mean(dW) if dW else 0.0
    for name,arm in [("with",with_),("dpa",dpa)]:
        xs=[d for _,d in dser(clean,arm,good)]; m,md,ci,dn,up,fl,n=stat(xs)
        rec="" if name=="with" else ("  recover=%+.4f"%(m-mW))
        print("%-6s | %+.4f | +-%.4f | %+.4f | %d/%d/%d | %s%s"%(name,m,ci,md,dn,up,fl,verdict(m,ci),rec))
    print()
print("=== 口粮 paired recovery: DP-A vs WITH (per-seed dpa.rate - with.rate, held-out %d-%d) ===" % (lo,hi))
seeds=[s for s in sorted(set(with_)&set(dpa)) if lo<=s<=hi]
diffs=[dpa[s]['final']['goods']['口粮']['rate']-with_[s]['final']['goods']['口粮']['rate'] for s in seeds]
n=len(diffs); m=statistics.mean(diffs); s=statistics.stdev(diffs); tc=TCRIT.get(n-1,2.1); ci=tc*s/math.sqrt(n)
up=sum(1 for x in diffs if x>0.001); dn=sum(1 for x in diffs if x<-0.001)
v="SIG UP(recover)" if (m-ci)>0 else ("SIG DOWN" if (m+ci)<0 else "n.s.")
print("dpa-with 口粮 | mean=%+.4f 95%%CI[%+.4f,%+.4f] | up/dn=%d/%d | %s" % (m,m-ci,m+ci,up,dn,v))
