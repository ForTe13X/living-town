"""Original, deterministic Living Town Blender source kit.

Execute through the official Blender Lab MCP with LT_STAGE='study' or 'town'.
Only creates its own scenes. Nothing in game/ is written. Metres; redesigned masterplan.
Beauty cameras are offline presentations, Production_Orthogonal is straight XY.
"""
import bpy, math, json, random, hashlib, time, importlib.util
from pathlib import Path
from collections import defaultdict
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1] if len(ROOT.parents)>1 else ROOT.parent
SOURCE_MAP = REPO/'game/data/map.json'
if not SOURCE_MAP.exists():SOURCE_MAP=ROOT/'source_snapshot/map.json'
TEX = ROOT / 'textures'
STAGE = globals().get('LT_STAGE', 'study')
RNG = random.Random(71126)
S = 1.8
MATS = {}
ROOFS, FRONTS, UPPER, BUILDINGS = [], [], [], []
PONDS=[]
SOURCE_RECTS=[]
REDESIGNED=False
TERRAIN=None
TOPO_PLAN={}
TOPO_PADS={}
TOPO_ROADS={}
INTERIOR_RECORDS=[]
interior_spec=importlib.util.spec_from_file_location('living_town_interiors',ROOT/'tools/interior_design.py')
INTERIOR_MODULE=importlib.util.module_from_spec(interior_spec);interior_spec.loader.exec_module(INTERIOR_MODULE)
SCENE = bpy.data.scenes.new('LT_Study' if STAGE == 'study' else 'Living_Town_Summer')
bpy.context.window.scene = SCENE
SCENE.unit_settings.system = 'METRIC'
SCENE.unit_settings.scale_length = 1
SCENE['purpose'] = 'Offline authored environment. No runtime geometry or projection migration.'
SCENE['source_cell_metres'] = S
SCENE['seed'] = 71126
SCENE['source_head'] = 'f204276'

def coll(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or SCENE.collection).children.link(c)
    return c

WORLD = coll('00_Landscape_and_Streets')
ARCH = coll('01_Buildings')
PROPS = coll('02_Street_Life')
VEG = coll('03_Gardens_and_Trees')
RIG = coll('90_Cameras_and_Light')

def rgba(c):
    if isinstance(c, str):
        c = tuple(int(c[i:i+2],16)/255 for i in (0,2,4))
    # Input palette is sRGB; shader values are linear.
    return tuple(((v+.055)/1.055)**2.4 if v>.04045 else v/12.92 for v in c)+(1,)

def mat(name, color, tex=None, rough=.72, metal=0, emit=0):
    m = bpy.data.materials.new('LT_'+name)
    m.use_nodes=True
    m.diffuse_color=rgba(color)
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=rgba(color)
    p.inputs['Roughness'].default_value=rough
    p.inputs['Metallic'].default_value=metal
    if emit:
        p.inputs['Emission Color'].default_value=rgba(color)
        p.inputs['Emission Strength'].default_value=emit
    if tex:
        tile_sizes={'slate':2.4,'lime_plaster':2,'granite':2,'cobbles':2,'oak':2,'sand':3,'grass':4,'ceramic_tile':1.2,'canvas':1}
        m['tile_size_metres']=tile_sizes[tex]
        ns=m.node_tree.nodes; lk=m.node_tree.links
        bc=TEX/(tex+'_basecolor.png')
        if not bc.exists(): raise FileNotFoundError(bc)
        n=ns.new('ShaderNodeTexImage'); n.image=bpy.data.images.load(str(bc),check_existing=True)
        n.label='Original periodic base color / metric UVs'
        if color != 'ffffff':
            mix=ns.new('ShaderNodeMixRGB'); mix.blend_type='MULTIPLY'; mix.inputs[0].default_value=1
            mix.inputs[2].default_value=rgba(color); lk.new(n.outputs['Color'],mix.inputs[1]); lk.new(mix.outputs[0],p.inputs['Base Color'])
        else: lk.new(n.outputs['Color'],p.inputs['Base Color'])
        for kind in ('roughness','normal'):
            q=ns.new('ShaderNodeTexImage'); q.image=bpy.data.images.load(str(TEX/(tex+'_'+kind+'.png')),check_existing=True)
            q.image.colorspace_settings.name='Non-Color'
            if kind=='normal':
                nm=ns.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value=.42
                lk.new(q.outputs['Color'],nm.inputs['Color']); lk.new(nm.outputs[0],p.inputs['Normal'])
            else: lk.new(q.outputs['Color'],p.inputs['Roughness'])
    MATS[name]=m
    return name

def make_materials():
    for n,t in [('Plaster','lime_plaster'),('Granite','granite'),('Slate','slate'),('Paving','cobbles'),('Oak','oak'),('Sand','sand'),('Grass','grass'),('Tile','ceramic_tile'),('Canvas','canvas')]: mat(n,'ffffff',t)
    mat('Ochre','dfbe82','lime_plaster'); mat('PaleRose','ead7c7','lime_plaster')
    mat('Stone','b1aaa0','granite'); mat('DarkStone','7f817b','granite')
    mat('White','eee8db'); mat('Sage','657b69','oak'); mat('BluePaint','506d7d','oak'); mat('Burgundy','874d43','oak')
    mat('Ink','303d40'); mat('Iron','384744',rough=.36,metal=.72); mat('Zinc','8e9b9d',rough=.37,metal=.65)
    mat('Glass','456568',rough=.19,metal=.12); mat('WindowWarm','cfbd9b',rough=.3,emit=.05)
    gp=MATS['Glass'].node_tree.nodes.get('Principled BSDF');gp.inputs['Transmission Weight'].default_value=0;gp.inputs['Metallic'].default_value=0;gp.inputs['Alpha'].default_value=.28;gp.inputs['Roughness'].default_value=.12;gp.inputs['Base Color'].default_value=rgba('c4d2cb')
    MATS['Glass'].surface_render_method='DITHERED'
    mat('Terracotta','a16a50'); mat('Brick','a47760','granite'); mat('AwningBlue','41677e','canvas')
    mat('Dirt','8a8067','sand'); mat('WetSand','ada892','sand'); mat('Sea','579aaa',rough=.20)
    mat('Courtyard','c1bcb0','cobbles');mat('ClaySlate','b38c72','slate')
    mat('Shallows','78b7b6',rough=.29); mat('Foam','e1e9df',rough=.36)
    mat('Leaf','547245'); mat('LeafLight','6e8954'); mat('LeafDark','344f39'); mat('LeafSilver','8d9a78')
    mat('Trunk','6e6650','oak'); mat('BloomBlue','7d94ab'); mat('BloomPink','b58b9b'); mat('BloomCream','d9d2b7')
    mat('Linen','d5c7ae','canvas'); mat('TealCloth','7c9f9c','canvas'); mat('Cushion','a37564','canvas')
    mat('Brass','b29555',rough=.31,metal=.7); mat('Lamp','ffe4b3',rough=.35,emit=1.5)
    mat('Skin','bf9675'); mat('Hair','594e41'); mat('Shirt','d1c7b2'); mat('Trousers','526a7b')
    grass=MATS['Grass'];ns=grass.node_tree.nodes;lk=grass.node_tree.links;p=ns.get('Principled BSDF')
    old=p.inputs['Base Color'].links[0].from_socket;vc=ns.new('ShaderNodeVertexColor');vc.layer_name='TerrainTint'
    mix=ns.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;lk.new(old,mix.inputs[1]);lk.new(vc.outputs['Color'],mix.inputs[2]);lk.new(mix.outputs[0],p.inputs['Base Color'])
    sea=MATS['Sea'];ns=sea.node_tree.nodes;lk=sea.node_tree.links;p=ns.get('Principled BSDF')
    sea['tile_size_metres']=4
    n=ns.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(TEX/'water_normal.png'),check_existing=True);n.image.colorspace_settings.name='Non-Color'
    normal=ns.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.7;lk.new(n.outputs['Color'],normal.inputs['Color']);lk.new(normal.outputs[0],p.inputs['Normal'])
    mat('PondWater','638e86',rough=.22)
    pond=MATS['PondWater'];pond['tile_size_metres']=4
    ns=pond.node_tree.nodes;lk=pond.node_tree.links;p=ns.get('Principled BSDF')
    n=ns.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(TEX/'water_normal.png'),check_existing=True);n.image.colorspace_settings.name='Non-Color'
    normal=ns.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.16;lk.new(n.outputs['Color'],normal.inputs['Color']);lk.new(normal.outputs[0],p.inputs['Normal'])

class Batch:
    """One mesh per role/material; editable roof/front ownership stays separate."""
    def __init__(self,name,collection,origin=(0,0,0),angle=0):
        self.name=name; self.collection=collection; self.origin=Vector(origin)
        self.angle=angle
        self.parts=defaultdict(lambda:[[],[],[]])
    def poly(self,verts,faces,material,uvs=None):
        vs,fs,us=self.parts[material]; off=len(vs)
        co,si=math.cos(self.angle),math.sin(self.angle)
        vs.extend([(v[0]*co-v[1]*si+self.origin.x,v[0]*si+v[1]*co+self.origin.y,v[2]+self.origin.z) for v in verts])
        fs.extend([tuple(off+i for i in f) for f in faces])
        if uvs is None:
            for f in faces:
                p=[Vector(verts[i]) for i in f]; normal=(p[1]-p[0]).cross(p[2]-p[0]); a=max(range(3),key=lambda x:abs(normal[x]))
                axes=[i for i in range(3) if i!=a]
                us.append([(verts[i][axes[0]]/2,verts[i][axes[1]]/2) for i in f])
        else: us.extend(uvs)
    def box(self,pos,size,material,rot=0):
        x,y,z=pos; a,b,c=[v/2 for v in size]; co,si=math.cos(rot),math.sin(rot)
        vs=[]
        for dx,dy,dz in [(-a,-b,-c),(a,-b,-c),(a,b,-c),(-a,b,-c),(-a,-b,c),(a,-b,c),(a,b,c),(-a,b,c)]:
            vs.append((x+dx*co-dy*si,y+dx*si+dy*co,z+dz))
        self.poly(vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],material)
    def rod(self,p0,p1,r,material,n=10,r2=None):
        p0,p1=Vector(p0),Vector(p1); d=(p1-p0).normalized(); a=d.cross(Vector((0,0,1)))
        if a.length<.01:a=d.cross(Vector((0,1,0)))
        a.normalize(); b=d.cross(a); vs=[]
        for p,rr in ((p0,r),(p1,r if r2 is None else r2)):
            for i in range(n):vs.append(tuple(p+rr*(a*math.cos(i*math.tau/n)+b*math.sin(i*math.tau/n))))
        fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        self.poly(vs,fs,material)
    def ellipsoid(self,p,r,material,n=10,rings=6):
        vs=[]
        for j in range(rings+1):
            lat=-math.pi/2+math.pi*j/rings
            for i in range(n):
                ang=i*math.tau/n
                vs.append((p[0]+r[0]*math.cos(lat)*math.cos(ang),p[1]+r[1]*math.cos(lat)*math.sin(ang),p[2]+r[2]*math.sin(lat)))
        fs=[]
        for j in range(rings):
            for i in range(n):fs.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
        self.poly(vs,fs,material)
    def flush(self,bevel=0):
        out=[]
        for material,(vs,fs,us) in self.parts.items():
            me=bpy.data.meshes.new(self.name+'_'+material); me.from_pydata(vs,[],fs); me.materials.append(MATS[material]); me.update()
            if material.startswith('Leaf') or material.startswith('Bloom'):
                for face in me.polygons:face.use_smooth=True
            uv=me.uv_layers.new(name='MetricUV')
            uvscale=2/MATS[material].get('tile_size_metres',2)
            for p,tex in zip(me.polygons,us):
                for li,t in zip(p.loop_indices,tex):uv.data[li].uv=(t[0]*uvscale,t[1]*uvscale)
            ob=bpy.data.objects.new(self.name+'_'+material,me); self.collection.objects.link(ob)
            if material=='Grass':
                attr=me.color_attributes.new(name='TerrainTint',type='FLOAT_COLOR',domain='CORNER')
                for poly in me.polygons:
                    for li in poly.loop_indices:
                        vx,vy,_=me.vertices[me.loops[li].vertex_index].co
                        t=.82+.09*math.sin(vx*.083+math.sin(vy*.057)*2)+.06*math.cos(vy*.12-vx*.031)
                        attr.data[li].color=(t*.92,t,t*.86,1)
                me.color_attributes.active_color=attr
            if bevel and material not in ('Plaster','Ochre','PaleRose'):
                mod=ob.modifiers.new('Small crafted edges','BEVEL'); mod.width=bevel; mod.segments=2
            out.append(ob)
        self.parts.clear()
        return out

