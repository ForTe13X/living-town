"""Coastal residence study. Run inside Blender through the integrated MCP bridge.
Creates new scenes; preserves all existing scene contents. Dimensions are metres.
"""
import bpy, math, random, os, json
from mathutils import Vector
random.seed(24)
OUT = r'D:\Documents\Dev\living-town\analysis\blender_residence'
os.makedirs(OUT, exist_ok=True)
scene = bpy.data.scenes.new('Residence • 01 Exterior')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
groups = {}
def group(name):
    global current
    current = bpy.data.collections.new(name)
    scene.collection.children.link(current)
    groups[name] = current
    return current
def mat(name, color, rough=.65, metal=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    return m
plaster=mat('Shell / warm limewash',(.79,.72,.59))
cream=mat('Trim / chalk',(.92,.88,.75))
stone=mat('Plinth / weathered granite',(.35,.38,.36))
slate=mat('Roof / blue slate',(.12,.19,.23))
slates=[mat('Slate variation %02d'%i,(.10+i*.014,.16+i*.014,.20+i*.014)) for i in range(5)]
green=mat('Joinery / sea sage',(.22,.39,.34))
dark=mat('Metal / charcoal',(.045,.07,.075),.35,.5)
oak=mat('Furniture / honey oak',(.47,.28,.13))
woods=[mat('Floorboard tone %d'%i,(.48+i*.018,.32+i*.015,.18+i*.012)) for i in range(5)]
linen=mat('Upholstery / oat linen',(.82,.77,.63))
terra=mat('Accent / clay',(.62,.26,.15))
blue=mat('Textile / Atlantic blue',(.16,.32,.42))
white=mat('Ceramics / porcelain',(.89,.91,.86),.24)
glass=mat('Glazing / sea reflection',(.19,.38,.42),.18,.25)
soil=mat('Garden / soil',(.17,.12,.08))
leaves=[mat('Foliage %d'%i,(.12+i*.025,.25+i*.035,.10+i*.018)) for i in range(4)]
brass=mat('Hardware / brass',(.55,.37,.13),.27,.65)
tile=mat('Wet areas / muted celadon',(.42,.56,.50))
def obj(name,verts,faces,ma):
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    o=bpy.data.objects.new(name,me); current.objects.link(o)
    if ma: me.materials.append(ma)
    return o
def box(name,loc,size,ma,bevel=0):
    x,y,z=[v/2 for v in size]
    o=obj(name,[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)],[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)],ma); o.location=loc
    if bevel:
        m=o.modifiers.new('Soft edges','BEVEL'); m.width=bevel; m.segments=2
        o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o
def cyl(name,loc,r,depth,ma,n=16):
    vs=[(r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),z) for z in [-depth/2,depth/2] for i in range(n)]
    fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    o=obj(name,vs,fs,ma); o.location=loc; return o
def ball(name,loc,size,ma):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,location=loc)
    o=bpy.context.object; o.name=name; o.scale=size
    for c in list(o.users_collection): c.objects.unlink(o)
    current.objects.link(o); o.data.materials.append(ma)
    for p in o.data.polygons:p.use_smooth=True
    return o
def bar(name,a,b,r,ma):
    v=Vector(b)-Vector(a); o=cyl(name,(Vector(a)+Vector(b))/2,r,v.length,ma)
    o.rotation_euler=v.to_track_quat('Z','Y').to_euler(); return o
def plant(x,y,z,s=1):
    cyl('Terracotta planter',(x,y,z+.2*s),.25*s,.4*s,terra)
    cyl('Potting soil',(x,y,z+.405*s),.22*s,.018,soil)
    for i in range(7):
        a=i*2.4; h=(.55+(i%3)*.17)*s
        tip=(x+math.cos(a)*.3*s,y+math.sin(a)*.3*s,z+h)
        bar('Plant stem',(x,y,z+.4*s),tip,.015*s,green)
        o=ball('Leaf',tip,(.16*s,.08*s,.3*s),leaves[i%4]); o.rotation_euler=(.5*math.sin(a),.7*math.cos(a),a)
def furniture_legs(x,y,z,w,d,h):
    for dx in [-w/2+.08,w/2-.08]:
        for dy in [-d/2+.08,d/2-.08]:box('Taper-look oak leg',(x+dx,y+dy,z+h/2),(.07,.07,h),oak,.01)
