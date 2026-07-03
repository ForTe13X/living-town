#!/usr/bin/env python3
# llm_probe.py — 横比 LM Studio 几个模型在「NPC 自由对话」上的表现（回复质量/延迟/是否空）。容器内跑，连宿主。
import json, time, urllib.request
EP = "http://host.docker.internal:1234/v1/chat/completions"
SYS = "你在扮演像素小镇咖啡馆老板「阿丽」，热情爱八卦。用一两句中文自然回应玩家，符合人设，不要旁白、不要思考过程。"
USER = "你最近怎么样？听说镇上要办夜市？"

def ask(model, sys, extra=""):
    body = {"model": model, "max_tokens": 200, "temperature": 0.7,
            "messages": [{"role": "system", "content": sys + extra}, {"role": "user", "content": USER}]}
    req = urllib.request.Request(EP, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer lm-studio"})
    t = time.time()
    try:
        r = json.loads(urllib.request.urlopen(req, timeout=90).read())
        dt = time.time() - t
        msg = r["choices"][0]["message"]
        content = (msg.get("content") or "").strip()
        reasoning = (msg.get("reasoning_content") or "").strip()
        return f"[{dt:.1f}s] content({len(content)}): {content[:160]!r}" + (f"  | reasoning({len(reasoning)}) 非空" if reasoning else "")
    except Exception as e:
        return f"ERR {e}"

for m in ["qwen-3-8b-instruct", "google/gemma-4-12b-qat", "qwen3.6-35b-a3b", "gemma-4-e4b-uncensored-hauhaucs-aggressive"]:
    print(f"\n== {m} ==")
    print("  普通:    ", ask(m, SYS))
    print("  /no_think:", ask(m, SYS, " /no_think"))
