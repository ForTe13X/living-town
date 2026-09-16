#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CI lane 对账门（docs/205）。

tools/ci.sh 从 docs/205 起按 lane 切成几段，.github/workflows/ci.yml 把每条 lane 挂到一个
并行 job 上。**这就开出了一个新的失败模式：一道门可以不被删掉、只是不再被任何 job 点到，
于是它从此永远不跑，而每一个 PR 依旧全绿。** 拆并行最大的风险不是跑得慢，是这种静默的漏跑。

本门逐字对账两边，任何一侧改了而另一侧没跟上都红：

  ① ci.sh 里每一处 `lane <名>` 守卫用到的名字，都必须在 `CI_LANES_ALL` 里（防拼错——
     `lane scnes` 永远为假 ⇒ 那一段再也不跑，而 bash 不会吭一声）。
  ② `CI_LANES_ALL` 里每一条 lane 都必须至少被一处 `lane <名>` 守卫用到（防留下空名字）。
  ③ workflow 里各 job 的 `CI_LANE` 并起来必须【恰好等于】`CI_LANES_ALL`：少一条 = 那道门
     在 GHA 上不再跑；多一条 = 名字对不上 ci.sh。
  ④ 同一条 lane 不许挂在两个 job 上（重复跑只是白花分钟，但更要紧的是"它到底在哪儿跑"
     不再有唯一答案，下一次调度就没法照着读）。
  ⑤ 汇总 job `ci`（= 分支保护里那个 required context）必须 `needs:` 每一个 lane job——
     漏掉一个，那个 job 红了也拦不住合并，而 required check 依旧显示绿。

