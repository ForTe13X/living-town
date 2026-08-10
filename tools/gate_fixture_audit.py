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
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")   # AE2：否则 traceback 在 GBK 控制台成乱码
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
    # ★ 2026-08-02 Y2：`CI_BG_DAYS` 8 → 30（编号 94 §四·3① 那条菜单被买下）⇒ 这一格跟着改名换值。
    #   留着旧名 BG8 会让下面这张表在量 30 天的世界、而表头写着 8 —— 正是本工具自己在防的那件事。
    ("BG30",      "4d/4e 后端门（backend=null 代理）", "1-4", 30, 0, "",       "hard"),
    ("VOICE60",   "4f VoiceGate",          "1-3",   60,   0,      "",         "none"),
    ("STORY14",   "5 story_test / goals_test（默认档）", "1-12", 14, 0, "",    "none"),
]

# Invariants.HARD_IDS 的副本。**每次运行都对着源码核一遍**（见 _check_hard_ids）——
# 冻结字面量会过期，这是 S2 编号 73 §二·3 量出来的统一结论。
HARD_IDS = [1, 6, 7, 9, 10, 12, 13, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33,
            34, 35, 36, 37, 38, 39, 41, 42, 43, 44, 45, 46]
DIAG_IDS = [15]


# 这张表描述的是 `tools/ci.sh` 的默认值。**它自己就是一份会过期的抄件**，
# 所以下面这个函数每次运行都去 ci.sh 里把 `${CI_*:-默认}` 现读一遍对账——
# 不对账的话，ci.sh 哪天改了默认，本工具会**静默地在量另一个格子**，而输出看起来一模一样。
CI_DEFAULT_EXPECT = {
    "S0":      [("CI_SEEDS", "1-12"), ("CI_DAYS", "60")],
    "POOL16":  [("CI_POOL_N", "16"), ("CI_POOL_SEEDS", "1-12"), ("CI_POOL_DAYS", "60")],
    "DET_default": [("CI_DG_SEEDS", "1-4"), ("CI_DG_DAYS", "20")],
    "BG30":    [("CI_BG_SEEDS", "1-4"), ("CI_BG_DAYS", "30"), ("CI_BG_N", "12")],
    "VOICE60": [("CI_VOICE_SEEDS", "1-3"), ("CI_VOICE_DAYS", "60")],
    # ⚠ 这一格量的是 **X3 改动之前**那个 14 天档（"问题长什么样"的底片）。
    #   ci.sh 今天的默认是 40 天 —— 所以这里对的是 `CI_GOALS_DAYS`（没动的那个），
    #   `CI_STORY_DAYS` 单独列在下面，期望值写 40：它一旦又变了，表头会当场印 ❌。
    "STORY14": [("CI_STORY_SEEDS", "1-12"), ("CI_GOALS_DAYS", "14"), ("CI_STORY_DAYS", "40")],
}


