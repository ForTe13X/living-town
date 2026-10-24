"""Original gathered linen bow, with physical strip UVs and closed cloth edges."""
import math

from .geometry import catmull_path


def _unit(vector):
    length=math.sqrt(sum(v*v for v in vector))
    return tuple(v/length for v in vector) if length>1e-10 else (1.,0.,0.)


def _cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])


def _strip(points,widths,across,twist,scale,repeat,pleat=.0012):
    front=[];back=[];uv=[];distance=0.;columns=5
    for row,point in enumerate(points):
        t=row/(len(points)-1);before=points[max(0,row-1)];after=points[min(len(points)-1,row+1)]
        tangent=_unit(tuple(after[k]-before[k] for k in range(3)))
        dot=sum(across[k]*tangent[k] for k in range(3))
        side=_unit(tuple(across[k]-dot*tangent[k] for k in range(3)))
        normal=_unit(_cross(tangent,side));angle=twist(t)
        side=tuple(side[k]*math.cos(angle)+normal[k]*math.sin(angle) for k in range(3))
        normal=_unit(_cross(tangent,side))
        if row:distance+=math.dist(points[row-1],point)
        width=widths(t)
        for column in range(columns):
            u=column/(columns-1)-.5
            # A broad central crease gathers the fabric without noisy bumps.
            gather=pleat*(.35+.65*math.sin(math.pi*t)**2)*math.cos(u*math.tau)
            p=tuple(point[k]+side[k]*width*u+normal[k]*gather for k in range(3))
            front.append(p);back.append(tuple(p[k]-normal[k]*.0012 for k in range(3)))
            uv.append((u*width*scale/repeat[0],distance*scale/repeat[1]))
    n=len(front);faces=[]
    for row in range(len(points)-1):
        for column in range(columns-1):
            a=row*columns+column;b=a+columns
            faces.extend([(a,b,b+1,a+1),(n+a+1,n+b+1,n+b,n+a)])
        a=row*columns;b=a+columns
        faces.extend([(a,n+a,n+b,b),(a+columns-1,b+columns-1,n+b+columns-1,n+a+columns-1)])
    for column in range(columns-1):
        a=column;b=(len(points)-1)*columns+column
        faces.extend([(a,a+1,n+a+1,n+a),(b,n+b,n+b+1,b+1)])
    return front+back,faces,uv+uv


def gathered_bow(anchor,back_depth,scale,repeat):
    """Tie the existing rear waist attachment; no additional joints required.

    Both loops, the wrapped gathered knot and two folded tails use the same
    measured linen repeat. Back tails follow the actual trouser envelope and
    remain attached to PelvisRoot, rather than the front apron seat hinge.
    """
    ax,ay,az=anchor;parts=[]
    for sign in (-1,1):
        controls=[(.003*sign,0.,0.),(.022*sign,-.006,.012),(.047*sign,-.010,.017),
                  (.058*sign,-.006,.005),(.045*sign,.002,-.008),(.018*sign,.003,-.006),(.002*sign,0.,-.002)]
        points=catmull_path([(ax+x,ay+y,az+z) for x,y,z in controls],4)
        parts.append(_strip(points,lambda t:.007+.014*math.sin(math.pi*t)**.7,(0.,0.,1.),
                            lambda t:sign*(.25*math.sin(math.tau*t)-.10),scale,repeat,.0011))
        length=.148 if sign<0 else .163
        controls=[]
        for t in (0.,.18,.48,.77,1.):
            x=ax+sign*(.004+.036*t+.004*math.sin(math.pi*t));z=az-.010-length*t
            y=min(ay-.004-.004*math.sin(math.pi*t),back_depth(x,z)-.003)
            controls.append((x,y,z))
        points=catmull_path(controls,5)
        parts.append(_strip(points,lambda t:.008+.011*math.sin(min(1.,t*3)*math.pi/2),
                            (1.,0.,0.),lambda t:sign*(.16+.20*math.sin(math.pi*t)),scale,repeat,.0014))
    # A narrow fabric band wraps the compressed center, not a solid bead.
    points=[]
    for row in range(25):
        angle=row/24*(math.tau-.20)
        points.append((ax+.0015*math.sin(2*angle),ay+.006*math.cos(angle),az+.010*math.sin(angle)))
    parts.append(_strip(points,lambda t:.017+.002*math.sin(math.pi*t),(1.,0.,0.),lambda t:0.,scale,repeat,.0007))
    vertices=[];faces=[];uv=[]
    for points,polygons,coords in parts:
        offset=len(vertices);vertices.extend(points);faces.extend(tuple(offset+i for i in face) for face in polygons);uv.extend(coords)
    geometry=(vertices,faces,uv)
    weights=[{'PelvisRoot':1.} for point in vertices]
    return geometry,weights,{'style':'two gathered cloth loops, wrapped linen knot and two folded tails',
                             'anchor_source_m':list(anchor),'parts':5,'extra_joints':0,
                             'material':'existing verified apron linen PBR','uv_mapping':'physical strip width and cumulative arc length divided by photographed repeat; persona scale included',
                             'repeat_m':list(repeat),'minimum_tail_source_z_m':min(p[2] for p in vertices),
                             'rig':'PelvisRoot; rear waist stays independent of front ApronDrape seat hinge'}
