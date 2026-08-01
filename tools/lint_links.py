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
#
# 2026-08-02（Z3）：**同族的第二个静默失效——正文里用省略号写的引用会被算成一条真引用。**
#   `docs/52@worktree-…`（docs/98 §七·1）与 `docs/54@worktree-agent-…`（docs/99 §三①）里的 `…`
#   不在分支名的字符集里，于是分支被截成 `worktree-` / `worktree-agent-`，git 当然解析不到
#   ⇒ 上一版把它们各报成一行「**本地没有这条 ref**（新 clone 上正常；无法判定）」。
#   **那句判词是假的**：不是本机缺分支，是那根本不是一条引用，而是一句【在谈论引用】的话。
#   后果两条：①「N 条不同引用 / M 处」被虚高（实测 **7 条 / 30 处** → 真值 **5 条 / 28 处**）；
#   ②一条**结构上永远无法判定**的行长期挂在输出里，正是 docs/41 §6 说的"训练所有人忽略这一段"。
#   判别规则（两条都取自 git 自己的 ref 命名规则，不是启发式）：紧跟其后的字符是 `…`，
#   或分支名以 `.` / `/` 结尾（`git check-ref-format` 明令禁止这两种）⇒ 判为**正文省略写法**，
#   单独列一行、不进引用计数、也不去 git 里查。
#   负对照可复跑：`python tools/lint_links.py --self-test`（9 例，不需要 git，约 0.01 s）。
#   ⚠️ 它**不解决**另一半：一份【谈论悬空引用的文档】自己也会把处数推高一格（X3 在 docs/94 §四·1-3
#   自陈过这个自指）。那一半是语料的性质，不是解析的缺陷 ⇒ **要引用的是「条数」，不是「处数」。**
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
#   ⚠️ 2026-08-02（Z3）：slug 那一段的字符类里**必须排掉 `@`**。排掉之前它是贪婪的，
#   于是 `docs/54-scale-n60.md@worktree-agent-xxx` 会被整段吞成 slug ⇒ `branch=None`
#   ⇒ **逃生门对"带文件名的写法"静默失效**，那条引用被当成普通的 `docs/54` 去查 HEAD。
#   今天树上这种写法 0 处 ⇒ 这是**潜伏**缺陷不是现行假绿（与 `2de5e44` 同一个形状：在它咬人之前修）。
#   它是被 `--self-test` 第 9 例抓出来的，不是读出来的。
NUMDOC = re.compile(r'docs/(\d{2,3})(?:-[^\s)\],;。，、）】@]*)?(@[A-Za-z0-9._/-]+)?')
GITREV = re.compile(r'[A-Za-z0-9._/-]+:$')              # trailing "branch:" right before docs/NN

# Numbered docs that actually exist on this tree, keyed by their NN prefix.
HAVE = set()
_docs_dir = os.path.join(ROOT, "docs")
if os.path.isdir(_docs_dir):
    for name in os.listdir(_docs_dir):
        m = re.match(r'^(\d{2,3})', name)
        if m:
            HAVE.add(m.group(1))

dead = []
branch_refs = {}    # (NN, branch) -> 引用处数
elided_refs = {}    # (NN, 被截断的分支前缀) -> 处数 —— 正文省略写法，**不是**引用


def is_elided(branch, next_char):
    """这条 `docs/NN@branch` 是不是【正文里的省略写法】而不是一条引用？

    两条判据都来自 `git check-ref-format`，不是拍脑袋的启发式：
      ① 紧跟其后的字符是 `…`（U+2026）—— 分支名被省略号截掉了；
      ② 分支名以 `.` 或 `/` 结尾 —— git 的 ref 名**不允许**这两种结尾，
         所以它只可能是 `docs/NN@branch-...` 这类 ASCII 省略号被字符集吞掉的残骸。
    """
    return next_char == "…" or branch.endswith(".") or branch.endswith("/")