def chair(x,y,z,rot=0):
    before=set(current.objects)
    box('Dining chair / seat',(x,y,z+.46),(.48,.48,.11),linen,.05)
    furniture_legs(x,y,z,.45,.45,.42)
    box('Dining chair / back',(x,y+.21,z+.78),(.48,.09,.52),oak,.04)
    for o in set(current.objects)-before:
        dx=o.location.x-x;dy=o.location.y-y
        o.location.x=x+dx*math.cos(rot)-dy*math.sin(rot);o.location.y=y+dx*math.sin(rot)+dy*math.cos(rot);o.rotation_euler.z+=rot
def bed(x,y,z,w=1.7,col=blue):
    box('Bed / oak platform',(x,y,z+.28),(w+.12,2.12,.35),oak,.045)
    box('Bed / mattress',(x,y,z+.52),(w,2,.25),white,.1)
    box('Bed / upholstered headboard',(x,y+.98,z+.76),(w+.18,.13,1.12),linen,.05)
    box('Bed / folded duvet',(x,y-.29,z+.69),(w+.02,1.37,.13),col,.07)
    for dx in ([-.43,.43] if w>1.3 else [0]):box('Bed / pillow',(x+dx,y+.65,z+.74),(.63,.42,.18),linen,.09)
    for dx in [-w/2-.35,w/2+.35]:
        box('Bedside / cabinet',(x+dx,y+.65,z+.30),(.45,.48,.6),oak,.025)
        cyl('Bedside / lamp stem',(x+dx,y+.65,z+.74),.025,.28,brass)
        cyl('Bedside / linen shade',(x+dx,y+.65,z+.95),.17,.25,linen)
def artwork(x,y,z,w=1):
    box('Artwork / oak frame',(x,y,z),(w,.06,w*.7),oak,.015)
    box('Artwork / canvas',(x,y-.04,z),(w-.09,.01,w*.7-.09),linen)
    ball('Artwork / abstract sun',(x+.18*w,y-.057,z+.08*w),(.15*w,.012,.15*w),terra)
    box('Artwork / sea stripe',(x,y-.06,z-.13*w),(w-.12,.014,.12*w),blue)

group('00 Site • paving, garden and terrace')
box('Presentation ground',(0,0,-.48),(200,200,.2),mat('Backdrop / sand',(.69,.70,.64)))
box('Site / raised plot',(0,0,-.24),(14,12,.36),stone,.12)
box('Garden / lawn',(0,3.9,-.025),(13.6,3.8,.14),leaves[2],.05)
for x in range(-7,7):
    for y in [-5.7,-5.0,-4.3]:box('Front paving',(x+.48,y,-.025),(.94,.63,.1),cream,.025)
box('West sun terrace',(-6,0,.01),(2,7.5,.14),oak,.025)
for y in range(19):box('Terrace / board seam',(-6,-3.5+y*.39,.087),(1.98,.018,.009),stone)
for x,y in [(-6,-3),(-6,3),(5.8,-3.1),(5.8,3.8)]:plant(x,y,.05,1.3)
for x in [-5.6,-2.7,.1,2.9,5.6]:
    cyl('Garden / tree trunk',(x,5,.85),.12,1.7,oak)
    for dx,dy,dz in [(0,0,0),(.45,0,.15),(-.4,.2,.3),(0,.2,.7)]:ball('Garden / sculpted canopy',(x+dx,5+dy,1.8+dz),(.73,.63,.72),leaves[int(abs(x))%4])
box('Garden / rear boundary',(0,5.75,.45),(13.6,.2,1),stone,.03)
for x in [-6.2,6.2]:box('Garden / boundary return',(x,4.5,.4),(.18,2.5,.9),stone,.02)
cyl('Terrace / cafe table',(-6,-.4,.76),.57,.08,cream);cyl('Terrace / table pedestal',(-6,-.4,.4),.07,.72,dark)
chair(-6,-1.3,.08);chair(-6,.5,.08,math.pi)

