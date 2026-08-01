#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""recalc.py — **把"这个数旁边要有一条重算它的命令"从宣言变成门。**

## 为什么是门而不是红线（编号 82 · U3；派单原话「门比宣言值钱」）

S2（编号 73 §二·3）在 11 条能拿到"记录值 vs 今天值"的臂上量出一条统一结论：

> **9 条会【重算并打印】的臂，记录全部今天仍然成立（其中四条逐位相同）；
> 2 族不重算的（打印冻结字面量 / 只把余量留在注释里），记录全部过期。**

⇒ 一条**宣言**（"以后写数字要附命令"）落在第二族里：没有人会去查它。
本工具落在第一族里：**每次运行都从文档里现读那个数、现跑那条命令、现比。**

## 它没有冻结字面量——这是它自己的设计红线

- **期望值不写在本工具里，也不写在注册表里**：由 `locator` 正则**从文档正文里现抓**。
  ⇒ 全仓这个数**只有一份**（在文档里），改文档就是改期望值。
- **实测值不写在任何地方**：由 `command` 现跑现出。
- ⇒ 本工具里唯一被冻结的是 **`tol`（容差）**，而容差不是测量值。

## 判据（每一条都会红，不是装饰）

对每一条 `gate: true` 的条目：
  1. `locator` 在文档里**必须恰好命中一次**。0 次 = 那句话被改写/删掉了；>1 次 = 正则不够窄。
     **两种都红。**（这一条比数值比对更早生效：它守的是"这个数还在不在它该在的地方"。）
  2. `command` 必须 rc=0。
  3. `extract` 在命令输出里必须恰好命中一次。
  4. `|文档值 − 实测值| <= tol`。

对 `gate: false` 的条目：**必须写 `why`**（为什么不上门）。空的 `why` 也红——
理由与 [docs/41 §2.5](41-baton-contract.md) 那条 `does_not_detect` 一样：
**这一栏空着 = 你没想过。**

## 用法

    python tools/recalc.py --verify        # 全跑，打印逐条对照（不判红）
    python tools/recalc.py --gate          # CI 用：gate:true 的条目有一条不对就 rc=1
    python tools/recalc.py --list
    python tools/recalc.py --self-test     # 负对照（四条，见下）

## 负对照（`--self-test`，每次跑都跑）

在临时目录里造一份文档 + 一份注册表 + 一条真会跑的命令：
  ① 一致 ⇒ **PASS**；
  ② 只把**文档里的数**改掉一位 ⇒ **必须 FAIL**（"改一个参数必须不同"）；
  ③ 只把**命令的输出**改掉一位 ⇒ **必须 FAIL**；
  ④ 把 `locator` 改成命中 0 次 ⇒ **必须 FAIL**（且失败信息要说的是"锚点丢了"而不是数值不符）。
