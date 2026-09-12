import sys, json
sys.stdout.reconfigure(encoding='utf-8')
# DP-A probe E (hard invariants). Reads a jsonl (ScaleSupply per-seed records carry hard_fails/soft_fails
# from a full Inv.check_all) and confirms hard invariants are green across all seeds. Flags the brief's
# watch-list {1,34,35,38,39}. #34 (SLM device hang) is a device-only concern, not exercised headless.
# Usage: python hardinv.py <run.jsonl> [lo] [hi]
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
lo=int(sys.argv[2]) if len(sys.argv)>2 else 1
hi=int(sys.argv[3]) if len(sys.argv)>3 else 30
seeds=[s for s in sorted(d) if lo<=s<=hi]
WATCH={1,34,35,38,39}
print("=== DP-A probe E (hard invariants) : %s seeds %d-%d, n=%d ===" % (sys.argv[1],lo,hi,len(seeds)))
any_hard=False; hard_union=set(); soft_union=set(); bad=[]
for s in seeds:
    hf=[int(x) for x in d[s].get('hard_fails',[])]
    sf=[int(x) for x in d[s].get('soft_fails',[])]
    hard_union|=set(hf); soft_union|=set(sf)
    if hf:
        any_hard=True; bad.append((s,hf))
print("seeds with ANY hard fail: %s" % (bad or 'NONE'))
print("hard-fail id union over %d seeds: %s" % (len(seeds), sorted(hard_union) or '[] (all hard green)'))
print("soft-fail id union over %d seeds: %s (soft = per-invariant >=11/12 gate, informational here)" % (len(seeds), sorted(soft_union) or '[]'))
print("watch-list {1,34,35,38,39} hard-fail hits: %s" % (sorted(WATCH & hard_union) or 'NONE'))
print("PASS E iff no hard fail on any seed: %s" % ("FAIL" if any_hard else "PASS"))
