"""Bake a portable world-space diffuse atlas from verified CC0 ground scans.

This technical map bake uses actual terrain slopes and tree-root positions.
All portable channels share one atlas UV set; original scan maps are retained.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ASSETS=('leafy_grass','forest_leaves_02','aerial_grass_rock')


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def smooth(value):
    value=np.clip(value,0,1);return value*value*(3-2*value)


def fields(guide, size=768):
    x0,y0,x1,y1=guide['bounds_xy_m'];sx=(size-1)/(x1-x0);sy=(size-1)/(y1-y0)
    woodland=Image.new('L',(size,size));draw=ImageDraw.Draw(woodland)
    def forest_weight(tree):
        x,y,_=tree['position_m']
        return max(float(smooth((-x-105)/65)),float(smooth((y-108)/58)))
    for tree in sorted(guide['trees'],key=forest_weight):
        x,y,_=tree['position_m']
        # Garden trees retain maintained lawn; woodland trees leave litter.
        forest=forest_weight(tree)
        if forest<=0:continue
        radius=max(2.,min(7.,4.2*tree['scale'][0]));u=(x-x0)*sx;v=(y1-y)*sy
        draw.ellipse((u-radius*sx,v-radius*sy,u+radius*sx,v+radius*sy),fill=round(255*forest))
    woodland=np.asarray(woodland.filter(ImageFilter.GaussianBlur(2.1)),dtype=np.float32)/255
    woodland=smooth(woodland*1.65)*.94
    slope=np.zeros((size,size),np.float32)
    points=np.asarray(guide['slope_samples'],np.float32)
    if len(points):
        ix=np.clip(((points[:,0]-x0)*sx).astype(int),0,size-1)
        iy=np.clip(((y1-points[:,1])*sy).astype(int),0,size-1)
        np.maximum.at(slope,(iy,ix),smooth((points[:,2]-.15)/.45))
    rock=np.asarray(Image.fromarray(np.uint8(slope*255)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.2)),dtype=np.float32)/255
    return woodland,rock


def sample(source,x,y,repeat):
    height,width=source.shape[:2]
    u=np.mod(x/repeat[0],1)*width-.5;v=np.mod(-y/repeat[1],1)*height-.5
    ix=np.floor(u).astype(np.int32);iy=np.floor(v).astype(np.int32);fx=(u-ix)[...,None];fy=(v-iy)[...,None]
    return ((source[iy%height,ix%width]*(1-fx)+source[iy%height,(ix+1)%width]*fx)*(1-fy)+
            (source[(iy+1)%height,ix%width]*(1-fx)+source[(iy+1)%height,(ix+1)%width]*fx)*fy)


def adapted_sample(source,x,y,repeat,role,adaptation):
    if not adaptation.get('anti_tile',False):return sample(source,x,y,repeat)
    result=None
    for angle,weight,offset in ((0.,.50,(0.,0.)),(np.pi/2,.30,(.37,.19)),(.8482300165,.20,(.13,.61))):
        c,s=np.cos(angle),np.sin(angle)
        value=sample(source,c*x+s*y+offset[0]*repeat[0],-s*x+c*y+offset[1]*repeat[1],repeat)
        if role=='nor_gl':
            # Return tangent normals from the rotated scan axes into the
            # unchanged world-XY atlas tangent basis before blending them.
            nx,ny=value[:,:,0].copy(),value[:,:,1].copy()
            value[:,:,0]=c*nx-s*ny;value[:,:,1]=s*nx+c*ny
        result=value*weight if result is None else result+value*weight
    return result


def bake(guide_path,sources,output,size):
    guide=json.loads(Path(guide_path).read_text(encoding='utf-8'));sources=Path(sources);output=Path(output)
    adaptation=guide.get('scan_adaptation',{})
    receipt=json.loads((sources/'source_receipts.json').read_text(encoding='utf-8'))
    for row in receipt['files']:
        path=sources/row['path']
        if sha(path)!=row['sha256']:raise ValueError('Changed CC0 terrain scan '+str(path))
    output.mkdir(parents=True,exist_ok=True);wood,rock=fields(guide)
    wood_img=Image.fromarray(wood.astype('float32'),'F').resize((size,size),Image.Resampling.BILINEAR)
    rock_img=Image.fromarray(rock.astype('float32'),'F').resize((size,size),Image.Resampling.BILINEAR)
    repeats=[[v/1000 for v in receipt['assets'][asset]['dimensions_mm']] for asset in ASSETS]
    if any(len(r)!=2 or not np.isfinite(r).all() or min(r)<=0 for r in repeats):raise ValueError('Missing source physical dimensions')
    x0,y0,x1,y1=guide['bounds_xy_m']
    if not np.isfinite([x0,y0,x1,y1]).all() or x1<=x0 or y1<=y0:raise ValueError('Invalid terrain bounds')
    xs=(x0+(np.arange(size,dtype=np.float32)+.5)*(x1-x0)/size)[None,:]
    maps={}
    for role in ('diff','nor_gl','arm'):
        maps[role]=[]
        for asset,repeat in zip(ASSETS,repeats):
            # Avoid point-sampling a 2K photograph into a roughly 30px tile.
            # Retain correctly band-limited detail at this atlas's density.
            dimensions=(max(16,round(size*repeat[0]/(x1-x0))),max(16,round(size*repeat[1]/(y1-y0))))
            value=np.asarray(Image.open(sources/asset/(role+'.jpg')).convert('RGB'),dtype=np.float32)/255
            if role=='diff':
                value=np.where(value<=.04045,value/12.92,((value+.055)/1.055)**2.4)
                value=np.stack([np.asarray(Image.fromarray(value[:,:,i],'F').resize(dimensions,Image.Resampling.LANCZOS)) for i in range(3)],axis=2)
            else:
                value=np.asarray(Image.open(sources/asset/(role+'.jpg')).convert('RGB').resize(dimensions,Image.Resampling.LANCZOS),dtype=np.float32)/255
                if role=='nor_gl':value=value*2-1
            maps[role].append(value)
    atlases={role:Image.new('RGB',(size,size)) for role in maps}
    for start in range(0,size,96):
        end=min(start+96,size);ys=(y1-(np.arange(start,end,dtype=np.float32)+.5)*(y1-y0)/size)[:,None]
        x,y=np.broadcast_arrays(xs,ys)
        w=np.asarray(wood_img.crop((0,start,size,end)))[...,None];r=np.asarray(rock_img.crop((0,start,size,end)))[...,None]
        macro=.98+.075*np.sin(x*.037+np.sin(y*.026))+.045*np.sin(y*.071-x*.019)
        for role,source_maps in maps.items():
            channels=[adapted_sample(source,x,y,repeat,role,adaptation if index==0 else {}) for index,(source,repeat) in enumerate(zip(source_maps,repeats))]
            if role=='diff':
                for index,asset in enumerate(ASSETS):channels[index]*=np.asarray(adaptation.get('linear_rgb_factors',{}).get(asset,[1,1,1]),dtype=np.float32)
            value=(channels[0]*(1-w)+channels[1]*w)*(1-r*.7)+channels[2]*r*.7
            if role=='diff':
                value=np.clip(value*macro[...,None],0,1)
                value=np.where(value<=.0031308,value*12.92,1.055*value**(1/2.4)-.055)
            elif role=='nor_gl':
                value/=np.maximum(np.linalg.norm(value,axis=2,keepdims=True),.0001);value=(value+1)*.5
            atlases[role].paste(Image.fromarray(np.uint8(np.clip(value*255,0,255))),(0,start))
    paths={role:output/('terrain_world_'+role+'.png') for role in atlases}
    for role,path in paths.items():atlases[role].save(path,compress_level=6)
    Image.fromarray(np.uint8(wood*255)).save(output/'woodland_mask.png')
    Image.fromarray(np.uint8(rock*255)).save(output/'slope_mask.png')
    result={'schema':'living_town.terrain_atlas.v1','status':'BAKED_REQUIRES_VISUAL_REVIEW',
            'bounds_xy_m':guide['bounds_xy_m'],'dimensions':[size,size],
            'metres_per_texel':[(x1-x0)/size,(y1-y0)/size],
            'maps':{role:{'path':path.name,'sha256':sha(path),'bytes':path.stat().st_size} for role,path in paths.items()},
            'input_guide_sha256':sha(guide_path),'source_receipts_sha256':sha(sources/'source_receipts.json'),
            'tool_sha256':sha(__file__),'source_repeat_metres':dict(zip(ASSETS,repeats)),
            'tree_roots':len(guide['trees']),'actual_slope_samples':len(guide['slope_samples']),
            'scan_adaptation':adaptation,
            'policy':'Portable common-UV0 diffuse/OpenGL tangent-normal/ARM atlases; source-sized tiling before a density-filtered technical bake; actual topographic slope and authored woodland-root masks; no terrain topology or paving changed.'}
    (output/'terrain_atlas_receipt.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result));return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--guide',type=Path,required=True);parser.add_argument('--sources',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--size',type=int,default=8192)
    args=parser.parse_args()
    if args.size not in (2048,4096,8192):parser.error('Use a bounded 2K, 4K or 8K atlas')
    bake(args.guide,args.sources,args.output,args.size)