def shell(level):
    z=level*3.2
    # True openings in wall meshes, with separate lintels, jambs and sills.
    def wall(name,axis,fixed,length,opens,front):
        group('%02d %s shell • %s'%(10+level*20,'GF' if not level else 'L1',name))
        def piece(n,a,b,lo,hi,ma=plaster,th=.24):
            if b-a<.001 or hi-lo<.001:return
            loc=((a+b)/2,fixed,z+(lo+hi)/2) if axis=='X' else (fixed,(a+b)/2,z+(lo+hi)/2)
            size=(b-a,th,hi-lo) if axis=='X' else (th,b-a,hi-lo)
            return box(n,loc,size,ma,.015)
        cursor=-length/2
        for center,w,sill,h in sorted(opens):
            a=center-w/2;b=center+w/2
            piece('Masonry / pier',cursor,a,0,3.2);piece('Masonry / under window',a,b,0,sill);piece('Masonry / lintel',a,b,sill+h,3.2)
            piece('Opening / sill',a-.08,b+.08,sill-.07,sill,cream,.37)
            piece('Opening / head trim',a-.1,b+.1,sill+h,sill+h+.12,cream,.31)
            for edge in [a,b]:piece('Opening / jamb',edge-.045,edge+.045,sill,sill+h,cream,.3)
            if sill>.01:
                piece('Window / reflective pane',a+.06,b-.06,sill+.06,sill+h-.06,glass,.035)
                for edge in [a+.06,center,b-.06]:piece('Window / vertical frame',edge-.025,edge+.025,sill,sill+h,cream,.09)
                piece('Window / crossbar',a,b,sill+h*.48,sill+h*.48+.05,cream,.09)
                if axis=='X':
                    for side in [-1,1]:
                        sx=center+side*(w/2+.27)
                        o=box('Shutter / sage',(sx,fixed+front*.18,z+sill+h/2),(.43,.08,h),green,.02)
                        for j in range(9):box('Shutter / louver',(sx,fixed+front*.23,z+sill+.1+j*(h-.2)/8),(.35,.05,.045),cream,.008)
            else:
                piece('Entry / oak door',a+.05,b-.05,.02,h-.04,green,.1)
                for zz in [.5,1.25]:piece('Entry / inset panel',a+.16,b-.16,zz,zz+.44,oak,.13)
                if axis=='X':ball('Entry / brass handle',(b-.17,fixed+front*.13,z+1.05),(.035,.04,.035),brass)
            cursor=b
        piece('Masonry / pier',cursor,length/2,0,3.2)
        piece('Facade / string course',-length/2,length/2,3.08,3.2,cream,.33)
        piece('Facade / granite skirting',-length/2,length/2,0,.22,stone,.29)
    wall('South removable facade','X',-4,10,[(-3,1.8,.85,1.65),(-.4,1.4,.85,1.65),(2.6,1.2,0,2.4)] if not level else [(-3,1.7,.8,1.75),(0,1.4,.8,1.75),(3,1.6,.8,1.75)],-1)
    wall('North facade','X',4,10,[(-3,1.7,1.05,1.5),(.5,1.3,1.1,1.45),(3.9,.7,1,1.6)],1)
    wall('West facade','Y',-5,8,[(-1.8,1.7,.85,1.65),(2,1.4,.95,1.55)],-1)
    wall('East removable facade','Y',5,8,[(-2,1.5,.85,1.65),(2,1.3,1.1,1.5)],1)

shell(0);shell(1)
group('11 GF • oak floor and foundation')
box('Foundation',(0,0,-.13),(10.3,8.3,.26),stone,.025)
for i in range(40):
    for j in range(4):box('GF / staggered oak board',(-4.875+i*.25,-3+j*2,.025),(.244,1.99,.05),woods[(i+j)%5])
