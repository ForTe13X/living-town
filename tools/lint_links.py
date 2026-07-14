#!/usr/bin/env python
# CI lint: relative links + image refs in *.md must resolve to a real file.
# Skips http(s)/mailto/anchor-only links. Exit 1 on any dead relative target.
import re, sys, os, glob
ROOT = os.path.join(os.path.dirname(__file__), "..")
_SKIP = (os.sep + "android" + os.sep, os.sep + ".godot" + os.sep, os.sep + "build" + os.sep,
         os.sep + ".git" + os.sep, os.sep + "node_modules" + os.sep)
MD = [p for p in glob.glob(os.path.join(ROOT, "**", "*.md"), recursive=True)
      if not any(s in p for s in _SKIP)]
LINK = re.compile(r'!?\[[^\]]*\]\(([^)]+)\)')          # [text](target) and ![alt](target)
IMG = re.compile(r'<img[^>]+src=["\']([^"\']+)["\']')   # <img src="...">
dead = []
for md in MD:
    base = os.path.dirname(md)
    txt = open(md, encoding="utf-8", errors="replace").read()
    for m in list(LINK.finditer(txt)) + list(IMG.finditer(txt)):
        tgt = m.group(1).strip().split()[0]            # drop optional "title"
        if re.match(r'^(https?:|mailto:|#|data:)', tgt):
            continue
        tgt = tgt.split("#")[0]                         # strip anchor
        if not tgt:
            continue
        path = os.path.normpath(os.path.join(base, tgt))
        if not os.path.exists(path):
            rel = os.path.relpath(md, ROOT).replace(os.sep, "/")
            dead.append(f"{rel}: -> {tgt}")
if dead:
    print(f"lint_links: FAIL ({len(dead)} dead relative link(s)):")
    for d in dead: print("  -", d)
    sys.exit(1)
print(f"lint_links: OK — {len(MD)} markdown files, all relative links resolve")
