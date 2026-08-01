#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""夹具有效性普查（fixture validity audit）—— **量具，不是门**。

它回答 docs/41 §2 第三个盲区的普查版问题：

    `tools/ci.sh` 每一步实际跑的那个夹具（seeds / days / N / 场景）下，
    **这道门要判的那件事发生过几次？** 零次 = 它在这一格里结构上不可能变红。

此前这件事每次都是靠人偶然撞见的：E4 撞见 `player_touch_test` 跑在刚出生的世界上、
D1 撞见 `BackendGate` 的 C 臂在两条出货臂上恒真、W3 撞见 `story_test` 的 14 天档里
promise/secret/pact 三条弧一条都开不出来。**"偶然撞见"不是覆盖率。**

── 两种门，两种问法（**混起来问就会得到错的答案**）─────────────────────────────
  · **条件式**（"若 X 发生则 X 良构"，本仓库 41 条不变量里的绝大多数）：
      X 归零 ⇒ 判据对空输入恒真 ⇒ **空洞**。这一类才是本工具的正题。
  · **禁令式**（"X 一个都不许有"：红线#4 权重门、art/terrain/asset gate 的逐像素相等）：
      X = 0 **正是它要的结果**，不是空洞。这一类的对应问法是
      **"这道门自己的判别力自检这一跑有没有真的执行？"**——本仓库那几道门都自带每跑一次的
      1px / 三例负对照自检，所以它们不在本工具的量程里（见 `docs/41 §2.5`）。

⚠ 本工具**永不判红**，也**不进 ci.sh**。理由与 `recalc_registry.json` 里那条 `gate:false` 逐字相同：
  活输入是【随语料移动的快照】，谁改一次平衡它就会动 ⇒ 给它上门 = 造一道会因为无关改动变红的门，
  而那比没有门更坏（docs/41 §6）。它的用法是**改标定 / 加门 / 换夹具之前跑一次**。

用法：
    python tools/gate_fixture_audit.py --run            # git archive 出隔离副本 → 跑全部夹具 → 出表
    python tools/gate_fixture_audit.py --from <目录>     # 只解析已有的探针输出
    python tools/gate_fixture_audit.py --self-test      # 解析器的负对照（不需要 godot）
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# ── ci.sh 里每一格【真正跑的那个夹具】。改 ci.sh 的默认值时这张表要跟着改。 ────────────
# 值取自 tools/ci.sh 的 ${CI_*:-默认} 与各 bench 自己的默认，**不是**猜的。
# `consumes` = 这一格**真的把不变量当判据**的范围：
#   all  —— Harness：硬 + 软（+诊断只报）
#   hard —— DetGate / BackendGate：**只**收 `c["hard"]`（读过它们的源码，不是推的）
#   none —— VoiceGate / story_test：根本不调 `check_all`；列在这里只为给它们的世界形状留一份底
FIXTURES = [
    # tag,        ci 步骤,                 seeds,   days, agents, scenario,   consumes
    ("S0",        "4 S0 门",               "1-12",  60,   0,      "",         "all"),
    ("POOL16",    "4a 宏观池尺度门",        "1-12",  60,   16,     "",         "all"),
    ("DET_default",   "4c DetGate/default",   "1-4",   20,   0,   "",         "hard"),
    ("DET_faction",   "4c DetGate/faction",   "1-4",   20,   0,   "faction",  "hard"),
    ("DET_betray",    "4c DetGate/betray",    "1-4",   20,   0,   "betray",   "hard"),
    ("DET_freerider", "4c DetGate/freerider", "1-4",   20,   0,   "freerider","hard"),
    ("BG8",       "4d/4e 后端门（backend=null 代理）", "1-4", 8, 0, "",        "hard"),
    ("VOICE60",   "4f VoiceGate",          "1-3",   60,   0,      "",         "none"),
    ("STORY14",   "5 story_test / goals_test（默认档）", "1-12", 14, 0, "",    "none"),
]

# Invariants.HARD_IDS 的副本。**每次运行都对着源码核一遍**（见 _check_hard_ids）——
# 冻结字面量会过期，这是 S2 编号 73 §二·3 量出来的统一结论。
HARD_IDS = [1, 6, 7, 9, 10, 12, 13, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33,
            34, 35, 36, 37, 38, 39, 41]
