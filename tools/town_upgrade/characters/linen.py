"""Hash-verified Poly Haven photographed linen, separate from MakeHuman data."""
import hashlib
import json
from pathlib import Path

VENDOR=Path(__file__).resolve().parent/'vendor/polyhaven_rough_linen'


def verify_linen():
    receipt=json.loads((VENDOR/'source_receipts.json').read_text(encoding='utf-8'))
    if receipt.get('license')!='CC0-1.0' or receipt.get('license_url')!='https://polyhaven.com/license':raise ValueError('Unverified linen license receipt')
    asset=receipt['assets']['rough_linen']
    if asset['asset_url']!='https://polyhaven.com/a/rough_linen':raise ValueError('Unexpected linen source')
    for key,name in [('info','rough_linen_info.json'),('files','rough_linen_files.json')]:
        if hashlib.sha256((VENDOR/name).read_bytes()).hexdigest()!=asset['metadata_sha256'][key]:raise ValueError('Linen source metadata changed')
    for row in receipt['files']:
        path=(VENDOR/row['path']).resolve()
        if not path.is_relative_to(VENDOR.resolve()):raise ValueError('Invalid linen source path')
        data=path.read_bytes()
        if len(data)!=row['bytes'] or hashlib.sha256(data).hexdigest()!=row['sha256']:raise ValueError('Linen source bytes changed: '+row['path'])
    receipt['files']={row['path']:row for row in receipt['files']}
    return receipt


def repeat_m():
    return [value/1000 for value in verify_linen()['assets']['rough_linen']['dimensions_mm']]


def metric_geometry(geometry,scale,repeat,strip_width=None):
    """Use physical meters per photographed repeat, including persona stature.

    Panels retain their planar cutting coordinates X/Z. Closed ribbon UVs store
    normalized width and four times cumulative centerline meters, so both axes
    can be converted without stretching one repeat across an entire strap.
    """
    vertices,faces,uv=geometry
    if strip_width is None:mapped=[(p[0]*scale/repeat[0],p[2]*scale/repeat[1]) for p in vertices]
    else:mapped=[(u*strip_width*scale/repeat[0],v*.25*scale/repeat[1]) for u,v in uv]
    return vertices,faces,mapped
