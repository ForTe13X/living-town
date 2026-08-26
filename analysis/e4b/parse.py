import sys, json
sys.stdout.reconfigure(encoding='utf-8')

# E4b #40 probe for 风筝 (kite) on host 玩耍. Mirrors analysis/e3c/parse.py.
GOOD = '风筝'
HOST = '玩耍'
TITLE = '风筝匠'

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

def show(path):
    recs=load(path); recs.sort(key=lambda r:r['seed'])
    print("=== %s / #40 (%s) ===" % (GOOD, path))
    rates=[]; ns=0; bf=0; gt=0; works=[]
    for r in recs:
        g=r['final']['goods'].get(GOOD)
        att=r['attempts_by_action']
        w=r['work_by_title'].get(TITLE,'-')
        if isinstance(w,int): works.append(w)
        if g is None:
            print('seed',r['seed'],'NO',GOOD); continue
        rate=g['rate']; rates.append(rate)
        if g['gated']: gt+=1
        if g['gated'] and g['shortage_days']==0: ns+=1
        if g['gated'] and rate<0.5: bf+=1
        print('seed %2d | %s(demand)=%s | %s rate=%.3f (%d/%d) short_days=%2d gated=%s | work=%s stock_end=%d spoiled=%d | hard=%s soft=%s' % (
            r['seed'], HOST, att.get(HOST), GOOD, rate, g['served'], g['demand'], g['shortage_days'], g['gated'], w, g['stock_end'], g['spoiled'], r['hard_fails'], r['soft_fails']))
    if rates:
        rs=sorted(rates)
        import statistics
        wtxt = ('work min/med/max=%d/%d/%d'%(min(works),int(statistics.median(works)),max(works))) if works else 'work=?'
        print('--- %s rate min/med/max = %.3f / %.3f / %.3f | gated=%d never_short=%d below_floor=%d | N=%d | %s' % (
            GOOD, rs[0], rs[len(rs)//2], rs[-1], gt, ns, bf, len(rates), wtxt))

if __name__=='__main__':
    for p in sys.argv[1:]:
        show(p)