group('12 GF • internal partitions')
# Kitchen at rear left; open passage to living room. Service room behind dining.
for a,b in [(-4.88,-2.4),(-1.2,.1)]:box('Kitchen / screen wall',((a+b)/2,1.35,1.4),(b-a,.14,2.8),plaster,.018)
box('Utility / west partition',(.7,2.6,1.4),(.14,2.8,2.8),plaster,.018)
box('Utility / front wall',(1.2,1.25,1.4),(1,.14,2.8),plaster,.018)
box('Utility / door header',(2.1,1.25,2.6),(.8,.14,.4),plaster)
group('13 GF • living room furniture and decor')
box('Living / woven rug',(-2.9,-1.8,.07),(3.4,3.15,.04),linen,.06)
for i in range(7):box('Rug / woven stripe',(-2.9,-3.1+i*.43,.095),(3.18,.035,.006),terra)
box('Sofa / plinth',(-3,-.05,.25),(2.8,.95,.34),oak,.05)
box('Sofa / back',(-3,.33,.78),(2.9,.23,.95),linen,.1)
for x in [-4.35,-1.65]:box('Sofa / arm',(x,-.02,.62),(.22,.95,.55),linen,.07)
for x in [-3.85,-3,-2.15]:
    box('Sofa / seat',(x,-.13,.5),(.8,.72,.23),linen,.09)
    p=box('Sofa / cushion',(x,.12,.91),(.55,.18,.48),blue if x==-3 else terra,.08);p.rotation_euler.x=-.15
box('Coffee table / rounded oak',(-3,-1.75,.48),(1.55,.75,.12),oak,.17);furniture_legs(-3,-1.75,.09,1.4,.6,.33)
for i in range(3):box('Coffee table / books',(-3.3,-1.7,.57+i*.045),(.36,.26,.04),[blue,cream,terra][i],.005)
cyl('Coffee table / bowl',(-2.6,-1.75,.6),.17,.12,white)
box('Reading chair / seat',(-4.05,-2.9,.47),(.75,.72,.24),green,.1)
box('Reading chair / back',(-4.05,-3.22,.83),(.75,.18,.65),green,.09);furniture_legs(-4.05,-2.9,.07,.65,.6,.3)
box('Living / media console',(-.28,-1.75,.43),(.42,2,.75),oak,.035)
box('Living / television',(-.27,-1.75,1.23),(.07,1.35,.75),dark,.025)
plant(-4.45,.8,.05,.8);artwork(-3,1.25,1.9,1.6)
group('14 GF • kitchen cabinets and equipment')
for x in [-4.35,-3.45,-2.55,-1.65,-.75]:
    box('Kitchen / base cabinet',(x,3.48,.48),(.87,.82,.9),green,.025)
    box('Kitchen / drawer front',(x,3.045,.73),(.78,.04,.22),cream,.012)
    bar('Kitchen / brass pull',(x-.18,3.005,.72),(x+.18,3.005,.72),.014,brass)
    box('Kitchen / stone worktop',(x,3.45,.96),(.91,.91,.08),cream,.018)
    box('Kitchen / upper cabinet',(x,3.68,2.23),(.87,.42,.83),green,.02)
box('Kitchen / backsplash',(-2.5,3.855,1.4),(4.7,.035,.75),tile)
box('Kitchen / sink rim',(-3.45,3.44,1.015),(.66,.51,.045),dark,.06)
box('Kitchen / sink basin',(-3.45,3.44,1.04),(.54,.39,.025),stone,.07)
bar('Kitchen / tap',(-3.45,3.75,1.02),(-3.45,3.75,1.38),.025,brass);bar('Kitchen / spout',(-3.45,3.75,1.38),(-3.45,3.5,1.38),.025,brass)
box('Kitchen / hob',(-1.65,3.42,1.02),(.74,.62,.035),dark,.035)
for x in [-1.85,-1.45]:
    for y in [3.22,3.6]:cyl('Hob / burner',(x,y,1.045),.12,.012,stone)
box('Kitchen / oven',(-1.65,3.025,.43),(.7,.05,.48),dark,.025)
box('Kitchen / island',(-2.75,2.08,.46),(1.7,.65,.9),oak,.035)
box('Kitchen / island top',(-2.75,2.08,.96),(1.85,.77,.11),cream,.025)
cyl('Kitchen / fruit bowl',(-2.6,2.1,1.07),.23,.1,white)
for i in range(4):ball('Kitchen / citrus',(-2.75+i*.09,2.1,1.16),(.065,.065,.065),terra)
group('15 GF • dining and entry')
box('Dining / rug',(1.65,-1.2,.065),(2.75,2.9,.035),blue,.03)
box('Dining / oak table',(1.65,-1.1,.79),(1.25,1.75,.12),oak,.08);furniture_legs(1.65,-1.1,.09,1.1,1.55,.64)
for y in [-1.65,-.55]:chair(.68,y,.09,-math.pi/2);chair(2.62,y,.09,math.pi/2)
for y in [-1.55,-.65]:
    for x in [1.25,2.05]:cyl('Dining / ceramic plate',(x,y,.862),.18,.025,white)
