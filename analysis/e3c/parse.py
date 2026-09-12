import sys, json
sys.stdout.reconfigure(encoding='utf-8')

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

def show_denglong(path):
    recs=load(path)
    print("=== 花灯 / #40 (%s) ===" % path)
    rates=[]; ns=0; bf=0; gt=0
    for r in recs:
        g=r['final']['goods'].get('花灯')
        att=r['attempts_by_action']
        w=r['work_by_title'].get('扎灯匠','-')
        if g is None:
            print('seed',r['seed'],'NO 花灯'); continue
        rate=g['rate']; rates.append(rate)
        if g['gated']: gt+=1
        if g['gated'] and g['shortage_days']==0: ns+=1
        if g['gated'] and rate<0.5: bf+=1
        print('seed %2d | 逛灯会(demand)=%s | 花灯 rate=%.3f (%d/%d) short_days=%2d gated=%s | work=%s stock_end=%d spoiled=%d | hard=%s soft=%s' % (
            r['seed'], att.get('逛灯会'), rate, g['served'], g['demand'], g['shortage_days'], g['gated'], w, g['stock_end'], g['spoiled'], r['hard_fails'], r['soft_fails']))
    if rates:
        rs=sorted(rates)
        print('--- 花灯 rate min/med/max = %.3f / %.3f / %.3f | gated=%d never_short=%d below_floor=%d | N=%d' % (
            rs[0], rs[len(rs)//2], rs[-1], gt, ns, bf, len(rates)))

if __name__=='__main__':
    show_denglong(sys.argv[1])
