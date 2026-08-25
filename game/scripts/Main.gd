extends Node2D
## Main.gd — 入口/屏幕管理器（范式同《小鱼岛》Main.gd）。
## 解析 CLI（--backend / --seed / --speed），启动 Sim，挂上 WorldView 渲染与 HUD（状态 + 滚动事件日志 + 图例）。

var _view: Node2D
var _probe: Node                      # ProbeController：拥有 Camera2D + 观察状态（纯 View，不写 Sim）
var _locked_ortho_c1: Node2D          # optional C1 projection; no Sim authority or input ownership
var _sg: RefCounted                   # SpaceGraph：Space/Floor/Portal 合同（纯数据查询；兼容期 town/outdoor 兜底）
var _modulate: CanvasModulate
var _status: RichTextLabel
var _logbox: RichTextLabel
# 播报分两栏（docs/B2 小镇编年史）：置顶「大事」= 高显著度事件（背叛/盟约/选举/冲突…），
# 「近况」= 时间序尾巴。一天里一半事件是打招呼，单一滚动条会把一次背叛在三秒内挤出屏幕。
var _log_hot: Array = []               # 置顶大事（按发生序，保留最后 LOG_HOT_CAP 条）
var _log_recent: Array = []            # 近况尾巴（含系统提示：存读档/后端切换…）
const LOG_HOT_CAP := 4
## 6 → 5：给「小镇纪事」那一行腾出位置，**不动播报框的几何**。
## 播报框是 548×236 @ 字号 15（行高约 20px ⇒ 约 11.8 行可见），而改动前的上限已经是
## 4 条大事 + 2 条分隔 + 6 条近况 = 12 行，本来就压着边。加一行标题而不减一行近况会把最老的一条静默裁掉
## （RichTextLabel 的 scroll_active=false 不报错、只是看不见）⇒ 这是刻意的等行数交换。
const LOG_RECENT_CAP := 5
const FEED_RESCAN := 200               # 回放/读档后从 event_log 尾部回扫多少条来重建播报

# ── 小镇纪事（单局形状 / 社会成就；docs/46 §二-D2）─────────────────────────
## ★红线：`Goals` 是**对 Sim.event_log 的只读派生**，与 ProbeController 同一纪律 —— 绝不写世界状态。
##   Main 这一侧的义务只有两条：①每 tick 把 event_log 喂给它（`_sync_goals`）；
##   ②时间线一换就整份重算（`_rebuild_feed`，与播报共用同一个入口）。
##   机器证明在 scenes/goals_test.tscn。
var _goals: RefCounted                 # Goals.gd 实例
var _goals_pan: TextureRect            # 展开档面板（默认【隐藏】：docs/46 §一 #5 已经在说 chrome 太多）；羽化 scrim，见 _mk_scrim
var _goals_box: RichTextLabel
var _goals_open := false
var _goals_line := ""                  # 缓存的一行摘要：只有它变了才重画播报（免每 tick join 一次）

# ── 小镇故事（因果弧；docs/47 §二-E2）────────────────────────────────────────
## ★红线同上：`Story` 也是**对 Sim.event_log 的只读派生**。Main 这一侧的义务与 Goals 逐字相同：
##   ①每 tick 喂一次 event_log（`_sync_story`）；②时间线一换就整份重算（`_rebuild_feed`）。
##   机器证明在 scenes/story_test.tscn（含 4 组合成对照 —— 光有 live==replay 没有判别力，D2 已实测）。
## 它与「小镇纪事」的分工：纪事回答**还差几件**（有进度、无主角、永不结束），
##   故事回答**发生了什么**（有开头、有几幕、有一个结局，且系在两个具体的人身上）。
var _story: RefCounted                 # Story.gd 实例
var _story_pan: TextureRect            # 展开档面板（默认隐藏；K 键 / 点播报里 ◇ 那一行）
var _story_box: RichTextLabel
var _story_open := false
var _story_rev := -1                   # 已排进面板的 Story.rev（脏标记缓存；见 _sync_story_panel）
# 相机/观察状态已全部搬进 ProbeController（P0-b）：Main 只做装配 + HUD/时间轴输入仲裁。

# ── 观察台 / 回放 ──────────────────────────────────────────────────────────
var _obs: RichTextLabel               # 右侧角色明细面板
var _obs_expanded := false            # 观察台档位：false=名片档（人设+当下+需求），true=完整卷宗
var _obs_fit_frames := 0              # --obs-fit：还差几帧开跑 W8 装得下断言（0 = 不跑）
var _obs_btn: Button                  # 「详情 / 收起」——手机上唯一够得着的入口（V 键是桌面同款）
var _scrub_track: ColorRect           # 时间轴底槽
var _scrub_fill: ColorRect            # 已播放进度
var _scrub_handle: ColorRect          # 拖动手柄
var _selected_id := ""                # 当前观察的角色
var _player_mode := false             # --player：玩家入镇（gameplay M1）
var _demo_mode := false               # --player-demo：脚本化玩家 autopilot（录 demo）
var _player_spawn_override := Vector2i(-1, -1) # --player-pos x y：产品截图/玩法验收把玩家放到被测纵切；默认仍是广场
var _demo_steps: Array = []           # [{type:walk_to|select|act|chat|wait, ...}] 顺序执行
var _demo_i := 0
var _chat_in: LineEdit                # 玩家→NPC 对话输入框
var _chat_generation := 0             # 世界/会话替换使在飞回调失效
var _chat_session_id := 0             # world/load session identity, distinct from request generation
var _backend_btn: Button              # 后端切换按钮（手机无 CLI：点按在 logic/slm/… 间轮换；桌面也可点）
# ── 演示镜头编排（--demo-cam；docs/46 §三-D4）──────────────────────────────
## 轨迹本体在 ProbeController（连同"为什么框地方不框人"的理由）。Main 这一侧只有三件事：
##   ①每 tick 把 tick 号交给它；②按它给的取景**决定选中谁**（View 状态，不进仿真）；③可选地写一份轨迹 trace。
## ★红线：这条路对 Sim **只读**。它不喂 lod_focus、不写任何世界状态——
##   「相机可以决定画什么，绝不能决定仿真什么」（本文件 :159 的那条），演示镜头不是它的例外。
const WorldViewScript = preload("res://scripts/WorldView.gd")   # 只为取 LABEL_MIN_ZOOM：名牌门的阈值**读原件**，不抄第二份
var _demo_cam := false                # --demo-cam：确定性演示相机轨迹（录屏用；关闭时逐像素与改动前相同）
var _demo_trace: FileAccess           # --demo-cam-trace <abs.txt>：每 tick 一行 (tick|shot|u|zoom|x|y|labels|sel)。
                                      # 用途=确定性硬证据：同参数两跑的 trace 必须**逐字节相同**，
                                      # 而这一点在"录屏抽同一秒的帧做 diff"上是**拿不到**的——见 docs/46 §三-D4 回执。
## 取景框判定用【真视口矩形】而不是一个圆：圆的半径要么套不住宽屏的左右，要么越过上下边。
## 而且是**施密特触发**——进场比留场严：
##   选人时要求他离画面边缘还有 DEMO_IN_MARGIN 的余量（别一选中就走出去），
##   留人时只要求还在画面里（DEMO_KEEP_MARGIN）。两个阈值相等的话，站在边界上的人会逐 tick 进出。
## 进场余量从 110 提到 150 是**换来的**，不是拍的：安全框（见 _demo_box）比整个视口小，
## 人更快走出去 ⇒ 换人从 47 次涨到 62 次、中位停留掉到 20 tick（≈0.6s @speed3，卷宗还没读完就换人）。
## 进场压到 150（选人时要求他离框边更远 ⇒ 他能待更久）：换人 51 次、中位 31 tick、p25 19，
## 代价是观察台有人的时长 68.3%→63.8%（候选更少，偶尔一个都不合格）。12 位居民仍全部出场。
const DEMO_IN_MARGIN := 150.0         # 进场余量(屏幕 px)
const DEMO_KEEP_MARGIN := 10.0        # 留场余量(屏幕 px)
const DEMO_SEL_HOLD := 130            # 换人节奏(tick)：约 3.5 秒 @ --speed 3
var _demo_sel_hold := 0               # 当前选中已保持的 tick 数（迟滞计数）
## ★"选谁"这条规则被改了三次，每一次都是被【量出来的抖动】推翻的，记在这里免得下一个人再走一遍：
##   ① 离镜头最近的那个            → 2380 tick 的循环里换人 **196 次**，中位停留 6 tick（观察台像跑马灯）
##   ② 距离量化到 2 格 + 社交加分  → **171 次**，中位仍是 6。不稳定的根本不是精度：
##      画面里的 4-6 个人每走一步就互换名次，"正在社交"这个加分项还每隔几 tick 亮灭一次。
##   ③ 会合哈希(HRW)，键=⌊tick/HOLD⌋ → **119 次**，中位 8。仍然churn，因为候选集合本身在变：
##      人不断跨过取景半径的边界进出。
##   ④ **迟滞 + HRW（现行）**：选中的人只要还在画面里就留着，最多 HOLD tick 再换。
##      这一步引入了【状态】，但状态**每 tick 恰好推进一步、不吃帧 delta** ⇒ 录屏仍然逐字节可复现
##      （证据：--speed 8 与 --speed 30 两跑 trace 在 2400 行公共前缀上 0 行不同）。
##      代价写清楚：`--shot --warmup-tick T` 复现的是**取景**，选中的人则是在 T 处重新起算的
##      （goto_tick 暖机发生在信号接线之前，迟滞状态重放不出来）——所以静帧与录屏可能选中不同的人。
##   哈希用项目自有的 `Sim.fnv1a32`（红线 #1：不得用引擎内建 String.hash()）。
var _shot_path := ""                  # --shot <abs.png>：渲一帧存图退出（dev 验证/出图；需真 framebuffer=Xvfb 或带窗口，纯 --headless 得空图）
var _shot_fit := false                # --shot-fit：出图整镇入画（否则用跟随相机的角色特写，供 find_betray/endorse 眼验）
var _digest_at := -1                  # --digest-at <tick>：跑到该 tick 时【自动】写 digest 并退出。
                                      # 为何不靠数按键：注入 40 次单步里丢 1 次，两跑就差 1 tick，
                                      # 于是比的是"按键可靠性"而非"相机是否影响历史"（第一版就这么假 FAIL 了）。
                                      # 定 tick 写盘 → 两跑必然在【同一 tick】比较，多按几次也无所谓。
var _digest_out := ""                 # --digest-out <abs.txt>：按 F9 把 (tick, digest, event_digest) 写盘。
                                      # 用途=Probe 观察者无关性【硬门】：同 seed、同步进步数，一次不碰相机、一次狂拖狂缩，
                                      # 两边 digest 必须逐字节相同。截图差分证明不了这件事（analysis §11 的正确批评）。
const Inv = preload("res://bench/Invariants.gd")
var _settings_panel: ColorRect        # ⚙ 设置面板（NPC 数量/速度/后端；⚙ 按钮或 O 键开关）
var _npc_val: Label                   # 设置面板里的 NPC 数量数字
var _npc_target := 6                  # 当前目标 NPC 数（改动→同种子重开 sim）
var _seed := 0                        # 记住开局种子，供设置里"改 NPC 数重开"复用
# ── dev 性能 overlay（类 RTSS：FPS/内存/绘制/对象/NPC/tick 率/LLM stats）──
var _perf: RichTextLabel              # 左上角实时资源监控（F3 或设置里开关）
var _perf_on := false
var _perf_dt_acc := 0.0               # 采样窗口累计秒
var _perf_last_tick := 0             # 上个采样窗口的 tick_no（算 tick/s）
var _perf_rate := 0.0                 # 平滑后的 sim tick/s
var _model_btn: Button                # 设置面板里的 SLM 模型选择钮（循环手选 gguf）
var _models: Array = []               # 扫到的 *.gguf 绝对路径列表
var _model_idx := 0
var _max_tick := 0                    # 见过的最大 tick（scrub 范围上限）
var _scrubbing := false
const SCRUB_X0 := 584.0
const SCRUB_X1 := 1268.0
const SCRUB_Y := 724.0
const SCRUB_H := 16.0
## 键位提示行的字号与它那块底板的几何（T3：**HUD 可读性的地板就在这一行**）。
## 改前 = 字号 **12**、底板 `_mk_panel` 的黑 0.42、正文框高 18。三样一起构成全 HUD 最差的一格：
##   实测（`--warmup-tick 600`，提示行右半正压在亮草地上）：**WCAG 对比度 4.24**，低于 AA 的 4.5；
##   同一行在暗背景上是 8.7–9.1 ⇒ **它的可读性完全取决于底下恰好是什么**，而那是相机决定的。
## 底板不透明度照抄顶栏那一档（0.02/0.03/0.05 @0.74）——顶栏当初就是被同一个病（浅墙透上来）逼出来的，
## 那里已经算过账：0.42 之下浅墙 (216,189,147) 仍有 43.7% 亮度，0.74 之下只剩 22.6%。
## 字号 12→14 ⇒ 引擎实测行高 17→20（Smiley Sans Oblique，`get_height`），正文框跟着 18→22、
## 顶沿上抬 2px 塞进多出来的那 4px 行高。**底板的几何一个像素都没动**——
## 它的上沿 698 与观察台【完整卷宗档】的正文下沿 706 本来就叠 8px（收起档不叠，故出货帧看不见），
## 把底板抬高会把这个既有的叠加变成 12px，而卷宗此刻的最坏余量只有 +11px。**别为了 4px 去动它。**
const SCRUB_HINT_FS := 14             # **上限**，不是定值：真正用哪一档由 _fit_hint_fs 量出来
const SCRUB_HINT_FS_MIN := 12         # 退到这一档还装不下就认了（宁可小，也不要静默折行被裁）
const SCRUB_HINT_DY := 24.0           # 提示行顶 = SCRUB_Y - 这个（改前 22）
const SCRUB_HINT_H := 22.0            # 提示行框高（改前 18；字号 14 的引擎行高是 20）
const SCRUB_HINT_W := 700.0           # 提示行框宽（= 底板 576..1276 的 700px；改前是写在两处的裸字面量）
const SCRUB_PAN_DY := 26.0            # 底板顶 = SCRUB_Y - 这个（**与改前逐字相同**）
const SCRUB_PAN_H := SCRUB_H + 34.0   # 底板高（**与改前逐字相同**）
var _scrub_pending := -1              # 待应用的 scrub 目标 tick；每帧至多 flush 一次（见 _flush_scrub）

# ── B15 视口自适应 ────────────────────────────────────────────────────────
# project.godot 的 window/stretch/aspect 从 "keep" 改成 "expand"。
#   keep：按设计比 1280x768(=1.67:1) 等比缩放后【左右打黑边】。真机 Redmagic 8 Elite 是 2688x1216(=2.21:1)，
#         实测渲染区只有 2026x1216 —— 屏幕两侧共 662px（24.6%）是纯黑，白扔掉四分之一块屏。
#   expand：同样等比缩放（scale=min(w/1280,h/768)），但把多出来的那一维【补进设计空间】而不是补黑边。
#         2688x1216 → get_viewport_rect() 实测 1697x768（算出来是 1698.0，引擎取整到 1697；
#         别照抄纸上算的那个数——本文件一律用运行时 vp，不写死）。原点仍在左上，多出来的宽全在右边。
# 代价正是此前把这件事一直押后的理由：本文件的 HUD 全是对 1280x768 的绝对坐标，
# 多出来的 417 会变成右侧一条【没有任何 HUD】的空带（后端钮孤零零悬在半空、时间轴右端早早断掉）。
# 故所有 HUD 元素改为按 (dx, dy) = 视口 − 设计基准 重新定位（见 _relayout_hud）。
# ★硬约束：dx=dy=0（桌面/CI 的 1280x768）时每个元素都必须回到与改动前【逐像素相同】的几何，
#   所以下面一律写成「基准常量 + 增量」，绝不改写基准本身。
const DESIGN := Vector2(1280.0, 768.0)

# 需要跟随视口的 HUD 节点（⚙ 钮、性能 overlay 锚在左上角，天然不用动，故不记引用）
var _log_pan: TextureRect             # 左下播报底板（跟底边）——羽化 scrim，见 _mk_scrim
var _obs_pan: TextureRect             # 右侧观察台底板（跟右边，高度跟底边）——羽化 scrim
var _scrub_pan: ColorRect             # 时间轴底板（跟底边 + 右边）
var _scrub_hint: RichTextLabel        # 时间轴提示行
var _status_pan: ColorRect            # 顶栏底板（跟右边；宽度=整屏，见 _build_hud 里的注释）
var _act_pan: ColorRect               # 玩家动作条底板（跟底边；仅玩家模式可见）
var _act_btns: Array = []             # 7 个动词按钮（顺序 = PLAYER_VERBS）
var _player_btn: Button               # 设置面板里的「玩家模式」开关

# ── 玩家动词（触屏动作条 ≡ 物理键，同一条 _player_do 路径）──────────────────
# ★这张表是【单一真源】：键位分发(_unhandled_input)、动作条按钮(_build_action_bar)、
#   状态栏第二行提示(_update_status) 全部由它生成 —— 三处各写一份就一定会漂。
const PLAYER_VERBS := [
	{"verb": "greet",     "label": "招呼", "key": "G"},
	{"verb": "give",      "label": "送礼", "key": "F"},
	{"verb": "gossip",    "label": "八卦", "key": "B"},
	{"verb": "invite",    "label": "约见", "key": "Y"},
	{"verb": "confront",  "label": "理论", "key": "T"},
	{"verb": "apologize", "label": "道歉", "key": "P"},
	{"verb": "mediate",   "label": "调解", "key": "M"},
]
const ACT_X := 584.0                  # 动作条左端（与聊天框对齐）
const ACT_Y := 606.0                  # 动作条顶（聊天框 y=648 之上，留 11px 间隙）
const ACT_BW := 52.0
const ACT_BH := 34.0
const ACT_STEP := 54.0
# 顶栏高度：玩家模式下状态栏是【两行】（第二行是 7 个动词的键位）。
# 改动前 _status.size.y 恒为 28 → 第二行被 Control 裁掉，实测只剩字形顶端 ~6px，整行不可读。
const STATUS_H1 := 28.0
const STATUS_H2 := 52.0

# ── HUD scrim 版式（C8）─────────────────────────────────────────────────────
# 硬边矩形贴在世界上会切出一条【直线】。实测（未改动的树，--warmup-tick 600 --shot-fit）：
#   编年史右边 x=568 相邻像素亮度跃变 中位 65.8 / 最大 94.3；上边 y=470 中位 65.8 / 最大 131.1；
#   观察台左边 x=978 中位 65.8 / 最大 141.0（跟随相机那一帧上三条边都在 57-71）。
# 这正是 C7 在世界层量到的同一种病（docs/41 §6：等距连续的硬边比它想藏起来的东西更刺眼），
# 只不过 C7 那条边在地图边界上、这三条在 HUD 边界上。解法同样是【把边界抹掉】而不是换个颜色：
#   ① 能贴屏幕边的就贴到边（左/下/右各自到 0 或 DESIGN）——贴边的那一侧根本不存在接缝；
#   ② 够不着屏幕边的那一两条边用 alpha 斜坡羽化（_mk_scrim）。
# 底色用 C3 已经量过的那一档 (0.02,0.03,0.05)：0.42 黑压不住浅墙（0.58×(216,189,147) 仍有 43.7% 亮度），
# 0.74+ 档只剩 ~22%。这里取 0.84 —— 编年史正文是全屏第二密的文字，且在跟随相机下整片背景都是亮草地。
const SCRIM_COL := Color(0.02, 0.03, 0.05, 0.84)
const SCRIM_TEX := 64                 # scrim 纹理边长（靠 TEXTURE_FILTER_LINEAR 拉伸成平滑斜坡；1 个 draw call）
# 编年史 scrim：贴住屏幕【左下角】，只羽化右边与上边。
const LOG_SCRIM_TOP := 414.0          # 上边（羽化到 y=470 才满不透明，正文从 476 起 ⇒ 第一行已在满档上）
const LOG_SCRIM_W := 576.0            # 右缘（正文框 548 宽 + 边距；核心满档到 400，之后 176px 斜坡到 0）
const LOG_CORE_R := 400.0
# 观察台：右缘贴屏幕右边（DESIGN.x）⇒ 右侧无接缝；只羽化左边与下边。
# ★两档而不是一个开关：名片档保住"随时看得见这个人是谁/在干嘛/缺什么"，
#   完整卷宗（关系/记忆/派系/观点/信念）退到【一次交互】之外，而不是被删掉。
const OBS_TOP := 36.0
const OBS_PAD := 6.0                  # 正文相对面板的上内边距 —— 刻意仍是 6（正文 y=42，与改动前逐像素同位）。
                                      # ★第一版把「详情」钮做成面板自己的标题行（30px），实测立刻出事：
                                      #   完整卷宗正文实测 653px，而改前可用 664px —— 只剩 11px 余量，
                                      #   一个标题行就把正文推到 y=719，压进时间轴面板底下（那块是后加的，画在观察台之上）。
                                      #   是 player_touch_test 的 get_content_height() 断言抓住的，肉眼绝对看不出来。
                                      #   ⇒ 钮改放【顶栏】里、后端钮左边：同样在屏幕右上角、正对着它控制的面板，
                                      #   但不吃观察台一个像素，于是展开档的可用高度与改动前实质相同（662 vs 664）。
# 两档的尺寸都是【量出来的】不是估的：player_touch_test.gd 用 RichTextLabel.get_content_height()
# 对同一 fixture 比正文高度与可用高度。第一版 (232,300) 实测正文 293px / 可用 262px —— 溢出，
# 而且 240 宽正好让人物简介那一行不再折行（少一行 19.5px）：**宽一点反而矮得多**。
## 名片档：屏宽 18.75% / 屏面积 **8.89%**（本棒之前 8.30%，更早的调试密度档是 20.22%）。
## ⚠️ **高度 340 → 364 是被 CI 逼出来的，不是我顺手放大的**，而这一条正是"冻结字面量成对失效"的现场：
##   字号 14→15 时我同步把 `OBS_LINE_H` 18→19，**却没有意识到 340 这个数也是按 18 标定的**。
##   后果不是溢出——`get_content_height()` 实测 290px / 可用 328px，**真内容其实装得下**——
##   而是 `_obs_fit_lines()` 自己的**估算**撞上了它保留的 2 行余量（328 − 2×19 = 290），
##   于是它把最后一行"关系·冲突·记忆·观点·信念 / → 点右上「详情」（或 V）"**换成了"…还有 N 行没排下"**。
##   ⇒ 名片档从此不再告诉玩家详情在哪里，而手机上那句话是「完整卷宗」**唯一的**入口提示。
##   抓住它的是 `player_touch_test` 的「名片档指出详情在哪」这一条断言（`tools/ci.sh` 第 5 步）。
##   **`--obs-fit` 抓不到它**：那条只量【完整卷宗档】，名片档不在它的采集里。
## 两档的尺寸都是【量出来的】不是估的（见上一段注释里 player_touch_test 的做法）。
const OBS_CARD := Vector2(240.0, 364.0)
const OBS_FULL := Vector2(302.0, 676.0)   # 完整卷宗：左缘 x=978，与改动前同位（宽多出的 8 是贴边补的）
const OBS_FEATH := 40.0                   # 观察台 scrim 的羽化带宽（设计 px，**绝对值**）。
                                          # ★两条实测教训都在这一个常量上：
                                          #   ① 羽化带必须落在【正文矩形之外】——第一版让斜坡压在正文左侧与下侧，
                                          #      名片档最后两行（恰恰是那两行在指路"完整卷宗在哪"）直接糊在草地上；
                                          #   ② 羽化宽度不能写成"占面板边长的比例"——同一张纹理被两档共用，
                                          #      比例式会让名片档(340 高)的下斜坡只有卷宗档(676 高)的一半，两档不可能同时对。
                                          # 40px 把 ~65 的边界跃变摊成 ~1.6/px，低于像素画本身的噪声地板。
const OBS_BTN_W := 62.0                   # 「详情/收起」钮（顶栏内，后端钮左边）
const OBS_BTN_X := 1140.0 - 6.0 - OBS_BTN_W
const STATUS_W := OBS_BTN_X - 52.0 - 6.0  # 状态栏文本宽：从 ⚙ 钮右边到「详情」钮左边（改前 1082 → 1014）。
                                          # 实测状态栏那一行在 NPC 12 时只用掉约 690px，玩家模式第二行约 640px ⇒ 余量充足。
# 时间轴运行时几何：常量是 1280x768 设计基准，实际值由 _relayout_hud 加宽/下移。
# 命中测试(_in_scrub)、x→tick 换算(_tick_at_x)、绘制(_update_scrubber/_preview_scrub)
# 必须吃【同一套】运行时值 —— 否则手指按在槽上、goto_tick 却按老坐标算，会整体错开 dx。
var _sx0 := SCRUB_X0
var _sx1 := SCRUB_X1
var _sy := SCRUB_Y