# ── 每个夹具【是怎么挂在 ci.sh 上】的 ──────────────────────────────────────────
# 本表不是测量结果，是**接线图**：它说的是"想让这一格真的跑起来，树上必须还有什么"。
# `--bake-ledger` 把它连同**测出来的活输入来源**一起烘进 tools/gate_complement_ledger.json，
# 而那份锚由 tools/gate_complement_guard.py 每次 CI 现读一遍（约 0.02 s，不进 godot）。
#
# ⚠ `consumes == "none"` 的那两格（VoiceGate / story_test）**不进接线图**：
#   它们一条不变量都不调 ⇒ 结构上给不出任何"活输入来源"，列进去只会把守卫的量程讲得比实际宽。
WIRING = {
    "S0": {
        "requires": [{"file": "tools/ci.sh", "pattern": r"bench/Harness\.gd(?:[\s\S]{0,400}?)--golden",
                      "why": "第 4 步 S0 门（带跨进程金标锚的那一次 Harness 调用）"}],
        "floors": {"CI_SEEDS": ("seeds", None), "CI_DAYS": ("int", None)},
    },
    "POOL16": {
        "requires": [{"file": "tools/ci.sh", "pattern": r'bench/Harness\.gd(?:[\s\S]{0,400}?)--agents "\$POOL_N"',
                      "why": "第 4a 步宏观池尺度门（传 --agents 的那一次 Harness 调用）"}],
        "floors": {"CI_POOL_SEEDS": ("seeds", None), "CI_POOL_DAYS": ("int", None),
                   "CI_POOL_N": ("int", None)},
    },
    "BG30": {
        "requires": [{"file": "tools/ci.sh", "pattern": r"bench/BackendGate\.tscn",
                      "why": "第 4d 步外部后端门（模型路唯一的硬不变量门）"}],
        "floors": {"CI_BG_SEEDS": ("seeds", None), "CI_BG_DAYS": ("int", None),
                   "CI_BG_N": ("int", None)},
    },
}
# 四条 DetGate track 共用第 4c 步那**一次**调用，但**各自**还依赖 DetGate.TRACKS 里的那个字符串
# ——「4c 还在、betray 轨被从 TRACKS 里拿掉」是一种删得掉却看不见的删法，必须单独查。
for _tag, _scen in (("DET_default", ""), ("DET_faction", "faction"),
                    ("DET_betray", "betray"), ("DET_freerider", "freerider")):
    WIRING[_tag] = {
        "requires": [
            {"file": "tools/ci.sh", "pattern": r"bench/DetGate\.gd", "why": "第 4c 步场景确定性门"},
            {"file": "game/bench/DetGate.gd",
             "pattern": r'TRACKS\s*:=\s*\[[^\]]*"%s"' % _scen if _scen
                        else r'TRACKS\s*:=\s*\[\s*""',
             "why": "DetGate.TRACKS 里的 `%s` 轨" % (_scen or "(default)")},
        ],
        "floors": {"CI_DG_SEEDS": ("seeds", None), "CI_DG_DAYS": ("int", None)},
    }


def _check_ci_defaults(src=None):
    """FIXTURES 表里写的 seeds/days（= 本工具测量用的那个格子）与 ci.sh 现值对账。
    `src` 可注入 ci.sh 文本（自检用）；不给就读真文件。对不上返回以 ❌ 开头的串。"""
    if src is None:
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
    # Z1 的 #42：它判的是 `_survival_pull` 这个**纯函数**的响应面 + 一条代数界，
    # **根本不看轨迹** ⇒ 没有"前件归零"这回事，结构上不可能空洞 ⇒ 归 A 档。
    # （Z1 实测：九个变异体共享同一个 digest，摘要门在这里全瞎，而 #42 照样红。）
    42: ("A", "纯函数响应面 + 代数界（不看轨迹，结构上不可能空洞）", lambda L, D: -1),
    # AA3 的 #43：与 #41 同形（"被看见·被知道·不外溢"），但挂在**消费侧**的 transfer 上。
    # 归 G 档而不是 C 档：`production.vendor.trade_credit` 缺键 ⇒ 整段短路 ⇒ 显式豁免。
    43: ("G", "开了 vendor.trade_credit 且商贩真的成交过",
         lambda L, D: 0 if ("豁免" in D.get(43, "") or "关" == D.get(43, "").strip()) else 1),
    # ── E1/E2a/E-export 的贸易溯源三条 #44/#45/#46（Codex 外审 P0-1 2026-08-10）：此前【不在 SPEC】⇒
    #    互补性守卫把它们当"未知硬门"warn 后 rc0 放行＝假绿。实测夹具已跑 import/export（S0 60 天：
    #    import≈20/export≈6·seed，#44/#45/#46 逐 seed fire green），provider 非空、可解释。
    # #44 进口溯源：与 #43/#38 同形 G 档——缺 logistics.json 整段短路显式豁免（detail "物流系统关闭"），否则每笔 import 都要可溯源到声明的节点与货。
    44: ("G", "logistics 开·import 事件全部可溯源（缺 logistics.json 则显式豁免）",
         lambda L, D: 0 if "物流系统关闭" in D.get(44, "") else 1),
    # #45 钱跨镇边界溯源：C 档——provider=跨镇边界流量（进+出 money）。无任何进出 ⇒ external≡0≡应值、判据空洞（无边界流可查）。
    45: ("C", "跨镇边界流量 进+出（=0 则无边界流可查=空洞）",
         lambda L, D: _detail_int(D.get(45, ""), r"进(\d+)") + _detail_int(D.get(45, ""), r"出(\d+)")),
    # #46 出口原子性：同 #44 形——缺 logistics.json 显式豁免，否则每笔 export 的钱货须一一绑定同量。
    46: ("G", "logistics 开·export 钱货一一绑定同量（缺 logistics.json 则显式豁免）",
         lambda L, D: 0 if "物流系统关闭" in D.get(46, "") else 1),
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


