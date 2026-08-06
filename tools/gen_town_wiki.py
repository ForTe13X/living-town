#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/gen_town_wiki.py — AD1 镇民百科渲染器（docs/114 §一 / docs/115）。

读 game/bench/wiki_dump.gd 导出的【纯只读投影】JSON，渲染成一份自包含、可离线打开的 HTML 百科：
每个 NPC 一页——职业与班次、五需求、带符号的关系(亲密/信任/怨气/名声)、信念(CR:/TR:/SH:/W:/秘密)、
大事记(event_log 讲成人话)、以及由数据归纳的故事弧。

两条硬纪律（docs/41 红线#2 的精神 + docs/114 §一 硬要求）：
  1) 【可追溯】每一句大事记都指回它依据的那条 event（id + tick/day）。渲染器绝不发明情节：
     每条大事记行都由一条真实 event 生成，并在 HTML 上以 `#<id>` 标注、data-ev 属性机读。
  2) 【被拒如实标】社交类事件用 event.accepted 区分「做成了 / 被婉拒」。这正是 AA2 量到的 27.4%
     ——本层不修 Sim，但在 wiki 层【如实标成被拒】，绝不把 rejected 叙述成 happened。
     ⚠ accepted 的语义【随事件类型而变】（见 OUTCOME 说明）：把每个 accepted=false 都当「社交被拒」
     本身就是一次误标（shortage/conflict 的 false 是结构性的，事件确实发生了）——所以按类型分岔。

自检门（§2.5 三行包络）由 --gate 落地：断言"每条大事记可追溯 + 社交被拒被如实标"，写 traceability_report.json。

用法：
  python tools/gen_town_wiki.py --in analysis/wiki/seed07/town_wiki.json --outdir analysis/wiki/seed07
  python tools/gen_town_wiki.py --in ... --outdir ... --gate   # 额外跑可追溯性门，非零退出即门红