## 事件显著度（纯视图评分——**不**调 Sim._impt：那个吃 agent 字典、属于仿真侧，视图不该碰）。
## >= SALIENT_MIN 进置顶「大事」区，其余只落「近况」尾巴。
const SALIENCE := {
	"betray": 100, "pact": 88, "election": 86, "conflict": 80, "rally_oust": 76,
	"leak": 74, "confront": 70, "apologize": 66, "mediate": 64, "aid": 62,
	"meet": 58, "confide": 56,
	"endorse": 44, "gossip_rep": 40, "discuss": 34, "gossip": 30, "invite": 28, "give": 20, "greet": 10,
	# E1 的四类产出事件。**今天这四行是不生效的**（FEED_SKIP 在算分之前就把它们挡了），
	# 写在这里是为了让"以后谁把 shortage 从 FEED_SKIP 移出去"这一步是安全的：
	# 不写的话它们会落到 `SALIENCE.get(t, 60)` 的兜底 60 上 —— 而 SALIENT_MIN=55，
	# 于是 produce/consume/spoil 会**和背叛、盟约、选举挤在同一块「镇上的大事」里**。
	# 60 天单 seed 实测（本棒自己数的，seeds 1/2/3）：produce 44/33/45 · consume 180/133/161 ·
	# spoil 42/24/45 · shortage 35/90/56 —— 不是转述里的 470/1915/463（差一个数量级，见报告）。
	"shortage": 72, "produce": 12, "consume": 4, "spoil": 4,
	# E1 车道 E1：进口到港。同 produce/consume/spoil ——ledger 事件、不 emit social_event ⇒ 也在 FEED_SKIP 里
	# （不写这行的话，一 scrub/读档就会冒出 "port_dock 交了一批货进镇上"，正是 _nm 兜底要消灭的英文 id）。
	"import": 8,
}
const SALIENT_MIN := 55
## 不进社交播报的类型。**判据不是"重不重要"，是"Sim 侧 emit 不 emit social_event"。**
## 这条规矩是构造性的：播报有两条入口 —— 实时靠 `social_event` 信号（`_on_social`→`_push_event`），
## 换时间线后靠 `_rebuild_feed` 回扫 event_log 尾部 200 条。两条都只按 FEED_SKIP 过滤。
## 于是【不 emit 但也不 skip】的类型 = 实时看不见、一 scrub/读档/`--warmup` 就冒出来一片
##   ⇒ **同一个 tick 的编年史内容变成"你怎么走到这里"的函数**。那是本项目最不能有的形状。
##
## ★E1（Wave E 产出闭环）新加的四类全部落在这里，逐条核过 `game/scripts/Sim.gd`（不是照抄转述）：
##   `_stock_move`(produce/consume/spoil) 与 `_shortage_fallout`(shortage) **四条路一条都不 emit social_event**。
##   另外两条各自独立的理由：
##   · produce 的 target 是 "town"、consume/spoil 的 actor **和** target 都是 "town"，
##     而 `_nm()` 查不到 agent 时**原样返回 id** ⇒ 走通用兜底成文会在屏幕上打出英文 "town"
##     （"阿林 对 town 交了一批货进镇上"）——正是 `_nm_opt` 注释里点名要消灭的那件事。
##   · shortage 确实是四条里唯一有戏的一条（actor=扑空的人、target=被怪的岗位、accepted=false、带旁观者），
##     但它同样不 emit ⇒ 放进播报只会造出上面那个"看路径的编年史"。**它改从故事层出面**：
##     Story.gd 的 grudge 弧收了一幕 `empty`（shortage 的 actor→target 与怨气弧的有向键同序），
##     那条路是对 event_log 的折叠，live 与 replay 按构造同值。
##   ⇒ 想让 shortage 直接进播报，正确的改法是在 `Sim._shortage_fallout` 末尾加一行
##     `emit_signal("social_event", ...)`（Sim.gd 归 E1，不在本棒的文件里），然后把它从本表移出去。
const FEED_SKIP := ["pay", "world", "produce", "consume", "spoil", "shortage", "import", "export"]
const TOPIC_LABEL := {"cafe_expand": "扩建咖啡馆", "night_market": "办夜市", "old_tales": "老故事"}
## ⚠️ **这个常数在 W8 里被判定为坏量具，现已降级为"长尾额度的下限兜底"，不再是版式预算。**
## 它数的是**逻辑行**，而 RichTextLabel(`scroll_active=false`) 截的是**视觉行**，中文还会折行 ——
## 实测（未修的树 · `--obs-fit --agents 60 --player --warmup 30`）：可用 **664px**、最坏内容 **853px**，
## **60/61 个居民**的卷宗被面板下沿静默切掉（12 居民 · 第 5 天就已经是 5/12 · 最坏 799px）。
## ⇒ 版式预算改由 `_obs_fit_lines()` 按**量出来的**像素高度算，见那里。
const OBS_MAX_LINES := 34
## 观察台正文字号（T3：14 → 15）。它是 HUD 上**最密的一块**，改前实测：墨迹高 13-14px、
## **笔画游程众数 1px**、行距 18px。1px 的笔画意味着任何一次降采样都会整根丢掉笔画
## （`tools/make_gif.sh` 抬头那张五行表量到的正是这件事），而这块又恰好是"这是工具不是游戏"的最大来源。
## ⚠️ **这个数不能单独改**：`OBS_LINE_H` 是按它标定的版式预算，两者必须一起动（见下一条）。
const OBS_FS := 15
## 观察台的行距预算。**14→15 的同时 18→19，两个数是一对。**
## 来源不再是"出图上 13 个行距 = 234px"那次（那是 STORY 面板、字号 14 的读数），
## 而是本棒在真引擎帧上逐块量出来的**渲染行距**：字号 14 → 18px、字号 15 → 19px
## （feed 字号 15 实测同为 19px，两处互证）。经验式是 **pitch ≈ font_size + 4**，
## 与 `Font.get_height()` 给的 20/22 **不同** —— RichTextLabel 按每行实际字形的升降部排版，
## 比字体的全局行高紧。**照 `get_height()` 去做版式预算会高估约 15%。**
## ⚠️ 这是一个**冻结字面量**（docs/75 §四点名的那一族）：它只在 1280×768 + Smiley Sans 上量过。
const OBS_LINE_H := 19.0

## 小镇纪事展开档面板：左上角，顶栏之下、播报 scrim 之上（LOG_SCRIM_TOP=414 ⇒ 底边 322 留 92px 余量）。
## 行数预算：11 条目标各 1 行 + 标题 + "下一步"的提示行 + 页脚 = 14 行 × 约 18px(字号 14) ≈ 252px。
## 它不进 _relayout_hud：锚在左上角 ⇒ dx/dy（更宽/更方的屏幕多出来的那部分）按定义影响不到它。
const GOALS_X := 10.0
const GOALS_Y := 42.0
const GOALS_SZ := Vector2(344.0, 280.0)
const GOALS_FEATH := 40.0                 # 展开档 scrim 的羽化带宽（绝对 px，同 OBS_FEATH 的理由）；只用于右/下两边

## 小镇故事展开档面板：与「小镇纪事」**共用左上角这一个槽位，且互斥**（开一个自动关另一个）。
## 为什么不是各占一块：docs/46 §一 #5 记着"25.5% 的屏幕已经是 chrome"，两块常驻元层面板会把这个数字再抬一截；
## 而这两块本来就是同一类东西（都是对 event_log 的只读派生、都默认收起、都只在玩家主动问的时候出现）。
## 互斥换来的是**零新增屏幕占用**，代价是不能并排对读 —— 这个代价是明知的，写在这里免得后人当 bug 修。
## 几何：底边 42+332=374，加 40px 羽化正好落在 LOG_SCRIM_TOP=414 上 ⇒ 与播报底板**不叠**（两层 scrim 叠加会双倍压暗）。
## 宽 470 而不是纪事的 344：故事是**成句的中文**，344px @ 字号14 只有约 24 个字，一句结局就要折行 ——
## 而折行会吃掉行数预算，正是 D2 那条"scroll_active=false 只会静默裁掉尾巴"的教训的触发条件。
const STORY_X := 10.0
const STORY_Y := 42.0
const STORY_SZ := Vector2(470.0, 332.0)
const STORY_FEATH := 40.0
## 行数预算：实测出图（after_story_t6300.png）标题基线 y≈57、末行 y≈291 ⇒ 13 个行距 234px ⇒ **行高 18px**。
## 正文可用高 332−12=320px ⇒ 17.7 行。取 16：留出约 1.7 行给中文折行（一句结局折一次就是多一行）。
## 第一版取 14，出图上面板底下空了 80px —— 不是 bug，但那是白付的屏幕成本。
const STORY_LINES := 16

