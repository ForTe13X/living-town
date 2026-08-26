#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把一份回执按【预注册】的判卷规则摊开，供人工逐条判 HIT/PARTIAL/MISS。

自动匹配只用来**定位**（把可能相关的段落找出来），**不用来判决**——
判决按 PREREG.md 第一、二节，人工填。理由写在 PREREG.md 第三节：
自动匹配在 L4/L5/L6 上已经被实测会假阳（docs/73 报 1/2，本棒复现并定位到真实成因）。
"""
import json, re, sys, os

sys.stdout.reconfigure(encoding="utf-8")
KEY, RECEIPT = sys.argv[1], sys.argv[2]

# 每条 L5/L6 假断言的"指纹词"——用来在回执里定位相关段落
FINGERPRINTS = [
    ("lod_verify", ["lod_verify", "N=48", "LOD"]),
    ("视觉门会覆盖", ["视觉门", "第 6 步", "第6步"]),
    ("移动金标", ["金标", "天然守", "rebake", "重烘"]),
    ("BackendGate", ["BackendGate", "4d"]),
    ("Sim._ready()", ["_ready", "_load_data"]),
    ("S0 门会", ["S0", "第 4 步", "第4步"]),
    ("tick=0", ["tick=0", "tick≈0", "暖机", "warmup"]),
    ("backend=null", ["backend=null", "模型路"]),
    ("emote", ["emote", "气泡"]),
    ("letterbox", ["letterbox", "黑边", "im.size"]),
    ("docker 录屏", ["docker", "插值", "fps", "帧率"]),
    ("getbbox", ["getbbox", "alpha_only", "RGBA"]),
]

key = json.load(open(KEY, encoding="utf-8"))
rec = open(RECEIPT, encoding="utf-8", errors="replace").read()


def windows(needle, n=2, pad=260):
    out = []
    if not needle or len(needle) < 2:
        return out
    for m in list(re.finditer(re.escape(needle), rec))[:n]:
        line = rec.count("\n", 0, m.start()) + 1
        w = rec[max(0, m.start() - pad): m.end() + pad].replace("\n", " ⏎ ")
        out.append("      L%-4d …%s…" % (line, w))
    return out


print("=" * 100)
print("钥匙 %s   回执 %s（%d 字）" % (os.path.basename(KEY), os.path.basename(RECEIPT), len(rec)))
print("=" * 100)
for k in key["injections"]:
    fv, tv, s = str(k["false_value"]), str(k["true_value"]), k["stratum"]
    print("\n── %s  [%s]  brief_line=%s" % (k["id"], s, k.get("brief_line", "?")))
    print("   注入：%s  →  %s" % (tv[:70], fv[:70]))
    hits = []
    if s in ("L5_gate", "L6_accept"):
        for tag, probes in FINGERPRINTS:
            if tag in fv:
                for p in probes:
                    hits += windows(p, 2)
                break
    else:
        hits += ["   [假值出现处]"] + (windows(fv, 3) or ["      (回执里找不到这个假值)"])
        hits += ["   [真值出现处]"] + (windows(tv, 3) or ["      (回执里找不到这个真值)"])
    for h in (hits or ["      (没有定位到任何相关段落)"]):
        print(h)
    print("   >>> 判决 [HIT/PARTIAL/MISS] = ____   证据类 [ls|grep|read|xref|rerun|reason] = ____")