def ground_z(x,y):
    if REDESIGNED:return TERRAIN.design_height(x,y)
    z=.25+max(0,-x-28)*.065+.06*math.sin(x*.12)*math.cos(y*.13)
    if PONDS:
        dist=min(max(abs(x-px),abs(y-py)) for px,py in PONDS)
        if dist<1.0:return -1.0
        if dist<1.8:return -1+(z+1)*(dist-1)/.8
    return z
def xy(cx,cy): return ((cx-32)*S,(24-cy)*S)

def text(name,body,loc,size,material='White',collection=PROPS,rotation=(math.pi/2,0,0)):
    c=bpy.data.curves.new(name,'FONT'); c.body=body; c.align_x='CENTER'; c.align_y='CENTER'; c.size=size; c.extrude=.002
    fp=ROOT/'external_assets/fonts/SourceSerif4-Regular.ttf'
    if not fp.exists():fp=Path('C:/Windows/Fonts/georgia.ttf')
    if fp.exists():c.font=bpy.data.fonts.load(str(fp),check_existing=True)
    c.materials.append(MATS[material]); ob=bpy.data.objects.new(name,c); collection.objects.link(ob); ob.location=loc; ob.rotation_euler=rotation
    return ob

def window(b,x,y,z,w=1,h=1.4,shutters=True,paint='Sage'):
    key=int(abs(x*127+z*313+y*43))%7
    b.box((x,y+.05,z),(w,.025,h),'WindowWarm' if shutters and key==1 else 'Glass')
    if shutters and key in (1,3):
        for side in (-1,1):b.box((x+side*w*.34,y+.075,z),(.22*w,.025,h*.95),'Linen')
    for dx in (-w/2,w/2):b.box((x+dx,y-.04,z),(.075,.14,h+.14),'White')
    for dz in (-h/2,h/2):b.box((x,y-.04,z+dz),(w+.15,.14,.08),'White')
    b.box((x,y-.07,z),(.04,.12,h),'White')
    for dz in (-h/6,h/6):b.box((x,y-.07,z+dz),(w,.12,.035),'White')
    b.box((x,y-.08,z-h/2-.12),(w+.34,.35,.15),'Granite')
    b.box((x,y+.015,z+h/2+.16),(w+.33,.18,.19),'Granite')
    if shutters:
        sw=.35
        for side in (-1,1):
            xx=x+side*(w/2+sw/2+.14)
            b.box((xx,y+.04,z),(sw,.06,h+.02),paint)
            for j in range(8):b.box((xx,y-.012,z-h*.43+j*h*.123),(sw*.84,.045,.035),paint)
            for dz in (-.4,.4):b.box((xx,y-.03,z+dz),(sw,.02,.045),'Iron')

def table(b,x,y,z,r=.48,chairs=True):
    b.rod((x,y,z+.7),(x,y,z+.76),r,'White',n=20)
    b.rod((x,y,z+.06),(x,y,z+.7),.045,'Iron'); b.rod((x,y,z+.035),(x,y,z+.07),.25,'Iron',n=14)
    b.rod((x+.12,y,z+.765),(x+.12,y,z+.78),.10,'White',n=12)
    b.rod((x+.12,y,z+.78),(x+.12,y,z+.87),.055,'White',n=12)
    b.rod((x-.18,y+.1,z+.765),(x-.18,y+.1,z+.94),.045,'Sage',n=9)
    if chairs:
        for ang in (0,math.pi):chair(b,x+math.cos(ang)*.83,y+math.sin(ang)*.83,z,ang+math.pi)

def chair(b,x,y,z,rot=0):
    def p(dx,dy,dz):return (x+dx*math.cos(rot)-dy*math.sin(rot),y+dx*math.sin(rot)+dy*math.cos(rot),z+dz)
    b.rod(p(0,0,.43),p(0,0,.49),.235,'Oak',n=16)
    # Bentwood bistro back and woven seat instead of a rectangular chair block.
    for j in range(7):
        yy=-.18+j*.06;span=math.sqrt(max(0,.215**2-yy**2))
        b.rod(p(-span,yy,.495),p(span,yy,.495),.009,'Linen',n=5)
    for dx in (-.15,.15):
        for dy in (-.15,.15):b.rod(p(dx,dy,.04),p(dx,dy,.44),.023,'Iron',n=6)
        b.rod(p(dx,.18,.4),p(dx,.18,.9),.024,'Iron',n=6)
    pts=[p(math.cos(math.pi*i/12)*.215,.18,.68+math.sin(math.pi*i/12)*.27) for i in range(13)]
    for a,c in zip(pts,pts[1:]):b.rod(a,c,.025,'Oak',n=7)
    for dx in (-.105,0,.105):b.rod(p(dx,.18,.66),p(dx,.18,.86),.013,'Oak',n=6)

def flower_head(b,x,y,z,r,material):
    for j in range(17):
        zz=(j+.5)/17*2-1;phi=j*2.39996;rr=math.sqrt(max(0,1-zz*zz))*r
        px=x+rr*math.cos(phi);py=y+rr*math.sin(phi);pz=z+zz*r*.75
        b.ellipsoid((px,py,pz),(r*.28,r*.27,r*.18),material,n=5,rings=3)

def pot(b,x,y,z,flower=True,scale=1):
    b.rod((x,y,z),(x,y,z+.44*scale),.20*scale,'Terracotta',n=12,r2=.29*scale)
    b.rod((x,y,z+.43*scale),(x,y,z+.48*scale),.30*scale,'Terracotta',n=12)
    for i in range(7):
        a=i*math.tau/7; px=x+math.cos(a)*.21*scale; py=y+math.sin(a)*.21*scale
        b.ellipsoid((px,py,z+.64*scale),(.23*scale,.22*scale,.24*scale),'Leaf',n=7,rings=4)
        if flower:flower_head(b,px,py,z+.86*scale,.15*scale,('BloomBlue','BloomPink','BloomCream')[i%3])

def lamp(b,x,y,z,h=3.1):
    b.rod((x,y,z),(x,y,z+.24),.14,'Iron')
    b.rod((x,y,z+.2),(x,y,z+h),.055,'Iron')
    b.box((x,y,z+h+.19),(.26,.26,.38),'Lamp')
    for dx in (-.145,.145):
        for dy in (-.145,.145):b.rod((x+dx,y+dy,z+h-.02),(x+dx*.7,y+dy*.7,z+h+.4),.018,'Iron',n=6)
    b.rod((x,y,z+h+.38),(x,y,z+h+.51),.23,'Iron',n=4,r2=.02)

def railing(b,p0,p1,z,h=.92):
    x0,y0=p0; x1,y1=p1; count=max(2,int(math.dist(p0,p1)/.7))
    for i in range(count+1):
        t=i/count; x=x0+(x1-x0)*t; y=y0+(y1-y0)*t
        b.rod((x,y,z),(x,y,z+h),.025,'Iron',n=6)
    for zz in (.2,h):b.rod((x0,y0,z+zz),(x1,y1,z+zz),.032,'Iron',n=8)

def gable_roof(b,w,d,z,rise,material='Slate',cx=0,cy=0):
    e=.24; w+=2*e; d+=2*e
    vs=[(cx-w/2,cy-d/2,z),(cx+w/2,cy-d/2,z),(cx+w/2,cy,z+rise),(cx-w/2,cy,z+rise),
        (cx-w/2,cy+d/2,z),(cx+w/2,cy+d/2,z)]
    slope=math.hypot(d/2,rise)
    b.poly(vs,[(0,1,2,3),(3,2,5,4)],material,[[ (0,0),(w/2,0),(w/2,slope/2),(0,slope/2)],[(0,slope/2),(w/2,slope/2),(w/2,0),(0,0)]])
    # Closed 6 cm roof skin exports with a visible eave and correct underside.
    b.poly(vs+[(x,y,zz-.06) for x,y,zz in vs],[(9,8,7,6),(10,11,8,9),(0,6,7,1),(4,5,11,10),(0,3,9,6),(3,4,10,9),(1,7,8,2),(2,8,11,5)],material)
    b.rod((cx-w/2-.04,cy,z+rise+.025),(cx+w/2+.04,cy,z+rise+.025),.09,'Zinc',n=10)
    for side in (-1,1):
        b.rod((cx-w/2,cy+side*d/2,z-.035),(cx+w/2,cy+side*d/2,z-.035),.055,'Zinc',n=8)
        count=max(4,int(slope/.34))
        for j in range(1,count):
            t=j/count; yy=cy+side*d/2*(1-t); zz=z+rise*t+.009
            b.rod((cx-w/2,yy,zz),(cx+w/2,yy,zz),.009,'Ink',n=4)

def roof_surface_height(lx,ly,w,d,h,rise,typology):
    """Upper roof plane in building-local metres, matching the authored mesh.

    Ordinary gables pitch across Y; the rotated villa gable pitches across X.
    Mansard hips have the same outer eave, break ring and short ridge as their
    ten mesh vertices below. This is a construction profile, not audit proof.
    """
    if typology=='mansard_hotel':
        ex,ey=w/2+.25,d/2+.25;bx,by=w*.39,d*.31
        if abs(lx)>ex+1e-8 or abs(ly)>ey+1e-8:raise ValueError('Point lies outside mansard roof')
        if abs(lx)>bx or abs(ly)>by:
            return h+2.3*min((ex-abs(lx))/(ex-bx),(ey-abs(ly))/(ey-by))
        return h+min(3-.7*abs(ly)/by,3-.7*max(0,abs(lx)-w*.28)/(w*.11))
    if abs(lx)>w/2+.24+1e-8 or abs(ly)>d/2+.24+1e-8:raise ValueError('Point lies outside gable roof')
    return h+rise*(1-abs(lx)/(w/2+.24)) if typology=='cross_gable_villa' else h+rise*(1-abs(ly)/(d/2+.24))

def wall_with_holes(b,w,y,h,openings,material):
    xs=sorted(set([-w/2,w/2]+[e for o in openings for e in (o[0]-o[2]/2,o[0]+o[2]/2)]))
    zs=sorted(set([0,h]+[e for o in openings for e in (o[1]-o[3]/2,o[1]+o[3]/2)]))
    xs=[x for x in xs if -w/2-.001<=x<=w/2+.001];zs=[z for z in zs if -.001<=z<=h+.001]
    for x0,x1 in zip(xs,xs[1:]):
        for z0,z1 in zip(zs,zs[1:]):
            x=(x0+x1)/2;z=(z0+z1)/2
            if any(abs(x-o[0])<o[2]/2-.001 and abs(z-o[1])<o[3]/2-.001 for o in openings):continue
            b.box((x,y,z), (x1-x0,.30,z1-z0), material)

def practical_room_lights(record,origin,angle):
    count=0
    for floor in record['floors']:
        for room in floor['rooms']:
            if not room['assets']:continue
            a,b,c,d=room['bounds_m'];lx=(a+c)/2;ly=(b+d)/2
            light=bpy.data.lights.new(room['id']+'_Practical','AREA');light.energy=min(80,max(28,14*math.sqrt((c-a)*(d-b))))
            light.shape='DISK';light.size=.28;light.color=(1,.86,.69)
            ob=bpy.data.objects.new(room['id']+'_Practical',light);bpy.data.collections[room['id']].objects.link(ob)
            ob.location=(origin[0]+lx*math.cos(angle)-ly*math.sin(angle),origin[1]+lx*math.sin(angle)+ly*math.cos(angle),origin[2]+floor['finished_floor_local_z_m']+(2.17 if floor['level']<record['floor_count']-1 else 1.91))
            ob['room_id']=room['id'];ob['purpose']='Native interior practical lighting; engine consumers choose their own light budget.';count+=1
    record['practical_lights']=count
    return count