def _live_ci_default(src, var):
    m = re.findall(r"\$\{%s:-([^}]*)\}" % var, src)
    return m[-1] if m else None


def _seeds_count(spec):
    n = 0
    for part in str(spec).split(","):
        part = part.strip()
        if not part:
            continue
        m = re.fullmatch(r"(\d+)-(\d+)", part)
        if m:
            n += int(m.group(2)) - int(m.group(1)) + 1
        elif part.isdigit():
            n += 1
        else:
            return -1
    return n if n else -1


def providers_of(data, tags):
    """**测出来的**那一半：每条 C/G 不变量，在哪些夹具里拿到过非零前件。

    这正是编号 94 §二·2 结尾那句"4c 的 betray 轨与 4a 的 N=16 恰好补上了第 4 步的洞"
    ——只不过写成机器读得懂的形状，而不是一张躺在文档里的表。
    """
    out = {}
    for iid in sorted(SPEC):
        if SPEC[iid][0] not in ("C", "G"):
            continue           # A 归零即红、D 本来就不成门 —— 两者都问不到"空洞"这件事
        provs, judged = [], False
        for tag, step, _s, _d, _a, _sc, consumes in tags:
            if consumes == "none" or (consumes == "hard" and iid not in HARD_IDS):
                continue
            judged = True
            fn = SPEC[iid][2]
            vals = [fn(data[tag][sd]["live"], data[tag][sd]["detail"])
                    for sd in sorted(data[tag]) if "live" in data[tag][sd]]
            if vals and max(vals) > 0:
                provs.append(tag)
        if judged:
            out[str(iid)] = provs
    return out


