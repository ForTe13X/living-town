import sys, json, statistics, math
sys.stdout.reconfigure(encoding='utf-8')
# E7 leak attribution. Reads CLEAN + all arms, computes 口粮 (and CORE) held-out Δ vs CLEAN,
# and the leak carried by each ablated channel = Δ_arm - Δ_WITH (recovery vs the diluting base).
CORE=['口粮','柴薪','屋瓦','糕点','整洁']
TCRIT={17:2.110,18:2.101,19:2.093}
R="E:/Documents/Dev/June/26th/.claude/worktrees/agent-a88b63618f1e0e767/analysis/e7/runs/"
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
def delta_series(base,arm,good,lo=13,hi=30):
    seeds=[s for s in sorted(set(base)&set(arm)) if lo<=s<=hi]
    out=[]
    for sd in seeds:
        gb=base[sd]['final']['goods'].get(good); ga=arm[sd]['final']['goods'].get(good)
        if gb and ga: out.append((sd,ga['rate']-gb['rate']))
    return out
def stat(ds):
    xs=[d for _,d in ds]; n=len(xs); m=statistics.mean(xs); md=statistics.median(xs)
    s=statistics.stdev(xs) if n>1 else 0.0; tc=TCRIT.get(n-1,2.1); ci=tc*s/math.sqrt(n) if n>1 else 0.0
    dn=sum(1 for x in xs if x<-0.001); up=sum(1 for x in xs if x>0.001); fl=n-dn-up
    return m,md,ci,dn,up,fl,n
clean=load(R+"clean.jsonl")
arms={a:load(R+a+".jsonl") for a in ["with","arm1_abl_standing","arm2_abl_belief","arm3_abl_both","arm4_dpb_mei"]}
print("=== E7 ATTRIBUTION (held-out 13-30, base=CLEAN committed batons no-饼干) ===\n")
for good in CORE:
    print("--- %s ---"%good)
    print("%-22s | mean d(vs CLEAN) | 95%%CI | median | dn/up/fl | leak-carried(=d_arm - d_WITH)"%"arm")
    dW=delta_series(clean,arms["with"],good); mW=statistics.mean([d for _,d in dW])
    for a in ["with","arm1_abl_standing","arm2_abl_belief","arm3_abl_both","arm4_dpb_mei"]:
        ds=delta_series(clean,arms[a],good); m,md,ci,dn,up,fl,n=stat(ds)
        carried = m-mW  # positive => arm recovered 口粮 relative to WITH => channel was a leak
        tag="" if a=="with" else ("  recover=%+.4f"%carried)
        print("%-22s | %+.4f | +-%.4f | %+.4f | %d/%d/%d%s"%(a,m,ci,md,dn,up,fl,tag))
    print()
# paired per-seed: does arm recover 口粮 vs WITH? (paired diff arm-WITH per seed on held-out)
print("=== 口粮 paired recovery vs WITH (per-seed, arm.rate - WITH.rate, held-out 13-30) ===")
W=arms["with"]
for a in ["arm1_abl_standing","arm2_abl_belief","arm3_abl_both","arm4_dpb_mei"]:
    seeds=[s for s in sorted(set(W)&set(arms[a])) if 13<=s<=30]
    diffs=[arms[a][s]['final']['goods']['口粮']['rate']-W[s]['final']['goods']['口粮']['rate'] for s in seeds]
    n=len(diffs); m=statistics.mean(diffs); s=statistics.stdev(diffs); tc=TCRIT.get(n-1,2.1); ci=tc*s/math.sqrt(n)
    dn=sum(1 for x in diffs if x<-0.001); up=sum(1 for x in diffs if x>0.001)
    v="SIG UP(recover)" if (m-ci)>0 else ("SIG DOWN" if (m+ci)<0 else "n.s.")
    print("%-22s | mean(arm-WITH)=%+.4f 95%%CI[%+.4f,%+.4f] | up/dn=%d/%d | %s"%(a,m,m-ci,m+ci,up,dn,v))