def building(ident,center,w,d,floors=2,kind='home',front_door=0,base=None,source=None,face='S',source_door=None,yaw_degrees=0,typology='plain_gable',district=None):
    if kind=='halles' and REDESIGNED:return market_hall(ident,center,w,d,yaw_degrees,source,district)
    x,y=center; z=(TOPO_PADS[ident]['pad_base_z_m'] if REDESIGNED else ground_z(x,y)) if base is None else base
    c=coll(ident,ARCH); c['source_ref']=source or 'offline_prototype'; c['footprint_m']=[w,d];c['visual_only']=True
    anchor=bpy.data.objects.new(ident+'_Anchor',None);c.objects.link(anchor);anchor.location=(x,y,z);anchor['kind']=kind
    angle=math.radians(yaw_degrees)+(math.pi if face=='N' else 0)
    def wp(lx,ly):return (x+lx*math.cos(angle)-ly*math.sin(angle),y+lx*math.sin(angle)+ly*math.cos(angle),z)
    anchor.rotation_euler.z=angle
    if face=='N':front_door=-front_door
    main=Batch(ident+'_Shell',c,(x,y,z),angle); front=Batch(ident+'_Front',c,(x,y,z),angle)
    roofc=coll(ident+'_Roof',c);ROOFS.append(roofc)
    roof=Batch(ident+'_RoofParts',roofc,(x,y,z),angle)
    upc=coll(ident+'_UpperFloorCover',c);UPPER.append(upc)
    frontc=coll(ident+'_FrontWall',c);FRONTS.append(frontc);front.collection=frontc
    interiorc=coll(ident+'_Interior',c); interior=Batch(ident+'_Interior',interiorc,(x,y,z),angle)
    h=floors*2.85; rise=max(1.5,min(3.7,d*.38))
    if REDESIGNED and kind in ('work','cannery','netshed'):h=3.8
    upperwalls=Batch(ident+'_UpperWallParts',upc,(x,y,z),angle)
    paint=RNG.choice(['Sage','BluePaint','Sage','Burgundy']);plaster=RNG.choice(['Plaster']*7+['PaleRose']*2+['Ochre'])
    if kind in ('chapel','mairie','wash'):plaster='Granite'
    if kind in ('work','cannery','netshed'):plaster='Stone'
    if kind=='cafe':plaster='Plaster';paint='BluePaint'
    foundation_bottom=TOPO_PADS[ident]['foundation_toe_recommendation_z_m']-z if REDESIGNED else 0
    main.box((0,0,(foundation_bottom+.3)/2),(w+.12,d+.12,.3-foundation_bottom),'Granite')
    interior.box((0,0,.33),(w-.25,d-.25,.10),'Tile' if kind in ('cafe','shop','wash','bakery','creperie') else 'Oak')
    lower=2.85 if floors>1 else h
    def party_spans(side,owned_only=False):
        spans=[]
        for item in SOURCE_RECTS:
            other,ox,oy,ow,od=item[:5];oa=math.radians(item[5]) if len(item)>5 else 0
            if other==ident:continue
            dx,dy=ox-x,oy-y;lx=dx*math.cos(angle)+dy*math.sin(angle);ly=-dx*math.sin(angle)+dy*math.cos(angle)
            rel=(oa-angle)%math.pi
            if min(rel,math.pi-rel)<.015:pass
            elif abs(rel-math.pi/2)<.015:ow,od=od,ow
            else:continue
            if abs(side*w/2-(lx-side*ow/2))>.065:continue
            if not owned_only or ident=='Main_cafe' or (other!='Main_cafe' and ident>other):
                lo=max(-d/2,ly-od/2);hi=min(d/2,ly+od/2)
                if hi>lo:spans.append((lo,hi))
        return spans
    # Actual window holes in side/rear walls let daylight reach segmented rooms.
    # Shared party walls keep one owner and never receive a window opening.
    for side in (-1,1):
        skip=ident.startswith('Study_') and ((ident=='Study_Bakery' and side==1) or (ident=='Study_Home' and side==-1) or ident=='Study_Cafe')
        spans=party_spans(side,True);cuts=sorted(set([-d/2,d/2]+[v for sp in spans for v in sp]))
        candidates=[-d/2+(j+.5)*d/max(1,int(d/3)) for j in range(max(1,int(d/3)))]
        yy_valid=[] if skip else [yy for yy in candidates if not any(lo-.6<yy<hi+.6 for lo,hi in party_spans(side))]
        for level in range(floors):
            level_col=c if level==0 else upc
            loc=wp(side*w/2,0);loc=(loc[0],loc[1],z+level*2.85)
            sb=Batch(ident+'_SideWindows'+str(level),level_col,loc,angle+side*math.pi/2)
            for yy in yy_valid:window(sb,side*yy,-.17,1.38,.85,1.25,kind not in ('work','cannery'),paint)
            sb.flush(.01)
            if ident=='Study_Cafe':continue
            for aa,bb in zip(cuts,cuts[1:]):
                if any(lo<(aa+bb)/2<hi for lo,hi in spans):continue
                loc=wp(side*w/2,(aa+bb)/2);loc=(loc[0],loc[1],z+level*2.85)
                wb=Batch(ident+'_SideWall'+str(side)+'_'+str(level),level_col,loc,angle+side*math.pi/2)
                ops=[(side*(yy-(aa+bb)/2),1.38,.85,1.25) for yy in yy_valid if aa+.5<yy<bb-.5]
                wall_with_holes(wb,bb-aa,0,3.8 if floors==1 and kind in ('work','cannery','netshed') else 2.85,ops,plaster);wb.flush(.01)
    for level in range(floors):
        loc=wp(0,d/2);loc=(loc[0],loc[1],z+level*2.85)
        rb=Batch(ident+'_RearWindows'+str(level),c if level==0 else upc,loc,angle+math.pi)
        xxes=[-w/2+(j+.5)*w/max(1,int(w/3)) for j in range(max(1,int(w/3)))]
        for xx in xxes:window(rb,xx,-.17,1.38,.85,1.25,False,paint)
        wall_with_holes(rb,w,0,3.8 if floors==1 and kind in ('work','cannery','netshed') else 2.85,[(xx,1.38,.85,1.25) for xx in xxes],plaster)
        rb.flush(.01)
    commercial=kind in ('cafe','shop','bakery','creperie','halles','hotel') or typology=='shop_house'
    doorx=max(-w/2+.6,min(w/2-.6,front_door));ops=[(doorx,1.15,1.08,2.3)]
    count=max(1,int(w/2.6));positions=[-w/2+(i+.5)*w/count for i in range(count)]
    for level in range(floors):
        for xx in positions:
            if level==0 and abs(xx-doorx)<1.5:continue
            ww=min(1.8 if commercial and level==0 else 1.0,w/count*.55)
            hh=1.75 if commercial and level==0 else 1.35
            zz=1.37+level*2.85
            ops.append((xx,zz,ww,hh));window(front,xx,-d/2-.08,zz,ww,hh,not(commercial and level==0),paint)
    wall_with_holes(front,w,-d/2,h,ops,plaster)
    # Wooden door, transom, panel relief and brass knob.
    front.box((doorx,-d/2-.015,1.12),(.96,.11,2.24),paint)
    front.box((doorx,-d/2-.085,1.58),(.66,.025,.93),'Glass')
    for dx in (-.49,.49):front.box((doorx+dx,-d/2-.07,1.15),(.11,.20,2.45),'Granite')
    front.box((doorx,-d/2-.07,2.38),(1.18,.20,.18),'Granite')
    for dx in (-.23,.23):front.box((doorx+dx,-d/2-.08,.47),(.32,.035,.5),paint)
    front.ellipsoid((doorx+.33,-d/2-.17,1.0),(.037,.04,.037),'Brass',n=8,rings=4)
    if REDESIGNED:
        nstep=2
        for _ in range(3):
            ex,ey,_=wp(doorx,-d/2-nstep*.28)
            outside=ground_z(ex,ey);nstep=max(1,min(8,math.ceil(max(.05,z+.30-outside)/.16)))
        step_rise=(z+.30-outside)/nstep
        for j in range(nstep):
            top=outside-z+step_rise*(j+1);bottom=min(outside-z-.10,foundation_bottom)
            front.box((doorx,-d/2-(nstep-j-.5)*.28,(top+bottom)/2),(1.34,.285,top-bottom),'Granite')
    else:front.box((doorx,-d/2-.38,.15),(1.34,.67,.3),'Granite')
    # Quoins, plinth and cornice, with subtle repeated masonry scale.
    for side in (-1,1):
        for j in range(int(h/.43)):
            front.box((side*(w/2-.12),-d/2-.06,.22+j*.43),(.45 if j%2 else .62,.16,.38),'Granite')
    front.box((0,-d/2-.1,h-.10),(w+.25,.32,.20),'White')
    front.box((0,-d/2-.07,.42),(w,.1,.17),'Granite')
    for level in range(1,floors):front.box((0,-d/2-.06,level*2.85-.08),(w,.12,.12),'Granite')
    if kind in ('belleepoque','hotel','mairie'):
        for level in range(1,floors):
            zz=level*2.85+.13
            front.box((0,-d/2-.43,zz),(w*.82,.84,.12),'Granite')
            railing(front,(-w*.40,-d/2-.82),(w*.40,-d/2-.82),zz+.06,.8)
            for xx in (-w*.35,w*.35):front.rod((xx,-d/2-.1,zz-.5),(xx,-d/2-.7,zz),.035,'Iron',n=6)
    if kind in ('cafe','creperie','whitehouse'):
        for xx in positions[::2]:
            front.box((xx,-d/2-.35,3.48),(.92,.38,.20),'Terracotta')
            for j in range(5):front.ellipsoid((xx-.36+j*.18,-d/2-.35,3.65),(.15,.14,.14),'Leaf',n=8,rings=5)
            for j in range(4):front.ellipsoid((xx-.3+j*.2,-d/2-.38,3.76),(.1,.1,.09),'BloomPink',n=8,rings=5)
    # Gable end masonry and removable pitched roof.
    if typology=='mansard_hotel':
        rise=3.0
        vs=[(-w/2-.25,-d/2-.25,h),(w/2+.25,-d/2-.25,h),(w/2+.25,d/2+.25,h),(-w/2-.25,d/2+.25,h),
            (-w*.39,-d*.31,h+2.3),(w*.39,-d*.31,h+2.3),(w*.39,d*.31,h+2.3),(-w*.39,d*.31,h+2.3),(-w*.28,0,h+3),(w*.28,0,h+3)]
        roof.poly(vs,[(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,9,8),(7,8,9,6),(4,8,7),(5,6,9)],'Slate')
        for yy in (-d/2-.3,d/2+.3):roof.rod((-w/2,yy,h),(w/2,yy,h),.065,'Zinc',n=8)
    elif typology=='cross_gable_villa':
        cr=Batch(ident+'_FrontGableRoof',roofc,(x,y,z),angle+math.pi/2)
        gable_roof(cr,d,w,h,rise,'ClaySlate' if kind in ('cottage','whitehouse') else 'Slate');cr.flush()
        for yy in (-d/2,d/2):roof.poly([(-w/2,yy,h),(w/2,yy,h),(0,yy,h+rise)],[(0,1,2)],plaster)
        window(roof,0,-d/2-.08,h+rise*.32,.9,1.15,False)
        # Glazed veranda, with terrace rail and slim white-painted posts.
        for xx in (-w*.42,0,w*.42):front.rod((xx,-d/2-1.15,.3),(xx,-d/2-1.15,2.55),.045,'White',n=8)
        front.box((0,-d/2-.65,.2),(w*.9,1.3,.16),'Granite')
        front.box((0,-d/2-.65,2.6),(w*.94,1.4,.15),'White')
        railing(front,(-w*.44,-d/2-1.32),(w*.44,-d/2-1.32),2.7,.72)
        for side in (-1,1):front.box((side*w*.42,-d/2-.60,1.4),(.025,1.1,2.05),'Glass')
    else:
        for sx in (-1,1):
            xx=sx*w/2;roof.poly([(xx,-d/2,h),(xx,d/2,h),(xx,0,h+rise)],[(0,1,2)],plaster)
        gable_roof(roof,w,d,h,rise,'ClaySlate' if kind in ('cottage','whitehouse') else 'Slate')
    dormers=max(1,int(w/5.5)) if floors>1 and typology not in ('plain_gable','cross_gable_villa') and kind not in ('work','cannery','netshed','halles') else 0
    for j in range(dormers):
        xx=-w/2+(j+1)*w/(dormers+1); yy=-d*.34 if typology=='mansard_hotel' else -d*.25; zz=h+rise*.5
        roof.box((xx,yy,zz+.35),(1.12,.95,1.05),'Plaster');gable_roof(roof,1.15,1.0,zz+.87,.52,cx=xx,cy=yy)
        window(roof,xx,yy-.51,zz+.38,.70,.78,False)
    chimney_count=2 if typology=='mansard_hotel' else (0 if kind in ('netshed','halles') else 1+int(sum(map(ord,ident))%4==0))
    chimney_records=[];roofc['chimney_count']=chimney_count
    for index,sx in enumerate((-1,1)[:chimney_count]):
        xx=sx*(w/2-.55);chz=h+rise-.35
        # Preserve the original shaft top, cap, pots and XY. The former uniform
        # ridge-based foot floated over mansard/villa slopes, and left gaps at
        # the downslope corners of ordinary gables. Extend only the lower body
        # through the least roof height across its actual square footprint.
        samples=[roof_surface_height(xx+dx,.35+dy,w,d,h,rise,typology)
            for dx in (-.34,0,.34) for dy in (-.34,0,.34)]
        body_bottom=min(samples)-.10;body_top=chz+1.3
        chimney_id=ident+f'_Chimney_{index:02d}'
        shaft=Batch(chimney_id+'_Body',roofc,(x,y,z),angle)
        shaft.box((xx,.35,(body_bottom+body_top)/2),(.68,.68,body_top-body_bottom),'Granite')
        wx,wy,_=wp(xx,.35)
        body_objects=shaft.flush()
        for ob in body_objects:
            ob['asset_role']='chimney_body';ob['chimney_id']=chimney_id;ob['building_id']=ident
            ob['roof_collection']=roofc.name;ob['chimney_center_world_xy']=[wx,wy]
            ob['chimney_width_m']=.68;ob['chimney_yaw_degrees']=math.degrees(angle)
            ob['chimney_bottom_local_z_m']=body_bottom;ob['chimney_top_local_z_m']=body_top
        chimney_records.append({'id':chimney_id,'body_objects':[ob.name for ob in body_objects],
            'center_local_xy_m':[xx,.35],'width_m':.68,'body_bottom_local_z_m':body_bottom,
            'body_top_local_z_m':body_top,'roof_min_local_z_m':min(samples),'embed_m':.10})
        for j in range(5):roof.box((xx,.35,chz+j*.27),(.71,.71,.035),'DarkStone')
        course=chz-.27
        while course>body_bottom+.04:
            roof.box((xx,.35,course),(.71,.71,.035),'DarkStone');course-=.27
        roof.box((xx,.35,chz+1.36),(.84,.84,.16),'Granite')
        for dx in (-.18,.18):roof.rod((xx+dx,.35,chz+1.4),(xx+dx,.35,chz+1.7),.11,'Terracotta',n=10)
    # Downpipe belongs to facade rather than roof.
    front.rod((w/2-.22,-d/2-.2,.25),(w/2-.22,-d/2-.2,h-.15),.045,'Zinc',n=8)
    sign={'cafe':'CAFÉ DES MARÉES','shop':'ÉPICERIE','library':'BIBLIOTHÈQUE','bakery':'BOULANGERIE','creperie':'CRÊPERIE','mairie':'MAIRIE','hotel':'HÔTEL DE LA PLAGE','halles':'LES HALLES','cannery':'CONSERVERIE','work':'ATELIER DU PORT','wash':'BAINS PUBLICS','netshed':'FILETS & CORDAGES'}.get(kind)
    if sign:
        sw=min(w-.55,11)
        front.box((0,-d/2-.16,2.63),(sw,.16,.44),paint)
        sx,sy,_=wp(0,-d/2-.255)
        text(ident+'_Sign',sign,(sx,sy,z+2.64),min(.29,sw/max(1,len(sign))*.9),'White',frontc,(math.pi/2,0,angle))
    if commercial and kind!='halles' and (kind in ('cafe','shop','bakery','creperie','hotel') or sum(map(ord,ident))%3==0):
        # Stripes are original geometric cloth bands; no borrowed pixels.
        aw=min(w-.7,13.8); n=max(4,int(aw/.3));ay=-d/2
        for i in range(n):
            x0=-aw/2+i*aw/n;x1=x0+aw/n
            vs=[]
            for j in range(7):
                t=j/6;yy=ay-.15-1.5*t;zz=2.5-.35*t-.075*math.sin(t*math.pi)
                vs.extend([(x0,yy,zz),(x1,yy,zz)])
            front.poly(vs,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(6)],'Canvas' if i%2==0 else 'AwningBlue')
            front.box(((x0+x1)/2,ay-1.65,2.06),(aw/n,.05,.18),'Canvas' if i%2==0 else 'AwningBlue')
        for xx in (-aw/2,aw/2):front.rod((xx,ay,1.9),(xx,ay-1.6,2.15),.025,'Iron',n=6)
    # Per-room architecture, furniture and decoration on every declared floor.
    interior_record=INTERIOR_MODULE.build_interior(globals(),ident,interiorc,upc,(x,y,z),angle,w,d,floors,kind,doorx)
    practical_room_lights(interior_record,(x,y,z),angle)
    INTERIOR_RECORDS.append(interior_record)
    if kind=='halftimber':
        for xx in (-w/2+.25,0,w/2-.25):front.box((xx,-d/2-.18,h/2),(.16,.13,h),'Trunk')
        for zz in (2.8,h-.2):front.box((0,-d/2-.18,zz),(w,.13,.15),'Trunk')
        front.rod((-w/2+.25,-d/2-.2,2.9),(0,-d/2-.2,h-.25),.07,'Trunk',n=4)
        front.rod((0,-d/2-.2,h-.25),(w/2-.25,-d/2-.2,2.9),.07,'Trunk',n=4)
    if kind=='mairie':
        front.rod((0,-d/2-.21,h-1.05),(0,-d/2-.28,h-1.05),.48,'White',n=24)
        front.rod((0,-d/2-.30,h-1.05),(0,-d/2-.30,h-.73),.022,'Iron',n=6)
        front.rod((0,-d/2-.30,h-1.05),(.24,-d/2-.30,h-1.15),.022,'Iron',n=6)
    if kind=='chapel':
        for side in (-1,1):
            for yy in (-d*.3,0,d*.3):
                main.box((side*(w/2+.27),yy,1.8),(.58,.7,3.6),'Granite')
                main.box((side*(w/2+.32),yy,3.56),(.72,.8,.18),'Stone')
        tw=min(w*.55,2.4); tx=0;ty=d*.12
        main.box((tx,ty,h+1.5),(tw,tw,3.8),'Granite')
        for a in (-1,1):main.box((tx,ty+a*(tw/2+.01),h+2.1),(.65,.04,1.3),'Ink')
        z0=h+3.4;vs=[(-tw*.7,ty-tw*.7,z0),(tw*.7,ty-tw*.7,z0),(tw*.7,ty+tw*.7,z0),(-tw*.7,ty+tw*.7,z0),(0,ty,z0+4)]
        roof.poly(vs,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],'Slate')
        roof.rod((0,ty,z0+4),(0,ty,z0+4.8),.035,'Iron');roof.rod((-.23,ty,z0+4.5),(.23,ty,z0+4.5),.035,'Iron')
    if kind=='windmill':
        for a in (0,math.pi/2,math.pi,math.pi*1.5):
            dx=math.cos(a)*3.3;dz=math.sin(a)*3.3
            roof.rod((0,-d/2-.6,h),(dx,-d/2-.6,h+dz),.08,'Trunk')
            for j in range(3):roof.rod((dx*.4,-d/2-.6,h+dz*.4+j*.14),(dx,-d/2-.6,h+dz+j*.14),.06,'Oak')
    main.flush(.018);front.flush(.012);roof.flush();interior.flush(.012)
    info={'interior_room_count':interior_record['room_count'],'interior_furnishing_count':interior_record['furnishing_count'],'id':ident,'kind':kind,'center_m':[x,y,z],'footprint_m':[w,d],'floors':floors,'source_ref':source,'collection':c.name,'roof_collection':roofc.name,'front_collection':frontc.name,'upper_cover_collection':upc.name,'door_local_x':doorx,'front_face':face,'yaw_degrees':yaw_degrees,'typology':typology,'district':district,'chimneys':chimney_records}
    if REDESIGNED:info.update({'pad_base_z_m':z,'finished_floor_z_m':z+.38,'foundation_toe_z_m':z+foundation_bottom,'entry_step_count':nstep})
    if source_door:
        sx,sy=source_door;info['source_door_cell']=[sx,sy];info['source_door_center_m']=list(xy(sx+.5,sy+.5))
        info['facade_threshold_m']=[x+doorx*(1 if face=='S' else -1),y+(-d/2 if face=='S' else d/2)]
        info['door_anchor_note']='Source center is 0.9m inside facade boundary; short art-only approach connector records the offset.'
    BUILDINGS.append(info)
    return info