def bake_ledger(data, path, tree_sha=None):
    """把「接线图（WIRING，读的是树）」+「活输入来源（providers，量出来的）」烘成一份锚。

    ⚠ **不完整的数据不许烘**：少跑一格，那一格独有的活输入就会凭空消失，
    烘出来的锚会把一堆本来有牙的不变量记成"处处空转"——本工具 §5.3 的 does_not_detect
    第二条点的正是这个坑，这里把它变成一次**拒绝**而不是一行警告。

    ⚠ AE2：**来源闭环**也在这里合拢——baked_commit 必须真的读到（不给空 sha），
    且测量用的那棵 game 树（tree_sha）必须就是要盖章的那个 commit 的 game 树，否则拒绝。
    """
    need = [f[0] for f in FIXTURES if f[6] != "none"]
    missing = [t for t in need if t not in data or not data[t]]
    if missing:
        print("❌ 拒绝烘锚：缺 %s ⇒ 少跑一格会把一堆有牙的不变量误烘成「处处空转」。"
              "请跑完整的 `--run`（不要带 --only）。" % ",".join(missing))
        return 1
    # ── 来源闭环 ①：commit 章必须真的读到，绝不盖空 ──────────────────────────────
    sha = _rev_parse("HEAD")
    if not sha:
        print("❌ 拒绝烘锚：`git rev-parse HEAD` 读不到 commit ⇒ 不给锚盖一个空的来源章。"
              "（空 baked_commit 会让 gate_complement_guard 侧的来源闭环静默失效。）")
        return 1
    # ── 来源闭环 ②：量的树必须【真的测到了】，且 == 要盖的章的那棵树 ────────────────────
    #   AE2 P0.①（外审 2026-08-06 21:00 §三 P1）：tree_sha 只有走 `--run` 才非 None
    #   （run_fixtures 现读 HEAD:game 并按它内容寻址隔离副本）。不带 --run（例如 `--from OLD`）
    #   ⇒ tree_sha=None。旧版这道比较被 `tree_sha is not None` 挡在门外【被跳过】，盖章路
    #   `tree_sha or cur_tree` 又拿当前 HEAD:game 顶包 ⇒ 旧/伪输出被盖成当前树（confirmed bypass）。
    #   堵法：没有可信的【测量用 game 树】就拒绝盖章，绝不拿 HEAD:game 顶包。
    cur_tree = _rev_parse("HEAD:game")
    if tree_sha is None:
        print("❌ 拒绝烘锚：没有可信的【测量用 game 树】（tree_sha=None）——只有 `--run` 会真的测量并"
              "按 HEAD:game 内容寻址隔离副本。不带 --run（如 `--from`）时绝不拿当前 HEAD:game 顶包盖章。")
        return 1
    if cur_tree is None:
        print("❌ 拒绝烘锚：`git rev-parse HEAD:game` 读不到当前 game 树 ⇒ 无法确认量的树==要盖的章的树。")
        return 1
    if tree_sha != cur_tree:
        print("❌ 拒绝烘锚：测量用的 game 树 %s ≠ 当前 HEAD:game %s ⇒ 量的树与要盖的章不是同一棵。"
              % (tree_sha[:12], cur_tree[:12]))
        return 1
    tags = [f for f in FIXTURES if f[0] in data]
    provs = providers_of(data, tags)
    ci_src = open(os.path.join(ROOT, "tools", "ci.sh"), encoding="utf-8", errors="replace").read()
    fixtures = {}
    for tag, spec in WIRING.items():
        floors = {}
        for var, (kind, _) in (spec.get("floors") or {}).items():
            raw = _live_ci_default(ci_src, var)
            if raw is None:
                print("❌ 拒绝烘锚：ci.sh 里读不到 ${%s:-…}（%s 的接线图与树对不上）" % (var, tag))
                return 1
            val = _seeds_count(raw) if kind == "seeds" else int(raw)
            if val <= 0:
                print("❌ 拒绝烘锚：${%s:-%s} 解不出正数" % (var, raw))
                return 1
            floors[var] = {"kind": kind, "value": val}
        fixtures[tag] = {
            "step": next((f[1] for f in FIXTURES if f[0] == tag), tag),
            "requires": spec["requires"],
            "floors": floors,
        }
    # sha / cur_tree / tree_sha 已在函数开头读到并校验过（sha 非空、tree_sha 非空且 == cur_tree）。
    dead = sorted(int(i) for i, p in provs.items() if not p)
    old = {}
    if os.path.isfile(path):
        try:
            old = json.load(open(path, encoding="utf-8"))
        except ValueError:
            old = {}
    hist = list(((old.get("_meta") or {}).get("rebake_history") or []))
    hist.append("%s · 烘于 commit %s · %d 个夹具 × %d 条 C/G 不变量 · 烘锚时处处空转的：%s"
                % (_today(), (sha or "?")[:7], len(fixtures), len(provs),
                   ", ".join("#%02d" % i for i in dead) if dead else "（无）"))
    doc = {
        "_meta": {
            "note": "互补性锚：哪些夹具是哪条不变量【唯一】的活输入来源。"
                    "由 tools/gate_fixture_audit.py --run --bake-ledger 烘，"
                    "由 tools/gate_complement_guard.py 每次 CI 现读一遍。"
                    "期望值不写在守卫里，只写在这里——守卫那一侧没有任何冻结字面量。",
            "baked_by": "GODOT=… python tools/gate_fixture_audit.py --run --bake-ledger",
            "baked_at": _today(),
            "baked_commit": sha,
            "baked_game_tree": tree_sha,   # 已校验非空且 == cur_tree；不再用 `tree_sha or cur_tree` 顶包
            "dead_at_bake": dead,
            "rebake_history": hist,
        },
        "fixtures": fixtures,
        "providers": provs,
        "invariant_kinds": {str(i): SPEC[i][0] for i in sorted(SPEC)},
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2, sort_keys=False)
        fh.write("\n")
    sole = {}
    for iid, p in provs.items():
        if len(p) == 1:
            sole.setdefault(p[0], []).append(int(iid))
    print("🔨 已烘 %s（%d 夹具 × %d 条 C/G 不变量）" % (_rel(path), len(fixtures), len(provs)))
    print("   烘锚时处处空转：%s" % (", ".join("#%02d" % i for i in dead) if dead else "（无）"))
    for tag in sorted(sole):
        print("   单点依赖 %-14s ← %s" % (tag, ", ".join("#%02d" % i for i in sorted(sole[tag]))))
    return 0


