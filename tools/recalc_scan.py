#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""recalc_scan.py — 量一件事：**文档里的数字，今天还有多少条能被重新算出来。**

由来（编号 82 · U3）：T2 的 L4 分层劈得干干净净——
**真值在树上另有一份副本的 3/3 被抓住；真值只此一份、必须重算的 0/2。**
A3 明写它为什么没抓到：**它去找 CIEDE2000 的工具想重算，而那套工具从未入库。**

⇒ 本工具把那次 n=5 的观察扩成一次**全语料普查**，好让「补哪些工具」这件事有个分母。

⚠️ **而普查当场推翻了"有第二份副本 = 抓得住"这个等号**：T2 那两条 MISS（`2.18` / `45.77`）
在今天的树上**有**第二份副本——**而那第二份就是 T2 自己那份说它们不可复算的回执**。
⇒ **`copy` 这一列随时间单调变松**（每讨论一次就多一份 xref），而它要衡量的那件事没变。
**别拿它当重算路径用**，见口径 2。

## 口径（三条，每条都会缩窄结论，所以写在最前面）

1. **population = 小数**，正则与 `brief_mutate.cand_number` **逐字相同**
   （`(?<![\w.])(\d+\.\d+)(?![\w.])`，0 < v < 1000，排除小节号/`§x.y`/`第x.y`/`vx.y`）。
   **整数不进分母**：`60 天` / `12 seed` / `2026` / `Sim.gd:3196` / `88 FPS` 混在一起，
   噪声会淹掉信号。⇒ 本扫描**不覆盖整数量**，这是已知缺口，别把它读成"整数都有重算路径"。
   用同一个正则的理由是：这样出来的数**与 T2 的 L4 直接可比**，不是另起一个口径。

2. **`copy` 这一列量的是"有没有第二份拷贝"，不是"能不能重算"。** T2 已经把这两件事分开过
   （`xref` vs `rerun`）：一个数在源码里另有一份，只证明**这个仓库把它抄了两遍**，
   不证明有人能重新量它。反过来也不对称——`#40` 的 0.419 全仓只在一份回执里，
   而 `bench/ScaleSupply.gd` 随时能重算它。**两列必须分开读。**

3. **`instrument` 这一列是【上界】。** 判据是"这个数所在的小节里，有没有指名一个**今天存在**的
   可执行件（`tools/*.py|sh` / `bench/*.gd` / `scenes/*.tscn` / 代码块里的 `python|bash|godot` 命令）"。
   小节里提到 `tools/ci.sh` **不等于** ci.sh 会算这个 ΔE00。
   ⇒ `instrument=present` 只说明**近旁有一条命令**，不说明它算的就是这个数。
   而 `instrument=missing`（指名了一个**不在树上**的可执行件）是一条**强**信号——
   那正是 A3 撞上的形状。

## 用法

    python tools/recalc_scan.py                    # 全量扫描，打印分布（逐文档展布，不给均值）
    python tools/recalc_scan.py --json out.json    # 落盘逐条明细
    python tools/recalc_scan.py --doc docs/47-wave-e-plan.md   # 只扫一份
    python tools/recalc_scan.py --orphans          # 只列 copy=none 且 instrument!=present 的那些
    python tools/recalc_scan.py --orphans --emph-only          # 同上，只看加粗的头条数字
    python tools/recalc_scan.py --with-analysis    # 把 analysis/** 加回语料（复核 EXCLUDE_PREFIX 那段）
    python tools/recalc_scan.py --self-test        # 负对照（见下）

## 负对照（`--self-test`，每次跑都会跑一遍，不是一次性的）

三条，全部构造在**临时目录**里，不碰仓库：
  A. 一个数在别处有拷贝 ⇒ 必须判 `copy=code`；把那份拷贝拿掉 ⇒ 必须判 `copy=none`。
     （**同一个数、同一份文档，只动树** ⇒ 分类必须翻面。）
  B. 小节里指名一个存在的工具 ⇒ `instrument=present`；把工具名改成一个不存在的
     ⇒ `instrument=missing`。（**同一棵树、只动一个字符** ⇒ 分类必须翻面。）
  C. 小节号 `### 1.3` / `§0.8` **不得**进分母（T2 实测的那条假阳）。
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 与 brief_mutate.NUMBER_RE 逐字相同 —— 故意的，见模块 docstring 口径 1
NUMBER_RE = re.compile(r"(?<![\w.])(\d+\.\d+)(?![\w.])")
HEADING_RE = re.compile(r"^#{1,6}\s", re.M)

