#!/usr/bin/env bash
# V1 §2.5 探测包络：给 #41 造变异体，每个都在【隔离副本】里跑，跑完不动出货树。
# 用法： bash analysis/v1/mutants.sh <scratch_dir> <godot>
# 判读：门该红的红、该绿的绿；每个变异体的 Harness 判决行写进 <scratch>/mut_<name>.txt
set -u
SP="$1"; GODOT="$2"
REPO="$(pwd)"
SEEDS="${SEEDS:-1-4}"
DAYS="${DAYS:-60}"

mk () {   # mk <name>  → 复制一份干净的出货树到 $SP/mut_<name>/game
  rm -rf "$SP/mut_$1"
  mkdir -p "$SP/mut_$1"
  cp -r "$REPO/game" "$SP/mut_$1/game"
}
run () {  # run <name>
  "$GODOT" --headless --path "$SP/mut_$1/game" -s res://bench/Harness.gd -- \
      --seeds "$SEEDS" --days "$DAYS" > "$SP/mut_$1.txt" 2>&1
  echo "── $1 ──"
  grep -E "#41 |S0 GATE" "$SP/mut_$1.txt" | head -3
}

# ── m1：把 produce 事件的目击者拆回去（`_stock_move` 恢复恒 []）───────────────
#     守的是"①produce 事件真的带上了目击者"这一臂。
mk m1_no_witness
python - "$SP/mut_m1_no_witness/game/scripts/Sim.gd" <<'PY'
import sys,io
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
old='\t_log_event(type, actor_id, "town", good, true, witnesses, "%s*%d" % [reason, absi(applied)])'
new='\t_log_event(type, actor_id, "town", good, true, [], "%s*%d" % [reason, absi(applied)])'
assert old in s, "m1 anchor missing"
io.open(p,'w',encoding='utf-8',newline='').write(s.replace(old,new,1))
PY
run m1_no_witness

# ── m2：把社会后果整段摘掉（只留目击者，不写信念/声誉/记忆）──────────────────
#     守的是"②别人真的形成了 CR:<职位> 信念"这一臂。
mk m2_no_fallout
python - "$SP/mut_m2_no_fallout/game/scripts/Sim.gd" <<'PY'
import sys,io
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
old='\t\tif not cc.is_empty() and not wits.is_empty():\n\t\t\t_craft_fallout(ag, wits, title, good, cc)'
new='\t\tif false:\n\t\t\t_craft_fallout(ag, wits, title, good, cc)'
assert old in s, "m2 anchor missing"
io.open(p,'w',encoding='utf-8',newline='').write(s.replace(old,new,1))
PY
run m2_no_fallout

# ── m3：把目击者接成全局副作用（所有产者都带目击者，不再只有开了本机制的那一门）──
#     守的是"④没开本机制的手艺不许留痕"这一臂——也就是"这是【一门】手艺的产出"这句话。
mk m3_global_leak
python - "$SP/mut_m3_global_leak/game/scripts/Sim.gd" <<'PY'
import sys,io
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
old='\tvar wits: Array = _nearby_agents(ag) if not cc.is_empty() else []'
new='\tvar wits: Array = _nearby_agents(ag)'
assert old in s, "m3 anchor missing"
io.open(p,'w',encoding='utf-8',newline='').write(s.replace(old,new,1))
PY
run m3_global_leak

# ── m4：张冠李戴（信念的 subject 写成镇库而不是干活的人）─────────────────────
#     守的是"③subject 必须是本人"这一臂。
mk m4_wrong_subject
python - "$SP/mut_m4_wrong_subject/game/scripts/Sim.gd" <<'PY'
import sys,io
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
old='\t\t\ts["beliefs"][bid] = {"claim": claim, "subject": String(worker["id"]), "source": "__seen__", "via": "seen", "tick": tick_no}'
new='\t\t\ts["beliefs"][bid] = {"claim": claim, "subject": "town", "source": "__seen__", "via": "seen", "tick": tick_no}'
assert old in s, "m4 anchor missing"
io.open(p,'w',encoding='utf-8',newline='').write(s.replace(old,new,1))
PY
run m4_wrong_subject

# ── m5（**预期【绿】** = does_not_detect 的第一条）：把声誉增量设成 0 ──────────
#     信念照形成、事件照带目击者，只是【没有人因此改变对他的看法】。
#     这一条必须真的跑出来，才敢写进 does_not_detect（docs/41 §2.5：那一栏必须是跑出来的）。
mk m5_zero_standing
python - "$SP/mut_m5_zero_standing/game/data/production.json" <<'PY'
import sys,io,json
p=sys.argv[1]; d=json.load(io.open(p,encoding='utf-8'))
d["craft_credit"]["环卫工"]["standing"]=0.0
json.dump(d,io.open(p,'w',encoding='utf-8'),ensure_ascii=False,indent=2)
PY
run m5_zero_standing

# ── m6（**预期【绿】** = does_not_detect 的第二条）：目击者名单塞不在场的人 ──────
#     把 `_nearby_agents(ag)` 换成"全镇所有人"——事件带目击者、信念照形成，
#     而门看不出这些人当时根本不在广场上。
mk m6_fake_witness
python - "$SP/mut_m6_fake_witness/game/scripts/Sim.gd" <<'PY'
import sys,io
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
old='\tvar wits: Array = _nearby_agents(ag) if not cc.is_empty() else []'
new='\tvar wits: Array = []\n\tif not cc.is_empty():\n\t\tfor _o in agents:\n\t\t\tif String(_o["id"]) != String(ag["id"]):\n\t\t\t\twits.append(_o)'
assert old in s, "m6 anchor missing"
io.open(p,'w',encoding='utf-8',newline='').write(s.replace(old,new,1))
PY
run m6_fake_witness

# ── m7（**预期【绿】** = off 门自检）：把键摘掉 ───────────────────────────────
mk m7_key_off
python - "$SP/mut_m7_key_off/game/data/production.json" <<'PY'
import sys,io,json
p=sys.argv[1]; d=json.load(io.open(p,encoding='utf-8'))
d.pop("craft_credit",None); d.pop("_v1_craft_credit_why",None)
json.dump(d,io.open(p,'w',encoding='utf-8'),ensure_ascii=False,indent=2)
PY
run m7_key_off
