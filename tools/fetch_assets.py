#!/usr/bin/env python3
# fetch_assets.py — 按 tools/assets_catalog.json 下载 CC0 美术资源（幂等：已有则跳过）。
# 范式同 22nd gamecraft-bench/scripts/fetch_oga_assets.py。每个 slug 一个子目录 + LICENSE.txt。
#   python3 /tools/fetch_assets.py --catalog /tools/assets_catalog.json --dest /game/assets/art/library
import argparse, json, os, urllib.request, zipfile, sys

ap = argparse.ArgumentParser()
ap.add_argument("--catalog", required=True)
ap.add_argument("--dest", required=True)
a = ap.parse_args()
UA = "living-town-asset-fetch/0.1"

cat = json.load(open(a.catalog, encoding="utf-8"))
for e in cat:
    d = os.path.join(a.dest, e["slug"])
    os.makedirs(d, exist_ok=True)
    # LICENSE 总是写（小、便于审计）
    with open(os.path.join(d, "LICENSE.txt"), "w", encoding="utf-8") as f:
        f.write(f"{e['title']}\nLicense: {e['license']}\nAuthor: {e.get('author','?')}\nSource: {e['url']}\n")
    have = [p for p in os.listdir(d) if p != "LICENSE.txt"]
    if have:
        print(f"[skip] {e['slug']} (已有 {len(have)} 项)")
        continue
    for fobj in e["files"]:
        dst = os.path.join(d, fobj["name"])
        req = urllib.request.Request(fobj["url"], headers={"User-Agent": UA})
        print(f"[get ] {e['slug']}/{fobj['name']}")
        with urllib.request.urlopen(req, timeout=120) as r, open(dst, "wb") as out:
            out.write(r.read())
        if dst.endswith(".zip"):
            with zipfile.ZipFile(dst) as z:
                z.extractall(d)
            os.remove(dst)
            print(f"        extracted + removed zip")
    print(f"[done] {e['slug']} -> {os.listdir(d)}")
print("ALL DONE")