DIAG_IDS = [15]


# 这张表描述的是 `tools/ci.sh` 的默认值。**它自己就是一份会过期的抄件**，
# 所以下面这个函数每次运行都去 ci.sh 里把 `${CI_*:-默认}` 现读一遍对账——
# 不对账的话，ci.sh 哪天改了默认，本工具会**静默地在量另一个格子**，而输出看起来一模一样。
CI_DEFAULT_EXPECT = {
    "S0":      [("CI_SEEDS", "1-12"), ("CI_DAYS", "60")],
    "POOL16":  [("CI_POOL_N", "16"), ("CI_POOL_SEEDS", "1-12"), ("CI_POOL_DAYS", "60")],
    "DET_default": [("CI_DG_SEEDS", "1-4"), ("CI_DG_DAYS", "20")],
    "BG8":     [("CI_BG_SEEDS", "1-4"), ("CI_BG_DAYS", "8"), ("CI_BG_N", "12")],
    "VOICE60": [("CI_VOICE_SEEDS", "1-3"), ("CI_VOICE_DAYS", "60")],
    # ⚠ 这一格量的是 **X3 改动之前**那个 14 天档（"问题长什么样"的底片）。
    #   ci.sh 今天的默认是 40 天 —— 所以这里对的是 `CI_GOALS_DAYS`（没动的那个），
    #   `CI_STORY_DAYS` 单独列在下面，期望值写 40：它一旦又变了，表头会当场印 ❌。
    "STORY14": [("CI_STORY_SEEDS", "1-12"), ("CI_GOALS_DAYS", "14"), ("CI_STORY_DAYS", "40")],
}


def _check_ci_defaults():
    p = os.path.join(ROOT, "tools", "ci.sh")
    try:
        src = open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return "（读不到 ci.sh，跳过对账）"
    live = dict(re.findall(r"\$\{(CI_[A-Z_0-9]+):-([^}]*)\}", src))
    bad = []
    for tag, pairs in CI_DEFAULT_EXPECT.items():
        for var, want in pairs:
            got = live.get(var)
            if got is None:
                bad.append("%s: ci.sh 里没有 ${%s:-…}" % (tag, var))
            elif got != want:
                bad.append("%s: %s 本工具写 %s，ci.sh 现在是 %s" % (tag, var, want, got))
    if bad:
        return "❌ 与 ci.sh 对不上（**下面的表在量另一个格子**）：" + "；".join(bad)
    return "与 ci.sh 的 %d 个默认值逐个对得上" % sum(len(v) for v in CI_DEFAULT_EXPECT.values())


def _check_hard_ids():
    """把上面那两张表跟 game/bench/Invariants.gd 现读现比。对不上就报出来，别静默用过期的。"""
    p = os.path.join(ROOT, "game", "bench", "Invariants.gd")
    try:
        src = open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return "（读不到 Invariants.gd，跳过核对）"
    out = []
    for name, mine in (("HARD_IDS", HARD_IDS), ("DIAG_IDS", DIAG_IDS)):
        m = re.search(r"const\s+%s\s*:=\s*\[([^\]]*)\]" % name, src)
        if not m:
            out.append("%s：源码里找不到，无法核对" % name)
            continue
        live = [int(x) for x in re.findall(r"\d+", m.group(1))]
        out.append("%s %s（源码 %d 条 vs 本工具 %d 条）"
                   % (name, "对得上" if live == mine else "❌ 对不上", len(live), len(mine)))
    return "；".join(out)

# ── 每条不变量的【前件】：它要判的那件事，以及怎么从探针数据里数出来 ──────────────────
#   kind:  C=条件式（前件归零即空洞）· A=活性断言（归零即红，结构上不可能空洞）
#          G=带显式豁免（豁免放行即空洞）· D=诊断（永不成门）
#   live:  取活输入的函数 (live_dict, detail_by_id) -> int
def _t(L, k):
    return int((L.get("types") or {}).get(k, 0))


def _detail_int(detail, pat):
    m = re.search(pat, detail)
    return int(m.group(1)) if m else 0


