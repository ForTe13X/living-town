#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""brief_mutate.py — 给方法论装一个分母（docs/50 §四 的 H4，S2 补交）。

本仓库通篇在报「第 N 次被自己的数据推翻」。**N 是分子。分母从来没有人算过。**
外审的原话（docs/50 §四 转引）：「24 不是质量指标……你不知道分母。」

## 这个工具做什么

往一份**已经合入的 brief** 里注入若干条**已知为假**的断言，派一根只读棒去执行
「指出这份 brief 哪里是错的」，然后拿注入清单去对回执，量**发现率**。

## 这个工具刻意做的三件事，每一件都是为了不让那个数字虚高

1. **分层（stratify），不合并。** 五类注入的**发现成本相差一个数量级**：
   改一个行号可以 `sed -n` 一秒钟证伪；改一个基线数字要重跑一次 60 天 × 12 seed 的网格。
   把它们汇总成一个「30/30」会让最便宜的那一层把整个数字抬上去。
   ⇒ 本工具**逐层报**，并且**拒绝**打印一个合并的点估计（`--pool` 才会打，且带警告）。

2. **区分「钥匙能自证」与「钥匙只能自称」。** L1/L2/L3 三层，工具能当场证明
   「原来那句是真的、改完那句是假的」（读文件 / 查存在性 / grep 全仓）；
   L4/L5/L6 三层做不到——它们要一次真的测量才能判。
   ⇒ 每条注入都带 `auto_verified`，报告里**分开算**。
   一条自己都没被证明为假的注入，被「发现」了也不构成证据。

3. **给区间，不给点估计。** 30/30 的 Wilson 95% 区间是 [0.885, 1.000]——
   而它的**下界**才是能拿出去说的那个数。本 session 已经吃过一次亏：
   docs/67 §〇 记着「把 `#01` 的 1.3% 当点估计用，而 1.3% 是 Wilson 下界(1.3-15.8%)」。
   ⇒ `score` 永远打区间；`--point` 不存在。

## 这个工具**测不到**什么（docs/41 §2.5 的 does_not_detect，写在最前面）

- **注入是「被宣布过的」。** 棒子知道自己在找错（brief 里有一节要求它交这个）。
  真实的漏检发生在**没有人在找**的时候。⇒ 本工具量到的发现率是**上界**，
  它与「野生错误的发现率」之间隔着一个无法从这个实验里估出来的因子。
- **注入是合成的。** 真实的错误分布未知；我按 docs/50 §四 列的五类造，而那五类
  本身是当初拍的，不是从错误样本里学的。⇒ 分层比例不可信，**只有逐层的数可信**。
- **它不测「错误活了多久」。** 回溯法（数「这条错的断言是被当场抓住的，还是几波之后
  别人抓住的」）测的是另一个量，而那个量不需要这个工具，数据已经在树上。两者互补。
- **它不测不可证伪的句子。** brief 里大量的话（「这条路可能更贵」「建议先量再动」）
  无真假可言，压根不进分母。⇒ 分母是「**可证伪的断言数**」，不是「句子数」。

## 用法

    # 1) 注入（写出一份变异 brief + 一份答案钥匙；两个文件都不进 docs/）
    python tools/brief_mutate.py inject --brief docs/67-wave-r-plan.md \\
        --out /tmp/mut.md --key /tmp/key.json --seed 7 --count 8

    # 2) 派棒执行变异 brief（钥匙不给它看）

    # 3) 对分（拿回执去撞钥匙）
    python tools/brief_mutate.py score --key /tmp/key.json --receipt /tmp/receipt.md

    # 自检：证明注入器本身在这棵树上真的能造出「原来真、改完假」的断言
    python tools/brief_mutate.py selftest --brief docs/67-wave-r-plan.md