def tree(b,x,y,z=None,scale=1):
    z=ground_z(x,y) if z is None else z;h=6.0*scale
    rrng=random.Random(71126+int(x*37+y*113))
    b.rod((x,y,z),(x+.16*scale,y,z+h*.78),.21*scale,'Trunk',n=9,r2=.055*scale)
    for i in range(7):
        a=i*2.4+rrng.random()*.5;rr=(1.0+rrng.random()*.8)*scale
        zz=z+h*(.62+rrng.random()*.23);px=x+math.cos(a)*rr;py=y+math.sin(a)*rr
        base=(x+.1*scale,y,z+h*(.36+i*.045))
        b.rod(base,(px,py,zz),.075*scale,'Trunk',n=7,r2=.022*scale)
        for j in range(9):
            aa=j*2.4+i;rad=rrng.uniform(.15,.9)*scale
            qx=px+math.cos(aa)*rad;qy=py+math.sin(aa)*rad;qz=zz+rrng.uniform(-.38,.65)*scale
            if j%3==0:b.rod((px,py,zz-.3*scale),(qx,qy,qz),.022*scale,'Trunk',n=5,r2=.007*scale)
            leafsize=rrng.uniform(.48,.78)*scale
            b.ellipsoid((qx,qy,qz),(leafsize,leafsize*.85,leafsize*.73),['Leaf','LeafLight','LeafDark','Leaf'][j%4],n=7,rings=4)

def person(b,x,y,z,scale=1,angle=0):
    # Small original static scale figures, not rigged inhabitants or gameplay evidence.
    b.ellipsoid((x,y,z+1.53*scale),(.13*scale,.12*scale,.17*scale),'Skin',n=8,rings=5)
    b.ellipsoid((x,y+.025,z+1.64*scale),(.14*scale,.12*scale,.08*scale),'Hair',n=8,rings=4)
    b.rod((x,y,z+.78*scale),(x,y,z+1.35*scale),.19*scale,RNG.choice(['Shirt','Sage','BluePaint','Burgundy']),n=8,r2=.22*scale)
    for side in (-1,1):
        b.rod((x+side*.10,y,z+.12*scale),(x+side*.09,y,z+.85*scale),.068*scale,'Trousers',n=8)
        b.rod((x+side*.24,y,z+.84*scale),(x+side*.22,y,z+1.28*scale),.055*scale,'Skin',n=7)
        b.box((x+side*.1,y-.06,z+.07),(.14,.30,.14),'Ink')

def ribbon(b,points,width,material='Paving',zoffset=.03):
    # Dense stations let road surfaces follow the authored grades between plan vertices.
    sampled=[]
    for a,c in zip(points,points[1:]):
        length=math.hypot(c[0]-a[0],c[1]-a[1]);count=max(1,math.ceil(length/.65))
        sampled.extend([(a[0]+(c[0]-a[0])*i/count,a[1]+(c[1]-a[1])*i/count) for i in range(count)])
    if points:sampled.append(points[-1])
    points=sampled
    vs=[]
    for i,(x,y) in enumerate(points):
        prev=Vector(points[max(0,i-1)]);nxt=Vector(points[min(len(points)-1,i+1)])
        t=(nxt-prev).normalized();n=Vector((-t.y,t.x))*width/2
        for side in (-1,1):
            xx=x+n.x*side;yy=y+n.y*side;offset=zoffset
            if REDESIGNED:
                dist=TERRAIN.rect_distance(xx,yy,TERRAIN.QUAY_RECT)
                offset*=.1+.9*min(1,dist/2)
            vs.append((xx,yy,ground_z(xx,yy)+offset))
    b.poly(vs,[(i*2,i*2+2,i*2+3,i*2+1) for i in range(len(points)-1)],material)

def catmull(pts,steps=8):
    pts=[pts[0]]+pts+[pts[-1]];out=[]
    for i in range(1,len(pts)-2):
        p0,p1,p2,p3=[Vector(p) for p in pts[i-1:i+3]]
        for j in range(steps):
            t=j/steps;out.append(tuple(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)))
    out.append(tuple(pts[-2]));return out

def camera(name,loc,target,lens=45,ortho=None):
    d=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,d);RIG.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    d.lens=lens;d.clip_end=600
    if ortho:d.type='ORTHO';d.ortho_scale=ortho
    return ob

def lighting():
    w=bpy.data.worlds.new('LT_Atlantic_Summer');w.use_nodes=True;bg=w.node_tree.nodes.get('Background');bg.inputs[0].default_value=rgba('cbdbe2');bg.inputs[1].default_value=.45;SCENE.world=w
    hdri=ROOT/'external_assets/polyhaven/kloofendal_48d_partly_cloudy_puresky_2k.hdr'
    if hdri.exists():
        ns=w.node_tree.nodes;lk=w.node_tree.links;env=ns.new('ShaderNodeTexEnvironment');env.image=bpy.data.images.load(str(hdri),check_existing=True)
        mapping=ns.new('ShaderNodeMapping');mapping.inputs['Rotation'].default_value[2]=.65;coords=ns.new('ShaderNodeTexCoord')
        lk.new(coords.outputs['Generated'],mapping.inputs['Vector']);lk.new(mapping.outputs['Vector'],env.inputs['Vector']);lk.new(env.outputs['Color'],bg.inputs[0])
        w['hdri_source']='Poly Haven CC0 / Kloofendal 48d partly cloudy pure sky / provenance in external_assets/polyhaven'
    ld=bpy.data.lights.new('Northwest_summer_sun','SUN');ld.energy=2.1;ld.angle=math.radians(2.5);lo=bpy.data.objects.new('Northwest_summer_sun',ld);RIG.objects.link(lo);lo.rotation_euler=(.55,-.65,-.65)
    a=bpy.data.lights.new('Broad_sky_fill','AREA');a.energy=1800;a.shape='DISK';a.size=40;ao=bpy.data.objects.new('Broad_sky_fill',a);RIG.objects.link(ao);ao.location=(-15,-20,45)
    SCENE.render.engine='CYCLES';SCENE.cycles.samples=24;SCENE.cycles.use_denoising=True
    SCENE.render.resolution_x=1800;SCENE.render.resolution_y=1200;SCENE.render.resolution_percentage=100
    SCENE.render.image_settings.file_format='PNG';SCENE.render.film_transparent=False
    SCENE.view_settings.view_transform='AgX'
    try:SCENE.view_settings.look='AgX - Medium High Contrast'
    except TypeError:pass
    SCENE.view_settings.exposure=.1
    SCENE.render.threads_mode='AUTO'

