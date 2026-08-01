#!/usr/bin/env bash
# Living Town CI — runs locally and in GitHub Actions. Fails (exit 1) on any red step.
#   GODOT     path to the Godot 4.6.2 headless binary (default: godot on PATH)
#   CI_SEEDS  S0 seed range (default 1-12)      CI_DAYS  S0 days (default 60)   CI_DET  det seeds (default 3)
#   CI_POOL_N/CI_POOL_SEEDS/CI_POOL_DAYS/CI_POOL_DET  4a 宏观池尺度门 (default 16 / 1-12 / 60 / 1)
#   CI_BG_SEEDS/CI_BG_DAYS/CI_BG_N  4d 外部后端门 (default 1-4 / 8 / 12)
# Fast local plumbing check: CI_SEEDS=1-3 CI_DAYS=30 bash tools/ci.sh
#   （原注释写的是 CI_DAYS=20 —— 实测在【改动之前的树上就已经是红的】：软不变量 #08「承诺生命周期」
#     在 20 天里 0/3（invite→meet 的赴约要更长的 horizon），所以那条"快跑"从来跑不绿。30 天是实测最近的绿点。
#     注意 CI_DAYS≠60 时金标无可比行（摘要与天数绑定），会打印"0 条可比"——快跑只查管路，不构成跨进程锚。）
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
CI_SEEDS="${CI_SEEDS:-1-12}"; CI_DAYS="${CI_DAYS:-60}"; CI_DET="${CI_DET:-3}"
# 日志目录按【本仓库路径 + PID】隔离：多 worktree 并行跑 CI 时，固定的 /tmp/lt_*.log 会互相覆盖——
# 判定本身走 PIPESTATUS 不受影响，但 scan 步骤会去读【别人的】日志，误报/漏报都可能（B10 实测踩到）。
LT_LOG="${LT_LOG:-/tmp/lt-$(printf '%s' "$PWD" | tr -c 'A-Za-z0-9' '_' | tail -c 40)-$$}"
mkdir -p "$LT_LOG"
PY="${PYTHON:-python}"
FAIL=0
ok(){ echo "  ✅ $1"; }
bad(){ echo "  ❌ FAIL: $1"; FAIL=1; }

# ── 运行期错误哨兵 ──────────────────────────────────────────────────────────
# 为什么需要：GDScript 的 push_error() / SCRIPT ERROR 【不改变进程退出码】。
# 例：Sim.gd:304 在数据文件缺失时 push_error("缺数据文件: ...") 然后继续跑——整条 CI 依旧全绿。
# 所以每个【运行期】步骤（4 / 4b / 4c / 4d / 4e / 5）的输出都必须做模式扫描，只靠 exit code 是不够的。
#
# ── 白名单纪律（2026-07-26 D1 收窄）────────────────────────────────────────
# 唯一合法的噪声是 NobodyWho（端侧 SLM）GDExtension 的开场白：红线#4 不许 .so/.dll 入库，于是
# `--import` 之后【每一次】godot 启动都固定打这 4 行（实测：--script 与 scene 两种模式都恰好 4 行）。
# 旧白名单是 `nobodywho|GDExtension|open_dynamic_library|load_extensions|Condition "!FileAccess::exists(path)" is true`，
# 按【裸子串】放行，于是那条 Condition 把**每一个被扫步骤里的任何 FileAccess::exists 失败**都遮住了
# ——数据文件、场景、存档、资源缺失全在内（docs/43 §1.2j-④ 点的名）。现在改成【绑上下文】：
#   · 两行指名 nobodywho ⇒ 按名放行。换成别的扩展缺失，名字对不上 ⇒ 红。
#   · 两行是裸的 Condition ⇒ 只在它紧随的 "at:" 行是 `open_dynamic_library` 时放行；
#     且任何多出来的缺失动态库都会同时产生一条【指名】的 "not found: '<path>'" ⇒ 那条名字对不上 ⇒ 红。
#     （全仓库 .gd 里没有任何 `OS.open_dynamic_library` 调用，故不存在"只有裸行、没有指名行"的路径。）
# 额外白名单（第 3 参）现在必须带【预期条数】（第 4 参）：放行的是**被断言的那一条**，不是这个模式的所有出现。
ERR_PAT='SCRIPT ERROR|USER ERROR|Parse Error|Failed to load script|ERROR:'
ERR_OK='(GDExtension dynamic library not found|Error loading extension): .res://addons/nobodywho/|Condition "!FileAccess::exists\(path\)" is true\..* at: open_dynamic_library '

