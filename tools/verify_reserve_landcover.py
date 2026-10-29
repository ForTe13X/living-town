"""Verify the portable fixed-Pond landcover fixture; no engine or third-party dependency."""
from pathlib import Path
import argparse,hashlib,json
SIDE=505;COUNT=SIDE*SIDE;NAMES=['Meadow','WoodlandLitter','SteepRock','PondSoil']
SHA='d83c74821b884ad75a80a9efa278374fcfa3674f8a8cf40c27db3bd59ba69ad9'
HEIGHT_SHA='2b5839619c03277cc4e73bb97e0d250661e9aec1efe5efe61850e5c16170b5cb'
KEYS={'schema','raw','width','height','channels','encoding','row0','grid','per_vertex_sum','sha256','byte_count','height_source_sha256','scope'}
def need(ok,message):
 if not ok:raise ValueError(message)
def validate(data,meta):
 need(set(meta)==KEYS and meta['schema']=='LivingTown.ReserveLandcoverSource.v1','Closed versioned fixture schema')
 need(meta['raw']=='Landcover_Actual229_505_RGBA8.bin'and meta['encoding']=='uint8_interleaved_RGBA_no_header'and meta['width']==meta['height']==SIDE and meta['channels']==NAMES,'Exact physical sample/semantic channel layout')
 need(meta['row0']=='minimum_UE_Y_maximum_canonical_Y'and meta['per_vertex_sum']==255 and meta['height_source_sha256']==HEIGHT_SHA,'Source coordinate/partition/height binding')
 need(meta['grid']=={'UE_X_cm':'-60000+100*column','UE_Y_cm':'-22400+100*row','canonical_metres':'[UE_X/100,-UE_Y/100,UE_Z/100]','height_encoding':'uint16_le','UE_Z_cm':'4000+(height_u16-32768)*25/128'},'Exact source axes/spacing/elevation formula')
 need(len(data)==meta['byte_count']==COUNT*4,'Exact raw byte count')
 need(all(sum(v)==255 for v in zip(data[0::4],data[1::4],data[2::4],data[3::4])),'Every source vertex partition sums255')
 need(hashlib.sha256(data).hexdigest()==meta['sha256']==SHA,'Exact source weights SHA256')
 return {'samples':COUNT,'bytes':len(data),'sha256':SHA,'channels':NAMES,'all_vertex_sums255':True}
def reorder(data,indices,visibility,native_layers=5,visibility_index=2):
 need(len(data)==COUNT*4 and len(visibility)==COUNT,'Source/Visibility plane shape')
 need(native_layers==5 and len(indices)==4 and len(set(indices))==4 and 0<=visibility_index<5 and all(type(i)is int and 0<=i<5 and i!=visibility_index for i in indices),'Only4 roles+recognized Visibility; actual indices required')
 result=bytearray(COUNT*5);result[visibility_index::5]=visibility
 for role,index in enumerate(indices):result[index::5]=data[role::4]
 return result
def self_test(data,meta):
 def refuses(call):
  try:call()
  except ValueError:return
  raise AssertionError('Negative source control unexpectedly accepted')
 refuses(lambda:validate(data[:-1],meta));bad=bytearray(data);bad[0]^=1;refuses(lambda:validate(bad,meta))
 bad=bytearray(data);first=next(i for i,v in enumerate(bad[:4])if v);other=(first+1)%4;bad[first]-=1;bad[other]+=1;refuses(lambda:validate(bad,meta)) # partition preserved; SHA still refuses changed meaning
 refuses(lambda:validate(data,{**meta,'foreign_key':0}))
 visibility=bytes(i%251 for i in range(COUNT));permutation=[4,0,3,1];packed=reorder(data,permutation,visibility)
 need(packed[2::5]==visibility,'Visibility source bytes preserved exactly')
 for role,index in enumerate(permutation):need(packed[index::5]==data[role::4],'Cross-source nonidentity role/index mapping')
 refuses(lambda:reorder(data,[0,0,3,4],visibility));refuses(lambda:reorder(data,[0,1,2,4],visibility));refuses(lambda:reorder(data,permutation,visibility,6))
 return {'negative_controls':7,'nonidentity_5slot_rows_checked':COUNT,'visibility_pattern':'i%251','does_not_authorize_actual_visibility_allocations':True}
def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture-dir',type=Path,default=Path(__file__).resolve().parents[1]/'unreal/Content/ReserveLandcoverSource_v001');p.add_argument('--self-test',action='store_true');a=p.parse_args();meta=json.loads((a.fixture_dir/'source.json').read_text(encoding='utf-8-sig'));data=(a.fixture_dir/'Landcover_Actual229_505_RGBA8.bin').read_bytes();result=validate(data,meta)
 if a.self_test:result['controls']=self_test(data,meta)
 print(json.dumps({'status':'PASS_PORTABLE_FIXED_POND_SOURCE_WEIGHTS_NOT_NATIVE_PAINT_OR_ART','fixture':result}))
if __name__=='__main__':main()
