import sys, json

def load(path):
    recs=[]
    with open(path, encoding='utf-8') as f:
        for line in f:
            line=line.strip()
            if not line: continue
            if line.startswith('[SCALE]'): line=line[8:].strip()
            try: recs.append(json.loads(line))
            except: pass
    return recs

def show_gaodian(path):
    recs=load(path)
    print("=== 糕点 / #40 (%s) ===" % path)
    rates=[]
    ns=0; bf=0; gt=0
    for r in recs:
        g=r['final']['goods'].get('糕点')
        att=r['attempts_by_action']
        w=r['work_by_title'].get('糕点师','-')
        if g is None:
            print('seed',r['seed'],'NO 糕点'); continue
        rate=g['rate']; rates.append(rate)
        if g['gated']: gt+=1
        if g['gated'] and g['shortage_days']==0: ns+=1
        if g['gated'] and rate<0.5: bf+=1
        print('seed %2d | 闲聊(demand)=%s | 糕点 rate=%.3f (%d/%d) short_days=%2d gated=%s | work=%s stock_end=%d spoiled=%d | hard=%s soft=%s' % (
            r['seed'], att.get('闲聊'), rate, g['served'], g['demand'], g['shortage_days'], g['gated'], w, g['stock_end'], g['spoiled'], r['hard_fails'], r['soft_fails']))
    if rates:
        rs=sorted(rates)
        print('--- 糕点 rate min/med/max = %.3f / %.3f / %.3f | gated=%d never_short=%d below_floor=%d | N=%d' % (
            rs[0], rs[len(rs)//2], rs[-1], gt, ns, bf, len(rates)))

def core3(path, label):
    recs=load(path)
    out={}
    for r in recs:
        for good in ['口粮','柴薪','屋瓦']:
            g=r['final']['goods'].get(good)
            if g is None: continue
            out.setdefault(good,{})[r['seed']]=g['rate']
    print("=== core3 %s (%s) ===" % (label, path))
    return out

if __name__=='__main__':
    cmd=sys.argv[1]
    if cmd=='gaodian': show_gaodian(sys.argv[2])
    elif cmd=='core3':
        d=core3(sys.argv[2], sys.argv[2])
        for good,v in d.items():
            rs=sorted(v.values())
            print('%s: min/med/max=%.3f/%.3f/%.3f  n=%d' % (good, rs[0], rs[len(rs)//2], rs[-1], len(rs)))