# 可执行件的三种写法。`bench/X.gd` 在文档里常写成 `game/bench/X.gd` 或 `res://bench/X.gd`
ARTIFACT_RE = re.compile(
    r"(?:res://|game/|\./)?((?:tools|bench|scenes|analysis)/[A-Za-z0-9_./-]+\.(?:py|sh|gd|tscn|mjs|ps1))"
)
# 代码块里的命令行（只认能跑的三种头）
CMD_RE = re.compile(r"^\s*(?:\$\s*)?(python\d?|bash|godot|GODOT=|MSYS_NO_PATHCONV=|docker)\b", re.M)

TEXT_EXT = {".gd", ".py", ".sh", ".json", ".tscn", ".mjs", ".ps1", ".cfg",
            ".gdshader", ".yml", ".yaml", ".txt", ".tsv", ".gpl", ".import"}

# ⚠ `analysis/**` 默认整个排除，两个方向都排：
#   · 作为**文档总体**：它是实验原料（T2 的变异 brief、各臂回执），不是本仓库的自述；
#   · 作为**拷贝索引**：`analysis/t2/briefs/A3.md.txt` 按构造就是 docs/47 的一份逐字快照
#     ⇒ 不排的话，docs/47 里**每一个**数字都会被判成"源码里另有一份"（因为 `.md.txt` 不是 `.md`）。
#     实测差别：不排时 copy=none 是 23.1%，排掉之后见 `--with-analysis` 的对照打印。
#   `--with-analysis` 可以把它加回来，好让上面这句话是可复核的而不是我的自称。
EXCLUDE_PREFIX = ("analysis/",)


def tracked_files():
    # AE2：旧版直接 `return out.stdout.splitlines()`，git 非零退出（非仓库/损坏）时 stdout 为空
    # ⇒ 语料悄悄变空 ⇒ 报「分母 = 0」，读起来像"没有可重算的数字"而不是"扫描根本没跑成"。
    # 子进程非零 ⇒ 立即失败，别把失败伪装成一个干净的空结果。
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True,
                         encoding="utf-8", errors="replace")
    if out.returncode != 0:
        raise SystemExit("git ls-files 退出码 %d（cwd=%s）—— 扫描无法建立语料，拒绝返回空集冒充'没有数字'。%s"
                         % (out.returncode, ROOT, (out.stderr or "").strip()[:200]))
    files = [p for p in out.stdout.splitlines() if p]
    if not files:
        raise SystemExit("git ls-files 返回空（cwd=%s 不是 git 仓库？）—— 拒绝把空语料读成'0 个候选数字'。" % ROOT)
    return files


def load_corpus(root=ROOT, files=None, with_analysis=False):
    """返回 {rel_path: text}，只收得动的文本文件。"""
    corpus = {}
    for rel in (files if files is not None else tracked_files()):
        if not with_analysis and rel.replace("\\", "/").startswith(EXCLUDE_PREFIX):
            continue
        ext = os.path.splitext(rel)[1].lower()
        if ext not in TEXT_EXT and ext != ".md":
            continue
        p = os.path.join(root, rel)
        try:
            with open(p, encoding="utf-8") as f:
                corpus[rel] = f.read()
        except (OSError, UnicodeDecodeError):
            continue
    return corpus


def section_of(text, pos):
    """这个位置所在的小节：上一个标题行 → 下一个标题行。没有标题就整篇。"""
    start = 0
    for m in HEADING_RE.finditer(text):
        if m.start() > pos:
            end = m.start()
            break
        start = m.start()
    else:
        end = len(text)
    return text[start:end], start


def _is_section_number(text, m):
    """与 brief_mutate.cand_number 里那两条排除逐字同源（T2 加的）。"""
    ls = text.rfind("\n", 0, m.start()) + 1
    if text[ls:ls + 1] == "#" and not text[ls:m.start()].strip("# ").strip():
        return True
    pre = text[max(0, m.start() - 2):m.start()].strip()
    if pre and pre[-1] in "§#第v版":
        return True
    return False


