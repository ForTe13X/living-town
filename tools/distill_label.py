#!/usr/bin/env python3
# distill_label.py — L3 蒸馏第2步：用 teacher(8B, LM Studio) 给导出的决策上下文打 label，产出 SFT 数据集。
# 输入：DistillDump 导出的 distill_contexts.jsonl（每行 {sys,user,cands,n,agent}）
# 输出：distill_sft.jsonl（每行 {messages:[{system},{user},{assistant: 合法决策JSON}]}），仅保留通过合法校验(pick∈[0,n))的样本。
# 用法：python3 tools/distill_label.py <contexts.jsonl> <out_sft.jsonl> [host=127.0.0.1] [port=1234] [teacher_model] [limit]
import json, re, sys, time, urllib.request

CTX = sys.argv[1] if len(sys.argv) > 1 else "game/bench/distill_contexts.jsonl"
OUT = sys.argv[2] if len(sys.argv) > 2 else "game/bench/distill_sft.jsonl"
HOST = sys.argv[3] if len(sys.argv) > 3 else "127.0.0.1"
PORT = sys.argv[4] if len(sys.argv) > 4 else "1234"
TEACHER = sys.argv[5] if len(sys.argv) > 5 else "qwen-3-8b-instruct"
LIMIT = int(sys.argv[6]) if len(sys.argv) > 6 else 0
BASE = f"http://{HOST}:{PORT}/v1/chat/completions"

def ask(sys_p, user_p):
    body = {"model": TEACHER, "max_tokens": 128, "temperature": 0.7,
            "messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": user_p}]}
    req = urllib.request.Request(BASE, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer lm-studio"})
    r = json.loads(urllib.request.urlopen(req, timeout=120).read())
    return (r["choices"][0]["message"].get("content") or "").strip()

def parse_pick(raw, n):
    # 镜像 GDScript parse_decision：抠第一个 {…}，校验 pick∈[0,n)
    s, e = raw.find("{"), raw.rfind("}")
    if s < 0 or e <= s: return None
    try:
        obj = json.loads(raw[s:e+1])
    except Exception:
        return None
    if not isinstance(obj, dict) or "pick" not in obj: return None
    try:
        p = int(obj["pick"])
    except Exception:
        return None
    if p < 0 or p >= n: return None
    # 规范化输出标签（只留契约字段）
    out = {"pick": p, "speech": str(obj.get("speech", ""))[:60]}
    if "emotion" in obj: out["emotion"] = str(obj["emotion"])
    if "affinity_delta" in obj:
        try: out["affinity_delta"] = max(-3, min(3, int(obj["affinity_delta"])))
        except Exception: pass
    return out

def main():
    rows = [json.loads(l) for l in open(CTX, encoding="utf-8") if l.strip()]
    if LIMIT: rows = rows[:LIMIT]
    ok = bad = 0
    t0 = time.time()
    with open(OUT, "w", encoding="utf-8") as fo:
        for i, row in enumerate(rows):
            try:
                raw = ask(row["sys"], row["user"])
                lab = parse_pick(raw, int(row["n"]))
            except Exception as ex:
                lab, raw = None, f"ERR {ex}"
            if lab is None:
                bad += 1
                continue
            fo.write(json.dumps({"messages": [
                {"role": "system", "content": row["sys"]},
                {"role": "user", "content": row["user"]},
                {"role": "assistant", "content": json.dumps(lab, ensure_ascii=False)},
            ]}, ensure_ascii=False) + "\n")
            ok += 1
            if (i + 1) % 10 == 0:
                print(f"  {i+1}/{len(rows)}  ok={ok} bad={bad}  ({(time.time()-t0):.0f}s)")
    print(f"完成：合格 {ok} / 共 {len(rows)}（合法率 {100.0*ok/max(1,ok+bad):.1f}%）→ {OUT}")

if __name__ == "__main__":
    main()