负对照：`python tools/assert_ci_lanes.py --self-test`（五条各一例，逐条必须被抓住）。
"""
import re
import sys

# Windows 控制台默认 GBK，编不出 ⇒/✅ 会直接抛 UnicodeEncodeError（同 assert_no_weights.py:22）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

CI_SH = "tools/ci.sh"
WF = ".github/workflows/ci.yml"
AGG_JOB = "ci"  # 分支保护里的 required context 名，改它要同时改 branch protection


def parse_ci_sh(text):
    m = re.search(r'^CI_LANES_ALL="([^"]*)"', text, re.M)
    if not m:
        raise SystemExit("assert_ci_lanes: tools/ci.sh 里读不到 CI_LANES_ALL=\"...\"")
    declared = m.group(1).split()
    # 只认守卫处的用法（`if lane x; then` / `lane x && ...`），不认函数定义那一行。
    used = re.findall(r'(?:^|[;&|(]\s*|\bif\s+)lane\s+([A-Za-z0-9_]+)', text, re.M)
    used = [u for u in used if u != "()"]
    return declared, sorted(set(used))


def parse_workflow(text):
    """{job 名: {"lanes": [...], "needs": [...]}}；只解析本仓库这份 workflow 的缩进形状。"""
    jobs, cur = {}, None
    lines = text.split("\n")
    in_jobs = False
    for i, ln in enumerate(lines):
        if re.match(r"^jobs:\s*$", ln):
            in_jobs = True
            continue
        if not in_jobs:
            continue
        if ln and not ln.startswith(" ") and not ln.startswith("#"):
            in_jobs = False
            continue
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", ln)
        if m:
            cur = m.group(1)
            jobs[cur] = {"lanes": [], "needs": []}
            continue
        if cur is None:
            continue
        m = re.match(r'^\s+CI_LANE:\s*"?([^"#\n]*?)"?\s*$', ln)
        if m:
            jobs[cur]["lanes"] = m.group(1).split()
        m = re.match(r"^\s+needs:\s*\[([^\]]*)\]\s*$", ln)
        if m:
            jobs[cur]["needs"] = [x.strip() for x in m.group(1).split(",") if x.strip()]
    return jobs


def check(ci_sh_text, wf_text):
    bad = []
    declared, used = parse_ci_sh(ci_sh_text)
    jobs = parse_workflow(wf_text)

    for u in used:
        if u not in declared:
            bad.append("① ci.sh 里 `lane %s` 用了一个不在 CI_LANES_ALL 里的名字"
                       "（拼错的 lane 永远为假 ⇒ 那一段再也不跑）" % u)
    for d in declared:
        if d not in used:
            bad.append("② CI_LANES_ALL 里的 lane '%s' 没有任何 `lane %s` 守卫用到它" % (d, d))

    seen, wf_lanes = {}, []
    for name, j in jobs.items():
        for l in j["lanes"]:
            wf_lanes.append(l)
            if l in seen:
                bad.append("④ lane '%s' 同时挂在 job '%s' 与 job '%s' 上" % (l, seen[l], name))
            seen[l] = name
    for l in sorted(set(wf_lanes) - set(declared)):
        bad.append("③ workflow 点了一条 ci.sh 不认识的 lane '%s'" % l)
    for l in declared:
        if l not in wf_lanes:
            bad.append("③ lane '%s' 没有挂在任何 job 上 ⇒ 它在 GHA 上一次都不跑，"
                       "而每个 PR 依旧全绿" % l)

    if AGG_JOB not in jobs:
        bad.append("⑤ workflow 里没有汇总 job '%s'（分支保护的 required context）" % AGG_JOB)
    else:
        lane_jobs = sorted(n for n, j in jobs.items() if j["lanes"])
        for n in lane_jobs:
            if n not in jobs[AGG_JOB]["needs"]:
                bad.append("⑤ 汇总 job '%s' 的 needs 里缺 '%s' ⇒ 它红了也拦不住合并"
                           % (AGG_JOB, n))
    return bad, declared, jobs


def self_test():
    ci = open(CI_SH, encoding="utf-8").read()
    wf = open(WF, encoding="utf-8").read()
    base, _, _ = check(ci, wf)
    if base:
        print("self-test 前提不成立：未改动的树就已经是红的：\n  " + "\n  ".join(base))
        return 1
    declared, _ = parse_ci_sh(ci)
    victim = "gates" if "gates" in declared else declared[-1]
    cases = [
        ("① lane 名拼错",
         ci.replace("if lane %s; then" % victim, "if lane %sx; then" % victim, 1), wf),
        ("② CI_LANES_ALL 里多一个没人用的名字",
         ci.replace('CI_LANES_ALL="', 'CI_LANES_ALL="ghost ', 1), wf),
        ("③ 某条 lane 从 workflow 里掉出去",
         ci, re.sub(r'(CI_LANE:\s*"[^"]*)\b%s\b' % victim, r"\1", wf, count=1)),
        ("④ 同一条 lane 挂在两个 job 上",
         ci, re.sub(r'(CI_LANE:\s*")', r'\g<1>%s ' % victim, wf, count=1)),
        ("⑤ 汇总 job 的 needs 漏一个 lane job",
         ci, re.sub(r"(needs:\s*\[)[A-Za-z0-9_-]+,\s*", r"\1", wf, count=1)),
    ]
    rc = 0
    for label, c, w in cases:
        try:
            problems, _, _ = check(c, w)
        except SystemExit as e:
            problems = [str(e)]
        if problems:
            print("  ✅ 负对照 %s ⇒ 红（%s）" % (label, problems[0][:60]))
        else:
            print("  ❌ 负对照 %s ⇒ 仍然绿 —— 这道门在这一格没牙" % label)
            rc = 1
    return rc


def main():
    if "--self-test" in sys.argv:
        return self_test()
    ci = open(CI_SH, encoding="utf-8").read()
    wf = open(WF, encoding="utf-8").read()
    problems, declared, jobs = check(ci, wf)
    if problems:
        for p in problems:
            print("  " + p)
        return 1
    for name in sorted(jobs):
        if jobs[name]["lanes"]:
            print("  · job %-10s lane: %s" % (name, " ".join(jobs[name]["lanes"])))
    print("  lane 全集 %d 条，workflow 逐条对上" % len(declared))
    return 0


if __name__ == "__main__":
    sys.exit(main())