func _ready() -> void:
	var seed := 20260626
	var backend := "logic"
	var spd := 1.0
	var warmup_days := 0                   # --warmup N：开局前静默推进到第 N 天（录 demo 跳到节日日用）
	var warmup_tick := 0                   # --warmup-tick T：静默推进到精确 tick T（眼验：定格某一瞬的社交事件）
	var _sel_arg := ""                     # --select id：定格后观察台默认选中此角色（眼验居中到当事人）
	var _dbg_nav_arg := false              # --dbg-nav：启动/出图即开导航叠层
	var _probe_space_arg := ""             # --probe-space id：启动即把 Probe 切到该 Space（P3 咖啡馆室内眼验）
	var _probe_floor_arg := ""             # --probe-floor id：配 --probe-space 指定楼层
	var _obs_arg := false                  # --obs-full：启动即展开观察台完整卷宗（出图对照用；默认档是名片档）
	var _lod_agg_arg := false              # --lod-agg：仅【测量/眼验】用，启用观察无关 aggregate LOD（CLI-only，绝不进 boot/面板出货路径；默认 off=逐字节不变）
	var _locked_ortho_c1_arg := false      # --locked-ortho-c1：可删除的 C1 纯 View 适配器，默认绝不实例化
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--backend" and i + 1 < args.size():
			backend = args[i + 1]
		elif args[i] == "--seed" and i + 1 < args.size():
			seed = int(args[i + 1])
		elif args[i] == "--speed" and i + 1 < args.size():
			spd = float(args[i + 1])
		elif args[i] == "--endpoint" and i + 1 < args.size():
			AIBackend.endpoint = args[i + 1]   # 容器内连宿主 LM Studio：http://host.docker.internal:1234/v1/chat/completions
		elif args[i] == "--gpu":
			AIBackend.slm_use_gpu = true       # slm 后端用 GPU(本机原生 Vulkan)
		elif args[i] == "--debug-llm":
			AIBackend.debug_llm = true         # 诊断：打印每次 LLM 返回
		elif args[i] == "--scenario" and i + 1 < args.size():
			Sim.scenario = args[i + 1]         # S3 定向场景（faction/betray/freerider）；空=默认
		elif args[i] == "--agents" and i + 1 < args.size():
			Sim.spawn_count = int(args[i + 1]) # 扩 N：克隆到 N（含 L6 调色板变体演示）
		elif args[i] == "--player":
			_player_mode = true                # 玩家入镇（gameplay M1：WASD 移动 + G/F/B/Y/P/M 社交动作）
		elif args[i] == "--player-pos" and i + 2 < args.size():
			_player_mode = true                # 可见集成钩：玩家站在被测机制旁，截图/录屏呈现真实操作视角
			_player_spawn_override = Vector2i(int(args[i + 1]), int(args[i + 2]))
		elif args[i] == "--player-demo":
			_player_mode = true                # 录 demo 用：脚本化玩家 autopilot（确定性按 tick 触发动作）
			_demo_mode = true
		elif args[i] == "--locked-ortho-c1":
			_locked_ortho_c1_arg = true
		elif args[i] == "--warmup" and i + 1 < args.size():
			warmup_days = int(args[i + 1])     # 录 demo：跳到第 N 天开场（确定，goto_tick 同款重演）
		elif args[i] == "--warmup-tick" and i + 1 < args.size():
			warmup_tick = int(args[i + 1])     # 眼验：精确定格到 tick T（goto_tick 同款确定重演）
		elif args[i] == "--select" and i + 1 < args.size():
			_sel_arg = args[i + 1]             # 眼验：定格后默认选中此角色
		elif args[i] == "--digest-at" and i + 1 < args.size():
			_digest_at = int(args[i + 1])
		elif args[i] == "--digest-out" and i + 1 < args.size():
			_digest_out = args[i + 1]          # dev 硬门：F9 写 digest（见变量注释）
		elif args[i] == "--shot" and i + 1 < args.size():
			_shot_path = args[i + 1]           # dev 出图：渲一帧存 png 退出（需真 framebuffer：Xvfb 或带窗口）
		elif args[i] == "--shot-fit":
			_shot_fit = true                   # 出图整镇入画（缩放到整图-HUD 余量）；缺省保留跟随相机（角色特写眼验）
		elif args[i] == "--dbg-nav":
			_dbg_nav_arg = true                # 出图/启动即开导航叠层（阻挡格+交互格）
		elif args[i] == "--probe-space" and i + 1 < args.size():
			_probe_space_arg = args[i + 1]     # 出图/启动即把 Probe 切到某 Space（眼验 P3 咖啡馆室内）
		elif args[i] == "--probe-floor" and i + 1 < args.size():
			_probe_floor_arg = args[i + 1]     # 配 --probe-space：指定楼层（1f/2f）
		elif args[i] == "--obs-full":
			_obs_arg = true                    # 出图/眼验：直接以【完整卷宗】档启动（否则出图只拍得到名片档，没法对照）
		elif args[i] == "--goals":
			_goals_open = true                 # 出图/眼验：启动即展开小镇纪事清单（默认是【收起】的，出图拍不到）
		elif args[i] == "--story":
			_story_open = true                 # 出图/眼验：启动即展开小镇故事（同上；两个都给了以 --story 为准，见下）
		elif args[i] == "--lod-agg":
			_lod_agg_arg = true                # 测量/眼验：启用观察无关 aggregate LOD（docs/32）。只在此 CLI 口，不接出货窗口（休眠靠"窗口从不设 LOD 标志"不变量）
		elif args[i] == "--demo-cam":
			_demo_cam = true                   # 录屏：确定性演示镜头（推近越过名牌门 + 选人 → 观察台亮起）
		elif args[i] == "--demo-cam-trace" and i + 1 < args.size():
			_demo_cam = true
			_demo_trace = FileAccess.open(args[i + 1], FileAccess.WRITE)   # dev：轨迹逐 tick 落盘，供两跑逐字节比对
		elif args[i] == "--obs-fit":
			# W8 断言（docs/47 §五-E4）：逐个居民量**真实控件**的 `get_content_height()`，
			# 与可用高度对比，超一格就 exit 1。**不是截图印象，是两个数**。
			_obs_fit_frames = 3                # 等 3 帧让 HUD 布局落定，再开量
			_obs_arg = true                    # 最坏一档 = 完整卷宗（名片档装得下不代表卷宗装得下）
	AIBackend.backend = backend
	# 后端优先级：CLI --backend 显式 > user://settings.cfg（手机 UI 存的默认）> 默认 logic。
	# headless CI 不经此路（Harness/soak 直接 Sim.backend=null）→ 确定性逐字节不变。
	if not ("--backend" in args):
		AIBackend._load_user_settings()          # 可能把 AIBackend.backend 改成上次选的 slm/mock
	AIBackend.backend_requested = AIBackend.backend
	backend = AIBackend.backend                  # 让下方 probe 判定用最终值
	_seed = seed
	# NPC 数量 + 速度：同款优先级 CLI > user://settings.cfg > 默认（改 NPC 数会同种子重开小镇，故也存这里）。
	var _scfg := ConfigFile.new()
	_scfg.load("user://settings.cfg")
	if not ("--agents" in args):
		var _n := int(_scfg.get_value("sim", "npc_count", 0))
		if _n > 0:
			Sim.spawn_count = _n
	if not ("--speed" in args):
		spd = float(_scfg.get_value("sim", "speed", spd))
	# 玩家模式：同款优先级 CLI --player > user://settings.cfg > 默认【关】。
	# 默认必须是关：开着会调 Sim.add_player() 从而合法地移动 digest（docs/41 §3），
	# 而 tools/probe_digest_test.sh 之类的容器跑用的是全新的 user://，读到的就是这个默认值。
	if not ("--player" in args) and not ("--player-demo" in args) and not ("--player-pos" in args):
		_player_mode = bool(_scfg.get_value("sim", "player", false))
	AIBackend.slm_model_override = String(_scfg.get_value("slm", "model_path", ""))   # 上次在设置里手选的 gguf
	# 观察台档位（纯视图偏好，不进仿真）。默认【名片档】——研究用法（钉住卷宗刷时间轴）按一次就回来，
	# 而且会被记住；出图/CI 走全新的 user:// ⇒ 恒为默认档，截图可复现。
	_obs_expanded = _obs_arg or bool(_scfg.get_value("ui", "obs_expanded", false))

	# L7：--scenario 指向 data/scenarios/<id>.json（含 70B 编剧产出）→ 注册数据驱动场景 provider（窗口里也能演）。
	# 空/内建场景(faction/betray/freerider 无此文件)→ 不注册 → 回落内建 _seed_scenario；默认 ""→ Sim.ext 保持 null 逐字节不变。
	if Sim.scenario != "" and FileAccess.file_exists("res://data/scenarios/%s.json" % Sim.scenario):
		var ext := preload("res://scripts/SimExtensions.gd").new()
		ext.register_scenario(preload("res://scripts/DataScenarioProvider.gd").new(Sim.scenario))
		ext.freeze()
		Sim.ext = ext
	if _lod_agg_arg:
		Sim.lod_aggregate = true            # 置于 start_new 前 → warmup goto_tick + 出图定格都跑聚合档，前缀与 live 同档、goto_tick 逐字节可复现，截到的正是聚合档
	if not Sim.world_reset.is_connected(_invalidate_chat_generation):
		Sim.world_reset.connect(_invalidate_chat_generation)
	Sim.start_new(seed)
	if warmup_tick > 0:
		Sim.goto_tick(warmup_tick)          # 眼验：精确定格到某一 tick
		_selected_id = "ben"
	elif warmup_days > 0:
		Sim.goto_tick((warmup_days - 1) * int(Sim.TICKS_PER_DAY) + 8)   # 跳到第 N 天开场（节日已在日界 spawn）
		_selected_id = "ben"                # 录 demo：默认选中木匠(有职业+钱) → 观察台展示经济/职业行
	if _sel_arg != "":
		_selected_id = _sel_arg             # --select 覆盖默认选中（眼验居中到当事人）
	Sim.backend = AIBackend   # 窗口模式注入可插拔后端；headless/soak 时 Sim.backend=null 走内置 logic
	Sim.speed = spd
	_npc_target = maxi(6, Sim.agents.size())   # 设置面板 NPC 数量初值 = 实际居民数（基础 cast=agents.json，或 spawn_count 克隆总数）
	if _player_mode:
		Sim.add_player(_player_spawn_override) # 玩家入社交图；产品截图可把玩家放到被测纵切，正常启动仍回落广场
	if _demo_mode:
		_demo_setup()                 # 舞台布置（首帧前，无可见跳变）+ 动作剧本
	Sim.auto_run = true               # 镇子立刻跑（logic 地板）——slm/llm 探测改后台异步，不再挡首帧

	_view = preload("res://scripts/WorldView.gd").new()
	_view.dbg_nav = _dbg_nav_arg      # --dbg-nav：出图/启动即开导航叠层（否则运行时按 N 切）
	add_child(_view)
	if _locked_ortho_c1_arg:
		_activate_locked_ortho_c1()

	# 相机：可拖可缩的"探针"。红线（docs/19 §3）：相机【纯视图】——只决定画哪、怎么映射输入，
	# 绝不喂 Sim.lod_focus。若"精细模拟哪块"取决于人眼在看哪，小镇历史就成了观察路径的函数 →
	# 同存档不同看法回放出不同 event_log → digest 不可复现、回放红线破。渲染可以跟相机，仿真分级不行。
	_sg = preload("res://scripts/SpaceGraph.gd").new()
	_sg.load_from()                              # 缺 spaces.json → 空图 → bounds 回落 Sim.GRID（off 门）
	_probe = preload("res://scripts/ProbeController.gd").new()
	add_child(_probe)
	_probe.setup(self, _space_bounds())          # 边界来自 active Space（兼容期=town；P1 起由 SpaceGraph 给）
	# ★开局取景（docs/43 §1.1 / §三-C3-4）：setup() 只把相机放到 bounds 中心，zoom 保持 Camera2D 默认的 1.0。
	# 64×48 格 × 48px = 3072×2304 的镇子在 1280×768 里只露 (1280×768)/(3072×2304) = 13.9% —— 一开局就是"贴脸"，
	# 玩家看不到自己在哪个镇上。Home 键（go_home）早就修好了这件事，只是【从来没人替他按过第一次】。
	# 复用 go_home 而不是另写一份 fit：它是"回到全镇"的唯一真源（--shot-fit、点门出屋也都走它）。
	_probe.go_home()
	# 但要把它顺手压进返回栈的那一帧丢掉：否则开局第一次按 ESC 会「退回」到上面那个 13.9% 的坏取景，
	# 而不是按既有语义清掉选中。历史栈这时必然是空的，clear 不会误伤任何用户操作。
	_probe._history.clear()
	_probe.tapped.connect(_on_probe_tap)
	_probe.double_tapped.connect(_on_probe_double_tap)
	if _locked_ortho_c1 != null:
		_locked_ortho_c1.setup(_probe)
		_locked_ortho_c1.apply_fixed_frame(_vp(), _probe.HOME_PAD)
	if _demo_cam:
		_probe.demo_cam = true
		_demo_cam_apply()                        # 首帧就在轨迹上（否则录屏第一帧仍是 go_home，第二帧才跳过去）
	if _probe_space_arg != "" and _sg.has_space(_probe_space_arg):   # --probe-space：启动即进某 Space（P3 室内眼验）
		var _pf: String = _probe_floor_arg if _probe_floor_arg != "" else _sg.default_floor(_probe_space_arg)
		_probe.set_space(_probe_space_arg, _pf, _sg.bounds_px(_probe_space_arg))
	if _locked_ortho_c1 != null:
		# C1 never permits a CLI/Probe inspection shortcut around player portals.
		_probe.set_space("town", "outdoor", _sg.bounds_px("town"))
		_probe._history.clear()
		_locked_ortho_c1.apply_fixed_frame(_vp(), _probe.HOME_PAD)

	# 昼夜光照：CanvasModulate 只染世界画布，不染 HUD（HUD 在独立 CanvasLayer）
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	# ★首帧就上色（docs/41 §6 盲区④ / docs/43 R4-④ 的修复点）。
	# CanvasModulate 建出来是【白】的，而 _daylight 此前只在 _on_tick / _after_jump / _after_load 三处施加——
	# 这三条路 --shot 一条都不走（它把 auto_run=false 定格在 warmup tick），于是所有静帧一律按正午渲染：
	# 实测 before_night_t488.png（HUD 写「第 3 天 00:48 夜」）与 before_noon_t600.png 的主草地色
	# 逐字节都是 (133,166,67)，两张图的世界区差分 bbox 只来自钟点文字与居民位置。
	# 后果不是"截图不好看"，而是【这个项目所有视觉判断用的尺子是坏的】：任何"偏亮/偏暗"的结论都不可信。
	# 这里在 warmup(goto_tick) 之后、首帧之前施加一次 —— 出图、录屏首帧、真机开局三条路一起修好。
	_modulate.color = _daylight(Sim.time_of_day())

	# 小镇纪事：**先于** _build_hud 建好 —— 播报框的第一行就是它的一行摘要，HUD 建的时候得能问到它。
	# 缺 data/goals.json → load_defs 返回 false、state 为空 → summary_line()=="" ⇒ 整条进度线静默消失，
	# 其余 HUD 逐像素不变（同 economy/festivals 那套"缺文件即整个子系统关掉"的纪律）。
	# 这里就 sync 一次的理由：--warmup/--warmup-tick 靠 goto_tick 静默跳到第 N 天，
	# 那段历史发生在任何信号接线【之前】——纯靠信号累积的 UI 在跳转开局一律是空的（契约 §6 盲区②）。
	# 本类根本不接信号、只按 event_log 折，所以这条盲区在这里是【按构造】不成立的，这一行只是把游标推到位。
	_goals = preload("res://scripts/Goals.gd").new()
	_goals.load_defs()
	_goals.sync(Sim.event_log)

	# 小镇故事：同一条纪律、同一个理由（--warmup/--warmup-tick 的那段历史发生在接线之前，
	# 靠信号累积的 UI 在跳转开局一律是空的 —— 契约 §6 盲区②；本类按 event_log 折，故这条盲区按构造不成立）。
	# 文法写死在 Story.gd 里（brief 只给了两个文件），故没有"缺文件即关掉"的第二条分支要守。
	_story = preload("res://scripts/Story.gd").new()
	_story.sync(Sim.event_log)
	if _story_open:
		_goals_open = false                # 两块共用左上角槽位 ⇒ --story 与 --goals 同时给时以 --story 为准

	_build_hud()
	Sim.ticked.connect(_on_tick)
	Sim.social_event.connect(_on_social)
	Sim.day_changed.connect(func(d): _push("[color=#ffe08a]——— 第 %d 天 ———[/color]" % d))
	_update_status()
	_update_obs()
	_update_scrubber()
	# 播报按【当前 event_log】重建一次：--warmup/--warmup-tick 靠 goto_tick 静默跳到第 N 天（录 demo/出图的主路径），
	# 那些事件发生在 social_event 接线【之前】，只靠信号的话开局播报是【空】的——15 天的镇子却一行戏都没有。
	# 眼验发现（headless bench 看不见）：本行让"跳转开局"与 scrub/读档(_after_jump/_after_load)走同一套重建，三路一致。
	_rebuild_feed()
	if OS.has_feature("android"):           # 手机上无控制台：把模型是否就位讲出来，缺则玩家知道往哪放 gguf
		var ms := AIBackend.model_status()
		_push("[color=#9ad0ff]端上模型 %s\n%s[/color]" % [("已就位" if ms["exists"] else "未找到 → 用 logic 地板（把 gguf 放进 Documents 后重开）"), ms["path"]])
	# 端上模型：首帧/HUD 已建好，才【异步】探测——真机 1.9GB 模型 load+2 暖发要 ~85s，绝不能挡首帧(否则黑屏)。
	# 探测期间镇子跑 logic 地板(活着)；够快切 slm/llm，太慢/坏留 logic。（headless CI 不经窗口路 → 逐字节不变。）
	if backend == "slm" or backend == "llm":
		_probe_and_activate(backend)        # 不 await：后台跑，首帧已可见
	if _shot_path != "":                    # dev 出图：等 1.5s 让世界渲染+纹理加载，再存一帧退出
		Sim.auto_run = false                # 定格：冻结在 warmup tick，等待期间不再推进（tick-precise 眼验，防漂）
		if _demo_cam and _probe != null:    # --demo-cam + --warmup-tick T：把录屏在 tick T 的构图【定格】拍下来。
			_demo_cam_apply()               # 这是本棒唯一可复现的量具：轨迹是 tick 的闭式函数 ⇒ 这一帧 == 录屏那一帧
		elif _shot_fit and _probe != null:  # --shot-fit：整镇（或当前室内 Space）入画，缩放到【bounds - HUD 余量】刚好塞进视口
			_fit_active_space()
		elif _selected_id != "" and _probe != null:   # --select（无 --shot-fit）：特写居中到当事人（角色眼验）
			var _sag := Sim.get_agent(_selected_id)
			if not _sag.is_empty():
				_probe.focus_on(Vector2(int(_sag["pos"].x) * 48 + 24, int(_sag["pos"].y) * 48 + 24), _selected_id)
		get_tree().create_timer(1.5).timeout.connect(func():
			var img := get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(_shot_path)
			get_tree().quit())

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var fnt := Art.font()

	# 顶栏底板。为什么它此前【没有】：日志(:_log_pan)、观察台(:_obs_pan)、时间轴(:_scrub_pan) 三块都补过板，
	# 唯独全屏最密的这一行是裸的 —— 实测 before_town_day5.png 的 y=10 整行有 1112/1280 px 亮度 ≥40%，
	# 草地 (133,166,67) 与浅墙 (216,189,147) 直接透到白字底下。
	# 用比 _mk_panel(黑 0.42) 更实的一档（同 dev overlay 的 0.02/0.03/0.05 @0.74）：0.42 压不住浅墙——
	# 算过：0.58×(216,189,147) 亮度仍有 43.7%，而 0.74 档只剩 22.6%。
	# 它【必须】先于 _status/⚙钮/后端钮入树：CanvasLayer 按添加序叠放，晚了就盖住字。
	# 宽度取整屏（不是 _status 的 1082）：⚙ 钮在 x=10、后端钮在 x=1140，两端都要有底。
	_status_pan = ColorRect.new()
	_status_pan.color = Color(0.02, 0.03, 0.05, 0.74)
	_status_pan.position = Vector2.ZERO
	_status_pan.size = Vector2(DESIGN.x, STATUS_H1 + 12.0)
	_status_pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status_pan)

	_status = _mk_label(layer, fnt, 17, Vector2(52, 6), Vector2(STATUS_W, STATUS_H1))   # 左留 ⚙ 设置钮，右留「详情」+ 后端切换钮

	# 设置钮（左上角；点开 NPC 数量/速度/后端面板。O 键同款开关）
	# 字形纪律：随包字体 Smiley Sans 是 CJK 显示体，无 emoji 覆盖 —— HUD 里一律用汉字/ASCII，否则真机上是豆腐块。
	var gear := Button.new()
	gear.text = "设"
	gear.add_theme_font_override("font", fnt)
	gear.add_theme_font_size_override("font_size", 18)
	gear.position = Vector2(10, 4)
	gear.size = Vector2(36, 30)
	gear.focus_mode = Control.FOCUS_NONE
	gear.pressed.connect(_toggle_settings)
	layer.add_child(gear)

	# 左下角滚动事件日志：把看不见的社交戏剧讲出来。
	# 底板从「(8,470) 560×246 的硬边黑 0.42 矩形」换成【贴住左下角的羽化 scrim】：
	#   · 左边到 x=0、下边到屏幕底 ⇒ 这两条边根本不在画面里，不可能成为接缝；
	#   · 右边与上边用 alpha 斜坡抹掉（改前中位跃变 65.8 / 71.0，是画面上第二刺眼的直线）；
	#   · 核心档 0.84 而不是 0.42 —— 跟随相机那一帧上，改前正文背景均值亮度高达 102/255（40.1%），
	#     白字压在亮草地上基本读不出，"既读不清字、又挡着世界"两头不讨好。
	_log_pan = _mk_scrim(layer, Vector2(0, LOG_SCRIM_TOP), Vector2(LOG_SCRIM_W, DESIGN.y - LOG_SCRIM_TOP),
		0.0, 1.0 - LOG_CORE_R / LOG_SCRIM_W, (476.0 - LOG_SCRIM_TOP) / (DESIGN.y - LOG_SCRIM_TOP), 0.0)
	_logbox = _mk_label(layer, fnt, 15, Vector2(16, 476), Vector2(548, 236))
	# 【仅】日志面板改为吃鼠标：每行是 [url=<居民id>]，点一行 → 选中当事人并把镜头飞过去。
	# 其余 HUD 面板保持 MOUSE_FILTER_IGNORE（世界点选/缩放照旧穿透）。手机无键盘，这是唯一能跟戏的入口。
	_logbox.mouse_filter = Control.MOUSE_FILTER_STOP
	_logbox.meta_clicked.connect(_on_log_meta)

	# 右侧观察台明细面板。**它是本项目最独特的能力（任意 tick 检查任意居民），所以一行功能都不删**——
	# 改的是"默认占多大"：改前恒占屏宽 22.97% / 屏面积 20.22%，且是 OBS_MAX_LINES=34 行的调试密度文本，
	# 这是整张图上"这是工具不是游戏"的最大单一来源。现在分两档：
	#   名片档（默认）：谁 / 在哪 / 在干嘛 / 钱与职业 / 5 条需求 —— 屏宽 18.75% / 屏面积 8.30%；
	#   完整卷宗（点「详情」或 V）：关系 / 冲突 / 记忆 / 派系 / 盟约 / 秘密 / 观点 / 信念，版式与改前逐行相同。
	# 两档共用同一个 RichTextLabel 与同一份 _panel_text()，**没有第二套渲染**（同 C3 的动作条纪律）。
	_obs_pan = _mk_scrim(layer, Vector2(DESIGN.x - OBS_FULL.x, OBS_TOP), OBS_FULL, 0.26, 0.0, 0.0, 0.18)
	_obs = _mk_label(layer, fnt, OBS_FS, Vector2(986, OBS_TOP + OBS_PAD), Vector2(286, OBS_FULL.y - OBS_PAD * 2.0))

	# 底部时间轴 scrubber
	# 先铺底板再铺控件（CanvasLayer 按添加序叠放）：提示行原本是 #9aa0b5 直接画在草地上，眼验实测几乎读不出
	# （B3 视觉复核指出，但它属 Main.gd 不在其归属内）。与日志/观察台同款半透明底板，成本一行、不碰仿真。
	_scrub_pan = _mk_panel(layer, Vector2(SCRUB_X0 - 8, SCRUB_Y - SCRUB_PAN_DY), Vector2(SCRUB_X1 - SCRUB_X0 + 16, SCRUB_PAN_H))
	_scrub_pan.color = Color(0.02, 0.03, 0.05, 0.74)   # T3：与顶栏同一档（0.42 压不住浅墙/亮草地，见 SCRUB_HINT_FS 处的实测）
	_scrub_track = ColorRect.new()
	_scrub_track.color = Color(1, 1, 1, 0.14)
	_scrub_track.position = Vector2(SCRUB_X0, SCRUB_Y)
	_scrub_track.size = Vector2(SCRUB_X1 - SCRUB_X0, SCRUB_H)
	_scrub_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_scrub_track)
	_scrub_fill = ColorRect.new()
	_scrub_fill.color = Color("#5ad1c2", 0.55)
	_scrub_fill.position = Vector2(SCRUB_X0, SCRUB_Y)
	_scrub_fill.size = Vector2(0, SCRUB_H)
	_scrub_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_scrub_fill)
	_scrub_handle = ColorRect.new()
	_scrub_handle.color = Color("#ffd166")
	_scrub_handle.size = Vector2(4, SCRUB_H + 8)
	_scrub_handle.position = Vector2(SCRUB_X0, SCRUB_Y - 4)
	_scrub_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_scrub_handle)
	_scrub_hint = _mk_label(layer, fnt, SCRUB_HINT_FS, Vector2(SCRUB_X0, SCRUB_Y - SCRUB_HINT_DY), Vector2(SCRUB_HINT_W, SCRUB_HINT_H))
	# 键位提示。改动前只列了 6 个绑定（_unhandled_input 里实有 30 个动作 / 37 个 keycode），
	# 而漏掉的恰好是 Home —— 就是那个能把"开局只看得见 13.9% 的镇子"一键修好的键（docs/43 §1.1）。
	#
	# ⚠️ **上一版这里写的"原文只用掉 700px 里的约 376px"是错的，错了 1.7 倍。**
	#   引擎实测（`Font.get_string_size`，Smiley Sans Oblique，BBCode 已剥）：**字号 12 → 640px / 700px（91.4%）**。
	#   ⇒ 它从来就没有"仍是单行"的余量，只是恰好没越线；而字号一抬到 14 就是 **746px**、直接折行，
	#     再被 22px 的框高**静默裁掉**第二行（`scroll_active=false` 的老毛病）。
	#     这个回归是本棒**先做出来、再被 3× 放大对照图抓住的**——数字对照没抓到它，因为我量的是对比度不是宽度。
	# ⇒ 两条修法一起用，而不是二选一：
	#   ① 去掉"（确定性重演）"这个**编辑性注解**（不是键位）⇒ 字号 14 实测 **671px / 700px**，余 29px。
	#      这句话在 README 与 docs 里都在，HUD 这一行的职责是列键位。
	#   ② 字号**不写死**：`_fit_hint_fs` 从 SCRUB_HINT_FS 往下退到装得进 700px 的第一档。
	#      于是下一个往这行加字的人会自动掉到 13 或 12，而不是静默丢掉半行——**把冻结字面量换成量具**。
	_scrub_hint.text = "[color=#9aa0b5]时间轴：拖动回放 · 空格暂停 · , . 单步 · [ ] 跳天 · Tab 切角色 · [color=#ffd166]Home 回全镇[/color] · L 跟随 · [color=#ffd166]V 详情[/color] · [color=#ffd166]J 纪事[/color] · O 设置 · F5/F8 存读档 · 点居民查看[/color]"
	_scrub_hint.add_theme_font_size_override("normal_font_size", _fit_hint_fs(fnt, _scrub_hint.text))

	# 玩家 → NPC 对话输入框（**玩家模式下**选中居民后出现；Enter 发送）。M2：经 AIBackend.chat → LLM/mock/罐头。
	# ★改前它只 gate 在"选中了人"上，没有 gate 在玩家模式上 —— 于是纯观察模式下点任何一个居民，
	#   都会在世界正中央浮出一个"对 XX 说…"的输入框，而那个模式里根本没有"你"可以说话。
	#   （它甚至出现在 --shot 的每一张出图上：warmup 会置 _selected_id="ben"。）
	#   位置不动：玩家模式下它与动作条(y=606)在同一列，两者构成底部中央的一簇，不再是孤零零一条。
	_chat_in = LineEdit.new()
	_chat_in.add_theme_font_override("font", fnt)
	_chat_in.add_theme_font_size_override("font_size", 15)
	_chat_in.position = Vector2(584, 648)
	_chat_in.size = Vector2(380, 30)   # 让开右侧观察台（它加高到 y=712）
	_chat_in.visible = false
	_chat_in.text_submitted.connect(_on_player_say)
	layer.add_child(_chat_in)

	_build_action_bar(layer, fnt)

	# 观察台档位钮（顶栏右侧，后端钮左边）。放在这里而不是面板里的理由见 OBS_PAD 的注释。
	# 手机上没有键盘 ⇒ 这一个按钮就是「完整卷宗」的唯一入口（V 键只是桌面同款，走同一个 _toggle_obs）。
	_obs_btn = Button.new()
	_obs_btn.add_theme_font_override("font", fnt)
	_obs_btn.add_theme_font_size_override("font_size", 15)   # T3：与观察台正文同档（钮框 62×30，字号 15 的引擎行高 22 ⇒ 仍有余量）
	_obs_btn.position = Vector2(OBS_BTN_X, 4)
	_obs_btn.size = Vector2(OBS_BTN_W, 30)
	_obs_btn.focus_mode = Control.FOCUS_NONE   # 不抢键盘焦点（同 ⚙/后端/动作条钮）
	_obs_btn.pressed.connect(_toggle_obs)
	layer.add_child(_obs_btn)

	# 后端切换按钮（右上角）。手机上无 CLI → 靠这个在 logic/slm/… 间轮换；emulate_mouse_from_touch 默认开 → 点按即触发。
	# Button 独占自身矩形，不干扰世界点选；FOCUS_NONE 免抢键盘焦点（否则空格/快捷键失灵）。
	_backend_btn = Button.new()
	_backend_btn.add_theme_font_override("font", fnt)
	_backend_btn.add_theme_font_size_override("font_size", 15)   # T3：同上（钮框 132×30）
	_backend_btn.position = Vector2(1140, 4)
	_backend_btn.size = Vector2(132, 30)
	_backend_btn.focus_mode = Control.FOCUS_NONE
	_backend_btn.pressed.connect(_on_toggle_backend)
	layer.add_child(_backend_btn)
	_sync_backend_btn()

	_build_settings(layer, fnt)

	# 小镇纪事的【展开档】面板（默认隐藏；J 键 或 点播报栏顶那一行）。
	# 为什么默认隐藏、且收起档只在播报框里占**一行**：docs/46 §一 #5 记着"25.5% 的屏幕已经是 chrome"，
	# 再挂一块常驻面板就是往那个数字上加。收起档的成本是 1 行文字，且它长在**已经存在**的播报底板里，
	# 不新增任何底板/接缝（C7 的教训：沿边界多描一个矩形比原来那条硬边更糟）。
	# ★ 展开档必须走 _mk_scrim 而不是 ColorRect。D2 的像素验收只测了【收起档】，于是展开档带着一条
	# 和 C8 刚刚抹掉的那条一模一样的硬边回来了：实测右缘 x=354 逐行亮度跃变 **中位数 110.99，且 median==max**
	# （每一行都是同一个 111 的台阶 = 教科书式的硬边），而隔壁 C8 羽化过的播报右缘同一量法是 **0.93**。
	# 左/上两边贴着屏幕角 ⇒ 不需要羽化；只羽化右边与下边（这两条才压在世界上）。
	_goals_pan = _mk_scrim(layer, Vector2(GOALS_X, GOALS_Y), GOALS_SZ + Vector2(GOALS_FEATH, GOALS_FEATH),
		0.0, GOALS_FEATH / (GOALS_SZ.x + GOALS_FEATH), 0.0, GOALS_FEATH / (GOALS_SZ.y + GOALS_FEATH))
	_goals_pan.visible = _goals_open
	_goals_box = RichTextLabel.new()
	_goals_box.bbcode_enabled = true
	_goals_box.scroll_active = false
	_goals_box.add_theme_font_override("normal_font", fnt)
	# T3 **量了之后决定不改**（docs/75 §四要求把这种决定写进回执）：
	# 本块可用高 GOALS_SZ.y-12 = 268px，内容 14 行（标题+11 目标+下一步+页脚）。
	# 按本棒实测的行距（字号 14→18px、15→19px）：14 → 14×18=252/268（余 16px）；**15 → 14×19=266/268（余 2px）**。
	# 而 RichTextLabel `scroll_active=false` 溢出**不报错、不出滚动条，只静默裁掉尾巴**（D2 的教训），
	# 中文只要折一次行就会多出 19px ⇒ 直接吞掉最后一条目标。**代价大于收益，故留在 14。**
	_goals_box.add_theme_font_size_override("normal_font_size", 14)
	_goals_box.position = Vector2(10, 6)
	_goals_box.size = GOALS_SZ - Vector2(20, 12)
	_goals_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goals_pan.add_child(_goals_box)
	_sync_goals_panel()

	# 小镇故事的展开档面板（默认隐藏；K 键 或 点播报里 ◇ 那一行）。与纪事面板同槽互斥，见 STORY_X 处的注释。
	# 同样走 _mk_scrim 而不是 ColorRect：D2 那条"展开档带回一条硬边"的教训只被修在纪事上，
	# 新开一块面板如果偷懒用 ColorRect，就是把同一个 bug 重新生一遍（右缘 x=480 会是一条 111 的台阶）。
	_story_pan = _mk_scrim(layer, Vector2(STORY_X, STORY_Y), STORY_SZ + Vector2(STORY_FEATH, STORY_FEATH),
		0.0, STORY_FEATH / (STORY_SZ.x + STORY_FEATH), 0.0, STORY_FEATH / (STORY_SZ.y + STORY_FEATH))
	_story_pan.visible = _story_open
	_story_box = RichTextLabel.new()
	_story_box.bbcode_enabled = true
	_story_box.scroll_active = false
	_story_box.add_theme_font_override("normal_font", fnt)
	# T3 同样**量了之后决定不改**：可用高 320px，STORY_LINES=16。
	# 14 → 16×18=288/320（余 32px ≈ 1.8 行折行余量，正是 STORY_LINES 注释里那 1.7 行的来源）；
	# 15 → 16×19=304/320（余 16px ≈ 0.84 行）。而字号一大每行少约 2 个汉字（450px / 15px ⇒ 30 字 vs 32 字）
	# ⇒ **折行概率同时上升、余量同时下降**，两头都朝坏的方向走。留在 14。
	_story_box.add_theme_font_size_override("normal_font_size", 14)
	_story_box.position = Vector2(10, 6)
	_story_box.size = STORY_SZ - Vector2(20, 12)
	_story_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_story_pan.add_child(_story_box)
	_sync_story_panel()

	# dev 性能 overlay（默认隐藏；F3 或设置面板里开）。label 挂在 panel 下 → 一起显隐。
	# ★位置从 (10,42) 挪到 纪事/故事面板的右边：那一块被元层面板占了，两个都开会叠在一起。
	#   基准从 GOALS 换成 STORY（470 > 344，取宽的那块才对两种面板都不叠）。
	#   三块都默认隐藏 ⇒ 出货帧/出图帧逐像素不受影响（只有同时按 F3+J/K 的 dev 看得见差别）。
	var pperf := ColorRect.new()
	pperf.color = Color(0.02, 0.03, 0.05, 0.74)
	pperf.position = Vector2(STORY_X + STORY_SZ.x + 10.0, 42)
	pperf.size = Vector2(384, 152)
	pperf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pperf.visible = false
	layer.add_child(pperf)
	_perf = RichTextLabel.new()
	_perf.bbcode_enabled = true
	_perf.scroll_active = false
	_perf.add_theme_font_override("normal_font", fnt)
	_perf.add_theme_font_size_override("normal_font_size", 14)
	_perf.position = Vector2(10, 6)
	_perf.size = Vector2(368, 140)
	_perf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pperf.add_child(_perf)

	# B15：按当前视口锚定一次；并接 size_changed —— 手机转屏/桌面拉窗口都会重排（这是唯一入口）。
	_relayout_hud()
	var _vpn := get_viewport()
	if _vpn != null:
		_vpn.size_changed.connect(_relayout_hud)

## 触屏动作条：7 个玩家动词各一个屏幕按钮，走【与物理键完全同一条】的 _player_do。
## 为什么这件事是出货级的：出货目标是 Android APK，而 7 个动词此前全锁在
## 「--player 启动旗标 + 物理键盘」后面 —— 手机上两样都没有，Living Town 在真出货平台上是一块屏保。
## 纪律：不新开动作路径。按钮只 emit 一次 _player_do(verb)，与 KEY_G/F/B/Y/T/P/M 落到同一个函数、
## 同一份前置校验、同一条 Sim.player_act —— 「按钮路径 ≡ 按键路径」因此是【构造上成立】而非靠测试维持，
## 测试(scripts/player_touch_test.gd)只是把这句话钉死，防后人分叉。
func _build_action_bar(layer: CanvasLayer, fnt: Font) -> void:
	_act_pan = ColorRect.new()
	_act_pan.color = Color(0, 0, 0, 0.42)
	_act_pan.position = Vector2(ACT_X - 8.0, ACT_Y - 6.0)
	_act_pan.size = Vector2(ACT_STEP * PLAYER_VERBS.size() + 12.0, ACT_BH + 12.0)
	_act_pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_act_pan.visible = _player_mode          # 非玩家模式：整条隐藏（隐藏的 Control 不吃输入，世界点选照旧）
	layer.add_child(_act_pan)
	_act_btns.clear()
	for i in PLAYER_VERBS.size():
		var v: Dictionary = PLAYER_VERBS[i]
		var b := Button.new()
		b.text = String(v["label"])
		b.tooltip_text = "%s（键 %s）" % [String(v["label"]), String(v["key"])]
		b.add_theme_font_override("font", fnt)
		b.add_theme_font_size_override("font_size", 15)
		b.position = Vector2(ACT_X + ACT_STEP * i, ACT_Y)
		b.size = Vector2(ACT_BW, ACT_BH)
		b.focus_mode = Control.FOCUS_NONE     # 不抢键盘焦点，否则空格/快捷键全失灵（同 ⚙/后端钮）
		b.visible = _player_mode
		var verb := String(v["verb"])
		b.pressed.connect(func(): _player_do(verb))
		layer.add_child(b)
		_act_btns.append(b)

## keycode → 动词（PLAYER_VERBS 的 "key" 字段是唯一真源）。查不到 → ""，_player_do 会当作未知动作交给 Sim 拒绝。
func verb_for_key(kc: int) -> String:
	for v in PLAYER_VERBS:
		if OS.find_keycode_from_string(String(v["key"])) == kc:
			return String(v["verb"])
	return ""

## 动作条显隐 + 重排（玩家模式开关、视口变化两处共用）。
func _sync_action_bar(dx: float = 0.0, dy: float = 0.0) -> void:
	if _act_pan == null:
		return
	var show := _player_mode and not _player_in_warehouse_observatory()
	_act_pan.visible = show
	_act_pan.position = Vector2(ACT_X - 8.0, ACT_Y - 6.0 + dy)
	for i in _act_btns.size():
		var b: Button = _act_btns[i]
		b.visible = show
		b.position = Vector2(ACT_X + ACT_STEP * i, ACT_Y + dy)

## P1-v：货运观测室是只读控制面，不伪装成社交目标或玩家卸货台。
## 只在 visibility 上切上下文；键盘路径另由 _player_do 同门拒绝。
func _sync_action_bar_context() -> void:
	if _act_pan == null:
		return
	var show := _player_mode and not _player_in_warehouse_observatory()
	_act_pan.visible = show
	for raw in _act_btns:
		(raw as Button).visible = show

func _player_in_warehouse_observatory() -> bool:
	if not _player_mode:
		return false
	var pl: Dictionary = Sim.get_agent("player")
	return not pl.is_empty() and String(pl.get("space", "town")) == "port_warehouse" \
		and String(pl.get("floor", "outdoor")) == "1f"

func _agent_location_label(ag: Dictionary) -> String:
	var sid := String(ag.get("space", "town"))
	var fid := String(ag.get("floor", "outdoor"))
	if sid == "port_warehouse" and fid == "1f":
		return "东海货仓 · 货运观测室"
	if sid != "town":
		return "%s · %s" % [_sg.label_of(sid) if _sg != null else sid, fid]
	return Sim._area_label(ag.get("pos", Vector2i.ZERO))

func _mk_panel(layer: CanvasLayer, pos: Vector2, sz: Vector2) -> ColorRect:
	var p := ColorRect.new()
	p.color = Color(0, 0, 0, 0.42)
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(p)
	return p

