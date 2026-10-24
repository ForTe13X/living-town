"""Real whole-scene CPU renders for street, terrain, park and forest review."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from collections import defaultdict

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def local(row,p):
    x,y,z=p;a=math.radians(row['yaw_degrees']);cx,cy=row['center_m'][:2]
    return cx+x*math.cos(a)-y*math.sin(a),cy+x*math.sin(a)+y*math.cos(a),row['pad_level_m']+z


class Visibility:
    """Immutable native mesh queries; no object hiding or dependency updates."""
    def __init__(self,rows):
        self.rows,self.grid,self.bounds,self.cache=rows,defaultdict(list),{},{}
        self.cell=16.;self.ground=[];self.roofs=defaultdict(float)
        for ob in bpy.context.scene.objects:
            if ob.type!='MESH' or not ob.data.polygons:continue
            terrain=ob.name=='Atlantic_Terrain_Grass' or ob.get('reserve_role')=='terrain'
            building=ob.get('building_id');tree=ob.get('vegetation_role')=='tree'
            if not (terrain or building or tree):continue
            points=[ob.matrix_world@Vector(p) for p in ob.bound_box]
            lo=Vector(tuple(min(p[k] for p in points) for k in range(3)));hi=Vector(tuple(max(p[k] for p in points) for k in range(3)))
            self.bounds[ob.name]=(lo,hi)
            if building:self.roofs[building]=max(self.roofs[building],hi.z)
            if terrain:self.ground.append(ob);continue
            for x in range(math.floor(lo.x/self.cell),math.floor(hi.x/self.cell)+1):
                for y in range(math.floor(lo.y/self.cell),math.floor(hi.y/self.cell)+1):self.grid[x,y].append(ob)

    def near(self,lo,hi):
        result={}
        for x in range(math.floor(lo[0]/self.cell),math.floor(hi[0]/self.cell)+1):
            for y in range(math.floor(lo[1]/self.cell),math.floor(hi[1]/self.cell)+1):
                for ob in self.grid.get((x,y),[]):result[ob.name]=ob
        return result.values()

    def mesh(self,ob):
        key=ob.data.as_pointer()
        if key not in self.cache:
            self.cache[key]=BVHTree.FromPolygons([v.co.copy() for v in ob.data.vertices],[tuple(p.vertices) for p in ob.data.polygons],all_triangles=False)
        return self.cache[key]

    def cast(self,ob,start,end):
        inv=ob.matrix_world.inverted();a=inv@start;delta=inv@end-a;length=delta.length
        if length<1e-8:return None
        delta.normalize();point,normal,index,distance=self.mesh(ob).ray_cast(a,delta,length)
        return ob.matrix_world@point if point is not None else None

    def ground_height(self,x,y):
        start,end=Vector((x,y,1000)),Vector((x,y,-1000));hits=[self.cast(ob,start,end) for ob in self.ground]
        return max((p.z for p in hits if p is not None),default=float('nan'))

    def camera_clear(self,position):
        p=Vector(position);z=self.ground_height(p.x,p.y)
        if not math.isfinite(z) or p.z<z+2.:return False,'below_or_too_close_to_actual_terrain'
        for row in self.rows.values():
            a=math.radians(row['yaw_degrees']);dx,dy=p.x-row['center_m'][0],p.y-row['center_m'][1]
            x,y=dx*math.cos(a)+dy*math.sin(a),-dx*math.sin(a)+dy*math.cos(a);w,d=row['footprint_m']
            if abs(x)<w/2+.4 and abs(y)<d/2+.4 and row['pad_level_m']-.3<p.z<self.roofs.get(row['id'],row['pad_level_m']+12)+.5:
                return False,'inside_actual_building_roof_envelope:'+row['id']
        for ob in self.near((p.x-1,p.y-1),(p.x+1,p.y+1)):
            lo,hi=self.bounds[ob.name]
            if any(p[k]<lo[k]-.8 or p[k]>hi[k]+.8 for k in range(3)):continue
            inv=ob.matrix_world.inverted();minimum=min(ob.matrix_world.to_scale())
            point,normal,index,distance=self.mesh(ob).find_nearest(inv@p,.8/max(.01,minimum))
            if point is not None and (ob.matrix_world@point-p).length<.8:return False,'camera_near_actual_mesh:'+ob.name
        return True,None

    def first_occluder(self,start,end,target_id):
        a,b=Vector(start),Vector(end);nearest=None
        lo=[min(a[k],b[k]) for k in range(3)];hi=[max(a[k],b[k]) for k in range(3)]
        for ob in self.near(lo,hi):
            if ob.get('building_id')==target_id:continue
            lower,upper=self.bounds[ob.name]
            if any(hi[k]<lower[k] or lo[k]>upper[k] for k in range(3)):continue
            hit=self.cast(ob,a,b)
            if hit is not None and (hit-a).length<(b-a).length-.12:
                distance=(hit-a).length
                if nearest is None or distance<nearest['distance_m']:
                    nearest={'object':ob.name,'distance_m':distance,'world_m':list(hit),'kind':'tree' if ob.get('vegetation_role')=='tree' else 'neighbor_building'}
        return nearest


def select_facade(row,label,visibility):
    w,d=row['footprint_m'];levels=row['floor_count'];front=-d/2-.24
    heights=(1.1,2.2,4.0) if levels>1 else (1.0,2.1,3.0)
    samples=[{'kind':'facade','point':local(row,(x,front,z))} for x in (-w*.4,0,w*.4) for z in heights]
    samples += [{'kind':'entry','point':local(row,(row.get('door_local_x',0),front-.10,z))} for z in (1.0,1.9)]
    candidates=[]
    # Left-biased candidates avoid the observed right foreground cafe/bath
    # trees, but every candidate must prove its actual camera/sight clearance.
    lateral=(-.85,-.45,0,.45,.85)
    for distance in (6.,9.,12.,16.):
        for factor in lateral:
            for height in (2.2,3.4,5.,7.,10.,14.,18.):
                position=local(row,(factor*w,-d/2-distance,height))
                clear,reason=visibility.camera_clear(position)
                if not clear:continue
                rays=[]
                for sample in samples:
                    hit=visibility.first_occluder(position,sample['point'],row['id'])
                    rays.append({'kind':sample['kind'],'target_world_m':list(sample['point']),'clear':hit is None,'occluder':hit})
                total=sum(r['clear'] for r in rays);entry=sum(r['clear'] for r in rays if r['kind']=='entry')
                # Prefer complete facade/entry visibility, then restrained
                # height and moderate angle rather than an extreme overhead.
                score=entry*100+total*10-height*.18-abs(factor)*.9-distance*.015
                candidates.append({'position':position,'rays':rays,'clear_samples':total,'entry_clear':entry,
                                   'score':score,'height_above_pad_m':height,'lateral_factor':factor,'front_distance_m':distance})
    if not candidates:raise RuntimeError('No actual clear camera candidate for '+label)
    candidates.sort(key=lambda r:r['score'],reverse=True);best=candidates[0]
    target=local(row,(0,front,2.8 if levels>1 else 1.9))
    distance=(Vector(best['position'])-Vector(target)).length
    # 36mm sensor: fit the full frontage with margin at the selected distance.
    lens=max(20.,min(38.,36*distance/(w*1.35)))
    proof={'selection':'Bounded native camera/roof/terrain clearance plus actual facade/entry segment rays',
           'target_building_id':row['id'],'candidate_count':len(candidates),'selected':best,
           'top_candidates':[{k:v for k,v in c.items() if k!='rays'} for c in candidates[:6]],
           'status':'CLEAR_SAMPLED_FACADE_AND_ENTRY' if best['clear_samples']==len(samples) else 'BEST_AVAILABLE_REQUIRES_VISUAL_REVIEW',
           'lens_mm':lens,'tree_ray_policy':'Conservative full source leaf triangles; alpha cutouts may overestimate occlusion. No objects hidden or moved.'}
    return best['position'],target,None,proof


def select_panorama(visibility,aspect):
    position=Vector((-120,-250,240));target=Vector((-280,0,28));forward=(target-position).normalized()
    right=forward.cross(Vector((0,0,1))).normalized();up=right.cross(forward).normalized()
    span=350.;attempts=[]
    for attempt in range(8):
        hits=[]
        for horizontal,vertical in ((-1,-1),(-1,1),(1,-1),(1,1),(0,-1),(0,1),(-1,0),(1,0)):
            start=position+right*(horizontal*span/2)+up*(vertical*span/aspect/2)
            points=[visibility.cast(ob,start,start+forward*2000) for ob in visibility.ground]
            actual=[p for p in points if p is not None]
            hits.append(list(min(actual,key=lambda p:(p-start).length)) if actual else None)
        attempts.append({'span_m':span,'actual_terrain_frame_hits':hits})
        if all(h is not None for h in hits):
            return tuple(position),tuple(target),span,{'selection':'Reframed inside actual terrain; all8 frame-edge rays hit native ground','attempts':attempts,'status':'FRAME_INSIDE_ACTUAL_TERRAIN'}
        span*=.9
    raise RuntimeError('Reserve panorama cannot frame actual terrain without an edge/void')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--native',type=Path,required=True);parser.add_argument('--buildings',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--size',type=int,default=1500);parser.add_argument('--samples',type=int,default=16);parser.add_argument('--views',default='')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);args.output.mkdir(parents=True,exist_ok=True)
    rows={r['id']:r for r in json.loads(args.buildings.read_text(encoding='utf-8'))['buildings']};native_hash=sha(args.native)
    bpy.ops.wm.open_mainfile(filepath=str(args.native),load_ui=False)
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=args.samples;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=6
    scene.render.resolution_x=args.size;scene.render.resolution_y=round(args.size*2/3);scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False;scene.view_settings.view_transform='AgX'
    views={'town_overview':((165,-185,170),(-48,35,6),285,{'selection':'Existing reviewed context camera retained'}),
           'reserve_edge':((-195,-190,75),(-210,-85,28),180,{'selection':'Existing reviewed context camera retained'}),
           'reserve_panorama':None,
           'park_pond':((54,-71,26),(23,-42,.7),52,{'selection':'Existing reviewed context camera retained'}),
           'cafe_front_garden':None,'home_garden':None,'bathhouse_trail':None}
    selected=set(args.views.split(',')) if args.views else set(views);receipts=[]
    if selected-set(views):raise ValueError('Unknown context views: '+str(selected-set(views)))
    dynamic={'reserve_panorama','cafe_front_garden','home_garden','bathhouse_trail'}
    if selected & dynamic:
        print('CONTEXT_CAMERA_NATIVE_OBSTACLE_INDEX',flush=True);visibility=Visibility(rows)
        if 'reserve_panorama' in selected:views['reserve_panorama']=select_panorama(visibility,scene.render.resolution_x/scene.render.resolution_y)
        for ident,label in (('Main_cafe','cafe_front_garden'),('Main_home','home_garden'),('Reserve_Bathhouse','bathhouse_trail')):
            if label not in selected:continue
            print('CONTEXT_CAMERA_SELECT '+label,flush=True);views[label]=select_facade(rows[ident],label,visibility)
            proof=views[label][3];print('CONTEXT_CAMERA_SELECTED '+label+' '+json.dumps({'status':proof['status'],'position':views[label][0],'clear_samples':proof['selected']['clear_samples'],'entry_clear':proof['selected']['entry_clear']}),flush=True)
    for name,configuration in views.items():
        if name not in selected:continue
        position,target,span,proof=configuration
        data=bpy.data.cameras.new('ContextReview_'+name);camera=bpy.data.objects.new(data.name,data);scene.collection.objects.link(camera)
        camera.location=position;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();data.clip_end=3000
        if span is None:data.type='PERSP';data.lens=proof.get('lens_mm',27)
        else:data.type='ORTHO';data.ortho_scale=span
        scene.camera=camera;path=args.output/(name+'.png');scene.render.filepath=str(path)
        print('WHOLE_TOWN_CONTEXT_RENDER '+name,flush=True);bpy.ops.render.render(write_still=True)
        receipts.append({'view':name,'path':path.name,'sha256':sha(path),'native_sha256':native_hash,'camera_world_m':list(position),'target_world_m':list(target),'camera_selection_proof':proof,'visual_acceptance':'AWAITING_REVIEW'})
        temporary=args.output/'render_receipts.json.tmp'
        temporary.write_text(json.dumps({'schema':'living_town.context_views.v1','native_sha256':native_hash,'buildings_sha256':sha(args.buildings),'render_tool_sha256':sha(__file__),'views':receipts,'site_objects_hidden_or_moved':[],'native_geometry_mutations':[],'scene_saved':False},indent=2)+'\n',encoding='utf-8')
        temporary.replace(args.output/'render_receipts.json')
    print('WHOLE_TOWN_CONTEXT_COMPLETE '+str(len(receipts)),flush=True)


if __name__=='__main__':main()
