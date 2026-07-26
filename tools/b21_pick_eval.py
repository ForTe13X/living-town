#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/b21_pick_eval.py — B21：把【出货那一份闭集选号 prompt】喂给任意 OpenAI 兼容后端，
用【docs/36 §4 的同一套判据】打分，并与【同配置的均匀随机零假设】和【鹦鹉地板】对拍。

输入 = game/bench/PickCtxDump.gd 导出的 JSONL（每行一个真实决策点，含 sys / user_nat /
user_shuf / user_rev / 逐候选 score / 引擎基线下标 base_idx / 纯 argmax 下标 argmax_idx）。

判据（逐条对着 AIBackend._shadow_compare 的实现移植，不是照 docs 复述）：
  ① 归一化分数名次 rank = #{j: s_j > s_pick} / (n-1)     0=最高分, 0.5=随机, 1=最低分
  ② 效用落差 gap = s_base - s_pick；随机期望落差 gap_rand = s_base - mean(s)
     效用保住率 = 1 - Σgap / Σgap_rand                    1=完美复读, 0=等于随机, <0=不如随机
  ③ 换动作种类率：实测 vs 随机期望 #{j:(action,kind)_j != (action,kind)_base}/n
  ④ Δ/L = 采纳的选择 ≠ 引擎在同一冻结闭集上的选择 的比例；随机基线 = 1 - mean(1/n)
  ⑤ 选号直方图 / 选 0 号率（本棒的主诊断）

接受规则 = AIBackend.parse_decision 的忠实移植（fail-closed：首字符是合法编号且其后无任何
ASCII 字母/数字才算数；否则退 JSON {"pick":N} 兼容路；再否则算 parse_fail）。

消融（把"位置偏置"和"内容盲"分开）：
  --variant nat|shuf|rev      候选在 prompt 里的排列（nat = 出货那一份）
  --sys orig|noex|ex0|exlast  系统 prompt 里的【示例编号】（出货原文写着"一个字符，如 3 或 A"）
  --labels digits|letters|one_based   编号字母表（0-9/A-Z → A-Z / 1-9,A-Z）