def study():
    make_materials();lighting()
    b=Batch('Study_Pavement',WORLD);b.box((0,0,-.18),(28,21,.36),'Paving');b.flush()
    for ident,center,w,kind in [('Study_Bakery',(-8,0),6,'bakery'),('Study_Cafe',(0,0),10,'cafe'),('Study_Home',(8,0),6,'home')]:building(ident,center,w,8,2,kind,base=0)
    p=Batch('Study_StreetFurniture',PROPS)
    for x in (-3.1,3.1):table(p,x,-6,.01,.55);pot(p,x+1.1,-5.2,.01)
    lamp(p,-11,-5.5,0);lamp(p,11,-5.5,0);p.flush(.014)
    v=Batch('Study_Hydrangeas',VEG);pot(v,-10.5,-4.7,0,True,1.2);v.flush()
    SCENE.camera=camera('Study_Exterior',(23,-33,23),(0,0,3),ortho=30)
    camera('Study_Cutaway',(17,-22,22),(0,0,1.7),ortho=26)
    camera('Study_Orthogonal',(0,0,80),(0,0,0),ortho=28)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'living_town_building_study.blend'))
    manifest()

def landscape(data):
    b=Batch('Coastal_Terrain',WORLD)
    PONDS.extend([xy(a+.5,c+.5) for a,c in data['water'] if a<59])
    vs=[];nx,ny=150,200
    for j in range(ny+1):
        y=-160+j*320/ny
        edge=42.8+1.2*math.sin(y*.07)
        for i in range(nx+1):
            x=-150+(edge+150)*i/nx;vs.append((x,y,ground_z(x,y)))
    b.poly(vs,[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i) for j in range(ny) for i in range(nx)],'Grass')
    # Continuous quiet beach, wide water and shoreline with measurable elevation.
    vv=[]
    for j in range(101):
        y=-160+j*3.2;edge=42.8+1.2*math.sin(y*.07)
        for x,z in [(edge,.22),(46.5+.6*math.sin(y*.07),-.25),(50.4+.25*math.sin(y*.12),-.87)]:vv.append((x,y,z))
    b.poly(vv,[(j*3+k,j*3+k+1,(j+1)*3+k+1,(j+1)*3+k) for j in range(100) for k in range(2)],'Sand')
    b.box((150,0,-1.03),(230,400,.22),'Sea')
    for px,py in PONDS:b.box((px,py,-.76),(1.82,1.82,.035),'Shallows')
    # Broken surf ribbons avoid a straight decorative border.
    for k in range(2):
        v=[]
        for j in range(160):
            y=-65+j*.82;x=50.5+.25*math.sin(y*.12)+k*1.4+.2*math.sin(y*1.3+k)
            v.extend([(x,y,-.884+k*.009),(x+.07+.03*math.sin(j),y,-.884+k*.009)])
        b.poly(v,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(159) if (j+k*3)%19<6],'Foam')
    b.flush()
    roads=Batch('Street_Network',WORLD)
    # Calm, continuous stone/gravel civic ground gives enclosure rather than
    # isolated buildings standing in a uniform lawn. This is authored art only.
    surf=[]
    for j in range(57):
        yy=-24+j*.9
        for i in range(75):
            xx=-30+i*.9;surf.append((xx,yy,ground_z(xx,yy)+.012))
    roads.poly(surf,[(j*75+i,j*75+i+1,(j+1)*75+i+1,(j+1)*75+i) for j in range(56) for i in range(74)],'Courtyard')
    # Core transverse route plus district loops and narrow lanes.
    import importlib.util
    spec=importlib.util.spec_from_file_location('lt_streets',ROOT/'tools/plan_streets.py');planner=importlib.util.module_from_spec(spec);spec.loader.exec_module(planner)
    paths=planner.plan_streets(data)
    for path in paths:ribbon(roads,path['points'],path['width'])
    # Each frontage gets a modest pavement apron connected to its true approach.
    for a in list(data['areas'].values())+[{'rect':l['pos']+l['footprint']} for l in data['solid_lots']]:
        if a.get('type')=='plaza':continue
        ax,ay,ww,dd=a['rect'];xx,yy=xy(ax+ww/2,ay+dd)
        roads.box((xx,yy-.85,ground_z(xx,yy)+.045),(ww*S+.35,1.7,.075),'Paving')
    # Plaza occupies the source plaza footprint, rather than an unrelated new square.
    roads.box((0,0,ground_z(0,0)+.045),(14.4,10.8,.08),'Paving')
    # Promenade stays on dry ground, with simple steps down to the broad beach.
    for j in range(100):
        y=-62+j*1.25;x=41.5+.8*math.sin(y*.07);z=ground_z(x,y)
        roads.box((x,y,z+.06),(3.2,1.28,.12),'Paving')
    roads.flush()
    p=Batch('Seafront_Masonry',WORLD)
    for j in range(125):
        y=-62+j; x=43.0+.8*math.sin(y*.07)
        p.box((x,y,-.2),(.65,1.02,1),'Granite')
        p.box((x,y,.35),(.83,1.02,.15),'Granite')
        if j%9==0:lamp(p,x-1.1,y,.35)
    for y in (-30,-4,20):
        x=43.0+.8*math.sin(y*.07)
        for j in range(6):p.box((x+.3+j*.42,y,.25-j*.15),(.45,2.3,.24),'Granite')
    p.flush(.012)

def boat(b,x,y,z,scale=1):
    # Original clinker-like small fishing hull, not a sourced game asset.
    ring=[(-.55,-2),(.55,-2),(.9,-1),(.85,1),(.45,2),(0,2.5),(-.45,2),(-.85,1),(-.9,-1)]
    vs=[(x+xx*scale,y+yy*scale,z) for xx,yy in ring]+[(x+xx*.7*scale,y+yy*.9*scale,z-.5*scale) for xx,yy in ring]
    b.poly(vs,[(i,(i+1)%9,(i+1)%9+9,i+9) for i in range(9)]+[tuple(range(9,18))],'BluePaint')
    b.box((x,y,z-.03),(1.3*scale,3.3*scale,.12),'Oak')
    b.box((x,y-.7*scale,z+.55*scale),(1.0*scale,1.0*scale,1.0*scale),'White')
    b.box((x,y-1.21*scale,z+.65*scale),(.8*scale,.03,.45*scale),'Glass')
    b.rod((x,y+.3*scale,z),(x,y+.3*scale,z+3.6*scale),.045*scale,'Oak')
    b.rod((x,y-1.8*scale,z+.4*scale),(x,y+.3*scale,z+3.4*scale),.012,'Linen',n=5)
    for yy in (-1.7,1.4):b.box((x,y+yy*scale,z+.2), (1.35*scale,.18,.16),'Oak')

def harbor():
    p=Batch('Harbor_Quay_and_Work',WORLD)
    # The source dock remains at (56..60,7..12); eastward quay is visual-only.
    x,y=xy(58,9.5);p.box((x+7,y,.0),(20,10,1.7),'Granite');p.box((x+7,y,.9),(20.3,10.3,.15),'Paving')
    for i in range(13):
        yy=y-5+i*.8;p.box((x+17.1,yy,.1),(.3,.43,1.6),'Trunk')
    for xx in (x+1,x+7,x+13):
        for yy in (y-4.5,y+4.5):p.rod((xx,yy,.98),(xx,yy,1.38),.14,'Iron')
    for i in range(8):
        xx=x+RNG.uniform(-.3,5);yy=y+RNG.uniform(-3,3);p.box((xx,yy,1.4),(1.0,1.0,.9),'Oak')
        for zz in (1.12,1.65):p.box((xx,yy,zz),(1.05,1.05,.06),'Trunk')
    for i in range(5):boat(p,x+2+i*4.5,y-8-RNG.random()*2,-.42,.8+RNG.random()*.15)
    p.flush(.015)
    b=Batch('Beach_Leisure',PROPS)
    for y in (-38,-24,-12,5,18):
        xx=46.5+RNG.random()*1.0
        b.rod((xx,y,-.2),(xx,y,1.8),.035,'Oak')
        vs=[(xx,y,2.15)]+[(xx+1.2*math.cos(i*math.tau/12),y+1.2*math.sin(i*math.tau/12),1.8) for i in range(12)]
        for i in range(12):b.poly(vs,[(0,i+1,(i+1)%12+1)],'Canvas' if i%2 else 'AwningBlue')
        b.box((xx+1.8,y-.2,-.19),(.8,1.6,.025),'TealCloth')
    b.flush()

