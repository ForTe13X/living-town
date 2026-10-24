import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from tools.town_upgrade.terrain_cache import reuse,sha


class ExactTerrainCache(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.cache=self.root/'cache';self.cache.mkdir()
        self.output=self.root/'new';self.output.mkdir();self.sources=self.root/'sources';self.sources.mkdir()
        self.guide=self.root/'guide.json';self.guide.write_bytes(b'{"bound":2}')
        self.tool=self.root/'bake.py';self.tool.write_bytes(b'# frozen atlas recipe\n')
        source=self.sources/'scan.jpg';source.write_bytes(b'original scan bytes')
        (self.sources/'source_receipts.json').write_text(json.dumps({'files':[{'path':source.name,'sha256':sha(source)}]}))
        def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',2,2,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+b'\x80'*6)*2))+chunk(b'IEND',b'')
        maps={}
        for role in ('diff','nor_gl','arm'):
            path=self.cache/(role+'.png');path.write_bytes(png)
            maps[role]={'path':path.name,'bytes':len(png),'sha256':sha(path)}
        self.receipt={'schema':'living_town.terrain_atlas.v1','input_guide_sha256':sha(self.guide),
                      'source_receipts_sha256':sha(self.sources/'source_receipts.json'),'tool_sha256':sha(self.tool),
                      'dimensions':[2,2],'maps':maps}
        self.save_receipt()

    def save_receipt(self):
        (self.cache/'terrain_atlas_receipt.json').write_text(json.dumps(self.receipt))

    def invoke(self):return reuse(self.cache,self.guide,self.sources,self.output,self.tool,2)

    def reject_without_writes(self):
        with self.assertRaises(ValueError):self.invoke()
        self.assertEqual(list(self.output.iterdir()),[])

    def test_exact_reuse_preserves_every_map_byte(self):
        result=self.invoke()
        for role,row in self.receipt['maps'].items():
            self.assertEqual((self.output/row['path']).read_bytes(),(self.cache/row['path']).read_bytes())
            self.assertEqual(result['maps_sha256'][role],row['sha256'])

    def test_changed_contour_guide_rejected(self):
        self.guide.write_bytes(b'{"bound":3}');self.reject_without_writes()

    def test_changed_scan_bytes_rejected(self):
        (self.sources/'scan.jpg').write_bytes(b'changed scan bytes');self.reject_without_writes()

    def test_changed_recipe_rejected(self):
        self.tool.write_bytes(b'# changed sampling\n');self.reject_without_writes()

    def test_corrupt_map_rejected(self):
        with (self.cache/'diff.png').open('ab') as stream:stream.write(b'corrupt')
        self.reject_without_writes()

    def test_wrong_actual_dimensions_rejected_even_with_updated_hash(self):
        path=self.cache/'diff.png';data=bytearray(path.read_bytes());data[16:20]=struct.pack('>I',3);path.write_bytes(data)
        self.receipt['maps']['diff']['sha256']=sha(path);self.save_receipt();self.reject_without_writes()

    def test_map_path_escape_rejected(self):
        self.receipt['maps']['diff']['path']='../guide.json';self.save_receipt();self.reject_without_writes()


if __name__=='__main__':unittest.main()
