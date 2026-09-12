import sys, json
sys.stdout.reconfigure(encoding='utf-8')

# E4d-B #40 probe for 饼干 (cookies) — coco (糕点师) makes it as a SECOND good in her
# SAME 做点心 sessions via E4d-A's produce Array. Mirrors analysis/e4c/parse.py.
#   produce.糕点师 = [{糕点,6},{饼干,B}]   ← E4d-A produce Array (first good 糕点 locks cadence)
#   consume.闲聊   = [{糕点,1},{饼干,1}]   ← E4a consume Array
# 饼干 supply = coco_work(糕点师) × B (coco cadence unchanged, locked to first good 糕点).
# 饼干 demand == 糕点's demand (same host 闲聊, amount 1 each).
GOOD = '饼干'
HOST = '闲聊'
TITLE = '糕点师'

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
