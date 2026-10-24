"""Pure guards for hidden review meshes and separate export source bindings."""
import ast
from copy import deepcopy
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

from tools.town_upgrade import portable_export as exporter
from tools.town_upgrade.portable_curves import render_scope
from tools.tests.test_town_portable_curves import collection


class Object(dict):
    def __init__(self,name,hidden=False,selected=False,**properties):
        super().__init__(properties);self.name=name;self.type='MESH';self.hide_render=hidden;self.selected=selected
        self.data=SimpleNamespace(polygons=[1],as_pointer=lambda:id(self))
        self.location=SimpleNamespace(x=0,y=0)
    def select_get(self):return self.selected
    def select_set(self,value):self.selected=value


class ExportSourceBindings(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.source=self.root/'export.py';self.source.write_bytes(b'before')

    def test_same_size_source_mutation_is_rejected(self):
        binding=exporter.source_bindings([self.source],self.root);exporter.verify_sources(binding,self.root)
        self.source.write_bytes(b'after!')
        with self.assertRaises(ValueError):exporter.verify_sources(binding,self.root)

    def test_native_bindings_do_not_include_export_helpers(self):
        path=Path(__file__).resolve().parents[1]/'town_upgrade/build_whole_town.py'
        tree=ast.parse(path.read_text(encoding='utf-8'))
        node=next(n for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='NATIVE_RECIPE_MODULES' for t in n.targets))
        modules=ast.literal_eval(node.value)
        self.assertIn('architecture_upgrade.py',modules)
        self.assertFalse(set(modules)&{'portable_export.py','portable_curves.py','export_verified_town.py'})
        self.assertEqual({p.name for p in exporter.EXPORT_SOURCES},{'portable_export.py','portable_curves.py','export_verified_town.py','build_whole_town.py'})


