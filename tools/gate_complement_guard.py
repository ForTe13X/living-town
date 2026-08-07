#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""互补性守卫（complementarity guard）—— **门**，不是量具。

它守的是编号 94 §二·2 结尾那条被点名、但当时没有任何机器在维护的性质：

    全 CI 口径下"整条 CI 都抓不到"的不变量条数是 **0**，
    **而那个 0 之所以成立，只因为 4c 的 betray 轨与 4a 的 N=16 恰好补上了第 4 步的洞。**
    这四条 track 是 D 波、K/L 波各自为了别的理由加的，**没有任何机制在维护这份互补关系**。
    谁哪天为了省钱把 4c 从 CI 里拿掉（它的 betray 轨是 #22/#23/#24 **唯一**的活输入），
    三条硬不变量当场退化成纸，**而每一步都还是绿的**。

── 为什么这一道能上门，而 `gate_fixture_audit.py` 本身不能 ────────────────────
X3 明确把普查工具挡在 `ci.sh` 外面，理由逐字照抄 `recalc_registry.json` 划的那条界线：
**能上门 = HEAD 这棵树的性质；不能上门 = 随语料移动的快照。**
「#29 的 aid_accepted 这一跑是 9 还是 1」正是后者——谁调一次平衡它就动。

本门**不重量那件事**。它把那次昂贵普查的结果当成一份**烘出来的锚**
（`tools/gate_complement_ledger.json`，与 `golden_digests.json` / `modelpath_anchor.json` 同一个形状），
然后每次 CI 只做一件**纯结构**的事：

    **把锚里记下的"谁是某条不变量【唯一】的活输入来源"，跟今天的 `tools/ci.sh` /
    `game/bench/DetGate.gd` 现读一遍，看那个来源还在不在、有没有变弱。**

⇒ 它读的两侧都是 HEAD 这棵树的文本，判决与 seed / 平衡 / 语料统统无关，
   在任何人的机器上逐字节同一个结果，**约 0.02 s、不进 godot**。

── 三条硬判据（红）与两条只打印（警告）──────────────────────────────────────
红 ①  锚里有某条不变量的活输入来源**是空集** ⇒ 这条不变量整条 CI 都不可能变红。
       ⚠ 烘锚那一刻若已经存在这样的不变量，**那是发现不是 bug**——它会在这里被点名，
         而不是被悄悄放过。今天这一栏是空的（见 `_meta.dead_at_bake`）。
红 ②  某条不变量的**全部**活输入来源都从 `ci.sh` 里消失了（典型：有人删掉第 4c 步）。
       信息里会点名**哪几条不变量会因此退化成纸**，而不只是"少了一步"。
红 ③  这些来源的夹具参数**变弱**了（天数/seed 数低于烘锚时）。**变强不红**——
       抬天数是本波正在做的事，一道会因为夹具变好而变红的门比没有门更坏（docs/41 §6）。
警告 ④ 某个来源没了，但它守的每条不变量在别处都还有活输入 ⇒ 只是冗余被削掉，打印不判红。
警告 ⑤ `Invariants.gd` 里出现了锚不认识的新不变量 ⇒ 它的夹具没人普查过。
       **默认只打印**：`game/bench/Invariants.gd` 不在造这道门的那根棒的行里，
       让别人写一条新不变量就把 CI 弄红 = 拿红色惩罚一个正当改动，正是 docs/41 §6
       点名的"训练所有人忽略红色"的那种门。`LT_COMPLEMENT_STRICT=1` 可以让 ④⑤ 也红。

用法：
    python tools/gate_complement_guard.py                # 门（ci.sh 每次跑）
    python tools/gate_complement_guard.py --self-test    # 六条负对照，不需要 godot
    # 重烘锚（需要 godot，约 12 min）：
    GODOT=... python tools/gate_fixture_audit.py --run --bake-ledger
