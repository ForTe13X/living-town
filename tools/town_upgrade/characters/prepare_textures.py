"""Prepare registered CC0 character atlases before the supervised Blender build.

This is the character consumer of the repository's dedicated refinement route:
verified source maps -> documented 2K palette bake -> ordinary PBR graph ->
embedded-pixel verification. No model weights, inference or RGB-derived normal
estimation are used. Original source UV registration is retained unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

from PIL import Image
import numpy as np

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
if str(REPO) not in sys.path:sys.path.insert(0,str(REPO))
from tools.town_upgrade.characters.assets import VENDOR,verify_assets
from tools.town_upgrade.characters.manifest import build_manifest
from tools.town_upgrade.characters.linen import VENDOR as LINEN_VENDOR,verify_linen

FEMALE={'aria','coco','evy','fei','mei','qin','hua','mian','gui','liu'}


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def linear(c):return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
def srgb(c):return np.where(c<=.0031308,c*12.92,1.055*np.maximum(c,0)**(1/2.4)-.055)


def recolor(image,color,kind):
    """Retain authored face/garment feature contrast; bake only identity tint."""
    a=np.array(image.convert('RGBA'),dtype=np.float32)/255
    rgb=linear(a[:,:,:3]);target=linear(np.array([int(color[i:i+2],16)/255 for i in (1,3,5)],dtype=np.float32))
    luminance=rgb@np.array([.2126,.7152,.0722],dtype=np.float32)
    valid=(a[:,:,3]>.5)&(luminance>.015)&(luminance<.75)
    if kind=='skin':
        median=np.median(rgb[valid],axis=0)
        # Preserve freckles, veins, lips and eye/nostril cavities; limit the
        # target color shift so the registered skin never becomes flat paint.
        multiplier=np.clip(target/np.maximum(median,.025),.70,1.35)
        result=rgb*multiplier
    elif kind=='cloth':
        # Desaturate the source dye while retaining its seam/button/pocket and
        # denim weave exposure. A different tint is baked for top and trousers.
        center=float(np.median(luminance[valid]))
        detail=np.clip((luminance+.02)/(center+.02),.12,2.2)
        result=target[None,None,:]*detail[:,:,None]
    else:
        # Hair/brow/lash alpha contains authored individual strands; RGB tint
        # cannot change coverage or move details relative to their native UV.
        result=target[None,None,:]*(.72+np.minimum(1,luminance*5))[:,:,None]
    a[:,:,:3]=np.clip(srgb(np.clip(result,0,1)),0,1)
    return Image.fromarray(np.rint(a*255).astype(np.uint8),'RGBA')


def prepare_registered_image(image,role,resolution,color=None,kind=None):
    # Eye atlases include an intentionally transparent cornea UV island. Its
    # blue RGB fill is a placeholder, not visible iris color. Never drop alpha
    # when preparing such a surface, even when no palette bake is requested.
    image=image.convert('RGBA' if color or role=='alpha_basecolor' else 'RGB')
    if image.size!=(resolution,resolution):image=image.resize((resolution,resolution),Image.Resampling.LANCZOS)
    return recolor(image,color,kind) if color else image


def prepare(output,personas=(),size=2048):
    provenance=verify_assets();linen=verify_linen();output=Path(output).resolve()
    if output.exists():raise FileExistsError('Use a fresh texture library: '+str(output))
    output.mkdir(parents=True);records={};source_records={};prepared={}
    manifest=build_manifest(json.loads((REPO/'game/data/personas.json').read_text(encoding='utf-8')))
    keys=list(personas) or list(manifest['characters'])
    def map_image(source,role,color=None,kind=None,resolution=size,provider='MakeHuman',channel=None):
        key=(provider,source,role,color,kind,resolution,channel)
        if key in prepared:return prepared[key]
        origin=provenance if provider=='MakeHuman' else linen
        source_root=VENDOR if provider=='MakeHuman' else LINEN_VENDOR
        entry=origin['files'].get(source)
        if not entry:raise ValueError('Source absent from CC0 provenance: '+source)
        source_records[provider+'/'+source]=entry
        name=hashlib.sha256(repr(key).encode()).hexdigest()[:16]+'_'+role+'.png'
        with Image.open(source_root/source) as image:
            source_size=list(image.size)
            if channel:image=image.getchannel(channel).convert('RGB')
            image=prepare_registered_image(image,role,resolution,color,kind)
            image.save(output/name)
        record={'path':name,'sha256':sha(output/name),'source':source,'source_provider':provider,'source_sha256':entry['sha256'],'source_dimensions':source_size,'dimensions':[resolution,resolution],'color_space':'sRGB' if role in ('basecolor','alpha_basecolor') else 'Non-Color','registration':'authored native UV; no tiling, projection or region relocation' if provider=='MakeHuman' else 'physical-repeat cloth UV; photographed repeat dimensions from Poly Haven metadata','preparation':'Lanczos size preparation'+('; '+kind+' identity palette baked in linear light' if color else '; source channels preserved')+('; source channel '+channel if channel else ''),'reconstructed_from_rgb':False}
        prepared[key]=record
        return record
    for key in keys:
        look=manifest['characters'][key];sex='female' if key in FEMALE or key=='dou' else 'male'
        age='young' if look['age']<38 else 'middleage' if look['age']<63 else 'old'
        stem=f'skins/{age}_asian_{sex}/'
        source=next(n for n in provenance['files'] if n.startswith(stem) and n.endswith('.png'))
        roles={}
        roles['skin']={'material':f'PBR_{key}_skin','maps':{'basecolor':map_image(source,'basecolor',look['skin'],'skin')},'roughness':.57 if age=='old' else .49,'roughness_source':'explicit artistic skin finish; upstream provides no roughness map','subsurface':.065}
        outfit=look['outfit_asset'];cloth=f'clothes/{outfit}/{outfit}'
        for role,color in [('shirt',look['top']),('pants',look['lower'])]:
            roles[role]={'material':f'PBR_{key}_{role}','maps':{'basecolor':map_image(cloth+'_diffuse.png','basecolor',color,'cloth'),'normal':map_image(cloth+'_normal.png','normal'),'ao':map_image(cloth+'_ao.png','ao')},'roughness':.76 if role=='shirt' else .83,'roughness_source':'explicit artistic woven-cotton/denim finish; source has normal/AO but no independent roughness','normal_strength':.55,'normal_convention':'OpenGL +Y tangent normal; native MakeHuman normal atlas, subject to native/render verification'}
        roles['eyes']={'material':f'PBR_{key}_eyes','maps':{'basecolor':map_image('eyes/materials/brown_eye.png','alpha_basecolor',resolution=1024)},'roughness':.17,'roughness_source':'explicit artistic eye gloss','alpha_mode':'MASK','alpha_cutoff':.35,'double_sided':False,'alpha_semantics':'authored RGBA cornea placeholder has alpha0; retain coverage to expose registered iris beneath'}
        shoe=look['shoe_asset'];shoe_stem=f'clothes/{shoe}/{shoe}'
        shoe_maps={'basecolor':map_image(shoe_stem+'_diffuse.png','basecolor')}
        if shoe_stem+'_normal.png' in provenance['files']:shoe_maps['normal']=map_image(shoe_stem+'_normal.png','normal')
        roles['shoes']={'material':f'PBR_{key}_shoes','maps':shoe_maps,'roughness':.49 if shoe=='shoes01' else .71,'roughness_source':'explicit artistic leather or trainer finish','normal_strength':.6}
        brow='eyebrow005' if key in FEMALE else 'eyebrow001'
        for role,source in [('brows',f'eyebrows/{brow}/{brow}.png'),('lashes','eyelashes/eyelashes01/eyelashes01.png')]:
            roles[role]={'material':f'PBR_{key}_{role}','maps':{'basecolor':map_image(source,'alpha_basecolor',look['hair'],'strand',resolution=1024)},'roughness':.67,'alpha_mode':'MASK','alpha_cutoff':.35,'double_sided':True}
        if look['detail'] in ('apron','leather_apron','paint','sewing','flowers','herbs'):
            roles['apron']={'material':f'PBR_{key}_apron','maps':{'basecolor':map_image('rough_linen/diff.jpg','basecolor',look['apron'] if look['detail']!='paint' else '#c8baa0','cloth',provider='Poly Haven'),'normal':map_image('rough_linen/nor_gl.jpg','normal',provider='Poly Haven'),'roughness':map_image('rough_linen/arm.jpg','roughness',provider='Poly Haven',channel='G'),'ao':map_image('rough_linen/arm.jpg','ao',provider='Poly Haven',channel='R')},'roughness':1.0,'roughness_source':'source ARM green channel, explicit source-packed AO/roughness/metalness convention','normal_strength':.18,'normal_convention':'source OpenGL +Y tangent normal','mapping':'metric_cloth','repeat_m':[value/1000 for value in linen['assets']['rough_linen']['dimensions_mm']],'source_asset':'https://polyhaven.com/a/rough_linen','license':'CC0-1.0'}
        records[key]={'roles':roles,'skin_asset':stem.rstrip('/'),'eye_asset':'eyes/high-poly','brow_asset':'eyebrows/'+brow,'lash_asset':'eyelashes/eyelashes01','garment_asset':'clothes/'+outfit,'shoe_asset':'clothes/'+shoe,'uv_registration':'HM08 body, garment and fitted face-component authored UVs, no reprojection','license':'CC0-1.0'}
        print('CHARACTER_TEXTURES '+key,flush=True)
    receipt={'schema':'living_town.character_pbr.v1','source_pipeline':'tools/asset_refinement source-bound CC0 preparation/material/export-verification pattern, adapted to registered character atlases','size':size,'source_module_sha256':sha(__file__),'source_provenance_sha256':sha(VENDOR/'provenance.json'),'license':'CC0-1.0','official_asset_table':provenance['official_asset_table'],'source_files':source_records,'characters':records,'limitations':['Original assets provide diffuse skin and eye maps but no independent skin roughness/normal scan; roughness values are artistic and are not mislabeled as measured maps.','Native garment atlas provides genuine authored normal and AO; no normal was estimated from generated RGB.','Numerical preparation and pixel binding do not establish aesthetic approval.']}
    receipt['source_look_manifest_sha256']=sha(HERE/'manifest.py')
    receipt['linen_receipt_sha256']=sha(LINEN_VENDOR/'source_receipts.json')
    receipt['linen_credit']={'authors':json.loads((LINEN_VENDOR/'rough_linen_info.json').read_text(encoding='utf-8'))['authors'],'license_url':linen['license_url'],'asset_url':linen['assets']['rough_linen']['asset_url']}
    (output/'library_manifest.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return receipt


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--personas',default='');parser.add_argument('--size',type=int,default=2048,choices=[2048,4096]);args=parser.parse_args()
    prepare(args.output,[p for p in args.personas.split(',') if p],args.size)