# Godot 的一条错误占两行（"ERROR: ..." + "   at: fn (file:line)"）。把它们拼成一条记录再过滤，
# 白名单才可能要求上下文。顺带去掉 CRLF 的 \r（Windows 上的 godot 写的是 \r\n）。
pair_errs(){ awk -v P="$ERR_PAT" '{ gsub(/\r/,""); l[NR]=$0 }
  END { for (i=1;i<=NR;i++) if (l[i] ~ P) { r=l[i]; if (l[i+1] ~ /^[ \t]*at: /) r = r " " l[i+1]; print r } }' "$1"; }

scan(){  # scan <label> <logfile> [额外白名单正则] [该正则的预期条数]
  local extra="${3:-}" want="${4:-}" hits n
  hits=$(pair_errs "$2" 2>/dev/null | grep -avE "$ERR_OK")
  if [ -n "$extra" ]; then
    n=$(printf '%s\n' "$hits" | grep -acE "$extra")
    hits=$(printf '%s\n' "$hits" | grep -avE "$extra")
    if [ -n "$want" ] && [ "$n" -ne "$want" ]; then
      bad "$1 (白名单 '$extra' 出现 $n 次，预期恰好 $want 次 —— 多了=新的未解释错误，少了=那条被断言的负例没跑到)"
    fi
  fi
  hits=$(printf '%s' "$hits" | grep -av '^[[:space:]]*$')
  if [ -n "$hits" ]; then echo "$hits" | head -12; bad "$1 (运行期错误行，见上)"; fi
}

echo "### 0. 版权红线：git 里不得有模型权重 / 预编译二进制"
# 红线#4。.gitignore 今天只挡 game/models/*.gguf —— 换个目录放权重就会被静默入库。
# 这里对【整棵已跟踪树】把关，而不是对某个目录。
#
# 2026-08-01：从一行手写扩展名清单换成 tools/assert_no_weights.py（两条臂）。
# 起因是 S2 的对抗评审（编号 73）把这道门点名为【纸】。我复核了它：
#   旧清单 `\.(gguf|so|dll|bin|safetensors|pt)$` 对 14 个样本文件名只抓住 7 个，
#   放过 .onnx / .tflite / .pth / .dlc / .so.1 / .dylib —— 而 .tflite 与 .dlc
#   恰好是本项目端上 SLM 真会产出的两种格式。
# 更要紧的是**改名就能绕过去**，所以新门加了一条读幻数的内容臂。
# 负对照：`python tools/assert_no_weights.py --self-test`（三例，含"GGUF 改名成 .dat"）。
"$PY" tools/assert_no_weights.py && ok "no tracked weights/binaries" \
                                 || bad "tracked weights/binaries (红线#4：权重与二进制一律不入库)"
"$PY" tools/assert_no_weights.py --self-test >/dev/null 2>&1 \
  && ok "红线#4 负对照（该抓的三例都抓住了）" \
  || bad "红线#4 负对照失败 —— 这道门没牙"

echo "### 1. data lint (json parse + foreign keys + 必需数据文件在位)"
"$PY" tools/lint_data.py && ok "lint_data" || bad "lint_data"

echo "### 1b. map audit (town-world 导航自洽：typed-layers 一致 + 全可达 + 每家具有交互格 + ≥2 路线)"
"$PY" tools/audit_map.py && ok "audit_map" || bad "audit_map"

echo "### 2. link lint (markdown relative links)"
"$PY" tools/lint_links.py && ok "lint_links" || bad "lint_links"

echo "### 2b. art gate (出货 game/assets/art/pro 必须等于 coif_characters.py 当场重建的结果)"
# 为什么现在才有这一步（docs/49 §〇）：在它之前，本文件里【没有任何一处】提到 assets / art / palette /
# coif / deprop —— 唯一的字面命中是上面 4b 那行 `fresh-rest**art**` 里的三个字母。
# ⇒ 十张出货角色表是这个仓库唯一一类"改了没有任何门会响"的资产，而它同时是玩家唯一直接看得见的东西。
# 删一张、被 deprop 覆盖一张、手改一个像素——步骤 0-6 每一步都照样全绿。
#
# 判据不是"校验和清单对得上"（那种门可以靠更新清单通过，而更新清单正是偷改像素的人下一步会做的事），
# 是**当场从 library/ 重新生成、再逐字节比对**。
# ⚠️ 硬判据只认**解码后的 RGBA 像素**；PNG 容器字节只打印不判红（它随 zlib/Pillow 版本走，
#    而"一道在别人机器上因环境变红的门比没有门更坏"——理由与下面第 6 步同源）。
#
# 负对照（G1 实测，全部亲眼看着变红，见 docs/49 §一 验收 1/2）：
#   ① 单独跑 deprop_characters.py（已知的静默回退路径）⇒ 9/10 张红（Character-Base 它不写，故绿）；
#      逐张 13542-17508 px 不同，其中 832-1094 px 落在 12 个可达帧上。
#   ② 某张表某个像素蓝通道 +1（能做的最小改动）⇒ 红，指名 Soldier-Yellow 表内(46,14)。
#   ③ 删一张 ⇒ "缺 1 张"；④ 塞一张管线生成不出来的 ⇒ "多出 1 张"；
#   ⑤ 把重建源头指向 pro/（coif :444 记过的 x→x 退化）⇒ "抄答案不是重建"；
#   ⑥ 把比对器改成恒返回"一样" ⇒ 门内每次都跑的 1px 判别力自检把它抓住。
# ⚠️ 它需要 Pillow。装不上就没有这道门 ⇒ 直接红，不做 SKIP：
#    SKIP 与 PASS 在汇总里都读作"没红"，那会把这道门退化成一枚看不见结果的硬币（visual_gate.sh 抬头③）。
"$PY" tools/art_gate.py && ok "art gate（出货 pro/ == 当场重建）" || bad "art gate（出货 pro/ != coif_characters.py 当场重建的结果）"

echo "### 2c. terrain gate (出货 game/assets/art/terrain 必须等于 slice_shore.py 当场重建的结果)"
# G5（docs/49 §七）。与 2b 同一套形状，守的是另一类资产：13 张地形瓦（5 张原有 + 8 张本棒新加的岸线瓦）。
# 由来：G1 建 2b 时点名"另有 31 张出货 png 一道门都没有"（emote 10 / decor 8 / terrain 5 / obj 5 / building 3）。
# 本棒把 terrain 那 5 张（现 13 张）补上；**其余 26 张仍然无门**，理由写在 terrain_gate.py 抬头
# （没在真机上眼验过的东西不该被钉成"正确"——本棒的整个由来就是一张没人看过的贴图躺了一个月）。
#
# 负对照（G5 实测，逐条亲眼看着变红 + 核过退出码）：
#   ① 某张岸线瓦翻 1 个像素 ⇒ 红，指名 water_n (7,9)，exit 1；
#   ② 删一张 ⇒ "缺 1 张 water_se"，exit 1；改回来 ⇒ exit 0。
#   ③ 门内每次都跑的 1px 判别力自检守着"比对器退化成恒真"。
#   ④ 本门特有的第 4 条：slice_shore.LEGACY 与 slice_visual.py 里那两份切图坐标必须逐个相同
#      （两份漂开的话，"重建"重建的就不是出货文件真正的来源）。
# ⚠️ 同 2b：硬判据只认解码后的 RGBA 像素；PNG 容器字节只打印不判红。
#    实测 5 张 legacy 瓦的容器字节与本机 Pillow 重编码**不同**（它们当年是 ffmpeg 切的）而像素全同
#    —— 这正是"容器字节必须是软判据"的现成例子。
"$PY" tools/terrain_gate.py && ok "terrain gate（出货 terrain/ == 当场重建）" || bad "terrain gate（出货 terrain/ != slice_shore.py 当场重建的结果）"

echo "### 2d. asset gate (上门的 22 张 emote/decor/obj png == 切图/自绘配方当场重建 + 表情两两可分 + 配方无断口)"
# H2（docs/50 §二）。与 2b / 2c 同一套形状的**第三个实例**（不是第三种形状）：当场从 CC0 库重建 → 解码后逐像素比对。
# 由来：2c 抬头点名"其余 26 张仍然无门"，而 G5 刻意没上门的理由必须继承——
#   **给没人眼验过的美术上门 = 把当前状态钉成"正确"**（池塘那个 bug 正是这样活了一个月）。
#   H1 于 2026-07-30 把 26 张在真机上逐张看完（docs/51），这一步只给它判为 OK 的 **10 张**上门。
#
# ⚠️ 范围是刻意窄的，只剩 1 张【故意不守】，这不是欠债，是本棒的要点：
#   · decor/tree_small —— 判「从不出现」：它不在 `WorldView.DECOR_POOL` 里。
#     **给上不了屏的素材上门 = 把死资产钉成"正确"**（docs/50 §八）。
#     门每次运行都**重新核**这一条；哪天有人接上线，它会红——那正是该重新眼验、重新决定的时刻（棘轮）。
#   （9 张 emote 由 I1 重画后上门；obj/bath、obj/arcade、decor/tree_big 由 J2 重画后上门，见下。）
#
# ⚠️ **2026-07-30 J2 变更：那三张「读不出/需重切」的图重画完了，并且给这道门加了第 3 条性质。**
#   `obj/bath`、`obj/arcade`、`decor/tree_big` 改为**自绘**（配方在 `slice_all.SPRITES` 的字符画里，
#   与 I1 给 9 张 emote 做的是同一条路）。**三张的病不是同一种**：`tree_big` 真的切错了
#   （右边界 27/32、下边界 29/32 个不透明像素）；另两张一个像素都没切错，错在**题材**
#   ——那两格画的是一口井和一根告示柱，而 `WorldView._draw_landmarks()` 里本来就有程序化的
#   `well` 与 `board`（`board` 就在 `arcade_1` 正下方 2 格）。
#   新增的第 3 条性质是 **`bleed` 断口判据**：一条 crop 如果把图集里**连通的**美术拦腰截断，
#   切出来的就是碎片不是精灵。地板 0.10 是量出来的（阳性 shop 0.474 / tree_big旧 0.438 / hut 0.297 /
#   house 0.188；阴性 11 条并列 0.000、最高 tree_small 0.031 ⇒ 两侧余量 3.2x 与 1.9x）。
#   **它判的是配方几何、不是画得好不好，所以它覆盖【没上门】的那张**——house/shop/tree_big
#   三次都是缺这道门，而三次都是靠人眼在事后发现的。
#
# ⚠️ **2026-07-30 I2 变更：building/{house,hut,shop} 那 3 张已经不在"不上门"里了——它们被【删掉】了。**
#   H2 当初给的处置是"接线或删掉"，I2 眼验后选了删（docs/09 §1.1：消费者早在 `841d4c4` 就被当作
#   用户报的「比例失调」头号成因拆掉；另两张还是图集竖条断口）。png / `Art.building_tex()` /
#   `slice_visual.py` 的 3 行配方 / `asset_gate.NOT_GATED` 的 3 条**同批删除**。
#   **棘轮没消失，是换了输入**：原来那条查 `building_tex` 调用点，而它的输入随函数一起没了 ⇒
#   `check_deleted()` 改查"这三个名字有没有回来"（出货目录 / 切图配方 / `.gd` 非注释引用，三处任一即红）。
#
# ⚠️ 硬判据必须是**解码后 RGBA 逐像素**，不能是逐字节（docs/50 §二 坑①）：
#    H1 实测重切 26 张 ⇒ **逐像素同 26/26、逐字节同 0/26**。
#    ⚠️ **J2 更正了这个 0 的成因**：不是"出货那批当年被重新编码压缩过"（docs/51 §三·2 的说法）。
#    把两份配方原样放进 `gamecraft-runner:4.6.2` 容器里跑一遍 ⇒ **28/28 逐像素相同且逐【字节】相同**。
#    差的只是 ffmpeg 版本：容器里 **4.4.2**，H1 用的是宿主机 **8.1.2**。
#    ⇒ 结论不变、理由更结实：**字节取决于编码器版本，而这道门要在任何人的机器上跑。**容器字节只打印。
# ⚠️ 判据比的是 `Image.load()` 出来的 RGBA 元组，**不是 `getbbox()`**（docs/41 §6：它在 RGBA 上默认只看 alpha，
#    翻一个不透明像素的 RGB 会被判成"完全相同"）。门里带一个只打印的量具把这件事每次量给你看。
#
# 负对照（H2 实测，逐条亲眼看着变红 + 核过退出码与判决行，不是推断）：
#   ① **逐张**牙齿：10 张各翻 1 px，各跑一次完整的门 ⇒ **10/10 全红**，每次只点名那一张（detected 10/10）；
#   ② 红→绿：obj/bench 翻 1 px ⇒ FAIL rc=1；改回 ⇒ PASS rc=0；
#   ③ 删一张上门的（decor/stump）⇒ 红；删一张未上门的（emote/greet）⇒ **绿 + WARN**（刻意的，不在范围里）；
#   ④ 把比对器改成恒返回"一样" ⇒ 门内每次都跑的逐张自检报 detected 0/10 ⇒ 红；
#   ⑤ 重建源头指向出货目录 ⇒ 红（"这不是重建" / 只偷读一张也报"抄答案不是重建"）；
#   ⑥ 把死资产接上线（tree_small 进 DECOR_POOL）⇒ 红（棘轮生效）；**J2 复跑，仍然红（rc=1）**——
#      它是自证④这条臂**唯一的活输入**，而 J2 的 tree_big 是自绘的、没有消费掉 tree_small。
#   ⑦ **把一张到不了屏幕的图偷偷加进上门表** ⇒ 红「代码里到不了屏幕」——最想拦的那个错是机检的，不是靠自觉。
#   ⑧（J2）把 `tree_big` 单独退回 HEAD 的切图路线 ⇒ 断口臂红并点名：`decor/tree_big 断口 56/128 = 0.438`。
#      **这条是在【未改动的树】上跑出来的**（docs/41 §6 ★），不是只在我造的变异体上。
#   ⑨（J2）自绘那三张各翻 1 px ⇒ 各自红并点名（B/C/D 三个变异体，rc 均为 1）；
#      把 `render_drawn` 改成读出货 png ⇒ 红「抄答案不是重建」；清空 `SPRITES` ⇒ 红两处。
#   ⑧ **I2 加的 check_deleted，隔离副本 6 个变异逐条读判决行 + rc（不是推断）**：
#        M0 未改动                                        rc=0 PASS ← 无假红
#        M-a building/hut.png 回到出货目录                 rc=1 FAIL 点名该文件
#        M-b slice_visual.py 三行配方加回来                rc=1 FAIL（check_deleted + 范围自证各自报）
#        M-c .gd 里 `Art.tex("res://assets/art/building/hut.png")`  rc=1 FAIL 点名 WorldView.gd:690
#        M-d `func building_tex` 原样加回并调用            rc=1 FAIL 点名 3 行
#        M-e **只在注释里**提这两个词                       rc=0 PASS ← 负对照（旧判据在这里会假红）
#      does_not_detect：**把 `check_deleted` 那一行删掉 ⇒ 全绿**（M-g 实测 rc=0）。
#      这道判据没有"门自己会不会是假的"那层自检（`compare()` 有，靠每次跑的 1px 逐张牙齿），拆了没人拦。
#   ⑨ **删资产必须连表一起删**（I2 实测）：只删 png + 配方行、`NOT_GATED` 还写着它们 ⇒ 范围自证的
#      `phantom` 臂当场红「三张表里有 3 张配方根本产不出的图」rc=1。范围自证是**双向**的。
# does_not_detect（同样是实测的，docs/41 §2.5 要求这一栏必须跑出来）：
#   切图坐标与出货 png **一起**改 ⇒ 绿（bush 换成另一格瓦、124/256 px 不同，门一声不吭）；
#   未上门那 16 张整张像素取反 ⇒ 绿；容器重编码（160→1108 B、像素不变）⇒ 绿；
#   再加一种物件借 bench.png（第 6 个别名）⇒ 绿（那是 H3 的 OBJ_SLOT_ALIAS_BUDGET 的活）；
#   渲染侧砍掉 emote 绘制 ⇒ 绿（门只看文件，看不见屏幕）。
# ⚠️ 同 2b/2c：需要 Pillow，装不上直接红，不做 SKIP（SKIP 与 PASS 在汇总里都读作"没红"）。
"$PY" tools/asset_gate.py && ok "asset gate（上门的 22 张 emote/decor/obj == 当场重建 + 表情可分 + 配方无断口）" || bad "asset gate（上门的 22 张 != 切图/自绘配方当场重建，或表情两两可分度跌破地板，或某条 crop 从连着的美术中间切过去）"

# ── 2e. 可重算门 ────────────────────────────────────────────────────────────
# U3（编号 82）。守的是一件此前完全没有机器在守的事：
#   **一个写进文档的数，今天还能不能被重新算出来，以及算出来的还是不是同一个数。**
#
# 由来：T2（编号 77 §4.1b）把「brief 里的假数字」这一层一刀劈成两半——
#   真值在树上另有副本的 3/3 被抓住，**真值只此一份、必须重算的 0/2**。
#   A3 明写它为什么没抓到：**它去找 CIEDE2000 的工具想重算，而那套工具从未入库。**
# 而 S2（编号 73 §二·3）在 11 条臂上量出的统一结论指的是同一件事的另一面：
#   **每次运行都重算并打印余量的臂 9/9 至今准确；打印冻结字面量的两族全部过期。**
# ⇒ 这一步就是把"重算并打印"这条性质**变成一道门**，而不是一条谁都不会去查的宣言。
#
# 形状（tools/recalc_registry.json）：一条 = 一个【文档里的数】+【重算它的那条命令】。
#   · 期望值**不写在门里也不写在注册表里**，由 locator 正则从文档正文现抓；
#   · 实测值由 command 现跑现出。
#   ⇒ **全仓这个数只有一份**（在文档里），本步没有任何冻结字面量（唯一冻结的是容差）。
#
# ⚠️ 什么能上门是**量出来的**，写在编号 82 §4.2：
#   能上门 = 【HEAD 这棵树的性质】；不能上门 = 【随时间移动的快照】。
#   `lint_links` 印的「N 份 markdown」属于后者——谁加一份文档它都会变，
#   给它上门 = 造一道会因为无关改动变红的门，而那比没有门更坏（docs/41 §6）。
#   注册表里留了它一条 `gate:false` 的样本，**每次跑都打印、永远不判红**，
#   好让这条界线有一个可跑的例子而不是一句话。
#
# ── 探测包络（docs/41 §2.5；完整版见编号 82 §五）────────────────────────────
# detects（五个变异体都在 --self-test 里，每次 CI 跑一遍，不是一次性的）：
#   ① 只改文档里的数 ⇒ 红「文档写 X，现跑得 Y」；② 只改命令的输出 ⇒ 红；
#   ③ locator 命中 0 次 ⇒ 红，且信息说的是【锚点丢了】—— 数值比对拦不住"把整句话删掉"；
#   ④ locator 命中 >1 次 ⇒ 红（锚点不够窄，比中的可能不是同一个量）；
#   ⑤ gate:false 却没写 why ⇒ 红（与 §2.5 的 does_not_detect 同一条规矩）。
# does_not_detect（跑出来的）：
#   ① **只守注册表里那 5 条**（覆盖率 5/3740 ≈ 0.13%）。它是约定的载体，不是一次覆盖。
#   ② 守不住"这个数从写下时就是错的"——判据是自洽（文档值 == 现跑值）。
#      唯一的例外是 `ciede-sharma`，它比的是**外部**真值（Sharma-Wu-Dalal 34 对）。
#   ③ 守不住要重跑网格 / 要渲染 / 要模型的数：本步刻意只收 2 s 以内、不进 godot/docker 的条目。
#      编号 82 §1.4 量到 10/19 条"无重算路径"的数是**模型路**的，而红线#4 不许权重入库
#      ⇒ 它们**结构上**进不了这个注册表，这不是漏。
#   ④ 守不住"随时间移动的快照"——那是 §4.2 故意排除的。
# confidence：N=5 个变异体（自检五臂），另加 ciede2000 自己的 34 对外部真值。
# 成本：约 2 s（asset_gate 0.5s × 1 + ciede2000 × 2 + lint_links × 1，同一条命令只跑一次）。
echo "### 2e. 可重算门 (文档里的数 == 现跑那条命令算出来的数)"
"$PY" tools/recalc.py --self-test >"$LT_LOG/recalc_selftest.log" 2>&1 \
  && ok "可重算门 负对照（改文档值/改实测值/丢锚点/缺理由 四条都会红）" \
  || { tail -12 "$LT_LOG/recalc_selftest.log"; bad "可重算门 负对照失败 —— 这道门没牙"; }
"$PY" tools/recalc.py --gate 2>&1 | tee "$LT_LOG/recalc.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "可重算门（注册表逐条现读现算现比）" \
  || bad "可重算门（有数字与它自己的重算命令对不上，见上）"
# ciede2000 是本步两条条目的量具，它自己的负对照也每次跑（外部真值 34 对 + 扰动 + 与现役门交叉核对）
"$PY" tools/ciede2000.py --self-test >"$LT_LOG/ciede.log" 2>&1 \
  && ok "CIEDE2000 量具自检（Sharma-Wu-Dalal 34 对外部真值 + 扰动 + 与 assert_interior_shell 同源）" \
  || { tail -12 "$LT_LOG/ciede.log"; bad "CIEDE2000 量具自检失败"; }
# 普查器（编号 82 §一 的数字出自它）：只跑它自己的三条分类翻面负对照，不判普查结果
# —— 普查结果是【随语料移动的快照】，按 §4.2 那条界线它不该上门。
"$PY" tools/recalc_scan.py --self-test >"$LT_LOG/recalc_scan.log" 2>&1 \
  && ok "可重算普查器 负对照（三条分类翻面）" \
  || { tail -12 "$LT_LOG/recalc_scan.log"; bad "可重算普查器 负对照失败"; }

echo "### 3. godot import + parse smoke"
"$GODOT" --headless --path game --import >"$LT_LOG/import.log" 2>&1 || true
if grep -qiE 'SCRIPT ERROR|Parse Error|Failed to load script' "$LT_LOG/import.log"; then
  grep -iE 'SCRIPT ERROR|Parse Error|Failed to load script' "$LT_LOG/import.log" | head; bad "godot parse"
else ok "import/parse clean"; fi

echo "### 4. S0 gate (invariants + determinism + 金标; seeds=$CI_SEEDS days=$CI_DAYS det=$CI_DET)"
# --golden：跨进程/跨提交/跨引擎版本锚（红线#1）。没有它，CI 只证明「同一二进制同一进程内跑两次一样」。
"$GODOT" --headless --path game --script res://bench/Harness.gd -- \
  --seeds "$CI_SEEDS" --days "$CI_DAYS" --det "$CI_DET" \
  --golden game/bench/golden_digests.json 2>&1 | tee "$LT_LOG/s0.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "S0 gate" || bad "S0 gate"
scan "S0 gate" "$LT_LOG/s0.log"

# ── 4a. 宏观池尺度门 ──────────────────────────────────────────────────────────
# 由来：K1（merge `ed599e8`）把产出侧改成宏观池 `production = _pool_rescale(_production_raw, agents.size())`，
# 并在自己的回执里点名留下这一条。出货阵容 **N=12 == scale.base_population=12 ⇒ 倍率恰为 1 ⇒
# `_pool_rescale` 直接 return raw、一个整数都不算**（Sim.gd:2952-2953 是显式的短路），
# 而上面第 4 步恒 N=12（不传 `--agents`）⇒ **换尺度之后的产出表，从来没有被任何一条判据评估过。**
#
# ⚠️ **说准一点：不是「算术一次都没执行过」。** docs/58 §一 与 K1 回执都是这么写的，两处都不严谨；
#    docs/54 §八「更正二」早就把话说对了，而它没有被抄进后来的 brief。事实：
#      · 第 4b 步 `lod_verify` 传 `CI_LOD_N:-48` ⇒ **乘除每一次 CI 都在跑**；
#      · 但 4b **只比对 [Inv.digest, event_digest] 双摘要，从不调 `Inv.check_all`**；
#      · 而且它跑 **3 天 < Invariants.SUPPLY_MIN_DAYS=60** ⇒ 就算给它接上判据，
#        #40 的满足率臂也按构造禁用（会打印「未启用(3<60天)」）。
#    **本棒把这件事量成了两个数**（seed 17 × 3 天 × N=48，也就是 4b 自己的配置）：
#        产出走宏观池     digest 632226373  event_digest 7136159286272743904  events 650
#        产出走逐笔契约   digest 990424415  event_digest  526545081279226260  events 688
#      ⇒ **换尺度的算术确实在跑，而且确实改了轨迹**（两份摘要没有一位相同）；
#      **然而同一棵 pooled 树与同一棵逐笔树上，4b 都是 `LOD-VERIFY GATE: ✅ PASS`**
#      ——它比的是"自己跟自己一致"，不是"值对不对"，所以**它对这件事的分辨率恰好是零**。
#    ⇒ 真正的缺口窄一格、也更难看见：**「大 N」与「供给判据」在这道 CI 里此前是互斥的。**
#    这是 docs/41 §2 第三个盲区（一道门跑在一个它守的那件事不可能发生的配置上）的又一实例，
#    **而这一个是 Wave K 我们自己刚造出来的**。本步就是把它消掉，所以它自己绝不能又造一个（见下面的预检）。
#
# ── 为什么是 N=24，而不是 docs/58 §一 写的 N=16 —— **实测否掉的，不是偏好** ──────────────
#   未改动的出货树上跑 S0 全套判据（12 seed × 60 天，backend=null，无 LOD），逐 N 的判决：
#     N=16  ❌ FAIL   #40 软门 **10/12**（红 seed 8,9；软门要 ≥11）           141 s
#     N=20  ❌ FAIL   **硬 #01 红 seed 6**（social 触底 106 tick·need，det 1/1 两跑一致） 196 s
#     N=24  ✅ PASS   硬 12/12 · #40 11/12 · 活性过 · det 过                 291 s
#     N=60  —         K1 实测 #40 红 2/12 ⇒ 软门破；本棒只复跑到 seeds 1-3（3/3 绿），
#                     12 seed ≈990 s 超单次工具上限，没有复跑到红的那两个 seed。
#   ⇒ **N=24 是唯一一个今天能绿的大 N 格。** 照 docs/58 §一 写的 N=16 接进来 = CI 当场变红。
#   ⚠️ 而且 **N=16 上那条 brief 指定的负对照是【空的】**：实测删 scale 块之后 N=16 也是 **10/12**
#     （红 seed 4,5 而不是 8,9）——**红/绿两侧同为 2/12**，改与不改分不开。
#     在 N=16 建这一格，会同时得到"未改动的树上就是红的"和"负对照也红"两件坏事。
#   ⚠️ N=20 的那条硬 #01 值得单独记一笔：**逐笔契约下 N=20 的硬 #01 是 12/12 绿**（本棒实测，
#     与 docs/54 §五 的表一致），**上池之后才在 seed 6 红**；而同一张表在 N=24 上方向相反
#     （逐笔红 seed 3 → 上池后 12/12 绿，本棒两边都实测到）。⇒ **池【移动】了 #01 的落点，
#     不是单调变好或变坏**；格数是 72 分之 3，按 docs/41 §5 只能读作"这个网格分辨不出"。
#
# ⚠️ **余量是 0，写在这里让下一个人一眼看见**（docs/41 §5「收紧判据前先量余量」）：
#   #40 在 N=24 上是 **11/12，恰好等于软门阈值**，唯一的红是 seed 8（口粮 满足率 0.48 < 下限 0.50）。
#   **再红一个 seed 这一步就变红。** 这不是「别的机器上会假红」那种病（同 seed 同二进制逐字节可复现，
#   与机器快慢无关），是真实的灵敏度。嫌太紧的话 `CI_POOL_SEEDS=1-6` ⇒ 6/6 全绿、容 1 个红、成本减半
#   （seed 8 落在 7-12 那半）——**但那等于把 fixture 朝最容易过的方向选，正是第三个盲区的病**，故默认取全网格。
#
# **不传 `--golden`**：`golden_digests.json` 是在 N=12 出货阵容上烘的，N=24 的 digest 与它天生不同
#   ⇒ 传了只会因为「对不上一份本来就不该对上的表」变红。跨进程锚仍由第 4 步独占，本步守的是**判据**。
#
# ── 成本（实测墙钟。⚠️ 本机全程有并行棒的 godot 在跑，run-to-run 噪声很大，所以给区间不给单点）──
#     本步单跑（12 seed × 60 天 + det 1）：**239 s / 291 s**（两次，同一命令）。
#     docs/54 §七 的干净串行参照：N=24 × 12 seed = 179 s，加 det 1 约 **195 s**。
#     整份 `tools/ci.sh`：接入前 **683 s**；接入后两次分别 **775 s / 909 s**，三次都读到 `=== CI PASS ✅ ===`。
#     ⇒ 诚实的说法是「**+200 s 上下，约 +30%**」，而**不是** 909−683=226 这个看起来很精确的差
#       （同一棵接入后的树两次相差 134 s，噪声比信号的一半还大）。
#     嫌贵：`CI_POOL_SEEDS=1-6` 成本减半（但见上面「余量是 0」那段——它同时把 seed 8 拿掉了）。
#
# ── 负对照（**实测**，隔离副本，只删 `production.json` 的 `scale` 块 = K1 的 ablation 开关）──
#     未改动的树     rc=0  S0 GATE PASS ✅   #40 **11/12**  硬 12/12
#     删掉 scale 块  rc=1  S0 GATE FAIL ❌   #40 **1/12**   硬 **11/12**（#01 红 seed 3）
#   逐 seed：删块后 seed 1,2,4-12 的 #40 全红，seed 3 直接硬红。
#   ★ 这一列与 docs/54 §二/§五 在**同一个 N=24 上独立测过的那两行逐位吻合**（11 个红 + 硬 #1 落在 seed 3）
#     ⇒ 负对照复现了一份更早的独立测量，不是我自己造出来的孤证。
#   ⚠️ 把 `base_population` 改成 24 与「删 scale 块」在**返回值上是同一件事**（`num == base` 直接 return raw）
#     ⇒ 上面那条红对那种改法逐字节同样成立，不必再跑一遍。
#
# ── 探测包络（docs/41 §2.5）────────────────────────────────────────────────────
# detects（四个变异体逐条跑过，**读的是判决行不是退出码**）：
#   ① 删 `scale` 块（brief 指定的那条）⇒ **预检**红（0.2 s，不进 godot）；同一份数据在 Harness 上
#      单跑也红：rc=1、#40 1/12、硬 #01 seed 3。**两条臂各自都抓得住它。**
#   ② `CI_POOL_N=12`（倍率退化为 1）⇒ 预检红：「池倍率 12/12 恰为 1 ⇒ 会退化成第 4 步的复读」。
#   ③ `CI_POOL_DAYS=30`（< SUPPLY_MIN_DAYS）⇒ 预检红：「#40 满足率臂按构造禁用」。
#   ④ **`scale` 块在、倍率对、`pool` 列表清空**（一个字段都不换尺度 ⇒ production 与逐笔逐值相同）
#      ⇒ **预检看不见它**（预检只查倍率与天数），只有判据抓得住：整份 CI 跑完 **`=== CI FAIL ❌ ===` rc=1，
#      全文件恰好一条 `❌ FAIL: 宏观池尺度门`，其余每一步照旧全绿（含第 4 步 N=12 金标 PASS）**。
#      ★ 这一条是四个里最重要的：**它证明红不是预检独占的**，昂贵的那条判据臂自己就有牙。
#      ★ 它的逐 seed 数与 ① 逐位相同（#40 1/12、硬 #01 seed 3、seed 1 口粮 0.48/屋瓦 0.45）
#        ——因为两者产出表逐值相同，这是构造上的必然，不是巧合。
#      ⚠️ 并且它暴露了一件事：`detail` 里那句「产出契约=宏观池 ×24/12」在这个变异体上**照样打印**
#        （`prod_pooled` 只记倍率、不记有没有真的换过字段）⇒ **那行字不是证据，判据才是。**
# does_not_detect（**跑出来的，不是想出来的**）：
#   ① **整除截断那一路**：24 是 base 的整数倍 ⇒ `v*24/12` 精确、`maxi(1,·)` 两处钳位**一次都不触发**。
#      真正会截断的是 N∉12ℤ（16 的 ×4/3、20 的 ×5/3），而那两个 N 今天是红的
#      ⇒ **K1 那两处「原料/损耗永不取整到 0」的保护，本门守不住。**
#   ② **N=60 那一端没有门**：本门跑 N=24；K1 实测 N=60 上 #40 仍红 2/12
#      （本棒复跑 seeds 1-3 = 3/3 绿，没复跑到红的那两个）。
#   ③ 继承 #40 自己的盲区：**没有上限臂**（K1 实测批量 ×8 ⇒ #40 绿 2/2 @N=60）；
#      原料需求靠「在班完成次数 × 用量」重建，第二条不经 `_produce_for` 的原料通道会让分母静默偏低（docs/54 §十）。
#   ④ **`pool` 列表只被削掉一部分**（例如只留 `amount`）：没测。K1 测过 amount+inputs 那一档在 N=60 上仍红，
#      但**在 N=24 上会不会红没人跑过** ⇒ 这一门对"池被削薄"的分辨率不明。
#   ⑤ 帧时 / 内存 / 真机 / 有玩家 / 有 SLM 后端 / 有 LOD：本步是 backend=null 的 headless 地板，
#      docs/41 §2 点名的五个温和配置里它只换掉了 N=12 这一个。
# confidence：**N=4 个变异体**（数据侧 2 个：删块 → 预检红且判据也红 / 清空 pool → 只有判据红；
#      配置侧 2 个 → 预检红），另在 5 个网格（N=16/20/24/24-删块/16-删块，各 12 seed × 60 天）
#      上量过判据的红绿分布，N=60 只有 3 个 seed。
POOL_N="${CI_POOL_N:-16}"; POOL_SEEDS="${CI_POOL_SEEDS:-1-12}"
POOL_DAYS="${CI_POOL_DAYS:-60}"; POOL_DET="${CI_POOL_DET:-1}"
# ⚠️ 这一段必须用【带引号的 heredoc】，不能用 echo "…"：
#   T3 查出（我已复现）原来那个多行 echo 的双引号里含反引号 `maxi(1,·)` ⇒ bash 每次运行都做一次
#   命令替换，报 `syntax error near unexpected token` ——**而且它把那段文字吃掉了**：
#   `maxi(1,·)` 整个消失，连同它后面那对双引号。CI 从不因此变红，所以没人发现。
cat <<'POOL_NOTE'
# ★ 默认从 N=24 翻成 N=16（2026-07-31，L1 给的建议 + 主 session 实测复核）：
#   ① 更便宜：合并树上 146s vs 239s（−39%）。
#   ② 覆盖更宽：16/12 = ×4/3 会走【整数截断】那条路，而 24 是 12 的整数倍 ⇒ 因子恰好 ×2、
#      `maxi(1,·)` 永不触发，K1 那句"inputs 不会舍入到 0"的守卫在 N=24 上【结构上测不到】。
#   ③ 它同时是 I3 实测的【边缘】（软门最早在 N=16 破）⇒ fixture 朝被守的性质最容易破的方向选，
#      而不是朝最容易绿的方向（契约 §2 第三个盲区）。
#   余量：⚠️ 这里原本写着"最紧一格仍有 0.188 的余量，不是卡边"。**那个数已经过期。**
#      S2（编号 73）把 6c7c8bc 拉进隔离副本复核：那棵树确实是 +0.189；
#      而在今天的树上做消融（从 utility.json 删 gossip_news_first/bonus）恢复到 +0.183
#      ⇒ **O1 的调参吃掉了约 3.4 倍余量，今天最紧一格是 0.056。**
#      这个数写在这里【本身就是 S2 那条统一结论的样本】：打印冻结字面量的都会过期。
#      ⇒ 别再手抄它了；要当真就去读 4a 每次运行自己打印的判决行。
#   L1 当时改不了这个默认，因为在它自己的分支上（L2 未合入）N=16 是红的。
POOL_NOTE
echo "### 4a. 宏观池尺度门 (N=$POOL_N seeds=$POOL_SEEDS days=$POOL_DAYS det=$POOL_DET；S0 判据首次跑在池倍率≠1 的配置上)"
# 预检①②：**照 `_pool_rescale` 自己的算法**（含 quantum 向上取整）从 production.json 现算倍率，
#   而不是写死 `POOL_N != 12` 那种比较——删 scale 块 / 改 base_population / 改 quantum 都会当场把它打红。
# 预检③：`SUPPLY_MIN_DAYS` 从源码 grep，不写魔数（判据改名/搬家 ⇒ 读不到 ⇒ 红，而不是静默放行）。
POOL_PRE=$("$PY" -c '
import json, sys
sc = (json.load(open("game/data/production.json", encoding="utf-8")).get("scale") or {})
base = int(sc.get("base_population", 0)); q = int(sc.get("quantum", 0)); num = max(1, int(sys.argv[1]))
if q > 0: num = ((num + q - 1) // q) * q
print(base, num)
' "$POOL_N" 2>/dev/null)
POOL_BASE="${POOL_PRE%% *}"; POOL_NUM="${POOL_PRE##* }"
SUP_MIN=$(grep -oE 'const[[:space:]]+SUPPLY_MIN_DAYS[[:space:]]*:=[[:space:]]*[0-9]+' game/bench/Invariants.gd | grep -oE '[0-9]+$')
POOL_PRE_OK=1
if ! [ "${POOL_BASE:-x}" -gt 0 ] 2>/dev/null; then
  bad "4a 预检：production.json 读不到 scale.base_population>0 ⇒ 产出侧退回逐笔契约，这一格守不住任何东西"; POOL_PRE_OK=0
elif [ "$POOL_NUM" -eq "$POOL_BASE" ]; then
  bad "4a 预检：N=$POOL_N 在 base_population=$POOL_BASE 下池倍率 $POOL_NUM/$POOL_BASE 恰为 1 ⇒ _pool_rescale 直接 return raw、一个整数都不算 —— 这一格会退化成第 4 步的复读（正是本步存在的理由）"; POOL_PRE_OK=0
elif ! [ "${SUP_MIN:-x}" -gt 0 ] 2>/dev/null; then
  bad "4a 预检：从 Invariants.gd 读不到 SUPPLY_MIN_DAYS（判据可能改名或搬家）"; POOL_PRE_OK=0
elif [ "$POOL_DAYS" -lt "$SUP_MIN" ]; then
  bad "4a 预检：days=$POOL_DAYS < SUPPLY_MIN_DAYS=$SUP_MIN ⇒ #40 的满足率臂按构造禁用（会打印「未启用」）—— 这一格会退化成 4b"; POOL_PRE_OK=0
fi
if [ "$POOL_PRE_OK" -eq 1 ]; then
  ok "4a 预检：池倍率 ×$POOL_NUM/$POOL_BASE ≠ 1（换尺度的算术真的会跑） · days=$POOL_DAYS ≥ SUPPLY_MIN_DAYS=$SUP_MIN（#40 满足率臂真的会评估）"
  "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
    --seeds "$POOL_SEEDS" --days "$POOL_DAYS" --det "$POOL_DET" --agents "$POOL_N" 2>&1 | tee "$LT_LOG/s0_pool.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] && ok "宏观池尺度门 (N=$POOL_N，产出契约=宏观池 ×$POOL_NUM/$POOL_BASE)" \
    || bad "宏观池尺度门 (N=$POOL_N，产出契约=宏观池 ×$POOL_NUM/$POOL_BASE)"
  scan "宏观池尺度门" "$LT_LOG/s0_pool.log"
fi

echo "### 4b. LOD 观察无关红线 (V2 相机路径无关 + V3 确定性/存读/fresh-restart)"
# 永久门：aggregate LOD 的 cohort 必须【只由 committed sim 态】选、绝不读相机 lod_focus。
# 若日后有人把 cohort 从相机取回，V2(5 个 lod_focus→同 digest) 立即变红（Main.gd:159 红线机器化）。
"$GODOT" --headless --path game --script res://bench/lod_verify.gd -- "${CI_LOD_N:-48}" "${CI_LOD_DAYS:-3}" 2>&1 | tee "$LT_LOG/lod.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "LOD viewer-independence gate" || bad "LOD viewer-independence gate"
scan "LOD gate" "$LT_LOG/lod.log"

echo "### 4c. DetGate 场景确定性门 (default / faction / betray / freerider)"
# Invariants.gd:15 对任何非空 scenario 豁免硬不变量 #1，且 Harness 没有 --scenario ——
# 在此门落地之前，三条内置定向场景在 CI 里跑过 0 次（docs/17 早就开了这个方子）。
"$GODOT" --headless --path game --script res://bench/DetGate.gd -- \
  --seeds "${CI_DG_SEEDS:-1-4}" --days "${CI_DG_DAYS:-20}" 2>&1 | tee "$LT_LOG/detgate.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "DetGate scenario determinism" || bad "DetGate scenario determinism"
scan "DetGate" "$LT_LOG/detgate.log"

echo "### 4d. BackendGate 外部后端门 (硬不变量含#01 / 同seed两跑一致 / 闭集封闭)"
# 为什么必须单独有这一步：上面每一道门（金标 / LOD / DetGate）都恒 Sim.backend=null（红线#2 的零模型地板）
# ⇒ AIBackend.decide() 从不被调用 ⇒ 硬不变量 #01 只在【引擎自己挑】的路径上验过。
# docs/38 §五 实测：同一份配置下 logic 0/8 seed 饿穿，random/slm 都是 8/8 —— CI 全绿与产品已破可以同时成立。
# 用 random 而不是 slm：random 的选号来自 Sim._rng_at(RANDOM_SALT) 确定性流、时延按 tick 计，逐字节可重跑
#   （本门自己把这条性质机检了：每个 seed 跑两遍比 digest/链）；slm 有 run-to-run 噪声，永远不进 CI。
#   两条臂走的是【同一条落地路】(decide→闭集选号→重验→agent_apply)，故这条路上的护栏一旦立住，两者同时受保护。
#   ⚠ 2026-07-30（E6/W5）收窄：上面这句**对 A/B 成立，对 C 不成立**。`random`/`slm` 结构上
#     都只能交回 `candidates` 的子集（`_instant_random` 挑下标 / `parse_decision` 取 `candidates[pk]`），
#     ⇒ C 的 escape 数在这两条臂上**恒为 0**，"闭集 1332/1332 ✅"是恒真、不是证据。
# 三条臂 + 一条自检臂（2026-07-26 D1 起，此前第三条是假的——它与第一条的 #01 逐位同一个谓词）：
#   A 硬不变量全绿  B 同 seed 两跑 digest/事件/逐tick前缀链一致  C 闭集封闭（后端交回的 intent 必在本次候选里）
#   S 自检臂 `inject:fabricate`（**只在门内部**，绝不进出货路径）：一个会篡改 `amount` 的假后端，
#     判据是**反的**——C 必须变红。它给 C 补上此前缺的那半：**注入时红、不注入时绿**。
#     实测（seeds 1-4 × 8 天）：伪造 141-147 次、探针恰好抓到 141-147 次、其中 109-116 次被
#     `agent_apply` **原样落地** ⇒ 下面那句"引擎自己不强制它"从此是量出来的，不是推的。
# C 守的是红线#2 的后半句，而【引擎自己不强制它】：Sim.gd:1185-1201 只做生存/视野否决，
#   一个凭空捏造的 intent 只要不违反生存否决就会被 agent_apply 原样落地。
#   ⇒ C 是一道**回归门**（守未来任何新后端 / `parse_decision` 的改写），**不是**"现有后端已被验过"的证书。
"$GODOT" --headless --path game res://bench/BackendGate.tscn -- \
  --seeds "${CI_BG_SEEDS:-1-4}" --days "${CI_BG_DAYS:-8}" --agents "${CI_BG_N:-12}" 2>&1 | tee "$LT_LOG/backendgate.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "BackendGate 外部后端门（硬不变量/两跑一致/闭集封闭）" || bad "BackendGate 外部后端门（硬不变量/两跑一致/闭集封闭）"
scan "BackendGate" "$LT_LOG/backendgate.log"

echo "### 4e. ModelPathGate 出货 prompt 编码门 (闭集编号字母表 / 示例编号 / 裁剪保序)"
# 为什么和 4d 分开：4d 守的是【落地之后】的世界（硬不变量 #01、两跑一致），
# 4e 守的是【问出去之前】那一份 prompt 的编码性质——docs/42 量到的三条病都活在这里：
#   ① 系统 prompt 里的字面示例编号把三成决策焊在一个候选位上；
#   ② 字符 '0' 的先验让模型从不选 0 号槽，而 index 0 有 74.84% 是吃饭/睡觉 ⇒ 系统性跳过维生动作；
#   ③ 裁剪路径若按 score 重排候选，会把引擎 argmax 顶到首位——那正是 docs/42 §9-4 判定
#      bench/log_decisions.gd 不可用于位置研究的同一个混淆，且它会悄悄抵消 ① ② 的修复。
# 允许 'Parse JSON failed'【恰好 1 次】：那是 A 段最后一条断言（prose fail-closed）故意喂 "A 去 eat"，
#   引擎在 JSON 兼容路上必打的一行（AIBackend.gd:886）。多一次 = 新的、没人解释过的错误；
#   少一次 = 那条负例断言已经不再跑到那条路上（门悄悄少了一条），两边都该红。
# C 段现在比对提交锚 game/bench/modelpath_anchor.json（此前它零条断言、只 print digest）。
#   锚移动了且是蓄意的 → --bake-anchor 重烘并在 _meta.rebake_history 里补一条原因（docs/41 §3）。
"$GODOT" --headless --path game res://bench/ModelPathGate.tscn -- \
  --seeds "${CI_MP_SEEDS:-1-4}" --days "${CI_MP_DAYS:-8}" --agents "${CI_MP_N:-12}" 2>&1 | tee "$LT_LOG/modelpath.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "ModelPathGate 模型路径编码门" || bad "ModelPathGate 模型路径编码门"
scan "ModelPathGate" "$LT_LOG/modelpath.log" 'Parse JSON failed' 1

echo "### 4f. VoiceGate 台词覆盖门 (每个被 offer 的候选动作都要有本人格的话可说)"
# 为什么需要它：F4 普查出 14 个动作在【任何】人格下都没有台词 = 111 对 (人格,动作) 让
#   _canned_say 返回空串，而当时没有任何一道门会响。更阴的是它不表现为沉默——
#   WorldView._set_dialogue 在 last_say 为空时回落到 DIALOG[type]，屏幕上照样有气泡，
#   只是 12 个人共用一套 12 行通用词。缺陷是【人格声音丢失】，不是哑巴。
# 口径取【被 offer 的候选】而不是【被选中的那一个】：台词只在动作被选中时上屏，
#   但候选一旦能被选中就可能上屏；只查被选中的那个，门的判别力会随机波动。
# 网格 1-3 x 60 天是量出来的：60 天才见得全 31 个可选动作，20 天的网格漏 3 个
#   （详见 game/bench/VoiceGate.gd 抬头的覆盖表与 docs/48 第七节）。
# 覆盖地板是【结构性】的，不是数量：阵容里出现过的每个人格都必须真的被枚举到过。
#   2026-07-30 外审（指令"尽力反驳"）判定原来那个 --min-pairs 250 是四条结论里最弱的一条：
#   250 与实测 293 之间没有理论依据（只是 85%），而且"数量不是语义"。
#   实测坐实了它的反例：让一个人格从此不被枚举，在 CI 这一格上仍有 271 对 > 250 ⇒ 旧地板放行；
#   结构判据当场变红并点名 [hai]。删掉一个岗位则阵容与枚举同时少掉 ⇒ 不假红。没有魔数。
# 它上线当天就考了一次真的：F5 新增 打渔/授课/劈柴 三个动作，门当场报出
#   dan|劈柴 hai|打渔 shu|授课 三对为空——写在这三个动作存在之前，仍然抓到了它们。
"$GODOT" --headless --path game --script res://bench/VoiceGate.gd -- \
  --seeds "${CI_VOICE_SEEDS:-1-3}" --days "${CI_VOICE_DAYS:-60}" 2>&1 | tee "$LT_LOG/voicegate.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "VoiceGate 台词覆盖门" || bad "VoiceGate 台词覆盖门"

echo "### 5. unit / integration scenes"
# player_touch_test：C3 的 31 条 + C8 的 13 条断言（触屏按钮路径 ≡ 按键路径、7 个动词可分辨、
#   观察台两档"卡片是详情的逐行前缀"）。它在 2026-07-26 Wave C 里写好后【一直没进 CI】——
#   docs/43 §1.2d 曾把它写成"已落地"，而 C8 查出这里的场景列表根本没有它。补上。
# goals_test：D2 的「小镇纪事」回放等价门 —— goto_tick 后从 event_log 重算的目标状态必须等于实时状态，
#   且挂上目标追踪前后 Inv.digest/event_digest 逐字节不动（= 它留在 View 侧的机器证明，docs/46 §二-D2）。
#   ★ tools/ci.sh 归 D1 独占，本行是【D2 声明过的越界】：只在下面这个场景名单里加一个词。
#     加它的理由就写在 docs/43 §1.2d 里 —— player_touch_test 写好后"一直没进 CI"，
#     一道没进 CI 的门不是门。冲突时直接取并集即可，回滚 = 删掉这一个词。
#   默认 12 seed × 14 天；本机约 2 分钟。CI_GOALS_SEEDS / CI_GOALS_DAYS 可调。
# story_test：E2 的「小镇故事」门（docs/47 §二-E2）。同样是 View 侧只读派生的回放等价断言，
#   但它的**牙齿不在 seed 循环里，在五组合成 fixture 上**——D2 已经实测「live==replay」和「至少 N 条」
#   两条判据都没有判别力（一个什么都不记 / 一个第一天全点亮的 tracker 都能满分）。
#   F1 只喂 greet → 故事必须 0 条；F2 手写因果链 → 必须给出指定的结局/幕次/旁支计数；
#   F3 冷场收场时刻必须等于"最后一幕+cold"（且 F3′ 反过来断言阈值之内不许判死）；F4 爽约/如约两支都要认。
#   另有两条账本自洽断言（进行中+终身收场==开过；grudge 开场数==conflict 事件数）守 MAX_CLOSED 裁剪。
#   ★ tools/ci.sh 归 D1 独占，本行是【E2 声明过的越界】：只在下面这个场景名单里再加一个词。
#     理由同 D2 那一行——一道没进 CI 的门不是门。冲突时取并集即可，回滚 = 删掉这一个词。
#   默认 12 seed × 14 天。CI_STORY_SEEDS / CI_STORY_DAYS 可调。
for scene in m2_test reqlife_test player_agency_test player_touch_test s4_replay_test space_test save_load_test goals_test story_test; do
  "$GODOT" --headless --path game "res://scenes/$scene.tscn" >"$LT_LOG/$scene.log" 2>&1
  code=$?
  if [ $code -eq 0 ]; then ok "$scene"; else tail -8 "$LT_LOG/$scene.log"; bad "$scene (exit $code)"; fi
  case "$scene" in
    # m2_test 是【负例测试】：故意把畸形 JSON 喂给 AIBackend.parse_decision 验证它拒收，
    # 引擎因此必打【恰好两行】"Parse JSON failed"（实测）。这是被断言的行为，不是回归 → 只对本场景、只放行这两条。
    m2_test) scan "$scene" "$LT_LOG/$scene.log" 'Parse JSON failed' 2 ;;
    *)       scan "$scene" "$LT_LOG/$scene.log" ;;
  esac
done

echo "### 6. 视觉门：昼夜 + 界外层重画 + 空间往返 + 岸线 + 室内外壳 + 家具语义（无渲染环境时自动 SKIP，不假红）"
# 为什么是这一条先进 CI：docs/41 §6 盲区④——`--shot` 曾经【永远渲不出昼夜】，
# 于是【这个项目所有视觉判断用的尺子】是坏的（"偏亮/偏暗"的结论全部不可信）。C3 用 Main.gd:271 一行修好了它，
# 而在此之前没有任何门守着那一行：把它删掉，上面 0-5 每一步都照样全绿。
#
# ⚠️ 它跟前面五步不一样：**需要一个能真的出图的渲染环境**（pin 死的 gamecraft-runner 镜像，或 Xvfb+godot）。
# ⚠️ 上一版这里写着"GitHub Actions 的 ubuntu-latest 两样都没有 ⇒ 自动 SKIP"——**那句是假的**，
# 且 `tools/visual_gate.sh` 抬头早已逐字撤回它，而这份文件没跟着改（同一波、同一个所有者、两处相反的说法，
# 2026-07-28 外部评审抓到）。事实：runner 镜像**自带 Xvfb**，workflow 又把 godot 放上 PATH，
# 所以 `have_native()` 在那里为真、`auto` 会选 native ——**靠"探不到就跳过"是拦不住的**。
# 真正让它在 GHA 上跳过的是 visual_gate.sh 里那条**显式** `$GITHUB_ACTIONS` 判断。
# 这是蓄意的：**一道在别人机器上因环境变红的门比没有门更坏**——它训练所有人忽略红色。
# 判据都在 tools/visual_gate.sh 抬头；想让它必须跑（例如宿主 CI）：`LT_VISUAL=require bash tools/ci.sh`。
#
# ── 这一步现在有【六】道门，一次 Xvfb 全跑完 ──────────────────────────────────
#   ① 昼夜量具（C3 那一行修复的守门人，assert_daynight.py）
#   ② 界外层重画门（D7 的 9× 帧时那条结构性性质，`--void-gate`）
#   ③ **空间往返像素门**（assert_space_roundtrip.py）——评审那句「没有人看过空间切换之后的任何一帧」。
#      ②③ 不是同一件事做两遍：② 数的是**重画次数**，③ 看的是**画出来的像素**。
#      实测负对照（把界外层改成"照常重画但什么都不画"）：**② PASS、③ FAIL** —— ② 结构上看不见它。
#      而同一棵坏树上 ① 也会红，但它的失败信息说的是"夜帧主色不对"，把人指向昼夜乘子——
#      ③ 的失败信息才指着真正坏掉的那条性质。**误导性的失败信息和假红一样坏。**
#   ④ 岸线判据（G5，tools/pond.py，吃 ① 已经拍好的两帧，不额外渲）
#   ⑤ **室内外壳类型门**（R2 / docs/69，assert_interior_shell.py）——"进屋之后这栋楼还得是这栋楼"。
#      ⚠️ 抬头原文写着"这一步现在有【三】道门"，而 ④ 早已落地没跟着改；R2 补这一笔时一并更正为五。
#      **同一份文件里两处相反的说法，这已经是第二次**（上一次是 GHA 那段，2026-07-28 外部评审抓到）。
#   ⑥ **家具语义分化门**（S3，assert_furniture_role.py）——"架子上摆的东西得是这间屋子会有的东西"。
#      与 ⑤ 不重叠：⑤ 只看**墙**（R2 的 does_not_detect 明写它连地板都不看），⑥ 只看**家具字形**。
#      同样吃 ⑤ 已经拍好的 vg_int_*.png，**不额外渲一帧**；为它增拍的 home2 / shop 两张
#      顺带给 ⑤ 各多了一对同类对子（两道门都变严了一点，没有一道被放松）。
bash tools/visual_gate.sh 2>&1 | tee "$LT_LOG/visual.log"
VRC="${PIPESTATUS[0]}"
case "$VRC" in
  0)  ok "视觉门（昼夜 / 界外层重画 / 空间往返 / 岸线 / 室内外壳 / 家具语义）" ;;
  77) echo "  ⏭  SKIP: 视觉门（本机没有渲染环境；LT_VISUAL=require 可让它变红）" ;;
  *)  bad "视觉门 (exit $VRC)" ;;
esac

echo
[ $FAIL -eq 0 ] && echo "=== CI PASS ✅ ===" || echo "=== CI FAIL ❌ ==="
exit $FAIL
