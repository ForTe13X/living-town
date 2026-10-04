"""Run once through Blender MCP with atlantic_residence.blend open.
Adds procedural materials, detail geometry and photographic lighting.
Saves a separate detailed revision, leaving the first design file intact.
"""
import bpy, math, os, random, json, bmesh
from mathutils import Vector
random.seed(82)
OUT=r'D:\Documents\Dev\living-town\analysis\blender_residence'
scene=bpy.data.scenes['Residence • 01 Exterior']
assert not scene.get('detail_revision'), 'Detailed revision already applied; open the base file to rebuild.'
bpy.context.window.scene=scene
groups={c.name:c for c in scene.collection.children}
M=bpy.data.materials
plaster=M['Shell / warm limewash'];cream=M['Trim / chalk'];stone=M['Plinth / weathered granite']
slate=M['Roof / blue slate'];green=M['Joinery / sea sage'];dark=M['Metal / charcoal']
oak=M['Furniture / honey oak'];linen=M['Upholstery / oat linen'];terra=M['Accent / clay']
blue=M['Textile / Atlantic blue'];white=M['Ceramics / porcelain'];glass=M['Glazing / sea reflection']
brass=M['Hardware / brass'];soil=M['Garden / soil'];leaves=[M['Foliage %d'%i] for i in range(4)]
src=open(r'D:\Documents\Dev\living-town\tools\build_blender_residence.py',encoding='utf8').read()
exec(src[src.index('def mat('):src.index("plaster=mat(")])
exec(src[src.index('def obj('):src.index("group('00 Site")])
original=set(scene.objects)

