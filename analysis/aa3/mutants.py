# -*- coding: utf-8 -*-
"""AA3 · #43 的探测包络（docs/41 §2.5）——**跑出来的**变异体，不是想出来的。

每个变异体：git 树之外的隔离副本 → 打一处补丁 → `Harness --seeds 1-4 --days 60` → 只看 #43 那一行。
用法：python analysis/aa3/mutants.py <scratch_dir> <godot> [only_name]
"""
import io, os, shutil, subprocess, sys

SIM = "game/scripts/Sim.gd"
PROD = "game/data/production.json"


def sub(path, old, new, count=1):
    s = io.open(path, encoding="utf-8").read()
    if s.count(old) < 1:
        raise SystemExit("patch anchor not found in %s: %r" % (path, old[:80]))
    io.open(path, "w", encoding="utf-8").write(s.replace(old, new, count))


# ── 变异体定义（名字 → 期望 → 打补丁的函数）────────────────────────────────────
def m1_no_witness(root):
    """① 把消费侧的 witnesses 拆回恒 [] —— 应红（arm ① 通道断了）"""
    sub(os.path.join(root, SIM),
        "var twits: Array = _nearby_agents(ag) if not tc.is_empty() else []",
        "var twits: Array = []")


def m2_no_fallout(root):
    """② 把 _trade_fallout 短路（只留目击者、不写信念/记忆）—— 应红（arm ② 没人知道）"""
    sub(os.path.join(root, SIM),
        "func _trade_fallout(buyer: Dictionary, vendor_id: String, seen: Array, action: String, tc: Dictionary) -> void:\n"
        "\tif int(_trade_day.get(vendor_id, -1)) == day:",
        "func _trade_fallout(buyer: Dictionary, vendor_id: String, seen: Array, action: String, tc: Dictionary) -> void:\n"
        "\tif true:\n\t\treturn\n"
        "\tif int(_trade_day.get(vendor_id, -1)) == day:")


def m3_global_spill(root):
    """③ 把目击者接成 transfer 的【全局副作用】—— 应红（arm ③ 不外溢）"""
    sub(os.path.join(root, SIM),
        "\tvar ev := _log_event(\"pay\", from_id, to_id, \"\", true, witnesses, reason)",
        "\tvar _w2: Array = witnesses\n"
        "\tif _w2.is_empty() and _agent_by_id.has(from_id):\n"
        "\t\t_w2 = _nearby_agents(_agent_by_id[from_id])\n"
        "\tvar ev := _log_event(\"pay\", from_id, to_id, \"\", true, _w2, reason)")


def m4_wrong_subject(root):
    """④ 张冠李戴：信念主语写成 town —— 应红（arm ② subject 不对）"""
    sub(os.path.join(root, SIM),
        "s[\"beliefs\"][bid] = {\"claim\": claim, \"subject\": vendor_id, \"source\": \"__seen__\", \"via\": \"seen\", \"tick\": tick_no}",
        "s[\"beliefs\"][bid] = {\"claim\": claim, \"subject\": \"town\", \"source\": \"__seen__\", \"via\": \"seen\", \"tick\": tick_no}")


def m5_standing_on(root):
    """⑤ 把 standing 从出货的 0.0 抬到镜像值 0.5 —— 应【绿】（本门不查 standing）"""
    sub(os.path.join(root, PROD), '"standing": 0.0,', '"standing": 0.5,')


def m6_fake_witness(root):
    """⑥ 目击者伪造成【全镇所有人】（大多不在场）—— 应【绿】（本门不查是否属实）"""
    sub(os.path.join(root, SIM),
        "var twits: Array = _nearby_agents(ag) if not tc.is_empty() else []",
        "var twits: Array = agents.duplicate() if not tc.is_empty() else []")


def m7_no_dayquota(root):
    """⑦ 拆掉日名额（后果逐笔写）—— 应【绿】（本门不查投放量）"""
    sub(os.path.join(root, SIM),
        "\tif int(_trade_day.get(vendor_id, -1)) == day:\n\t\treturn",
        "\tif false:\n\t\treturn")


def m8_free_market(root):
    """⑧ 把赶集改成【全免费】(vendor.price 3→0) —— 应【绿】：人→人成交归零 ⇒ 走豁免线【静默通过】"""
    sub(os.path.join(root, PROD), '"title": "商贩", "action": "赶集", "price": 3,',
        '"title": "商贩", "action": "赶集", "price": 0,')


MUTANTS = [
    ("m1_no_witness", "红", m1_no_witness),
    ("m2_no_fallout", "红", m2_no_fallout),
    ("m3_global_spill", "红", m3_global_spill),
    ("m4_wrong_subject", "红", m4_wrong_subject),
    ("m5_standing_on", "绿", m5_standing_on),
    ("m6_fake_witness", "绿", m6_fake_witness),
    ("m7_no_dayquota", "绿", m7_no_dayquota),
    ("m8_free_market", "绿", m8_free_market),
]


def main():
    scratch, godot = sys.argv[1], sys.argv[2]
    only = sys.argv[3] if len(sys.argv) > 3 else ""
    here = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    out = io.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "mutants.txt"),
                  "a", encoding="utf-8")
    for name, expect, patch in MUTANTS:
        if only and only != name:
            continue
        root = os.path.join(scratch, "mut_" + name)
        if os.path.isdir(root):
            shutil.rmtree(root)
        os.makedirs(root)
        # 忽略 .godot 导入缓存：CI 跑过之后它里面会出现超长文件名，Windows 上 copytree 会炸；
        # 缺它 godot 自己会重新 import（只是第一跑慢一点），对判决没有影响。
        shutil.copytree(os.path.join(here, "game"), os.path.join(root, "game"),
                        ignore=shutil.ignore_patterns(".godot"))
        patch(root)
        log = os.path.join(root, "run.txt")
        with io.open(log, "wb") as fh:
            subprocess.call([godot, "--headless", "--path", os.path.join(root, "game"),
                             "--script", "res://bench/Harness.gd", "--",
                             "--seeds", "1-4", "--days", "60"],
                            stdout=fh, stderr=fh, shell=(os.name == "nt"))
        txt = io.open(log, encoding="utf-8", errors="replace").read()
        line43 = [l for l in txt.splitlines() if "#43" in l]
        verdict = [l for l in txt.splitlines() if "S0 GATE" in l]
        out.write("── %s（期望：%s）%s\n" % (name, expect, patch.__doc__.strip()))
        for l in line43 + verdict:
            out.write("   " + l.strip() + "\n")
        # 首违那一行的下一行带 detail
        for i, l in enumerate(txt.splitlines()):
            if "#43" in l and "❌" in l:
                out.write("   " + txt.splitlines()[i].strip()[:400] + "\n")
        out.write("\n")
        out.flush()
        print(name, "done")
    out.close()


if __name__ == "__main__":
    main()