退出码：0 = 正常；1 = 自检失败 / 参数错误。
"""
import argparse
import io
import json
import math
import os
import random
import re
import subprocess
import sys

try:                                    # Windows 控制台默认 GBK，直接 print 中文会 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ── 分层定义 ────────────────────────────────────────────────────────────────
# cost = 一根棒要花多少力气才能证伪它。这一列是本工具存在的全部理由：
#        把 cost 不同的东西汇总成一个发现率，得到的数没有意义。
STRATA = {
    "L1_lineno":  dict(cost="grep",  auto=True,  desc="行号漂移（`File.gd:NNN` 指到别处）"),
    "L2_path":    dict(cost="ls",    auto=True,  desc="文件名/路径不存在"),
    "L3_symbol":  dict(cost="grep",  auto=True,  desc="符号名全仓不存在"),
    "L4_number":  dict(cost="rerun", auto=False, desc="把基线/余量数字改掉（要重跑才知道）"),
    "L5_gate":    dict(cost="rerun", auto=False, desc="声称某道门会红，而它不会"),
    "L6_accept":  dict(cost="judge", auto=False, desc="不可满足的验收条目"),
}

CORRECTION_MARKERS = [
    "错", "假", "不成立", "证伪", "更正", "纠正", "对不上", "查无", "不存在",
    "实际是", "实测", "撤回", "漂", "并非", "没有这", "找不到",
]

# ── 小工具 ──────────────────────────────────────────────────────────────────


def _read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def _exists(rel):
    return os.path.exists(os.path.join(REPO, rel))


def _linecount(rel):
    try:
        with open(os.path.join(REPO, rel), "r", encoding="utf-8", errors="replace") as f:
            return sum(1 for _ in f)
    except OSError:
        return -1


def _line_at(rel, n):
    try:
        with open(os.path.join(REPO, rel), "r", encoding="utf-8", errors="replace") as f:
            for i, ln in enumerate(f, 1):
                if i == n:
                    return ln.strip()
    except OSError:
        pass
    return None


def _grep_repo(token):
    """token 在【已跟踪的】树里出现几次。用 git grep，避免扫进 .godot / scratchpad。"""
    try:
        r = subprocess.run(["git", "grep", "-c", "-F", "--", token],
                           cwd=REPO, capture_output=True, text=True, errors="replace")
    except OSError:
        return -1
    if r.returncode not in (0, 1):
        return -1
    return sum(int(l.rsplit(":", 1)[1]) for l in r.stdout.splitlines() if ":" in l)


_NUMERIC = re.compile(r"^\d+(?:\.\d+)?$")


def find_value(needle, hay, strict=True):
    """在回执里找一个"值"。`strict=False` 是 S2 原样的裸子串匹配（`--loose` 恢复它）。

    **为什么要有 strict**（T2 复现 S2 自己的负对照时定位到的，docs/77 §一）：
    S2 记的机制是「一个两位小数在长文档里本来就会撞上，邻近恰好有『实测/更正』这类词」。
    **两句都不对。** 那一次假阳（`0.8 → 1.3` 撞 docs/68）的实际成因是**两次无边界子串命中**：
      · 假值 `1.3` 命中的是 **`### 1.3 逐岗位…` 这个小节编号**，不是任何一个测量值；
      · ±250 窗口里**一个更正语都没有**，真正触发的是另一条分支 `真值 in 窗口`,
        而真值 `0.8` 命中的是 **`0.887` / `0.886` 里面的那三个字符**。
    ⇒ 修法是给纯数字的值加数字边界，并且不认小节编号。
    """
    if not strict or not _NUMERIC.match(needle):
        yield from re.finditer(re.escape(needle), hay)
        return
    for m in re.finditer(r"(?<![\d.])" + re.escape(needle) + r"(?![\d.])", hay):
        ls = hay.rfind("\n", 0, m.start()) + 1
        if hay[ls:m.start()].strip().rstrip(".").replace("#", "") == "" and hay[ls:ls + 1] == "#":
            continue                         # `### 1.3 逐岗位…` —— 小节编号，不是测量值
        yield m


def wilson(k, n, z=1.96):
    """Wilson 得分区间。n=0 时返回 (0,1)——「这个网格分辨不出」，不是「零」（docs/41 §5）。"""
    if n <= 0:
        return (0.0, 1.0)
    p = k / n
    d = 1.0 + z * z / n
    c = p + z * z / (2 * n)
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (max(0.0, (c - h) / d), min(1.0, (c + h) / d))


# ── 注入器：每个函数返回 [(旧串, 新串, meta)] 候选列表 ───────────────────────
FILE_RE = re.compile(r"\b((?:game|tools|docs|analysis|scripts|bench)/[\w./-]+?\.(?:gd|py|sh|json|md|tscn))(?::(\d+))?\b")
GDCITE_RE = re.compile(r"\b(\w+\.(?:gd|py|sh)):(\d+)\b")
SYMBOL_RE = re.compile(r"`(_?[A-Za-z][A-Za-z0-9_]{4,})`")
NUMBER_RE = re.compile(r"(?<![\w.])(\d+\.\d+)(?![\w.])")


def cand_lineno(text):
    out = []
    for m in GDCITE_RE.finditer(text):
        base, num = m.group(1), int(m.group(2))
        rel = None
        for pref in ("game/scripts/", "game/bench/", "tools/", "game/scripts/"):
            if _exists(pref + base):
                rel = pref + base
                break
        if rel is None or _linecount(rel) < num + 60:
            continue
        new = num + 37                       # 固定偏移：可复现，且足够远
        if _line_at(rel, num) == _line_at(rel, new):
            continue                         # 两行内容一样 ⇒ 这条注入不是假的，跳过
        out.append((m.group(0), "%s:%d" % (base, new),
                    dict(stratum="L1_lineno", file=rel, true_value=num, false_value=new,
                         true_line=_line_at(rel, num), false_line=_line_at(rel, new))))
    return out


def cand_path(text):
    out = []
    for m in FILE_RE.finditer(text):
        rel = m.group(1)
        if m.group(2) or not _exists(rel):
            continue
        stem, ext = os.path.splitext(rel)
        fake = stem + "_v2" + ext
        if _exists(fake):
            continue
        out.append((rel, fake,
                    dict(stratum="L2_path", true_value=rel, false_value=fake)))
    return out


def cand_symbol(text):
    out = []
    for m in SYMBOL_RE.finditer(text):
        sym = m.group(1)
        if _grep_repo(sym) < 3:              # 出现太少 ⇒ 不是一个"棒子会去 grep"的符号
            continue
        fake = sym + "_ex"
        if _grep_repo(fake) != 0:
            continue
        out.append(("`%s`" % sym, "`%s`" % fake,
                    dict(stratum="L3_symbol", true_value=sym, false_value=fake)))
    return out


def cand_number(text):
    out = []
    for m in NUMBER_RE.finditer(text):
        v = m.group(1)
        try:
            f = float(v)
        except ValueError:
            continue
        if f <= 0 or f >= 1000:
            continue
        # ⚠ T2 加：小节号 / 标题编号不是「基线数字」。
        # B1 的第一版把 docs/41 的 `§1.5 读仓库纪律` 注成了 `§2.4` —— 它确实是假的，
        # 但证伪它只要 `grep '## '` 一秒钟，而 L4 这一层的成本标的是 `rerun`。
        # 把它留在 L4 里，就是在【同一层内部】重犯"把差两个数量级的成本合并"那个错。
        ls = text.rfind("\n", 0, m.start()) + 1
        if text[ls:ls + 1] == "#" and not text[ls:m.start()].strip("# ").strip():
            continue                          # `### 1.3 逐岗位…`
        if text[max(0, m.start() - 2):m.start()].strip() and \
           text[max(0, m.start() - 2):m.start()].strip()[-1] in "§#第v版":
            continue                          # `§1.5` / `第1.5` / `v1.5`
        # 朝"更乐观"的方向改：余量变大、满足率变高——这正是现实里最常见的漂移方向
        nf = round(f * 1.6, len(v.split(".")[1]))
        new = ("%." + str(len(v.split(".")[1])) + "f") % nf
        if new == v:
            continue
        out.append((v, new, dict(stratum="L4_number", true_value=v, false_value=new)))
    return out


# ⚠ 每一条都必须是【本仓库文档里已经明写为假】的断言，否则注入就变成了我的自称。
# 括号里注的是"哪份文档的哪一节把它证伪了"——判卷的人照着那一节就能复核。
GATE_CLAIMS = [
    # docs/41 §2 盲区①：backend=null ⇒ AIBackend.decide() 根本不进；S0 是必要不充分条件
    "⚠️ 注意：这条一旦破，`tools/ci.sh` 第 4 步的 S0 门会**当场变红**——所以不必另造对照。",
    # docs/41 §6：视觉门只覆盖渲染那条路，不覆盖仿真/经济/模型路
    "⚠️ 注意：`tools/ci.sh` 的视觉门会覆盖这一条，改坏了它会在第 6 步变红。",
    # docs/41 §3：金标只在【蓄意移动】时才是证据，"天然守着"是反的
    "⚠️ 注意：这一改动会移动金标，所以第 4 步天然守着它，无需自造负对照。",
    # docs/41 §2 第 4d 关：BackendGate 只守 硬不变量/两跑一致/无饿穿 三条臂，"不守别的"（原文）
    "⚠️ 注意：`BackendGate`（第 4d 关）会覆盖模型路上的这类回归，不必另写对照。",
    # docs/41 §2：Sim._ready() 在 S0 网格的评分过程中【从不执行】（3 seed 只跑 1 次，且在判决之后）
    "⚠️ 注意：`Sim._ready()` 在 S0 网格里每个 seed 都会跑一次，所以 `_load_data()` 的改动天然被金标守住。",
    # docs/41 §2.5 / docs/73 P5：lod_verify 比的是自己跟自己一致，一条不变量都不评估
    "⚠️ 注意：`lod_verify` 在 CI 里跑 N=48，所以大 N 下的硬不变量也一并测过了。",
]
ACCEPT_CLAIMS = [
    # docs/41 §2.5 第三个盲区：tick≈0 的新世界会让这一类判据失去判别力；#40 还要 SUPPLY_MIN_DAYS=60
    "**验收：证明该性质在 `tick=0` 的新世界上同样成立**（不许用暖机）。",
    # docs/41 §2 盲区①：backend=null 下模型路根本不进，抓不到任何模型路回归
    "**验收：给出该判据在 `backend=null` 下抓到模型路径回归的一次实测。**",
    # docs/41 §6 盲区①：--shot 永远拍不到 emote/气泡
    "**验收：用 `--shot` 拍一张带气泡（emote）的截图作为证据。**",
    # docs/41 §6 盲区③：--shot 只返回内容区，letterbox 黑边一条都拍不出来
    "**验收：用 `--shot` 拍一张能看见 letterbox 黑边的截图作为证据。**",
    # docs/41 §6 盲区⑧：容器 5.3-10.8 fps < 12.5 ticks/s ⇒ 两个 tick 之间不存在帧
    "**验收：用 docker 录屏证明插值生效（两个 tick 之间的中间帧）。**",
    # docs/41 §6 getbbox 陷阱：Pillow ≥11.3 对 RGBA 只看 alpha ⇒ 这条断言是空真的
    "**验收：用 `ImageChops.difference(a,b).getbbox() is None`（RGBA）证明逐像素未变。**",
]


def cand_appended(text, pool, stratum):
    """在若干个二级标题后面各插一句。返回 (锚点, 锚点+插入句, meta)。"""
    out = []
    heads = [m for m in re.finditer(r"^#{2,3} .*$", text, re.M)]
    for i, m in enumerate(heads):
        claim = pool[i % len(pool)]
        anchor = m.group(0)
        out.append((anchor, anchor + "\n\n" + claim,
                    dict(stratum=stratum, true_value="(无此断言)", false_value=claim)))
    return out


def build_candidates(text):
    c = []
    c += cand_lineno(text)
    c += cand_path(text)
    c += cand_symbol(text)
    c += cand_number(text)
    c += cand_appended(text, GATE_CLAIMS, "L5_gate")
    c += cand_appended(text, ACCEPT_CLAIMS, "L6_accept")
    return c


def do_inject(a):
    text = _read(a.brief)
    cands = build_candidates(text)
    by_s = {}
    for old, new, meta in cands:
        by_s.setdefault(meta["stratum"], []).append((old, new, meta))
    if not by_s:
        print("❌ 这份 brief 里找不到任何可注入的锚点（没有文件引用 / 行号 / 反引号符号 / 小数）")
        return 1

    rng = random.Random(a.seed)
    strata = a.strata.split(",") if a.strata else sorted(by_s)
    picked, per = [], max(1, a.count // max(1, len([s for s in strata if by_s.get(s)])))
    used_new, used_lines = set(), set()
    for s in strata:
        pool = by_s.get(s, [])
        if not pool:
            print("  ⚠  层 %s 在这份 brief 上没有锚点 —— **这一层测不到，不是 0**" % s)
            continue
        rng.shuffle(pool)
        seen_old = set()
        for old, new, meta in pool:
            if len(picked) >= a.count or sum(1 for p in picked if p[2]["stratum"] == s) >= per:
                break
            if old in seen_old or text.count(old) != 1:
                continue                     # 只改**唯一出现**的锚点，免得一次改到多处
            line = text.count("\n", 0, text.index(old)) + 1
            if not a.legacy:
                # (T2 加的两条，理由见 docs/77 §二·2；`--legacy` 恢复 S2 原样)
                # ① 同一句插入语不许注两遍：两条注入的 false_value 逐字相同时，
                #    对分器无法把它们分开，而它们也不是两个独立的观测。
                if new in used_new:
                    continue
                # ② 两条注入不许挤在同一行/相邻行：A1 的第一版把 `×1.00` 与 `×0.50`
                #    注进了同一句话，抓到一个几乎必然抓到另一个 ⇒ 不是独立样本。
                if any(abs(line - u) < a.min_gap for u in used_lines):
                    continue
            seen_old.add(old)
            used_new.add(new)
            used_lines.add(line)
            meta = dict(meta, brief_line=line)
            picked.append((old, new, meta))

    out = text
    key = []
    for i, (old, new, meta) in enumerate(picked, 1):
        out = out.replace(old, new, 1)
        meta = dict(meta)
        meta["id"] = "M%02d" % i
        meta["auto_verified"] = bool(STRATA[meta["stratum"]]["auto"])
        meta["cost"] = STRATA[meta["stratum"]]["cost"]
        key.append(meta)

    with open(a.out, "w", encoding="utf-8") as f:
        f.write(out)
    with open(a.key, "w", encoding="utf-8") as f:
        json.dump(dict(brief=a.brief, seed=a.seed, injections=key), f, ensure_ascii=False, indent=1)

    print("注入 %d 条 → %s   钥匙 → %s" % (len(key), a.out, a.key))
    for k in key:
        print("  %s [%-10s cost=%-5s auto=%s] %s → %s"
              % (k["id"], k["stratum"], k["cost"], "Y" if k["auto_verified"] else "N",
                 str(k["true_value"])[:44], str(k["false_value"])[:44]))
    n_auto = sum(1 for k in key if k["auto_verified"])
    print("\n⚠ 其中 %d 条是【工具能自证为假】的，%d 条只能自称 —— 报告里必须分开算。"
          % (n_auto, len(key) - n_auto))
    return 0


def do_score(a):
    key = json.load(open(a.key, encoding="utf-8"))
    receipt = _read(a.receipt)
    manual = set((a.detected or "").split(",")) - {""}

    rows = []
    for k in key["injections"]:
        fv, tv = str(k["false_value"]), str(k["true_value"])
        hit, how = False, ""
        if k["id"] in manual:
            hit, how = True, "人工判定"
        else:
            strict = not a.loose
            for m in find_value(fv[:60], receipt, strict):
                w = receipt[max(0, m.start() - 250): m.end() + 250]
                # ⚠ 两条分支分开报：S2 那次假阳走的是【真值】分支，而打印的字串
                #   把两条合成了一句「更正语/真值」，于是机制被记反了。
                mk = [x for x in CORRECTION_MARKERS if x in w]
                if mk:
                    hit, how = True, "假值出现 + 邻近更正语「%s」" % mk[0]
                    break
                if any(True for _ in find_value(tv[:40], w, strict)):
                    hit, how = True, "假值出现 + 邻近真值（**这条最容易假阳，必须人工复核**）"
                    break
            if not hit and tv not in ("(无此断言)",) and len(tv) > 3:
                for m in find_value(tv[:60], receipt, strict):
                    w = receipt[max(0, m.start() - 250): m.end() + 250]
                    if any(True for _ in find_value(fv[:40], w, strict)):
                        hit, how = True, "回执里真假值同段出现"
                        break
        rows.append((k, hit, how))

    print("=== brief 变异测试 · 对分 ===")
    print("brief=%s  seed=%s  回执=%s" % (key["brief"], key["seed"], a.receipt))
    print("\n%-5s %-10s %-6s %-5s %-6s %s" % ("id", "层", "成本", "自证", "抓到", "依据"))
    for k, hit, how in rows:
        print("%-5s %-10s %-6s %-5s %-6s %s"
              % (k["id"], k["stratum"], k["cost"], "Y" if k["auto_verified"] else "N",
                 "✅" if hit else "❌", how))

    print("\n── 逐层（**不合并**：五层的证伪成本相差一个数量级）──")
    print("%-10s %-6s %-8s %-22s %s" % ("层", "成本", "k/n", "Wilson 95%", "说明"))
    for s in sorted(set(k["stratum"] for k, _, _ in rows)):
        sub = [(k, h) for k, h, _ in rows if k["stratum"] == s]
        k_, n_ = sum(1 for _, h in sub if h), len(sub)
        lo, hi = wilson(k_, n_)
        print("%-10s %-6s %-8s [%.3f, %.3f]      %s"
              % (s, STRATA[s]["cost"], "%d/%d" % (k_, n_), lo, hi, STRATA[s]["desc"]))

    auto = [(k, h) for k, h, _ in rows if k["auto_verified"]]
    ka, na = sum(1 for _, h in auto if h), len(auto)
    lo, hi = wilson(ka, na)
    print("\n【只算工具能自证为假的那些】%d/%d   Wilson 95%% = [%.3f, %.3f]" % (ka, na, lo, hi))
    print("  其余 %d 条的「假」是我自己声称的 —— 抓到它们不构成对方法论的证据。" % (len(rows) - na))

    if a.pool:
        kk, nn = sum(1 for _, h, _ in rows if h), len(rows)
        lo, hi = wilson(kk, nn)
        print("\n⚠ 合并值（你要了才打）：%d/%d  Wilson 95%% = [%.3f, %.3f]" % (kk, nn, lo, hi))
        print("  ⚠ 它没有意义：便宜的那一层会把它抬上去。逐层看上面那张表。")

    print("\n⚠ 这个数是【上界】：注入是被宣布过的（棒子知道自己在找错），")
    print("  而野生的错误活在没有人找的地方。两者之间的因子，这个实验估不出来。")
    print("⚠ **自动匹配会假阳**，而且我量过：拿一份【根本没见过这些注入】的回执去撞钥匙")
    print("  （`--key`=docs/67 的注入 vs `--receipt`=docs/68），L4 那一层报出 1/2 —— 因为")
    print("  一个两位小数在一份长文档里本来就会撞上，邻近又恰好有『实测/更正』这类词。")
    print("  ⇒ **L4/L5/L6 的每一个 ✅ 都必须人工复核那一段**；自证的 L1/L2/L3 在同一次")
    print("  负对照上是 0/4，那三层的自动判读可以信。")
    return 0


def do_selftest(a):
    text = _read(a.brief)
    cands = build_candidates(text)
    by_s = {}
    for _, _, m in cands:
        by_s[m["stratum"]] = by_s.get(m["stratum"], 0) + 1
    print("=== selftest · %s ===" % a.brief)
    auto_empty, auto_total = 0, 0
    for s in STRATA:
        n = by_s.get(s, 0)
        note = ""
        if STRATA[s]["auto"]:
            auto_total += 1
            if n == 0:
                auto_empty += 1
                note = "  ← 这份 brief 上【测不到这一层】（不是 0 分，是没有分母）"
        print("  %-10s 锚点 %3d  %s%s" % (s, n, STRATA[s]["desc"], note))
    # 逐条验证 L1/L2/L3 的「原来真、改完假」
    checked = 0
    for old, new, m in cands:
        if m["stratum"] == "L2_path":
            assert _exists(m["true_value"]) and not _exists(m["false_value"]), m
            checked += 1
        elif m["stratum"] == "L3_symbol":
            assert _grep_repo(m["true_value"]) > 0 and _grep_repo(m["false_value"]) == 0, m
            checked += 1
        elif m["stratum"] == "L1_lineno":
            assert m["true_line"] != m["false_line"], m
            checked += 1
    print("  自证通过：%d 条 L1/L2/L3 注入满足「原来那句真、改完那句假」" % checked)
    if auto_empty:
        print("  ⚠ %d/%d 个可自证的层在这份 brief 上没有锚点 —— 报告里那几层写「未测」，"
              "**不要**写 0/0 然后当成满分。" % (auto_empty, auto_total))
    if auto_empty == auto_total or checked == 0:
        print("❌ selftest FAIL：这份 brief 上一条能自证为假的注入都造不出来 ⇒ 拿它做实验只会量到我的自称")
        return 1
    print("=== selftest PASS ===")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("inject")
    p.add_argument("--brief", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--count", type=int, default=12)
    p.add_argument("--strata", default="")
    p.add_argument("--min-gap", dest="min_gap", type=int, default=2,
                   help="两条注入之间至少隔几行（默认 2；免得同一句里注两条，那不是两个独立样本）")
    p.add_argument("--legacy", action="store_true",
                   help="恢复 S2 原样的挑选（允许重复插入语、允许同一行两条）—— 只为复现 docs/73 的数")
    p.set_defaults(fn=do_inject)

    p = sub.add_parser("score")
    p.add_argument("--key", required=True)
    p.add_argument("--receipt", required=True)
    p.add_argument("--detected", default="", help="人工判定抓到的 id，逗号分隔（自动匹配保守，漏了手工补）")
    p.add_argument("--pool", action="store_true", help="额外打印一个合并值（带警告）")
    p.add_argument("--loose", action="store_true",
                   help="恢复 S2 原样的裸子串匹配（会让 `0.8` 命中 `0.887`）—— 只为复现 docs/73 的数")
    p.set_defaults(fn=do_score)

    p = sub.add_parser("selftest")
    p.add_argument("--brief", required=True)
    p.set_defaults(fn=do_selftest)

    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
