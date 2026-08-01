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
#
# 2026-08-02（X3）：check (2) 的 `@branch` 逃生门此前是**零验证**的（S2 编号 73 §二·5-P2 点名）。
#   现在它每次都把每一条 `docs/NN@branch` 拿去 git 里【现查现印】：分支在不在、那份文档在不在那条分支上、
#   有没有其实已经并进 HEAD 了。**只打印，不判红**——理由与 recalc_registry 里那条 `gate:false` 同源，
#   而且这里更硬：这些 `worktree-agent-*` / `claude/*` 分支是**本地**的，
#   在一份全新 clone（GitHub Actions）上一条都不存在 ⇒ 拿它判红 = 换台机器就全假红
#   （docs/41 §6：一道在别人机器上因环境变红的门比没有门更坏）。
#   想让它变红：`LT_LINKS_STRICT=1`（只在你确信本地有全部分支时用）。
import re, subprocess, sys, os, glob
ROOT = os.path.join(os.path.dirname(__file__), "..")
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass
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
branch_refs = {}    # (NN, branch) -> 引用处数


def _git(*args):
    try:
        r = subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True)
        return r.returncode, r.stdout.decode("utf-8", "replace")
    except OSError:
        return 127, ""


def resolve_branch_refs():
    """把 `docs/NN@branch` 逐条拿去 git 现查现印。返回 (报告行列表, 真的解析不到的条数)。"""
    lines, unresolved = [], 0
    for (num, br), n in sorted(branch_refs.items()):
        rc, _ = _git("rev-parse", "--verify", "--quiet", br)
        if rc == 127:
            lines.append("    docs/%s@%s  ×%d  —— 本机没有 git，无法判定" % (num, br, n))
            continue
        if rc != 0:
            lines.append("    docs/%s@%s  ×%d  —— **本地没有这条 ref**（新 clone 上正常；无法判定）" % (num, br, n))
            continue
        _, out = _git("ls-tree", "-r", "--name-only", br, "--", "docs")
        on_br = bool(re.search(r"^docs/%s-" % num, out, re.M))
        on_head = num in HAVE
        if on_br:
            tail = "在该分支上 ✅" + ("（**且已并进 HEAD** ⇒ `@%s` 可以去掉了）" % br if on_head else "")
        elif on_head:
            tail = "**不在该分支上**，但 HEAD 上有 docs/%s-* ⇒ 引用能到达，分支名已经不对了" % num
        else:
            tail = "**分支在、文档不在** ⇒ 这条引用今天指向一个不存在的文件"
            unresolved += n
        lines.append("    docs/%s@%s  ×%d  —— %s" % (num, br, n, tail))
    return lines, unresolved


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
            key = (num, branch[1:])
            branch_refs[key] = branch_refs.get(key, 0) + 1
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

# `@branch` 逃生门的普查：**每次现查现印**，不留冻结字面量（S2 编号 73 §二·3 的统一结论）。
if branch_refs:
    _lines, _unresolved = resolve_branch_refs()
    print("  `docs/NN@branch` 逃生门 %d 条不同引用 / %d 处（**只打印不判红**，理由见本文件抬头）："
          % (len(branch_refs), sum(branch_refs.values())))
    for _l in _lines:
        print(_l)
    if _unresolved:
        msg = ("  ⚠ 其中 %d 处指向【分支在、文档不在】的引用 —— 逃生门放行的正是这一类。" % _unresolved)
        if os.environ.get("LT_LINKS_STRICT") == "1":
            print(msg + " LT_LINKS_STRICT=1 ⇒ 判红。")
            sys.exit(1)
        print(msg + " 设 LT_LINKS_STRICT=1 可让它变红（默认不判：本地分支集因机器而异）。")