EMPH_RE = re.compile(r"\*\*(.+?)\*\*", re.S)


def _emphasised_spans(text):
    """`**…**` 覆盖的区间。本仓库的写作习惯是把【承重的那个数】加粗，
    所以这是一个便宜且机械的「头条数字」代理——**不是**一个语义判断。
    它会漏掉没加粗的承重数，也会收进加粗但不承重的（`**60** 居民`）。方向未量。"""
    return [(m.start(1), m.end(1)) for m in EMPH_RE.finditer(text)]


def extract(text):
    """从一份文档里抽候选数字。返回 [(value, offset, lineno, emphasised)]"""
    spans = _emphasised_spans(text)
    out = []
    for m in NUMBER_RE.finditer(text):
        v = m.group(1)
        try:
            f = float(v)
        except ValueError:
            continue
        if f <= 0 or f >= 1000:
            continue
        if _is_section_number(text, m):
            continue
        emph = any(a <= m.start() and m.end() <= b for a, b in spans)
        out.append((v, m.start(), text.count("\n", 0, m.start()) + 1, emph))
    return out


def build_index(corpus):
    """{字面量 -> {文件}}。一次过把每份文件的小数 token 全收进来。

    ⚠ 这与"逐个数字 × 逐个文件 regex search"**逐位等价**，因为两边用的是同一个带
    数字边界的正则：`17.31` 不会命中 `117.31` / `17.312`。换索引纯粹是为了跑得完
    （逐条搜是 O(数字 × 文件)，在 850 个跟踪文件上跑不动）。
    """
    idx = {}
    for rel, txt in corpus.items():
        for m in NUMBER_RE.finditer(txt):
            idx.setdefault(m.group(1), set()).add(rel)
    return idx


def classify_copy(value, self_path, index):
    """这个字面量在树上别处有没有第二份。返回 ('code'|'doc'|'none', [命中的文件])"""
    hits = index.get(value, ())
    code_hits = sorted(r for r in hits if r != self_path and not r.lower().endswith(".md"))
    doc_hits = sorted(r for r in hits if r != self_path and r.lower().endswith(".md"))
    if code_hits:
        return "code", code_hits
    if doc_hits:
        return "doc", doc_hits
    return "none", []


def classify_instrument(section, exists):
    """小节里有没有指名一个【今天存在】的可执行件。

    返回 ('present'|'missing'|'none', [名字])。
    ⚠ present 是上界：指名了一条命令 ≠ 那条命令算的就是这个数（模块 docstring 口径 3）。
    """
    names = []
    for m in ARTIFACT_RE.finditer(section):
        n = m.group(1)
        if n not in names:
            names.append(n)
    present = [n for n in names if exists(n)]
    missing = [n for n in names if not exists(n)]
    if present:
        return "present", present
    if missing:
        return "missing", missing
    if CMD_RE.search(section):
        return "present", ["<内联命令>"]
    return "none", []


def scan(docs, corpus, root=ROOT):
    tracked = set(corpus.keys())
    index = build_index(corpus)

    def exists(rel):
        # 文档里写 `game/bench/X.gd` 或 `bench/X.gd` 都要认
        return (rel in tracked or ("game/" + rel) in tracked
                or os.path.exists(os.path.join(root, rel))
                or os.path.exists(os.path.join(root, "game", rel)))

    rows = []
    for rel in docs:
        text = corpus[rel]
        seccache = {}
        for value, pos, lineno, emph in extract(text):
            sec, sstart = section_of(text, pos)
            cp, cp_hits = classify_copy(value, rel, index)
            if sstart in seccache:
                inst, inst_names = seccache[sstart]
            else:
                inst, inst_names = classify_instrument(sec, exists)
                seccache[sstart] = (inst, inst_names)
            rows.append(dict(doc=rel, line=lineno, value=value, emph=emph, copy=cp,
                             copy_hits=cp_hits[:4], instrument=inst,
                             instrument_names=inst_names[:4]))
    return rows


def is_orphan(r):
    return r["copy"] == "none" and r["instrument"] != "present"


