"""Portable CPU shape/refusal controls; actual engine qualification is separate."""
import csv,tempfile,unittest
from pathlib import Path
from validate_viewport_csv import FIELDS,MAXIMUM_EXACT_FRAME,qualify_rows,qualify_csv

class ExtentQualificationTests(unittest.TestCase):
    def fixture(self):
        return ['EVENTS',*FIELDS],[['boundary','0','0','0','0']]+[['','1920','1080',str(5001+i),'1']for i in range(6)]
    def test_valid_dense_native_shape(self):
        h,r=self.fixture();self.assertEqual(qualify_rows(h,r,0)['retained_rows'],6)
        r[0][0]='CsvExecCommand : GetMaxTickRate##1.0'
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'instrumented.csv'
            with path.open('w',encoding='utf-8',newline='') as stream:csv.writer(stream).writerows([h,*r,h])
            self.assertEqual(qualify_csv(path)['retained_rows'],6)
    def test_single_changed_extent_is_refused(self):
        h,r=self.fixture();r[4][1:3]=['1280','649']
        with self.assertRaisesRegex(ValueError,'extent changed at CSV row 4'):qualify_rows(h,r,0)
    def test_single_missing_tick_is_refused(self):
        h,r=self.fixture();r[2][-1]='0'
        with self.assertRaisesRegex(ValueError,'one game-thread viewport sample'):qualify_rows(h,r,0)
    def test_duplicate_tick_is_refused(self):
        h,r=self.fixture();r[2][-1]='2'
        with self.assertRaisesRegex(ValueError,'got 2'):qualify_rows(h,r,0)
    def test_missing_column_is_refused(self):
        h,r=self.fixture();h[1]='unrelated'
        with self.assertRaisesRegex(ValueError,'unique native viewport'):qualify_rows(h,r,0)
    def test_duplicate_column_is_refused(self):
        h,r=self.fixture();h.append(FIELDS[0])
        with self.assertRaisesRegex(ValueError,'unique native viewport'):qualify_rows(h,r,0)
    def test_missing_row_field_is_refused(self):
        h,r=self.fixture();r[3].pop()
        with self.assertRaisesRegex(ValueError,'Missing native viewport sample'):qualify_rows(h,r,0)
    def test_frame_gap_and_repeat_are_refused(self):
        for bad in('5002','5004'):
            h,r=self.fixture();r[3][3]=bad
            with self.assertRaisesRegex(ValueError,'not consecutive'):qualify_rows(h,r,0)
    def test_missing_viewport_is_refused(self):
        h,r=self.fixture();r[3][1:3]=['0','0']
        with self.assertRaisesRegex(ValueError,'extent changed'):qualify_rows(h,r,0)
    def test_native_overflow_sentinel_is_refused(self):
        h,r=self.fixture();r[3][3]='-1'
        with self.assertRaisesRegex(ValueError,'frame-counter range'):qualify_rows(h,r,0)
    def test_nonfinite_fractional_and_out_of_contract_values_are_refused(self):
        for bad in('NaN','inf','5003.5',str(MAXIMUM_EXACT_FRAME+1)):
            h,r=self.fixture();r[3][3]=bad
            with self.assertRaises(ValueError):qualify_rows(h,r,0)
    def test_exact_upper_bound_is_preserved(self):
        h,_=self.fixture();r=[['boundary','0','0','0','0'],['','1920','1080',str(MAXIMUM_EXACT_FRAME),'1']]
        self.assertEqual(qualify_rows(h,r,0)['last_GT_frame'],MAXIMUM_EXACT_FRAME)
    def test_uninstrumented_csv_fixture_is_refused(self):
        # Synthetic portable negative; this does not reread a historical capture.
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'uninstrumented.csv'
            rows=[['EVENTS','FrameTime'],['CsvExecCommand : GetMaxTickRate##1.0','1'],['','1'],['EVENTS','FrameTime']]
            with path.open('w',encoding='utf-8',newline='') as stream:csv.writer(stream).writerows(rows)
            with self.assertRaisesRegex(ValueError,'Four unique native viewport'):qualify_csv(path)

if __name__=='__main__':unittest.main()
