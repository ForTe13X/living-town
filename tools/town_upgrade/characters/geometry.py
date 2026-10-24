"""Dependency-free anatomy topology; Blender is only the scene/export adapter."""
from __future__ import annotations

import math


def ring_surface(profile, segments=24, folds=0.0):
    """Closed cross-section surface with explicit UVs and outward winding.

    Profile rows: (z, x_radius, y_radius, y_center). Positive Y is the face
    in Blender; glTF axis conversion makes this negative Z in the engine.
    """
    profile=sorted(profile,key=lambda row:row[0])
    vertices=[]; faces=[]; uv=[]
    for j,(z,rx,ry,cy) in enumerate(profile):
        for i in range(segments+1):
            a=2*math.pi*i/segments
            wrinkle=folds*(math.sin(a*7+j*.9)+.45*math.sin(a*13-j*.6))
            vertices.append((math.sin(a)*(rx+wrinkle),cy+math.cos(a)*(ry+wrinkle),z))
            uv.append((i/segments,j/max(1,len(profile)-1)))
    for j in range(len(profile)-1):
        for i in range(segments):
            a=j*(segments+1)+i; b=a+segments+1
            faces.append((a,b,b+1,a+1))
    faces.append(tuple(range(segments)))
    start=(len(profile)-1)*(segments+1)
    faces.append(tuple(start+i for i in range(segments-1,-1,-1)))
    return vertices,faces,uv


def ellipsoid(center,radii,segments=20,rings=12):
    profile=[]
    for j in range(rings+1):
        a=-math.pi/2+math.pi*j/rings
        profile.append((center[2]+radii[2]*math.sin(a),max(.0001,radii[0]*math.cos(a)),max(.0001,radii[1]*math.cos(a)),0))
    vertices,faces,uv=ring_surface(profile,segments)
    vertices=[(x+center[0],y+center[1],z) for x,y,z in vertices]
    return vertices,faces,uv


def tube(points,radius=.002,segments=6):
    """A continuous tube following a polyline; useful for seams and hair locks."""
    def norm(v):
        length=math.sqrt(sum(x*x for x in v)) or 1
        return tuple(x/length for x in v)
    def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
    vertices=[]; faces=[]; uv=[]
    for j,p in enumerate(points):
        before=points[max(0,j-1)]; after=points[min(len(points)-1,j+1)]
        tangent=norm(tuple(after[k]-before[k] for k in range(3)))
        first=norm(cross(tangent,(0,0,1) if abs(tangent[2])<.9 else (0,1,0)))
        second=cross(tangent,first)
        r=radius[j] if isinstance(radius,(list,tuple)) else radius
        for i in range(segments+1):
            a=2*math.pi*i/segments
            vertices.append(tuple(p[k]+r*(math.cos(a)*first[k]+math.sin(a)*second[k]) for k in range(3)))
            uv.append((i/segments,j/max(1,len(points)-1)))
        if j:
            for i in range(segments):
                a=(j-1)*(segments+1)+i;b=a+segments+1
                faces.append((a,a+1,b+1,b))
    faces.extend([tuple(range(segments-1,-1,-1)),tuple((len(points)-1)*(segments+1)+i for i in range(segments))])
    return vertices,faces,uv


def bounds(vertices):
    return {"minimum":[min(p[i] for p in vertices) for i in range(3)],"maximum":[max(p[i] for p in vertices) for i in range(3)]}


def catmull_path(points,steps=5):
    result=[]
    for index in range(len(points)-1):
        a,b,c,d=[points[max(0,min(len(points)-1,i))] for i in [index-1,index,index+1,index+2]]
        for n in range(steps):
            t=n/steps;t2=t*t;t3=t2*t
            result.append(tuple(.5*(2*b[k]+(-a[k]+c[k])*t+(2*a[k]-5*b[k]+4*c[k]-d[k])*t2+(-a[k]+3*b[k]-3*c[k]+d[k])*t3) for k in range(3)))
    return result+[points[-1]]


def ribbon(points,width=.012,thickness=.0012,across=(1,0,0)):
    """Closed thin fabric strip; width and thickness are independent dimensions."""
    def unit(v):
        length=math.sqrt(sum(c*c for c in v)) or 1
        return tuple(c/length for c in v)
    def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
    front=[];back=[];uv=[];distance=0
    for index,p in enumerate(points):
        before=points[max(0,index-1)];after=points[min(len(points)-1,index+1)]
        tangent=unit(tuple(after[k]-before[k] for k in range(3)));dot=sum(across[k]*tangent[k] for k in range(3))
        side=unit(tuple(across[k]-dot*tangent[k] for k in range(3)))
        normal=unit(cross(tangent,side))
        if index:distance+=math.dist(points[index-1],p)
        for sign in [-1,1]:
            q=tuple(p[k]+side[k]*width*.5*sign for k in range(3));front.append(q)
            back.append(tuple(q[k]-normal[k]*thickness for k in range(3)));uv.append(((sign+1)*.5,distance*4))
    faces=[];n=len(front)
    for index in range(len(points)-1):
        a=index*2;faces.append((a,a+2,a+3,a+1));faces.append((a+n+1,a+n+3,a+n+2,a+n))
        faces.extend([(a,a+n,a+n+2,a+2),(a+1,a+3,a+n+3,a+n+1)])
    faces.extend([(0,1,n+1,n),(n-2,2*n-2,2*n-1,n-1)])
    return front+back,faces,uv+uv
