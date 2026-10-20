"""Original contextual limewash and split-slate maps for the reconstructed cafe."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def generate(output, size=1024):
    output=Path(output);output.mkdir(parents=True,exist_ok=False)
    rng=np.random.default_rng(20261019)
    v,u=np.meshgrid(np.linspace(0,1,size),np.linspace(0,1,size),indexing='ij')
    grit=rng.normal(0,1,(size,size));broad=np.zeros_like(u)
    for _ in range(18):
        broad+=np.sin(2*np.pi*(rng.integers(1,8)*u+rng.integers(1,8)*v)+rng.uniform(0,6.28))
    broad/=18
    # Image rows top-to-bottom, facade UV V points up. Context follows actual openings.
    z=(1-v)*6.5;x=(u-.5)*8.6
    wear=np.exp(-z/.38)*.12+np.exp(-((z-6.35)/.12)**2)*.035
    for xx in [-2.55,0,2.55]:
        wear+=np.exp(-((x-xx)/.7)**4)*np.exp(-((z-3.55)/.65)**2)*.027
    plaster=np.array([224,218,201])+broad[:,:,None]*4+grit[:,:,None]*.8-wear[:,:,None]*np.array([70,65,54])
    slate=np.array([67,75,79])+broad[:,:,None]*5+grit[:,:,None]*1.5
    records={}
    for family,rgb,rough in [('facade_limewash',plaster,.91),('split_slate',slate,.79)]:
        for channel,pixels in [('basecolor',np.uint8(np.clip(rgb,0,255))),('roughness',np.uint8(np.clip(rough+grit*.008,0,1)*255))]:
            name=f'{family}_{channel}.png';path=output/name;Image.fromarray(pixels).save(path)
            records[name]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'resolution':[size,size],
                           'color_space':'sRGB' if channel=='basecolor' else 'Non-Color'}
    record={'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'original':True,'ai_inference':False,'seed':20261019,'facade_dimensions_m':[8.6,6.5],
            'notes':'Contextual facade colour is not a periodic general material. Roof has no painted tile grid; tile overlaps are mesh geometry.',
            'files':records}
    (output/'manifest.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    return record


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--size',type=int,default=1024)
    a=p.parse_args();generate(a.output,a.size)
