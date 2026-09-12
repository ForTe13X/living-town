import sys, json, statistics, math
sys.stdout.reconfigure(encoding='utf-8')

# E6a — abundant-industry probe (docs/172). Reads two ScaleSupply jsonl arms:
#   baseline (committed integration/batons, no 饼干) vs a prototype variant.
# Reports A (abundance), B (core held-out anchor), C (#40 soft gate + discretionary-aware glut arm).
#   A: is the discretionary treat never-short on every seed?  (byte-identity requires 饼干 never shorts)
#   B: 口粮 median Δrate on held-out seeds 13-30 — criterion: >= 0 (flat-or-up).
#   C: #40 per-seed pass (inv40_ok, the REAL verdict incl. discretionary exemption) on seeds 1-12;
#      soft gate needs >=11/12. Also prints the discretionary-aware glut arm counts.
CORE = ['口粮','柴薪','屋瓦','糕点','整洁']
TCRIT = {9:2.262,10:2.228,11:2.201,12:2.179,15:2.131,17:2.110,18:2.101,19:2.093,20:2.086,25:2.060,29:2.045}

def load(p):
    d={}
    for l in open(p,encoding='utf-8'):
        l=l.strip()
        if l.startswith('[SCALE]'): l=l[8:]
        if not l: continue
        try:
            r=json.loads(l); d[r['seed']]=r
        except: pass
    return d

base=load(sys.argv[1]); after=load(sys.argv[2])
label=sys.argv[3] if len(sys.argv)>3 else 'variant'
TREATS=['糕点','饼干']
seeds_all=sorted(set(base)&set(after))

print("="*78)
print("E6a analysis: base=%s  after=%s (%s)" % (sys.argv[1], sys.argv[2], label))
print("="*78)

# ---- A. ABUNDANCE: treats never-short? ----
print("\n[A] ABUNDANCE (discretionary treats never-short across seeds %d-%d)"%(seeds_all[0],seeds_all[-1]))
print(" seed | 糕点 rate/short | 饼干 rate/short/spoiled/end | inv40_ok")
anyshort={t:0 for t in TREATS}
for sd in seeds_all:
    g=after[sd]['final']['goods']
    row=" %4d |"%sd
    for t in TREATS:
        gg=g.get(t,{}); sh=gg.get('shortage_days',-1)
        if sh>0: anyshort[t]+=1
    gk=g.get('糕点',{}); bk=g.get('饼干',{})
    print(" %4d | 糕点 %.3f/%2d | 饼干 %.3f/%d/%d/%d | %s"%(
        sd, gk.get('rate',-1),gk.get('shortage_days',-1),
        bk.get('rate',-1),bk.get('shortage_days',-1),bk.get('spoiled',-1),bk.get('stock_end',-1),
        after[sd].get('inv40_ok')))
for t in TREATS:
    ns=len(seeds_all)-anyshort[t]
    print("   %s: never-short on %d/%d seeds  (%s)"%(t,ns,len(seeds_all),
        'ABUNDANT' if anyshort[t]==0 else '**SHORTS on %d seeds**'%anyshort[t]))

# ---- Byte-identity check (decision-inert?) ----
print("\n[byte-identity] core goods served/demand identical to baseline?")
ALL7=['口粮','柴薪','屋瓦','糕点','整洁','话本','豆子']
nbad=0
for sd in seeds_all:
    for g in ALL7:
        gb=base[sd]['final']['goods'].get(g,{}); ga=after[sd]['final']['goods'].get(g,{})
        if gb.get('served')!=ga.get('served') or gb.get('demand')!=ga.get('demand'):
            nbad+=1
            print("   seed %d %s: base sv=%s dm=%s | after sv=%s dm=%s"%(sd,g,gb.get('served'),gb.get('demand'),ga.get('served'),ga.get('demand')))
    if base[sd].get('social_events')!=after[sd].get('social_events'):
        print("   seed %d social_events %s -> %s"%(sd,base[sd].get('social_events'),after[sd].get('social_events')))
    if base[sd].get('work_by_title')!=after[sd].get('work_by_title'):
        print("   seed %d work_by_title differs"%sd)