def legacy_town():
    make_materials();lighting()
    data=json.loads(SOURCE_MAP.read_text(encoding='utf-8'));landscape(data)
    for name,area in data['areas'].items():
        if area['type']=='plaza':continue
        ax,ay,ww,dd=area['rect'];xx,yy=xy(ax+ww/2,ay+dd/2);SOURCE_RECTS.append(('Main_'+name,xx,yy,ww*S,dd*S))
    for lot in data['solid_lots']:
        ax,ay=lot['pos'];ww,dd=lot['footprint'];xx,yy=xy(ax+ww/2,ay+dd/2);SOURCE_RECTS.append((lot['id'],xx,yy,ww*S,dd*S))
    doorlookup={a['name']:a for a in data['doors']}
    for name,area in data['areas'].items():
        if area['type']=='plaza':continue
        ax,ay,w,d=area['rect'];x,y=xy(ax+w/2,ay+d/2)
        door=doorlookup[name];dx=(door['pos'][0]+.5-(ax+w/2))*S
        floors=2 if name not in ('wash','work') else 1
        building('Main_'+name,(x,y),w*S,d*S,floors,name,dx,source='map.areas.'+name,face=door['face'],source_door=door['pos'])
    for lot in data['solid_lots']:
        ax,ay=lot['pos'];w,d=lot['footprint'];x,y=xy(ax+w/2,ay+d/2);kind=lot['sprite']
        floors=1 if kind in ('netshed','cottage','longere','halles','cannery','windmill') else (3 if kind in ('hotel','mairie','belleepoque') else 2)
        dx=0
        if 'door' in lot:dx=(lot['door'][0]+.5-(ax+w/2))*S
        building(lot['id'],(x,y),w*S,d*S,floors,kind,dx,source='map.solid_lots.'+lot['id'],source_door=lot.get('door'))
    building('Port_Warehouse_Exterior',xy(57.1,8.2),2.8,3.0,1,'netshed',base=.95,source='spaces.port_warehouse / map.areas.dock.boathouse; exterior_only')
    harbor()
    b=Batch('Everyday_StreetFurniture',PROPS)
    # Cafe terrace stays outside its threshold.
    cafe=next(a for a in BUILDINGS if a['id']=='Main_cafe');cx,cy,cz=cafe['center_m'];d=cafe['footprint_m'][1]
    for xx in (cx-5,cx-1.7,cx+2,cx+5.2):
        table(b,xx,cy-d/2-2.6,ground_z(xx,cy-d/2-2.6)+.1,.55)
    for xx in (cx-7,cx+7):pot(b,xx,cy-d/2-1.7,cz)
    # A-frame menus, wall sign and bicycle provide human-scale reading close up.
    for xx in (cx-3,cx+4.3):
        yy=cy-d/2-1.9;b.box((xx,yy,cz+.67),(.55,.10,.8),'Oak');b.box((xx,yy-.06,cz+.69),(.47,.025,.68),'Ink')
        for side in (-1,1):b.rod((xx+side*.26,yy-.22,cz),(xx+side*.26,yy,cz+1.1),.028,'Oak',n=6)
    text('Cafe_Menu','MENU\nCafé  •  Thé\nCrêpes',(cx-3,cy-d/2-1.97,cz+.7),.10,'White')
    # Bicycle wheels are true open rings, rather than solid disks.
    bx,by=cx+7,cy-d/2-.5
    for wx in (bx-.5,bx+.5):
        for i in range(24):
            a0=i*math.tau/24;a1=(i+1)*math.tau/24
            b.rod((wx+math.cos(a0)*.34,by,cz+.4+math.sin(a0)*.34),(wx+math.cos(a1)*.34,by,cz+.4+math.sin(a1)*.34),.022,'Ink',n=5)
        for i in range(8):
            aa=i*math.tau/8;b.rod((wx,by,cz+.4),(wx+math.cos(aa)*.33,by,cz+.4+math.sin(aa)*.33),.006,'Zinc',n=4)
    for p0,p1 in [((bx-.5,by,cz+.4),(bx-.1,by,cz+.9)),((bx-.1,by,cz+.9),(bx+.5,by,cz+.4)),((bx+.5,by,cz+.4),(bx,by,cz+.4)),((bx,by,cz+.4),(bx-.1,by,cz+.9))]:b.rod(p0,p1,.025,'BluePaint',n=7)
    # Fountain and benches anchor the quiet social square.
    z=ground_z(0,0)+.12
    b.rod((-2,1,z),(-2,1,z+.35),1.25,'Granite',n=24)
    b.rod((-2,1,z+.36),(-2,1,z+.40),1.08,'Shallows',n=24)
    b.rod((-2,1,z+.4),(-2,1,z+1.65),.16,'Granite',n=12)
    b.rod((-2,1,z+1.5),(-2,1,z+1.64),.53,'Granite',n=20)
    for x,y in [(-5,-3),(3,-3),(4,3),(-5,3)]:
        zz=ground_z(x,y)+.1
        for j in range(4):b.box((x,y-.22+j*.14,zz+.48),(1.9,.10,.08),'Oak')
        for dx in (-.7,.7):b.box((x+dx,y,zz+.25),(.07,.52,.5),'Iron')
        b.box((x,y+.26,zz+.82),(1.9,.06,.35),'Oak')
    for x,y in [(-7,-4),(7,4),(-27,0),(25,0),(-42,24),(15,23),(-25,-21),(25,-22)]:lamp(b,x,y,ground_z(x,y))
    # A small market: tables, canvas roofs, produce clusters.
    for i in range(3):
        x=-18+i*3.4;y=24;zz=ground_z(x,y)
        b.box((x,y,zz+.85),(2.8,1.25,.15),'Oak')
        for dx in (-1.3,1.3):
            for dy in (-.5,.5):b.rod((x+dx,y+dy,zz),(x+dx,y+dy,zz+2.45),.045,'Oak')
        for j in range(8):b.box((x-1.4+(j+.5)*.35,y,zz+2.5),(.35,1.5,.09),'Canvas' if j%2 else 'AwningBlue')
        for j in range(16):b.ellipsoid((x-1.15+j%8*.32,y-.25+j//8*.45,zz+1.02),(.12,.11,.11),'Terracotta' if i%2 else 'LeafLight',n=7,rings=4)
    for x,y in [(-3,-2),(2,1),(13,1),(28,0),(44,12),(43,-14),(-41,24),(-24,-21),(17,23),(-8,0),(5,-9),(40,26)]:person(b,x,y,ground_z(x,y)+.06)
    b.flush(.012)
    veg=Batch('Garden_Vegetation',VEG)
    rects=[(a['center_m'][0],a['center_m'][1],a['footprint_m'][0],a['footprint_m'][1]) for a in BUILDINGS]
    def clear(x,y):return all(abs(x-cx)>w/2+2 or abs(y-cy)>d/2+2 for cx,cy,w,d in rects)
    treecount=0
    for tx,ty in data['trees'][::3]:
        x,y=xy(tx+.5,ty+.5)
        if x>41 or not clear(x,y):continue
        tree(veg,x,y,scale=RNG.uniform(.7,1.15));treecount+=1
        if treecount>=60:break
    for i in range(40):
        x=RNG.uniform(-74,-60);y=RNG.uniform(-58,58);tree(veg,x,y,scale=RNG.uniform(.8,1.3))
    tree(veg,4.6,2.5,scale=1.35)
    for a in BUILDINGS:
        x,y,z=a['center_m'];w,d=a['footprint_m']
        if a['kind'] in ('work','cannery','netshed'):continue
        if RNG.random()<.6:pot(veg,x-w*.35,y-d/2-.6,z,True,.85)
    # Low private garden boundaries and hydrangeas fill quiet peripheral yards.
    gardens=Batch('Garden_Walls_and_Borders',VEG)
    for a in BUILDINGS:
        if a['kind'] not in ('home','home2','cottage','longere','townhouse','belleepoque','terrace','halftimber','whitehouse','ochre'):continue
        x,y,z=a['center_m'];ww,dd=a['footprint_m'];yy=y+dd/2+1.1
        if not clear(x,yy+1.5):continue
        gardens.box((x,yy+1.2,ground_z(x,yy)+.35),(ww+.65,.35,.7),'Granite')
        gardens.box((x,yy+1.2,ground_z(x,yy)+.73),(ww+.75,.45,.1),'White')
        for xx in (x-ww*.30,x+ww*.30):
            for k in range(5):
                px=xx+RNG.uniform(-.3,.3);py=yy+RNG.uniform(-.35,.35);pz=ground_z(px,py)
                veg.ellipsoid((px,py,pz+.40),(.46,.40,.44),'Leaf',n=12,rings=7)
                for j in range(5):veg.ellipsoid((px+RNG.uniform(-.32,.32),py+RNG.uniform(-.3,.3),pz+.68+RNG.random()*.18),(.12,.12,.12),'BloomBlue' if k%2 else 'BloomPink',n=9,rings=5)
    gardens.flush(.016)
    # Granite headlands frame the beaches without making the beach busy.
    rocks=Batch('Coastal_Granite_Outcrops',WORLD)
    for sy in (-1,1):
        for i in range(16):
            xx=RNG.uniform(43,52);yy=sy*RNG.uniform(47,61)
            rocks.ellipsoid((xx,yy,-.30),(RNG.uniform(.5,1.8),RNG.uniform(.6,1.5),RNG.uniform(.5,1.4)),'Granite',n=7,rings=4)
    rocks.flush()
    for i in range(700):
        x=RNG.uniform(-72,44);y=RNG.uniform(-60,60)
        if not clear(x,y):continue
        zz=ground_z(x,y)
        for k in range(3):
            a=k*math.pi/3;dx=math.cos(a)*.11;dy=math.sin(a)*.11
            veg.poly([(x-dx,y-dy,zz),(x+dx,y+dy,zz),(x+.08,y,zz+.25)],[(0,1,2)],'LeafLight')
    veg.flush()
    SCENE.camera=camera('01_Town_Beauty',(139,-170,152),(0,0,2),ortho=153)
    camera('02_Cafe_Street',(cx+9,cy-21,cz+8.5),(cx,cy-d/2,cz+3),lens=40)
    camera('03_Cafe_Section',(cx+11,cy-16,cz+22),(cx,cy,cz+1.7),ortho=26)
    camera('04_Promenade',(63,-34,15),(34,18,2),lens=38)
    camera('05_Harbor',(93,63,58),(39,24,2),ortho=72)
    camera('06_Production_Orthogonal',(0,0,180),(0,0,0),ortho=142)
    camera('07_Material_Closeup',(cx+10,cy-20,cz+9),(cx+2,cy-d/2,cz+2.4),lens=55)
    SCENE['tree_count']=treecount+41
    SCENE['building_count']=len(BUILDINGS)
    # Make opening the .blend useful even without rendering.
    for screen in bpy.data.screens:
        for ar in screen.areas:
            if ar.type=='VIEW_3D':
                ar.spaces.active.region_3d.view_perspective='CAMERA';ar.spaces.active.clip_end=500
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'living_town_complete.blend'))
    manifest()

def coast_x(y):return 49+2*math.sin(y*.055)-7*math.exp(-((y-43)/10)**2)

def beach_width(y):
    if TERRAIN:return TERRAIN.beach_width(y)
    t=max(0,min(1,(y-20)/16));return 7-6*(t*t*(3-2*t))

def market_hall(ident,center,w,d,yaw,source,district):
    x,y=center;z=TOPO_PADS[ident]['pad_base_z_m'];angle=math.radians(yaw)
    c=coll(ident,ARCH);rc=coll(ident+'_Roof',c);fc=coll(ident+'_FrontWall',c);uc=coll(ident+'_UpperFloorCover',c)
    ic=coll(ident+'_Interior',c);produce=Batch(ident+'_ProduceStalls',ic,(x,y,z),angle)
    ROOFS.append(rc);FRONTS.append(fc);UPPER.append(uc)
    b=Batch(ident+'_OpenTimberArcade',c,(x,y,z),angle);r=Batch(ident+'_SlateCanopy',rc,(x,y,z),angle);f=Batch(ident+'_EntranceSign',fc,(x,y,z),angle)
    toe=TOPO_PADS[ident]['foundation_toe_recommendation_z_m']-z
    b.box((0,0,(toe+.3)/2),(w,d,.3-toe),'Granite');b.box((0,0,.33),(w-.25,d-.25,.10),'Paving')
    for j in range(2):b.box((0,-d/2-(1.5-j)*.28,.075+j*.075),(3.2,.29,.15+j*.15),'Granite')
    bays=max(3,int(w/3));h=3.35
    for i in range(bays+1):
        xx=-w/2+i*w/bays
        for yy in (-d/2+.15,d/2-.15):
            b.box((xx,yy,1.75),(.20,.20,3.2),'Trunk')
            b.box((xx,yy,.5),(.36,.36,.45),'Granite')
        b.rod((xx,-d/2,h-.15),(xx,d/2,h-.15),.12,'Trunk',n=4)
        b.rod((xx,-d/2,h-.1),(xx,0,h+1.5),.12,'Trunk',n=4);b.rod((xx,d/2,h-.1),(xx,0,h+1.5),.12,'Trunk',n=4)
    for yy in (-d/2,d/2):b.box((0,yy,h),(w+.25,.20,.23),'Trunk')
    gable_roof(r,w,d,h,1.6)
    f.box((0,-d/2-.13,2.84),(w*.65,.12,.42),'BluePaint')
    sx=x+math.sin(angle)*(d/2+.22);sy=y-math.cos(angle)*(d/2+.22)
    text(ident+'_MarketSign','LES HALLES',(sx,sy,z+2.85),.30,'White',fc,(math.pi/2,0,angle))
    b.flush(.016);r.flush();f.flush(.012);produce.flush(.012)
    interior_record=INTERIOR_MODULE.build_interior(globals(),ident,ic,uc,(x,y,z),angle,w,d,1,'halles',0)
    practical_room_lights(interior_record,(x,y,z),angle)
    INTERIOR_RECORDS.append(interior_record)
    info={'id':ident,'kind':'halles','center_m':[x,y,z],'footprint_m':[w,d],'floors':1,'source_ref':source,'collection':c.name,'roof_collection':rc.name,'front_collection':fc.name,'upper_cover_collection':uc.name,'door_local_x':0,'front_face':'S','yaw_degrees':yaw,'typology':'open_timber_market','district':district}
    info.update({'pad_base_z_m':z,'finished_floor_z_m':z+.38,'foundation_toe_z_m':z+toe,'entry_step_count':2})
    BUILDINGS.append(info);return info

