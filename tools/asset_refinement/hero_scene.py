"""Reconstructed concept-led cafe vignette and original-asset four-view pack.

Blender --background --threads 6 --python-exit-code 1 --python <this.py>
-- --output <new-directory> --materials <counter-materials> --surfaces <hero-surfaces>.
This constructs new authored assets. It does not load or overwrite the old town.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'art/living_town'
HERE=Path(__file__).resolve().parent


def sha(path):
    with Path(path).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


def module(name):
    spec=importlib.util.spec_from_file_location('hero_'+name,HERE/('hero_'+name+'.py'))
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod


def linear(c):return tuple(((v+.055)/1.055)**2.4 if v>.04045 else v/12.92 for v in c)


def material(name,rgb,rough=.7,metal=0,alpha=1,files=None):
    m=bpy.data.materials.new('Hero_'+name);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*linear(rgb),1)
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;p.inputs['Alpha'].default_value=alpha
    if alpha<1:m.surface_render_method='DITHERED'
    if files:
        uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='MetricUV'
        for slot,path in files.items():
            t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(path),check_existing=True)
            t.image.colorspace_settings.name='sRGB' if slot=='basecolor' else 'Non-Color'
            m.node_tree.links.new(uv.outputs[0],t.inputs['Vector'])
            if slot=='normal':
                n=m.node_tree.nodes.new('ShaderNodeNormalMap');n.uv_map='MetricUV';n.inputs['Strength'].default_value=.45
                m.node_tree.links.new(t.outputs[0],n.inputs['Color']);m.node_tree.links.new(n.outputs[0],p.inputs['Normal'])
            else:m.node_tree.links.new(t.outputs[0],p.inputs['Base Color' if slot=='basecolor' else 'Roughness'])
    return m


class Batch:
    def __init__(self,name,collection):self.name=name;self.collection=collection;self.parts={}
    def poly(self,verts,faces,mat,uvs=None):
        vs,fs,us=self.parts.setdefault(mat,([],[],[]));n=len(vs);vs.extend(verts)
        for i,face in enumerate(faces):
            fs.append(tuple(n+j for j in face))
            if uvs is not None:us.append(uvs[i]);continue
            a,b,c=[Vector(verts[j]) for j in face[:3]];normal=(b-a).cross(c-a)
            axes=[k for k in range(3) if k!=max(range(3),key=lambda k:abs(normal[k]))]
            us.append([(verts[j][axes[0]]/2,verts[j][axes[1]]/2) for j in face])
    def box(self,center,size,mat):
        x,y,z=center;w,d,h=[v/2 for v in size]
        self.poly([(x+sx*w,y+sy*d,z+sz*h) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]],
                  [(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
    def rod(self,a,b,r,mat,n=10):
        a,b=Vector(a),Vector(b);axis=(b-a).normalized();side=axis.cross(Vector((0,0,1)))
        if side.length<.01:side=axis.cross(Vector((0,1,0)))
        side.normalize();other=axis.cross(side).normalized()
        vs=[tuple(p+r*(math.cos(i*math.tau/n)*side+math.sin(i*math.tau/n)*other)) for p in [a,b] for i in range(n)]
        self.poly(vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat)
    def finish(self):
        result=[]
        for mat,(vs,fs,uvs) in self.parts.items():
            mesh=bpy.data.meshes.new(self.name+'_'+mat.name);mesh.from_pydata(vs,[],fs);mesh.materials.append(mat);mesh.update()
            uv=mesh.uv_layers.new(name='MetricUV')
            for face,coords in zip(mesh.polygons,uvs):
                for li,coord in zip(face.loop_indices,coords):uv.data[li].uv=coord
            ob=bpy.data.objects.new(mesh.name,mesh);self.collection.objects.link(ob);ob['authored_asset_version']='concept-hero-1';result.append(ob)
        return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--materials',type=Path,required=True);p.add_argument('--surfaces',type=Path,required=True)
    p.add_argument('--samples',type=int,default=32);p.add_argument('--width',type=int,default=1800)
    p.add_argument('--pbr-library',type=Path,help='Prepared CC0 library manifest; replaces provisional smooth materials')
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);out=a.output.resolve()
    if out.exists():raise FileExistsError(out)
    out.mkdir(parents=True);(out/'renders').mkdir();(out/'input').mkdir()
    # Factory empty file: no inherited cameras/materials/objects from previous town.
    bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.name='Living_Town_Concept_Cafe_Hero'
    scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    collections={}
    for name in ['Architecture','Roof','FrontCover','Interior','Street','Foliage','Lighting']:
        col=bpy.data.collections.new('Hero_'+name);scene.collection.children.link(col);collections[name]=col
    maps=lambda family:{slot:a.materials.resolve()/(family+'_'+slot+'.png') for slot in ['basecolor','roughness','normal']}
    oak=material('CabinetOak',(.6,.42,.23),files=maps('cabinet_oak'))
    granite=material('HonedGranite',(.54,.54,.49),files=maps('honed_granite'))
    scan_reports=[];library=None
    if a.pbr_library:
        library_path=a.pbr_library.resolve();library=json.loads(library_path.read_text(encoding='utf-8'))
        assert library['schema']=='living_town.scanned_pbr_library.v1'
        def scanned(role,name,**settings):
            asset=library['materials'][library['roles'][role]]
            paths={key:library_path.parent/row['path'] for key,row in asset['maps'].items()}
            for key,path in paths.items():assert sha(path)==asset['maps'][key]['sha256'],path
            mat,record=module('pbr').build_scanned_material('Hero_'+name,**paths,repeat_metres=asset['repeat_metres'],**settings)
            record['source_asset']=asset;scan_reports.append(record);return mat
        oak=scanned('cabinet_oak','CabinetOak_Scan',roughness_scale=.82)
        if 'honed_granite' in library['roles']:granite=scanned('honed_granite','HonedGranite_CC0',roughness_scale=.8,normal_strength=.35)
    base_slate={slot:a.surfaces.resolve()/('split_slate_'+slot+'.png') for slot in ['basecolor','roughness']}
    M={'oak':oak,'stone':granite,'iron':material('Iron',(.16,.19,.18),.45,.65),'brass':material('Brass',(.62,.49,.26),.4,.7),
       'glass':material('Glass',(.79,.88,.84),.09,alpha=.12),'ceramic':material('Ceramic',(.88,.85,.76),.25),
       'cane':material('Cane',(.57,.46,.29),.74),'pastry':material('Pastry',(.58,.32,.12),.68),
       'lime':material('Lime',(.86,.83,.75),.92),'granite':material('CutGranite',(.56,.56,.51),.87),
       'blue':material('FadedNavy',(.21,.29,.34),.78),'cream':material('CanvasCream',(.83,.80,.70),.88),
       'sage':material('SageShutter',(.40,.45,.36),.76),'zinc':material('WeatheredZinc',(.39,.43,.44),.53,.4),
       'terracotta':material('Terracotta',(.55,.29,.20),.86),'chalk':material('Chalkboard',(.13,.17,.15),.96)}
    facade=material('FacadeLimewash',(.88,.85,.79),files={s:a.surfaces.resolve()/('facade_limewash_'+s+'.png') for s in ['basecolor','roughness']})
    if library:
        M['lime']=scanned('plaster','Limewash_Scan',tint=(.98,.98,.98),normal_strength=.5)
        facade=M['lime']
        if 'cut_granite' in library['roles']:
            M['granite']=scanned('cut_granite','CutGranite_CC0',normal_strength=.25)
    slates=[material('Slate'+str(i),(.26,.30,.31),files=base_slate) for i in range(3)]
    for i,m in enumerate(slates):
        pbr=m.node_tree.nodes.get('Principled BSDF')
        # Linked textures override socket defaults. Use an actual multiplicative
        # factor so the separate slate courses retain a modest color variation.
        tex=next(n for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image.colorspace_settings.name=='sRGB')
        mix=m.node_tree.nodes.new('ShaderNodeMix');mix.data_type='RGBA';mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
        shade=[.86,.93,1.0][i];mix.inputs[7].default_value=(shade,shade,shade,1)
        m.node_tree.links.new(tex.outputs['Color'],mix.inputs[6]);m.node_tree.links.new(mix.outputs[2],pbr.inputs['Base Color'])
    paving=material('Paving',(.6,.57,.49),files={s:ART/'textures'/('cobbles_'+s+'.png') for s in ['basecolor','roughness','normal']})
    interior_floor=scanned('interior_floor','InteriorFloor_Scan') if library and 'interior_floor' in library['roles'] else paving
    batches={k:Batch(k,collections[k]) for k in ['Architecture','Roof','FrontCover','Interior','Street']}
    A,R,F,I,S=[batches[k] for k in ['Architecture','Roof','FrontCover','Interior','Street']]
    # Main facade: true ground-floor storefront and first-floor apertures.
    holes=[(-2.55,1.65,2.05,1.95),(0,1.36,1.25,2.72),(2.55,1.65,2.05,1.95)]+[(x,4.75,1.08,1.55) for x in [-2.55,0,2.55]]
    xs=sorted(set([-4.3,4.3]+[x+sg*w/2 for x,z,w,h in holes for sg in [-1,1]]));zs=sorted(set([0,6.5]+[z+sg*h/2 for x,z,w,h in holes for sg in [-1,1]]))
    for x0,x1 in zip(xs,xs[1:]):
        for z0,z1 in zip(zs,zs[1:]):
            x,z=(x0+x1)/2,(z0+z1)/2
            if any(abs(x-cx)<w/2-1e-6 and abs(z-cz)<h/2-1e-6 for cx,cz,w,h in holes):continue
            # Front faces get facade-specific contextual UVs.
            before=len(F.parts.get(facade,([],[],[]))[1]);F.box((x,.06,z),(x1-x0,.28,z1-z0),facade)
            vs,fs,uvs=F.parts[facade]
            if not library:
                for j in range(before,len(fs)):uvs[j]=[((vs[k][0]+4.3)/8.6,vs[k][2]/6.5) for k in fs[j]]
    for xx in [-4.22,4.22]:
        A.box((xx,3.2,1.6),(.22,6.4,3.2),M['lime']);R.box((xx,3.2,4.85),(.22,6.4,3.3),M['lime'])
    A.box((0,6.32,3.25),(8.6,.22,6.5),M['lime'])
    A.box((0,3.2,-.10),(8.6,6.4,.20),interior_floor);R.box((0,3.2,3.28),(8.4,6.2,.16),oak)
    for x,z,w,h in holes:
        F.box((x,-.03,z),(w,.035,h),M['glass'])
        for xx in [x-w/2-.07,x+w/2+.07]:F.box((xx,-.12,z),(.14,.38,h+.26),M['granite'])
        for zz in [z-h/2-.07,z+h/2+.07]:F.box((x,-.15,zz),(w+.28,.44,.14),M['granite'])
        frame=M['blue'] if z<3 else M['cream']
        for xx in [x-w/2+.045,x+w/2-.045,x]:F.box((xx,-.075,z),(.065,.075,h),frame)
        F.box((x,-.075,z+.05),(w,.075,.065),frame)
        if z>3:
            for side in [-1,1]:
                sx=x+side*(w/2+.32);F.box((sx,-.12,z),(.46,.07,h),M['sage'])
                for k in range(12):F.box((sx,-.17,z-h/2+.09+k*(h-.15)/12),(.40,.04,.025),M['sage'])
            F.rod((x-w/2-.1,-.45,z-.28),(x+w/2+.1,-.45,z-.28),.022,M['iron'])
            for k in range(7):F.rod((x-w/2+k*w/6,-.45,z-h/2),(x-w/2+k*w/6,-.45,z-.28),.012,M['iron'],6)
    # Corner quoins, skirting and a continuous sign fascia.
    for xx in [-4.25,4.25]:
        for k in range(17):F.box((xx,-.11,.2+k*.37),(.31 if k%2 else .43,.34,.32),M['granite'])
    for side in [-1,1]:F.box((side*2.4625,-.11,.24),(3.675,.35,.46),M['granite'])
    F.box((0,-.25,3.02),(8.35,.24,.55),M['blue'])
    font=bpy.data.fonts.load(str(ART/'external_assets/fonts/SourceSerif4-Regular.ttf'))
    def text(label,loc,size,mat,name,group='FrontCover'):
        cu=bpy.data.curves.new(name,'FONT');cu.body=label;cu.size=size;cu.align_x='CENTER';cu.font=font;cu.extrude=.0015
        ob=bpy.data.objects.new(name,cu);collections[group].objects.link(ob);ob.location=loc;ob.rotation_euler=(math.pi/2,0,0);cu.materials.append(mat)
    text('CAFÉ DU PORT',(0,-.382,2.90),.42,M['cream'],'Cafe_Sign')
    text('CAFÉ  ·  CRÊPES  ·  GLACES',(0,-.38,2.68),.105,M['cream'],'Cafe_Subtitle')
    # Shaped striped awning with a lower valance; individual seams align across the curve.
    for i in range(38):
        x0=-4.15+i*8.3/38;x1=x0+8.3/38;mat=M['cream'] if i%2 else M['blue']
        verts=[]
        for k in range(9):
            t=k/8;verts.extend([(x0,-.25-1.35*t,2.66-.32*t-.10*math.sin(math.pi*t)),(x1,-.25-1.35*t,2.66-.32*t-.10*math.sin(math.pi*t))])
        F.poly(verts,[(2*k,2*k+1,2*k+3,2*k+2) for k in range(8)],mat)
        F.box(((x0+x1)/2,-1.61,2.245),(x1-x0,.04,.19),mat)
    for xx in [-3.9,3.9]:F.rod((xx,-.25,2.65),(xx,-1.6,2.33),.018,M['iron']);F.rod((xx,-1.6,2.33),(xx,-.18,1.95),.014,M['iron'])
    # Sloped overlapping individual slate tiles, not a painted roof grid.
    rng=random.Random(20261019);width=9.1;half=3.5;rise=2.45
    R.poly([(-width/2,-.3,6.45),(width/2,-.3,6.45),(width/2,3.2,8.9),(-width/2,3.2,8.9),(-width/2,6.7,6.45),(width/2,6.7,6.45)],[(0,1,2,3),(3,2,5,4)],M['zinc'])
    rows=19;cols=30
    for side in [-1,1]:
        for row in range(rows):
            t=row/rows;t2=min(1,(row+1.23)/rows)
            # A real lap: the exposed lower edge sits above the head of the
            # previous course. Randomly offset coplanar rows flicker in engines.
            y0=3.2+side*half*(1-t);y1=3.2+side*half*(1-t2);z0=6.45+rise*t+.047;z1=6.45+rise*t2+.035
            for col in range(cols):
                x0=-width/2+(col+.5*(row%2))*width/cols;x1=min(width/2,x0+width/cols-.006)
                if x0>=width/2:continue
                jitter=rng.uniform(-.0005,.0005)
                R.poly([(x0,y0,z0+jitter),(x1,y0,z0+jitter),(x1,y1,z1+jitter),(x0,y1,z1+jitter)],[(0,1,2,3)] if side<0 else [(3,2,1,0)],slates[rng.randrange(3)])
    for y in [-.33,6.73]:R.rod((-4.55,y,6.43),(4.55,y,6.43),.052,M['zinc'])
    F.rod((4.4,-.18,6.42),(4.4,-.18,.2),.045,M['zinc'])
    R.box((2.7,4.6,8.30),(.65,.65,2.5),M['granite']);R.box((2.7,4.6,9.58),(.85,.85,.13),M['zinc'])
    # Pavement and understated adjoining building context.
    # Furniture, entrance and terrace share the exact z=0 walking datum.
    S.box((0,-3.3,-.12),(25,6.6,.24),paving);S.box((0,-6.65,-.11),(25,.28,.32),M['granite'])
    for side,color in [(-1,(.76,.66,.46)),(1,(.78,.78,.71))]:
        mm=material('Neighbour'+str(side),color,.9);xx=side*7.2
        A.box((xx,3.1,3.05),(5.4,6.4,6.1),mm)
        for z in [1.65,4.55]:
            for dx in [-1.45,1.45]:
                A.box((xx+dx,-.13,z),(1.1,.08,1.5),M['blue'])
                for edge in [-.59,.59]:A.box((xx+dx+edge,-.19,z),(.12,.18,1.7),M['granite'])
                A.box((xx+dx,-.20,z-.82),(1.4,.28,.14),M['granite'])
                A.box((xx+dx,-.19,z),(.045,.08,1.45),M['cream']);A.box((xx+dx,-.19,z+.03),(1.04,.08,.045),M['cream'])
        R.poly([(xx-2.8,-.2,6.1),(xx+2.8,-.2,6.1),(xx+2.8,3.1,8.0),(xx-2.8,3.1,8.0),(xx-2.8,6.4,6.1),(xx+2.8,6.4,6.1)],[(0,1,2,3),(3,2,5,4)],slates[1])
    # A rear service partition and lit backbar anchor the interior activity.
    I.box((0,5.4,1.35),(8.1,.18,2.7),M['lime']);I.box((0,5.26,1.45),(4.9,.20,1.95),M['blue'])
    S.box((-3.35,-2.50,.64),(.56,.06,.82),M['chalk'])
    for xx in [-3.64,-3.06]:
        S.rod((xx,-2.50,1.07),(xx,-2.87,.02),.025,oak);S.rod((xx,-2.50,1.07),(xx,-2.14,.02),.025,oak)
    text('CRÊPES\nCAFÉ\nGLACES',(-3.35,-2.54,.84),.095,M['cream'],'Street_Menu','Street')
    for b in batches.values():b.finish()
    furniture=module('furniture');fm={'cabinet_oak':oak,'honed_granite':granite,**{k:M[k] for k in ['iron','brass','glass','ceramic','cane','pastry']}}
    counter=furniture.build_counter(collections['Interior'],origin=(0,4.12,0),materials=fm)
    shelves=[furniture.build_shelf(collections['Interior'],origin=(xx,5.13,0),materials=fm) for xx in [-1.12,1.12]]
    sets=[]
    for loc,rot,col in [((-2.1,-2.2,0),.18,'Street'),((2.1,-2.2,0),-.16,'Street'),((-2.2,2.2,0),.1,'Interior'),((2.2,2.2,0),-.1,'Interior')]:
        sets.append(furniture.build_bistro_set(collections[col],origin=loc,rotation=rot,materials=fm))
    foliage=module('foliage');tree=foliage.build_tree(collections['Foliage'],origin=(-6.0,-3.3,-.04),height=6.2,crown_radius=2.65,seed=20261019)
    plants=[]
    pots=Batch('Planters',collections['Street'])
    for j,x in enumerate([-4.0,4.0]):
        pots.box((x,-.65,.22),(.72,.66,.44),M['terracotta'])
        plants.append(foliage.build_hydrangea(collections['Foliage'],origin=(x,-.65,.43),radius=.43,seed=200+j))
    pots.finish()
    # The furniture helper uses a descriptive local UV name. All shared image
    # materials bind MetricUV explicitly, so harmonize that name before either
    # rendering or exporting; a missing named UV silently samples one texel.
    for mesh in bpy.data.meshes:
        furniture_uv=mesh.uv_layers.get('HeroMetricUV_2m')
        if furniture_uv is not None:furniture_uv.name='MetricUV'
    for obj in collections['Interior'].all_objects:
        if obj.type=='MESH' and any(m and m.name in [oak.name,granite.name] for m in obj.data.materials):
            assert obj.data.uv_layers.get('MetricUV'),obj.name
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=a.samples;scene.cycles.use_denoising=True
    scene.cycles.max_bounces=6;scene.render.threads_mode='FIXED';scene.render.threads=6
    scene.render.resolution_x=a.width;scene.render.resolution_y=round(a.width*.68);scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.view_settings.view_transform='AgX'
    world=bpy.data.worlds.new('Breton_Summer_Sky');world.use_nodes=True;scene.world=world
    env=world.node_tree.nodes.new('ShaderNodeTexEnvironment');env.image=bpy.data.images.load(str(ART/'external_assets/polyhaven/kloofendal_48d_partly_cloudy_puresky_2k.hdr'))
    world.node_tree.links.new(env.outputs[0],world.node_tree.nodes['Background'].inputs[0]);world.node_tree.nodes['Background'].inputs[1].default_value=.4
    sun=bpy.data.lights.new('Warm_Summer_Sun','SUN');sun.energy=2.2;sun.angle=math.radians(7);sun.color=(1,.92,.80)
    so=bpy.data.objects.new(sun.name,sun);collections['Lighting'].objects.link(so);so.rotation_euler=(.55,-.4,-.55)
    lamp=bpy.data.lights.new('Cafe_Soft_Interior','AREA');lamp.energy=230;lamp.color=(1,.76,.50);lamp.shape='RECTANGLE';lamp.size=5;lamp.size_y=3
    ob=bpy.data.objects.new(lamp.name,lamp);collections['Lighting'].objects.link(ob);ob.location=(0,3.2,2.9)
    cam=bpy.data.objects.new('Hero_Camera',bpy.data.cameras.new('Hero_Camera'));collections['Lighting'].objects.link(cam);scene.camera=cam
    def shot(name,loc,target,lens=44):
        cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='PERSP';cam.data.lens=lens
        scene.render.filepath=str(out/'renders'/name);bpy.ops.render.render(write_still=True)
        return {'image':'renders/'+name,'sha256':sha(out/'renders'/name),'position_blender_m':list(loc),'target_blender_m':list(target),'lens_mm':lens}
    shots=[shot('01_cafe_street.png',(10,-16,3.8),(0,1.1,3.9),43)]
    collections['Roof'].hide_render=True;collections['FrontCover'].hide_render=True
    shots.append(shot('02_cafe_interior.png',(1,-10,10),(0,2.8,1.0),47))
    shots.append(shot('03_counter_detail.png',(2.9,1.0,1.85),(0,4.12,1.2),50))
    collections['Roof'].hide_render=False;collections['FrontCover'].hide_render=False
    shots.append(shot('04_facade_detail.png',(3.1,-6.5,3.1),(1.2,0,3.8),50))
    # Export and render the NEW counter alone, retaining its versioned component hierarchy.
    counter_names=counter.get('objects',[])
    counter_objects=[bpy.data.objects[n] for n in counter_names if n in bpy.data.objects]
    assert counter_objects,'Furniture API must return the new counter objects'
    counter_root=bpy.data.objects.get(counter.get('root',''))
    assert counter_root is not None,'Counter export requires its authored hierarchy root'
    for obj in scene.objects:
        if obj.type=='MESH':
            tri=obj.modifiers.new('Portable triangulation','TRIANGULATE');tri.quad_method='BEAUTY';tri.ngon_method='BEAUTY'
    for obj in scene.objects:obj.select_set(False)
    for obj in counter_objects:obj.select_set(True)
    counter_root.select_set(True)
    bpy.context.view_layer.objects.active=counter_objects[0]
    bpy.ops.export_scene.gltf(filepath=str(out/'input/counter.glb'),export_format='GLB',use_selection=True,export_extras=True,export_tangents=True,export_apply=True)
    visible={obj:obj.hide_render for obj in scene.objects if obj.type not in ['LIGHT','CAMERA']}
    for obj in visible:obj.hide_render=(obj not in counter_objects)
    for light in collections['Lighting'].objects:
        if light.type=='LIGHT':light.hide_render=True
    fill=bpy.data.lights.new('Neutral_Counter_Fill','AREA');fill.energy=350;fill.size=5
    fo=bpy.data.objects.new(fill.name,fill);collections['Lighting'].objects.link(fo);fo.location=(0,2,5)
    world.node_tree.nodes['Background'].inputs[1].default_value=.75
    cam.data.type='ORTHO';cam.data.ortho_scale=3.8;scene.render.resolution_x=1024;scene.render.resolution_y=1024;scene.render.film_transparent=True
    views=[]
    for name,loc in [('front',(0,-2,.6)),('left',(-5,4.12,.6)),('back',(0,10,.6)),('right',(5,4.12,.6))]:
        cam.location=loc;cam.rotation_euler=(Vector((0,4.12,.6))-cam.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(out/'input'/(name+'.png'));bpy.ops.render.render(write_still=True)
        views.append({'name':name,'image':'input/'+name+'.png','sha256':sha(out/'input'/(name+'.png')),'camera_position_blender_m':list(loc),'ortho_scale_m':3.8})
    for obj,hidden in visible.items():obj.hide_render=hidden
    for light in collections['Lighting'].objects:light.hide_render=False
    fo.hide_render=True;scene.render.film_transparent=False
    world.node_tree.nodes['Background'].inputs[1].default_value=.4
    scene.render.resolution_x=a.width;scene.render.resolution_y=round(a.width*.68)
    cam.data.type='PERSP';cam.data.lens=43;cam.location=(10,-16,3.8);cam.rotation_euler=(Vector((0,1.1,3.9))-cam.location).to_track_quat('-Z','Y').to_euler()
    for ob in scene.objects:ob.select_set(ob.type in ['MESH','FONT','CURVE','EMPTY'])
    bpy.ops.export_scene.gltf(filepath=str(out/'cafe_hero.glb'),export_format='GLB',use_selection=True,export_extras=True,export_tangents=True,export_apply=True)
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(out/'cafe_hero.blend'))
    report={'schema':'living_town.reconstructed_cafe_hero.v1','status':'BUILT_REQUIRES_VISUAL_REVIEW','ai_inference_executed':False,
            'design_authority':'User-approved idealized concept; existing meshes may be replaced. This is a new cafe/street exemplar, not a regenerated whole town.',
            'concept_sha256':sha(ART/'concept/01_idealized_presentation.png'),'source_modules':{str(f.relative_to(ROOT)):sha(f) for f in [Path(__file__),HERE/'hero_furniture.py',HERE/'hero_foliage.py',HERE/'hero_surfaces.py',HERE/'materials.py',HERE/'hero_pbr.py']},
            'scanned_materials':scan_reports,'pbr_library_sha256':sha(a.pbr_library.resolve()) if library else None,
            'functional_dimensions_m':{'building_width':8.6,'building_depth':6.4,'ground_ceiling':3.2,'door_width':1.25,'door_height':2.72,'awning_clear_height':2.15},
            'counter':counter,'backbar_shelves':shelves,'bistro_sets':sets,'tree':tree,'hydrangeas':plants,'renders':shots,'conditioning_views':views,
            'input_provenance':{'HDRI':json.loads((ART/'external_assets/polyhaven/PROVENANCE.json').read_text()),'font':json.loads((ART/'external_assets/fonts/PROVENANCE.json').read_text())},
            'files':{str(f.relative_to(out)):{'sha256':sha(f),'bytes':f.stat().st_size} for f in out.rglob('*') if f.is_file()}}
    (out/'hero_manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('HERO_READY',out,flush=True)


if __name__=='__main__':main()
