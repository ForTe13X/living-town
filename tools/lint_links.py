#!/usr/bin/env python
# CI lint for *.md, two checks:
#   (1) relative [text](target) links and <img src> must resolve to a real file
#       (http(s)/mailto/anchor-only/data: are skipped);
#   (2) PLAIN-TEXT `docs/NN` references must point at a numbered doc that exists.
#       Prose citations like "见 docs/27" are invisible to check (1) because they are
#       not markdown links — yet a reader following the reference hits a hole just the
#       same. If the doc genuinely lives only on an unmerged branch, write it either as
#       `docs/NN@branch` (e.g. docs/27@exile-hardening) or as a git revision
#       (`exile-hardening:docs/27-...`). Both forms are accepted and both tell the reader
#       exactly where to look.
# Exit 1 on any dead target.
import re, sys, os, glob
ROOT = os.path.join(os.path.dirname(__file__), "..")
_SKIP = (os.sep + "android" + os.sep, os.sep + ".godot" + os.sep, os.sep + "build" + os.sep,
         os.sep + ".git" + os.sep, os.sep + "node_modules" + os.sep)
MD = [p for p in glob.glob(os.path.join(ROOT, "**", "*.md"), recursive=True)
      if not any(s in p for s in _SKIP)]
LINK = re.compile(r'!?\[[^\]]*\]\(([^)]+)\)')          # [text](target) and ![alt](target)
IMG = re.compile(r'<img[^>]+src=["\']([^"\']+)["\']')   # <img src="...">
# docs/27  ·  docs/27-exile-hardening-negative-result.md  ·  docs/27@exile-hardening
NUMDOC = re.compile(r'docs/(\d{2})(?:-[^\s)\],;。，、）】]*)?(@[A-Za-z0-9._/-]+)?')
GITREV = re.compile(r'[A-Za-z0-9._/-]+:$')              # trailing "branch:" right before docs/NN

# Numbered docs that actually exist on this tree, keyed by their NN prefix.
HAVE = set()
_docs_dir = os.path.join(ROOT, "docs")
if os.path.isdir(_docs_dir):
    for name in os.listdir(_docs_dir):
        m = re.match(r'^(\d{2})', name)
        if m:
            HAVE.add(m.group(1))

dead = []
for md in MD:
    base = os.path.dirname(md)
    rel = os.path.relpath(md, ROOT).replace(os.sep, "/")
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
            dead.append(f"{rel}: -> {tgt}")
    # (2) plain-text docs/NN citations
    for m in NUMDOC.finditer(txt):
        num, branch = m.group(1), m.group(2)
        if branch:                                      # docs/NN@branch — deliberately off-tree
            continue
        if num in HAVE:
            continue
        if GITREV.search(txt[:m.start()]):              # "branch:docs/NN-..." (git revision)
            continue
        line = txt.count("\n", 0, m.start()) + 1
        dead.append(f"{rel}:{line}: -> {m.group(0)} (no docs/{num}-* on this tree; "
                    f"write docs/{num}@<branch> if it lives on an unmerged branch)")

if dead:
    print(f"lint_links: FAIL ({len(dead)} dead reference(s)):")
    for d in dead: print("  -", d)
    sys.exit(1)
print(f"lint_links: OK — {len(MD)} markdown files, "
      f"all relative links resolve and all docs/NN citations exist ({len(HAVE)} numbered docs)")
