"""Read-only receipt of the current native and botanical source topology."""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys
import bpy

p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
bpy.ops.wm.open_mainfile(filepath=str(a.native),load_ui=False)
result={'objects':len(bpy.context.scene.objects),'tree_roles':{},'samples':{},'materials':[],'collections':[]}
for tag in ('reserve_role','prototype','semantic_role'):
    result['tree_roles'][tag]=dict(Counter(str(o.get(tag)) for o in bpy.context.scene.objects if o.get(tag)))
for prefix in ('Reserve_Tree','Layered_Street','Expansion_Tree','Main_cafe','Reserve_Camp'):
    result['samples'][prefix]=[{'name':o.name,'vertices':len(o.data.vertices) if o.type=='MESH' else 0,'location':list(o.location),'props':dict(o.items()),'materials':[m.name for m in o.data.materials] if o.type=='MESH' else [],'collections':[c.name for c in o.users_collection]} for o in bpy.context.scene.objects if o.name.startswith(prefix)][:12]
result['materials']=[{'name':m.name,'images':list({n.image.name for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}) if m.use_nodes else []} for m in bpy.data.materials]
result['collections']=[c.name for c in bpy.data.collections]
bpy.ops.wm.read_homefile(use_empty=True,use_factory_startup=True)
bpy.ops.import_scene.gltf(filepath=str(a.source))
result['botanical']=[{'name':o.name,'vertices':len(o.data.vertices),'polygons':len(o.data.polygons),'dimensions':list(o.dimensions),'material_faces':dict(Counter(o.data.materials[p.material_index].name for p in o.data.polygons))} for o in bpy.context.scene.objects if o.type=='MESH']
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2,default=str)+'\n',encoding='utf-8')
print('NATIVE_INSPECTED',result['objects'],result['botanical'],flush=True)