def new_landscape(plan):
    b=Batch('Atlantic_Terrain',WORLD);nx=220;vs=[]
    ys=sorted(set([-500,-300,-180,-120,-95]+[-75+i*.6 for i in range(268)]+[-48+i*.2 for i in range(61)]+[37,55,110,160,240,400,600]))
    far_x=[-500,-300,-180,-120,-95]
    pond_x=[18+i*.2 for i in range(81)]
    cols=len(far_x)+nx+1+len(pond_x)
    for y in ys:
        edge=coast_x(y)-beach_width(y)
        for x in sorted(far_x+[-85+(edge+85)*i/nx for i in range(nx+1)]+pond_x):vs.append((x,y,ground_z(x,y)))
    faces=[]
    for j in range(len(ys)-1):
        for i in range(cols-1):
            face=(j*cols+i,j*cols+i+1,(j+1)*cols+i+1,(j+1)*cols+i)
            mx=sum(vs[k][0] for k in face)/4;my=(ys[j]+ys[j+1])/2
            if 31<mx<66 and 37<my<55:continue
            faces.append(face)
    b.poly(vs,faces,'Grass')
    vs=[]
    for y in ys:
        water=coast_x(y);edge=water-beach_width(y)
        vs.extend([(edge+(water-edge)*i/8,y,TERRAIN.beach_height(edge+(water-edge)*i/8,y)) for i in range(9)])
    for mat in ('Sand','WetSand','Granite'):
        faces=[]
        for j in range(len(ys)-1):
            ym=(ys[j]+ys[j+1])/2
            if 37<ym<55:continue
            stone=beach_width(ym)<3
            if stone:
                if mat!='Granite':continue
                indices=range(8)
            else:
                if mat=='Granite':continue
                indices=range(6) if mat=='Sand' else range(6,8)
            faces.extend([(j*9+k,j*9+k+1,(j+1)*9+k+1,(j+1)*9+k) for k in indices])
        b.poly(vs,faces,mat)
    pond=TERRAIN.pond_spec();px,py=pond['center'];rx,ry=pond['water_radii_m'];water_z=pond['water_z_m']
    waterverts=[(px,py,water_z)]+[(px+rx*math.cos(i*math.tau/96),py+ry*math.sin(i*math.tau/96),water_z) for i in range(96)]
    b.poly(waterverts,[(0,i+1,(i+1)%96+1) for i in range(96)],'PondWater')
    # A sampled smooth soil margin follows the exact water ellipse. Coarse
    # terrain-face material classification would make a visibly jagged shore.
    rings=(1.,1.03,1.06,1.085);shore=[]
    for r in rings:
        for i in range(96):
            x=px+rx*r*math.cos(i*math.tau/96);y=py+ry*r*math.sin(i*math.tau/96)
            shore.append((x,y,ground_z(x,y)+.004))
    b.poly(shore,[(j*96+i,j*96+(i+1)%96,(j+1)*96+(i+1)%96,(j+1)*96+i) for j in range(len(rings)-1) for i in range(96)],'Dirt')
    b.box((800,0,TERRAIN.WATER_Z-.11),(1600,2200,.22),'Sea')
    for k in range(2):
        vs=[]
        for j in range(220):
            y=-80+j*.72;x=coast_x(y)+k*1.3+.15*math.sin(y*.8+k)
            vs.extend([(x,y,-.879+k*.004),(x+.07,y,-.879+k*.004)])
        b.poly(vs,[(j*2,j*2+2,j*2+3,j*2+1) for j in range(219) if j%21<6 and not 32<vs[j*2][1]<57],'Foam')
    b.flush()
    streets=Batch('Connected_Streets_and_Pavements',WORLD)
    steps=Batch('Graded_Threshold_Approach_Steps',WORLD);stepped_count=0
    for road in plan['streets']:
        pts=road['points'];wd=road['width']
        if TOPO_ROADS.get(road['id'],{}).get('treatment')=='entry_steps_required':
            a,c=pts[0],pts[-1];dx=c[0]-a[0];dy=c[1]-a[1];length=math.hypot(dx,dy)
            za,zb=ground_z(*a)+.075,ground_z(*c)+.075;n=max(1,math.ceil(abs(zb-za)/.15))
            nx=-dy/length*wd/2;ny=dx/length*wd/2
            for i in range(n):
                x0=a[0]+dx*i/n;y0=a[1]+dy*i/n;x1=a[0]+dx*(i+1)/n;y1=a[1]+dy*(i+1)/n
                top=za+(zb-za)*(i+1 if zb>za else i)/n;bottom=min(za,zb)-.14
                xy=[(x0+nx,y0+ny),(x0-nx,y0-ny),(x1-nx,y1-ny),(x1+nx,y1+ny)]
                vs=[(x,y,z) for z in (bottom,top) for x,y in xy]
                steps.poly(vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'Granite')
            stepped_count+=1
            continue
        ribbon(streets,pts,wd+.3,'Paving',.055)
        ribbon(streets,pts,wd,'Courtyard',.068)
    for a in plan.get('entrance_paths',[]):ribbon(streets,a['points'],a.get('width',1.15),'Paving',.06)
    p=plan.get('plaza',{});polygon=p.get('polygon',[[-13,-8],[7,-8],[7,8],[-13,8]]) if isinstance(p,dict) else p
    if polygon:
        streets.poly([(x,y,ground_z(x,y)+.08) for x,y in polygon],[tuple(range(len(polygon)))],'Paving')
    # Harbor is a built working apron on an inlet, distinct from beach promenade.
    streets.box((48.5,46,.6),(35,18,1.8),'Granite');streets.box((48.5,46,1.55),(35.25,18.25,.13),'Paving')
    streets.flush();steps.flush(.008);SCENE['stepped_approach_count']=stepped_count
    edge=Batch('Promenade_Stone_Edge',WORLD)
    for j in range(155):
        y=-65+j*.65
        if y>34:break
        x=coast_x(y)-beach_width(y);z=ground_z(x,y)
        edge.box((x,y,z-.20),(.55,.67,1.0),'Granite');edge.box((x,y,z+.34),(.75,.68,.13),'Granite')
        if j%12==0:lamp(edge,x-1.25,y,z+.06)
    for yy in (-30,-3,17):
        xx=coast_x(yy)-beach_width(yy)
        for j in range(7):edge.box((xx+.3+j*.34,yy,ground_z(xx,yy)-j*.15),(.36,1.8,.20),'Granite')
    edge.flush(.014)

def topographic_review_and_drainage():
    review=coll('04_Topographic_Review');review['purpose']='Optional contours and spot levels. Hide building collection for ground-only review; disabled in beauty renders.'
    for i,path in enumerate(TOPO_PLAN['contour_segments']):
        cu=bpy.data.curves.new('Contour_'+str(path['level_m']),'CURVE');cu.dimensions='3D';cu.bevel_depth=.035;cu.bevel_resolution=1
        spline=cu.splines.new('POLY');spline.points.add(len(path['points'])-1)
        for p,xyz in zip(spline.points,path['points']):p.co=(xyz[0],xyz[1],xyz[2]+.035,1)
        ob=bpy.data.objects.new('Contour_%02d_%+.1fm'%(i,path['level_m']),cu);review.objects.link(ob);cu.materials.append(MATS['Ink'])
    for label,x,y in [('Mill',-56,35),('Church',-23,29),('Square',-3,0),('Cafe',11.5,0),('Quay',51,50),('Sea',61,8)]:
        z=TERRAIN.surface_height(x,y);text('Spot_Level_'+label,label+' %+.2fm'%z,(x,y,z+.09),.8,'Ink',review,(0,0,0))
    review.hide_render=True;review.hide_viewport=True
    b=Batch('Stormwater_Grates_and_Culvert_Heads',PROPS)
    for feature in TOPO_PLAN['drainage']['grates_and_outfalls']:
        x,y=feature['center'];kind=feature['kind']
        if 'outfall' in kind:
            z=feature['level_m'];b.box((x-.20,y,z+.10),(.35,.72,.85),'Granite')
            b.rod((x-.2,y,z),(x+.50,y,z),.19,'Zinc',n=18);b.rod((x+.505,y,z),(x+.51,y,z),.15,'Ink',n=18)
        else:
            z=TERRAIN.QUAY_Z+.012 if 'quay' in kind else ground_z(x,y)+.082
            b.box((x,y,z-.018),(.66,.48,.025),'Ink')
            for dy in (-.25,.25):b.box((x,y+dy,z),(.72,.045,.055),'Iron')
            for dx in (-.36,.36):b.box((x+dx,y,z),(.045,.54,.055),'Iron')
            for j in range(8):b.box((x-.28+j*.08,y,z),(.026,.47,.045),'Iron')
    # Narrow covered channels take the port apron to its visible seaward edge.
    for x in (47,61):
        b.box((x,39.1,TERRAIN.QUAY_Z+.007),(.15,3.1,.012),'Ink')
        for j in range(18):b.box((x,37.6+j*.17,TERRAIN.QUAY_Z+.022),(.17,.025,.025),'Iron')
    b.flush(.005);SCENE['drainage_feature_count']=len(TOPO_PLAN['drainage']['grates_and_outfalls'])

