extends Node2D
## WorldView.gd — 纯订阅者像素渲染（不持有权威状态，全部读 Sim）。
## 范式同《小鱼岛》GameScreen：监听 Sim 信号 → queue_redraw；占位用程序化色块，M5 换正式像素美术。
## M1 增量：把「看不见的社交戏剧」画出来——关系连线 / 对话连线 / 冲突⚡ / 约见标记 / 台词气泡。

const T := 48  # 与 Art.TILE 一致
const EMOTE_TICKS := 24  # 头顶 emote 显示时长

# ── 整数像素尺（TEXTURE_FILTER_NEAREST 下的"不融化"前提）────────────────────────
# 地面/装饰一直是 T/16 = 3x 整数倍，可角色曾按 32→46(1.4375x)、物件 16→40(2.5x)、emote 20→26(1.3x) 画：
# nearest 采样下这些非整数倍让一部分源像素占 1 个屏幕像素、另一部分占 2 个 → 精灵在清晰的地形上读作"融化的"。
# 全部改成整数倍后，一个源像素恒等于 N 个屏幕像素。
const AGENT_PX := 64.0   # 32px 源帧 × 2
const EMOTE_PX := 40.0   # 20px 源帧 × 2
const OBJ_PX := 48.0     # 16px 源帧 × 3（= T，与地面/装饰同一个像素尺）
# 角色源帧 32x32 里人物实际占的行区间（用 alpha bbox 实测：y 5..24，x 9..23）。
# 用它把【脚】对齐落脚线、把【头顶】算出来给名字/emote 让位——不然放大后人会"浮"在影子上方。
const CHAR_FEET_ROW := 24.0
const CHAR_HEAD_ROW := 5.0

# ══ D6 · 收敛调色板 ═════════════════════════════════════════════════════════
# 改动前实测：`game/scripts/*.gd` 里 **156** 个不同的硬编码色值（不是 docs/44 §三 写的 134——
# 那条 grep 的口径是 `Color\("#hex"\)`，**要求 hex 后面紧跟 `")`**，于是漏掉了
# `Color("#hex", alpha)` 这个两参形式；实测有 15 个色值【只】以两参形式出现，其中 6 个正是 D3 的夜灯层）。
#
# 靶子是 game/assets/art/palette.gpl（40 色）+ docs/44。**但 40 不是要凑的数**：
# 那 40 色是外部评审在只看到约 30 个色值、且没看过室内地板/家具/表情 UI 的情况下提的，
# 硬把室内七种木色压成一个只会让室内变成一坨。下面是【授权色】+ 逐组合并理由；
# 位移量（dE00）逐条记在 docs/46 的 D6 回执里。
#
# P_* = palette.gpl 原样采用；X_* = 扩表（gpl 证明覆盖不到，每个带理由）；
# D_* = 从锚点算出的明暗档，**不是新的授权色**（换掉锚点，它们跟着走）。
# ★ 纪律：本文件里不许再出现新的 `Color("#...")` 字面量——要新色先往这张表里加并写理由。

# ── palette.gpl 原样（39 个）──
const P_RES_FACE     := Color("#c2a071")   # gpl res-wall-face
const P_RES_TOP      := Color("#d8bd93")   # gpl res-wall-top
const P_RES_FOOT     := Color("#836a48")   # gpl res-wall-foot
const P_RES_ROOF     := Color("#a8443a")   # gpl res-roof
const P_COM_FACE     := Color("#9a6c40")   # gpl com-wall-face（docs/44 §二 由 #8a6238 提亮）
const P_COM_TOP      := Color("#b98956")   # gpl com-wall-top（docs/44 §二 由 #a67f4e 提亮）
const P_COM_FOOT     := Color("#5a4028")   # gpl com-wall-foot（docs/44 §二 吸收 #5e4326）
const P_COM_ROOF     := Color("#b5484a")   # gpl com-roof
const P_PUB_FACE     := Color("#7c8a92")   # gpl pub-wall-face
const P_PUB_TOP      := Color("#a7b3ba")   # gpl grass-winter / pub 墙 top（docs/44 §二 吸收 #9fabb2）
const P_PUB_FOOT     := Color("#556169")   # gpl pub-wall-foot
const P_PUB_ROOF     := Color("#5a86b0")   # gpl pub-roof
const P_WRK_FACE     := Color("#82868f")   # gpl wrk-wall-face（**只剩室内用途**：浴池石沿。建筑外墙见 X_WRKW_*）
const P_WRK_TOP      := Color("#a0a4ac")   # gpl wrk-wall-top（同上，只剩井沿高光）
const P_WRK_FOOT     := Color("#585c64")   # gpl wrk-wall-foot（同上，只剩咖啡机顶盖/灶面）
const P_WRK_ROOF     := Color("#3f4b50")   # gpl wrk-roof（docs/44 §二 吸收 #3e4a5a）
const P_RES_FLOOR    := Color("#c8a273")   # gpl res-floor-base
const P_RES_LINE     := Color("#9c7748")   # gpl res-floor-line
const P_COM_FLOOR    := Color("#bf9257")   # gpl com-floor-base
const P_COM_LINE     := Color("#8c6533")   # gpl com-floor-line
const P_PUB_FLOOR    := Color("#96a5ab")   # gpl pub-floor-base
const P_PUB_LINE     := Color("#6c7b83")   # gpl pub-floor-line
const P_STONE        := Color("#9b968d")   # gpl stone-base
const P_STONE_LINE   := Color("#6d6a61")   # gpl stone-line
## ★ R2 删掉了 P_KERB（gpl road-kerb）：它唯一的使用点是室内石板地的亮格，而那格现在由
##   `FLOOR_PAL[typ].base.lightened(0.18)` 派生（澡堂/图书馆是冷灰、工坊是暖灰，改前两者共用这一个写死值）。
##   D6 的注释写着"此前代码零使用，本棒启用"——本棒把它用掉的那一处又拿走了，故一并删，不留零引用常量。
const P_PLAZA        := Color("#c3a97a")   # gpl plaza-base
const P_PLAZA_LINE   := Color("#9a8253")   # gpl plaza-line
# ── AP1 内容棒（编号140）：门→广场走廊【石铺连街】+ 广场 flagstone。纯 View（Sim 读 blockers，读不到绘制）＝零金标。
#   P_STREET 是一档【暖石板】：取在 P_STONE(#9b968d 冷暖灰) 与 P_PLAZA(#c3a97a 暖砂) 之间、略偏暖，
#   让门口的石街与中央广场读作【同一套铺装】而不是两种材质——这正是"连街"要的连续感。派生阶见下面 D_ 段。
## ★ AV3(161) 把它再往【暖灰鹅卵石】压一档：旧 #a89e8b 是【略偏暖的中性灰】（R−B=29），与 AV2 暖草/暖土同框时
##   仍读作"冷石"。新值 #a8916c（R−B=60，量自参考 STONE PAVEMENT 行的 hue G≈R·0.86 / B≈R·0.64）落进暖石族，
##   与广场/工坊石收敛成一整块暖铺装。P_STREET + 其全部派生（S_STREET_* / S_CURB）**只在户外石街绘制里用**
##   （grep 实证：66/68 定义、152-155 派生、3106/3118/3122 石街 draw、3131-3134 路缘——0 处室内/道具/门采样面）
##   ⇒ 改这一个常量【零室内爆炸半径】，也是本片唯一直接改的授权色常量。
const P_STREET       := Color("#a8916c")   # 暖灰鹅卵石路面（cobble base；AV3 由 #a89e8b 压暖）
const P_GRASS        := Color("#85a643")   # gpl grass-summer
const P_GRASS_AUT    := Color("#b59a4a")   # gpl grass-autumn
const P_FOLIAGE_D    := Color("#5f7b34")   # gpl foliage-deep
const P_FOLIAGE_M    := Color("#78933f")   # gpl foliage-mid
const P_WATER_LIT    := Color("#86b7c8")   # gpl water-lit
const P_WATER        := Color("#5a8ea6")   # gpl water-base
const P_WATER_DEEP   := Color("#365f73")   # gpl water-deep
const P_INT_COM      := Color("#4c463d")   # gpl int-wall-com
const P_INT_WRK      := Color("#484054")   # gpl int-wall-wrk
const P_TEXT         := Color("#e8e1d2")   # gpl ui-text（暖白：纸/布/奶油）
const P_PANEL        := Color("#22252a")   # gpl ui-panel（最深轮廓）
const P_NIGHT        := Color("#59627f")   # gpl night-multiply。现役两处：室内占位框描边(_draw_space_placeholder) + "quiet"房型地板(_mat_floor)。★旧注"启用为冷紫暗面"已过期——grep 实测从未做过夜间暗面罩(夜色由 Main._daylight 乘子 + 加色光层负责)，留此更正免得有人照旧注去找一个不存在的暗面层。

# ── 扩表（20 个，gpl 覆盖不到）──
## ★ E5 新增三个（X_WRKW_*）：**工坊建筑外墙**从 gpl 的 wrk-wall-* 里分出来。
##   起因是 docs/44 §二 自己点名的「夜间最容易糊」那一对，而 §四·五 的 D6 回执报的是另外两对（W2）。
##   E5 把量具补齐后实测（四昼夜档 × 四季 × 三天气，合成后再算）：
##     public↔workshop 墙 face **夜 0.99 / 全局最差 0.62**、foot **1.06 / 0.66**、top **2.20 / 1.56**
##     —— 三段【全部】在 JND(2.3) 以下，不是只有 §四·五 报的那两对。
##   机制是可以写清楚的：夜乘子 (0.4242,0.4714,0.7972) **最不压蓝**，所以差异**落在蓝通道上才活得过夜**。
##   而 gpl 里这两族的蓝通道只差 3/255（146 vs 143）——它们的区别全押在 R/G 上，正好是被压掉的那两个。
##   ⇒ 治法不是"再挑一个灰"，是**把工坊搬到暖灰石一族**（代码自己的注释就写着 public=灰蓝石 / workshop=灰石，
##     只是色值没兑现），这样差异天然落在 b* 上。三个值由 P_STONE 派生（不是新色相）：
##       face = P_STONE.darkened(0.26) / top = P_STONE.lightened(0.04) / foot = P_STONE.darkened(0.56)
##     （BLD_PAL 是 const 字典，不能引用 var 派生档 ⇒ 只能写成字面量；派生式写在这里，改 P_STONE 时照它重算。）
##   代价与收益逐项量过（见报告）：face↔pub 0.62→3.75、top↔pub 1.56→3.54、foot↔pub 0.66→3.98，
##   face↔工坊区地板 2.93→3.89，三段自身 face↔top 3.06→4.38、face↔foot 4.31→4.44。**没有一项退步。**
##   `P_WRK_ROOF`（深蓝黑顶）**原样不动**——它正是 docs/44 §二 自己开的那副药，动了就把药也拆了。
const X_WRKW_FACE    := Color("#736f68")   # 工坊外墙·主面 = P_STONE.darkened(0.26)
const X_WRKW_TOP     := Color("#9f9a92")   # 工坊外墙·顶棱 = P_STONE.lightened(0.04)
const X_WRKW_FOOT    := Color("#44423e")   # 工坊外墙·墙脚 = P_STONE.darkened(0.56)
const X_WOOD_MID     := Color("#6e4d31")   # 木器中段。gpl 的棕阶从 com-wall-foot(L30) 直跳 res-wall-foot(L47)，而全镇的门/家具体/柱/树干都落在这个空档里
const X_VOID_BASE    := Color("#0b1209")   # 界外深林底 —— 必须逐字节等于 project.godot 的 default_clear_color（该文件不在本棒独占集内，改不了）
const X_VOID_SPILL   := Color("#8fb36a")   # 镇子漏进林子的光。gpl 没有「溢光」这一档
const X_CANOPY_A     := Color("#16301a")   # 界外林冠三档之一（C1/C7 出货的是森林，docs/44 §四写的是灰色布景，实物为准）
const X_CANOPY_B     := Color("#1e3d22")   # 同上
const X_CANOPY_C     := Color("#0f2413")   # 同上
const X_LIGHT_WIN    := Color("#ff9a30")   # D3 加色光层·窗。色值由算术推出（R>1.111G 且 G>1.691B 才能活过夜蓝乘子）
const X_LIGHT_LAMP   := Color("#ff8418")   # D3 加色光层·火。同上，更橙
const X_GLOW_DEEP    := Color("#ffbe63")   # 室内/建筑底光。全家族里唯一 G/B 余量≥1.9 的，乘暗后才咬得住暖调（D3 实测）
const X_GLOW         := Color("#ffd27a")   # 光池/点亮的玻璃/灯笼描边
const X_GOLD         := Color("#ffd166")   # 金色强调（门把/传送锚/约见标记/灶台火苗心/灯笼流苏）。**定点**：Main.gd:518 在用，而 Main.gd 不在本棒独占集内
## ★ 玩家金环【不能】并进 X_GOLD —— 这条是 R10 全帧眼验在 1.8× 夜景特写里抓到的，纸面上看不出来：
##   夜乘子 (0.4242,0.4714,0.7972) **最不压蓝**。`#ffd700` 的 B=0，乘完还是 0 ⇒ 夜里 (108,101,0)，彩度 108；
##   `#ffd166` 的 B=102 被乘成 81 ⇒ 夜里 (108,99,81)，彩度 **27**。**同一个"金"，夜里差 4 倍彩度。**
##   合并的纸面代价只有 dE00 8.0（白天量的），而实际代价是"缺口#4 的玩家标记在夜里退成一圈米色"。
##   ⇒ 全表里唯一一个 B=0 的色值，留着，理由就是这条通道。
const X_PLAYER_GOLD  := Color("#ffd700")   # 玩家地面金环（见上）
const X_PARCHMENT    := Color("#f2dca8")   # 淡暖字/淡暖边（招牌字、房型标签、室内暖边）
const X_COLD_WHITE   := Color("#eaf3f8")   # 蒸汽/瓷/枕头。gpl 最亮的一档只有暖白 ui-text，冷白是真缺口
const X_SIGNAL_POS   := Color("#7ed957")   # 好感正。**不采纳 gpl 的 grass-spring**：它与线所压着的 grass-summer 只差 dE00 6.3 —— 那条线会消失在草地里（见报告）
const X_SIGNAL_NEG   := Color("#e85a5a")   # 好感负/冲突/灯笼/红指示灯/被子。**不采纳 gpl 的 com-roof**：那会让关系负线与每一片商业屋顶同色（D3 已记过这条撞色）
const X_PACT         := Color("#39d4c8")   # 互助盟约双线。青色信号，gpl 无对应（water-lit 会与水撞）
## ★ H3 · 「没有槽位认领这一格」的警示品红。**它是全表里唯一一个【蓄意不属于本作调色板】的色值**——
##   理由正好与上面每一条相反：其余色值都要求"融进画面"，这一个要求"永远不可能被误读成美术"。
##   由来：F1 的四个工位以占位框出货了一整波，而那个占位框用的是 P_RES_FOOT（暖石灰，和墙同色）
##   ⇒ 它在 2560×1536 的整帧里读起来像一件家具，八根棒和一次合并验证都没看见（F5 cd55df6）。
##   实测（本文件全部 60 个 P_/X_ 常量逐个算 dE00）：品红的最近邻是 **P_PUB_FLOOR #96a5ab，dE00 = 16.8**，
##   其后 P_PUB_FACE 19.2 / P_PUB_LINE 20.6 —— 全表没有一个色值落进"可能被看成同一个东西"的区间。
##   ⚠️ 我第一次写的是"最近邻 X_SIGNAL_NEG ≈ 47"，那是**猜的**；算完才发现连最近的是哪一族都猜错了。
const X_MISSING      := Color("#ff00ff")

# ── 派生明暗档（12 个；const 不能带方法调用，故用 var —— 只在实例化时算一次）──
var D_WOOD_LINE      := X_WOOD_MID.darkened(0.45)    # 木器描边/门框/门缝/搁板线 —— 木家族自己的最暗档；映到 ui-panel 会让它变冷（dE00 14.8），那正是「室内变一坨」
## ★ R2 删掉了 D_INT_WALL_TOP / D_INT_WALL_FOOT：室内墙不再写死住宅色，两条派生式搬进 `_interior_shell()`
##   （对住宅逐字节相同，其余三类各按自己的 BLD_PAL 派生）。留着会是两个零引用常量。
var D_FURN_HI        := P_COM_LINE.lightened(0.18)   # 木家具二级高光（桌/凳/条凳的上沿）
var D_POT            := P_COM_FACE.darkened(0.16)    # 陶罐底/花盆（0.10 时罐身↔罐底只剩 dE00 4.8，压到 0.16 拉回 7.5）
var D_STAIR          := P_PLAZA_LINE.darkened(0.22)  # 楼梯踏板
var D_STAIR_TOP      := P_PLAZA_LINE.lightened(0.10) # 楼梯踏面高光
var D_RUG_RED        := P_COM_ROOF.darkened(0.24)    # 地毯·暖红（卧房/默认）
var D_RUG_OLIVE      := P_PLAZA_LINE.darkened(0.30)  # 地毯·橄榄（茶座/咖啡）
## 地毯·青（浴/盥洗）。D6 原写 0.20，理由是「0.12 时地毯↔地板只剩 dE00 3.9（全表最窄），压到 0.20 拉回 6.5」。
## **那个 6.5 是白天、锚点对锚点量的。** E5 把它放进四昼夜档 × 四季 × 三天气再量：最差只剩 **2.10**
## （冬雨夜；出货气候的夜里也只有 2.96）——D6 那次调参解决的是白天，夜里它又滑回 JND 附近。
## 压到 0.38：最差 **4.01**，出货气候夜里 5.0+。这是 D6 那条「白天量的色差不能外推到夜里」在同一张表上的第二例。
var D_RUG_TEAL       := P_WATER_DEEP.darkened(0.38)
var D_BOOK_BLUE      := P_PUB_ROOF.darkened(0.28)    # 书脊·蓝（书架与书堆共用同一套三色）
## 室内取景的界外底。原值 #0e1017 直接并进 P_PANEL 会把它抬亮 dE00 6.3，而它铺满约 59% 的画面
## ——`_draw_interior_backdrop` 的整个设计（"镜头在屋外的暗处往里看"）就靠这块底比室内暗。
## 用 P_PANEL 派生一档（dE00 3.2）：既不新增授权色，又保住那层暗。
var D_BACKDROP       := P_PANEL.darkened(0.55)       # 室内取景的界外底
# ── AP1（编号140）石街派生阶（都从 P_STREET / P_PLAZA 派生，不新增授权色，红线#5 复用优先）───────
var S_STREET_HI      := P_STREET.lightened(0.12)     # 亮鹅卵石高光（受光的石面）
var S_STREET_LO      := P_STREET.darkened(0.14)      # 暗鹅卵石（阴影里的石块，做出铺面颗粒）
var S_STREET_SEAM    := P_STREET.darkened(0.34)      # 石缝（灌浆线）
var S_CURB           := P_STREET.darkened(0.46)      # 路缘石：街与草的交界，读作"这条街是砌出来的"
# ★ AV3(161) 删掉 S_PLAZA_HI / S_PLAZA_LO：AP1 那两档广场 flagstone 明暗面**唯一的消费者**（_draw_area_floors 铺装
#   分支 + 徽章 apron）本片已全部换到暖石族 G_PLAZA_HI / G_PLAZA_LO ⇒ 这两个变量成零引用，按仓库纪律不留（同 R2 删 P_KERB）。
var S_LAMP_POST      := X_WOOD_MID.darkened(0.30)    # 街灯灯柱（暗木/铸铁）
var S_BENCH_WOOD     := X_WOOD_MID                    # 长椅木条（复用镇上木家族中段）
var S_PLANTER        := P_STONE.darkened(0.10)       # 花坛石框
# ── AV3(161) 户外【暖灰鹅卵石】铺装族：把 AV2 之后仍冷的三块地面（广场 / 工坊石板 / 石街）收敛到同一族暖石，
#   照 ref_terrain 的 STONE PAVEMENT·PLAZA 行——那一整行【同一料】既做石铺又做广场。
#   ★关键克制：【不改】P_PLAZA / P_STONE 两个常量。它们除了户外地面还喂**室内**茶座地板(_mat_floor parlor)、
#     咖啡后厨地板(cafe)、市集货袋/藤篮(P_PLAZA 系)、建筑石基/井/广场徽章心(P_STONE 系)——动常量会把
#     FURNROLE / floor-roundtrip / cafe2f 的采样面一起挪走。故广场/工坊石的暖化在 `_draw_area_floors` 里【就地覆盖 base】，
#     只碰户外那一层像素，室内逐字节不动。石街走 P_STREET（已证路专用，见上）。
#   暖石 hue：G≈R·0.86 / B≈R·0.64（量自参考 (155,131,96)）。三档亮度：广场亮=社交焦点 / 石街中 / 工坊石略沉。
const G_PLAZA_WARM   := Color("#c0a682")   # 广场暖石铺装 base（比 P_PLAZA #c3a97a 略灰暖：G−B 47→36，退黄进灰，仍是全镇最亮地面）
const G_STONE_WARM   := Color("#a18a65")   # 工坊户外石板 base（原 P_STONE #9b968d 近中性灰 R−B=14 → 暖灰石 R−B=60）
var G_PLAZA_HI       := G_PLAZA_WARM.lightened(0.10)  # 广场大方砖·受光档
var G_PLAZA_LO       := G_PLAZA_WARM.darkened(0.10)   # 广场大方砖·背光档
var G_PLAZA_LINE     := G_PLAZA_WARM.darkened(0.30)   # 广场灌浆缝
var G_STONE_HI       := G_STONE_WARM.lightened(0.12)  # 工坊石·亮石
var G_STONE_LO       := G_STONE_WARM.darkened(0.14)   # 工坊石·暗石
var G_STONE_LINE     := G_STONE_WARM.darkened(0.34)   # 工坊石缝
# ══════════════════════════════════════════════════════════════════════════

# ── 画面 LOD / 裁剪（纯 DRAW 侧）────────────────────────────────────────────────
# ★红线：本节的一切【只决定画什么】，绝不回喂 Sim——不写 Sim.lod_focus、不改 Sim 任何字段。
#   机器门：game/bench/lod_verify.gd（tools/ci.sh 步骤 4b）拿 5 个不同 lod_focus 跑，digest 必须逐字节相同。
const LABEL_MIN_ZOOM := 0.45   # 低于此缩放：名字/气泡/emote/需求条一律不画（那时它们只是几像素糊斑，白烧填充率）
var _vis := Rect2()            # 本帧可见世界矩形（每帧 _draw 开头刷新）
var _zoom := 1.0               # 本帧 世界→屏幕 缩放

# ── D7 · 逐 pass draw-call 归因（默认全关；出货路径上 `_askip` 恒为 "" ⇒ 逐字节不变）────────
# docs/33 §7 的原话是这一节存在的全部理由：**「别推断瓶颈，埋计时器【测】」**——那一次凭直觉
# 连着判错三次单一瓶颈（sim-only → render-only → sim-only），直到真机 usec 分拆才看清。
# 真机 2026-07-28 又量到 FPS 11 / 绘制 4913，而派棒的假设（季节色调是逐格 pass）**是从 draw 数
# 反推出来的推断**。所以这一棒的第一件事不是改代码，是造一把尺子。
#
# 用法（世界必须冻结，否则 agent 相关 pass 的差值会被移动污染）：
#   godot --path game -- --speed 0 --warmup-tick 600 --draw-audit /out/audit.txt
# 机制：每一步把**恰好一个** pass 关掉重画一帧，读
#   `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`，与基线的差 = 该 pass 的 draw 数。
#   另测「全关」一档作**地板**（HUD + 引擎固定开销），基线−地板 = 世界层总量，
#   用它对逐 pass 差值求和做**闭合校验**（差值和 ≈ 世界层总量 ⇒ 归因没有漏项/重复计）。
const AUDIT_PASSES: Array[String] = [
	"backdrop", "grass", "water", "paths", "areafloor", "rooms", "walls",
	"facades", "dressing", "port", "arealabels", "decor", "trees", "towndoors",
	"landmarks", "objects", "climate", "factionrings", "pactlinks",
	"rellines", "talklinks", "agents", "rain", "snow", "lights",
	# backdrop 的子 pass（与 "backdrop" 重叠，故不进闭合校验；单独列出是为了知道该动哪一段）
	"bd:base", "bd:vergeramp", "bd:vergemotif", "bd:spill", "bd:canopy", "bd:vignette",
]
## 上面后 6 项是 "backdrop" 的**子集**，会被重复计入 ⇒ 闭合校验只对前 25 项求和。
## （AI1 编号129 加了 "snow" pass，23→24；AP-port 编号163 加了 "port" pass，24→25；
##   闭合校验实际用 `not begins_with("bd:")` 自动纳入，此常量仅存文档。）
const AUDIT_PRIMARY := 25
var _askip := ""               # 本帧要跳过的 pass 名（"" = 全开）
var _audit_path := ""          # --draw-audit <file>：非空即进入审计模式
var _audit_i := -2             # -2=预热 / -1=基线 / 0..n-1=逐 pass / n=全关地板
var _audit_phase := 0
var _audit_rows: Array = []
var _audit_zoom := 0.0         # >0：审计前把相机钉到这个缩放（扫 zoom 用）
var _audit_usec := 0           # 上一帧 _draw() 的 GDScript 墙钟（µs）。
                               # ★ draw-call 数只是【代理指标】。docs/33 §7 的教训正是"别拿代理当结论"：
                               #   一次 draw_circle 在 GDScript 侧要跑一趟循环 + 引擎侧要现场三角化，
                               #   两笔成本都不体现在"绘制"那个数字里。所以两个都量。

## 审计闸门（函数调用型 pass）。审计关闭时 `_askip == ""` ⇒ 恒 true ⇒ 调用点行为不变。
## `"*"` 是「全关」哨兵，用来量出 HUD + 引擎的固定地板。
func _ap(nm: String) -> bool:
	return _askip != nm and _askip != "*"

## 审计闸门（循环集合型 pass）：`for x in _ac("walls", _wall_set)`。
## 用它而不是把整个循环体缩进一层 `if` —— 零重排 ⇒ 这段插桩不可能顺手改到画面。
func _ac(nm: String, coll):
	return coll if (_askip != nm and _askip != "*") else []

const AUDIT_SETTLE := 12       # 每一步连画几帧再读表（第一帧的命令表可能还是上一步的）
const AUDIT_WARM := 4          # 前几帧不计入 µs 均值（缓存/纹理上传的一次性成本）
var _audit_uacc := 0
var _audit_un := 0

## 审计状态机。每步：设定 `_askip` → 连画 AUDIT_SETTLE 帧 → 读 draw 表 → 记一行 → 下一步。
func _audit_step() -> void:
	if _audit_i > AUDIT_PASSES.size():
		return
	if _audit_zoom > 0.0:
		# 把相机钉在指定缩放（dev 量具专用）。ProbeController.min_zoom() 是给手操作用的地板，
		# 这里绕开它 —— 扫 zoom 就是要看两端，含手操作到不了的那一端。相机只决定【画什么】，
		# 不回喂 Sim（lod_verify 的相机无关门不受影响）。
		var _m := get_parent()
		var _p = _m.get("_probe") if _m != null else null
		if _p != null and _p.cam != null:
			_p.cam.zoom = Vector2(_audit_zoom, _audit_zoom)
			_p.cam.position = Vector2(float(Sim.world.get("width", 24)) * T, float(Sim.world.get("height", 16)) * T) * 0.5
	if _audit_phase == 0:
		_askip = "" if _audit_i < 0 else ("*" if _audit_i == AUDIT_PASSES.size() else AUDIT_PASSES[_audit_i])
	_redraw_all()
	_audit_phase += 1
	if _audit_phase > AUDIT_WARM:
		_audit_uacc += _audit_usec; _audit_un += 1     # µs 单帧抖动 ±1.4ms，必须取均值才读得出小 pass
	if _audit_phase < AUDIT_SETTLE:
		return
	_audit_phase = 0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _audit_i >= -1:
		var nm := "BASELINE" if _audit_i < 0 else ("FLOOR_ALL_OFF" if _audit_i == AUDIT_PASSES.size() else AUDIT_PASSES[_audit_i])
		_audit_rows.append({"n": nm, "d": draws, "o": objs, "p": prims,
			"u": int(_audit_uacc / maxi(1, _audit_un))})
	_audit_uacc = 0; _audit_un = 0
	_audit_i += 1
	if _audit_i > AUDIT_PASSES.size():
		_audit_write()

func _audit_write() -> void:
	_askip = ""
	var base := int(_audit_rows[0]["d"])
	var floor_d := int(_audit_rows[_audit_rows.size() - 1]["d"])
	var lines: Array[String] = []
	lines.append("# D7 draw-call attribution · zoom=%.3f vis=%s season=%s weather=%s tick=%d N=%d" % [
		_zoom, str(_vis), Sim.season_today, Sim.weather_today, Sim.tick_no, Sim.agents.size()])
	var base_u := int(_audit_rows[0]["u"])
	lines.append("# baseline_total=%d  floor(all world passes off)=%d  world_layer=%d" % [base, floor_d, base - floor_d])
	lines.append("# baseline _draw() gdscript = %d us   floor = %d us" % [base_u, int(_audit_rows[_audit_rows.size() - 1]["u"])])
	lines.append("pass\tdraws_without\tdelta\tshare_of_world\tus_without\tus_delta")
	var sum_delta := 0
	for r in _audit_rows:
		var nm := String(r["n"])
		if nm == "BASELINE" or nm == "FLOOR_ALL_OFF":
			continue
		var d := base - int(r["d"])
		if not nm.begins_with("bd:"):
			sum_delta += d
		lines.append("%s\t%d\t%d\t%.1f%%\t%d\t%d" % [nm, int(r["d"]), d,
			100.0 * float(d) / maxf(1.0, float(base - floor_d)), int(r["u"]), base_u - int(r["u"])])
	lines.append("# sum_of_deltas(primary only)=%d  vs world_layer=%d  (closure check)" % [sum_delta, base - floor_d])
	var f := FileAccess.open(_audit_path, FileAccess.WRITE)
	for l in lines:
		print("[DRAWAUDIT] " + l)
		if f != null:
			f.store_line(l)
	if f != null:
		f.close()
	get_tree().quit()

# ── 世界层浮动文字的【按需显示】（docs/46 §三-D5 / 缺口 #5）────────────────────
# 病症（评审实测，跟随相机 zoom=1.8）：每个可见居民恒带 名牌 + 动作牌 + 需求条 + 派系环，
# 5 人 ≈ 20 块浮动物（本棒复量 seed3/t600：5 名牌 + 5 动作牌 + 5 需求条 + 4 派系环 = **19**，
# 可可 faction 为空所以少一个环），世界区里 1418 个近白字形像素。
# **而那 5 张动作牌当时写的是同一个词「吃饭」**——重复的同义标签信息量≈0，却占着最抢眼的一层。
#
# 这里**不删功能**，只把它分成两条可达路径（"该看见时看得见"才是判据，不是像素数变小）：
#   ① 焦点集（_is_focus）：选中者 / 玩家 / 冲突或约会当事人 / 正在社交事务里的双方 / 正在说话的人
#      —— 任何缩放档下【恒显】名牌与动作牌，与改动前完全一致。
#   ② 其余人：随缩放淡入。zoom≤LABEL_FADE_LO 全隐，≥LABEL_FADE_HI 与改动前完全一致，中间线性。
#      两个阈值都在 ProbeController.ZOOM_MAX(3.0) 之内，且 focus 档 1.8 按 `+` 两下即 2.38 ⇒ 可达。
# 需求条同理改成【危机才出现】：阈值 35 直接取自它原本的红/绿分界 —— 即"它本来要变红的那一刻才出现"，
# 没有引入任何新语义。实测（seed 3）：绿条 427/595 px → 0，而 t=660 那条**红**条 211 px → 211 px 逐字节不动。
#
# ★ 本改动是**纯闸门**，有机器证据：把这两个常量压成 0.40/0.45（即 detail 恒为 1）之后，
#   4 个场景（含 --player 与一个社交/危机帧）渲出的 PNG 与**未改动的树 SHA256 完全相同**。
#   ⇒ "把浮动文字压下去"这件事没有删掉任何一个字，只是给它们加了条件。
const LABEL_FADE_LO := 2.00    # ≤ 此缩放：非焦点者不画名牌/动作牌（跟随相机 1.8 落在这一侧 ⇒ 干净）
const LABEL_FADE_HI := 2.60    # ≥ 此缩放：非焦点者全量恢复（贴脸细查档 ⇒ 一个字都没丢）
const NEED_CRISIS := 35.0      # 与 _draw_urgent_need 里原有的红/绿分界同一个数，不是新阈值
var _rc_social_ids := {}       # 每帧预建：正在一次社交事务里的双方（actor + partner）
var _rc_sel_id := ""           # 每帧预建：当前选中者（_selected_id() 要走 get_parent().get()，别在 per-agent 循环里调 N 次）

# ── 关系连线（S1 起最贵也最乱的一层）──────────────────────────────────────────
enum RelMode { ALL, SELECTED, OFF }
const REL_TOP_K := 3           # 每人只保留最强的 K 条（一条边在任一端的 top-K 里就留 → 强关系不会被单侧挤掉）
const REL_MIN_AFF := 20.0
const REL_FADE_PX := 520.0     # 屏幕长度超过它开始变淡：横穿全镇的长线信息密度最低，却最挡视线
## ★ E5/W4 · 关系线的 alpha **下限**。
## 原式 `(0.26 + t*0.52) * fade * focus` 有三个可以同时取到下界的因子：
##   t=0（affinity 刚过 REL_MIN_AFF）× fade=0.25（横穿全镇的长线）× focus=0.55（不是选中者的线）
##   ⇒ **a = 0.26 × 0.25 × 0.55 = 0.0358**。
## 把这一档按【真实合成】量出来（sRGB 混色 → 大气罩 → 昼夜乘子；合成律见报告的标定一节）：
##   压在草地上 ΔE00 **0.27-0.54**、土路 1.02-1.27、广场 0.78-1.97 —— **全部远低于 JND 2.3**。
## 也就是说这条线**被画了出来、占了 draw call、却一个人也看不见**。评审报的 "0.52-1.29" 正是这一档
## （不是"关系线普遍看不见"：同一条线在典型档 a=0.468 上是 4.48-6.50）。
## 解法不是取消衰减（衰减本身有理由：长线信息密度最低），而是给它一个**能被看见的地板**：
##   实测 a=0.36 时最弱一档回到 **2.68**（正向绿压在春草上、夜、这是全表最难的一格），
##   a=0.30 只有 2.24 —— 还差一点。取 0.36。
## 负向红在 a=0.12 就过 JND；地板由**正向绿压在草上**这一格决定，因为它天生是"绿画在绿上"。
const REL_A_FLOOR := 0.36
var rel_mode: int = RelMode.ALL   # Main 可直接改这个属性（本 baton 不动 Main，故不加键位）

var _prev_pos := {}      # id -> Vector2i（推断朝向/行走）

# ── 居民插值（渲染时钟，不是 tick 时钟）────────────────────────────────────────
# Sim 的位置是【格】，而 tick_interval=0.08 ⇒ 居民每秒瞬移 12.5 次、每次整整 T=48 像素。
# 这里在 View 内维护一份【渲染坐标】，在 _process(delta) 里向格心 lerp；Sim 一个字节都不碰。
# ★红线（本文件 :22）：_render_pos 只喂【绘制】。所有裁剪/LOD 判定一律仍按 Sim 的精确格心 _center()
#   算——否则"画什么"就会依赖上一帧的渲染残余，观察无关性从纯函数退化成有状态的。
# ★冻结 tick 的 --shot 必须与未插值版逐字节相同（docs/43 C1 验收）：靠 SNAP_PX 硬吸附保证，
#   不靠"指数收敛到浮点精度以下"这种概率性论证。
const LERP_FRACTION := 0.60    # 在一格【实际耗时】的 60% 内走完 → 跟得上 x8 加速，也不拖影
const SNAP_PX := 0.05          # 收敛阈值：小于它直接吸附到精确格心
const TELEPORT_TILES := 3.0    # 超过它视为瞬移（换 Space / 时间轴跳转 / 读档 / 换 N）→ 直接吸附，不横穿全镇滑行
var _render_pos := {}          # id -> Vector2（纯渲染坐标）
var _moving := {}              # id -> bool（是否仍在追格心；行走帧靠它）
var _walk_row := {}            # id -> int（行走帧行号，进入移动时锁定）
var _emote := {}         # id -> {tex, until}
var _say := {}           # id -> {text, until}（对话罐头台词；M2 换 LLM 生成）
const SAY_TICKS := 40

# L6 调色板变体（docs/12）：扩 N 的克隆(id=npc_*)复用 6 张 CC0 精灵，用确定性色相旋转让每个各不相同
# → 视觉数量线性增长、零新增 PNG、零版权、完全可复现。命名 6 人(aria..fei)零位移保留正典外观；6 人小镇本层休眠。
# 实现：首次用到时把精灵 CPU 色相旋转成一张 ImageTexture 变体并缓存（Godot 4 immediate-mode 无法 per-draw 换 material）。
const HUE_BUCKETS := 24   # 色相分桶数（bucket0=原图）
var _hued := {}          # "sprite#bucket" -> ImageTexture（懒建缓存）

## 实际被采样的表区域：_agent_frame 只取 col 0-3 / row 0-3（idle+行走三向），即左上角 128x128。
## 整张表是 768x256 = 196,608 像素，而用到的只有 16,384——旧实现每建一个色相变体都要 GDScript 逐像素扫全表
## （12x 空转 + 每变体多留 ~720 KB），且变体是扩 N 时【边玩边建】的，卡顿正好落在最需要帧时间的时候。
## 裁到用到的区域即可：变体纹理与原图共用左上角坐标系，src Rect2(col*32,row*32,32,32) 两边通用，取帧代码一行不用改。
const CHAR_USED := Vector2i(128, 128)

## 克隆按 id 取确定性色相变体；命名原型(非 npc_)或 bucket0 直接返回原图。绕 HSV 色相环旋转→保亮度=真换色，非压暗 modulate。
func _hued_tex(spr_name: String, id: String) -> Texture2D:
	var base := Art.agent_tex(spr_name)
	if base == null or not id.begins_with("npc_"):
		return base
	var bucket := absi(id.hash()) % HUE_BUCKETS
	if bucket == 0:
		return base
	return _hue_variant(spr_name, base, bucket)

## 色相变体的实现体（原本内联在 `_hued_tex` 里）。抽出来是为了让「空 sprite 回退」也能复用同一份
## 缓存与同一套像素处理——两份实现必然漂移。NPC 那条路的行为逐字节不变（同样的 key、同样的 shift）。
func _hue_variant(spr_name: String, base: Texture2D, bucket: int) -> Texture2D:
	var key := spr_name + "#" + str(bucket)
	if _hued.has(key):
		return _hued[key]
	var img := base.get_image()
	if img == null:
		return base
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	var rw := mini(CHAR_USED.x, img.get_width())
	var rh := mini(CHAR_USED.y, img.get_height())
	img = img.get_region(Rect2i(0, 0, rw, rh))     # 只留被采样的左上角帧区（12x 少扫、~12x 少留内存）
	var shift := float(bucket) / float(HUE_BUCKETS)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.02:
				continue
			c.h = fmod(c.h + shift, 1.0)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_hued[key] = t
	return t

## ── 「空 sprite」的体面回退（docs/46 §二-D3-3）───────────────────────────────
## `Sim.add_player()` 给玩家 `persona.sprite = ""`（Sim.gd:752），`Art.agent_tex("")` 返回 null，
## 于是 `_draw_agent` 掉进 `draw_circle` 分支——**玩家是全镇唯一一个圆盘**，
## 而周围 12 个居民都是像素小人。本棒不许改 `Sim.gd`，所以回退做在 View 层。
##
## 选 `Character-Base` 不是随手挑的：它是素材包里**唯一没有职业道具**的一张
## （其余是法师/弓箭手/战士/士兵），正对 docs/44 §一 裁决的"现代日常小镇居民"方向；
## 它已经在 personas.json 里被阿梅用着 ⇒ 零新增资源、零版权面（红线#4）。
const FALLBACK_SPRITE := "Character-Base"
## `Character-Base` 帧 (0,0) 的主色 (246,169,84) 的 HSV 色相 = 31.5°/360。
## 回退用的色相桶不是 hash 出来的，而是**把这张基础皮转到 persona.color 的色相上**——
## 玩家的 persona.color 是 `#ffd700`(h=0.1405) ⇒ 桶 1（+15°）⇒ 小人本身就是金色的，
## 与保留下来的金环同调；而阿梅（原图，桶 0）与玩家不会撞脸。
const FALLBACK_BASE_HUE := 0.0875

func _fallback_tex(ag: Dictionary) -> Texture2D:
	var base := Art.agent_tex(FALLBACK_SPRITE)
	if base == null:
		return null                                    # 连回退皮都缺 → 让调用方继续走圆盘兜底
	var col := Color(str(ag.get("persona", {}).get("color", "#ffffff")))
	var bucket := int(round(fposmod(col.h - FALLBACK_BASE_HUE, 1.0) * float(HUE_BUCKETS))) % HUE_BUCKETS
	if bucket == 0:
		return base
	return _hue_variant(FALLBACK_SPRITE, base, bucket)

# 罐头对话库（发起方 init / 接受方 yes / 拒绝方 no）；M2 由 LLM 按人设生成替换
const DIALOG := {
	"greet": {"init": ["嘿，最近怎么样？", "今天天气真好呀！", "好久不见！"], "yes": ["挺好的，你呢？", "正想找你聊聊～"], "no": ["现在有点忙…", "下次再聊吧。"]},
	"gossip": {"init": ["偷偷跟你说个事儿……", "你听说了吗？", "我跟你讲哦……"], "yes": ["真的假的？！", "快说快说～"], "no": ["这种话我不爱听。", "算了吧。"]},
	"give": {"init": ["这个送你～", "一点小心意，收下。"], "yes": ["谢谢你！", "太客气啦～"], "no": ["这我不能要…", "心领了。"]},
	"invite": {"init": ["回头一起去广场？", "改天约一个？"], "yes": ["好呀，说定了！", "行，到时见！"], "no": ["最近没空…", "下次吧。"]},
	"confront": {"init": ["咱们得谈谈。", "你这样让我很难受。"], "yes": ["……你说得对。", "我听着呢。"], "no": ["我不知道你在说什么。", "这跟我没关系。"]},
	"apologize": {"init": ["对不起，是我不好。", "上次的事，我道歉。"], "yes": ["……没事了。", "我原谅你。"], "no": ["我还没法释怀。", "给我点时间。"]},
	"meet": {"init": ["你来啦！", "等你好久～"], "yes": ["来咯～", "走，一起！"], "no": [], "fail": ["怎么没来呢…", "白等一场。"]},
	# S3 社交深化
	"confide": {"init": ["有件事…我只告诉你", "我心里藏着个秘密…"], "yes": ["我替你保密。", "尽管说，我听着～"], "no": []},
	"leak": {"init": ["其实啊，ta 跟我说过……", "偷偷告诉你个秘密哦……"], "yes": ["不会吧？！", "快讲快讲～"], "no": []},
	"betray": {"init": ["（一时口快说漏了嘴…）"], "yes": ["你怎么能这样！我信错人了！", "你竟把我的秘密说出去！"], "no": []},
	"endorse": {"init": ["ta 那种人，咱们看在眼里", "这事咱们口径一致"], "yes": ["没错，我也这么想。", "算我一个。"], "no": []},
	"rally_oust": {"init": ["大家都对你有意见！", "我们不欢迎这样的人。"], "yes": ["凭什么针对我…", "你们……"], "no": ["凭什么针对我…"]},
	"aid": {"init": ["别担心，有我呢～", "来，我帮你！"], "yes": ["太谢谢你了！", "有你真好。"], "no": []},
	"pact": {"init": ["以后咱们互相帮衬！", "结个伴吧～"], "yes": ["一言为定！", "好，说定了！"], "no": ["你总只索取，这盟约到头了。"]},
}

# 视觉大改：地面分层 + 装饰散布（切图前自动回退）
var _grass: Array = []   # 草地变体纹理（带权）
var _grass_var := PackedByteArray()   # 每格的草地变体下标（_build_grass_var 一次性烘；合批用）
var _decor_items: Array = []  # [{tex, cell:Vector2i, k:池内下标}]（I2：原注释里的 h_tiles 是死字段，已随 tree* 分支一起删）
var _decor_built := false
# P2-2 地形层：map.json 的 walls/water/trees（纯渲染；导航走 blockers 并集，与此无关）。start_new 时重建。
var _path_set := {}      # idx(y*W+x) -> true（土路格：广场↔各家门口；渲染 + 装饰避让）
var _plaza_cells := {}   # AP1(140) idx -> true（所有 type=="plaza" 区的格：石街铺面与 verge 街具用它判"已铺装"）
var _paths_built := false
# AP1(140) 纯 View 街具（路灯/花坛/长椅/矮柱），落在 verge（路/广场旁的 free cell）。程序化画、Sim 永不感知。
# 由 `_build_decor` 一并烘（共用 `_decor_built`，不新增缓存标志 ⇒ cache-gate/W6 作废逻辑一字不动）。
var _street_prop_items: Array = []   # [{cell:Vector2i, kind:int}]，行优先排序（逐字节可复现）
var _street_prop_cells := {}         # idx -> true（散花草时避开这些格，别把花画在灯柱脚下）
var _wall_set := {}      # idx(y*W+x) -> true（墙格，用于画石墙 + 装饰避让）
var _water_set := {}     # idx -> true（水格）
## 水格按【岸线瓦片】分组：[[瓦片名, PackedInt32Array(格子下标)], ...]，9 个 slot。
## 在 `_build_terrain` 里一次算好 —— 四邻查询是**只跟地图有关**的纯函数，不该每帧重算，
## 更不该进 `_draw`（那是 D7 反复清理过的地方）。跟着 `_terrain_built` 一起失效。
var _water_by_slot: Array = []
var _tree_cells: Array = []  # [Vector2i]（authored 阻挡树，替代程序化装饰树）
var _tree_draw: Array = []   # V3 林相：[{cell,off,tone}]，行优先排好序（_build_tree_styles 一次性烘）
var _tree_set := {}      # idx(y*W+x) -> true（同上，供 O(1) 查：_is_blocked 与界外 motif 每帧都要问它）
var _wall_type := {}     # P2-4 idx -> 建筑类型（住宅/商业/公共/工坊）→ 墙面按类型上色
var _terrain_built := false
var dbg_nav := false     # P2-4 导航开发叠层开关（Main 的 N 键切换）：阻挡格 + 交互格可视化
var _interiors := {}     # P3 室内内容 interiors.json：space -> floor -> {label,floor,furniture[]}
var _interiors_loaded := false
# P2-4 分类型建筑外观：墙面(face/top/foot 三段做体积)+屋檐(roof)+招牌图标，让"住宅/商业/公共/工坊"一眼可辨。
## ★ D6：`icon` 只有 commercial（遮阳篷条纹）与 public（♨蒸汽）两处被读；
##   residential 的 `#c85a4e` 与 workshop 的 `#cfcfcf` **全仓零读取**（`_draw_sign` 的这两个分支
##   分别走 `pal["roof"]` 与字面量），已删。
## ★ commercial 的 face/top 换成 palette.gpl 的**提亮值**（docs/44 §二「提亮两个」：
##   #8A6238→#9A6C40、#A67F4E→#B98956，理由是原色夜里与室内木墙糊成一块）。
##   同样的 #8a6238/#a67f4e 在家具上是另一个角色（木器高光），走 P_COM_LINE / D_FURN_HI，不跟着提亮。
const BLD_PAL := {
	"residential": {"face": P_RES_FACE, "top": P_RES_TOP, "foot": P_RES_FOOT, "roof": P_RES_ROOF},                    # 暖木墙+红瓦顶
	"commercial":  {"face": P_COM_FACE, "top": P_COM_TOP, "foot": P_COM_FOOT, "roof": P_COM_ROOF, "icon": P_TEXT},    # 棕木店面+红白条纹遮阳+咖啡招牌
	"public":      {"face": P_PUB_FACE, "top": P_PUB_TOP, "foot": P_PUB_FOOT, "roof": P_PUB_ROOF, "icon": X_COLD_WHITE},  # 灰蓝石+蓝瓦+♨蒸汽
	"workshop":    {"face": X_WRKW_FACE, "top": X_WRKW_TOP, "foot": X_WRKW_FOOT, "roof": P_WRK_ROOF},                # 暖灰石+深蓝灰顶+烟囱黑烟（E5/W2：见 X_WRKW_* 的推导）
}
## 分类型【地板】：与 BLD_PAL 的墙色同族但更亮（屋顶被切掉，地面才是受光面）。
## 旧版只有广场有真地板，其余七个区只压一层 0.10 alpha 的淡色罩 —— 于是每栋建筑读作"围了圈墙的草坪院子"，
## 床和灶台直接摆在草上。这是整镇"灰盒原型感"的头号来源，而它整个在 View 层。
const FLOOR_PAL := {
	"residential": {"base": P_RES_FLOOR, "line": P_RES_LINE, "mode": "plank"},   # 暖木地板
	"commercial":  {"base": P_COM_FLOOR, "line": P_COM_LINE, "mode": "plank"},   # 深一档的店面木地板
	"public":      {"base": P_PUB_FLOOR, "line": P_PUB_LINE, "mode": "slab"},    # 冷灰石板（澡堂/图书馆）
	"workshop":    {"base": P_STONE, "line": P_STONE_LINE, "mode": "slab"},    # 暖灰石板（工坊）
	"plaza":       {"base": P_PLAZA, "line": P_PLAZA_LINE, "mode": "paving"},  # 中央广场铺装
}

# ── 四季与天气（Wave C）──────────────────────────────────────────────────────
# Sim.season_today / Sim.weather_today 每天边界都在算并进效用乘子（Sim.gd:1076-1078、:2305、:2322），
# 而本文件里这两个词此前【零命中】—— 也就是说仿真里换了季，屏幕上逐像素相同。
# 这里只【读】它们，纯 View：veg = 植被（草地/花草/树）的乘算色偏；wash = 压在地形与建筑之上、
# 居民之下的大气罩（乘算做不出"冬天发白"，必须靠叠加）。缺数据文件时两者都是恒等，画面回到今天。
const SEASON_VEG := {
	"春": Color(1.00, 1.06, 0.90),   # 新绿，略偏黄
	## ★ 深浓：旧值 (0.88,1.00,0.72) 只把基草压 12%/0%/28%，实测（seed3 晴天真帧、草地众数色）
	##   与【春】仅 ΔE00 2.71(昼) / 2.40(夜) —— 卡在 JND(≈2.3)，两个绿季眼验里糊成一块（旧注写"深浓"但值没兑现）。
	##   压到真正的浓绿：R−28% / G−10% / B−42%，众数色离春 ΔE00≈7，与其余各季对（8–23）拉齐；autumn/winter 本就分得开，不动。
	##   只动【夏】= 游戏日 15-29，而所有 CI 视觉帧都在【春·游戏日 3】(seed3 tick 488/600) ⇒ 昼夜门等一帧不碰、逐字节不变。
	##   ★ AV2（Lane V，2026-08-08）：暖色生成瓦替换 grass_a 后，渲染出的春帧地面主色由 (134,179,63)
	##   变暖变深到 (114,140,33)，把【夜】春↔夏 ΔE00 从 4.30 压到 2.73 < 3.20（昼 7.49 仍宽）。summer 是
	##   AV2 派单唯一允许的 WorldView 改动：把【夏】从 (0.72,0.90,0.58) 再压深到 (0.60,0.82,0.46)，
	##   夜春↔夏实测回到 4.28 ≥ 3.20（恢复 ~1.34× 余量；标定/前后数见 docs/159）。春/秋/冬 veg 不动
	##   ⇒ 昼夜门的春帧只受【瓦本身变暖】影响（已重量：DAYNIGHT/POND/TREESTAND 全 PASS），夏改动不碰它。
	"夏": Color(0.60, 0.82, 0.46),   # 深浓（AV2 因暖色基草再压一档；别按"看着太深"改回去，会让夜春↔夏退回 JND）
	"秋": Color(1.22, 0.98, 0.60),   # 金黄（第一版 1.32/0.52 眼验偏芥末，压了一档）
	"冬": Color(0.84, 0.92, 1.00),   # 冷、褪色
}
const SEASON_WASH := {
	"春": Color(0.62, 0.90, 0.48, 0.05),
	"夏": Color(1.00, 0.90, 0.42, 0.06),
	"秋": Color(0.95, 0.58, 0.22, 0.10),
	"冬": Color(0.80, 0.89, 1.00, 0.24),   # 霜白：多亏了它，冬天才不是"绿得冷一点"
}
const WEATHER_WASH := {
	"阴": Color(0.52, 0.57, 0.64, 0.16),
	"雨": Color(0.34, 0.45, 0.62, 0.24),
}

func _season_veg() -> Color:
	return SEASON_VEG.get(Sim.season_today, Color.WHITE)

## 季节 + 天气的大气罩，画在地形/建筑之上、居民之下。只覆盖【地图矩形 ∩ 视口】——
## 界外暗林不跟着变季，否则夜林会被冬天的霜白刷成灰板。
func _draw_climate_wash(w: int, h: int) -> void:
	var area := Rect2(0.0, 0.0, float(w) * T, float(h) * T).intersection(_vis)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var sw: Color = SEASON_WASH.get(Sim.season_today, Color(0, 0, 0, 0))
	if sw.a > 0.0:
		draw_rect(area, sw, true)
	var ww: Color = WEATHER_WASH.get(Sim.weather_today, Color(0, 0, 0, 0))
	if ww.a > 0.0:
		draw_rect(area, ww, true)

## 降水层铺设范围：【地图矩形 ∩ 视口】——与 _draw_climate_wash 同一条界（界外暗林不下雨/雪）。
## ★ 为什么要 clip：全镇取景（--shot-fit 或 go_home zoom≈0.229）下 _vis 远大于地图（含界外背板），
##   直接按 _vis 铺格会冲上 5000+ 格 → VOID_DECOR_MAX_CELLS 守卫触发、整层不画（编号129 实测：
##   冬雪在展开后的镇上 shot-fit 得 97×60=5820 格 > 4096 ⇒ 被吞）。夹到地图后 64×48 图恒 ≤ ~2000 格，
##   既保住红线#3 手机填充率上限，又让降水在全镇视角也画得出来。返回的 gx/gy 是【夹后】格坐标。
func _precip_area() -> Rect2:
	var w := float(Sim.world.get("width", 0)); var h := float(Sim.world.get("height", 0))
	return Rect2(0.0, 0.0, w * T, h * T).intersection(_vis)

## 雨丝 + 地面涟漪。确定性：位置来自 _hash(gx,gy,salt)，下落/眨相位来自 Sim.tick_no —— 不抽 RNG、不读墙钟，
## 于是【同一 tick 重拍逐像素相同】（--shot 冻结 tick，precip 门靠这条可比性做 on/off 负对照）。
## ★ AI1 强化（编号129）：旧版只有 36% 密度、单档 1.5px 短丝，量出来偏弱（before 帧眼验偏淡）。
##   现在 = 两档景深雨丝（近：亮/长/粗；远：淡/短/细，52% 密度）+ 独立散布的地面涟漪（扩大环，按 tick 眨）。
##   只在 `weather=="雨" 且非冬` 时调用（冬季降水走 _draw_snow，见调度处）——不新增仿真态、不改 weather.json。
func _draw_rain() -> void:
	var area := _precip_area()
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var cell := T * 1.5
	var gx0 := int(floor(area.position.x / cell)); var gx1 := int(ceil(area.end.x / cell))
	var gy0 := int(floor(area.position.y / cell)); var gy1 := int(ceil(area.end.y / cell))
	if (gx1 - gx0) * (gy1 - gy0) > VOID_DECOR_MAX_CELLS:
		return                                    # 极端缩放/超大图兜底：白烧填充率（红线#3 手机）
	var phase := float(Sim.tick_no % 6) / 6.0
	var col_near := Color(0.84, 0.91, 1.00, 0.44)
	var col_far := Color(0.78, 0.87, 1.00, 0.26)
	for gy in range(gy0, gy1):
		for gx in range(gx0, gx1):
			var hsh := _hash(gx, gy, 57)
			var m := hsh % 100
			if m >= 52:                           # 密度 36→52：更明显（before 帧偏淡）
				continue
			var near := m < 26                    # 一半近景一半远景 ⇒ 景深，读作真在下雨
			var p := Vector2((float(gx) + float(hsh % 61) / 61.0) * cell,
				(float(gy) + float(hsh / 61 % 61) / 61.0 + phase) * cell)
			if near:
				draw_line(p, p + Vector2(-T * 0.16, T * 0.56), col_near, 1.9)
			else:
				draw_line(p, p + Vector2(-T * 0.12, T * 0.34), col_far, 1.1)
	# 地面涟漪：独立散布（salt 43），扩大环按 tick 眨（每 8 tick 亮 3 tick，半径随亮度扩大、透明度衰减）
	# —— 读作雨点打在地上。分开一套散布 ⇒ 与雨丝落点解耦，不会连成"相框"（docs/41 §6 等距连续陷阱）。
	var rcell := T * 2.0
	var rx0 := int(floor(area.position.x / rcell)); var rx1 := int(ceil(area.end.x / rcell))
	var ry0 := int(floor(area.position.y / rcell)); var ry1 := int(ceil(area.end.y / rcell))
	for ry in range(ry0, ry1):
		for rx in range(rx0, rx1):
			var rh := _hash(rx, ry, 43)
			if rh % 100 >= 22:
				continue
			var blink := (Sim.tick_no + rh) % 8   # 相位含 rh ⇒ 每个涟漪各眨各的，不同步闪烁
			if blink >= 3:
				continue                          # 每 8 tick 只亮 3 tick
			var rp := Vector2((float(rx) + float(rh % 50) / 50.0) * rcell,
				(float(ry) + float(rh / 50 % 50) / 50.0) * rcell)
			var rr := T * (0.10 + 0.06 * float(blink))
			draw_arc(rp, rr, 0.0, TAU, 9, Color(0.88, 0.93, 1.00, 0.36 - 0.10 * float(blink)), 1.3)

## 冬雪。确定性：位置来自 _hash(gx,gy,salt)，飘落/漂移相位来自 Sim.tick_no —— 不抽 RNG、不读墙钟，
## 同一 tick 重拍逐像素相同（--shot 冻结 tick；precip 门靠这条可比性）。
## ★ AI1（编号129）：冬季地面霜白由 SEASON_WASH["冬"](α0.24) 负责，本层补的是【飘落的雪花】——
##   before 帧实测：冬天只有冷色调 + 弱霜白、无落雪，眼验读不出"冬天"。雪只读 Sim.season_today=="冬"，
##   不新增仿真态、不改 lifecycle.json。两层视差（近大慢飘 / 远小快落）+ 侧向漂移，读作有体积的雪。
##   风暴档：冬遇阴/雨 ⇒ 更密（暴风雪）；晴 ⇒ 疏落飘雪。纯读 weather，无新态。
func _draw_snow() -> void:
	var area := _precip_area()
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var cell := T * 1.25
	var gx0 := int(floor(area.position.x / cell)); var gx1 := int(ceil(area.end.x / cell))
	var gy0 := int(floor(area.position.y / cell)); var gy1 := int(ceil(area.end.y / cell))
	if (gx1 - gx0) * (gy1 - gy0) > VOID_DECOR_MAX_CELLS:
		return                                    # 极端缩放/超大图兜底：白烧填充率（红线#3 手机）
	var dense := 40                               # 晴：疏落飘雪
	if Sim.weather_today == "阴":
		dense = 54
	elif Sim.weather_today == "雨":
		dense = 70                                # 暴风雪（冬季降水统一走这里，_draw_rain 在冬季不调）
	var slow := float(Sim.tick_no % 10) / 10.0    # 大片：慢飘
	var fast := float(Sim.tick_no % 5) / 5.0      # 小点：快落
	var sway_slow := sin(slow * TAU)              # 侧向漂移相位（每帧常量，循环外算一次）
	var sway_fast := sin(fast * TAU)
	var big := Color(0.97, 0.98, 1.00, 0.94)
	var small := Color(0.90, 0.94, 1.00, 0.68)
	for gy in range(gy0, gy1):
		for gx in range(gx0, gx1):
			var hsh := _hash(gx, gy, 91)
			if hsh % 100 >= dense:
				continue
			var jx := float(hsh % 53) / 53.0
			var jy := float(hsh / 53 % 53) / 53.0
			var amp := (float((hsh / 7) % 5) - 2.0) * 0.07 * T   # 每片各自的漂移幅度 [-2..2]
			if hsh % 3 == 0:                       # ~1/3 大片，近景，慢飘
				var p := Vector2((float(gx) + jx) * cell + amp * sway_slow,
					(float(gy) + jy + slow) * cell)
				draw_rect(Rect2(p.x, p.y, T * 0.14, T * 0.14), big, true)
			else:                                  # 其余小点，远景，快落
				var p2 := Vector2((float(gx) + jx) * cell + amp * sway_fast,
					(float(gy) + jy + fast) * cell)
				draw_rect(Rect2(p2.x, p2.y, T * 0.09, T * 0.09), small, true)

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST  # 像素清晰，不糊
	_grass = [
		{"t": Art.terrain_tex("grass_a"), "w": 70},
		{"t": Art.terrain_tex("grass_b"), "w": 24},
		{"t": Art.terrain_tex("grass_flowers"), "w": 6},
	].filter(func(g): return g["t"] != null)
	_build_void_layer()
	_build_night_lights()
	# ★真机上的 pass 开关。Godot 4.6 Android **不读** intent 的 `command_line_args`
	#   （memory `reference-godot-android-loop` 实测），所以 CLI 旗到不了手机；而"每验一条假设
	#   就重出一次 APK"是 6 分钟一发。改从 `user://settings.cfg` 读一个键，就能用
	#   `adb ... run-as` 推一行字换一个实验 —— 出一次 APK，量任意多条 pass。
	#   缺键 ⇒ `_askip == ""` ⇒ 出货路径逐字节不变。
	var _dcfg := ConfigFile.new()
	if _dcfg.load("user://settings.cfg") == OK:
		_askip = String(_dcfg.get_value("dev", "draw_skip", ""))
	var _uargs := OS.get_cmdline_user_args()
	for _i in _uargs.size():
		if _uargs[_i] == "--draw-audit" and _i + 1 < _uargs.size():
			_audit_path = _uargs[_i + 1]        # dev 量具：逐 pass draw-call 归因（见 AUDIT_PASSES 一节）
		elif _uargs[_i] == "--draw-audit-zoom" and _i + 1 < _uargs.size():
			_audit_zoom = float(_uargs[_i + 1]) # 同上，但先把相机钉到指定缩放（扫 zoom 用；绕开 min_zoom 地板）
		elif _uargs[_i] == "--draw-skip" and _i + 1 < _uargs.size():
			_askip = String(_uargs[_i + 1])     # AI1（编号129）：视觉门/dev —— 跳过一个绘制 pass。
			                                    # precip 门用它拍 on/off 负对照（--draw-skip snow / rain）。
			                                    # 缺旗 ⇒ _askip 保持 settings.cfg 的值（出货为 ""）⇒ 逐字节不变。
		elif _uargs[_i] == "--void-gate":
			_void_gate = true                   # 见 _void_gate_step()：把这一棒的 9× 那条性质机器化
		elif _uargs[_i] == "--cache-gate":
			_cache_gate = true                  # 见 _cache_gate_step()：W6 的机器断言
	Sim.ticked.connect(func(_t): _redraw_all())
	Sim.agent_changed.connect(func(_id): _redraw_all())
	Sim.social_event.connect(_on_social)
	# ★ E5/W6：换世界 ⇒ 作废所有从 Sim.world 烘出来的渲染缓存。
	# `world_reset` 由 `Sim.start_new`（新局 / 玩家模式开关）与 `Sim.load_game`（F8 读档）**两条**路径发，
	# 而 `load_game` 是 `for k in state: set(k, state[k])` —— `world` 是 Sim 的脚本变量、不在 DERIVED 排除表里，
	# **所以读档会整个换掉 `Sim.world`**。此前没有任何一条路径清过下面这四样。
	Sim.world_reset.connect(_invalidate_world_caches)
	# ★ H3 · 开局就把「每个 advertises 的对象都解析得出精灵槽」查一遍（见文件末尾 H3 一节）。
	#   实测（本棒探针，--headless 下的 player_touch_test 路径）：WorldView._ready() 里
	#   `Sim.world["objects"] is Dictionary == true, n=24` ⇒ 这里读到的是**已经装好的**世界，
	#   不是 docs/41 §2 那个"节点在但数据是空的"陷阱（那条讲的是 `--script` 的 `_initialize()`）。
	_slot_probe_tick()

## ★ W6 · 把从 `Sim.world` 烘出来的渲染缓存全部作废（下一帧 `_draw` 会按需重建）。
##
## 病症（外部评审 2026-07-28，E5 复核为真）：`_terrain_built` / `_paths_built` / `_decor_built`
## 三个标志位**从建起来就没有任何一条路径清过**，而 `_grass_var` 按**第一个**世界的 `w*h` 分配、
## 却在 `_draw` 里用**当前** `w` 索引（`_grass_var[ty*w + tx]`）。今天地图尺寸恒定 ⇒ 潜伏；
## 一旦读进一张不同尺寸的地图，轻则画错格子、重则 `_grass_var` 越界。
##
## ⚠️ 这里**只清标志、不重建**：重建必须发生在 `_draw` 里，因为 `_build_decor` 要读 `Sim.world["objects"]`，
## 而 `load_game` 的 `_rebuild_after_load` 与本回调的先后次序不该被这一层依赖。
## `_verge_ground`（草地纹理均值）也一并清：它是 `_grass` 的函数，换切片包时同样会过期。
func _invalidate_world_caches() -> void:
	_terrain_built = false
	_paths_built = false
	_decor_built = false
	_grass_var = PackedByteArray()
	_verge_ground = Color(0, 0, 0, 0)
	_slot_probe_n = -1                    # H3：换世界 ⇒ 下一次 _redraw_all 重新体检精灵槽
	if _void != null:
		_void_key = ""                    # 界外层的缓存键也得作废：新世界的地图矩形可能不一样
		_void.queue_redraw()
	queue_redraw()

## ── ★ 暂停时换空间 / 换选中，世界层不更新（E6 发现，E5 复核并在出货路径上复现）────────────
## 病症：本节点只在 `Sim.ticked` / `Sim.agent_changed` / 渲染坐标脏 三种情况下 `queue_redraw()`。
## 而 **空格暂停 = `Sim.running = false`**（`Main.gd:2012`），`Sim._process` 首行是
## `if not (auto_run and running): return` ⇒ tick 停了；此时点门走 `Main._portal_click`，
## 它只改 `_probe.active_space` 与相机、**这三样一个都不碰** ⇒ `_draw()` 再也不跑
## ⇒ 世界层继续画着**镇子**，而 HUD 已经写着「阿丽的咖啡馆 / 1f 层（点进门）」。
##
## **实测**（本文件的临时探针，真调 `Main._portal_click(咖啡馆街门 41,19)`，非模拟）：
##   `[PAUSEPORTAL] f20 暂停：running=false auto_run=true space=town`
##   `[PAUSEPORTAL] f30 点门：hit=true space=cafe`
##   `[PAUSEPORTAL] f60 点门后 30 帧：WorldView._draw() 被调用了 **0** 次`
## 不暂停时看不见，只因为 80ms 后下一个 tick 就来了 —— 它是一个**只在暂停下暴露的真 bug**。
##
## 同一形状还有第二个：`Main._select_at_world` 改 `_selected_id` 也不重画 ⇒ 暂停时点居民，
## 选中高亮 / 关系线的 focus 压暗 / D5 的焦点集恒显 全都不更新。
## （`dbg_nav` 那条**不在此列**——`Main.gd:2047` 自己补了 `_view.queue_redraw()`，我去查过了。）
##
## 为什么是窄键而不是别的两种做法：
##   · **不接 probe 的信号**：那要改 `ProbeController.gd` / `Main.gd`，两个都不在本棒的独占集里。
##   · **不并进 `_void_cache_key()`**：那把 zoom/vis 也带进了键 ⇒ 相机一动就整层重画，
##     正是 D7 花了 9 倍帧时才去掉的东西。这里只取「不随 tick 变、而 `_draw()` 会读」的那几样。
func _view_state_key() -> String:
	var mn := get_parent()
	if mn == null:
		return ""
	var pb = mn.get("_probe")
	var sp := "town"
	var fl := "outdoor"
	if pb != null:
		sp = String(pb.active_space)
		fl = String(pb.active_floor)
	return "%s|%s|%s|%d|%d" % [sp, fl, _selected_id(), int(dbg_nav), rel_mode]

var _view_key := ""

## 本节点 + 加色光层一起重画。光层的内容只依赖 time_of_day 与静态地形，所以跟 tick 走就够了；
## 相机移动不需要重画（光层是本节点的子 Node2D，共用同一条画布变换）。
func _redraw_all() -> void:
	_slot_probe_tick()      # H3：只在 world["objects"] 规模变了时做 O(n) 全扫（civic_/fest_ 是运行期 spawn 的）
	queue_redraw()
	if _lights != null:
		_lights.queue_redraw()

func _hash(x: int, y: int, salt: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	return absi(h)

## 每格用哪一张草地切片（`_hash(tx,ty,3)` 的纯函数）。建一次、缓存；建它是为了让 `_draw`
## 能**按变体分组**画而不必每格重算加权抽样。地图 64×48 ⇒ 3072 字节，可以忽略不计。
func _build_grass_var(w: int, h: int) -> void:
	var tw := 0
	for g in _grass:
		tw += int(g["w"])
	if tw <= 0:
		return
	_grass_var.resize(w * h)
	for ty in range(h):
		var row := ty * w
		for tx in range(w):
			var r := _hash(tx, ty, 3) % tw
			var pick := 0
			for gi in _grass.size():
				r -= int(_grass[gi]["w"])
				if r < 0:
					pick = gi
					break
			_grass_var[row + tx] = pick

## ── H3-c · 装饰池：**同一条病的第三个实例**，H1 2026-07-30 真机眼验时报出来的 ────────────
## 原文是一句写死的字面量 `["bush","flower_red","flower_yellow","flower_white","rock","stump","mushroom"]`，
## 而 **`assets/art/decor/flower_white.png` 根本不存在**（实测：该目录只有 bush / flower_red /
## flower_yellow / mushroom / rock / stump / tree_big / tree_small 八个）。
## 下面那句 `if t != null` 把它**静默滤掉**了 ⇒ 这行字面量**不是"画了什么"的证据**，
## 而任何人读代码都会以为镇上有白花。这和 `id.split("_")[0]` 是同一条病：
## **一个名字 → 一份资产的隐式契约 + 一条静默的兜底路径。**
##
## 处理分两步（都在本文件里）：
##   ① 把死名字从表里删掉 —— **这一步逐像素零改动**：它本来就在 `if t != null` 处被丢弃，
##      `pool` / `total_w` / 顺序 / 权重全都不变。实测：本文件全部改动 vs 未改动的树，
##      2560×1536 整帧、夜(warmup 3)与正午(tick 600)两帧都是 `bbox=None`、不同像素 0
##      （先 `convert("RGB")`，避开 docs/41 §6 那条 `getbbox()` 只看 alpha 的空真陷阱）。
##   ② 加一条 `verify_decor_pool()`：声明了却没有贴图 ⇒ push_error，不再静默。
##      **在未改动的树上这条判据是红的**（flower_white）——它有一个真实的活实例，不是装饰性判据。
const DECOR_POOL := ["bush", "flower_red", "flower_yellow", "rock", "stump", "mushroom"]

## 声明了装饰名却没有对应切图 ⇒ 吼。（`tree_big` 不在此列：它在 _draw 里有程序化回退，缺图是合法的。）
func verify_decor_pool() -> int:
	var bad := 0
	for nm in DECOR_POOL:
		if Art.decor_tex(String(nm)) != null:
			continue
		bad += 1
		var key := "DECOR|" + String(nm)
		if _slot_shouted.has(key):
			continue
		_slot_shouted[key] = true
		push_error(("[WorldView] 装饰池里的 '%s' 没有切图（assets/art/decor/%s.png 不存在）。" +
			"它会被 _build_decor 静默滤掉 ⇒ 代码上看着有、屏幕上一个都不会出现。" +
			"要么补图，要么把这个名字从 WorldView.DECOR_POOL 里删掉。") % [nm, nm])
	return bad

## 在区域外的草地上确定性散布装饰（树/花/草丛…），让小镇不再空旷。切图缺失则跳过。
func _build_decor() -> void:
	_decor_built = true
	_decor_items.clear()
	if not _paths_built:
		_build_paths()                    # 先有路，散装饰时才能避开它
	_build_street_props()                 # AP1(140)：先落 verge 街具，花草再避开它（别把花画在灯柱脚下）
	var pool := []
	# 树不再散布：P2-2 的可见树 = authored 阻挡树（_tree_cells）。程序化装饰只留贴地花草石（可踩，纯装饰）。
	# ── I2 2026-07-30：这里原本还有两个 `tree*` 分支（H2 报的"699-700 两行死代码"）────────────────
	# 	var tall := 2 if nm == "tree_big" else 1
	# 	var weight := 3 if nm.begins_with("tree") else (10 if ...)
	# `DECOR_POOL` 里**一个 `tree*` 都没有**（G3/H3 之后只剩 6 项花草石）⇒ 两个条件恒假。
	# 顺着 `tall` 往下还有**一整条死链**，H2 只报到了头两行：
	#   `tall`(恒 1) → `pool["h"]` → `_decor_items["h"]` → `_draw_body` 里的 `var th := int(it["h"])`
	#   → **`th` 没有任何读者**（不写行号：行号会漂，这仓库已经为此纠正过三次）。
	# 画的尺寸一直是从纹理量的（`dw/dh = tex.get_width()/16*T`），从来不看 `h`。四段一起删。
	# **逐像素零改动是可证的，不是"看起来一样"**：`weight` 对现存 6 个名字取值不变（flower*=10，其余=6）
	# ⇒ `total_w`、抽样、`k`、排序全序、布局逐格相同；`h` 从来不进任何 `draw_*` 调用。
	for nm in DECOR_POOL:
		var t := Art.decor_tex(nm)
		if t != null:
			pool.append({"t": t, "w": 10 if nm.begins_with("flower") else 6})
	if pool.is_empty():
		return
	var total_w := 0
	for p in pool:
		total_w += int(p["w"])
	var w: int = int(Sim.world.get("width", 24))
	var h: int = int(Sim.world.get("height", 16))
	for y in range(h):
		for x in range(w):
			if _in_area(x, y) or _is_object(x, y) or _is_blocked(x, y) or _path_set.has(y * w + x) or _street_prop_cells.has(y * w + x):
				continue                      # 区域/家具/阻挡/土路/街具格 上都不散装饰（路面保持干净）
			if _hash(x, y, 7) % 100 >= 22:   # ~22% 密度
				continue
			var r := _hash(x, y, 13) % total_w
			for pi in pool.size():
				r -= int(pool[pi]["w"])
				if r < 0:
					_decor_items.append({"tex": pool[pi]["t"], "cell": Vector2i(x, y), "k": pi})
					break
	# ★D7 合批：按【纹理】稳定排序（同纹理内保持原有先后）。散布【布局】一个字节没动，只改了画的次序
	#   ⇒ 实测 427 次 draw call 塌成每种纹理一段。
	#   **逐像素不变是可证的**：`pool` 里全是 16×16 源图 ⇒ `dw=dh=T`，底对齐后
	#   `(c.y+1)*T - T == c.y*T` ⇒ **恰好铺满自己那一格**，且每格最多散一件
	#   ⇒ 一组互不相交的图元，画的顺序不影响任何一个像素（带 alpha 也一样，因为各自压在
	#   不同的底上）。真正会跨格的 `tree_big` 走 `_tree_cells`，不在这个数组里。
	#   比较子是**全序**（k → y → x），不靠 sort_custom 的稳定性：等价键会让排序结果随实现摇摆，
	#   而 `--shot` 的逐字节可复现是本仓库的既有承诺。
	_decor_items.sort_custom(func(a, b):
		if int(a["k"]) != int(b["k"]):
			return int(a["k"]) < int(b["k"])
		var ca: Vector2i = a["cell"]
		var cb: Vector2i = b["cell"]
		return ca.y < cb.y if ca.y != cb.y else ca.x < cb.x)

## ── AP1(140) verge 街具：在【路/广场旁】的 free cell 上确定性落纯 View 街景（路灯/花坛/长椅/系缆柱）──
## ⚠ 安全谓词【复用】`_build_decor` 现成那一套（非区 ∧ 非家具 ∧ 非blocked ∧ 非路）——**不自造 free-cell 判定**；
##   在它之上再加一层【贴着铺装】(`_is_paved` 的 8 邻) 把散布收敛到 verge。这是**布局选择**，不动安全性那一层。
## 确定性：落点/类型全走 `_hash(x,y,salt)`（无 randi/Time）⇒ `--shot` 逐像素可复现（红旗#4）。
## Sim 永不感知：这些格仍是 walkable 草地（**不进 blockers**）；街具是纯美术，不改任何格 walkable、零金标。
func _build_street_props() -> void:
	_street_prop_items.clear()
	_street_prop_cells.clear()
	if _plaza_cells.is_empty() and _path_set.is_empty():
		return                              # 没有铺装 ⇒ 没有 verge，什么都不落
	var w: int = int(Sim.world.get("width", 24))
	var h: int = int(Sim.world.get("height", 16))
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			# ★复用 _build_decor 的安全谓词（`_in_area` 已含广场；`_path_set` 是街）——一字不改。
			if _in_area(x, y) or _is_object(x, y) or _is_blocked(x, y) or _path_set.has(idx):
				continue
			# verge：8 邻里至少一格是铺装（街 或 广场/码头）⇒ 把街具收敛到路两侧/广场周边（越界格自然为假）
			var near_paved := false
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx; var ny: int = y + dy
					if nx >= 0 and nx < w and ny >= 0 and ny < h and _is_paved(nx, ny):
						near_paved = true
						break
				if near_paved:
					break
			if not near_paved:
				continue
			if _hash(x, y, 41) % 100 >= 44:       # ~44% 的 verge 格落一件（街被点亮但不拥挤）
				continue
			var b := _hash(x, y, 43) % 100         # 类型加权：路灯偏多 → 花坛 → 长椅 → 系缆柱
			var kind := 0
			if b < 38:      kind = 0               # lamp   路灯
			elif b < 64:    kind = 1               # planter 花坛
			elif b < 84:    kind = 2               # bench  长椅
			else:           kind = 3               # bollard 系缆矮柱
			# 逐 y、逐 x 顺序 append ⇒ 数组本身即 (y,x) 全序，`--shot` 可复现，无需再排序。
			_street_prop_items.append({"cell": Vector2i(x, y), "kind": kind})
			_street_prop_cells[idx] = true

## AP1(140) 画一件 verge 街具。纯 draw_* 图元（同 `_draw_landmarks` 的路子），底对齐格子。
## 四季植栽走 `_season_veg()`（与草地/装饰同源），其余是静态石/木/暖光（不做逐 tick 动画 ⇒ 无 Time 依赖）。
func _draw_street_prop(kind: int, cell: Vector2i) -> void:
	var base := Vector2(cell.x * T, cell.y * T)
	var cx := base.x + T * 0.5
	match kind:
		0:                                          # 路灯：暗柱 + 暖光灯笼
			draw_rect(Rect2(cx - T * 0.11, base.y + T * 0.80, T * 0.22, T * 0.10), Color(0, 0, 0, 0.20), true)  # 灯脚落影
			draw_rect(Rect2(cx - T * 0.045, base.y + T * 0.22, T * 0.09, T * 0.62), S_LAMP_POST, true)          # 灯柱
			draw_rect(Rect2(cx - T * 0.14, base.y + T * 0.05, T * 0.28, T * 0.20), S_LAMP_POST.darkened(0.12), true)  # 灯罩壳
			draw_rect(Rect2(cx - T * 0.105, base.y + T * 0.08, T * 0.21, T * 0.14), X_GLOW, true)               # 暖玻璃
			draw_rect(Rect2(cx - T * 0.105, base.y + T * 0.08, T * 0.21, T * 0.14), Color(X_GOLD, 0.9), false, 1.0)  # 金框
			draw_rect(Rect2(cx - T * 0.16, base.y + T * 0.01, T * 0.32, T * 0.05), S_LAMP_POST, true)           # 顶帽
		1:                                          # 花坛：石框 + 四季植栽 + 花点
			var by1 := base.y + T * 0.5
			draw_rect(Rect2(base.x + T * 0.16, by1 + T * 0.10, T * 0.68, T * 0.34), S_PLANTER, true)            # 石框
			draw_rect(Rect2(base.x + T * 0.16, by1 + T * 0.10, T * 0.68, T * 0.06), S_PLANTER.lightened(0.18), true)  # 上沿高光
			draw_rect(Rect2(base.x + T * 0.16, by1 + T * 0.10, T * 0.68, T * 0.34), S_PLANTER.darkened(0.26), false, 1.0)  # 描边
			var veg := _season_veg()
			draw_circle(Vector2(base.x + T * 0.36, by1 + T * 0.06), T * 0.13, P_FOLIAGE_M * veg)                # 灌丛
			draw_circle(Vector2(base.x + T * 0.60, by1 + T * 0.03), T * 0.13, P_FOLIAGE_D * veg)
			draw_circle(Vector2(base.x + T * 0.42, by1 + T * 0.01), T * 0.032, X_SIGNAL_NEG)                    # 红花点
			draw_circle(Vector2(base.x + T * 0.66, by1 - T * 0.01), T * 0.032, X_GOLD)                          # 黄花点
		2:                                          # 长椅：木条座 + 靠背 + 椅腿
			var by2 := base.y + T * 0.5
			draw_rect(Rect2(base.x + T * 0.14, by2 + T * 0.36, T * 0.72, T * 0.08), Color(0, 0, 0, 0.18), true)  # 落影
			draw_rect(Rect2(base.x + T * 0.21, by2 + T * 0.24, T * 0.06, T * 0.16), S_BENCH_WOOD.darkened(0.30), true)  # 左腿
			draw_rect(Rect2(base.x + T * 0.73, by2 + T * 0.24, T * 0.06, T * 0.16), S_BENCH_WOOD.darkened(0.30), true)  # 右腿
			draw_rect(Rect2(base.x + T * 0.14, by2 + T * 0.19, T * 0.72, T * 0.10), S_BENCH_WOOD, true)          # 座板
			draw_rect(Rect2(base.x + T * 0.14, by2 + T * 0.19, T * 0.72, T * 0.03), D_FURN_HI, true)             # 座板高光
			draw_rect(Rect2(base.x + T * 0.14, by2 + T * 0.04, T * 0.72, T * 0.05), S_BENCH_WOOD, true)          # 靠背横档
			draw_rect(Rect2(base.x + T * 0.16, by2 + T * 0.08, T * 0.05, T * 0.12), S_BENCH_WOOD.darkened(0.20), true)  # 靠背左柱
			draw_rect(Rect2(base.x + T * 0.79, by2 + T * 0.08, T * 0.05, T * 0.12), S_BENCH_WOOD.darkened(0.20), true)  # 靠背右柱
		_:                                          # 系缆矮柱（bollard）：石柱 + 铜顶
			var by3 := base.y + T * 0.5
			draw_rect(Rect2(cx - T * 0.11, by3 + T * 0.34, T * 0.22, T * 0.08), Color(0, 0, 0, 0.18), true)     # 落影
			draw_rect(Rect2(cx - T * 0.10, by3 + T * 0.06, T * 0.20, T * 0.34), S_PLANTER, true)                # 石柱
			draw_rect(Rect2(cx - T * 0.10, by3 + T * 0.06, T * 0.20, T * 0.06), S_PLANTER.lightened(0.20), true)  # 柱顶受光
			draw_rect(Rect2(cx - T * 0.10, by3 + T * 0.06, T * 0.20, T * 0.34), S_PLANTER.darkened(0.28), false, 1.0)  # 描边
			draw_circle(Vector2(cx, by3 + T * 0.05), T * 0.055, X_GOLD)                                         # 铜帽

## 水格 → 岸线瓦片分组（G5 / docs/49 §七）。按**四邻是不是水**选瓦，瓦片名里的方位
## 指的是**陆地在哪一侧**（`water_n` = 北面是岸），因为这里手上有的正是"四邻水不水"。
##
## **界外一律按陆地算**：贴着地图边的水域会长出岸线，而不是被悄悄当成"外面还有水"而留一条硬边。
##
## ⚠ 三面/四面临陆的格子（1 格宽的水沟、孤立的一格水塘）**当前地图里一个都没有**
## （两个池塘都是实心矩形：north x28-35 y2-6、south x28-35 y42-46，实测 perfect_rect=True）。
## 这类 mask 这里按"先判角、再判边"退化成某一个角瓦 —— 它会漏掉第三面的岸。
## 写清楚是因为**将来谁挖一条 1 格宽的河，这里就是要改的地方**；不写死断言是因为
## 视图层不该因为地图长得不合意就崩，退化画法比开天窗好。
func _build_water_slots(wd: int, ht: int) -> void:
	var by := {}
	for idx in _water_set:
		var wx: int = idx % wd
		var wy: int = idx / wd
		# 界外 = 陆地（`has()` 对越界下标自然为 false，但 x 方向要显式挡住绕行到上/下一行）
		var ln := wy <= 0 or not _water_set.has(idx - wd)
		var ls := wy >= ht - 1 or not _water_set.has(idx + wd)
		var lw := wx <= 0 or not _water_set.has(idx - 1)
		var le := wx >= wd - 1 or not _water_set.has(idx + 1)
		var nm := "water"
		if ln and lw:      nm = "water_nw"
		elif ln and le:    nm = "water_ne"
		elif ls and lw:    nm = "water_sw"
		elif ls and le:    nm = "water_se"
		elif ln:           nm = "water_n"
		elif ls:           nm = "water_s"
		elif lw:           nm = "water_w"
		elif le:           nm = "water_e"
		if not by.has(nm):
			by[nm] = PackedInt32Array()
		by[nm].append(idx)
	# 名字排序后再落数组：分组顺序**与字典遍历顺序无关** ⇒ 同一张地图每次得到同一张表。
	# （画面本来就与顺序无关，见 `_draw` 里那段证明；这里求的是"表本身可复现"，便于逐字节对拍。）
	_water_by_slot.clear()
	var names := by.keys()
	names.sort()
	for nm in names:
		_water_by_slot.append([nm, by[nm]])


# ══ V3 · 林相分化（authored 阻挡树）═════════════════════════════════════════════════════
#
# **改前实测**：`map.json trees` 的 156 格是**两块 6×13 的实心矩形**（x 2-7 / x 56-61，y 18-30），
# 而画法是【同一张 tree_big × 同一个 veg 乘子 × 同一个亚格偏移 × 同一个尺寸】。
# 于是它不是一片林子，是一张**盖章点阵**——而且矩形的四条边是直的。
# 量出来的读数（`--shot-fit`、seed 3、tick 600、2560×1536；判据见回执）：
#   林块内部【平移恰好一格】之后的平均逐像素差 P：横 **0.180 / 0.133**（两块）。
#   同一帧的对照：空草地 4.05 / 10.12、广场 18.4、**池塘 0.000**。
#   ⇒ 这片"林子"的周期性读数和一潭死水同一个数量级。这就是壁纸的定义。
#
# 分化只用两样东西，**两样都不是新素材、也不是新数据**（红线#4 素材、#5 复用优先）：
#   ① **authored 结构**：这一格的四邻里有几个也是树。与上面 `_build_water_slots` 按四邻选岸线瓦
#      是同一条路子 —— 判据的真源仍然是 `map.json`，本函数只读不写。
#   ② **确定性位置哈希** `_hash(x,y,salt)`：与 `_build_decor` / `_draw_rain` 同源。
#      不抽 RNG、不读墙钟 ⇒ **同一 tick 重拍逐像素相同**（`--shot` 的既有承诺）。
#
# ⚠️ 三条自己给自己划的线，每条都有出处：
#   · **偏移以【源像素】为步长**（`T/16` = 3 世界像素）。本文件抬头那条"整数像素尺"讲的就是这件事：
#     非整数倍会让一部分源像素占 1 个屏幕像素、另一部分占 2 个 ⇒ 精灵读作"融化的"。
#   · **不许拿颜色去标林块边界。** docs/41 §6★ 记着 C7 的教训：沿边界**等距且连续**的任何东西
#     都会从"延续"退化成【相框】——比原来那条硬边更糟。所以外沿那一档拿到的是**更大的偏移幅度**
#     （林线因此是锯齿），**不是**更亮的颜色（那等于把这个矩形又描一遍）。
#   · **不引入新的 `Color("#...")` 字面量**（本文件抬头的纪律）：明暗档是**乘算档**，
#     与 `SEASON_VEG` 同形 —— 换掉锚点色它们跟着走，不是第二份真相。
const TREE_SALT_JIT  := 41    # 两个盐，分别喂偏移与明暗；同源于 _hash(x,y,salt)
const TREE_SALT_TONE := 47
## 林冠明暗档（**乘算**，不是授权色）。
## **四档的理由不是"两档会条纹"** —— 用下面 `_hash_mix` 之后两档同样混得开（实测同值率 50.0/52.5/54.4%）。
## 是因为要让三种读法各有一档：**林子深处**（背阴）/ **树冠顶面**（受光）/ **另一株树**（另一种绿），
## 加上"原样"共四档。实测分布 27/42/42/45，相邻同档率 24.1%（理想 25%）。
const TREE_TONE: Array[Color] = [
	Color(1.00, 1.00, 1.00),   # 原样（改前全体都是这一档）
	Color(0.86, 0.90, 0.84),   # 背阴：压绿压亮，读作林子深处
	Color(1.10, 1.06, 0.92),   # 受光：偏暖，读作树冠顶面
	Color(0.93, 1.01, 0.88),   # 另一种绿：只动 G/B 的比，读作另一株而不是另一个光照
]

## ⚠️ **不许直接对 `_hash()` 取 `% 2` / `% 4`。这条是实测出来的，而且是我这一棒自己先踩的。**
##
## `_hash = |(x*73856093) ^ (y*19349663) ^ (salt*83492791)|`，而 `73856093 % 4 == 1`、
## `19349663 % 4 == 3` —— XOR 是**逐位**的 ⇒ **低两位只由 `(x%4, y%4)` 决定**。
## 于是 `% 2` 是一张**完美棋盘**、`% 4` 是一张 **4×4 的壁纸**。实测（156 棵树，同值率 = 相邻 d 格取值相同的比例）：
## ```
##              d=1      d=2      d=4     理想
##   h % 2      0.0%   100.0%   100.0%     50%    ← 严格周期
##   h % 4      0.0%     0.0%   100.0%     25%    ← 严格周期
##   (h/7) % 2 50.0%    52.5%    54.4%     50%    ← 混开了
##   (h/7) % 4 24.1%    22.9%    21.9%     25%
## ```
## **这正是本棒要治的那个病的复发**：为了打散点阵而引入的"随机档"，它的低位本身就是一张点阵
## ——按周期 2/4 把刚拆掉的格子又摆回去。**"先量再动"对【自己的改动】同样成立。**
## 除以 7（与低位互质、把高位拉下来）之后三个 d 都回到理想值附近。
## 偏移用的 `% 5` / `% 9` **不受影响**（模数是奇数、本来就依赖全值：实测 d1 15.3% / d2 22.5% / d4 13.1%）。
func _hash_mix(x: int, y: int, salt: int) -> int:
	return int(_hash(x, y, salt) / 7)

## 一棵 authored 树画成什么样（**纯函数**：只读格坐标与 `_tree_set`，不读 tick、不读相机、不抽 RNG）。
func _tree_style(tc: Vector2i, wd: int) -> Dictionary:
	var px := float(T) / 16.0                 # 一个源像素 = 3 个世界像素
	var open := 0                             # 四邻里【不是树】的方向数：>0 即在林块外沿
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _tree_set.has((tc.y + d.y) * wd + (tc.x + d.x)):
			open += 1
	var amp := 2 if open == 0 else 4          # 外沿幅度加倍 ⇒ 林线锯齿化（见抬头第二条线）
	var jx := _hash(tc.x, tc.y, TREE_SALT_JIT) % (amp * 2 + 1) - amp   # 左右对称；模数是奇数 ⇒ 不用过 _hash_mix
	var jy := _hash_mix(tc.x, tc.y, TREE_SALT_JIT) % (amp + 2) - amp   # 偏上：树冠可以往上长，脚不该离地
	return {
		"cell": tc,
		"off": Vector2(float(jx) * px, float(jy) * px),
		"tone": TREE_TONE[_hash_mix(tc.x, tc.y, TREE_SALT_TONE) % TREE_TONE.size()],
	}

## ── ⚠️ 这里**没有**"水平镜像"这一档，而它是**做出来、量完之后拿掉的**（不是没想到）──────────
##
## 做法本身是对的：预先烘一张 `tree_big` 的 `Image.flip_x()` 纹理。
## **不能**用 `draw_texture_rect_region` 的负宽矩形——`tree_big` 的 alpha **左右完全对称**
## （实测：镜像后 alpha 逐像素差 **0/1024**，只有 RGB 内部明暗差 150 px）
## ⇒ **一次正确的镜像必然不改变覆盖面积**。拿这条去量（西林块+边距 8×16 格、全体强制翻转、数草地色像素）：
## ```
##   不翻转（基准）                     15 277 / 61 952   24.66%
##   draw_texture_rect_region 负【源】宽 39 170 / 61 952   63.23%   ← 树基本没画出来
##   同一调用          负【目标】宽      19 700 / 61 952   31.80%   ← 也不是纯镜像
##   预烘的 flip_x 纹理                 15 277 / 61 952   24.66%   ← 与基准逐字节相同
## ```
## 两种负宽写法在屏幕上都"看起来翻转了"（确实有像素在动），而它们**同时把树吃掉了一块**。
##
## **拿掉它的理由是合批**（D7 那一棒的行）：第二张纹理 + 行优先次序 ⇒ 两张图逐棵交替，
## `--draw-audit` 实测 `trees` pass **1 → 80 次 draw call**（世界层 2817 → 2896，+2.8%）。
## 而它买到的东西很小：一格周期性残差 P 只涨 8-9%（最紧的夜档 11.89 → 13.00），
## **没有它 P 仍然是门线 8.0 的 1.49 倍**。
## ⇒ **80× 的合批代价换 8% 的指标，不划算。**（换 pass 内按 flip 分趟也不行：同一行相邻两棵有 18 世界像素的
##   不透明重叠 ⇒ 换序会改像素，而那正是上面那条"行优先"要修的东西。）

## 一次性烘出 156 条画法，并把绘制次序改成**行优先**。
##
## ⚠️ **次序这一条是独立的一个 bug，不是顺手做的**：`map.json trees` 是**列优先**存的
## （x=2 的 13 格、x=3 的 13 格…），而绘制次序就是遍历次序 ⇒ `(3,18)`（上排那棵）
## 画在 `(2,30)`（下排那棵）**之后**，于是**上排的树压住了下排的树**。
## 32×32 的树精灵占 2×2 格、必然互相重叠，所以这不是理论问题。
## 行优先（y 升序、同行 x 升序）之后，**近处（下方）的树压住远处（上方）的树**，重叠才读作纵深。
## 排序键是**全序**（y → x），不靠 `sort_custom` 的稳定性 —— 等价键会让结果随实现摇摆，
## 而 `--shot` 的逐字节可复现是本仓库的既有承诺（同 `_build_decor` 那条注释）。
func _build_tree_styles(wd: int) -> void:
	_tree_draw.clear()
	for tc in _tree_cells:
		_tree_draw.append(_tree_style(tc, wd))
	_tree_draw.sort_custom(func(a, b):
		var ca: Vector2i = a["cell"]
		var cb: Vector2i = b["cell"]
		return ca.y < cb.y if ca.y != cb.y else ca.x < cb.x)


## 从 map.json 的 walls/water/trees 建渲染集合（纯渲染；导航仍走 Sim 的 blockers 并集）。世界重载即失效。
func _build_terrain() -> void:
	_terrain_built = true
	_wall_set.clear(); _water_set.clear(); _tree_cells.clear(); _tree_set.clear(); _wall_type.clear()
	_water_by_slot.clear()
	var wd: int = int(Sim.world.get("width", 24))
	for c in Sim.world.get("walls", []):
		_wall_set[int(c[1]) * wd + int(c[0])] = true
	for c in Sim.world.get("water", []):
		_water_set[int(c[1]) * wd + int(c[0])] = true
	_build_water_slots(wd, int(Sim.world.get("height", 16)))
	for c in Sim.world.get("trees", []):
		_tree_cells.append(Vector2i(int(c[0]), int(c[1])))
		_tree_set[int(c[1]) * wd + int(c[0])] = true
	_build_tree_styles(wd)                    # V3 林相：每棵树的偏移/镜像/明暗档，一次算好（见 _tree_style）
	# 给每个墙格标上所属建筑【类型】（住宅/商业/公共/工坊）→ 墙面按类型上色。用 area.rect 的边框判定归属。
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var typ := String(a.get("type", "workshop"))
		if typ == "plaza":
			continue
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2]); var bh := int(r[3])
		for i in range(bw):
			_wall_type[(y0) * wd + (x0 + i)] = typ
			_wall_type[(y0 + bh - 1) * wd + (x0 + i)] = typ
		for j in range(bh):
			_wall_type[(y0 + j) * wd + x0] = typ
			_wall_type[(y0 + j) * wd + (x0 + bw - 1)] = typ

## P3 打磨：土路网——每家门口通到中央广场。L 形（先垂直离开建筑、再拐向广场），只铺在可走格上。
## 纯渲染（map.json 的 doors 层是渲染用、不进导航/digest）；装饰会避开土路，路面才干净。
func _build_paths() -> void:
	_paths_built = true
	_path_set.clear()
	_plaza_cells.clear()
	var areas: Dictionary = Sim.world.get("areas", {})
	# AP1(140)：所有 type=="plaza" 的区（广场 + 码头）都记成"已铺装"格 —— 石街的路缘石判邻、
	# verge 街具判"贴着铺装"都读它。**只读 areas[*].rect/type（Sim 也读的面），不写、不改** ⇒ 零金标。
	var wd0: int = int(Sim.world.get("width", 24))
	for aid0 in areas:
		var a0: Dictionary = areas[aid0]
		if String(a0.get("type", "")) != "plaza":
			continue
		var r0: Array = a0.get("rect", [0, 0, 0, 0])
		var ax0 := int(r0[0]); var ay0 := int(r0[1]); var aw0 := int(r0[2]); var ah0 := int(r0[3])
		for yy0 in range(ay0, ay0 + ah0):
			for xx0 in range(ax0, ax0 + aw0):
				_plaza_cells[yy0 * wd0 + xx0] = true
	if not areas.has("plaza"):
		return
	var pr: Array = (areas["plaza"] as Dictionary).get("rect", [0, 0, 0, 0])
	var px0 := int(pr[0]); var py0 := int(pr[1])
	var px1 := px0 + int(pr[2]) - 1; var py1 := py0 + int(pr[3]) - 1
	var wd: int = int(Sim.world.get("width", 24))
	var outdir := {"S": Vector2i(0, 1), "N": Vector2i(0, -1), "W": Vector2i(-1, 0), "E": Vector2i(1, 0)}
	for d in Sim.world.get("doors", []):
		var dp: Array = (d as Dictionary).get("pos", [0, 0])
		var od: Vector2i = outdir.get(String((d as Dictionary).get("face", "S")), Vector2i(0, 1))
		var cur := Vector2i(int(dp[0]), int(dp[1])) + od           # 门外第一格（不铺在门格本身）
		var gx: int = clampi(cur.x, px0, px1)                      # 广场最近的 x/y 带
		var gy: int = clampi(cur.y, py0, py1)
		while cur.y != gy:                                         # 竖腿：先离开建筑
			if not _is_blocked(cur.x, cur.y): _path_set[cur.y * wd + cur.x] = true
			cur.y += signi(gy - cur.y)
		while cur.x != gx:                                         # 横腿：再拐向广场
			if not _is_blocked(cur.x, cur.y): _path_set[cur.x + cur.y * wd] = true
			cur.x += signi(gx - cur.x)
		if not _is_blocked(cur.x, cur.y): _path_set[cur.y * wd + cur.x] = true
	# AP2(141) 码头连街：dock 这类【无门】的 plaza-type 区，本身已铺装(_plaza_cells)、却没有任何 door 路连过去，
	#   在整镇俯瞰里读作【孤岛】。给每个非主广场的 plaza-type 区补一条 View-only 连缀石街到主广场：
	#   与 door 路【同构】——只写 `_path_set`（Sim 不读它 ⇒ 零金标）、逐格 `_is_blocked` 跳过挡格，
	#   连缀格全落在已 walkable 的空地上（实测 dock→plaza 的 x32 / y9-20 走廊 0 挡格，见 docs/141 §连街网）。
	for aid2 in areas:
		if String(aid2) == "plaza":
			continue                                               # 主广场是连接【目标】，不给自己连
		var a2: Dictionary = areas[aid2]
		if String(a2.get("type", "")) != "plaza":
			continue
		var r2: Array = a2.get("rect", [0, 0, 0, 0])
		var cc := Vector2i(int(r2[0]) + int(r2[2]) / 2, int(r2[1]) + int(r2[3]) / 2)  # 区中心格（在 _plaza_cells 内）
		var tgx: int = clampi(cc.x, px0, px1)                      # 广场最近的 x/y 带（同 door 路的 clamp）
		var tgy: int = clampi(cc.y, py0, py1)
		while cc.y != tgy:                                         # 竖腿：从区中心朝广场推进（穿 y9-20 空地）
			if not _is_blocked(cc.x, cc.y): _path_set[cc.y * wd + cc.x] = true
			cc.y += signi(tgy - cc.y)
		while cc.x != tgx:                                         # 横腿：再对齐到广场带
			if not _is_blocked(cc.x, cc.y): _path_set[cc.x + cc.y * wd] = true
			cc.x += signi(tgx - cc.x)
		if not _is_blocked(cc.x, cc.y): _path_set[cc.y * wd + cc.x] = true

func _is_blocked(x: int, y: int) -> bool:
	if not _terrain_built:
		_build_terrain()
	var idx := y * int(Sim.world.get("width", 24)) + x
	if _wall_set.has(idx) or _water_set.has(idx):
		return true
	for c in _tree_cells:
		if c.x == x and c.y == y:
			return true
	return false

## AP1(140)：这一格是不是【已铺装】（石街 或 广场/码头）。石街画路缘石、verge 街具判邻都用它。
## 纯 View 派生（读 `_path_set`/`_plaza_cells`，二者皆由 `_build_paths` 从 map.json 只读烘出）。
func _is_paved(x: int, y: int) -> bool:
	var idx := y * int(Sim.world.get("width", 24)) + x
	return _path_set.has(idx) or _plaza_cells.has(idx)

## P2-4：每栋（非广场）沿顶墙悬挑一条 roof 色屋檐 + 门顶挂类型招牌图标。不铺满屋顶（否则遮住室内家具/居民）。
## AT1（编号148）：每栋建筑的确定性外观变体（0/1/2）。纯 f(建筑左上角格)，不抽 RNG/不读墙钟
## ⇒ --shot 逐像素可复现。用途：同类两栋楼的屋顶色各挑一档，读作"两栋不同的房子"而非"一个模子印两次"。
## ⚠️ 只动**屋顶/装饰**这一档；墙主面色 BLD_PAL[typ]["face/top/foot"] 一个字不碰——那是"四类一眼可分"的锚
##    （室内壳门 assert_interior_shell 采样的是室内墙、走 _draw_interior，与本层无关；本层是外景屋顶）。
func _bld_variant(x0: int, y0: int) -> int:
	return _hash(x0, y0, 91) % 3

## 屋顶色按建筑变体做小幅色相+明度偏移：留在类型的屋顶色系里（红瓦仍读红瓦），只让同类两栋分得开。
func _roof_variant(base: Color, v: int) -> Color:
	var c := base
	match v:
		1: c = Color.from_hsv(fmod(c.h - 0.028 + 1.0, 1.0), minf(1.0, c.s * 1.10), c.v * 0.84, c.a)   # 更沉·略偏暖（旧瓦）
		2: c = Color.from_hsv(fmod(c.h + 0.030, 1.0), c.s * 0.90, minf(1.0, c.v * 1.16), c.a)          # 晒亮·略偏冷（新瓦）
	return c

## AV1（编号156）：每栋的木构件（角柱/雨棚支柱）挑一档做旧木色，纯 f(建筑角格) ⇒ 同类两栋的木框也分得开。
## 全部由 X_WOOD_MID / P_COM_FOOT 派生（不新增字面量），留在暖木一族里——做旧/新木只差明暗，不换色相。
func _trim_wood(v: int) -> Color:
	match v:
		1: return X_WOOD_MID.darkened(0.20)     # 做旧深木
		2: return X_WOOD_MID.lightened(0.14)    # 晒白略亮
		3: return P_COM_FOOT                     # 深棕硬木
	return X_WOOD_MID                            # 常规木（v==0）

## 切顶俯视的屋檐带 → 画成有【瓦纹/受光屋脊/檐口投影/山墙收头】的坡屋顶。
## rect = 悬挑屋檐带。瓦纹逐片由 _hash(列,行) 定明暗（确定性），fit 缩放下瓦纹并作一片、屋脊/檐影/山墙读作体积。
## AV1（编号156）：在 AT1 的瓦纹上再加料 —— 三行错缝瓦（逐片带底影，读作一层压一层的叠瓦）+
##   一条【木脊梁盖】（比旧版单条高光更像真屋脊）+ 【受光/背光两端山墙】（不再是两端同暗，读出坡向）。
func _draw_pitched_roof(rect: Rect2, roof: Color) -> void:
	draw_rect(rect, roof, true)                                                       # 底瓦色
	var rows := 3                                                                     # 三行错缝瓦（旧两行）——瓦纹更密，读作叠瓦
	var rh := rect.size.y / float(rows)
	var tw := T * 0.40
	for rr in range(rows):
		var ry := rect.position.y + float(rr) * rh
		var off := (tw * 0.5) if rr % 2 == 1 else 0.0
		var cx := rect.position.x - off
		while cx < rect.end.x:
			var hh := _hash(int(floor(cx / tw)), rr, 61) % 3
			var tc := roof.lightened(0.13) if hh == 0 else (roof.darkened(0.17) if hh == 1 else roof)
			var w0 := maxf(0.0, minf(cx + tw - 1.0, rect.end.x) - maxf(cx, rect.position.x))
			if w0 > 0.0:
				draw_rect(Rect2(maxf(cx, rect.position.x), ry, w0, rh - 1.0), tc, true)
				draw_rect(Rect2(maxf(cx, rect.position.x), ry + rh - 2.0, w0, 1.5), roof.darkened(0.30), true)  # 每片瓦底影 → 一层压一层
			cx += tw
	# 屋脊：受光高光带 + 一条木脊梁盖（深木）+ 梁下沿高光——三层叠出"顶上有根脊梁"
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, T * 0.09), roof.lightened(0.36), true)          # 脊侧受光
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, T * 0.05), P_COM_FOOT, true)                    # 脊梁（深木盖）
	draw_rect(Rect2(rect.position.x, rect.position.y + T * 0.05, rect.size.x, 1.5), X_WOOD_MID.lightened(0.10), true)  # 脊梁下沿高光
	draw_rect(Rect2(rect.position.x, rect.end.y - T * 0.10, rect.size.x, T * 0.10), roof.darkened(0.34), true)     # 檐口投影
	# 山墙收头：左端受光、右端背光（光从左上来，与墙面顶棱/左棱高光同一套光向）⇒ 读出坡屋顶的两个斜面
	draw_colored_polygon(PackedVector2Array([rect.position, Vector2(rect.position.x + T * 0.28, rect.position.y), Vector2(rect.position.x, rect.end.y)]), roof.lightened(0.20))
	draw_colored_polygon(PackedVector2Array([Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - T * 0.28, rect.position.y), Vector2(rect.end.x, rect.end.y)]), roof.darkened(0.26))

## 商业遮阳篷：条纹布棚（类型信号）+ 顶棱高光 + 扇贝檐边（valance）+ 两端木支柱 → 读作真的支起来的店铺雨棚。
## AV1（编号156）：条纹深色按建筑变体挑（红/蓝/暖金），亮条恒为奶白——对齐参考里集市三顶不同色的布棚，
##   让两家商业（咖啡馆/杂货铺）的雨棚一眼分得开；深色三档都由已授权常量派生，不新增字面量。
func _draw_awning(eave: Rect2, pal: Dictionary, bw: int, v: int) -> void:
	var accent: Color = pal["roof"]                     # v==0：红（默认商业）
	match v:
		1: accent = P_PUB_ROOF                          # 蓝白（另一家店：读作不同铺面）
		2: accent = X_GLOW_DEEP.darkened(0.10)          # 暖金白
	var light: Color = P_TEXT                           # 亮条（奶白）
	var n := bw * 2
	var stripe := eave.size.x / float(n)
	for s in range(n):
		var col: Color = accent if s % 2 == 0 else light
		var sx := eave.position.x + float(s) * stripe
		draw_rect(Rect2(sx, eave.position.y, stripe + 1.0, eave.size.y), col, true)
		# 扇贝檐边：每条布幅底沿挂一枚半圆凸缘，读作垂布
		draw_circle(Vector2(sx + stripe * 0.5, eave.end.y), stripe * 0.5, col)
	draw_rect(Rect2(eave.position.x, eave.position.y, eave.size.x, T * 0.08), light.lightened(0.06), true)        # 顶棱高光（布面受光）
	draw_rect(Rect2(eave.position.x, eave.position.y, eave.size.x, eave.size.y), Color(0, 0, 0, 0.14), false, 1.0) # 外框描边
	# 两端支柱：木杆从檐角垂到墙面 → 读作把布棚支起来的柱子（参考里每顶集市棚都有）
	for pxx in [eave.position.x + stripe * 0.5, eave.end.x - stripe * 0.5]:
		draw_rect(Rect2(pxx - T * 0.03, eave.end.y - T * 0.02, T * 0.06, T * 0.30), X_WOOD_MID, true)
		draw_rect(Rect2(pxx - T * 0.03, eave.end.y - T * 0.02, T * 0.02, T * 0.30), X_WOOD_MID.lightened(0.20), true)  # 受光棱

## AV1（编号156）：木构角框 —— 左右两条【竖角板】（贴最外缘薄板，避开内缩≥0.10T 的窗扇）把整栋"框起来"，
##   四角再压【加宽木块】（角格永不开窗，可宽）+ 底排【石柱脚】。这是把大片平板墙面读成"木构建筑"的关键笔画：
##   参考里每栋都靠这对深木角柱 + 石脚把屋顶撑在石基上。柱头塞在屋檐下（dressing 里屋顶画在其后 ⇒ 屋顶坐在柱上）。
func _draw_corner_posts(x0: int, y0: int, bw: int, bh: int, wood: Color) -> void:
	var lit := wood.lightened(0.22)
	var shd := wood.darkened(0.34)
	var top := float(y0) * T + T * 0.24                 # 顶端塞屋檐下
	var bot := float(y0 + bh) * T                        # 到石基
	# 左右两条竖角板（薄，贴最外缘 ⇒ 让木框从檐下一路连到石脚）
	var bwid := T * 0.12
	for cxg in [x0, x0 + bw - 1]:
		var ex := float(cxg) * T if cxg == x0 else float(cxg + 1) * T - bwid
		draw_rect(Rect2(ex, top, bwid, bot - top), wood, true)
		draw_rect(Rect2(ex, top, bwid * 0.5, bot - top), lit, true)                     # 受光竖棱
	# 四角加宽木块 + 底排石柱脚
	var pw := T * 0.30
	for cyg in [y0, y0 + bh - 1]:
		var cy0 := float(cyg) * T + (T * 0.24 if cyg == y0 else 0.0)
		var cy1 := float(cyg + 1) * T
		for cxg in [x0, x0 + bw - 1]:
			var px := float(cxg) * T if cxg == x0 else float(cxg + 1) * T - pw
			draw_rect(Rect2(px, cy0, pw, cy1 - cy0), wood, true)                        # 角柱身
			draw_rect(Rect2(px, cy0, pw * 0.34, cy1 - cy0), lit, true)                  # 受光竖棱
			draw_rect(Rect2(px + pw * 0.78, cy0, pw * 0.22, cy1 - cy0), shd, true)      # 背光竖棱
			if cyg == y0 + bh - 1:                       # 底排：石柱脚
				draw_rect(Rect2(px - 1.0, cy1 - T * 0.14, pw + 2.0, T * 0.14), P_STONE, true)
				draw_rect(Rect2(px - 1.0, cy1 - T * 0.14, pw + 2.0, 1.5), P_STONE_LINE, true)

## AV1（编号156）：底墙下段一条【错缝石基】（皮数线 + 砌块缝）→ 让建筑"坐"在石头地基上，不像浮在草上。
## 只压底墙那一行的最下 ~T*0.26（在窗洞之下、门槛之上，留在建筑轮廓内 ⇒ 不碰地面/岸线/林块采样格）。
func _draw_foundation(x0: int, y0: int, bw: int, bh: int) -> void:
	var fx := float(x0) * T
	var fwd := float(bw) * T
	var fy := float(y0 + bh) * T - T * 0.26
	draw_rect(Rect2(fx, fy, fwd, T * 0.26), P_STONE, true)                              # 石基主面
	draw_rect(Rect2(fx, fy, fwd, T * 0.07), P_STONE.lightened(0.12), true)             # 顶棱受光
	draw_rect(Rect2(fx, fy + T * 0.20, fwd, T * 0.06), P_STONE.darkened(0.18), true)   # 底影
	draw_line(Vector2(fx, fy + T * 0.13), Vector2(fx + fwd, fy + T * 0.13), P_STONE_LINE, 1.0)  # 皮数线
	var bwd := T * 0.72                                                                 # 砌块宽
	var sx := fx
	var k := 0
	while sx < fx + fwd:
		var seam := sx + (bwd * 0.5 if k % 2 == 1 else 0.0)                             # 错缝
		if seam > fx and seam < fx + fwd:
			draw_line(Vector2(seam, fy), Vector2(seam, fy + T * 0.26), P_STONE_LINE, 1.0)
		sx += bwd
		k += 1

## AV1（编号156）：先压【石基 + 四角木柱】（读作木构建筑坐在石头地基上），再压屋顶（盖住柱头 = 屋顶坐在柱上），
##   最后挂招牌 + 入口提灯（夜里点亮）。木柱/雨棚色按建筑变体挑一档 ⇒ 同类两栋的木框与布棚都分得开。
func _draw_building_dressing(w: int) -> void:
	var tod := Sim.time_of_day()
	var night := tod < 0.24 or tod > 0.78
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var typ := String(a.get("type", ""))
		if typ == "" or typ == "plaza":
			continue
		var pal: Dictionary = BLD_PAL.get(typ, BLD_PAL["workshop"])
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2]); var bh := int(r[3])
		var v := _bld_variant(x0, y0)
		var roof: Color = _roof_variant(pal["roof"], v)
		var wood: Color = _trim_wood(_hash(x0, y0, 93) % 4)
		_draw_foundation(x0, y0, bw, bh)                # 石基（底墙下段）
		_draw_corner_posts(x0, y0, bw, bh, wood)        # 四角木柱（顶端塞屋檐下）
		var eave := Rect2(x0 * T - T * 0.12, y0 * T - T * 0.16, bw * T + T * 0.24, T * 0.46)  # 悬挑屋檐
		if typ == "commercial":                         # 商业：坡屋脊 + 条纹遮阳篷（最醒目的类型信号，色按变体挑）
			_draw_pitched_roof(Rect2(eave.position.x, eave.position.y - T * 0.14, eave.size.x, T * 0.24), roof)
			_draw_awning(eave, pal, bw, v)
		else:
			_draw_pitched_roof(eave, roof)
		_draw_sign(typ, pal, (x0 + bw * 0.5) * T, y0 * T - T * 0.5, night)

## AV1（编号156）：招牌两侧加一对檐下提灯（夜里点亮、白天是熄灯的铜灯）—— 参考里几乎每栋入口都挂灯。
##   night 由 dressing 现算传入（Sim.time_of_day 确定性，与 facades 同一判据）；灯芯色由 X_GLOW* 派生。
func _draw_sign(typ: String, pal: Dictionary, cx: float, cy: float, night: bool = false) -> void:
	for lxo in [-T * 0.44, T * 0.44]:                                                     # 招牌两侧各挂一盏
		var lx: float = cx + lxo
		var lyc: float = cy + T * 0.04
		draw_rect(Rect2(lx - T * 0.015, cy - T * 0.16, T * 0.03, T * 0.16), X_WOOD_MID, true)   # 挂杆
		if night:
			draw_circle(Vector2(lx, lyc), T * 0.16, Color(X_GLOW, 0.28))                        # 夜里暖光晕
		draw_rect(Rect2(lx - T * 0.05, lyc - T * 0.05, T * 0.10, T * 0.13), D_WOOD_LINE, true)  # 灯框
		draw_rect(Rect2(lx - T * 0.034, lyc - T * 0.03, T * 0.068, T * 0.09), X_GLOW if night else X_GLOW_DEEP.darkened(0.30), true)  # 灯芯
	match typ:
		"commercial":                                   # 挂牌 + 咖啡杯 + 蒸汽（悬挑吊牌）
			draw_rect(Rect2(cx - T * 0.03, cy - T * 0.40, T * 0.06, T * 0.16), X_WOOD_MID, true)   # 吊杆
			draw_rect(Rect2(cx - T * 0.26, cy - T * 0.20, T * 0.52, T * 0.30), X_WOOD_MID, true)   # 牌底框
			draw_rect(Rect2(cx - T * 0.22, cy - T * 0.16, T * 0.44, T * 0.22), P_TEXT, true)       # 牌面
			draw_rect(Rect2(cx - T * 0.11, cy - T * 0.12, T * 0.22, T * 0.16), X_WOOD_MID, true)   # 咖啡杯身
			draw_rect(Rect2(cx - T * 0.11, cy - T * 0.12, T * 0.22, T * 0.04), pal["roof"], true)  # 杯口
			draw_circle(Vector2(cx + T * 0.15, cy - T * 0.04), T * 0.05, X_WOOD_MID)               # 杯把
			draw_circle(Vector2(cx, cy - T * 0.20), T * 0.04, Color(1, 1, 1, 0.55))               # 蒸汽
		"public":                                       # ♨ 蓝底温泉标（澡堂）：蓝圆盘 + 三缕上升蒸汽
			draw_rect(Rect2(cx - T * 0.03, cy - T * 0.42, T * 0.06, T * 0.14), X_WOOD_MID, true)   # 吊杆
			draw_circle(Vector2(cx, cy), T * 0.25, X_WOOD_MID)                                     # 牌框
			draw_circle(Vector2(cx, cy), T * 0.22, pal["roof"])
			draw_circle(Vector2(cx, cy), T * 0.22, (pal["roof"] as Color).lightened(0.3), false, 2.0)
			for k in range(3):
				draw_rect(Rect2(cx - T * 0.14 + float(k) * T * 0.13, cy - T * 0.02, T * 0.05, T * 0.14), pal["icon"], true)
		"workshop":                                     # 铁砧 + 锤（工坊的身份，比"烟囱图标"更认得出——真烟囱在 _draw_facades 上）
			draw_rect(Rect2(cx - T * 0.20, cy - T * 0.02, T * 0.40, T * 0.14), P_WRK_ROOF, true)   # 砧身
			draw_rect(Rect2(cx - T * 0.11, cy + T * 0.12, T * 0.22, T * 0.06), P_WRK_ROOF.darkened(0.3), true)  # 砧座
			draw_rect(Rect2(cx + T * 0.06, cy - T * 0.06, T * 0.16, T * 0.05), (pal["top"] as Color).lightened(0.2), true)  # 砧尖
			draw_rect(Rect2(cx - T * 0.20, cy - T * 0.24, T * 0.06, T * 0.22), X_WOOD_MID, true)   # 锤柄
			draw_rect(Rect2(cx - T * 0.26, cy - T * 0.28, T * 0.18, T * 0.09), P_WRK_ROOF.lightened(0.25), true)  # 锤头
		"residential":                                  # 山墙小屋剪影 + 烟囱（暖木门牌）
			draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - T * 0.34), Vector2(cx - T * 0.28, cy - T * 0.04), Vector2(cx + T * 0.28, cy - T * 0.04)]), pal["roof"])
			draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - T * 0.34), Vector2(cx - T * 0.28, cy - T * 0.04), Vector2(cx - T * 0.06, cy - T * 0.04)]), (pal["roof"] as Color).lightened(0.22))  # 受光坡
			draw_rect(Rect2(cx - T * 0.14, cy - T * 0.04, T * 0.28, T * 0.14), X_WOOD_MID, true)   # 墙身
			draw_rect(Rect2(cx - T * 0.04, cy + T * 0.00, T * 0.08, T * 0.10), X_GLOW_DEEP, true)  # 暖门
			draw_rect(Rect2(cx + T * 0.06, cy - T * 0.44, T * 0.09, T * 0.16), X_WOOD_MID, true)   # 烟囱

## P3 打磨：外墙细节——沿上/下墙等距开窗（跳过转角与门口），住宅/工坊再加一根冒烟的烟囱。
## 夜里窗透暖光（tod 判昼夜）→ 一眼看出"屋里有人住"。纯渲染、无 RNG（位置由 rect 等距推出）。
func _draw_facades() -> void:
	var doorset := {}
	for d in Sim.world.get("doors", []):
		var dp: Array = (d as Dictionary).get("pos", [0, 0])
		doorset[Vector2i(int(dp[0]), int(dp[1]))] = true
	var tod := Sim.time_of_day()
	var night := tod < 0.24 or tod > 0.78
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var typ := String(a.get("type", ""))
		if typ == "" or typ == "plaza":
			continue
		var pal: Dictionary = BLD_PAL.get(typ, BLD_PAL["workshop"])
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2]); var bh := int(r[3])
		for i in range(1, bw - 1):                       # 跳过两端转角
			if i % 2 == 0:
				continue                                 # 等距（隔一格）开窗
			for wy in [y0, y0 + bh - 1]:                 # 上墙 + 下墙
				if doorset.has(Vector2i(x0 + i, wy)):
					continue                             # 门口不开窗
				var fl := typ == "residential" and _hash(x0 + i, wy, 88) % 2 == 0   # 住宅约半数窗挂花箱（确定性）
				_draw_window((x0 + i) * T, wy * T, pal, night and _window_lit(x0 + i, wy), night, fl)
		for j in range(1, bh - 1):                       # 左墙 + 右墙（四面都开，别只有正背面有细节）
			if j % 2 == 0:
				continue
			for wx in [x0, x0 + bw - 1]:
				if doorset.has(Vector2i(wx, y0 + j)):
					continue
				_draw_window(wx * T, (y0 + j) * T, pal, night and _window_lit(wx, y0 + j), night)
		if typ == "residential" or typ == "workshop":    # 烟囱：坐在顶墙右段，飘炊烟
			_draw_chimney(float(x0 + bw - 2) * T + T * 0.28, float(y0) * T - T * 0.52, x0, y0)

## AT1（编号148）：砖砌烟囱 + 【确定性炊烟】。
## 炊烟位置/半径/透明度只由 _hash(建筑左上角,71) 定相位 + Sim.tick_no 推进（禁 randi / 禁 Time.*）——
##   同一 tick 重拍逐像素相同，--shot 冻结 tick 时炊烟不抖（precip 层同款纪律）。
##   三团烟沿一个上升周期错相循环：起步淡→中段浓→升高侧漂并淡出，读作"屋里生着火"。
func _draw_chimney(bx: float, by: float, x0: int, y0: int) -> void:
	# 砖砌烟囱：主体 + 帽檐 + 两道砖缝
	draw_rect(Rect2(bx, by, T * 0.40, T * 0.52), X_WOOD_MID, true)                                  # 砖身
	draw_rect(Rect2(bx - T * 0.04, by - T * 0.06, T * 0.48, T * 0.12), P_COM_FOOT, true)            # 帽檐
	draw_line(Vector2(bx, by + T * 0.20), Vector2(bx + T * 0.40, by + T * 0.20), P_COM_FOOT, 1.0)   # 砖缝
	draw_line(Vector2(bx, by + T * 0.38), Vector2(bx + T * 0.40, by + T * 0.38), P_COM_FOOT, 1.0)
	# 炊烟：三团，沿一个上升周期错相循环
	var tx := bx + T * 0.20
	var ty := by - T * 0.08
	var ph0 := _hash(x0, y0, 71) % 100
	var cyc := 48
	for k in range(3):
		var ph := (Sim.tick_no + ph0 + k * 16) % cyc
		var t := float(ph) / float(cyc)                                    # 0..1 上升进度
		var drift := sin(t * TAU + float(ph0)) * T * 0.22                  # 侧向漂移
		var px := tx + drift + (float(k) - 1.0) * T * 0.05
		var py := ty - t * T * 1.15                                         # 越升越高
		var rad := T * (0.09 + 0.11 * t)                                    # 越升越大
		var al := 0.44 * (1.0 - t) * (0.45 + 0.55 * t)                      # 起淡·中浓·顶淡
		draw_circle(Vector2(px, py), rad, Color(0.86, 0.86, 0.85, al))

## `lit` = 这扇窗**点着灯**（夜里约 55%，由 `_window_lit` 确定性选）；`night` = 现在是夜。
## 改动前所有夜窗一律画成 `#f2d489`，而它被夜乘子乘过之后是 **(103,100,109)——蓝主导，读作冷灰**。
## 那正是"夜里零个光源"的成因之一：暖色玻璃在纸面上是暖的，在屏幕上不是。
## 现在分成两档：亮着的窗给更饱和的暖玻璃（配合加色光层的光池），黑着的窗给冷暗玻璃 ⇒
## 一排窗有明有暗，才读得出"有几户还醒着"。白天两档都不走，正午帧逐像素不动。
func _draw_window(x: float, y: float, pal: Dictionary, lit: bool, night: bool, flower: bool = false) -> void:
	var glass: Color = P_WATER                                  # 昼=映天色
	if night:
		glass = X_GLOW if lit else P_WRK_ROOF            # 夜：点灯=暖玻璃 / 熄灯=冷暗玻璃
	# 百叶木窗扇：窗洞两侧各挂一板（比墙脚略深 + 一道亮竖缝当百叶），读作可开合的窗——纯装饰
	var sh: Color = (pal["foot"] as Color).darkened(0.06)
	var shl: Color = (pal["top"] as Color).lightened(0.10)
	for sxo in [T * 0.10, T * 0.78]:
		draw_rect(Rect2(x + sxo, y + T * 0.22, T * 0.12, T * 0.48), sh, true)
		draw_line(Vector2(x + sxo + T * 0.06, y + T * 0.26), Vector2(x + sxo + T * 0.06, y + T * 0.66), shl, 1.0)
	draw_rect(Rect2(x + T * 0.22, y + T * 0.24, T * 0.56, T * 0.44), pal["foot"], true)            # 窗洞（深）
	draw_rect(Rect2(x + T * 0.26, y + T * 0.28, T * 0.48, T * 0.36), glass, true)                  # 玻璃
	if lit:
		draw_rect(Rect2(x + T * 0.16, y + T * 0.18, T * 0.68, T * 0.56), Color(X_GLOW, 0.15), true)  # 外溢暖光
	draw_line(Vector2(x + T * 0.5, y + T * 0.28), Vector2(x + T * 0.5, y + T * 0.64), pal["foot"], 1.5)        # 竖棂
	draw_line(Vector2(x + T * 0.26, y + T * 0.46), Vector2(x + T * 0.74, y + T * 0.46), pal["foot"], 1.5)      # 横棂
	draw_rect(Rect2(x + T * 0.22, y + T * 0.24, T * 0.56, T * 0.44), (pal["top"] as Color).lightened(0.18), false, 1.5)  # 窗框
	if flower:                                                                                     # 窗台花箱（住宅魅力）：木槽 + 三簇花
		draw_rect(Rect2(x + T * 0.20, y + T * 0.66, T * 0.60, T * 0.14), X_WOOD_MID, true)
		draw_rect(Rect2(x + T * 0.20, y + T * 0.66, T * 0.60, T * 0.05), P_FOLIAGE_D, true)          # 叶
		for fk in range(3):
			draw_circle(Vector2(x + T * (0.30 + 0.20 * float(fk)), y + T * 0.66), T * 0.055, [P_RES_ROOF, X_GLOW, P_PUB_ROOF][fk])

## 本帧的可见世界矩形 + 世界→屏幕缩放（纯读画布变换）。裁剪与标签 LOD 都吃它。
## ★这是【画】的裁剪，不是【算】的裁剪：Sim 看不到它，lod_verify 的相机无关门因此不受影响。
func _refresh_view_metrics() -> void:
	var ct := get_global_transform_with_canvas()
	var sc := ct.get_scale()
	_zoom = maxf(0.0001, (absf(sc.x) + absf(sc.y)) * 0.5)
	var inv := ct.affine_inverse()
	var vs: Vector2 = get_viewport_rect().size
	var r := Rect2(inv * Vector2.ZERO, Vector2.ZERO)
	r = r.expand(inv * Vector2(vs.x, 0.0)).expand(inv * Vector2(0.0, vs.y)).expand(inv * vs)
	_vis = r.grow(T * 2.0)          # 留两格余量：贴边的精灵/连线不会在边缘闪掉

## 每个 district 铺【真地板】：dirt 瓦片打底（保住 3x 像素颗粒，纯色地板在像素游戏里读作"没画完"）
## → 类型底色半透盖上 → 类型纹样（木条 / 石板 / 铺装）→ 内缘压暗让地板"沉"进墙里。
## 只读 Sim.world['areas']，不改 game/data/**、不造房间。
func _draw_area_floors(dirt: Texture2D) -> void:
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2]); var bh := int(r[3])
		if bw <= 0 or bh <= 0:
			continue
		var rect := Rect2(x0 * T, y0 * T, bw * T, bh * T)
		if not _vis.intersects(rect):
			continue
		var atype := String(a.get("type", ""))
		var pal: Dictionary = FLOOR_PAL.get(atype, FLOOR_PAL["workshop"])
		var base: Color = pal["base"]
		var line: Color = pal["line"]
		# ── AV3(161) 户外暖石【就地覆盖】：广场(paving)/工坊石(slab) 换到暖灰石族，室内地板/货袋/石基逐字节不动
		#   （不碰 P_PLAZA/P_STONE 常量——见调色板 G_*_WARM 段的克制说明）。public(冷澡堂/图书馆) 与
		#   res/com(暖木) 保持原样：它们不是"该暖的石地面"，且动它们会挤 INTSHELL/floor 门的关系余量。
		var warm_stone := false
		if atype == "plaza":
			base = G_PLAZA_WARM; line = G_PLAZA_LINE; warm_stone = true
		elif atype == "workshop":
			base = G_STONE_WARM; line = G_STONE_LINE; warm_stone = true
		if dirt != null:
			for yy in range(y0, y0 + bh):
				for xx in range(x0, x0 + bw):
					draw_texture_rect(dirt, Rect2(xx * T, yy * T, T, T), false)
			draw_rect(rect, Color(base.r, base.g, base.b, 0.80), true)
		else:
			draw_rect(rect, base, true)
		match String(pal["mode"]):
			"plank":                                   # 木地板：半格宽长板 + 错缝短接头
				var py := rect.position.y
				var row := 0
				while py < rect.end.y - 1.0:
					draw_rect(Rect2(rect.position.x, py, rect.size.x, 1.0), Color(line.r, line.g, line.b, 0.50), true)
					var sx := rect.position.x + (T * 0.5 if row % 2 == 1 else 0.0) + T
					while sx < rect.end.x - 1.0:
						draw_rect(Rect2(sx, py, 1.0, T * 0.5), Color(line.r, line.g, line.b, 0.34), true)
						sx += T * 1.5
					py += T * 0.5
					row += 1
			"slab":                                    # 石板：交错明暗方砖 + 横竖石缝
				if warm_stone:
					# AV3(161) 工坊户外石：逐格【确定性】暖石明暗（_hash(x,y,47)，无 RNG/Time ⇒ ROUNDTRIP 冻结帧可复现）。
					#   多数格保持 base、少数抬亮/压暗成"亮石/暗石"，读作铺过的暖石而非一块死灰。石缝沿用暖 line。
					for yy in range(bh):
						for xx in range(bw):
							var wc := _hash(x0 + xx, y0 + yy, 47) % 6   # 0-5：0 亮石 / 1 暗石 / 2 微亮，其余保持 base（变化才 subtle）
							if wc <= 2:
								var sc: Color = G_STONE_HI if wc == 0 else (G_STONE_LO if wc == 1 else G_STONE_WARM.lightened(0.05))
								draw_rect(Rect2(rect.position.x + xx * T + 1.0, rect.position.y + yy * T + 1.0, T - 2.0, T - 2.0), Color(sc.r, sc.g, sc.b, 0.34), true)
						draw_rect(Rect2(rect.position.x, rect.position.y + yy * T, rect.size.x, 1.0), Color(line.r, line.g, line.b, 0.42), true)
					for xx in range(bw):
						draw_rect(Rect2(rect.position.x + xx * T, rect.position.y, 1.0, rect.size.y), Color(line.r, line.g, line.b, 0.32), true)
				else:                                  # public(冷石板)：原样保留，逐字节不动
					for yy in range(bh):
						for xx in range(bw):
							if (xx + yy) % 2 == 0:
								draw_rect(Rect2(rect.position.x + xx * T, rect.position.y + yy * T, T, T), Color(1, 1, 1, 0.08), true)
						draw_rect(Rect2(rect.position.x, rect.position.y + yy * T, rect.size.x, 1.0), Color(line.r, line.g, line.b, 0.42), true)
					for xx in range(bw):
						draw_rect(Rect2(rect.position.x + xx * T, rect.position.y, 1.0, rect.size.y), Color(line.r, line.g, line.b, 0.32), true)
			_:                                         # 广场：大方砖十字缝（比土路"踩实"，两者可区分）
				# AP1(140) flagstone：2×2 大方砖交错明暗 + 十字灌浆缝 + 亮内沿（纯 View 上色，Sim 零读 type ⇒ 零金标）。
				# 石街鹅卵石(2×2 细分)汇入广场 flagstone(2×2 大块) ⇒ 同一套铺装语言、读作“街—广场”一体。
				# ★ AV3(161)：flagstone 换到暖石族 G_PLAZA_*（base 已就地覆盖为 G_PLAZA_WARM），并给【每块大方砖】
				#   叠一档【确定性】暖/沉 jitter（_hash(块坐标,48)），让广场从"一片均匀砂"变成"铺过的暖石广场"——
				#   仍留最亮档在 base 上 ⇒ 广场依旧是全镇最亮地面=社交焦点（保 docs 要的可读焦点）。
				for yy in range(bh):
					for xx in range(bw):
						var blk := ((xx / 2) + (yy / 2)) % 2          # 2×2 一块大石板，整块一个明/暗档
						var fc: Color = G_PLAZA_HI if blk == 0 else G_PLAZA_LO
						var jt := _hash(x0 + xx / 2, y0 + yy / 2, 48) % 4   # 每块大方砖再抖一档：0 更亮 / 1 更沉 / 其余不动
						if jt == 0: fc = fc.lightened(0.07)
						elif jt == 1: fc = fc.darkened(0.08)
						draw_rect(Rect2(rect.position.x + xx * T + 1.0, rect.position.y + yy * T + 1.0, T - 2.0, T - 2.0), Color(fc.r, fc.g, fc.b, 0.30), true)
				for yy in range(bh):
					draw_rect(Rect2(rect.position.x, rect.position.y + yy * T, rect.size.x, 1.0), Color(line.r, line.g, line.b, 0.30), true)
				for xx in range(bw):
					draw_rect(Rect2(rect.position.x + xx * T, rect.position.y, 1.0, rect.size.y), Color(line.r, line.g, line.b, 0.30), true)
				draw_rect(rect, Color(G_PLAZA_HI.r, G_PLAZA_HI.g, G_PLAZA_HI.b, 0.35), false, 2.0)   # 亮内沿：框住广场、接住汇入的石街
				if String(aid) == "plaza":
					_draw_plaza_medallion(rect)   # AP2(141) 只给【主广场】加中心徽章（dock 也是 plaza 型，但它是码头不是镇心）
		draw_rect(rect, Color(0, 0, 0, 0.20), false, 3.0)

## 区名：旧版画在 rect 左上角、字号 12、alpha 0.28 —— 那格正好是顶墙，墙随后盖上去，于是【一个字也看不见】。
## 现在画在墙之后、地板第一行上，并把字号按缩放反比放大 → 缩到全镇俯瞰时区名仍读得出来（这才是"地图可读"）。
func _draw_area_labels() -> void:
	var fnt := Art.font()
	var fs := int(clampf(13.0 / _zoom, 13.0, 52.0))
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var r: Array = a.get("rect", [0, 0, 0, 0])
		if int(r[2]) <= 0 or int(r[3]) <= 0:
			continue
		var rect := Rect2(int(r[0]) * T, int(r[1]) * T, int(r[2]) * T, int(r[3]) * T)
		if not _vis.intersects(rect):
			continue
		var txt := str(a.get("label", aid))
		var sz := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p := Vector2(rect.get_center().x - sz.x * 0.5, rect.position.y + T * 1.10 + sz.y * 0.5)
		draw_rect(Rect2(p.x - 6.0, p.y - sz.y + 2.0, sz.x + 12.0, sz.y + 3.0), Color(0, 0, 0, 0.42), true)
		draw_string(fnt, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.82))

func _in_area(x: int, y: int) -> bool:
	for a in Sim.world.get("areas", {}).values():
		var r: Array = a.get("rect", [0, 0, 0, 0])
		if x >= int(r[0]) and x < int(r[0]) + int(r[2]) and y >= int(r[1]) and y < int(r[1]) + int(r[3]):
			return true
	return false

func _is_object(x: int, y: int) -> bool:
	for o in Sim.world.get("objects", {}).values():
		if int(o["pos"].x) == x and int(o["pos"].y) == y:
			return true
	return false

func _on_social(e: Dictionary) -> void:
	var key := _emote_key(e)
	var t := Art.emote_tex(key)
	if t != null:
		var until := Sim.tick_no + EMOTE_TICKS
		_emote[e["actor"]] = {"tex": t, "until": until}
		if String(e.get("target", "")) != "":
			_emote[e["target"]] = {"tex": t, "until": until}
	_set_dialogue(e)
	queue_redraw()

## 交谈台词：真模型(llm/slm)下优先显示决策生成的真台词；logic 模式用类型化罐头库（变化更丰富）。
func _set_dialogue(e: Dictionary) -> void:
	var t := String(e["type"])
	var actor := String(e["actor"])
	var target := String(e.get("target", ""))
	var until := Sim.tick_no + SAY_TICKS
	var actor_set := false
	# 发起者决策台词优先顶上气泡：llm/slm=模型实时生成；logic=Sim._canned_say（冻结·70B 语音库→人设台词，缺库回落通用罐头）。
	# 有词就用它、覆盖 DIALOG 类型化罐头；为空才回落 DIALOG。（WorldView 是纯视图，动不了 digest。）
	var ls := String(Sim.get_agent(actor).get("last_say", "")).strip_edges()
	if ls != "":
		_say[actor] = {"text": ls, "until": until}
		actor_set = true
	if not DIALOG.has(t):
		return
	var bank: Dictionary = DIALOG[t]
	var ok := bool(e["accepted"])
	if t == "meet" and not ok:
		if not actor_set:
			var fl := _pick(bank.get("fail", []), actor)
			if fl != "":
				_say[actor] = {"text": fl, "until": until}
		return
	if not actor_set:
		var il := _pick(bank.get("init", []), actor)
		if il != "":
			_say[actor] = {"text": il, "until": until}
	if target != "":
		var rl := _pick(bank.get("yes" if ok else "no", []), target)
		if rl != "":
			_say[target] = {"text": rl, "until": until}

func _pick(arr: Array, who: String) -> String:
	if arr.is_empty():
		return ""
	return String(arr[_hash(who.hash(), Sim.tick_no, 5) % arr.size()])

## 供 Main 在玩家对话时把 NPC 回复显示为头顶气泡（停留更久）。
func show_say(id: String, text: String, ticks: int = 60) -> void:
	_say[id] = {"text": text, "until": Sim.tick_no + ticks}
	queue_redraw()

func _emote_key(e: Dictionary) -> String:
	var t := String(e["type"])
	var ok := bool(e["accepted"])
	match t:
		"meet": return "meet_fulfilled" if ok else "meet_broken"
		"confront": return "confront" if ok else "conflict"
		"apologize": return "apologize_ok" if ok else "apologize_no"
		"conflict": return "conflict"
		_: return t   # greet/give/gossip/invite

## 由移动推断行走帧 {col,row,flip}：横向走用 down 行 + 水平翻转(左)，上走=row3，静止=正面 idle 缓慢呼吸。
var _facing_left := {}
## 行走帧/朝向。★这里【不再有副作用】——朝向与 _prev_pos 的推进整体搬到了 _process()。
## 原因：加插值后 _draw 从"每 tick 一次"变成"每帧一次"，而旧实现是在 _draw 里做 pos 差分并
## 就地更新 _prev_pos，于是移动后的第 2 帧起差分恒为零 → 居民一边滑行一边播 idle（动画反而更糟）。
## 现在"是否在走"= 渲染坐标是否还在追格心（_moving），动画与插值同寿。
func _agent_frame(ag: Dictionary) -> Dictionary:
	var id := String(ag["id"])
	var flip := bool(_facing_left.get(id, false))
	if not bool(_moving.get(id, false)):
		return {"col": int(Sim.tick_no / 16.0) % 4, "row": 0, "flip": flip}  # idle 微动，保留上次朝向
	return {"col": Sim.tick_no % 4, "row": int(_walk_row.get(id, 1)), "flip": flip}

## P1：Probe 切到非 town 的 Space 时，画该 Space/Floor 的占位（bounds + 楼层 + Portal 锚点）。
## 诚实边界：test_loft 没有内容——这里只证明"active Space/Floor 渲染与 hit-test 走得通"，
## 不假装它是一栋建筑。真内容在 P3（阿丽咖啡馆 1F/2F）按同一合同长出来。
func _load_interiors() -> void:
	_interiors_loaded = true
	if not FileAccess.file_exists("res://data/interiors.json"):
		return
	var f := FileAccess.open("res://data/interiors.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		_interiors = d

## 室内背景。一层至多 432x336 px，塞进 1280x768 后四周是一大片【默认 clear color 的死灰】
## （docs/media/shot-p3-patrons-cafe.png 里那条灰带就是它）。铺暗底 + 四周暗角 + 房子外圈落影 + 极淡暖边，
## 读法变成"镜头在屋外的暗处往里看"，而不是"一个方块浮在空白画布上"。纯 View。
func _draw_interior_backdrop(main: Node, probe) -> void:
	draw_rect(_vis, D_BACKDROP, true)
	# 暗角：由外向内 6 圈，越外越沉（随后室内地板会不透明地盖回中间，暗角只作用在虚空上）
	var bw := minf(_vis.size.x, _vis.size.y) * 0.05
	for k in 6:
		var inset := float(k) * bw
		var vg := Color(0, 0, 0, 0.10 * (1.0 - float(k) / 6.0))
		var iw := _vis.size.x - inset * 2.0
		var ih := _vis.size.y - inset * 2.0
		if iw <= 0.0 or ih <= 0.0:
			break
		draw_rect(Rect2(_vis.position.x + inset, _vis.position.y + inset, iw, bw), vg, true)
		draw_rect(Rect2(_vis.position.x + inset, _vis.end.y - inset - bw, iw, bw), vg, true)
		draw_rect(Rect2(_vis.position.x + inset, _vis.position.y + inset, bw, ih), vg, true)
		draw_rect(Rect2(_vis.end.x - inset - bw, _vis.position.y + inset, bw, ih), vg, true)
	var sg = main.get("_sg") if main != null else null
	if sg == null:
		return
	var b: Rect2 = sg.bounds_px(String(probe.active_space))
	for k in range(8, 0, -1):                       # 外圈落影：由外向内叠，越贴墙越暗 → 房子"坐"在暗处
		draw_rect(b.grow(float(k) * 9.0), Color(0, 0, 0, 0.06), true)
	draw_rect(b.grow(4.0), Color(X_PARCHMENT, 0.07), true)   # 极淡暖边：屋里透出来的一点光

## Probe 进入非-town Space：有 interiors.json 内容 → 画【真室内】（地板/墙/家具/门/楼梯）；否则回落占位网格。
func _draw_space_placeholder() -> void:
	var main := get_parent()
	var sg = main.get("_sg")
	var probe = main.get("_probe")
	var sid := String(probe.active_space)
	var fid := String(probe.active_floor)
	var b: Rect2 = sg.bounds_px(sid)
	if not _interiors_loaded:
		_load_interiors()
	var content: Dictionary = (_interiors.get(sid, {}) as Dictionary).get(fid, {})
	if not content.is_empty():
		_draw_interior(sg, sid, fid, b, content)
		return
	draw_rect(b, P_PANEL, true)
	draw_rect(b, P_NIGHT, false, 2.0)
	for gx in range(int(b.size.x / T) + 1):
		draw_line(Vector2(b.position.x + gx * T, b.position.y), Vector2(b.position.x + gx * T, b.end.y), Color(1, 1, 1, 0.05), 1.0)
	for gy in range(int(b.size.y / T) + 1):
		draw_line(Vector2(b.position.x, b.position.y + gy * T), Vector2(b.end.x, b.position.y + gy * T), Color(1, 1, 1, 0.05), 1.0)
	draw_string(Art.font(), b.position + Vector2(10, 26), "%s / %s（Probe inspect · 无内容占位）" % [sg.label_of(sid), fid],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, X_COLD_WHITE)
	for pt in sg.portals_from(sid, fid):          # Portal 锚点：看得见"这层通向哪"
		var to: Dictionary = pt["to"]
		var pos: Array = to.get("pos", [0, 0])
		var c := Vector2(float(pos[0]) * T + T * 0.5, float(pos[1]) * T + T * 0.5)
		draw_circle(c, 10.0, Color(X_GOLD, 0.85))
		draw_string(Art.font(), c + Vector2(12, 4), "%s→%s/%s" % [pt["kind"], to.get("space", ""), to.get("floor", "")],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, X_GOLD)

## 画一层真室内：木地板 + 外墙(门口留缺) + 家具(程序化) + 门/上下楼提示 + 楼层标签。纯 View、只读数据。
func _draw_interior(sg, sid: String, fid: String, b: Rect2, content: Dictionary) -> void:
	var wc := int(b.size.x / T); var hc := int(b.size.y / T)
	var ox := b.position.x; var oy := b.position.y
	# 门缺口：扫 portal 端点落在本层的门(kind=door)格 → 那格墙留缺
	var door_gap := {}
	for p in sg.portals:
		for side in ["from", "to"]:
			var e: Dictionary = p.get(side, {})
			if String(e.get("space", "")) == sid and String(e.get("floor", "")) == fid and String(p.get("kind", "")) == "door":
				var ep: Array = e.get("pos", [0, 0])
				door_gap[int(ep[1]) * wc + int(ep[0])] = true
	# ★ R2：外壳（地板+墙）改由【这栋楼自己的类型】决定，而不是一份写死的住宅配方。见 _interior_shell()。
	var shell := _interior_shell(sid, String(content.get("floor", "wood")))
	# 地板：mode 仍来自 interiors.json 的 floor 字段（authored 几何），颜色来自本楼类型的 FLOOR_PAL
	if shell["slab"]:
		draw_rect(b, shell["floor"], true)
		for gy in range(hc):
			for gx in range(wc):
				if (gx + gy) % 2 == 0:
					draw_rect(Rect2(ox + gx * T, oy + gy * T, T, T), Color(shell["checker"], 0.55), true)   # 交错石板
		for gy in range(hc):
			draw_rect(Rect2(ox, oy + gy * T, b.size.x, 2), Color(shell["floor_line"], 0.45), true)          # 横缝
	else:
		draw_rect(b, shell["floor"], true)
		for gy in range(hc):
			if gy % 2 == 0:
				draw_rect(Rect2(ox, oy + gy * T, b.size.x, 3), Color(shell["floor_line"], 0.4), true)
	# 外墙（边框），门口那格留缺、画成门
	for gx in range(wc):
		_interior_wall(shell, ox + gx * T, oy, door_gap.has(gx))                          # 上墙
		_interior_wall(shell, ox + gx * T, oy + (hc - 1) * T, door_gap.has((hc - 1) * wc + gx))  # 下墙
	for gy in range(hc):
		_interior_wall(shell, ox, oy + gy * T, door_gap.has(gy * wc))                      # 左墙
		_interior_wall(shell, ox + (wc - 1) * T, oy + gy * T, door_gap.has(gy * wc + wc - 1))  # 右墙
	# 家具（按 slot 程序化）。★ S3：同一个 slot 在不同用途的房间里画成不同的东西 —— 见 _furniture_role()。
	# role 每层只算一次（它只依赖本层的 authored 家具清单 + areas[].type，与逐件家具无关）。
	var role := _furniture_role(sid, content)
	# `_ac("interior_furniture", …)` = 零重排的绘制闸门（出货 `_askip==""` ⇒ 原样返回集合 ⇒ 逐字节不变）。
	# AM1 的 2F 像素门用 `--draw-skip interior_furniture` 拍一张【无家具】的 2F 作【真渲染负对照】：
	# 家具被跳掉 ⇒ 只剩地板/墙 ⇒ assert_cafe_2f 的"非空/可分"必红（= 这道门有牙，见 tools/assert_cafe_2f.py）。
	for fr in _ac("interior_furniture", content.get("furniture", [])):
		var fp: Array = (fr as Dictionary).get("pos", [0, 0])
		_draw_interior_furniture(String((fr as Dictionary).get("slot", "")), Vector2(ox + int(fp[0]) * T, oy + int(fp[1]) * T), role)
	if sid == "port_warehouse":
		_draw_port_warehouse_status(b)
	# P3 打磨：夜间氛围（暖底光 + 每盏灯源暖池，占用的床更旺）——画在家具之上、居民之下，居民自身仍清晰
	_draw_interior_night(b, content, sid, fid)
	# P3 Tier-B：画【此刻真在这层】的居民（阿丽在自家咖啡馆睡觉/看摊）。Space bounds 从原点起 → _draw_agent 用
	# ag.pos*T 的室内局部坐标即落在本层画面里。纯 View、只读 ag 平面字段。
	for ag in Sim.agents:
		if String(ag.get("space", "town")) == sid and String(ag.get("floor", "outdoor")) == fid:
			_draw_agent(ag)
	# 楼层标签
	draw_string(Art.font(), b.position + Vector2(T + 8, 22), "%s · %s" % [sg.label_of(sid), content.get("label", fid)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, D_WOOD_LINE)

## P1-i 东海货仓账簿：室内不是静态布景，直接读同一份 town_stock + CargoManifest 查询投影。
## 纯 View、无缓存/无 RNG；`warehouse_status` 负对照可只关这块，证明视觉确实来自权威状态。
func _draw_port_warehouse_status(b: Rect2) -> void:
	draw_string(Art.font(), b.end - Vector2(T * 3.55, T * 0.34), "右侧木门 · 返回东海码头", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, D_WOOD_LINE)
	if not _ap("warehouse_status"):
		return
	var panel := Rect2(b.position + Vector2(T * 3.18, T * 0.62), Vector2(T * 2.72, T * 2.12))
	draw_rect(Rect2(panel.position + Vector2(3, 4), panel.size), Color(0, 0, 0, 0.26), true)
	draw_rect(panel, P_COM_FOOT, true)
	draw_rect(panel, X_WOOD_MID, false, 3.0)
	draw_rect(Rect2(panel.position + Vector2(5, 5), Vector2(panel.size.x - 10, T * 0.44)), P_FOLIAGE_D, true)
	draw_string(Art.font(), panel.position + Vector2(12, T * 0.35), "东港到货簿", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, X_PARCHMENT)
	var goods := ["柴薪", "豆子", "口粮"]
	for i in goods.size():
		var good: String = goods[i]
		var cfg: Dictionary = (Sim.production.get("goods", {}) as Dictionary).get(good, {})
		var cap := maxi(1, int(cfg.get("cap", 1)))
		var qty := Sim._stock_of(good)
		var y := panel.position.y + T * (0.67 + float(i) * 0.31)
		draw_string(Art.font(), Vector2(panel.position.x + 10, y + 11), "%s %d/%d" % [good, qty, cap], HORIZONTAL_ALIGNMENT_LEFT, T * 1.05, 13, X_COLD_WHITE)
		var bx := panel.position.x + T * 1.48
		draw_rect(Rect2(bx, y, T * 0.98, 10), Color(0.03, 0.07, 0.08, 0.65), true)
		draw_rect(Rect2(bx + 1, y + 1, (T * 0.98 - 2) * clampf(float(qty) / float(cap), 0.0, 1.0), 8), X_GLOW if good == "柴薪" else P_WATER_LIT, true)
	var st := Sim.cargo_status_for_node("port_dock")
	var status := "泊位：暂无待卸货物"
	if String(st.get("state", "empty")) == "invalid":
		status = "泊位：货单异常 · 暂停卸货"
	elif String(st.get("state", "empty")) != "empty":
		var state_label := String({"ready": "待卸", "working": "卸货中", "blocked_capacity": "仓位不足", "blocked_funds": "镇库不足"}.get(String(st.get("state", "")), "待处理"))
		status = "泊位：%s×%d · %s" % [String(st.get("good", "货物")), int(st.get("qty", 0)), state_label]
	draw_string(Art.font(), panel.position + Vector2(10, T * 1.82), status, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 20, 13, X_GOLD)

## P3 打磨：室内夜间氛围。CanvasModulate 把整幅世界画布乘暗（室内也不例外）→ 夜里进屋本是【冷灰洞】：
## 暖木地板被夜蓝乘平。这里靠【相对暖光】把屋子从冷夜拉出来：整层压一层暖底光 + 每件光源家具
## （床/桌/吧台/咖啡机/书桌/灶）落一盏径向暖池；被人【占着】的（如睡在床上）那盏更旺 = 床头灯。
## 于是深夜点开住宅，一眼看出"这屋有人、亮着灯"。白昼无人 → 一笔不画（日间室内原样）。纯 View、只读、digest 不变。
func _draw_interior_night(b: Rect2, content: Dictionary, sid: String, fid: String) -> void:
	var night := _night_amt()
	var occ := 0
	var occ_cells := {}
	for ag in Sim.agents:
		if String(ag.get("space", "town")) == sid and String(ag.get("floor", "outdoor")) == fid:
			occ += 1
			occ_cells[Vector2i(ag["pos"])] = true
	var lit := 0.20 * night + minf(0.12, occ * 0.04) * (0.5 + 0.5 * night)
	if lit <= 0.001:
		return                                        # 白昼无人：日间室内保持原样
	draw_rect(b, Color(X_GLOW_DEEP, lit), true)         # 暖底光：偏橙、被夜蓝乘过后仍咬得住暖调
	var ox := b.position.x; var oy := b.position.y
	var light_slots := {"bed": true, "table": true, "counter": true, "coffee": true, "desk": true, "stove": true}
	for fr in content.get("furniture", []):
		var slot := String((fr as Dictionary).get("slot", ""))
		if not light_slots.has(slot):
			continue
		var fp: Array = (fr as Dictionary).get("pos", [0, 0])
		var cell := Vector2i(int(fp[0]), int(fp[1]))
		# 有人占着这盏灯（同格或紧邻上下——睡在床上/坐在桌前）→ 更旺
		var occupied := occ_cells.has(cell) or occ_cells.has(cell + Vector2i(0, 1)) or occ_cells.has(cell + Vector2i(0, -1))
		var pool := 0.20 * night + (0.16 if occupied else 0.0)
		if pool <= 0.01:
			continue
		var cen := Vector2(ox + float(cell.x) * T + T * 0.5, oy + float(cell.y) * T + T * 0.5)
		for k in 4:                                   # 四层同心：内亮外淡，叠出"光源在这"的衰减
			var f := 1.0 - float(k) / 4.0
			draw_circle(cen, T * (0.55 + 0.5 * float(k)), Color(X_GLOW, pool * 0.14 * f))

## ★ R2 · 室内外壳配方：由【这栋楼在 map.json areas 里的 type】决定，与外墙 / 区地板同源。
##
## 由来（实测，不是设计推演）：改前 7 栋楼 8 个楼层的**墙是同一条配方**——`_interior_wall()` 的第一个参数
## 是 `sg`，而函数体**一次都没用过它**；墙主面写死 `P_RES_FOOT`（住宅暖石灰）。于是澡堂/工坊/图书馆
## 在**外面**是灰蓝石墙 / 暖灰石墙（`BLD_PAL`，`_wall_type` 早就按 `areas[].type` 分好了），
## **一进门就变成住宅的暖木墙**——同一栋楼的里外自相矛盾。地板同理：只有 wood/stone 两档服务 8 个楼层。
##
## ⇒ 修法不是新造一套室内色，是**把外面已经有的那套接进来**（红线#5 复用优先）：
##   墙主面 = `BLD_PAL[typ]["foot"]`，顶棱/墙脚沿用原来的 lightened(0.20)/darkened(0.28) 派生式；
##   地板 = `FLOOR_PAL[typ]` 的 base/line。
##   **选 `foot` 而不是 `face` 有实测理由**：`P_RES_FACE #c2a071` 与住宅木地板 `#c8a273` 只差 6/6/2，
##   拿它当墙会让住宅的墙和地板糊成一块；`foot` 档恰好等于今天写死的那个值 ⇒ **住宅两栋逐像素不变**，
##   其余三类各自跟着自己的族走。
## ⚠ `mode`(plank/slab) 仍取 interiors.json 的 `floor` 字段，**不从 FLOOR_PAL 取**：两处都有 mode 就会漂。
##   实测这 8 个楼层里 authored `floor` 与 `FLOOR_PAL[typ].mode` **逐条一致**（wood↔plank 5 条、stone↔slab 3 条），
##   所以今天两种取法等价；写成 authored 优先是为了将来有人蓄意写一间"石头地的住宅"时不被静默覆盖。
## 纯 View：只读 `Sim.world.areas[*].type`（Sim 侧从不读这个字段，D6/F5 已记过），不写任何状态、不抽 RNG。
func _interior_shell(sid: String, floor_mode: String) -> Dictionary:
	var areas: Dictionary = Sim.world.get("areas", {}) if Sim.world.get("areas", {}) is Dictionary else {}
	var a: Dictionary = areas.get(sid, {}) if areas.get(sid, {}) is Dictionary else {}
	var typ := String(a.get("type", "residential"))
	# 认不出的 type 退回住宅（= 改前行为），与 BLD_PAL 认不出退回 workshop 的口径不同：
	# 这里退回"改前长什么样"，让未知建筑至少不比今天差。
	if not BLD_PAL.has(typ) or not FLOOR_PAL.has(typ):
		typ = "residential"
	var wall: Color = BLD_PAL[typ]["foot"]
	var fp: Dictionary = FLOOR_PAL[typ]
	return {
		"type": typ,
		"wall": wall,
		"wall_top": wall.lightened(0.20),      # 与 D_INT_WALL_TOP 同一派生式（住宅档逐字节相同）
		"wall_foot": wall.darkened(0.28),      # 与 D_INT_WALL_FOOT 同一派生式
		"floor": fp["base"],
		"floor_line": fp["line"],
		"checker": (fp["base"] as Color).lightened(0.18),   # 交错石板的亮格；改前是写死的 P_KERB
		"slab": floor_mode == "stone",
	}

func _interior_wall(shell: Dictionary, x: float, y: float, is_door: bool) -> void:
	if is_door:                                    # 门：地板延伸 + 门框 + 木门
		draw_rect(Rect2(x + T * 0.12, y + T * 0.1, T * 0.76, T * 0.8), X_WOOD_MID, true)
		draw_rect(Rect2(x + T * 0.12, y + T * 0.1, T * 0.76, T * 0.8), D_WOOD_LINE, false, 2.0)
		draw_circle(Vector2(x + T * 0.72, y + T * 0.5), T * 0.05, X_GOLD)   # 门把
		return
	draw_rect(Rect2(x, y, T, T), shell["wall"], true)                        # 墙主面（按建筑类型）
	draw_rect(Rect2(x, y, T, T * 0.24), shell["wall_top"], true)             # 顶棱高光
	draw_rect(Rect2(x, y + T * 0.86, T, T * 0.14), shell["wall_foot"], true) # 墙脚暗边

## ── S3：家具语义按【房间用途】分化 ──────────────────────────────────────────
## 病（R2 交接 docs/69 §五，本棒在像素侧复核过）：`shelf` **一份画法（三色书脊的书架）
## × 11 个实例 × 8/8 个楼层**。它在图书馆和阿丽卧室是**对的**，
## 在**杂货铺（该是货架）、工坊（该是工具架）、澡堂（该是毛巾架）、咖啡区（该是杯碟架）是错的**。
##
## ⚠ 修法**不能**只看 `areas[].type`——它按构造做不到：type 是**四分**的，而语义要**六档**，
##   且冲突就在 type 内部：`commercial` 一类里同时装着 咖啡区(cafe/1f)、阿丽的卧室(cafe/2f)、
##   杂货铺(shop/1f) **三种互不相同的用途**；`public` 一类里装着 澡堂 与 图书馆。
##   **只按 type 分，最优分配下仍有 3/11 件必错**（commercial 错 2：cafe 的两层；public 错 1：澡堂）。
##   ⇒ 更根本的一句：**`type` 是【每栋楼】一个属性，而 cafe 一栋楼的 1f 与 2f 用途不同**
##     ——只要判据的粒度停在"楼"，咖啡馆的两层就永远分不开。逐实例算例见本棒回执 §二。
## ⚠ 也**不能**改 `slot`：slot 进 `Sim._build_interior_grids()` 的 `WALKABLE_SLOTS`、
##   也进 `_compile_interiors()` 造的对象 id ⇒ 那是**会移动 digest** 的动作（R2 已记，docs/69 §四·2）。
##
## ⇒ 走第三条路：**房间自己的家具清单，就是它用途的 authored 证据。**
##   浴池只出现在盥洗空间、柜台+货箱只出现在零售、床只出现在起居。这些都是 `interiors.json`
##   **已经写下**的事实，本函数**只读**——不改数据、不写状态、不抽 RNG。
##   好处是它**跟着数据长**：将来有人加第二间澡堂，只要那间有 `bath`，毛巾架自动就对；
##   而"按 space id 查一张表"那种写法要手工补一行，漏了就静默退回书架。
##
## 判据的顺序是有意的（**先特征、后兜底**），每一档都指名它靠哪条 authored 事实分出来：
##   1. 有 `bath`                     ⇒ 盥洗（wash/1f）——浴池是全镇独一份的强特征
##   2. `type == workshop`            ⇒ 作坊（work/1f）——这一类 type 内部没有二义，可以直接用
##   3. 有 `counter` **且**有 `crate` ⇒ 零售（shop/1f）——柜台配货箱＝前店后仓
##   4. 有 `counter` 或 `coffee`      ⇒ 堂食（cafe/1f）——有柜台但没货箱
##   5. `shelf`≥2 且有 `desk` 且无 `bed` ⇒ 藏书（library/1f）——成排书架配书桌、且不是卧室
##   6. 其余                          ⇒ 起居（home/1f、home2/1f、cafe/2f）
func _furniture_role(sid: String, content: Dictionary) -> String:
	if sid == "port_warehouse":
		return "store"
	var slots := {}
	for fr in content.get("furniture", []):
		var s := String((fr as Dictionary).get("slot", ""))
		slots[s] = int(slots.get(s, 0)) + 1
	var areas: Dictionary = Sim.world.get("areas", {}) if Sim.world.get("areas", {}) is Dictionary else {}
	var a: Dictionary = areas.get(sid, {}) if areas.get(sid, {}) is Dictionary else {}
	if slots.has("bath"):
		return "bath"
	if String(a.get("type", "")) == "workshop":
		return "workshop"
	if slots.has("counter") and slots.has("crate"):
		return "store"
	if slots.has("counter") or slots.has("coffee"):
		return "cafe"
	if int(slots.get("shelf", 0)) >= 2 and slots.has("desk") and not slots.has("bed"):
		return "study"
	return "living"

func _draw_interior_furniture(slot: String, base: Vector2, role: String = "living") -> void:
	match slot:
		"bed": _draw_bed(base)
		"coffee":                                   # 咖啡机：深色金属机身 + 红灯 + 杯
			draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.15, T * 0.6, T * 0.62), P_WRK_ROOF, true)
			draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.15, T * 0.6, T * 0.14), P_WRK_FOOT, true)
			draw_circle(Vector2(base.x + T * 0.68, base.y + T * 0.3), T * 0.05, X_SIGNAL_NEG)
			draw_rect(Rect2(base.x + T * 0.42, base.y + T * 0.52, T * 0.16, T * 0.14), P_TEXT, true)
		"counter":                                  # 吧台 / 杂货铺柜台 —— 按房间用途分化（S3 同型，与 _draw_shelf 一样按 role 派发）
			if role == "store":                     # AM2（编号134）：杂货铺前柜 —— 木柜台 + 收银机 + 挂秤 + 台面果篮，与咖啡吧台分得开
				draw_rect(Rect2(base.x + 2, base.y + T * 0.6, T - 4, T * 0.35), Color(0, 0, 0, 0.18), true)      # 投影
				draw_rect(Rect2(base.x + T * 0.03, base.y + T * 0.42, T * 0.94, T * 0.44), X_WOOD_MID, true)     # 柜身
				draw_rect(Rect2(base.x + T * 0.03, base.y + T * 0.42, T * 0.94, T * 0.09), P_COM_TOP, true)      # 台面高光
				draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.22, T * 0.28, T * 0.22), P_WRK_FOOT, true)      # 收银机机身（深金属）
				draw_rect(Rect2(base.x + T * 0.13, base.y + T * 0.25, T * 0.22, T * 0.09), X_COLD_WHITE, true)   # 收银机显示窗
				draw_circle(Vector2(base.x + T * 0.18, base.y + T * 0.4), T * 0.03, X_GOLD)                      # 按键/铜钮
				draw_line(Vector2(base.x + T * 0.72, base.y + T * 0.18), Vector2(base.x + T * 0.72, base.y + T * 0.32), D_WOOD_LINE, 2.0)  # 挂秤立柱
				draw_rect(Rect2(base.x + T * 0.6, base.y + T * 0.32, T * 0.24, T * 0.05), P_WRK_FOOT, true)      # 秤盘横梁
				draw_circle(Vector2(base.x + T * 0.66, base.y + T * 0.39), T * 0.05, X_SIGNAL_NEG)               # 篮里红果
				draw_circle(Vector2(base.x + T * 0.78, base.y + T * 0.39), T * 0.045, X_GOLD)                    # 篮里黄果
			else:                                   # 咖啡区吧台（改前那段，逐字节不动 ⇒ cafe 渲染不受扰）
				draw_rect(Rect2(base.x + 2, base.y + T * 0.6, T - 4, T * 0.35), Color(0, 0, 0, 0.18), true)
				draw_rect(Rect2(base.x + T * 0.03, base.y + T * 0.32, T * 0.94, T * 0.5), X_WOOD_MID, true)
				draw_rect(Rect2(base.x + T * 0.03, base.y + T * 0.32, T * 0.94, T * 0.1), P_COM_LINE, true)
		"table":                                    # 餐桌
			draw_rect(Rect2(base.x + T * 0.24, base.y + T * 0.5, T * 0.1, T * 0.34), P_COM_FOOT, true)
			draw_rect(Rect2(base.x + T * 0.66, base.y + T * 0.5, T * 0.1, T * 0.34), P_COM_FOOT, true)
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.3, T * 0.7, T * 0.24), P_COM_LINE, true)
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.3, T * 0.7, T * 0.08), D_FURN_HI, true)
		"chair":                                    # 椅子
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.2, T * 0.32, T * 0.5), X_WOOD_MID, true)
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.44, T * 0.32, T * 0.13), P_COM_LINE, true)
		"shelf": _draw_shelf(role, base)             # 书架/货架/工具架/毛巾架/杯碟架 —— 按房间用途分化
		"plant":                                    # 盆栽
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.56, T * 0.32, T * 0.28), D_POT, true)
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.42), T * 0.24, P_FOLIAGE_D)
			draw_circle(Vector2(base.x + T * 0.4, base.y + T * 0.32), T * 0.14, P_FOLIAGE_M)
		"rug":                                       # 地毯
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.15, T * 0.84, T * 0.7), Color(D_RUG_RED, 0.75), true)
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.15, T * 0.84, T * 0.7), Color(X_GOLD, 0.5), false, 2.0)
		"desk":                                      # 书桌 —— 按房间用途分化（S3 同型，与 counter/crate/shelf 一样按 role 派发）
			if role == "study":                     # AM4（编号138）：图书馆阅读桌 —— 桌面摊开一本书 + 墨水瓶，与 cafe 私宅书桌分得开
				draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.35, T * 0.7, T * 0.28), X_WOOD_MID, true)      # 桌面
				draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.35, T * 0.7, T * 0.08), P_COM_LINE, true)      # 桌沿高光
				draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.55, T * 0.09, T * 0.28), P_COM_FOOT, true)      # 左腿
				draw_rect(Rect2(base.x + T * 0.71, base.y + T * 0.55, T * 0.09, T * 0.28), P_COM_FOOT, true)     # 右腿
				draw_rect(Rect2(base.x + T * 0.23, base.y + T * 0.2, T * 0.54, T * 0.17), P_COM_FOOT, true)      # 摊开书的底影
				draw_rect(Rect2(base.x + T * 0.26, base.y + T * 0.21, T * 0.23, T * 0.15), X_COLD_WHITE, true)   # 左页
				draw_rect(Rect2(base.x + T * 0.51, base.y + T * 0.21, T * 0.23, T * 0.15), X_PARCHMENT, true)    # 右页
				draw_line(Vector2(base.x + T * 0.5, base.y + T * 0.2), Vector2(base.x + T * 0.5, base.y + T * 0.36), P_COM_FOOT, 2.0)  # 书脊
				for k in range(3):                                                                             # 页面上的字行
					draw_rect(Rect2(base.x + T * 0.29, base.y + T * (0.24 + k * 0.037), T * 0.16, T * 0.014), P_COM_FOOT, true)
				draw_circle(Vector2(base.x + T * 0.83, base.y + T * 0.31), T * 0.05, P_WRK_FOOT)                 # 墨水瓶
				draw_circle(Vector2(base.x + T * 0.83, base.y + T * 0.29), T * 0.022, X_GOLD)                    # 瓶口铜环
			else:                                    # 改前那段，逐字节不动 ⇒ cafe 2F 私宅书桌渲染不受扰
				draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.35, T * 0.7, T * 0.28), X_WOOD_MID, true)
				draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.35, T * 0.7, T * 0.08), P_COM_LINE, true)
				draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.55, T * 0.09, T * 0.28), P_COM_FOOT, true)
				draw_rect(Rect2(base.x + T * 0.71, base.y + T * 0.55, T * 0.09, T * 0.28), P_COM_FOOT, true)
				draw_rect(Rect2(base.x + T * 0.26, base.y + T * 0.22, T * 0.2, T * 0.14), P_TEXT, true)
		"window":                                    # 窗（画在墙上）：天光 + 木框 + 十字
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.12, T * 0.7, T * 0.5), P_WATER_LIT, true)
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.12, T * 0.7, T * 0.5), P_COM_FOOT, false, 3.0)
			draw_line(Vector2(base.x + T * 0.5, base.y + T * 0.12), Vector2(base.x + T * 0.5, base.y + T * 0.62), P_COM_FOOT, 2.0)
		"bath":                                      # 浴池：石沿 + 水面 + 蒸汽
			draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.2, T * 0.8, T * 0.66), P_WRK_FACE, true)
			draw_rect(Rect2(base.x + T * 0.17, base.y + T * 0.27, T * 0.66, T * 0.52), P_WATER, true)
			draw_rect(Rect2(base.x + T * 0.17, base.y + T * 0.27, T * 0.66, T * 0.12), Color(P_WATER_LIT, 0.8), true)
			draw_circle(Vector2(base.x + T * 0.36, base.y + T * 0.14), T * 0.07, Color(1, 1, 1, 0.35))
			draw_circle(Vector2(base.x + T * 0.6, base.y + T * 0.07), T * 0.055, Color(1, 1, 1, 0.22))
		"bench":                                     # 条凳：长座板 + 两腿
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.42, T * 0.84, T * 0.17), P_COM_LINE, true)
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.42, T * 0.84, T * 0.05), D_FURN_HI, true)
			draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.59, T * 0.1, T * 0.24), P_COM_FOOT, true)
			draw_rect(Rect2(base.x + T * 0.74, base.y + T * 0.59, T * 0.1, T * 0.24), P_COM_FOOT, true)
		"crate":                                     # 木箱 / 杂货铺果箱 —— 按房间用途分化
			if role == "store":                     # AM2（编号134）：杂货铺敞口果蔬箱 —— 板条箱 + 堆尖的果蔬
				draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.4, T * 0.72, T * 0.46), X_WOOD_MID, true)      # 箱体
				draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.4, T * 0.72, T * 0.46), D_WOOD_LINE, false, 2.0)  # 边框
				for k in range(3):                                                                              # 板条竖缝
					draw_line(Vector2(base.x + T * (0.14 + k * 0.24), base.y + T * 0.4), Vector2(base.x + T * (0.14 + k * 0.24), base.y + T * 0.86), D_WOOD_LINE, 1.5)
				draw_circle(Vector2(base.x + T * 0.3, base.y + T * 0.37), T * 0.1, X_SIGNAL_NEG)                 # 红果（苹果）
				draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.34), T * 0.09, P_GRASS)                     # 绿果
				draw_circle(Vector2(base.x + T * 0.68, base.y + T * 0.37), T * 0.09, X_GOLD)                     # 黄果（柑橘）
			else:                                   # 通用木箱（改前那段，逐字节不动 ⇒ 未来别处用 crate 不受扰）
				draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.3, T * 0.68, T * 0.56), P_RES_LINE, true)
				draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.3, T * 0.68, T * 0.56), P_COM_FOOT, false, 2.0)
				draw_line(Vector2(base.x + T * 0.16, base.y + T * 0.86), Vector2(base.x + T * 0.84, base.y + T * 0.3), P_COM_FOOT, 2.0)
				draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.3, T * 0.68, T * 0.08), P_COM_TOP, true)
		"stool":                                     # 圆凳
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.5), T * 0.22, P_COM_LINE)
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.47), T * 0.18, D_FURN_HI)
			draw_rect(Rect2(base.x + T * 0.44, base.y + T * 0.62, T * 0.12, T * 0.22), P_COM_FOOT, true)
		"stairs":                                    # 楼梯：斜阶
			for k in range(4):
				draw_rect(Rect2(base.x + T * 0.12 + k * T * 0.17, base.y + T * 0.62 - k * T * 0.13, T * 0.2, T * 0.15), D_STAIR, true)
				draw_rect(Rect2(base.x + T * 0.12 + k * T * 0.17, base.y + T * 0.62 - k * T * 0.13, T * 0.2, T * 0.04), D_STAIR_TOP, true)
		# ── AM1（编号133）：cafe 身份分区新增的纯装饰 slot ─────────────────────────
		# 咖啡区：甜点柜 / 吧凳 / 吊灯 / A 字菜单牌（+复用 counter/coffee/杯碟架）；
		# 私宅：衣柜 / 床头柜台灯 / 梳妆镜 / 相框（公共 vs 私人两套家具语汇）。
		# 全部无 advertises ⇒ 不进 world 候选（只挡格 + 渲染），golden 已实测 12/12 逐字节不变。
		# 每件都严格画在本格 [base, base+T] 内（不越格污染墙面采样带 col0/7）。
		"pastry":                                    # 玻璃甜点柜（咖啡区）：浅木柜体 + 玻璃罩 + 糕点
			draw_rect(Rect2(base.x + T * 0.12, base.y + T * 0.5, T * 0.76, T * 0.36), X_WOOD_MID, true)
			draw_rect(Rect2(base.x + T * 0.12, base.y + T * 0.5, T * 0.76, T * 0.06), D_FURN_HI, true)          # 台面高光
			draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.2, T * 0.72, T * 0.32), Color(P_WATER_LIT, 0.32), true)  # 玻璃罩
			draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.2, T * 0.72, T * 0.32), Color(X_COLD_WHITE, 0.5), false, 2.0)  # 玻璃框
			draw_circle(Vector2(base.x + T * 0.32, base.y + T * 0.42), T * 0.08, X_SIGNAL_NEG)                  # 红蛋糕
			draw_circle(Vector2(base.x + T * 0.56, base.y + T * 0.44), T * 0.07, X_PARCHMENT)                  # 奶油点心
			draw_rect(Rect2(base.x + T * 0.68, base.y + T * 0.34, T * 0.14, T * 0.16), P_RES_ROOF, true)       # 一块糕
		"barstool":                                  # 吧凳（咖啡区）：高柱 + 圆座 + 脚踏环
			draw_rect(Rect2(base.x + T * 0.45, base.y + T * 0.4, T * 0.1, T * 0.44), P_COM_FOOT, true)         # 高柱
			draw_rect(Rect2(base.x + T * 0.4, base.y + T * 0.64, T * 0.2, T * 0.04), P_COM_LINE, true)         # 脚踏环
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.36), T * 0.19, X_WOOD_MID)                    # 圆座
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.33), T * 0.15, D_FURN_HI)                     # 座面高光
		"menu":                                      # A 字黑板菜单牌（咖啡区）：木框 + 深绿板 + 粉笔行 + 支腿
			draw_rect(Rect2(base.x + T * 0.24, base.y + T * 0.18, T * 0.52, T * 0.56), X_WOOD_MID, true)       # 板框
			draw_rect(Rect2(base.x + T * 0.29, base.y + T * 0.23, T * 0.42, T * 0.46), P_FOLIAGE_D, true)      # 黑板面（深绿）
			for k in range(3):                                                                               # 粉笔行
				draw_rect(Rect2(base.x + T * 0.33, base.y + T * (0.3 + k * 0.12), T * (0.34 if k == 0 else 0.28), T * 0.035), Color(X_COLD_WHITE, 0.85), true)
			draw_line(Vector2(base.x + T * 0.32, base.y + T * 0.74), Vector2(base.x + T * 0.24, base.y + T * 0.88), X_WOOD_MID, 3.0)  # 支腿
			draw_line(Vector2(base.x + T * 0.68, base.y + T * 0.74), Vector2(base.x + T * 0.76, base.y + T * 0.88), X_WOOD_MID, 3.0)
		"wardrobe":                                  # 高衣柜（卧室）：柜体 + 双门缝 + 铜把手
			draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.08, T * 0.68, T * 0.8), X_WOOD_MID, true)        # 柜体
			draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.08, T * 0.68, T * 0.8), D_WOOD_LINE, false, 2.0) # 边框
			draw_line(Vector2(base.x + T * 0.5, base.y + T * 0.1), Vector2(base.x + T * 0.5, base.y + T * 0.86), D_WOOD_LINE, 2.0)  # 门缝
			draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.12, T * 0.28, T * 0.74), Color(D_FURN_HI, 0.22), true)  # 左门高光
			draw_circle(Vector2(base.x + T * 0.44, base.y + T * 0.5), T * 0.035, X_GOLD)                       # 左把手
			draw_circle(Vector2(base.x + T * 0.56, base.y + T * 0.5), T * 0.035, X_GOLD)                       # 右把手
		"vanity":                                    # 梳妆镜（卧室）：妆台 + 镜框 + 镜面 + 反光条
			draw_rect(Rect2(base.x + T * 0.28, base.y + T * 0.56, T * 0.44, T * 0.14), X_WOOD_MID, true)       # 妆台
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.14, T * 0.4, T * 0.44), P_COM_FOOT, true)         # 镜框
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.18, T * 0.32, T * 0.36), Color(P_WATER_LIT, 0.7), true)  # 镜面
			draw_line(Vector2(base.x + T * 0.4, base.y + T * 0.2), Vector2(base.x + T * 0.6, base.y + T * 0.5), Color(X_COLD_WHITE, 0.55), 3.0)  # 反光条
		"picture":                                   # 相框（挂墙，卧室私人相片墙）：木框 + 画面 + 地平线 + 暖点
			draw_rect(Rect2(base.x + T * 0.24, base.y + T * 0.2, T * 0.52, T * 0.5), X_WOOD_MID, true)         # 木框
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.26, T * 0.4, T * 0.38), P_WATER_LIT, true)        # 画面（天）
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.48, T * 0.4, T * 0.16), P_FOLIAGE_M, true)        # 地平线（草）
			draw_circle(Vector2(base.x + T * 0.6, base.y + T * 0.35), T * 0.05, X_GOLD)                        # 暖点（日/月）
		# ── AM2（编号134）：shop 杂货铺 + work 工坊身份分区新增的纯装饰 slot ─────────────
		# 杂货铺：谷袋（sacks）；工坊：工作台(workbench)/木料堆(lumber)/铁砧(anvil)/材料箱(materials)。
		# 全部无 advertises ⇒ 不进 world 候选（只挡格 + 渲染）；每件都【原地换 slot】、位置+walkable 不变
		# ⇒ 导航挡格集逐字节不变（自证见 analysis/am2/edit_interiors.py），golden 实测 12/12 逐字节不变（含 chain）。
		# 每件严格画在本格 [base, base+T] 内、x∈[0.05,0.92]、不越格污染 INTSHELL 的墙面采样列（col0/col w-1）。
		"sacks":                                     # 谷袋堆（杂货铺）：三只麻袋 + 扎口 + 溢出的谷粒
			draw_rect(Rect2(base.x + T * 0.12, base.y + T * 0.5, T * 0.34, T * 0.36), P_PLAZA, true)          # 底左袋
			draw_rect(Rect2(base.x + T * 0.12, base.y + T * 0.5, T * 0.34, T * 0.36), P_PLAZA_LINE, false, 1.5)
			draw_rect(Rect2(base.x + T * 0.5, base.y + T * 0.54, T * 0.34, T * 0.32), P_PLAZA, true)          # 底右袋
			draw_rect(Rect2(base.x + T * 0.5, base.y + T * 0.54, T * 0.34, T * 0.32), P_PLAZA_LINE, false, 1.5)
			draw_rect(Rect2(base.x + T * 0.31, base.y + T * 0.26, T * 0.36, T * 0.32), P_PLAZA, true)         # 顶袋
			draw_rect(Rect2(base.x + T * 0.31, base.y + T * 0.26, T * 0.36, T * 0.32), P_PLAZA_LINE, false, 1.5)
			draw_rect(Rect2(base.x + T * 0.43, base.y + T * 0.22, T * 0.12, T * 0.06), P_PLAZA_LINE, true)    # 扎口
			draw_circle(Vector2(base.x + T * 0.49, base.y + T * 0.34), T * 0.05, X_PARCHMENT)                # 溢出谷粒
		"workbench":                                 # 工作台（工坊）：厚台面 + 台钳 + 木工刨 + 台腿
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.36, T * 0.84, T * 0.16), X_WOOD_MID, true)      # 厚台面
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.36, T * 0.84, T * 0.05), D_FURN_HI, true)       # 台面高光
			draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.52, T * 0.1, T * 0.34), P_COM_FOOT, true)       # 左腿
			draw_rect(Rect2(base.x + T * 0.76, base.y + T * 0.52, T * 0.1, T * 0.34), P_COM_FOOT, true)       # 右腿
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.6, T * 0.4, T * 0.07), P_COM_FOOT, true)         # 横撑
			draw_rect(Rect2(base.x + T * 0.06, base.y + T * 0.42, T * 0.12, T * 0.16), P_WRK_FOOT, true)      # 台钳身
			draw_rect(Rect2(base.x + T * 0.05, base.y + T * 0.47, T * 0.16, T * 0.05), P_WRK_TOP, true)       # 台钳口
			draw_rect(Rect2(base.x + T * 0.4, base.y + T * 0.28, T * 0.34, T * 0.08), P_WRK_FOOT, true)       # 刨身
			draw_rect(Rect2(base.x + T * 0.46, base.y + T * 0.24, T * 0.08, T * 0.06), X_WOOD_MID, true)      # 刨手柄
		"lumber":                                    # 木料堆（工坊）：三层锯好的板材 + 两截露端木的原木
			for k in range(3):
				var ly := base.y + T * (0.42 + k * 0.15)
				draw_rect(Rect2(base.x + T * 0.12, ly, T * 0.76, T * 0.12), X_WOOD_MID, true)                 # 板材
				draw_rect(Rect2(base.x + T * 0.12, ly, T * 0.76, T * 0.035), D_FURN_HI, true)                 # 板面高光
				draw_rect(Rect2(base.x + T * 0.12, ly, T * 0.76, T * 0.12), D_WOOD_LINE, false, 1.5)          # 板缘
			draw_circle(Vector2(base.x + T * 0.28, base.y + T * 0.3), T * 0.09, X_WOOD_MID)                   # 原木端面
			draw_circle(Vector2(base.x + T * 0.28, base.y + T * 0.3), T * 0.045, D_WOOD_LINE)                 # 年轮
			draw_circle(Vector2(base.x + T * 0.52, base.y + T * 0.28), T * 0.08, X_WOOD_MID)                  # 原木端面
			draw_circle(Vector2(base.x + T * 0.52, base.y + T * 0.28), T * 0.04, D_WOOD_LINE)                 # 年轮
		"anvil":                                     # 铁砧（工坊）：木墩 + 深金属砧身 + 砧角 + 搁着的锤
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.62, T * 0.4, T * 0.24), X_WOOD_MID, true)        # 木墩
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.62, T * 0.4, T * 0.05), D_FURN_HI, true)         # 墩顶高光
			draw_rect(Rect2(base.x + T * 0.28, base.y + T * 0.5, T * 0.44, T * 0.12), P_WRK_ROOF, true)       # 砧台面
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.5, T * 0.34, T * 0.035), P_WRK_TOP, true)       # 砧面高光棱
			draw_rect(Rect2(base.x + T * 0.38, base.y + T * 0.44, T * 0.24, T * 0.08), P_WRK_FOOT, true)      # 砧腰
			draw_rect(Rect2(base.x + T * 0.68, base.y + T * 0.51, T * 0.14, T * 0.07), P_WRK_ROOF, true)      # 砧角
			draw_rect(Rect2(base.x + T * 0.44, base.y + T * 0.3, T * 0.04, T * 0.2), X_WOOD_MID, true)        # 锤柄
			draw_rect(Rect2(base.x + T * 0.38, base.y + T * 0.28, T * 0.16, T * 0.07), P_WRK_FOOT, true)      # 锤头
		"materials":                                 # 材料箱（工坊）：料箱 + 竖插的棒料 + 一卷铜线
			draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.46, T * 0.72, T * 0.4), P_COM_FOOT, true)       # 料箱
			draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.46, T * 0.72, T * 0.06), X_WOOD_MID, true)      # 箱沿
			for k in range(4):                                                                              # 竖插棒料
				draw_rect(Rect2(base.x + T * (0.2 + k * 0.16), base.y + T * 0.2, T * 0.04, T * 0.3), P_WRK_TOP, true)
			draw_circle(Vector2(base.x + T * 0.52, base.y + T * 0.66), T * 0.1, X_GOLD)                       # 铜线卷
			draw_circle(Vector2(base.x + T * 0.52, base.y + T * 0.66), T * 0.05, P_COM_FOOT)                  # 线卷孔
		# ── AM4（编号138）：home/home2/library/wash 四栋室内身份分区新增的纯装饰 slot ─────────────
		# 民居：五斗柜(dresser)/柴炉(stove)；澡堂：洗漱台(basin)；图书馆：落地阅读灯(lamp)。
		# 全部无 advertises ⇒ 不进 world 候选（只挡格 + 渲染）；每件都【原地换 slot】、位置+walkable 不变
		# ⇒ 导航挡格集逐字节不变（自证见 analysis/am4/edit_interiors.py），golden 实测 12/12 逐字节不变（含 chain）。
		# 每件严格画在本格 [base, base+T] 内、x∈[0.05,0.92]、不越格污染 INTSHELL 的墙面采样列（col0/col w-1）。
		"dresser":                                   # 五斗柜（民居 home·温馨）：矮柜身 + 三层抽屉 + 铜拉手 + 柜面小相框（私人物件）
			draw_rect(Rect2(base.x + 2, base.y + T * 0.62, T - 4, T * 0.3), Color(0, 0, 0, 0.16), true)       # 投影
			draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.34, T * 0.72, T * 0.54), X_WOOD_MID, true)      # 柜身
			draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.34, T * 0.72, T * 0.54), D_WOOD_LINE, false, 2.0)  # 边框
			draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.34, T * 0.72, T * 0.06), D_FURN_HI, true)       # 柜面高光
			for k in range(3):                                                                              # 三层抽屉缝 + 铜拉手 ×2
				var dy := base.y + T * (0.46 + k * 0.14)
				draw_line(Vector2(base.x + T * 0.14, dy), Vector2(base.x + T * 0.86, dy), D_WOOD_LINE, 1.5)
				draw_circle(Vector2(base.x + T * 0.36, dy + T * 0.07), T * 0.028, X_GOLD)
				draw_circle(Vector2(base.x + T * 0.64, dy + T * 0.07), T * 0.028, X_GOLD)
			draw_rect(Rect2(base.x + T * 0.55, base.y + T * 0.12, T * 0.28, T * 0.23), X_WOOD_MID, true)      # 相框木边
			draw_rect(Rect2(base.x + T * 0.58, base.y + T * 0.14, T * 0.22, T * 0.13), P_WATER_LIT, true)     # 相片（天）
			draw_rect(Rect2(base.x + T * 0.58, base.y + T * 0.23, T * 0.22, T * 0.08), P_FOLIAGE_M, true)     # 相片（人/地）
			draw_circle(Vector2(base.x + T * 0.69, base.y + T * 0.2), T * 0.03, X_GOLD)                       # 相片暖点
		"stove":                                     # 柴炉（民居 home·温馨）：深金属炉身 + 炉门火光 + 顶板 + 烟囱 + 短腿（slot 名 stove ⇒ 夜里自带暖光池）
			draw_rect(Rect2(base.x + T * 0.26, base.y + T * 0.28, T * 0.48, T * 0.54), P_WRK_FOOT, true)      # 炉身
			draw_rect(Rect2(base.x + T * 0.24, base.y + T * 0.24, T * 0.52, T * 0.09), P_WRK_ROOF, true)      # 顶板
			draw_rect(Rect2(base.x + T * 0.24, base.y + T * 0.24, T * 0.52, T * 0.03), P_WRK_TOP, true)       # 顶板高光棱
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.42, T * 0.32, T * 0.26), Color(0, 0, 0, 0.55), true)  # 炉膛口（暗）
			draw_rect(Rect2(base.x + T * 0.36, base.y + T * 0.5, T * 0.28, T * 0.16), X_SIGNAL_NEG, true)     # 炉火（红）
			draw_rect(Rect2(base.x + T * 0.4, base.y + T * 0.54, T * 0.2, T * 0.1), X_GOLD, true)             # 炉火（黄芯）
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.58), T * 0.05, X_GLOW)                       # 火心暖点
			draw_rect(Rect2(base.x + T * 0.6, base.y + T * 0.06, T * 0.09, T * 0.2), P_WRK_ROOF, true)        # 烟囱
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.82, T * 0.08, T * 0.1), P_WRK_FOOT, true)        # 左腿
			draw_rect(Rect2(base.x + T * 0.62, base.y + T * 0.82, T * 0.08, T * 0.1), P_WRK_FOOT, true)       # 右腿
		"basin":                                     # 洗漱台（澡堂 wash）：石台 + 陶盆盛水 + 龙头 + 上方圆镜（石材取 P_WRK_FACE 与浴池同族）
			draw_rect(Rect2(base.x + 2, base.y + T * 0.66, T - 4, T * 0.24), Color(0, 0, 0, 0.16), true)      # 投影
			draw_rect(Rect2(base.x + T * 0.18, base.y + T * 0.5, T * 0.64, T * 0.4), P_WRK_FACE, true)        # 石台身
			draw_rect(Rect2(base.x + T * 0.18, base.y + T * 0.5, T * 0.64, T * 0.08), P_WRK_TOP, true)        # 台面高光
			draw_rect(Rect2(base.x + T * 0.24, base.y + T * 0.5, T * 0.52, T * 0.16), P_WATER, true)          # 盆内水
			draw_rect(Rect2(base.x + T * 0.24, base.y + T * 0.5, T * 0.52, T * 0.05), Color(P_WATER_LIT, 0.85), true)  # 水面高光
			draw_rect(Rect2(base.x + T * 0.47, base.y + T * 0.34, T * 0.06, T * 0.16), P_WRK_FOOT, true)      # 龙头立管
			draw_rect(Rect2(base.x + T * 0.47, base.y + T * 0.34, T * 0.15, T * 0.05), P_WRK_FOOT, true)      # 龙头出水嘴
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.22), T * 0.13, P_WRK_FACE)                   # 镜框
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.22), T * 0.1, Color(P_WATER_LIT, 0.7))       # 镜面
			draw_line(Vector2(base.x + T * 0.44, base.y + T * 0.18), Vector2(base.x + T * 0.54, base.y + T * 0.27), Color(X_COLD_WHITE, 0.6), 2.5)  # 镜面反光
		"lamp":                                      # 落地阅读灯（图书馆 library·台灯）：底座 + 细杆 + 灯罩 + 暖光晕
			draw_rect(Rect2(base.x + T * 0.38, base.y + T * 0.78, T * 0.24, T * 0.08), P_COM_FOOT, true)      # 底座
			draw_rect(Rect2(base.x + T * 0.47, base.y + T * 0.36, T * 0.06, T * 0.44), P_COM_FOOT, true)      # 灯杆
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.2, T * 0.4, T * 0.2), X_PARCHMENT, true)         # 灯罩
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.16, T * 0.32, T * 0.05), X_PARCHMENT, true)     # 罩顶（收窄）
			draw_rect(Rect2(base.x + T * 0.3, base.y + T * 0.36, T * 0.4, T * 0.05), X_GOLD, true)            # 罩口暖边
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.46), T * 0.16, Color(X_GLOW, 0.32))          # 灯下暖光晕
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.43), T * 0.08, Color(X_GOLD, 0.4))           # 光晕内芯
		_:
			draw_rect(Rect2(base.x + 9, base.y + 12, T - 18, T - 18), P_RES_FOOT, true)

## `shelf` 的分化派发（S3）。**living / study 两档逐字节沿用改前那段代码**——
## 它们本来就是对的（R2：图书馆与阿丽卧室），不动同时也是本棒最强的负对照：
## home / home2 / cafe·2f / library 四个楼层的整帧 diff 必须 `bbox=None`。
##
## ⚠ 五档**全部**铺满同一块背板 `[0.10,0.90]×[0.05,0.90]`。这不是审美要求，是**量具的前提**：
##   `tools/assert_furniture_role.py` 从 `[0.15,0.85]²` 取字形样本，若某一档画得比背板小，
##   地板就会漏进采样窗——而地板早已被 R2 按建筑类型分过档 ⇒ 门会把**地板的差异**
##   读成"货架分开了"，得出一个假绿。（本棒第一版的清点脚本正是这么量错的，见回执 §一。）
func _draw_shelf(role: String, base: Vector2) -> void:
	match role:
		"bath":     _shelf_towel(base)
		"workshop": _shelf_tools(base)
		"store":    _shelf_goods(base)
		"cafe":     _shelf_crockery(base)
		_:          _shelf_books(base)      # living / study —— 改前的画法，逐字节不变

## 书架（改前唯一那份画法，原样搬过来，一个数都没动）
func _shelf_books(base: Vector2) -> void:
	draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.05, T * 0.8, T * 0.85), P_COM_FOOT, true)
	var bookcols := [P_RES_ROOF, P_FOLIAGE_D, D_BOOK_BLUE]
	for k in range(3):
		draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.24 + k * T * 0.22, T * 0.7, T * 0.04), D_WOOD_LINE, true)
		draw_rect(Rect2(base.x + T * 0.18, base.y + T * 0.12 + k * T * 0.22, T * 0.5, T * 0.11), bookcols[k], true)

## 毛巾架（澡堂）：石灰背板 + 横杆 + 三条对折毛巾 + 底部藤篮。
## 背板取 `P_WRK_FACE`——它在本文件里的注释已经写着"**只剩室内用途**：浴池石沿"，
## 于是毛巾架与同一间屋里的浴池自然同族，不引入新色。
func _shelf_towel(base: Vector2) -> void:
	draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.05, T * 0.8, T * 0.85), P_WRK_FACE, true)
	draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.05, T * 0.8, T * 0.1), P_WRK_TOP, true)     # 顶棱
	draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.2, T * 0.72, T * 0.045), P_WRK_FOOT, true) # 横杆
	var towels := [X_COLD_WHITE, D_RUG_TEAL, X_PARCHMENT]
	for k in range(3):
		var tx := base.x + T * (0.17 + k * 0.235)
		var c: Color = towels[k]
		draw_rect(Rect2(tx, base.y + T * 0.24, T * 0.19, T * 0.48), c, true)
		draw_rect(Rect2(tx, base.y + T * 0.24, T * 0.19, T * 0.055), c.darkened(0.24), true)   # 搭在杆上的一折
		draw_rect(Rect2(tx, base.y + T * 0.48, T * 0.19, T * 0.03), c.darkened(0.14), true)    # 对折线
	draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.76, T * 0.6, T * 0.12), P_PLAZA, true)    # 藤篮
	draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.76, T * 0.6, T * 0.035), P_PLAZA_LINE, true)

## 工具架（工坊）：洞洞板 + 挂钉 + 锤/锯/凿 + 底层零件盒。
## 背板取 `X_WRKW_FOOT`（= 工坊外墙墙脚），于是"进了工坊，架子也是工坊的"。
func _shelf_tools(base: Vector2) -> void:
	draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.05, T * 0.8, T * 0.85), X_WRKW_FOOT, true)
	draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.05, T * 0.8, T * 0.09), P_WRK_TOP, true)      # 顶棱
	for k in range(4):                                                                            # 挂钉排
		draw_circle(Vector2(base.x + T * (0.21 + k * 0.19), base.y + T * 0.21), T * 0.028, P_WRK_ROOF)
	draw_rect(Rect2(base.x + T * 0.19, base.y + T * 0.26, T * 0.05, T * 0.3), X_WOOD_MID, true)    # 锤柄
	draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.24, T * 0.17, T * 0.09), P_WRK_TOP, true)    # 锤头
	draw_rect(Rect2(base.x + T * 0.4, base.y + T * 0.26, T * 0.04, T * 0.2), X_WOOD_MID, true)     # 锯柄
	draw_rect(Rect2(base.x + T * 0.36, base.y + T * 0.42, T * 0.26, T * 0.1), P_WRK_TOP, true)     # 锯身
	draw_rect(Rect2(base.x + T * 0.36, base.y + T * 0.5, T * 0.26, T * 0.025), P_WRK_ROOF, true)   # 锯齿
	draw_rect(Rect2(base.x + T * 0.68, base.y + T * 0.25, T * 0.05, T * 0.32), P_WRK_FOOT, true)   # 凿
	draw_rect(Rect2(base.x + T * 0.78, base.y + T * 0.25, T * 0.05, T * 0.26), P_WRK_FOOT, true)   # 錾
	draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.64, T * 0.72, T * 0.22), P_COM_FOOT, true)   # 零件盒
	draw_rect(Rect2(base.x + T * 0.14, base.y + T * 0.64, T * 0.72, T * 0.05), X_WOOD_MID, true)
	for k in range(3):                                                                            # 盒里的铜件
		draw_circle(Vector2(base.x + T * (0.27 + k * 0.23), base.y + T * 0.76), T * 0.05, X_GOLD)

## 货架（杂货铺）：柜体沿用商用棕（镇上的木工是同一批人），**差别全在货上**——
## 麻袋 / 陶罐 / 布卷，没有一根书脊。这一档与书架**共用柜体色**是蓄意的：
## 它逼着量具去看**货**，而不是靠"柜子换个颜色"蒙混过关。
func _shelf_goods(base: Vector2) -> void:
	draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.05, T * 0.8, T * 0.85), P_COM_FOOT, true)
	for k in range(3):
		draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.24 + k * T * 0.22, T * 0.7, T * 0.04), D_WOOD_LINE, true)
	for k in range(2):                                                                            # 上层：陶罐 ×2
		var jx := base.x + T * (0.3 + k * 0.24)
		draw_circle(Vector2(jx, base.y + T * 0.17), T * 0.08, D_POT)
		draw_rect(Rect2(jx - T * 0.04, base.y + T * 0.08, T * 0.08, T * 0.04), D_POT.darkened(0.22), true)
	for k in range(3):                                                                            # 中层：麻袋 ×3
		var sx := base.x + T * (0.19 + k * 0.21)
		draw_rect(Rect2(sx, base.y + T * 0.34, T * 0.16, T * 0.12), P_PLAZA, true)
		draw_rect(Rect2(sx + T * 0.045, base.y + T * 0.3, T * 0.07, T * 0.045), P_PLAZA_LINE, true)   # 扎口
	draw_rect(Rect2(base.x + T * 0.18, base.y + T * 0.55, T * 0.28, T * 0.13), X_SIGNAL_NEG, true)    # 下层：布卷
	draw_rect(Rect2(base.x + T * 0.18, base.y + T * 0.55, T * 0.28, T * 0.04), X_SIGNAL_NEG.lightened(0.22), true)
	draw_rect(Rect2(base.x + T * 0.52, base.y + T * 0.55, T * 0.26, T * 0.13), P_PLAZA, true)
	draw_rect(Rect2(base.x + T * 0.52, base.y + T * 0.55, T * 0.26, T * 0.04), P_PLAZA_LINE, true)
	draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.74, T * 0.68, T * 0.13), P_RES_LINE, true)      # 底层：散货箱
	draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.74, T * 0.68, T * 0.04), P_COM_TOP, true)

## 杯碟架（咖啡区）：浅木柜体 + 白瓷杯碟 + 深色咖啡罐。
## 冷白瓷（`X_COLD_WHITE`，注释原文"蒸汽/瓷/枕头"）是这一档的识别特征。
func _shelf_crockery(base: Vector2) -> void:
	draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.05, T * 0.8, T * 0.85), X_WOOD_MID, true)
	for k in range(3):
		draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.24 + k * T * 0.22, T * 0.7, T * 0.04), D_WOOD_LINE, true)
	for k in range(3):                                                                            # 上层：白瓷杯 ×3
		var cx := base.x + T * (0.26 + k * 0.2)
		draw_circle(Vector2(cx, base.y + T * 0.17), T * 0.068, X_COLD_WHITE)
		draw_rect(Rect2(cx + T * 0.06, base.y + T * 0.15, T * 0.032, T * 0.05), X_COLD_WHITE, true)   # 把手
	draw_rect(Rect2(base.x + T * 0.19, base.y + T * 0.37, T * 0.22, T * 0.075), X_COLD_WHITE, true)   # 中层：碟摞
	draw_rect(Rect2(base.x + T * 0.19, base.y + T * 0.33, T * 0.22, T * 0.045), X_COLD_WHITE.darkened(0.1), true)
	draw_rect(Rect2(base.x + T * 0.47, base.y + T * 0.33, T * 0.18, T * 0.12), P_TEXT, true)          # 奶罐
	draw_rect(Rect2(base.x + T * 0.7, base.y + T * 0.35, T * 0.14, T * 0.1), X_PARCHMENT, true)       # 糖罐
	for k in range(2):                                                                            # 下层：咖啡罐 ×2
		var tx := base.x + T * (0.2 + k * 0.3)
		draw_rect(Rect2(tx, base.y + T * 0.53, T * 0.22, T * 0.15), P_WRK_FOOT, true)
		draw_rect(Rect2(tx, base.y + T * 0.53, T * 0.22, T * 0.04), P_WRK_TOP, true)
	draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.74, T * 0.68, T * 0.13), P_PLAZA, true)         # 底层：豆袋
	draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.74, T * 0.68, T * 0.04), P_PLAZA_LINE, true)

var _rc_conflict_ids := {}   # 每帧预建：卷入活跃冲突的 agent 端点集（渲染缓存，_draw_agent 用 O(1) 查）
var _rc_meet_ids := {}       # 每帧预建：有活跃约会的 agent 端点集

## ── 界外虚空 ───────────────────────────────────────────────────────────────
## 全镇视角下地图矩形只占画面的一小半，其余是 Godot 未改的默认 clear color(#4d4d4d)：
## 小镇读作"灰色虚空里的一座孤岛"。室内早有解（_draw_interior_backdrop），小镇分支一直没有对应物——
## 草地被钳在 [0,w)x[0,h)（下面的 tx0..tx1/ty0..ty1），界外一个像素都没人画。
##
## ★这一层只画【地图矩形之外】：把 _vis 减去 map 得到上/下/左/右四条带，只在带里绘制。
##   R5 双向断言就靠这条 —— 界内必须逐像素不变（ImageChops bbox 完全落在地图矩形外）。
const VOID_BASE := X_VOID_BASE     # 深林底（与 project.godot 的 default_clear_color 同色）
const VOID_SPILL := X_VOID_SPILL    # 镇子漏进林子的那点光（贴着地图外缘最亮，向外熄灭）
const VOID_CANOPY_A := X_CANOPY_A
const VOID_CANOPY_B := X_CANOPY_B
const VOID_CANOPY_C := X_CANOPY_C
const VOID_SPILL_TILES := 6.0           # 光晕带宽（格）
const VOID_FADE_TILES := 22.0           # 从地图外缘到"全黑深林"的距离（格）
const VOID_DECOR_MAX_CELLS := 4096      # 装饰上限：极端缩放下只铺底色，不烧填充率（红线#3 手机）

## ── 界外第一层：边界延续（docs/44 §四 第一层 / docs/43 §三-C7）───────────────────
## C1 把灰虚空 28.30% → 0.00%，但【接缝】接替它成了画面上最刺眼的东西：小镇是一块亮绿色矩形、
## 硬边直接贴在暗色森林上，读作"深色地板上铺了一张绿地毯"。这不是审美判断——实测那条边的
## **最大相邻像素亮度跃变 = 131.5/255（正午）/ 62.1（夜）**：一个像素跨掉半个动态范围。
##
## 修法不是再调背板色（那只是把地毯换个颜色），而是【把地面继续画出去】：
##   0.0-1.0 格：纯地面延续（草坡的受光顶）——第一眼看过去，边缘外还是同一块地
##   1.1-1.5 格：矮石墙 / 路缘（分段、带缺口，**不能是一圈完整边框**）
##   1.6-2.0 格：排水沟
##   2.0-3.0 格：草坡沉进林子
## ★ 硬质用 #9B968D / #6D6A61，草坡用 #5F7B34（docs/44 §四给定值）。
## ★ 不放门、路标或完整建筑——那会暗示界外可以进入。**这也是这一棒不画"道路收口"的原因**：
##   本地图没有任何土路走到边界（_build_paths 只连门↔广场），凭空画一条通向界外的路
##   恰恰是在暗示"可以走出去"，与规格自相矛盾。
## ★ 一切界外绘制统一走 _verge_seg / _verge_ring 的 bands 求交 ⇒ **界内逐像素不动是构造保证**。
const VERGE_TILES := 3.0                    # 第一层深度（docs/44 §四："2-3 格"）
const VERGE_KNEE := 0.30                    # 斜坡拐点：t<KNEE 从地面色过渡到草坡色
const VERGE_SLOPE := P_FOLIAGE_D       # 草坡（docs/44 §四）
const VERGE_STONE := P_STONE       # 硬质·受光顶面（docs/44 §四）
const VERGE_STONE_FOOT := P_STONE_LINE  # 硬质·背光面（docs/44 §四）
const VERGE_MOTIF_ZOOM := 0.18              # 低于此缩放只铺斜坡，不画硬质细节（红线#3 手机）
const GRASS_FALLBACK := P_GRASS    # 缺草地切片时的地面色（= grass_a 的实测均值 133,166,67）

var _verge_ground := Color(0, 0, 0, 0)      # 草地纹理加权均值缓存（a<=0 = 未算）

## 点到矩形的最短距离（点在矩形内=0）。界外暗林用它做"离镇越远越黑越稀"的衰减。
func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)

## 草坡贴边那一档的颜色 = 【当前草地纹理的加权平均】× 季节色偏 × 季节/天气大气罩。
## ★不硬编码一个绿：换一套草地切片、或换季、或下雨，斜坡自动跟着走。
##   否则冬天界内被霜白罩刷淡、界外仍是夏绿 —— 接缝会以另一种形式复活（这是本棒踩到的真陷阱）。
##   大气罩只染贴边这一档（权重随 t 衰减到 KNEE 处归零），深处的林子不进冬天，与 C1 的取舍一致。
func _verge_ground_col() -> Color:
	if _verge_ground.a <= 0.0:
		var acc := Vector3.ZERO
		var tot := 0.0
		for g in _grass:
			var t: Texture2D = g["t"]
			var img: Image = t.get_image() if t != null else null
			if img == null:
				continue
			if img.is_compressed():
				img = img.duplicate()
				img.decompress()
			var s := Vector3.ZERO
			var n := 0
			for y in range(0, img.get_height(), 2):     # 隔点采样：16x16 的切片没必要逐像素扫
				for x in range(0, img.get_width(), 2):
					var c := img.get_pixel(x, y)
					if c.a < 0.5:
						continue
					s += Vector3(c.r, c.g, c.b)
					n += 1
			if n > 0:
				acc += (s / float(n)) * float(g["w"])
				tot += float(g["w"])
		_verge_ground = GRASS_FALLBACK if tot <= 0.0 else Color(acc.x / tot, acc.y / tot, acc.z / tot, 1.0)
	var v := _season_veg()
	return Color(clampf(_verge_ground.r * v.r, 0.0, 1.0),
		clampf(_verge_ground.g * v.g, 0.0, 1.0),
		clampf(_verge_ground.b * v.b, 0.0, 1.0), 1.0)

## 距离 t∈(0,1]（0=贴边、1=第一层外沿）处的斜坡色。t<KNEE 段还要吃一份衰减的大气罩，
## 这样界内 _draw_climate_wash 刷出来的冬白/雨蓝在边缘是连续的。
func _verge_ramp(g: Color, t: float) -> Color:
	var col := g.lerp(VERGE_SLOPE, t / VERGE_KNEE) if t <= VERGE_KNEE \
		else VERGE_SLOPE.lerp(VOID_BASE, (t - VERGE_KNEE) / (1.0 - VERGE_KNEE))
	var fade := clampf(1.0 - t / VERGE_KNEE, 0.0, 1.0)
	if fade > 0.0:
		for wsh in [SEASON_WASH.get(Sim.season_today, Color(0, 0, 0, 0)),
				WEATHER_WASH.get(Sim.weather_today, Color(0, 0, 0, 0))]:
			var wc: Color = wsh
			if wc.a > 0.0:
				col = col.lerp(Color(wc.r, wc.g, wc.b, 1.0), wc.a * fade)
	return col

## 一圈（map 外扩 d 世界像素）填色，**只落在界外带里**。
func _verge_ring(c: CanvasItem, map: Rect2, bands: Array, d: float, col: Color) -> void:
	var ring := map.grow(d)
	for b in bands:
		var s := ring.intersection(b)
		if s.size.x > 0.0 and s.size.y > 0.0:
			c.draw_rect(s, col, true)

## 把「沿边 a0..a1 格 × 向外 d0..d1 格」换算成世界矩形并**只画在界外带里**。
func _verge_seg(c: CanvasItem, e: Dictionary, bands: Array, a0: float, a1: float, d0: float, d1: float, col: Color) -> void:
	var base: Vector2 = e["base"]
	var al: Vector2 = e["al"]
	var ov: Vector2 = e["out"]
	var p0: Vector2 = base + al * (a0 * T) + ov * (d0 * T)
	var p1: Vector2 = base + al * (a1 * T) + ov * (d1 * T)
	var r := Rect2(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)),
		Vector2(absf(p1.x - p0.x), absf(p1.y - p0.y)))
	for b in bands:
		var s := r.intersection(b)
		if s.size.x > 0.0 and s.size.y > 0.0:
			c.draw_rect(s, col, true)

## 这一格边界外该延续什么：贴边 3 格内有 authored 树带 → 林缘（林子继续，不砌墙）；否则 → 人住过的边。
##
## ★ docs/44 §四 还列了「河岸」与「道路收口」，本棒【两个都没做】，理由同一条：
##   **这张地图上没有任何水体或土路走到边界**——实测水体离边界最近 2 格（y=2 / y=45,46），
##   土路是 _build_paths 从门连到广场、全在内部。"延续"必须有东西可延续。
##   实际试过一版河岸（水体 3 格内 → 界外铺湿地+芦苇）：眼验读作**一块悬在池塘上方的半透明灰绿板**，
##   像 UI 面板不像湿地 —— 因为池塘与边界之间还隔着两格草地，那片"湿地"跟池塘根本不连。
##   ⇒ 已删除。真要做河岸，前提是地图生成器把水放到边界上，那是 Wave D 连同 gen_town 一起的事。
func _verge_motif(en: int, i: int, w: int, h: int) -> String:
	for k in 3:
		var x := i
		var y := k
		match en:
			1: y = h - 1 - k
			2: x = k; y = i
			3: x = w - 1 - k; y = i
		if _tree_set.has(y * w + x):
			return "grove"
	return "kerb"

## 第一层主体：亮度斜坡 + 逐格 motif。斜坡环数随缩放自适应（贴边 1px 一档），
## 既不在拉近时露出色带，也不在拉远时空烧填充率。
func _draw_town_verge(c: CanvasItem, map: Rect2, bands: Array, w: int, h: int) -> void:
	if not _terrain_built:
		_build_terrain()        # ★背板画在草地循环【之前】，而地形集合本来在草地之后才建 ⇒
		#   不先建的话首帧 _water_set/_tree_set 全空、河岸与林缘退化成石墙（实测踩到）
	var g := _verge_ground_col()
	var steps := clampi(int(VERGE_TILES * float(T) * _zoom), 24, 96)
	if not _ap("bd:vergeramp"):
		steps = 0
	for k in range(steps, 0, -1):               # 由外向内：内环覆盖外环 ⇒ 得到连续斜坡
		var t := float(k) / float(steps)
		_verge_ring(c, map, bands, t * VERGE_TILES * float(T), _verge_ramp(g, t))
	if _zoom < VERGE_MOTIF_ZOOM or not _ap("bd:vergemotif"):
		return
	var edges := [
		{"n": 0, "base": Vector2(0, 0), "al": Vector2(1, 0), "out": Vector2(0, -1), "cells": w, "on": _vis.position.y < 0.0},
		{"n": 1, "base": Vector2(0, float(h) * T), "al": Vector2(1, 0), "out": Vector2(0, 1), "cells": w, "on": _vis.end.y > float(h) * T},
		{"n": 2, "base": Vector2(0, 0), "al": Vector2(0, 1), "out": Vector2(-1, 0), "cells": h, "on": _vis.position.x < 0.0},
		{"n": 3, "base": Vector2(float(w) * T, 0), "al": Vector2(0, 1), "out": Vector2(1, 0), "cells": h, "on": _vis.end.x > float(w) * T},
	]
	for e in edges:
		if not bool(e["on"]):
			continue
		var en: int = int(e["n"])
		var horiz := en <= 1
		var lo := (_vis.position.x if horiz else _vis.position.y) / float(T)
		var hi := (_vis.end.x if horiz else _vis.end.y) / float(T)
		var i0 := maxi(0, int(floor(lo)))
		var i1 := mini(int(e["cells"]), int(ceil(hi)))
		var i := i0 - (i0 % 2)                  # 双格步长：石墙以 2 格为一段，边缘不会碎成栅栏
		while i < i1:
			var a0 := float(i)
			var a1 := float(mini(i + 2, int(e["cells"])))
			match _verge_motif(en, i, w, h):
				"grove":
					# 林缘：authored 树带走到边界 → 界外直接是林下灌木，不设石墙（林子里砌墙很怪）
					for s in 3:
						var hs2 := _hash(i, en, 71 + s)
						var ba := a0 + 0.15 + float(hs2 % 9) * 0.19
						var bd := 1.25 + float(hs2 / 9 % 11) * 0.14
						var bc: Color = VOID_CANOPY_B if hs2 % 2 == 0 else VOID_CANOPY_A
						_verge_seg(c, e, bands, ba, ba + 0.34, bd, bd + 0.30, Color(bc.r, bc.g, bc.b, 0.45))
				_:
					# 人住过的边：**散落的**矮石墙残段 + 排水沟。
					# ★这里踩过一次坑，值得写下来：第一版按 72% 覆盖、固定 1.10 格外扩铺连续石墙，
					#   数值上 cross 已经修好（131.5→2.9），**眼验却读作"给地图加了一圈装饰边框"**
					#   —— 与 C1 记下的"矩形青色岸带"是同一个病：
					#   **任何与边界等距且连续的元素，都会从"边界延续"退化成"画框"，**
					#   而画框比原来的硬边更糟：它把那条我们正想让人忘掉的矩形又描了一遍。
					#   数值上同时被 outband 抓到（26.5 → 68.8），两把尺子一致。
					#   修法不是删掉硬质（docs/44 §四点名要 #9B968D/#6D6A61），而是让它
					#   【不等距 + 不连续 + 低对比】：外扩距离抖 1.3 格、段长抖、覆盖率降到约 1/3。
					var hw := _hash(i, en, 41)
					if hw % 100 < 34:
						var d0 := 0.85 + float(hw / 100 % 13) * 0.11      # 外扩 0.85..2.17 格
						var la := a0 + float(hw / 7 % 5) * 0.16
						var lb := la + 0.55 + float(hw / 13 % 7) * 0.16   # 段长 0.55..1.51 格
						_verge_seg(c, e, bands, la, lb, d0, d0 + 0.20, Color(VERGE_STONE.r, VERGE_STONE.g, VERGE_STONE.b, 0.52))
						_verge_seg(c, e, bands, la, lb, d0 + 0.20, d0 + 0.34, Color(VERGE_STONE_FOOT.r, VERGE_STONE_FOOT.g, VERGE_STONE_FOOT.b, 0.50))
					var hd := _hash(i, en, 43)
					if hd % 100 < 30:                                     # 排水沟独立抽，刻意不与石墙对齐
						var dd := 1.15 + float(hd / 100 % 11) * 0.13      # 1.15..2.45 格
						var da := a0 + float(hd / 5 % 6) * 0.20
						_verge_seg(c, e, bands, da, da + 0.75 + float(hd / 11 % 5) * 0.18, dd, dd + 0.22, Color(0, 0, 0, 0.20))
			i += 2

# ══ 界外虚空：独立的【静态】子层 ═══════════════════════════════════════════════
# ★ 为什么要把它搬出 `_draw()`（这是 D7 的头条改动，理由全部是量出来的）：
#   真机 NX789J / N=12 / 白天 / 开局取景（`go_home` fit，zoom 0.229）实测三点：
#     ① 未改动的树              4989 draw · 100.0ms · FPS 10
#     ② 只做合批（草地/土路/装饰）2903 draw ·  83.3ms · FPS 12   ← 少了 2086 次 draw，只买回 16.7ms
#     ③ 再把界外树冠整段关掉      775 draw ·  11.8ms · FPS 85   ← 少了 2128 次 draw，买回 71.5ms
#   同样数量级的 draw，②每次约 8µs、③每次约 34µs ⇒ **"绘制"那个数字本身是个被混淆的代理**。
#   差别在**命令种类**：合批掉的是 `draw_rect`/`draw_texture_rect`（走实例化四边形），
#   而树冠是 `draw_circle` ⇒ 每一个都是独立的 **polygon 命令**（自带顶点缓冲、断批），
#   而且 `_draw()` 每帧都跑 ⇒ 这 2128 个多边形**每帧现场重新三角化、重新上传**。
#   ⇒ 治法不是"少画几棵树"（那会改画面），而是**让它别每帧重建**：
#     界外层的输入只有 `_vis / _zoom / 季节 / 天气`（它**不读 tick、不读 agent、不读昼夜**，
#     已逐行核对），所以相机不动时它逐帧完全相同 —— 搬进独立 CanvasItem、只在输入变化时
#     `queue_redraw()`，画面**逐字节不变**而每帧的重建成本归零。
class VoidLayer extends Node2D:
	var host = null
	func _draw() -> void:
		if host != null:
			host._draw_void_layer(self)

var _void: Node2D = null
var _void_key := ""
var _void_draws := 0           # 界外层实际重画了几次（门用）

func _build_void_layer() -> void:
	_void = VoidLayer.new()
	_void.host = self
	_void.name = "VoidBackdrop"
	_void.z_index = -1          # 画在本节点自身之下 —— 与它原先"草地循环之前第一笔"的位置等价
	add_child(_void)

## 界外层的缓存键：**穷举**了 `_draw_town_backdrop` 会读的一切可变量。
## `_askip` 也进键，否则逐 pass 审计会读到上一档的缓存。
func _void_cache_key() -> String:
	var mn := get_parent()
	var pb = mn.get("_probe") if mn != null else null
	var sp := String(pb.active_space) if pb != null else "town"
	return "%.4f|%.2f,%.2f,%.2f,%.2f|%s|%s|%s|%s" % [_zoom,
		_vis.position.x, _vis.position.y, _vis.size.x, _vis.size.y,
		Sim.season_today, Sim.weather_today, sp, _askip]

## 相机/季节/天气变了才让界外层重画。`_process` 与 `_draw` 里各查一次：
## 前者让"相机这一帧动了"在**同一帧**生效，后者兜住相机在本节点 `_process` 之后才更新的次序。
func _void_sync() -> void:
	if _void == null:
		return
	if _void_cache_key() != _void_key:
		_void.queue_redraw()

## ── R11 的门，但**不是 R11 写的那道门** ────────────────────────────────────────
## R11 要求"视觉棒必须报 draw-call 数"，并建议"场景模式下断言总 draw < 阈值"。
## 本棒的真机三点实测把这条建议**证伪**了：
##   合批档 2903 draw → 83.3ms ；缓存档 2911 draw → **11.1ms**。
##   **draw 数几乎相同，帧时差 7.5 倍** ⇒ 一道"总 draw < 阈值"的门对这次修复
##   **完全没有分辨力**：它在 83ms 和 11ms 两棵树上给出同一个判读，甚至会把更快的那棵判得更差。
##   （docs/41 §6-★ 的同一条纪律：写下判据后先问"一个什么都不做的改动能不能通过它"，
##     这次更糟——**一个真正的修复会被它判成退步**。）
## 真正值 89ms 的那条性质是**结构性**的：
##   **相机不动时，界外层不得随 tick 重画。**
## 这道门直接断言它：跑一段真 tick、相机不动，`_void_draws` 必须停在 1。
## 用法（可一行接进 tools/ci.sh，需要真 framebuffer=Xvfb）：
##   godot --path game --display-driver x11 --rendering-driver opengl3 -- --backend logic --seed 3 --void-gate
## 退出码 0=PASS / 1=FAIL。
var _void_gate := false
var _gate_frames := 0
var _gate_base := -1
var _gate_tick0 := 0
var _gate_static := 0          # 静态相位（40-200 帧）里随 tick 发生的重画次数
var _gate_ticks := 0
var _gate_days := 0
var _gate_rt_base := -1        # 切回 town 的那一刻的 _void_draws
var _gate_rt_draws := 0        # 切回之后又画了几次（必须 >= 1）
var _gate_rt_space := ""

func _void_gate_step() -> void:
	_gate_frames += 1
	var pb = get_parent().get("_probe") if get_parent() != null else null
	# ── 静态相位（40-200 帧）：相机不动，量"随 tick 重画了几次"────────────────
	if _gate_frames == 40:                     # 前 40 帧留给首帧建层 + 纹理加载
		_gate_base = _void_draws
		_gate_tick0 = Sim.tick_no
	# ── 往返相位（200 帧起）：切到别的平面再切回 town，界外层必须重画一次 ──────
	elif _gate_frames == 200:
		_gate_static = _void_draws - maxi(_gate_base, 0)
		_gate_ticks = Sim.tick_no - _gate_tick0
		_gate_days = int(float(Sim.tick_no) / float(Sim.TICKS_PER_DAY)) - int(float(_gate_tick0) / float(Sim.TICKS_PER_DAY))
		if pb != null:
			# ★ 必须【只翻 active_space、不碰相机】。第一版用 pb.set_space(...) 往返，
			# 而 set_space 会改相机 ⇒ 回到 town 时键因为【取景变了】而不同 ⇒ 照样会重画
			# ⇒ 负对照（把修复回滚）依然 PASS。**我自己的负对照当场把这条判据判死了。**
			# 真 bug 的形状要求：进出期间取景**逐字节不变**，这样回来时键才会"恰好又相等"。
			# 出货路径正是如此——`_portal_click` 出店调 go_home()，那是个**固定**取景，与开局同一个 P。
			_gate_rt_space = "cafe"
			pb.active_space = _gate_rt_space
	elif _gate_frames == 260 and pb != null:
		pb.active_space = "town"
		_gate_rt_base = _void_draws            # 回到 town 的那一刻记账；之后必须涨
	elif _gate_frames == 320 and _gate_rt_base >= 0:
		_gate_rt_draws = _void_draws - _gate_rt_base
	elif _gate_frames >= 400 and _gate_base >= 0:
		var extra := _gate_static          # 只算【静态相位】的重画；往返相位的重画是被【要求】的
		var ticks := _gate_ticks
		# ★ 允许量必须按【日边界】给，不能写死 0（2026-07-28 实测，这道门第一次跑在别人机器上就假红了）。
		# 界外层的缓存键里有 season 与 weather，而这两样【在日边界会合法地变】⇒ 跨一天就该重画一次。
		# 而"400 帧里推进多少 tick"取决于机器快慢：同一棵树，独立跑推进 189 tick(0 次重画, PASS)、
		# 在 visual_gate.sh 里跑推进 445 tick(1 次重画, FAIL)——**同一份代码、同一个性质，两种结论**。
		# 写死 0 的门不是在守"相机不动就不重画"，是在守"你的机器别太快"。
		var days := _gate_days             # 同 extra/ticks：用【静态相位】结束时的读数，不是全程
		# ★ 上界之外必须有【下界】。2026-07-28 外部评审："这道门有上界没有下界——
		#   **一个界外层根本不画的构建同样能通过它**"，而那恰好就是同一份评审抓到的真 bug 造成的树。
		#   一道连"它正在守的东西已经没了"都发现不了的门，守的是自己的存在感。
		#   下界一：settle 期间必须真的画过（_gate_base >= 1）。
		var drew := _gate_base >= 1
		#   下界二：**空间往返**——切到别的平面再切回来，界外层【必须】重画。
		#   这正是真 bug 的形状：键停在旧值 ⇒ 回到 town 时键"恰好又相等" ⇒ 不排重画 ⇒ 永久空白。
		var rt_ok := _gate_rt_draws >= 1
		var ok := extra <= days and ticks >= 20 and drew and rt_ok
		print("[VOIDGATE] frames=%d ticks=%d days=%d static_redraws=%d (allow<=%d) settle_draws=%d roundtrip_redraws=%d zoom=%.3f => %s"
			% [_gate_frames, ticks, days, extra, days, _gate_base, _gate_rt_draws, _zoom, "PASS" if ok else "FAIL"])
		if not drew:
			push_error("VOIDGATE FAIL: 界外层在 settle 期间【一次都没画】——门本身失去意义（上界为真是因为它什么都没做）")
		elif not rt_ok:
			push_error("VOIDGATE FAIL: 空间往返（town→%s→town）之后界外层【没有重画】——缓存键停在旧值，界外层会永久空白" % _gate_rt_space)
		elif not ok:
			push_error("VOIDGATE FAIL: 界外层在相机不动时重画了 %d 次，跨过的日边界只有 %d 个（tick 推进 %d）" % [extra, days, ticks])
		get_tree().quit(0 if ok else 1)

## ── W6 的机器断言：换世界之后，从 `Sim.world` 烘出来的缓存必须真的被作废并按新世界重建 ──────
## 用法：`godot --path game --display-driver x11 --rendering-driver opengl3 -- --backend logic --seed 3 --cache-gate`
## 退出码 0=PASS / 1=FAIL。
##
## ★ 它走的是**真的 F8 往返**（`Sim.save_game` → `Sim.load_game`），不是自己发一个信号糊弄自己：
##   `load_game` 是 `for k in state: set(k, state[k])`，而 `world` 是 Sim 的脚本变量、不在 DERIVED 排除表里
##   ⇒ 读档**整个换掉** `Sim.world`。这正是 W6 说的那条"F8 读档没有任何路径清它们"。
##
## ★ 判别力（docs/41 §6-★：先问"一个什么都不做的改动能不能通过它"）：
##   臂 A「读档之后四样缓存必须处于已作废状态」在**未改动的树上必然红**——那里没有任何东西会去清它们。
##   已实跑负对照：把 `_ready` 里那行 `Sim.world_reset.connect(...)` 注释掉，本门 FAIL。
##   臂 B「重建之后尺寸与当前世界一致」**在今天这张固定尺寸的地图上没有判别力**（w/h 恒定 ⇒ 恒真），
##   这一点必须明写：它守的是将来换图/换尺寸时的那一次，今天只是个恒真的看门人。
var _cache_gate := false
var _cg_frames := 0
var _cg_phase := 0
var _cg_before := ""
var _cg_after_reset := ""
var _cg_inv := false            # 读档【当场】四样是否都已作废（快照，见臂 A）
const CG_SAVE := "user://e5_cache_gate.sav"

func _cache_state() -> String:
	return "terrain=%s paths=%s decor=%s grass_var=%d walls=%d path_cells=%d decor_items=%d" % [
		_terrain_built, _paths_built, _decor_built, _grass_var.size(),
		_wall_set.size(), _path_set.size(), _decor_items.size()]

func _cache_gate_step() -> void:
	_cg_frames += 1
	var w: int = int(Sim.world.get("width", 0))
	var h: int = int(Sim.world.get("height", 0))
	if _cg_phase == 0 and _cg_frames >= 30:
		# ── 相位 0：等首帧把四样都烘出来（不烘出来说明门测的东西根本没发生）──
		if not (_terrain_built and _paths_built and _decor_built) or _grass_var.is_empty():
			print("[CACHEGATE] settle FAIL —— 缓存在 %d 帧后仍未建起：%s" % [_cg_frames, _cache_state()])
			push_error("CACHEGATE FAIL: 缓存从未建起，门失去意义（下界）")
			get_tree().quit(1)
			return
		_cg_before = _cache_state()
		# ── 相位 1：真的存一次、读一次（= 玩家按 F5 再按 F8）──
		if not Sim.save_game(CG_SAVE, {"why": "e5 cache gate"}):
			print("[CACHEGATE] save FAIL")
			push_error("CACHEGATE FAIL: save_game 失败，无法构造读档往返")
			get_tree().quit(1)
			return
		if not Sim.load_game(CG_SAVE):
			print("[CACHEGATE] load FAIL")
			push_error("CACHEGATE FAIL: load_game 失败，无法构造读档往返")
			get_tree().quit(1)
			return
		_cg_after_reset = _cache_state()
		_cg_inv = (not _terrain_built) and (not _paths_built) and (not _decor_built) and _grass_var.is_empty()
		_cg_phase = 1
		return
	if _cg_phase == 1:
		# ── 臂 A：读档【当场】四样必须已作废（这一条在未改动的树上必红）──
		# ⚠️ 读的是 `_cg_inv` 这个**在 load_game 返回的那一行就记下来的**快照，不是当前值：
		#   本相位跑在第 40 帧，中间的 `_draw` 早就把它们按需重建回来了 —— 第一版就是读当前值，
		#   于是它在【已经修好的树上】也报红。判据自己踩了一次"量错了时刻"。
		var invalidated := _cg_inv
		# ── 臂 B：本帧起会按需重建；等一帧让 _draw 跑完再验尺寸 ──
		if _cg_frames < 40:
			return
		var rebuilt := _terrain_built and _paths_built and _decor_built
		var sized := _grass_var.size() == w * h
		var consistent := _wall_set.size() == (Sim.world.get("walls", []) as Array).size()
		var ok := invalidated and rebuilt and sized and consistent
		print("[CACHEGATE] 读档前 %s" % _cg_before)
		print("[CACHEGATE] 读档后（当场）%s" % _cg_after_reset)
		print("[CACHEGATE] 重建后 %s   world=%dx%d" % [_cache_state(), w, h])
		print("[CACHEGATE] 臂A作废=%s 臂B重建=%s 尺寸=%s(%d vs %d) 一致=%s => %s"
			% [invalidated, rebuilt, sized, _grass_var.size(), w * h, consistent, "PASS" if ok else "FAIL"])
		if not invalidated:
			push_error("CACHEGATE FAIL（臂A）: 读档换掉了 Sim.world，但 _terrain_built/_paths_built/_decor_built/_grass_var 仍是旧世界的 —— 换一张不同尺寸的地图就会用旧尺寸的下标去索引新世界")
		elif not rebuilt:
			push_error("CACHEGATE FAIL（臂B）: 作废之后没有任何一帧把它们重建回来")
		elif not sized:
			push_error("CACHEGATE FAIL（臂B）: _grass_var 尺寸 %d != 当前世界 %d" % [_grass_var.size(), w * h])
		elif not consistent:
			push_error("CACHEGATE FAIL（臂B）: _wall_set 与当前 Sim.world.walls 不一致")
		get_tree().quit(0 if ok else 1)

func _draw_void_layer(cv: CanvasItem) -> void:
	# ★★ 键必须在【任何 early return 之前】写。2026-07-28 外部对抗评审抓到的真 bug：
	# 原来 `_void_key` 只在 town 分支的末尾赋值，于是两条 early return 会让它停在旧值上：
	#   ① 在镇上取景 P 画一次 → 存下 K(P,"town")
	#   ② 进店（active_space="cafe"）⇒ 每帧键都不匹配 ⇒ _void_sync 每帧 queue_redraw，
	#      而本函数在 :1453 就 return ⇒ **CanvasItem 的命令表被清空**，_void_key 仍是 K(P,"town")
	#   ③ 出店 ⇒ _portal_click 调 go_home()（**固定**取景，与开局同一个 P）⇒ 键重算又等于 K(P,"town")
	#      ⇒ **不排重画** ⇒ 界外层永久空白：verge 斜坡、石墙与排水沟、溢光、~2136 个林冠圆
	#      全部消失，只剩不是 CanvasItem、因而连昼夜都不跟的清屏色。
	# 「启动 → 进店 → 出店」就能稳定复现，全在出货路径上。
	# 把赋值提到最前面，三条路径（空世界 / 非-town / town）都会把**自己那一帧的真实状态**记进键，
	# 于是出店时 "cafe" → "town" 必然不匹配 ⇒ 必然重画。顺带治好"在室内每帧空排一次重画"。
	_void_key = _void_cache_key()
	if Sim.world.is_empty():
		return
	var mn := get_parent()
	var pb = mn.get("_probe") if mn != null else null
	if pb != null and String(pb.active_space) != "town":
		return                       # 非-town 平面有自己的底（_draw_interior_backdrop）
	_refresh_view_metrics()          # 与本节点共用画布变换；自己刷一次，保证画的是**本帧**的取景
	_void_key = _void_cache_key()    # 取景刷新后键可能变，以刷新后的为准
	_void_draws += 1
	if not _ap("backdrop"):
		return
	_draw_town_backdrop(cv, int(Sim.world.get("width", 24)), int(Sim.world.get("height", 16)))

func _draw_town_backdrop(c: CanvasItem, w: int, h: int) -> void:
	var map := Rect2(0.0, 0.0, float(w) * T, float(h) * T)
	var v := _vis
	var bands: Array = []
	if v.position.y < map.position.y:
		bands.append(Rect2(v.position.x, v.position.y, v.size.x, map.position.y - v.position.y))
	if v.end.y > map.end.y:
		bands.append(Rect2(v.position.x, map.end.y, v.size.x, v.end.y - map.end.y))
	var my0 := maxf(v.position.y, map.position.y)
	var my1 := minf(v.end.y, map.end.y)
	if my1 > my0:
		if v.position.x < map.position.x:
			bands.append(Rect2(v.position.x, my0, map.position.x - v.position.x, my1 - my0))
		if v.end.x > map.end.x:
			bands.append(Rect2(map.end.x, my0, v.end.x - map.end.x, my1 - my0))
	if bands.is_empty():
		return                                  # 镜头完全在界内（跟随相机的常态）：一笔都不画
	for b in _ac("bd:base", bands):
		c.draw_rect(b, VOID_BASE, true)
	# ★第一层：边界延续（docs/44 §四 / docs/43 §三-C7）。必须在暗林/暗角【之前】——
	#   它是"地面继续往外走"的那一层，林子应当长在它外面，而不是压在它上面。
	_draw_town_verge(c, map, bands, w, h)
	# 镇子漏进林子的光：贴着地图外缘最亮、向外 8 圈熄灭。旧稿在这里放过一条【矩形青色岸带】，
	# 眼验读作"给地图加了个装饰边框"——硬边框是原型感的来源，换成柔性光晕就消失了。
	for k in range(8 if _ap("bd:spill") else 0, 0, -1):
		var ring := map.grow(VOID_SPILL_TILES * T * (float(k) / 8.0))
		var a := 0.030 * (1.0 - float(k - 1) / 8.0)
		for b in bands:
			var seg := ring.intersection(b)
			if seg.size.x > 0.0 and seg.size.y > 0.0:
				c.draw_rect(seg, Color(VOID_SPILL.r, VOID_SPILL.g, VOID_SPILL.b, a), true)
	# 界外暗林：2 格粗粒度的确定性树冠（_hash，不抽 RNG、与相机无关）。太远的镜头只留底色。
	# 每格画【两丛】并给足抖动，否则规则网格会读成波点墙纸（第一版实测就是这个毛病）。
	var cell := T * 2.0
	var gx0 := int(floor(v.position.x / cell))
	var gy0 := int(floor(v.position.y / cell))
	var gx1 := int(ceil(v.end.x / cell))
	var gy1 := int(ceil(v.end.y / cell))
	var fade_px := VOID_FADE_TILES * T
	if _zoom >= 0.18 and (gx1 - gx0) * (gy1 - gy0) <= VOID_DECOR_MAX_CELLS and _ap("bd:canopy"):
		for gy in range(gy0, gy1):
			for gx in range(gx0, gx1):
				for sub in 2:
					var hsh := _hash(gx, gy, 91 + sub * 37)
					var cp := Vector2(gx * cell, gy * cell) \
						+ Vector2(float(hsh % 97), float(hsh / 97 % 97)) * (cell / 97.0)
					if map.has_point(cp):
						continue                # 界内不长树（R5：界内必须逐像素不变）
					# 离镇越远越黑越稀：林子要"退进夜里"，不是铺一层等密度的点
					var dist := _rect_dist(map, cp)
					var r := cell * (0.30 + float(hsh / 11 % 9) * 0.030)
					# ★第一层是"地面延续"，不长成片的树：暗树冠（亮度 ~30）压在贴边草坡（亮度 ~150）上，
					#   会把刚抹平的接缝换成一排更碎的高对比斑点。
					#   ⚠️ 判据必须是【整个圆】在第一层之外，不是圆心：树冠半径最大 1.08 格，
					#   只查圆心时实测仍有树冠伸到 1.47 格处，在 outband 上打出 81.1 的单点尖峰
					#   （比没做这一棒之前还差）——这是本棒第二个被数值抓到、肉眼看不出的回归。
					if dist - r < VERGE_TILES * float(T) * 0.80:
						continue
					var lit := clampf(1.0 - dist / fade_px, 0.0, 1.0)
					if hsh / 9409 % 100 >= int(26.0 + 52.0 * lit):
						continue
					var cc := VOID_CANOPY_A if hsh % 3 == 0 else (VOID_CANOPY_B if hsh % 3 == 1 else VOID_CANOPY_C)
					cc = cc.lerp(VOID_BASE, 1.0 - lit)      # 远处的树冠融进底色
					c.draw_circle(cp, r, cc)
					if lit > 0.25:
						c.draw_circle(cp + Vector2(-r * 0.28, -r * 0.32), r * 0.44,
							Color(cc.r, cc.g, cc.b, 0.50 * lit))   # 受光叶簇
	# 暗角：由地图外缘向外 6 圈加深 → 视线自然被收回镇子里
	for k in (6 if _ap("bd:vignette") else 0):
		var vg := Rect2(map).grow(VOID_SPILL_TILES * T + float(k + 1) * T * 2.6)
		var a := 0.050 + float(k) * 0.034
		# 逐圈压暗：只压 band 里落在这一圈【之外】的部分（四条外带），避免整片重复叠加
		for b in bands:
			var out_top := Rect2(b.position.x, b.position.y, b.size.x, maxf(0.0, vg.position.y - b.position.y))
			var out_bot := Rect2(b.position.x, maxf(b.position.y, vg.end.y), b.size.x, maxf(0.0, b.end.y - maxf(b.position.y, vg.end.y)))
			var iy0 := maxf(b.position.y, vg.position.y)
			var iy1 := minf(b.end.y, vg.end.y)
			var out_lft := Rect2(b.position.x, iy0, maxf(0.0, vg.position.x - b.position.x), maxf(0.0, iy1 - iy0))
			var out_rgt := Rect2(maxf(b.position.x, vg.end.x), iy0, maxf(0.0, b.end.x - maxf(b.position.x, vg.end.x)), maxf(0.0, iy1 - iy0))
			for o in [out_top, out_bot, out_lft, out_rgt]:
				if o.size.x > 0.0 and o.size.y > 0.0:
					c.draw_rect(o, Color(0, 0, 0, a), true)

# ══ 夜灯（加色光层）══════════════════════════════════════════════════════════
# ★ 为什么这一层【必须】是独立的加色子节点，而不是在 _draw() 里多画几个亮块：
#   `CanvasModulate` 在 tick 488（00:48）的乘子实测是 (0.4242, 0.4714, 0.7972)。它乘的是
#   每一个 CanvasItem 的最终颜色 ⇒ 普通绘制路径上每个通道的**上限**是 R=108 / G=120 / B=203，
#   白色的 luma 上限只有 **123.6**。改动前夜帧世界区最亮像素实测 max-channel=187、luma=113.7，
#   两者都已经贴着这个天花板。
#   ⇒ 在这条路上，「夜里出现一个亮的暖色像素」不是"没人做"，而是**算术上不可能**：
#     想让 max-channel 破 190，源色的 B 通道得 ≥238（那是一个冷白像素，不是灯）；
#     想让 luma 破 190，任何源色都做不到。
#   加色混合是唯一的出口：光的（已被乘暗的）颜色**加**在底色之上，叠够层数就能顶到 255，
#   而且叠加的是**暖色增量**，所以结果同时满足 R>G>B。这就是"点灯"与"把夜调亮"的区别。
#
# ★ 光色的选取有一半是算出来的、一半是眼验逼出来的。
#   算的那半：要让结果读作暖光，源色必须活过那个蓝偏乘子，即
#     R > (0.4714/0.4242)·G = 1.111·G   且   G > (0.7972/0.4714)·B = 1.691·B。
#   眼验的那半：第一版取 `#ffb45a`（乘暗后 (108,85,72)）——判据过了，**画面却是错的**。
#   三个通道差得太近 ⇒ 只要叠够层把 R 顶到 255，G/B 也一起顶上去，核心一律烧成**白团**，
#   出图上整排房子糊成一片、暖调全丢。压到下面这两个色（乘暗后 (108,73,38) / (108,62,19)）之后，
#   R 先到顶而 G/B 还留在一半，核心才读作**琥珀色的火**而不是白炽灯。
#   ⇒ 「满足暖光判据」与「看起来像灯」是两件事，前者是后者的必要不充分条件。
const LIGHT_WIN := X_LIGHT_WIN    # 窗/告示板：暖黄
const LIGHT_LAMP := X_LIGHT_LAMP   # 门楣/井灯/节日灯：更橙的火光
# ★ 光晕用一张**程序生成的径向衰减贴图**叠 LIGHT_STACK 次，不用同心圆堆。
#   第一版是 6 个同心 `draw_circle`：在 `--shot-fit`（zoom 0.23）下完全看不出问题，
#   但 R10 要求的**特写全帧眼验**（`--select player`，zoom 1.8）里，那 6 圈是 **6 道硬边同心环**，
#   像水波纹贴在地上。⇒ 「只做点采样」的孪生病是「**只在一个缩放档看**」。
#   贴图路同时更省：每盏灯 3 次 draw 而不是 6 次，且衰减形状与缩放无关。
const LIGHT_STACK := 3                 # 同一张衰减贴图叠几次（加色 ⇒ 中心累计 = stack × amp，可破 255 天花板）
const LIGHT_TEX_PX := 96               # 衰减贴图分辨率（线性过滤放大，96 足够）
const LIGHT_ZOOM_MIN := 0.10           # 低于此缩放不画（红线#3 手机：整镇俯瞰时几十盏灯只剩糊点）
var _light_tex: Texture2D = null       # 径向衰减贴图（懒建缓存）
var _lights: Node2D = null             # 加色光层（子节点；材质 BLEND_MODE_ADD）

## 径向衰减贴图：alpha = (1 − d)^1.35，d=归一化半径。指数在 1 附近导数趋 0 ⇒ 边缘没有可见的圈。
## 生成一次、缓存；纯 CPU、确定性，不进 digest。
func _light_texture() -> Texture2D:
	if _light_tex != null:
		return _light_tex
	var n := LIGHT_TEX_PX
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(float(x) - c, float(y) - c).length() / (float(n) * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.35)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_light_tex = ImageTexture.create_from_image(img)
	return _light_tex

## 水的夜罩（乘性，full-night 时的系数）。系数是**解出来的**，中间踩了一个坑值得记：
##   水瓦片的原始色是 (4,160,180)，但屏幕上的池塘是 (31,161,175) —— 差的那一截是
##   `_draw_climate_wash()` 压在**水之上**的两层大气罩（春 5% + 阴 16%）。第一版按屏幕色反推系数，
##   算出的夜色比实测亮 15%-21%，**因为那两层罩会把任何乘性调整稀释掉、还各自加回一份底色**。
##   把整条链写全再解（raw → ×tint → 春罩 → 阴罩 → `_daylight` 夜乘子 (0.4242,0.4714,0.7972)）：
##       (4,160,180) × (1.0,0.42,0.30) → 春/阴罩 → ×夜乘子 = **(13,41,59)**
##   绝对彩度 (max−min) **127 → 46（−64%）**，luma **67.2 → 36.6**（草地是 75.3）。
## R 系数取 1.0 不是偷懒：瓦片的红通道本来就只有 4/255，没有可减的东西。
## 蓝通道仍是三者里最高的——夜里的水本该是蓝黑的；要治的从来不是"它是蓝的"，
## 而是"**改动前它是全帧彩度最高、最响的那块**"。
const WATER_NIGHT := Color(1.0, 0.42, 0.30)
## ★ AV3(161) 水色【日间调和】：AV2 把池心换成暖生成瓦、把地面全烘暖后，两个池塘仍是全帧最冷的一块——
##   实测 noon 池水众数 (31,161,175) 的 **B>G**（蓝主导 = cyan-blue），与暖石村格格不入。WATER_DAY 只压【蓝通道】
##   一档（×0.90）：池水由 cyan-blue(B>G) 收进 **teal(G≥B)**（(31,161,175)→(31,161,158)、中心 (60,129,134)→(60,129,121)），
##   与参考 RIVER 行的 teal (50,125,133)（G≈B）同族。R/G 不动 ⇒ 不掉亮度、不改岸线台阶的【存在】，只挪蓝。
##   ⚠ 这一层【乘在所有水瓦上】（池心 + 8 向 CC0 岸线一视同仁）⇒ 直接压在 POND 门量的那道岸上 —— 已实测 POND 仍绿（见 docs/161）。
##   夜里从 WATER_DAY 插值到 WATER_NIGHT：夜 tick 深、_wn 高 ⇒ 夜罩≈原 WATER_NIGHT（蓝仅差 ~1/255），守住 D3-2 的夜彩度对照。
const WATER_DAY := Color(1.0, 1.0, 0.90)

## 加色光层。它只有 _draw()，内容全部由宿主的 _draw_night_lights() 提供——
## 不新增脚本文件（本棒独占 WorldView.gd），用内部类即可。
class NightLights extends Node2D:
	var host: Node = null
	func _draw() -> void:
		if host != null:
			host._draw_night_lights(self)

func _build_night_lights() -> void:
	_lights = NightLights.new()
	_lights.host = self
	_lights.name = "NightLights"
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = m
	_lights.z_index = 1        # 画在本节点自身之上（居民/雨也在本节点的同一个 canvas item 里）
	_lights.texture_filter = TEXTURE_FILTER_LINEAR   # 光晕要线性过滤：NEAREST 会把 96px 衰减贴图放大成马赛克
	add_child(_lights)

## 一盏灯：把衰减贴图在同一个矩形上叠 LIGHT_STACK 次。
## 加色下中心累计 = stack × amp × 光色 ⇒ amp≈0.5 时中心加约 1.5 份光，足以把地面顶到 255（破天花板）；
## 而衰减形状完全由贴图给出，与缩放无关 —— 这是"不出同心环"的那一半。
func _glow(c: Node2D, p: Vector2, rad: float, col: Color, amp: float) -> void:
	if amp <= 0.004 or rad <= 0.5:
		return
	var tex := _light_texture()
	if tex == null:
		return
	var r := Rect2(p - Vector2(rad, rad), Vector2(rad * 2.0, rad * 2.0))
	var m := Color(col.r, col.g, col.b, amp)
	for _k in LIGHT_STACK:
		c.draw_texture_rect(tex, r, false, m)

## 窗户是否点着灯（确定性、纯渲染）。`_draw_window` 与 `_collect_lights` 共用同一个判据——
## 分成两份必然漂移，于是会出现"亮着的窗没有光晕/黑窗底下有一摊光"。
## 只点约 55%：00:48 的小镇不该家家灯火通明，"有几户还醒着"比"全亮"更像有人住。
func _window_lit(x: int, y: int) -> bool:
	return Sim._hash01("win:%d,%d" % [x, y]) < 0.55

## 一扇亮窗的光池。半径带确定性抖动（0.72-1.18 格）——**这是 docs/41 §6-★「等距连续 = 相框」的预防**：
## 窗户本来就是沿墙等距开的，如果每盏光晕又一模一样大，一栋房子就被一串等距等大的光珠**描了个边**，
## 比原来那条硬墙线更抢眼。抖动 + 只点 55% 就把它打散成"有几户还醒着"。
func _win_light(x: int, y: int) -> Dictionary:
	var jitter := 0.72 + 0.46 * Sim._hash01("winr:%d,%d" % [x, y])
	return {"p": Vector2(x * T + T * 0.5, y * T + T * 0.46),
		"r": T * jitter, "c": LIGHT_WIN, "a": 0.26}

## 收集本帧的所有光源（世界像素坐标）。纯几何 + 确定性哈希，不抽 RNG、不读 Sim 的可变状态之外的东西。
## ⚠️ 本波【故意不新增实体灯柱】：灯柱在正午也得在，而"正午帧逐像素不动"是这一棒的天然负对照
##    （docs/46 §二-D3 验收）。所以光源一律挂在**已经存在的几何**上：窗、门、井、告示板、节日灯笼、
##    以及 enclosed 房间自己的屋内灯。实体灯柱留给 D6（美术落地）。
func _collect_lights() -> Array:
	var out: Array = []
	var doorset := {}
	for d in Sim.world.get("doors", []):
		var dp: Array = (d as Dictionary).get("pos", [0, 0])
		doorset[Vector2i(int(dp[0]), int(dp[1]))] = true
	# ① 外墙窗户（与 _draw_facades 同一套位置与同一个 _window_lit 判据）
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var typ := String(a.get("type", ""))
		if typ == "" or typ == "plaza":
			continue
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2]); var bh := int(r[3])
		for i in range(1, bw - 1):
			if i % 2 == 0:
				continue
			for wy in [y0, y0 + bh - 1]:
				if doorset.has(Vector2i(x0 + i, wy)) or not _window_lit(x0 + i, wy):
					continue
				out.append(_win_light(x0 + i, wy))
		for j in range(1, bh - 1):
			if j % 2 == 0:
				continue
			for wx in [x0, x0 + bw - 1]:
				if doorset.has(Vector2i(wx, y0 + j)) or not _window_lit(wx, y0 + j):
					continue
				out.append(_win_light(wx, y0 + j))
	# ② 门楣灯（_draw_town_doors 已经画了一条 #f0d68a 暖光带 —— 这里给它真正的光池）
	var main := get_parent()
	var sg = main.get("_sg") if main != null else null
	if sg != null:
		for p in sg.portals:
			var fr: Dictionary = p.get("from", {})
			if String(fr.get("space", "")) != "town" or String(fr.get("floor", "")) != "outdoor" or String(p.get("kind", "")) != "door":
				continue
			if String((p.get("to", {}) as Dictionary).get("space", "")).begins_with("test_"):
				continue                                   # 测试平面的门本体已不画（见 _draw_town_doors），别给它点灯
			var dpos: Array = fr.get("pos", [0, 0])
			out.append({"p": Vector2(int(dpos[0]) * T + T * 0.5, int(dpos[1]) * T + T * 0.30),
				"r": T * 1.35, "c": LIGHT_LAMP, "a": 0.44})
	# ③ 广场地标：水井挂灯 + 告示板灯（广场是全镇唯一的公共夜间光源，不点它夜里镇中心是个黑洞）
	for lm in Sim.world.get("landmarks", []):
		var lp: Array = lm.get("pos", [0, 0])
		var lx := int(lp[0]) * T; var ly := int(lp[1]) * T
		match String(lm.get("type", "")):
			"well":
				out.append({"p": Vector2(lx + T * 0.5, ly + T * 0.06), "r": T * 2.2, "c": LIGHT_LAMP, "a": 0.52})
			"board":
				out.append({"p": Vector2(lx + T * 0.5, ly + T * 0.24), "r": T * 1.4, "c": LIGHT_WIN, "a": 0.27})
	# ④ 节日灯笼（fest_ 物件本来就画成暖光灯笼，只有节日日存在）
	for id in Sim.world.get("objects", {}):
		var o: Dictionary = Sim.world["objects"][id]
		if String(o.get("space", "town")) != "town":
			continue                                   # 平面守卫：室内家具不在镇上（同 _draw 的物件循环）
		if not String(id).begins_with("fest"):
			continue
		var fp: Vector2i = o["pos"]
		out.append({"p": Vector2(fp.x * T + T * 0.5, fp.y * T + T * 0.4), "r": T * 1.9, "c": LIGHT_LAMP, "a": 0.46})
	# ⑤ 屋内灯（_draw_building 已经画了暖池，但它是【普通混合】⇒ 顶到天花板也只有 max<110）。
	#    这里给 enclosed 房间补一份加色的光，让屋子在夜里真的"亮着"，并从北窗往外洒一小片。
	for rid in Sim.world.get("rooms", {}):
		var rm: Dictionary = Sim.world["rooms"][rid]
		if not bool(rm.get("enclosed", false)):
			continue
		var rr: Array = rm.get("rect", [0, 0, 0, 0])
		var inner := Rect2(rr[0] * T, rr[1] * T, rr[2] * T, rr[3] * T)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			continue
		out.append({"p": inner.get_center(), "r": maxf(inner.size.x, inner.size.y) * 0.52,
			"c": LIGHT_WIN, "a": 0.16})
		out.append({"p": Vector2(inner.get_center().x, inner.position.y - WALL * 0.6),
			"r": minf(inner.size.x, T * 3.0) * 0.62, "c": LIGHT_WIN, "a": 0.14})
	return out

## 加色光层的绘制入口（由内部类 NightLights._draw 调用）。
## ★ `_night_amt()` 在正午（tod=0.5）恒为 0 ⇒ 本函数直接返回、一个像素都不画。
##   这就是本棒的天然负对照："正午帧改前改后 diff bbox 必须是 None"。
func _draw_night_lights(c: Node2D) -> void:
	if Sim.world.is_empty() or not _ap("lights"):
		return
	var main := get_parent()
	var pb = main.get("_probe") if main != null else null
	if pb != null and String(pb.active_space) != "town":
		return                                   # 只点镇上的灯；室内平面有自己的一套照明
	var night := _night_amt()
	if night <= 0.001:
		return
	_refresh_view_metrics()                      # 光层与本节点共用变换，读同一个 _vis 做裁剪
	if _zoom < LIGHT_ZOOM_MIN:
		return
	for L in _collect_lights():
		var p: Vector2 = L["p"]
		var rad: float = L["r"]
		if not _vis.intersects(Rect2(p - Vector2(rad, rad), Vector2(rad * 2.0, rad * 2.0))):
			continue                             # 视口外的灯不画（布局与相机无关）
		_glow(c, p, rad, L["c"], float(L["a"]) * night)

func _draw() -> void:
	var _at0 := Time.get_ticks_usec()   # D7 量具：_draw() 的 GDScript 墙钟（docs/33 §7「埋计时器测」）
	_draw_body()
	_audit_usec = Time.get_ticks_usec() - _at0

func _draw_body() -> void:
	_refresh_view_metrics()
	_void_sync()                # 界外虚空已搬到独立子层（见 _draw_void_layer），这里只判断要不要让它重画。
	                            # ★必须在下面的室内 early-return **之前**：进店时界外层要被通知擦掉自己，
	                            #   否则它会带着上一次的镇外林子留在室内画面的最底层。
	var _main := get_parent()
	var _pb = _main.get("_probe") if _main != null else null
	if _pb != null and String(_pb.active_space) != "town":
		_draw_interior_backdrop(_main, _pb)        # 先铺暗底/暗角/外圈落影，室内不再泡在一片死灰里
		_draw_space_placeholder()                 # 非 town：只画该 Space/Floor（active-space 渲染）
		return
	if Sim.world.is_empty():
		return
	var w: int = int(Sim.world.get("width", 24))
	var h: int = int(Sim.world.get("height", 16))
	var veg := _season_veg()    # 四季：植被的乘算色偏（春新绿 / 夏深浓 / 秋金黄 / 冬冷褪）
	# 地面：逐格选草地变体（有切片时）→ 否则平铺单图 → 否则色块
	if not _grass.is_empty():
		if _grass_var.is_empty():
			_build_grass_var(w, h)
		# 只画【看得见的】格子。旧版每帧无条件铺满 64x48 = 3072 个 draw_texture_rect，
		# 而 1280x768 视口在 zoom=1 时只装得下约 27x16 ≈ 430 格 —— 其余 85% 是纯浪费的填充率，
		# 这是手机上最便宜的一笔回收。变体仍由 _hash(tx,ty) 决定，与看哪儿无关 → 画面逐像素不变。
		var tx0 := maxi(0, int(floor(_vis.position.x / float(T))))
		var ty0 := maxi(0, int(floor(_vis.position.y / float(T))))
		var tx1 := mini(w, int(ceil(_vis.end.x / float(T))))
		var ty1 := mini(h, int(ceil(_vis.end.y / float(T))))
		if not _ap("grass"):
			ty1 = ty0                # D7 审计：关掉草地 pass（出货路径不走这一行）
		# ★D7 合批：**按变体分组**画，而不是逐格切纹理。
		#   旧写法沿着行走，三种草地纹理随机交替 ⇒ 每换一次纹理就断一次批
		#   ⇒ 实测 3072 格烧掉 **1425 次 draw call**（全镇取景，占世界层 29.4%）。
		#   分组之后同一张纹理连着画，3072 格塌成 3 段。
		#   **逐像素不变是可证的，不是"看起来一样"**：三张草地切片实测**全不透明**
		#   （alpha 恒 255）、且每格恰好占 `Rect2(tx*T, ty*T, T, T)` 一个互不相交的格子
		#   ⇒ 一组互不相交的不透明矩形，**画的顺序不影响任何一个像素**。
		#   变体归属仍是 `_hash(tx,ty,3)` 的纯函数（缓存在 `_grass_var` 里），与相机无关。
		for gi in _grass.size():
			var gt: Texture2D = _grass[gi]["t"]
			for ty in range(ty0, ty1):
				var grow := ty * w
				for tx in range(tx0, tx1):
					if int(_grass_var[grow + tx]) == gi:
						draw_texture_rect(gt, Rect2(tx * T, ty * T, T, T), false, veg)
	else:
		var grass := Art.ground_tex()
		if grass != null:
			draw_texture_rect(grass, Rect2(0, 0, w * T, h * T), true, veg)
		else:
			draw_rect(Rect2(0, 0, w * T, h * T), GRASS_FALLBACK * veg, true)   # D6：原为 Art.ground（深蓝灰），而这是【缺草地切片时的地面】—— 用同文件的草色兜底才对，且让 Art.gd 不再持有任何色值
	var dirt := Art.terrain_tex("dirt")
	# 水面（map.json water 层）：铺在草地之上、区域/建筑之下，作为地形读。深蓝底 + 浅蓝格纹岸边微光，
	# 用确定性 _hash 做静态涟漪（不抽 RNG、不进 digest）。
	if not _terrain_built:
		_build_terrain()
	var wtile := Art.terrain_tex("water")
	# ★★ 岸线（G5 / docs/49 §七）。改前：两个 8x5 水域各铺一张**纯色填充瓦**，
	#   渲染成硬 90° 直角的青色矩形直接压在草地上 —— 真机帧上北池取样 9856 px **只有 1 种颜色**。
	#   根因不是"没人画岸线"，而是**当初切图切错了一格**：出货 water.png 切自 CC0 总表的 (18,11)，
	#   那是一个自动贴图块的**正中心**；它外面那一圈（岸泥 + 浅水亮边）一直躺在同一个文件里没人取。
	#   现在按四邻的水/陆关系选 9 张瓦之一（`_water_by_slot`，在 `_build_terrain` 里一次算好）。
	#   **中心那张仍是原来的 water.png，逐像素未动** ⇒ 池心颜色不变，改动只发生在边界一圈。
	# ★ 夜里把水压下去（docs/46 §二-D3-2）。改动前实测：夜帧世界区**彩度最高的东西就是这两个池塘**——
	#   水色 (31,161,175) 是蓝主导，而 `_daylight` 夜里的乘子 (0.4242, 0.4714, 0.7972) 恰恰**最不压蓝**
	#   ⇒ 水的绝对彩度 (max−min) 从白天的 144 只掉到 **127**，而草地从 94 掉到 **25**。
	#   于是全局乘暗把整座镇子压进夜色，唯独两个青色矩形几乎原样留在那里，成了画面上最响的东西。
	#   修法是给水一层随夜量渐入的**乘性夜罩**：白天恒为白（正午 `_night_amt()==0` ⇒ 逐像素不动）。
	# ⚠ G5 实测记一笔：`WATER_NIGHT` 是给**整格都是水**的贴图标定的，而岸线瓦里有一圈**岸泥**。
	#   夜里这个重红偏的乘子把岸泥染成锈褐（真机夜帧实测 (106,112,66) → (50,33,37)）。
	#   **没有改它**，理由是量过：夜帧里岸泥的绝对彩度(max−min)=26，**低于**草地 33、也低于水 41
	#   ⇒ docs/46 §二-D3-2 守的那条「入夜后水不许是画面上最响的东西」没有被破坏，
	#   锈褐岸读作"湿泥滩"也说得通。若将来要分开染，得先给岸泥单独标一个夜罩并重跑 D3-2 的彩度对照，
	#   而不是随手把这里的 lerp 调淡（调淡会让岸线里那圈**浅水亮边**在夜里重新跳出来）。
	var wtint := WATER_DAY                    # AV3(161)：日间基调不再是纯白，而是压过蓝的 teal 调和罩（见 WATER_DAY 抬头）
	var _wn := _night_amt()
	if _wn > 0.001:
		wtint = WATER_DAY.lerp(WATER_NIGHT, _wn)   # 从 teal 日基插值到重红夜罩（夜深处≈原 WATER_NIGHT）
	# ★合批：**按瓦片分组**画（沿用 D7 在草地/土路上立的那条规矩），而不是逐格切纹理。
	#   `_water_by_slot` 的每一项是 [瓦片名, 该瓦片的格子下标数组]，分组在 `_build_terrain` 里做好。
	#   **逐像素不变可证**：9 个 slot 是水格集合的一个**划分**（每格恰好属于一个 slot），
	#   每格恰好画进 `Rect2(wx*T, wy*T, T, T)` 这一个**互不相交**的格子里
	#   ⇒ 任何一格的像素只由它自己那张瓦片决定，与别的格子画在它前面还是后面无关。
	#   （边缘瓦有透明区，但混合的对象是**它底下那格草地**，不是邻格的水 ⇒ 顺序依旧无关。）
	for pair in _ac("water", _water_by_slot):
		var stile: Texture2D = Art.terrain_tex(String(pair[0]))
		if stile == null:
			stile = wtile                      # 缺岸线瓦 → 退回填充瓦（画面回到改前的纯色矩形，不至于开天窗）
		for idx in pair[1]:
			var wx: int = idx % w
			var wy: int = idx / w
			var wr := Rect2(wx * T, wy * T, T, T)
			if stile != null:
				draw_texture_rect(stile, wr, false, wtint)
			else:
				draw_rect(wr, P_WATER_DEEP * wtint, true)
				if _hash(wx, wy, 21) % 100 < 30:   # 静态涟漪高光
					draw_rect(Rect2(wx * T + T * 0.18, wy * T + T * 0.30, T * 0.42, T * 0.12), Color(P_WATER_LIT, 0.35) * wtint, true)

	# ── AP1(140) 门→广场【石铺连街】：把原来的土径重铺成暖石板 cobble ────────────────────────────
	# **只改绘制/调色板**：`_path_set` 仍由 `_build_paths` 从 doors/plaza（map.json 只读）烘出，一格 walkable 都没动
	# ⇒ Sim 读 blockers、读不到这一层，**零金标**。石街(P_STREET) 与广场(P_PLAZA) 同暖族 ⇒ 读作一体的连街，不再是孤岛间的土径。
	if not _paths_built:
		_build_paths()
	if dirt != null:
		# ① dirt 打底：保住 3x 像素颗粒（纯色路面在像素游戏里读作"没画完"，同草地那条注释）。合批一趟。
		for idx in _ac("paths", _path_set):
			draw_texture_rect(dirt, Rect2((idx % w) * T, (idx / w) * T, T, T), false)
		# ② 石板铺面：每格盖一层暖石底 + 4 块 hash 明暗鹅卵石（颗粒）+ 石缝十字。逐格确定性、每格互不相交。
		#   **确定性**：明暗档只读本格 `_hash(rx,ry,45)`（无 RNG/Time）⇒ `--shot` 逐像素可复现（红旗#4）。
		for idx in _ac("paths", _path_set):
			var rx: int = idx % w; var ry: int = idx / w
			var rr := Rect2(rx * T, ry * T, T, T)
			# AV3(161)：整格暖石底再抖一档（_hash(rx,ry,46)，确定性、无 RNG/Time）——多数格保持 P_STREET、
			#   少数微亮/微沉，让石街从"一条匀色带"变成"铺过的鹅卵石路"（与广场/工坊石同一套暖石 jitter 语言）。
			var pv := _hash(rx, ry, 46) % 5
			var pbase: Color = P_STREET
			if pv == 0: pbase = P_STREET.lightened(0.06)
			elif pv == 1: pbase = P_STREET.darkened(0.07)
			elif pv == 2: pbase = S_STREET_LO
			draw_rect(rr, Color(pbase.r, pbase.g, pbase.b, 0.90), true)                           # 暖石底（透一点土颗粒；整格 jitter）
			for sj in range(2):
				for si in range(2):
					var hv := _hash(rx * 2 + si, ry * 2 + sj, 45) % 3
					var sc: Color = P_STREET if hv == 0 else (S_STREET_HI if hv == 1 else S_STREET_LO)
					draw_rect(Rect2(rx * T + si * T * 0.5 + 1.0, ry * T + sj * T * 0.5 + 1.0, T * 0.5 - 2.0, T * 0.5 - 2.0), Color(sc.r, sc.g, sc.b, 0.55), true)
			draw_rect(Rect2(rx * T, ry * T + T * 0.5 - 0.5, T, 1.0), Color(S_STREET_SEAM.r, S_STREET_SEAM.g, S_STREET_SEAM.b, 0.5), true)   # 横缝
			draw_rect(Rect2(rx * T + T * 0.5 - 0.5, ry * T, 1.0, T), Color(S_STREET_SEAM.r, S_STREET_SEAM.g, S_STREET_SEAM.b, 0.5), true)   # 竖缝
		# ③ 路缘石：每条街格【朝非铺装的那一侧】压一条暗石边 → 读作"砌出来的街"，不是踩出来的土径。
		#   路网全在地图内部（x12-52 / y9-37，实测），邻格 ±1 不越界 ⇒ `_is_paved` 无绕行下标之虞。
		for idx in _ac("paths", _path_set):
			var cxx: int = idx % w; var cyy: int = idx / w
			var bx := cxx * T; var by := cyy * T
			if not _is_paved(cxx, cyy - 1): draw_rect(Rect2(bx, by, T, T * 0.10), S_CURB, true)                  # 上缘
			if not _is_paved(cxx, cyy + 1): draw_rect(Rect2(bx, by + T * 0.90, T, T * 0.10), S_CURB, true)       # 下缘
			if not _is_paved(cxx - 1, cyy): draw_rect(Rect2(bx, by, T * 0.10, T), S_CURB, true)                  # 左缘
			if not _is_paved(cxx + 1, cyy): draw_rect(Rect2(bx + T * 0.90, by, T * 0.10, T), S_CURB, true)       # 右缘

	# 区域【真地板】：每个 district 按 type 铺木/石/铺装地板（旧版只有广场有地板，其余七个区只有一层
	# 0.10 alpha 的淡色罩 —— 那层淡到什么也读不出来，于是墙里全是草，房子读作"围了圈墙的院子"）。
	if _ap("areafloor"):
		_draw_area_floors(dirt)
	# 室内房间 → 画成【真·建筑】（docs/16 / docs/19 §9）：外墙有厚度 + 落地阴影 + 屋檐、南墙开门、北墙开窗、
	# 室内按房型铺材质地板，有人时透暖光。参照 Stardew / Stoneshard / ZeroSievert 的"切顶俯视"读法：
	# 建筑必须有体积，人才有比例——旧版把 6x4 的房间画成一块半透明色块 + 文字标签，读作"色区"而非"房子"。
	# 纯渲染：不进 digest、不抽 RNG（门窗变体用 Sim._hash01(room_id) 确定性选）。红线不动。
	for rid in _ac("rooms", Sim.world.get("rooms", {})):
		var rm: Dictionary = Sim.world["rooms"][rid]
		var rr: Array = rm.get("rect", [0, 0, 0, 0])
		_draw_building(str(rid), Rect2(rr[0] * T, rr[1] * T, rr[2] * T, rr[3] * T),
			str(rm.get("type", rid)), bool(rm.get("enclosed", false)))
	# （网格线已移除：Stardew/Stoneshard/ZeroSievert 都不画格子——硬网格是最大的"原型感"来源。
	#   瓦片结构由草地变体/地板纹理自然读出。需要格子时走 dev overlay，不进玩家视图。）
	# （1 格小屋地标已移除：那正是"房子=人一般大"的比例谎言来源；建筑现由上面的真·建筑体现。）

	# 分类型建筑外墙（map.json walls 层，按所属建筑 type 上色）：buildings.json 清空后，districts 的体积就靠这层墙读出。
	# 切顶俯视：落地阴影 + 三段墙面(顶棱高光/主面/墙脚暗边)让 1 格墙读作有厚度；颜色由类型区分（住宅暖木/商业米黄/公共蓝灰/工坊灰石）。门缺口天然留白。
	for idx in _ac("walls", _wall_set):
		var sx: int = idx % w
		var sy: int = idx / w
		var pal: Dictionary = BLD_PAL.get(String(_wall_type.get(idx, "workshop")), BLD_PAL["workshop"])
		draw_rect(Rect2(sx * T + 2, sy * T + T * 0.55, T, T * 0.5), Color(0, 0, 0, 0.22), true)      # 落地阴影
		draw_rect(Rect2(sx * T, sy * T, T, T), pal["face"], true)                                     # 墙主面
		draw_rect(Rect2(sx * T, sy * T, T, T * 0.22), pal["top"], true)                               # 顶棱高光
		draw_rect(Rect2(sx * T, sy * T + T * 0.86, T, T * 0.14), pal["foot"], true)                   # 墙脚暗边
	# 屋檐 + 招牌：每栋（非广场）沿顶墙内侧铺一条屋檐色带 + 门上方挂类型招牌图标 → 类型一眼可辨。
	if _ap("facades"):
		_draw_facades()            # P3 打磨：开窗（夜透暖光）+ 住宅/工坊烟囱——先画在墙面上
	if _ap("dressing"):
		_draw_building_dressing(w) # 再压屋檐/招牌（自然遮住顶墙窗上沿，像真的屋檐）
	if _ap("arealabels"):
		_draw_area_labels()        # 区名画在墙【之后】（旧版画在顶墙格上，被墙盖掉，等于没画）
	# AP-port(163)：给滩头 dock 画真·港口身份（栈桥/系缆桩/货箱/渔船/船屋 + 交通路牌）。
	#   ★画在 arealabels 之【后】：整-镇取景(--shot-fit)下「滩头」区名字号被拉到 ~52px、正压在栈桥中央，
	#     会糊住渔船/货堆；港口结构本身已让 dock 一眼是码头 ⇒ 让结构盖过那个巨字（诚实边界见 docs/163 §五）。
	#   零金标（只读 areas.dock.rect，Sim 一格读不到本层）；POND 安全（一像素都不画到水线 py 之上，见 _draw_port）。
	if _ap("port"):
		_draw_port()

	# 装饰散布（区域外草地上的花/草丛/石，确定性布局；在物件与居民之下。**这里没有树**，见 _build_decor 抬头）
	if not _decor_built:
		_build_decor()
	for it in _ac("decor", _decor_items):
		var dtex: Texture2D = it["tex"]
		var c: Vector2i = it["cell"]
		if not _vis.has_point(Vector2(c.x * T, c.y * T)):
			continue                       # 视口外的花草石不画（布局仍由 _build_decor 一次性确定，与相机无关）
		var dw := float(dtex.get_width()) * (float(T) / 16.0)
		var dh := float(dtex.get_height()) * (float(T) / 16.0)
		# 底对齐格子（高物件如树向上伸出）；四季色偏与草地同源
		draw_texture_rect_region(dtex, Rect2(c.x * T + (T - dw) * 0.5, (c.y + 1) * T - dh, dw, dh), Rect2(0, 0, dtex.get_width(), dtex.get_height()), veg)

	# AP1(140) verge 街具（路灯/花坛/长椅/系缆柱）：在花草之上、物件/居民之下。纯 draw_* 图元，落点由 _build_street_props 一次性确定。
	# 复用 "decor" 审计 pass（不新增 pass ⇒ AUDIT_PASSES 闭合校验一字不动）。视口裁剪同花草。
	for sp in _ac("decor", _street_prop_items):
		var spc: Vector2i = sp["cell"]
		if not _vis.has_point(Vector2(spc.x * T, spc.y * T)):
			continue
		_draw_street_prop(int(sp["kind"]), spc)

	# authored 阻挡树（map.json trees 层）：这些是【会挡路】的真树（与上面可踩的程序化花草区分开）。
	# 用 tree_big 切图底对齐画；缺切图则程序化画树冠+树干。占满格 → 玩家一眼读出"这里过不去"。
	var ttex := Art.decor_tex("tree_big")
	# ★ V3 林相：画法从 `_tree_draw` 取（偏移/镜像/明暗档 + 行优先次序，见 _build_tree_styles）。
	#   `_ac("trees", …)` 的 pass 名不变 ⇒ D7 的逐 pass draw-call 审计仍然对得上同一行。
	for st in _ac("trees", _tree_draw):
		var tc: Vector2i = st["cell"]
		if ttex != null:
			var tdw := float(ttex.get_width()) * (float(T) / 16.0)
			var tdh := float(ttex.get_height()) * (float(T) / 16.0)
			var toff: Vector2 = st["off"]
			var dst := Rect2(tc.x * T + (T - tdw) * 0.5 + toff.x, (tc.y + 1) * T - tdh + toff.y, tdw, tdh)
			# 明暗档走 modulate（进顶点色，**不**换纹理 ⇒ 156 棵仍然合成一批；见 _tree_style 下面那段"为什么没有镜像"）
			draw_texture_rect_region(ttex, dst, Rect2(0, 0, ttex.get_width(), ttex.get_height()), veg * (st["tone"] as Color))
		else:
			# ★ 缺切图的程序化回退**蓄意不吃 V3 的分化**：它只在 `tree_big.png` 不存在时可达，
			#   而那张图今天由 asset_gate 的 GATED 表守着 ⇒ 这条分支在出货树上跑不到。
			#   给一条跑不到的路加分化，等于给它加一份没人验过的行为（docs/41 §2.5 第三个盲区的形状）。
			var cx: float = tc.x * T + T * 0.5
			draw_rect(Rect2(tc.x * T + T * 0.30, tc.y * T + T * 0.55, T * 0.40, T * 0.45), X_WOOD_MID, true)  # 树干
			draw_circle(Vector2(cx, tc.y * T + T * 0.42), T * 0.42, P_FOLIAGE_D * veg)                          # 树冠
			draw_circle(Vector2(cx - T * 0.18, tc.y * T + T * 0.30), T * 0.24, P_FOLIAGE_M * veg)                # 高光叶

	if _ap("towndoors"):
		_draw_town_doors()         # P3 UX：给能进的建筑画醒目木门 + 招牌（点门进店）
	if _ap("landmarks"):
		_draw_landmarks()          # P2-4 公共地标（水井 / 告示板）：程序化画在地形层、居民之下

	# 对象：CC0 物件精灵。★槽位取自**显式** OBJ_SLOT_BY_TYPE 表（不再是 id 前缀，见文件末尾 H3 一节）；
	# 表里没有 ⇒ 走 _draw_unmapped_object（品红 + push_error），**不再**静默画一个和墙同色的暖石灰框。
	for id in _ac("objects", Sim.world.get("objects", {})):
		var o: Dictionary = Sim.world["objects"][id]
		# ★ 平面守卫。`_compile_interiors()`(Sim.gd:532) 把室内家具也塞进 world["objects"]，坐标是
		# 【室内局部格】(0..7, 0..6) 且带 space/floor 标记。这个循环此前无条件画【全部】对象，于是那些
		# 家具被当成 town 坐标画在了地图西北角——`slot` 取到 "cafe1f"/"home1f" 没有贴图 ⇒ 掉进下面的
		# 占位分支，把原始数据键（table / 床 / 桌子 / 咖啡吧台）用 draw_string 直接印在草地上。
		# 它进了本波【每一张】已发布的截图与 GIF，八根棒和一次合并验证都没看见——因为所有视觉验收
		# 用的都是点采样与 diff-bbox，没有一条是"有人把整帧看一遍"（外部评审 2026-07-26 抓到）。
		if String(o.get("space", "town")) != "town":
			continue
		var p: Vector2i = o["pos"]
		var slot := _obj_slot(String(id), o)
		var base := Vector2(p.x * T, p.y * T)
		match slot:
			"bed": _draw_bed(base)
			"stove": _draw_stove(base)
			"dock": _draw_dock(base)
			"fest": _draw_festival(base)   # Wave 2b：节日机会地形（灯笼，暖光）
			_:
				var otex: Texture2D = Art.object_tex(slot) if slot != "" else null
				if otex != null:
					var s := OBJ_PX          # 16px 源 × 3（= 整格）：与地面/装饰同一个像素尺，不再 2.5x 融化
					draw_texture_rect_region(otex, Rect2(base.x + (T - s) * 0.5, base.y + (T - s) * 0.5, s, s), Rect2(0, 0, otex.get_width(), otex.get_height()))
				else:
					_draw_unmapped_object(base, String(id), o)

	# 四季 / 天气的大气罩：压在地形与建筑之上、居民之下（居民不该被刷成一片霜白）
	if _ap("climate"):
		_draw_climate_wash(w, h)

	# ── 社交层（在 Agent 之下先画连线，再画 Agent 与标记）──────────────────
	# 每帧预建冲突/约会端点集 → _draw_agent 用 O(1) 查代替 per-agent 线性扫 Sim.conflicts/commitments（N 大时省 O(N×|conflicts|)）。
	_rc_conflict_ids = {}
	for _c in Sim.conflicts:
		var _s := String(_c["status"])
		if _s == "simmering" or _s == "escalated" or _s == "confronted" or _s == "lingering":
			_rc_conflict_ids[_c["a"]] = true; _rc_conflict_ids[_c["b"]] = true
	_rc_meet_ids = {}
	for _c in Sim.commitments:
		if String(_c["status"]) == "active":
			_rc_meet_ids[_c["a"]] = true; _rc_meet_ids[_c["b"]] = true
	# D5：正在社交事务里的双方 —— 与 _draw_talking_links() 判定同源（option.kind=="social"），
	# 但那里只画线，这里要的是"这两个人的名牌该恒显"。partner 可能在室内/不存在，照记不影响。
	_rc_social_ids = {}
	for _a in Sim.agents:
		var _o = _a.get("option")
		if _o != null and String(_o.get("kind", "")) == "social":
			_rc_social_ids[String(_a["id"])] = true
			var _pid := String(_o.get("partner", ""))
			if _pid != "":
				_rc_social_ids[_pid] = true
	_rc_sel_id = _selected_id()
	if _ap("factionrings"):
		_draw_faction_rings()      # S3a：派系归属（同色脚环）
	if _ap("pactlinks"):
		_draw_pact_links()         # S3b：互助盟约（青色双线 + 🤝）
	if _ap("rellines"):
		_draw_relationship_lines()
	if _ap("talklinks"):
		_draw_talking_links()
	for ag in _ac("agents", Sim.agents):
		if String(ag.get("space", "town")) != "town":
			continue            # P3 Tier-B：非-town 平面的居民(在咖啡馆室内的阿丽)不画在镇上——否则会用室内格坐标在镇上"鬼影"
		_draw_agent(ag)

	# 降水画在【居民之上】：雨/雪在人前面落，才读作下雨/下雪而不是地面贴图。
	# 冬季降水统一走雪（_draw_snow 自己按 weather 调密度）；其余季节的「雨」才走雨丝 ⇒ 二者不叠加。
	if Sim.season_today == "冬" and _ap("snow"):
		_draw_snow()            # AI1（编号129）：冬雪。只读 season，纯表现层。
	elif Sim.weather_today == "雨" and _ap("rain"):
		_draw_rain()            # AI1（编号129）：强化雨（两档景深雨丝 + 地面涟漪）

	if dbg_nav:                 # P2-4 开发叠层（N 键）：可视化导航权威数据——阻挡格 + 交互格
		_draw_nav_overlay(w)

## P2-4 导航开发叠层：红=Sim._blocked 阻挡权威集（墙/水/树/家具），绿点=家具的可走正交邻格（居民站着用的交互格）。
## 纯 View、只读 Sim._blocked/objects，绝不写 Sim；只有 dbg_nav 开时才画（默认关，玩家视图不受影响）。
func _draw_nav_overlay(w: int) -> void:
	for idx in Sim._blocked:
		var bx: int = idx % w; var by: int = idx / w
		draw_rect(Rect2(bx * T, by * T, T, T), Color(0.92, 0.22, 0.22, 0.22), true)
		draw_rect(Rect2(bx * T, by * T, T, T), Color(0.92, 0.22, 0.22, 0.5), false, 1.0)
	for oid in Sim.world.get("objects", {}):
		var op: Vector2i = Sim.world["objects"][oid].get("pos", Vector2i.ZERO)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = op + d
			if n.x >= 0 and n.y >= 0 and n.x < w and not Sim._blocked.has(n.y * w + n.x):
				draw_rect(Rect2(n.x * T + T * 0.3, n.y * T + T * 0.3, T * 0.4, T * 0.4), Color(0.3, 0.95, 0.42, 0.6), true)

## P2-4 公共基础设施地标：程序化画水井（石圈+蓝顶）与告示板（木板+红顶+纸），风格与分类型建筑一致。
## P3 UX：镇上给每个【能进的建筑】画一扇醒目木门 + 悬挂招牌（portal from=town/outdoor 的 door）→ 玩家一眼看出可点进入。
func _draw_town_doors() -> void:
	var main := get_parent()
	var sg = main.get("_sg") if main != null else null
	if sg == null:
		return
	for p in sg.portals:
		var fr: Dictionary = p.get("from", {})
		if String(fr.get("space", "")) != "town" or String(fr.get("floor", "")) != "outdoor" or String(p.get("kind", "")) != "door":
			continue
		# ★ R10 全帧眼验抓到的：`1b20071` 只拿掉了测试平面那块**招牌**（「测试阁楼」，见下面第二处 test_ 判断），
		#   而**门本体**（门框/门板/门楣暖光/门把/落地影）还立在镇子西北角 `[3,3]` 的空草地上——
		#   spaces.json 的 `p_loft_door` → `test_loft`，一个纯测试用的 Space 端口。
		#   它在本波之前的**每一张已发布素材**里都在，谁也没看见：它孤零零一格、在没有房子的角落。
		#   这次是加色光层把它点成了一盏灯才够刺眼 —— 两个各自不显眼的东西叠起来才被抓到，
		#   正是"点采样 + diff-bbox"验收永远抓不到的那一类（docs/46 §〇-R10 的原话）。
		var to0: Dictionary = p.get("to", {})
		if String(to0.get("space", "")).begins_with("test_"):
			continue
		var pos: Array = fr.get("pos", [0, 0])
		var x := int(pos[0]) * T; var y := int(pos[1]) * T
		draw_rect(Rect2(x + 2, y + T * 0.5, T - 4, T * 0.5), Color(0, 0, 0, 0.25), true)          # 落地阴影
		draw_rect(Rect2(x + T * 0.1, y + T * 0.06, T * 0.8, T * 0.9), D_WOOD_LINE, true)      # 门框
		draw_rect(Rect2(x + T * 0.16, y + T * 0.12, T * 0.68, T * 0.82), X_WOOD_MID, true)   # 门板
		draw_rect(Rect2(x + T * 0.16, y + T * 0.12, T * 0.68, T * 0.1), Color(X_GLOW, 0.5), true)  # 门楣暖光
		draw_rect(Rect2(x + T * 0.48, y + T * 0.12, T * 0.03, T * 0.82), D_WOOD_LINE, true)   # 门缝
		draw_circle(Vector2(x + T * 0.72, y + T * 0.55), T * 0.055, X_GOLD)              # 门把
		var to_space := String(to0.get("space", ""))
		var label := String(sg.label_of(to_space))
		var sw: float = 8.0 + Art.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var sx := x + T * 0.5 - sw * 0.5
		draw_rect(Rect2(sx, y - T * 0.52, sw, T * 0.36), P_COM_FOOT, true)                   # 招牌木板
		draw_rect(Rect2(sx, y - T * 0.52, sw, T * 0.36), Color(X_GOLD, 0.8), false, 1.5)        # 金边
		draw_string(Art.font(), Vector2(sx + 5, y - T * 0.52 + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, X_PARCHMENT)

## AP2(141) 广场【中心徽章】：中央一圈同心石环 + 8 向放射缝 + 冷石心盘。纯 View 铺面细节（画在 flagstone 上、
## Sim 零读 type ⇒ 零金标）。★刻意做成【多格尺度】：默认全镇 zoom 下一格才 ~11px、单格细节读不出，唯有跨数格的
## 色块/环才咬得住镜头——这一圈让"镇中心"在整镇俯瞰里也一眼成立（docs/141 §街具可读性）。几何全由广场 rect + T 派生
## （无 RNG/Time ⇒ `--shot` 逐像素可复现，红旗#4）。
func _draw_plaza_medallion(rect: Rect2) -> void:
	var c := rect.get_center()
	var R := minf(rect.size.x, rect.size.y) * 0.42                # 收在广场内、留边不溢到草地
	var pl := G_PLAZA_LINE   # AV3(161)：环缝随广场进暖石族（原 P_PLAZA_LINE）
	draw_circle(c, R, Color(G_PLAZA_HI.r, G_PLAZA_HI.g, G_PLAZA_HI.b, 0.22))                       # 受光石 apron（暖石）
	draw_arc(c, R, 0.0, TAU, 44, Color(pl.r, pl.g, pl.b, 0.55), 2.0, false)                        # 外环缝
	draw_arc(c, R * 0.66, 0.0, TAU, 32, Color(pl.r, pl.g, pl.b, 0.40), 1.5, false)                 # 中环缝
	for k in range(8):                                            # 8 向放射灌浆缝（罗盘感、把眼睛引向心）
		var ang := TAU * float(k) / 8.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * (R * 0.30), c + d * R, Color(pl.r, pl.g, pl.b, 0.30), 1.0, false)
	draw_circle(c, R * 0.30, Color(P_STONE.r, P_STONE.g, P_STONE.b, 0.42))                          # 冷石心盘【故意留冷】：与暖石广场拉材质对比 ⇒ 心"沉"下去成焦点（AV3 保留这条焦点对比）
	draw_arc(c, R * 0.30, 0.0, TAU, 24, Color(P_STONE_LINE.r, P_STONE_LINE.g, P_STONE_LINE.b, 0.55), 1.5, false)
	draw_circle(c, R * 0.11, Color(G_PLAZA_HI.r, G_PLAZA_HI.g, G_PLAZA_HI.b, 0.55))                 # 心点高光（暖石）

## AP2(141) 广场【座圈】：徽章外沿一圈小石凳。南半留口（朝水井/告示板那侧不叠座）⇒ 读作"围着中心坐的一圈"。
## 画在 _draw_landmarks 里（在花草/街具之上、居民之下）：人站上去自然遮住 = "有人坐在这儿"。纯 View、非 blocker。
func _draw_plaza_seatring(rect: Rect2) -> void:
	var c := rect.get_center()
	var R := minf(rect.size.x, rect.size.y) * 0.42
	for k in range(8):
		var ang := TAU * (float(k) / 8.0) + TAU / 16.0            # 错开 22.5°：座位落在放射缝【之间】，不压线
		var dir := Vector2(cos(ang), sin(ang))
		if dir.y > 0.35:                                          # 南半（朝水井/告示板）留口，不叠座
			continue
		var p := c + dir * (R * 1.02)
		draw_circle(p + Vector2(0, T * 0.10), T * 0.21, Color(0, 0, 0, 0.18))                       # 落地影
		draw_circle(p, T * 0.19, S_PLANTER)                                                          # 石凳身
		draw_circle(p - Vector2(0, T * 0.05), T * 0.15, S_PLANTER.lightened(0.18))                   # 座面受光
		draw_arc(p, T * 0.19, 0.0, TAU, 16, S_PLANTER.darkened(0.30), 1.0, false)                    # 描边

func _draw_landmarks() -> void:
	for lm in Sim.world.get("landmarks", []):
		var lp: Array = lm.get("pos", [0, 0])
		var bx := int(lp[0]) * T; var by := int(lp[1]) * T
		match String(lm.get("type", "")):
			"well":
				# AP2(141) 有分量的圆石水井（双坡木顶 + 摇柄横梁 + 吊桶 + 井水反光）。向上伸出本格（顶棚 overhang，
				#   同建筑画法）；纯 draw，**永不进 blockers**（进了=挡广场中央生存路 ⇒ #01 破，docs/139 ②）。
				var wc := bx + T * 0.5                                                                # 井中轴
				draw_circle(Vector2(wc, by + T * 0.86), T * 0.40, Color(0, 0, 0, 0.22))               # 落地影
				draw_circle(Vector2(wc, by + T * 0.66), T * 0.40, P_STONE.darkened(0.18))             # 井座暗（做圆台厚度）
				draw_circle(Vector2(wc, by + T * 0.60), T * 0.40, P_PUB_FACE)                         # 石圈主体
				draw_circle(Vector2(wc, by + T * 0.56), T * 0.34, P_PUB_TOP)                          # 井沿受光
				draw_circle(Vector2(wc, by + T * 0.56), T * 0.26, P_STONE_LINE)                       # 井内壁
				draw_circle(Vector2(wc, by + T * 0.58), T * 0.20, P_WATER_DEEP)                       # 井水
				draw_arc(Vector2(wc, by + T * 0.55), T * 0.11, PI, TAU, 10, Color(X_COLD_WHITE.r, X_COLD_WHITE.g, X_COLD_WHITE.b, 0.5), 1.5, false)  # 水面反光
				draw_rect(Rect2(bx + T * 0.14, by - T * 0.28, T * 0.08, T * 0.80), X_WOOD_MID, true)   # 左立柱
				draw_rect(Rect2(bx + T * 0.78, by - T * 0.28, T * 0.08, T * 0.80), X_WOOD_MID, true)   # 右立柱
				draw_rect(Rect2(bx + T * 0.14, by - T * 0.28, T * 0.08, T * 0.80), D_WOOD_LINE, false, 1.0)
				draw_rect(Rect2(bx + T * 0.78, by - T * 0.28, T * 0.08, T * 0.80), D_WOOD_LINE, false, 1.0)
				draw_rect(Rect2(bx + T * 0.10, by - T * 0.08, T * 0.80, T * 0.08), X_WOOD_MID, true)   # 卷绳横梁
				draw_line(Vector2(wc, by - T * 0.02), Vector2(wc, by + T * 0.30), D_WOOD_LINE, 1.5)    # 井绳
				draw_rect(Rect2(bx + T * 0.42, by + T * 0.26, T * 0.16, T * 0.16), X_WOOD_MID, true)   # 吊桶
				draw_rect(Rect2(bx + T * 0.42, by + T * 0.26, T * 0.16, T * 0.05), D_WOOD_LINE, true)  # 桶箍
				var rt := by - T * 0.26                                                               # 檐线高度
				draw_colored_polygon(PackedVector2Array([Vector2(wc, by - T * 0.62), Vector2(bx - T * 0.02, rt), Vector2(bx + T * 1.02, rt)]), P_PUB_ROOF)  # 双坡顶
				draw_colored_polygon(PackedVector2Array([Vector2(wc, by - T * 0.62), Vector2(bx - T * 0.02, rt), Vector2(wc, rt)]), P_PUB_ROOF.darkened(0.12))  # 顶阴面
				draw_line(Vector2(bx - T * 0.02, rt), Vector2(bx + T * 1.02, rt), P_PUB_FOOT, 1.5)     # 檐口线
			"board":
				# AP2(141) 有分量的镇【告示栏】：木框软木板 + 一排不同色告示 + 红披檐 + 图钉。纯 draw、永不进 blockers。
				var ax := bx
				draw_rect(Rect2(ax + T * 0.06, by + T * 0.80, T * 0.88, T * 0.16), Color(0, 0, 0, 0.20), true)  # 落地影
				draw_rect(Rect2(ax + T * 0.15, by + T * 0.30, T * 0.09, T * 0.64), P_COM_FOOT, true)   # 左立柱
				draw_rect(Rect2(ax + T * 0.76, by + T * 0.30, T * 0.09, T * 0.64), P_COM_FOOT, true)   # 右立柱
				draw_rect(Rect2(ax + T * 0.08, by - T * 0.02, T * 0.84, T * 0.56), X_WOOD_MID, true)   # 木外框
				draw_rect(Rect2(ax + T * 0.13, by + T * 0.04, T * 0.74, T * 0.44), P_RES_FLOOR, true)  # 软木板面（暖木）
				draw_rect(Rect2(ax + T * 0.08, by - T * 0.02, T * 0.84, T * 0.56), D_WOOD_LINE, false, 1.5)
				draw_rect(Rect2(ax + T * 0.18, by + T * 0.09, T * 0.20, T * 0.17), P_TEXT, true)       # 告示·奶油纸
				draw_rect(Rect2(ax + T * 0.44, by + T * 0.10, T * 0.16, T * 0.14), X_SIGNAL_POS, true) # 告示·绿
				draw_rect(Rect2(ax + T * 0.65, by + T * 0.09, T * 0.18, T * 0.16), X_PARCHMENT, true)  # 告示·羊皮
				draw_rect(Rect2(ax + T * 0.20, by + T * 0.29, T * 0.17, T * 0.15), D_BOOK_BLUE, true)  # 告示·蓝
				draw_rect(Rect2(ax + T * 0.47, by + T * 0.28, T * 0.18, T * 0.16), X_SIGNAL_NEG, true) # 告示·红
				draw_rect(Rect2(ax + T * 0.70, by + T * 0.30, T * 0.13, T * 0.13), P_TEXT, true)       # 告示·小纸
				draw_rect(Rect2(ax + T * 0.04, by - T * 0.12, T * 0.92, T * 0.13), P_COM_ROOF, true)   # 红披檐
				draw_rect(Rect2(ax + T * 0.04, by - T * 0.12, T * 0.92, T * 0.04), P_COM_ROOF.lightened(0.15), true)  # 檐受光
	# AP2(141) 座圈画在地标循环【之后】：读广场 rect（Sim 也读的面、只读不写 ⇒ 零金标），与徽章同一几何中心。
	var _areas: Dictionary = Sim.world.get("areas", {})
	if _areas.has("plaza"):
		var _pr: Array = (_areas["plaza"] as Dictionary).get("rect", [0, 0, 0, 0])
		if int(_pr[2]) > 0 and int(_pr[3]) > 0:
			_draw_plaza_seatring(Rect2(int(_pr[0]) * T, int(_pr[1]) * T, int(_pr[2]) * T, int(_pr[3]) * T))

## ══════════════════════════════════════════════════════════════════════════════
## AP-port（docs/163）· 滩头 dock 的【港口身份】—— 纯 View、零金标、POND 安全
## ──────────────────────────────────────────────────────────────────────────────
## F5 建的 `dock` 区（type:plaza、rect [30,7,4,2]、北池南岸、蓄意不含水格）此前只铺了广场石板 +
## 一个借 bench 精灵的 `bench_pier 渔台` worksite，读作"一块带凳子的铺装"，没有任何码头/船/仓库。
## 本函数把这块铺装【就地】画成真港口：木栈桥板 + 临水边梁 + 系缆桩 + 系着的渔船 + 货箱/桶/麻袋 +
## P1-c：carrier 是 CargoManifest 的【纯 View 投影】，不是第二份 world 状态。
## 一个 route/node 无论积压多少 ready manifest 都只画一艘泊位船，单数用徽记表示；零 ready 即零货船。
## 这条路不 spawn/despawn、不写 event、不进导航/存档/chain，权威时序仍是 manifest arrival→exact unload。
static func carrier_projections_for(sim, logistics_data: Dictionary, manifests: Dictionary, order: Array) -> Array:
	var out: Array = []
	var raw_carriers = logistics_data.get("carriers", [])
	if not (raw_carriers is Array):
		return out
	for raw_cfg in raw_carriers:
		if not (raw_cfg is Dictionary):
			continue
		var cfg: Dictionary = raw_cfg
		var route := String(cfg.get("route_id", ""))
		var node := String(cfg.get("node", ""))
		var berth = cfg.get("berth", [])
		if route == "" or node == "" or not (berth is Array) or (berth as Array).size() < 2:
			continue
		var first: Dictionary = {}
		var ready_count := 0
		var ready_qty := 0
		for raw_id in order:
			var manifest_id := String(raw_id)
			var rec = manifests.get(manifest_id, {})
			if not (rec is Dictionary):
				continue
			var rd: Dictionary = rec
			if sim._manifest_authority_error(manifest_id, rd, logistics_data, int(sim.day), sim.event_log) != "":
				continue
			if String(rd.get("route_id", "")) != route or String(rd.get("node", "")) != node:
				continue
			var qty := int(rd.get("remaining_qty", 0))
			if String(rd.get("state", "")) != "ready" or qty <= 0:
				continue
			if first.is_empty():
				first = rd
			ready_count += 1
			ready_qty += qty
		if first.is_empty():
			continue
		var p: Dictionary = cfg.duplicate(true)
		p["manifest_id"] = String(first.get("id", ""))
		p["good"] = String(first.get("good", ""))
		p["remaining_qty"] = int(first.get("remaining_qty", 0))
		p["ready_count"] = ready_count
		p["ready_qty"] = ready_qty
		out.append(p)
	return out

func _cargo_carrier_projections() -> Array:
	return carrier_projections_for(Sim, Sim.logistics, Sim.cargo_manifests, Sim.cargo_manifest_order)

func _draw_port() -> void:
	var dock = Sim.world.get("areas", {}).get("dock", {})
	if dock is Dictionary and String((dock as Dictionary).get("facing", "")) == "east":
		_draw_port_east(dock)
		return
	_draw_port_legacy_north()

## East Ocean 港面：陆上 deck 完全落在 dock rect；货船 anchor 完全取 authored berth，不硬编码 route 坐标。
func _draw_port_east(dock: Dictionary) -> void:
	var dr = dock.get("rect", [])
	if not (dr is Array) or (dr as Array).size() < 4:
		return
	var dx := int(dr[0]); var dy := int(dr[1]); var dw := int(dr[2]); var dh := int(dr[3])
	if dw <= 0 or dh <= 0:
		return
	var deck := Rect2(dx * T, dy * T, dw * T, dh * T)
	if _vis.intersects(deck):
		var seam := D_WOOD_LINE
		var plank := X_WOOD_MID.lightened(0.14)
		draw_rect(deck, plank, true)
		for x in range(dw * 2 + 1):
			var px := deck.position.x + float(x) * T * 0.5
			draw_line(Vector2(px, deck.position.y), Vector2(px, deck.end.y), Color(seam.r, seam.g, seam.b, 0.45), 1.0)
		for y in range(dh + 1):
			var py := deck.position.y + float(y) * T
			draw_line(Vector2(deck.position.x, py), Vector2(deck.end.x, py), Color(seam.r, seam.g, seam.b, 0.52), 1.2)
		# 面海护舷、系缆桩与货堆；east 分支蓄意不画旧北池常驻渔船。
		draw_rect(Rect2(deck.end.x - T * 0.12, deck.position.y, T * 0.12, deck.size.y), seam, true)
		_port_bollard(deck.end.x - T * 0.15, deck.position.y + T * 0.18)
		_port_bollard(deck.end.x - T * 0.15, deck.end.y - T * 0.42)
		_port_boathouse(deck.position.x + T * 0.06, deck.position.y + T * 0.05, T * 0.92)
		_port_crate(deck.position.x + T * 1.30, deck.position.y + T * 0.22, T * 0.34)
		_port_barrel(deck.position.x + T * 2.12, deck.position.y + T * 0.28, T * 0.22, T * 0.36)
		var bean_cap := maxi(1, int(((Sim.production.get("goods", {}) as Dictionary).get("豆子", {}) as Dictionary).get("cap", 45)))
		var bean_fill := clampf(float(Sim._stock_of("豆子")) / float(bean_cap), 0.0, 1.0)
		_port_sacks(deck.position.x + T * 2.62, deck.position.y + T * 1.34, T * 0.28, bean_fill)
		_port_signpost(deck.position.x + T * 0.55, deck.end.y + T * 0.52)
	# 船体可能仍在画面内而 deck 已在左侧画面外；carrier 必须按自己的 hull 做裁剪。
	if not _ap("carrier"):
		return
	for projection in _cargo_carrier_projections():
		_draw_cargo_carrier(projection)

## 泊位货船：west-facing 横向船体，与 `_port_boat` 的常驻小渔船在生命周期、尺寸和货单徽记上明确区分。
func _draw_cargo_carrier(projection: Dictionary) -> void:
	var berth = projection.get("berth", [])
	if not (berth is Array) or (berth as Array).size() < 2:
		return
	var bx := int(berth[0]); var by := int(berth[1])
	# 2.65×1.16 格：在 --shot-fit 的 0.23x 全镇帧里仍约 30×13px，可读；又完整收在四列海域内。
	var hull := Rect2((float(bx) + 0.06) * T, (float(by) - 0.08) * T, T * 2.65, T * 1.16)
	if not _vis.intersects(hull):
		return
	var shadow := Rect2(hull.position + Vector2(T * 0.05, T * 0.08), hull.size)
	draw_rect(shadow, Color(0.04, 0.10, 0.14, 0.55), true)
	# 西向尖艏、宽货舱、桅杆与显眼帆色；全部确定性整数/常量几何。
	var bow := Vector2(hull.position.x, hull.get_center().y)
	var stern_x := hull.end.x
	var poly := PackedVector2Array([
		bow, Vector2(hull.position.x + T * 0.34, hull.position.y),
		Vector2(stern_x, hull.position.y + T * 0.10), Vector2(stern_x, hull.end.y - T * 0.10),
		Vector2(hull.position.x + T * 0.34, hull.end.y)])
	draw_colored_polygon(poly, X_WOOD_MID.darkened(0.20))
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[4], poly[0]]), D_WOOD_LINE, 2.0)
	var mast_x := hull.position.x + T * 1.34
	draw_line(Vector2(mast_x, hull.position.y - T * 0.72), Vector2(mast_x, hull.end.y), D_WOOD_LINE, 2.4)
	var sail := PackedVector2Array([
		Vector2(mast_x + 2, hull.position.y - T * 0.68), Vector2(mast_x + T * 0.86, hull.position.y - T * 0.06),
		Vector2(mast_x + 2, hull.position.y - T * 0.06)])
	draw_colored_polygon(sail, X_PARCHMENT)
	# 三只货箱表示 cargo，不按数量线性增对象；backlog 用 bounded 徽记。
	for i in 3:
		_port_crate(hull.position.x + T * (0.78 + float(i) * 0.38), hull.position.y + T * 0.48, T * 0.30)
	var count := int(projection.get("ready_count", 1))
	var badge_c := Vector2(hull.end.x - T * 0.16, hull.position.y + T * 0.06)
	draw_circle(badge_c, T * 0.27, X_SIGNAL_NEG if count > 1 else X_GLOW)
	draw_string(Art.font(), badge_c + Vector2(-T * 0.15, T * 0.10), str(count), HORIZONTAL_ALIGNMENT_CENTER, T * 0.30, 16, Color.WHITE)

## 小船屋 silhouette + 一个方向路牌（呼应 item#2「交通:港口」）。
##
## ★零金标：只读 `Sim.world.areas.dock.rect`（Sim 也读的面，只读不写；Sim 从不读 type/terrain/本层 draw）
##   ⇒ 一格 digest 都动不了（金标 12/12 逐字节，同 AV1/AV2/AV3 的 View-only 纪律）。
## ★POND 安全（docs/162 §三 点名的唯一真风险）：dock 在北池南岸，POND 门采样北池那圈 grass↔water 岸线。
##   **本函数一像素都不画到水线 `py`(=dock 顶边=池南岸) 之上** —— 所有结构 clamp 在 y≥py 的已铺 dock 格里，
##   池水/岸线像素一个不碰。南岸(`bot@`)剖线陆侧本就是铺装非草(被 POND 的 path/grass 判据天然排除)，
##   而木结构只会给 `levels` 台阶判据**加**台阶(利好)、不会抹掉草→水梯度。实测 POND before/after 见 docs/163。
## ★确定性：几何全由 rect+T 派生，木纹/明暗档只读 `_hash(x,y,salt)`、夜灯只读 `_night_amt()`(f(time_of_day))
##   —— 无 randi/randf/Time/OS ⇒ `--shot` 逐像素可复现(ROUNDTRIP 冻结帧)。
## ★复用现有色常量(木 X_WOOD_MID/D_WOOD_LINE、水 P_WATER_DEEP/LIT、暖光 X_GLOW*、麻布 P_PLAZA)，不加新 BLD_PAL。
## `port_dock` 只是 logistics 声明节点(保留位 [33,8]、不落 world.objects)，本函数不读它、不碰 logistics.json。
func _draw_port_legacy_north() -> void:
	var areas: Dictionary = Sim.world.get("areas", {})
	if not areas.has("dock"):
		return
	var dr: Array = (areas["dock"] as Dictionary).get("rect", [0, 0, 0, 0])
	var dwc := int(dr[2]); var dhc := int(dr[3])
	if dwc <= 0 or dhc <= 0:
		return
	var dx0 := int(dr[0]); var dy0 := int(dr[1])
	var px := float(dx0 * T); var py := float(dy0 * T)      # py = dock 顶边 = 北池南岸【水线】：下面所有 draw 都 ≥ py
	var pw := float(dwc * T); var ph := float(dhc * T)
	if not _vis.intersects(Rect2(px, py, pw, ph)):
		return                                              # 视口裁剪（同花草/街具）：dock 不在画面就整段跳过

	# ── ① 木栈桥板（把广场石板就地盖成一层晒白的木甲板；竖板 + 板缝 + 木纹 + 钉头，全确定性）──────────
	var seam := D_WOOD_LINE                                 # 板缝/描边：木家族最暗档
	var deck0 := X_WOOD_MID.lightened(0.16)                 # 甲板底：晒白的栈桥木
	var board_w := T * 0.5
	var nb := int(round(pw / board_w))
	for row in range(dhc):
		var ry := py + float(row) * T
		for bi in range(nb):
			var bx := px + float(bi) * board_w
			var tone := _hash(bi, dy0 + row, 63) % 5
			var col := deck0
			if tone == 0: col = deck0.lightened(0.10)
			elif tone == 1: col = deck0.darkened(0.09)
			elif tone == 2: col = X_WOOD_MID
			draw_rect(Rect2(bx, ry, board_w, T), col, true)
			for g in range(2):                              # 板面横木纹（两道，确定性抖动）
				var gy := ry + T * (0.32 + 0.36 * float(g)) + float(_hash(bi, dy0 + row, 71 + g) % 3)
				draw_rect(Rect2(bx + 1.0, gy, board_w - 2.0, 1.0), Color(seam.r, seam.g, seam.b, 0.28), true)
	for bi2 in range(nb + 1):                               # 竖板缝
		var sx := px + float(bi2) * board_w
		draw_rect(Rect2(sx - 0.5, py, 1.0, ph), Color(seam.r, seam.g, seam.b, 0.5), true)
	for row2 in range(dhc + 1):                             # 横向龙骨线 + 钉头（每板一颗）
		var jy := py + float(row2) * T
		draw_rect(Rect2(px, jy - 0.5, pw, 1.4), Color(seam.r, seam.g, seam.b, 0.45), true)
		for bi3 in range(nb):
			draw_circle(Vector2(px + (float(bi3) + 0.5) * board_w, jy + 2.0), 1.0, Color(seam.r, seam.g, seam.b, 0.55))

	# ── ② 临水边梁（bull rail）：栈桥朝水那条边压一根深木梁 + 受光高光。就在水线 py 上，不越线。──────────
	draw_rect(Rect2(px, py, pw, T * 0.13), seam, true)
	draw_rect(Rect2(px, py, pw, T * 0.035), X_WOOD_MID.lightened(0.06), true)

	# ── ③ 结构（自西向东：船屋 / 系缆桩 / 渔船 / 货堆 / 路牌）。位置按 rect 分数派生，都 clamp 在 y≥py。──────
	_port_boathouse(px + T * 0.05, py + T * 0.05, T * 0.92)           # 西端(cell30) 船屋
	var boll_w := px + pw * 0.34                                      # 西系缆桩(cell31.4，系船)
	var boll_e := px + pw * 0.90                                      # 东系缆桩(cell33.6，近货堆)
	_port_bollard(boll_w, py + T * 0.07)
	_port_bollard(boll_e, py + T * 0.07)
	var boat_cx := px + pw * 0.64                                     # 渔船(cell32.6 水线，避开 cell31 的渔台 worksite)
	var boat_top := py + T * 0.06
	var rope := Color(P_COM_FOOT.r, P_COM_FOOT.g, P_COM_FOOT.b, 0.85) # 系缆绳：西桩顶→船首（两段松弛折线，端点都≥py）
	draw_line(Vector2(boll_w, py + T * 0.10), Vector2((boll_w + boat_cx) * 0.5, py + T * 0.26), rope, 1.4)
	draw_line(Vector2((boll_w + boat_cx) * 0.5, py + T * 0.26), Vector2(boat_cx - T * 0.5, boat_top + T * 0.24), rope, 1.4)
	_port_boat(boat_cx, boat_top, T * 0.56, T * 0.30)
	_port_crate(px + pw * 0.78, py + T * 0.54, T * 0.36)             # 货堆(cell33)：木箱堆 + 桶 + 出口豆子麻袋
	_port_crate(px + pw * 0.80, py + T * 0.22, T * 0.28)
	_port_barrel(px + pw * 0.945, py + T * 0.58, T * 0.22, T * 0.36)
	# P1-c(178)：出口豆子麻袋堆【读 town_stock 显形】——袋数随豆子库存/cap(0..1)涨落，把镇里【可出口的余量】
	#   显形在码头。纯 View 只读 `Sim._stock_of`（红线 WorldView:184 绝不回喂 Sim）⇒ 零 sim 金标；几何 clamp 在
	#   deck 内不越水线 py（满袋=原样，POND 前后一致）。豆子恒是 production 货（不依赖 logistics 开），空仓不画。
	var _bean_cap := maxi(1, int(((Sim.production.get("goods", {}) as Dictionary).get("豆子", {}) as Dictionary).get("cap", 45)))
	var _bean_fill := clampf(float(Sim._stock_of("豆子")) / float(_bean_cap), 0.0, 1.0)
	_port_sacks(px + pw * 0.79, py + T * 1.44, T * 0.30, _bean_fill)
	# 交通路牌（item#2）：立在 dock 西南侧【陆地】上(cell~30.5,y9)——独立可读、指向港口，
	#   不挤东端货堆。落点仍在 y≥py 的陆格，纯 View decor(非 blocker)，对 POND grass 环带众数无影响。
	_port_signpost(px + pw * 0.14, py + ph + T * 0.60)

## AP-port 结构件（都是纯 draw_* 图元；调用方 _draw_port 保证 top_y/ground_y ≥ 水线 py）。────────────
## 系缆桩：临水一根矮木桩 + 深帽 + 缆环。
func _port_bollard(cx: float, top_y: float) -> void:
	var w := T * 0.15
	var hgt := T * 0.32
	draw_circle(Vector2(cx, top_y + hgt), w * 0.85, Color(0, 0, 0, 0.20))                     # 落地影
	draw_rect(Rect2(cx - w * 0.5, top_y, w, hgt), X_WOOD_MID, true)                            # 桩身
	draw_rect(Rect2(cx - w * 0.5, top_y, w * 0.34, hgt), X_WOOD_MID.lightened(0.14), true)     # 受光
	draw_rect(Rect2(cx - w * 0.5, top_y, w, hgt), D_WOOD_LINE, false, 1.0)                     # 描边
	draw_circle(Vector2(cx, top_y), w * 0.62, D_WOOD_LINE)                                     # 桩帽
	draw_circle(Vector2(cx, top_y - 1.0), w * 0.42, X_WOOD_MID.lightened(0.10))
	draw_arc(Vector2(cx, top_y + hgt * 0.5), w * 0.5, 0.12 * PI, 0.88 * PI, 8,
		Color(P_COM_FOOT.r, P_COM_FOOT.g, P_COM_FOOT.b, 0.9), 1.5, false)                      # 缆环

## 渔船（系在栈桥边的平底小船，蓄意画成【平的】以整船落在水线 py 之下）：深木壳 + 浅木舷内 + 坐板 + 盘网 + 渔获。
func _port_boat(cx: float, top_y: float, hw: float, hh: float) -> void:
	var cy := top_y + hh
	draw_circle(Vector2(cx, cy + hh * 0.55), hw * 0.92, Color(P_WATER_DEEP.r, P_WATER_DEEP.g, P_WATER_DEEP.b, 0.20))  # 水影
	var hull := PackedVector2Array([
		Vector2(cx - hw, cy), Vector2(cx - hw * 0.55, cy - hh), Vector2(cx + hw * 0.55, cy - hh),
		Vector2(cx + hw, cy), Vector2(cx + hw * 0.55, cy + hh), Vector2(cx - hw * 0.55, cy + hh)])
	draw_colored_polygon(hull, D_WOOD_LINE)                                                    # 船壳（深木尖头椭圆）
	var f := 0.66
	var inner := PackedVector2Array([
		Vector2(cx - hw * f, cy), Vector2(cx - hw * 0.4 * f, cy - hh * f), Vector2(cx + hw * 0.4 * f, cy - hh * f),
		Vector2(cx + hw * f, cy), Vector2(cx + hw * 0.4 * f, cy + hh * f), Vector2(cx - hw * 0.4 * f, cy + hh * f)])
	draw_colored_polygon(inner, X_WOOD_MID.lightened(0.08))                                    # 舷内（浅木）
	draw_rect(Rect2(cx - hw * 0.5, cy - hh * 0.42, hw * 0.32, hh * 0.20), X_WOOD_MID, true)    # 坐板×2
	draw_rect(Rect2(cx + hw * 0.18, cy - hh * 0.42, hw * 0.32, hh * 0.20), X_WOOD_MID, true)
	draw_arc(Vector2(cx + hw * 0.32, cy + hh * 0.10), hh * 0.34, 0.0, TAU, 12,
		Color(X_PARCHMENT.r, X_PARCHMENT.g, X_PARCHMENT.b, 0.8), 1.4, false)                   # 盘起的渔网
	draw_arc(Vector2(cx + hw * 0.32, cy + hh * 0.10), hh * 0.20, 0.0, TAU, 10,
		Color(X_PARCHMENT.r, X_PARCHMENT.g, X_PARCHMENT.b, 0.6), 1.2, false)
	draw_circle(Vector2(cx - hw * 0.42, cy + hh * 0.06), hh * 0.17, X_COLD_WHITE)              # 渔获（银鱼）
	draw_circle(Vector2(cx - hw * 0.28, cy - hh * 0.04), hh * 0.13, Color(P_WATER_LIT.r, P_WATER_LIT.g, P_WATER_LIT.b, 0.9))
	draw_circle(Vector2(cx - hw * 0.92, cy), hh * 0.15, X_WOOD_MID)                            # 船首柱

## 船屋 / 小仓库 silhouette：人字木屋，屋脊在临水侧(顶边=py)，门朝栈桥(南)，夜里小窗透暖光。
func _port_boathouse(bx0: float, top_y: float, bw: float) -> void:
	var cx := bx0 + bw * 0.5
	var eaves := top_y + bw * 0.46
	var body_bot := top_y + T * 1.56
	draw_rect(Rect2(bx0 + 3.0, body_bot - T * 0.36, bw, T * 0.44), Color(0, 0, 0, 0.20), true)  # 落地影
	draw_rect(Rect2(bx0, eaves - 2.0, bw, body_bot - eaves + 2.0), X_WOOD_MID, true)             # 屋身
	draw_rect(Rect2(bx0, eaves - 2.0, bw * 0.30, body_bot - eaves + 2.0), X_WOOD_MID.darkened(0.12), true)  # 阴面
	for k in range(3):                                                                           # 木板条
		var ly := eaves + T * (0.28 + 0.34 * float(k))
		draw_rect(Rect2(bx0, ly, bw, 1.0), Color(D_WOOD_LINE.r, D_WOOD_LINE.g, D_WOOD_LINE.b, 0.35), true)
	draw_rect(Rect2(bx0, eaves - 2.0, bw, body_bot - eaves + 2.0), D_WOOD_LINE, false, 1.5)      # 描边
	draw_colored_polygon(PackedVector2Array([                                                    # 人字顶（apex 在 top_y = 水线，不越线）
		Vector2(cx, top_y), Vector2(bx0 - 3.0, eaves), Vector2(bx0 + bw + 3.0, eaves)]), P_RES_ROOF)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, top_y), Vector2(bx0 - 3.0, eaves), Vector2(cx, eaves)]), P_RES_ROOF.darkened(0.12))  # 顶阴面
	draw_line(Vector2(bx0 - 3.0, eaves), Vector2(bx0 + bw + 3.0, eaves), P_RES_FOOT, 1.5)        # 檐口线
	var door := Rect2(cx - bw * 0.26, body_bot - T * 0.86, bw * 0.52, T * 0.86)                  # 大门（朝栈桥）
	draw_rect(door, D_WOOD_LINE, true)
	draw_rect(door, X_WOOD_MID, false, 1.5)
	draw_rect(Rect2(cx - 1.0, body_bot - T * 0.86, 2.0, T * 0.86), X_WOOD_MID, true)             # 门缝
	var na := _night_amt()                                                                       # 门上小窗：夜里透暖光
	var win := Rect2(cx - bw * 0.15, eaves + T * 0.14, bw * 0.30, T * 0.22)
	draw_rect(win, Color(X_GLOW_DEEP.r, X_GLOW_DEEP.g, X_GLOW_DEEP.b, 0.30 + 0.55 * na), true)
	draw_rect(win, D_WOOD_LINE, false, 1.0)
	if na > 0.01:
		draw_circle(win.get_center(), bw * 0.55, Color(X_GLOW.r, X_GLOW.g, X_GLOW.b, 0.16 * na))  # 灯晕

## 货箱：木箱 + 顶受光 + X 撑 + 中缝。
func _port_crate(x: float, y: float, s: float) -> void:
	draw_rect(Rect2(x + 2.0, y + s * 0.85, s, s * 0.26), Color(0, 0, 0, 0.18), true)             # 影
	draw_rect(Rect2(x, y, s, s), X_WOOD_MID, true)
	draw_rect(Rect2(x, y, s, s * 0.18), X_WOOD_MID.lightened(0.12), true)                        # 顶受光
	draw_rect(Rect2(x, y, s, s), D_WOOD_LINE, false, 1.5)                                        # 边框
	var xb := Color(D_WOOD_LINE.r, D_WOOD_LINE.g, D_WOOD_LINE.b, 0.7)
	draw_line(Vector2(x, y), Vector2(x + s, y + s), xb, 1.2)                                     # X 撑
	draw_line(Vector2(x + s, y), Vector2(x, y + s), xb, 1.2)
	draw_rect(Rect2(x, y + s * 0.5 - 0.5, s, 1.0), Color(D_WOOD_LINE.r, D_WOOD_LINE.g, D_WOOD_LINE.b, 0.55), true)  # 中缝

## 木桶：深棕桶身 + 三道铁箍 + 木盖。
func _port_barrel(cx: float, top_y: float, w: float, h: float) -> void:
	draw_circle(Vector2(cx, top_y + h + 2.0), w * 0.55, Color(0, 0, 0, 0.16))                    # 影
	var body := Rect2(cx - w * 0.5, top_y, w, h)
	draw_rect(body, P_COM_FOOT, true)                                                            # 桶身
	draw_rect(Rect2(cx - w * 0.5, top_y, w * 0.28, h), P_COM_FOOT.lightened(0.16), true)         # 受光
	for k in range(3):                                                                           # 铁箍
		draw_rect(Rect2(cx - w * 0.5, top_y + h * (0.12 + 0.37 * float(k)), w, 1.6),
			Color(D_WOOD_LINE.r, D_WOOD_LINE.g, D_WOOD_LINE.b, 0.85), true)
	draw_rect(Rect2(cx - w * 0.5, top_y, w, h * 0.13), X_WOOD_MID.darkened(0.08), true)          # 桶沿
	draw_rect(Rect2(cx - w * 0.36, top_y + 1.0, w * 0.72, h * 0.10), X_WOOD_MID.lightened(0.12), true)  # 桶盖（内缩、读作圆口）
	draw_rect(body, D_WOOD_LINE, false, 1.2)

## 麻袋堆（出口·豆子）：暖麻布圆包 + 扎口。★P1-c(178)：袋数随 fill(豆子库存/cap,0..1)——
## 空仓不画、满仓 3 袋（＝原样，几何/顺序不变 ⇒ 满库存帧逐像素同旧，POND 前后一致，仅低库存帧减袋）。
func _port_sacks(x: float, y: float, s: float, fill: float = 1.0) -> void:
	var n := int(round(clampf(fill, 0.0, 1.0) * 3.0))   # 0..3 袋（顶袋在 y−0.52s，仍 clamp 在 deck 内、不越水线）
	if n <= 0:
		return
	draw_rect(Rect2(x - s * 0.6, y + s * 0.28, s * 1.8, s * 0.5), Color(0, 0, 0, 0.16), true)    # 影
	var burlap := P_PLAZA.darkened(0.06)
	var _pp := [Vector2(x, y), Vector2(x + s * 0.78, y + s * 0.06), Vector2(x + s * 0.40, y - s * 0.52)]
	for i in range(n):
		var pos: Vector2 = _pp[i]
		draw_circle(pos, s * 0.5, burlap)
		draw_circle(pos - Vector2(s * 0.12, s * 0.12), s * 0.28, burlap.lightened(0.13))
		draw_arc(pos, s * 0.5, 0.0, TAU, 12, burlap.darkened(0.26), 1.0, false)
		draw_line(pos + Vector2(0, -s * 0.5), pos + Vector2(0, -s * 0.66), P_COM_FOOT, 1.4)      # 扎口

## 交通路牌（呼应 item#2「交通:港口」）：木柱 + 两块方向牌 + 箭头。立在 deck 上。
func _port_signpost(cx: float, ground_y: float) -> void:
	var top := ground_y - T * 0.86
	draw_circle(Vector2(cx, ground_y), T * 0.10, Color(0, 0, 0, 0.18))                           # 影
	draw_rect(Rect2(cx - T * 0.045, top, T * 0.09, ground_y - top), X_WOOD_MID, true)            # 柱
	draw_rect(Rect2(cx - T * 0.045, top, T * 0.09, ground_y - top), D_WOOD_LINE, false, 1.0)
	var board := P_RES_FLOOR                                                                     # 暖木牌面（读得出的浅木）
	var arrow := P_COM_FOOT                                                                       # 深色箭头/字
	var b1 := Rect2(cx - T * 0.04, top + T * 0.04, T * 0.42, T * 0.20)                           # 上牌·指右
	draw_rect(b1, board, true)
	draw_rect(b1, D_WOOD_LINE, false, 1.2)
	draw_colored_polygon(PackedVector2Array([                                                    # 右箭头
		Vector2(b1.end.x - T * 0.02, b1.position.y + b1.size.y * 0.5),
		Vector2(b1.end.x - T * 0.13, b1.position.y + T * 0.03),
		Vector2(b1.end.x - T * 0.13, b1.end.y - T * 0.03)]), arrow)
	var b2 := Rect2(cx - T * 0.38, top + T * 0.30, T * 0.42, T * 0.20)                           # 下牌·指左
	draw_rect(b2, board.darkened(0.06), true)
	draw_rect(b2, D_WOOD_LINE, false, 1.2)
	draw_colored_polygon(PackedVector2Array([                                                    # 左箭头
		Vector2(b2.position.x + T * 0.02, b2.position.y + b2.size.y * 0.5),
		Vector2(b2.position.x + T * 0.13, b2.position.y + T * 0.03),
		Vector2(b2.position.x + T * 0.13, b2.end.y - T * 0.03)]), arrow)

## Sim 的【精确格心】。裁剪/LOD 判定只许用它（见 _render_pos 一节的红线）。
func _center(ag: Dictionary) -> Vector2:
	var p: Vector2i = ag["pos"]
	return Vector2(p.x * T + T * 0.5, p.y * T + T * 0.5)

## 【绘制】坐标 = 插值后的渲染坐标；没有记录（首帧 / 非 town / 刚进场）时回落到精确格心。
func _rpos(ag: Dictionary) -> Vector2:
	return _render_pos.get(String(ag["id"]), _center(ag))

## 渲染时钟：把渲染坐标向格心推进。只读 Sim.agents，绝不写 Sim。
func _process(delta: float) -> void:
	if Sim.world.is_empty():
		return
	if _audit_path != "":
		_audit_step()
		return                  # 审计模式独占：插值也会让画面动，会污染逐 pass 差值
	if _void_gate:
		_void_gate_step()
	if _cache_gate:
		_cache_gate_step()
	_refresh_view_metrics()     # 界外层的脏判定要用【本帧】的取景，不能等到 _draw 才刷
	_void_sync()
	var _vk := _view_state_key()   # ★ 见 _view_state_key()：暂停时 tick 停了，这几样变了也得重画
	if _vk != _view_key:
		_view_key = _vk
		queue_redraw()
	# 一格实际占多少实时秒：tick_interval / speed（x8 加速时只有 0.01s）。
	# 下限 0.008 防除零/抖动，上限 0.16 防 --speed 0 时把收敛拖成"永远在爬"。
	var step := clampf(Sim.tick_interval / maxf(Sim.speed, 0.25), 0.008, 0.16)
	var k := clampf(delta / maxf(step * LERP_FRACTION, 0.001), 0.0, 1.0)
	var tele := TELEPORT_TILES * T
	var dirty := false
	var alive := {}
	for ag in Sim.agents:
		var id := String(ag["id"])
		alive[id] = true
		var target := _center(ag)
		# 朝向/行走帧按【格】的变化判定（Sim 的离散移动），与插值进度解耦。
		# 旧版把这段差分做在 _draw 里，而 _draw 从"每 tick 一次"变成"每帧一次"之后，
		# 差分会在移动后的第一帧就归零 → 人一边滑行一边播 idle。
		var gp: Vector2i = ag["pos"]
		var prev: Vector2i = _prev_pos.get(id, gp)
		if gp != prev:
			var d := gp - prev
			if absi(d.x) >= absi(d.y) and d.x != 0:
				_walk_row[id] = 1
				_facing_left[id] = d.x < 0
			elif d.y < 0:
				_walk_row[id] = 3
			else:
				_walk_row[id] = 1
			_prev_pos[id] = gp
		var cur: Vector2 = _render_pos.get(id, target)
		if cur.distance_to(target) > tele:
			cur = target
		else:
			cur = cur.lerp(target, k)
		var moving := cur.distance_to(target) > SNAP_PX
		if not moving:
			cur = target        # ★硬吸附：冻结 tick 下渲染坐标 ≡ 格心，--shot 前后 bbox 必须是 None
		if not _render_pos.has(id) or _render_pos[id] != cur or bool(_moving.get(id, false)) != moving:
			dirty = true
		_render_pos[id] = cur
		_moving[id] = moving
	if _render_pos.size() != alive.size():      # 换 N / 读档：清掉已不存在的 id，别留幽灵
		for id in _render_pos.keys():
			if not alive.has(id):
				_render_pos.erase(id); _moving.erase(id); _walk_row.erase(id)
				_prev_pos.erase(id); _facing_left.erase(id)
				dirty = true
	if dirty:
		queue_redraw()

## 关系连线：|affinity|>20 才画；绿=亲密、红=敌意，粗细/透明度随强度。
## 是否在镇上平面（非咖啡馆等室内）——室内居民用室内局部坐标，画在镇上会"鬼影"，与 agent 主循环(:752)同款过滤。
func _in_town(ag: Dictionary) -> bool:
	return String(ag.get("space", "town")) == "town"

## Main 当前选中的居民（只读，View→View）。没有选中或拿不到 → 空串。
func _selected_id() -> String:
	var m := get_parent()
	if m == null:
		return ""
	var v = m.get("_selected_id")
	return String(v) if v != null else ""

## 关系连线。旧版：|affinity|>20 的【每一对】都画，无上限、无衰减、无裁剪 —— N=12 时最多 66 条，
## N=60 时上千条，第 48 天变成一张横穿全镇的洋红蛛网；真机实测这一趟吃掉 166.7ms 帧里的 59.5ms。
## 现在四道闸：每人只留最强 K 条 → 屏幕长度衰减 → 视口裁剪 → 选中某人时其余线退到背景。
## 全是 DRAW 侧取舍，Sim 读不到任何一个（相机无关红线：game/bench/lod_verify.gd）。
func _draw_relationship_lines() -> void:
	if rel_mode == RelMode.OFF:
		return
	var sel := _selected_id()
	if rel_mode == RelMode.SELECTED and sel == "":
		return
	# 1) 每人取 top-K：一条边只要落在任一端的 top-K 里就保留（否则单侧的强关系会被对方的更强关系挤掉）
	var keep := {}
	for ag in Sim.agents:
		if not _in_town(ag):
			continue   # 室内居民不在镇上画关系线（否则室内局部坐标鬼影）
		var aid := String(ag["id"])
		if rel_mode == RelMode.SELECTED and aid != sel:
			continue
		var top := []      # ≤K 条，按 |affinity| 降序；同强度先到先得（relationships 是有序字典 → 确定，画面不闪）
		for oid in ag["relationships"]:
			var aff := float(ag["relationships"][oid].get("affinity", 0.0))
			var mag := absf(aff)
			if mag <= REL_MIN_AFF:
				continue
			if top.size() >= REL_TOP_K and mag <= float(top[top.size() - 1]["mag"]):
				continue
			var ins := top.size()
			for i in top.size():
				if mag > float(top[i]["mag"]):
					ins = i
					break
			top.insert(ins, {"id": String(oid), "aff": aff, "mag": mag})
			if top.size() > REL_TOP_K:
				top.resize(REL_TOP_K)
		for e in top:
			var oid2 := String(e["id"])
			var k := (aid + ">" + oid2) if aid < oid2 else (oid2 + ">" + aid)
			keep[k] = e["aff"]
	# 2) 画：视口裁剪 + 屏幕长度衰减 + 选中聚焦
	for k in keep:
		var ids := String(k).split(">")
		var a: Dictionary = Sim.get_agent(ids[0])
		var b: Dictionary = Sim.get_agent(ids[1])
		if a.is_empty() or b.is_empty() or not _in_town(a) or not _in_town(b):
			continue
		# 裁剪按【格心】（_center），绘制按【渲染坐标】（_rpos）：剔除不许依赖插值残余。
		var c1 := _center(a)
		var c2 := _center(b)
		if not _vis.intersects(Rect2(c1, Vector2.ZERO).expand(c2)):
			continue                                   # 整段在视口外 → 一笔不画
		var p1 := _rpos(a)
		var p2 := _rpos(b)
		var aff2 := float(keep[k])
		var t := clampf(absf(aff2) / 100.0, 0.0, 1.0)
		var screen_len := c1.distance_to(c2) * _zoom   # 长度衰减也走格心：否则每帧微抖，长线会轻微闪
		var fade := clampf(1.0 - (screen_len - REL_FADE_PX) / REL_FADE_PX, 0.25, 1.0)
		var focus := 1.0
		var width := 1.2 + t * 2.4
		if sel != "" and rel_mode == RelMode.ALL and ids[0] != sel and ids[1] != sel:
			focus = 0.55                               # 选了人 → 别人的线退半档背景，ta 的关系站出来（不是抹掉：全镇结构仍要看得见）
		elif sel != "":
			width += 1.2                               # 选中当事人的线加粗一档
		var col := (X_SIGNAL_POS if aff2 > 0.0 else X_SIGNAL_NEG)
		col.a = maxf(REL_A_FLOOR, (0.26 + t * 0.52) * fade * focus)   # E5/W4：见 REL_A_FLOOR
		draw_line(p1, p2, col, width)

## S3a 派系：同派系成员脚下画同色环（颜色由派系 medoid id 确定性派生）。
##
## ★ 这里改了两件事，第二件才是真正的病（docs/46 §二-D3-4 把它写成"派系环盖住了 C1 的柔和椭圆影"，
##   **但绘制序是反的**：`_draw_faction_rings()` 在 agent 循环【之前】调用，所以环在影子【下面】）。
##   实际的缺陷是几何：环是一个**正圆**，半径 0.20 格 ⇒ 上下各伸出 9.6px；
##   而 C1 那圈影子是 y 轴压扁 0.40 的**地面椭圆**，上下只有 ±4.8px。
##   一个立在屏幕平面上的正圆套着一个躺在地面上的椭圆——两者根本不在同一个平面里，
##   于是环既不像"脚下的地面标记"，又长到会横穿**邻居**的名牌（实测 zoom_before_agents.png：
##   上面那位的脚环正好圈住下面那位的「小薇」名牌）。
##   ⇒ 改成同样 0.40 压扁的地面椭圆（用 draw_polyline 而不是 draw_set_transform 缩放，
##      否则线宽会被一起压扁成 0.8px）。半径放到 0.30 格去外切影子，**竖直占位反而从 ±9.6px 降到 ±5.8px**。
func _draw_faction_rings() -> void:
	for ag in Sim.agents:
		if not _in_town(ag):
			continue   # 室内居民不在镇上画派系环
		var fac := String(ag.get("faction", ""))
		if fac == "":
			continue
		var col := _faction_color(fac)
		col.a = 0.80
		if not _vis.has_point(_center(ag) + Vector2(0, T * 0.30)):
			continue                                  # 裁剪走格心
		var c := _rpos(ag) + Vector2(0, T * 0.30)     # 落脚线（与影子/精灵底边同一条）
		_draw_ground_ring(c, T * 0.30, col, 2.0)

## 躺在地面上的椭圆环（y 轴压扁 0.40，与 C1 的脚影同一个平面）。线宽保持均匀。
func _draw_ground_ring(c: Vector2, rx: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in range(21):
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * rx * 0.40))
	draw_polyline(pts, col, width, true)

## 派系强调色：从 docs/44 的 40 色目标表（game/assets/art/palette.gpl）里取 5 个强调色轮换。
## 旧实现是 `Color.from_hsv(hash%360/360, 0.65, 0.95)` —— **整个色相环上的任意霓虹**，
## 在一套低饱和的日常小镇调色板上读作调试标记而不是归属标记。
## 刻意**没有**取的两个：`com-roof #B5484A`（与关系连线的负向红 `#e85a5a`、冲突「!」`#ff6b6b` 同族）
## 与 `water-lit #86B7C8`（与盟约双线的青 `#39d4c8` 同族）——语义撞色比颜色难看更糟。
## 哈希换成项目自有的 `Sim.fnv1a32`（红线#1）：`String.hash()` 是引擎内建实现，换个 Godot 版本
## 就可能把全镇的派系色静默洗一遍。
## ★ E5/W4：五个强调色里有**两个在它们实际会落到的地面上过不了 JND**——而这条只有"合成之后再算"才看得见
##（环是 `col.a = 0.80` 画在地面上的，锚点对锚点的样本结构上够不到它）。实测（四昼夜档 × 四季 × 三天气的最小值）：
##   `grass-autumn` 压在**土路**上 **0.91**（土路本身就是一片赭黄）、`grass-winter` 压在**公共区地板**上 **1.53**。
##   ⇒ 这两个派系的居民站在那两种地面上时，脚环等于没画。
## 换成对全部 7 种地面都 ≥5 且与保留三色都 ≥6 的两个：`X_COLD_WHITE`(冷白) 与 `P_WRK_ROOF`(深蓝黑)。
## 换完全组对地面的最小值 0.91 → **2.71**（新的最弱一环是**保留下来的** foliage-mid 压在草上——
## 橄榄绿画在草上，它天生就是这一组里最难的一格；2.71 已在 JND 之上，本棒不再动它）。
const FACTION_ACCENTS := [
	P_PUB_ROOF,   # pub-roof     蓝
	X_COLD_WHITE,   # 冷白（替 grass-autumn：它在土路上 0.91）
	P_FOLIAGE_M,   # foliage-mid  橄榄绿
	P_WRK_ROOF,   # 深蓝黑（替 grass-winter：它在公共区地板上 1.53）
	P_RES_ROOF,   # res-roof     砖红（比 UI 的告警红暗得多，不混）
]

func _faction_color(fac: String) -> Color:
	return FACTION_ACCENTS[Sim.fnv1a32(fac) % FACTION_ACCENTS.size()]

## S3b 互助盟约：active pact 双方画青色双线 + 中点握手标记。
func _draw_pact_links() -> void:
	var drawn := {}
	for ag in Sim.agents:
		if not _in_town(ag):
			continue   # 室内居民不在镇上画盟约连线
		for oid in ag.get("pacts", {}):
			var p: Dictionary = ag["pacts"][oid]
			if String(p.get("status", "")) != "active":
				continue
			var key := String(p.get("key", ""))
			if drawn.has(key):
				continue
			drawn[key] = true
			var other: Dictionary = Sim.get_agent(oid)
			if other.is_empty() or not _in_town(other):
				continue
			if not _vis.intersects(Rect2(_center(ag), Vector2.ZERO).expand(_center(other))):
				continue                              # 裁剪走格心
			var a := _rpos(ag)
			var b := _rpos(other)
			var perp := (b - a).orthogonal().normalized() * 2.0
			var cyan := Color(X_PACT, 0.7)
			draw_line(a + perp, b + perp, cyan, 1.6)
			draw_line(a - perp, b - perp, cyan, 1.6)
			# 中点标记：原本是 🤝，但它走 ThemeDB.fallback_font 而那张表【没有 emoji】→ 每条盟约中点都是一个豆腐框。
			# 换成自带中文字体一定有的「盟」，零新增资源、手机上同样成立。
			if _zoom >= LABEL_MIN_ZOOM:
				_draw_plate_text((a + b) * 0.5 + Vector2(0, 5), "盟", 13, cyan, Color(0, 0, 0, 0.5))

## 对话连线：正在一次社交事务里的两人之间画一条暖黄线。
func _draw_talking_links() -> void:
	for ag in Sim.agents:
		if not _in_town(ag):
			continue   # 室内居民不在镇上画对话连线
		var opt = ag.get("option")
		if opt != null and String(opt.get("kind", "")) == "social":
			var other: Dictionary = Sim.get_agent(String(opt.get("partner", "")))
			if not other.is_empty() and _in_town(other):
				if _vis.intersects(Rect2(_center(ag), Vector2.ZERO).expand(_center(other))):
					draw_line(_rpos(ag), _rpos(other), Color(X_GOLD, 0.85), 2.5)   # 裁剪走格心、绘制走渲染坐标

## 居中的「深色底板 + 文字」。anchor = 文字基线中点；返回底板矩形，供旁边的标记贴边摆放。
## 旧版的名字是【无描边无底板的纯白 draw_string】——在草地上勉强能读，一压到这次新铺的木/石地板就糊没了。
func _draw_plate_text(anchor: Vector2, txt: String, fs: int, fg: Color, bg: Color) -> Rect2:
	var fnt := Art.font()
	var sz := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var plate := Rect2(anchor.x - sz.x * 0.5 - 4.0, anchor.y - sz.y + 2.0, sz.x + 8.0, sz.y + 3.0)
	draw_rect(plate, bg, true)
	draw_string(fnt, Vector2(anchor.x - sz.x * 0.5, anchor.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
	return plate

## 头顶气泡的动作文案：社交动作在 Sim 里是英文 id（greet/give/gossip_rep/…），直接 str() 出来就是生英文。
## 走 Sim._verb（只读 Sim.gd，不改它）转中文；物件/行程动作本来就是中文，_verb 对未匹配项原样返回 → 不受影响。
func _action_label(opt: Dictionary) -> String:
	var act := str(opt.get("action", ""))
	if act == "":
		return ""
	return Sim._verb(act) if String(opt.get("kind", "")) == "social" else act

func _draw_agent(ag: Dictionary) -> void:
	var center := _rpos(ag)                   # 绘制坐标（插值后）；本函数不做裁剪判定
	var feet := center.y + T * 0.30          # 落脚线：影子 / 派系环 / 精灵底边都对齐它
	var col := Color(str(ag.get("persona", {}).get("color", "#ffffff")))
	var spr := _hued_tex(str(ag.get("persona", {}).get("sprite", "")), String(ag["id"]))  # L6：克隆取确定性色相变体，命名 6 人=正典
	if spr == null:
		spr = _fallback_tex(ag)              # 空/缺 sprite（玩家）→ 体面回退，别再画圆盘
	var head := center.y - T * 0.32          # 头顶（fallback 圆的情形）
	if spr != null:
		# 软阴影 + 按移动选行走帧（cols0-3 循环，左向水平翻转）。整数 2x 缩放，且把源帧里人物的【脚】压在落脚线上
		var fr := _agent_frame(ag)
		# 脚下阴影：旧版是 draw_circle(feet, T*0.22, α=.25) —— 直径 0.44 格几乎和精灵一样宽、边缘还是硬的，
		# 读起来像"人浮在一个圆盘上"。改成压扁的椭圆（y 轴 0.40）+ 3 圈由外向内变实的 alpha 衰减，
		# 核心宽度收到 0.15 格；叠加后中心不透明度 ≈0.27，与旧值同档，但边缘化开、不再抢精灵的轮廓。
		draw_set_transform(Vector2(center.x, feet), 0.0, Vector2(1.0, 0.40))
		for si in 3:
			draw_circle(Vector2.ZERO, T * 0.15 * (1.0 + float(2 - si) * 0.34), Color(0, 0, 0, 0.07 + float(si) * 0.030))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var sz := AGENT_PX
		var top := feet - sz * (CHAR_FEET_ROW / 32.0)
		head = top + sz * (CHAR_HEAD_ROW / 32.0)
		var src := Rect2(int(fr["col"]) * Art.CHAR_FRAME.x, int(fr["row"]) * Art.CHAR_FRAME.y, Art.CHAR_FRAME.x, Art.CHAR_FRAME.y)
		if bool(fr["flip"]):
			draw_set_transform(Vector2(center.x, top), 0.0, Vector2(-1, 1))
			draw_texture_rect_region(spr, Rect2(-sz * 0.5, 0.0, sz, sz), src)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(spr, Rect2(center.x - sz * 0.5, top, sz, sz), src)
	else:
		draw_circle(center, T * 0.32, col)
		draw_circle(center, T * 0.32, Color(0, 0, 0, 0.4), false, 2.0)
	# 玩家标识：金环保留（--player 模式一眼可辨"这是我"），但**挪到地面平面**——
	# 旧的是屏幕平面上以【身体中心】为圆心的正圆（r=0.42 格），套在一个立着的小人身上时
	# 既不像地面标记、又会和头顶名牌/脚下气泡打架。现在与影子/派系环同一个 0.40 压扁的地面椭圆。
	if ag.get("is_player", false):
		_draw_ground_ring(Vector2(center.x, feet), T * 0.38, X_PLAYER_GOLD, 2.5)
	if _zoom < LABEL_MIN_ZOOM:
		return          # 全镇俯瞰档：名字/emote/气泡/需求条缩到几像素只剩糊斑 —— 不画，画面更干净、填充率也省下来
	var aid := String(ag["id"])
	var sy = _say.get(aid)
	var saying: bool = sy != null and Sim.tick_no < int(sy["until"])
	var focus := _is_focus(ag, aid, saying)          # 恒显档（见 LABEL_FADE_LO 抬头）
	# 缩放淡入系数（**不含**焦点豁免）与最终系数。分成两个的理由见下面需求条那一段。
	var zoom_detail := clampf((_zoom - LABEL_FADE_LO) / (LABEL_FADE_HI - LABEL_FADE_LO), 0.0, 1.0)
	# 非焦点者的淡入系数：0 ⇒ 一个字不画；1 ⇒ 与改动前逐字节相同。
	var detail := 1.0 if focus else zoom_detail
	# 最紧迫需求条（落脚线正下方）：只在【危机】时出现（原本恒显）。
	# **故意不给焦点豁免**：选中者的五项需求本来就在观察台上带数字写着，那条 32×4px 的条是纯冗余；
	# 让它只在危机时出现，这一层才从"装饰"变回"信号"。细查档（zoom_detail>0）照旧全量给出
	# —— 所以"看不见需求"永远只是一次缩放的距离。
	# ⚠️ **这里本来还写了一条 `or is_player`（"自己的状态恒显"），实测证明那是【死代码】，已删**：
	#   `Sim.add_player()` 把玩家五项需求全部冻结在**恰好 100.0**（Sim.gd:753-754，M1 有意为之），
	#   而 `_draw_urgent_need` 的 `worst` 初值就是 100.0 且比较是严格 `<` ⇒ 全 100 时 `worst_id` 永远为空 ⇒ 直接 return。
	#   实测 before/after 两棵树的 `--player --select player` 帧在玩家脚下的绿色像素**都是 0**。
	#   留着那一条只会让人以为玩家有条需求条。真要开玩家生存玩法时，危机分支自然会接管。
	if zoom_detail > 0.0 or _worst_need(ag) < NEED_CRISIS:
		_draw_urgent_need(Vector2(center.x, feet + T * 0.20), ag)
	# 头顶 emote（社交事件触发，短暂显示）：20px 源 × 2 整数倍。
	# **恒显、不参与稀释**：它本身就是"此刻有事发生"的信号，且是 D4 录屏抽帧要抓的东西之一。
	var name_y := head - T * 0.12            # 名字基线：紧贴头顶上方
	var em = _emote.get(aid)
	if em != null and Sim.tick_no < int(em["until"]):
		var et: Texture2D = em["tex"]
		draw_texture_rect_region(et, Rect2(center.x - EMOTE_PX * 0.5, name_y - T * 0.50 - EMOTE_PX, EMOTE_PX, EMOTE_PX), Rect2(0, 0, et.get_width(), et.get_height()))
	# 名牌：名字 + 冲突「!」+ 约见「约」画进【同一块底板】。
	# 旧版把两个标记按固定像素偏移丢在名字外面，人挨着站时标记落在【邻居的名字】旁边，读不出是谁在闹。
	var has_cf := _in_conflict(aid)
	var has_mt := _has_meet(aid)
	if detail > 0.0:
		var nm := str(ag.get("persona", {}).get("name", aid))
		var fnt := Art.font()
		var nsz := fnt.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var lw := 11.0 if has_cf else 0.0
		var rw := 18.0 if has_mt else 0.0
		var total := nsz.x + lw + rw
		draw_rect(Rect2(center.x - total * 0.5 - 4.0, name_y - nsz.y + 2.0, total + 8.0, nsz.y + 3.0), Color(0, 0, 0, 0.62 * detail), true)
		var tx := center.x - total * 0.5
		if has_cf:
			draw_string(fnt, Vector2(tx, name_y), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, X_SIGNAL_NEG * Color(1, 1, 1, detail))
			tx += lw
		draw_string(fnt, Vector2(tx, name_y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.97 * detail))
		if has_mt:
			draw_string(fnt, Vector2(tx + nsz.x + 4.0, name_y), "约", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, X_GOLD * Color(1, 1, 1, detail))
	# 气泡：交谈台词（短暂）优先，其次当前动作。放在需求条下方 → 与派系环/需求条不再互相穿插。
	# 台词恒显（saying ⇒ focus，见 _is_focus）；**动作牌**才是被稀释的那一层——评审那一帧里 5 张牌
	# 写着同一个「吃饭」，删掉 4 张丢失的信息量是 0，而它们占掉的正是人眼最先扫到的一层。
	var bubble := ""
	if saying:
		bubble = String(sy["text"])
	elif detail > 0.0:
		var opt = ag.get("option")
		if opt != null:
			bubble = _action_label(opt)
	if bubble != "":
		var ba := 1.0 if saying else detail
		_draw_plate_text(Vector2(center.x, feet + T * 0.64), bubble, 12, Color(1, 1, 1, 0.95 * ba), Color(0, 0, 0, 0.72 * ba))

## 恒显档的判据。**它就是这一棒的"信息还够不够得着"的定义**：凡是玩家此刻需要认出来的人，
## 一律不参与稀释——选中者（观察台正在讲他）、玩家自己、冲突/约会当事人（剧情的两端）、
## 正在一次社交事务里的双方、以及正在说话的人（一句没有名字的台词等于没有）。
func _is_focus(ag: Dictionary, aid: String, saying: bool) -> bool:
	if saying or ag.get("is_player", false):
		return true
	if aid != "" and aid == _rc_sel_id:
		return true
	return _rc_conflict_ids.has(aid) or _rc_meet_ids.has(aid) or _rc_social_ids.has(aid)

## 最低的一项需求（0..100）。_draw_urgent_need 内部本来就要算一次；这里单拎出来给"是否危机"用。
func _worst_need(ag: Dictionary) -> float:
	var worst := 100.0
	for nid in ag.get("needs", {}):
		var v := float(ag["needs"][nid])
		if v < worst:
			worst = v
	return worst

## 程序化像素床（顶视角）：木框 + 床单 + 枕头 + 被子。base=格左上像素。
## ── 建筑（切顶俯视）────────────────────────────────────────────────────────
const WALL := 13.0     # 外墙厚(px)≈0.27 格：够读出体积，又不吃室内——室内可走面积仍是房间 rect 本身（墙向外长）

## 房型显示名：buildings.json 的 room.type 是【英文键】（_mat_wall/_mat_floor 靠子串匹配它选材质），
## 但屏幕上其余全是中文——直接把键画上去会突兀。这里只做「键→显示名」，缺表则原样回落（旧的
## parlor/workshop/quietroom 三个模板名也在表里）。纯渲染：不进 digest、不回喂 Sim。
const ROOM_NAME := {
	"bedroom": "卧房", "parlor": "茶座", "quietroom": "静室", "workshop": "工坊",
	"workroom": "工位", "storeroom": "库房", "cafe_bar": "后厨", "bathroom": "浴池",
	"washroom": "盥洗", "shopfloor": "货架",
}

## 墙比地板【暗】一档：屋顶被切掉后墙体仍处在背光面，明度差才让"墙/地"分得开（旧版两者同明度 → 一块板）。
func _mat_wall(rtype: String) -> Color:
	if "work" in rtype or "shop" in rtype: return P_INT_COM     # 石/土墙
	if "wash" in rtype or "bath" in rtype: return P_WRK_ROOF
	if "quiet" in rtype: return P_INT_WRK
	return P_COM_FOOT                                             # 木墙（居室/茶座）

## 夜量 0..1（夜=1、昼=0，晨昏平滑）。与 Main._daylight 的色停同频——它把整块世界画布乘暗，
## 所以室内要靠【相对】暖度把自己从冷夜里拉出来。
func _night_amt() -> float:
	var tod := Sim.time_of_day()
	if tod < 0.20: return 1.0
	if tod < 0.32: return 1.0 - (tod - 0.20) / 0.12
	if tod < 0.72: return 0.0
	if tod < 0.88: return (tod - 0.72) / 0.16
	return 1.0

## 房型 → 地板色。**E5/W3：这里原本有四个房型全部返回 P_COM_LINE**（bed / parlor / cafe / shop），
## 于是 8 个房型只画得出 5 种地板，六对房型之间 ΔE00 **恰好 0.00**。
## D6 的 33 对相邻表面样本抓不到它，因为那份样本里根本没有"房间地板 vs 另一个房间地板"这一类。
## ⚠️ 其中**只有一对真的会同框**：`cafe`(cafe_kitchen) 与 `parlor`(cafe_hall) 同属 buildings.json 的 cafe 楼；
##   评审点名的 bed↔shop / parlor↔shop 分处地图两端（home@19,14 与 shop@50,6），**永远不同框**。
##   但"今天的地图上它们不同框"是关于**这一张地图**的事实，不是代码的性质（docs/47 §三 还要加新建筑），
##   所以四个都给了各自的值，而不是只拆开会同框的那一对。
## 取值全部来自既有授权色（不新增），并且逐对量过：对**其余 7 种地板 + 自己的地毯 + 自己的内墙**
## 的最差 ΔE00（四昼夜档 × 四季 × 三天气）= **2.50**，改前 = **0.00**。
func _mat_floor(rtype: String) -> Color:
	if "bed" in rtype: return P_COM_LINE      # 卧房：暖木（不动，D6 量过的「地毯·卧房↔卧房地板」靠它）
	if "cafe" in rtype: return P_STONE        # 咖啡吧台后厨：灰石防滑地（与同楼的茶座拉开：0.00 → 12.10）
	if "parlor" in rtype: return P_PLAZA      # 茶座：暖砂铺装
	if "work" in rtype: return P_STONE_LINE
	if "quiet" in rtype: return P_NIGHT
	if "wash" in rtype or "bath" in rtype: return P_WATER_DEEP
	if "shop" in rtype: return P_RES_TOP      # 店堂：浅木板
	# 库房原先落在下面那个默认档 X_WOOD_MID 上，而它自己的内墙是 P_COM_FOOT ——
	# 两个深棕，**同一间房里贴着**，实测最差 ΔE00 **1.29**（改动后它一度是全表最小的一对）。
	# 这条不是 W3 点名的，是量具补齐之后自己冒出来的：房间地板此前从没和【自己的内墙】比过。
	if "store" in rtype: return P_COM_TOP     # 库房：浅一档的木板（↔内墙 1.29 → 6.79）
	return X_WOOD_MID

## 一栋建筑：落地影 → 外墙(屋檐/受光高光) → 室内地板+材质纹理 → 内墙投影 → 南门 → 北窗 → 有人透暖光。
func _draw_building(rid: String, inner: Rect2, rtype: String, enclosed: bool) -> void:
	var outer := inner.grow(WALL)
	var wc := _mat_wall(rtype)
	var fc := _mat_floor(rtype)
	# 落地阴影（右下偏移）→ 体积感：让房子"坐"在地上而不是浮在草上
	draw_rect(Rect2(outer.position + Vector2(4.0, 5.0), outer.size), Color(0, 0, 0, 0.30), true)
	# 外墙实心 + 屋檐暗带 + 上/左受光高光 + 外缘描边
	draw_rect(outer, wc, true)
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, WALL * 0.55)), Color(0, 0, 0, 0.30), true)
	draw_line(outer.position, Vector2(outer.end.x, outer.position.y), wc.lightened(0.30), 2.0)
	draw_line(outer.position, Vector2(outer.position.x, outer.end.y), wc.lightened(0.16), 2.0)
	# AT1（编号148）：屋脊暖盖——顶墙压一条按房号确定性选档的木瓦脊，同类两间读作两间不同的屋子（纯装饰）。
	# 取暖木三档（非饱和红）：冷色的工坊/公共室内盒压上也不跳色，读作一道木脊瓦而非红条。
	var ridge: Color = [X_WOOD_MID, P_COM_FOOT, D_WOOD_LINE][int(Sim._hash01(rid + ":ridge") * 3.0) % 3]
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, 3.0)), Color(ridge.r, ridge.g, ridge.b, 0.85), true)
	draw_rect(Rect2(outer.position + Vector2(0.0, 3.0), Vector2(outer.size.x, 2.0)), Color(0, 0, 0, 0.22), true)  # 脊下投影
	draw_rect(outer, Color(0, 0, 0, 0.38), false, 1.5)
	# 室内地板
	draw_rect(inner, fc, true)
	# 地板材质：石地/铺装走方砖，木地板走木纹横板。
	# （E5：随 _mat_floor 一起改——`cafe` 现在是灰石、`parlor` 是暖砂铺装 ⇒ 进方砖；
	#   `shop` 现在是浅木板 ⇒ 出方砖进木纹。不改材质的话会画出"石头色的木地板"。）
	if "wash" in rtype or "bath" in rtype or "cafe" in rtype or "parlor" in rtype:
		var gx := inner.position.x + T * 0.5
		while gx < inner.end.x - 1.0:
			draw_line(Vector2(gx, inner.position.y + 1), Vector2(gx, inner.end.y - 1), Color(0, 0, 0, 0.10), 1.0)
			gx += T * 0.5
		var gy := inner.position.y + T * 0.5
		while gy < inner.end.y - 1.0:
			draw_line(Vector2(inner.position.x + 1, gy), Vector2(inner.end.x - 1, gy), Color(0, 0, 0, 0.10), 1.0)
			gy += T * 0.5
	else:
		var py := inner.position.y + T * 0.5
		while py < inner.end.y - 1.0:
			draw_line(Vector2(inner.position.x + 1, py), Vector2(inner.end.x - 1, py), Color(0, 0, 0, 0.11), 1.0)
			py += T * 0.5
	# 陈设：地毯 + 靠墙杂物（"住着人"的密度——空房间是"简陋"的另一半主因）
	_draw_room_decor(rid, inner, rtype)
	# 内墙投影：墙在室内投下的暗边 → 读出"墙有厚度"
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 4.0)), Color(0, 0, 0, 0.26), true)
	draw_rect(Rect2(inner.position, Vector2(4.0, inner.size.y)), Color(0, 0, 0, 0.16), true)
	# 南墙开门（确定性位置）：门洞露地板色 + 深色门槛
	var dw := minf(T * 0.85, inner.size.x)
	var dspan := maxf(0.0, inner.size.x - dw)
	var dx := inner.position.x + Sim._hash01(rid + ":door") * dspan
	draw_rect(Rect2(dx, inner.end.y, dw, WALL), fc.darkened(0.12), true)
	draw_rect(Rect2(dx, inner.end.y + WALL - 3.0, dw, 3.0), D_WOOD_LINE, true)
	draw_rect(Rect2(dx - 1.0, inner.end.y, dw + 2.0, 2.5), X_WOOD_MID, true)                        # 门楣（过梁）：门顶一道木过梁，读作门框
	# 有人在内？（灯火强度用）
	var occ := 0
	for ag in Sim.agents:
		if inner.has_point(Vector2(ag["pos"].x * T + T * 0.5, ag["pos"].y * T + T * 0.5)):
			occ += 1
	# ── 灯火（Stoneshard/ZeroSievert 的招牌：暖池 vs 冷夜）────────────────────
	# 夜里 enclosed 房间点灯（有人更旺）。CanvasModulate 会把整幅世界乘暗，故这里要下得【重】——
	# 乘暗后剩下的"暖 vs 冷"相对差，才是玩家读到的那盏灯。
	var night := _night_amt()
	# 平铺底光压低（0.52→0.26）：整块均匀刷色会把地毯/杂物/木纹全洗平——光要有【落点】，
	# 所以大头交给中心的径向暖池，底光只负责"这屋是亮的"。
	var lit := 0.0
	if enclosed:
		lit += 0.26 * night
	lit += minf(0.14, occ * 0.05) * (0.45 + 0.55 * night)
	if lit > 0.001:
		draw_rect(inner, Color(X_GLOW_DEEP, lit), true)         # 偏橙灯火色：被夜蓝乘过后仍咬得住暖调
	# 灯芯：房间中心的径向暖池（"光源在屋里"的层次）——夜里最明显，白天几乎不见
	var pool := (0.30 * night + minf(0.20, occ * 0.07))
	if pool > 0.01:
		var cen := inner.get_center()
		var rad := minf(inner.size.x, inner.size.y) * 0.55
		for k in 4:
			var f := 1.0 - float(k) / 4.0
			draw_circle(cen, rad * (0.30 + 0.24 * float(k)), Color(X_GLOW, pool * 0.13 * f))
	# 北墙开窗（enclosed 才有；1-2 扇，确定性）；夜里从窗口向北洒一片暖光到地上
	if enclosed:
		var n := 1 + int(Sim._hash01(rid + ":win") * 2.0)
		for i in n:
			var ww := minf(T * 0.55, inner.size.x * 0.5)
			var t := (float(i) + 0.5) / float(n)
			var wx := inner.position.x + t * inner.size.x - ww * 0.5
			var wy := outer.position.y + WALL * 0.42
			var glow := 0.30 * night + minf(0.25, occ * 0.08) * night
			if glow > 0.01:                                    # 窗口洒光（越远越淡，三层叠出衰减）
				for k in 3:
					var sp := float(k + 1)
					draw_rect(Rect2(wx - sp * 3.0, outer.position.y - sp * 7.0, ww + sp * 6.0, sp * 7.0),
						Color(X_GLOW, glow * (0.30 - 0.07 * float(k))), true)
			# 窗本体：夜里点亮（暖黄），白天冷玻璃
			var wcol := X_GLOW.lerp(P_WRK_ROOF, 1.0 - night) if glow > 0.01 else P_WRK_ROOF
			draw_rect(Rect2(wx, wy, ww, WALL * 0.52), wcol, true)
			draw_rect(Rect2(wx, wy, ww, WALL * 0.52), Color(P_WATER_LIT, 0.45), false, 1.0)
	# 房型标签：压低存在感（不再是主视觉）。房间小于 ~2 格宽时不画——11px 字会横穿整间，读作乱码而非标签。
	# ★ E5：标签色必须跟着地板走。原来恒为淡暖 `X_PARCHMENT@0.45`，那在**当时全是深色**的地板上没问题；
	#   本棒把 cafe/parlor/shop/store 换成浅色地板之后，同一个淡标签压在浅地板上实测掉到
	#   **茶座 2.38 / 店堂 1.34**（低于 JND）——「店堂」两个字在改动后的图上肉眼就找不到了。
	#   这条是 R10 全帧眼验抓到的，**任何一张色差表都不会报它**（表里没有"标签 vs 它压着的地板"这一对；
	#   现在加进去了）。修法：按地板亮度二选一，两侧实测最差 4.03（原来最好的一档是 5.82）。
	if inner.size.x >= T * 1.9:
		var lab := D_WOOD_LINE if fc.get_luminance() >= 0.5 else X_PARCHMENT
		draw_string(Art.font(), inner.position + Vector2(6, 15), String(ROOM_NAME.get(rtype, rtype)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(lab, 0.45))

## 室内陈设（Stardew 的"住着人"密度）：地毯 + 靠墙杂物。全确定性（_hash01(room_id:key)），纯渲染不进 digest。
func _draw_room_decor(rid: String, inner: Rect2, rtype: String) -> void:
	# 地毯：够大的房间才铺；按房型给花色
	if inner.size.x >= T * 2.5 and inner.size.y >= T * 2.0:
		var rw := inner.size.x * (0.42 + 0.16 * Sim._hash01(rid + ":rugw"))
		var rh := inner.size.y * (0.38 + 0.16 * Sim._hash01(rid + ":rugh"))
		var rug := Rect2(inner.get_center() - Vector2(rw, rh) * 0.5, Vector2(rw, rh))
		var rc := D_RUG_RED
		if "quiet" in rtype: rc = P_INT_WRK
		elif "parlor" in rtype or "cafe" in rtype: rc = D_RUG_OLIVE
		elif "work" in rtype or "shop" in rtype: rc = P_INT_COM
		elif "wash" in rtype or "bath" in rtype: rc = D_RUG_TEAL
		draw_rect(rug, rc.darkened(0.22), true)
		draw_rect(rug.grow(-4.0), rc, true)
		draw_rect(rug.grow(-4.0), rc.lightened(0.28), false, 1.0)
	# 靠墙杂物：2-4 件，沿内墙确定性摆放（小件、贴墙 → 不与床/桌打架）
	var n := 2 + int(Sim._hash01(rid + ":clutn") * 3.0)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var side := int(Sim._hash01(rid + ":side" + str(i)) * 3.0)
		var p := Vector2.ZERO
		match side:
			0: p = Vector2(inner.position.x + T * 0.34, inner.position.y + t * inner.size.y)
			1: p = Vector2(inner.end.x - T * 0.34, inner.position.y + t * inner.size.y)
			_: p = Vector2(inner.position.x + t * inner.size.x, inner.position.y + T * 0.42)
		_draw_prop(p, int(Sim._hash01(rid + ":prop" + str(i)) * 4.0))

## 程序化小杂物：0=木箱 1=陶罐 2=书堆 3=盆栽（包里没有的就程序化画——docs/13 的老规矩）
func _draw_prop(p: Vector2, kind: int) -> void:
	var s := T * 0.30
	match kind:
		0:
			draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), X_WOOD_MID, true)
			draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), D_WOOD_LINE, false, 1.0)
			draw_line(Vector2(p.x - s * 0.5, p.y), Vector2(p.x + s * 0.5, p.y), P_COM_LINE, 1.0)
		1:
			draw_circle(p, s * 0.44, D_POT)
			draw_circle(p, s * 0.44, D_WOOD_LINE)
			draw_circle(p - Vector2(0, s * 0.06), s * 0.36, P_COM_FACE)
			draw_rect(Rect2(p.x - s * 0.15, p.y - s * 0.58, s * 0.30, s * 0.22), P_COM_FOOT, true)
		2:
			for k in 3:
				draw_rect(Rect2(p.x - s * 0.40, p.y + s * 0.26 - float(k) * 4.0, s * 0.80, 3.2),
					[D_RUG_RED, D_BOOK_BLUE, P_FOLIAGE_D][k], true)
		_:
			draw_rect(Rect2(p.x - s * 0.26, p.y, s * 0.52, s * 0.34), D_POT, true)
			draw_circle(p - Vector2(0, s * 0.16), s * 0.32, P_FOLIAGE_D)
			draw_circle(p - Vector2(s * 0.12, s * 0.26), s * 0.16, P_FOLIAGE_M)

# ══ H3 · 物件槽位：显式 type→slot 表 + 「广告位对象必须解析出渲染器」断言 ═══════════════
#
# 病史（同一条隐式契约，三次发作，前两次都是靠人眼在整帧上抓到的）：
#   本文件此前用 `String(id).split("_")[0]` 当精灵槽 —— 即**数据里的对象 ID 前缀必须恰好等于
#   某张贴图名**，而没有任何东西在检查它。
#   ① F1 的四个工位（`ws_*`）以占位框出货了**一整波**，草地上直接印着数据键；
#      F5(cd55df6) 在 2560×1536 的一帧里看见了，修法是**把七个工位 ID 改名去命中已有贴图**
#      ——那是绕开，不是根治，耦合原样留着，G3 的砖垛紧接着就骑了上去。
#   ② 同一波里 F5 自己的 dock 也中招（`type:"waterfront"` 落不进 BLD_PAL，滩头画了一栋灰房子）。
#   ③ **今天仍然活着的第三个，本棒实测抓到**：选举通过时 spawn 的 WorldPatch（Sim.gd:2802，
#      `id = "civic_%s_%d" % [topic, day]`）前缀是 `civic`，没有任何贴图 ⇒ 它在镇北 [22,2]
#      画一个占位框、上面印着数据键「扩建咖啡馆」。探针实测（seed 1，20 天）：
#      `civic_cafe_expand_14  town  扩建咖啡馆  slot=civic  adv=1  ❌ 占位框+印数据键  first_day=14`
#      —— 选举每 14 天一次，所以**任何一局玩到第 14 天的正常游戏都会看到它**。
#      节日的 `fest_*` 只是侥幸：那个前缀恰好等于下面 match 里的程序化分支名。
#
# 现在：槽位由**显式表**决定，key 是数据的语义字段 `type`，不是 ID 的偶然前缀。
# 表里没有的 type ⇒ **解析不出槽位** ⇒ 醒目品红占位 + `push_error`（不是那个和墙同色的暖石灰框）。
#
# ⚠️ **这张表管不了、也永远管不了的那一半**：它只保证"这个 type 有一张真实存在的贴图"，
#    **不保证那张贴图画的是对的东西**。G3 的砖垛（type「砖垛」）解析到 `bench`，
#    渲染出来就是一条木凳 —— 上面那条「解析得出渲染器」的判据对它**全绿**，实测见回执 §does_not_detect。
#    下表里带 `# 借用` 的每一行都属于这一类，它们的**可读性**归 H1 的人眼判定，不归任何一道门。
#    别名的**增长**由下面 OBJ_SLOT_ALIAS_BUDGET 那道棘轮管住；**存量**（bench 5 / counter 4）管不住。
const OBJ_SLOT_BY_TYPE := {
	# ── 程序化画（无贴图；见 _draw_bed / _draw_stove）──
	"床": "bed",
	"灶台": "stove",
	"码头": "dock",
	# ── 有专属贴图（assets/art/obj/*.png；pro/obj_*.png 优先覆盖）──
	"吧台": "counter",
	"浴池": "bath",
	"工作台": "desk",
	"长椅": "bench",
	"游戏机": "arcade",
	# ── 借用：F1/F5/G3 的工位。这七行不是新决定，是把 F5「改 ID 去命中贴图」那次绕行
	#    从 ID 字符串里**搬到明面上**——同一份错配，区别只在于现在它是一行可以被 review 的表项。
	"面案": "counter",     # 借用（面案 ≠ 吧台）
	"摊位": "counter",     # 借用
	"清扫车": "bench",     # 借用（推车 ≠ 长椅）
	"渔台": "bench",       # 借用
	"讲台": "desk",        # 借用
	"柴垛": "bench",       # 借用 —— F5 自己记过"柴垛像条木凳"
	"砖垛": "bench",       # 借用 —— G3 的砖垛，docs/50 §〇 点名的那一个
	# ── 借用：选举 WorldPatch（上面病史③）。**这一行是本棒真正改掉的那个 bug**：
	#    改前它没有任何槽位 ⇒ 占位框 + 草地上印「扩建咖啡馆」；现在借咖啡馆吧台的贴图。
	#    仍然是借用，不是对的素材 —— 一并交给 H1 判读得出读不出。
	"扩建咖啡馆": "counter",
}

## 没有 `type` 字段的 spawn 家族只能按 ID 前缀认。今天只有一个：节日机会地形
## （festivals.json 的 objects[] 里**没有** type，Sim.gd:2753 给它派的 id 是 `fest_<名>_<日>_<序>`）。
## 这张表存在的意义是把"按前缀认"从**默认行为**降级成**列举出来的例外**。
const OBJ_SLOT_BY_ID_PREFIX := {"fest": "fest"}

## 程序化画出来的槽（没有对应 png，但**有**渲染器）。改这里要同步改 _draw() 里的 match。
const OBJ_SLOT_PROCEDURAL := {"bed": true, "stove": true, "dock": true, "fest": true}

# ══ H3-b · 别名预算（aliasing budget）——H1 真机眼验之后补的第二条判据 ═══════════════
#
# **上面那条判据不够，而它不够的方式正是本棒最容易自欺的那一种。**
# 我先写的是「advertises 的对象必须解析到一张真实存在的贴图」。H1 在真机上量完之后指出：
# `bench_brickpile` **解析成功**，`obj/bench.png` **真的存在** ⇒ 那条判据对着"砖垛像木凳"这个
# 派本棒的原始症状**恒绿**。病不是【退化】(degradation)，是【别名】(aliasing)：贴图不缺，是被反复借用。
#
# 两个口径都记下来，因为它们不一样，混用会得到不同的数字：
#   贴图        按【对象】数  按【不同 type】数
#   bench.png       5              5    长椅 · 清扫车 · 渔台 · 柴垛 · 砖垛
#   desk.png        3              2    工作台(desk_1) + 工作台(desk_workbench) + 讲台
#                                        —— **同一个 type 出现两次不是别名**，是两件同型号的家具
#   counter.png     3              3    吧台 · 面案 · 摊位   （本棒给「扩建咖啡馆」补表后 → 4）
# ⇒ H1 报的 "desk 服务 3 个" 按对象数为真、按 type 数是 2。本门取 **type** 口径：
#    两件同型号家具共用一张图是**对的**，把它算成病会得到一个没有判别力的数。
#
# 这道门**不是**"禁止别名"——那会在今天当场把 CI 焊红，而真正的修法是补美术，不在本棒的行里
# （docs/50 §一：**先眼验、再上门**；给没人看过的美术上门等于把现状钉成正确）。
# 它是**棘轮**：把今天量到的数钉进代码，**再多一个就红**。
#   · G3 当初给 bench 添第 5 个 type（砖垛）会当场变红 —— 实测把预算改回 4 即复现（回执 M7）。
#   · 下一根想借 bench 的棒必须**手动把 5 改成 6**，那一行会出现在 diff 里、必须有人签字。
#     「借用」从此是一次显式决定，而不是一次没人注意的字符串巧合。
# ⚠️ 它**不会**告诉你现存的 5 个借用哪一个读得出、哪一个读不出——那件事只有人眼能做（H1）。
const OBJ_SLOT_ALIAS_BUDGET := {"bench": 5, "counter": 4, "desk": 2}

var _slot_shouted := {}       # 已经吼过的坏 key（type|前缀）→ 每个只吼一次，不随 tick 刷屏
var _slot_probe_n := -1       # 上次体检时 world["objects"] 的规模（civic_/fest_ 是运行期 spawn 的，所以要跟着变）
var _slot_declared_done := false

## 对象 → 精灵槽。返回 "" = **无人认领**（调用方必须走醒目占位，不许静默兜底）。
func _obj_slot(id: String, o: Dictionary) -> String:
	var t := String(o.get("type", ""))
	if OBJ_SLOT_BY_TYPE.has(t):
		return String(OBJ_SLOT_BY_TYPE[t])
	var pre := id.split("_")[0]
	if OBJ_SLOT_BY_ID_PREFIX.has(pre):
		return String(OBJ_SLOT_BY_ID_PREFIX[pre])
	return ""

## 这个槽真的画得出东西吗？程序化分支算数；否则必须有一张**真实存在的**贴图。
## 判据用 `Art.object_tex()` 本身而不是 `FileAccess.file_exists`——门要和渲染器问同一个问题，
## 否则会出现"文件在、但导入失败/解不出 Texture2D，门绿而屏幕上是空的"。
## 实测：`--headless` 下 `Art.object_tex("bench")=true / ("nosuchslot")=false`，这道门在无渲染环境里照样有判别力。
func _slot_has_renderer(slot: String) -> bool:
	if slot == "":
		return false
	if OBJ_SLOT_PROCEDURAL.has(slot):
		return true
	return Art.object_tex(slot) != null

## ── 断言：**任何 town 平面上 advertises 的对象，都必须解析出一个画得出东西的槽** ──────────
## 范围（写清楚，因为门的价值一半在它守不住的那一栏）：
##   · 只查 `space=="town"` —— 室内家具走 `_draw_interior_furniture`，那条路的 slot 是数据**显式**给的，
##     不经过本文件的 id 前缀，不是同一个缺陷（它自己的坑另记，见回执 does_not_detect）。
##   · 只查 `advertises` 非空 —— 纯装饰对象根本进不了 `world["objects"]`（Sim.gd:584 / :644 各一处 continue）。
## 返回坏对象个数。**push_error 而不是 assert**：assert 在 release 构建里是空的，而这条性质
## 恰恰要在出货构建里也成立；push_error 会被 `tools/ci.sh` 的 `scan` 抓成红（实测 `ERROR: <msg>` 两行）。
func verify_object_slots() -> int:
	var objs = Sim.world.get("objects", {})
	if not (objs is Dictionary):
		return 0                       # `_load_data()` 走完之前它是 authored 数组，此时还没有权威的 id→def
	var bad := 0
	for id in objs:
		var o = objs[id]
		if not (o is Dictionary):
			continue
		var od: Dictionary = o
		if String(od.get("space", "town")) != "town":
			continue
		if (od.get("advertises", []) as Array).is_empty():
			continue
		if _slot_has_renderer(_obj_slot(String(id), od)):
			continue
		bad += 1
		_shout_unmapped(String(id), String(od.get("type", "")), "world.objects")
	return bad

## 运行期才 spawn、但**在数据里已经声明**的那些（选举 WorldPatch / 节日机会地形）。
## 为什么单独查：docs/41 §2 第三个盲区——「一道门可以已经在 CI 里、已经是绿的，却跑在一个它
## 永远不可能变红的配置上」。本门在 CI 里唯一的 fixture 是 `player_touch_test` 里那个 **tick 0 的世界**，
## 而 `civic_*` 要到第 14 天、`fest_*` 要到第 3 天才存在 ⇒ 光查 `world["objects"]` 的话，
## 病史③那个真 bug **在 CI 里一次都不会被看见**。这一段把它们提前到开局就查掉。
## ⚠️ 它耦合了 Sim 的两处命名（`civic_` @Sim.gd:2802、`fest_` @Sim.gd:2753）。改名 ⇒ 这里失效，
##    但不会假绿到底：对象真的 spawn 出来时 `verify_object_slots()` / 绘制路径仍会吼。
func verify_declared_slots() -> int:
	var bad := 0
	var op = Sim.elections.get("on_pass", {})
	if op is Dictionary and (op as Dictionary).get("object", null) is Dictionary:
		bad += _check_declared((op as Dictionary)["object"], "civic", "elections.json on_pass.object")
	var fs = Sim.festivals.get("festivals", {})
	if fs is Dictionary:
		for nm in (fs as Dictionary):
			var f = (fs as Dictionary)[nm]
			if not (f is Dictionary):
				continue
			for od in ((f as Dictionary).get("objects", []) as Array):
				if od is Dictionary:
					bad += _check_declared(od, "fest", "festivals.json 节日「%s」" % str(nm))
	return bad

## ── 断言二：**一张贴图被几个不同 type 借用，不许超过预算**（见上面 OBJ_SLOT_ALIAS_BUDGET）──
## 判据只读 OBJ_SLOT_BY_TYPE 这张表 ⇒ 它是一条**静态**性质，与世界里当下有没有那个对象无关：
## 有人往表里加一行借用，第一次跑起来就红，不必等到那个对象真的被 spawn 出来。
func verify_slot_aliasing() -> int:
	var by_slot := {}
	for t in OBJ_SLOT_BY_TYPE:
		var s := String(OBJ_SLOT_BY_TYPE[t])
		if not by_slot.has(s):
			by_slot[s] = []
		(by_slot[s] as Array).append(String(t))
	var bad := 0
	var slots: Array = by_slot.keys()
	slots.sort()                       # 定序：报错文本不随字典遍历序抖动
	for s in slots:
		var types: Array = by_slot[s]
		var budget := int(OBJ_SLOT_ALIAS_BUDGET.get(s, 1))
		if types.size() <= budget:
			continue
		bad += 1
		var key := "ALIAS|" + String(s)
		if _slot_shouted.has(key):
			continue
		_slot_shouted[key] = true
		push_error(("[WorldView] 贴图别名超预算：'%s' 现在被 **%d** 个不同的 type 共用（预算 %d）：%s。" +
			"这不是「贴图缺失」，是「贴图被借用」——屏幕上这几样东西会长得一模一样。" +
			"要么给新的 type 画一张自己的图（assets/art/obj/<slot>.png），" +
			"要么**手动把 OBJ_SLOT_ALIAS_BUDGET['%s'] 改成 %d 并在 commit 里说明为什么这次借用可以接受**。") % [
			s, types.size(), budget, str(types), s, types.size()])
	return bad

func _check_declared(def: Dictionary, spawn_prefix: String, where: String) -> int:
	if (def.get("advertises", []) as Array).is_empty():
		return 0
	var slot := ""
	var t := String(def.get("type", ""))
	if OBJ_SLOT_BY_TYPE.has(t):
		slot = String(OBJ_SLOT_BY_TYPE[t])
	elif OBJ_SLOT_BY_ID_PREFIX.has(spawn_prefix):
		slot = String(OBJ_SLOT_BY_ID_PREFIX[spawn_prefix])
	if _slot_has_renderer(slot):
		return 0
	_shout_unmapped(spawn_prefix + "_*", t, where)
	return 1

## 同一个坏 key 只吼一次（key = type|前缀）：本函数会被逐 tick 的体检与逐帧的绘制两条路调用。
func _shout_unmapped(id_hint: String, type_name: String, where: String) -> void:
	var key := "%s|%s" % [type_name, id_hint.split("_")[0]]
	if _slot_shouted.has(key):
		return
	_slot_shouted[key] = true
	push_error(("[WorldView] 精灵槽无人认领：对象 '%s' 的 type='%s'（来自 %s）在 OBJ_SLOT_BY_TYPE / " +
		"OBJ_SLOT_BY_ID_PREFIX 里都没有条目，或者它指向的贴图不存在。" +
		"它会在地图上画成一个品红占位框、并把数据键印在草地上。" +
		"修法：往 WorldView.OBJ_SLOT_BY_TYPE 里加一行（借用已有贴图也算一个显式决定），或补一张 assets/art/obj/<slot>.png。") % [
		id_hint, type_name, where])

## 世界规模变了才重新体检（civic_/fest_ 是运行期 spawn 的；`_redraw_all` 逐 tick 调，不能在这里做 O(n) 全扫）。
func _slot_probe_tick() -> void:
	var objs = Sim.world.get("objects", {})
	var n: int = objs.size() if (objs is Dictionary or objs is Array) else -1
	if n == _slot_probe_n:
		return
	_slot_probe_n = n
	verify_object_slots()
	if not _slot_declared_done and (objs is Dictionary):
		_slot_declared_done = true          # 下面三条都是【静态】性质（只读表与资产），查一次就够
		verify_declared_slots()
		verify_slot_aliasing()
		verify_decor_pool()

## 无人认领的对象：**醒目**画法。旧版用 P_RES_FOOT（暖石灰，和墙同色）+ 11px 白字，
## 于是它在整帧里读起来像一件家具 —— F1 的四个工位就是这样活过一整波的。
## 现在：品红实心 + 黑叉 + 黑描边，几乎占满整格，字前面加 `?`。**它不是兜底，它是一块喊叫的补丁。**
func _draw_unmapped_object(base: Vector2, id: String, o: Dictionary) -> void:
	var r := Rect2(base.x + 4, base.y + 4, T - 8, T - 8)
	draw_rect(r, X_MISSING, true)
	# 黑叉：纯色块在缩略图/远景里仍可能被读成"一件红东西"，一个叉不会。两条对角线严格落在框内。
	draw_line(r.position, r.position + r.size, P_PANEL, 3.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), P_PANEL, 3.0)
	draw_rect(r, P_PANEL, false, 2.0)
	draw_string(Art.font(), Vector2(base.x + 4, base.y + T - 3),
		"?" + String(o.get("type", id)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, X_MISSING)
	_shout_unmapped(id, String(o.get("type", "")), "world.objects(绘制)")

func _draw_bed(base: Vector2) -> void:
	var x := base.x + 8.0
	var y := base.y + 5.0
	var w := float(T) - 16.0
	var h := float(T) - 8.0
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), X_WOOD_MID, true)        # 木框
	draw_rect(Rect2(x, y, w, h), P_TEXT, true)                        # 床单
	draw_rect(Rect2(x + 2, y + 2, w - 4, 9), X_COLD_WHITE, true)            # 枕头
	draw_rect(Rect2(x, y + 13, w, h - 13), X_SIGNAL_NEG, true)              # 被子
	draw_rect(Rect2(x, y + 13, w, 3), P_COM_ROOF, true)                   # 被沿
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), Color(0, 0, 0, 0.35), false, 1.5)

## 程序化像素灶台（顶视角）：炉体 + 灶面 + 火眼(一只点火) + 烤箱门。
func _draw_stove(base: Vector2) -> void:
	var x := base.x + 9.0
	var y := base.y + 9.0
	var w := float(T) - 18.0
	var h := float(T) - 16.0
	draw_rect(Rect2(x, y, w, h), P_WRK_ROOF, true)                        # 炉体
	draw_rect(Rect2(x + 2, y + 2, w - 4, h - 11), P_WRK_FOOT, true)       # 灶面
	draw_circle(Vector2(x + 8, y + 8), 3.5, P_PANEL)                   # 火眼1
	draw_circle(Vector2(x + w - 8, y + 8), 3.5, X_LIGHT_LAMP)               # 火眼2(点火)
	draw_circle(Vector2(x + w - 8, y + 8), 1.6, X_GOLD)
	draw_rect(Rect2(x + 3, y + h - 7, w - 6, 5), P_PANEL, true)        # 烤箱门
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.35), false, 1.5)

## P1-a 功能码头：木栈板、系缆桩、缆绳与卸货箭头。程序化槽不占贴图别名预算。
func _draw_dock(base: Vector2) -> void:
	var deck := Rect2(base.x + 4, base.y + 6, T - 8, T - 12)
	draw_rect(deck, X_WOOD_MID, true)
	for i in range(1, 5):
		var py := deck.position.y + float(i) * deck.size.y / 5.0
		draw_line(Vector2(deck.position.x, py), Vector2(deck.end.x, py), P_PANEL, 1.0)
	for bx in [deck.position.x + 4.0, deck.end.x - 4.0]:
		draw_circle(Vector2(bx, deck.position.y + 3.0), 2.5, P_PANEL)
		draw_line(Vector2(bx, deck.position.y + 3.0), Vector2(base.x + T * 0.5, base.y + T * 0.5), X_SIGNAL_POS, 1.5)
	var c := base + Vector2(T * 0.5, T * 0.5)
	draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), X_COLD_WHITE, 2.0)
	draw_line(c + Vector2(3, -4), c + Vector2(7, 0), X_COLD_WHITE, 2.0)
	draw_line(c + Vector2(3, 4), c + Vector2(7, 0), X_COLD_WHITE, 2.0)
	draw_rect(deck, Color(0, 0, 0, 0.35), false, 1.5)

## Wave 2b 节日灯笼（暖光晕 + 灯身 + 挑杆），一眼可辨"这里在办节日"。纯渲染。
func _draw_festival(base: Vector2) -> void:
	var c := base + Vector2(T * 0.5, T * 0.5)
	# 呼吸光晕（用 tick 相位做确定性明暗，不引 RNG）
	var pulse := 0.35 + 0.12 * sin(float(Sim.tick_no) * 0.15)
	draw_circle(c, T * 0.55, Color(X_LIGHT_WIN, pulse * 0.5))
	draw_circle(c, T * 0.34, Color(X_GLOW, pulse))
	# 挑杆
	draw_line(base + Vector2(T * 0.5, 2), c + Vector2(0, -T * 0.18), X_WOOD_MID, 2.0)
	# 灯身（红灯笼）
	var lw := T * 0.30
	var lh := T * 0.34
	draw_rect(Rect2(c.x - lw * 0.5, c.y - lh * 0.35, lw, lh), X_SIGNAL_NEG, true)
	draw_rect(Rect2(c.x - lw * 0.5, c.y - lh * 0.35, lw, lh), X_GLOW, false, 1.5)
	draw_line(Vector2(c.x, c.y + lh * 0.55), Vector2(c.x, c.y + lh * 0.78), X_GOLD, 2.0)  # 流苏
	draw_string(Art.font(), c + Vector2(-7, -lh * 0.55 - 4), "灯会", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, X_GLOW)

## at = 需求条的【上边中点】（由 _draw_agent 按落脚线给，不再是"格心 +30px"的硬编码）。
func _draw_urgent_need(at: Vector2, ag: Dictionary) -> void:
	var worst := 100.0
	var worst_id := ""
	for nid in ag["needs"]:
		var v := float(ag["needs"][nid])
		if v < worst:
			worst = v
			worst_id = nid
	if worst_id == "":
		return
	var bar := Rect2(at.x - 16, at.y, 32, 4)
	draw_rect(bar, Color(0, 0, 0, 0.5), true)
	var frac := clampf(worst / 100.0, 0.0, 1.0)
	var c := X_SIGNAL_POS if worst > 35.0 else X_SIGNAL_NEG
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), c, true)

func _in_conflict(id: String) -> bool:
	return _rc_conflict_ids.has(id)   # 集在 _draw 每帧预建（语义同旧的线性扫，O(1) 查）

func _has_meet(id: String) -> bool:
	return _rc_meet_ids.has(id)