## B15：把 HUD 从「对 1280x768 的绝对像素」改成「对当前视口的锚定」。
## 为什么不用 Control 的 anchor：这些控件直接挂在 CanvasLayer 下（没有 Control 父节点当锚框），
## anchor 要靠父 Control 的 rect 变化来传播；在 CanvasLayer 下做这件事要么加一层全屏容器重排整棵 HUD，
## 要么依赖"无 Control 父节点时退回 viewport rect"这条不那么显式的规则。既然本文件的版式本来就是
## 一串手写坐标，这里就【显式】按 (dx,dy) 摆一次，比装成布局系统更诚实，也更好对着截图 debug。
## 每条规则都是「设计基准常量 + 增量」→ dx=dy=0 时逐像素回到改动前。
func _relayout_hud() -> void:
	if _status == null:
		return
	var vp := get_viewport_rect().size
	var dx := maxf(0.0, vp.x - DESIGN.x)      # 多出来的宽（手机 2688x1216 → 实测 417）
	var dy := maxf(0.0, vp.y - DESIGN.y)      # 多出来的高（比设计更"方"的屏，如 4:3 平板）
	# 顶部状态栏：左端钉在 ⚙ 钮右边，右端跟着后端钮一起外扩
	# 高度只有玩家模式才是两行 —— dx=dy=0 且非玩家模式时仍是 28，逐像素回到改动前。
	var sh := STATUS_H2 if _player_mode else STATUS_H1
	_status.size = Vector2(STATUS_W + dx, sh)
	if _status_pan != null:                    # 顶栏底板：整屏宽（含 ⚙ 钮与后端钮），高度跟状态栏行数
		_status_pan.size = Vector2(DESIGN.x + dx, sh + 12.0)
	if _backend_btn != null:                   # 后端切换钮：跟右边
		_backend_btn.position = Vector2(1140.0 + dx, 4.0)
	if _obs_btn != null:                       # 观察台档位钮：跟右边（紧贴后端钮左侧）
		_obs_btn.position = Vector2(OBS_BTN_X + dx, 4.0)
		_obs_btn.text = "收起" if _obs_expanded else "详情"
	if _log_pan != null:                       # 左下播报 scrim：贴住左下角（下边跟屏幕底 ⇒ 永远没有下接缝）
		_log_pan.position = Vector2(0.0, LOG_SCRIM_TOP + dy)
		_log_pan.size = Vector2(LOG_SCRIM_W, DESIGN.y + dy - (LOG_SCRIM_TOP + dy))
	if _logbox != null:
		_logbox.position = Vector2(16.0, 476.0 + dy)
	_sync_obs_panel(dx, dy)                    # 右侧观察台：按当前档位摆面板与正文（「详情」钮在顶栏，上面已摆）
	# 时间轴：左端不动（紧挨播报面板），右端跟右边 → 屏幕越宽，时间轴刻度越细
	_sx0 = SCRUB_X0
	_sx1 = SCRUB_X1 + dx
	_sy = SCRUB_Y + dy
	if _scrub_pan != null:
		_scrub_pan.position = Vector2(_sx0 - 8.0, _sy - SCRUB_PAN_DY)
		_scrub_pan.size = Vector2(_sx1 - _sx0 + 16.0, SCRUB_PAN_H)
	if _scrub_track != null:
		_scrub_track.position = Vector2(_sx0, _sy)
		_scrub_track.size = Vector2(_sx1 - _sx0, SCRUB_H)
	if _scrub_hint != null:
		_scrub_hint.position = Vector2(_sx0, _sy - SCRUB_HINT_DY)
		_scrub_hint.size = Vector2(SCRUB_HINT_W + dx, SCRUB_HINT_H)
	if _chat_in != null:                       # 聊天框：跟底边；宽度吃掉观察台让出的那段，保持 14px 间隙
		# ★高度只读不写：构造期（入树前）写的 30 会在入树后被主题最小高抬到 31；此处若照抄常量 30
		# 又会把它压回去，文字基线上移 1px —— 桌面基准的「逐像素不变」就毁在这一个像素上（已被 PIL 差分抓到）。
		_chat_in.position = Vector2(584.0, 648.0 + dy)
		_chat_in.size = Vector2(380.0 + dx, _chat_in.size.y)
	_sync_action_bar(dx, dy)                   # 动作条：跟底边（左端与聊天框对齐，宽度不随 dx 变——按钮是定宽的）
	if _settings_panel != null:                # 设置面板：保持居中（1280x768 下算出来正好是 _build_settings 里的 430,124）
		_settings_panel.position = Vector2(430.0 + dx * 0.5, 124.0 + dy * 0.5)
	_update_scrubber()                         # fill/handle 由它按新的 _sx0/_sx1/_sy 重画

## 观察台两档几何（_relayout_hud 与 _toggle_obs 共用；dx/dy 见 B15 的"基准 + 增量"写法）。
## 展开档的左缘刻意仍是 x=978 —— 与改动前逐像素同位，便于差分只归因于"档位"而不是"我顺手挪了面板"。
func _sync_obs_panel(dx: float = 0.0, dy: float = 0.0) -> void:
	if _obs_pan == null:
		return
	var sz: Vector2 = OBS_FULL if _obs_expanded else OBS_CARD
	if _obs_expanded:
		sz.y += dy                                   # 屏更高 ⇒ 卷宗多几行；名片档是定高的（内容有上限）
	var x0 := DESIGN.x + dx - sz.x                    # 右缘贴屏幕右边 ⇒ 右侧不存在接缝
	# scrim 比【正文矩形】向左、向下各多出 OBS_FEATH：羽化带落在正文之外（见 OBS_FEATH 的注释）。
	# 上缘不羽化——它压在顶栏底板下面；右缘不羽化——它就是屏幕边。
	var pw := sz.x + OBS_FEATH
	var ph := sz.y + OBS_FEATH
	_obs_pan.position = Vector2(x0 - OBS_FEATH, OBS_TOP)
	_obs_pan.size = Vector2(pw, ph)
	_obs_pan.texture = _scrim_tex(OBS_FEATH / pw, 0.0, 0.0, OBS_FEATH / ph)
	if _obs != null:
		_obs.position = Vector2(x0 + 8.0, OBS_TOP + OBS_PAD)
		_obs.size = Vector2(sz.x - 16.0, sz.y - OBS_PAD * 2.0)

# ── 小镇纪事（单局形状）────────────────────────────────────────────────────
## 每 tick 一次：把新事件折进目标，并把**新达成**的那几条播出去。
## ★这是 Main 唯一一处主动喂 Goals 的地方，且方向是【单向的】：Main → Goals。
##   Goals 从不回写 Sim，也从不回写 Main 的任何仿真相关字段。
func _sync_goals() -> void:
	if _goals == null:
		return
	for i in _goals.sync(Sim.event_log):
		_push(_goals.toast(i))                 # 达成的那一刻推进播报栏 —— 进度线上唯一的"事件"
	var line: String = _goals.summary_line()
	if line != _goals_line:                    # 只有摘要真的变了才重画（否则每 tick 都在 join 一遍）
		_goals_line = line
		_render_log()
	if _goals_open:
		_sync_goals_panel()

func _sync_goals_panel() -> void:
	if _goals_box != null and _goals != null:
		_goals_box.text = _goals.panel_text()

## 展开档开关（J 键 与 点播报栏顶那一行共用；纯视图，不碰 Sim）。
func _toggle_goals() -> void:
	_goals_open = not _goals_open
	if _goals_pan != null:
		_goals_pan.visible = _goals_open
	if _goals_open:
		_close_story()                         # 同槽互斥（见 STORY_X 处的注释）
		_sync_goals_panel()

# ── 小镇故事（因果弧）──────────────────────────────────────────────────────
## 每 tick 一次：把新事件折进故事，并把**刚刚收场**的那几段播出去。
## ★方向同样是单向的：Main → Story。Story 从不回写 Sim，也不回写 Main 的任何仿真相关字段。
## ★只在**收场**时播报，不在开头/中间播 —— 这正是它与编年史的分界：
##   编年史已经把每一件事各播过一遍了；故事再播一遍开头只是重复，播结局才是新信息
##   （"刚才那五件散事其实是一段，而它这样收场了"）。
func _sync_story() -> void:
	if _story == null:
		return
	for arc in _story.sync(Sim.event_log):
		_push(_story.toast(arc, _story_name))
	if _story_open:
		_sync_story_panel()

## 只有故事**真的动了**才重排面板。`Story.rev` 是折叠的脏标记（开/推进/收场/裁剪时才 +1）。
## 理由是 docs/46 §二·六 那笔账（真机 FPS 88 → 11）：面板一开就每 tick 对 128 条弧排两次序是白烧的，
## 而实测事件疏密下绝大多数 tick 根本没有任何弧发生变化。
func _sync_story_panel() -> void:
	if _story_box == null or _story == null or int(_story.rev) == _story_rev:
		return
	_story_rev = int(_story.rev)
	_story_box.text = _story.panel_text(_story_name, STORY_LINES)

## 展开档开关（K 键 与 点播报里 ◇ 那一行共用；纯视图，不碰 Sim）。
func _toggle_story() -> void:
	_story_open = not _story_open
	if _story_pan != null:
		_story_pan.visible = _story_open
	if _story_open:
		_close_goals()                         # 同槽互斥
		_story_rev = -1                        # 关着的时候不重排 ⇒ 再打开时缓存必然是旧的，强制重排一次
		_sync_story_panel()

func _close_story() -> void:
	_story_open = false
	if _story_pan != null:
		_story_pan.visible = false

func _close_goals() -> void:
	_goals_open = false
	if _goals_pan != null:
		_goals_pan.visible = false

## Story.gd 不认识 Sim（它连 autoload 都不依赖），名字由这里供给。
## 查不到就退回 id —— 但 Sim._name 对空 dict 已经返回 "?"，所以实际上永远走不到 id 那条路。
func _story_name(id: String) -> String:
	var ag := Sim.get_agent(id)
	return "" if ag.is_empty() else str(ag.get("persona", {}).get("name", id))

## 观察台档位开关（「详情/收起」钮 与 V 键共用；纯视图，不碰 Sim）。
func _toggle_obs() -> void:
	_obs_expanded = not _obs_expanded
	_save_ui_setting("obs_expanded", _obs_expanded)
	_relayout_hud()
	_update_obs()

## 带 alpha 斜坡的 HUD 底板（scrim）。
## 为什么不是 ColorRect：ColorRect 只能画硬边矩形，而硬边贴在世界上就是一条直线——
## 实测（未改动的树）观察台左边界的相邻像素亮度跃变中位 65.8、最大 141.0，编年史右边界中位 65.8。
## C7 已经在世界层付过一次学费：**沿边界连续的硬边比它想藏起来的那个矩形更刺眼**（docs/41 §6）。
## 实现：烘一张 SCRIM_TEX² 的 RGBA 小图（RGB 恒为底色，A = 基础 alpha × 四条边的 smoothstep 斜坡），
## 用 TEXTURE_FILTER_LINEAR 拉伸成面板大小 —— 1 个节点、1 个 draw call，且缩放到任何分辨率都平滑。
## 参数 fl/fr/ft/fb 是各边羽化宽度【占面板边长的比例】，0 = 该边不羽化（因为它贴着屏幕边或压在别的面板下）。
func _mk_scrim(layer: CanvasLayer, pos: Vector2, sz: Vector2, fl: float, fr: float, ft: float, fb: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _scrim_tex(fl, fr, ft, fb)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # 显式写死：默认是"继承项目设置"，别人改了像素画滤波就会把斜坡切成台阶
	tr.position = pos
	tr.size = sz
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)
	return tr

## 烘一张 SCRIM_TEX² 的 RGBA 斜坡图。fl/fr/ft/fb = 各边羽化宽度【占该边长度的比例】。
## 观察台两档尺寸不同 ⇒ 同一组比例给不出同一个像素宽度，故档位切换时按【绝对 px / 当前边长】重烘一次（约 4k 次写点）。
func _scrim_tex(fl: float, fr: float, ft: float, fb: float) -> ImageTexture:
	var img := Image.create(SCRIM_TEX, SCRIM_TEX, false, Image.FORMAT_RGBA8)
	for iy in SCRIM_TEX:
		var v := (float(iy) + 0.5) / float(SCRIM_TEX)
		var ay := _ramp(v, ft) * _ramp(1.0 - v, fb)
		for ix in SCRIM_TEX:
			var u := (float(ix) + 0.5) / float(SCRIM_TEX)
			img.set_pixel(ix, iy, Color(SCRIM_COL.r, SCRIM_COL.g, SCRIM_COL.b,
				SCRIM_COL.a * ay * _ramp(u, fl) * _ramp(1.0 - u, fr)))
	return ImageTexture.create_from_image(img)

## 距某条边 t（归一化 0..1）处的 smoothstep 斜坡；w<=0 表示这条边不羽化。
func _ramp(t: float, w: float) -> float:
	if w <= 0.0:
		return 1.0
	var s := clampf(t / w, 0.0, 1.0)
	return s * s * (3.0 - 2.0 * s)

## 键位提示行的字号 = **能把整行装进 SCRUB_HINT_W 的最大那一档**（从 SCRUB_HINT_FS 往下退）。
## 为什么要有它：这一行是一条**会被人继续往上加东西**的清单（历史上已经加过一轮 Home/L/O/F5-F8），
## 而它一旦超宽就折行、再被框高静默裁掉——`RichTextLabel.scroll_active=false` 不报错、不出滚动条。
## 于是"字号"和"这行有多长"是一对**必须一起成立**的约束，写死其中任何一个都会在下一次编辑时静默破掉。
## 测的是**剥掉 BBCode 之后**的纯文本：只剥已知标签，`[ ] 跳天` 里那对方括号必须留着（它是画出来的字）。
func _fit_hint_fs(fnt: Font, bb: String) -> int:
	var re := RegEx.new()
	re.compile("\\[/?(?:color|b|i|u|s|url|font|img)[^\\]]*\\]")
	var plain := re.sub(bb, "", true)
	var s := SCRUB_HINT_FS
	while s > SCRUB_HINT_FS_MIN and fnt.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > SCRUB_HINT_W:
		s -= 1
	return s

func _mk_label(layer: CanvasLayer, fnt: Font, fsize: int, pos: Vector2, sz: Vector2) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.scroll_active = false
	l.add_theme_font_override("normal_font", fnt)
	l.add_theme_font_size_override("normal_font_size", fsize)
	l.position = pos
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	return l

func _on_tick(_t: int) -> void:
	if _digest_at > 0 and Sim.tick_no >= _digest_at:      # dev 硬门：到点写 digest 并退出（两跑必在同一 tick 比较）
		_digest_at = -1
		_write_digest()
		get_tree().quit()
		return
	if _demo_mode:
		_demo_tick()               # --player-demo：剧本驱动玩家（确定性）
	if _demo_cam:
		_demo_cam_apply()          # --demo-cam：演示镜头（纯 View；tick 驱动，不读墙钟）
	_modulate.color = _daylight(Sim.time_of_day())
	_max_tick = maxi(_max_tick, Sim.tick_no)
	_sync_goals()
	_sync_story()
	_update_status()
	_update_scrubber()
	_update_obs()

# ── 演示镜头（--demo-cam）─────────────────────────────────────────────────
## 每 tick 一次：把相机放到轨迹上，并**按取景**决定选中谁。
## ★"选中谁"跟着取景走，不是取景跟着人走——后者会让镜头去追一个每 tick 跳一格的目标（抖、且不可闭式复现），
##   更要紧的是它会把"镜头需要什么"变成一条对仿真的诉求。**镜头制造机会，不点名要人。**
func _demo_cam_apply() -> void:
	if _probe == null or not _demo_cam:
		return
	if not bool(_probe.demo_cam):        # 人手动过相机 → Probe 自己把 demo_cam 关了，这里跟着退场
		_demo_cam = false
		return
	var st: Dictionary = _probe.demo_apply(Sim.tick_no, _vp())
	if st.is_empty():
		return
	# ── 室内插曲（本棒新增）───────────────────────────────────────────────
	# `demo_apply` 只描述"相机在小镇平面的哪、多大"，它没有"在哪个 Space"这一维
	# ⇒ 光有它，镜头**结构上进不了屋**（docs/74 §五·2 实测：45 帧里 0 帧室内取景）。
	# 这几行在它**之后**覆盖：切 active Space + 用与 --shot-fit 同一份 `_fit_active_space` 摆机位。
	# 仍是 tick 的**闭式函数**：窗口来自常量表 DEMO_INTERIOR，进/出只发生在窗口边界那一 tick。
	var inter: Dictionary = _demo_interior_at(int(st["t"]))
	var sp_id := String(inter.get("space", "town"))
	var fl_id := String(inter.get("floor", "outdoor"))
	if String(_probe.active_space) != sp_id or String(_probe.active_floor) != fl_id:
		_demo_enter(sp_id, fl_id)
		if sp_id == "town":
			# 出屋那一 tick：`set_space` 把相机拽到了 town bounds 的正中，而这一拍的机位在别处
			# ⇒ 不放回去就会有恰好一帧的跳切（下一 tick 才被 demo_apply 纠正）。
			_probe.cam.position = Vector2(st["pos"])
			_probe.cam.zoom = Vector2.ONE * float(st["zoom"])
	# 有效机位：室内那几拍相机由 fit 决定，`st` 里那一份是小镇平面的、已被覆盖 ⇒ 选人/trace 都要读有效值。
	var cz := float(st["zoom"])
	var cpos := Vector2(st["pos"])
	if sp_id != "town":
		_fit_active_space(false)
		cz = _probe.cam.zoom.x
		cpos = _probe.cam.position
	# 只在越过名牌门之后才选人：全景档（zoom≈0.229）名字/气泡根本不画，选了观察台会与画面对不上。
	# 阈值**读 WorldView 的原件**而不是抄一个 0.45——抄一份就一定会漂（docs/41 §4 的同一条教训）。
	var sel := ""
	if cz >= WorldViewScript.LABEL_MIN_ZOOM:
		sel = _demo_pick(cpos, cz, sp_id, fl_id)
	else:
		_demo_sel_hold = 0               # 拉回全景 ⇒ 清空选中（那一档名牌根本不画，观察台会与画面对不上）
	if sel != _selected_id:
		_selected_id = sel
		_update_obs()
	if _demo_trace != null:
		# 末两列 = 被选中者此刻的【屏幕坐标】。存在的理由：判断"他是不是被不透明 HUD 挡住了"
		# 只能在屏幕空间做，而这一条正是 D5 把世界层名牌收进焦点集合之后最要命的失败模式
		# （观察台亮着某人、画面里找不到他）。没有这两列就只能靠肉眼翻帧去猜。
		# 第 11 列（本棒加）= 此刻的 space/floor：没有它，"这一拍在不在屋里"只能靠翻帧去猜。
		var sp := Vector2(-1, -1)
		if sel != "":
			var sa := Sim.get_agent(sel)
			if not sa.is_empty():
				sp = (Vector2(float(sa["pos"].x) * 48.0 + 24.0, float(sa["pos"].y) * 48.0 + 24.0) \
					- cpos) * cz + _vp() * 0.5
		_demo_trace.store_line("%d|%s|%.4f|%.5f|%.2f|%.2f|%d|%s|%.1f|%.1f|%s/%s" % [
			Sim.tick_no, String(st["shot"]), float(st["u"]), cz,
			cpos.x, cpos.y,
			1 if cz >= WorldViewScript.LABEL_MIN_ZOOM else 0, sel, sp.x, sp.y, sp_id, fl_id])
		_demo_trace.flush()

## 演示镜头的【室内插曲】表：`t` 是 ProbeController 那条 2510-tick 循环里的位置（`demo_apply` 返回的 `t`）。
## ★两段都**落在对应定场镜头的中段**（`cafe` 是 t∈[1200,1620)、`work` 是 t∈[1800,2180)）：
##   先在门外看见这栋楼，再进屋，再退回小镇——而不是凭空跳进一个不知道在哪的房间。
## ★为什么不写进 ProbeController 的 `DEMO_SHOTS`：那张表只有"相机在哪/多大"，没有"在哪个 Space"；
##   而进屋还要动 `SpaceGraph` 查 bounds、动 `WorldView` 换渲染路径——这两样本来就由 Main 装配。
##   （ProbeController 也不在本棒的 owns 里，一个字节都没动。）
## ★这两间屋是 R2 的外壳分色 + S3 的家具分化**都拍得到**的两档：
##   `cafe` = commercial（杯碟架）、`work` = workshop（工具架），墙色与货架画法都不同。
##
## ⚠️ **屋里有没有人是量出来的，不是想出来的**（seed 20260626，tick 20..2540 每 20 一采、共 127 个采样点）：
##   `home/1f` 101/127 有人（79.5%）· `cafe/1f` 30/127（23.6%）· **`work/1f` / `shop/1f` / `library/1f` 恒为 0**。
##   ⇒ **工坊那一拍必然是一间空屋**——它照样值得拍（工具架/工作台/木箱都是 R2+S3 的产出），
##     但"演示里的室内会有人在活动"这句话对它是**假的**，写在这里免得后人当 bug 查。
##   ⇒ 想要"有人的室内"，唯一够密的是 `home/1f`；本棒没有选它，因为镜头此刻看的是咖啡馆/工坊，
##     从工坊外景切进一间民居会让"进的是你正在看的那栋楼"这条读法断掉。这是**取舍**，不是遗漏。
##   咖啡馆那一段刻意压到定场镜头的后半（1420–1610）：seed 20260626 的第一圈里 1520–1600 正好有人。
##   **这不是可依赖的性质**——占用是绝对 tick 的函数，而窗口是 `tick % 2510` 的函数，换 seed / 第二圈就未必。
const DEMO_INTERIOR := [
	{"t0": 1420, "t1": 1610, "space": "cafe", "floor": "1f"},   # 在 `cafe` 定场镜头 [1200,1620) 的后半
	{"t0": 1900, "t1": 2120, "space": "work", "floor": "1f"},   # 在 `work` 定场镜头 [1800,2180) 的中段
]

## t → 该进哪间屋（{} = 留在小镇）。纯查表，无状态。
func _demo_interior_at(t: int) -> Dictionary:
	for e in DEMO_INTERIOR:
		if t >= int(e["t0"]) and t < int(e["t1"]):
			return e
	return {}

## 演示镜头切 Space：**纯 View**（`set_space` 只动 Probe 自己的 bounds/相机，不移动任何 Agent、不写 Sim）。
## `queue_redraw` 是必须的：docs/41 §6 盲区⑨——世界层只从 `Sim.ticked`/`Sim.agent_changed`/渲染位脏三处排重画，
## 而 `--shot` 把 `auto_run=false` ⇒ 定格路径上 `Sim.ticked` 不会来，画面会停在旧空间而 HUD 说你已经进屋了。
func _demo_enter(sid: String, fid: String) -> void:
	if _probe == null or _sg == null:
		return
	if sid != "town" and not _sg.has_space(sid):
		return                                  # 数据里没这间屋 ⇒ 静默留在小镇（同"缺文件即关掉整个子系统"的纪律）
	_probe.set_space(sid, fid, _sg.bounds_px(sid))
	if _view != null:
		_view.queue_redraw()

## 取景内选人：**对 Sim 只读**。候选 = 此刻真的在画面里的居民；从中按 HRW 取一个（理由见 DEMO_SEL_HOLD）。
## 每 tick 重算（而不是"在分镜边界记一次"）是刻意的：只有这样它才是 tick 的纯函数，
## `--shot --warmup-tick T` 才能复现录屏在 tick T 选中的那个人。
## `space`/`floor`：镜头此刻在哪一层。**候选必须与镜头同层**——原先写死 `!= "town"` 就 continue，
## 于是室内那几拍会去选一个站在镇上、画面里根本没有的人（"观察台亮着某人、画面里找不到他"的同一种病）。
## 室内 Agent 的 `pos` 是**该层的局部格**，而室内 Space 的 bounds 从原点起（见 WorldView `_draw_space_placeholder`）
## ⇒ `pos*48+24` 这条映射在两种层上逐字通用，不需要第二套坐标。
func _demo_pick(center: Vector2, zoom: float, space := "town", floor_id := "outdoor") -> String:
	# ① 迟滞：现在这位还在安全框里、且没到换人节奏 → 就让镜头陪他把这段待完
	var keep := _demo_box(zoom, DEMO_KEEP_MARGIN)
	if _selected_id != "" and _demo_sel_hold < DEMO_SEL_HOLD and _demo_in_frame(_selected_id, center, keep, space, floor_id):
		_demo_sel_hold += 1
		return _selected_id
	# ② 换人：候选 = 此刻离安全框边缘还有余量的居民；按 HRW 取一个（键在一个窗口内恒定 ⇒ 不会逐 tick 跳）
	var box := _demo_box(zoom, DEMO_IN_MARGIN)
	var c := center + Vector2(box[0])
	var half: Vector2 = box[1]
	var k := "#" + str(Sim.tick_no / DEMO_SEL_HOLD)
	var best := ""
	var best_h := -1
	for ag in Sim.agents:
		if ag.get("is_player", false):
			continue
		if String(ag.get("space", "town")) != space or String(ag.get("floor", "outdoor")) != floor_id:
			continue                     # 人不在镜头这一层 ⇒ 画面里看不见他，选了就是观察台与画面对不上
		var d := (Vector2(float(ag["pos"].x) * 48.0 + 24.0, float(ag["pos"].y) * 48.0 + 24.0) - c).abs()
		if d.x > half.x or d.y > half.y:
			continue
		var h := Sim.fnv1a32(String(ag["id"]) + k)
		if h > best_h:                   # id 互异 ⇒ 不可能同值；Sim.agents 序稳定 ⇒ 完全确定
			best_h = h
			best = String(ag["id"])
	_demo_sel_hold = 0
	return best

## 取景半尺寸（世界 px）：视口的一半按缩放折回世界，再各留一圈屏幕空间的余量。
## 取景安全框（屏幕 px）：视口**减掉不透明 HUD**。
## ★这不是保守起见，是量出来的：第一版用整个视口判定"在画面里"，于是被选中的人可以站在
##   观察台面板背后——正在展示他卷宗的那块板子把他本人挡住了。实测（trace 末两列＝被选中者
##   的屏幕坐标）：改前 **3645/20414 tick = 选中时长的 17.9%** 的被选中者落在不透明 HUD 之下，
##   其中 2120 tick 就压在观察台那块板子底下（典型：t=319 mei 在 x=981，板子左缘 978）。改后为 0。
##   改前没人看得出来：世界层那时给每个人都画名牌，画面里另有三四个名字顶着。
##   D5 把世界层名牌收进"焦点集合"之后，被选中者是**唯一**保证画名牌的人 ⇒ 这一条从
##   "不好看"升级成"观察台亮着某人、画面里找不到他"。两棒相交才暴露，单棒都测不到。
## 左下角的纪事播报是**半透明** scrim（D5 实测：世界层的东西会透上来）⇒ 不从安全框里扣，
## 扣掉它会把每一次选人都往画面右侧偏。这里只扣真正挡人的：右侧观察台、顶栏、底部时间轴。
const DEMO_SAFE_L := 24.0
const DEMO_SAFE_R := 966.0        # 观察台完整卷宗左缘 x=978 再留 12 余量
const DEMO_SAFE_T := 52.0         # 顶栏
const DEMO_SAFE_B := 664.0        # 时间轴槽上沿