SPEC = {
    1:  ("G", "判据未被 scenario 豁免（`starved==0 or not harmony`）",
         lambda L, D: 1 if L["scenario"] == "" else 0),
    2:  ("A", "已接受社交事务（归零即红）", lambda L, D: -1),
    3:  ("C", "阵容里的居民数（每人都要参与过）", lambda L, D: L["n_agents"]),
    4:  ("A", "affinity 跨度 >0（归零即红）", lambda L, D: -1),
    5:  ("G", "判据未被 scenario 豁免", lambda L, D: 1 if L["scenario"] == "" else 0),
    6:  ("C", "需溯源的 belief 条数（via 不是 seed/seen）", lambda L, D: L["beliefs_need_trace"]),
    7:  ("C", "非零的关系事件指针（last_pos/last_neg）", lambda L, D: L["rel_ptrs"]),
    8:  ("A", "承诺创建/兑现（归零即红）", lambda L, D: -1),
    9:  ("C", "承诺条数（扫它们找过期仍 active 的）", lambda L, D: L["commitments"]),
    10: ("C", "违约承诺数（后果臂的前件；等式臂前件=承诺条数）", lambda L, D: L["c_broken"]),
    11: ("A", "冲突触发/对质/修复（归零即红）", lambda L, D: -1),
    12: ("C", "已修复的冲突数", lambda L, D: L["cf_repaired"]),
    13: ("C", "已修复的冲突数", lambda L, D: L["cf_repaired"]),
    14: ("A", "standing 跨度 >0（归零即红）", lambda L, D: -1),
    15: ("D", "诊断档，永不成门（DIAG_IDS）", lambda L, D: 0),
    16: ("G", "镇上存在坏名声（st_min ≤ REP_GOSSIP_TH）", lambda L, D: 1 if L["st_min"] <= L["rep_gossip_th"] else 0),
    17: ("A", "负向声誉 + 修复（归零即红）", lambda L, D: -1),
    18: ("G", "判据未被 scenario 豁免", lambda L, D: 1 if L["scenario"] == "" else 0),
    19: ("G", "判据未被 scenario 豁免", lambda L, D: 1 if L["scenario"] == "" else 0),
    20: ("G", "小 N 守护放行（agents ≤ 12）", lambda L, D: 1 if L["n_agents"] <= 12 else 0),
    21: ("C", "秘密 belief 条数", lambda L, D: L["beliefs_secret"]),
    22: ("C", "betray 事件数", lambda L, D: _t(L, "betray")),
    23: ("C", "betray 事件数", lambda L, D: _t(L, "betray")),
    24: ("C", "betray 事件数", lambda L, D: _t(L, "betray")),
    25: ("C", "居民数（对齐臂扫全员；相识臂另需有派系归属者）", lambda L, D: L["n_agents"]),
    26: ("G", "样本守卫放行（harmony 且 派系≥2 且 内外对各≥3）",
         lambda L, D: 1 if "同派系均" in D.get(26, "") else 0),
    27: ("C", "endorse 事件数（越界臂扫全部关系）", lambda L, D: _t(L, "endorse")),
    28: ("C", "派系桶数", lambda L, D: L["factions"]),
    29: ("G", "样本守卫放行（aid_accepted ≥ 8）", lambda L, D: 1 if L["aid_accepted"] >= 8 else 0),
    30: ("C", "因 freerider 解体的盟约数", lambda L, D: L["pacts_broken_freerider"]),
    31: ("C", "active 盟约数", lambda L, D: L["pacts_active"]),
    32: ("C", "盟约总数", lambda L, D: L["pacts"]),
    33: ("C", "已解体盟约数", lambda L, D: L["pacts_broken"]),
    34: ("G", "经济系统开着（economy.json 在）", lambda L, D: 1 if L["economy_on"] else 0),
    35: ("C", "居民数（扫每人的 coin）", lambda L, D: L["n_agents"]),
    36: ("C", "节日 spawn 事件数", lambda L, D: _detail_int(D.get(36, ""), r"spawn=(\d+)")),
    37: ("C", "选举场次", lambda L, D: L["elections"]),
    38: ("G", "产出系统开着（production.json 在）", lambda L, D: 1 if L["production_on"] else 0),
    39: ("C", "produce 事件数", lambda L, D: L["produce_events"]),
    40: ("G", "满足率臂被启用（days ≥ SUPPLY_MIN_DAYS=60）",
         lambda L, D: 0 if "未启用" in D.get(40, "") else 1),
    41: ("G", "开了 craft_credit 的职位真的上了工（produce ≥ CRAFT_MIN_WORKS）",
         lambda L, D: 0 if ("豁免" in D.get(41, "") or "关" == D.get(41, "").strip()) else 1),
}


