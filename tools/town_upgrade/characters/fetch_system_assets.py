"""Fetch a checksum-pinned subset of official CC0 graphical assets by ZIP range.

No MakeHuman application code or inference service is used. The official asset
table labels these system clothes/hair/skins CC0. ZIP member CRC is checked by
zipfile and each extracted file receives a SHA-256 provenance entry.
"""
import concurrent.futures
import io
import json
from pathlib import Path
import hashlib
import urllib.request
import time
import zipfile

URL='https://files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip'
SIZE=280737770
ROOT=Path(__file__).parent/'vendor/system_assets'


class RemoteZip(io.RawIOBase):
    cache={}
    def __init__(self):self.position=0
    def readable(self):return True
    def seekable(self):return True
    def tell(self):return self.position
    def seek(self,offset,whence=0):
        self.position=offset if whence==0 else self.position+offset if whence==1 else SIZE+offset
        return self.position
    def read(self,count=-1):
        count=min(count if count>=0 else SIZE-self.position,SIZE-self.position)
        if count<=0:return b''
        key=(self.position,count)
        if key in self.cache:self.position+=count;return self.cache[key]
        for attempt in range(5):
            address=URL if attempt%2==0 else URL.replace('files2.','files.')
            request=urllib.request.Request(address,headers={'Range':f'bytes={self.position}-{self.position+count-1}'})
            try:
                with urllib.request.urlopen(request,timeout=60) as response:
                    if response.status!=206:raise RuntimeError('Server does not honor ZIP byte ranges')
                    data=response.read()
                if len(data)!=count:raise RuntimeError('Truncated ZIP byte range')
                break
            except Exception:
                if attempt==4:raise
                time.sleep(.5*(attempt+1))
        if len(data)!=count:raise RuntimeError('Truncated ZIP byte range')
        if count<1000000:self.cache[key]=data
        self.position+=count;return data


def fetch():
    ROOT.mkdir(parents=True,exist_ok=True)
    selected=[]
    with zipfile.ZipFile(RemoteZip()) as archive:
        for name in archive.namelist():
            wanted=['male_casualsuit01','female_casualsuit01','male_worksuit01','short01','ponytail01','young_asian_male','young_asian_female','middleage_asian_male','middleage_asian_female','old_asian_male','old_asian_female','eyebrow001','eyebrow005','eyelashes01','high-poly','shoes01','shoes05']
            if any('/'+asset+'/' in '/'+name for asset in wanted):
                if name.endswith(('.obj','.mhclo','.mhmat','.mhw','.thumb','.png')):selected.append(name)
            elif name in ['eyes/materials/brown_eye.png','eyes/materials/brown.mhmat']:selected.append(name)
            # Fine photographic skin remains optional; the model generator can
            # use the original procedural skin without downloading a large pack.
    def one(name):
        path=ROOT/name;path.parent.mkdir(parents=True,exist_ok=True)
        if not path.resolve().is_relative_to(ROOT.resolve()):raise ValueError('Unsafe archive member path')
        if not path.exists():
            with zipfile.ZipFile(RemoteZip()) as archive:path.write_bytes(archive.read(name))
        data=path.read_bytes()
        print('CC0_ASSET '+name+' '+str(len(data)),flush=True)
        return name,{'archive':URL,'member':name,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:rows=list(pool.map(one,selected))
    provenance={'license':'CC0-1.0','official_asset_table':'https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html','retrieved_utc':'2026-10-20','files':dict(rows)}
    (ROOT/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':fetch()
