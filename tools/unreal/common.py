"""Small file helpers shared by the Windows editor bootstrap."""
from pathlib import Path
import json,hashlib,sys
sys.dont_write_bytecode=True
def need(ok,msg):
 if not ok:raise ValueError(msg)
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,v):Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
def sha(p):
 with Path(p).open('rb')as f:return hashlib.file_digest(f,'sha256').hexdigest()
def binding(p):
 p=Path(p).resolve();return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)}
def verify(rows):
 for row in rows:need(binding(row['path'])==row,'Bound input changed: '+row['path'])
def tree_stats(root):
 root=Path(root)
 return {str(p):[p.stat().st_size,p.stat().st_mtime_ns]for p in root.rglob('*')if p.is_file()}if root.exists()else{}