print("   -> %s"%("DECISION BYTE-IDENTICAL (core served/demand + social + work all match)" if nbad==0 else "**%d core mismatches**"%nbad))

# ---- B. CORE HELD-OUT ANCHOR (seeds 13-30) ----
lo,hi=13,30
seeds=[s for s in seeds_all if lo<=s<=hi]
print("\n[B] CORE HELD-OUT ANCHOR (seeds %d-%d, n=%d) — criterion 口粮 Δ >= 0 (flat-or-up)"%(lo,hi,len(seeds)))
print(" good | mean Δ | 95%% CI(t) | median | down/up/flat | verdict")
for good in CORE:
    ds=[]
    for sd in seeds:
        gb=base[sd]['final']['goods'].get(good); ga=after[sd]['final']['goods'].get(good)
        if gb and ga: ds.append(ga['rate']-gb['rate'])
    if not ds:
        print(" %s: (no data)"%good); continue
    n=len(ds); m=statistics.mean(ds); md=statistics.median(ds)
    sd_=statistics.stdev(ds) if n>1 else 0.0
    tc=TCRIT.get(n-1,2.1); ci=tc*sd_/math.sqrt(n) if n>1 else 0.0
    downs=len([x for x in ds if x<-0.001]); ups=len([x for x in ds if x>0.001]); flat=n-downs-ups
    if (m-ci)>0: v="SIG UP"
    elif (m+ci)<0: v="SIG DOWN"
    elif m<-0.001: v="n.s.(leans down)"
    elif m>0.001: v="n.s.(leans up)"
    else: v="flat"
    print(" %-3s | %+.4f | [%+.4f,%+.4f] | %+.4f | %d/%d/%d | %s"%(good,m,m-ci,m+ci,md,downs,ups,flat,v))

# ---- C. #40 SOFT GATE (seeds 1-12) ----
print("\n[C] #40 SOFT GATE (seeds 1-12) — inv40_ok is the REAL verdict (incl. discretionary exemption)")
print(" seed | inv40_ok | glut_gated(non-disc) never_short(non-disc) | detail")
lo2,hi2=1,12
s12=[s for s in seeds_all if lo2<=s<=hi2]
npass=0
for sd in s12:
    r=after[sd]
    g=r['final']['goods']
    gated_nd=[k for k,v in g.items() if v.get('gated') and not v.get('discretionary')]
    ns_nd=[k for k in gated_nd if g[k].get('shortage_days',0)==0]
    ok=r.get('inv40_ok'); npass+=1 if ok else 0
    trip = len(ns_nd)*2>len(gated_nd)
    print(" %4d | %-5s | glut_gated=%d never_short=%d %-22s | %s"%(
        sd, str(ok), len(gated_nd), len(ns_nd), '['+','.join(ns_nd)+']',
        (r.get('inv40_detail','') or '-')[:70]))
print("   -> #40 [soft] pass %d/12  (gate needs >=11/12): %s"%(npass, 'PASS' if npass>=11 else '**FAIL**'))

# ---- D. HARD invariants (all seeds) ----
print("\n[D] HARD invariants (all seeds) — hard_fails must be empty")
hbad=[]
for sd in seeds_all:
    hf=after[sd].get('hard_fails',[])
    if hf: hbad.append((sd,hf))
print("   -> %s"%("ALL HARD GREEN (0 hard fails across %d seeds)"%len(seeds_all) if not hbad else "**HARD FAILS: %s**"%hbad))
# also list any soft fails other than none
sf_seen={}
for sd in seeds_all:
    for f in after[sd].get('soft_fails',[]):
        sf_seen.setdefault(f,[]).append(sd)
print("   soft fails by id: %s"%(sf_seen or 'none'))