"""
import argparse
import json
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LEDGER = os.path.join(ROOT, "tools", "gate_complement_ledger.json")
_UNSET = object()   # gate() 的 cur_game_tree 默认哨兵：未传 ⇒ 现读 git；显式传 None ⇒ "git 读不到"（fail-closed）


def _head_game_tree():
    """现读 `git rev-parse HEAD:game`（committed game/ 的 tree sha）。读不到 / 非零退出 ⇒ None
    （**绝不返回空串冒充成功**）。判决与 seed / 平衡无关，逐字节确定，约 0.01 s、不进 godot。"""
    try:
        r = subprocess.run(["git", "rev-parse", "HEAD:game"], cwd=ROOT,
                           capture_output=True, text=True)
    except OSError:
        return None
    sha = (r.stdout or "").strip()
    return sha if (r.returncode == 0 and sha) else None


def check_ledger_freshness(ledger, cur_game_tree):
    """AE2 P0.①（外审 2026-08-06 21:00 §三 P1 第 4 点）：consumer 侧的【依赖树闭环】。

    比锚里的 `_meta.baked_game_tree` 与当前 `HEAD:game`。不符 / 缺失 / 读不到 ⇒ 返回红原因，否则 None。

    ⚠ 旧版守卫**只打印 metadata、不比当前依赖树** ⇒ 锚的 `baked_game_tree` 与当前 `HEAD:game`
      不符时**照样返 0**（fail-open：它照着一份烘自另一棵 game 树的测量在守，而没人被告知）。
      这里把它变成 fail-closed，并在信息里**点名 stale + 叫重烘**（别打谜语）。
    """
    baked = (ledger.get("_meta") or {}).get("baked_game_tree")
    rebake = "请重烘：GODOT=… python tools/gate_fixture_audit.py --run --bake-ledger"
    if not baked:
        return ("锚缺 _meta.baked_game_tree ⇒ 无法证明它烘自当前 game 树（fail-closed）。%s" % rebake)
    if not cur_game_tree:
        return ("读不到当前 HEAD:game（git rev-parse 失败）⇒ 无法确认锚是否新鲜（fail-closed）。%s" % rebake)
    if baked != cur_game_tree:
        return ("锚 STALE：baked_game_tree=%s ≠ 当前 HEAD:game=%s ⇒ 锚烘自另一棵 game 树，"
                "它记录的活输入来源可能与当前依赖树不符。%s"
                % (baked[:12], cur_game_tree[:12], rebake))
    return None


def _read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def strip_comments(src, kind):
    """把整行注释剔掉再匹配。

    ⚠ 这一步不是装饰：`tools/ci.sh` 里**注释提到某个 bench 的次数远多于真正调用它的次数**
    （第 4a 步那一大段历史注释里 `Harness` 出现好几次）。不剔注释的话，
    "把第 4c 步整段注释掉"这种改法会被判成"还在"——门当场变成纸。
    """
    out = []
    for line in src.splitlines():
        s = line.lstrip()
        if kind == "sh" and s.startswith("#"):
            continue
        if kind == "gd" and s.startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)


def seeds_count(spec):
    """`1-12` → 12 · `1-4` → 4 · `1,3,5` → 3。看不懂就返回 -1（调用方按"无法判定"处理）。"""
    spec = str(spec).strip()
    n = 0
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.fullmatch(r"(\d+)-(\d+)", part)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            if b < a:
                return -1
            n += b - a + 1
        elif part.isdigit():
            n += 1
        else:
            return -1
    return n if n else -1


def ci_defaults(src):
    """现读 `${CI_XXX:-默认}`。同名多处取**最后一处**（bash 里后写的那个才是生效的赋值）。"""
    out = {}
    for var, val in re.findall(r"\$\{(CI_[A-Z_0-9]+):-([^}]*)\}", src):
        out[var] = val
    return out


def live_invariant_ids(src):
    """从 `Invariants.gd` 现抓 `_chk(<id>, …)` 的 id 集合。抓不到返回 None（= 无法判定，不假红）。"""
    ids = sorted({int(x) for x in re.findall(r"_chk\(\s*(\d+)", src)})
    return ids or None


class Tree(object):
    """被检查的那棵树。测试里可以喂合成内容，正式跑时读真文件。"""

    def __init__(self, files=None):
        self._files = files or {}

    def text(self, rel):
        if rel in self._files:
            return self._files[rel]
        p = os.path.join(ROOT, rel.replace("/", os.sep))
        if not os.path.isfile(p):
            return None
        return _read(p)


def check_fixture(tree, tag, spec):
    """返回 (ok, [失败原因…], [警告…])。ok=False ⇒ 这个夹具已经不能再算作活输入来源。"""
    bad, warn = [], []
    for req in spec.get("requires", []):
        rel = req["file"]
        raw = tree.text(rel)
        if raw is None:
            bad.append("%s：读不到 %s" % (tag, rel))
            continue
        body = strip_comments(raw, "sh" if rel.endswith(".sh") else "gd")
        if not re.search(req["pattern"], body):
            bad.append("%s：%s 里已经找不到 `%s` —— %s"
                       % (tag, rel, req["pattern"], req.get("why", "")))
    ci_raw = tree.text("tools/ci.sh")
    live = ci_defaults(strip_comments(ci_raw, "sh")) if ci_raw is not None else {}
    for var, floor in (spec.get("floors") or {}).items():
        kind, baked = floor["kind"], floor["value"]
        got = live.get(var)
        if got is None:
            bad.append("%s：ci.sh 里没有 ${%s:-…} 了（烘锚时它是 %s）" % (tag, var, baked))
            continue
        cur = int(got) if kind == "int" and str(got).strip().isdigit() else (
            seeds_count(got) if kind == "seeds" else -1)
        if cur < 0:
            warn.append("%s：${%s:-%s} 解不出数量，无法判定强弱" % (tag, var, got))
        elif cur < baked:
            bad.append("%s：%s 从 %s 降到 %s ⇒ 夹具变弱（变强不判红，只有变弱才红）"
                       % (tag, var, baked, cur))
    return (not bad), bad, warn


def run_gate(tree, ledger, strict=False):
    fixtures = ledger["fixtures"]
    providers = ledger["providers"]
    fails, warns, notes = [], [], []

    status = {}
    for tag, spec in fixtures.items():
        ok, bad, warn = check_fixture(tree, tag, spec)
        status[tag] = ok
        warns.extend(warn)
        if not ok:
            notes.extend(bad)

    # ── 红 ①：烘锚那一刻就已经处处空转的 ────────────────────────────────────
    dead_at_bake = sorted(int(i) for i, p in providers.items() if not p)
    if dead_at_bake:
        fails.append("锚里有 %d 条不变量【没有任何夹具给它活输入】⇒ 整条 CI 都不可能因它变红：%s"
                     % (len(dead_at_bake), ", ".join("#%02d" % i for i in dead_at_bake)))

    # ── 红 ②③：某条不变量的全部来源都没了 / 变弱了 ──────────────────────────
    orphaned = {}
    for iid, provs in sorted(providers.items(), key=lambda kv: int(kv[0])):
        if not provs:
            continue
        alive = [p for p in provs if status.get(p, False)]
        if not alive:
            orphaned.setdefault(tuple(sorted(provs)), []).append(int(iid))
    for provs, ids in sorted(orphaned.items(), key=lambda kv: kv[1][0]):
        fails.append("%s 已经不成立 ⇒ %s 从此在整条 CI 上不可能变红（它%s唯一的活输入来源）"
                     % ("、".join(provs), ", ".join("#%02d" % i for i in ids),
                        "是它们" if len(provs) == 1 else "们是它们"))

    # ── 警告 ④：来源没了但没有孤儿（冗余被削掉）────────────────────────────
    orphan_provs = {p for provs in orphaned for p in provs}
    for tag, ok in sorted(status.items()):
        if not ok and tag not in orphan_provs:
            warns.append("%s 已经不成立，但它守的每条不变量在别处仍有活输入 ⇒ 只是冗余被削掉，不判红"
                         % tag)

    # ── 警告 ⑤：锚不认识的新不变量 ─────────────────────────────────────────
    inv_raw = tree.text("game/bench/Invariants.gd")
    if inv_raw is None:
        warns.append("读不到 Invariants.gd ⇒ 跳过「新不变量」核对")
    else:
        live_ids = live_invariant_ids(inv_raw)
        if live_ids is None:
            warns.append("Invariants.gd 里抓不到 `_chk(<id>` ⇒ 跳过「新不变量」核对（判据可能改了写法）")
        else:
            known = {int(i) for i in ledger.get("invariant_kinds", {})} | {int(i) for i in providers}
            unknown = sorted(set(live_ids) - known)
            if unknown:
                warns.append("Invariants.gd 有 %d 条锚不认识的不变量：%s"
                             " ⇒ 没人普查过它们的夹具。重烘：`GODOT=… python tools/gate_fixture_audit.py --run --bake-ledger`"
                             % (len(unknown), ", ".join("#%02d" % i for i in unknown)))
            # 反向：锚里有、树上没了。**这不是本门守的那件事**（它守的是"喂给判据的世界"，
            # 不是"判据本身还在不在"），但一条被删掉的不变量会让锚里那一行从此无意义 ⇒ 至少说一声。
            gone = sorted({int(i) for i in providers} - set(live_ids))
            if gone:
                warns.append("锚里有 %d 条不变量在 Invariants.gd 上已经没有了：%s ⇒ 锚该重烘了"
                             % (len(gone), ", ".join("#%02d" % i for i in gone)))

    if strict:
        fails.extend(warns)
        warns = []
    return fails, warns, notes, status


def _sole_table(ledger):
    """把"单点依赖"打出来——这份表就是那条互补关系本身，让它每跑一次都被看见一次。"""
    providers = ledger["providers"]
    sole = {}
    for iid, provs in providers.items():
        if len(provs) == 1:
            sole.setdefault(provs[0], []).append(int(iid))
    return {k: sorted(v) for k, v in sorted(sole.items())}


def gate(ledger_path=LEDGER, tree=None, strict=False, quiet=False, cur_game_tree=_UNSET):
    if not os.path.isfile(ledger_path):
        print("❌ 找不到互补性锚 %s ⇒ 先跑 `python tools/gate_fixture_audit.py --run --bake-ledger`"
              % os.path.relpath(ledger_path, ROOT))
        return 1
    ledger = json.loads(_read(ledger_path))
    tree = tree or Tree()
    # AE2 P0.①：依赖树闭环——锚的 baked_game_tree 必须 == 当前 HEAD:game，否则红（stale）。
    # 未显式传 ⇒ 现读 git；显式传 None ⇒ 视为"git 读不到"（fail-closed，不假装新鲜）。
    if cur_game_tree is _UNSET:
        cur_game_tree = _head_game_tree()
    fails, warns, notes, status = run_gate(tree, ledger, strict)
    stale = check_ledger_freshness(ledger, cur_game_tree)
    if stale:
        fails = [stale] + fails
    meta = ledger.get("_meta", {})
    if not quiet:
        print("互补性守卫：锚烘于 %s（commit %s，%d 个夹具 × %d 条不变量）"
              % (meta.get("baked_at", "?"), (meta.get("baked_commit") or "?")[:7],
                 len(ledger["fixtures"]), len(ledger["providers"])))
        sole = _sole_table(ledger)
        if sole:
            print("  单点依赖（这一条夹具一旦没了，右边这些不变量整条 CI 都不可能再变红）：")
            for tag, ids in sole.items():
                print("    %-14s ← %s" % (tag, ", ".join("#%02d" % i for i in ids)))
        else:
            print("  单点依赖：（无）—— 每条不变量都至少有两个夹具给它活输入")
        for n in notes:
            print("  · " + n)
        for w in warns:
            print("  ⚠  " + w)
    for f in fails:
        print("  ❌ " + f)
    return 1 if fails else 0


# ── 负对照 ───────────────────────────────────────────────────────────────────
_SYN_CI = """#!/usr/bin/env bash
CI_DG_SEEDS="${CI_DG_SEEDS:-1-4}"
step "4c. DetGate"
"$GODOT" --headless --path game --script res://bench/DetGate.gd -- \\
  --seeds "${CI_DG_SEEDS:-1-4}" --days "${CI_DG_DAYS:-20}"
