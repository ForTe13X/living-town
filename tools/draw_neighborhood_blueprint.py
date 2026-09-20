"""Render the authored proposal as a reusable, texture-free visual anchor."""
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'analysis/247'
OUT.mkdir(parents=True,exist_ok=True)
def read(p): return json.loads((ROOT/p).read_text(encoding='utf8'))
world=read('game/data/map.json'); plan=read('game/data/coastal_plan.json')
lots=read('game/assets/art/houses/lots.json')['lots']; interior=read('game/data/interiors.json')
spaces=read('game/data/spaces.json')
im=Image.new('RGB',(2200,1700),'#f2efe6'); d=ImageDraw.Draw(im)
INK='#304842'; MUTED='#66776d'; LINE='#aab2a3'; HOUSE='#c39176'; CIVIC='#85a6ae'; GREEN='#b2c3a0'
def font(s,b=False):return ImageFont.truetype('C:/Windows/Fonts/'+('arialbd.ttf' if b else 'arial.ttf'),s)
def text(p,t,s=22,fill=INK,b=False):d.text(p,t,font=font(s,b),fill=fill)
def rect(r,fill,outline=None,width=1):d.rectangle(r,fill=fill,outline=outline,width=width)
def arrow(x,y,dx,dy,length=21):
 ex,ey=x+dx*length,y+dy*length
 d.line((x,y,ex,ey),fill=INK,width=3)
 d.polygon([(ex,ey),(ex-dx*8+dy*5,ey-dy*8-dx*5),(ex-dx*8-dy*5,ey-dy*8+dx*5)],fill=INK)
text((65,40),'COASTAL TOWN',46,b=True)
text((65,101),'247 / Massing, planted streets & room plans',26)
text((1540,45),'DESIGN ANCHOR',24,b=True)
text((1540,84),'Schematic plan · not a rendered screenshot',20,fill=MUTED)
d.line((65,148,2135,148),fill=LINE,width=2)
X,Y,S=65,200,22
def box(x,y,w,h):return (X+x*S,Y+y*S,X+(x+w)*S,Y+(y+h)*S)
rect(box(0,0,64,48),'#e4e9d9')
for x in range(65):d.line((X+x*S,Y,X+x*S,Y+48*S),fill='#dbe0d2')
for y in range(49):d.line((X,Y+y*S,X+64*S,Y+y*S),fill='#dbe0d2')
for x,y in world['water']:rect(box(x,y,1,1),'#b4d0d4')
for material,cells in plan['surfaces'].items():
 for x,y in cells:rect(box(x,y,1,1),{'paving':'#fcf9ee','asphalt':'#aeb3af','gravel':'#d8ccaf'}[material])
for bed in plan['flowerbeds']:
 x,y=bed['pos'];px,py=X+(x+.5)*S,Y+(y+.5)*S
 d.ellipse((px-7,py-4,px+7,py+4),fill='#b298a8')
for x,y in world['trees']:
 px,py=X+(x+.5)*S,Y+(y+.5)*S
 d.ellipse((px-12,py-12,px+12,py+12),fill=GREEN,outline='#728e6b',width=2)
 d.line((px-5,py,px+5,py),fill='#728e6b')
def building(x,y,w,h,kind,facing='south',label=None,row=False):
 r=box(x,y,w,h); a,b,c,e=r
 rect((a+4,b+5,c+4,e+5),'#c5c8b9')
 rect(r,CIVIC if kind in ['library','wash','civic'] else HOUSE,INK,2)
 if kind=='library':
  rr=min(w,h)*S*.28;cx,cy=(a+c)/2,(b+e)/2
  d.ellipse((cx-rr,cy-rr,cx+rr,cy+rr),fill='#dce4df',outline=INK,width=2)
 elif kind=='wash':
  for cx,rr in [((a+c)/2,23),(a+22,12),(c-22,12)]:d.ellipse((cx-rr,(b+e)/2-rr,cx+rr,(b+e)/2+rr),fill='#dce4df',outline=INK,width=2)
 elif kind=='work':
  for yy in range(int(b)+15,int(e),27):d.line((a+5,yy,c-5,yy),fill=INK,width=2)
 elif kind=='courtyard':
  rect((a+w*S*.28,b+h*S*.22,c-w*S*.28,e-h*S*.26),'#e4e9d9',INK,2)
 else:
  d.line((a+8,(b+e)/2,c-8,(b+e)/2),fill=INK,width=2)
  d.line((a,b,a+8,(b+e)/2,a,e),fill=INK)
  d.line((c,b,c-8,(b+e)/2,c,e),fill=INK)
 if row:
  for xx in range(int(a)+int(S*2),int(c),int(S*2)):d.line((xx,b,xx,e),fill=INK,width=2)
 if facing=='north':arrow((a+c)/2,b,0,-1)
 elif facing=='east':arrow(c,(b+e)/2,1,0)
 elif facing=='west':arrow(a,(b+e)/2,-1,0)
 else:arrow((a+c)/2,e,0,1)
 if label:
  tw=d.textlength(label,font=font(18,True)); px=(a+c-tw)/2;py=(b+e)/2-10
  rect((px-4,py-2,px+tw+4,py+23),'#f9f5e9')
  text((px,py),label,18,b=True)
