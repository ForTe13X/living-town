import sys, json
sys.stdout.reconfigure(encoding='utf-8')
# Off-gate / reproduction proof: compare per-seed digests of two jsonl files.
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
a=load(sys.argv[1]); b=load(sys.argv[2])
seeds=sorted(set(a)&set(b))
same=0; diff=[]
for s in seeds:
    da=a[s].get('digest'); db=b[s].get('digest')
    if da==db: same+=1
    else: diff.append((s,da,db))
print("compare %s  vs  %s"%(sys.argv[1],sys.argv[2]))
print("digest byte-identical: %d/%d seeds"%(same,len(seeds)))
if diff:
    for s,da,db in diff: print("  MISMATCH seed %d: %s vs %s"%(s,da,db))
else:
    print("  ALL MATCH (pure no-op / exact reproduction)")