def texture(m,kind,scale,depth):
    nt=m.node_tree;n=nt.nodes;l=nt.links;p=n.get('Principled BSDF')
    base=tuple(p.inputs['Base Color'].default_value)
    tc=n.new('ShaderNodeTexCoord');tc.label='Real material coordinates'
    vm=n.new('ShaderNodeVectorMath');vm.operation='MULTIPLY'
    vm.inputs[1].default_value=scale;l.new(tc.outputs['Object'],vm.inputs[0])
    no=n.new('ShaderNodeTexNoise');no.inputs['Scale'].default_value=1;no.inputs['Detail'].default_value=3;no.inputs['Roughness'].default_value=.7;l.new(vm.outputs[0],no.inputs['Vector'])
    ramp=n.new('ShaderNodeValToRGB');ramp.label=kind+' color variation'
    ramp.color_ramp.elements[0].position=.22;ramp.color_ramp.elements[1].position=.78
    contrast=.55 if kind=='Oak grain' else .82
    ramp.color_ramp.elements[0].color=(*(v*contrast for v in base[:3]),1)
    ramp.color_ramp.elements[1].color=(*(min(1,v*1.08) for v in base[:3]),1)
    l.new(no.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs[0],p.inputs['Base Color'])
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.34;bump.inputs['Distance'].default_value=depth
    l.new(no.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs[0],p.inputs['Normal'])
    rough=n.new('ShaderNodeMapRange');rough.inputs['To Min'].default_value=.35 if kind=='Oak grain' else .58;rough.inputs['To Max'].default_value=.62 if kind=='Oak grain' else .88
    l.new(no.outputs['Fac'],rough.inputs[0]);l.new(rough.outputs[0],p.inputs['Roughness'])
    if kind=='Woven linen':
        p.inputs['Sheen Weight'].default_value=.3
        wave=n.new('ShaderNodeTexWave');wave.bands_direction='X';wave.inputs['Scale'].default_value=180;wave.inputs['Distortion'].default_value=1.3
        l.new(tc.outputs['Object'],wave.inputs['Vector'])
        wave2=n.new('ShaderNodeTexWave');wave2.bands_direction='Y';wave2.inputs['Scale'].default_value=190
        l.new(tc.outputs['Object'],wave2.inputs['Vector'])
        mix=n.new('ShaderNodeMath');mix.operation='MULTIPLY';l.new(wave.outputs['Color'],mix.inputs[0]);l.new(wave2.outputs['Color'],mix.inputs[1]);l.new(mix.outputs[0],bump.inputs['Height'])
    if kind=='Limewash':
        fine=n.new('ShaderNodeTexNoise');fine.inputs['Scale'].default_value=95;fine.inputs['Detail'].default_value=2;l.new(tc.outputs['Object'],fine.inputs['Vector'])
        l.new(fine.outputs['Fac'],bump.inputs['Height'])
    for i,node in enumerate(n):node.location=(i%5*230,-(i//5)*250)

for m in list(M):
    if m.name.startswith('Floorboard') or m==oak:texture(m,'Oak grain',(14,.65,8),.008)
    elif m in [linen,blue]:texture(m,'Woven linen',(26,26,26),.006)
    elif m in [plaster,cream]:texture(m,'Limewash',(2.5,2.5,2.5),.016)
    elif m.name.startswith('Slate') or m==slate:texture(m,'Split slate',(20,32,5),.025)
    elif m==stone:texture(m,'Granite',(35,35,35),.025)
    elif m==terra:texture(m,'Fired clay',(38,38,38),.009)
    elif m==green:texture(m,'Painted timber',(12,1,12),.003)
curtain=mat('Detail / ivory curtain',(.76,.72,.61),.82)
texture(curtain,'Woven linen',(24,24,24),.003)
stitch=mat('Detail / linen piping',(.62,.55,.42),.84)
throwmat=mat('Detail / rust woven throw',(.38,.095,.045),.95);texture(throwmat,'Woven linen',(25,25,25),.008)
glass.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.8,.92,.96,1)
gp=glass.node_tree.nodes.get('Principled BSDF');gp.inputs['Metallic'].default_value=0;gp.inputs['Roughness'].default_value=.09;gp.inputs['Transmission Weight'].default_value=1
gn=glass.node_tree.nodes;gl=glass.node_tree.links
trans=gn.new('ShaderNodeBsdfTransparent');mix=gn.new('ShaderNodeMixShader');mix.inputs[0].default_value=.7
gl.new(gp.outputs[0],mix.inputs[1]);gl.new(trans.outputs[0],mix.inputs[2]);gl.new(mix.outputs[0],gn.get('Material Output').inputs['Surface'])
mirror=mat('Detail / silvered mirror',(.87,.91,.92),.055,1)
for o in scene.objects:
    if o.name.startswith('Bath / mirror'):o.data.materials.clear();o.data.materials.append(mirror)
    # Eliminate coplanar facade bands and add genuine bottom window rails.
    if o.name.startswith('Facade / granite skirting'):o.location.z+=.009

def new_details(name,prefix):
    global current
    current=bpy.data.collections.new(name)
    for s in bpy.data.scenes:
        if s.name.startswith('Residence') and any(c.name.startswith(prefix) for c in s.collection.children):s.collection.children.link(current)
    return current
def pipe(name,points,r,material,closed=False):
    cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=2;cu.bevel_depth=r;cu.bevel_resolution=3
    sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
    for p,co in zip(sp.points,points):p.co=(*co,1)
    sp.use_cyclic_u=closed
    o=bpy.data.objects.new(name,cu);current.objects.link(o);cu.materials.append(material);return o
def rounded_rect(name,x,y,z,w,d,r,material):
    pts=[]
    for cx,cy,a in [(x+w/2-r,y+d/2-r,0),(x-w/2+r,y+d/2-r,90),(x-w/2+r,y-d/2+r,180),(x+w/2-r,y-d/2+r,270)]:
        for j in range(7):
            t=math.radians(a+j*15);pts.append((cx+r*math.cos(t),cy+r*math.sin(t),z))
    return pipe(name,pts,.008,material,True)
def lamp(name,loc,power,color,r=.2):
    d=bpy.data.lights.new(name,'POINT');d.energy=power;d.color=color;d.shadow_soft_size=r
    o=bpy.data.objects.new(name,d);current.objects.link(o);o.location=loc;return o
def emissive(name,color,strength):
    m=mat(name,color,.38);p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=strength;return m
glow=emissive('Detail / warm lamp glow',(1,.56,.24),2.8)

# Window details follow the existing facade collections, including cutaway visibility.
for name,c in list(groups.items()):
    if 'shell' not in name:continue
    current=c
    for pane in [o for o in list(c.objects) if o.name.startswith('Window / reflective pane')]:
        x,y,z=pane.location;w,d,h=pane.dimensions
        axis='X' if w>d else 'Y';span=max(w,d);floor=0 if z<3.2 else 3.2
        if axis=='X':
            box('Detail / lower window rail',(x,y,z-h/2-.02),(span+.08,.1,.08),cream,.012)
            box('Detail / upper window rail',(x,y,z+h/2+.02),(span+.08,.1,.08),cream,.012)
            inside=y+(.23 if y<0 else -.23)
            bar('Detail / curtain rod',(x-span/2-.15,inside,z+h/2+.18),(x+span/2+.15,inside,z+h/2+.18),.022,brass)
            for side in [-1,1]:
                center=x+side*(span/2-.13);width=.34
                vs=[];fs=[]
                for j in range(13):
                    zz=floor+.3+(z+h/2-floor-.2)*j/12
                    for i in range(25):
                        xx=center-width/2+width*i/24
                        yy=inside+.045*math.sin(i/24*math.tau*4)+.015*math.sin(j*.7)
                        vs.append((xx,yy,zz))
                for j in range(12):
                    for i in range(24):k=j*25+i;fs.append((k,k+1,k+26,k+25))
                o=obj('Detail / pleated curtain',vs,fs,curtain)
                so=o.modifiers.new('Fabric thickness','SOLIDIFY');so.thickness=.003
                for p in o.data.polygons:p.use_smooth=True
        else:
            box('Detail / lower window rail',(x,y,z-h/2-.02),(.1,span+.08,.08),cream,.012)
            box('Detail / upper window rail',(x,y,z+h/2+.02),(.1,span+.08,.08),cream,.012)
    for sh in [o for o in list(c.objects) if o.name.startswith('Shutter / sage')]:
        x,y,z=sh.location
        for dz in [-.55,.55]:
            box('Detail / shutter strap',(x,y+(-.048 if y<0 else .048),z+dz),(.3,.025,.045),dark,.006)
            for dx in [-.11,.11]:ball('Detail / hinge rivet',(x+dx,y+(-.067 if y<0 else .067),z+dz),(.016,.012,.016),brass)

current=new_details('18 GF • crafted interior details','13 GF')
for x in [-3.85,-3,-2.15]:rounded_rect('Detail / sofa seat piping',x,-.13,.618,.75,.67,.1,stitch)
# A draped throw with modeled folds across the sofa arm and down the front.
vs=[];fs=[]
for j in range(35):
    t=j/34
    for i in range(19):
        x=-4.17+i*.031; y=.35-.93*min(t/.72,1)
        z=.70 if t<.72 else .70-(t-.72)/.28*.48
        z+=.025*math.sin(i*.8+t*4)
        vs.append((x,y,z))
for j in range(34):
    for i in range(18):k=j*19+i;fs.append((k,k+1,k+20,k+19))
o=obj('Detail / draped woven throw',vs,fs,throwmat);so=o.modifiers.new('Hem thickness','SOLIDIFY');so.thickness=.009
for p in o.data.polygons:p.use_smooth=True
for i in range(16):pipe('Detail / throw fringe',[(-4.15+i*.033,-.58,.245),(-4.15+i*.033,-.60,.135)],.006,throwmat)
for x in [-4.5+i*.055 for i in range(59)]:
    for y in [-3.4,-.22]:pipe('Detail / rug tassel',[(x,y,.078),(x,y+(-.075 if y< -1 else .075),.074)],.004,linen)
for i in range(3):
    box('Detail / book pages',(-3.3,-1.7,.57+i*.045),(.325,.245,.024),cream,.003)
for x,y in [(-3.55,-1.8),(-2.5,-1.8)]:
    cyl('Detail / stoneware cup',(x,y,.65),.064,.14,white,32)
    cyl('Detail / coffee',(x,y,.723),.052,.005,oak,32)
    pipe('Detail / cup handle',[(x+.06+.032*math.sin(i*math.pi/12),y,.65+.047*math.cos(i*math.pi/12)) for i in range(13)],.009,white)
# Baseboards on the living room and kitchen divider.
for a,b in [(-4.86,-2.4),(-1.2,.08)]:box('Detail / living skirting',((a+b)/2,1.255,.13),(b-a,.045,.2),cream,.01)
box('Detail / west skirting',(-4.855,-.3,.13),(.05,7.1,.2),cream,.01)
for x,y in [(-4.3,-2.2)]:
    ball('Detail / reading lamp bulb',(x,y,1.57),(.055,.055,.08),glow)
    lamp('Practical / reading lamp',(x,y,1.57),65,(1,.60,.32),.12)
for x in [-4.5,-.9]:
    box('Detail / wall socket',(x,1.26,.36),(.085,.015,.13),white,.008)
    for dx in [-.015,.015]:ball('Detail / socket pin',(x+dx,1.249,.36),(.006,.004,.009),dark)

current=new_details('19 GF • kitchen and table detail','14 GF')
for x in [-4.35,-3.45,-2.55,-1.65,-.75]:
    box('Detail / cabinet lower inset',(x,3.018,.38),(.71,.026,.42),green,.013)
    bar('Detail / cabinet handle',(x-.14,2.99,.56),(x+.14,2.99,.56),.012,brass)
for i in range(8):
    box('Detail / backsplash subway tile',(-4.6+i*.51,3.826,1.12),(.493,.02,.21),white,.008)
for x,y in [(-4.25,3.42),(-4.05,3.42)]:
    cyl('Detail / pantry jar',(x,y,1.16),.08,.25,white,24);cyl('Detail / jar cork lid',(x,y,1.30),.084,.035,oak,24)
box('Detail / chopping board',(-.75,3.34,1.025),(.5,.32,.027),oak,.065)
for i in range(3):
    ball('Detail / loaf scoring',(-.83+i*.1,3.36,1.1),(.14,.10,.065),cream)
for x,y in [(1.25,-1.55),(2.05,-1.55),(1.25,-.65),(2.05,-.65)]:
    box('Detail / folded napkin',(x,y,.88),(.2,.26,.015),curtain,.007)
    bar('Detail / knife',(x+.21,y-.1,.88),(x+.21,y+.12,.88),.011,brass)
    bar('Detail / fork',(x-.21,y-.1,.88),(x-.21,y+.1,.88),.012,brass)
    for i in range(3):bar('Detail / fork tine',(x-.23+i*.02,y+.07,.88),(x-.23+i*.02,y+.135,.88),.003,brass)
    cyl('Detail / drinking tumbler',(x,y+.25,.95),.055,.17,glass,32)
lamp('Practical / dining pendant',(1.65,-1.1,2.04),90,(1,.66,.37),.23)
for o in scene.objects:
    if o.name.startswith('Dining pendant / diffuser'):o.data.materials.clear();o.data.materials.append(glow)

current=new_details('37 L1 • textiles and bedroom details','33 L1')
for o in list(scene.objects):
    if o.name.startswith('Bed / folded duvet'):
        x,y,z=o.location;w,d,h=o.dimensions
        for i in range(6):
            xx=x-w/2+.1+i*(w-.2)/5
            pipe('Detail / quilt channel',[(xx,y-d/2+.05+j*(d-.1)/20,z+h/2+.003+math.sin(j*.7)*.003) for j in range(21)],.004,stitch)
    if o.name.startswith('Bed / pillow'):
        x,y,z=o.location;rounded_rect('Detail / pillow piping',x,y,z+.071,.58,.37,.08,stitch)
    if o.name.startswith('Bedside / cabinet'):
        x,y,z=o.location;box('Detail / bedside drawer',(x,y-.247,z+.12),(.38,.025,.2),oak,.012);ball('Detail / drawer pull',(x,y-.27,z+.12),(.025,.017,.025),brass)
    if o.name.startswith('Bedside / linen shade'):
        x,y,z=o.location;lamp('Practical / bedside lamp',(x,y,z-.1),12,(1,.61,.31),.11)
        ball('Detail / bedside bulb',(x,y,z-.1),(.035,.035,.045),glow)
for x,y,z in [(-1.5,-.75,3.87),(-4.4,3.31,3.87)]:
    for i in range(2):box('Detail / bedside paperback',(x,y,z+i*.035),(.23,.3,.03),blue if i else terra,.003)

current=new_details('38 L1 • bathroom details','36 L1')
for i in range(5):
    x=.28+i*.42
    for j in range(4):box('Detail / glazed bath wall tile',(x,3.86,3.42+j*.35),(.407,.025,.337),M['Wet areas / muted celadon'],.006)
bar('Detail / basin faucet',(1.8,2.4,4.22),(1.8,2.4,4.49),.019,brass);bar('Detail / basin spout',(1.8,2.4,4.49),(1.8,2.18,4.49),.019,brass)
for x in [1.52,2.05]:cyl('Detail / soap and lotion',(x,2.35,4.28),.04,.18,terra,24)
for i in range(3):box('Detail / folded bath towel',(1.05,3.16,4.01+i*.055),(.4,.27,.05),curtain,.024)

current=new_details('42 Exterior • masonry and hardware','41 Exterior')
for x in [-4.8,4.8]:
    for i in range(14):
        z=.4+i*.42
        box('Detail / corner quoin',(x,-4.145,z),(.39 if i%2 else .54,.10,.38),cream,.016)
for x in [-4.7,4.7]:
    for z in [.45,1.8,3.6,5.35]:box('Detail / downpipe collar',(x,-4.282,z),(.14,.11,.048),dark,.009)
for i in range(23):
    x=-4.84+i*.42
    if 1.95<x<3.25:continue
    box('Detail / granite plinth joint',(x,-4.151,.12),(.012,.015,.2),cream,.001)
for x in [1.65,3.55]:
    box('Detail / porch lantern backplate',(x,-4.17,2),(.17,.06,.3),dark,.025)
    box('Detail / porch lantern glass',(x,-4.31,2),(.13,.18,.23),glow,.016)
    box('Detail / porch lantern cap',(x,-4.31,2.145),(.22,.25,.055),dark,.018)
    lamp('Practical / porch lantern',(x,-4.46,2),18,(1,.57,.26),.1)
box('Detail / house number plaque',(3.48,-4.175,1.57),(.24,.045,.18),dark,.014)
cu=bpy.data.curves.new('House number typography','FONT');cu.body='24';cu.size=.125;cu.align_x='CENTER';cu.extrude=.002
o=bpy.data.objects.new('Detail / house number 24',cu);current.objects.link(o);o.location=(3.48,-4.204,1.515);o.rotation_euler.x=math.pi/2;cu.materials.append(brass)
for x in [-3,-.4]:
    for i in range(12):
        xx=x+random.uniform(-.64,.64);yy=-4.3+random.uniform(-.1,.1);zz=1+random.uniform(.1,.28)
        bar('Detail / flower stem',(xx,yy,.96),(xx,yy,zz),.009,green)
        for j in range(5):
            a=j*math.tau/5;ball('Detail / flower petal',(xx+.035*math.cos(a),yy+.035*math.sin(a),zz),(.035,.028,.016),terra if i%2 else cream)

# Lower fill and a broad warm sun create depth, contact shadows and grazing texture.
world=scene.world;world.node_tree.nodes['Background'].inputs[0].default_value=(.48,.61,.79,1);world.node_tree.nodes['Background'].inputs[1].default_value=.24
bpy.data.objects['Large warm key'].data.energy=450;bpy.data.objects['Large warm key'].data.color=(1,.82,.62)
bpy.data.objects['Soft sky fill'].data.energy=650;bpy.data.objects['Soft sky fill'].data.color=(.65,.78,1)
sun=bpy.data.objects['Late afternoon sun'];sun.data.energy=2.5;sun.data.color=(1,.78,.52);sun.data.angle=.07
sun.rotation_euler=Vector((7,9,-10)).to_track_quat('-Z','Y').to_euler()
for s in bpy.data.scenes:
    if not s.name.startswith('Residence'):continue
    s.render.engine='CYCLES';s.cycles.samples=128;s.cycles.use_denoising=True;s.cycles.adaptive_threshold=.018
    s.cycles.max_bounces=10;s.cycles.transmission_bounces=8;s.cycles.transparent_max_bounces=12
    s.render.resolution_x=1800;s.render.resolution_y=1440;s.render.resolution_percentage=100
    s.view_settings.view_transform='AgX';s.view_settings.exposure=.35

# Two architectural closeups with perspective cameras.
current=bpy.data.collections.new('91 Detail cameras')
scene.collection.children.link(current)
def closeup(name,source,loc,target,lens):
    s=bpy.data.scenes.new(name)
    for c in source.collection.children:s.collection.children.link(c)
    if current.name not in s.collection.children:s.collection.children.link(current)
    s.world=world;s.render.engine='CYCLES';s.cycles.samples=128;s.cycles.use_denoising=True;s.cycles.adaptive_threshold=.012
    s.render.resolution_x=1800;s.render.resolution_y=1400;s.render.resolution_percentage=100;s.view_settings.view_transform='AgX';s.view_settings.exposure=.55
    ca=bpy.data.cameras.new(name+' camera');o=bpy.data.objects.new(name+' camera',ca);current.objects.link(o)
    o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();ca.lens=lens;ca.clip_start=.05
    s.camera=o;ca.dof.use_dof=True;ca.dof.focus_distance=(Vector(target)-o.location).length;ca.dof.aperture_fstop=8
    return s
living=closeup('Residence • 06 Living material study',bpy.data.scenes['Residence • 02 Ground cutaway'],(-.8,-3.7,2.5),(-3,-.35,1),30)
bedroom=closeup('Residence • 07 Bedroom material study',bpy.data.scenes['Residence • 03 Upper cutaway'],(-.65,-3.85,5.55),(-2.7,-1.05,4.0),32)
# EVENING_SETUP_BEGIN
evening=closeup('Residence • 08 Evening lighting',living,(-.8,-3.7,2.25),(-3,-.35,1),30)
for c in list(evening.collection.children):
    if c.name.startswith('90 Presentation'):evening.collection.children.unlink(c)
for n in ['10 GF shell • South removable facade','10 GF shell • East removable facade']:
    evening.collection.children.link(groups[n])
ew=world.copy();ew.name='Evening / blue hour';evening.world=ew
ew.node_tree.nodes['Background'].inputs[0].default_value=(.20,.33,.62,1)
ew.node_tree.nodes['Background'].inputs[1].default_value=.08
current=bpy.data.collections.new('92 Evening • ceiling and window light');evening.collection.children.link(current)
box('Evening / ceiling',(0,0,3.15),(9.75,7.75,.10),plaster,.01)
for loc,target,power,size in [((-6,-1.5,3),(-2,-1,1),68.4,3),((0,-5.5,2.5),(-3,-1,1),46.8,2.5)]:
    d=bpy.data.lights.new('Evening / cool window light','AREA');d.energy=power;d.color=(.38,.56,1);d.shape='DISK';d.size=size
    o=bpy.data.objects.new(d.name,d);current.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
evening.view_settings.exposure=1.5
# EVENING_SETUP_END
# FINAL_MATERIAL_REVIEW_BEGIN
shade=linen.copy();shade.name='Detail / light transmitting lampshade'
n=shade.node_tree.nodes;l=shade.node_tree.links;p=n.get('Principled BSDF')
tr=n.new('ShaderNodeBsdfTranslucent');tr.inputs['Color'].default_value=(.8,.65,.4,1)
mix=n.new('ShaderNodeMixShader');mix.inputs[0].default_value=.65
l.new(p.outputs[0],mix.inputs[1]);l.new(tr.outputs[0],mix.inputs[2]);l.new(mix.outputs[0],n.get('Material Output').inputs['Surface'])
for o in scene.objects:
    if o.name.startswith(('Reading lamp / linen shade','Bedside / linen shade','Dining pendant / shade')):
        o.data.materials.clear();o.data.materials.append(shade)
    if o.name.startswith('Detail / quilt channel'):o.data.bevel_depth=.001
    if o.name.startswith('Detail / pillow piping'):o.data.bevel_depth=.0025
    if o.name.startswith('Detail / sofa seat piping'):o.data.bevel_depth=.0035
# FINAL_MATERIAL_REVIEW_END
# Correct outward normals on all new meshes.
for o in {o for s in bpy.data.scenes if s.name.startswith('Residence') for o in s.objects}-original:
    if o.type=='MESH':
        bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
scene['detail_revision']='02 / procedural materials, tailored textiles, architectural hardware and practical lighting'
bpy.context.window.scene=scene
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'atlantic_residence_detailed.blend'),compress=True)
result={'file':bpy.data.filepath,'objects':len(scene.objects),'materials':len(M),'new_scenes':[living.name,bedroom.name,evening.name]}
json.dump(result,open(os.path.join(OUT,'detail_manifest.json'),'w'),indent=2)