cyl('Dining / vase',(1.65,-1.1,1.02),.12,.32,terra)
box('Entry / coir mat',(2.6,-3.45,.07),(1.1,.55,.035),oak,.015)
box('Entry / bench',(4.1,-3.35,.48),(1.1,.42,.12),oak,.02);furniture_legs(4.1,-3.35,.05,1,.38,.37)
plant(.25,-3.3,.05,.7)
group('16 GF • laundry and WC')
box('Laundry / washing machine',(1.35,3.4,.5),(.65,.65,.92),white,.04)
o=cyl('Laundry / round washer door',(1.35,3.06,.5),.23,.045,dark);o.rotation_euler.x=math.pi/2
box('WC / cistern',(2.3,3.58,.62),(.43,.23,.77),white,.07)
ball('WC / bowl',(2.3,3.22,.38),(.27,.39,.25),white)
box('Utility / small basin',(1.15,2,.87),(.58,.43,.13),white,.07)
group('17 Stair • independent treads and balustrade')
for i in range(16):
    y=-1+i*.285; z=(i+1)*.2
    box('Stair / tread %02d'%(i+1),(4.08,y,z-.06),(1.28,.3,.12),oak,.012)
    box('Stair / riser %02d'%(i+1),(4.08,y-.13,z-.15),(1.28,.035,.2),cream)
    if i%2==0:bar('Stair / baluster',(3.43,y,z),(3.43,y,z+.88),.022,dark)
bar('Stair / continuous handrail',(3.43,-1,.98),(3.43,3.275,3.98),.045,oak)
bar('Stair / stringer',(3.55,-1,.06),(3.55,3.275,3.06),.075,oak)
group('31 L1 • floor with stair opening')
box('L1 / structural floor',(-.81,0,3.13),(8.38,8,.14),cream)
box('L1 / front floor wing',(4.19,-2.7,3.13),(1.62,2.6,.14),cream)
box('L1 / stair landing',(4.19,3.71,3.13),(1.62,.58,.14),cream)
for i in range(33):
    for j in range(4):box('L1 / oak floorboard',(-4.87+i*.25,-3+j*2,3.22),(.243,1.99,.04),woods[(i+j)%5])
box('L1 / front bedroom floor',(4.14,-2.69,3.22),(1.6,2.58,.04),woods[2])
box('L1 / landing finish',(4.1,3.7,3.22),(1.8,.58,.04),woods[2])
group('32 L1 • room divisions with open doorways')
def partition_y(name,y,a,b,gaps):
    cursor=a
    for lo,hi in gaps:
        box(name,((cursor+lo)/2,y,4.55),(lo-cursor,.14,2.7),plaster,.012)
        box(name+' / door lintel',((lo+hi)/2,y,5.72),(hi-lo,.14,.36),plaster)
        cursor=hi
    box(name,((cursor+b)/2,y,4.55),(b-cursor,.14,2.7),plaster,.012)