def _rel(path):
    """相对 ROOT 的展示路径。AE2：`--ledger` 指到别的盘（C: vs E:）时 `os.path.relpath`
    会抛 ValueError ⇒ 一次【已经烘好】的锚在最后一行 print 上崩掉、退出码变 1（假红）。
    回退到绝对路径，别让展示串把成功报成失败。"""
    try:
        return os.path.relpath(path, ROOT)
    except ValueError:
        return os.path.abspath(path)


def _today():
    import datetime
    return datetime.date.today().isoformat()


def _resolve_godot(g):
    """Windows 上 `GODOT=.../bin/godot` 常常是一个 **sh 包装脚本**（本机就是），
    `subprocess` 直接 exec 它会得到 `WinError 193 不是有效的 Win32 应用程序`。
    同目录若有 `.cmd`/`.exe` 同名兄弟就改用它。**实测踩到过，不是预防性的。**"""
    if os.name == "nt" and os.path.isfile(g) and not os.path.splitext(g)[1]:
        for ext in (".cmd", ".bat", ".exe"):
            if os.path.isfile(g + ext):
                return g + ext
    return g


def _rev_parse(ref, cwd=ROOT):
    """`git rev-parse <ref>` 现读。读不到 / 非零退出 ⇒ 返回 None（**绝不返回空串冒充成功**）。
    AE2：旧 bake_ledger 直接 `sha = ...stdout.strip()` 且只 except OSError ⇒ git 非零但不抛异常时
    baked_commit 会被静默盖成 ""，来源闭环当场失效。"""
    try:
        r = subprocess.run(["git", "rev-parse", ref], cwd=cwd, capture_output=True, text=True)
    except OSError:
        return None
    sha = (r.stdout or "").strip()
    return sha if (r.returncode == 0 and sha) else None


def _probe_dirty():
    """AE2 P0.①（外审 2026-08-06 21:00 §三 P1 第 2 点）：`--run` archive 的是 committed HEAD:game，
    但探针 `tools/gate_fixture_probe.gd` 是从**工作树**复制进隔离副本的。若它相对 HEAD 有未提交改动，
    测量用的就是一份【没进要盖的章】的探针代码 ⇒ 盖出来的锚 provenance 是断的。
    返回 True=脏（烘锚前应拒）/ False=干净或无法判定（无法判定不拦，避免在非 git 环境假红）。"""
    rel = "tools/gate_fixture_probe.gd"
    try:
        r = subprocess.run(["git", "status", "--porcelain", "--", rel],
                           cwd=ROOT, capture_output=True, text=True)
    except OSError:
        return False
    if r.returncode != 0:
        return False
    return bool((r.stdout or "").strip())


