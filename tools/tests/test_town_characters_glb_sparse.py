"""Standard glTF sparse morph decoding, independent of either game engine."""
import math
import struct
import unittest

from tools.town_upgrade.characters.verify_textures import float_attribute


class Fixture:
    def __init__(self,accessor,views,strides=None):
        self.views=views
        self.doc={'accessors':[accessor],'bufferViews':[{'byteLength':len(v),**((strides or {}).get(i,{}))} for i,v in enumerate(views)]}
    def view(self,index):return self.views[index]


def sparse_fixture(indices=(1,3),patches=((1.,2.,3.),(-1.,-.5,0.))):
    return Fixture({'type':'VEC3','componentType':5126,'count':4,'sparse':{'count':len(indices),'indices':{'bufferView':0,'componentType':5121},'values':{'bufferView':1}}},[bytes(indices),b''.join(struct.pack('<3f',*p) for p in patches)])


class SparseMorphTests(unittest.TestCase):
    def test_missing_base_view_initializes_zero_then_applies_sparse_patch(self):
        self.assertEqual(float_attribute(sparse_fixture(),0,'VEC3'),[(0.,0.,0.),(1.,2.,3.),(0.,0.,0.),(-1.,-.5,0.)])

    def test_interleaved_base_and_sparse_override_both_survive(self):
        base=struct.pack('<f3ff3f',99.,1.,2.,3.,99.,4.,5.,6.)
        fixture=Fixture({'type':'VEC3','componentType':5126,'count':2,'bufferView':0,'byteOffset':4,'sparse':{'count':1,'indices':{'bufferView':1,'componentType':5123},'values':{'bufferView':2}}},[base,struct.pack('<H',1),struct.pack('<3f',7.,8.,9.)],{0:{'byteStride':16}})
        self.assertEqual(float_attribute(fixture,0,'VEC3'),[(1.,2.,3.),(7.,8.,9.)])

    def test_duplicate_unsorted_or_out_of_range_indices_fail(self):
        for ids in [(1,1),(3,1),(1,4)]:
            with self.subTest(indices=ids),self.assertRaisesRegex(ValueError,'sorted, unique and in range'):
                float_attribute(sparse_fixture(ids),0,'VEC3')

    def test_sparse_values_and_index_spans_cannot_escape_views(self):
        for view in (0,1):
            fixture=sparse_fixture();fixture.views[view]=fixture.views[view][:-1]
            with self.subTest(view=view),self.assertRaisesRegex(ValueError,'span exceeds'):
                float_attribute(fixture,0,'VEC3')

    def test_nonfinite_base_or_patch_is_rejected_even_when_overwritten(self):
        fixture=sparse_fixture(patches=((math.nan,0.,0.),(0.,0.,0.)))
        with self.assertRaisesRegex(ValueError,'Nonfinite sparse'):float_attribute(fixture,0,'VEC3')
        fixture=Fixture({'type':'VEC3','componentType':5126,'count':1,'bufferView':0,'sparse':{'count':1,'indices':{'bufferView':1,'componentType':5121},'values':{'bufferView':2}}},[struct.pack('<3f',math.inf,0.,0.),b'\0',struct.pack('<3f',0.,0.,0.)])
        with self.assertRaisesRegex(ValueError,'Nonfinite float base'):float_attribute(fixture,0,'VEC3')

    def test_invalid_sparse_count_alignment_or_stride_fails(self):
        fixture=sparse_fixture();fixture.doc['accessors'][0]['sparse']['count']=5
        with self.assertRaisesRegex(ValueError,'sparse count'):float_attribute(fixture,0,'VEC3')
        fixture=sparse_fixture();fixture.doc['accessors'][0]['sparse']['values']['byteOffset']=1
        with self.assertRaisesRegex(ValueError,'span exceeds'):float_attribute(fixture,0,'VEC3')
        fixture=sparse_fixture();fixture.doc['bufferViews'][1]['byteStride']=12
        with self.assertRaisesRegex(ValueError,'span exceeds'):float_attribute(fixture,0,'VEC3')


if __name__=='__main__':unittest.main()