partition_y('Bedrooms / corridor south',.15,-5,3.36,[(-1.6,-.65),(1.5,2.4)])
partition_y('Bedrooms / corridor north',1.5,-5,3.36,[(-1.6,-.65),(1.5,2.4)])
box('Bedrooms / party wall',(-.1,-1.92,4.55),(.14,4.0,2.7),plaster,.015)
box('Bathroom / party wall',(-.1,2.75,4.55),(.14,2.5,2.7),plaster,.015)
box('Stair / bedroom divider',(3.36,-.63,4.55),(.14,1.56,2.7),plaster,.015)
for y in [-.9,-.3,.3,.9,1.5,2.1,2.7,3.25]:bar('Landing / guard post',(3.36,y,3.23),(3.36,y,4.15),.023,dark)
bar('Landing / guard top',(3.36,-1.2,4.15),(3.36,3.3,4.15),.04,oak)
group('33 L1 • primary bedroom')
box('Primary / rug',(-2.7,-2,3.26),(3.45,3.2,.04),linen,.04)
bed(-2.7,-1.45,3.25)
box('Primary / wardrobe',(-4.48,-1.1,4.37),(.65,1.9,2.2),green,.03)
for y in [-1.55,-.65]:bar('Wardrobe / handle',(-4.13,y,4.2),(-4.13,y,4.5),.02,brass)
artwork(-2.7,.055,5.0,1.2)
box('Primary / window bench',(-2.65,-3.55,3.62),(1.7,.45,.68),oak,.03)
box('Primary / bench cushion',(-2.65,-3.55,4),(1.75,.48,.13),terra,.035)
group('34 L1 • guest bedroom and study')
bed(1.55,-2.2,3.25,1.25,terra)
box('Guest / writing desk',(.62,-.45,4.02),(.85,.52,.1),oak,.025);furniture_legs(.62,-.45,3.25,.8,.45,.72)
chair(.65,-1,3.25,math.pi)
box('Guest / notebook',(.62,-.45,4.095),(.3,.24,.035),blue)
plant(2.9,-3.4,3.25,.65)
group('35 L1 • child bedroom')
bed(-3.55,2.66,3.25,1.05,green)
box('Child / round rug',(-1.45,2.65,3.27),(1.55,1.7,.035),terra,.2)
box('Child / bookshelf',(-.52,3.5,3.98),(.55,.6,1.45),oak,.02)
for z in [3.55,4,4.45]:
    for i in range(4):box('Child / storybook',(-.72+i*.12,3.16,z),(.085,.23,.25),[blue,linen,green,terra][i],.003)
for i in range(5):box('Child / wooden block',(-1.8+i*.18,2.5,3.36),(.15,.15,.16),[cream,green,blue,terra,oak][i],.01)
group('36 L1 • tiled bathroom')
for i in range(7):
    for j in range(5):box('Bath / floor tile',(.18+i*.45,1.77+j*.45,3.26),(.435,.435,.035),tile if (i+j)%2 else cream,.005)
box('Bath / tub outer',(1.1,3.27,3.59),(1.75,.9,.62),white,.16)
box('Bath / tub inset',(1.1,3.27,3.915),(1.48,.65,.035),glass,.15)
bar('Bath / tub tap',(.45,3.7,3.9),(.45,3.7,4.2),.026,brass)
box('Bath / vanity',(2.8,2.12,3.68),(.72,.8,.85),oak,.035)
box('Bath / basin',(2.8,2.12,4.15),(.73,.78,.13),white,.09)
box('Bath / mirror',(3.255,2.15,4.83),(.035,.68,.95),glass,.045)
box('Bath / towel rail',(.32,2,4.2),(.055,.65,.045),brass)
box('Bath / towel',(.30,2,3.98),(.06,.42,.48),linen,.02)

group('40 Roof • removable slate assembly')
# Gable volume is split from roof planes to support clean cutaways.
for x in [-5,5]:
    obj('Roof / limewashed gable',[(x-.1,-4,6.4),(x-.1,4,6.4),(x-.1,0,8.35),(x+.1,-4,6.4),(x+.1,4,6.4),(x+.1,0,8.35)],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],plaster)
pitch=math.atan2(1.95,4.35)
for sign in [-1,1]:
    o=box('Roof / slate plane',(0,sign*2.18,7.36),(10.7,4.85,.16),slate,.025);o.rotation_euler.x=-sign*pitch
    for row in range(12):
        y=sign*(.17+row*.375);z=8.35-abs(y)*1.95/4.35+.11
        for col in range(24):
            x=-5.18+col*.45+(row%2)*.05
            o=box('Roof / individual slate course',(x,y,z),(.437,.415,.035),slates[(row+col)%5],.008);o.rotation_euler.x=-sign*pitch
    bar('Roof / rain gutter',(-5.3,sign*4.4,6.34),(5.3,sign*4.4,6.34),.085,dark)
