"""Hash-bound real Blender evidence for every building and authored floor.

Exterior views isolate one native building. Floor views show the actual floor
collection from overhead, preserving source partitions/furniture. These are
explicit architectural review cuts, not screenshots of playable behavior.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def local(row,point):
    a=math.radians(row['yaw_degrees']);x,y,z=point;cx,cy=row['center_m'][:2]
    return Vector((cx+x*math.cos(a)-y*math.sin(a),cy+x*math.sin(a)+y*math.cos(a),row['pad_level_m']+z))


def _surface_vertex_indices(mesh):
    """Vertices which can contribute a rendered face; loose vertices do not."""
    return sorted({index for polygon in mesh.polygons if polygon.area > 1e-12
                   for index in polygon.vertices})


def frame_native_objects(camera,objects,row,kind,depsgraph):
    """Fit actual evaluated surfaces, including chimneys and open doors.

    Exact source-component removals can leave empty material batches or loose
    vertices. Their object bounds can still extend to world zero, despite
    contributing no pixels. Keep the original objects linked, but derive the
    camera fit only from vertices used by nondegenerate evaluated faces.
    No distance/footprint heuristic censors genuine surfaces or shared walls.
    """
    points=[];empty=[];surface_objects=0;loose_vertices=0
    for original in objects:
        ob=original.evaluated_get(depsgraph)
        temporary=ob.type!='MESH'
        mesh=ob.to_mesh(preserve_all_data_layers=False,depsgraph=depsgraph) if temporary else ob.data
        try:
            indices=_surface_vertex_indices(mesh) if mesh is not None else []
            loose_vertices+=len(mesh.vertices)-len(indices) if mesh is not None else 0
            if not indices:
                empty.append(original.name)
                continue
            surface_objects+=1
            points.extend(ob.matrix_world @ mesh.vertices[index].co for index in indices)
        finally:
            if temporary:ob.to_mesh_clear()
    if any(not math.isfinite(value) for point in points for value in point):raise ValueError('Nonfinite evaluated surface: '+row['id'])
    if not points:raise ValueError('No rendered surfaces for '+row['id'])
    low=Vector(tuple(min(point[i] for point in points) for i in range(3)))
    high=Vector(tuple(max(point[i] for point in points) for i in range(3)))
    target=(low+high)*.5
    if kind=='floor':
        camera.rotation_euler=(0,0,math.radians(row['yaw_degrees']))
        direction=Vector((0,0,1))
    else:
        a=math.radians(row['yaw_degrees'])
        direction=Vector((.52*math.cos(a)+.86*math.sin(a),.52*math.sin(a)-.86*math.cos(a),.68)).normalized()
        camera.rotation_euler=(-direction).to_track_quat('-Z','Y').to_euler()
    rotation=camera.rotation_euler.to_quaternion()
    inverse=rotation.inverted()
    projected=[inverse @ (point-target) for point in points]
    left=min(point.x for point in projected);right=max(point.x for point in projected)
    bottom=min(point.y for point in projected);top=max(point.y for point in projected)
    target+=rotation @ Vector(((left+right)*.5,(bottom+top)*.5,0))
    camera.data.ortho_scale=max(right-left,top-bottom,.5)*1.12
    camera.data.clip_end=max(1000,(high-low).length*10)
    camera.location=target+direction*max(20,(high-low).length*3)
    proof={'policy':'All nondegenerate evaluated polygon surfaces; no distance or footprint outlier filtering.',
           'linked_objects':len(objects),'surface_objects':surface_objects,
           'empty_surface_objects_excluded_from_framing_only':empty,
           'unreferenced_or_degenerate_only_vertices_excluded':loose_vertices,
           'surface_vertex_count':len(points),'world_surface_bounds_m':[list(low),list(high)],
           'projected_surface_span_m':[right-left,top-bottom],'margin_factor':1.12}
    return target,proof


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--native',type=Path,required=True);p.add_argument('--buildings',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--size',type=int,default=640);p.add_argument('--samples',type=int,default=12);p.add_argument('--ids',default='');p.add_argument('--limit',type=int,default=0);p.add_argument('--resume',action='store_true')
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:]);args.output.mkdir(parents=True,exist_ok=True)
    rows=json.loads(args.buildings.read_text(encoding='utf-8'))['buildings'];selected=set(args.ids.split(',')) if args.ids else None
    if selected:rows=[row for row in rows if row['id'] in selected]
    if args.limit:rows=rows[:args.limit]
    native_hash=sha(args.native);bpy.ops.wm.open_mainfile(filepath=str(args.native),load_ui=False)
    native_scene=bpy.context.scene
    # Use original linked geometry in an isolated, disposable Scene. Changing
    # visibility across the full forest would repeatedly invalidate 50k objects.
    # The inactive native Scene and every native mesh remain unmodified on disk.
    scene=bpy.data.scenes.new('WholeTown_Architectural_Review')
    scene.world=native_scene.world
    for ob in native_scene.objects:
        if ob.type=='LIGHT':
            ob.hide_render=False
            scene.collection.objects.link(ob)
    bpy.context.window.scene=scene
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=args.samples;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=6;scene.render.resolution_x=args.size;scene.render.resolution_y=args.size;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
    scene.view_settings.view_transform='AgX'
    camera_data=bpy.data.cameras.new('WholeTown_Catalog_Camera');camera=bpy.data.objects.new(camera_data.name,camera_data);scene.collection.objects.link(camera);camera_data.type='ORTHO';scene.camera=camera
    receipts=[];active_collection=None;receipt_path=args.output/'render_receipts.json'
    binding={'native_sha256':native_hash,'buildings_sha256':sha(args.buildings),'render_tool_sha256':sha(__file__),
             'render_config':{'size':args.size,'samples':args.samples,'device':'CPU','engine':'CYCLES','blender':bpy.app.version_string}}
    if receipt_path.exists():
        if not args.resume:raise FileExistsError('Existing review receipts require --resume or a fresh output directory')
        previous=json.loads(receipt_path.read_text(encoding='utf-8'))
        if any(previous.get(key)!=value for key,value in binding.items()):raise ValueError('Cannot resume changed native/buildings/render source or configuration')
        receipts=previous['views']
        for view in receipts:
            path=args.output/view['path']
            if not path.is_file() or sha(path)!=view['sha256']:raise ValueError('Changed completed render '+str(path))
    completed={(view['building_id'],view['kind'],view['level']) for view in receipts}
    if len(completed)!=len(receipts):raise ValueError('Duplicate completed render identities')
    def save(complete=False):
        temporary=receipt_path.with_suffix('.json.tmp')
        temporary.write_text(json.dumps({'schema':'living_town.whole_town_visual_catalog.v1',**binding,'views':receipts,'complete':complete,
            'scope':'Isolated native exteriors include exact shared walls. Floor plates show exact per-floor partitions and furnishings; exterior/shared shell collections are omitted from those plates. Floor enclosure is checked separately by native rays, exteriors and actual gameplay cutaways. These are architectural review images, not gameplay screenshots.'},indent=2)+'\n',encoding='utf-8')
        temporary.replace(receipt_path)
    for ordinal,row in enumerate(rows):
        root=bpy.data.collections.get(row['collections']['root'])
        if root is None:raise RuntimeError('Missing building collection '+row['id'])
        w,d=row['footprint_m'];baseff=row['interior']['levels'][0]['finished_floor_local_z_m']
        # A real native exterior image for this building, distinct from its
        # in-situ street/landscape screenshots captured later in the game.
        exterior_objects={ob.name:ob for ob in root.all_objects}
        for name in row.get('shared_shell_object_names',[]):
            ob=bpy.data.objects.get(name)
            if ob is None:raise RuntimeError('Missing shared native shell '+row['id']+'/'+name)
            exterior_objects[name]=ob
        views=[('exterior',None,list(exterior_objects.values()),local(row,(w*.95,-d*1.6,max(w,d)*1.05+row['floor_count'])),local(row,(0,0,baseff+row['floor_count']*1.3)),max(w,d,row['floor_count']*3.1)*1.55)]
        for floor in row['interior']['levels']:
            level=floor['level'];col=bpy.data.collections.get(row['id']+f'_Interior_L{level:02d}')
            if col is None:raise RuntimeError('Missing floor collection '+row['id']+'/'+str(level))
            ff=floor['finished_floor_local_z_m'];target=local(row,(0,0,ff));position=target+Vector((0,0,max(w,d)*2+10))
            views.append(('floor',level,list(col.all_objects),position,target,max(w,d)*1.18))
        for kind,level,objects,position,target,span in views:
            if (row['id'],kind,level) in completed:continue
            if active_collection is not None:bpy.data.collections.remove(active_collection)
            last=[ob for ob in objects if ob.type in ('MESH','FONT','CURVE')]
            active_collection=bpy.data.collections.new('Current_Native_Building_View')
            scene.collection.children.link(active_collection)
            for ob in last:
                ob.hide_render=False
                active_collection.objects.link(ob)
            linked=set(scene.objects)
            for ob in last:
                dependencies=([ob.parent] if ob.parent else [])+[getattr(constraint,'target',None) for constraint in ob.constraints]
                if any(target is not None and target not in linked for target in dependencies):raise ValueError('Native object has an unlinked transform dependency: '+ob.name)
            bpy.context.view_layer.update()
            target,framing=frame_native_objects(camera,last,row,kind,bpy.context.evaluated_depsgraph_get());position=camera.location.copy();span=camera_data.ortho_scale
            name=row['id']+('_exterior' if level is None else f'_L{level:02d}')+'.png';path=args.output/name
            scene.render.filepath=str(path);print('BUILDING_CATALOG '+str(ordinal+1)+'/'+str(len(rows))+' '+name,flush=True);bpy.ops.render.render(write_still=True)
            receipts.append({'building_id':row['id'],'kind':kind,'level':level,'path':name,'sha256':sha(path),'rendered_objects':len(last),
                'camera_world_m':list(position),'target_world_m':list(target),'ortho_span_m':span,'native_sha256':native_hash,'visual_acceptance':'AWAITING_REVIEW',
                'framing':framing,'geometry':'Original native objects linked into a disposable isolated review Scene; all nondegenerate evaluated surfaces framed, including exact shared walls. Empty/loose geometry remains linked but does not affect the camera.'})
            completed.add((row['id'],kind,level));save()
    expected={(row['id'],kind,level) for row in json.loads(args.buildings.read_text(encoding='utf-8'))['buildings'] for kind,level in [('exterior',None)]+[('floor',floor['level']) for floor in row['interior']['levels']]}
    save(completed==expected)
    print('BUILDING_CATALOG_COMPLETE '+str(len(receipts)),flush=True)


if __name__=='__main__':main()