"""
import argparse
import json
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = os.path.join(ROOT, "tools", "recalc_registry.json")


def _one(pattern, text, what):
    """恰好命中一次才算数。返回 (值, 错误信息)。"""
    ms = list(re.finditer(pattern, text))
    if len(ms) == 0:
        return None, "%s：正则一次都没命中 —— 那句话被改写或删掉了" % what
    if len(ms) > 1:
        return None, "%s：正则命中 %d 次（要求恰好 1 次）—— 锚点不够窄，比中的可能不是同一个量" % (what, len(ms))
    try:
        return float(ms[0].group(1)), None
    except (IndexError, ValueError):
        return None, "%s：命中了但捕获组不是一个数（%r）" % (what, ms[0].group(0)[:60])


def run_command(spec, root=ROOT, cache=None):
    key = json.dumps(spec["argv"])
    if cache is not None and key in cache:
        return cache[key]
    p = subprocess.run(spec["argv"], cwd=root, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    res = (p.returncode, (p.stdout or "") + (p.stderr or ""))
    if cache is not None:
        cache[key] = res
    return res


def verify(reg, root=ROOT, only_gated=False):
    """返回 (rows, n_fail_gated, n_fail_ungated)。"""
    cache = {}
    rows = []
    for e in reg["entries"]:
        if only_gated and not e.get("gate"):
            continue
        r = dict(id=e["id"], doc=e["doc"], gate=bool(e.get("gate")),
                 doc_value=None, live_value=None, ok=None, err=None,
                 why=e.get("why", ""))
        # 结构判据：不上门的必须说明为什么
        if not e.get("gate") and not e.get("why", "").strip():
            r["err"] = "gate:false 但 why 是空的 —— 契约 §2.5 同一条规矩：这一栏空着 = 你没想过"
            r["ok"] = False
            rows.append(r)
            continue
        path = os.path.join(root, e["doc"])
        if not os.path.exists(path):
            r["err"] = "文档不存在：%s" % e["doc"]
            r["ok"] = False
            rows.append(r)
            continue
        with open(path, encoding="utf-8") as f:
            doc_text = f.read()
        dv, err = _one(e["locator"], doc_text, "locator@" + e["doc"])
        if err:
            r["err"] = err
            r["ok"] = False
            rows.append(r)
            continue
        r["doc_value"] = dv
        rc, out = run_command(reg["commands"][e["command"]], root, cache)
        if rc != 0:
            r["err"] = "命令 rc=%d：%s" % (rc, " ".join(reg["commands"][e["command"]]["argv"]))
            r["ok"] = False
            rows.append(r)
            continue
        lv, err = _one(e["extract"], out, "extract@" + e["command"])
        if err:
            r["err"] = err
            r["ok"] = False
            rows.append(r)
            continue
        r["live_value"] = lv
        tol = float(e.get("tol", 0.0))
        r["ok"] = abs(lv - dv) <= tol
        if not r["ok"]:
            r["err"] = "文档写 %s，现跑得 %s（差 %.6g > 容差 %.6g）" % (dv, lv, abs(lv - dv), tol)
        rows.append(r)
    fg = sum(1 for r in rows if r["gate"] and not r["ok"])
    fu = sum(1 for r in rows if not r["gate"] and not r["ok"])
    return rows, fg, fu


def print_rows(rows):
    print("  %-28s %-6s %12s %12s  %s" % ("id", "上门", "文档值", "现跑值", "判决"))
    for r in rows:
        v = "✅" if r["ok"] else "❌"
        dv = "-" if r["doc_value"] is None else ("%g" % r["doc_value"])
        lv = "-" if r["live_value"] is None else ("%g" % r["live_value"])
        print("  %-28s %-6s %12s %12s  %s" % (r["id"], "是" if r["gate"] else "否", dv, lv, v))
        if r["err"]:
            print("      ↳ %s" % r["err"])
        if not r["gate"] and r["why"]:
            print("      ↳ 不上门的理由：%s" % r["why"])


# ────────────────────────── 负对照 ──────────────────────────
def self_test():
    import tempfile
    fails = []
    with tempfile.TemporaryDirectory() as td:
        os.makedirs(os.path.join(td, "docs"))
        os.makedirs(os.path.join(td, "tools"))
        doc = "docs/x.md"

        def write_doc(v):
            with open(os.path.join(td, doc), "w", encoding="utf-8") as f:
                f.write("# t\n\n实测最小间距 **%s** 个码值。\n" % v)

        def write_probe(v):
            with open(os.path.join(td, "tools", "p.py"), "w", encoding="utf-8") as f:
                f.write("print('MIN=%s')\n" % v)

        def mk(locator=r"实测最小间距 \*\*([0-9.]+)\*\*"):
            return {"commands": {"p": {"argv": [sys.executable, "tools/p.py"]}},
                    "entries": [{"id": "t", "doc": doc, "locator": locator,
                                 "command": "p", "extract": r"MIN=([0-9.]+)",
                                 "tol": 0.0, "gate": True}]}

        write_doc("17.31"); write_probe("17.31")
        rows, fg, _ = verify(mk(), root=td)
        print("  ① 一致            → %s" % ("PASS" if fg == 0 else "FAIL:" + str(rows[0]["err"])))
        if fg != 0:
            fails.append("①: 一致的情况下红了")

        write_doc("17.32")                       # 只改文档
        rows, fg, _ = verify(mk(), root=td)
        print("  ② 只改文档里的数   → %s（期望 FAIL）  %s" % ("FAIL" if fg else "PASS", rows[0]["err"] or ""))
        if fg == 0:
            fails.append("②: 改了文档值却没红 —— 这道门没牙")

        write_doc("17.31"); write_probe("17.30")  # 只改命令输出
        rows, fg, _ = verify(mk(), root=td)
        print("  ③ 只改命令的输出   → %s（期望 FAIL）  %s" % ("FAIL" if fg else "PASS", rows[0]["err"] or ""))
        if fg == 0:
            fails.append("③: 改了实测值却没红")

        write_probe("17.31")
        rows, fg, _ = verify(mk(locator=r"这句话不存在 ([0-9.]+)"), root=td)
        got = rows[0]["err"] or ""
        print("  ④ 锚点丢了         → %s（期望 FAIL 且信息说锚点）  %s" % ("FAIL" if fg else "PASS", got))
        if fg == 0:
            fails.append("④: 锚点丢了却没红")
        elif "命中" not in got:
            fails.append("④: 红了但失败信息没说锚点问题：%s" % got)

        # ⑤ gate:false 且 why 为空 ⇒ 必须红（结构判据，不是数值判据）
        reg = mk()
        reg["entries"][0]["gate"] = False
        reg["entries"][0]["why"] = ""
        rows, _, fu = verify(reg, root=td)
        print("  ⑤ 不上门且没写理由 → %s（期望 FAIL）" % ("FAIL" if fu else "PASS"))
        if fu == 0:
            fails.append("⑤: gate:false 没写 why 却没红")

    if fails:
        for f in fails:
            print("  ❌ " + f)
        print("=== RECALC SELFTEST FAIL ❌ ===")
        return 1
    print("=== RECALC SELFTEST PASS ✅（五条：一致过 / 改文档红 / 改实测红 / 丢锚点红 / 缺理由红）===")
    return 0


def main():
    ap = argparse.ArgumentParser(description="可重算注册表：从文档现读期望值、现跑命令、现比")
    ap.add_argument("--registry", default=REGISTRY)
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()

    if a.self_test:
        return self_test()

    with open(a.registry, encoding="utf-8") as f:
        reg = json.load(f)

    if a.list:
        for e in reg["entries"]:
            print("  %-28s %-6s %s  ←  %s"
                  % (e["id"], "门" if e.get("gate") else "记录", e["doc"],
                     " ".join(reg["commands"][e["command"]]["argv"])))
        return 0

    rows, fg, fu = verify(reg)
    n_gate = sum(1 for r in rows if r["gate"])
    print("=== recalc · 注册表 %d 条（上门 %d 条 / 只记录 %d 条）==="
          % (len(rows), n_gate, len(rows) - n_gate))
    print_rows(rows)
    print("  ── 上门的 %d 条：%d 条对得上，%d 条对不上 ──" % (n_gate, n_gate - fg, fg))
    if fu:
        print("  ── 另有 %d 条【只记录】的条目也对不上（不判红，见上面各自的理由）──" % fu)
    if a.gate:
        if fg:
            print("=== RECALC GATE: FAIL ❌ ===")
            return 1
        print("=== RECALC GATE: PASS ✅（%d 条数字现读现算现比）===" % n_gate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
