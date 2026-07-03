#!/usr/bin/env python3
# build_video.py — 把分段中文旁白 WAV + 中英脚本，合成整条旁白音轨 + 中英双语 .ass 字幕；
# 若给了 --video，则把视频 + 旁白 + 烧入字幕合成最终 mp4。容器内运行（需 ffmpeg/ffprobe）。
#
#   python3 /tools/build_video.py --media /out --narr /tools/narration.json \
#       --fontdir /game/assets/fonts [--video /out/town_raw.mp4 --out /out/living_town_demo.mp4]
import argparse, json, os, subprocess, sys

def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        print("CMD FAILED:", " ".join(cmd)); print(r.stdout); sys.exit(1)
    return r.stdout

def dur(path):
    out = run(["ffprobe","-v","error","-show_entries","format=duration","-of","default=noprint_wrappers=1:nokey=1",path])
    return float(out.strip())

def ts(t):  # ass time h:mm:ss.cs
    cs = int(round(t*100)); h=cs//360000; m=(cs%360000)//6000; s=(cs%6000)//100; c=cs%100
    return f"{h}:{m:02d}:{s:02d}.{c:02d}"

def ass_escape(s):
    return s.replace("\\","\\\\").replace("{","(").replace("}",")")

ap = argparse.ArgumentParser()
ap.add_argument("--media", required=True)
ap.add_argument("--narr", required=True)
ap.add_argument("--fontdir", required=True)
ap.add_argument("--video", default="")
ap.add_argument("--out", default="")
ap.add_argument("--lead", type=float, default=0.6)
ap.add_argument("--gap", type=float, default=0.35)
ap.add_argument("--tail", type=float, default=0.8)
a = ap.parse_args()

segs = json.load(open(a.narr, encoding="utf-8"))
tmp = os.path.join(a.media, "_tmp"); os.makedirs(tmp, exist_ok=True)
SR = "44100"

# 1) 归一化每段；测时长
norm, durs = [], []
for i,_ in enumerate(segs):
    src = os.path.join(a.media, f"seg_{i+1:02d}.wav")
    dst = os.path.join(tmp, f"n{i+1:02d}.wav")
    run(["ffmpeg","-y","-i",src,"-ar",SR,"-ac","1","-c:a","pcm_s16le",dst])
    norm.append(dst); durs.append(dur(dst))

# 2) 静音片段
def silence(name, t):
    p = os.path.join(tmp, name)
    run(["ffmpeg","-y","-f","lavfi","-i",f"anullsrc=r={SR}:cl=mono","-t",f"{t}","-c:a","pcm_s16le",p]); return p
lead = silence("lead.wav", a.lead); gap = silence("gap.wav", a.gap); tail = silence("tail.wav", a.tail)

# 3) 拼接 narration.wav（lead, seg, gap, seg, ..., segN, tail）
listf = os.path.join(tmp, "list.txt")
with open(listf,"w",encoding="utf-8") as f:
    f.write(f"file '{lead}'\n")
    for i,p in enumerate(norm):
        f.write(f"file '{p}'\n")
        f.write(f"file '{gap if i < len(norm)-1 else tail}'\n")
narration = os.path.join(a.media, "narration.wav")
run(["ffmpeg","-y","-f","concat","-safe","0","-i",listf,"-c","copy",narration])
total = dur(narration)

# 4) 计算字幕打轴 + 写 .ass（CN 大、EN 小灰）
cues, t = [], a.lead
for i, seg in enumerate(segs):
    start, end = t, t + durs[i]
    cues.append((start, end - 0.05, seg["cn"], seg["en"]))
    t = end + a.gap

ass = os.path.join(a.media, "subs.ass")
with open(ass,"w",encoding="utf-8") as f:
    f.write("[Script Info]\nScriptType: v4.00+\nPlayResX: 1280\nPlayResY: 768\nWrapStyle: 2\nScaledBorderAndShadow: yes\n\n")
    f.write("[V4+ Styles]\n")
    f.write("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n")
    f.write("Style: CN,SimHei,30,&H00FFFFFF,&H000000FF,&H00101010,&H80000000,0,0,0,0,100,100,0,0,1,3,1,2,60,60,40,1\n\n")
    f.write("[Events]\nFormat: Layer, Start, End, Style, MarginL, MarginR, MarginV, Effect, Text\n")
    for (s,e,cn,en) in cues:
        txt = ass_escape(cn) + "\\N{\\fs22\\c&H00C8C8C8&}" + ass_escape(en)
        f.write(f"Dialogue: 0,{ts(s)},{ts(e)},CN,,0,0,0,,{txt}\n")

print(f"SEGMENTS={len(segs)}  NARRATION_TOTAL={total:.2f}s")

# 5) 可选：合成最终视频（烧字幕 + 配音）
if a.video and a.out:
    vdur = dur(a.video)
    print(f"VIDEO_DUR={vdur:.2f}s  (need >= {total:.2f}s)")
    # 让 libass 通过 fontconfig 也能找到 SimHei（双保险）
    subprocess.run(f"cp {a.fontdir}/cjk.ttf /usr/share/fonts/ 2>/dev/null; fc-cache -f >/dev/null 2>&1", shell=True)
    assf = ass.replace(":","\\:")
    vf = f"subtitles='{assf}':fontsdir='{a.fontdir}'"
    run(["ffmpeg","-y","-i",a.video,"-i",narration,
         "-filter_complex",f"[0:v]{vf}[v]",
         "-map","[v]","-map","1:a","-t",f"{total:.3f}",
         "-c:v","libx264","-preset","veryfast","-pix_fmt","yuv420p","-crf","23",
         "-c:a","aac","-b:a","160k",a.out])
    print(f"WROTE {a.out}  ({dur(a.out):.2f}s)")