def town():
    global REDESIGNED,TERRAIN,TOPO_PLAN,TOPO_PADS,TOPO_ROADS
    REDESIGNED=True
    spec=importlib.util.spec_from_file_location('living_town_terrain',ROOT/'tools/terrain_profile.py')
    TERRAIN=importlib.util.module_from_spec(spec);spec.loader.exec_module(TERRAIN)
    TOPO_PLAN=json.loads((ROOT/'terrain_plan.json').read_text(encoding='utf-8'))
    TOPO_PADS={a['id']:a for a in TOPO_PLAN['building_pads']};TOPO_ROADS={a['id']:a for a in TOPO_PLAN['roads']}
    make_materials();lighting();plan=json.loads((ROOT/'masterplan.json').read_text(encoding='utf-8'))
    SCENE['purpose']='Redesigned offline Breton town masterplan; user authorized replacing poor original layout. No game-map integration is claimed.'
    SCENE['masterplan_version']=plan.get('version',2)
    for a in plan['buildings']:
        x,y=a['center'];SOURCE_RECTS.append((a['id'],x,y,a['width'],a['depth'],a.get('yaw_degrees',0)))
    new_landscape(plan)
    for a in plan['buildings']:
        building(a['id'],a['center'],a['width'],a['depth'],a.get('floors',2),a['kind'],source=a.get('source_ref'),yaw_degrees=a.get('yaw_degrees',0),typology=a.get('typology','plain_gable'),district=a.get('district'))
    topographic_review_and_drainage()
    p=Batch('Civic_Square_and_Summer_Life',PROPS)
    z=ground_z(-3,0)+.12
    p.rod((-3,0,z),(-3,0,z+.35),1.4,'Granite',n=28);p.rod((-3,0,z+.37),(-3,0,z+.41),1.2,'Shallows',n=28)
    p.rod((-3,0,z+.4),(-3,0,z+1.7),.16,'Granite',n=12);p.rod((-3,0,z+1.6),(-3,0,z+1.72),.55,'Granite',n=22)
    # Cafe terrace faces the square, leaving its central approach clear.
    for yy in (-3.3,0,3.3):table(p,4.5,yy,ground_z(4.5,yy)+.12,.52)
    for yy in (-4.2,4.2):pot(p,6.4,yy,ground_z(6.4,yy),True,1.1)
    for xx,yy in [(-10,-5),(-10,5),(3.5,6.0),(-3,-6)]:
        zz=ground_z(xx,yy)+.12
        for j in range(4):p.box((xx,yy-.22+j*.14,zz+.48),(1.9,.10,.08),'Oak')
        for dx in (-.7,.7):p.box((xx+dx,yy,zz+.25),(.07,.52,.5),'Iron')
        p.box((xx,yy+.26,zz+.82),(1.9,.06,.35),'Oak')
    for xx,yy in [(-12,-7),(6,-7),(-12,7),(5,7),(-29,-14),(-44,-20),(-42,12),(-20,17),(18,20),(27,-1)]:lamp(p,xx,yy,ground_z(xx,yy))
    for xx,yy in [(-5,-3),(1,1),(4,5),(-10,3),(-18,-10),(-37,-19),(-43,12),(-12,-32),(39,-17),(40,9),(28,37),(52,39)]:person(p,xx,yy,ground_z(xx,yy)+.1)
    # Separate working port clutter stays on its loading apron.
    for i in range(16):
        xx=RNG.uniform(45,59);yy=RNG.uniform(37,51);p.box((xx,yy,2.0),(1.0,1.0,.9),'Oak')
        for zz in (1.66,2.24):p.box((xx,yy,zz),(1.06,1.06,.06),'Trunk')
    for i in range(6):boat(p,50+i*3.3,31.5-RNG.random()*1.2,-.42,.8+RNG.random()*.16)
    for xx in (36,43,50,57,64):
        p.rod((xx,37,1.6),(xx,37,2.0),.14,'Iron');p.rod((xx,54.6,1.6),(xx,54.6,2.0),.14,'Iron')
    for yy in (-34,-21,-7,10):
        xx=coast_x(yy)-3.1;p.rod((xx,yy,-.25),(xx,yy,1.6),.032,'Oak')
        vs=[(xx,yy,1.95)]+[(xx+math.cos(i*math.tau/12)*1.05,yy+math.sin(i*math.tau/12)*1.05,1.60) for i in range(12)]
        for i in range(12):p.poly(vs,[(0,i+1,(i+1)%12+1)],'Canvas' if i%2 else 'AwningBlue')
        p.box((xx+1.2,yy-.4,-.18),(.65,1.5,.025),'TealCloth')
    p.flush(.012)
    garden=Batch('Private_Courtyards_and_Retaining_Walls',VEG)
    routes=[(r['points'],r['width']) for r in plan['streets']]+[(r['points'],r.get('width',1.15)) for r in plan.get('entrance_paths',[])]
    def route_clear(x,y,margin=.4):
        for pts,width in routes:
            for a,b in zip(pts,pts[1:]):
                dx=b[0]-a[0];dy=b[1]-a[1];length=dx*dx+dy*dy
                t=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/length)) if length else 0
                if math.hypot(x-a[0]-t*dx,y-a[1]-t*dy)<width/2+margin:return False
        return True
    def parcel_clear(x,y,margin=.4):
        for a in plan['buildings']:
            cx,cy=a['center'];ang=math.radians(a.get('yaw_degrees',0));dx=x-cx;dy=y-cy
            lx=dx*math.cos(ang)+dy*math.sin(ang);ly=-dx*math.sin(ang)+dy*math.cos(ang)
            if abs(lx)<a['width']/2+margin and abs(ly)<a['depth']/2+margin:return False
        return True
    def wall_line(a,b,height=.9,width=.35):
        # Gates are actual gaps wherever a verified public route crosses the boundary.
        dx=b[0]-a[0];dy=b[1]-a[1];length=math.hypot(dx,dy);count=max(1,math.ceil(length/.38))
        for i in range(count):
            x=a[0]+dx*(i+.5)/count;y=a[1]+dy*(i+.5)/count
            if not route_clear(x,y,width/2+.35) or not parcel_clear(x,y,.05):continue
            nx=-dy/length*width/2;ny=dx/length*width/2
            xa=a[0]+dx*i/count;ya=a[1]+dy*i/count;xb=a[0]+dx*(i+1)/count;yb=a[1]+dy*(i+1)/count
            xy=[(xa+nx,ya+ny),(xa-nx,ya-ny),(xb-nx,yb-ny),(xb+nx,yb+ny)]
            vs=[(xx,yy,ground_z(xx,yy)+zz) for zz in (0,height) for xx,yy in xy]
            garden.poly(vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'Granite')
    # A walled garden behind the cafe block is a coherent interior of the block.
    for xx in (17.4,27.0):wall_line((xx,-6.5),(xx,10.5))
    for yy in (-6.5,10.5):
        for xx,ww in ((19.0,3.2),(25.2,3.2)):wall_line((xx-ww/2,yy),(xx+ww/2,yy))
    # Churchyard stone enclosure steps up the inland slope.
    for xx in (-30,-16):wall_line((xx,19),(xx,39),1.0,.45)
    wall_line((-30,39),(-16,39),1.0,.45)
    for xx,ww in ((-27,6),(-19,6)):wall_line((xx-ww/2,19),(xx+ww/2,19),1.0,.45)
    for j in range(8):garden.box((-23,18.4-j*.28,ground_z(-23,18.4)-j*.08),(2.3,.3,.15),'Granite')
    # Small domestic yards at the quiet south edge have gates rather than random props.
    for x0,x1 in [(-11,-4),(-4,3),(3,10)]:
        yy=-44;wall_line((x0,yy),(x1-.4,yy),.76,.3)
        wall_line((x0,-44),(x0,-38),.76,.3)
    garden.flush(.016)
    v=Batch('Sheltered_Gardens_and_Canopies',VEG)
    for xx,yy,sc in [(2.6,4.4,1.1),(22,3,.8),(-28.5,34,1.0),(-47,26,1.1),(-39,26,.9),(-57,25,1.05),(-53,-6,.9),(-25,-32,.85),(14,-41,.95),(34,56,1.0)]:
        if route_clear(xx,yy,.5) and parcel_clear(xx,yy,.7):tree(v,xx,yy,scale=sc)
    # Windbreak and agricultural edge, with no trees planted on urban paths.
    for i in range(32):
        xx=RNG.uniform(-76,-65);yy=RNG.uniform(-48,54);tree(v,xx,yy,scale=RNG.uniform(.8,1.3))
    for xx,yy in [(18.2,-3),(18.2,0),(18.2,5),(26,8),(-28,23),(-28,36),(-11,-43),(-4,-43),(3,-43),(10,-43)]:
        zz=ground_z(xx,yy)
        for k in range(6):
            px=xx+RNG.uniform(-.5,.5);py=yy+RNG.uniform(-.4,.4);v.ellipsoid((px,py,zz+.48),(.45,.42,.42),'Leaf',n=12,rings=7)
            for j in range(4):v.ellipsoid((px+RNG.uniform(-.3,.3),py+RNG.uniform(-.3,.3),zz+.73+RNG.random()*.16),(.12,.12,.12),'BloomBlue' if k%2 else 'BloomPink',n=9,rings=5)
    gardens_built=0
    for a in plan['buildings']:
        if a['kind'] not in ('home','home2','cottage','longere','townhouse','terrace','halftimber','whitehouse','ochre'):continue
        ang=math.radians(a.get('yaw_degrees',0));cx,cy=a['center'];ly=a['depth']/2+1.65
        xx=cx-ly*math.sin(ang);yy=cy+ly*math.cos(ang)
        if not all(route_clear(xx+dx,yy+dy,.65) and parcel_clear(xx+dx,yy+dy,.3) for dx,dy in [(0,0),(-1,-.6),(1,.6)]):continue
        z=ground_z(xx,yy);v.box((xx,yy,z+.12),(2.4,1.25,.24),'Trunk',ang)
        v.box((xx,yy,z+.25),(2.15,1.0,.04),'Stone',ang)
        for j in range(5):
            lx=-.8+j*.4;px=xx+lx*math.cos(ang);py=yy+lx*math.sin(ang)
            for side in (-.27,.27):v.ellipsoid((px-side*math.sin(ang),py+side*math.cos(ang),z+.40),(.17,.17,.15),'LeafLight',n=8,rings=5)
        gardens_built+=1
    SCENE['vegetable_garden_count']=gardens_built
    for a in BUILDINGS:
        if a['kind'] not in ('cafe','bakery','creperie','home','home2','whitehouse'):continue
        xx,yy,zz=a['center_m'];ang=math.radians(a['yaw_degrees']);ww,dd=a['footprint_m']
        lx=-ww*.34;ly=-dd/2-.35;px=xx+lx*math.cos(ang)-ly*math.sin(ang);py=yy+lx*math.sin(ang)+ly*math.cos(ang)
        pot(v,px,py,zz,True,.75)
    v.flush()
    rocks=Batch('Granite_Headland',WORLD)
    for i in range(30):
        yy=RNG.uniform(-60,-48);xx=coast_x(yy)+RNG.uniform(-3,2)
        rocks.ellipsoid((xx,yy,-.25),(RNG.uniform(.6,2),RNG.uniform(.5,1.5),RNG.uniform(.6,1.5)),'Granite',n=7,rings=4)
    rocks.flush()
    refinement_spec=importlib.util.spec_from_file_location('living_town_environment',ROOT/'tools/refine_environment.py')
    refinement=importlib.util.module_from_spec(refinement_spec);refinement_spec.loader.exec_module(refinement)
    SCENE['environment_refinement']=json.dumps(refinement.enrich_environment(globals(),plan,route_clear,parcel_clear))
    SCENE.camera=camera('01_Town_Beauty',(112,-151,105),(-6,11,3.5),lens=47)
    camera('02_Cafe_Street',(-9,-13,8),(9,0,3),lens=37)
    camera('03_Cafe_Section',(-8,-12,23),(11.5,0,1.8),ortho=24)
    camera('04_Promenade',(61,-42,25),(33,10,3),lens=44)
    camera('05_Harbor',(95,4,53),(38,42,2),ortho=65)
    camera('06_Production_Orthogonal',(0,5,180),(0,5,0),ortho=145)
    camera('07_Material_Closeup',(-3,-6,6.5),(8.8,0,2.2),lens=55)
    hx,hy,hz=next(b['center_m'] for b in BUILDINGS if b['id']=='Main_home')
    camera('09_Home_Section',(hx-12,hy-14,hz+16),(hx,hy,hz+1.4),ortho=18)
    hotel=next(b for b in BUILDINGS if b['kind']=='hotel');hx,hy,hz=hotel['center_m']
    camera('10_Hotel_Section',(hx+24,hy-24,hz+27),(hx,hy,hz+1.5),ortho=30)
    hx,hy,hz=next(b['center_m'] for b in BUILDINGS if b['id']=='Main_library')
    camera('11_Library_Section',(hx-12,hy-19,hz+22),(hx,hy,hz+1.5),ortho=24)
    cz=next(b['center_m'][2] for b in BUILDINGS if b['id']=='Main_cafe')
    camera('12_Cafe_Interior',(8.2,2.3,cz+1.96),(13.4,-.3,cz+1.7),lens=23)
    camera('13_Cafe_UpperFloor',(-2,-12,18),(11.5,0,cz+4.1),ortho=22)
    camera('14_Pond_Park',(46,-26,27),(26,-43,.6),lens=50)
    SCENE['camera_movement']=json.dumps(refinement.camera_movement(globals()))
    SCENE['building_count']=len(BUILDINGS);SCENE['masterplan_sha256']=hashlib.sha256((ROOT/'masterplan.json').read_bytes()).hexdigest()
    SCENE['terrain_plan_sha256']=hashlib.sha256((ROOT/'terrain_plan.json').read_bytes()).hexdigest()
    SCENE['terrain_profile_sha256']=hashlib.sha256((ROOT/'tools/terrain_profile.py').read_bytes()).hexdigest()
    SCENE['landscape_plan_sha256']=hashlib.sha256((ROOT/'landscape_plan.json').read_bytes()).hexdigest()
    SCENE['landscape_details_sha256']=hashlib.sha256((ROOT/'tools/landscape_details.py').read_bytes()).hexdigest()
    SCENE['water_datum_z_m']=TERRAIN.WATER_Z;SCENE['quay_deck_z_m']=TERRAIN.QUAY_Z
    for screen in bpy.data.screens:
        for ar in screen.areas:
            if ar.type=='VIEW_3D':
                ar.spaces.active.region_3d.view_perspective='CAMERA';ar.spaces.active.clip_end=1200
                ar.spaces.active.shading.type='MATERIAL';ar.spaces.active.shading.color_type='MATERIAL';ar.spaces.active.shading.use_scene_world=True;ar.spaces.active.shading.use_scene_lights=True
    manifest()

def manifest():
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:
            im.pack()
    for font in bpy.data.fonts:
        if font.filepath and font.name!='Bfont Regular':
            try:font.pack()
            except Exception:pass
    SCENE['roof_collection_names']=json.dumps([a.name for a in ROOFS])
    SCENE['front_collection_names']=json.dumps([a.name for a in FRONTS])
    SCENE['upper_collection_names']=json.dumps([a.name for a in UPPER])
    path=ROOT/('study_manifest.json' if STAGE=='study' else 'town_manifest.json')
    source=SOURCE_MAP.read_bytes()
    SCENE['interior_plan_sha256']=hashlib.sha256((ROOT/'interior_plan.json').read_bytes()).hexdigest()
    SCENE['interior_module_sha256']=hashlib.sha256((ROOT/'tools/interior_design.py').read_bytes()).hexdigest()
    doc={'stage':STAGE,'source_head':'f204276','source_map_sha256':hashlib.sha256(source).hexdigest(),'cell_metres':S,'bounds_m':[115.2,86.4],'building_count':len(BUILDINGS),'buildings':BUILDINGS,'cameras':[o.name for o in SCENE.objects if o.type=='CAMERA'],'materials':list(MATS),'objects':len(SCENE.objects),'mesh_vertices':sum(len(o.data.vertices) for o in SCENE.objects if o.type=='MESH'),'note':'Authored engine-agnostic environment source. Game assets are exported separately to portable GLB and verified in an isolated Godot consumer; existing game source is unchanged.'}
    doc['interiors']=INTERIOR_RECORDS
    doc['interior_plan_sha256']=SCENE['interior_plan_sha256'];doc['interior_module_sha256']=SCENE['interior_module_sha256']
    doc['interior_floor_count']=sum(b['floor_count'] for b in INTERIOR_RECORDS)
    doc['interior_room_count']=sum(b['room_count'] for b in INTERIOR_RECORDS)
    doc['interior_furnishing_count']=sum(b['furnishing_count'] for b in INTERIOR_RECORDS)
    doc['packed_images']=[im.name for im in bpy.data.images if im.source=='FILE' and im.packed_file]
    doc['packed_image_count']=len(doc['packed_images'])
    if (ROOT/'tools/interior_design.py').exists():doc['interior_design_sha256']=hashlib.sha256((ROOT/'tools/interior_design.py').read_bytes()).hexdigest()
    if REDESIGNED:
        doc['environment_refinement']=json.loads(SCENE['environment_refinement']);doc['camera_movement']=json.loads(SCENE['camera_movement'])
        doc['environment_design_sha256']=hashlib.sha256((ROOT/'tools/refine_environment.py').read_bytes()).hexdigest()
        doc['landscape_plan_sha256']=SCENE['landscape_plan_sha256'];doc['landscape_details_sha256']=SCENE['landscape_details_sha256']
    if REDESIGNED:
        doc['layout']='Reference-led irregular masterplan v3, supersedes original map geometry; original source map is program inventory only.'
        doc['masterplan_sha256']=hashlib.sha256((ROOT/'masterplan.json').read_bytes()).hexdigest();doc['bounds_m']=[125,115];doc.pop('cell_metres',None)
        doc['terrain_plan_sha256']=hashlib.sha256((ROOT/'terrain_plan.json').read_bytes()).hexdigest();doc['stepped_approaches']=SCENE['stepped_approach_count']
        doc['terrain_profile_sha256']=SCENE['terrain_profile_sha256'];doc['drainage_features']=SCENE['drainage_feature_count']
    path.write_text(json.dumps(doc,indent=2),encoding='utf-8')
    # Save again after packing and metadata, so .blend is self-contained.
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/('living_town_building_study.blend' if STAGE=='study' else 'living_town_complete.blend')))
    return doc

if STAGE=='study':study()
elif STAGE=='town':town()
else:raise ValueError(STAGE)
result={'stage':STAGE,'buildings':len(BUILDINGS),'scene':SCENE.name,'filepath':bpy.data.filepath,'objects':len(SCENE.objects)}