"""
import argparse
import html
import io
import json
import math
import os
import sys

# ── 事件结局分类（accepted 的语义随事件 type 而变——AD2 2026-08-06 实读代码的更正）───────────
# 三族语义（Sim.gd）：
#   社交族 accepted 真区分接受/婉拒（被拒记忆文案 Sim 写「被婉拒了」Sim.gd:2433）；
#   经济族 produce/consume/pay/spoil 的 accepted 【恒 true】（Sim.gd:3331，失败的 pay 根本不落账 :3202）
#     ⇒ 绝不读它、绝不当「做成了」的凭据，直接叙述「发生了」；
#   conflict/shortage 的 accepted 【恒 false】（:2684/:3464）⇒ 不是被拒，是这类事件的固定标记。
# SOCIAL_REBUFF：这些类型的 accepted=false = 一次【社交尝试被婉拒/失败】→ 必须标「被拒」，绝不写成 happened。
# （discuss/greet 也在此族、也读 accepted；只是高频，走聚合而非逐条——见 AMBIENT_TYPES。）
SOCIAL_REBUFF = {
    "greet", "give", "gossip", "gossip_rep", "discuss", "invite",
    "confide", "leak", "endorse", "aid", "meet", "confront", "apologize",
}
# 经济族：accepted 恒 true，只叙述发生，绝不读 accepted 做被拒判断。
ECONOMY = {"produce", "consume", "pay", "spoil"}
# 固定标记族：accepted 恒 false，但事件确实发生（不是被拒）。
FIXED_FALSE = {"conflict", "shortage"}
# 提案 / 号召类：election(通过/否决) · rally_oust(有无响应) · mediate(劝没劝和)——读 accepted，但不是「社交被拒」框，
# 各自在 prose() 里显式叙述（failed/未成，而非「被婉拒」）。
PROPOSAL = {"election", "rally_oust", "mediate"}

# 高信息量、逐条渲染的类型（其余高频环境事件走聚合，不占大事记正文）。
CHRONICLE_TYPES = {
    "confide", "betray", "leak", "aid", "meet", "confront", "apologize",
    "mediate", "endorse", "rally_oust", "pact", "gossip_rep", "gossip",
    "give", "invite", "shortage", "election", "conflict",
}
# 走聚合统计、不逐条刷屏的类型。
AMBIENT_TYPES = {"greet", "pay", "consume", "spoil", "produce", "world", "discuss"}

RHYTHM_LABEL = {"night": "夜", "dawn": "清晨", "day": "白天", "dusk": "黄昏", "late": "深夜"}
NEED_ORDER = ["hunger", "energy", "social", "fun", "hygiene"]


def day_of(tick):
    if tick <= 0:
        return 0  # 开局种子
    return (tick - 1) // 240 + 1


def day_label(tick):
    d = day_of(tick)
    return "开局" if d == 0 else "第%d天" % d


class Wiki:
    def __init__(self, data):
        self.data = data
        self.meta = data["meta"]
        self.agents = data["agents"]
        self.events = data["events"]
        self.id2name = dict(self.meta["id_to_name"])
        self.needs_meta = {n["id"]: n for n in self.meta["needs"]}
        self.by_id = {a["id"]: a for a in self.agents}
        # 反向声誉：别人对本 NPC 持有的 CR:/TR:/SH:/W: 信念（subject == 本 id）。
        self.inbound = {a["id"]: {"CR": [], "TR": [], "SH": [], "W": [], "secret": []} for a in self.agents}
        for holder in self.agents:
            for bid, b in holder["beliefs"].items():
                if not isinstance(b, dict):
                    continue
                subj = b.get("subject", "")
                if subj not in self.inbound:
                    continue
                if bid.startswith("CR:"):
                    self.inbound[subj]["CR"].append((holder["id"], b))
                elif bid.startswith("TR:"):
                    self.inbound[subj]["TR"].append((holder["id"], b))
                elif bid.startswith("SH:"):
                    self.inbound[subj]["SH"].append((holder["id"], b))
                elif bid.startswith("W:"):
                    self.inbound[subj]["W"].append((holder["id"], b))
                elif b.get("secret") or bid == "R1" or bid.startswith("S"):
                    if holder["id"] != subj:  # 别人知道的关于 TA 的秘密/传闻
                        self.inbound[subj]["secret"].append((holder["id"], b))

    def name(self, aid):
        return self.id2name.get(aid, aid)

    # ── 把一条 event 讲成人话；返回 (text, outcome) ─────────────────────────
    # outcome ∈ {"done","rejected","failed","conflict","neutral"} —— 决定标什么徽章。
    def prose(self, e, me):
        t = e["type"]
        ok = e["accepted"]
        A = self.name(e["actor"])
        B = self.name(e["target"])
        subj = e["subject"]
        subj_name = self.name(subj) if subj in self.id2name else subj
        note = e.get("note", "")
        # 视角：本 NPC 是发起者(actor) 还是承受者(target) 还是旁观(witness/subject)。
        is_actor = e["actor"] == me
        is_target = e["target"] == me
        other = B if is_actor else A
        # ── 社交类：accepted 分岔（这一段就是 AA2 被拒如实标的落点）──
        if t in SOCIAL_REBUFF:
            done = {
                "greet": "和%s打了招呼、聊了几句" % other,
                "give": "送了%s一点东西" % other,
                "gossip": "和%s嚼了会儿舌根" % other,
                "gossip_rep": "跟%s议论起%s的近况" % (other, subj_name) if subj else "跟%s说了说别人的事" % other,
                "discuss": "和%s交换了看法" % other,
                "invite": "约了%s见面" % other,
                "confide": ("向%s吐露了心事" % other) if is_actor else ("%s向自己吐露了心事" % A),
                "leak": "把%s的秘密说漏了嘴（对%s）" % (subj_name, other),
                "endorse": "和%s统一了口径" % other,
                "aid": ("在%s困难时雪中送炭" % other) if is_actor else ("困难时得到%s的接济" % A),
                "meet": "如约见到了%s" % other,
                "confront": ("当面把话和%s挑明，%s认了" % (other, other)) if is_actor else ("被%s当面理论，自己认了" % A),
                "apologize": ("向%s道了歉，和好了" % other) if is_actor else ("%s来道歉，自己接受了" % A),
            }
            rej = {
                "greet": "想找%s搭话，被冷淡回绝" % other,
                "give": "想送%s东西，被推辞" % other,
                "gossip": "想拉%s说悄悄话，%s没接茬" % (other, other),
                "gossip_rep": "想跟%s议论%s，被挡了回来" % (other, subj_name) if subj else "想跟%s说闲话，被挡了回来" % other,
                "discuss": "想和%s论一论，话不投机" % other,
                "invite": "想约%s，被婉拒" % other,
                "confide": ("想跟%s掏心窝子，没能说出口" % other) if is_actor else ("%s想吐露心事，自己没接住" % A),
                "leak": "话到嘴边，到底没把%s的秘密说出去" % subj_name,
                "endorse": "想拉%s统一口径，没谈拢" % other,
                "aid": ("想帮%s一把，被谢绝" % other) if is_actor else ("落难时向%s求助，被回绝" % A),
                "meet": ("和%s约好却爽了约" % other) if is_actor else ("被%s放了鸽子" % A),
                "confront": ("当面质问%s，%s不认账" % (other, other)) if is_actor else ("被%s当面质问，自己没认" % A),
                "apologize": ("想向%s道歉，%s没接受" % (other, other)) if is_actor else ("%s来道歉，自己没接受" % A),
            }
            return (done[t], "done") if ok else (rej[t], "rejected")
        # ── 提案类（选举）：accepted = 通过/否决 ──
        if t == "election":
            topic = subj or B
            return ("镇上就「%s」表决通过" % topic, "done") if ok else ("镇上就「%s」的提案被否决" % topic, "failed")
        # ── 背叛：一次实打实发生的失信 ──
        if t == "betray":
            if is_actor:
                return ("辜负了%s的信任，把TA的秘密（%s）捅了出去" % (B, subj_name), "conflict")
            return ("信任被%s辜负，秘密（%s）遭泄露" % (A, subj_name), "conflict")
        # ── 盟约 ──
        if t == "pact":
            if note.startswith("dissolved"):
                return ("与%s的互助盟约散了（对方搭便车）" % (B if is_actor else A), "failed")
            return ("和%s结成了互助盟约" % (B if is_actor else A), "done")
        # ── 施压排挤 ──
        if t == "rally_oust":
            n = note.replace("backers:", "") if note.startswith("backers:") else "?"
            if ok:
                return ("联合众人向%s施压，有%s人响应" % (B, n), "conflict") if is_actor else ("成了众矢之的，%s带头施压" % A, "conflict")
            return ("想鼓动大家排挤%s，应者寥寥" % B, "failed") if is_actor else ("%s想煽动排挤自己，没人响应" % A, "neutral")
        # ── 缺货记恨（accepted 结构性为 false，但事件确实发生：东西断了）──
        if t == "shortage":
            good = subj
            if is_actor:
                return ("没买到%s，心里记恨到了%s头上" % (good, B), "neutral")
            return ("被%s怪罪：%s断了货" % (A, good), "neutral")
        # ── 冲突（结构性 false，冲突确实发生）──
        if t == "conflict":
            return ("和%s起了口角" % (B if is_actor else A), "conflict")
        # ── 调解（player 主导，NPC 是被调解方）──
        if t == "mediate":
            return ("有人从中说和了自己和%s的疙瘩" % (B if is_target else A), "done") if ok else ("有人想调解，没能劝和", "failed")
        # ── 产出/支付/消费等环境事件（一般走聚合，这里给兜底）──
        if t == "produce":
            return ("交了一批%s进镇上（%s）" % (subj, note), "done")
        if t == "pay":
            return ("有一笔进账/开销（%s）" % note, "done")
        return (t, "neutral")

    # 本 NPC 参与的、要逐条上大事记的事件（按 tick 升序）。
    def chronicle_events(self, me):
        out = []
        for e in self.events:
            if e["type"] not in CHRONICLE_TYPES:
                continue
            if me == e["actor"] or me == e["target"] or me == e["subject"] or me in e.get("witnesses", []):
                # 只在「当事人」（actor/target/subject）时逐条讲；纯旁观(witness)不刷屏。
                if me == e["actor"] or me == e["target"] or me == e["subject"]:
                    out.append(e)
        out.sort(key=lambda e: (e["tick"], e["id"]))
        return out

    def ambient_stats(self, me):
        """本 NPC 的高频环境事件聚合（每类给 count + 首末 event id，仍可追溯到 id 区间）。"""
        stats = {}
        for e in self.events:
            if e["type"] not in AMBIENT_TYPES:
                continue
            if me != e["actor"] and me != e["target"]:
                continue
            t = e["type"]
            s = stats.setdefault(t, {"n": 0, "ok": 0, "no": 0, "first": None, "last": None, "goods": {}})
            s["n"] += 1
            s["ok" if e["accepted"] else "no"] += 1
            if s["first"] is None:
                s["first"] = e["id"]
            s["last"] = e["id"]
            if t == "produce" and e["subject"]:
                s["goods"][e["subject"]] = s["goods"].get(e["subject"], 0) + 1
        return stats


# ── 关系分类（纯状态，非发明）──────────────────────────────────────────────
def rel_label(r):
    aff = r["affinity"]
    res = r["resentment"]
    if aff >= 40:
        return ("挚友", "pos")
    if aff >= 15:
        return ("朋友", "pos")
    if res >= 8 or aff <= -30:
        return ("结怨", "neg")
    if aff <= -8:
        return ("有嫌隙", "neg")
    if aff > 0:
        return ("点头之交", "mild")
    return ("相识", "neutral")


def sign_str(v):
    return ("+%.1f" % v) if v > 0 else ("%.1f" % v)


# ── HTML 渲染 ───────────────────────────────────────────────────────────────
def esc(s):
    return html.escape(str(s))


CSS = """
:root{--bg:#f7f5f0;--card:#fff;--ink:#26221c;--sub:#6c6459;--line:#e6e0d6;
--pos:#2f8f5b;--neg:#c1533e;--mild:#b98a2e;--accent:#7a5cff;--chip:#f0ece3;--rej:#c1533e;}
@media (prefers-color-scheme:dark){:root{--bg:#16140f;--card:#211e17;--ink:#ece6da;--sub:#9c9384;--line:#332f26;--chip:#2b2820;--pos:#5fce90;--neg:#e88a72;--mild:#e0b45a;--accent:#a68cff;--rej:#e88a72;}}
:root[data-theme=light]{--bg:#f7f5f0;--card:#fff;--ink:#26221c;--sub:#6c6459;--line:#e6e0d6;--pos:#2f8f5b;--neg:#c1533e;--mild:#b98a2e;--accent:#7a5cff;--chip:#f0ece3;--rej:#c1533e;}
:root[data-theme=dark]{--bg:#16140f;--card:#211e17;--ink:#ece6da;--sub:#9c9384;--line:#332f26;--chip:#2b2820;--pos:#5fce90;--neg:#e88a72;--mild:#e0b45a;--accent:#a68cff;--rej:#e88a72;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 -apple-system,"Segoe UI",Roboto,"Noto Sans SC","Microsoft YaHei",sans-serif}
a{color:inherit}
.wrap{max-width:1120px;margin:0 auto;padding:24px 18px 80px}
header.top{display:flex;flex-wrap:wrap;align-items:baseline;gap:12px;border-bottom:2px solid var(--line);padding-bottom:14px;margin-bottom:22px}
header.top h1{font-size:26px;margin:0}
header.top .meta{color:var(--sub);font-size:13px}
.roster{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px;margin-bottom:30px}
.rcard{display:flex;gap:10px;align-items:center;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px 12px;text-decoration:none}
.rcard:hover{border-color:var(--accent)}
.av{width:38px;height:38px;border-radius:50%;flex:0 0 38px;display:flex;align-items:center;justify-content:center;color:#fff;font-weight:700}
.rcard .n{font-weight:600}.rcard .j{color:var(--sub);font-size:12px}
.npc{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:22px 22px 8px;margin-bottom:26px;scroll-margin-top:14px}
.npc h2{margin:0 0 2px;font-size:21px;display:flex;align-items:center;gap:12px}
.tags{color:var(--sub);font-size:13px;margin:2px 0 10px}
.bio{color:var(--sub);margin:0 0 16px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:22px}
@media(max-width:760px){.grid2{grid-template-columns:1fr}.roster{grid-template-columns:repeat(auto-fill,minmax(130px,1fr))}}
h3.sec{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--sub);margin:18px 0 8px;border-bottom:1px solid var(--line);padding-bottom:4px}
.need{display:grid;grid-template-columns:52px 1fr 46px;align-items:center;gap:8px;margin:5px 0;font-size:13px}
.bar{height:9px;border-radius:5px;background:var(--chip);overflow:hidden}
.bar>i{display:block;height:100%;border-radius:5px}
table.rel{width:100%;border-collapse:collapse;font-size:13px}
table.rel td,table.rel th{padding:4px 6px;border-bottom:1px solid var(--line);text-align:left}
table.rel th{color:var(--sub);font-weight:600;font-size:11px;text-transform:uppercase}
.pill{display:inline-block;padding:1px 8px;border-radius:20px;font-size:11px;font-weight:600}
.pos{color:var(--pos)}.neg{color:var(--neg)}.mild{color:var(--mild)}
.pill.pos{background:color-mix(in srgb,var(--pos) 18%,transparent);color:var(--pos)}
.pill.neg{background:color-mix(in srgb,var(--neg) 18%,transparent);color:var(--neg)}
.pill.mild{background:color-mix(in srgb,var(--mild) 18%,transparent);color:var(--mild)}
.pill.neutral{background:var(--chip);color:var(--sub)}
.belief{margin:6px 0;font-size:13px;padding-left:10px;border-left:3px solid var(--line)}
.belief .src{color:var(--sub);font-size:11px}
.bgrp{margin-bottom:10px}.bgrp .lbl{font-size:12px;font-weight:600;color:var(--sub)}
.chron{list-style:none;margin:0;padding:0}
.chron li{display:flex;gap:10px;padding:6px 0;border-bottom:1px dashed var(--line);font-size:13.5px;align-items:baseline}
.chron .day{flex:0 0 62px;color:var(--sub);font-size:12px;font-variant-numeric:tabular-nums}
.chron .tx{flex:1}
.chron .ev{flex:0 0 auto;color:var(--sub);font-size:11px;font-variant-numeric:tabular-nums;opacity:.7}
.badge{display:inline-block;font-size:10.5px;font-weight:700;padding:0 6px;border-radius:5px;margin-right:6px;vertical-align:1px}
.badge.rej{background:color-mix(in srgb,var(--rej) 20%,transparent);color:var(--rej)}
.badge.fail{background:color-mix(in srgb,var(--mild) 22%,transparent);color:var(--mild)}
.badge.conf{background:color-mix(in srgb,var(--neg) 16%,transparent);color:var(--neg)}
.arc{background:var(--chip);border-radius:12px;padding:12px 14px;font-size:13.5px;margin:6px 0 4px}
.arc b{color:var(--accent)}
.kv{color:var(--sub);font-size:12px;margin:2px 0}
.amb{color:var(--sub);font-size:12px;margin:3px 0}
.foot{color:var(--sub);font-size:12px;margin-top:30px;border-top:1px solid var(--line);padding-top:14px}
.tog{cursor:pointer;border:1px solid var(--line);background:var(--card);color:var(--sub);border-radius:8px;padding:4px 10px;font-size:12px}
/* ── AJ1 横切总览（关系图谱 / 镇级年表 / 派系与冲突）──────────────────────── */
.ov{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:22px 22px 16px;margin-bottom:26px}
.ov>h2{margin:0 0 4px;font-size:22px}
.ov .lead{color:var(--sub);font-size:13px;margin:0 0 14px}
.netwrap{width:100%;overflow-x:auto}
.netwrap svg{display:block;width:100%;height:auto;max-width:880px;margin:0 auto}
.net-node text{font:600 12.5px -apple-system,"Segoe UI","Noto Sans SC","Microsoft YaHei",sans-serif;fill:var(--ink)}
.legend{display:flex;flex-wrap:wrap;gap:14px;color:var(--sub);font-size:12px;margin:6px 2px 2px}
.legend i{display:inline-block;vertical-align:middle;margin-right:5px}
.legend .ln{width:22px;height:0;border-top-width:3px;border-top-style:solid}
.legend .dot{width:12px;height:12px;border-radius:50%;border:2px solid}
.ovgrid{display:grid;grid-template-columns:1fr 1fr;gap:22px}
@media(max-width:820px){.ovgrid{grid-template-columns:1fr}}
.faccard{background:var(--chip);border-radius:12px;padding:10px 13px;margin:0 0 10px}
.faccard .fh{font-weight:700;font-size:14px;margin-bottom:3px}
.faccard .fm{color:var(--sub);font-size:12.5px}
table.ovt{width:100%;border-collapse:collapse;font-size:13px}
table.ovt td,table.ovt th{padding:5px 7px;border-bottom:1px solid var(--line);text-align:left}
table.ovt th{color:var(--sub);font-weight:600;font-size:11px;text-transform:uppercase}
table.ovt td.num{font-variant-numeric:tabular-nums}
table.ovt .evref{color:var(--sub);font-size:11px;font-variant-numeric:tabular-nums;opacity:.7}
.ovnav{display:flex;flex-wrap:wrap;gap:10px;margin:2px 0 16px}
.ovnav a{background:var(--chip);border:1px solid var(--line);border-radius:20px;padding:4px 12px;font-size:12.5px;text-decoration:none;color:var(--sub)}
.ovnav a:hover{border-color:var(--accent);color:var(--ink)}
"""

THEME_JS = """
document.querySelectorAll('.chron').forEach(function(c){
  var extra=c.querySelectorAll('li.more'); if(extra.length===0)return;
  var lbl=c.getAttribute('data-more-label')||'条大事记';
  var b=document.createElement('button');b.className='tog';b.textContent='展开全部 '+extra.length+' '+lbl;
  extra.forEach(function(li){li.style.display='none'});
  b.onclick=function(){var open=extra[0].style.display==='none';extra.forEach(function(li){li.style.display=open?'flex':'none'});b.textContent=open?'收起':'展开全部 '+extra.length+' '+lbl;};
  c.parentNode.insertBefore(b,c.nextSibling);
});
"""


def need_bar(nid, val, meta):
    label = meta.get(nid, {}).get("label", nid)
    low = meta.get(nid, {}).get("low", 30)
    color = "var(--neg)" if val < low else ("var(--mild)" if val < low + 25 else "var(--pos)")
    return ('<div class="need"><span>%s</span><span class="bar"><i style="width:%.0f%%;background:%s"></i></span>'
            '<span>%.0f</span></div>') % (esc(label), max(0, min(100, val)), color, val)


def render_agent(w, a, chron_out):
    aid = a["id"]
    color = a["color"] if a["color"].startswith("#") else "#888"
    init = a["name"][0] if a["name"] else "?"
    parts = []
    parts.append('<section class="npc" id="npc-%s">' % esc(aid))
    parts.append('<h2><span class="av" style="background:%s">%s</span>%s'
                 '<span style="font-size:13px;color:var(--sub);font-weight:400">· %s</span></h2>'
                 % (esc(color), esc(init), esc(a["name"]), esc(aid)))
    job = a.get("job") or {}
    jtxt = ""
    if job:
        shift = "、".join(RHYTHM_LABEL.get(s, s) for s in job.get("shift", [])) or "全天"
        jtxt = "%s · 班次%s · 日薪%d" % (job.get("title", ""), shift, job.get("wage", 0))
    fac = (" · 派系 %s(%d人)" % (a["faction"], a["faction_size"])) if a.get("faction") else ""
    parts.append('<div class="tags">%s%s · %s · 存钱 %d</div>' % (
        esc("、".join(a["traits"])), esc(fac), esc(jtxt), a.get("coin", 0)))
    if a.get("bio"):
        parts.append('<p class="bio">%s</p>' % esc(a["bio"]))

    parts.append('<div class="grid2"><div>')
    # 需求
    parts.append('<h3 class="sec">五需求（终局）</h3>')
    for nid in NEED_ORDER:
        if nid in a["needs"]:
            parts.append(need_bar(nid, a["needs"][nid], w.needs_meta))
    # 关系
    parts.append('<h3 class="sec">关系账本（带符号）</h3>')
    rels = a["relationships"]
    ranked = sorted(rels.items(), key=lambda kv: -abs(kv[1]["affinity"]) - kv[1]["resentment"] * 0.5)
    ranked = [kv for kv in ranked if kv[1]["familiarity"] > 0 or abs(kv[1]["affinity"]) > 0 or kv[1]["resentment"] > 0]
    if ranked:
        parts.append('<table class="rel"><tr><th>对谁</th><th>关系</th><th>亲密</th><th>信任</th><th>怨气</th><th>名声</th></tr>')
        for oid, r in ranked[:12]:
            lab, cls = rel_label(r)
            parts.append('<tr><td>%s</td><td><span class="pill %s">%s</span></td>'
                         '<td class="%s">%s</td><td>%s</td><td class="%s">%s</td><td>%s</td></tr>' % (
                             esc(w.name(oid)), cls, esc(lab),
                             "pos" if r["affinity"] > 0 else ("neg" if r["affinity"] < 0 else ""), sign_str(r["affinity"]),
                             sign_str(r["trust"]),
                             "neg" if r["resentment"] > 0 else "", ("%.1f" % r["resentment"]),
                             sign_str(r["standing"])))
        parts.append('</table>')
    else:
        parts.append('<div class="kv">尚无成型关系。</div>')

    parts.append('</div><div>')
    # 信念
    parts.append('<h3 class="sec">信念与见闻</h3>')
    parts.append(render_beliefs(w, a))
    # 声誉（反向：别人怎么看 TA）
    parts.append(render_reputation(w, aid))
    parts.append('</div></div>')

    # 故事弧（数据归纳）
    parts.append('<h3 class="sec">故事弧（由数据归纳，非杜撰）</h3>')
    parts.append(render_arc(w, a, chron_out))

    # 大事记
    parts.append('<h3 class="sec">大事记（每条指回其依据的 event）</h3>')
    parts.append(render_chronicle(w, aid, chron_out))
    parts.append(render_ambient(w, aid))
    parts.append('</section>')
    return "".join(parts)


def render_beliefs(w, a):
    groups = [("秘密 / 传闻", []), ("手艺口碑 CR", []), ("买卖口碑 TR", []), ("缺货记恨 SH", []), ("贫富见闻 W", [])]
    for bid, b in a["beliefs"].items():
        if not isinstance(b, dict):
            continue
        claim = b.get("claim", "")
        via = b.get("via", "")
        tick = b.get("tick", 0)
        src = '<span class="src">（来源 %s · %s）</span>' % (esc(via), esc(day_label(tick)))
        line = '<div class="belief">%s %s</div>' % (esc(claim), src)
        if bid.startswith("CR:"):
            groups[1][1].append(line)
        elif bid.startswith("TR:"):
            groups[2][1].append(line)
        elif bid.startswith("SH:"):
            groups[3][1].append(line)
        elif bid.startswith("W:"):
            groups[4][1].append(line)
        else:
            groups[0][1].append(line)
    out = []
    any_shown = False
    for lbl, lines in groups:
        if not lines:
            continue
        any_shown = True
        out.append('<div class="bgrp"><div class="lbl">%s（%d）</div>%s</div>' % (esc(lbl), len(lines), "".join(lines)))
    if not any_shown:
        out.append('<div class="kv">尚无信念记录。</div>')
    return "".join(out)


def render_reputation(w, aid):
    inb = w.inbound[aid]
    bits = []
    if inb["CR"]:
        bits.append("%d人认得TA的手艺" % len(inb["CR"]))
    if inb["TR"]:
        bits.append("%d人念着TA的摊子" % len(inb["TR"]))
    if inb["SH"]:
        bits.append("%d人因缺货记恨TA" % len(inb["SH"]))
    rich = sum(1 for _, b in inb["W"] if "rich" in b.get("claim", "") or ":rich" in str(b))
    if inb["secret"]:
        bits.append("%d人知道TA的私事" % len(inb["secret"]))
    if not bits:
        return ""
    return '<h3 class="sec">镇上怎么看TA</h3><div class="kv">%s。</div>' % esc("；".join(bits))


def render_arc(w, a, chron_out):
    aid = a["id"]
    rels = a["relationships"]
    # 关系走向：最亲 / 最怨
    friends = sorted(rels.items(), key=lambda kv: -kv[1]["affinity"])
    top_friend = next(((oid, r) for oid, r in friends if r["affinity"] >= 15), None)
    rivals = sorted(rels.items(), key=lambda kv: kv[1]["affinity"])
    rival = next(((oid, r) for oid, r in rivals if r["affinity"] <= -8 or r["resentment"] >= 8), None)
    lines = []
    if top_friend:
        lines.append("和 <b>%s</b> 走得最近（亲密 %s）" % (esc(w.name(top_friend[0])), sign_str(top_friend[1]["affinity"])))
    if rival:
        lines.append("和 <b>%s</b> 有过节（亲密 %s，怨气 %.1f）" % (
            esc(w.name(rival[0])), sign_str(rival[1]["affinity"]), rival[1]["resentment"]))
    # 职业主线：produce 聚合
    prod = [e for e in w.events if e["type"] == "produce" and e["actor"] == aid]
    if prod:
        goods = {}
        for e in prod:
            goods[e["subject"]] = goods.get(e["subject"], 0) + 1
        gtxt = "、".join("%s×%d" % (g, n) for g, n in sorted(goods.items(), key=lambda x: -x[1]))
        lines.append("靠手艺交了 <b>%d</b> 批货进镇上（%s）" % (len(prod), esc(gtxt)))
    # 高光/低谷：从 chron 里挑 conflict / rejected 计数
    n_rej = sum(1 for e, o in chron_out if o == "rejected")
    n_conf = sum(1 for e, o in chron_out if o == "conflict")
    aids_help = sum(1 for e in w.events if e["type"] == "aid" and e["accepted"] and (e["actor"] == aid or e["target"] == aid))
    if aids_help:
        lines.append("经历过 <b>%d</b> 次雪中送炭（施或受）" % aids_help)
    if n_conf:
        lines.append("卷入 <b>%d</b> 桩冲突/背叛/施压" % n_conf)
    if n_rej:
        lines.append("有 <b>%d</b> 次社交尝试吃了闭门羹（已如实标注在大事记）" % n_rej)
    if not lines:
        lines.append("这一季过得平静，没留下什么大风浪。")
    return '<div class="arc">' + "；".join(lines) + "。</div>"


def render_chronicle(w, aid, chron_out):
    if not chron_out:
        return '<div class="kv">这一季没有值得记的大事。</div>'
    out = ['<ul class="chron">']
    SHOW = 8
    for i, (e, outcome) in enumerate(chron_out):
        text, _ = w.prose(e, aid)
        badge = ""
        if outcome == "rejected":
            badge = '<span class="badge rej">被拒</span>'
        elif outcome == "failed":
            badge = '<span class="badge fail">未成</span>'
        elif outcome == "conflict":
            badge = '<span class="badge conf">冲突</span>'
        cls = "more" if i >= SHOW else ""
        out.append('<li class="%s" data-ev="%d"><span class="day">%s</span>'
                   '<span class="tx">%s%s</span><span class="ev">#%d</span></li>' % (
                       cls, e["id"], esc(day_label(e["tick"])), badge, esc(text), e["id"]))
    out.append('</ul>')
    return "".join(out)


def render_ambient(w, aid):
    stats = w.ambient_stats(aid)
    if not stats:
        return ""
    bits = []
    order = ["greet", "produce", "pay", "consume", "discuss", "spoil"]
    lab = {"greet": "打招呼", "produce": "出货", "pay": "钱进出", "consume": "消耗", "discuss": "闲聊", "spoil": "存货放坏"}
    for t in order:
        if t not in stats:
            continue
        s = stats[t]
        extra = ""
        # 只有社交族(greet/discuss)才读 accepted 标被拒；经济族 accepted 恒 true，不套被拒框。
        if s["no"] and t in SOCIAL_REBUFF:
            extra = "（其中 %d 次被拒）" % s["no"]
        if t == "produce" and s["goods"]:
            extra = "（%s）" % "、".join("%s×%d" % (g, n) for g, n in s["goods"].items())
        bits.append("%s %d 次%s" % (lab.get(t, t), s["n"], extra))
    return '<div class="amb">日常（聚合，可追溯 event 区间）：%s。</div>' % esc("；".join(bits))


# ══════════════════════════════════════════════════════════════════════════
# AJ1 · 横切总览（关系图谱 + 镇级大事年表 + 派系/冲突概览）
# ──────────────────────────────────────────────────────────────────────────
# 纪律与逐 NPC 页完全一致：**只从已有 town_wiki/v1 JSON 归纳，一条都不发明**。
#   · 每条年表项 → 一条真实 event.id（`#<id>` + data-ev）；被拒/未成按 accepted 如实标。
#   · 每条网络边 → 一条真实 relationships 记录（data-a/data-b/data-aff/data-res，数值由源账本重算）。
#   · 每个派系成员/施压项/怨气对 → 真实 agent.faction / rally_oust event / relationship。
# 可追溯性由 --gate 的 §2.5 包络断言（正对照 + 喂假边/假年表项的负对照）。

# 收录进【镇级年表】的高信息、改变镇上格局的事件类型（口角76/断货40 等高频摩擦不刷屏、
# 聚合进下方「派系与冲突概览」）。选择在标题里写明，绝不悄悄取舍。
TOWN_TIMELINE_TYPES = {
    "election", "pact", "rally_oust", "betray", "mediate",
    "aid", "confide", "leak", "endorse", "confront",
}
# 派系环色（仅用于节点描边；节点填色仍用人格自带 color）。无派系=灰。
FACTION_RING = {"": "#9aa0a6"}
FACTION_PALETTE = ["#c77dff", "#4cc9f0", "#ff9e6d", "#4caf7d", "#e0658a", "#d4b23c"]

# 网络图收边阈值（写进图注，透明）。此镇 66 对里约 49 对达标。
EDGE_AFF_FRIEND = 20.0   # 亲密 ≥ 此 → 友好边
EDGE_AFF_RIVAL = -20.0   # 亲密 ≤ 此 → 敌对边
EDGE_RES_RIVAL = 8.0     # 怨气 ≥ 此 → 敌对边

# 网络图画布几何（确定性，无随机）。
NET_W, NET_H, NET_CX, NET_CY, NET_R = 860, 620, 430, 300, 232


def town_prose(w, e):
    """把一条 event 讲成【镇视角】人话（点名 actor→target），纯用 event 字段，不发明。"""
    t = e["type"]
    A = w.name(e["actor"])
    B = w.name(e["target"])
    subj = e["subject"]
    subj_name = w.name(subj) if subj in w.id2name else subj
    note = e.get("note", "")
    ok = e["accepted"]
    if t == "election":
        topic = subj or B
        return ("镇上表决「%s」——通过" % topic) if ok else ("镇上表决「%s」——被否决" % topic)
    if t == "pact":
        if note.startswith("dissolved"):
            return "%s 与 %s 的互助盟约散了（有人搭便车）" % (A, B)
        return "%s 与 %s 结成互助盟约" % (A, B)
    if t == "rally_oust":
        n = note.replace("backers:", "") if note.startswith("backers:") else "?"
        return ("%s 联合 %s 人向 %s 施压" % (A, n, B)) if ok else ("%s 想鼓动排挤 %s，应者寥寥" % (A, B))
    if t == "betray":
        return "%s 辜负了 %s 的信任，把秘密（%s）捅了出去" % (A, B, subj_name)
    if t == "mediate":
        return ("有人从中说和了 %s 与 %s" % (A, B)) if ok else ("有人想调解 %s 与 %s，没劝和" % (A, B))
    if t == "aid":
        return ("%s 在困难时接济了 %s（%s）" % (A, B, subj)) if ok else ("%s 向 %s 求助，被回绝" % (A, B))
    if t == "confide":
        return ("%s 向 %s 吐露了心事" % (A, B)) if ok else ("%s 想向 %s 吐露心事，没说出口" % (A, B))
    if t == "leak":
        return ("%s 把 %s 的秘密说漏给了 %s" % (A, subj_name, B)) if ok else ("%s 话到嘴边，到底没说 %s 的秘密" % (A, subj_name))
    if t == "endorse":
        return ("%s 与 %s 统一了口径（谈及 %s）" % (A, B, subj_name)) if ok else ("%s 想拉 %s 统一口径，没谈拢" % (A, B))
    if t == "confront":
        return ("%s 当面质问 %s，%s 认了" % (A, B, B)) if ok else ("%s 当面质问 %s，%s 不认账" % (A, B, B))
    return "%s → %s（%s）" % (A, B, t)


def build_overview(w):
    """从 town_wiki/v1 JSON 归纳出三视图所需的结构化数据（供渲染器与 --gate 共用同一份，杜绝分叉）。"""
    agents = w.agents
    order_index = {a["id"]: i for i, a in enumerate(agents)}

    # ── 节点布局：按派系分组成弧，确定性圆布局（无随机/无力导）───────────────
    fac_first = {}
    for i, a in enumerate(agents):
        f = a["faction"]
        if f and f not in fac_first:
            fac_first[f] = i
    # 派系环色：按首次出现顺序发一个稳定色；无派系恒灰。
    fac_color = dict(FACTION_RING)
    for k, f in enumerate(sorted([f for f in fac_first], key=lambda f: fac_first[f])):
        fac_color[f] = FACTION_PALETTE[k % len(FACTION_PALETTE)]

    def fac_rank(f):
        return (1, 10 ** 9) if f == "" else (0, fac_first[f])

    ordered = sorted(agents, key=lambda a: (fac_rank(a["faction"]), order_index[a["id"]]))
    nodes = []
    mtot = len(ordered)
    for i, a in enumerate(ordered):
        ang = -math.pi / 2 + i * 2 * math.pi / mtot
        nodes.append({
            "id": a["id"], "name": a["name"], "color": a["color"], "faction": a["faction"],
            "ring": fac_color.get(a["faction"], FACTION_RING[""]),
            "x": round(NET_CX + NET_R * math.cos(ang), 1),
            "y": round(NET_CY + NET_R * math.sin(ang), 1),
            "cos": math.cos(ang),
        })

    # ── 边：无向对，数值由【源关系账本】重算（两向取 亲密均值 / 怨气最大值）─────
    byid = w.by_id
    seen = set()
    edges = []
    for a in agents:
        for oid, r in a["relationships"].items():
            if oid not in byid:
                continue
            key = tuple(sorted((a["id"], oid)))
            if key in seen:
                continue
            seen.add(key)
            r2 = byid[oid]["relationships"].get(a["id"], {})
            aff = round((r["affinity"] + r2.get("affinity", r["affinity"])) / 2.0, 2)
            res = round(max(r["resentment"], r2.get("resentment", 0.0)), 2)
            if not (aff >= EDGE_AFF_FRIEND or aff <= EDGE_AFF_RIVAL or res >= EDGE_RES_RIVAL):
                continue
            kind = "neg" if (res >= EDGE_RES_RIVAL or aff <= EDGE_AFF_RIVAL) else "pos"
            weight = (res * 3.0 + max(0.0, -aff)) if kind == "neg" else aff
            edges.append({"a": key[0], "b": key[1], "aff": aff, "res": res, "kind": kind, "weight": weight})
    edges.sort(key=lambda e: (e["kind"], -e["weight"]))
    deg = {a["id"]: 0 for a in agents}
    for e in edges:
        deg[e["a"]] += 1
        deg[e["b"]] += 1
    isolates = [aid for aid, d in deg.items() if d == 0]

    # ── 镇级年表：跨 NPC 的高信息事件，按 (tick,id) 升序；outcome 复用 prose 的判定（单一真源）──
    timeline = []
    for e in w.events:
        if e["type"] not in TOWN_TIMELINE_TYPES:
            continue
        outcome = w.prose(e, e["actor"])[1]
        timeline.append({"e": e, "outcome": outcome, "text": town_prose(w, e)})
    timeline.sort(key=lambda row: (row["e"]["tick"], row["e"]["id"]))

    # ── 派系花名册 ─────────────────────────────────────────────────────────
    fac_members = {}
    for a in agents:
        fac_members.setdefault(a["faction"], []).append(a["id"])
    factions = []
    for f in sorted(fac_members, key=lambda f: (1, 10 ** 9) if f == "" else (0, fac_first[f])):
        factions.append({"key": f, "ring": fac_color.get(f, FACTION_RING[""]),
                         "leader": f if f in byid else "", "members": fac_members[f]})

    # ── 联合施压组：rally_oust 按 target 聚合（谁被围攻、谁牵头、几场、最多几人响应）──
    pressure = {}
    for e in w.events:
        if e["type"] != "rally_oust":
            continue
        tgt = e["target"]
        p = pressure.setdefault(tgt, {"target": tgt, "events": [], "instigators": {}, "max_backers": 0, "landed": 0})
        p["events"].append(e["id"])
        p["instigators"][e["actor"]] = p["instigators"].get(e["actor"], 0) + 1
        if e["accepted"]:
            p["landed"] += 1
        n = e.get("note", "")
        if n.startswith("backers:"):
            try:
                p["max_backers"] = max(p["max_backers"], int(n.replace("backers:", "")))
            except ValueError:
                pass
    pressure_list = sorted(pressure.values(), key=lambda p: (-len(p["events"]), p["target"]))

    # ── 高怨气对（有向，源自关系账本）+ 该对之间的口角次数（conflict event）───────
    conflict_between = {}
    for e in w.events:
        if e["type"] != "conflict":
            continue
        k = tuple(sorted((e["actor"], e["target"])))
        conflict_between.setdefault(k, []).append(e["id"])
    res_pairs = []
    for a in agents:
        for oid, r in a["relationships"].items():
            if r["resentment"] > 0 and oid in byid:
                k = tuple(sorted((a["id"], oid)))
                res_pairs.append({"src": a["id"], "dst": oid, "res": r["resentment"], "aff": r["affinity"],
                                  "conflicts": conflict_between.get(k, [])})
    res_pairs.sort(key=lambda p: (-p["res"], p["src"], p["dst"]))

    return {
        "nodes": nodes, "edges": edges, "isolates": isolates, "deg": deg,
        "timeline": timeline, "factions": factions,
        "pressure": pressure_list, "resentment": res_pairs,
        "fac_color": fac_color,
        "n_pairs_total": len(seen),
    }


def _lerp(a, b, t):
    return a + (b - a) * max(0.0, min(1.0, t))


def render_network_svg(w, ov, link_prefix=""):
    nodes = ov["nodes"]
    edges = ov["edges"]
    pos = {n["id"]: n for n in nodes}
    # 归一化线宽/透明度（按 kind 各自归一，友好/敌对分开量纲）。
    maxw = {"pos": 1.0, "neg": 1.0}
    for e in edges:
        if e["weight"] > maxw[e["kind"]]:
            maxw[e["kind"]] = e["weight"]
    parts = ['<svg viewBox="0 0 %d %d" role="img" aria-label="全镇关系网络图" xmlns="http://www.w3.org/2000/svg">' % (NET_W, NET_H)]
    # 边（画在节点之下）
    for e in edges:
        na, nb = pos[e["a"]], pos[e["b"]]
        frac = e["weight"] / maxw[e["kind"]]
        wdt = round(_lerp(1.1, 5.6, frac), 2)
        op = round(_lerp(0.28, 0.9, frac), 3)
        var = "--pos" if e["kind"] == "pos" else "--neg"
        parts.append('<line data-a="%s" data-b="%s" data-aff="%s" data-res="%s" data-kind="%s" '
                     'x1="%s" y1="%s" x2="%s" y2="%s" style="stroke:var(%s);stroke-width:%s;opacity:%s"/>' % (
                         esc(e["a"]), esc(e["b"]), e["aff"], e["res"], e["kind"],
                         na["x"], na["y"], nb["x"], nb["y"], var, wdt, op))
    # 节点 + 标签（整个节点是指向该居民详页的链接——图谱即导航枢纽）
    for n in nodes:
        anchor = "start" if n["cos"] >= 0 else "end"
        lx = n["x"] + (24 if n["cos"] >= 0 else -24)
        col = n["color"] if str(n["color"]).startswith("#") else "#888"
        parts.append('<a href="%s#npc-%s"><g class="net-node">'
                     '<circle cx="%s" cy="%s" r="17" fill="%s" stroke="%s" stroke-width="3.5"/>'
                     '<text x="%s" y="%s" text-anchor="%s">%s</text></g></a>' % (
                         esc(link_prefix), esc(n["id"]),
                         n["x"], n["y"], esc(col), esc(n["ring"]),
                         round(lx, 1), round(n["y"] + 4, 1), anchor, esc(n["name"])))
    parts.append('</svg>')
    return "".join(parts)


def render_overview(w, ov, link_prefix=""):
    """总览 HTML 片段（三视图）。link_prefix 让节点/年表指向 town_wiki 的 NPC 锚（同页='' 或 'town_wiki.html'）。"""
    m = w.meta
    P = []
    n_friend = sum(1 for e in ov["edges"] if e["kind"] == "pos")
    n_rival = sum(1 for e in ov["edges"] if e["kind"] == "neg")

    P.append('<section class="ov" id="ov-network">')
    P.append('<h2>① 关系图谱 · 全镇社会网络</h2>')
    P.append('<p class="lead">%d 位居民为节点（描边=派系），带符号关系为边：'
             '<span class="pos">绿=亲密</span> / <span class="neg">红=怨气·结怨</span>，粗细与深浅=强度。'
             '仅显示 |亲密|≥%d 或 怨气≥%d 的关系（%d 条边 / 全镇 %d 对；友好 %d · 敌对 %d）。'
             '布局为按派系分弧的确定性圆布局（无随机、无力导）。</p>' % (
                 m["n_agents"], int(EDGE_AFF_FRIEND), int(EDGE_RES_RIVAL),
                 len(ov["edges"]), ov["n_pairs_total"], n_friend, n_rival))
    P.append('<div class="netwrap">%s</div>' % render_network_svg(w, ov, link_prefix))
    P.append('<div class="legend">'
             '<span><i class="ln" style="border-top-color:var(--pos)"></i>亲密（越粗越深越亲）</span>'
             '<span><i class="ln" style="border-top-color:var(--neg)"></i>怨气/结怨（越粗越深越敌对）</span>'
             '<span><i class="dot" style="border-color:%s"></i>节点描边=所属派系</span>' % esc("#c77dff"))
    if ov["isolates"]:
        P.append('<span>孤立者（无达标关系）：%s</span>' % esc("、".join(w.name(x) for x in ov["isolates"])))
    else:
        P.append('<span>无孤立者（人人都有达标关系）</span>')
    P.append('</div></section>')

    # ── ② 镇级大事年表 ─────────────────────────────────────────────────────
    P.append('<section class="ov" id="ov-timeline">')
    P.append('<h2>② 镇级大事年表</h2>')
    P.append('<p class="lead">跨居民、按时间排的高信息事件（选举·盟约·施压·背叛·调解·接济·吐露·结盟·对质）；'
             '高频摩擦（口角、断货）聚合在下方③。每条指回其 event id，被拒/未成按 accepted 如实标。共 %d 条。</p>'
             % len(ov["timeline"]))
    if not ov["timeline"]:
        P.append('<div class="kv">本局没有可上镇级年表的高信息事件。</div>')
    else:
        P.append('<ul class="chron" data-more-label="条镇情">')
        SHOW = 24
        for i, row in enumerate(ov["timeline"]):
            e = row["e"]
            badge = ""
            if row["outcome"] == "rejected":
                badge = '<span class="badge rej">被拒</span>'
            elif row["outcome"] == "failed":
                badge = '<span class="badge fail">未成</span>'
            elif row["outcome"] == "conflict":
                badge = '<span class="badge conf">冲突</span>'
            cls = "more" if i >= SHOW else ""
            P.append('<li class="%s" data-ev="%d"><span class="day">%s</span>'
                     '<span class="tx">%s%s</span><span class="ev">#%d</span></li>' % (
                         cls, e["id"], esc(day_label(e["tick"])), badge, esc(row["text"]), e["id"]))
        P.append('</ul>')
    P.append('</section>')

    # ── ③ 派系与冲突概览 ───────────────────────────────────────────────────
    P.append('<section class="ov" id="ov-factions">')
    P.append('<h2>③ 派系与冲突概览</h2>')
    P.append('<p class="lead">派系归属、被围攻者（联合施压）、以及高怨气对（含彼此口角次数）——全部由关系账本与 event_log 聚合。</p>')
    P.append('<div class="ovgrid"><div>')
    P.append('<h3 class="sec">派系花名册</h3>')
    for f in ov["factions"]:
        title = ("%s 派（领 %s）" % (w.name(f["leader"]), w.name(f["leader"]))) if f["key"] else "无派系（散居）"
        mem = "、".join("%s%s" % (w.name(mid), ("（领）" if mid == f["leader"] and f["key"] else "")) for mid in f["members"])
        dot = '<span style="display:inline-block;width:10px;height:10px;border-radius:50%%;background:%s;margin-right:6px;vertical-align:1px"></span>' % esc(f["ring"])
        P.append('<div class="faccard"><div class="fh">%s%s · %d 人</div><div class="fm">%s</div></div>' % (
            dot, esc(title), len(f["members"]), esc(mem)))
    P.append('<h3 class="sec">联合施压（rally_oust 聚合）</h3>')
    if not ov["pressure"]:
        P.append('<div class="kv">本局没有联合施压。</div>')
    else:
        P.append('<table class="ovt"><tr><th>被围攻者</th><th>牵头人</th><th class="num">场次</th>'
                 '<th class="num">最多响应</th><th>event</th></tr>')
        for p in ov["pressure"]:
            insti = "、".join("%s×%d" % (w.name(k), v) for k, v in sorted(p["instigators"].items(), key=lambda kv: -kv[1]))
            refs = " ".join("#%d" % i for i in p["events"][:6]) + (" …" if len(p["events"]) > 6 else "")
            P.append('<tr><td>%s</td><td>%s</td><td class="num">%d</td><td class="num">%d</td>'
                     '<td class="evref">%s</td></tr>' % (
                         esc(w.name(p["target"])), esc(insti), len(p["events"]), p["max_backers"], esc(refs)))
        P.append('</table>')
    P.append('</div><div>')
    P.append('<h3 class="sec">高怨气对（Top，含彼此口角次数）</h3>')
    if not ov["resentment"]:
        P.append('<div class="kv">本局没有记恨记录。</div>')
    else:
        P.append('<table class="ovt"><tr><th>谁</th><th>记恨谁</th><th class="num">怨气</th>'
                 '<th class="num">亲密</th><th class="num">口角</th></tr>')
        for p in ov["resentment"][:14]:
            refs = ('<span class="evref"> %s</span>' % " ".join("#%d" % i for i in p["conflicts"][:4])) if p["conflicts"] else ""
            P.append('<tr><td>%s</td><td>%s</td><td class="num neg">%.1f</td>'
                     '<td class="num">%s</td><td class="num">%d%s</td></tr>' % (
                         esc(w.name(p["src"])), esc(w.name(p["dst"])), p["res"],
                         sign_str(p["aff"]), len(p["conflicts"]), refs))
        P.append('</table>')
    P.append('</div></div></section>')
    return "".join(P)


def build_overview_doc(w, ov):
    """独立自包含总览页（docs/media 交付用）；节点/年表回指 town_wiki.html 的 NPC 锚。"""
    m = w.meta
    body = ['<div class="wrap">']
    body.append('<header class="top"><h1>镇情总览 · 横切百科</h1>'
                '<div class="meta">seed %s · 第%d天终局 · %d 位居民 · %d 条事件账本 · Godot %s<br>'
                '关系图谱 + 镇级年表 + 派系/冲突——纯从只读投影归纳，每条指回真实 event/relationship。'
                '<a href="town_wiki.html" style="color:var(--accent)">↗ 逐居民详页</a></div></header>' % (
                    esc(m["seed"]), m.get("days", m["day"]), m["n_agents"], m["n_events"], esc(m.get("godot", ""))))
    body.append('<div class="ovnav"><a href="#ov-network">① 关系图谱</a>'
                '<a href="#ov-timeline">② 镇级年表</a><a href="#ov-factions">③ 派系与冲突</a></div>')
    body.append(render_overview(w, ov, link_prefix="town_wiki.html"))
    body.append('<div class="foot">本页由 <code>tools/gen_town_wiki.py</code> 从 '
                '<code>game/bench/wiki_dump.gd</code> 的只读投影生成。digest=%s · event_digest=%s · chain=%s。'
                '仿真侧逐字节未动（导出 JSON 未改）。</div>' % (
                    esc(m.get("digest", "")), esc(m.get("event_digest", "")), esc(m.get("chain", ""))))
    body.append('</div>')
    doc = ('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
           '<meta name="viewport" content="width=device-width,initial-scale=1">'
           '<title>镇情总览 (seed %s)</title><style>%s</style></head><body>%s'
           '<script>%s</script></body></html>') % (esc(m["seed"]), CSS, "".join(body), THEME_JS)
    return doc


def build_html(w, ov=None):
    m = w.meta
    # 预先算好每个 NPC 的 chronicle（带 outcome），也供 gate 复用。
    chron = {}
    for a in w.agents:
        evs = w.chronicle_events(a["id"])
        chron[a["id"]] = [(e, w.prose(e, a["id"])[1]) for e in evs]
    out = []
    out.append('<div class="wrap">')
    out.append('<header class="top"><h1>%s镇 · 镇民百科</h1>'
               '<div class="meta">seed %s · 第%d天终局 · %d 位居民 · %d 条事件账本 · Godot %s<br>'
               '纯只读投影（wiki_dump.gd）· 每条大事记指回其 event id · 被拒事件如实标注</div></header>' % (
                   "", esc(m["seed"]), m.get("days", m["day"]), m["n_agents"], m["n_events"], esc(m.get("godot", ""))))
    # 花名册
    out.append('<div class="roster">')
    for a in w.agents:
        color = a["color"] if a["color"].startswith("#") else "#888"
        job = (a.get("job") or {}).get("title", "居民")
        out.append('<a class="rcard" href="#npc-%s"><span class="av" style="background:%s">%s</span>'
                   '<span><span class="n">%s</span><br><span class="j">%s</span></span></a>' % (
                       esc(a["id"]), esc(color), esc(a["name"][0] if a["name"] else "?"),
                       esc(a["name"]), esc(job)))
    out.append('</div>')
    # 横切总览（AJ1）：三视图放在逐居民详页之前，作为镇情入口。
    if ov is None:
        ov = build_overview(w)
    out.append('<div class="ovnav"><a href="#ov-network">① 关系图谱</a>'
               '<a href="#ov-timeline">② 镇级年表</a><a href="#ov-factions">③ 派系与冲突</a></div>')
    out.append(render_overview(w, ov, link_prefix=""))
    for a in w.agents:
        out.append(render_agent(w, a, chron[a["id"]]))
    out.append('<div class="foot">本页由 <code>tools/gen_town_wiki.py</code> 从 '
               '<code>game/bench/wiki_dump.gd</code> 的只读投影生成。digest=%s · event_digest=%s · chain=%s。'
               '仿真侧逐字节未动（见 docs/115 的 A/B + 金标证据）。</div>' % (
                   esc(m.get("digest", "")), esc(m.get("event_digest", "")), esc(m.get("chain", ""))))
    out.append('</div>')
    body = "".join(out)
    doc = ('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
           '<meta name="viewport" content="width=device-width,initial-scale=1">'
           '<title>%s镇 · 镇民百科 (seed %s)</title><style>%s</style></head><body>%s'
           '<script>%s</script></body></html>') % ("", esc(m["seed"]), CSS, body, THEME_JS)
    return doc, chron


# ── 总览可追溯性校验（AJ1）：每条边/年表项/施压/怨气对都指回真实 relationship/event ──────
def validate_overview(w, ov):
    """返回 violations 列表：总览里任何一条【无源可指】或【与源不符】的项都记一条。空 = 全可追溯。"""
    ev_by_id = {e["id"]: e for e in w.events}
    byid = w.by_id
    V = []
    # ① 每条网络边 → 一条真实 relationships 记录，且 aff/res 由源账本重算得出（非发明/非篡改）
    for e in ov["edges"]:
        a, b = e["a"], e["b"]
        if a not in byid or b not in byid:
            V.append("网络边引用了不存在的居民 (%s,%s)" % (a, b)); continue
        ra = byid[a]["relationships"].get(b)
        rb = byid[b]["relationships"].get(a)
        if ra is None and rb is None:
            V.append("网络边 (%s,%s) 在关系账本里没有任何记录（发明的边）" % (a, b)); continue
        vals = [r["affinity"] for r in (ra, rb) if r is not None]
        aff = round(sum(vals) / len(vals), 2)
        res = round(max((ra["resentment"] if ra else 0.0), (rb["resentment"] if rb else 0.0)), 2)
        if abs(aff - e["aff"]) > 0.01 or abs(res - e["res"]) > 0.01:
            V.append("网络边 (%s,%s) 数值(aff=%s,res=%s)与账本重算(aff=%s,res=%s)不符" % (a, b, e["aff"], e["res"], aff, res))
    # ② 每条年表项 → 真实 event id；社交类 accepted=false 必须标 rejected（不得写成 happened）
    for row in ov["timeline"]:
        e = row["e"]
        if e["id"] not in ev_by_id:
            V.append("年表引用了不存在的 event id %s（发明情节）" % e["id"]); continue
        if e["type"] in SOCIAL_REBUFF and not e["accepted"] and row["outcome"] != "rejected":
            V.append("年表社交 event #%d(%s,accepted=false) 未标成被拒(outcome=%s)" % (e["id"], e["type"], row["outcome"]))
    # ③ 联合施压项 → 真实 rally_oust event，且 target 一致
    for p in ov["pressure"]:
        for eid in p["events"]:
            e = ev_by_id.get(eid)
            if e is None or e["type"] != "rally_oust":
                V.append("施压项引用了非 rally_oust/不存在的 event #%s" % eid)
            elif e["target"] != p["target"]:
                V.append("施压项 event #%d 的 target 与聚合键(%s)不符" % (eid, p["target"]))
    # ④ 高怨气对 → 真实 relationship（怨气值一致）；引用的口角 → 真实 conflict event
    for p in ov["resentment"]:
        r = byid[p["src"]]["relationships"].get(p["dst"]) if p["src"] in byid else None
        if r is None:
            V.append("怨气对 (%s→%s) 无关系记录" % (p["src"], p["dst"])); continue
        if abs(r["resentment"] - p["res"]) > 0.01:
            V.append("怨气对 (%s→%s) 怨气值与账本不符" % (p["src"], p["dst"]))
        for eid in p["conflicts"]:
            e = ev_by_id.get(eid)
            if e is None or e["type"] != "conflict":
                V.append("怨气对 (%s→%s) 引用了非 conflict event #%s" % (p["src"], p["dst"], eid))
    # ⑤ 派系成员 → 真实居民，且 faction 字段与聚合键一致
    for f in ov["factions"]:
        for mid in f["members"]:
            if mid not in byid:
                V.append("派系成员 %s 不是真实居民" % mid)
            elif byid[mid]["faction"] != f["key"]:
                V.append("派系成员 %s 的 faction 与聚合键(%s)不符" % (mid, f["key"]))
    return V


def overview_negative_control(w, ov):
    """负对照：往总览里注入 4 种伪造项，断言 validate_overview 逐一抓到（抓不到=门是装饰）。"""
    ev_ids = {e["id"] for e in w.events}
    fake_eid = (max(ev_ids) + 9999) if ev_ids else 999999
    variants = []
    edges = list(ov["edges"])
    # V1 幽灵边：一对在关系账本里根本不存在的居民
    edges.append({"a": w.agents[0]["id"], "b": "__ghost__", "aff": 99.0, "res": 0.0, "kind": "pos", "weight": 99.0})
    variants.append("V1 幽灵边 %s—__ghost__" % w.agents[0]["id"])
    # V2 篡改数值：真实一对，但把亲密 +50 谎报
    if ov["edges"]:
        base = dict(ov["edges"][0]); base["aff"] = round(base["aff"] + 50.0, 2)
        edges.append(base)
        variants.append("V2 篡改 %s—%s 的亲密" % (base["a"], base["b"]))
    timeline = list(ov["timeline"])
    # V3 不存在的 event id（凭空捏造的年表项）
    timeline.append({"e": {"id": fake_eid, "tick": 1, "type": "aid", "accepted": True}, "outcome": "done", "text": "凭空捏造"})
    variants.append("V3 不存在 event #%d" % fake_eid)
    # V4 把一条真实的【社交被拒】谎标成 happened
    v4 = next((e for e in w.events if e["type"] in SOCIAL_REBUFF and not e["accepted"]), None)
    if v4 is not None:
        timeline.append({"e": v4, "outcome": "done", "text": "把被拒讲成做成了"})
        variants.append("V4 社交被拒 #%d 谎标 done" % v4["id"])
    poisoned = dict(ov); poisoned["edges"] = edges; poisoned["timeline"] = timeline
    viol = validate_overview(w, poisoned)
    hits = {
        "V1": any("__ghost__" in x or "不存在的居民" in x for x in viol),
        "V2": any("网络边" in x and "不符" in x for x in viol),
        "V3": any(str(fake_eid) in x for x in viol),
        "V4": (v4 is None) or any(("#%d" % v4["id"]) in x and "被拒" in x for x in viol),
    }
    return all(hits.values()), {"variants": variants, "hits": hits, "n_injected": len(variants),
                                "n_violations": len(viol), "violations": viol}


# ── 可追溯性门（§2.5）──────────────────────────────────────────────────────
def run_gate(w, chron, ov=None):
    """断言：①每条大事记都指回一条真实 event id；②每个社交类 accepted=false 都被标成 rejected（非 happened）。"""
    ev_ids = {e["id"] for e in w.events}
    report = {"detects": [], "does_not_detect": [], "confidence": "", "checks": {}}
    violations = []
    total_lines = 0
    social_false_total = 0
    social_false_marked = 0
    # ① 追溯：每条 chronicle 行的 data-ev 必须是真实 event id
    for aid, rows in chron.items():
        for e, outcome in rows:
            total_lines += 1
            if e["id"] not in ev_ids:
                violations.append("agent %s 大事记引用了不存在的 event id %s" % (aid, e["id"]))
            # ② 社交被拒如实标
            if e["type"] in SOCIAL_REBUFF and not e["accepted"]:
                social_false_total += 1
                if outcome == "rejected":
                    social_false_marked += 1
                else:
                    violations.append("agent %s 的社交 event #%d(%s,accepted=false) 未被标成被拒（outcome=%s）"
                                      % (aid, e["id"], e["type"], outcome))
    # 全局对账：投影里社交类 accepted=false 的总数（应 == 被逐条如实标注的数——凡当事人页都覆盖）
    global_social_false = sum(1 for e in w.events if e["type"] in SOCIAL_REBUFF and not e["accepted"])

    # ── AJ1 横切总览的可追溯性（正对照 + 负对照）──────────────────────────────
    if ov is None:
        ov = build_overview(w)
    ov_violations = validate_overview(w, ov)
    neg_ok, neg = overview_negative_control(w, ov)

    report["checks"] = {
        "chronicle_lines": total_lines,
        "all_lines_traceable": len(violations) == 0,
        "social_rejected_in_pages": social_false_total,
        "social_rejected_marked": social_false_marked,
        "global_social_rejected_events": global_social_false,
        "violations": violations[:40],
        "n_violations": len(violations),
        # 总览三视图
        "overview": {
            "n_edges": len(ov["edges"]),
            "n_pairs_total": ov["n_pairs_total"],
            "n_timeline": len(ov["timeline"]),
            "n_pressure_targets": len(ov["pressure"]),
            "n_resentment_pairs": len(ov["resentment"]),
            "n_factions": len(ov["factions"]),
            "all_traceable": len(ov_violations) == 0,
            "n_violations": len(ov_violations),
            "violations": ov_violations[:40],
        },
        # 负对照：喂假边/假年表项/篡改值/漏标被拒，门必须逐一抓到
        "negative_control": {
            "injected": neg["variants"],
            "each_variant_detected": neg["hits"],
            "all_detected": neg_ok,
            "n_violations_when_poisoned": neg["n_violations"],
        },
    }
    report["detects"] = [
        "大事记引用了投影里不存在的 event id（发明情节/串号）⇒ 门红。本次 %d 行全部命中真实 id。" % total_lines,
        "社交类 accepted=false 的事件被渲染成 happened（漏标被拒，AA2 的 27.4%% 病）⇒ 门红。"
        "本次 %d/%d 条社交被拒事件被如实标注。" % (social_false_marked, social_false_total),
        "【总览】网络边指向关系账本里不存在的一对居民，或边的 亲密/怨气 与账本重算不符 ⇒ 门红"
        "（负对照 V1/V2 实测抓到）。",
        "【总览】镇级年表引用不存在的 event id，或把社交被拒谎标成 happened ⇒ 门红"
        "（负对照 V3/V4 实测抓到）。",
    ]
    report["does_not_detect"] = [
        "大事记/年表措辞的语义保真度（subject 指错人、器物/年代错等）——只校 event.accepted 与 id 这两位，不校文案质量。",
        "Sim 自身把事件标错 accepted 的情形（wiki 层如实转写 Sim 的字段，不复核 Sim 的判定）。",
        "非社交类 accepted=false（shortage/conflict 结构性 false）——那不是被拒，按类型另行叙述，故意不套被拒框。",
        "witness-only 参与的事件不逐条上大事记（避免刷屏），故不在追溯范围内（可追溯性只覆盖当事人行）。",
        "【总览】收边阈值/年表类型选择是否'合适'——门只校【被显示的每一项都有真源且数值一致】，"
        "不评判取舍口径（阈值写在图注里透明交代）。",
        "【总览】边把有向关系合并成无向时的聚合口径（亲密取均值/怨气取最大）是否'最优'——门只断言渲染值=按此口径重算值。",
    ]
    report["confidence"] = ("在 seed %s / %d 天 / %d 个 NPC 的投影上校验：N=%d 条大事记行、%d 条社交被拒事件；"
                            "跨页对账全镇社交被拒 event 共 %d 条。总览：%d 条边 / %d 条年表 / %d 个施压目标 / "
                            "%d 个怨气对全部可追溯；负对照注入 %d 种伪造项，逐一被抓（N=%d）。" % (
                                w.meta["seed"], w.meta["days"], w.meta["n_agents"],
                                total_lines, social_false_total, global_social_false,
                                len(ov["edges"]), len(ov["timeline"]), len(ov["pressure"]),
                                len(ov["resentment"]), neg["n_injected"], neg["n_injected"]))
    ok = (len(violations) == 0 and social_false_marked == social_false_total
          and len(ov_violations) == 0 and neg_ok)
    report["verdict"] = "PASS" if ok else "FAIL"
    return ok, report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--md", action="store_true", help="额外导出每个 NPC 的 markdown 样例")
    args = ap.parse_args()

    with io.open(args.inp, encoding="utf-8") as f:
        data = json.load(f)
    w = Wiki(data)
    os.makedirs(args.outdir, exist_ok=True)

    ov = build_overview(w)  # 一份总览数据，渲染器与 --gate 共用（杜绝分叉）
    doc, chron = build_html(w, ov)
    html_path = os.path.join(args.outdir, "town_wiki.html")
    with io.open(html_path, "w", encoding="utf-8") as f:
        f.write(doc)
    print("[gen] HTML → %s (%d bytes)" % (html_path, len(doc.encode("utf-8"))))

    # 独立自包含总览页（docs/media 交付用）
    ov_doc = build_overview_doc(w, ov)
    ov_path = os.path.join(args.outdir, "town_overview.html")
    with io.open(ov_path, "w", encoding="utf-8") as f:
        f.write(ov_doc)
    print("[gen] 总览 HTML → %s (%d bytes; 边=%d 年表=%d 施压目标=%d 怨气对=%d)" % (
        ov_path, len(ov_doc.encode("utf-8")), len(ov["edges"]), len(ov["timeline"]),
        len(ov["pressure"]), len(ov["resentment"])))

    if args.md:
        md_dir = os.path.join(args.outdir, "md")
        os.makedirs(md_dir, exist_ok=True)
        for a in w.agents:
            md = render_markdown(w, a, chron[a["id"]])
            p = os.path.join(md_dir, "%s.md" % a["id"])
            with io.open(p, "w", encoding="utf-8") as f:
                f.write(md)
        print("[gen] markdown → %s/*.md (%d 页)" % (md_dir, len(w.agents)))

    rc = 0
    if args.gate:
        ok, report = run_gate(w, chron, ov)
        rep_path = os.path.join(args.outdir, "traceability_report.json")
        with io.open(rep_path, "w", encoding="utf-8") as f:
            f.write(json.dumps(report, ensure_ascii=False, indent=2))
        print("[gate] %s → %s" % (report["verdict"], rep_path))
        print("[gate] 大事记行=%d 全部可追溯=%s；社交被拒 %d/%d 如实标注；全镇社交被拒 event=%d" % (
            report["checks"]["chronicle_lines"], report["checks"]["all_lines_traceable"],
            report["checks"]["social_rejected_marked"], report["checks"]["social_rejected_in_pages"],
            report["checks"]["global_social_rejected_events"]))
        oc = report["checks"]["overview"]
        nc = report["checks"]["negative_control"]
        print("[gate] 总览：边=%d/%d对 年表=%d 施压目标=%d 怨气对=%d 全部可追溯=%s（违规 %d）" % (
            oc["n_edges"], oc["n_pairs_total"], oc["n_timeline"], oc["n_pressure_targets"],
            oc["n_resentment_pairs"], oc["all_traceable"], oc["n_violations"]))
        print("[gate] 负对照：注入 %s → 逐项抓到=%s（毒化后违规 %d 条）" % (
            "/".join(k for k in nc["each_variant_detected"]), nc["all_detected"],
            nc["n_violations_when_poisoned"]))
        if not ok:
            for v in report["checks"]["violations"]:
                print("   VIOLATION(chron):", v)
            for v in oc["violations"]:
                print("   VIOLATION(overview):", v)
            if not nc["all_detected"]:
                print("   NEG-CONTROL FAILED: 某伪造项未被门抓到 →", nc["each_variant_detected"])
            rc = 1
    return rc


def render_markdown(w, a, chron_out):
    aid = a["id"]
    L = []
    L.append("# %s（%s）\n" % (a["name"], aid))
    L.append("- **性格**：%s" % "、".join(a["traits"]))
    if a.get("bio"):
        L.append("- **简介**：%s" % a["bio"])
    job = a.get("job") or {}
    if job:
        shift = "、".join(RHYTHM_LABEL.get(s, s) for s in job.get("shift", [])) or "全天"
        L.append("- **职业**：%s · 班次 %s · 日薪 %d" % (job.get("title", ""), shift, job.get("wage", 0)))
    L.append("\n## 五需求（终局）\n")
    for nid in NEED_ORDER:
        if nid in a["needs"]:
            L.append("- %s：%.0f" % (w.needs_meta.get(nid, {}).get("label", nid), a["needs"][nid]))
    L.append("\n## 关系账本\n")
    rels = sorted(a["relationships"].items(), key=lambda kv: -abs(kv[1]["affinity"]) - kv[1]["resentment"] * 0.5)
    for oid, r in rels[:12]:
        if r["familiarity"] <= 0 and r["affinity"] == 0 and r["resentment"] == 0:
            continue
        lab, _ = rel_label(r)
        L.append("- %s（%s）：亲密 %s / 信任 %s / 怨气 %.1f / 名声 %s" % (
            w.name(oid), lab, sign_str(r["affinity"]), sign_str(r["trust"]), r["resentment"], sign_str(r["standing"])))
    L.append("\n## 信念与见闻\n")
    for bid, b in a["beliefs"].items():
        if isinstance(b, dict) and b.get("claim"):
            L.append("- %s（来源 %s · %s）" % (b["claim"], b.get("via", ""), day_label(b.get("tick", 0))))
    L.append("\n## 大事记（每条标注依据的 event id）\n")
    for e, outcome in chron_out:
        text, _ = w.prose(e, aid)
        tag = {"rejected": "【被拒】", "failed": "【未成】", "conflict": "【冲突】"}.get(outcome, "")
        L.append("- %s %s%s  `#%d @%s`" % (day_label(e["tick"]), tag, text, e["id"], "tick%d" % e["tick"]))
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    sys.exit(main())
