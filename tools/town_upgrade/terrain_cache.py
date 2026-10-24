"""Reuse a terrain bake only when its complete inputs and output bytes match."""
import hashlib
import json
from pathlib import Path
import shutil
import struct


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def reuse(cache,guide,sources,output,tool,size):
    cache=Path(cache).resolve(strict=True);output=Path(output)
    receipt_path=cache/'terrain_atlas_receipt.json'
    receipt=json.loads(receipt_path.read_text(encoding='utf-8'))
    if receipt.get('schema')!='living_town.terrain_atlas.v1':raise ValueError('Unsupported cached terrain schema')
    expected={'input_guide_sha256':sha(guide),'source_receipts_sha256':sha(sources/'source_receipts.json'),
              'tool_sha256':sha(tool),'dimensions':[size,size]}
    for key,value in expected.items():
        if receipt.get(key)!=value:raise ValueError('Terrain cache input mismatch: '+key)
    source_receipt=json.loads((sources/'source_receipts.json').read_text(encoding='utf-8'))
    for row in source_receipt['files']:
        source=(sources/row['path']).resolve(strict=True)
        if not source.is_relative_to(sources.resolve()) or sha(source)!=row['sha256']:raise ValueError('Changed cached terrain source: '+row['path'])
    if set(receipt['maps'])!={'diff','nor_gl','arm'}:raise ValueError('Incomplete cached terrain maps')
    files=[]
    for row in receipt['maps'].values():
        source=(cache/row['path']).resolve(strict=True)
        if not source.is_relative_to(cache) or source.stat().st_size!=row['bytes'] or sha(source)!=row['sha256']:raise ValueError('Changed cached terrain map')
        with source.open('rb') as stream:header=stream.read(24)
        if header[:8]!=b'\x89PNG\r\n\x1a\n' or header[12:16]!=b'IHDR' or struct.unpack('>II',header[16:24])!=(size,size):raise ValueError('Invalid cached terrain PNG dimensions')
        destination=output/row['path']
        if destination.parent.resolve()!=output.resolve() or destination.exists():raise ValueError('Unsafe/nonfresh cached terrain destination')
        files.append((source,destination,row['sha256']))
    # No writes before every source, guide and map has passed preflight.
    for source,destination,digest in files:
        shutil.copyfile(source,destination)
        if sha(destination)!=digest:raise IOError('Cached map copy changed bytes')
    shutil.copyfile(receipt_path,output/receipt_path.name)
    return {'source_receipt_sha256':sha(receipt_path),'maps_sha256':{role:row['sha256'] for role,row in receipt['maps'].items()},
            'policy':'Exact guide, source bytes, atlas tool, dimensions and every cached PNG verified before reuse.'}
