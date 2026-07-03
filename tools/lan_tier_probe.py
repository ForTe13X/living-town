#!/usr/bin/env python3
# lan_tier_probe.py — 经局域网探一台机器的 LM Studio，量「中端 GPU 分档」延迟带。
# 复现路C(嵌入式 NobodyWho)的等效负载：同决策 prompt(/no_think, 无 json_schema, 靠抽 {…}) + 同对话 prompt。
# LM Studio 底层=llama.cpp Vulkan，与 NobodyWho 同引擎 → 其 tok/s ≈ 嵌入式路C(HTTP 开销可忽略)。
#
# 用法：  python3 tools/lan_tier_probe.py <host-ip> [port=1234] [model_substr_filter]
#   例： python3 tools/lan_tier_probe.py 192.168.1.50
#        python3 tools/lan_tier_probe.py 192.168.1.50 1234 qwen2.5
# 可在容器内跑(python3)，容器可直连 LAN IP；或宿主 python。
import json, sys, time, urllib.request

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = sys.argv[2] if len(sys.argv) > 2 else "1234"
FILT = sys.argv[3] if len(sys.argv) > 3 else ""
BASE = f"http://{HOST}:{PORT}/v1"
DEADLINE_MS = 12000   # 与 AIBackend.DEADLINE_MS 一致

# 决策 prompt（镜像 AIBackend._system_prompt + build_prompt，9 候选）
DEC_SYS = ("你在扮演一个像素小镇的居民。只能从【候选】里按下标 pick 选一个行动，并给≤2句符合人设的台词。"
           "台词只用中文、不夹英文单词，要贴合你的人设与当下处境，避免泛泛的天气寒暄。"
           "严格只输出 JSON：{\"pick\":整数下标,\"speech\":\"台词\",\"emotion\":\"neutral|happy|angry|sad|anxious|fond\",\"affinity_delta\":-3到3}。 /no_think")
DEC_USER = ("[人设] 阿丽：咖啡馆老板，认识镇上每个人，消息最灵通。 口吻：活泼爱感叹、爱打听新鲜事\n"
            "[此刻] 第3天 时段0.40\n[记忆] 老陈昨天没赴约；小芸在传夜市的事\n"
            "[候选] 0=吃饭 1=睡觉 2=找老陈打招呼 3=给小芸一杯咖啡 4=找小芸八卦(夜市) 5=约老陈晚上见 6=晒太阳 7=做活 8=找阿本对质")
CHAT_SYS = "你在扮演像素小镇居民「阿丽」（咖啡馆老板，爱八卦）。用一两句中文自然回应玩家，符合人设，不要旁白。 /no_think"
CHAT_USER = "你最近怎么样？听说镇上要办夜市？"

def call(model, sys_p, user_p, max_tokens=128):
    body = {"model": model, "max_tokens": max_tokens, "temperature": 0.6,
            "messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": user_p}]}
    req = urllib.request.Request(BASE + "/chat/completions", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer lm-studio"})
    t = time.time()
    try:
        r = json.loads(urllib.request.urlopen(req, timeout=120).read())
        dt = (time.time() - t) * 1000.0
        msg = r["choices"][0]["message"]
        content = (msg.get("content") or "").strip()
        ctoks = int(r.get("usage", {}).get("completion_tokens", 0))
        tps = (ctoks / (dt / 1000.0)) if dt > 0 and ctoks else 0.0
        return dt, content, ctoks, tps
    except Exception as e:
        return -1.0, f"ERR {e}", 0, 0.0

def models():
    try:
        r = json.loads(urllib.request.urlopen(BASE + "/models", timeout=10).read())
        return [m["id"] for m in r.get("data", [])]
    except Exception as e:
        print(f"无法连 {BASE}/models : {e}"); return []

def main():
    ms = models()
    if FILT:
        ms = [m for m in ms if FILT.lower() in m.lower()]
    # 只测看起来是 instruct 决策模型的（跳过 embedding/vl）
    ms = [m for m in ms if "embed" not in m.lower() and "-vl" not in m.lower()]
    print(f"=== LAN 分档探针  host={HOST}:{PORT}  候选模型 {len(ms)} 个 ===")
    print(f"{'模型':<34} {'决策ms':>8} {'tok/s':>7} {'≤12s':>5}  {'对话ms':>8} {'tok/s':>7}")
    print("-" * 80)
    for m in ms:
        d_ms, d_txt, _, d_tps = call(m, DEC_SYS, DEC_USER)
        c_ms, c_txt, _, c_tps = call(m, CHAT_SYS, CHAT_USER)
        ok = "✅" if 0 < d_ms <= DEADLINE_MS else "❌"
        print(f"{m[:34]:<34} {d_ms:>8.0f} {d_tps:>7.1f} {ok:>5}  {c_ms:>8.0f} {c_tps:>7.1f}")
        print(f"    决策: {d_txt[:90]}")
        print(f"    对话: {c_txt[:90]}")
    print("\n判读：决策 ms 是否 ≪ 12000(截止线)；tok/s 反映 780M 算力；据此定中端档默认模型尺寸。")

if __name__ == "__main__":
    main()