def run_fixtures(godot, iso, outdir, only=None):
    """跑全部（或 --only 指定的）夹具探针。返回 (fails, tree_sha)：
      · fails —— 子进程非零退出码 / 导入失败 的清单。**非空即 fail-closed**（旧版只打印 rc 就往下走）。
      · tree_sha —— 这次真正测量的那棵【committed game/】树的 sha；隔离副本按它内容寻址。"""
    godot = _resolve_godot(godot)
    os.makedirs(outdir, exist_ok=True)
    fails = []
    # committed game/ 的 tree 对象 —— 隔离副本正是 `git archive HEAD -- game` 出来的这棵树。
    tree_sha = _rev_parse("HEAD:game")
    # ── 隔离副本【内容寻址】：绑到 committed game/ 的 tree sha ────────────────────
    # 旧版：`if not isdir(iso/game): extract`。⇒ 换一个 commit 再跑，旧树被**原样复用**，
    #   而 baked_commit 却盖今天的 HEAD —— 量的是 A 树、盖的是 B 章，来源闭环是断的（AE2 抓到的主症）。
    # 现在把上次抽取的 tree sha 记在 iso/.lt_game_tree；对不上 / 读不到 ⇒ **擦掉重抽**，绝不复用旧树。
    game_dir = os.path.join(iso, "game")
    marker = os.path.join(iso, ".lt_game_tree")
    have = None
    if os.path.isfile(marker):
        try:
            have = open(marker, encoding="utf-8").read().strip()
        except OSError:
            have = None
    fresh = (not os.path.isdir(game_dir)) or (tree_sha is None) or (have != tree_sha)
    if fresh:
        if os.path.isdir(iso):
            shutil.rmtree(iso, ignore_errors=True)
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
        if tree_sha:
            with open(marker, "w", encoding="utf-8") as fh:
                fh.write(tree_sha + "\n")
        if have is not None and have != tree_sha:
            print("  ♻ 隔离副本原是 game@%s ≠ 当前 HEAD:game@%s ⇒ 已擦掉重抽（不复用旧树）"
                  % ((have or "?")[:12], (tree_sha or "?")[:12]), flush=True)
    else:
        print("  ↺ 复用隔离副本 game@%s（与当前 HEAD:game 逐位相同）" % (tree_sha or "?")[:12], flush=True)
    shutil.copyfile(os.path.join(ROOT, "tools", "gate_fixture_probe.gd"),
                    os.path.join(game_dir, "bench", "gate_fixture_probe.gd"))
    imp = subprocess.run([godot, "--headless", "--path", game_dir, "--import"], capture_output=True)
    if imp.returncode != 0:
        fails.append("godot --import 退出码 %d ⇒ 隔离副本导入失败，后面每一格的测量都不可信" % imp.returncode)
    for tag, step, seeds, days, agents, scen, _consumes in FIXTURES:
        if only and tag not in only:
            continue
        cmd = [godot, "--headless", "--path", game_dir, "--script",
               "res://bench/gate_fixture_probe.gd", "--", "--seeds", seeds, "--days", str(days), "--tag", tag]
        if agents:
            cmd += ["--agents", str(agents)]
        if scen:
            cmd += ["--scenario", scen]
        r = subprocess.run(cmd, capture_output=True)
        with open(os.path.join(outdir, tag + ".txt"), "wb") as fh:
            fh.write(r.stdout)
        rc = r.returncode
        print("  跑完 %-14s (%s)  rc=%d%s" % (tag, step, rc, "" if rc == 0 else "  ❌ 非零退出 ⇒ 该格测量不可信"),
              flush=True)
        if rc != 0:
            fails.append("%s：探针子进程退出码 %d（打印 rc 却不阻止 = fail-open，AE2 改为阻止）" % (tag, rc))
    return fails, tree_sha


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
        # ci.sh 对账的合成源：从 CI_DEFAULT_EXPECT 现造，改一个默认值就该被判 ❌。
        def _syn_ci(overrides=None):
            overrides = overrides or {}
            parts = []
            for _tag, pairs in CI_DEFAULT_EXPECT.items():
                for var, want in pairs:
                    parts.append('%s="${%s:-%s}"' % (var, var, overrides.get(var, want)))
            return "\n".join(parts) + "\n"

        ci_match = _check_ci_defaults(_syn_ci())
        ci_drift = _check_ci_defaults(_syn_ci({"CI_DAYS": "20"}))       # 把 S0 的 60 天漂成 20
        # 空 sha 的可检出性：非 git 目录里 rev-parse 必须返回 None（旧版会盖成 ""）。
        nogit = tempfile.mkdtemp(prefix="gfa_nogit_")
        sha_none = _rev_parse("HEAD", cwd=nogit)
        shutil.rmtree(nogit, ignore_errors=True)
        # ── AE2 P0.①：bake_ledger 的【树来源闭环】（不需要 godot）───────────────────
        #   造一份【完整】的合成普查数据（所有非 none 夹具都非空，过得了旧的"缺格"拦截），
        #   专门去测烘锚的盖章判据——这正是 confirmed bypass 走的那条路：
        #     · tree_sha=None（= `--from` 无 `--run`）⇒ 必须拒绝，绝不拿当前 HEAD:game 顶包；
        #     · tree_sha ≠ 当前 HEAD:game        ⇒ 必须拒绝；
        #     · tree_sha == 当前 HEAD:game       ⇒ 正常烘（证明上面两条不是"一律拒绝"）。
        import contextlib as _cl
        import io as _io2
        cbase = dict(base)
        cbase["aid_accepted"] = 9
        cbase["types"] = {"betray": 2, "endorse": 2}
        _full = {}
        for _tag in [f[0] for f in FIXTURES if f[6] != "none"]:
            _full[_tag] = {sd: {"live": dict(cbase), "detail": {}, "ok": {}, "hard": {}}
                           for sd in (1, 2)}
        _cur_game = _rev_parse("HEAD:game")
        _lp = os.path.join(tmp, "syn_ledger.json")

        def _bake_rc(ts):
            with _cl.redirect_stdout(_io2.StringIO()):
                return bake_ledger(_full, _lp, tree_sha=ts)

        bake_none_refused = _bake_rc(None) == 1
        bake_mism_refused = _bake_rc("0" * 40) == 1
        bake_fresh_ok = (_cur_game is not None) and (_bake_rc(_cur_game) == 0)
        checks = [
            ("betray=0 ⇒ #22 前件必须是 0", SPEC[22][2](s[1]["live"], s[1]["detail"]) == 0),
            ("aid_accepted=0 ⇒ #29 样本守卫必须判空", SPEC[29][2](s[1]["live"], s[1]["detail"]) == 0),
            ("detail 写「未启用」⇒ #40 满足率臂必须判空", SPEC[40][2](s[1]["live"], s[1]["detail"]) == 0),
            ("n_agents=12 ⇒ #20 小 N 守护必须判活", SPEC[20][2](s[1]["live"], s[1]["detail"]) == 1),
            ("production_on ⇒ #38 必须判活", SPEC[38][2](s[1]["live"], s[1]["detail"]) == 1),
            ("解析器读到了两个 seed", sorted(s) == [1, 2]),
            ("AE2 ci 对账：默认值全对 ⇒ 不判 ❌（不假红）", not ci_match.startswith("❌")),
            ("AE2 ci 对账：CI_DAYS 60→20 漂了 ⇒ 判 ❌（拦住烘锚）", ci_drift.startswith("❌")),
            ("AE2 来源闭环：非 git 目录 rev-parse HEAD ⇒ None（不冒充成空 sha）", sha_none is None),
            ("AE2 P0.①：tree_sha=None（--from 无 --run 后门）⇒ bake 拒绝盖章（不拿 HEAD:game 顶包）",
             bake_none_refused),
            ("AE2 P0.①：量的树 ≠ 当前 HEAD:game ⇒ bake 拒绝", bake_mism_refused),
            ("AE2 P0.①：量的树 == 当前 HEAD:game ⇒ bake 正常烘（不假拒）", bake_fresh_ok),
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
    ap.add_argument("--bake-ledger", action="store_true",
                    help="把互补性锚烘到 tools/gate_complement_ledger.json（需要完整的 --run 数据）")
    ap.add_argument("--ledger", default=os.path.join(ROOT, "tools", "gate_complement_ledger.json"))
    a = ap.parse_args()
    if a.self_test:
        print("[夹具普查] 解析器负对照：")
        bad = self_test()
        print("[夹具普查] 负对照 %s" % ("PASS ✅" if not bad else "FAIL ❌ (%d)" % bad))
        return 1 if bad else 0
    only = [x for x in a.only.split(",") if x] or None
    # ⚠️ 这道拦截必须在 --run 【之前】：一次完整普查要十几分钟，
    #   而"副本与源码对不上"这件事在第一行就能查出来。失败要快。
    if a.bake_ledger:
        # ⚠ AE2 P0.①（外审 2026-08-06 21:00 §三 P1 的 confirmed bypass）：`--from OLD --bake-ledger`
        #   不带 `--run` ⇒ run_fixtures 从不执行 ⇒ tree_sha=None ⇒ 旧/伪输出被盖成当前 HEAD:game。
        #   堵在最前面（失败要快）：--bake-ledger 必须与 --run 同用（--from 只解析、测不到当前 game 树）。
        #   bake_ledger 里的 tree_sha=None 拒绝是同一后门的第二道闸（防有人绕过 CLI 直接调）。
        if not a.run:
            print("\n❌ 拒绝烘锚：--bake-ledger 必须与 --run 同用。")
            print("   `--from <目录>` 只解析已有输出、【测不到当前 game 树】⇒ 会把旧/伪输出盖成当前 HEAD:game")
            print("   （外审 2026-08-06 21:00 §三 P1 confirmed bypass）。要烘就跑 `--run --bake-ledger`。")
            return 1
        # ⚠ 外审 §三 P1 第 2 点：探针从工作树复制。脏探针 ⇒ 测量用了没进章的代码 ⇒ 拒烘（先提交探针）。
        #   放在 run_fixtures 之前（省掉一次 ~12 min 的 godot），无法判定（非 git）不拦。
        if _probe_dirty():
            print("\n❌ 拒绝烘锚：tools/gate_fixture_probe.gd 相对 HEAD 有未提交改动（dirty probe）。")
            print("   `--run` 从工作树复制探针进隔离副本 ⇒ 脏探针会让测量用一份【没进要盖的章】的代码。")
            print("   先提交探针再烘（外审 2026-08-06 21:00 §三 P1 第 2 点）。")
            return 1
        _chk = _check_hard_ids()
        if "对不上" in _chk:
            print("\n❌ 拒绝烘锚：%s" % _chk)
            print("   本工具的 HARD_IDS 副本与 game/bench/Invariants.gd 不一致 ⇒ 枚举必然漏条，")
            print("   而烘出来的锚会把这个漏洞【固化成基线】。先把副本与谓词表补齐再烘。")
            return 1
    run_fails, tree_sha = [], None
    if a.run:
        run_fails, tree_sha = run_fixtures(a.godot, a.iso, a.out, only)
        a.src = a.out
    if not a.src:
        print("要么 --run，要么 --from <目录>")
        return 2
    data = parse_dir(a.src)
    report(data, only)
    if run_fails:
        # ⚠ AE2：子进程非零 ⇒ **立即失败**，不再只把 rc 打印出来就当没事。
        print("\n❌ 子进程非零退出 / 导入失败（fail-closed，不再打印 rc 就往下走）：")
        for f in run_fails:
            print("   · " + f)
    if a.bake_ledger:
        # （HARD_IDS 副本与源码的对账拦截在 --run 之前就做过了，见上面 main() 里那一段。）
        if only:
            print("\n❌ 拒绝烘锚：--only 与 --bake-ledger 不能同用（理由见 bake_ledger 抬头）。")
            return 1
        # ⚠ AE2：ci.sh 默认值漂了 ⇒ 本工具在量【另一个格子】。旧版把这行对账**打印了却不阻止**，
        #   照样烘 —— 正是 docs/41 反复点名的那个病。这里把它变成一次拒绝。
        ci_msg = _check_ci_defaults()
        if ci_msg.startswith("❌"):
            print("\n❌ 拒绝烘锚：%s" % ci_msg)
            print("   FIXTURES 表（本次测量用的 seeds/days）与 ci.sh 现值对不上 ⇒ 量的是另一个格子，烘出来的锚会错位。")
            return 1
        if run_fails:
            print("\n❌ 拒绝烘锚：本次 --run 有子进程非零退出（见上）⇒ 测量不可信，不给它盖章。")
            return 1
        print("")
        return bake_ledger(data, a.ledger, tree_sha)
    return 1 if run_fails else 0


if __name__ == "__main__":
    sys.exit(main())
