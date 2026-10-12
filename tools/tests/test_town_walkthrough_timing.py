"""Exercise a sparse decoded-picture timeline, as produced by Theora repeats."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from tools.build_town_walkthrough import movie_timeline_trim, theora_repeat_timeline


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg required")
class WalkthroughTimingTests(unittest.TestCase):
    def test_actual_theora_repeat_packets_preserve_the_static_tail(self):
        def run(*args):
            return subprocess.run(args, check=True, capture_output=True, text=True).stdout

        with tempfile.TemporaryDirectory(prefix="town_theora_timing_") as folder:
            source, result = Path(folder) / "repeats.ogv", Path(folder) / "tour.mkv"
            run("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x64:r=24:d=3",
                "-c:v", "libtheora", "-threads", "1", str(source))
            packets = json.loads(run("ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_packets", "-show_entries", "packet=pts,duration,size", "-of", "json", str(source)))["packets"]
            timeline = theora_repeat_timeline(packets)
            self.assertEqual(timeline["packet_count"], 72)
            self.assertGreater(timeline["trailing_repeat_packets"], 0)
            run("ffmpeg", "-v", "error", "-threads", "1", "-i", str(source), "-vf",
                movie_timeline_trim(24, 48, timeline["trailing_repeat_packets"]),
                "-fps_mode", "passthrough", "-c:v", "ffv1", "-threads", "1", str(result))
            finished = json.loads(run("ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
                "-show_entries", "stream=nb_read_frames:format=duration", "-of", "json", str(result)))
            self.assertEqual(int(finished["streams"][0]["nb_read_frames"]), 48)
            self.assertAlmostEqual(float(finished["format"]["duration"]), 2.0, places=2)
            with self.assertRaises(ValueError):
                theora_repeat_timeline(packets[:-1] + [{**packets[-1], "pts": 73}])

    def test_sparse_pictures_preserve_the_complete_movie_timeline(self):
        def run(*args):
            return subprocess.run(args, check=True, capture_output=True, text=True).stdout

        def probe(path):
            return json.loads(run("ffprobe", "-v", "error", "-count_frames",
                                  "-select_streams", "v:0", "-show_entries",
                                  "stream=nb_read_frames:format=duration", "-of", "json", str(path)))

        with tempfile.TemporaryDirectory(prefix="town_movie_timing_") as folder:
            source, result = Path(folder) / "sparse.mkv", Path(folder) / "tour.mkv"
            # Missing pictures retain their original timestamps. A player holds
            # the previous picture; counting decoded pictures would skip time.
            run("ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "color=c=blue:s=64x64:r=24:d=3", "-vf", "select=not(between(n\\,1\\,5))",
                "-fps_mode", "vfr", "-c:v", "ffv1", "-threads", "1", str(source))
            original = probe(source)
            self.assertLess(int(original["streams"][0]["nb_read_frames"]), 72)
            run("ffmpeg", "-v", "error", "-threads", "1", "-i", str(source),
                "-vf", movie_timeline_trim(24, 48), "-fps_mode", "passthrough",
                "-c:v", "ffv1", "-threads", "1", str(result))
            finished = probe(result)
            self.assertEqual(int(finished["streams"][0]["nb_read_frames"]), 48)
            self.assertAlmostEqual(float(finished["format"]["duration"]), 2.0, places=2)


if __name__ == "__main__":
    unittest.main()