def parse_dir(d):
    """读一批探针输出，返回 {tag: {seed: {"live":…, "detail":{id:str}, "ok":{id:bool}}}}"""
    out = {}
    for name in sorted(os.listdir(d)):
        if not name.endswith(".txt"):
            continue
        cur_tag = None
        pend = {}
        for line in open(os.path.join(d, name), encoding="utf-8", errors="replace"):
            if line.startswith("[X3CHK] "):
                r = json.loads(line[8:])
                cur_tag = r["tag"]
                pend.setdefault(r["seed"], {"detail": {}, "ok": {}, "hard": {}})
                pend[r["seed"]]["detail"][int(r["id"])] = r["detail"]
                pend[r["seed"]]["ok"][int(r["id"])] = bool(r["ok"])
                pend[r["seed"]]["hard"][int(r["id"])] = bool(r["hard"])
            elif line.startswith("[X3LIVE] "):
                L = json.loads(line[9:])
                sd = sorted(k for k in pend if "live" not in pend[k])[-1]
                pend[sd]["live"] = L
        if cur_tag:
            out.setdefault(cur_tag, {}).update(pend)
    return out


def spread(vals):
    """展布，不给均值（docs/41 §4/§5）。**极值带并列个数**：`0..16` 与 `0×8..16` 是两件事。"""
    if not vals:
        return "n/a"
    lo, hi = min(vals), max(vals)
    if lo == hi:
        return str(lo)
    nlo, nhi = vals.count(lo), vals.count(hi)
    return "%s..%s" % ("%d×%d" % (lo, nlo) if nlo > 1 else str(lo),
                       "%d×%d" % (hi, nhi) if nhi > 1 else str(hi))


