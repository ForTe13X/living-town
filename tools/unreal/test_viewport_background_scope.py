import unittest
from types import SimpleNamespace
from viewport_background_scope import begin_background_scope, submit_background_restore, verify_background_restore

class BackgroundScopeTests(unittest.TestCase):
 def fixture(self,throttle=True):
  frame=[0];properties={'bThrottleCPUWhenNotForeground':throttle};view={'world_path':'owned','location_cm':[1,2,3],'rotation_pitch_yaw_roll':[4,5,6],'fov':60,'lit':True,'game_view':False,'realtime':not throttle,'client_identity_diagnostic_only':'client','viewport_identity_diagnostic_only':'viewport'};writes=[]
  def set_property(key,value):properties[key]=value;writes.append((key,value))
  cdo=SimpleNamespace(get_editor_property=lambda k:properties[k],set_editor_property=set_property);u=SimpleNamespace(find_object=lambda outer,path:cdo,SystemLibrary=SimpleNamespace(get_frame_count=lambda:frame[0]));read=lambda:dict(view);verified=[];guard=lambda:verified.append('SOURCE_BYTES');return u,read,frame,view,properties,writes,verified,guard
 def test_background_false_to_realtime_then_later_original_false(self):
  u,read,f,v,p,w,seen,guard=self.fixture();token=begin_background_scope(u,read);self.assertFalse(p['bThrottleCPUWhenNotForeground']);v['realtime']=True;submit_background_restore(u,token);f[0]=1;self.assertEqual(verify_background_restore(u,token,read,guard)['status'],'PENDING_LATER_NATIVE_BACKGROUND_TICK');self.assertFalse(seen);f[0]=2;v['realtime']=False;result=verify_background_restore(u,token,read,guard);self.assertEqual(result['status'],'RESTORED_EXACT_AFTER_NATIVE_BACKGROUND_TICK');self.assertEqual(seen,['SOURCE_BYTES']);self.assertEqual(w,[('bThrottleCPUWhenNotForeground',False),('bThrottleCPUWhenNotForeground',True)])
 def test_original_unthrottled_realtime_state(self):
  u,read,f,v,p,w,seen,guard=self.fixture(False);token=begin_background_scope(u,read);submit_background_restore(u,token);f[0]=2;self.assertEqual(verify_background_restore(u,token,read,guard)['status'],'RESTORED_EXACT_AFTER_NATIVE_BACKGROUND_TICK');self.assertFalse(p['bThrottleCPUWhenNotForeground'])
 def test_wrong_late_realtime_or_pose_refuses(self):
  for key,value in [('realtime',True),('world_path','foreign'),('fov',61),('location_cm',[9,9,9])]:
   u,read,f,v,p,w,seen,guard=self.fixture();token=begin_background_scope(u,read);submit_background_restore(u,token);f[0]=2;v[key]=value
   with self.assertRaises(ValueError):verify_background_restore(u,token,read,guard)
   self.assertFalse(seen);self.assertEqual(token['phase'],'RESTORE_SUBMITTED')
 def test_wrong_cdo_or_thread_refuses(self):
  for wrong_thread in (False,True):
   u,read,f,v,p,w,seen,guard=self.fixture();token=begin_background_scope(u,read);submit_background_restore(u,token);f[0]=2
   if wrong_thread:token['submitted']['OS_thread']=-1
   else:p['bThrottleCPUWhenNotForeground']=False
   with self.assertRaises(ValueError):verify_background_restore(u,token,read,guard)
   self.assertFalse(seen)
 def test_source_validator_failure_cannot_mark_restored(self):
  u,read,f,v,p,w,seen,guard=self.fixture();token=begin_background_scope(u,read);submit_background_restore(u,token);f[0]=2
  with self.assertRaises(ValueError):verify_background_restore(u,token,read,lambda:False)
  self.assertEqual(token['phase'],'RESTORE_SUBMITTED')
 def test_single_submit_and_verify_lifecycle(self):
  u,read,f,v,p,w,seen,guard=self.fixture();token=begin_background_scope(u,read)
  with self.assertRaises(ValueError):verify_background_restore(u,token,read,guard)
  submit_background_restore(u,token)
  with self.assertRaises(ValueError):submit_background_restore(u,token)
 def test_missing_native_readback_or_cdo_refuses(self):
  u,read,f,v,p,w,seen,guard=self.fixture();v.pop('realtime')
  with self.assertRaises(ValueError):begin_background_scope(u,read)
  self.assertFalse(w)
  u,read,f,v,p,w,seen,guard=self.fixture();u.find_object=lambda *args:None
  with self.assertRaises(ValueError):begin_background_scope(u,read)
  self.assertFalse(w)
if __name__=='__main__':unittest.main()