def classify(m, txt):
    """把一次 `NUMDOC` 命中分成三类，返回 `(kind, (num, branch))`：

      `ref`    —— 一条真的 `docs/NN@branch` 引用（branch 拿去 git 现查）
      `elided` —— 正文里的省略写法，**不是**引用（不进计数、不查 git）
      `plain`  —— 普通的 `docs/NN` 纯文本引用（branch 为 None，走 HAVE 判定）

    ⚠️ **主循环与 `--self-test` 必须走这同一个函数** —— 否则自测测的是另一份逻辑，
    而那正是本仓库反复抓到的"量具复刻了判据"那个病（W3 的第一版量具就是这么错的）。
    """
    num, branch = m.group(1), m.group(2)
    if branch:
        key = (num, branch[1:])
        return ("elided" if is_elided(branch[1:], txt[m.end():m.end() + 1]) else "ref"), key
    # `docs/NN@…` —— 分支名被【整段】省略。`…` 不在分支名的字符集里，所以上面那个可选组
    # 一个字符都匹配不到 ⇒ branch is None ⇒ 上一版会把它当成普通的 `docs/NN` 判成【死引用】。
    # **那是一次假红**：作者其实用对了逃生门，只是把分支名省略了。（Z3 自己写回执时连撞两次。）
    if txt[m.end():m.end() + 1] == "@" and is_elided("", txt[m.end() + 1:m.end() + 2]):
        return "elided", (num, "")
    return "plain", (num, None)


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


def self_test():
    """9 例负对照，**不需要 git、不读仓库**，约 0.01 s。

    前 3 例守 2026-08-02（Z3）那条省略写法；中 3 例守"真引用不许被误判成省略"；
    后 3 例守 `2de5e44` 修的那条**三位数编号**——它是同一族的第一次发作，
    而当时没有留下任何可复跑的负对照，于是这次一并补上。
    """
    cases = [
        # (正文片段, 期望 (num, branch) 或 None, 期望是不是省略写法)
        ("见 docs/52@… 那一条",                       ("52", ""),                   True),
        ("见 docs/52@worktree-… 那 9 处",            ("52", "worktree-"),          True),
        ("见 docs/54@worktree-agent-… ×2",           ("54", "worktree-agent-"),    True),
        ("见 docs/52@worktree-agent-... 的说法",      ("52", "worktree-agent-..."), True),
        ("见 docs/27@exile-hardening 的负结果",       ("27", "exile-hardening"),    False),
        ("见 docs/45@claude/objective-lumiere-e6f125`", ("45", "claude/objective-lumiere-e6f125"), False),
        ("见 docs/26@phase-d-contract-hardening 一节", ("26", "phase-d-contract-hardening"), False),
        ("见 docs/102@some-branch 的回执",            ("102", "some-branch"),       False),
        ("见 docs/10@some-branch 的回执",             ("10", "some-branch"),        False),
        ("见 docs/100-foo.md@some-branch",            ("100", "some-branch"),       False),
    ]
    bad = 0
    for txt, want_key, want_elided in cases:
        m = NUMDOC.search(txt)
        kind, key = classify(m, txt) if m else ("plain", (None, None))
        got_key = key if kind in ("ref", "elided") else None
        got_elided = (kind == "elided")
        ok = (got_key == want_key) and (got_elided == want_elided)
        if not ok:
            bad += 1
        print("  %s %-46s 期望 %-42s 省略=%-5s | 实得 %-42s 省略=%s"
              % ("✅" if ok else "❌", txt, want_key, want_elided, got_key, got_elided))
    if bad:
        print("lint_links --self-test: FAIL（%d/%d 例不符）" % (bad, len(cases)))
        return 1
    print("lint_links --self-test: PASS（%d/%d 例）—— 4 例省略写法 · 3 例真引用 · "
          "3 例编号位数（10 / 100 / 102，守 2de5e44 那条三位数修法不回退）" % (len(cases), len(cases)))
    return 0


if "--self-test" in sys.argv[1:]:
    sys.exit(self_test())

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
        kind, key = classify(m, txt)
        if kind == "ref":                               # docs/NN@branch — deliberately off-tree
            branch_refs[key] = branch_refs.get(key, 0) + 1
            continue
        if kind == "elided":                            # 正文省略写法，不是引用
            elided_refs[key] = elided_refs.get(key, 0) + 1
            continue
        num = key[0]
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
    if elided_refs:
        print("  另有 %d 条 / %d 处是【正文里的省略写法】（`docs/NN@分支…`），**不是引用，不进上面的计数**："
              % (len(elided_refs), sum(elided_refs.values())))
        for (_n, _b), _c in sorted(elided_refs.items()):
            print("    docs/%s@%s…  ×%d" % (_n, _b, _c))
    if _unresolved:
        msg = ("  ⚠ 其中 %d 处指向【分支在、文档不在】的引用 —— 逃生门放行的正是这一类。" % _unresolved)
        if os.environ.get("LT_LINKS_STRICT") == "1":
            print(msg + " LT_LINKS_STRICT=1 ⇒ 判红。")
            sys.exit(1)
        print(msg + " 设 LT_LINKS_STRICT=1 可让它变红（默认不判：本地分支集因机器而异）。")
