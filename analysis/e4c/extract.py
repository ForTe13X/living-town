import sys
# Extract the [SCALE]-prefixed jsonl lines from a ScaleSupply stdout log into a clean .jsonl.
# Usage: python extract.py <src_log> <dst_jsonl>
src, dst = sys.argv[1], sys.argv[2]
out=[]
for l in open(src, encoding='utf-8'):
    l=l.rstrip('\n')
    if l.startswith('[SCALE] '):
        out.append(l[8:])
with open(dst,'w',encoding='utf-8') as f:
    for o in out: f.write(o+'\n')
print('extracted %d lines -> %s' % (len(out), dst))