bar('Roof / ridge cap',(-5.4,0,8.43),(5.4,0,8.43),.09,slate)
box('Roof / brick chimney',(-3,1.5,8.17),(.65,.75,1.8),terra,.025)
for z in [7.6,7.85,8.1,8.35,8.6,8.85]:box('Chimney / mortar course',(-3,1.5,z),(.67,.77,.025),cream)
box('Chimney / stone cap',(-3,1.5,9.1),(.86,.95,.16),stone,.025)
group('41 Exterior • canopy, planters and trim')
box('Entry / canopy',(2.6,-4.5,2.8),(1.8,1.1,.12),slate,.02)
for x in [1.85,3.35]:bar('Canopy / brace',(x,-4.05,2.2),(x,-4.8,2.73),.035,dark)
for x in [-4.7,4.7]:bar('Facade / downpipe',(x,-4.27,.2),(x,-4.27,6.35),.045,dark)
for x in [-3,-.4]:
    box('Facade / window box',(x,-4.3,.75),(1.5,.36,.3),green,.03)
    for i in range(6):ball('Window box / foliage',(x-.6+i*.24,-4.3,1),(.18,.19,.2),leaves[i%4])
box('Entry / threshold',(2.6,-4.3,.09),(1.4,.65,.18),cream,.02)

group('90 Presentation • cameras and studio lighting')
world=bpy.data.worlds.new('Coastal daylight');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.69,.78,.88,1);world.node_tree.nodes['Background'].inputs[1].default_value=.45;scene.world=world
def light(name,loc,power,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    o=bpy.data.objects.new(name,data);current.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,2))-o.location).to_track_quat('-Z','Y').to_euler()
light('Large warm key',(-8,-10,18),2400,9);light('Soft sky fill',(7,3,14),1800,8)
sun=bpy.data.lights.new('Late afternoon sun','SUN');sun.energy=2;sun.angle=.12;o=bpy.data.objects.new('Late afternoon sun',sun);current.objects.link(o);o.rotation_euler=(.45,-.5,-.4)
def camera(name,loc,target,scale):
    d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);current.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=scale;return o
ext=camera('Camera / exterior',(16,-22,16),(0,0,3.1),20)
gf=camera('Camera / ground cutaway',(12,-17,18),(0,0,0),16)
up=camera('Camera / upper cutaway',(11,-16,21),(0,0,3.5),15)
plan0=camera('Camera / ground plan',(0,0,25),(0,0,0),12)
plan1=camera('Camera / upper plan',(0,0,28),(0,0,3.2),12)
def settings(s):
    s.world=world;s.render.engine='CYCLES';s.cycles.samples=32;s.cycles.use_denoising=True
    s.render.resolution_x=1500;s.render.resolution_y=1200;s.render.resolution_percentage=100
    s.render.image_settings.file_format='PNG';s.view_settings.view_transform='AgX'
settings(scene);scene.camera=ext
def variant(name,cam,allow):
    s=bpy.data.scenes.new(name);s.unit_settings.system='METRIC';settings(s);s.camera=cam
    for n,c in groups.items():
        if allow(n):s.collection.children.link(c)
    return s
ground=variant('Residence • 02 Ground cutaway',gf,lambda n:n.startswith(('00','11','12','13','14','15','16','17','90')) or (n.startswith('10') and ('North' in n or 'West' in n)))
upper=variant('Residence • 03 Upper cutaway',up,lambda n:n.startswith(('31','32','33','34','35','36','90')) or (n.startswith('30') and ('North' in n or 'West' in n)))
p0=variant('Residence • 04 Ground plan',plan0,lambda n:n.startswith(('10','11','12','13','14','15','16','17','90')))
p1=variant('Residence • 05 Upper plan',plan1,lambda n:n.startswith(('30','31','32','33','34','35','36','90')))
scene['Design']='Atlantic House / 10 x 8 m / two storeys / three bedrooms / 3.2 m floor-to-floor'
scene['Navigation']='Switch scenes for exterior, furnished cutaways and orthographic plans. Collection prefixes identify site, floor, room, facade, roof and presentation.'
scene['Status']='Editable visual design study; not construction documentation or integrated game art.'
bpy.context.window.scene=scene
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.shading.type='MATERIAL'
# REVIEW_REFINEMENTS_BEGIN
# Complete the landing-to-hall route outside the bathroom.
current=groups['32 L1 • room divisions with open doorways']
box('Bathroom / east wall beside landing corridor',(2.42,2.78,4.55),(.14,2.44,2.7),plaster,.015)
for o in current.objects:
    if o.name.startswith('Bedrooms / corridor north') and o.location.x>2.4:
        o.location.x=2.445;o.scale.x=.09/.96