def _block(rows, title):
    n = len(rows)
    print("\n════ %s（n=%d）════" % (title, n))
    if not n:
        return
    print("── A. 有没有第二份拷贝（= T2 的 xref 那一刀）──")
    for k, label in (("code", "源码/数据/工具里另有一份"),
                     ("doc", "另一份文档里另有一份"),
                     ("none", "**全仓只此一份**")):
        c = sum(1 for r in rows if r["copy"] == k)
        print("  copy=%-5s %5d  (%5.1f%%)  %s" % (k, c, 100.0 * c / n, label))

    print("── B. 近旁有没有指向一条可执行命令（= 本棒要建的那条约定的现状）──")
    for k, label in (("present", "小节里指名了一个【今天存在】的可执行件 —— **上界**"),
                     ("missing", "指名了一个【不在树上】的可执行件 —— A3 撞上的形状"),
                     ("none", "小节里一条命令都没有")):
        c = sum(1 for r in rows if r["instrument"] == k)
        print("  instrument=%-7s %5d  (%5.1f%%)  %s" % (k, c, 100.0 * c / n, label))

    print("── C. 两列交叉（行=copy，列=instrument）──")
    print("        %-9s %-9s %-9s" % ("present", "missing", "none"))
    for cp in ("code", "doc", "none"):
        cells = [sum(1 for r in rows if r["copy"] == cp and r["instrument"] == i)
                 for i in ("present", "missing", "none")]
        print("  %-5s %-9d %-9d %-9d" % (cp, *cells))
    orph = [r for r in rows if is_orphan(r)]
    print("  ⇒ **孤儿格**（全仓只此一份 且 近旁无可执行件）= %d / %d = %.1f%%"
          % (len(orph), n, 100.0 * len(orph) / n))


def report(rows, docs):
    n = len(rows)
    print("=== recalc_scan · 分母 = %d 个候选测量数字 / %d 份文档 ===" % (n, len(docs)))
    print("（口径：只收小数，正则与 brief_mutate.cand_number 逐字相同；整数不在分母里）")
    if not n:
        return

    emph = [r for r in rows if r["emph"]]
    plain = [r for r in rows if not r["emph"]]
    _block(rows, "全体候选数字")
    _block(emph, "**加粗**的那些 —— 文档自己标出来的头条数字")
    _block(plain, "没加粗的那些 —— 多数是逐 seed 数据表里的一行")

    print("\n── D. 逐文档展布（不给均值；按【加粗孤儿】数排序，只列前 20）──")
    per = {}
    for r in rows:
        d = per.setdefault(r["doc"], [0, 0, 0, 0])   # 总数 / 总孤儿 / 加粗数 / 加粗孤儿
        d[0] += 1
        if is_orphan(r):
            d[1] += 1
        if r["emph"]:
            d[2] += 1
            if is_orphan(r):
                d[3] += 1
    rank = sorted(per.items(), key=lambda kv: (-kv[1][3], -kv[1][1]))
    print("  %-50s %6s %6s %7s %8s" % ("文档", "候选", "孤儿", "加粗", "加粗孤儿"))
    for doc, (tot, o, e, eo) in rank[:20]:
        print("  %-50s %6d %6d %7d %8d" % (doc, tot, o, e, eo))
    zero_e = sum(1 for _, v in per.items() if v[3] == 0)
    print("  … 共 %d 份文档，其中 **%d 份【加粗孤儿】为 0**；"
          "加粗孤儿的逐文档极值 = %d(最多，%s) / 0(最少)"
          % (len(per), zero_e, rank[0][1][3] if rank else 0, rank[0][0] if rank else "-"))

    miss = [r for r in rows if r["instrument"] == "missing"]
    if miss:
        print("\n── E. `instrument=missing`：指名了一个不在树上的可执行件 ──")
        seen = {}
        for r in miss:
            for nm in r["instrument_names"]:
                seen.setdefault(nm, []).append("%s:%d" % (r["doc"], r["line"]))
        for nm, where in sorted(seen.items(), key=lambda kv: -len(kv[1])):
            print("  %-40s %3d 个数字   e.g. %s" % (nm, len(where), where[0]))


