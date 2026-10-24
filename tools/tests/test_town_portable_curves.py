"""Prevent native lettering from silently disappearing at glTF export."""
from copy import deepcopy
import json
from pathlib import Path
import struct
import tempfile
import unittest
from types import SimpleNamespace
from tools.town_upgrade.portable_curves import verify_export,render_scope,prepare


class PortableCurveBindings(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name)/'sign.glb'
        self.receipt={'objects':[{'portable_object_name':'Cafe_Sign','source_type':'FONT','text':'CAFE','building_id':'Cafe'}]}
        self.doc={'asset':{'version':'2.0'},'nodes':[{'name':'Cafe_Sign','mesh':0,'extras':{'portable_source_type':'FONT','portable_text':'CAFE','building_id':'Cafe'}}],
                  'meshes':[{'primitives':[{'attributes':{'POSITION':0,'TEXCOORD_0':1}}]}],'accessors':[{'count':12},{'count':12}]}

    def write(self,doc):
        data=json.dumps(doc).encode();data+=b' '*((-len(data))%4)
        self.path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(data))+struct.pack('<II',len(data),0x4e4f534a)+data)

    def check_rejected(self,doc):
        self.write(doc)
        with self.assertRaises(ValueError):verify_export([self.path],self.receipt)

    def test_prepared_mesh_node_is_bound(self):
        self.write(self.doc);self.assertEqual(verify_export([self.path],self.receipt)['count'],1)

    def test_missing_font_regression(self):
        doc=deepcopy(self.doc);doc['nodes']=[];self.check_rejected(doc)

    def test_empty_parent_cannot_masquerade_as_lettering(self):
        doc=deepcopy(self.doc);del doc['nodes'][0]['mesh'];self.check_rejected(doc)

    def test_empty_vertex_payload_rejected(self):
        doc=deepcopy(self.doc);doc['accessors'][0]['count']=0;self.check_rejected(doc)

    def test_missing_uv0_rejected(self):
        doc=deepcopy(self.doc);del doc['meshes'][0]['primitives'][0]['attributes']['TEXCOORD_0'];self.check_rejected(doc)

    def test_changed_text_or_owner_rejected(self):
        for key,value in [('portable_text','WRONG'),('building_id','Other')]:
            doc=deepcopy(self.doc);doc['nodes'][0]['extras'][key]=value;self.check_rejected(doc)


def collection(name,objects=(),children=(),hidden=False):
    return SimpleNamespace(name=name,objects=list(objects),children=list(children),hide_render=hidden)


def visual(name,kind='MESH',hidden=False):
    return SimpleNamespace(name=name,type=kind,hide_render=hidden)


class RenderVisibility(unittest.TestCase):
    def test_hidden_parent_excludes_descendants(self):
        ob=visual('Review_Mesh')
        leaf=collection('Child',[ob]);root=collection('Scene',children=[collection('Review',children=[leaf],hidden=True)])
        row=render_scope(SimpleNamespace(collection=root))[ob.name]
        self.assertFalse(row['eligible']);self.assertIn('all scene collection paths',row['reason'])

    def test_visible_collection_path_wins(self):
        ob=visual('Shared_Sign','FONT');shared=collection('Shared',[ob])
        root=collection('Scene',children=[collection('Hidden',children=[shared],hidden=True),collection('Visible',children=[shared])])
        row=render_scope(SimpleNamespace(collection=root))[ob.name]
        self.assertTrue(row['eligible']);self.assertEqual(sum(p['render_enabled'] for p in row['collection_paths']),1)

    def test_object_flag_overrides_visible_paths(self):
        ob=visual('Hidden_Object','FONT',True);root=collection('Scene',[ob])
        row=render_scope(SimpleNamespace(collection=root))[ob.name]
        self.assertFalse(row['eligible']);self.assertEqual(row['reason'],'object.hide_render')

    def test_other_scene_visible_collection_is_not_a_visible_path(self):
        ob=visual('Shared_Elsewhere');elsewhere=collection('OtherScene',[ob])
        root=collection('Scene',children=[collection('Hidden',[ob],hidden=True)])
        self.assertFalse(render_scope(SimpleNamespace(collection=root))[ob.name]['eligible'])
        self.assertFalse(elsewhere.hide_render)

    def test_hidden_overlay_curves_are_never_evaluated(self):
        overlays=[visual('Contour_'+str(i),'CURVE') for i in range(13)]+[visual('Spot_Level_'+str(i),'FONT') for i in range(6)]
        root=collection('Scene',children=[collection('04_Topographic_Review',overlays,hidden=True)])
        context=SimpleNamespace(scene=SimpleNamespace(collection=root,objects=overlays),
                                view_layer=SimpleNamespace(update=lambda:None),evaluated_depsgraph_get=lambda:None)
        # No mesh API exists on this fake: evaluating a hidden curve would fail.
        result=prepare(SimpleNamespace(context=context))
        self.assertEqual(result['objects'],[]);self.assertEqual(len(result['excluded_source_objects']),19)


if __name__=='__main__':unittest.main()
