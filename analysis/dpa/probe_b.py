import sys, json, statistics
sys.stdout.reconfigure(encoding='utf-8')
# DP-A probe B (drama preserved): from a dpa run jsonl, per-seed confirm the second industrial good
# 饼干 (biscuit) TRULY shorts (not a decoration good), ③ SH:饼干 belief still forms/spreads (gossip),
# and the rerouted ④ consequence is written into the self-contained grievance field (>0 = "seen").
# Usage: python probe_b.py <dpa.jsonl> [lo] [hi] [good]
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
d=load(sys.argv[1])
lo=int(sys.argv[2]) if len(sys.argv)>2 else 13
hi=int(sys.argv[3]) if len(sys.argv)>3 else 30
good=sys.argv[4] if len(sys.argv)>4 else '饼干'
seeds=[s for s in sorted(d) if lo<=s<=hi]
print("=== DP-A probe B (drama preserved) : %s, seeds %d-%d, n=%d ===" % (good,lo,hi,len(seeds)))
print("seed | %s rate | short_days | short_ev | gossip | SH:%s hold(seen/relay) | grievance_total(rels)" % (good,good))
srate=[]; sdays=[]; sev=[]; gtot=[]; holders=[]; relayed=[]; gsp=[]
shorts_ok=0; grievance_ok=0; belief_ok=0
for s in seeds:
    g=d[s]['final']['goods'].get(good,{})
    rate=g.get('rate',-1); sd=g.get('shortage_days',0); se=g.get('shortage_events',0)
    gt=d[s].get('grievance_total',0.0); gr=d[s].get('grievance_rels',0)
    hh=d[s].get('bing_belief_holders',0); hs=d[s].get('bing_belief_seen',0); hr=d[s].get('bing_belief_relayed',0)
    gg=d[s].get('social_by_type',{}).get('gossip',0)
    srate.append(rate); sdays.append(sd); sev.append(se); gtot.append(gt); holders.append(hh); relayed.append(hr); gsp.append(gg)
    if se>0 and rate<1.0: shorts_ok+=1
    if gt>0.0: grievance_ok+=1
    if hh>0: belief_ok+=1
    print("%4d | %.3f | %3d | %4d | %4d | %2d (%2d/%2d) | %.2f (%d)" % (s,rate,sd,se,gg,hh,hs,hr,gt,gr))
def mm(xs): return (statistics.mean(xs), min(xs), max(xs))
print("--- aggregates (n=%d held-out seeds) ---" % len(seeds))
print("%s rate           mean/min/max = %.3f / %.3f / %.3f" % ((good,)+mm(srate)))
print("%s shortage_days   mean/min/max = %.1f / %d / %d" % ((good,)+mm(sdays)))
print("%s shortage_events mean/min/max = %.1f / %d / %d" % ((good,)+mm(sev)))
print("gossip events        mean/min/max = %.1f / %d / %d" % mm(gsp))
print("SH:%s holders       mean/min/max = %.1f / %d / %d" % ((good,)+mm(holders)))
print("  of which relayed   mean/min/max = %.1f / %d / %d (via=gossip)" % mm(relayed))
print("grievance_total      mean/min/max = %.2f / %.2f / %.2f" % mm(gtot))
print("--- verdict gates ---")
print("B1 真缺货  (short_events>0 & rate<1) : %d/%d seeds" % (shorts_ok,len(seeds)))
print("B2 ③信念   (SH:%s holders>0)         : %d/%d seeds" % (good,belief_ok,len(seeds)))
print("B3 ④改道被写(grievance_total>0)       : %d/%d seeds" % (grievance_ok,len(seeds)))
print("PASS B iff B1==B2==B3==%d/%d" % (len(seeds),len(seeds)))