for o in groups['36 L1 • tiled bathroom'].objects:
    if o.name.startswith(('Bath / vanity','Bath / basin')):o.location.x=1.8
    if o.name.startswith('Bath / mirror'):o.location.x=2.325
    if o.name.startswith('Bath / floor tile') and o.location.x>2.35:o.hide_render=True;o.hide_viewport=True
for o in groups['31 L1 • floor with stair opening'].objects:
    if o.name.startswith(('L1 / stair landing','L1 / landing finish')):
        o.location.y=3.58;o.scale.y=1.42
current=groups['14 GF • kitchen cabinets and equipment']
for o in list(current.objects):
    if o.name.startswith('Kitchen / upper cabinet'):
        # Existing generated cabinets only; remove those obstructing the opening.
        if -3.95<o.location.x<-2:
            bpy.data.objects.remove(o,do_unlink=True)
            continue
    elif o.name.startswith('Kitchen / backsplash'):
        o.scale.z=.12;o.location.z=1.075
    if o.name.startswith(('Kitchen / island','Kitchen / fruit bowl','Kitchen / citrus')):
        o.location.x-=.55;o.location.y-=.12
box('Kitchen / refrigerator',(-.25,2.45,1.08),(.7,.75,2.06),cream,.055)
box('Kitchen / refrigerator door',(-.25,2.055,1.31),(.63,.045,1.38),white,.025)
bar('Refrigerator / handle',(.0,2.01,1.1),(.0,2.01,1.62),.02,brass)
current=groups['15 GF • dining and entry']
bar('Dining pendant / cord',(1.65,-1.1,2.95),(1.65,-1.1,2.27),.012,dark)
cyl('Dining pendant / shade',(1.65,-1.1,2.23),.35,.24,cream)
cyl('Dining pendant / diffuser',(1.65,-1.1,2.10),.30,.015,white)
current=groups['13 GF • living room furniture and decor']
cyl('Reading lamp / base',(-4.3,-2.2,.11),.22,.06,dark)
bar('Reading lamp / stem',(-4.3,-2.2,.12),(-4.3,-2.2,1.65),.025,brass)
cyl('Reading lamp / linen shade',(-4.3,-2.2,1.65),.25,.37,linen)
# Consistent outward normals avoid black bevel caps in cutaways.
import bmesh
for o in scene.objects:
    if o.type=='MESH':
        bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
# Fit the complete presentation plot in the cutaway frame.
for o in scene.objects:
    if o.name.startswith('Facade / string course'):o.location.z+=.045
# Plan-only partitions omit overhead lintels so door openings remain legible.
for ps,prefix in [(p0,'12 GF'),(p1,'32 L1')]:
    source=next(c for c in ps.collection.children if c.name.startswith(prefix))
    ps.collection.children.unlink(source)
    pc=bpy.data.collections.new(ps.name+' / plan partitions');ps.collection.children.link(pc)
    for o in source.objects:
        if 'lintel' in o.name or 'header' in o.name:continue
        copy=o.copy();pc.objects.link(copy)
        if copy.type=='MESH':
            copy.data=o.data.copy()
            base=3.2 if ps==p1 else 0
            copy.location.z=base+.55;copy.scale.z*=1.1/max(o.dimensions.z,.001)
gf.data.ortho_scale=18.5
up.data.ortho_scale=16
for s in [scene,ground,upper,p0,p1]:
    s.render.resolution_percentage=100;s.cycles.samples=32
# REVIEW_REFINEMENTS_END
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'atlantic_residence.blend'),compress=True)
manifest={'blend':os.path.join(OUT,'atlantic_residence.blend'),'objects':len(scene.objects),'collections':len(groups),'scenes':[s.name for s in [scene,ground,upper,p0,p1]],'renders':{s.name:os.path.join(OUT,n+'.png') for s,n in [(scene,'01_exterior'),(ground,'02_ground_cutaway'),(upper,'03_upper_cutaway'),(p0,'04_ground_plan'),(p1,'05_upper_plan')]}}
with open(os.path.join(OUT,'manifest.json'),'w') as f:json.dump(manifest,f,indent=2)
result=manifest
