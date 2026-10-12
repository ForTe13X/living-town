"""Encode, probe and visually index the completed native coastal animation.

Run with normal Python + Pillow after render_flythrough.py has completed.
The checksum and counted video frames bind evidence to the actual MP4.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile
from fractions import Fraction
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
record_path = ROOT / 'evidence/flythrough_render.json'
record = json.loads(record_path.read_text(encoding='utf-8'))
video = ROOT / record['video']
source = ROOT / 'living_town_complete.blend'
assert hashlib.sha256(source.read_bytes()).hexdigest() == record['source_blend_sha256']
frames = ROOT / record['frame_directory']
assert len(list(frames.glob('[0-9][0-9][0-9][0-9].png'))) == 240
subprocess.run(['ffmpeg', '-y', '-threads', '4', '-framerate', '24', '-i', str(frames / '%04d.png'),
                '-c:v', 'libx264', '-threads', '4', '-crf', '20', '-pix_fmt', 'yuv420p',
                '-movflags', '+faststart', str(video)], check=True)
with video.open('rb+') as stream:
    os.fsync(stream.fileno())
probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-count_frames',
    '-select_streams', 'v:0', '-show_entries', 'stream=width,height,nb_read_frames,avg_frame_rate,duration:format=duration',
    '-of', 'json', str(video)], text=True))
stream = probe['streams'][0]
checksum = hashlib.sha256(video.read_bytes()).hexdigest()
metrics = {'video_sha256': checksum, 'width': stream['width'], 'height': stream['height'],
           'frame_count': int(stream['nb_read_frames']), 'frame_count_source': 'nb_read_frames',
           'fps': float(Fraction(stream['avg_frame_rate'])),
           'duration_seconds': float(stream.get('duration', probe['format']['duration']))}
assert (metrics['width'], metrics['height'], metrics['frame_count']) == (1280, 720, 240)
assert abs(metrics['duration_seconds'] - 10) <= .05 and abs(metrics['fps'] - 24) <= .001
with tempfile.TemporaryDirectory(prefix='living_town_motion_') as temporary:
    pattern = str(Path(temporary) / '%02d.png')
    subprocess.run(['ffmpeg', '-v', 'error', '-threads', '4', '-i', str(video), '-vf',
        r'select=eq(n\,0)+eq(n\,79)+eq(n\,159)+eq(n\,239),scale=640:360',
        '-fps_mode', 'vfr', '-threads', '4', pattern], check=True)
    paths = sorted(Path(temporary).glob('*.png'))
    assert len(paths) == 4
    sheet = Image.new('RGB', (1280, 780), '#ece8dc')
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(paths):
        x, y = (index % 2) * 640, (index // 2) * 390
        with Image.open(path) as frame:
            sheet.paste(frame.convert('RGB'), (x, y))
        draw.text((x+12, y+366), ['0.00 s', '3.29 s', '6.63 s', '9.96 s'][index], fill='#293d36')
    sheet_path = ROOT / 'evidence/flythrough_contact.png'
    sheet.save(sheet_path)
record.update({'video_sha256': checksum, 'ffprobe': metrics,
               'contact_sheet': 'evidence/flythrough_contact.png',
               'contact_sheet_sha256': hashlib.sha256(sheet_path.read_bytes()).hexdigest()})
temporary = record_path.with_suffix('.tmp')
with temporary.open('w', encoding='utf-8') as output:
    json.dump(record, output, indent=2)
    output.flush(); os.fsync(output.fileno())
temporary.replace(record_path)
print(json.dumps({'status': 'PASS', 'video': str(video), 'ffprobe': metrics}, indent=2), flush=True)
