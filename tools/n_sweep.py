#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""V2 · 逐 N 扫描的调度器（**只读诊断**：只跑 bench/ScaleSupply.gd，不改任何仿真侧文件）。

为什么要一个调度器而不是手敲 8×3 条命令：
  · docs/41 §1 要求「跑矩阵前先清场，并断言"每个输出文件只有一段汇总"」——
    杀进程在并行期是**禁止**的（会杀掉别的棒），所以本仓库的替代纪律是
    **唯一输出路径 + 逐文件断言**。手敲命令没有地方放那条断言，于是它总被跳过。
    本脚本把断言写在收活的那一步：每个 jsonl 必须恰好 K 行、seed 集合恰好等于请求的那一批、
    且同一 (arm,N,seed) 三元组在整个矩阵里只出现一次。任何一条不成立 ⇒ 当场退出非 0。
  · 8 个 N × 3 条臂串行要 5 小时以上。本脚本按 (arm,N,seed 块) 切片并发，
    **每片一个独立文件**，所以并发不会让两次运行交织进同一个文件（那正是 §1 警告的那件事）。

它【不】做的事：
  · 不做任何统计。汇总在 tools/n_curve.py 里，判据从源码现读（docs/41 §5 / S2：
    打印冻结字面量的都会过期）。
  · 不杀任何进程。看到别人的 godot 在跑就让它跑（docs/41 §1）。

用法：
  python tools/n_sweep.py --plan <plan.json> --outdir analysis/v2/raw [--jobs 12] [--dry-run]

plan.json 形如：
  {"godot": "...", "cells": [{"arm": "ship", "gamedir": "game", "n": 24,
                              "seeds": [1,2,...], "days": 60}, ...]}