class ExportVisibilityAndStability(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.visible=Object('Cafe_Mesh',building_id='Cafe');self.review=Object('Review_Mesh',selected=True)
        scene=SimpleNamespace(objects=[self.visible,self.review],collection=collection('Scene',children=[
            collection('Production',[self.visible]),collection('04_Topographic_Review',[self.review],hidden=True)]))
        self.scene=scene;self.calls=[];self.on_export=lambda:None
        def gltf(**kwargs):
            self.calls.append((kwargs,{o.name for o in scene.objects if o.select_get()}))
            Path(kwargs['filepath']).write_bytes(b'synthetic unit payload')
            self.on_export()
        self.bpy=SimpleNamespace(context=SimpleNamespace(scene=scene,view_layer=SimpleNamespace(objects=SimpleNamespace(active=None))),
                                 ops=SimpleNamespace(export_scene=SimpleNamespace(gltf=gltf)))
        self.curves=SimpleNamespace(render_scope=render_scope,prepare=lambda bpy,scope:{'objects':[]},
                                     verify_export=lambda paths,receipt:{'status':'PASS','count':0})

    def run_export(self):
        with patch.object(exporter,'curve_module',return_value=self.curves),patch.object(exporter,'prepare_meshes',return_value={'status':'PASS'}):
            return exporter.export_chunks(self.bpy,self.root,[{'id':'Cafe','group':'urban'}])

    def test_hidden_mesh_and_stale_hidden_selection_are_excluded(self):
        records=self.run_export()
        self.assertEqual(records[0]['mesh_objects'],1);self.assertEqual(self.calls[0][1],{'Cafe_Mesh'})
        self.assertTrue(self.calls[0][0]['use_renderable']);self.assertFalse(self.review.select_get())
        receipt=json.loads((self.root/'portable_export_receipt.json').read_text())
        self.assertEqual(receipt['status'],'PASS')
        self.assertEqual([row['name'] for row in receipt['excluded_source_objects']],['Review_Mesh'])

    def test_changed_source_during_chunk_prevents_passing_receipt(self):
        source=self.root/'source.py';source.write_bytes(b'before')
        bindings=exporter.source_bindings([source],self.root)
        verify=exporter.verify_sources
        self.on_export=lambda:source.write_bytes(b'after!')
        with patch.object(exporter,'source_bindings',return_value=bindings),patch.object(exporter,'verify_sources',side_effect=lambda b:verify(b,self.root)):
            with self.assertRaises(ValueError):self.run_export()
        self.assertFalse((self.root/'portable_export_receipt.json').exists())


def mesh_fixture(triangulated=False):
    vertices=[SimpleNamespace(co=(i*.1,i%2,0.)) for i in range(9)]
    faces=[(0,1,2,3,4),(5,6,7,8)]
    source_loop_ids=[0,1,2,3,4,5,6,7,8]
    origins=[0,1]
    if triangulated:
        faces=[(0,1,2),(0,2,3),(0,3,4),(5,6,7,8)]
        source_loop_ids=[0,1,2,0,2,3,0,3,4,5,6,7,8];origins=[0,0,0,1]
    polygons=[];loops=[]
    for face,origin in zip(faces,origins):
        polygons.append(SimpleNamespace(loop_start=len(loops),loop_total=len(face),material_index=origin,use_smooth=origin==0))
        loops.extend(SimpleNamespace(vertex_index=i) for i in face)
    uv=[SimpleNamespace(name=name,data=[SimpleNamespace(uv=(i*.03+shift,i*.07)) for i in source_loop_ids]) for name,shift in [('UV0',0.),('UV1',.13)]]
    return SimpleNamespace(vertices=vertices,polygons=polygons,loops=loops,uv_layers=uv,materials=['first','second']),origins,source_loop_ids


class PortableTriangulationGuards(unittest.TestCase):
    def test_actual_promenade_lossy_normal_roundtrip_is_rejected_and_exact_targets_pass(self):
        # Exact positive-area corner from actual native probe v2; retain the
        # original guard rather than accepting the legacy INT16_2D codec loss.
        target=[(.10244844108819962,-.10247941315174103,.9894454479217529)]
        lossy=[(.10223144292831421,-.10243119299411774,.9894728660583496)]
        self.assertEqual(exporter.verify_corner_normals(target,list(target)),0.)
        with self.assertRaisesRegex(ValueError,'changed shaded corner normals'):exporter.verify_corner_normals(target,lossy)
        with self.assertRaisesRegex(ValueError,'coverage'):exporter.verify_corner_normals(target,[])
        with self.assertRaisesRegex(ValueError,'Nonfinite'):exporter.verify_corner_normals(target,[(float('nan'),0.,1.)])

    def test_actual_corner_provenance_accepts_ngon_triangles_and_unchanged_quad(self):
        source,_,_=mesh_fixture();portable,faces,loops=mesh_fixture(True)
        report=exporter.verify_triangulated_mesh(source,portable,faces,loops)
        self.assertEqual(report['source_ngons'],1)
        self.assertTrue(report['vertices_exact'] and report['corner_uvs_exact'])
        self.assertEqual((report['source_polygons'],report['portable_polygons']),(2,4))

    def test_changed_coordinate_uv_material_or_corner_mapping_is_rejected(self):
        source,_,_=mesh_fixture();base,faces,loops=mesh_fixture(True)
        for field in ('position','uv','material','origin','coverage'):
            with self.subTest(field=field):
                portable=deepcopy(base);face_map=list(faces);loop_map=list(loops)
                if field=='position':portable.vertices[0].co=(99.,0.,0.)
                elif field=='uv':portable.uv_layers[1].data[4].uv=(99.,99.)
                elif field=='material':portable.polygons[0].material_index=1
                elif field=='origin':loop_map[0]=8
                else:face_map[-1]=0
                with self.assertRaises(ValueError):exporter.verify_triangulated_mesh(source,portable,face_map,loop_map)

    def test_shared_eligible_users_share_one_copy_and_hidden_native_user_is_untouched(self):
        source,_,_=mesh_fixture();portable,_,_=mesh_fixture(True)
        source.name='Original';source.as_pointer=lambda:id(source)
        portable.name='Portable';portable.calc_tangents=lambda:None
        for loop in portable.loops:loop.tangent=(1.,0.,0.);loop.bitangent_sign=1.
        a=SimpleNamespace(name='a',data=source);b=SimpleNamespace(name='b',data=source);hidden=SimpleNamespace(name='hidden',data=source)
        bpy=SimpleNamespace(context=SimpleNamespace(view_layer=SimpleNamespace(update=lambda:None)))
        with patch.dict('sys.modules',{'bmesh':SimpleNamespace()}),patch.object(exporter,'triangulated_copy',return_value=(portable,{})) as copy:
            report=exporter.prepare_meshes(bpy,[a,b])
        self.assertEqual(copy.call_count,1);self.assertIs(a.data,b.data);self.assertIs(a.data,portable)
        self.assertIs(hidden.data,source);self.assertEqual(source.polygons[0].loop_total,5)
        self.assertEqual(report['copied_ngon_meshes'],1)

    def test_failed_tangent_calculation_cannot_publish_or_reassign_a_partial_copy(self):
        source,_,_=mesh_fixture();portable,_,_=mesh_fixture(True)
        source.as_pointer=lambda:id(source);source.name='Original';portable.name='Portable'
        def fail():raise RuntimeError('tangent calculation failed')
        portable.calc_tangents=fail
        ob=SimpleNamespace(name='owner',data=source)
        bpy=SimpleNamespace(context=SimpleNamespace(view_layer=SimpleNamespace(update=lambda:None)))
        with patch.dict('sys.modules',{'bmesh':SimpleNamespace()}),patch.object(exporter,'triangulated_copy',return_value=(portable,{})):
            with self.assertRaisesRegex(RuntimeError,'tangent calculation failed'):exporter.prepare_meshes(bpy,[ob])
        self.assertIs(ob.data,source)


if __name__=='__main__':unittest.main()