用法：
  python tools/b21_pick_eval.py gen --ctx pick_ctx.jsonl --n 800 --url http://HOST:8080/v1/chat/completions \
      --model m --tag qwen1.5b/nat --out raw/qwen1.5b_nat.jsonl
  python tools/b21_pick_eval.py score raw/*.jsonl --ctx pick_ctx.jsonl --n 800
  python tools/b21_pick_eval.py nulls --ctx pick_ctx.jsonl --n 800
"""
import argparse
import glob
import hashlib
import json
import math
import os
import random
import re
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# ─────────────────────────── 数据集 ───────────────────────────


def load_ctx(path):
    with open(path, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def subsample(rows, n, seed):
    """确定性均匀子采样。全量 5290 条时全模型全消融跑不完，故抽样；抽样本身与内容无关 →
    不会偏向任何一类决策点（对照：按 min_need 分层会系统性改变 |C| 分布）。"""
    if n <= 0 or n >= len(rows):
        return list(rows)
    rnd = random.Random(seed)
    idx = sorted(rnd.sample(range(len(rows)), n))
    return [rows[i] for i in idx]


# ───────────────────── 接受规则（parse_decision 移植） ─────────────────────


def label_idx(c, alphabet):
    """单字符编号 → 下标。alphabet 是本次使用的字母表（出货 = '0123456789A..Z'）。"""
    if len(c) != 1:
        return -1
    i = alphabet.find(c)
    return i if i >= 0 else -1


def is_alnum_ascii(c):
    if not c:
        return False
    o = ord(c[0])
    return (48 <= o <= 57) or (65 <= o <= 90) or (97 <= o <= 122)


def parse_decision(raw, n, alphabet):
    """AIBackend.parse_decision 的忠实移植。返回 (idx, reason)。idx<0 = 不采纳。"""
    if raw is None:
        return -1, "empty"
    s = raw.strip()
    if s == "" or n <= 0:
        return -1, "empty"
    pk = label_idx(s[0], alphabet)
    if 0 <= pk < n:
        rest = s[1:]
        if not any(is_alnum_ascii(ch) for ch in rest):
            return pk, "index"
    # JSON 兼容路（llm 老路仍可能这么回）
    data = None
    try:
        data = json.loads(s)
    except Exception:
        a, b = s.find("{"), s.rfind("}")
        if a >= 0 and b > a:
            try:
                data = json.loads(s[a:b + 1])
            except Exception:
                data = None
    if not isinstance(data, dict) or "pick" not in data:
        return -1, "prose_or_dirty"
    try:
        pick = int(data["pick"])
    except Exception:
        return -1, "prose_or_dirty"
    if pick < 0 or pick >= n:
        return -1, "out_of_range"
    return pick, "json"


DIGITS36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LETTERS36 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" + "abcdefghijklmnopqrstuvwxyz"[:10]
ONE_BASED = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0"   # 1..9,A..Z,0 → "第一项"的编号是 1


def alphabet_for(name):
    return {"digits": DIGITS36, "letters": LETTERS36, "one_based": ONE_BASED}[name]


# ───────────────────────── prompt 消融 ─────────────────────────

CAND_TAG = "[候选] "
# 出货系统 prompt 原文（AIBackend._system_prompt）里的示例编号那一段：
SYS_EXAMPLE = "（一个字符，如 3 或 A）"
SYS_VARIANTS = {
    "orig": SYS_EXAMPLE,                 # 出货原文：示例编号写死成 3
    "noex": "（一个字符）",                # 去掉示例
    "ex0": "（一个字符，如 0 或 A）",       # 示例换成 0
    "exlast": "（一个字符，如 7 或 A）",    # 示例换成另一个数字（控制"是不是只要有示例就塌到示例上"）
}


def apply_sys(sys_text, variant):
    if variant == "orig":
        return sys_text
    if SYS_EXAMPLE not in sys_text:
        raise SystemExit("系统 prompt 里找不到示例段 %r —— AIBackend._system_prompt 变了，消融失效" % SYS_EXAMPLE)
    return sys_text.replace(SYS_EXAMPLE, SYS_VARIANTS[variant])


def split_cand_line(user):
    """把 prompt 拆成 (前缀, [候选显示文本...])。候选行形如 '[候选] 0=睡觉 1=打招呼→阿丽(点头之交)'。"""
    i = user.rfind("\n" + CAND_TAG)
    if i < 0:
        if user.startswith(CAND_TAG):
            head, line = "", user
        else:
            raise ValueError("prompt 里没有候选行")
    else:
        head, line = user[:i + 1], user[i + 1:]
    body = line[len(CAND_TAG):]
    toks = body.split(" ")
    texts = []
    for t in toks:
        if len(t) < 2 or t[1] != "=" or t[0] not in DIGITS36:
            raise ValueError("候选 token 不合规: %r" % t)
        texts.append(t[2:])
    return head, texts


def relabel(user, alphabet):
    """用另一套字母表重写候选行（编号字符 → 位置的映射改变，候选内容与顺序一字不动）。"""
    if alphabet == DIGITS36:
        return user
    head, texts = split_cand_line(user)
    return head + CAND_TAG + " ".join("%s=%s" % (alphabet[i], t) for i, t in enumerate(texts))


# ───────────────────────── 生成（gen） ─────────────────────────


def post_json(url, payload, timeout):
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": "Bearer none"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def gen(args):
    rows = subsample(load_ctx(args.ctx), args.n, args.sample_seed)
    alphabet = alphabet_for(args.labels)
    ukey = {"nat": "user_nat", "shuf": "user_shuf", "rev": "user_rev"}[args.variant]

    def one(k_row):
        k, row = k_row
        sys_t = apply_sys(row["sys"], args.sys)
        user_t = relabel(row[ukey], alphabet)
        payload = {
            "model": args.model, "max_tokens": args.max_tokens, "temperature": args.temp,
            "seed": args.gen_seed + k,
            "messages": [{"role": "system", "content": sys_t}, {"role": "user", "content": user_t}],
        }
        if args.logprobs:
            payload["logprobs"] = True
            payload["top_logprobs"] = 20
        raw, lp, err = "", None, ""
        for attempt in range(3):
            try:
                j = post_json(args.url, payload, args.timeout)
                ch = j["choices"][0]
                raw = ch["message"]["content"]
                if args.logprobs:
                    try:
                        lp = ch["logprobs"]["content"][0]["top_logprobs"]
                    except Exception:
                        lp = None
                err = ""
                break
            except Exception as e:                                    # noqa: BLE001
                err = "%s: %s" % (type(e).__name__, e)
        return {"k": k, "seed": row["seed"], "tick": row["tick"], "agent": row["agent"],
                "n_cap": row["n_cap"], "raw": raw, "err": err, "top_logprobs": lp}

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    with ThreadPoolExecutor(max_workers=args.concurrency) as ex:
        results = list(ex.map(one, enumerate(rows)))
    meta = {"_meta": True, "tag": args.tag, "model": args.model, "variant": args.variant,
            "sys": args.sys, "labels": args.labels, "temp": args.temp,
            "max_tokens": args.max_tokens, "n": len(rows), "ctx": os.path.basename(args.ctx),
            "sample_seed": args.sample_seed, "gen_seed": args.gen_seed}
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(json.dumps(meta, ensure_ascii=False) + "\n")
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    nerr = sum(1 for r in results if r["err"])
    print("[gen] %s → %s  n=%d err=%d" % (args.tag, args.out, len(results), nerr))
    if nerr:
        print("      首个错误: %s" % next(r["err"] for r in results if r["err"]))


# ───────────────────────── 打分（score） ─────────────────────────


def variant_perm(row, variant):
    """变体位置 i → 自然序下标。"""
    n = row["n_cap"]
    if variant == "nat":
        return list(range(n))
    if variant == "shuf":
        return row["perm_shuf"]
    if variant == "rev":
        return row["perm_rev"]
    raise ValueError(variant)


def score_rows(rows, picks_nat, picks_variant_pos):
    """picks_nat[i] = 自然序下标（-1 = 未采纳）。返回一堆聚合量 + 逐 seed 明细。"""
    per_seed = {}
    agg = dict(L=0, N=len(rows), rank_sum=0.0, gap_sum=0.0, gap_rand_sum=0.0,
               kind_chg=0, exp_kind_sum=0.0, delta=0, inv_cand_sum=0.0, cand_sum=0,
               pick0=0, pos0=0, rank_n=0)
    hist = {}
    poshist = {}
    seen_n = {}
    for row in rows:                                  # 分母诚实：每个 seed 一共问了多少次（不只是采纳了多少次）
        seen_n[row["seed"]] = seen_n.get(row["seed"], 0) + 1
    for row, p, pos in zip(rows, picks_nat, picks_variant_pos):
        if p < 0:
            continue
        n = row["n_cap"]
        cs = row["cands"]
        b = row["base_idx"]
        agg["L"] += 1
        agg["cand_sum"] += n
        agg["inv_cand_sum"] += 1.0 / n
        s_p = cs[p]["score"]
        s_b = cs[b]["score"]
        smean = sum(c["score"] for c in cs) / n
        rank = sum(1 for c in cs if c["score"] > s_p)
        if n > 1:
            agg["rank_sum"] += rank / (n - 1.0)
            agg["rank_n"] += 1
        agg["gap_sum"] += s_b - s_p
        agg["gap_rand_sum"] += s_b - smean
        bk = (cs[b]["action"], cs[b]["kind"])
        if (cs[p]["action"], cs[p]["kind"]) != bk:
            agg["kind_chg"] += 1
        agg["exp_kind_sum"] += sum(1 for c in cs if (c["action"], c["kind"]) != bk) / float(n)
        if cs[p]["key"] != cs[b]["key"]:
            agg["delta"] += 1
        if p == 0:
            agg["pick0"] += 1
        if pos == 0:
            agg["pos0"] += 1
        hist[p] = hist.get(p, 0) + 1
        poshist[pos] = poshist.get(pos, 0) + 1
        sd = row["seed"]
        d = per_seed.setdefault(sd, dict(L=0, rank_sum=0.0, rank_n=0, gap=0.0, gap_rand=0.0,
                                         kind=0, exp_kind=0.0, delta=0, inv=0.0, pos0=0, pick0=0))
        d["L"] += 1
        if n > 1:
            d["rank_sum"] += rank / (n - 1.0)
            d["rank_n"] += 1
        d["gap"] += s_b - s_p
        d["gap_rand"] += s_b - smean
        d["kind"] += 1 if (cs[p]["action"], cs[p]["kind"]) != bk else 0
        d["exp_kind"] += sum(1 for c in cs if (c["action"], c["kind"]) != bk) / float(n)
        d["delta"] += 1 if cs[p]["key"] != cs[b]["key"] else 0
        d["inv"] += 1.0 / n
        d["pos0"] += 1 if pos == 0 else 0
        d["pick0"] += 1 if p == 0 else 0
    for sd, d in per_seed.items():
        d["N"] = seen_n.get(sd, 0)
    return agg, per_seed, hist, poshist


def summarize(tag, agg, per_seed, hist, poshist, extra=None):
    L = max(1, agg["L"])
    rank = agg["rank_sum"] / max(1, agg["rank_n"])
    ret = 1.0 - (agg["gap_sum"] / agg["gap_rand_sum"]) if abs(agg["gap_rand_sum"]) > 1e-9 else float("nan")
    out = {
        "tag": tag, "N": agg["N"], "L": agg["L"], "accept_rate": agg["L"] / max(1, agg["N"]),
        "rank": rank,
        "gap": agg["gap_sum"] / L, "gap_rand": agg["gap_rand_sum"] / L, "util_retention": ret,
        "kind_chg": agg["kind_chg"] / L, "kind_chg_rand": agg["exp_kind_sum"] / L,
        "delta_over_L": agg["delta"] / L,
        "delta_rand_baseline": 1.0 - agg["inv_cand_sum"] / L,
        "mean_ncap": agg["cand_sum"] / L,
        "pick0_rate": agg["pick0"] / L, "pos0_rate": agg["pos0"] / L,
        "distinct_idx": len(hist),
        "hist_top": sorted(hist.items(), key=lambda kv: -kv[1])[:8],
        "poshist_top": sorted(poshist.items(), key=lambda kv: -kv[1])[:8],
        "per_seed_rank": {},
        "per_seed_pos0": {},
        "per_seed": {},          # 原始累加量：下游可自行折算任何指标（逐 seed 配对检验用）
    }
    for sd, d in sorted(per_seed.items()):
        out["per_seed_rank"][sd] = d["rank_sum"] / max(1, d["rank_n"])
        out["per_seed_pos0"][sd] = d["pos0"] / max(1, d["L"])
        Ls = max(1, d["L"])
        out["per_seed"][sd] = {
            "L": d["L"], "N": d.get("N", 0), "accept": d["L"] / max(1, d.get("N", 1)),
            "rank": d["rank_sum"] / max(1, d["rank_n"]),
            "util_retention": (1.0 - d["gap"] / d["gap_rand"]) if abs(d["gap_rand"]) > 1e-9 else float("nan"),
            "kind_chg": d["kind"] / Ls, "kind_chg_rand": d["exp_kind"] / Ls,
            "delta_over_L": d["delta"] / Ls, "delta_rand_baseline": 1.0 - d["inv"] / Ls,
            "pos0": d["pos0"] / Ls, "pick0": d["pick0"] / Ls,
        }
    if extra:
        out.update(extra)
    return out


def analytic_nulls(rows, _depth=0):
    """同配置的【解析】零假设与鹦鹉地板：不抽样、直接算期望，避免蒙特卡洛噪声混进结论。"""
    n_ = len(rows)
    rank_sum = gap_sum = gap_rand_sum = exp_kind = inv = 0.0
    delta_rand = 0.0
    par_rank = par_gap = par_kind = par_delta = par_pick0 = 0.0
    rand_pick0 = 0.0
    for row in rows:
        n = row["n_cap"]
        cs = row["cands"]
        b = row["base_idx"]
        s_b = cs[b]["score"]
        smean = sum(c["score"] for c in cs) / n
        bk = (cs[b]["action"], cs[b]["kind"])
        # 均匀随机臂：逐候选求期望
        r = 0.0
        for j, c in enumerate(cs):
            r += sum(1 for d in cs if d["score"] > c["score"]) / (n - 1.0) if n > 1 else 0.0
        rank_sum += r / n
        gap_sum += s_b - smean
        gap_rand_sum += s_b - smean
        exp_kind += sum(1 for c in cs if (c["action"], c["kind"]) != bk) / float(n)
        inv += 1.0 / n
        delta_rand += sum(1 for c in cs if c["key"] != cs[b]["key"]) / float(n)
        rand_pick0 += 1.0 / n
        # 鹦鹉（纯 argmax）
        a = row["argmax_idx"]
        par_rank += sum(1 for c in cs if c["score"] > cs[a]["score"]) / (n - 1.0) if n > 1 else 0.0
        par_gap += s_b - cs[a]["score"]
        par_kind += 1 if (cs[a]["action"], cs[a]["kind"]) != bk else 0
        par_delta += 1 if cs[a]["key"] != cs[b]["key"] else 0
        par_pick0 += 1 if a == 0 else 0
    per_seed = {}
    if _depth == 0:                                   # 逐 seed 零假设（配对置换检验要用它做对照臂）
        by_sd = {}
        for r in rows:
            by_sd.setdefault(r["seed"], []).append(r)
        for sd, rs in sorted(by_sd.items()):
            sub = analytic_nulls(rs, _depth=1)
            per_seed[sd] = {"random": sub["random"], "parrot": sub["parrot"]}
    return {
        "per_seed": per_seed,
        "random": {"tag": "uniform-random null (analytic)", "N": n_, "L": n_, "accept_rate": 1.0,
                   "rank": rank_sum / n_, "gap": gap_sum / n_, "gap_rand": gap_rand_sum / n_,
                   "util_retention": 1.0 - gap_sum / gap_rand_sum,
                   "kind_chg": exp_kind / n_, "kind_chg_rand": exp_kind / n_,
                   "delta_over_L": delta_rand / n_, "delta_rand_baseline": 1.0 - inv / n_,
                   "mean_ncap": sum(r["n_cap"] for r in rows) / n_,
                   "pick0_rate": rand_pick0 / n_, "pos0_rate": rand_pick0 / n_},
        "parrot": {"tag": "parrot floor argmax(score)", "N": n_, "L": n_, "accept_rate": 1.0,
                   "rank": par_rank / n_, "gap": par_gap / n_, "gap_rand": gap_rand_sum / n_,
                   "util_retention": 1.0 - par_gap / gap_rand_sum,
                   "kind_chg": par_kind / n_, "kind_chg_rand": exp_kind / n_,
                   "delta_over_L": par_delta / n_, "delta_rand_baseline": 1.0 - inv / n_,
                   "mean_ncap": sum(r["n_cap"] for r in rows) / n_,
                   "pick0_rate": par_pick0 / n_, "pos0_rate": par_pick0 / n_},
    }


def load_raw(path):
    with open(path, "r", encoding="utf-8") as f:
        lines = [json.loads(x) for x in f if x.strip()]
    meta = lines[0]
    assert meta.get("_meta"), "第一行必须是 _meta"
    return meta, lines[1:]


def score(args):
    ctx_all = load_ctx(args.ctx)
    out = []
    for path in sorted(set(sum([glob.glob(p) for p in args.raw], []))):
        meta, recs = load_raw(path)
        rows = subsample(ctx_all, meta["n"] if args.n <= 0 else args.n, meta["sample_seed"])
        assert len(rows) == len(recs), "%s: ctx %d vs raw %d 对不上" % (path, len(rows), len(recs))
        alphabet = alphabet_for(meta["labels"])
        picks_nat, picks_pos, reasons = [], [], {}
        for row, rec in zip(rows, recs):
            assert row["tick"] == rec["tick"] and row["agent"] == rec["agent"], "%s: 行对齐错了" % path
            n = row["n_cap"]
            pos, why = parse_decision(rec["raw"], n, alphabet)
            reasons[why] = reasons.get(why, 0) + 1
            perm = variant_perm(row, meta["variant"])
            picks_pos.append(pos)
            picks_nat.append(perm[pos] if pos >= 0 else -1)
        agg, per_seed, hist, poshist = score_rows(rows, picks_nat, picks_pos)
        s = summarize(meta["tag"], agg, per_seed, hist, poshist,
                      extra={"parse_reasons": reasons, "meta": meta,
                             "err_n": sum(1 for r in recs if r.get("err"))})
        out.append(s)
    nulls = analytic_nulls(subsample(ctx_all, args.n if args.n > 0 else out[0]["N"],
                                     out[0]["meta"]["sample_seed"] if out else 20260726))
    print(json.dumps({"arms": out, "nulls": nulls}, ensure_ascii=False, indent=1))


def nulls_cmd(args):
    rows = subsample(load_ctx(args.ctx), args.n, args.sample_seed)
    print(json.dumps(analytic_nulls(rows), ensure_ascii=False, indent=1))


# ───────────────────────── CLI ─────────────────────────


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("gen")
    g.add_argument("--ctx", required=True)
    g.add_argument("--n", type=int, default=800)
    g.add_argument("--sample-seed", type=int, default=20260726)
    g.add_argument("--gen-seed", type=int, default=1000)
    g.add_argument("--url", required=True)
    g.add_argument("--model", default="m")
    g.add_argument("--tag", required=True)
    g.add_argument("--out", required=True)
    g.add_argument("--variant", default="nat", choices=["nat", "shuf", "rev"])
    g.add_argument("--sys", default="orig", choices=list(SYS_VARIANTS))
    g.add_argument("--labels", default="digits", choices=["digits", "letters", "one_based"])
    g.add_argument("--temp", type=float, default=0.7)
    g.add_argument("--max-tokens", type=int, default=8)
    g.add_argument("--concurrency", type=int, default=16)
    g.add_argument("--timeout", type=float, default=300.0)
    g.add_argument("--logprobs", action="store_true")
    g.set_defaults(func=gen)

    s = sub.add_parser("score")
    s.add_argument("raw", nargs="+")
    s.add_argument("--ctx", required=True)
    s.add_argument("--n", type=int, default=0)
    s.set_defaults(func=score)

    z = sub.add_parser("nulls")
    z.add_argument("--ctx", required=True)
    z.add_argument("--n", type=int, default=800)
    z.add_argument("--sample-seed", type=int, default=20260726)
    z.set_defaults(func=nulls_cmd)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