## 安全框 → (相对相机中心的世界偏移, 世界半宽高)。margin 越大框越小（进场比留场严）。
func _demo_box(zoom: float, margin: float) -> Array:
	var vp := _vp()
	var z := maxf(zoom, 0.01)
	# 安全框按设计基准 1280x768 定义，跟着实际视口一起缩放（否则换分辨率就偏）。
	var sx := vp.x / 1280.0
	var sy := vp.y / 768.0
	var l := DEMO_SAFE_L * sx + margin
	var r := DEMO_SAFE_R * sx - margin
	var t := DEMO_SAFE_T * sy + margin
	var b := DEMO_SAFE_B * sy - margin
	if r <= l or b <= t:                      # 极端窄视口/极端 margin：退回整个视口，别把候选集合清空
		return [Vector2.ZERO, vp * 0.5 / z]
	var off := Vector2((l + r) * 0.5 - vp.x * 0.5, (t + b) * 0.5 - vp.y * 0.5) / z
	return [off, Vector2(r - l, b - t) * 0.5 / z]

## 某人此刻是否在【安全框】里（只读 Sim）。center=相机世界坐标，box=_demo_box 的返回。
func _demo_in_frame(id: String, center: Vector2, box: Array, space := "town", floor_id := "outdoor") -> bool:
	var ag := Sim.get_agent(id)
	if ag.is_empty() or String(ag.get("space", "town")) != space or String(ag.get("floor", "outdoor")) != floor_id:
		return false
	var p := Vector2(float(ag["pos"].x) * 48.0 + 24.0, float(ag["pos"].y) * 48.0 + 24.0)
	var d := (p - (center + Vector2(box[0]))).abs()
	var half: Vector2 = box[1]
	return d.x <= half.x and d.y <= half.y

## 人手一碰相机就退出演示轨迹（键盘侧；鼠标/触屏侧在 ProbeController.handle_input 里）。
func _demo_off() -> void:
	if _demo_cam:
		_demo_cam = false
		if _probe != null:
			_probe.demo_cam = false

## 昼夜色调：按一天进度 0..1 在几个色停之间插值（夜蓝→晨暖→白昼→暮橙→夜蓝）。
func _daylight(tod: float) -> Color:
	var stops := [
		[0.0, Color(0.42, 0.47, 0.80)], [0.24, Color(0.45, 0.48, 0.78)],
		[0.30, Color(1.0, 0.86, 0.72)], [0.38, Color(1, 1, 1)],
		[0.68, Color(1, 1, 1)], [0.78, Color(1.0, 0.80, 0.62)],
		[0.86, Color(0.5, 0.52, 0.82)], [1.0, Color(0.42, 0.47, 0.80)],
	]
	for i in range(stops.size() - 1):
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if tod >= float(a[0]) and tod <= float(b[0]):
			var f := (tod - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return (a[1] as Color).lerp(b[1] as Color, f)
	return Color(1, 1, 1)

## 异步探测端上模型再启用（够快切 want，太慢/坏留 logic 地板）。探测期间 backend/requested 都置 logic →
## 镇子跑地板不冻/不黑屏（真机 1.9GB 模型 load+2 暖发要 ~85s）。boot 与运行期 toggle 共用此路。
func _probe_and_activate(want: String) -> void:
	if Sim.agents.is_empty():
		return
	AIBackend.backend = "logic"                  # 探测期间跑地板；两者都 logic → decide() 的安全点切换不误动
	AIBackend.backend_requested = "logic"
	_sync_backend_btn()
	_push("[color=#9ad0ff]端上模型加载+探测中…（镇子先跑 logic 地板，够快才切 %s）[/color]" % want)
	var pag: Dictionary = Sim.agents[0]
	await AIBackend.probe_capability(want, pag, Sim.agent_candidates(pag), Sim._context(pag), func(info):
		_push("[color=#9ad0ff][算力探测] %s · p50=%dms · 后端 → %s[/color]" % [String(info.get("tier", "?")), int(info.get("p50_ms", 0)), String(info.get("backend", "logic"))]))
	_sync_backend_btn()

## 轮换后端（仅含 available_backends()；手机 = logic→slm→mock）。logic/mock 即时切；slm/llm 走异步探测。
func _on_toggle_backend() -> void:
	var avail := AIBackend.available_backends()
	var i := avail.find(AIBackend.backend_requested)
	var nxt := String(avail[(i + 1) % avail.size()]) if i >= 0 else "logic"
	AIBackend.request_backend(nxt)               # 记录意图 + 存 user://settings.cfg；下次启动也记住
	if nxt == "slm" or nxt == "llm":
		_push("[color=#9ad0ff]后端 → %s（探测端上模型中…够快启用，太慢留 logic）[/color]" % nxt)
		_probe_and_activate(nxt)                 # 异步：镇子跑地板探测，够快才启用（不再静默 100% 超时冻镇）
	else:
		_sync_backend_btn()
		_push("[color=#9ad0ff]后端 → %s[/color]" % nxt)

func _sync_backend_btn() -> void:
	if _backend_btn == null:
		return
	_backend_btn.text = "推理 %s" % AIBackend.backend_requested

# ── ⚙ 设置面板（NPC 数量 / 速度 / 后端；持久化到 user://settings.cfg 的 [sim] 段）───────────
func _build_settings(layer: CanvasLayer, fnt: Font) -> void:
	_settings_panel = ColorRect.new()
	_settings_panel.color = Color(0.05, 0.06, 0.09, 0.96)
	# 版式（数字都是 player_touch_test.gd 用 get_combined_minimum_size() 实测的，不是估的）：
	# 加了「玩家模式」这一行后真实内容高 474px。改动前是 9 个子项 / separation 16 → 内容 454px，
	# 而老底板 424px 里 vb 从 y=20 起只有 404px 可用 —— 超 50px，「关闭 Close」钮实际挂在暗底板【外面】。
	# 这里把 separation 收到 12、底板加到 520（20+474+20=514 ≤ 520），
	# 并把纵向居中常量从 168 改成 124（=(768-520)/2），仍是"设计基准 + 增量"的写法。
	_settings_panel.position = Vector2(430, 124)
	_settings_panel.size = Vector2(420, 520)
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 面板挡住背后世界点选
	_settings_panel.visible = false
	layer.add_child(_settings_panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(24, 20)
	vb.custom_minimum_size = Vector2(372, 480)
	vb.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(vb)

	var title := Label.new()
	title.text = "设置 Settings"
	title.add_theme_font_override("font", fnt)
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)

	# 存档 / 读档（R0-2）：手机没有 F5/F8，从这里进
	var rsl := _settings_row(vb, fnt, "存档 Save")
	var bsave := _mk_sbtn(fnt, "存档 (F5)", 130)
	bsave.pressed.connect(_quick_save)
	rsl.add_child(bsave)
	var bload := _mk_sbtn(fnt, "读档 (F8)", 130)
	bload.pressed.connect(_quick_load)
	rsl.add_child(bload)

	# 玩家模式（gameplay M1）。此前【只有】--player 启动旗标 —— 出货目标是 Android APK，手机上没有 CLI，
	# 于是 7 个玩家动词在真出货平台上一个都够不着。这一行是把它们解锁的唯一入口。
	var rpl := _settings_row(vb, fnt, "玩家模式 Player")
	_player_btn = _mk_sbtn(fnt, "—", 200)
	_player_btn.pressed.connect(_toggle_player_mode)
	rpl.add_child(_player_btn)
	_sync_player_btn()

	# 后端
	var rb := _settings_row(vb, fnt, "后端 Backend")
	var bcyc := _mk_sbtn(fnt, AIBackend.backend_requested, 160)
	bcyc.pressed.connect(func():
		_on_toggle_backend()
		bcyc.text = AIBackend.backend_requested)
	rb.add_child(bcyc)

	# SLM 模型（扫 Documents/Download/user:// 里的 *.gguf，点按循环手选；换模型 A/B 用）
	var rm := _settings_row(vb, fnt, "SLM 模型")
	_model_btn = _mk_sbtn(fnt, "—", 200)
	_model_btn.pressed.connect(_cycle_model)
	rm.add_child(_model_btn)
	_rescan_models()

	# NPC 数量
	var rn := _settings_row(vb, fnt, "NPC 数量")
	var minus := _mk_sbtn(fnt, "-", 46)
	minus.pressed.connect(func(): _apply_npc(-2))
	rn.add_child(minus)
	_npc_val = Label.new()
	_npc_val.add_theme_font_override("font", fnt)
	_npc_val.add_theme_font_size_override("font_size", 18)
	_npc_val.custom_minimum_size = Vector2(60, 0)
	_npc_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rn.add_child(_npc_val)
	var plus := _mk_sbtn(fnt, "+", 46)
	plus.pressed.connect(func(): _apply_npc(2))
	rn.add_child(plus)
	_sync_npc_val()

	# 速度
	var rs := _settings_row(vb, fnt, "速度 Speed")
	for sv in [0.0, 1.0, 2.0, 4.0, 8.0]:
		var b := _mk_sbtn(fnt, ("暂停" if sv == 0.0 else "%d×" % int(sv)), 52)
		b.pressed.connect(func(): _set_speed(sv))
		rs.add_child(b)

	# 性能监控（dev）
	var rp := _settings_row(vb, fnt, "性能监控 Dev")
	var pbtn := _mk_sbtn(fnt, "开/关 (F3)", 150)
	pbtn.pressed.connect(_toggle_perf)
	rp.add_child(pbtn)

	var hint := Label.new()
	hint.text = "改 NPC 数量 / 玩家模式 → 同种子重开小镇（确定性）"
	hint.add_theme_font_override("font", fnt)
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.66, 0.7, 0.82)
	vb.add_child(hint)

	var close := _mk_sbtn(fnt, "关闭 Close", 130)
	close.pressed.connect(func(): _settings_panel.visible = false)
	vb.add_child(close)

