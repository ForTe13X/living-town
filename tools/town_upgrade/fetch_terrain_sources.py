"""Fetch three explicit CC0 terrain scans with upstream size/MD5 receipts.

Powered by Poly Haven. Only redistributable texture maps and API metadata are
acquired; website previews and unrelated content are excluded.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path

from fetch_botanical_sources import digest, fetch, request

ASSETS = ('leafy_grass', 'forest_leaves_02', 'aerial_grass_rock')


def acquire(output):
    output=Path(output).resolve();output.mkdir(parents=True,exist_ok=True)
    metadata={};jobs=[]
    for asset in ASSETS:
        docs={}
        for endpoint in ('info','files'):
            path=output/(asset+'_'+endpoint+'.json')
            if path.exists():value=json.loads(path.read_text(encoding='utf-8'))
            else:
                with request('https://api.polyhaven.com/'+endpoint+'/'+asset) as response:value=json.load(response)
                path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
            docs[endpoint]=value
        metadata[asset]={'asset_url':'https://polyhaven.com/a/'+asset,
                         'dimensions_mm':docs['info'].get('dimensions'),
                         'metadata_sha256':{key:digest(output/(asset+'_'+key+'.json')) for key in docs}}
        for role, aliases in (('diff',('diff','Diffuse')),('nor_gl',('nor_gl',)),('arm',('arm',))):
            key=next((key for key in aliases if key in docs['files']),None)
            if key is None:raise ValueError('Missing terrain channel '+asset+'/'+role)
            jobs.append((output/asset/(role+'.jpg'),docs['files'][key]['2k']['jpg']))
    with ThreadPoolExecutor(max_workers=3) as pool:receipts=list(pool.map(fetch,jobs))
    record={'schema':'living_town.terrain_sources.v1','license':'CC0-1.0',
            'license_url':'https://polyhaven.com/license','credit':'Powered by Poly Haven',
            'assets':metadata,'files':[{**row,'path':Path(row['path']).relative_to(output).as_posix()} for row in receipts]}
    (output/'source_receipts.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'files':len(receipts),'bytes':sum(r['bytes'] for r in receipts),'output':str(output)}))
    return record


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    acquire(parser.parse_args().output)