"""
import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CHUNK_DEFAULT = 6

# Windows 控制台默认 GBK ⇒ 打 ✅ 会抛 UnicodeEncodeError，把一次【成功】的运行变成 rc=1。
# 实测踩到过一次（analysis/v2/sweep_deep.txt 末尾）：断言全过、数据齐全，而退出码是 1。
# 这正是 docs/41 §四「读输出不读退出码」的又一个实例 —— 但工具自己不该制造这种噪声。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def _seeds_arg(seeds):
    """ScaleSupply 的 --seeds 接 "a-b" 或 "a,b,c"。连续段用区间，省得命令行过长。"""
    seeds = sorted(seeds)
    if seeds == list(range(seeds[0], seeds[-1] + 1)):
        return "%d-%d" % (seeds[0], seeds[-1])
    return ",".join(str(s) for s in seeds)


def _run_one(job):
    godot, gamedir, n, seeds, days, out_path, log_path = job
    t0 = time.time()
    cmd = [godot, "--headless", "--path", gamedir,
           "--script", "res://bench/ScaleSupply.gd", "--",
           "--agents", str(n), "--seeds", _seeds_arg(seeds),
           "--days", str(days), "--out", out_path]
    with open(log_path, "w", encoding="utf-8", errors="replace") as lf:
        rc = subprocess.call(cmd, cwd=ROOT, stdout=lf, stderr=subprocess.STDOUT)
    return (out_path, log_path, rc, seeds, n, time.time() - t0)


def _verify(out_path, log_path, want_seeds, want_n, want_days):
    """逐文件断言（docs/41 §1：别静默分析到三次并发运行交织出来的数据）。"""
    problems = []
    if not os.path.exists(out_path):
        return ["%s: 文件不存在（跑挂了？看 %s）" % (out_path, log_path)]
    recs = []
    # 被中断的运行会留下【半行】甚至非法 UTF-8 的文件。用 errors="replace" 读进来、让 JSON 去报错，
    # 而不是让解码异常把整个调度器掀翻（实测踩到过一次：上一轮被外部看门狗杀掉，留下一个 2 字节的残文件）。
    with open(out_path, encoding="utf-8", errors="replace") as f:
        for ln, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                recs.append(json.loads(line))
            except ValueError as e:
                problems.append("%s:%d: 不是合法 JSON（%s）—— 多半是被中断的半行" % (out_path, ln, e))
    got = [int(r["seed"]) for r in recs]
    if sorted(got) != sorted(want_seeds):
        problems.append("%s: seed 集合对不上 want=%s got=%s" % (out_path, sorted(want_seeds), sorted(got)))
    if len(got) != len(set(got)):
        problems.append("%s: 有重复 seed ⇒ 同一个文件被两次运行写过（正是 docs/41 §1 说的那件事）" % out_path)
    for r in recs:
        if int(r["n_agents"]) != want_n:
            problems.append("%s: seed=%s 的 n_agents=%s ≠ 请求的 %d" % (out_path, r["seed"], r["n_agents"], want_n))
        if int(r["days"]) != want_days:
            problems.append("%s: seed=%s 的 days=%s ≠ 请求的 %d" % (out_path, r["seed"], r["days"], want_days))
    # ScaleSupply 每跑一次打一行 "=== ScaleSupply · ..." 抬头；多于一段 = 两次运行写进了同一个日志
    try:
        head = open(log_path, encoding="utf-8", errors="replace").read()
    except OSError:
        head = ""
    n_head = head.count("=== ScaleSupply · ")
    if n_head != 1:
        problems.append("%s: 抬头出现 %d 次（应为 1）⇒ 这个输出被不止一段运行写过" % (log_path, n_head))
    if "MISMATCH" in head:
        problems.append("%s: ScaleSupply 自己打了 MISMATCH（探针自算与 #40 判决不一致）" % log_path)
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--chunk", type=int, default=CHUNK_DEFAULT)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    plan = json.load(open(args.plan, encoding="utf-8"))
    godot = plan.get("godot") or os.environ.get("GODOT", "godot")
    outdir = os.path.join(ROOT, args.outdir) if not os.path.isabs(args.outdir) else args.outdir
    os.makedirs(outdir, exist_ok=True)

    # (arm, n, seed) 全局唯一性 —— 计划里就不许重复，否则两个 cell 会互相覆盖
    seen = set()
    jobs, checks = [], []
    for cell in plan["cells"]:
        arm, gamedir = cell["arm"], cell["gamedir"]
        n, days = int(cell["n"]), int(cell.get("days", 60))
        seeds = [int(s) for s in cell["seeds"]]
        for s in seeds:
            key = (arm, n, s)
            if key in seen:
                sys.exit("计划里 (arm=%s,N=%d,seed=%d) 出现两次 —— 拒绝跑" % key)
            seen.add(key)
        for i in range(0, len(seeds), args.chunk):
            blk = seeds[i:i + args.chunk]
            tag = "%s_n%02d_s%d-%d" % (arm, n, blk[0], blk[-1])
            out_path = os.path.join(outdir, tag + ".jsonl")
            log_path = os.path.join(outdir, tag + ".txt")
            if os.path.exists(out_path) and not args.dry_run:
                bad = _verify(out_path, log_path, blk, n, days)
                if not bad:
                    print("[skip] %s 已完整" % tag)
                    checks.append((out_path, log_path, blk, n, days))
                    continue
                print("[redo] %s（旧文件不完整：%s）" % (tag, bad[0]))
            jobs.append((godot, gamedir, n, blk, days, out_path, log_path))
            checks.append((out_path, log_path, blk, n, days))

    total_units = sum(j[2] * len(j[3]) for j in jobs)
    print("=== n_sweep: %d 片待跑（%d 局，%d agent-局）· jobs=%d ===" % (
        len(jobs), sum(len(j[3]) for j in jobs), total_units, args.jobs))
    if args.dry_run:
        for j in jobs:
            print("  would run: arm-dir=%s N=%d seeds=%s -> %s" % (j[1], j[2], _seeds_arg(j[3]), os.path.basename(j[5])))
        return 0

    t0 = time.time()
    done = 0
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for out_path, log_path, rc, seeds, n, dt in ex.map(_run_one, jobs):
            done += 1
            print("[%3d/%3d] rc=%d %5.0fs N=%2d seeds=%s -> %s" % (
                done, len(jobs), rc, dt, n, _seeds_arg(seeds), os.path.basename(out_path)), flush=True)

    problems = []
    for out_path, log_path, blk, n, days in checks:
        problems += _verify(out_path, log_path, blk, n, days)
    print("=== n_sweep done 墙钟=%.0fs ===" % (time.time() - t0))
    if problems:
        print("!!! %d 条断言不成立：" % len(problems))
        for p in problems:
            print("   " + p)
        return 1
    print("✅ 逐文件断言全过（seed 集合 / 无重复 / n_agents / days / 单段抬头 / 无 MISMATCH）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