func _settings_row(vb: VBoxContainer, fnt: Font, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.add_theme_font_override("font", fnt)
	l.add_theme_font_size_override("font_size", 16)
	l.custom_minimum_size = Vector2(148, 0)
	row.add_child(l)
	vb.add_child(row)
	return row

func _mk_sbtn(fnt: Font, txt: String, w: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_override("font", fnt)
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(w, 40)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _toggle_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = not _settings_panel.visible
		if _settings_panel.visible:
			_rescan_models()          # 每次打开重扫（用户可能刚拷了新 gguf 进 Documents）

## 扫一遍可放模型的目录，对齐当前选中项。
func _rescan_models() -> void:
	_models = AIBackend.list_models()
	_model_idx = _models.find(AIBackend.slm_model_override)
	if _model_idx < 0:
		_model_idx = 0
	_sync_model_btn()

func _sync_model_btn() -> void:
	if _model_btn == null:
		return
	if _models.is_empty():
		_model_btn.text = "无 gguf(放 Documents)"
	else:
		var nm := String(_models[_model_idx]).get_file().trim_suffix(".gguf")
		if nm.length() > 22:
			nm = nm.substr(0, 21) + "…"
		_model_btn.text = nm

## 循环选下一个 gguf → 记住 + 存盘 + 卸旧模型（下次 slm 决策按新路径重载）。
func _cycle_model() -> void:
	if _models.is_empty():
		_rescan_models()              # 可能刚放进去，再扫一次
		if _models.is_empty():
			return
	_model_idx = (_model_idx + 1) % _models.size()
	AIBackend.set_model_path(String(_models[_model_idx]))
	_sync_model_btn()
	_push("[color=#9ad0ff]SLM 模型 → %s（下次 slm 决策重载）[/color]" % String(_models[_model_idx]).get_file())

func _sync_npc_val() -> void:
	if _npc_val != null:
		_npc_val.text = str(_npc_target)

func _sync_player_btn() -> void:
	if _player_btn != null:
		_player_btn.text = "开（你已入镇）" if _player_mode else "关（只观察）"

## 玩家模式开关（⚙ 面板）。
## ★这是 docs/41 §3「会移动 digest 的改动」里的【受控动作】：开 = Sim.add_player() 把玩家写进社交图，
##   历史从此不同——这是玩家自己按下的意图，不是回归。**关着的时候必须逐字节等于金标**（默认 false，
##   且 headless CI 走 Harness/DetGate 根本不经本文件）。
## 为什么两个方向都重开世界：引擎侧【没有】Sim.remove_player()（docs/43 §三-C3 要求不得改 Sim.gd），
##   所以"退镇"只能靠同种子 start_new。两个方向对称走同一条路 → 开/关任意次数后，
##   同 (seed, npc_count, player) 三元组必然给出同一部历史，仍然可复现。走的正是 _apply_npc 那条既有路径。
func _toggle_player_mode() -> void:
	_player_mode = not _player_mode
	Sim.start_new(_seed)
	Sim.auto_run = true
	if _player_mode:
		Sim.add_player(_player_spawn_override)
	_selected_id = ""
	_reconcile_locked_ortho_c1()
	_max_tick = 0
	_save_sim_setting("player", _player_mode)       # 手机上没有 CLI：下次启动记住（--player 显式给出时不读这里）
	_sync_player_btn()
	_sync_action_bar()                              # 动作条随之显隐
	_relayout_hud()                                 # 顶栏从 1 行变 2 行（或反过来）
	_push("[color=#9ad0ff]玩家模式 → %s（同种子第 %d 号重开小镇）[/color]" % [("开" if _player_mode else "关"), _seed])
	_update_status()
	_update_obs()
	_update_scrubber()
	_rebuild_feed()   # 世界换了：播报必须照新的（空）event_log 重建，否则屏幕上还留着上一条时间线的字

## 改 NPC 数量 → 用同种子重开小镇（确定性；spawn_count=目标总数，克隆到 N）。
func _apply_npc(delta: int) -> void:
	var n := clampi(_npc_target + delta, 6, 60)
	if n == _npc_target:
		return
	_npc_target = n
	Sim.spawn_count = n
	Sim.start_new(_seed)
	Sim.auto_run = true
	if _player_mode:
		Sim.add_player(_player_spawn_override)
	_npc_target = maxi(6, Sim.agents.size() - (1 if _player_mode else 0))   # 低于基础 cast 时克隆环不减→回读实际数，显示不骗人
	_selected_id = ""
	_reconcile_locked_ortho_c1()
	_max_tick = 0
	_save_sim_setting("npc_count", n)
	_sync_npc_val()
	_update_status()
	_update_obs()
	_update_scrubber()
	_rebuild_feed()   # ★本行是 brief 之外的顺手修（同文件、一行）：start_new 已清空 event_log，
	                  # 而播报此前不重建 → 改完 NPC 数量，屏幕上继续讲一段已经被抹掉的历史。
	                  # 与 _after_jump/_after_load/_toggle_player_mode 三处同一纪律。

func _set_speed(v: float) -> void:
	if v <= 0.0:
		Sim.running = false
	else:
		Sim.running = true
		Sim.speed = v
		_save_sim_setting("speed", v)
	_update_status()

func _save_sim_setting(key: String, val: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")   # 保留其他键（backend 等）
	cfg.set_value("sim", key, val)
	cfg.save("user://settings.cfg")

## 纯视图偏好（观察台档位…）。刻意与 [sim] 分段：[sim] 里的键都会改变世界（人数/玩家/速度），
## 而这一段一个都不会 —— 分开写，后来人一眼看得出哪一段动得了 digest。
func _save_ui_setting(key: String, val: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("ui", key, val)
	cfg.save("user://settings.cfg")

func _toggle_perf() -> void:
	_perf_on = not _perf_on
	if _perf != null:
		_perf.get_parent().visible = _perf_on     # 连同背景 panel 一起显隐
	_perf_last_tick = Sim.tick_no
	_perf_dt_acc = 0.0

## dev 性能 overlay 每帧刷（FPS 要每帧才平滑；关时早退，零开销）。
func _process(dt: float) -> void:
	if _locked_ortho_c1 != null:
		_locked_ortho_c1.apply_fixed_frame(_vp(), _probe.HOME_PAD)
	_flush_scrub()                                 # 时间轴拖动合并点：每【渲染帧】至多一次 goto_tick
	if _obs_fit_frames > 0:
		_obs_fit_frames -= 1
		if _obs_fit_frames == 0:
			_obs_fit_report()
			return
	if not _perf_on or _perf == null:
		return
	_perf_dt_acc += dt
	if _perf_dt_acc >= 0.5:                        # 每 0.5s 采一次 tick 率
		_perf_rate = float(Sim.tick_no - _perf_last_tick) / _perf_dt_acc
		_perf_last_tick = Sim.tick_no
		_perf_dt_acc = 0.0
	var fps := Engine.get_frames_per_second()
	var frame_ms := (1000.0 / fps) if fps > 0.0 else 0.0        # 帧时由 FPS 反推，直观一致（TIME_PROCESS 在导出里会误导）
	var membytes := OS.get_static_memory_usage()               # 导出/release 里内存追踪常被编译掉→0，此时显示 n/a 而非骗人的 0
	var memtxt := ("%.0f MB" % (membytes / 1048576.0)) if membytes > 0 else "n/a"
	var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var st: Dictionary = AIBackend.stats
	_perf.text = "[color=#7ed957]● PERF[/color]  FPS %d · %.1fms\n内存 %s · 对象 %d · 节点 %d · 绘制 %d\nNPC %d · tick %d (%.1f/s ×%.0f)\n后端 [color=#ffd166]%s[/color] · 并发 %d\nLLM 发起 %d · 成功 %d · 超时 %d · 无效 %d" % [
		fps, frame_ms, memtxt, objs, nodes, draws,
		Sim.agents.size(), Sim.tick_no, _perf_rate, Sim.speed,
		AIBackend.backend, AIBackend._inflight,
		int(st.get("fired", 0)), int(st.get("landed", 0)), int(st.get("timeout", 0)), int(st.get("bad_parse", 0))]

func _update_status() -> void:
	if _status == null:
		return
	_sync_action_bar_context()
	var tod := Sim.time_of_day()
	var mins := int(tod * 24.0 * 60.0)
	var clock := "%02d:%02d" % [mins / 60, mins % 60]
	var hh := mins / 60
	var phase := "夜 night"
	if hh >= 5 and hh < 11: phase = "晨 morning"
	elif hh >= 11 and hh < 17: phase = "昼 day"
	elif hh >= 17 and hh < 21: phase = "暮 evening"
	var spd := ("×%.0f" % Sim.speed) if Sim.running else "已暂停"
	var btxt := "推理 %s" % AIBackend.backend                                        # 当前生效后端（诚实显示：可能已被降级/正在排队切换）
	if AIBackend.backend != AIBackend.backend_requested:
		btxt += "→%s…" % AIBackend.backend_requested                              # 切换排队中（等在飞请求清空）
	var sn := ("%s " % Sim.season_today) if Sim.season_today != "" else ""          # Wave 3b 季节（贴在天气前）
	var wx := ("  ·  %s%s" % [sn, Sim.weather_today]) if (Sim.weather_today != "" or sn != "") else ""   # Wave 1c 天气 + 3b 季节
	var etxt := ""                                                                # Wave 3a 选举：状态栏显示最近一次表决结果
	if not Sim.last_election.is_empty():
		var le: Dictionary = Sim.last_election
		etxt = "  ·  选举 %s %s %d:%d" % [String(TOPIC_LABEL.get(String(le["topic"]), le["topic"])), ("通过" if bool(le["pass"]) else "否决"), int(le["yea"]), int(le["nay"])]
	var meets_active := 0
	for c in Sim.commitments:
		if String(c["status"]) == "active":
			meets_active += 1
	var conf_active := 0
	for c in Sim.conflicts:
		var s := String(c["status"])
		if s == "simmering" or s == "escalated" or s == "confronted" or s == "lingering":
			conf_active += 1
	var ptxt := ""
	if _player_mode:
		var pl: Dictionary = Sim.get_agent("player")
		if not pl.is_empty():
			var pmeets := []
			for c in Sim.commitments:
				if String(c["status"]) == "active" and (String(c["a"]) == "player" or String(c["b"]) == "player"):
					var other := String(c["b"]) if String(c["a"]) == "player" else String(c["a"])
					pmeets.append("和%s约在%s(剩%dt)" % [Sim._name(Sim.get_agent(other)), Sim._area_label_id(String(c["area"])), int(c["deadline"]) - Sim.tick_no])
			if _player_in_warehouse_observatory():
				ptxt = "\n[color=#80e1ff]你：东海货仓 · 货运观测室（只读）  点右侧柜台查泊位/回执  卸货由码头工执行[/color]"
			else:
				var vkeys := []
				for v in PLAYER_VERBS:                                             # 单一真源：与动作条按钮同表，不再各写一份
					vkeys.append("%s%s" % [String(v["key"]), String(v["label"])])
				var cargo_hint := _player_cargo_hint(pl)
				ptxt = "\n[color=#ffd700]你：礼物×%d  WASD移动  选中居民后 %s C聊天（或点下方动作条）%s[/color]%s" % [
					int(pl["inventory"].get("gift", 0)), " ".join(vkeys), ("  约定：" + "；".join(pmeets)) if not pmeets.is_empty() else "", cargo_hint]
	_status.text = "[color=#e6e9f2]小镇有灵 Living Town  ·  第 %d 天 %s %s%s%s  ·  %s  ·  %s  ·  NPC %d  ｜  事件 %d  约会 %d(活%d)  冲突 %d(活%d)[/color]%s" % [
		Sim.day, clock, phase, wx, etxt, spd, btxt, Sim.agents.size(), Sim.event_log.size(), Sim.commitments.size(), meets_active, Sim.conflicts.size(), conf_active, ptxt]

## 玩家站在真实 port_dock 三格内才显示；只读 Sim 的 manifest 投影，不制造“玩家能亲手卸货”的假按钮。
func _player_cargo_hint(pl: Dictionary) -> String:
	var port: Dictionary = Sim.world.get("objects", {}).get("port_dock", {})
	var pp: Vector2i = pl.get("pos", Vector2i(-99, -99))
	var raw_pos = port.get("pos", Vector2i(-99, -99))
	var port_pos := Vector2i(-99, -99)
	if raw_pos is Vector2i:
		port_pos = raw_pos
	elif raw_pos is Array and raw_pos.size() >= 2:
		port_pos = Vector2i(int(raw_pos[0]), int(raw_pos[1]))
	if port_pos.x < 0 or absi(pp.x - port_pos.x) + absi(pp.y - port_pos.y) > 3:
		return ""
	var st: Dictionary = Sim.cargo_status_for_node("port_dock")
	if String(st.get("state", "")) == "empty":
		return "  [color=#9fb8c8]港：暂无待卸货物[/color]"
	if String(st.get("state", "")) == "invalid":
		return "  [color=#ffb06a]港：货单异常·暂停卸货[/color]"
	var worker := Sim._name(Sim.get_agent(String(st.get("worker_id", ""))))
	if worker == "": worker = "码头工"
	var state_label: String = String({
		"ready": "待卸", "working": "卸货中", "blocked_capacity": "仓位不足", "blocked_funds": "镇库不足",
	}.get(String(st.get("state", "")), "待处理"))
	var backlog := ""
	if int(st.get("ready_count", 0)) > 1:
		backlog = "·共%d单%d件" % [int(st.get("ready_count", 0)), int(st.get("ready_qty", 0))]
	return "  [color=#80e1ff]港：%s×%d %s%s·%s负责[/color]" % [String(st.get("good", "货物")), int(st.get("qty", 0)), state_label, backlog, worker]

# ── 观察台 / 时间轴 ────────────────────────────────────────────────────────
func _update_scrubber() -> void:
	if _scrub_fill == null:
		return
	var m := maxi(1, _max_tick)
	var f := clampf(float(Sim.tick_no) / float(m), 0.0, 1.0)
	var w := _sx1 - _sx0
	_scrub_fill.position = Vector2(_sx0, _sy)
	_scrub_fill.size = Vector2(w * f, SCRUB_H)
	_scrub_handle.position = Vector2(_sx0 + w * f - 2.0, _sy - 4.0)

## W8 断言（`--obs-fit`）：**逐个居民**把卷宗排进真实控件，量 `get_content_height()` vs 可用高度。
## 为什么必须用真实控件而不是自己数行：这正是 W8 本身的病 —— `OBS_MAX_LINES` 数的是**逻辑行**，
## 而面板截的是**视觉行**，中文还会折行。任何"自己数一遍"的量具都会复刻同一个错误。
## 用法（最坏一档：N=60 + 玩家在镇 + 完整卷宗 + 跑够天数让记忆/信念/冲突都长满）：
##   godot --headless --path game -- --obs-fit --agents 60 --player --warmup 30
func _obs_fit_report() -> void:
	if _obs == null:
		print("[obs-fit] 观察台未建成 —— 无法测量")
		get_tree().quit(1)
		return
	var keep := _selected_id
	var keep_exp := _obs_expanded
	var ids: Array = []
	for ag in Sim.agents:
		ids.append(String(ag["id"]))
	ids.sort()
	# 两档都要扫：名片档窄（240px）⇒ 同一句话在那里折得更凶，"卷宗装得下"推不出"名片档装得下"。
	var worst := 0.0          # 最小余量那一格的内容高度
	var avail := 0.0          # 同一格的可用高度
	var slack := INF          # 全网格最小余量（可用 − 内容）；两档的可用高度不同，故必须比余量而不是比高度
	var worst_id := ""
	var over := 0
	for expanded in [false, true]:
		_obs_expanded = expanded
		_sync_obs_panel()
		var cap: float = _obs.size.y
		for id in ids:
			_selected_id = String(id)
			_update_obs()
			var h := _obs.get_content_height()
			if h > cap:
				over += 1
			if cap - h < slack:
				slack = cap - h
				worst = h
				avail = cap
				worst_id = "%s/%s" % [String(id), "卷宗" if expanded else "名片"]
	_obs_expanded = keep_exp
	_sync_obs_panel()
	# R11：这一修给 HUD 加了逐行量宽（`_obs_rows`），得报它的代价，不能只报"装下了"。
	# 口径：连排 200 次完整卷宗的平均耗时（`_update_obs` 每 tick 一次，出货 tick 率 12.5/s）。
	_selected_id = String(ids[ids.size() - 1])
	var t0 := Time.get_ticks_usec()
	for _i in 200:
		var _t: String = _panel_text(false)
	var us := float(Time.get_ticks_usec() - t0) / 200.0
	_selected_id = keep
	_update_obs()
	print("[obs-fit] 排一次完整卷宗 %.0fµs（出货 12.5 tick/s ⇒ 占 CPU %.3f%%）" % [us, 100.0 * us * 12.5 / 1000000.0])
	print("[obs-fit] 居民 %d · 玩家=%s · 第 %d 天(tick %d) · 两档各扫一遍" % [
		ids.size(), str(_player_mode), Sim.day, Sim.tick_no])
	print("[obs-fit] 最坏一格：%s —— 内容 %.1fpx / 可用 %.1fpx · 余量 %+.1fpx · 溢出 %d/%d 格" % [
		worst_id, worst, avail, avail - worst, over, ids.size() * 2])
	if over > 0:
		print("[obs-fit] ❌ 观察台装不下：%d 格被面板下沿静默切掉（RichTextLabel.scroll_active=false 不报错、不出滚动条）" % over)
	else:
		print("[obs-fit] ✅ 观察台装得下（最坏余量 %+.1fpx）" % (avail - worst))
	get_tree().quit(1 if over > 0 else 0)

func _update_obs() -> void:
	if _obs != null:
		_obs.text = _panel_text(not _obs_expanded)
	if _chat_in != null:
		# ★ gate 在【玩家模式】上（C8 item 3）：非玩家模式里没有"你"，那个输入框只是浮在世界中间的一块 UI。
		if not _player_mode or _selected_id == "" or _selected_id == "player" or _player_in_warehouse_observatory():
			_chat_in.visible = false
		elif not _chat_in.has_focus():
			_chat_in.visible = true
			_chat_in.placeholder_text = "对 %s 说…（Enter 发送）" % _nm(_selected_id)

## BBCode 转义（P2-9）：不可信文本（玩家输入 / 模型回复）拼入 RichTextLabel 前把 [ 换成 [lb]，
## 防 [url]/[color] 等标签伪造界面。[lb] 在 BBCode 里正好渲染成字面 [。
func _esc(s: String) -> String:
	return s.replace("[", "[lb]")

func _invalidate_chat_generation(owner_token: int = -1) -> void:
	# Lifecycle cancellation owns presentation cleanup.  Async callbacks are never
	# allowed to mutate a target while proving their request stale.
	for raw_ag in Sim.agents:
		if raw_ag is Dictionary and (raw_ag as Dictionary).has("_chat_request_token") \
			and (owner_token < 0 or int((raw_ag as Dictionary).get("_chat_request_token", -2)) == owner_token):
			(raw_ag as Dictionary)["thinking"] = false
			(raw_ag as Dictionary).erase("_chat_request_token")
	if owner_token >= 0:
		return
	_chat_generation += 1
	_chat_session_id += 1

func _chat_target_reachable(target: Dictionary, player: Dictionary) -> bool:
	if target.is_empty() or String(target.get("id", "")) == "player":
		return false
	if String(target.get("space", "town")) != String(player.get("space", "town")) \
		or String(target.get("floor", "outdoor")) != String(player.get("floor", "outdoor")):
		return false
	var tp: Vector2i = target.get("pos", Vector2i(-99, -99))
	var pp: Vector2i = player.get("pos", Vector2i(-99, -99))
	return absi(tp.x - pp.x) + absi(tp.y - pp.y) <= 2

func _chat_target_allowed(id: String, target: Dictionary) -> bool:
	if id == "" or id == "player" or target.is_empty() or not _agent_on_active_plane(target):
		return false
	if not _player_mode:
		return true # demo/observer context has no player body; active-plane is the explicit scope
	var player := Sim.get_agent("player")
	return not player.is_empty() and _chat_target_reachable(target, player)

func _apply_chat_reply(token: int, target_id: String, target_space: String, target_floor: String,
		target_pos: Vector2i, player_space: String, player_floor: String, player_pos: Vector2i,
		sim_identity: int, session_id: int, prompt: String, reply: String) -> bool:
	var target := Sim.get_agent(target_id)
	if token != _chat_generation or session_id != _chat_session_id or Sim.get_instance_id() != sim_identity:
		return false
	if target.is_empty() or String(target.get("id", "")) != target_id:
		return false
	if String(target.get("space", "town")) != target_space or String(target.get("floor", "outdoor")) != target_floor \
			or Vector2i(target.get("pos", Vector2i(-99, -99))) != target_pos:
		return false
	if _player_mode:
		var player := Sim.get_agent("player")
		if player.is_empty() or String(player.get("space", "town")) != player_space \
				or String(player.get("floor", "outdoor")) != player_floor \
				or Vector2i(player.get("pos", Vector2i(-99, -99))) != player_pos \
				or not _chat_target_reachable(target, player) or _player_in_warehouse_observatory():
			return false
		var chat_receipt: Dictionary = Sim.player_chat_commit(target_id, prompt, reply)
		if not bool(chat_receipt.get("ok", false)):
			return false
	target["thinking"] = false
	target.erase("_chat_request_token")
	if _view != null and _view.has_method("show_say"):
		_view.show_say(target_id, reply, 90)
	_push("[color=#cfe8ff]%s：%s[/color]" % [_nm(target_id), _esc(reply)])
	return true

## 唯一聊天权威：输入框、快捷键和 demo 都先经过同一套空间/距离门；
## AI 回包只可通过 _apply_chat_reply，重新解析目标与玩家上下文后才写 UI/记忆。
func _on_player_say(text: String) -> void:
	text = text.strip_edges()
	if _selected_id == "" or text == "":
		return
	if _player_in_warehouse_observatory():
		_push("[color=#80e1ff]（货运观测室只读；不能在此聊天）[/color]")
		return
	var id := _selected_id
	var ag := Sim.get_agent(id)
	if not _chat_target_allowed(id, ag):
		if _player_mode: _push("[color=#f2a3a3]（目标不在可达范围内）[/color]")
		return
	var token := _chat_generation + 1
	_chat_generation = token
	var target_space := String(ag.get("space", "town"))
	var target_floor := String(ag.get("floor", "outdoor"))
	var target_pos: Vector2i = ag.get("pos", Vector2i(-99, -99))
	var player := Sim.get_agent("player")
	var player_space := String(player.get("space", "town"))
	var player_floor := String(player.get("floor", "outdoor"))
	var player_pos: Vector2i = player.get("pos", Vector2i(-99, -99))
	var sim_identity := Sim.get_instance_id()
	var session_id := _chat_session_id
	_push("[color=#9ad0ff]你 → %s：%s[/color]" % [_nm(id), _esc(text)])   # P2-9：不可信文本转义 [，防 BBCode 注入
	ag["thinking"] = true
	ag["_chat_request_token"] = str(token)
	AIBackend.chat(ag, text, {"tick": Sim.tick_no, "day": Sim.day}, func(reply: String):
		_apply_chat_reply(token, id, target_space, target_floor, target_pos, player_space, player_floor,
			player_pos, sim_identity, session_id, text, reply)
	)
	if _chat_in != null:
		_chat_in.text = ""

## dev：把 (tick, 批量 digest, 增量 event_digest) 写到 --digest-out。供 Probe 观察者无关性硬门比对。
func _write_digest() -> void:
	if _digest_out == "":
		return
	var f := FileAccess.open(_digest_out, FileAccess.WRITE)
	if f != null:
		f.store_string("%d %d %d" % [Sim.tick_no, Inv.digest(Sim), Sim.event_digest])
		f.close()

func _bar(v: float) -> String:
	var n := int(round(clampf(v, 0.0, 100.0) / 10.0))
	return "█".repeat(n) + "·".repeat(10 - n)

# ── 观察台的【视觉行】预算（W8，docs/47 §五-E4 / docs/46 §二·九-⑧）──────────
## 病根一句话：**预算数的是逻辑行，面板截的是视觉行，而中文会折行。**
## 于是"我只加了 3 行"在屏幕上可能是 6 行，多出来的那几行从面板下沿静默掉出去
## （`scroll_active=false` 不报错、不出滚动条、什么都不说）。E2 已经在 `Story.person_lines` 处踩过同一个坑。
## ⇒ 这里改成按**量出来的像素**排：排不下的直接不排，并在末行明写还剩多少 —— 与 `Story.panel_text` 同一条纪律。
## 判别力有机器证明：`--obs-fit` 逐个居民量真实控件的 `get_content_height()`（**不是自己数行**，
## 自己数行会复刻同一个错误）。未修的树上它必红，见 `_obs_fit_report`。

## 去 BBCode。**只用于量宽度，不上屏**。口径与 story_test._plain 一致：只吃形如 `[…]` 且不太长的片段。
## ⚠️ 用 RegEx 而不是逐字符拼串：第一版就是 GDScript 的 `out += s[i]` 循环。
##    实测（`--obs-fit --agents 60 --player --warmup 30`，排一次完整卷宗的平均耗时）：
##      未加本预算（基线）**406µs** → 逐字符版 **604µs**(+49%) → 编译一次的 RegEx 版 **498µs**(+23%)。
##    +92µs × 12.5 tick/s = **+0.115% CPU**。GDScript 里逐字符拼字符串在热路径上永远是错的选择。
static var _bb_re: RegEx = null
func _bb_strip(s: String) -> String:
	if _bb_re == null:
		_bb_re = RegEx.new()
		_bb_re.compile("\\[[^\\]]{0,38}\\]")
	return _bb_re.sub(s, "", true)

## 一条**逻辑行**在给定宽度下占几个**视觉行**。内嵌 `\n` 要拆开单独算（面板里确实有这种行）。
func _obs_rows(line: String, fnt: Font, width: float) -> int:
	var n := 0
	for seg in _bb_strip(line).split("\n"):
		var w: float = fnt.get_string_size(String(seg), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		n += maxi(1, ceili(w / maxf(1.0, width)))
	return maxi(1, n)

## 已经排掉多少像素（长尾额度据此算，而不是据 `L.size()`）。
func _obs_used_px(L: Array, width: float) -> float:
	var fnt := Art.font()
	var used := 0.0
	for ln in L:
		used += float(_obs_rows(String(ln), fnt, width)) * OBS_LINE_H
	return used

## 按视觉高度把逻辑行数组截到 `budget_px` 以内；被截掉几行**写在末行**，绝不静默消失。
func _obs_fit_lines(L: Array, width: float, budget_px: float) -> Array:
	var fnt := Art.font()
	var used := 0.0
	for i in L.size():
		var h := float(_obs_rows(String(L[i]), fnt, width)) * OBS_LINE_H
		# 留 **2** 行而不是 1 行。一行给"还剩多少"那句本身；另一行是**估计误差的余量**：
		# `_obs_rows` 算的是 `ceil(裸宽/可用宽)`，而 RichTextLabel 默认 `AUTOWRAP_WORD_SMART`
		# 在中英混排行上**可能提前折**（它不肯把一个拉丁词劈开）⇒ 我这个估计是**下界**，不是上界。
		# 实测：只留 1 行时最坏余量 +9.0px（半行），留 2 行后 +27.0px。半行的余量守不住一次估偏。
		if used + h > budget_px - OBS_LINE_H * 2.0:
			var kept: Array = L.slice(0, i)
			kept.append("[color=#9aa0b5]…还有 %d 行没排下[/color]" % (L.size() - i))
			return kept
		used += h
	return L

## 观察台正文。brief=true 是【名片档】：只到需求为止（谁 / 在哪 / 在干嘛 / 钱与职业 / 5 条需求）。
## 名片档【不是另一份实现】——它就是本函数在需求那一行提前 return，所以两档永远不可能讲出两套事实。
func _panel_text(brief: bool = false) -> String:
	if _selected_id == "":
		if brief:
			return "[color=#9aa0b5]点一个居民（或 Tab）\n看他此刻在做什么。[/color]"
		return "[color=#cfd3e0]观察台 Observatory[/color]\n\n[color=#9aa0b5]点选一个居民（或按 Tab 轮换），查看其需求 / 关系 / 信念 / 冲突 / 记忆。[/color]"
	var ag := Sim.get_agent(_selected_id)
	if ag.is_empty():
		return "（无此角色）"
	var p: Dictionary = ag.get("persona", {})
	var L := []
	L.append("[color=#ffe08a]%s[/color]  [color=#9aa0b5]%s[/color]" % [str(p.get("name", _selected_id)), " ".join(p.get("traits", []))])
	L.append("[color=#9aa0b5]%s · 在 %s[/color]" % [str(p.get("bio", "")), _agent_location_label(ag)])
	var opt = ag.get("option")
	var doing := "闲着"
	if opt != null:
		# 社交动作走 Sim._verb（引擎里的中文动词表）——此前直接打 action id，观察台上会出现 "gossip_rep→阿丽"。
		# 物件动作的 action 本身就是中文（"洗澡"/"吃饭"），原样显示。
		if String(opt.get("kind", "")) == "social":
			doing = "%s → %s" % [Sim._verb(String(opt.get("action", ""))), Sim._name(Sim.get_agent(String(opt.get("partner", ""))))]
		else:
			doing = str(opt.get("action", ""))
	L.append("当前：[color=#cfe8ff]%s[/color]" % doing)
	if not Sim.economy.is_empty():
		L.append("钱：[color=#ffd166]%d 币[/color]" % int(ag["inventory"].get("coin", 0)))   # Wave 1b
	var _jb: Dictionary = Sim._job_of(_selected_id)
	if not _jb.is_empty():
		var _lv := Sim._skill_level(ag, String(_jb.get("action", "")))   # Wave 2c
		var _sk := ("  熟练 Lv%d" % _lv) if _lv > 0 else ""
		L.append("职业：[color=#9ad0ff]%s[/color] [color=#9aa0b5](班次 %s · 薪 %d)[/color][color=#ffd166]%s[/color]" % [
			String(_jb.get("title", "")), "/".join(_jb.get("shift", [])), int(_jb.get("wage", 0)), _sk])   # Wave 2a/2c
	L.append("")
	L.append("[color=#cfd3e0]需求[/color]")
	for n in Sim.needs_def:
		var nid: String = n["id"]
		var v := float(ag["needs"].get(nid, 0))
		var c := "#7ed957" if v > 35.0 else "#e85a5a"
		L.append("%s [color=%s]%s[/color] %d" % [str(n["label"]), c, _bar(v), int(v)])
	# ★名片档到此为止。**下面每一块都还在**，只是退到一次点击之外 ——
	#   最后一行明写它们去哪了，否则"收起"读起来会像"这个项目没有这些东西"。
	if brief:
		L.append("")
		L.append("[color=#9aa0b5]关系 · 冲突 · 记忆 · 观点 · 信念\n→ 点右上「详情」（或 V）[/color]")
		return "\n".join(_obs_fit_lines(L, OBS_CARD.x - 16.0, OBS_CARD.y - OBS_PAD * 2.0))
	# 关系 top3
	L.append("")
	L.append("[color=#cfd3e0]关系[/color]")
	var rels: Dictionary = ag["relationships"]
	var arr := []
	for oid in rels:
		arr.append([oid, rels[oid]])
	arr.sort_custom(func(a, b): return absf(float(a[1]["affinity"])) > absf(float(b[1]["affinity"])))
	if arr.is_empty():
		L.append("[color=#9aa0b5]（还没有交集）[/color]")
	for i in mini(3, arr.size()):
		var oid: String = arr[i][0]
		var r: Dictionary = arr[i][1]
		var ac := "#7ed957" if float(r["affinity"]) >= 0 else "#e85a5a"
		var stv := int(r.get("standing", 0))
		var sttag := (" [color=#ffd166]名%+d[/color]" % stv) if stv != 0 else ""
		L.append("%s [color=%s]亲%d[/color] 信%d 怨%d%s" % [Sim._name(Sim.get_agent(oid)), ac, int(r["affinity"]), int(r.get("trust", 0)), int(r.get("resentment", 0)), sttag])
	# ── 版式次序（B2 修正）：面板高度固定 600px（约 OBS_MAX_LINES 行），而信念列表无上限。
	# 原次序把"冲突 / 近期记忆"排在信念之后 → 信念一多就被推到看不见的折叠线下面，
	# 而这两块恰是回答"这人为什么生气"的那两块（项目的招牌主张）。故把它们提到长尾之前，
	# 并给信念列表按剩余行数封顶 —— 手机上没有滚轮，靠排序+封顶而不是靠滚动才是可达的。
	# 冲突
	var cf := []
	for c in Sim.conflicts:
		var s := String(c["status"])
		if (s == "simmering" or s == "escalated" or s == "confronted" or s == "lingering") and (c["a"] == _selected_id or c["b"] == _selected_id):
			var other: String = c["b"] if c["a"] == _selected_id else c["a"]
			var role := "怨" if c["a"] == _selected_id else "被怨"
			cf.append("%s %s [color=#ff8c42]%s[/color]" % [role, Sim._name(Sim.get_agent(other)), CONFLICT_STATUS.get(s, s)])
	if not cf.is_empty():
		L.append("")
		L.append("[color=#cfd3e0]冲突[/color]")
		for i in mini(4, cf.size()):
			L.append(cf[i])
		if cf.size() > 4:
			L.append("[color=#9aa0b5]…还有 %d 段[/color]" % (cf.size() - 4))
	# 他身上的故事（docs/47 §二-E2）。**紧跟在「冲突」后面**是有理由的：
	# 上面那一块答的是"他现在跟谁不对付"（Sim.conflicts 的当下快照），这一块答的是"这事怎么走到这一步、后来怎么收的"。
	# 只在【完整卷宗】档出现 ⇒ 名片档仍是卷宗的逐行前缀（player_touch_test 断言的那条性质不动）。
	# 封 2 行（含标题 + 空行共 4 行）：它排在信念长尾之前，多占的每一行都是从"知道的事"里扣的。
	# ★为什么是 2 不是 3：这块面板正文只有 286px 宽，**实测（before 图）它在本棒之前就已经装不下了**——
	#   未改动的树上"观点"那一节的最后一行就已经被面板下沿切掉。所以这里多占的每一行都是从别人身上拿的，
	#   拿 2 行、且每行保证不折行（Story.person_lines 用的是短结局标签，见那里的注释）。
	if _story != null:
		var sl: Array = _story.person_lines(_selected_id, _story_name, 2)
		if not sl.is_empty():
			L.append("")
			L.append("[color=#cfd3e0]故事[/color]")   # 与「关系/冲突/近期记忆/观点」同一种朴素名词，别在这块面板上换语气
			L.append_array(sl)
	# 近期记忆
	var mem = ag.get("memory")
	if mem != null and not mem.items.is_empty():
		L.append("")
		L.append("[color=#cfd3e0]近期记忆[/color]")
		var items: Array = mem.items
		for i in range(maxi(0, items.size() - 4), items.size()):
			L.append("[color=#b8c0d0]· %s[/color]" % str(items[i]["text"]))
	# S3 派系 / 盟约 / 秘密（三小项共用一个空行分隔，缺项时不留孤零零的空段）
	var s3 := []
	var fac := String(ag.get("faction", ""))
	if fac != "":
		s3.append("[color=#cfd3e0]派系[/color] [color=#d9c2ff]%s 派（%d人）[/color]" % [Sim._name(Sim.get_agent(fac)), int(ag.get("faction_size", 1))])
	var pacts: Dictionary = ag.get("pacts", {})
	var pact_names := []
	for oid2 in pacts:
		if String(pacts[oid2].get("status", "")) == "active":
			pact_names.append("%s(给%d/收%d)" % [Sim._name(Sim.get_agent(oid2)), int(pacts[oid2].get("given", 0)), int(pacts[oid2].get("received", 0))])
	if not pact_names.is_empty():
		s3.append("[color=#cfd3e0]互助盟约[/color] [color=#39d4c8]%s[/color]" % "  ".join(pact_names))
	var sec_own := 0
	var sec_held := 0
	for cid3 in ag.get("beliefs", {}):
		var bb: Dictionary = ag["beliefs"][cid3]
		if bool(bb.get("secret", false)):
			if String(bb.get("owner", "")) == _selected_id: sec_own += 1
			else: sec_held += 1
	if sec_own + sec_held > 0:
		s3.append("[color=#cfd3e0]秘密[/color] [color=#c792ea]自有%d · 被托付%d[/color]" % [sec_own, sec_held])
	if not s3.is_empty():
		L.append("")
		L.append_array(s3)
	# 观点（S2：每话题 attitude，+绿/-红；偏离天生立场=被说动过）
	var att: Dictionary = ag.get("attitudes", {})
	if not att.is_empty():
		L.append("")
		L.append("[color=#cfd3e0]观点[/color]")
		for t in att:
			var v := float(att[t])
			var c2 := "#7ed957" if v >= 0.0 else "#e85a5a"
			L.append("%s [color=%s]%+.2f[/color]" % [String(TOPIC_LABEL.get(t, t)), c2, v])
	# 信念（长尾，按剩余行数封顶）。诚实边界：一个 11 条信念的居民仍装不下整块 ——
	# 但被砍的是这条长尾，而不是上面的冲突/记忆，且条数写进标题，绝不静默消失。
	var bel: Dictionary = ag["beliefs"]
	if not bel.is_empty():
		L.append("")
		var cids: Array = bel.keys()
		# 长尾额度按**剩余像素**算，不按剩余逻辑行 —— 后者正是 W8 的病根（中文折行让两者对不上）。
		# 下界仍保留 2 条：一块只剩标题的"知道的事"比没有更难读。`OBS_MAX_LINES` 到此只剩这个兜底作用。
		var room := maxi(2, int((OBS_FULL.y - OBS_PAD * 2.0 - OBS_LINE_H
			- _obs_used_px(L, OBS_FULL.x - 16.0)) / OBS_LINE_H) - 2)   # 留 1 行标题 + 1 行"…还有 N 条"
		var shown := mini(room, cids.size())
		L.append("[color=#cfd3e0]知道的事[/color] [color=#9aa0b5]%d 条[/color]" % cids.size() if shown < cids.size() else "[color=#cfd3e0]知道的事[/color]")
		for i in shown:
			var cid = cids[i]
			var b: Dictionary = bel[cid]
			L.append("[color=#d9c2ff]%s[/color] [color=#9aa0b5](%s)[/color]" % [str(b.get("claim", cid)), _belief_src(b)])
		if cids.size() > shown:
			L.append("[color=#9aa0b5]…还有 %d 条[/color]" % (cids.size() - shown))
	# ★最后一道：按量出来的像素高度硬截。上面的长尾额度是"该给谁让位"，这一道是"绝不溢出"的兜底 ——
	#   一个新加的板块（像 E2 的「故事」那样）不会再把别人静默挤下去。
	return "\n".join(_obs_fit_lines(L, OBS_FULL.x - 16.0, OBS_FULL.y - OBS_PAD * 2.0))

const CONFLICT_STATUS := {"simmering": "憋着", "escalated": "闹大了", "confronted": "已挑明", "lingering": "余温未消"}

## 信念来源措辞。Sim.gd 对亲眼撞见的传闻写 source="__seen__"（30 天一局里 ~108 条 vs 二手 ~3 条，
## 是绝对主流），而它不是任何 agent 的 id —— 旧代码把它喂给 Sim._name 得到 "?"，于是满屏"(听 ? 说)"。
func _belief_src(b: Dictionary) -> String:
	var src := String(b.get("source", ""))
	if src == "__seen__":
		return "亲眼所见"
	if src == "" or src == "__seed__":
		return "亲历/听闻"
	var sag := Sim.get_agent(src)
	if sag.is_empty():
		return "亲历/听闻"     # 查不到来源（人已离场/id 非人）→ 退到中性说法，绝不渲染 "听 ? 说"
	return "听 %s 说" % Sim._name(sag)

# ── --player-demo：脚本化玩家 autopilot（录 demo 用；确定性按 tick 执行剧本）─────────
## 舞台布置：预埋一段 ben-coco 冲突（双方在广场、对玩家有基础好感）→ 剧本=调解→找阿丽 打招呼/送礼/约见/聊天。
func _demo_setup() -> void:
	# 先把世界暖到清晨 ~09:30（首帧前，movie 从白天开场；夜里全镇在睡觉，社交 demo 没戏可拍）
	for i in 95:
		Sim.tick()
	var pl: Dictionary = Sim.get_agent("player")
	Sim.conflicts.append({"a": "ben", "b": "coco", "status": "simmering", "severity": 8.0,
		"escalations": 0, "confronted": 0, "repaired": 0, "triggered": Sim.tick_no, "lastEscalate": Sim.tick_no})
	for id in ["ben", "coco"]:
		var ag: Dictionary = Sim.get_agent(id)
		ag["option"] = null
		ag["talking"] = 0
		Sim._move_agent(ag, pl["pos"] + Vector2i(1 if id == "ben" else -1, 1))
		Sim._rel(ag, "player")["affinity"] = 12.0
	# 把两人钉在"僵持对话"里（互为社交对象 → 原地站定，画面上有对话连线），玩家走进来调解——比赛跑他们的早饭稳
	var _ben: Dictionary = Sim.get_agent("ben")
	var _coco: Dictionary = Sim.get_agent("coco")
	_ben["option"] = {"kind": "social", "action": "greet", "partner": "coco", "subject": "", "remaining": 24}
	_coco["option"] = {"kind": "social", "action": "greet", "partner": "ben", "subject": "", "remaining": 24}
	_ben["talking"] = 24
	_coco["talking"] = 24
	_demo_steps = [
		{"type": "wait", "left": 4},
		{"type": "select", "id": "ben"},
		{"type": "act", "action": "mediate", "target": "ben"},
		{"type": "wait", "left": 30},
		{"type": "select", "id": "aria"},
		{"type": "walk_to", "id": "aria"},
		{"type": "act", "action": "greet", "target": "aria"},
		{"type": "wait", "left": 24},
		{"type": "walk_to", "id": "aria"},
		{"type": "act", "action": "give", "target": "aria"},
		{"type": "wait", "left": 24},
		{"type": "walk_to", "id": "aria"},
		{"type": "act", "action": "invite", "target": "aria"},
		{"type": "wait", "left": 30},
		{"type": "chat", "text": "最近镇上有什么新鲜事吗？"},
	]
	_demo_i = 0

## 每 tick 推进剧本一步：walk_to=朝目标走一格直到可社交距离；act=玩家动作；chat=真模型对话。
func _demo_tick() -> void:
	if _demo_i >= _demo_steps.size():
		return
	var pl: Dictionary = Sim.get_agent("player")
	if pl.is_empty():
		return
	var s: Dictionary = _demo_steps[_demo_i]
	match String(s["type"]):
		"wait":
			s["left"] = int(s["left"]) - 1
			if int(s["left"]) <= 0:
				_demo_i += 1
		"select":
			_selected_id = String(s["id"])
			_update_obs()
			_demo_i += 1
		"walk_to":
			var tgt: Dictionary = Sim.get_agent(String(s["id"]))
			if tgt.is_empty():
				_demo_i += 1
				return
			var here := Sim._area_at(pl["pos"])
			var d: Vector2i = tgt["pos"] - pl["pos"]
			if (here != "" and here == Sim._area_at(tgt["pos"])) or absi(d.x) + absi(d.y) <= 2:
				_demo_i += 1                       # 已到可社交距离
			elif absi(d.x) >= absi(d.y):
				Sim.player_move(Vector2i(signi(d.x), 0))
			else:
				Sim.player_move(Vector2i(0, signi(d.y)))
		"act":
			if int(pl["talking"]) > 0:
				return                             # 等上一段对话结束
			var m := Sim.player_mediate(String(s["target"])) if String(s["action"]) == "mediate" else Sim.player_act(String(s["action"]), String(s["target"]))
			if m != "":
				_push("[color=#f2a3a3]（%s）[/color]" % m)
			_demo_i += 1
		"chat":
			_on_player_say(String(s["text"]))
			_demo_i += 1

## 玩家社交动作分发（--player 模式，目标=当前选中居民）；不可行原因打进事件日志。
## 物理键(KEY_G/F/B/Y/T/P/M) 与触屏动作条按钮【共用本函数】——这是"按钮 ≡ 按键"的构造性保证。
## 返回值 = Sim 给的不可行原因（""=已发起），供 headless 断言比对；UI 侧行为与改动前一致。
func _player_do(action: String) -> String:
	if not _player_mode:
		return "未开玩家模式"
	if _player_in_warehouse_observatory():
		var reason := "货运观测室只读；卸货由码头工执行"
		_push("[color=#80e1ff]（%s）[/color]" % reason)
		return reason
	if _selected_id == "" or _selected_id == "player":
		_push("[color=#f2a3a3]（先用 Tab/点选一位居民，再按动作键）[/color]")
		return "未选中居民"
	var msg := Sim.player_mediate(_selected_id) if action == "mediate" else Sim.player_act(action, _selected_id)
	if _locked_ortho_c1 != null and action == "greet":
		_locked_ortho_c1.show_receipt("问候已发起" if msg == "" else msg)
	if msg != "":
		_push("[color=#f2a3a3]（%s）[/color]" % msg)
	return msg

func _cycle_selection(dir: int) -> void:
	if Sim.agents.is_empty():
		return
	var ids := []
	for a in Sim.agents:
		if not a.get("is_player", false) and _agent_on_active_plane(a):
			ids.append(a["id"])       # 玩家不进观察循环（动作目标只会是居民）
	if ids.is_empty():
		return
	var i := ids.find(_selected_id)
	i = (i + dir + ids.size()) % ids.size()
	_focus_agent(String(ids[i]))   # Tab 轮换也把镜头带过去（此前只换面板文字，人还在屏幕外）

func _in_scrub(pos: Vector2) -> bool:
	return pos.x >= _sx0 - 8 and pos.x <= _sx1 + 8 and pos.y >= _sy - 12 and pos.y <= _sy + SCRUB_H + 12

func _tick_at_x(x: float) -> int:
	var f := clampf((x - _sx0) / (_sx1 - _sx0), 0.0, 1.0)
	return int(round(f * _max_tick))

func _scrub_to_x(x: float) -> void:
	Sim.running = false
	var jumped := Sim.goto_tick(_tick_at_x(x))
	_after_jump(jumped)

## 拖动时【只】挪手柄（不重演）：真正的 goto_tick 每帧最多一次，在 _flush_scrub 里做。
## 一次 goto_tick = start_new(seed) + 从 0 重跑到目标 tick（Sim.gd:802-826，~0.4ms/tick），
## 而一次拖拽会喷几十个 MouseMotion —— 逐个跑等于第 30 天每采样卡 ~3 秒。
func _preview_scrub(t: int) -> void:
	if _scrub_fill == null:
		return
	var f := clampf(float(t) / float(maxi(1, _max_tick)), 0.0, 1.0)
	var w := _sx1 - _sx0
	_scrub_fill.size = Vector2(w * f, SCRUB_H)
	_scrub_handle.position = Vector2(_sx0 + w * f - 2.0, _sy - 4.0)

func _flush_scrub() -> void:
	if _scrub_pending < 0:
		return
	var t := _scrub_pending
	_scrub_pending = -1
	Sim.running = false
	var jumped := Sim.goto_tick(t)
	_after_jump(jumped)

func _after_jump(reconcile_c1 := false) -> void:
	# A failed C1 replay must be an exact View no-op: it has no new canonical
	# world to reconcile, and even rebuilding the panel can redraw stale text.
	# Feature-off retains the historical failed-jump UI refresh behavior.
	if _locked_ortho_c1 != null and not reconcile_c1:
		return
	_modulate.color = _daylight(Sim.time_of_day())
	_update_status()
	_update_scrubber()
	if reconcile_c1:
		_reconcile_locked_ortho_c1()
	# C1 reconciliation can clear a cross-plane selection.  Render observation
	# only after that final View state is known, in the same successful jump frame.
	_update_obs()
	_rebuild_feed()   # 时间线换了：播报必须照当前 event_log 重建，不能留上一条时间线的字

func _nm(id: Variant) -> String:
	var a := Sim.get_agent(String(id))
	return str(a.get("persona", {}).get("name", id)) if not a.is_empty() else String(id)

## 居民名；查不到（如 election 的 actor="town"、秘密 id）返回空串，供调用方走"不提名字"的措辞。
## 纪律：绝不把英文 id 兜底抖到屏幕上 —— 那正是这批改动要消灭的东西。
func _nm_opt(id: Variant) -> String:
	var a := Sim.get_agent(String(id))
	if a.is_empty():
		return ""
	return str(a.get("persona", {}).get("name", ""))

## 从事件身份稳定折出一个措辞变体（同一事件实时播报与回放重建必得同一句 —— 见 _rebuild_feed）。
## 纯读 e 的身份字段（actor/target/subject/tick）+ 项目无关的 String.hash()，【绝不】碰 Sim/RNG，
## 故对金标零扰动（同 _event_prose 本身）。tick 进 key ⇒ 同一对人在不同 tick 的重复动作会轮换措辞，
## 这正是这批改动要治的"同一句模板刷屏"。合成测试事件无 tick ⇒ 折到固定下标，故每条变体都须自洽 AE1。
func _pick(variants: Array, e: Dictionary) -> String:
	var n := variants.size()
	if n <= 1:
		return String(variants[0]) if n == 1 else ""
	var key := "%s|%s|%s|%s|%s" % [
		str(e.get("id", 0)), String(e.get("actor", "")), String(e.get("target", "")),
		String(e.get("subject", "")), str(e.get("tick", 0))]
	return String(variants[(key.hash() % n + n) % n])

## 事件 → 中文散文（唯一的成文口径：实时播报与回放重建共用）。
## 每类给 2-3 条同义变体，_pick 按事件身份稳定选一条 —— 治"同一句刷屏"，不改任何 AE1/极性语义。
func _event_prose(e: Dictionary) -> String:
	var t := String(e.get("type", ""))
	var A := _nm(e.get("actor", ""))
	var B := _nm(e.get("target", ""))
	var C := _nm_opt(e.get("subject", ""))     # subject 可能是人(gossip_rep/endorse)，也可能是秘密/议题 id
	var ok := bool(e.get("accepted", false))
	var note := String(e.get("note", ""))
	match t:
		# AE1（docs/118）：以下十类走 KNOWN_SOCIAL_ACTIONS 通用「接受/婉拒」路（Sim.gd:2419-2568），
		# 真能 accepted=false（拒绝落 Sim.gd:2426 的 _log_event(...,false,...)）。此前它们不看 ok、
		# 恒讲成「做成了」⇒ 被拒被写成成功（AA2 实测出货树 976/27.4% 的主体）。照 meet/apologize 加 if ok else。
		"greet": return _pick([
				"[color=#cfe8ff]%s 找 %s 唠了两句[/color]" % [A, B],
				"[color=#cfe8ff]%s 在路上碰见 %s，站住唠了两句[/color]" % [A, B],
				"[color=#cfe8ff]%s 拉着 %s 唠了两句家常[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想找 %s 搭话，对方没接茬[/color]" % [A, B],
				"[color=#9aa0b5]%s 迎上去跟 %s 打招呼，人家没搭理[/color]" % [A, B],
				"[color=#9aa0b5]%s 想跟 %s 攀谈两句，话没递进去[/color]" % [A, B],
			], e)
		"give": return _pick([
				"[color=#cfe8ff]%s 送了 %s 一份小礼物[/color]" % [A, B],
				"[color=#cfe8ff]%s 顺手送了 %s 一样小东西[/color]" % [A, B],
				"[color=#cfe8ff]%s 挑了份小礼，送了 %s[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想送 %s 一份小礼物，被婉言谢绝了[/color]" % [A, B],
				"[color=#9aa0b5]%s 要塞给 %s 一份心意，被婉拒了[/color]" % [A, B],
				"[color=#9aa0b5]%s 备了份小礼想给 %s，对方谢绝了[/color]" % [A, B],
			], e)
		"gossip": return _pick([
				"[color=#d9c2ff]%s 悄悄向 %s 传了个八卦[/color]" % [A, B],
				"[color=#d9c2ff]%s 凑到 %s 耳边，传了个八卦[/color]" % [A, B],
				"[color=#d9c2ff]%s 压低声音给 %s 传了个八卦[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想找 %s 咬耳朵，对方没搭理[/color]" % [A, B],
				"[color=#9aa0b5]%s 凑过去想跟 %s 嚼舌根，没接茬[/color]" % [A, B],
				"[color=#9aa0b5]%s 想跟 %s 说点闲话，话没递进去[/color]" % [A, B],
			], e)
		"invite": return _pick([
				"[color=#bfe6c8]%s 约了 %s 稍后见面[/color]" % [A, B],
				"[color=#bfe6c8]%s 约了 %s 得空一起坐坐[/color]" % [A, B],
				"[color=#bfe6c8]%s 张罗着约了 %s 改日碰面[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想约 %s 见面，被婉拒了[/color]" % [A, B],
				"[color=#9aa0b5]%s 想邀 %s 得空聚聚，对方没应声[/color]" % [A, B],
				"[color=#9aa0b5]%s 提议跟 %s 找时间碰面，话没递进去[/color]" % [A, B],
			], e)
		"meet": return _pick([
				"[color=#7ed957]%s 与 %s 如约见面，更亲近了[/color]" % [A, B],
				"[color=#7ed957]%s 与 %s 碰上了头，聊得投机[/color]" % [A, B],
				"[color=#7ed957]%s 依约见到了 %s，两人更近了一步[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#e85a5a]%s 与 %s 的约会泡汤了（有人爽约）[/color]" % [A, B],
				"[color=#e85a5a]%s 空等了一场，%s 没赴约[/color]" % [A, B],
				"[color=#e85a5a]%s 与 %s 约好的碰面黄了（有人放了鸽子）[/color]" % [A, B],
			], e)
		"conflict": return _pick([
				"[color=#ffb3b3]%s 对 %s 渐渐积起了怨气[/color]" % [A, B],
				"[color=#ffb3b3]%s 和 %s 之间的疙瘩越结越深[/color]" % [A, B],
				"[color=#ffb3b3]%s 心里对 %s 慢慢结下了心结[/color]" % [A, B],
			], e)
		"confront": return _pick([
				"[color=#ffd166]%s 当面找 %s 把话说开[/color]" % [A, B],
				"[color=#ffd166]%s 拦住 %s，当面把话挑明[/color]" % [A, B],
				"[color=#ffd166]%s 找上 %s，把积着的话都说了[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#ff8c42]%s 质问 %s，对方不认（冲突升级）[/color]" % [A, B],
				"[color=#ff8c42]%s 当面发作，%s 却矢口否认（越闹越僵）[/color]" % [A, B],
				"[color=#ff8c42]%s 找 %s 对质，话不投机，反倒闹得更凶[/color]" % [A, B],
			], e)
		"apologize": return _pick([
				"[color=#7ed957]%s 向 %s 道了歉，两人和解[/color]" % [A, B],
				"[color=#7ed957]%s 低头向 %s 赔了不是，前嫌尽释[/color]" % [A, B],
				"[color=#7ed957]%s 主动找 %s 认了错，两人重归于好[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#e85a5a]%s 道歉，%s 一时还无法原谅[/color]" % [A, B],
				"[color=#e85a5a]%s 赔了礼，%s 心里的结一时还解不开[/color]" % [A, B],
				"[color=#e85a5a]%s 服了软，%s 却还没能放下这桩事[/color]" % [A, B],
			], e)
		"mediate": return _pick([
				"[color=#7ed957]%s 从中说和，%s 那边的火气消了些[/color]" % [A, B],
				"[color=#7ed957]%s 居中调停，%s 的气也顺了些[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想替 %s 说和，话没递进去[/color]" % [A, B],
				"[color=#9aa0b5]%s 想从中打圆场，%s 没接这个话头[/color]" % [A, B],
			], e)
		"betray":
			# 五个"此前静默"的事件类型之一（Sim.gd 里刚接上 social_event）。
			return _pick([
					"[color=#ff5c5c]%s 把 %s 托付的秘密说了出去[/color]" % [A, B],
					"[color=#ff5c5c]%s 转头就把 %s 交底的话抖了出去[/color]" % [A, B],
				], e) if C == "" else _pick([
					"[color=#ff5c5c]%s 把 %s 托付的秘密说了出去，%s 全听见了[/color]" % [A, B, C],
					"[color=#ff5c5c]%s 走漏了 %s 的私密话，%s 正好在旁听了个全[/color]" % [A, B, C],
				], e)
		"confide": return _pick([
				"[color=#c792ea]%s 对 %s 吐露了心事[/color]" % [A, B],
				"[color=#c792ea]%s 挑了个僻静处，对 %s 吐露了心事[/color]" % [A, B],
				"[color=#c792ea]%s 红着眼跟 %s 吐露了心事[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想对 %s 说几句心里话，对方没接住[/color]" % [A, B],
				"[color=#9aa0b5]%s 几次想跟 %s 交底，话没递进去[/color]" % [A, B],
				"[color=#9aa0b5]%s 想向 %s 掏心窝子，对方没接住[/color]" % [A, B],
			], e)
		# leak 被拒 = target 婉拒了这次搭讪，秘密根本没说出口（accepted 走通用路，Sim.gd:2426 会给 false）。
		# 注意：betray（Sim.gd:2507，恒 accepted=true）是 leak 成功时对第三方 teller 的副作用事件，
		# 它自己永不 false，故下面 betray 分支【不加 ok 分岔】——那是刻意的，不是漏。
		"leak": return _pick([
				"[color=#ff8c42]%s 在 %s 面前说漏了嘴[/color]" % [A, B],
				"[color=#ff8c42]%s 一时嘴快，当着 %s 说漏了嘴[/color]" % [A, B],
				"[color=#ff8c42]%s 没把住门，在 %s 跟前说漏了嘴[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想找 %s 攀谈，话没递进去[/color]" % [A, B],
				"[color=#9aa0b5]%s 凑上去想跟 %s 搭话，没接茬[/color]" % [A, B],
				"[color=#9aa0b5]%s 想跟 %s 套两句，对方没搭理[/color]" % [A, B],
			], e)
		"gossip_rep": return (_pick([
					"[color=#d9c2ff]%s 向 %s 议论起 %s 的为人[/color]" % [A, B, C],
					"[color=#d9c2ff]%s 跟 %s 议论起 %s 的种种[/color]" % [A, B, C],
				], e) if C != "" else _pick([
					"[color=#d9c2ff]%s 向 %s 说起了别人的长短[/color]" % [A, B],
					"[color=#d9c2ff]%s 跟 %s 低声说起了别人的长短[/color]" % [A, B],
				], e)) if ok else (_pick([
					"[color=#9aa0b5]%s 想向 %s 编排 %s 的不是，对方没接茬[/color]" % [A, B, C],
					"[color=#9aa0b5]%s 想拉 %s 议论 %s 的短处，没搭理[/color]" % [A, B, C],
				], e) if C != "" else _pick([
					"[color=#9aa0b5]%s 想向 %s 说人是非，没人搭腔[/color]" % [A, B],
					"[color=#9aa0b5]%s 想跟 %s 嚼别人的舌根，没接茬[/color]" % [A, B],
				], e))
		"endorse": return (_pick([
					"[color=#d9c2ff]%s 和 %s 对 %s 统一了口径[/color]" % [A, B, C],
					"[color=#d9c2ff]%s 跟 %s 就 %s 的事统一了口径[/color]" % [A, B, C],
				], e) if C != "" else _pick([
					"[color=#d9c2ff]%s 和 %s 把话说到了一处[/color]" % [A, B],
					"[color=#d9c2ff]%s 跟 %s 私下把话说到了一处[/color]" % [A, B],
				], e)) if ok else (_pick([
					"[color=#9aa0b5]%s 想拉 %s 一起数落 %s，没能说到一块[/color]" % [A, B, C],
					"[color=#9aa0b5]%s 想跟 %s 一道数落 %s，对方没应声[/color]" % [A, B, C],
				], e) if C != "" else _pick([
					"[color=#9aa0b5]%s 想拉 %s 把话说拢，对方没应声[/color]" % [A, B],
					"[color=#9aa0b5]%s 想拉 %s 把话对拢，没能说到一块[/color]" % [A, B],
				], e))
		"discuss": return _pick([
				"[color=#bfe6c8]%s 和 %s 聊起了各自的看法[/color]" % [A, B],
				"[color=#bfe6c8]%s 跟 %s 你一言我一语，聊起了各自的看法[/color]" % [A, B],
				"[color=#bfe6c8]%s 和 %s 凑在一处，聊起了各自的看法[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想和 %s 聊聊看法，对方没接茬[/color]" % [A, B],
				"[color=#9aa0b5]%s 想跟 %s 掰扯掰扯想法，没搭理[/color]" % [A, B],
				"[color=#9aa0b5]%s 起了话头想和 %s 论一论，话没递进去[/color]" % [A, B],
			], e)
		"aid": return _pick([
				"[color=#39d4c8]%s 在 %s 难处时搭了把手[/color]" % [A, B],
				"[color=#39d4c8]%s 见 %s 犯难，上前搭了把手[/color]" % [A, B],
				"[color=#39d4c8]%s 二话没说，给 %s 搭了把手[/color]" % [A, B],
			], e) if ok else _pick([
				"[color=#9aa0b5]%s 想在 %s 难处时搭把手，被回绝了[/color]" % [A, B],
				"[color=#9aa0b5]%s 想帮 %s 一把，对方谢绝了[/color]" % [A, B],
				"[color=#9aa0b5]%s 要给 %s 搭把手，被婉拒了[/color]" % [A, B],
			], e)
		"rally_oust":
			var backers := 0
			if note.begins_with("backers:"):
				backers = int(note.substr(8))
			if backers > 0:
				return _pick([
					"[color=#ff8c42]%s 串联了 %d 个人，一起给 %s 施压[/color]" % [A, backers, B],
					"[color=#ff8c42]%s 拉拢了 %d 个人，合力向 %s 发难[/color]" % [A, backers, B],
				], e)
			return _pick([
				"[color=#9aa0b5]%s 想拉人一起排挤 %s，没人应和[/color]" % [A, B],
				"[color=#9aa0b5]%s 想鼓动众人孤立 %s，应者寥寥[/color]" % [A, B],
			], e)
		"pact":
			if note.begins_with("dissolved"):
				return _pick([
						"[color=#ff8c42]%s 和 %s 的互助盟约散了 —— 一直只拿不给[/color]" % [A, B],
						"[color=#ff8c42]%s 与 %s 的盟约到头了 —— 总是一头热[/color]" % [A, B],
					], e)
			return _pick([
					"[color=#39d4c8]%s 与 %s 结成了互助盟约[/color]" % [A, B],
					"[color=#39d4c8]%s 和 %s 拉手结成了互助的盟约[/color]" % [A, B],
				], e)
		"election":
			# actor="town"、target=议题 id（TOPICS）、accepted=是否通过。
			var topic := String(TOPIC_LABEL.get(String(e.get("target", "")), "镇上的议题"))
			return _pick([
					"[color=#ffe08a]全镇表决：%s —— 通过[/color]" % topic,
					"[color=#ffe08a]全镇表决：%s —— 众议通过[/color]" % topic,
				], e) if ok else _pick([
					"[color=#9aa0b5]全镇表决：%s —— 否决[/color]" % topic,
					"[color=#9aa0b5]全镇表决：%s —— 未获通过[/color]" % topic,
				], e)
		"world":
			return ("[color=#ffe08a]镇上多了点新东西[/color]") if note == "spawn" else ("[color=#9aa0b5]镇上的临时布置撤了[/color]")
	# 兜底：先问 Sim._verb（引擎里早就写好的中文动词表），再退到不提类型的说法。绝不打印英文 id。
	var v := String(Sim._verb(t))
	if v != t:
		return "[color=#cfe8ff]%s 对 %s %s[/color]" % [A, B, v] if B != "" else "[color=#cfe8ff]%s %s[/color]" % [A, v]
	return "[color=#9aa0b5]%s 和 %s 之间起了点事[/color]" % [A, B] if B != "" else "[color=#9aa0b5]%s 那边有了动静[/color]" % A

## 显著度：类型分 + 失败/破裂加成（爽约、否认、盟约散伙通常更有戏）。
func _salience(e: Dictionary) -> int:
	var s := int(SALIENCE.get(String(e.get("type", "")), 60))   # 未知类型按偏高处理：宁可多讲，也不让新机制静默
	if not bool(e.get("accepted", true)):
		s += 6
	return s

## 成文 + 包一层 [url=<居民id>]：点日志一行 → 选中当事人并把镜头飞过去（见 _on_log_meta）。
func _fmt_event(e: Dictionary) -> String:
	var body := _event_prose(e)
	var focus := String(e.get("actor", ""))
	if Sim.get_agent(focus).is_empty():
		focus = String(e.get("target", ""))     # 如 election：actor="town" 不是人，退到 target
	if focus == "" or Sim.get_agent(focus).is_empty():
		return body
	return "[url=%s]%s[/url]" % [focus, body]

func _on_social(e: Dictionary) -> void:
	_push_event(e)

func _push_event(e: Dictionary) -> void:
	if String(e.get("type", "")) in FEED_SKIP:
		return
	var line := _fmt_event(e)
	if _salience(e) >= SALIENT_MIN:
		_log_hot.append(line)
		if _log_hot.size() > LOG_HOT_CAP:
			_log_hot = _log_hot.slice(_log_hot.size() - LOG_HOT_CAP, _log_hot.size())
	_log_recent.append(line)
	_render_log()

## 系统提示（存读档/后端切换/操作反馈）只进「近况」，不占大事位。
func _push(line: String) -> void:
	_log_recent.append(line)
	_render_log()

func _render_log() -> void:
	if _log_recent.size() > LOG_RECENT_CAP:
		_log_recent = _log_recent.slice(_log_recent.size() - LOG_RECENT_CAP, _log_recent.size())
	if _logbox == null:
		return
	var out: Array = []
	# 小镇纪事的一行摘要钉在最上面：它是这块面板里唯一"跨时间"的东西，其余都是刚刚发生的事。
	# 包在 [url] 里 ⇒ 点它就展开清单（手机没有键盘，这是唯一够得着的入口；与点居民名走同一个 meta_clicked）。
	if _goals_line != "":
		out.append(_goals_line)
	if not _log_hot.is_empty():
		out.append("[color=#ff8c42]— 镇上的大事 —[/color]")
		out.append_array(_log_hot)
		out.append("[color=#5a6072]— 近况 —[/color]")
	out.append_array(_log_recent)
	_logbox.text = "\n".join(out)

## 回放/读档后重建播报：旧时间线的字必须清干净，否则 scrub 完屏幕上还在讲一段已被抹掉的历史。
func _rebuild_feed() -> void:
	# ★时间线换了 ⇒ 小镇纪事必须【整份重算】，不能顺着旧游标往下折。
	#   这里是唯一入口：_after_jump（拖时间轴/跳天/单步回退）、_after_load（读档）、
	#   _toggle_player_mode / _apply_npc（同种子重开）四条路都已经汇到这一个函数上。
	#   recompute 是 O(事件数) 的一次性开销，只在这四种"世界换了"的时刻发生，不在 tick 热路径上。
	if _goals != null:
		_goals.recompute(Sim.event_log)
		_goals_line = _goals.summary_line()
		if _goals_open:
			_sync_goals_panel()
	# ★小镇故事同理，而且它比纪事更需要这一条：目标只会前进，故事会**收场**——
	#   顺着旧游标往下折的话，往回 scrub 之后那些"还没发生的结局"会一直挂在面板上。
	if _story != null:
		_story.recompute(Sim.event_log)
		_story_rev = -1                        # recompute 会把 rev 清零重数 ⇒ 缓存令牌必须一起作废
		if _story_open:
			_sync_story_panel()
	_log_hot.clear()
	_log_recent.clear()
	var evs: Array = Sim.event_log
	for i in range(maxi(0, evs.size() - FEED_RESCAN), evs.size()):
		var e: Dictionary = evs[i]
		if String(e.get("type", "")) in FEED_SKIP:
			continue
		var line := _fmt_event(e)
		if _salience(e) >= SALIENT_MIN:
			_log_hot.append(line)
		_log_recent.append(line)
	if _log_hot.size() > LOG_HOT_CAP:
		_log_hot = _log_hot.slice(_log_hot.size() - LOG_HOT_CAP, _log_hot.size())
	_render_log()

## 点日志里的居民名 → 选中 + 镜头飞过去（ProbeController 只被调用，不被改）。
## 顶上那一行「小镇纪事」的 meta 是固定串 Goals.PANEL_META，播报里 ◇ 那一行是 Story.PANEL_META；
## 两个都长成 "__xxx__"，不会与任何居民 id 撞。
func _on_log_meta(meta: Variant) -> void:
	if String(meta) == "__goals__":
		_toggle_goals()
		return
	if String(meta) == "__story__":
		_toggle_story()
		return
	_focus_agent(String(meta))

func _focus_agent(id: String) -> void:
	var ag := Sim.get_agent(id)
	if ag.is_empty() or not _agent_on_active_plane(ag):
		return
	_selected_id = id
	if _probe != null and _locked_ortho_c1 == null:
		_probe.focus_on(Vector2(int(ag["pos"].x) * 48 + 24, int(ag["pos"].y) * 48 + 24), id)
	_update_obs()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE: Sim.running = not Sim.running
			KEY_0, KEY_KP_0: Sim.running = false
			KEY_1, KEY_KP_1: Sim.running = true; Sim.speed = 1.0
			KEY_2, KEY_KP_2: Sim.running = true; Sim.speed = 2.0
			KEY_3, KEY_KP_3: Sim.running = true; Sim.speed = 4.0
			KEY_4, KEY_KP_4: Sim.running = true; Sim.speed = 8.0
			KEY_EQUAL, KEY_KP_ADD: if _locked_ortho_c1 == null: _demo_off(); _probe.zoom_at(1.15, _vp() * 0.5, _vp())
			KEY_MINUS, KEY_KP_SUBTRACT: if _locked_ortho_c1 == null: _demo_off(); _probe.zoom_at(1.0 / 1.15, _vp() * 0.5, _vp())
			KEY_L: if _locked_ortho_c1 == null: _demo_off(); _toggle_follow()                 # Probe 跟随/取消（F 已被"送礼"占用）
			KEY_HOME: if _locked_ortho_c1 == null: _demo_off(); _probe.go_home()              # 回到全镇
			KEY_I: if _locked_ortho_c1 == null: _probe_toggle_space()                         # Probe 进/出测试 Space（P1 Gate）
			KEY_PAGEUP: if _locked_ortho_c1 == null: _probe_cycle_floor(1)                    # 换楼层（Probe inspect）
			KEY_PAGEDOWN: if _locked_ortho_c1 == null: _probe_cycle_floor(-1)
			KEY_TAB: _cycle_selection(-1 if e.shift_pressed else 1)
			KEY_O: _toggle_settings()                            # ⚙ 设置面板开关（NPC 数量/速度/后端）
			KEY_V: _toggle_obs()                                 # 观察台名片档 ⇄ 完整卷宗（手机走右上「详情」钮，同一函数）
			KEY_J: _toggle_goals()                               # 小镇纪事清单开关（手机走"点播报栏顶那一行"，同一函数）
			KEY_K: _toggle_story()                               # 小镇故事开关（手机走"点播报里 ◇ 那一行"，同一函数）
			KEY_F5: _quick_save()                                # R0-2：快速存档
			KEY_F8: _quick_load()                                # R0-2：快速读档
			KEY_F9: _write_digest()                             # dev：把当前 digest 写盘（--digest-out）
			KEY_F3: _toggle_perf()                               # dev 性能 overlay 开关
			KEY_ESCAPE:                                          # 先退观察态(focus/follow/历史)，否则才清选中
				if _locked_ortho_c1 != null:
					_selected_id = ""
					_update_obs()
					_update_status()
					return
				if _probe.mode != 0 or not _probe.go_back():
					_probe.unfollow()
					_selected_id = ""
					_update_obs()
			KEY_C: _on_player_say("你好，最近怎么样？")        # 快捷：对当前平面选中居民打招呼
			                                                 # 非玩家观察模式仍允许演示对话；玩家进入货运观测室时，
			                                                 # _on_player_say 会 fail-closed，不能绕过只读合同写入聊天记忆。
			KEY_N:                                               # P2-4 导航开发叠层：阻挡格(红)+交互格(绿) 可视化
				if _view != null:
					_view.dbg_nav = not _view.dbg_nav
					_view.queue_redraw()
					_push("[color=#9ad0ff]NAV 叠层 %s（红=阻挡格 绿=交互格）[/color]" % ("开" if _view.dbg_nav else "关"))
			# ── 玩家能动性（--player）：WASD 移动 + 对选中居民 G打招呼/F送礼/B八卦/Y约见/P道歉/M调解 ──
			KEY_W, KEY_UP: if _player_mode: Sim.player_move(Vector2i(0, -1))
			KEY_S, KEY_DOWN: if _player_mode: Sim.player_move(Vector2i(0, 1))
			KEY_A, KEY_LEFT: if _player_mode: Sim.player_move(Vector2i(-1, 0))
			KEY_D, KEY_RIGHT: if _player_mode: Sim.player_move(Vector2i(1, 0))
			# 7 个动词键：改动前是 7 行硬编码 KEY_x → 字面量动词，与动作条按钮各写一份 ——
			# 那样"按钮 ≡ 按键"就只是【巧合】，靠人盯着两处不漂。现在两边都从 PLAYER_VERBS 查，
			# 等价性变成构造性的；player_touch_test.gd 再把这句话钉死。
			KEY_G, KEY_F, KEY_B, KEY_Y, KEY_T, KEY_P, KEY_M: _player_do(verb_for_key(e.keycode))
			KEY_PERIOD: if not Sim.running: Sim.tick()                                   # 单步 +1
			KEY_COMMA:
				Sim.running = false
				_after_jump(Sim.goto_tick(maxi(0, Sim.tick_no - 1)))
			KEY_BRACKETLEFT:
				Sim.running = false
				_after_jump(Sim.goto_tick(maxi(0, Sim.tick_no - Sim.TICKS_PER_DAY)))
			KEY_BRACKETRIGHT:
				Sim.running = false
				_after_jump(Sim.goto_tick(Sim.tick_no + Sim.TICKS_PER_DAY))
		_update_status()
	elif e is InputEventMouseButton or e is InputEventMouseMotion 			or e is InputEventMagnifyGesture or e is InputEventPanGesture:
		# C1 only permits left-button taps through the existing Probe tap signal.
		# Motion/right/middle/wheel/gesture never reach Probe, so they cannot pan,
		# zoom, follow, or alter the fixed architectural frame.
		if _locked_ortho_c1 != null and (not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT):
			return
		# 输入仲裁（analysis §4.3）：HUD/时间轴【先吃】——拖时间轴绝不能带动世界；剩下的才交给 Probe。
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed and _in_scrub(e.position):
				_scrubbing = true
				_scrub_to_x(e.position.x)
				return
			if not e.pressed and _scrubbing:
				_scrubbing = false
				_flush_scrub()          # 松手立刻落到最后一个采样点（不等下一帧）
				return
		if e is InputEventMouseMotion and _scrubbing:
			_scrub_pending = _tick_at_x(e.position.x)   # 合并：每帧最多一次 goto_tick（见 _flush_scrub）
			_preview_scrub(_scrub_pending)
			return
		_probe.handle_input(e, _vp())

const QUICKSAVE := "user://quicksave.dat"

func _quick_save() -> void:
	var ok: bool = Sim.save_game(QUICKSAVE, {"name": "quicksave", "day": Sim.day})
	_push("[color=#9ad0ff]存档%s（第 %d 天 · tick %d）[/color]" % [("成功" if ok else "失败"), Sim.day, Sim.tick_no])

func _quick_load() -> void:
	if not FileAccess.file_exists(QUICKSAVE):
		_push("[color=#ff8c42]没有存档（先按 F5 / 设置里存一份）[/color]")
		return
	var ok: bool = Sim.load_game(QUICKSAVE)          # load 内部发 world_reset → AIBackend.cancel_all
	if ok:
		_after_load()
	_push("[color=#9ad0ff]读档%s（第 %d 天 · tick %d）[/color]" % [("成功" if ok else "失败：坏档或版本不符"), Sim.day, Sim.tick_no])

## 读档后的 UI 对齐（同 _after_jump 的精神：世界换了，视图全部重对齐）。
func _after_load() -> void:
	Sim.running = false
	_max_tick = maxi(_max_tick, Sim.tick_no)
	_modulate.color = _daylight(Sim.time_of_day())
	# C0 keeps its historical eager clear. C1 lets the successful restore seam
	# make this decision so dependent UI is refreshed from its final state.
	if _locked_ortho_c1 == null:
		_selected_id = ""
	_update_status()
	_update_scrubber()
	_reconcile_locked_ortho_c1(true)
	# Keep the rendered panel coupled to the final reconciled plane/selection.
	_update_obs()
	_rebuild_feed()   # 读档=换世界：播报同样按新 event_log 重建

func _vp() -> Vector2:
	return get_viewport_rect().size

## active Space 的世界边界 —— 由 SpaceGraph 按 active_space 给（不再直读 Sim.GRID）。
## 缺 spaces.json / 未知 space → SpaceGraph 回落 Sim.GRID 全图 → 兼容期行为不变。
func _space_bounds() -> Rect2:
	var sid := "town"
	if _probe != null:
		sid = String(_probe.active_space)
	return _sg.bounds_px(sid)

## 把 **active Space**（小镇或某间室内）整个装进视口：缩放到【bounds − HUD 余量】刚好塞得下。
##
## ★这段代码此前**嵌在 `if _shot_path != ""` 分支里**（旧 :499）⇒ **只有 `--shot` 出图模式走得到**。
##   后果不是"少一个开关"，而是**录屏路径上没有任何出口**：`--probe-space` 能把 Probe 送进屋，
##   但相机留在小镇那一档的缩放上 ⇒ 实测房间只占画面约 1%（1280×768 里约 96×80 px），成片不可用。
##   docs/74 §五·2 把根因定位到了这一行、并明写"修法是把 fit 提到 `--shot` 分支之外"——这就是那一步。
##   提出来之后**出图与演示镜头共用同一份几何**（不是抄第二份：抄一份就一定会漂，docs/41 §4）。
##
## `reset_town`：town 才需要先 `go_home()` 复位边界；非-town 保持已进的 Space，别被 go_home 拽回 town。
##   演示镜头传 false —— 它每 tick 都调一次，而 `go_home()` 会每次 `push_history()`（返回栈被churn 掉）。
## 余量取 `ProbeController.HOME_PAD` 的**原件**而不是另抄一份 `Vector2(120,240)`：
##   ProbeController 那行注释原本写着"与 Main 的 --shot-fit 同款常量"——两处同款常量正是漂移的温床。
func _fit_active_space(reset_town := true) -> void:
	if _probe == null:
		return
	if reset_town and String(_probe.active_space) == "town":
		_probe.go_home()
	var b := _space_bounds()
	var mapsz: Vector2 = b.size
	if mapsz.x <= 1.0 or mapsz.y <= 1.0:
		return
	var pad: Vector2 = _probe.HOME_PAD          # 顶部状态栏 + 底部聊天/时间轴 HUD 余量
	var fit: Vector2 = (_vp() - pad) / mapsz
	_probe.cam.zoom = Vector2.ONE * minf(fit.x, fit.y)   # 刻意绕过 ZOOM_MIN 夹取：整图入画优先
	_probe.cam.position = b.get_center()

## P1 Gate + P3：Probe 切 Space/Floor（inspect-only，绝不移动任何 Agent）。I=循环空间（town→咖啡馆→测试阁楼→…），PgUp/PgDn=换层。
func _probe_toggle_space() -> void:
	var ids: Array = _sg.spaces.keys()          # 循环所有 Space（含 P3 咖啡馆真室内）
	if ids.is_empty():
		return
	var i := ids.find(String(_probe.active_space))
	var target := String(ids[(i + 1) % ids.size()])
	_probe.set_space(target, _sg.default_floor(target), _sg.bounds_px(target))
	_push("[color=#9ad0ff]Probe → %s / %s（观察者切空间；居民没动）[/color]" % [_sg.label_of(target), _probe.active_floor])
	_update_status()

func _probe_cycle_floor(dir: int) -> void:
	var fl: Array = _sg.floors_of(String(_probe.active_space))
	if fl.size() <= 1:
		return
	var i := fl.find(String(_probe.active_floor))
	var nf := String(fl[(maxi(i, 0) + dir + fl.size()) % fl.size()])
	_probe.active_floor = nf                      # 同 Space 内换层：不动相机边界
	_push("[color=#9ad0ff]Probe → %s / %s 层[/color]" % [_sg.label_of(String(_probe.active_space)), nf])
	_update_status()

## Probe 点选 → 角色 hit-test（选择语义留 Main；Probe 只报"点了世界哪一点"）。
## 自然穿门 UX（替代 I/PgUp/PgDn 开发键）：点 portal 格 → 进店 / 上下楼 / 出门。命中门则不再当作选人。
func _portal_click(world_pos: Vector2) -> bool:
	if _sg == null:
		return false
	var cell := Vector2i(int(floor(world_pos.x / 48.0)), int(floor(world_pos.y / 48.0)))
	var asp := String(_probe.active_space); var afl := String(_probe.active_floor)
	for p in _sg.portals:
		for side in ["from", "to"]:
			var e: Dictionary = p.get(side, {})
			if String(e.get("space", "")) != asp or String(e.get("floor", "")) != afl:
				continue
			var pos: Array = e.get("pos", [0, 0])
			if Vector2i(int(pos[0]), int(pos[1])) != cell:
				continue
			var other: Dictionary = p.get("to") if side == "from" else p.get("from")
			var os := String(other.get("space", "town")); var of := String(other.get("floor", "outdoor"))
			# 玩家模式下，人在当前平面且真的站到门边才随门穿越；远处点门仍保留 Probe inspect。
			# 这让产品截图/玩法验收里的“进仓”是玩家实体的空间变化，不是相机切到一张室内图。
			var player_crossed := false
			if _locked_ortho_c1 != null:
				# C1 admits no Probe-inspect fallback: a portal tap is either a
				# successful public Sim receipt or a visible no-op on this frame.
				if not _locked_ortho_c1.allows_portal(String(p.get("id", ""))):
					_locked_ortho_c1.show_receipt("C1 咖啡馆路线外：未进入")
					return true
				var c1_player: Dictionary = Sim.get_agent("player")
				var c1_pos: Vector2i = c1_player.get("pos", Vector2i(-99, -99)) if not c1_player.is_empty() else Vector2i(-99, -99)
				if not _player_mode or c1_player.is_empty() or String(c1_player.get("space", "town")) != asp \
						or String(c1_player.get("floor", "outdoor")) != afl or absi(c1_pos.x - cell.x) + absi(c1_pos.y - cell.y) > 1:
					_locked_ortho_c1.show_receipt("请走到入口旁")
					return true
				var c1_receipt: Dictionary = Sim.player_portal_intent({"source_space": asp, "source_floor": afl, "portal_pos": cell})
				if not bool(c1_receipt.get("ok", false)):
					var c1_reason := String(c1_receipt.get("reason", "入口不可通行"))
					_push("[color=#ff9b82]（%s）[/color]" % ("私人区域，未获通行许可" if c1_reason == "portal_not_permitted" else "入口暂时无法通行"))
					_locked_ortho_c1.show_receipt(c1_reason)
					return true
				player_crossed = true
			elif _player_mode:
				var pl: Dictionary = Sim.get_agent("player")
				var ppos: Vector2i = pl.get("pos", Vector2i(-99, -99)) if not pl.is_empty() else Vector2i(-99, -99)
				if not pl.is_empty() and String(pl.get("space", "town")) == asp and String(pl.get("floor", "outdoor")) == afl \
						and absi(ppos.x - cell.x) + absi(ppos.y - cell.y) <= 1:
					# Display hit-testing emits a typed player intent only.  Sim re-resolves
					# permission, topology and the atomic agent transition from authored state.
					var crossed: Dictionary = Sim.player_portal_intent({"source_space": asp, "source_floor": afl, "portal_pos": cell})
					if not bool(crossed.get("ok", false)):
						var denied_reason := String(crossed.get("reason", ""))
						var denied_text := "%s：私人区域，未获通行许可" % _sg.label_of(os) if denied_reason == "portal_not_permitted" \
							else "%s：入口暂时无法通行" % _sg.label_of(os)
						_push("[color=#ff9b82]（%s）[/color]" % denied_text)
						if _locked_ortho_c1 != null:
							_locked_ortho_c1.show_receipt(String(crossed.get("reason", "入口不可通行")))
						return true
					player_crossed = true
			var b: Rect2 = _sg.bounds_px(os)
			_probe.set_space(os, of, b)                # 入历史栈 → ESC 可原路退回
			if _locked_ortho_c1 != null:
				_locked_ortho_c1.apply_fixed_frame(_vp(), _probe.HOME_PAD)
			elif os == "town":
				_probe.go_home()                       # 出门 → 回全镇视角
				if player_crossed:
					var pnow: Dictionary = Sim.get_agent("player")
					var pc: Vector2i = pnow.get("pos", Vector2i.ZERO)
					_probe.focus_on(Vector2(pc.x * 48 + 24, pc.y * 48 + 24), "player")
			else:                                      # 进店/换层 → 缩放到室内刚好入画
				var fit: Vector2 = (_vp() - Vector2(120.0, 200.0)) / b.size
				_probe.cam.zoom = Vector2.ONE * clampf(minf(fit.x, fit.y), _probe.ZOOM_MIN.x, _probe.ZOOM_MAX.x)
				_probe.cam.position = b.get_center()
			_selected_id = "player" if player_crossed else ""
			var verb := "上下楼" if String(p.get("kind", "")) == "stairs" else ("进门" if os != "town" else "出门")
			_push("[color=#9ad0ff]%s / %s 层（点%s）[/color]" % [_sg.label_of(os), of, verb])
			_update_obs()
			_update_status()
			return true
	return false

func _on_probe_tap(world_pos: Vector2) -> void:
	if _portal_click(world_pos):                       # 先看点没点门/楼梯；点了就穿，不再选人
		return
	if _warehouse_observatory_click(world_pos):        # 观测柜台只读查询；不落 Sim 账、不选人
		return
	_select_at_world(world_pos)

func _warehouse_observatory_click(world_pos: Vector2) -> bool:
	if _probe == null or String(_probe.active_space) != "port_warehouse" or String(_probe.active_floor) != "1f":
		return false
	var cell := Vector2i(int(floor(world_pos.x / 48.0)), int(floor(world_pos.y / 48.0)))
	if cell != Sim.warehouse_observatory_console_cell():
		return false
	var projection: Dictionary = Sim.warehouse_observatory_projection("port_dock")
	var cargo: Dictionary = projection.get("cargo", {})
	var receipt: Dictionary = projection.get("receipt", {})
	var cargo_text := "泊位暂无待卸货物"
	if String(cargo.get("state", "")) == "invalid":
		cargo_text = "泊位货单异常，已暂停展示"
	elif String(cargo.get("state", "")) != "empty":
		cargo_text = "泊位 %s×%d（%s）" % [String(cargo.get("good", "货物")), int(cargo.get("qty", 0)),
			String({"ready": "待卸", "working": "卸货中", "blocked_capacity": "仓位不足", "blocked_funds": "镇库不足"}.get(String(cargo.get("state", "")), "待处理"))]
	var receipt_text := "尚无卸货回执"
	if String(receipt.get("state", "")) == "invalid":
		receipt_text = "最近回执异常，已隐藏明细"
	elif String(receipt.get("state", "")) == "complete":
		receipt_text = "最近回执 #%d：%s×%d · %s" % [int(receipt.get("event_id", -1)),
			String(receipt.get("good", "货物")), int(receipt.get("qty", 0)), Sim._name(Sim.get_agent(String(receipt.get("worker_id", ""))))]
	_push("[color=#80e1ff]观测台｜%s；%s（只读）[/color]" % [cargo_text, receipt_text])
	_update_status()
	return true

## Probe 双击 → 聚焦所点房间（analysis §4.2 Focus）。
func _on_probe_double_tap(world_pos: Vector2) -> void:
	if _locked_ortho_c1 != null:
		return
	for rid in Sim.world.get("rooms", {}):
		var rm: Dictionary = Sim.world["rooms"][rid]
		var r: Array = rm.get("rect", [0, 0, 0, 0])
		var rect := Rect2(r[0] * 48, r[1] * 48, r[2] * 48, r[3] * 48)
		if rect.has_point(world_pos):
			_probe.focus_on(rect.get_center(), String(rid))
			return
	_probe.focus_on(world_pos)

## L：Probe 跟随/取消跟随选中居民（Probe 跟随 ≠ Agent 移动）。
func _toggle_follow() -> void:
	if _probe.mode == 2:
		_probe.unfollow()
	elif _selected_id != "":
		_probe.follow(_selected_id)

func _select_at_world(w: Vector2) -> void:
	var best := ""
	var bestd := 1.0e9
	for a in Sim.agents:
		if not _agent_on_active_plane(a):
			continue
		var c := Vector2(a["pos"].x * 48 + 24, a["pos"].y * 48 + 24)
		var d := c.distance_to(w)
		if d < bestd:
			bestd = d
			best = String(a["id"])
	if bestd <= 42.0:
		_selected_id = best
		_update_obs()

## One activation seam for the CLI product path and the composed C1 contract
## scene. The adapter remains optional and has no authority outside View state.
func _activate_locked_ortho_c1() -> void:
	if _locked_ortho_c1 == null:
		_locked_ortho_c1 = preload("res://scripts/LockedOrthoC1.gd").new()
		add_child(_locked_ortho_c1)
	if _probe != null:
		_locked_ortho_c1.setup(_probe)
		_locked_ortho_c1.apply_fixed_frame(_vp(), _probe.HOME_PAD)

## Successful load/replay is authoritative in Sim.  C1 only mirrors that
## canonical player plane back into Probe, then reapplies its immutable frame;
## it never writes a portal, save, trace, or topology decision.
func _reconcile_locked_ortho_c1(clear_selection := false) -> void:
	if _locked_ortho_c1 == null or _probe == null or _sg == null:
		return
	var player: Dictionary = Sim.get_agent("player")
	# No-player mode has no canonical actor plane.  C1's deterministic observer
	# fallback is town/outdoor, so a settings reset cannot preserve stale cafe
	# projection state while still remaining wholly outside Sim authority.
	var space := String(player.get("space", "town"))
	var floor_id := String(player.get("floor", "outdoor"))
	_probe.set_space(space, floor_id, _sg.bounds_px(space))
	var selected := Sim.get_agent(_selected_id)
	if clear_selection or selected.is_empty() or String(selected.get("space", "town")) != space or String(selected.get("floor", "outdoor")) != floor_id:
		_selected_id = ""
	_locked_ortho_c1.clear_receipt()
	_locked_ortho_c1.apply_fixed_frame(_vp(), _probe.HOME_PAD)

func _agent_on_active_plane(ag: Dictionary) -> bool:
	if ag.is_empty():
		return false
	var space := "town"
	var floor_id := "outdoor"
	if _player_mode:
		var player := Sim.get_agent("player")
		if not player.is_empty():
			space = String(player.get("space", space))
			floor_id = String(player.get("floor", floor_id))
	elif _probe != null:
		space = String(_probe.active_space)
		floor_id = String(_probe.active_floor)
	return String(ag.get("space", "town")) == space and String(ag.get("floor", "outdoor")) == floor_id