def report(data, only=None):
    tags = [f for f in FIXTURES if f[0] in data and (only is None or f[0] in only)]
    print("═══ 夹具有效性普查（每格 = 该不变量的【前件】在这个夹具里发生了几次，展布 min..max）═══")
    print("kind: C=条件式(归零即空洞) · A=活性断言(归零即红) · G=带豁免 · D=诊断")
    print("核对：" + _check_hard_ids())
    print("核对：" + _check_ci_defaults() + "\n")
    hdr = "  # k  %-46s" % "前件（它要判的那件事）"
    for t in tags:
        hdr += "%-14s" % t[0]
    print(hdr)
    dead_rows = []
    for iid in sorted(SPEC):
        kind, desc, fn = SPEC[iid]
        row = "%3d %s  %-46s" % (iid, kind, desc[:46])
        zero_tags = []
        for t in tags:
            seeds = data[t[0]]
            vals = []
            for sd in sorted(seeds):
                rec = seeds[sd]
                if "live" not in rec:
                    continue
                v = fn(rec["live"], rec["detail"])
                vals.append(v)
            if not vals or vals[0] == -1:
                cell = "—"
            else:
                cell = spread(vals)
                nz = sum(1 for v in vals if v == 0)
                if nz:
                    cell += "(%d空)" % nz
                if max(vals) == 0:
                    zero_tags.append(t[0])
            row += "%-14s" % cell
        print(row)
        if zero_tags:
            dead_rows.append((iid, desc, zero_tags))
    print("\n── 点名：前件在【整格】上一次都没发生过的（= 这道臂在那个夹具里不可能变红）──")
    if not dead_rows:
        print("  （无）")
    for iid, desc, tg in dead_rows:
        print("  #%02d %-46s 空洞于：%s" % (iid, desc[:46], ", ".join(tg)))
    # ── 比例 ────────────────────────────────────────────────────────────────
    # 分母必须两次收窄，否则这个比例会虚高（docs/41 §5「注意分母」）：
    #   ① 只对【C 条件式】与【G 带豁免】问这个问题——A 活性断言归零就是红，D 诊断本来就不成门；
    #   ② 只算这一格**真的当判据用**的那些：DetGate / BackendGate 只收 hard。
    # ── 全 CI 口径：一条不变量只有在【每一个会拿它当判据的格子里】都空，才真的"整条 CI 抓不到" ──
    #    只看单格会把话说过头：#22/#23/#24 在 S0 网格里确实一次都不评估，
    #    但 4c 的 betray track 每个 seed 都给它们 1..3 条真事件。**逐格空洞 ≠ 全局空洞。**
    missing = [f[0] for f in FIXTURES if f[6] != "none" and f[0] not in [t[0] for t in tags]]
    print("\n── 全 CI 口径：在【所有会拿它当判据的格子】里都空洞的 ──")
    if missing:
        print("  ⚠ 本次缺 %s ⇒ 下面这一行**读不得**（少跑一格就会把一堆条目误判成全局空洞）。"
              % ",".join(missing))
    ci_dead = []
    for iid in sorted(SPEC):
        if SPEC[iid][0] not in ("C", "G"):
            continue
        seen_live, seen_any = False, False
        for tag, step, _s, _d, _a, _sc, consumes in tags:
            if consumes == "none" or (consumes == "hard" and iid not in HARD_IDS):
                continue
            seen_any = True
            fn = SPEC[iid][2]
            vals = [fn(data[tag][sd]["live"], data[tag][sd]["detail"])
                    for sd in sorted(data[tag]) if "live" in data[tag][sd]]
            if vals and max(vals) > 0:
                seen_live = True
                break
        if seen_any and not seen_live:
            ci_dead.append(iid)
    print("  " + (", ".join("#%02d" % i for i in ci_dead) if ci_dead else "（无）")
          + "   ← 这才是「整条 CI 都不可能抓到」的那一批")

    print("\n── 比例（分母 = 这一格真的当判据用、且形态上可能空洞的那些）──")
    for t in tags:
        tag, step, _s, _d, _a, _sc, consumes = t
        if consumes == "none":
            print("  %-14s %s —— 不调 check_all，不进这个比例" % (tag, step))
            continue
        pool = [i for i in SPEC if SPEC[i][0] in ("C", "G")]
        if consumes == "hard":
            pool = [i for i in pool if i in HARD_IDS]
        seeds = data[tag]
        dead, partial = [], []
        for iid in pool:
            fn = SPEC[iid][2]
            vals = [fn(seeds[sd]["live"], seeds[sd]["detail"]) for sd in sorted(seeds) if "live" in seeds[sd]]
            if not vals:
                continue
            if max(vals) == 0:
                dead.append(iid)
            elif min(vals) == 0:
                partial.append(iid)
        print("  %-14s %2d/%2d 整格空洞（%.0f%%）%s；另 %d 条部分 seed 空洞 %s"
              % (tag, len(dead), len(pool), 100.0 * len(dead) / max(1, len(pool)),
                 "[" + ",".join("#%02d" % i for i in dead) + "]" if dead else "",
                 len(partial), "[" + ",".join("#%02d" % i for i in partial) + "]" if partial else ""))


def _resolve_godot(g):
    """Windows 上 `GODOT=.../bin/godot` 常常是一个 **sh 包装脚本**（本机就是），
    `subprocess` 直接 exec 它会得到 `WinError 193 不是有效的 Win32 应用程序`。
    同目录若有 `.cmd`/`.exe` 同名兄弟就改用它。**实测踩到过，不是预防性的。**"""
    if os.name == "nt" and os.path.isfile(g) and not os.path.splitext(g)[1]:
        for ext in (".cmd", ".bat", ".exe"):
            if os.path.isfile(g + ext):
                return g + ext
    return g


