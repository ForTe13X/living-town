import sys, json, statistics, math
sys.stdout.reconfigure(encoding='utf-8')

# E7 core-goods held-out anchor. base=arg1 (CLEAN, committed batons, no 饼干), after=arg2 (an arm).
# Δ = after.rate - base.rate on held-out seeds [lo,hi] (default 13-30). Same CORE as E4d-B/E5a.
# Reports mean Δ, 95% t-CI, median, down/up/flat, |down|/|up| magnitudes.
CORE = ['口粮','柴薪','屋瓦','糕点','整洁']
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

base=load(sys.argv[1]); after=load(sys.argv[2])
lo=int(sys.argv[3]) if len(sys.argv)>3 else 13
hi=int(sys.argv[4]) if len(sys.argv)>4 else 30
label=sys.argv[5] if len(sys.argv)>5 else ''
seeds=[s for s in sorted(set(base)&set(after)) if lo<=s<=hi]
print("=== E7 CORE ANCHOR %s : %d held-out seeds %d-%d ===" % (label,len(seeds),lo,hi))
print("base=%s  after=%s" % (sys.argv[1], sys.argv[2]))
print("good | mean d | 95%% CI(t) | median | down/up/flat | |dn|/|up| | verdict")
for good in CORE:
    ds=[]
    for sd in seeds:
        gb=base[sd]['final']['goods'].get(good); ga=after[sd]['final']['goods'].get(good)
        if gb and ga: ds.append(ga['rate']-gb['rate'])
    if not ds:
        print("%s: (no data)"%good); continue
    n=len(ds); m=statistics.mean(ds); md=statistics.median(ds)
    sd_=statistics.stdev(ds) if n>1 else 0.0
    tc=TCRIT.get(n-1,2.1); ci=tc*sd_/math.sqrt(n)
    downs=[x for x in ds if x<-0.001]; ups=[x for x in ds if x>0.001]; flat=n-len(downs)-len(ups)
    dmag=statistics.mean([abs(x) for x in downs]) if downs else 0.0
    umag=statistics.mean(ups) if ups else 0.0
    if (m-ci)>0: v="SIG UP"
    elif (m+ci)<0: v="SIG DOWN"
    elif m<-0.001: v="n.s.(leans dn)"
    elif m>0.001: v="n.s.(leans up)"
    else: v="flat"
    print("%-3s | %+.4f | [%+.4f,%+.4f] | %+.4f | %d/%d/%d | %.3f/%.3f | %s" % (
        good,m,m-ci,m+ci,md,len(downs),len(ups),flat,dmag,umag,v))