step "4d. BackendGate"
"$GODOT" --headless --path game res://bench/BackendGate.tscn -- \\
  --seeds "${CI_BG_SEEDS:-1-4}" --days "${CI_BG_DAYS:-30}" --agents "${CI_BG_N:-12}"
"""
_SYN_DET = 'const TRACKS := ["", "faction", "betray", "freerider"]\n'
_SYN_INV = "".join("_chk(%d, 'x', true, '')\n" % i for i in (22, 23, 24, 29))

_SYN_LEDGER = {
    "_meta": {"baked_at": "synthetic", "baked_commit": "0" * 40},
    "fixtures": {
        "DET_betray": {
            "requires": [
                {"file": "tools/ci.sh", "pattern": r"bench/DetGate\.gd", "why": "第 4c 步"},
                {"file": "game/bench/DetGate.gd", "pattern": r'TRACKS\s*:=\s*\[[^\]]*"betray"', "why": "betray 轨"},
            ],
            "floors": {"CI_DG_DAYS": {"kind": "int", "value": 20},
                       "CI_DG_SEEDS": {"kind": "seeds", "value": 4}},
        },
        "BG30": {
            "requires": [{"file": "tools/ci.sh", "pattern": r"bench/BackendGate\.tscn", "why": "第 4d 步"}],
            "floors": {"CI_BG_DAYS": {"kind": "int", "value": 30}},
        },
    },
    "providers": {"22": ["DET_betray"], "23": ["DET_betray"], "24": ["DET_betray"],
                  "29": ["DET_betray", "BG30"]},
    "invariant_kinds": {"22": "C", "23": "C", "24": "C", "29": "G"},
}


def self_test():
    def mk(ci=_SYN_CI, det=_SYN_DET, inv=_SYN_INV, ledger=None):
        t = Tree({"tools/ci.sh": ci, "game/bench/DetGate.gd": det, "game/bench/Invariants.gd": inv})
        lg = json.loads(json.dumps(ledger or _SYN_LEDGER))
        return t, lg

    cases = []

    # M0 正样本面：合成树与合成锚一致 ⇒ 不许有红（**先测这一条**，否则下面每条红都可能是假红）
    t, lg = mk()
    f, w, _, _ = run_gate(t, lg)
    cases.append(("M0 未改动 ⇒ 不假红", not f, f))

    # M1 「处处空转」：锚里有一条不变量的来源是空集 ⇒ 必须响
    t, lg = mk()
    lg["providers"]["23"] = []
    f, _, _, _ = run_gate(t, lg)
    cases.append(("M1 某条不变量处处空转 ⇒ 红并点名 #23",
                  any("#23" in x and "没有任何夹具" in x for x in f), f))

    # M2 「有人把第 4c 步从 ci.sh 里删掉」⇒ 必须红，且要点名会退化成纸的那三条
    t, lg = mk(ci=_SYN_CI.replace("res://bench/DetGate.gd", "res://bench/Nope.gd"))
    f, _, _, _ = run_gate(t, lg)
    cases.append(("M2 删掉 4c ⇒ 红并点名 #22/#23/#24",
                  any(all(k in x for k in ("#22", "#23", "#24")) for x in f), f))

    # M2b 「4c 还在，但 betray 轨被从 DetGate.TRACKS 里拿掉」⇒ 同样必须红
    t, lg = mk(det='const TRACKS := ["", "faction", "freerider"]\n')
    f, _, _, _ = run_gate(t, lg)
    cases.append(("M2b 删掉 betray 轨 ⇒ 红并点名 #22/#23/#24",
                  any(all(k in x for k in ("#22", "#23", "#24")) for x in f), f))

    # M3 夹具**变弱**（CI_BG_DAYS 30→8）⇒ 红；#29 因此失去 BG30，但 DET_betray 还在 ⇒ 不成孤儿，只报变弱
    t, lg = mk(ci=_SYN_CI.replace("CI_BG_DAYS:-30", "CI_BG_DAYS:-8"))
    f, w, n, _ = run_gate(t, lg)
    cases.append(("M3 CI_BG_DAYS 30→8（变弱）⇒ 报出来，且不误报成孤儿",
                  any("变弱" in x for x in n) and not any("#29" in x for x in f), n + f))

    # M4 夹具**变强**（CI_BG_DAYS 30→60）⇒ 一个字都不许红（否则抬天数这件事本身会被这道门惩罚）
    t, lg = mk(ci=_SYN_CI.replace("CI_BG_DAYS:-30", "CI_BG_DAYS:-60"))
    f, _, n, _ = run_gate(t, lg)
    cases.append(("M4 CI_BG_DAYS 30→60（变强）⇒ 不红", not f and not n, f + n))

    # M5 冗余被削掉（BG30 没了，但 #29 在 DET_betray 上还有活输入）⇒ 只警告，不红
    t, lg = mk(ci=_SYN_CI.replace("res://bench/BackendGate.tscn", "res://bench/Gone.tscn"))
    f, w, _, _ = run_gate(t, lg)
    cases.append(("M5 非单点来源没了 ⇒ 只警告不红",
                  not f and any("冗余" in x for x in w), f + w))

    # M6 锚不认识的新不变量 ⇒ 警告（默认）/ 红（strict）
    t, lg = mk(inv=_SYN_INV + "_chk(42, 'new', true, '')\n")
    f, w, _, _ = run_gate(t, lg)
    fs, _, _, _ = run_gate(t, lg, strict=True)
    cases.append(("M6 新不变量 #42 ⇒ 默认警告、strict 下红",
                  not f and any("#42" in x for x in w) and any("#42" in x for x in fs), w))

    # M8 **明知抓不到的那一类**（docs/41 §2.5 要求 does_not_detect 是跑出来的，这一条就是它的证据）：
    #    把 `#22` 这条判据**从 Invariants.gd 里整个删掉** ⇒ 夹具、接线、ci.sh 全没变
    #    ⇒ 守卫**不判红**（它守的是"喂给判据的世界"，不是"判据本身还在不在"），只警告一声。
    t, lg = mk(inv=_SYN_INV.replace("_chk(22, 'x', true, '')\n", ""))
    f, w, _, _ = run_gate(t, lg)
    cases.append(("M8 把 #22 这条判据整个删掉 ⇒ **不红**（明知的盲区），只警告",
                  not f and any("#22" in x and "已经没有了" in x for x in w), f + w))

    # M7 「注释掉」不等于「还在」——整段注释掉第 4c 步必须照样红
    t, lg = mk(ci="\n".join("# " + l for l in _SYN_CI.splitlines()))
    f, _, _, _ = run_gate(t, lg)
    cases.append(("M7 把 ci.sh 整段注释掉 ⇒ 照样红（剔注释再匹配）", bool(f), f))

    # ── AE2 P0.①：consumer 侧的【依赖树闭环】（check_ledger_freshness，纯函数、不碰 git）──
    #   这四条正是外审说旧版守卫"只打印 metadata、不比当前依赖树"漏掉的那道闸。
    _fresh_lg = {"_meta": {"baked_game_tree": "a" * 40}}
    cases.append(("M9 baked_game_tree == 当前 HEAD:game ⇒ 不红（fresh 不假红）",
                  check_ledger_freshness(_fresh_lg, "a" * 40) is None, None))
    _stale = check_ledger_freshness(_fresh_lg, "b" * 40)
    cases.append(("M10 baked_game_tree ≠ 当前 HEAD:game ⇒ 红并点名 STALE + 叫重烘",
                  bool(_stale) and "STALE" in _stale and "重烘" in _stale, _stale))
    _miss = check_ledger_freshness({"_meta": {}}, "a" * 40)
    cases.append(("M11 锚缺 baked_game_tree ⇒ 红（fail-closed，不放过无证据的锚）",
                  bool(_miss) and "baked_game_tree" in _miss, _miss))
    _nogit = check_ledger_freshness(_fresh_lg, None)
    cases.append(("M12 读不到当前 HEAD:game（git 失败）⇒ 红（fail-closed，不假装新鲜）",
                  bool(_nogit), _nogit))

    bad = 0
    for why, ok, ev in cases:
        print("  [%s] %s" % ("✅" if ok else "❌", why))
        if not ok:
            bad += 1
            print("        证据：%s" % ev)
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ledger", default=LEDGER)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--strict", action="store_true",
                    default=os.environ.get("LT_COMPLEMENT_STRICT", "") == "1")
    a = ap.parse_args()
    if a.self_test:
        print("[互补性守卫] 负对照：")
        bad = self_test()
        print("[互补性守卫] 负对照 %s" % ("PASS ✅" if not bad else "FAIL ❌ (%d)" % bad))
        return 1 if bad else 0
    return gate(a.ledger, strict=a.strict)


if __name__ == "__main__":
    sys.exit(main())
