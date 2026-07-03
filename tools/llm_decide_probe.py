#!/usr/bin/env python3
# llm_decide_probe.py — 找「决策 JSON」对 qwen3 最稳的配置：json_schema vs 无schema+/no_think，不同 max_tokens。
import json, time, urllib.request
EP = "http://host.docker.internal:1234/v1/chat/completions"
MODEL = "qwen-3-8b-instruct"

SYS = ("你在扮演一个像素小镇的居民。只能从【候选】里按下标 pick 选一个行动，并给≤2句符合人设的台词。"
       "严格只输出 JSON：{\"pick\":整数下标,\"speech\":\"台词\",\"emotion\":\"neutral|happy|angry|sad|anxious|fond\",\"affinity_delta\":-3到3}。")
USER = ("你是阿丽（爱八卦的咖啡馆老板）。当前候选：\n"
        "[0] 待着不动\n[1] 找 老陈 打招呼\n[2] 找 小芸 八卦(夜市)\n[3] 给 老陈 一杯咖啡\n[4] 约 小芸 晚上见\n"
        "请选一个。")
SCHEMA = {"type": "object", "properties": {
    "pick": {"type": "integer"}, "speech": {"type": "string"},
    "emotion": {"type": "string"}, "affinity_delta": {"type": "integer"}},
    "required": ["pick", "speech"]}

def ask(label, schema, max_tokens, nothink):
    sys = SYS + (" /no_think" if nothink else "")
    body = {"model": MODEL, "max_tokens": max_tokens, "temperature": 0.6,
            "messages": [{"role": "system", "content": sys}, {"role": "user", "content": USER}]}
    if schema:
        body["response_format"] = {"type": "json_schema", "json_schema": {"name": "decision", "schema": schema}}
    req = urllib.request.Request(EP, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer lm-studio"})
    t = time.time()
    try:
        r = json.loads(urllib.request.urlopen(req, timeout=90).read())
        dt = time.time() - t
        msg = r["choices"][0]["message"]
        content = (msg.get("content") or "").strip()
        reasoning = (msg.get("reasoning_content") or "").strip()
        fr = r["choices"][0].get("finish_reason", "?")
        ok = False
        try:
            # 模拟 parse_decision：抽第一个 {...}
            s = content.find("{"); e = content.rfind("}")
            obj = json.loads(content[s:e+1]) if s >= 0 and e > s else None
            ok = isinstance(obj, dict) and "pick" in obj
        except Exception:
            ok = False
        print(f"  {label}: [{dt:.1f}s] finish={fr} {'✅' if ok else '❌'} content({len(content)}): {content[:120]!r}"
              + (f" | reasoning({len(reasoning)})非空" if reasoning else ""))
    except Exception as e:
        print(f"  {label}: ERR {e}")

print(f"== 决策配置探针  model={MODEL} ==")
ask("A json_schema/120     ", SCHEMA, 120, False)
ask("B json_schema/400     ", SCHEMA, 400, False)
ask("C no-schema/no_think/200", None, 200, True)
ask("D no-schema/plain/400  ", None, 400, False)
ask("E no-schema/no_think/400", None, 400, True)