for lot in lots:
 if lot['sprite'] in ['beach_social_pergola','beach_deckchair_cluster','netshed']:continue
 building(lot['x'],lot['y'],lot['w'],lot['h'],'civic' if lot.get('landmark') else 'house',lot.get('facing','south'),row=bool(lot.get('row_id')))
labels={'home':'RESIDENCES','home2':'COURTYARD','cafe':'CAFE','shop':'GROCER','wash':'BATHHOUSE','work':'WORKSHOP','library':'LIBRARY'}
for k,a in world['areas'].items():
 if k in labels:building(*a['rect'],'courtyard' if k=='home2' else k,'north' if k in ['work','wash'] else 'south',labels[k],k=='home')
for p in plan['passages']:
 x,y=p['pos'];w,h=p['footprint'];r=box(x,y,w,h)
 rect(r,None,INK,3)
 for xx,yy in p['open_cells']:rect(box(xx,yy,1,1),'#fcf9ee')
text((X+28*S,Y+23*S),'CIVIC',18,b=True);text((X+28*S,Y+24*S),'SQUARE',18,b=True)
text((X+60*S+7,Y+22*S),'SEA',18,fill='#4c737b',b=True)
arrow(X+63*S,Y+3*S,0,-1,35);text((X+62.6*S,Y+0.3*S),'N',22,b=True)
text((65,1290),'MASSING KEY',20,b=True)
for x,col,label in [(65,HOUSE,'Street-wall housing / shops'),(450,CIVIC,'Distinct civic silhouettes'),(830,GREEN,'Tree belts & planted verges')]:
 rect((x,1330,x+23,1353),col,INK);text((x+35,1329),label,20)
arrow(1270,1344,1,0);text((1305,1329),'Front',20)

# Interior sketches share the exact proposed partition and recess geometry.
text((1540,181),'ROOM PLAN STUDIES',24,b=True)
for sid,title,origin in [('cafe','01  Cafe / L-shaped salon',(1550,255)),('library','02  Library / reading rotunda',(1550,610)),('wash','03  Baths / screened suites',(1550,990))]:
 ox,oy=origin;text((ox,oy-36),title,23,b=True)
 w,h=spaces['spaces'][sid]['bounds'][2:]; ss=38
 r=(ox,oy,ox+w*ss,oy+h*ss);rect(r,'#fdfbf5',INK,4)
 content=interior[sid]['1f']
 for room in content.get('rooms',[]):
  x,y,rw,rh=room['rect'];rect((ox+x*ss,oy+y*ss,ox+(x+rw)*ss,oy+(y+rh)*ss),'#e3e4d7')
 for f in content['furniture']:
  x,y=f['pos'];fw,fh=f.get('size',[1,1]);a=ox+x*ss;b=oy+(y-fh+1)*ss
  if f['slot'] in ['window','rug','painting_sea','painting_parasol']:continue
  if f['slot']=='wall':rect((a,b,a+ss,b+ss),INK)
  else:rect((a+5,b+5,a+fw*ss-5,b+fh*ss-5),'#b9c7be',INK)
 for x,y,cw,ch in content.get('cutouts',[]):
  a,b,c,e=ox+x*ss,oy+y*ss,ox+(x+cw)*ss,oy+(y+ch)*ss
  rect((a,b,c,e),'#f2efe6')
  if x>0:d.line((a,b,a,e),fill=INK,width=3)
  if x+cw<w:d.line((c,b,c,e),fill=INK,width=3)
  if y>0:d.line((a,b,c,b),fill=INK,width=3)
  if y+ch<h:d.line((a,e,c,e),fill=INK,width=3)
 for p in spaces['portals']:
  if p['to']['space']==sid and p['kind']=='door':
   x,y=p['to']['pos'];px=ox+(x+.5)*ss;py=oy+(y+.5)*ss
   d.ellipse((px-8,py-8,px+8,py+8),fill='#f2efe6',outline=INK,width=2)
 text((ox,oy+h*ss+12),' / '.join(r['label'] for r in content.get('rooms',[])),18,fill=MUTED)

d.line((65,1390,2135,1390),fill=LINE,width=2)
text((65,1420),'STREET ELEVATION / one row, several identities',25,b=True)
for i,(color,height) in enumerate([('#c4ad89',112),('#bac0a5',118),('#d5b3a5',112),('#d4cbbb',112),('#bcb39c',125),('#c8a791',112)]):
 x=70+i*150;bottom=1630;top=bottom-height
 rect((x,top,x+150,bottom),color,INK,2)
 d.polygon([(x,top),(x+24,top-26),(x+133,top-26),(x+150,top)],fill=HOUSE,outline=INK)
 for xx in [x+27,x+83]:
  for yy in [top+16,top+51]:rect((xx,yy,xx+24,yy+22),'#f4efdf',INK,2)
 rect((x+60,bottom-37,x+83,bottom),INK)
text((1100,1488),'Aligned frontage, varied bays and rooflines',23,b=True)
text((1100,1530),'Doors face the street; gardens occupy the rear.',23)
text((1100,1570),'Civic domes and workshop sawtooths break the row.',23)
text((65,1665),'REFERENCE INTENT  /  Aranya coastal town · continuous blocks · green streets · distinct room plans',18,fill=MUTED)
im.save(OUT/'neighborhood-blueprint.png')
print(OUT/'neighborhood-blueprint.png')