def run_fixtures(godot, iso, outdir, only=None):
    godot = _resolve_godot(godot)
    os.makedirs(outdir, exist_ok=True)
    if not os.path.isdir(os.path.join(iso, "game")):
        os.makedirs(iso, exist_ok=True)
        # 只取 game/：探针跑的是引擎，docs/ 用不上。
        # ⚠ **不要**管道给外部 `tar`：Windows 上 PATH 里的 bsdtar 会把 `docs/02-技术架构…md`
        #   这类非 ASCII 路径解成 `Invalid empty pathname` 然后整包失败（实测，本工具第一版就栽在这里）。
        #   Python 的 tarfile 按 utf-8 解，稳。
        import io as _io
        import tarfile
        blob = subprocess.run(["git", "archive", "HEAD", "--", "game"],
                              cwd=ROOT, capture_output=True, check=True).stdout
        with tarfile.open(fileobj=_io.BytesIO(blob)) as tf:
            tf.extractall(iso)
    shutil.copyfile(os.path.join(ROOT, "tools", "gate_fixture_probe.gd"),
                    os.path.join(iso, "game", "bench", "gate_fixture_probe.gd"))
    subprocess.run([godot, "--headless", "--path", os.path.join(iso, "game"), "--import"],
                   capture_output=True)
    for tag, step, seeds, days, agents, scen, _consumes in FIXTURES:
        if only and tag not in only:
            continue
        cmd = [godot, "--headless", "--path", os.path.join(iso, "game"), "--script",
               "res://bench/gate_fixture_probe.gd", "--", "--seeds", seeds, "--days", str(days), "--tag", tag]
        if agents:
            cmd += ["--agents", str(agents)]
        if scen:
            cmd += ["--scenario", scen]
        r = subprocess.run(cmd, capture_output=True)
        with open(os.path.join(outdir, tag + ".txt"), "wb") as fh:
            fh.write(r.stdout)
        print("  跑完 %-14s (%s)  rc=%d" % (tag, step, r.returncode), flush=True)


def self_test():
    """解析器的负对照：喂两条合成记录，一条前件为 0、一条不为 0，表里必须分得开。"""
    tmp = tempfile.mkdtemp(prefix="gfa_selftest_")
    try:
        base = {"scenario": "", "n_agents": 12, "types": {}, "beliefs_need_trace": 3, "rel_ptrs": 5,
                "commitments": 1, "c_broken": 0, "conflicts": 1, "cf_repaired": 1, "beliefs_secret": 1,
                "factions": 2, "aid_accepted": 0, "pacts": 0, "pacts_active": 0, "pacts_broken": 0,
                "pacts_broken_freerider": 0, "economy_on": True, "production_on": True, "elections": 1,
                "produce_events": 2, "st_min": -1.0, "rep_gossip_th": -2.0}
        lines = []
        for sd, betrays in ((1, 0), (2, 0)):
            for iid in SPEC:
                lines.append("[X3CHK] " + json.dumps(
                    {"tag": "T", "seed": sd, "id": iid, "ok": True, "hard": False, "name": "n",
                     "detail": "未启用(14<60天)" if iid == 40 else ""}))
            L = dict(base)
            L["types"] = {"betray": betrays}
            lines.append("[X3LIVE] " + json.dumps(L))
        open(os.path.join(tmp, "t.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
        data = parse_dir(tmp)
        bad = 0
        s = data["T"]
        checks = [
            ("betray=0 ⇒ #22 前件必须是 0", SPEC[22][2](s[1]["live"], s[1]["detail"]) == 0),
            ("aid_accepted=0 ⇒ #29 样本守卫必须判空", SPEC[29][2](s[1]["live"], s[1]["detail"]) == 0),
            ("detail 写「未启用」⇒ #40 满足率臂必须判空", SPEC[40][2](s[1]["live"], s[1]["detail"]) == 0),
            ("n_agents=12 ⇒ #20 小 N 守护必须判活", SPEC[20][2](s[1]["live"], s[1]["detail"]) == 1),
            ("production_on ⇒ #38 必须判活", SPEC[38][2](s[1]["live"], s[1]["detail"]) == 1),
            ("解析器读到了两个 seed", sorted(s) == [1, 2]),
        ]
        for why, okv in checks:
            print("  [%s] %s" % ("✅" if okv else "❌", why))
            if not okv:
                bad += 1
        return bad
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--iso", default=os.path.join(tempfile.gettempdir(), "lt_gate_fixture_iso"))
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "lt_gate_fixture_out"))
    ap.add_argument("--from", dest="src")
    ap.add_argument("--only", default="")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        print("[夹具普查] 解析器负对照：")
        bad = self_test()
        print("[夹具普查] 负对照 %s" % ("PASS ✅" if not bad else "FAIL ❌ (%d)" % bad))
        return 1 if bad else 0
    only = [x for x in a.only.split(",") if x] or None
    if a.run:
        run_fixtures(a.godot, a.iso, a.out, only)
        a.src = a.out
    if not a.src:
        print("要么 --run，要么 --from <目录>")
        return 2
    report(parse_dir(a.src), only)
    return 0


if __name__ == "__main__":
    sys.exit(main())