# ────────────────────────── 负对照 ──────────────────────────
def self_test():
    """三条，全部在临时目录里造，不碰仓库。每条都要求【分类翻面】，不是"跑通了"。"""
    fails = []
    with tempfile.TemporaryDirectory() as td:
        os.makedirs(os.path.join(td, "docs"))
        os.makedirs(os.path.join(td, "tools"))
        doc = "docs/x.md"
        # A：有拷贝 / 无拷贝，同一个数
        body = "## 一节\n\n实测最小值 **17.31**。\n"
        with open(os.path.join(td, doc), "w", encoding="utf-8") as f:
            f.write(body)
        with open(os.path.join(td, "tools", "probe.py"), "w", encoding="utf-8") as f:
            f.write("THRESH = 17.31\n")
        corpus = load_corpus(td, [doc, "tools/probe.py"])
        got = scan([doc], corpus, root=td)
        a1 = got[0]["copy"] if got else "?"
        corpus2 = load_corpus(td, [doc])           # 把那份拷贝拿掉
        got2 = scan([doc], corpus2, root=td)
        a2 = got2[0]["copy"] if got2 else "?"
        print("  A 拷贝在 → copy=%s   拷贝拿掉 → copy=%s" % (a1, a2))
        if not (a1 == "code" and a2 == "none"):
            fails.append("A: 期望 code→none，实得 %s→%s" % (a1, a2))

        # B：指名存在的工具 / 指名不存在的工具
        b_ok = "## 一节\n\n跑 `tools/probe.py` 得 **17.31**。\n"
        b_no = "## 一节\n\n跑 `tools/nosuch_zz.py` 得 **17.31**。\n"
        res = []
        for body_b in (b_ok, b_no):
            with open(os.path.join(td, doc), "w", encoding="utf-8") as f:
                f.write(body_b)
            c = load_corpus(td, [doc, "tools/probe.py"])
            r = scan([doc], c, root=td)
            res.append(r[0]["instrument"] if r else "?")
        print("  B 工具在树上 → instrument=%s   换成不存在的 → instrument=%s" % (res[0], res[1]))
        if res != ["present", "missing"]:
            fails.append("B: 期望 present→missing，实得 %s" % res)

        # C：小节号不进分母（T2 那条假阳）
        c_body = "### 1.3 逐岗位在班完成次数\n\n见 §0.8 与 v2.1。\n"
        with open(os.path.join(td, doc), "w", encoding="utf-8") as f:
            f.write(c_body)
        c = load_corpus(td, [doc])
        r = scan([doc], c, root=td)
        print("  C 三个小节号（1.3 / 0.8 / 2.1）进分母的个数 = %d（必须是 0）" % len(r))
        if r:
            fails.append("C: 小节号进了分母：%s" % [x["value"] for x in r])

    if fails:
        for f in fails:
            print("  ❌ " + f)
        print("=== SELFTEST FAIL ❌ ===")
        return 1
    print("=== SELFTEST PASS ✅（三条分类翻面全部复现）===")
    return 0


def main():
    ap = argparse.ArgumentParser(description="扫描文档里的数字，量『还能不能被重新算出来』")
    ap.add_argument("--doc", action="append", help="只扫这些文档（可多次）")
    ap.add_argument("--json", help="逐条明细落盘")
    ap.add_argument("--orphans", action="store_true", help="只列孤儿格")
    ap.add_argument("--emph-only", action="store_true", help="--orphans 时只列加粗的")
    ap.add_argument("--with-analysis", action="store_true",
                    help="把 analysis/** 加回语料（默认排除，理由见 EXCLUDE_PREFIX 注释）")
    ap.add_argument("--self-test", action="store_true", help="跑负对照")
    a = ap.parse_args()

    if a.self_test:
        return self_test()

    corpus = load_corpus(with_analysis=a.with_analysis)
    docs = a.doc or sorted(p for p in corpus if p.lower().endswith(".md"))
    missing = [d for d in docs if d not in corpus]
    if missing:
        sys.exit("读不到：%s" % missing)
    rows = scan(docs, corpus)

    if a.orphans:
        for r in rows:
            if is_orphan(r) and (r["emph"] or not a.emph_only):
                print("%s:%d  %s%s  (instrument=%s %s)"
                      % (r["doc"], r["line"], r["value"], "  **" if r["emph"] else "",
                         r["instrument"], ",".join(r["instrument_names"])))
        return 0

    report(rows, docs)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(rows, f, ensure_ascii=False, indent=1)
        print("\n逐条明细 → %s" % a.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
