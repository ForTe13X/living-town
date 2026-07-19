extends Node
## Sim.gd — autoload "Sim"：headless 可测的世界 + Agent 仿真引擎。
## 范式继承《小鱼岛》Game.gd：全部权威状态在此、确定性种子 RNG、只用信号与视图通讯、
## 暴露 agent_candidates()/agent_apply() 的「合法候选」契约（LLM 只在候选里挑，引擎永远兜底合法）。
## 确定性纪律：scenario/回放/soak 走确定性逻辑，不调 LLM。
##
## M1 社交底座（垂直切片，经 tools/sim_social_port.mjs 验证 8 条不变量）：
## 候选除物件交互外，还枚举【感知到的其他 agent】的社交动作 greet/give/gossip；
## 社交按 SocialTransaction 协议执行：发起 → 评估(接受/拒绝) → 提交 → 双方+旁观者各写视角记忆。
## 关系账本(affinity/familiarity + event 溯源) + belief/知识边界(只能经事务/观察获知) + 不可变 event_log。

## preload 而非依赖 class_name 全局（未在编辑器导入的项目无全局类缓存，headless 下全局类名不可用）。
const MemoryStreamScript := preload("res://scripts/Memory.gd")

signal ticked(tick_no: int)
signal agent_changed(agent_id: String)
signal day_changed(day: int)
signal log_line(text: String)
signal social_event(event: Dictionary)   # 视图可订阅：渲染气泡/连线
signal world_reset                        # start_new 时发：AIBackend 订阅→cancel_all(bump epoch)，防旧世界回包污染新局(P1-3)。仅信号，Sim 不识 backend；CI 无监听=无操作，零 digest 影响。
var replaying := false                     # goto_tick 重演期间为 true → AIBackend.decide 直接走 logic，不在回放里发 live 请求(P1-6)

const TICKS_PER_DAY := 240
const GRID := Vector2i(24, 16)
# 导航（town-world P2 增量1）：权威 walkability + 确定性 A* 次步，取代裸 Manhattan step。
# off=NAV_PATHFIND=false 逐字节回退 _step_toward。纯 f(state)、无 RNG/Time；起点/终点恒可入(终点=交互格)。
const NAV_PATHFIND := true
const NAV_DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
# café 居民的这些需求只在【家 Space 内】满足（睡自家 2F 床、在 1F 吧台看摊）→ 镇上只为吃饭/洗澡/串门。
# 关键靠【承诺式行程 journey】落地(见 _journey_candidates/_advance_journey)：一旦决定"回家睡觉"就一路走到床、
# 中途不每 tick 按当下最紧需求重挑(那会在门口/楼梯 livelock 饿穿)——只有真危机(下面 PREEMPT)才打断。
const HOME_NEEDS := ["energy", "fun"]
const JOURNEY_URGENT := 30.0    # 偏紧(need<70)才发起跨平面行程（本地已无满足者时）
const PREEMPT_CRISIS := 12.0    # 承诺行程执行中，若【另一】需求跌破此危机线且当前行程目标本身不急 → 中止改救急（守 #01）
# 顾客进店（多人室内）：镇上的【常客】(cafe_regular)在营业时段、fun 偏低且无紧急事时 → 承诺行程进咖啡馆喝咖啡，
# 进去后与阿丽/其他客人同平面自然社交(闲坐/串门/八卦)，某需求偏紧再承诺行程出店办事。让咖啡馆成活的社交枢纽。
const CAFE_VISIT_FUN := 68.0    # fun<此(营业时段) → 常客动了"去喝杯咖啡"的心思（抢在就近游戏机之前）
const CAFE_VISIT_BONUS := 22.0  # 进店行程加成：让"专程去咖啡馆"稳压就近的镇上游戏机(否则路远永不选)→ 常客真会来
const CAFE_OPEN_LO := 0.15      # 营业时段 tod∈[lo,hi)（清晨到午后；夜里不揽客 → 顾客回家/镇上过夜）
const CAFE_OPEN_HI := 0.62
const CONVERSE_TICKS := 10      # 一次社交对话占用的 tick（双方绑定/暂停）——够读完一句台词
const SOCIAL_FULL := 88.0       # social 高于此不再主动发起社交
const GIFT_START := 3           # 每个 NPC 初始礼物数（give 破冰用）
const MEET_HORIZON := 40        # invite 创建的 meet 承诺：deadline = now + 此
const ATTEND_WINDOW := 16       # 离 deadline ≤ 此 → 引擎给「赴约」加权
const NEED_CRISIS := 15.0       # 任一需求 < 此 → 放弃赴约（真危机才爽约 → broken）
var SURVIVAL_GATE := 30.0       # 任一需求 < 此 → 本 tick 不社交，先去吃/睡（留赶路缓冲，防大 N 饿穿）。
                                # Phase-D：const→var（配置项，非 event 态→不进 digest；默认不变→CI 逐字节不变），供闭环 A/B 换档。
                                # 20→24→28→30：每次给 need-floor 更足缓冲，使 #01 无饿穿对【决策/地图扰动】鲁棒
                                # （endorse 抑制曾令阿本社交需求饿穿；P2-4 加建筑改 blockers→轨迹蝶变，seed11 阿本赴咖啡馆途中饿穿）。
const CONFLICT_TRIGGER := 6.0   # resentment 累积到此 → 触发一段冲突（simmering）
const ESC_THRESH := 2           # 升级次数到此 → escalated
const LINGER_AFTER := 350       # 触发后 tick 未对质 → lingering（冷战）
const FORGIVE_CAP := 22.0       # 冲突 severity 高于此则难被原谅
# CHARACTER 层（docs/24；两轮独立盲评 held-out 验证：char 规则 98% vs logic 6% in-character）：
# 委屈方对"小怨气"默认【不当面理论、让它过去】；只有直性子(耿直，本镇=老海)才会为此对质。
# 这是纯人设函数（无 RNG/Time，确定性），把决策从 logic 死规则升级到贴人设。DRAMA 层（导演，另一轴）
# 日后可为推进剧情按需重新抬起对质——两轴分开，绝不加权混合。BLUNT_TRAITS 是"会为小事对质"的人设标记。
var CHARACTER_DEFER := true     # Phase-D：const→var（配置，供 A/B 关掉→退回 logic 恒对质）
# Phase-D 双面裁决：确认性盲评（30-seed、一等-defer、中性 3 轴、A=A tie 率 1.0）说 in_character 上 莽撞(evy)/爽快(tie)
# 也一致判 confront（N28、p_eff=1.000）——但 Step-3 闭环 A/B 一票【否决】了这个扩项：多两个人设逢怨即对质→更多怨被
# 引爆和解→没人攒下持久坏名声→【涌现放逐 #15 被抹平】（10/12 破软门，正应验 DRAMA_ERUPT 注释的警告）。judge 验过 ≠ 能上，
# 必须过 CI gate——这正是要做闭环因果 A/B 的原因。故【保持仅耿直】。莽撞/爽快待更大样本 + DRAMA 侧不抹平 #15 的做法再议。
var BLUNT_TRAITS := ["耿直"]    # 直性子/认死理 → 会当面把话说开；其余默认让小怨气过去
# DRAMA 层（导演，独立轴——绝不与 CHARACTER 加权混合）：CHARACTER 让大多数小怨气默认憋着，
# 但一段【憋太久没说开】的心结应当被安排一场对质来推进剧情（否则 arc 悬着、冲突 dangling）。
# 越重/被反复冒犯(escalated)的怨越早爆；纯 f(age,severity,escalations)，无 RNG/Time → 确定性、可回放。
# 触发即重新广告 confront（其分自然压过维护 → 当选 → 对质→道歉→和解，冲突清账）。v1 用"憋够久"作 pacing；
# 更精细的场景预算(每日限 N 场/叙事弧)留后续。
const DRAMA_DIRECTOR := true
const DRAMA_ERUPT_AFTER := 1200   # ~5 天(TICKS_PER_DAY=240)没说开 → 导演安排对质（远长于 LINGER_AFTER=350）
const DRAMA_ERUPT_FLOOR := 480    # 最早也要 ~2 天，避免刚结怨就爆
var DRAMA_FORGIVE_FADE := true    # Phase-D 调参：夜间把"怨气已衰到触发线下"的未爆小怨归档成 faded 终态（宽恕落地）。
                                  # 诊断实测：severe 完成率已 0.88(导演够勤)、低完成全是小怨该淡着(保#15)、但 30% 悬空其实气早消了只是没标终态
                                  # → 这条纯重标签把完成率抬到更诚实的值、且不引爆任何怨(不碰#15)。const→var 供 A/B。
const DRAMA_ERUPT_SEV := 9        # 只有够重(>=此)或被反复冒犯(escalated)的心结才值一场戏；其余小怨就让它淡着——
                                  # 否则每段怨都爆→都和解→没人攒下持久坏名声→涌现放逐(#15)被抹平。这也是更好的戏剧：戏留给要紧的冲突。
# DRAMA 戏剧节拍 · 八卦泄密（secret-stake 盲评 held-out：默认守信 in-character、唯一例外=爱八卦人设 leak 率 100%）：
# 话痨(GOSSIP_TRAITS=爱八卦，本镇=阿丽)憋不住、把托付给她的秘密当谈资抖出去——但要憋够久(非一拿到就说)。
# 其余人设默认守信(logic 本就从不 leak，已验证 in-character)。纯 f(trait,age) 确定性；泄密→被背叛者积怨→冲突(既有后果)。
var DRAMA_GOSSIP_LEAK := true   # Phase-D：const→var（A/B 关掉→退回 logic 恒 leak/rally/endorse）
const GOSSIP_TRAITS := ["爱八卦"]
const GOSSIP_LEAK_AFTER := 600    # 拿到秘密憋 ~2.5 天后才忍不住说漏（TICKS_PER_DAY=240）
const GOSSIP_LEAK_BOOST := 26.0   # 憋够久的话痨：把 leak 分抬到压过维护 → 当选（抖出去）
# CHARACTER 层 · 派系合围（faction-moment 盲评：p_eff(rally_oust)=0.014、CI[0,0.028]、【无人设例外】）：
# 撺掇公开孤立/施压一个外群人，对本镇【每一个人设都极不入戏】——logic 却 49% 就这么干。默认弃权。
# 唯一保留：DRAMA 让"众人合围一个真·过街老鼠"成一场罕见的戏——对象名声极差(众怒)且已有【激化】的冲突时。
# 保 DRAMA 出口是为了不抹平涌现放逐(#15)/派系协同(#25-28)——同 confront 的 CHARACTER/DRAMA 两轴分法。
var FACTION_MOB_DEFER := true   # Phase-D：const→var（A/B 关掉→退回 logic 恒 leak/rally/endorse）
const MOB_ERUPT_STANDING := -2.5  # 对象在 ag 眼里名声极差(≤此，比 REP_GOSSIP_TH=-2 更狠) → 才够格被合围
# CHARACTER 层 · endorse（"和 X 咬耳朵、统一对 Y 的说法、一道贬低疏远他"）：盲评 p_eff(endorse)=0.043、
# 但【只有爱八卦的阿丽】in-character(0.43)、余 9 人设皆 0——endorse 本质是【八卦串谋】、落在 gossip 轴而非 mob 轴
# （故有 1 个人设例外、不同于 rally_oust 的零例外）。ON：仅 _is_gossipy(爱八卦=阿丽) 拉人统一口径、余弃权。
# #01-safe：全面弃权曾蝴蝶到 seed-4 的 #01 无饿穿——根因是抑制 endorse 减了全镇社交吞吐、阿本社交需求赶不上；
#   解法不是缩抑制、而是把 SURVIVAL_GATE 20→24 给 need-floor 更足赶路缓冲（真·鲁棒性升级，见其定义处）→ 12/12 绿。
var FACTION_ENDORSE_DEFER := true   # Phase-D：const→var（A/B 关掉→退回 logic 恒 leak/rally/endorse）
# S1（声誉×八卦×宽恕，docs/10 §A/§B）
const STANDING_CAP := 3.0       # standing 范围 [-CAP,+CAP]；sign=good/bad
const STANDING_K := 6.0         # 接受规则里 standing 权重 → 涌现放逐
const REP_GOSSIP_TH := -2.0     # standing ≤ 此 → 可对外传其坏名声(gossip_rep)
const INVEST_TRUST := -8.0      # 脆弱动作(give/invite)条件投资门：trust ≥ 此才发起
const RESENT_DECAY := 0.4       # 每日 resentment 衰减（宽恕：不永久世仇）
# S2（意见动力学，docs/10 §A2/§A3）
const TOPICS := ["cafe_expand", "night_market", "old_tales"]  # 镇上几个话题（attitude∈[-1,1]）
const CONF_BOUND := 0.85        # Deffuant 有界信任 ε
const DISCUSS_MINDIFF := 0.15   # 差异太小不值得谈
const STIFLE_K := 2             # Maki-Thompson：遇到 K 个已知者 → 变 stifler（谣言变冷）
const BACKFIRE_RESENT := 20.0   # resentment > 此 → 意见背离（signed FJ）
# S3（社交深化：观点派系 / 互助盟约 / 秘密信息博弈，docs/10 §B/§C；逻辑镜像 tools/sim_social_port.mjs）
const STANDING_DELTA_CAP := 2.0   # ★跨机制守卫：单 tick 内每 (观察者→对象) standing 总移动量上限（防叠穿）
const FACTION_BAND := 0.5         # 同话题"接近"带 |Δattitude|<此
const FACTION_SALIENT := 0.15     # 骑墙死区 |attitude|<此不计入同号
const FACTION_MIN_AGREE := 2      # 3 话题中 ≥此 个"同号且接近"才算对齐
const FACTION_QUORUM := 2         # 协同行动法定人数（派系 size 门）
const FACTION_ACCEPT_K := 8.0     # _acceptance_rule 同/跨派系门权重
const FACTION_INGROUP_AFF := 1.0  # 同派系成功社交额外 affinity 加成
const FACTION_ENDORSE_BONUS := 12.0
const FACTION_ENDORSE_AFF := 3.0
const OUST_BASE := 20.0
const FACTION_AFF_MARGIN := 2.0
const PACT_TRUST_TH := 12.0
const PACT_FAM_TH := 6.0
const PACT_COMPLEMENT_TH := 3
const PACT_CAP := 2
const AID_NEED_TH := 30.0
const AID_RELIEF := 18.0
const AID_BASE := 16.0
const AID_TRUST := 3.0
const PACT_INVITE_BONUS := 6.0
const PACT_ATTEND_BONUS := 12.0
const FREERIDER_GAP := 4
const FREERIDER_STREAK := 2
const PACT_MIN_EXCHANGES := 3
const PACT_BREAK_TRUST := 10.0
const PACT_BREAK_RESENT := 8.0
const PACT_RECONCILE_COOLDOWN := 4
const COMPLEMENT_LOW := 35.0
const COMPLEMENT_HIGH := 60.0
const EARSHOT := 2              # 秘密私语的"耳边"半径（曼哈顿格）：此内有第三者=会被听见=不算独处
const CONFIDE_TRUST := 25.0
const SECRET_AFF_FLOOR := 10.0
const CONFIDE_TRUST_GAIN := 8.0
const BETRAY_TRUST_CRASH := -40.0
const BETRAY_AFF_CRASH := -30.0
const BETRAY_RESENT := 14.0
const BETRAY_STANDING := -2.0
# L3 仿真 LOD（docs/12 §L3）：远离焦点(玩家/视口)的 agent 降低决策频率 → 省大 N 算力
var lod_near_radius := 8          # 到焦点曼哈顿距离 ≤ 此 = near(全保真)；窗口随相机缩放/视野调（var 以便 bench/相机调）
var lod_near_cap := 0             # >0：near cohort=距焦点最近的 K 个 agent（其余 far）；=0 按半径。小地图上比半径更可控（=相机周围 K 人）
var _near_set := {}               # lod_near_cap>0 时每 tick 重算的近端 id 集
const LOD_NEAR_RADIUS := 8        # 兼容旧引用（默认值）
const LOD_FAR_MULT := 3           # far agent 的决策周期 = decide_period × 此（降频）

var running := false
var auto_run := false          # 窗口模式由 Main 置 true；soak 手动 tick()
var speed := 1.0
var tick_interval := 0.08      # 实时秒/ tick（auto_run 时）

var tick_no := 0
var day := 1
var seed_base := 12345
var _accum := 0.0

var needs_def: Array = []       # [{id,label,decay,low}]
var world := {}                 # {width,height,areas,objects:{id:obj}}
var _blocked := {}              # town/outdoor 导航阻挡格 idx(y*W+x)->true（家具+blockers）；start_new 重建
var _path_cache := {}           # aid -> {goal,path,i}：算一次跟着走(大图性能)；transient(DERIVED、不入 digest/存档)
# P3 Tier-B 多平面：Space/Floor/Portal + 每平面导航网。纯 f(数据)，start_new 重建，不入 digest（transient/派生）。
var _spaces := {}               # spaces.json spaces：id -> {kind,label,bounds,floors,default_floor}
var _portals := []              # spaces.json portals：[{id,kind,from:{space,floor,pos},to,bidirectional,...}]
var _interiors_data := {}       # interiors.json：space -> floor -> {label,floor,furniture[]}
var _nav_grids := {}            # space -> floor -> {w,h,blocked}：每平面独立导航网（town 复用 _blocked 引用）
var rhythm := {}                # 昼夜节律偏好表 data/rhythm.json：{phases:{name:[lo,hi)}, prefs:{need:{phase:factor}}, default}
var utility := {}               # 效用/接受权重表 data/utility.json（docs/14 §1 步骤4）：行为调参数据化，缺键→代码默认(逐字节不变)
# ── Wave 1c 天气（docs/15 §3 挂点#3 最小版）：weather(day)=纯哈希查权重表——不消耗 RNG 流、不存历史，goto_tick 天然复现 ──
var weather := {}               # data/weather.json：{types:{名:{w:权重}}, mults:{天气:{动作:乘子≤1}}}；缺文件→恒晴=零扰动
var weather_today := ""         # 当日天气（start_new/日界重算；纯 f(seed_base,day)）
# ── Wave 3b 生命周期（docs/15 §3.3）：季节(纯 day 函数，按序轮转)+活动乘子(≤1 dampen)；agent 年龄/阶段(纯确定)。缺文件→零扰动 ──
var lifecycle := {}             # data/lifecycle.json：{season_length_days, seasons:{order:[...], mults:{季:{动作:≤1}}}, aging:{days_per_year, ages:{id:岁}, stages:[{max,name}]}}
var season_today := ""          # 当季（start_new/日界重算；纯 f(day)，按 春→夏→秋→冬 顺序，非随机）
# ── Wave 2b 节日（docs/15 §3 原语#4 WorldPatch）：data/festivals.json 驱动；缺文件→零扰动 ──
var festivals := {}             # {festivals:{名:{every_days,offset,weather_req:[],objects:[{id,pos,advertises}]}}}
var festival_active := ""       # 当日进行中的节日名（""=无）
var _fest_objects: Array = []   # 当前节日 spawn 的对象 id（despawn/start_new 清场用）
# ── Wave 2c 技能（docs/15 §3）：data/skills.json 驱动；缺文件→_skill_level≡0=逐字节不变 ──
var skills := {}                # {per_level:int, max_level:int, wage_bonus:int}
# ── 私密秘密（docs/16 秘密博弈激活）：data/secrets.json 驱动；缺文件→无种子→逐字节不变；仅默认沙盘场景播种，保留定向场景纯净 ──
var secrets := {}               # {seeds:[{owner:id, claim:str}]}；每条给 owner 一条 self-subject 秘密 → 走 confide/leak/betray 专道
# ── 冻结·70B 语音库（frozen-70B voice）：data/voicebank.json = {persona_id:{action:[台词…]}}；70B 离线著作、冻成数据 ──
# _canned_say 按 tick/agent 确定性挑一条 → LLM 质感、零端上推理、逐字节可回放。缺文件→{}→回落通用罐头(逐字节不变，off 门)。
# 说明：台词只进 UI 气泡/记忆视图，不进 event_log digest（digest 只哈希 id:type:actor:target:accepted:subject:tick），故语音是纯呈现、动不了红线。
var voicebank := {}
# ── Wave 2a 职业（docs/15 §3）：data/jobs.json 驱动；缺文件→_wage_for≡economy.wages 查表=逐字节不变 ──
var jobs := {}                  # {jobs:{holder:{title,action,wage,shift:[相位]}}, extra_advertises:[{object,action,need,amount,duration}]}
var _jobs_injected := false     # extra_advertises 只注入一次（防 _load_data 重入翻倍）
var _buildings_compiled := false # 阶段2 室内编译只跑一次（防重入翻倍家具）
# ── Wave 1b 经济（docs/15 §3）：data/economy.json 驱动；缺文件→_econ_on()=false→全部短路=逐字节不变 ──
var economy := {}               # {start_coin, town_start, prices:{action:int}, wages:{action:int}}
var town_coin := 0              # 镇库（吃饭收费流入、做活工资流出 → 闭环）
var econ_total0 := 0            # 开局货币总量（金钱守恒硬不变量的基准：Σagent coin + town_coin 恒等于它）
# ── Wave 3c 住房产权（docs/15 标注低优先；接 buildings.json rooms.owner）：每夜房客→房东经 Ledger 转租金 ──
var housing := {}               # {rent:int, tenancies:[{tenant:id, landlord:id}]}；缺文件→无租金=逐字节不变
# ── Wave 3a 治理/选举（docs/15 §3.3「收获期」）：S2 attitude 即选票，快照纯函数计票；缺文件→零扰动 ──
var elections := {}             # {topic, every_days, offset, abstain_below}
var election_log: Array = []    # 每次选举结果 {day,topic,yea,nay,abstain,pass,voters}（soak + 硬不变量#37 用）
var last_election := {}         # 最近一次结果（观察台/HUD）
var econ_stats := {"meals_paid": 0, "meals_free": 0, "wages_paid": 0, "wages_skipped": 0}  # 诊断计数
var agents: Array = []          # [agent dict]
var _agent_by_id := {}
var spawn_count := 0            # >0：克隆扩容到该 agent 数（扩 N 测试用；0=用数据原样 6 个）
var decide_period := 1          # L2 决策切片：每 agent 仅在 tick%P==hash(id)%P 做重决策(摊平大N尖峰)；1=不切片(零行为变化)
var lod := false               # L3 保守 LOD：true=远端 agent 降频决策（扩 N 用）；false=全保真
var lod_aggregate := false     # L3 激进 LOD：true=远端 agent 完全不跑 option/候选，只被动维持需求(冲上百 NPC)
## LOD 焦点 = **sim 内部的决定性点**（默认镇中心）。★红线（docs/19 §3）：**绝不可设成人眼相机/Probe**。
## 若"精细模拟哪块"取决于观察者在看哪，小镇历史就成了观察路径的函数 → 同存档不同看法回放出不同
## event_log → digest 不可复现、回放红线破，且窗口历史会与 headless CI 金标分叉。
## （渲染可以只画相机所在区；仿真分级不行。要做"玩家漫游"另开观察者相关的游玩视图，CI 恒跑 canonical 路径。）
var lod_focus := Vector2i(12, 8)
const AGG_RELIEF := 6.0        # 激进 far：每次被动维持给最低需求补的量
const SURVIVAL_NET_FLOOR := 8.0  # LOD 兜底：need 跌破此值就地小补（仅 LOD 开启时，补 LOD 节流/远端化造成的进食延迟；off 永不触发）
var cand_calls := 0            # 成本探针：本 run 累计候选枚举次数（LOD 收益的客观度量）
var event_digest := 0          # L4 增量滚动摘要：每事件 O(1) 折叠出的全程确定性见证（见 _log_event）

var event_log: Array = []       # 不可变事件账本（replay/debug/bench 的根）
var _next_event_id := 1
# S4：模型决策当「外部输入」记入 trace → 即使模型非确定，回放也可复现（docs/11 §5）
var decision_trace: Array = []  # [{tick,agent,kind,action,partner,subject,say,cand_hash}]（落地的模型决策）
var decision_sink: Callable = Callable()  # Phase-0 对拍数据集：默认空=off；设了则每次 logic 决策把 (ag,cands,pick_i) 喂给它。不抽 RNG、不进 event_log/digest、CI 恒空 → 红线零影响。
var record_decisions := false   # true → 记录模型决策
var replay_trace := {}          # "tick:agent_id" -> 记录的 intent（回放时用,绕过模型,确定性）
var replay_drift := 0           # 回放时记录的 pick 已不在当前合法候选(引擎逻辑变了) → 计数+兜底
var _replay_active := false
var _replay_ticks := {}         # agent_id -> [sorted 记录决策 tick]（按序+按 tick 还原异步时机）
var _replay_ptr := {}           # agent_id -> 当前回放指针

## S4：从 decision_trace 装载回放（在 start_new 前调用）。回放将复现记录的每个模型决策与其时机。
func set_replay(trace: Array) -> void:
	replay_trace = build_replay_trace(trace)
	_replay_ticks = {}
	for rec in trace:
		var aid := String(rec["agent"])
		if not _replay_ticks.has(aid):
			_replay_ticks[aid] = []
		(_replay_ticks[aid] as Array).append(int(rec["tick"]))
	for aid in _replay_ticks:
		(_replay_ticks[aid] as Array).sort()
	_replay_active = not trace.is_empty()
var commitments: Array = []     # [{id,type:"meet",a,b,area,created,deadline,status}]（全量历史，不变量/账本用）
var _active_commitments: Array = []  # 活跃工作集（引用子集）：每 tick 只扫这个 → per-tick 成本 ∝ 未决数而非累积总量(docs/14 §规模)
var _next_commit_id := 1
var conflicts: Array = []       # [{id,a(委屈方),b(冒犯方),status,triggered,severity,escalations,confronted,repaired}]
var st_neg_events := 0          # S1：累计负向 standing 评判次数（坏名声 L3 路径生效证据）
var refused_by_bound := 0       # S2：因 |Δattitude|>ε 拒谈次数（Deffuant 有界信任门生效证据）
var _next_conflict_id := 1
# S3 度量 + 派生表/台账
var endorse_events := 0
var oust_events := 0
var oust_neg_events := 0
var confide_events := 0
var betray_events := 0
var freerider_dissolves := 0
var aid_accepted := 0
var factions := {}              # medoid_id -> [member_id...]（每夜全量重建的只读视图）
var pacts_index: Array = []     # [{id,key,a,b,formed,status,defect_streak,...}]（单一真相源）
var _next_pact_id := 1
var last_broken_with := {}      # pact_key -> tick（解体冷却）
var scenario := ""              # 定向场景种子（"" / faction / betray / freerider）
var _st_delta := {}             # adjustStanding per-tick 守卫状态

## 可插拔决策后端（M2 由 Main 注入 AIBackend）。null = 用内置确定性 logic。
## 关键：Sim 不引用任何 autoload 全局名，因而能在 `--script`/headless（soak/bench）下独立实例化运行。
var backend: Object = null
## 可插拔场景/行为策略注册中枢（scripts/SimExtensions.gd，docs/14 §1）。null=纯内建行为(逐字节不变)。
## 注入同 backend：注入方 new()+register_*()+freeze() 后 S.ext=...；挂点全 `if ext != null` 短路。
var ext: Object = null

func _ready() -> void:
	_load_data()

func _process(delta: float) -> void:
	if not (auto_run and running):
		return
	_accum += delta * speed
	while _accum >= tick_interval:
		_accum -= tick_interval
		tick()

# ── 确定性 RNG（per-agent 计数器子流，docs/12 §L0）：种子混入 agent 维 who → 同 tick 同 salt 的
# 不同 agent 不再撞同一随机流(WSC15 相关坑)，且扩 N 时各 agent 的流不随 N 漂。who=0 兼容旧的非 per-agent 调用。
func _rng_at(salt: int, who: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_base + tick_no * 911 + salt * 7919 + who * 104729
	return r

## agent 维种子分量（id 的稳定哈希）。
func _aid(ag: Dictionary) -> int:
	return String(ag["id"]).hash()

# ── 数据加载 ─────────────────────────────────────────────────────────────
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("缺数据文件: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	return data if data is Dictionary else {}

func _load_data() -> void:
	needs_def = _read_json("res://data/needs.json").get("needs", [])
	world = _read_json("res://data/map.json")
	_compile_buildings()                            # 阶段2：buildings.json 编译期展开室内(直接写 world 数组/字典，须在 objects 转字典之前)
	rhythm = _read_json("res://data/rhythm.json")   # 昼夜节律偏好表（缺文件→空→_phase_pref 恒返 1.0=零扰动）
	utility = _read_json("res://data/utility.json") # 行为效用/接受权重（缺文件/缺键→_w 返代码默认=零扰动）
	economy = _read_json("res://data/economy.json") # Wave 1b 经济（缺文件→_econ_on()=false 全短路=零扰动）
	weather = _read_json("res://data/weather.json") # Wave 1c 天气（缺文件→weather_today=""=零扰动）
	jobs = _read_json("res://data/jobs.json")       # Wave 2a 职业（缺文件→_wage_for 退化=零扰动）
	skills = _read_json("res://data/skills.json")   # Wave 2c 技能（缺文件→_skill_level=0=零扰动）
	festivals = _read_json("res://data/festivals.json")  # Wave 2b 节日（缺文件→零扰动）
	secrets = _read_json("res://data/secrets.json") # 私密秘密（缺文件→无种子=零扰动）
	voicebank = _read_json("res://data/voicebank.json")  # 冻结·70B 语音库（缺文件→通用罐头=逐字节不变）
	housing = _read_json("res://data/housing.json") # Wave 3c 住房租金（缺文件→无租金=零扰动）
	elections = _read_json("res://data/elections.json") # Wave 3a 选举（缺文件→不选举=零扰动）
	lifecycle = _read_json("res://data/lifecycle.json") # Wave 3b 生命周期（缺文件→无季节无年龄=零扰动）
	# P3 Tier-B：Space/Floor/Portal 合同 + 室内内容（缺 spaces.json → 空 → 全 town/outdoor → 逐字节不变）。
	var _sp := _read_json("res://data/spaces.json")
	_spaces = _sp.get("spaces", {})
	_portals = _sp.get("portals", [])
	_interiors_data = _read_json("res://data/interiors.json")
	_compile_interiors()                            # 把带 advertises 的室内家具编译成 world 对象(标平面)，须在数组→字典之前
	var objs := {}
	for o in world.get("objects", []):
		o["pos"] = Vector2i(int(o["pos"][0]), int(o["pos"][1]))
		objs[o["id"]] = o
	world["objects"] = objs
	# 职业自带工位：extra_advertises 注入 world（跟 jobs.json 同门控 → OFF 时 map 原样）；只注一次防重入。
	# P1-5 修复：必须在 objects 数组→字典【之后】注入——此前 world["objects"] 还是 Array，.has(oid) 对字符串 id
	# 恒 false，看摊等职业工位从未真正加进 advertises（阿丽/阿林技能 30 天恒 Lv0）。字段访问加默认防脏数据。
	if not jobs.is_empty() and not _jobs_injected:
		_jobs_injected = true
		for ea in jobs.get("extra_advertises", []):
			var oid := String(ea.get("object", ""))
			if world["objects"].has(oid):
				var od: Dictionary = world["objects"][oid]
				if not od.has("advertises"):
					od["advertises"] = []
				(od["advertises"] as Array).append({
					"action": String(ea.get("action", "")), "need": String(ea.get("need", "")),
					"amount": int(ea.get("amount", 0)), "duration": int(ea.get("duration", 0))})

## 阶段2（docs/16 §10+）：把 data/buildings.json 编译期展开进 world（rooms + 家具 objects）。
## 确定性红线：直接写 world 字典/数组、【不经 spawn_object】(那会写 event→digest 漂/破 off 门)；
## 无 RNG/Time/计数器——变体用 _hash01(房间id) 选、authored 顺序遍历、家具 id=slot:房间:序(唯一确定)。
## 纯追加、不覆盖 map.json 手写房间。缺 buildings.json → 不编译 → 阶段1 逐字节不变(off 门)。
## 必须在 _load_data 里 objects 数组→字典转换【之前】调用（追加进数组，随后统一转字典/设区）。
func _compile_buildings() -> void:
	if _buildings_compiled:
		return
	var bdata := _read_json("res://data/buildings.json")
	if bdata.is_empty():
		return
	_buildings_compiled = true
	var templates: Dictionary = _read_json("res://data/room_templates.json").get("templates", {})
	var rooms: Dictionary = world.get("rooms", {})
	var objs: Array = world.get("objects", [])
	# 健壮性护栏（stage-2 review 五条 CONFIRMED）：编译管线把"JSON 数据正确性"升成了确定性红线的一部分，
	# 一个数据笔误可能静默破 digest / 崩载入半改 world / 每 tick 崩。以下护栏对合规数据全是 no-op（逐字节不变），
	# 只把畸形项【确定性地跳过 + push_error】而非中止/半改（rooms/objs 是 world 活引用，early-return 也会留残缺）。
	for b in bdata.get("buildings", []):
		if not (b is Dictionary):
			continue
		var bid := String((b as Dictionary).get("id", ""))
		for rm in _as_arr((b as Dictionary).get("rooms", [])):
			if not (rm is Dictionary):
				continue                                    # 非对象房间项 → 跳过（否则 `var rd: Dictionary = rm` 崩）
			var rd: Dictionary = rm
			var rid := String(rd.get("id", ""))
			if rid == "" or rooms.has(rid):
				continue                                    # 不覆盖 map.json 已有房间
			var rr: Array = _as_arr(rd.get("rect", [0, 0, 0, 0]))
			if rr.size() < 4:
				push_error("buildings 房间 rect 非法(需4元)，跳过整间: " + rid)
				continue                                    # 畸形 rect → 跳过（否则 int(rr[0..3]) 越界读中止函数、半改 world）
			var rtype := String(rd.get("type", rid))
			rooms[rid] = {"rect": rr, "enclosed": bool(rd.get("enclosed", true)),
				"type": rtype, "building": bid, "owner": String(rd.get("owner", ""))}
			var tv = templates.get(String(rd.get("furnish", rtype)), {})
			var tmpl: Dictionary = tv if tv is Dictionary else {}
			var furni: Array = _as_arr(tmpl.get("furniture", [])).duplicate(true)
			var variants: Array = _as_arr(tmpl.get("variants", []))
			if not variants.is_empty():
				var vi := int(_hash01(rid + ":var") * float(variants.size())) % variants.size()
				if variants[vi] is Dictionary:
					for extra in _as_arr((variants[vi] as Dictionary).get("add", [])):
						furni.append(extra)
			var fseq := 0
			for f in furni:
				var oid := "%s_%s_%d" % [String((f as Dictionary).get("slot", "obj")) if f is Dictionary else "obj", rid, fseq]
				fseq += 1                                   # 先占号：畸形/撞车项被跳过时后续家具 id 仍稳定
				if not (f is Dictionary):
					continue
				var fd: Dictionary = f
				var dp: Array = _as_arr(fd.get("dpos", [0, 0]))
				if dp.size() < 2:
					push_error("buildings 家具 dpos 非法(需2元)，跳过: " + oid)
					continue                                # 畸形 dpos → 跳过（否则 int(dp[0..1]) 越界读中止函数）
				var apos := Vector2i(int(rr[0]) + int(dp[0]), int(rr[1]) + int(dp[1]))
				var dup := false
				for eo in objs:
					if String((eo as Dictionary).get("id", "")) == oid:
						dup = true; break
				if dup:
					push_error("buildings 家具 id 撞车，跳过(否则静默覆盖→改候选集→破 digest): " + oid)
					continue
				var ar := _area_at(apos)
				if ar == "":
					push_error("buildings 家具越界(area='')，跳过(否则凭空候选→漂 digest): " + oid)
					continue
				objs.append({"id": oid, "type": String(fd.get("type", "")), "area": ar,
					"pos": [apos.x, apos.y], "advertises": _as_arr(fd.get("advertises", [])).duplicate(true)})
	world["rooms"] = rooms
	world["objects"] = objs

## P3 Tier-B：把 interiors.json 里【带 advertises】的室内家具编译成 world 对象（标平面 space/floor/area）。
## 纯装饰家具(无 advertises)不进 world（只 WorldView 渲染）。确定性：authored 顺序、id=space+floor+slot、无 RNG/Time。
## 非-town 平面 → _object_candidates 按平面门只对该层居民可见、_build_nav 只进该层网（绝不进 town _blocked）。
## 缺 interiors.json / 无 advertises → 不加对象 → 全 town → 逐字节不变。须在 objects 数组→字典【之前】调。
func _compile_interiors() -> void:
	if _interiors_data.is_empty():
		return
	var objs: Array = world.get("objects", [])
	for space in _interiors_data:
		if String(space).begins_with("_") or not (_interiors_data[space] is Dictionary):
			continue
		for floor in (_interiors_data[space] as Dictionary):
			var content = _interiors_data[space][floor]
			if not (content is Dictionary):
				continue
			for fu in _as_arr((content as Dictionary).get("furniture", [])):
				if not (fu is Dictionary):
					continue
				var adv: Array = _as_arr((fu as Dictionary).get("advertises", []))
				if adv.is_empty():
					continue                        # 纯装饰 → 不进 world（只渲染）
				var pos: Array = _as_arr((fu as Dictionary).get("pos", [0, 0]))
				if pos.size() < 2:
					continue
				var slot := String((fu as Dictionary).get("slot", "obj"))
				objs.append({
					"id": "%s%s_%s" % [space, floor, slot], "type": String((fu as Dictionary).get("label", slot)),
					"pos": [int(pos[0]), int(pos[1])],
					"space": String(space), "floor": String(floor), "area": String(space) + ":" + String(floor),
					"staff": bool((fu as Dictionary).get("staff", false)),   # P3：员工专属对象(吧台)——只有该店主人用；顾客用公共桌
					"advertises": adv.duplicate(true)})
	world["objects"] = objs

## Variant→Array 强转（缺失/错类型的 JSON 数组字段一律退化为空，守"错类型=零扰动"契约，替代会崩的 `as Array`）。
func _as_arr(v: Variant) -> Array:
	return v if v is Array else []

func start_new(p_seed: int = 12345) -> void:
	emit_signal("world_reset")             # 新世界 → 通知 AIBackend 取消所有在飞请求 + 进新 epoch（旧回包作废）。CI 无监听=no-op。
	seed_base = p_seed
	tick_no = 0
	day = 1
	_accum = 0.0
	agents.clear()
	_agent_by_id.clear()
	event_log.clear()
	_next_event_id = 1
	event_digest = 0
	cand_calls = 0
	commitments.clear()
	_active_commitments.clear()
	_next_commit_id = 1
	conflicts.clear()
	_next_conflict_id = 1
	st_neg_events = 0
	refused_by_bound = 0
	endorse_events = 0; oust_events = 0; oust_neg_events = 0
	confide_events = 0; betray_events = 0; freerider_dissolves = 0; aid_accepted = 0
	factions.clear(); pacts_index.clear(); _next_pact_id = 1; last_broken_with.clear(); _st_delta.clear()
	decision_trace.clear(); replay_drift = 0   # S4 per-run 重置（replay_trace 由调用方控制，不在此清）
	_replay_ptr = {}
	for aid in _replay_ticks:
		_replay_ptr[aid] = 0
	var personas := _read_json("res://data/personas.json")
	var adata: Array = _read_json("res://data/agents.json").get("agents", [])
	var defs := adata.duplicate(true)
	# 扩 N：克隆扩容到 spawn_count（确定性：persona 轮转、按区心生成、id 唯一→天生立场各异）
	if spawn_count > defs.size():
		var area_ids: Array = world.get("areas", {}).keys()
		for i in range(defs.size(), spawn_count):
			var base: Dictionary = adata[i % adata.size()]
			var c := _area_centroid(String(area_ids[i % maxi(1, area_ids.size())])) if not area_ids.is_empty() else Vector2i(2 + i % 20, 2 + i % 12)
			var sp := Vector2i(c.x + (i % 3) - 1, c.y + ((i / 3) % 3) - 1)
			defs.append({"id": "npc_%d" % i, "persona": base["persona"], "spawn": [sp.x, sp.y], "home": [sp.x, sp.y]})
	for adef in defs:
		var ag := _make_agent(adef, personas)
		agents.append(ag)
		_agent_by_id[ag["id"]] = ag
	# 种子谣言：阿丽（消息最灵通）知道一条关于可可的传闻 → 之后靠 gossip 扩散（验证知识边界+传播）
	if _agent_by_id.has("aria"):
		_agent_by_id["aria"]["beliefs"]["R1"] = {
			"claim": "可可最近心事重重", "subject": "coco", "source": "__seed__", "via": "seed", "tick": 0}
	# 私密秘密：只在默认沙盘（scenario 空）给每人一条 self-subject 秘密 → 有信任知己时才 confide，被转述即 leak/betray。
	# 缺 secrets.json 或非默认场景 → 不播种 → 逐字节不变（off 门）；定向场景(betray/faction/freerider)保持纯净可机检。
	if scenario == "" and not secrets.is_empty():
		for s in secrets.get("seeds", []):
			var oid := String(s.get("owner", ""))
			if not _agent_by_id.has(oid):
				continue
			var sid := "S_own_" + oid              # 唯一 id，与 betray 的 S_coco 不撞
			_agent_by_id[oid]["beliefs"][sid] = {"claim": String(s.get("claim", "")), "subject": oid,
				"source": oid, "via": "seed", "tick": 0, "secret": true, "owner": oid, "confidedBy": {}}
	# Wave 1b 经济：镇库注资 + 记录开局货币总量（守恒硬不变量基准）。缺 economy.json → 全为 0 零扰动。
	town_coin = int(economy.get("town_start", 0)) if not economy.is_empty() else 0
	econ_stats = {"meals_paid": 0, "meals_free": 0, "wages_paid": 0, "wages_skipped": 0}
	econ_total0 = money_total()
	election_log.clear(); last_election = {}   # Wave 3a：per-run 重置（goto_tick 反复 start_new）
	weather_today = _weather_of_day(day)   # Wave 1c：开局天气（日界在 tick() 重算）
	season_today = _season_of_day(day)     # Wave 3b：开局当季（日界在 tick() 重算；纯 f(day)）
	# Wave 2b/3a：world 只在 _load_data 载一次 → start_new(含 goto_tick 重演)必须清上一局残留的动态对象再重开。
	# fest_=节日临时对象；civic_=选举通过的永久 WorldPatch（本局内永存，但换局/回放重演须清，靠选举日重新 spawn 确定重建）。
	for oid in world.get("objects", {}).keys():
		if String(oid).begins_with("fest_") or String(oid).begins_with("civic_"):
			world["objects"].erase(oid)
	_fest_objects.clear()
	_build_nav()                        # 导航网：清完动态对象后按静态家具重建（每局同一张确定网）
	_path_cache = {}                    # 路径缓存 per-run 清空（goto_tick 重演一致）
	festival_active = ""
	_update_festival()
	if ext != null:
		ext.freeze()                 # 幂等排序（注册在注入时已做；这里只保证 goto_tick 反复 start_new 前 ext 就绪、定序）
	_seed_scenario()                 # S3 定向场景种子（faction/betray/freerider；空=默认）
	_recompute_factions()            # S3a 首日预算：让 day-1 候选可读 faction
	running = true
	emit_signal("day_changed", day)

# S3 定向场景种子（小N下罕见但关键路径可机检；镜像端口）。
func _seed_scenario() -> void:
	if ext != null and ext.seed_scenario(self, scenario):
		return                          # 注册的 ScenarioProvider 接管 → 跳过内建 if/elif（ext=null/无此场景则回落）
	if scenario == "betray" and _agent_by_id.has("aria") and _agent_by_id.has("coco"):
		var aria: Dictionary = _agent_by_id["aria"]
		aria["beliefs"]["S_coco"] = {"claim": "可可偷偷喜欢着谁", "subject": "coco", "source": "coco", "via": "confide", "tick": 0, "secret": true, "owner": "coco", "confidedBy": {"coco": 0}}
		_rel(aria, "coco")["resentment"] = 12.0
		_rel(aria, "coco")["affinity"] = -20.0
		_log_event("confide", "coco", "aria", "S_coco", true, [], "seed")
	elif scenario == "faction" and agents.size() >= 6:
		for i in range(3):
			for t in TOPICS: agents[i]["attitudes"][t] = 0.8; agents[i]["attitude0"][t] = 0.8
		for i in range(3, agents.size()):
			for t in TOPICS: agents[i]["attitudes"][t] = -0.8; agents[i]["attitude0"][t] = -0.8
		_rel(agents[0], String(agents[3]["id"]))["standing"] = -3.0
	elif scenario == "freerider" and agents.size() >= 2:
		var a: Dictionary = agents[0]
		var b: Dictionary = agents[1]
		var key := _pact_key(String(a["id"]), String(b["id"]))
		a["pacts"][b["id"]] = {"partner": b["id"], "key": key, "formedTick": 0, "status": "active", "given": 6, "received": 1, "lastAidTick": 0}
		b["pacts"][a["id"]] = {"partner": a["id"], "key": key, "formedTick": 0, "status": "active", "given": 1, "received": 6, "lastAidTick": 0}
		pacts_index.append({"id": _next_pact_id, "key": key, "a": a["id"], "b": b["id"], "formed": 0, "status": "active", "defect_streak": 0, "formTrustA": PACT_TRUST_TH, "formTrustB": PACT_TRUST_TH, "formFam": PACT_FAM_TH, "formComplement": PACT_COMPLEMENT_TH})
		_next_pact_id += 1
		_rel(a, String(b["id"]))["trust"] = 20.0; _rel(b, String(a["id"]))["trust"] = 20.0
		a["complementSeen"][b["id"]] = PACT_COMPLEMENT_TH; b["complementSeen"][a["id"]] = PACT_COMPLEMENT_TH

## 构建一个 agent（数据 def 或克隆 def 共用；确定性，天生立场由 id hash）。
func _make_agent(adef: Dictionary, personas: Dictionary) -> Dictionary:
	# P3 Tier-B 平面地址：带 spatial_address{space_id,floor_id,position} 的居民住非-town 平面（如阿丽 cafe/2f）；
	# pos 是【该 floor 内】的格。缺 spatial_address → town/outdoor + spawn（其余 11 人一行不变、逐字节一致）。
	var sa: Dictionary = adef.get("spatial_address", {}) if adef.get("spatial_address", {}) is Dictionary else {}
	var a_space := String(sa.get("space_id", "town"))
	var a_floor := String(sa.get("floor_id", "outdoor"))
	var a_pos: Vector2i = _v2i(sa["position"]) if sa.has("position") else Vector2i(int(adef["spawn"][0]), int(adef["spawn"][1]))
	var ag := {
		"id": adef["id"],
		"persona": personas.get(adef["persona"], {}),
		"persona_key": String(adef.get("persona", "")),   # 人设 id（voicebank/scriptwriter 按此键；克隆继承基座人设 id）
		"pos": a_pos,
		"home": Vector2i(int(adef["home"][0]), int(adef["home"][1])),
		"space": a_space, "floor": a_floor,
		"home_space": a_space, "home_floor": a_floor,     # 家=起始平面（阿丽=cafe/2f）→ 回家 traverse 目标
		"cafe_regular": bool(adef.get("cafe_regular", false)),   # P3：咖啡馆常客(营业时段进店喝咖啡+社交)；缺=false=不进店
		"needs": {},
		"option": null,
		"mood": "neutral",
		"talking": 0,
		"inventory": {"gift": GIFT_START},
		"relationships": {},
		"beliefs": {},
		"affinity": {},
		"attitudes": {}, "attitude0": {},
		"xi": 0.3, "eps": CONF_BOUND,
		"stifled": {}, "metKnower": {},
		"faction": "", "faction_size": 1,
		"pacts": {}, "complementSeen": {},
		"skills": {},                # Wave 2c：本职动作熟练度计数（缺 skills.json 时恒空、不读=零扰动）
		"thinking": false,
		"last_say": "",
		"memory": MemoryStreamScript.new(),
	}
	for n in needs_def:
		ag["needs"][n["id"]] = 72.0
	var tr: Array = ag["persona"].get("traits", [])
	ag["xi"] = 0.45 if ("好奇" in tr or "热情" in tr) else (0.18 if ("寡言" in tr or "务实" in tr) else 0.30)
	ag["eps"] = 1.1 if ("好奇" in tr or "豁达" in tr) else (0.55 if ("敏感" in tr or "寡言" in tr) else CONF_BOUND)
	for t in TOPICS:
		var a0 := _hash01(str(adef["id"]) + ":" + t) * 2.0 - 1.0
		ag["attitude0"][t] = a0
		ag["attitudes"][t] = a0
	ag["area"] = _area_key(ag["space"], ag["floor"], ag["pos"])   # P3 Tier-B：平面感知 area（town 恒等旧值）
	ag["room"] = _room_at(ag["pos"])   # docs/16：与 area 同址缓存（缺 rooms→""）
	if not economy.is_empty():
		ag["inventory"]["coin"] = int(economy.get("start_coin", 10))   # Wave 1b：经济开启才有钱（缺文件零扰动）
	return ag

func get_agent(id: String) -> Dictionary:
	return _agent_by_id.get(id, {})

# ── 玩家能动性（gameplay）：玩家=一等社交 agent，走同一套 SocialTransaction ─────────
## 玩家入镇（仅窗口模式调用；headless bench 从不加 → 确定性地板零回归）。
## 入 agents 即入社交图：NPC 会主动找玩家 greet/gossip/confide/邀约；接受规则/关系账本/记忆/旁观者对玩家全部生效。
const MEDIATE_AFF := 5.0        # 调解门槛：冲突双方对玩家好感 ≥ 此才听得进劝
# 引擎内建社交动作全集（conflict 类在 _commit_social 上游单独分流）；不在此集=扩展动作 → 走 ext.execute（L7 挂点#2）
const KNOWN_SOCIAL_ACTIONS := ["greet", "give", "gossip", "gossip_rep", "discuss", "invite", "confide", "leak", "endorse", "aid", "mediate"]
func add_player(pos: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if _agent_by_id.has("player"):
		return _agent_by_id["player"]
	var p := pos
	if p.x < 0:
		p = _area_centroid("plaza")
	var pl := _make_agent({"id": "player", "persona": "", "spawn": [p.x, p.y], "home": [p.x, p.y]}, {})
	pl["is_player"] = true
	pl["persona"] = {"name": "你", "color": "#ffd700", "traits": [], "bio": "刚搬来的新居民。", "style": "", "sprite": ""}
	for nid in pl["needs"]:
		pl["needs"][nid] = 100.0    # M1：玩家需求冻结（不衰减）；后续可开生存玩法
	agents.append(pl)
	_agent_by_id["player"] = pl
	econ_total0 += int(pl["inventory"].get("coin", 0))   # 玩家带钱入镇 → 守恒基准同步上调（钱不凭空出现）
	emit_signal("agent_changed", "player")
	return pl

## 玩家格移动（WASD/方向键）。走 _move_agent 以刷新 area 缓存（NPC 的邻近枚举依赖它）。
func player_move(dir: Vector2i) -> void:
	var pl: Dictionary = _agent_by_id.get("player", {})
	if pl.is_empty() or int(pl["talking"]) > 0:
		return
	var np: Vector2i = pl["pos"] + dir
	if np.x < 0 or np.y < 0 or np.x >= int(world.get("width", 24)) or np.y >= int(world.get("height", 16)):
		return
	_move_agent(pl, np)
	emit_signal("agent_changed", "player")

## 玩家社交动作：验证前提 → _apply_social 发起 → tick 推进 → _commit_social 裁决（NPC 可拒绝玩家！）。
## 返回 "" = 已发起；非空 = 不可行原因（HUD 显示）。
func player_act(action: String, target_id: String) -> String:
	var pl: Dictionary = _agent_by_id.get("player", {})
	if pl.is_empty():
		return "玩家未入镇"
	var tgt: Dictionary = _agent_by_id.get(target_id, {})
	if tgt.is_empty() or tgt.get("is_player", false):
		return "先点选一位居民"
	# 邻近判定（对抗审查#6）：须同一【非空】区域，或曼哈顿距离≤2——堵住"区域外空地 '' == '' 隔全图社交"漏洞
	var here := String(pl.get("area", ""))
	var mdist := absi(pl["pos"].x - tgt["pos"].x) + absi(pl["pos"].y - tgt["pos"].y)
	if not ((here != "" and here == String(tgt.get("area", ""))) or mdist <= 2):
		return "太远了，走近点（同一区域或贴身）"
	if int(pl["talking"]) > 0:
		return "正在交谈中"
	if int(tgt["talking"]) > 0:
		return "%s 正忙着呢" % _name(tgt)
	var subject := ""
	var say := ""
	match action:
		"greet":
			say = "嗨，%s！" % _name(tgt)
		"give":
			if int(pl["inventory"].get("gift", 0)) <= 0:
				return "没有礼物了"
			say = "%s，这个送你。" % _name(tgt)
		"gossip":
			subject = _unspread_belief(pl, tgt)
			if subject == "":
				return "没有对方不知道的传闻（先从别人那儿打听）"
			say = "跟你说个事……"
		"invite":
			if _has_active_meet("player", target_id):
				return "和%s已有未赴的约（先赴约或等它过期）" % _name(tgt)   # 防同对叠约刷好感（对抗审查#7）
			say = "%s，回头在这儿碰个面？" % _name(tgt)
		"confront":
			# 玩家是委屈方(a=player)时当面理论 → 走 _resolve_confront 状态机（对方接茬→confronted→对方会来道歉）（对抗审查#5）
			if _find_conflict("player", target_id, ["simmering", "escalated", "lingering"]).is_empty():
				return "你和%s之间没有要理论的疙瘩" % _name(tgt)
			say = "%s，那件事我们得说道说道。" % _name(tgt)
		"apologize":
			if _find_conflict(target_id, "player", ["confronted"]).is_empty():
				return "对方还没跟你把话挑明（无待道歉的冲突）"
			say = "那件事……是我不对。"
		_:
			return "未知动作"
	_apply_social(pl, {"kind": "social", "action": action, "partner": target_id, "subject": subject, "say": say})
	if pl.get("option") == null:
		return "现在开不了口（对方刚走开？）"
	return ""

## 玩家专属「调解」：促成 target 所涉冲突的和解。确定性规则=双方对玩家好感 ≥ MEDIATE_AFF 才听劝。
## 成功 → 冲突 repaired + 清怨气 + 双方互信/好感回升 + 都感谢玩家 + 旁观者视玩家为 help（standing↑）。
func player_mediate(target_id: String) -> String:
	var pl: Dictionary = _agent_by_id.get("player", {})
	if pl.is_empty():
		return "玩家未入镇"
	var tgt: Dictionary = _agent_by_id.get(target_id, {})
	if tgt.is_empty():
		return "先点选一位居民"
	var c := {}
	var own_conflict := false
	for cc in conflicts:
		if not (String(cc["status"]) in ["simmering", "escalated", "confronted", "lingering"]):
			continue
		if not (cc["a"] == target_id or cc["b"] == target_id):
			continue
		if cc["a"] == "player" or cc["b"] == "player":
			own_conflict = true      # 玩家自己卷入的疙瘩不能"自我调解"（对抗审查#4：防 _rel(player,player) 自我关系）
			continue
		c = cc
		break
	if c.is_empty():
		if own_conflict:
			return "这是你和%s之间的疙瘩——按 T 当面理论，或等对方挑明后按 P 道歉" % _name(tgt)
		return "%s 没有待化解的冲突" % _name(tgt)
	var A: Dictionary = _agent_by_id.get(String(c["a"]), {})
	var B: Dictionary = _agent_by_id.get(String(c["b"]), {})
	if A.is_empty() or B.is_empty():
		return "冲突另一方不在了"
	var here := String(pl.get("area", ""))
	if here == "" or String(A.get("area", "")) != here or String(B.get("area", "")) != here:
		return "得把 %s 和 %s 都请到同一区域才好说和" % [_name(A), _name(B)]
	var witnesses: Array = []
	for w in _nearby_agents(pl):
		if w["id"] != A["id"] and w["id"] != B["id"]:
			witnesses.append(w)
	var aff_a := float(_rel(A, "player")["affinity"])
	var aff_b := float(_rel(B, "player")["affinity"])
	if aff_a >= MEDIATE_AFF and aff_b >= MEDIATE_AFF:
		c["status"] = "repaired"
		c["repaired"] = tick_no
		# inv12/13 溯源语义（对抗审查#2）：调解=在玩家撮合下"当面说开+道了歉"——补记 confront/apologize 接受事件，
		# 使"先对质后和解/修复可溯源"硬不变量在含玩家的局面上依然成立（bench 无玩家不受影响）。
		if int(c["confronted"]) == 0:
			c["confronted"] = tick_no
			var ec := _log_event("confront", A["id"], B["id"], "", true, witnesses, "mediated")
			emit_signal("social_event", ec)
		var ea := _log_event("apologize", B["id"], A["id"], "", true, witnesses, "mediated")
		emit_signal("social_event", ea)
		var ra := _rel(A, B["id"])
		var rb := _rel(B, A["id"])
		ra["resentment"] = 0.0
		ra["trust"] = clampf(float(ra["trust"]) + 4.0, -100.0, 100.0)
		rb["trust"] = clampf(float(rb["trust"]) + 2.0, -100.0, 100.0)
		ra["affinity"] = clampf(float(ra["affinity"]) + 5.0, -100.0, 100.0)
		rb["affinity"] = clampf(float(rb["affinity"]) + 5.0, -100.0, 100.0)
		_rel(A, "player")["affinity"] = clampf(aff_a + 3.0, -100.0, 100.0)
		_rel(B, "player")["affinity"] = clampf(aff_b + 3.0, -100.0, 100.0)
		var ev := _log_event("mediate", "player", A["id"], B["id"], true, witnesses)
		ra["last_pos"] = ev["id"]; rb["last_pos"] = ev["id"]
		for w in witnesses:
			_judge_actor(w, "player", true, A["id"])   # 旁观者：玩家在 help → 名声↑
		A["memory"].add("多亏你从中说和，我和%s的疙瘩解开了" % _name(B), 7, tick_no, ["player", "conflict", "repair"])
		B["memory"].add("你劝我和%s把话说开，心里松了口气" % _name(A), 7, tick_no, ["player", "conflict", "repair"])
		pl["memory"].add("说和了%s和%s" % [_name(A), _name(B)], 6, tick_no, [A["id"], B["id"], "mediate"])
		pl["last_say"] = "都消消气，坐下聊聊。"
		emit_signal("social_event", ev)
		return ""
	var ev2 := _log_event("mediate", "player", A["id"], B["id"], false, witnesses)
	# 失败代价对称（对抗审查#10）：谁没听进去谁降好感——双方都冷淡则都降，别让 B 白嫖
	var colds: Array = []
	if aff_a < MEDIATE_AFF: colds.append(A)
	if aff_b < MEDIATE_AFF: colds.append(B)
	var cold_names: Array = []
	for cd in colds:
		_rel(cd, "player")["affinity"] = clampf(float(_rel(cd, "player")["affinity"]) - 1.0, -100.0, 100.0)
		cold_names.append(_name(cd))
	pl["memory"].add("想劝和%s和%s，%s没听进去" % [_name(A), _name(B), "和".join(cold_names)], 5, tick_no, [A["id"], B["id"], "mediate"])
	emit_signal("social_event", ev2)
	return "%s 还不信任你（好感不够），先处好关系再来劝" % "和".join(cold_names)

## 确定性回放：重置到当前种子并推进到 target tick（观察台时间轴 scrub 用）。
## 因全程确定性，重演必得同一状态——无需存快照即可前后拖动。
func goto_tick(target: int) -> void:
	var a := auto_run
	auto_run = false
	# 玩家豁免（对抗审查#1）：start_new 只从数据重建 NPC，会把玩家连人带关系清掉 → scrub 后 WASD/动作全失灵。
	# 记住玩家（位置/物品）→ 重演后原位放回。诚实局限：玩家的历史干预不在重演里（player_act 非 decision_trace），
	# 时间轴呈现的是"无玩家介入的平行世界"+玩家现身当下；根治=player_trace 回放（S4 范式），留待后续。
	var had_player := _agent_by_id.has("player")
	var p_pos := Vector2i.ZERO
	var p_inv := {}
	if had_player:
		p_pos = _agent_by_id["player"]["pos"]
		p_inv = (_agent_by_id["player"]["inventory"] as Dictionary).duplicate()
	start_new(seed_base)
	replaying = true                       # 回放期间 AIBackend.decide 走 logic，不发 live 请求(P1-6)
	var t := maxi(0, target)
	while tick_no < t:
		tick()
	replaying = false
	if had_player:
		var pl := add_player(p_pos)
		pl["inventory"] = p_inv
	auto_run = a

## 导出本局事件账本为可存档 trace（seed + event_log）。
func export_trace(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"seed": seed_base, "tick": tick_no, "events": event_log}, "  "))
		f.close()

# ── R0-2 存档 / 读档（可恢复的"过日子"存档）─────────────────────────────────
## 设计（analysis §Phase-2 / codex 评审 R0-2）：**全量状态快照**（provenance 无关——玩家动作/模型选择/
## 场景补丁怎么来的都不管，只存最终权威状态）。用反射抓【每个脚本 var】→ 完整性不靠手列（新增 var 自动纳入），
## 跳过 Object/Callable（backend/ext/decision_sink 是运行期接线、非状态，且反序列化不该实例化对象=安全）。
## ★关键事实：RNG 无状态（`_rng_at` 纯 f(seed_base,tick_no)）→ 没有 RNG 态要存，seed+tick 已在 var 里。
## 红线：save 只读状态+写文件（不动 digest）；load 只在用户显式读档时调（CI/tick 从不经此）→ digest 零影响。
const SAVE_MAGIC := "LTSAVE"
const SAVE_SCHEMA := 1

func save_game(path: String, meta := {}) -> bool:
	# 派生引用结构【不入档】：它们只是 agents[]/commitments[] 的别名视图，存了也只能得到孤儿副本；
	# 读档后由 _rebuild_after_load 从真源重建（_active_commitments 靠下面存的 id 列表还原成员资格）。
	const DERIVED := ["_agent_by_id", "_active_commitments", "_near_set", "_path_cache", "_nav_grids"]
	var state := {}
	for p in get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if String(p["name"]) in DERIVED:
			continue
		var v = get(p["name"])
		if v is Object or v is Callable:            # backend/ext/decision_sink：接线非状态，不入档
			continue
		state[p["name"]] = v
	# agent["memory"] 是【嵌套 Object】（MemoryStream）——store_var 会把它编码成 EncodedObjectAsID 死壳，
	# 读回后 mem.add() 直接崩（硬门抓到的头号 bug）。→ 存它的 items 数据，读档时重建对象。
	var ser_agents := []
	for ag in agents:
		var d: Dictionary = (ag as Dictionary).duplicate(true)   # 深拷贝纯数据；Object 引用照抄→下一行替换掉
		var mem = ag.get("memory")
		d["memory"] = {"__mem_items__": (mem.items as Array).duplicate(true) if mem is Object and "items" in mem else []}
		ser_agents.append(d)
	state["agents"] = ser_agents
	# fail-closed：状态里若还残留任何嵌套 Object/Callable（未来有人加新对象字段），宁可拒存也不写坏档。
	var leaks: Array = []
	_scan_objects(state, "state", leaks)
	if not leaks.is_empty():
		push_error("save_game REFUSED — nested Object/Callable in state (serialize them like memory): %s" % ", ".join(leaks))
		return false
	var active_ids := []                            # 活跃承诺的成员资格（id）——重建工作集用
	for c in _active_commitments:
		active_ids.append(int(c.get("id", -1)))
	var blob := {
		"magic": SAVE_MAGIC, "schema": SAVE_SCHEMA,
		"game_version": String(ProjectSettings.get_setting("application/config/version", "dev")),
		"saved_tick": tick_no, "saved_day": day, "seed": seed_base, "meta": meta,
		"active_commit_ids": active_ids, "state": state,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("save_game: cannot open %s" % path)
		return false
	f.store_32(SAVE_SCHEMA)                          # 头 4 字节=schema：坏档/旧档快速判，不误读
	f.store_var(blob)                               # store_var=var_to_bytes（默认不含 Object=安全，我们本就跳过）
	f.close()
	return true

## 读档头（不落地状态）：给 UI 列存档用。坏档/版本不符 → 返回 {}。
func peek_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 8 or f.get_32() != SAVE_SCHEMA:
		return {}
	var blob = f.get_var()
	f.close()
	if not (blob is Dictionary) or blob.get("magic") != SAVE_MAGIC:
		return {}
	blob.erase("state")                             # 只回头信息
	return blob

func load_game(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 8:
		return false
	var sch := f.get_32()
	if sch != SAVE_SCHEMA:                           # 版本不符 → 拒绝，绝不静默套错格式
		f.close()
		push_warning("load_game: schema %d != %d, refusing" % [sch, SAVE_SCHEMA])
		return false
	var blob = f.get_var()
	f.close()
	if not (blob is Dictionary) or blob.get("magic") != SAVE_MAGIC:
		return false
	var state: Dictionary = blob.get("state", {})
	for k in state:
		set(k, state[k])
	_rebuild_after_load(blob.get("active_commit_ids", []))
	emit_signal("world_reset")               # 读档=换世界：AIBackend cancel_all(bump epoch)，在飞旧回包一律作废（P1-3 同款）
	return true

## 深扫状态树找残留 Object/Callable（save_game 的 fail-closed 门用）。
func _scan_objects(v, path: String, out: Array) -> void:
	if v is Object or v is Callable:
		out.append(path)
	elif v is Dictionary:
		for k in v:
			_scan_objects(v[k], path + "." + str(k), out)
	elif v is Array:
		for i in (v as Array).size():
			_scan_objects(v[i], path + "[%d]" % i, out)

## 反序列化后：agents[] 与 _agent_by_id / _active_commitments 已成【各自独立副本】——
## 必须重建成【同一引用】，否则经其一改状态不动另一处 → 续跑立刻漂（这就是全套硬门要抓的头号 bug）。
func _rebuild_after_load(active_commit_ids: Array = []) -> void:
	for ag in agents:                                # 记忆：从 items 数据重建 MemoryStream 对象
		var m = ag.get("memory")
		if m is Dictionary and (m as Dictionary).has("__mem_items__"):
			var mem = MemoryStreamScript.new()
			mem.items = (m["__mem_items__"] as Array)
			ag["memory"] = mem
		elif not (m is Object):                      # 缺/坏 → 空记忆兜底（老档也能开）
			ag["memory"] = MemoryStreamScript.new()
	_agent_by_id.clear()
	for ag in agents:
		_agent_by_id[String(ag["id"])] = ag
	var want := {}                                   # 档里存的活跃 id → 映回 commitments[] 的真引用
	for i in active_commit_ids:
		want[int(i)] = true
	_active_commitments = []
	for c in commitments:
		if want.has(int(c.get("id", -1))):
			_active_commitments.append(c)
	_near_set = {}                                   # 每 tick 重算，清空即可
	_build_nav()                                     # P3：从 world/_spaces 重建 town _blocked + 各平面 _nav_grids（派生，不入档）
	_path_cache = {}

# ── 主循环 ───────────────────────────────────────────────────────────────
func tick() -> void:
	tick_no += 1
	if lod_near_cap > 0 and (lod or lod_aggregate):
		_compute_near_set()
	for ag in agents:
		_decay_needs(ag)
		_advance_agent(ag)
	_resolve_commitments()              # 解算到场/爽约
	_sweep_conflicts()                  # 久未对质的冲突 → lingering
	if tick_no % TICKS_PER_DAY == 0:
		day += 1
		weather_today = _weather_of_day(day)   # Wave 1c：日界换天气（纯 f(seed,day)）
		var _prev_season := season_today
		season_today = _season_of_day(day)     # Wave 3b：换季（纯 f(day)，按序 春夏秋冬）
		_update_lifecycle(_prev_season)        # Wave 3b：换季/生日里程碑（喂 voice grounding）
		_update_festival()                     # Wave 2b：昨日节日清场 → 今日按 日取模+天气 开节（确定）
		_update_election()                     # Wave 3a：到期把话题付诸投票（S2 attitude 即选票，快照纯函数计票）
		if ext != null:
			ext.seed_day(self, scenario, day)  # 周更编剧：schedule 里 day==当天的补丁到点确定性注入（无 schedule→零扰动）
		_nightly()
		emit_signal("day_changed", day)
	emit_signal("ticked", tick_no)

func time_of_day() -> float:
	return float(tick_no % TICKS_PER_DAY) / float(TICKS_PER_DAY)  # 0..1

## 咖啡馆营业时段（纯 f(tick)，无 RNG/Time）→ 顾客进店只在白天揽客窗口。
func _cafe_open() -> bool:
	var tod := time_of_day()
	return tod >= CAFE_OPEN_LO and tod < CAFE_OPEN_HI

## 昼夜节律（"行动↔时间同频"，docs/14）：确定性纯查表——tod=f(tick_no)，无 RNG/无 Time/区间不重叠故不依赖字典序。
## 时段名 = phases 里首个覆盖 tod 的半开区间 [lo,hi)；缺表/缺键 → 空/default。
func _phase_of(tod: float) -> String:
	var phases: Dictionary = rhythm.get("phases", {})
	for name in phases:
		var r: Array = phases[name]
		if tod >= float(r[0]) and tod < float(r[1]):
			return name
	return ""

## 某需求在当前时段的偏好乘子（clamp 0.3–2.0）；缺表/缺键→1.0(零扰动)。只调"偏好"、绝不用于生存路径(见调用点门控)。
func _phase_pref(need_id: String, tod: float) -> float:
	var prefs: Dictionary = rhythm.get("prefs", {})
	var tbl: Dictionary = prefs.get(need_id, {})
	if tbl.is_empty():
		return 1.0
	var ph := _phase_of(tod)
	return clampf(float(tbl.get(ph, rhythm.get("default", 1.0))), 0.3, 2.0)

func _decay_needs(ag: Dictionary) -> void:
	if ag.get("is_player", false):
		return                      # M1：玩家需求不衰减（生存玩法留待后续）
	for n in needs_def:
		var id: String = n["id"]
		ag["needs"][id] = max(0.0, float(ag["needs"][id]) - float(n["decay"]))

func _advance_agent(ag: Dictionary) -> void:
	if int(ag["talking"]) > 0:
		ag["talking"] = int(ag["talking"]) - 1
	# L3 激进 LOD：远端(离焦点远)agent 完全不跑 option/候选枚举/寻路/社交，只做廉价统计维持 → 单 agent 成本≈0，可冲上百。
	# 玩家豁免：远离焦点的玩家不得被降级(会吞掉进行中的社交)；bench 无玩家 → 零回归。
	if lod_aggregate and _is_far(ag) and not ag.get("is_player", false):
		ag["option"] = null
		_far_maintain(ag)
		return
	# LOD 饥饿兜底：LOD 近似(节流/远端化)可能让 agent 来不及进食而擦底 → 真危机时就地小补，守"无饿穿"硬不变量。
	# 仅 LOD 开启时生效；off(全保真,逐 tick 决策)永不跌到此阈值 → 基线零扰动。确定。
	if (lod or lod_aggregate) and _min_need(ag) < SURVIVAL_NET_FLOOR:
		for nid in ag["needs"]:
			if float(ag["needs"][nid]) < SURVIVAL_NET_FLOOR:
				ag["needs"][nid] = minf(100.0, float(ag["needs"][nid]) + AGG_RELIEF)
	var opt = ag["option"]
	if opt == null:
		if ag.get("is_player", false):
			return                  # 玩家不自动决策（由输入驱动 player_act/player_move）；进行中的 option 仍正常推进
		# 玩家专属礼遇：正在和玩家说话 → 站住听完，不中途走开（NPC-NPC 保持原语义；bench 无玩家 → 恒 false 零回归）
		if int(ag["talking"]) > 0 and String(ag.get("talk_with", "")) == "player":
			return
		# L2 决策切片 + L3 LOD：每 agent 仅在自己的相位 tick 做重决策；far(远离焦点)agent 用更大周期降频（确定可复现）
		var period := decide_period
		if lod and _is_far(ag):
			period = maxi(period, 1) * LOD_FAR_MULT
		# 生存覆盖：需求进危机时永不跳过决策（否则大 N 重节流下 far agent 会在重决策前擦底 → 破"无饿穿"硬不变量）。确定。
		if period > 1 and _min_need(ag) >= SURVIVAL_GATE and (tick_no % period) != (absi(_aid(ag)) % period):
			return
		var cands := agent_candidates(ag)
		if cands.is_empty():
			return
		# S4 确定性回放：按记录的 pick 复现（含还原异步思考延迟的时机），绕过模型 → 即便模型非确定也可复现。
		if _replay_active:
			var aid := String(ag["id"])
			var rticks: Array = _replay_ticks.get(aid, [])
			var ptr := int(_replay_ptr.get(aid, 0))
			while ptr < rticks.size() and int(rticks[ptr]) < tick_no:
				ptr += 1                            # 跳过已错过的记录(drift 后追平,避免冻结)
			_replay_ptr[aid] = ptr
			if ptr < rticks.size():
				if int(rticks[ptr]) == tick_no:
					var rintent := _resolve_replay(ag, cands, replay_trace["%d:%s" % [tick_no, aid]])
					_replay_ptr[aid] = ptr + 1
					agent_apply(ag, rintent)
				return                              # 否则：下一条记录决策在未来 → 本 tick 等待(还原思考延迟)
			agent_apply(ag, _logic_decide(ag, cands))   # 无更多记录 → 引擎兜底
			return
		# 注入了后端(窗口/M2)则走它；否则内置确定性 logic（soak/headless 永远兜底）。
		var intent: Dictionary
		if backend != null and backend.has_method("decide"):
			intent = backend.decide(ag, cands, _context(ag))
			if intent.get("_wait", false):
				return                              # M2：思考中，本 tick 不落地（保持 option==null 下 tick 再问）
			if intent.is_empty():
				intent = _logic_decide(ag, cands)   # 放弃/超时/脏输出 → 引擎兜底
			elif record_decisions:
				_record_decision(ag, cands, intent) # S4：模型落地决策记入 trace
		else:
			intent = _logic_decide(ag, cands)
		agent_apply(ag, intent)
		return
	# P3 承诺 pre-empt：正办一件【不急】的事(当前 option 的 need 还舒适≥SURVIVAL_GATE)，却有【另一】需求跌破危机线
	# → 中止改救急 → 下 tick 重新决策(会挑最紧的)。只打断"不急的承诺"、绝不打断"正在救急的行程"→ 既有决策黏性(消 livelock)
	# 又不会饿穿(守 #01)。仅对带 need 的 option(object/journey)；无 need 的(social/attend)不受影响。
	if opt is Dictionary and opt.has("need") and not ag.get("is_player", false):
		var onid := String(opt["need"])
		if ag["needs"].has(onid) and float(ag["needs"][onid]) >= SURVIVAL_GATE and _min_need(ag) < PREEMPT_CRISIS:
			ag["option"] = null
			return
	match String(opt.get("kind", "object")):
		"social": _advance_social(ag, opt)
		"attend": _advance_attend(ag, opt)
		"journey": _advance_journey(ag, opt)
		_: _advance_object(ag, opt)

## P3 Tier-B 承诺行程：一路走到【目标对象所在平面】(可跨多个 portal)，到那个平面即把 option 交回普通 object 逻辑
## (走到对象交互格→用它)。中途【不重挑】——承诺执行到底，只被 _advance_agent 的危机 pre-empt 打断。这就是消除
## livelock 的"决策黏性/分层规划"：决定"回家睡觉"后一直走到床、而非每 tick 按当下最紧需求重挑。A* 永不跨平面。
func _advance_journey(ag: Dictionary, opt: Dictionary) -> void:
	if not world["objects"].has(String(opt.get("target", ""))):
		ag["option"] = null                # 目标对象没了 → 放弃
		return
	if String(ag.get("space", "town")) == String(opt.get("dest_space", "town")) \
			and String(ag.get("floor", "outdoor")) == String(opt.get("dest_floor", "outdoor")):
		opt["kind"] = "object"             # 已到目标平面 → 交回普通对象逻辑（走到对象+用它，复用交互格/收费/工资/记忆）
		_advance_object(ag, opt)
		return
	var hop := _route_next_hop(String(ag.get("space", "town")), String(ag.get("floor", "outdoor")),
		String(opt.get("dest_space", "town")), String(opt.get("dest_floor", "outdoor")), ag)
	if hop.is_empty():
		ag["option"] = null                # 不可达 → 放弃（下 tick 重新决策）
		return
	if ag["pos"] == hop["from_pos"]:
		_traverse_portal(ag, hop)          # 到本层 portal 口 → 跨过去（【不清 option】，承诺继续）
	else:
		_move_agent(ag, _nav_step(ag, hop["from_pos"]))
	emit_signal("agent_changed", ag["id"])

func _advance_attend(ag: Dictionary, opt: Dictionary) -> void:
	var c := _find_commitment(int(opt["commit"]))
	# 承诺已了结 / 已过点 / 需求危机 → 放弃赴约（危机即爽约的根）
	if c.is_empty() or String(c["status"]) != "active" or tick_no >= int(c["deadline"]) or _min_need(ag) < NEED_CRISIS:
		ag["option"] = null
		return
	if String(ag.get("area", "")) != String(c["area"]):
		_move_agent(ag, _nav_step(ag, _area_centroid(String(c["area"]))))  # 未到则前往；到了守在该区等对方
		emit_signal("agent_changed", ag["id"])

func _advance_object(ag: Dictionary, opt: Dictionary) -> void:
	var target_obj: Dictionary = world["objects"].get(opt["target"], {})
	if target_obj.is_empty():
		ag["option"] = null
		return
	if opt["phase"] == "travel":
		# 交互格（town-world P2-3）：站在家具【旁】用它，不再踩到家具格上。抵达=与家具正交相邻(曼哈顿≤1)。
		# 导航目标仍是家具格(A* 终点豁免)，A* 的正交逐格路径必然经过"家具的某个可走邻格"(曼哈顿1)→ 在那一格即触发
		# use、绝不迈上家具格。那个邻格由 A* 走到=保证可达(gen_town 审计每个家具≥1 可达邻格)→ 无饿穿零风险，
		# 且比旧"踩上家具"早一格到达(需求更早满足、更安全)。同区邻格 → area 门控(社交/赴约)不变。
		if _manh(ag["pos"], target_obj["pos"]) <= 1:
			opt["phase"] = "use"
			# Wave 1b 收费点：有价动作(吃饭等)开用时向镇库付费。付不起→照用不误(meals_free)——
			# 生存永不被钱门住(守"无饿穿"硬不变量)，钱只造分化/戏剧，不造饿死。
			if _econ_on():
				var price := int(economy.get("prices", {}).get(String(opt["action"]), 0))
				if price > 0:
					if transfer(String(ag["id"]), "town", price, "price:" + String(opt["action"])):
						econ_stats["meals_paid"] += 1
					else:
						econ_stats["meals_free"] += 1
		else:
			_move_agent(ag, _nav_step(ag, target_obj["pos"]))
		emit_signal("agent_changed", ag["id"])
	else:  # use
		var per := float(opt["amount"]) / float(opt["dur_total"])
		var nid: String = opt["need"]
		ag["needs"][nid] = clamp(float(ag["needs"][nid]) + per, 0.0, 100.0)
		opt["remaining"] = int(opt["remaining"]) - 1
		if int(opt["remaining"]) <= 0:
			ag["memory"].add("在%s%s了" % [target_obj.get("area", ""), opt["action"]], 3, tick_no, [opt["need"], opt["target"]])
			# Wave 1b 发薪点：有薪动作(做活)完成时镇库付工资。镇库空→跳过(wages_skipped)——闭环:饭钱流入、工资流出。
			# Wave 2a：工资经 _wage_for（本职在班拿职位工资；差异工资→贫富分化）；本职完成写"上工"记忆(voice grounding)。
			if _econ_on():
				# Wave 2c 技能：本职动作完成 → 熟练度+1，升级写里程碑记忆(voice grounding)。先涨技能再算工资 → 升级当次即涨薪。数据门控。
				if not skills.is_empty():
					var jb1 := _job_of(String(ag["id"]))
					if not jb1.is_empty() and String(jb1.get("action", "")) == String(opt["action"]):
						var lv0 := _skill_level(ag, String(opt["action"]))
						ag["skills"][String(opt["action"])] = int((ag["skills"] as Dictionary).get(String(opt["action"]), 0)) + 1
						if _skill_level(ag, String(opt["action"])) > lv0:
							ag["memory"].add("手艺又精进了，%s越发得心应手" % String(jb1.get("title", "")), 5, tick_no, ["skill", "job"])
				var wage := _wage_for(ag, String(opt["action"]))
				if wage > 0:
					if transfer("town", String(ag["id"]), wage, "wage:" + String(opt["action"])):
						econ_stats["wages_paid"] += 1
						var jb := _job_of(String(ag["id"]))
						if not jb.is_empty() and String(jb.get("action", "")) == String(opt["action"]):
							ag["memory"].add("上工%s，挣了%d个钱" % [String(jb.get("title", "")), wage], 4, tick_no, ["job", "coin"])
					else:
						econ_stats["wages_skipped"] += 1
			ag["option"] = null
		emit_signal("agent_changed", ag["id"])

func _advance_social(ag: Dictionary, opt: Dictionary) -> void:
	var partner: Dictionary = _agent_by_id.get(opt["partner"], {})
	if partner.is_empty() or String(ag.get("area", "")) != String(partner.get("area", "")):
		ag["option"] = null      # 对方离开 → 作废
		ag["talking"] = 0
		return
	opt["remaining"] = int(opt["remaining"]) - 1
	if int(opt["remaining"]) <= 0:
		_commit_social(ag, opt)
		ag["option"] = null
		ag["talking"] = 0

func _nightly() -> void:
	# M3 反思（Stanford 生成式 agent）：每夜从社会状态提炼一条洞察写回记忆 → 丰富语音 grounding。
	# 引擎地板=确定性合成(下)；模型后端可再 LLM 润色(AIBackend.reflect)。far agent(激进 LOD)跳过=背景群演。
	for ag in agents:
		if lod_aggregate and lod_near_cap > 0 and not _near_set.is_empty() and not _near_set.has(ag["id"]):
			continue
		_reflect_agent(ag)
	# Wave 3c 住房：每夜房客经 Ledger 向房东转租金（transfer 守恒 + 付不起自动跳过→#34/#35 保）。缺 housing.json/经济关→零扰动。
	# 置于阶层 gossip 之前 → 当晚被目击的财富已含租金流动（房东更富/房客更穷 → 阶层信号更利落）。
	if _econ_on() and not housing.is_empty():
		var rent := int(housing.get("rent", 0))
		if rent > 0:
			for t in housing.get("tenancies", []):
				var td: Dictionary = t if t is Dictionary else {}
				var tnt := String(td.get("tenant", ""))
				var lld := String(td.get("landlord", ""))
				if tnt != lld and _agent_by_id.has(tnt) and _agent_by_id.has(lld):
					transfer(tnt, lld, rent, "rent")     # 房客→房东；付不起(coin<rent)则 transfer 返 false 自动跳过
	# Wave 2a+ 阶层 gossip：财富被同区邻居目击 → firsthand belief(via=seen) → 走既有 gossip 管线传播(S1 原样复用)。
	if _econ_on() and economy.has("wealth_gossip"):
		_observe_wealth()
	_recompute_factions()      # S3a：每夜从 attitudes 重算派系（先于名声漂移）
	_dissolve_freeriders()     # S3b：先解 free-rider 盟约
	_form_pacts_greedy()       # S3b：再单遍贪心结盟
	# S1 每日衰减：怨气缓降（宽恕，不永久世仇）；名声每 3 天向 0 漂移 1（慢淡化，坏名声能留一阵）
	var drift := (day % 3 == 0)
	for ag in agents:
		for oid in ag["relationships"]:
			var r: Dictionary = ag["relationships"][oid]
			if float(r["resentment"]) > 0.0:
				r["resentment"] = maxf(0.0, float(r["resentment"]) - RESENT_DECAY)
			if drift and float(r["standing"]) != 0.0:
				r["standing"] = float(r["standing"]) - signf(float(r["standing"]))
	# DRAMA pacing（Phase-D 调参）：把【被时间原谅的小怨】归档成终态 faded——委屈方怨气已衰到触发线(CONFLICT_TRIGGER)下、
	# 且是没被引爆的 simmering/lingering。纯重标签：不动 resentment/standing、不引爆、不新增冲突 → 靠【持久坏名声】的涌现放逐
	# (#15) 一分不受影响；只把"其实气早消了、只是没标终态"的怨从悬空弧挪出去 → 冲突完成率更诚实、且直性子不会再去翻已消的旧账。
	if DRAMA_FORGIVE_FADE:
		for c in conflicts:
			var st := String(c.get("status", ""))
			if st != "simmering" and st != "lingering":
				continue
			var ha: Dictionary = _agent_by_id.get(String(c.get("a", "")), {})
			if ha.is_empty():
				continue
			var rr: Dictionary = (ha.get("relationships", {}) as Dictionary).get(String(c.get("b", "")), {})
			if float(rr.get("resentment", 99.0)) < CONFLICT_TRIGGER:
				c["status"] = "faded"; c["faded"] = tick_no
	if ext != null:
		ext.nightly(self)          # 注册的 NightlyHook（按 (order,id) 定序，排在内建夜间机制之后）

# ── 合法候选契约（引擎枚举 → 后端挑 → 引擎执行/兜底）──────────────────────
## 返回当前对该 Agent 合法且有意义的候选（物件交互 + 社交）；每个候选可被 agent_apply 执行。
func agent_candidates(ag: Dictionary) -> Array:
	cand_calls += 1                         # 成本探针：候选枚举=最重的 per-agent 工作（LOD 省的就是它）
	var out := _object_candidates(ag)
	out.append_array(_social_candidates(ag))
	out.append_array(_attend_candidates(ag))
	out.append_array(_journey_candidates(ag))        # P3 Tier-B：跨平面承诺行程元候选（冻结在 ext 前的固定位；仅 café 居民非空 → town 零扰动）
	if ext != null:
		out.append_array(ext.candidates(self, ag))   # 注册的 CandidateProvider 追加（排在内建之后，不改内建枚举序 → 回放安全）
	return out

## P3 Tier-B 决策规划：跨平面【承诺式行程 journey】元候选。两类，都产出带完整对象参数的 journey 候选(选中→agent_apply
## 建 journey option→_advance_journey 承诺执行：跨 portal→到对象所在平面→交回普通对象逻辑用它，中途不重挑，只危机打断)：
##   (A) 顾客进店：镇上【常客】(cafe_regular)在营业时段、fun 偏低且无紧急事 → 去咖啡馆喝咖啡（进店后自然社交）。
##   (B) 离家在外(顾客在店/阿丽在镇)或 café 居民 → 本平面无满足的偏紧 need 承诺行程去有满足者的平面。
## 普通镇上居民(home=town、非常客/未进店) → 恒返 [] → town 逐字节不变。确定：对象/portal 文件序、无 RNG。
func _journey_candidates(ag: Dictionary) -> Array:
	if ag.get("is_player", false):
		return []
	var aspace := String(ag.get("space", "town"))
	var afloor := String(ag.get("floor", "outdoor"))
	var home_space := String(ag.get("home_space", "town"))
	var out: Array = []
	# (A) 常客进店：镇上常客、营业时段、fun<阈值、无紧急事 → 去咖啡馆喝杯咖啡（进店行程；只认 café 的 fun 对象）。
	var wants_visit := aspace == "town" and home_space == "town" and bool(ag.get("cafe_regular", false)) \
			and _cafe_open() and float(ag["needs"].get("fun", 100.0)) < CAFE_VISIT_FUN and _min_need(ag) >= SURVIVAL_GATE
	if wants_visit:
		var vc := _best_satisfier_journey(ag, "fun", aspace, afloor, home_space, true)
		if not vc.is_empty():
			out.append(vc)
	# (B) 离家在外 或 café 居民 → 为本平面无满足的偏紧 need 承诺行程。普通镇上居民(都在 town)不进此块。
	if aspace != "town" or home_space != "town":
		var covered := {}
		for id in world["objects"]:
			var o: Dictionary = world["objects"][id]
			if String(o.get("space", "town")) == aspace and String(o.get("floor", "outdoor")) == afloor:
				for adv in _as_arr(o.get("advertises", [])):
					if adv is Dictionary:
						var n := String(adv.get("need", ""))
						if not (n in HOME_NEEDS and aspace != home_space):   # 镇上的床/游戏机不算覆盖【居民】的 energy/fun
							covered[n] = true
		for nid in ag["needs"]:
			if nid == "social" or covered.has(nid):
				continue
			if 100.0 - float(ag["needs"][nid]) <= JOURNEY_URGENT:
				continue
			var jc := _best_satisfier_journey(ag, nid, aspace, afloor, home_space, false)
			if not jc.is_empty():
				out.append(jc)
	return out

## 锁定他平面满足 nid 的【最优对象】→ 一条 journey 候选。家绑定：【居民】的 energy/fun 只回家 Space(顾客 home=town 不受限)。
## is_visit=进店行程：只认咖啡馆对象、路程惩罚减半+进店加成(值得为一杯咖啡跑一趟，压过就近的镇上游戏机)。带 ag 走权限门(owner 楼梯)。
func _best_satisfier_journey(ag: Dictionary, nid: String, aspace: String, afloor: String, home_space: String, is_visit: bool) -> Dictionary:
	var urg := 100.0 - float(ag["needs"].get(nid, 100.0))
	var best_score := -1.0e18
	var best: Dictionary = {}
	for id in world["objects"]:
		var o: Dictionary = world["objects"][id]
		var os := String(o.get("space", "town")); var of := String(o.get("floor", "outdoor"))
		if os == aspace and of == afloor:
			continue
		if is_visit and os != "cafe":
			continue
		if not _staff_ok(ag, o):                                # 顾客的进店行程不冲吧台(员工专属)→ 锁定公共桌"喝咖啡"
			continue
		if nid in HOME_NEEDS and home_space != "town" and os != home_space:   # 居民的 energy/fun 只回家 Space
			continue
		var amt := 0; var dur := 0; var act := ""
		for adv in _as_arr(o.get("advertises", [])):
			if adv is Dictionary and String(adv.get("need", "")) == nid and int(adv.get("amount", 0)) > amt:
				amt = int(adv.get("amount", 0)); dur = int(adv.get("duration", 0)); act = String(adv.get("action", ""))
		if amt <= 0:
			continue
		var hop := _route_next_hop(aspace, afloor, os, of, ag)
		if hop.is_empty():
			continue
		var d := _manh(ag["pos"], hop["from_pos"]) + int(hop.get("cost", 1)) * 3   # 估路程：到本层 portal 口 + 过 portal 成本
		var pen: float = _w("obj_dist_penalty", 0.4) * (0.5 if is_visit else 1.0)
		var score := urg * (float(amt) / 60.0) - float(d) * pen + (CAFE_VISIT_BONUS if is_visit else 0.0)
		if score > best_score:
			best_score = score
			best = {"kind": "journey", "action": act, "target": String(id), "need": nid,
				"dest_space": os, "dest_floor": of, "amount": amt, "dur_total": dur, "score": score, "say": ""}
	return best

## 员工专属对象门：staff 对象(阿丽的吧台)只有该店主人(home_space==对象 Space)能用；顾客/外人不枚举它。
## 非 staff 对象恒真 → town 全员 + 所有旧对象逐字节不变。
func _staff_ok(ag: Dictionary, o: Dictionary) -> bool:
	return not bool(o.get("staff", false)) or String(ag.get("home_space", "town")) == String(o.get("space", "town"))

func _object_candidates(ag: Dictionary) -> Array:
	var out: Array = []
	# 昼夜节律（docs/14）：仅当 agent 无紧急需求(min≥SURVIVAL_GATE)时，用时段偏好乘子塑造"何时"满足需求(睡偏夜/吃偏三餐)。
	# 有任一紧急需求 → 节律关闭 → 纯 urgency 主导 → 绝不因时段延误进食 → 守 HARD#1 无饿穿。缺 rhythm.json → 恒关=零扰动。
	var mods_ok := _min_need(ag) >= SURVIVAL_GATE            # 共用生存门：紧急需求时一切偏好乘子关闭，纯 urgency 主导
	var rhythm_on := not rhythm.is_empty() and mods_ok
	var wx_on := weather_today != "" and mods_ok             # Wave 1c：天气与节律独立门控（各自缺数据文件即各自关闭）
	var sn_on := season_today != "" and mods_ok              # Wave 3b：季节乘子同样只在非紧急时塑形（生存优先不受季节影响）
	var tod := time_of_day()
	for id in world["objects"]:
		var o: Dictionary = world["objects"][id]
		if String(o.get("space", "town")) != String(ag.get("space", "town")) \
				or String(o.get("floor", "outdoor")) != String(ag.get("floor", "outdoor")):
			continue                        # P3：只枚举【同平面】对象（跨平面走 _journey_candidates 承诺行程）。town 居民↔town 对象 → 与旧一致
		if not _staff_ok(ag, o):
			continue                        # P3：员工专属对象(阿丽的吧台)只有店主人枚举；顾客不"看摊"，改用公共桌"喝咖啡"
		for adv in o.get("advertises", []):
			# 健壮性（stage-2 review #4）：改数据后可能出现残缺 advertises；用 .get() 取值+非对象跳过，
			# 避免"缺键裸括号"每 tick 崩。合规条目(四键齐全)取值与旧逐字节一致 → 不新增/移动候选 → digest 不漂。
			if not (adv is Dictionary):
				continue
			var amount := int(adv.get("amount", 0))
			if amount <= 0:
				continue
			var need_id := String(adv.get("need", ""))
			# 家绑定：café 居民的 energy/fun 只在【家 Space】(咖啡馆整栋)满足；镇上的床/游戏机对她不产候选
			# → 在镇上 energy/fun"无满足"→ _journey_candidates 发起【回咖啡馆】的承诺行程。按 SPACE 判(非 floor：否则
			# 楼上床/楼下吧台互相排除)。town 居民 home=town → 恒 false → 逐字节不变。
			if need_id in HOME_NEEDS and String(ag.get("home_space", "town")) != "town" \
					and String(ag.get("space", "town")) != String(ag.get("home_space", "town")):
				continue
			var action := String(adv.get("action", ""))
			var duration := int(adv.get("duration", 0))
			var cur := float(ag["needs"].get(need_id, 100.0))
			var urgency := 100.0 - cur
			if urgency <= 5.0:
				continue
			var dist := absi(ag["pos"].x - o["pos"].x) + absi(ag["pos"].y - o["pos"].y)
			var benefit := urgency * (float(amount) / 60.0)
			if rhythm_on:
				benefit *= _phase_pref(need_id, tod)      # 只缩放收益项、不动距离惩罚；生存路径不乘(上门控)
			if wx_on:
				benefit *= _weather_mult(action)          # Wave 1c：坏天压户外偏好(≤1 dampen-only)
			if sn_on:
				benefit *= _season_mult(action)           # Wave 3b：当季压某些活动偏好(≤1 dampen-only)
			var score := benefit - float(dist) * _w("obj_dist_penalty", 0.4)
			# Wave 1b 经济动机环：穷(coin<poor_line)时有薪动作加分 → 缺钱→去做活→挣了付饭钱(闭环)。
			# 确定性、数据门控；只加分不减分 → 生存(urgency 主导)不受威胁；economy.json 缺失恒不触发。
			# Wave 2a：工资经 _wage_for（本职在班=职位工资>零工价 → 班次时间自然被工作吸引；jobs 缺失≡旧查表）。
			if _econ_on() and _wage_for(ag, action) > 0 \
					and _coin_of(String(ag["id"])) < int(economy.get("poor_line", 6)):
				score += float(economy.get("work_urgency", 8.0))
			out.append({
				"kind": "object", "action": action, "target": id, "need": need_id,
				"amount": amount, "dur_total": duration,
				"score": score, "say": "",
			})
	return out

## 社交候选：对每个【同区可感知】的其他 agent 枚举 greet/give/gossip。
func _social_candidates(ag: Dictionary) -> Array:
	var out: Array = []
	# 生存优先：任一需求低于 SURVIVAL_GATE → 本 tick 不社交，让物件候选(吃/睡)胜出（留赶路缓冲）。
	# 防大 N 社交密度高时 agent 沉迷戏剧而饿穿(docs/12 R5 候选挤占的生存版)；小 N 几乎不触发。
	if _min_need(ag) < SURVIVAL_GATE:
		return out
	var social := float(ag["needs"].get("social", 100.0))
	if social >= SOCIAL_FULL:
		return out
	var urgency := 100.0 - social
	# R2(docs/14 §3)：预算「我对其有坏名声(≤REP_GOSSIP_TH)的第三方 C」——按 agent 定序、仅查已存在关系(不 auto-create)。
	# 与原 `for c2 in agents` 扫全量等价(未建关系者 standing=0>阈,从不入选)，但把 gossip_rep/endorse 里的 O(N)/邻居嵌套
	# 降为 O(坏名声数,通常极小) → 消除 _social_candidates 的 O(N²)。事件输出逐字节不变(digest 基于 event_log,零名声关系不产事件)。
	var bad_targets: Array = []
	var _my_rels: Dictionary = ag["relationships"]
	var _my_id := String(ag["id"])
	for c2 in agents:
		var c2id := String(c2["id"])
		if c2id != _my_id and _my_rels.has(c2id) and float(_my_rels[c2id]["standing"]) <= REP_GOSSIP_TH:
			bad_targets.append(c2id)
	for o in _nearby_agents(ag):
		if int(o["talking"]) > 0:
			continue
		var r := _rel(ag, o["id"])
		var aff := float(r["affinity"])
		var fam := float(r["familiarity"])
		# greet / smalltalk —— 总可发起
		out.append({"kind": "social", "action": "greet", "partner": o["id"], "subject": "",
			"need": "social", "score": urgency * 0.7 + aff * 0.1 + fam * 0.05 + _w("greet_base", 6.0), "say": ""})
		# give —— 有礼物 + 条件投资 trust 门（脆弱动作只对够信任者发起）；偏向还不熟、想拉近的人
		if int(ag["inventory"].get("gift", 0)) > 0 and float(r["trust"]) >= INVEST_TRUST:
			out.append({"kind": "social", "action": "give", "partner": o["id"], "subject": "",
				"need": "social", "score": urgency * 0.5 + (12.0 - minf(12.0, fam)) * 0.6 + 12.0, "say": ""})
		# gossip —— 有对方不知道的传闻时；爱八卦者更爱
		var cid := _unspread_belief(ag, o)
		if cid != "":
			var gossipy := 8.0 if "爱八卦" in ag.get("persona", {}).get("traits", []) else 0.0
			out.append({"kind": "social", "action": "gossip", "partner": o["id"], "subject": cid,
				"need": "social", "score": urgency * 0.6 + aff * 0.1 + gossipy + 5.0, "say": ""})
		# docs/16 隐私门（广义版，见 _secret_private）：封闭房间 或 独处无旁人 才吐露/说漏；缺 rooms→恒 true=逐字节不变。
		var priv_ok := _secret_private(ag, o)
		# S3c confide —— 仅 owner 向高 trust+aff 者吐露心事（最脆弱条件投资，门高于 give/invite）
		if priv_ok and float(r["trust"]) >= CONFIDE_TRUST and aff >= SECRET_AFF_FLOOR:
			var cs := _confidable_secret(ag, o)
			if cs != "":
				# docs/17 选项B：憋着未吐的秘密随持有时长累积"倾诉压力"，给 confide 在效用竞争里加分。
				# 纯 score、不新增候选=不动 tie-break salt；_w 缺键→系数 0→sp≡0→`+0.0` 逐字节不变(off 门)。
				# 压力 = 系数 × ramp(秘密龄 0→1，30 天饱和)：越憋越想说，但仍与紧急需求竞争、不夺生存。
				var sp := _w("confide_secret_pressure", 0.0)
				if sp != 0.0:
					var age := tick_no - int((ag["beliefs"][cs] as Dictionary).get("tick", 0))
					sp *= minf(1.0, float(maxi(0, age)) / float(TICKS_PER_DAY * 30))
				out.append({"kind": "social", "action": "confide", "partner": o["id"], "subject": cs,
					"need": "social", "score": urgency * 0.4 + (float(r["trust"]) - CONFIDE_TRUST) * 0.3 + fam * 0.2 + 9.0 + sp, "say": ""})
		# S3c leak —— 把别人吐露给我的秘密外传=背叛（无 trust 门；愧疚抑制，对托付者积怨则报复）
		var ls := _leakable_secret(ag, o) if priv_ok else ""
		if ls != "":
			var teller_id := String((ag["beliefs"][ls]["confidedBy"] as Dictionary).keys()[0])
			var rt2 := _rel(ag, teller_id)
			# revenge-leak(怨气×1.2 驱动背叛)被 secret-stake 盲评判为 out-of-character(resent→leak 率 0%)——移除；
			# 泄密纯由话痨人设(下面的 DRAMA 八卦节拍)驱动，其余人设 leak 分低、照旧守口。guilt(好感抑制)保留。
			var guilt := maxf(0.0, float(rt2["affinity"])) * 0.12
			var lgy := 9.0 if "爱八卦" in ag.get("persona", {}).get("traits", []) else 0.0
			var leak_score := urgency * 0.5 + lgy + 6.0 - guilt
			# DRAMA 八卦泄密：憋够久(GOSSIP_LEAK_AFTER)、还没说漏过的话痨(爱八卦)把秘密抖出去——分抬到压过维护 → 当选。
			# 只八卦一次(gossiped 标记)：不满镇乱抖同一桩。盲评 held-out：默认守信、唯一例外=爱八卦。纯 f(trait,age)。
			var lb2: Dictionary = ag["beliefs"][ls]
			if DRAMA_DIRECTOR and DRAMA_GOSSIP_LEAK and _is_gossipy(ag) and not lb2.has("gossiped") \
					and tick_no - int(lb2.get("tick", tick_no)) >= GOSSIP_LEAK_AFTER:
				leak_score += GOSSIP_LEAK_BOOST
			out.append({"kind": "social", "action": "leak", "partner": o["id"], "subject": ls,
				"need": "social", "score": leak_score, "say": ""})
		# discuss —— 挑"自己信任带 ε 内最大分歧"的话题聊（接受与否再走对方 Deffuant 门）
		var d_topic := ""
		var d_diff := DISCUSS_MINDIFF
		for t in TOPICS:
			var diff := absf(float(ag["attitudes"].get(t, 0.0)) - float(o["attitudes"].get(t, 0.0)))
			if diff > d_diff and diff <= float(ag["eps"]):
				d_diff = diff; d_topic = t
		if d_topic != "":
			out.append({"kind": "social", "action": "discuss", "partner": o["id"], "subject": d_topic,
				"need": "social", "score": urgency * 0.55 + d_diff * 6.0 + aff * 0.08 + 5.5, "say": ""})
		# gossip_rep —— 我对某第三方 C 有坏名声(≤阈)，o 印象没那么坏 → 传 C 名声（示警优先）。遍历预算 bad_targets(定序,首个匹配同原扫全量)。
		for c2id in bad_targets:
			if c2id == String(o["id"]):
				continue
			if float(_rel(o, c2id)["standing"]) > float(_rel(ag, c2id)["standing"]):
				var gy := 8.0 if "爱八卦" in ag.get("persona", {}).get("traits", []) else 0.0
				out.append({"kind": "social", "action": "gossip_rep", "partner": o["id"], "subject": c2id,
					"need": "social", "score": urgency * 0.6 + gy + 10.0, "say": ""})
				break
		# invite —— 约对方稍后再聚（创建 meet 承诺）；条件投资 trust 门；按熟悉度加权；手头无未了约会才发起
		if not _any_active_meet(ag["id"]) and not _has_active_meet(ag["id"], o["id"]) and float(r["trust"]) >= INVEST_TRUST:
			var pinv := PACT_INVITE_BONUS if _active_pact(ag, o["id"]) else 0.0  # S3b：优先约盟友
			out.append({"kind": "social", "action": "invite", "partner": o["id"], "subject": "",
				"need": "social", "score": urgency * 0.45 + aff * 0.15 + fam * 0.18 + 4.0 + pinv, "say": ""})
		# confront —— 我对 o 积怨成冲突 → 想当面说开（越严重越想）
		var cf := _find_conflict(ag["id"], o["id"], ["simmering", "escalated", "lingering"])
		if not cf.is_empty() and (not CHARACTER_DEFER or _is_blunt(ag) or _drama_erupts(cf)):   # CHARACTER 默认 defer；DRAMA 导演对憋太久的心结安排对质
			out.append({"kind": "social", "action": "confront", "partner": o["id"], "subject": "",
				"need": "social", "score": 30.0 + minf(float(cf["severity"]), 20.0), "say": ""})
		# apologize —— o 对我有冲突且已被我对质（我已知错）→ 想道歉
		if not _find_conflict(o["id"], ag["id"], ["confronted"]).is_empty():
			out.append({"kind": "social", "action": "apologize", "partner": o["id"], "subject": "",
				"need": "social", "score": 32.0, "say": ""})
		# ── S3a 协同行动（仅当 ag 已属派系）──
		if String(ag["faction"]) != "" and int(ag["faction_size"]) >= FACTION_QUORUM:
			# endorse —— o 是同派系；存在外群恶名第三方 C → 统一对外口径
			if String(o["faction"]) == String(ag["faction"]) and (not FACTION_ENDORSE_DEFER or _is_gossipy(ag)):   # CHARACTER：串谋贬损=八卦本性，盲评仅爱八卦(阿丽)一人 in-character → 余皆默认弃权
				for c2id in bad_targets:
					if c2id == String(o["id"]) or String(_agent_by_id[c2id]["faction"]) == String(ag["faction"]):
						continue
					if float(_rel(o, c2id)["standing"]) > float(_rel(ag, c2id)["standing"]):
						var egy := 8.0 if "爱八卦" in ag.get("persona", {}).get("traits", []) else 0.0
						out.append({"kind": "social", "action": "endorse", "partner": o["id"], "subject": c2id,
							"need": "social", "score": urgency * 0.6 + FACTION_ENDORSE_BONUS + egy, "say": ""})
						break
			# rally_oust —— o 是外群且 ag 对 o 有冲突/坏名声 → 协同施压（评分 < confront，私下对质优先）
			if String(o["faction"]) != String(ag["faction"]):
				var cfo := _find_conflict(ag["id"], o["id"], ["simmering", "escalated", "lingering"])
				var st_o := float(_rel(ag, o["id"])["standing"])
				# CHARACTER：撺掇公开合围极不入戏（盲评 p_eff 0.014、无人设例外）→ 默认弃权；
				# DRAMA：仅当对象名声极差 + 冲突已激化，才让"众人合围一个真麻烦"成一场罕见的戏。
				if (not cfo.is_empty() or st_o <= REP_GOSSIP_TH) and (not FACTION_MOB_DEFER or _mob_erupts(cfo, st_o)):
					out.append({"kind": "social", "action": "rally_oust", "partner": o["id"], "subject": "",
						"need": "social", "score": OUST_BASE + minf(float(cfo.get("severity", 0.0)), 15.0), "say": ""})
		# ── S3b aid（仅当 o 是 active pact 伙伴且其某 need 低）──
		if _active_pact(ag, o["id"]):
			var low := _partner_low_need(o)
			if low != "":
				out.append({"kind": "social", "action": "aid", "partner": o["id"], "subject": low,
					"need": "social", "score": (AID_NEED_TH - float(o["needs"][low])) * 1.2 + fam * 0.1 + AID_BASE, "say": ""})
	return out

# S3b 辅助
func _active_pact(ag: Dictionary, oid: String) -> bool:
	var p = ag["pacts"].get(oid)
	return p != null and String(p["status"]) == "active"
func _partner_low_need(o: Dictionary) -> String:
	var lid := ""
	var lv := AID_NEED_TH
	for nid in o["needs"]:
		if float(o["needs"][nid]) < lv:
			lv = float(o["needs"][nid]); lid = nid
	return lid

## attend —— 手头有临近 deadline 的 meet 承诺 → 引擎给「去赴约」加权（越近越急）。
func _attend_candidates(ag: Dictionary) -> Array:
	var out: Array = []
	for c in commitments:
		if String(c["status"]) != "active":
			continue
		if c["a"] != ag["id"] and c["b"] != ag["id"]:
			continue
		if int(c["deadline"]) - tick_no > ATTEND_WINDOW:
			continue
		var closeness := 1.0 - float(int(c["deadline"]) - tick_no) / float(MEET_HORIZON)
		var other_id := String(c["b"]) if String(c["a"]) == String(ag["id"]) else String(c["a"])
		var patt := PACT_ATTEND_BONUS if _active_pact(ag, other_id) else 0.0  # S3b：优先赴盟友的约
		out.append({"kind": "attend", "area": c["area"], "commit": c["id"], "score": 25.0 + closeness * 40.0 + patt, "say": ""})
	return out

## 执行一个 intent。非法/空 → 引擎兜底（永不破坏仿真）。
func agent_apply(ag: Dictionary, intent: Dictionary) -> void:
	if intent == null or intent.is_empty():
		intent = _best(_object_candidates(ag))
		if intent.is_empty():
			return
	match String(intent.get("kind", "object")):
		"social": _apply_social(ag, intent)
		"attend": ag["option"] = {"kind": "attend", "area": intent["area"], "commit": intent["commit"]}
		"journey": ag["option"] = {"kind": "journey", "target": String(intent.get("target", "")),   # P3：承诺式跨平面行程（到对象所在平面→用它）
			"dest_space": String(intent.get("dest_space", "town")), "dest_floor": String(intent.get("dest_floor", "outdoor")),
			"need": String(intent.get("need", "")), "action": String(intent.get("action", "")),
			"amount": int(intent.get("amount", 0)), "dur_total": int(intent.get("dur_total", 1)),
			"remaining": int(intent.get("dur_total", 1)), "phase": "travel"}
		_: _apply_object(ag, intent)

## P2-2 合法边界：object intent 是否可信。只检 target 存在不够——可插拔 backend / 扩展 / 迟到回包
## 可能塞来残缺或非法字段：dur_total<=0 会在推进时【除零】、未知 need 会【索引失败】。
## 引擎自产候选恒满足此式 → 对 logic 路是恒真的 no-op（digest 逐字节不变）。
func _object_intent_ok(ag: Dictionary, intent: Dictionary) -> bool:
	if intent == null or intent.is_empty():
		return false
	for k in ["action", "target", "need", "amount", "dur_total"]:
		if not intent.has(k):
			return false
	if not world["objects"].has(str(intent["target"])):
		return false
	if int(intent["dur_total"]) <= 0:                                   # 除零护栏
		return false
	if not (ag.get("needs", {}) as Dictionary).has(str(intent["need"])):  # 未知 need 护栏
		return false
	return true

func _apply_object(ag: Dictionary, intent: Dictionary) -> void:
	if not _object_intent_ok(ag, intent):
		var c := _object_candidates(ag)
		if c.is_empty():
			return
		intent = _best(c)
		if not _object_intent_ok(ag, intent):   # 引擎候选本应恒合法；仍不合法（数据脏）→ 放弃本 tick，永不崩
			return
	ag["option"] = {
		"kind": "object",
		"action": intent["action"], "target": intent["target"], "need": intent["need"],
		"amount": int(intent["amount"]), "dur_total": int(intent["dur_total"]),
		"remaining": int(intent["dur_total"]), "phase": "travel",
	}
	ag["last_say"] = str(intent.get("say", ""))
	emit_signal("log_line", "%s → %s @%s" % [_name(ag), intent["action"], intent["target"]])
	emit_signal("agent_changed", ag["id"])

func _apply_social(ag: Dictionary, intent: Dictionary) -> void:
	# P2-2：残缺 intent（无动作/无对象）不信 → 本 tick 不动。动作【合法性】另由 _social_transaction 的
	# KNOWN_SOCIAL_ACTIONS 门把关（未知动作不落通用效果，见 L7 ActionExecutor 注释）。引擎候选恒带这两字段 → no-op。
	var action := str(intent.get("action", ""))
	var pid := str(intent.get("partner", ""))
	if action == "" or pid == "":
		return
	var partner: Dictionary = _agent_by_id.get(pid, {})
	# 兜底：对方不存在/正忙/不同区 → 本 tick 不动，下 tick 重选（永不破坏仿真）
	if partner.is_empty() or int(partner["talking"]) > 0 or String(ag.get("area", "")) != String(partner.get("area", "")):
		return
	ag["option"] = {
		"kind": "social", "action": action, "partner": pid,
		"subject": str(intent.get("subject", "")), "remaining": CONVERSE_TICKS,
	}
	ag["talking"] = CONVERSE_TICKS
	# 把对方也绑进这次对话；玩家做被动方时 +1 补齐相位差（talking 先于 option 推进一拍归零，
	# 否则玩家可在最后一 tick 走出区域无成本作废 NPC 的事务——对抗审查#8；bench 无玩家零回归）
	var bind := CONVERSE_TICKS + (1 if partner.get("is_player", false) else 0)
	partner["talking"] = max(int(partner["talking"]), bind)
	partner["talk_with"] = String(ag["id"])   # 记录谈话对象（玩家专属"站住听完"门用，见 _advance_agent；NPC-NPC 语义不变）
	ag["last_say"] = str(intent.get("say", ""))
	emit_signal("agent_changed", ag["id"])

# ── SocialTransaction：发起 → 评估(接受/拒绝) → 提交 → 双方+旁观者写视角记忆 ─────
func _commit_social(ag: Dictionary, opt: Dictionary) -> void:
	var target: Dictionary = _agent_by_id.get(opt["partner"], {})
	if target.is_empty() or String(ag.get("area", "")) != String(target.get("area", "")):
		return
	var action := String(opt["action"])
	var subject := String(opt.get("subject", ""))
	var witnesses: Array = []
	for w in _nearby_agents(ag):
		if w["id"] != target["id"]:
			witnesses.append(w)
	# 冲突类社交（对质/道歉）有自己的状态机，单独处理
	if action == "confront":
		_resolve_confront(ag, target, witnesses)
		return
	if action == "apologize":
		_resolve_apologize(ag, target, witnesses)
		return
	if action == "rally_oust":
		_resolve_rally_oust(ag, target, witnesses)
		return
	# L7 ActionExecutor（docs/15 §3 #2，最大真缺口）：未知动作在进入通用接受/效果【之前】拦截——
	# 否则会被误套 greet 语义（social+16/affinity/事件/记忆）污染事件流与 digest。无人认领 → 不落任何通用效果。
	# 今日引擎不产未知动作 → 本分支恒不触发 → 逐字节零回归；CandidateProvider 的新动作由 ActionExecutor 认领落效果。
	if not (action in KNOWN_SOCIAL_ACTIONS):
		if ext != null:
			ext.execute(self, ag, opt)
		return
	var accepted := _acceptance_rule(ag, target, action, subject)
	var ra := _rel(ag, target["id"])
	var rt := _rel(target, ag["id"])

	if not accepted:
		ra["affinity"] = clampf(float(ra["affinity"]) - 3.0, -100.0, 100.0)
		rt["affinity"] = clampf(float(rt["affinity"]) - 3.0, -100.0, 100.0)
		var ev := _log_event(action, ag["id"], target["id"], subject, false, witnesses)
		ra["last_neg"] = ev["id"]; rt["last_neg"] = ev["id"]
		_bump_resentment(ag, target["id"], 3.0)   # 被婉拒积点怨气（足够多 → 触发冲突）
		# L3：拒绝=target 对 actor 的 defect；actor(self=good)+旁观者据此降 target 的 standing（拒绝坏人则正当）
		_judge_actor(ag, target["id"], false, ag["id"])
		for w in witnesses:
			_judge_actor(w, target["id"], false, ag["id"])
		ag["memory"].add("想找%s%s，被婉拒了" % [_name(target), _verb(action)], _impt(ag, target, 3.0, true), tick_no, [target["id"], "social", "refuse"])
		target["memory"].add("婉拒了%s的%s" % [_name(ag), _verb(action)], _impt(target, ag, 3.0, true), tick_no, [ag["id"], "social", "refuse"])
		emit_signal("social_event", ev)
		return

	# 接受 → 效果
	var aff_a := 2.0
	var aff_t := 2.0
	ag["needs"]["social"] = clampf(float(ag["needs"]["social"]) + 16.0, 0.0, 100.0)
	target["needs"]["social"] = clampf(float(target["needs"]["social"]) + 12.0, 0.0, 100.0)
	match action:
		"give":
			ag["inventory"]["gift"] = int(ag["inventory"].get("gift", 0)) - 1
			aff_t = 6.0; aff_a = 2.0
			target["needs"]["fun"] = clampf(float(target["needs"].get("fun", 0.0)) + 4.0, 0.0, 100.0)
		"gossip":
			# 知识边界：target 通过本次事务“得知”该 claim，source=actor
			if ag["beliefs"].has(subject) and not target["beliefs"].has(subject):
				var b: Dictionary = ag["beliefs"][subject]
				target["beliefs"][subject] = {"claim": b["claim"], "subject": b["subject"], "source": ag["id"], "via": "gossip", "tick": tick_no}
			if "爱八卦" in target.get("persona", {}).get("traits", []):
				target["needs"]["social"] = clampf(float(target["needs"]["social"]) + 6.0, 0.0, 100.0)
			aff_a = 1.0; aff_t = 1.0
		"invite":
			# 创建 meet 承诺：约在【当下两人所在的同一区】于 deadline 前再聚（赴约由 attend 驱动，需求危机会爽约 → broken）
			var area := String(ag.get("area", ""))
			if area == "":
				area = "plaza"
			var _cmt := {"id": _next_commit_id, "type": "meet", "a": ag["id"], "b": target["id"],
				"area": area, "created": tick_no, "deadline": tick_no + MEET_HORIZON, "status": "active"}
			commitments.append(_cmt)            # 全量历史（不变量/账本用）
			_active_commitments.append(_cmt)    # 活跃工作集（同一 dict 引用；每 tick 只扫这个，见 _resolve_commitments）
			_next_commit_id += 1
		"discuss":
			# FJ/Deffuant 成对更新：双方观点互相靠拢(固执锚定/高怨气背离)；演化但不坍缩成单一共识
			_fj_update(ag, target, subject)
			_fj_update(target, ag, subject)
			aff_a = 1.0; aff_t = 1.0
		"gossip_rep":
			# 传播第三方 C 的（坏）名声：信任源才采纳；target 对 C 的 standing 向 actor 靠拢一步 + affinity 微降
			if subject != "" and _agent_by_id.has(subject) and float(_rel(target, ag["id"])["trust"]) >= -20.0:
				var rc_a := _rel(ag, subject)
				var rc_t := _rel(target, subject)
				rc_t["standing"] = clampf(float(rc_t["standing"]) + signf(float(rc_a["standing"]) - float(rc_t["standing"])), -STANDING_CAP, STANDING_CAP)
				rc_t["affinity"] = clampf(float(rc_t["affinity"]) - 2.0, -100.0, 100.0)
				target["memory"].add("听%s说起%s的事" % [_name(ag), _name(_agent_by_id[subject])], 4, tick_no, [subject, ag["id"], "rep", "gossip"])
			aff_a = 1.0; aff_t = 1.0
		"confide":
			# S3c：owner 向信任者吐露秘密 → target 习得(via confide, confidedBy=直接上游) + 双向 trust 加深
			if ag["beliefs"].has(subject) and bool(ag["beliefs"][subject].get("secret", false)) and String(ag["beliefs"][subject].get("owner", "")) == String(ag["id"]) and not target["beliefs"].has(subject):
				var sb: Dictionary = ag["beliefs"][subject]
				target["beliefs"][subject] = {"claim": sb["claim"], "subject": sb["subject"], "source": ag["id"], "via": "confide", "tick": tick_no, "secret": true, "owner": sb["owner"], "confidedBy": {ag["id"]: tick_no}}
				confide_events += 1
			ra["trust"] = clampf(float(ra["trust"]) + CONFIDE_TRUST_GAIN, -100.0, 100.0)
			rt["trust"] = clampf(float(rt["trust"]) + CONFIDE_TRUST_GAIN, -100.0, 100.0)
			target["memory"].add("%s对我吐露了心事" % _name(ag), 6, tick_no, [ag["id"], "secret", "confided"])
			aff_a = 2.0; aff_t = 2.0
		"leak":
			# S3c：把别人吐露给我的秘密外传=背叛。target 习得(只记直接上游=actor)；对每个直接 teller 施背叛后果
			var tellers: Array = (ag["beliefs"][subject].get("confidedBy", {}) as Dictionary).keys() if ag["beliefs"].has(subject) else []
			if ag["beliefs"].has(subject) and bool(ag["beliefs"][subject].get("secret", false)) and not target["beliefs"].has(subject):
				var lb: Dictionary = ag["beliefs"][subject]
				target["beliefs"][subject] = {"claim": lb["claim"], "subject": lb["subject"], "source": ag["id"], "via": "leak", "tick": tick_no, "secret": true, "owner": lb["owner"], "confidedBy": {ag["id"]: tick_no}}
				lb["gossiped"] = tick_no   # 只八卦一次：说漏后这条秘密不再触发 DRAMA 加分（不满镇乱抖同一桩）
			for teller_id in tellers:
				if String(teller_id) == String(ag["id"]) or String(teller_id) == String(target["id"]):
					continue
				var betrayed: Dictionary = _agent_by_id.get(teller_id, {})
				if betrayed.is_empty():
					continue
				var rbv := _rel(betrayed, ag["id"])
				rbv["trust"] = clampf(float(rbv["trust"]) + BETRAY_TRUST_CRASH, -100.0, 100.0)
				rbv["affinity"] = clampf(float(rbv["affinity"]) + BETRAY_AFF_CRASH, -100.0, 100.0)
				_adjust_standing(betrayed, ag["id"], BETRAY_STANDING); st_neg_events += 1
				var be := _log_event("betray", ag["id"], String(teller_id), subject, true, witnesses, "leaked")
				rbv["last_neg"] = be["id"]
				_bump_resentment(betrayed, ag["id"], BETRAY_RESENT)   # >CONFLICT_TRIGGER → 必触发一段冲突
				betray_events += 1
				betrayed["memory"].add("%s把我吐露的秘密说了出去" % _name(ag), 9, tick_no, [ag["id"], "secret", "betray"])
				ag["memory"].add("把%s的秘密说漏了" % _name(betrayed), 6, tick_no, [String(teller_id), "secret", "betray"])
				_judge_actor(target, ag["id"], false, String(teller_id))
				for w in witnesses:
					if w["id"] != String(teller_id):
						_judge_actor(w, ag["id"], false, String(teller_id))
			aff_a = 1.0; aff_t = 1.0
		"endorse":
			# S3a：派系内对外群恶名者 C 统一口径 = gossip_rep 加速版（standing 靠拢两步，经守卫 clamp）
			if subject != "" and _agent_by_id.has(subject):
				var dir := signf(float(_rel(ag, subject)["standing"]) - float(_rel(target, subject)["standing"]))
				_adjust_standing(target, subject, dir * 2.0)
				var rce := _rel(target, subject)
				rce["affinity"] = clampf(float(rce["affinity"]) - FACTION_ENDORSE_AFF, -100.0, 100.0)
				endorse_events += 1
				target["memory"].add("和%s统一了对%s的看法" % [_name(ag), _name(_agent_by_id[subject])], 4, tick_no, [subject, ag["id"], "faction", "endorse"])
			aff_a = 1.0; aff_t = 1.0
		"aid":
			# S3b：盟友按需互助（补对方真实低 need），互惠记账 + 涨信任 + L3 help
			if subject != "" and target["needs"].has(subject):
				target["needs"][subject] = clampf(float(target["needs"][subject]) + AID_RELIEF, 0.0, 100.0)
			if int(ag["inventory"].get("gift", 0)) > 0 and subject == "fun":
				ag["inventory"]["gift"] = int(ag["inventory"]["gift"]) - 1
			_record_aid(ag, target)
			ra["trust"] = clampf(float(ra["trust"]) + AID_TRUST, -100.0, 100.0)
			rt["trust"] = clampf(float(rt["trust"]) + AID_TRUST, -100.0, 100.0)
			_judge_actor(target, ag["id"], true, target["id"])     # 互助=help-good→standing 升
			aid_accepted += 1
			target["memory"].add("%s雪中送炭帮了我" % _name(ag), 6, tick_no, [ag["id"], "pact", "aid"])
			aff_a = 3.0; aff_t = 3.0
	# S3a 同派系日常社交额外亲和（小量，防锁死；仅日常类，不与 aid/endorse 叠算）
	if String(ag["faction"]) != "" and String(ag["faction"]) == String(target["faction"]) and action in ["greet", "give", "gossip", "discuss"]:
		aff_a += FACTION_INGROUP_AFF; aff_t += FACTION_INGROUP_AFF
	ra["affinity"] = clampf(float(ra["affinity"]) + aff_a, -100.0, 100.0)
	rt["affinity"] = clampf(float(rt["affinity"]) + aff_t, -100.0, 100.0)
	ra["familiarity"] = float(ra["familiarity"]) + 1.0
	rt["familiarity"] = float(rt["familiarity"]) + 1.0
	_accrue_complement(ag, target)   # S3b：累积互补需求证据（needs→trigger 结盟依据）
	# Maki-Thompson 谣言变冷：actor 知道的谣言若 target 也已知 → 遇"已知者"，累计到 K 则停传(变 stifler)
	for cid2 in ag["beliefs"]:
		if ag["stifled"].has(cid2):
			continue
		if target["beliefs"].has(cid2):
			ag["metKnower"][cid2] = int(ag["metKnower"].get(cid2, 0)) + 1
			if int(ag["metKnower"][cid2]) >= STIFLE_K:
				ag["stifled"][cid2] = true

	var ev2 := _log_event(action, ag["id"], target["id"], subject, true, witnesses)
	ra["last_pos"] = ev2["id"]; rt["last_pos"] = ev2["id"]

	# 双方 + 旁观者各写“视角不同”的记忆（含人物 tag + 写入期 importance 派生）
	ag["memory"].add("和%s%s" % [_name(target), _verb(action)], _impt(ag, target, aff_a, false), tick_no, [target["id"], "social", action])
	target["memory"].add("%s来%s" % [_name(ag), _verb(action)], _impt(target, ag, aff_t, false), tick_no, [ag["id"], "social", action])
	for w in witnesses:
		w["memory"].add("看见%s和%s在%s%s" % [_name(ag), _name(target), _area_label(ag["pos"]), _verb(action)], 2, tick_no, [ag["id"], target["id"], "observe"])
	emit_signal("log_line", "%s → %s %s%s" % [_name(ag), _name(target), _verb(action), (" [%s]" % subject) if subject != "" else ""])
	emit_signal("social_event", ev2)

## 承诺解算：每 tick 检查 active meet → 双方到场即 fulfilled，到点没到即 broken（归责缺席方）。
## 只扫活跃工作集 _active_commitments（未决数 ∝ N，而非累积总量 ∝ N·time）→ per-tick 成本不随历史增长(docs/14)。
## 语义等价：工作集按创建序保留活跃项子集，与旧「扫全量跳过非活跃」逐项同序处理 → digest 逐字节不变。
func _resolve_commitments() -> void:
	var survivors: Array = []
	for c in _active_commitments:
		if String(c["status"]) != "active":
			continue                         # 被别处解算过 → 从工作集剔除（不进 survivors）
		var A: Dictionary = _agent_by_id.get(c["a"], {})
		var B: Dictionary = _agent_by_id.get(c["b"], {})
		if A.is_empty() or B.is_empty():
			survivors.append(c)              # 异常（agent 缺失）：留待下 tick
			continue
		var in_a := String(A.get("area", "")) == String(c["area"])
		var in_b := String(B.get("area", "")) == String(c["area"])
		if in_a and in_b:
			c["status"] = "fulfilled"
			var ra := _rel(A, B["id"])
			var rb := _rel(B, A["id"])
			ra["trust"] = clampf(float(ra["trust"]) + 4.0, -100.0, 100.0)
			rb["trust"] = clampf(float(rb["trust"]) + 4.0, -100.0, 100.0)
			ra["affinity"] = clampf(float(ra["affinity"]) + 3.0, -100.0, 100.0)
			rb["affinity"] = clampf(float(rb["affinity"]) + 3.0, -100.0, 100.0)
			ra["familiarity"] = float(ra["familiarity"]) + 1.0
			rb["familiarity"] = float(rb["familiarity"]) + 1.0
			ra["standing"] = clampf(float(ra["standing"]) + 1.0, -STANDING_CAP, STANDING_CAP)   # 守约=互相 help
			rb["standing"] = clampf(float(rb["standing"]) + 1.0, -STANDING_CAP, STANDING_CAP)
			var e := _log_event("meet", c["a"], c["b"], "", true, [])
			ra["last_pos"] = e["id"]; rb["last_pos"] = e["id"]
			var lbl := _area_label_id(String(c["area"]))
			A["memory"].add("如约在%s见到了%s" % [lbl, _name(B)], 5, tick_no, [B["id"], "commit", "meet"])
			B["memory"].add("如约在%s见到了%s" % [lbl, _name(A)], 5, tick_no, [A["id"], "commit", "meet"])
			emit_signal("social_event", e)
		elif tick_no >= int(c["deadline"]):
			c["status"] = "broken"
			var no_shows: Array = []
			if not in_a: no_shows.append(c["a"])
			if not in_b: no_shows.append(c["b"])
			var e2 := _log_event("meet", c["a"], c["b"], "", false, [])
			for ns in no_shows:
				var other_id: String = c["b"] if ns == c["a"] else c["a"]
				var other: Dictionary = _agent_by_id[other_id]
				var ns_ag: Dictionary = _agent_by_id[ns]
				var ro := _rel(other, ns)               # 被放鸽子的一方更新对爽约者的关系
				ro["trust"] = clampf(float(ro["trust"]) - 6.0, -100.0, 100.0)
				ro["affinity"] = clampf(float(ro["affinity"]) - 5.0, -100.0, 100.0)
				ro["standing"] = clampf(float(ro["standing"]) - 2.0, -STANDING_CAP, STANDING_CAP)  # L3：对守约者爽约=defect-against-good → 坏名声
				st_neg_events += 1
				ro["last_neg"] = e2["id"]
				_bump_resentment(other, ns, 5.0)        # 怨气累积 → 可能触发/升级一段冲突
				var lbl2 := _area_label_id(String(c["area"]))
				other["memory"].add("%s放了我鸽子，没来%s" % [_name(ns_ag), lbl2], 6, tick_no, [ns, "commit", "broken"])
				ns_ag["memory"].add("爽约了和%s在%s的约定" % [_name(other), lbl2], 5, tick_no, [other_id, "commit", "broken"])
			emit_signal("social_event", e2)
		if String(c["status"]) == "active":     # 仍未决（等对方 / 未到点）→ 留在工作集
			survivors.append(c)
	_active_commitments = survivors

# ── 冲突生命周期（GPT-5.5 §7.2/§9.3：积怨→对质→道歉→修复/冷战）─────────────────
## CHARACTER 层判据：此人设是否"会为小怨气当面理论"（直性子）。纯人设函数，确定性。
func _is_blunt(ag: Dictionary) -> bool:
	for t in ag.get("persona", {}).get("traits", []):
		if t in BLUNT_TRAITS:
			return true
	return false

## DRAMA 八卦泄密判据：此人设是否"憋不住托付的秘密"（爱八卦）。纯人设函数，确定性。
func _is_gossipy(ag: Dictionary) -> bool:
	for t in ag.get("persona", {}).get("traits", []):
		if t in GOSSIP_TRAITS:
			return true
	return false

## DRAMA 层判据：一段被 CHARACTER 默认憋着的心结是否憋够久、该由导演安排一场对质推进剧情。
## 越重(severity)/越被反复冒犯(escalations)的怨越早爆；纯 f(age,severity,escalations)，确定性、可回放。
func _drama_erupts(cf: Dictionary) -> bool:
	if not DRAMA_DIRECTOR:
		return false
	var sev: int = int(round(minf(float(cf.get("severity", 0.0)), 20.0)))
	var escalated: bool = int(cf.get("escalations", 0)) > 0
	if not (escalated or sev >= DRAMA_ERUPT_SEV):   # 只有够戏剧性的冲突才安排场；小怨留着不爆 → 保住社会分层
		return false
	var age: int = tick_no - int(cf.get("triggered", tick_no))
	var horizon: int = DRAMA_ERUPT_AFTER - sev * 25
	if escalated:
		horizon -= 200
	return age >= maxi(DRAMA_ERUPT_FLOOR, horizon)

## DRAMA 层判据 · 派系合围：只有对象是真·过街老鼠（名声极差 + 已激化的冲突）才让"众人合围"成一场罕见戏。
func _mob_erupts(cfo: Dictionary, standing: float) -> bool:
	if not DRAMA_DIRECTOR:
		return false
	return standing <= MOB_ERUPT_STANDING and not cfo.is_empty() and int(cfo.get("escalations", 0)) > 0

func _find_conflict(a_id: String, b_id: String, statuses: Array) -> Dictionary:
	for c in conflicts:
		if c["a"] == a_id and c["b"] == b_id and String(c["status"]) in statuses:
			return c
	return {}

## 给 holder 对 toward_id 累积怨气；越线则触发冲突；已有未了冲突则升级。
func _bump_resentment(holder: Dictionary, toward_id: String, amt: float) -> void:
	var r := _rel(holder, toward_id)
	r["resentment"] = clampf(float(r["resentment"]) + amt, 0.0, 100.0)
	var open := _find_conflict(holder["id"], toward_id, ["simmering", "escalated"])
	if not open.is_empty():
		open["escalations"] = int(open["escalations"]) + 1
		open["severity"] = float(open["severity"]) + amt
		if int(open["escalations"]) >= ESC_THRESH:
			open["status"] = "escalated"
	elif _find_conflict(holder["id"], toward_id, ["simmering", "escalated", "confronted", "lingering"]).is_empty() and float(r["resentment"]) >= CONFLICT_TRIGGER:
		conflicts.append({"id": _next_conflict_id, "a": holder["id"], "b": toward_id, "status": "simmering",
			"triggered": tick_no, "lastEscalate": tick_no, "severity": float(r["resentment"]), "escalations": 0, "confronted": 0, "repaired": 0})
		_next_conflict_id += 1
		_log_event("conflict", holder["id"], toward_id, "", false, [])
		holder["memory"].add("对%s积了怨气" % _name(_agent_by_id[toward_id]), 5, tick_no, [toward_id, "conflict", "trigger"])

## confront —— A(委屈方)当面对质 B(冒犯方)。B 接茬→confronted(通往和解)；B 否认/回避→escalated。
func _resolve_confront(A: Dictionary, B: Dictionary, witnesses: Array) -> void:
	var c := _find_conflict(A["id"], B["id"], ["simmering", "escalated", "lingering"])
	if c.is_empty():
		return
	A["needs"]["social"] = clampf(float(A["needs"]["social"]) + 10.0, 0.0, 100.0)
	B["needs"]["social"] = clampf(float(B["needs"]["social"]) + 6.0, 0.0, 100.0)
	var proud := -25.0 if "寡言" in B.get("persona", {}).get("traits", []) else 0.0
	var engage := 55.0 + proud + (_rng_at(71, _aid(A)).randf() - 0.5) * 30.0 > 0.0
	var ra := _rel(A, B["id"])
	var rb := _rel(B, A["id"])
	if engage:
		c["status"] = "confronted"; c["confronted"] = tick_no
		ra["affinity"] = clampf(float(ra["affinity"]) - 2.0, -100.0, 100.0)
		rb["affinity"] = clampf(float(rb["affinity"]) - 2.0, -100.0, 100.0)  # 对质当下气氛紧张
		var e := _log_event("confront", A["id"], B["id"], "", true, witnesses)
		ra["last_neg"] = e["id"]
		A["memory"].add("当面找%s把话说开了" % _name(B), 6, tick_no, [B["id"], "conflict", "confront"])
		B["memory"].add("%s来找我理论，我听了" % _name(A), 6, tick_no, [A["id"], "conflict", "confront"])
		emit_signal("social_event", e)
	else:
		c["severity"] = float(c["severity"]) + 4.0
		c["escalations"] = int(c["escalations"]) + 1
		c["status"] = "escalated"
		ra["resentment"] = clampf(float(ra["resentment"]) + 3.0, 0.0, 100.0)
		ra["affinity"] = clampf(float(ra["affinity"]) - 3.0, -100.0, 100.0)
		ra["standing"] = clampf(float(ra["standing"]) - 1.0, -STANDING_CAP, STANDING_CAP)   # 否认=defect-against-good
		st_neg_events += 1
		for w in witnesses:
			_judge_actor(w, B["id"], false, A["id"])
		var e2 := _log_event("confront", A["id"], B["id"], "", false, witnesses)
		ra["last_neg"] = e2["id"]
		A["memory"].add("找%s理论，%s不认，更气了" % [_name(B), _name(B)], 7, tick_no, [B["id"], "conflict", "escalate"])
		B["memory"].add("%s来质问，我没接茬" % _name(A), 5, tick_no, [A["id"], "conflict", "escalate"])
		emit_signal("social_event", e2)

## apologize —— B(冒犯方)向 A(委屈方)道歉（仅在已被对质后，知识边界）。A 视严重度决定原谅→repaired，或拒绝。
func _resolve_apologize(B: Dictionary, A: Dictionary, witnesses: Array) -> void:
	var c := _find_conflict(A["id"], B["id"], ["confronted"])
	if c.is_empty():
		return
	B["needs"]["social"] = clampf(float(B["needs"]["social"]) + 8.0, 0.0, 100.0)
	A["needs"]["social"] = clampf(float(A["needs"]["social"]) + 8.0, 0.0, 100.0)
	var ra := _rel(A, B["id"])
	var rb := _rel(B, A["id"])
	var forgiven := (FORGIVE_CAP - float(c["severity"])) + (_rng_at(73, _aid(A)).randf() - 0.5) * 16.0 > 0.0
	if forgiven:
		c["status"] = "repaired"; c["repaired"] = tick_no
		ra["resentment"] = 0.0                              # 和解 → 清账
		ra["trust"] = clampf(float(ra["trust"]) + 5.0, -100.0, 100.0)
		rb["trust"] = clampf(float(rb["trust"]) + 2.0, -100.0, 100.0)
		ra["affinity"] = clampf(float(ra["affinity"]) + 6.0, -100.0, 100.0)
		rb["affinity"] = clampf(float(rb["affinity"]) + 6.0, -100.0, 100.0)
		ra["standing"] = clampf(float(ra["standing"]) + 2.0, -STANDING_CAP, STANDING_CAP)   # 和解=B 在 help → 坏名声恢复
		for w in witnesses:
			_judge_actor(w, B["id"], true, A["id"])
		var e := _log_event("apologize", B["id"], A["id"], "", true, witnesses)
		ra["last_pos"] = e["id"]; rb["last_pos"] = e["id"]
		B["memory"].add("向%s道了歉，和解了" % _name(A), 6, tick_no, [A["id"], "conflict", "repair"])
		A["memory"].add("%s道歉了，我原谅了" % _name(B), 6, tick_no, [B["id"], "conflict", "repair"])
		emit_signal("social_event", e)
	else:
		var e2 := _log_event("apologize", B["id"], A["id"], "", false, witnesses)
		B["memory"].add("向%s道歉，没被接受" % _name(A), 5, tick_no, [A["id"], "conflict", "reject"])
		A["memory"].add("%s来道歉，我还没法原谅" % _name(B), 6, tick_no, [B["id"], "conflict", "reject"])
		emit_signal("social_event", e2)

## 久未对质的冲突 → lingering（冷战/积怨）。
func _sweep_conflicts() -> void:
	for c in conflicts:
		if (String(c["status"]) == "simmering" or String(c["status"]) == "escalated") and int(c["confronted"]) == 0 and tick_no - int(c["triggered"]) > LINGER_AFTER:
			c["status"] = "lingering"

func _area_label_id(area: String) -> String:
	return str(world.get("areas", {}).get(area, {}).get("label", area))

func _area_centroid(area: String) -> Vector2i:
	var r: Array = world.get("areas", {}).get(area, {}).get("rect", [0, 0, 1, 1])
	return Vector2i(int(r[0]) + int(r[2]) / 2, int(r[1]) + int(r[3]) / 2)

func _has_active_meet(a_id: String, b_id: String) -> bool:
	for c in _active_commitments:            # 只扫活跃工作集（O(未决)而非 O(累积)）
		if String(c["status"]) == "active" and ((c["a"] == a_id and c["b"] == b_id) or (c["a"] == b_id and c["b"] == a_id)):
			return true
	return false

func _any_active_meet(a_id: String) -> bool:
	for c in _active_commitments:
		if String(c["status"]) == "active" and (c["a"] == a_id or c["b"] == a_id):
			return true
	return false

func _find_commitment(id: int) -> Dictionary:
	for c in commitments:
		if int(c["id"]) == id:
			return c
	return {}

## 远/近判定：lod_near_cap>0 → 不在「最近 K」集即为 far；否则按到焦点的曼哈顿半径。
func _is_far(ag: Dictionary) -> bool:
	if lod_near_cap > 0:
		return not _near_set.has(ag["id"])
	return (absi(ag["pos"].x - lod_focus.x) + absi(ag["pos"].y - lod_focus.y)) > lod_near_radius

## 计算 near cohort = 距焦点最近的 K 个 agent（曼哈顿距离，按 _aid 做确定 tie-break）。每 tick 调用一次。
func _compute_near_set() -> void:
	_near_set = {}
	var ranked := agents.duplicate()
	ranked.sort_custom(func(a, b):
		var da := absi(a["pos"].x - lod_focus.x) + absi(a["pos"].y - lod_focus.y)
		var db := absi(b["pos"].x - lod_focus.x) + absi(b["pos"].y - lod_focus.y)
		if da != db: return da < db
		return absi(_aid(a)) < absi(_aid(b)))
	for i in range(mini(lod_near_cap, ranked.size())):
		_near_set[ranked[i]["id"]] = true

## L3 激进：远端 agent 的统计维持。每 LOD_FAR_MULT tick（按 _aid 错相位均摊）把偏低需求补一点，
## 模拟「在所处区域被动生活」——不寻路、不枚举候选、不参与社交。确定（无 RNG）→ 可回放。
func _far_maintain(ag: Dictionary) -> void:
	if (tick_no % LOD_FAR_MULT) != (absi(_aid(ag)) % LOD_FAR_MULT):
		return
	for nid in ag["needs"]:
		if float(ag["needs"][nid]) < 50.0:
			ag["needs"][nid] = minf(100.0, float(ag["needs"][nid]) + AGG_RELIEF)

func _min_need(ag: Dictionary) -> float:
	var m := 100.0
	for nid in ag["needs"]:
		m = minf(m, float(ag["needs"][nid]))
	return m

## 每夜反思：从关系/冲突/派系/名声确定性提炼一条洞察写回记忆（引擎地板，无模型也在）。
## 记忆不入 event_log/digest/不变量 → 确定且零回归。模型后端可事后用 AIBackend.reflect 润色覆盖(见 _reflect_llm)。
func _reflect_agent(ag: Dictionary) -> void:
	var mem = ag.get("memory")
	if mem == null:
		return
	var my_id := String(ag["id"])
	var best_id := ""
	var best_aff := 20.0
	var rival_id := ""
	var rival_aff := -15.0
	var familiars := 0
	for oid in ag["relationships"]:
		var r: Dictionary = ag["relationships"][oid]
		var aff := float(r["affinity"])
		if float(r["familiarity"]) > 2.0:
			familiars += 1
		if aff >= best_aff and float(r["familiarity"]) >= 8.0:
			best_aff = aff; best_id = oid
		if aff <= rival_aff:
			rival_aff = aff; rival_id = oid
	var conflict_with := ""
	for c in conflicts:
		if String(c["status"]) == "repaired":
			continue
		if String(c["a"]) == my_id: conflict_with = String(c["b"]); break
		if String(c["b"]) == my_id: conflict_with = String(c["a"]); break
	var insight := ""
	if conflict_with != "" and _agent_by_id.has(conflict_with):
		insight = "我和%s之间的疙瘩，还没解开。" % _name(_agent_by_id[conflict_with])
	elif rival_id != "" and _agent_by_id.has(rival_id):
		insight = "对%s，我心里始终存着一点提防。" % _name(_agent_by_id[rival_id])
	elif best_id != "" and _agent_by_id.has(best_id):
		insight = "%s大概是我在镇上最信得过的人了。" % _name(_agent_by_id[best_id])
	elif String(ag.get("faction", "")) != "" and int(ag.get("faction_size", 1)) > 1:
		insight = "有些事情上，我和几个人想到了一块儿。"
	elif familiars < 2:
		insight = "最近有点冷清，想找个人说说话。"
	else:
		insight = "日子过得平平淡淡，倒也踏实。"
	mem.add(insight, 6, tick_no, ["insight"])
	# 模型后端：把这条确定性洞察交给 LLM 润色成更自然的一句（异步、限预算、失败保留地板版）。
	if backend != null and backend.has_method("reflect"):
		_reflect_llm(ag, insight)

## LLM 反思润色（模型后端可选皮肤）：把地板洞察 + 近期记忆交给模型合成更自然的一句，异步写回。
func _reflect_llm(ag: Dictionary, floor_insight: String) -> void:
	var mem = ag.get("memory")
	var recent: Array = mem.retrieve([], tick_no, 5) if mem != null else []
	var aid := String(ag["id"])
	backend.reflect(ag, floor_insight, recent, func(text: String):
		var m2 = ag.get("memory")
		if m2 != null and text.strip_edges() != "":
			m2.add(text.strip_edges(), 7, tick_no, ["insight", "llm"]))

## 效用/接受权重查表（docs/14 §1 步骤4）：data/utility.json 有该键则用，否则回落代码默认。缺表/缺键 → 逐字节不变。
func _w(key: String, default: float) -> float:
	return float(utility.get(key, default))

# ── Wave 1c 天气（docs/15 §3）：纯函数、无状态、无 RNG 流消耗 ────────────────
## 当日天气 = _hash01(seed:day) 按权重表落桶。确定：同 seed 同 day 恒同天气；goto_tick 重演天然一致。
func _weather_of_day(d: int) -> String:
	var types: Dictionary = weather.get("types", {})
	if types.is_empty():
		return ""
	var names: Array = types.keys()
	names.sort()                       # 定序（不依赖字典插入序）
	var total := 0.0
	for n in names:
		total += float(types[n].get("w", 1.0))
	var r := _hash01("%d:wx:%d" % [seed_base, d]) * total
	var acc := 0.0
	for n in names:
		acc += float(types[n].get("w", 1.0))
		if r < acc:
			return String(n)
	return String(names[names.size() - 1])

## 动作在当日天气下的收益乘子（≤1 dampen-only：坏天只压户外偏好、不放大任何欲望）；缺表/缺键→1.0。
func _weather_mult(action: String) -> float:
	if weather_today == "":
		return 1.0
	var m: Dictionary = weather.get("mults", {}).get(weather_today, {})
	if m.is_empty():
		return 1.0
	return clampf(float(m.get(action, 1.0)), 0.3, 1.0)

## Wave 3b：当季 = 纯 day 函数，按 seasons.order【顺序】轮转（非随机；春→夏→秋→冬→…）。缺表→""=零扰动。
func _season_of_day(d: int) -> String:
	var order: Array = lifecycle.get("seasons", {}).get("order", [])
	if order.is_empty():
		return ""
	var slen := maxi(1, int(lifecycle.get("season_length_days", 15)))
	return String(order[((d - 1) / slen) % order.size()])

## 动作在当季的收益乘子（≤1 dampen-only，同 weather 教训：只压不放大→不触发全镇同步崩溃）；缺表/缺键→1.0。
func _season_mult(action: String) -> float:
	if season_today == "":
		return 1.0
	var m: Dictionary = lifecycle.get("seasons", {}).get("mults", {}).get(season_today, {})
	if m.is_empty():
		return 1.0
	return clampf(float(m.get(action, 1.0)), 0.3, 1.0)

## agent 当前年龄 = 起始龄 + 已过整年（纯确定 (day-1)/days_per_year）。缺 aging→0。
func _age_of(id: String) -> int:
	var agd: Dictionary = lifecycle.get("aging", {})
	if agd.is_empty():
		return 0
	var start := int((agd.get("ages", {}) as Dictionary).get(id, agd.get("default_start_age", 30)))
	return start + (day - 1) / maxi(1, int(agd.get("days_per_year", 30)))

## 年龄→人生阶段名（stages 按 max 升序，取首个 age<=max）。缺→""。
func _stage_of(age: int) -> String:
	for st in lifecycle.get("aging", {}).get("stages", []):
		if age <= int((st as Dictionary).get("max", 999)):
			return String((st as Dictionary).get("name", ""))
	return ""

## Wave 3b 日界：换季 + 生日里程碑（纯确定的记忆写入，喂 voice/观察台；只写 memory 不产生 event→不入 digest）。
func _update_lifecycle(prev_season: String) -> void:
	if lifecycle.is_empty():
		return
	if season_today != "" and prev_season != "" and season_today != prev_season:
		for ag in agents:
			ag["memory"].add("入%s了" % season_today, 3, tick_no, ["season", season_today])
	var agd: Dictionary = lifecycle.get("aging", {})
	if not agd.is_empty():
		var dpy := maxi(1, int(agd.get("days_per_year", 30)))
		if day > 1 and (day - 1) % dpy == 0:              # 跨年 → 各自长一岁
			for ag in agents:
				var a := _age_of(String(ag["id"]))
				ag["memory"].add("又长了一岁，%d 岁了（%s）" % [a, _stage_of(a)], 4, tick_no, ["birthday", "age"])

# ── Wave 2a 职业：差异工资 + 班次（数据驱动；jobs.json 缺失时 _wage_for ≡ economy.wages 查表=零扰动）──
func _job_of(id: String) -> Dictionary:
	return jobs.get("jobs", {}).get(id, {}) if not jobs.is_empty() else {}

## 是否在自己的班次相位内。空 shift=全天；rhythm 缺失(_phase_of 返 "")=视为在班（优雅降级）。
func _in_shift(job: Dictionary) -> bool:
	var sh: Array = job.get("shift", [])
	if sh.is_empty():
		return true
	var ph := _phase_of(time_of_day())
	return ph == "" or ph in sh

## Wave 2c 技能等级：本职动作完成数 / per_level，封顶 max_level。缺 skills.json → 恒 0（零扰动）。
func _skill_level(ag: Dictionary, action: String) -> int:
	if skills.is_empty():
		return 0
	var c := int((ag.get("skills", {}) as Dictionary).get(action, 0))
	return mini(int(skills.get("max_level", 5)), c / maxi(1, int(skills.get("per_level", 15))))

## 某 agent 做某动作此刻的工资：本职工作且在班 → 职位工资 + 技能加成（熟练工挣更多→深化分化）；否则 → 基础零工价。
func _wage_for(ag: Dictionary, action: String) -> int:
	var job := _job_of(String(ag["id"]))
	if not job.is_empty() and String(job.get("action", "")) == action and _in_shift(job):
		return int(job.get("wage", 0)) + _skill_level(ag, action) * int(skills.get("wage_bonus", 0) if not skills.is_empty() else 0)
	return int(economy.get("wages", {}).get(action, 0))

# ── Wave 2b·WorldPatch 原语（docs/15 §3 原语#4）：动态对象增删的【唯一通道】，写 event 溯源 ─────
## spawn：id 由调用方给定（须确定=f(名,day,序)，绝不用计数器/RNG）；写 event(type=world, note=spawn)。
func spawn_object(def: Dictionary) -> void:
	var oid := String(def["id"])
	if world["objects"].has(oid):
		return
	var od := def.duplicate(true)
	od["pos"] = Vector2i(int(def["pos"][0]), int(def["pos"][1])) if def["pos"] is Array else def["pos"]
	od["area"] = _area_at(od["pos"])
	world["objects"][oid] = od
	_log_event("world", "town", oid, "", true, [], "spawn")

func despawn_object(oid: String) -> void:
	if not world["objects"].has(oid):
		return
	world["objects"].erase(oid)
	# 清引用：正在用/赶往该对象的 agent 作废其 option（下 tick 重决策；确定）
	for ag in agents:
		var opt = ag.get("option")
		if opt != null and String(opt.get("kind", "object")) == "object" and String(opt.get("target", "")) == oid:
			ag["option"] = null
	_log_event("world", "town", oid, "", true, [], "despawn")

## Wave 2b 节日调度（Director v1=纯规则体,"只撒机会地形不写剧情"）：日界调用。
## 确定性：day 取模 + weather_today（本身纯函数）；对象 id=名:day:序。昨日节日先清场，再开今日的。
func _update_festival() -> void:
	if festival_active != "":
		for oid in _fest_objects:
			despawn_object(String(oid))
		_fest_objects.clear()
		festival_active = ""
	if festivals.is_empty():
		return
	var names: Array = festivals.get("festivals", {}).keys()
	names.sort()
	for nm in names:
		var f: Dictionary = festivals["festivals"][nm]
		var every := maxi(1, int(f.get("every_days", 7)))
		if day % every != int(f.get("offset", 0)):
			continue
		var req: Array = f.get("weather_req", [])
		if not req.is_empty() and not (weather_today in req):
			continue                      # 天气不合 → 顺延（天气→节日解锁链）
		festival_active = String(nm)
		var seq := 0
		for od in f.get("objects", []):
			var def: Dictionary = (od as Dictionary).duplicate(true)
			def["id"] = "fest_%s_%d_%d" % [nm, day, seq]
			seq += 1
			spawn_object(def)
			_fest_objects.append(def["id"])
		break                             # 一日一节

## Wave 3a 计票：S2 attitude 即选票，|a|<abstain_below 弃权、否则按符号。纯快照函数——只读 attitudes、定序遍历、无 RNG/Time。
## 玩家不自动计入（其立场由玩家自己；后续可加玩家投票动作）。这就是 docs/15「计票=快照纯函数=硬不变量」。
func _tally_election(topic: String, abstain_below: float) -> Dictionary:
	var yea := 0; var nay := 0; var abstain := 0
	for ag in agents:
		if bool(ag.get("is_player", false)):
			continue
		var a := float((ag["attitudes"] as Dictionary).get(topic, 0.0))
		if absf(a) < abstain_below:
			abstain += 1
		elif a > 0.0:
			yea += 1
		else:
			nay += 1
	return {"topic": topic, "yea": yea, "nay": nay, "abstain": abstain, "voters": yea + nay + abstain, "pass": yea > nay}

## Wave 3a 选举日界调度（docs/15 §3.3 收获期）：到期把 topic 付诸投票 → 记 election 事件溯源 + 全镇里程碑记忆。
## 确定性：day 取模调度 + 纯快照计票 + 定序记忆；缺 elections.json 或 topic 非法 → 直接返回=零扰动。
## LLM 演讲（若接）纯渲染一票不改；结果的世界效果(WorldPatch/调参键)留 V2。
func _update_election() -> void:
	if elections.is_empty():
		return
	var topic := String(elections.get("topic", ""))
	if not (topic in TOPICS):
		return
	var every := maxi(1, int(elections.get("every_days", 14)))
	if day % every != int(elections.get("offset", 0)):
		return
	var abstain_below := float(elections.get("abstain_below", FACTION_SALIENT))
	var res := _tally_election(topic, abstain_below)
	res["day"] = day
	election_log.append(res)
	last_election = res
	# 事件溯源：accepted=是否通过（town→topic）。不 emit social（治理非社交，与 pay/world 同类，inv2/3 已排除 election）。
	_log_event("election", "town", topic, topic, bool(res["pass"]), [], "pass" if bool(res["pass"]) else "fail")
	# V2：通过 → 发 WorldPatch（镇子照集体决定改样：如扩建咖啡馆的 civic 对象，本局内永久留存）。
	# 确定：id=civic_话题_日（spawn_object 幂等防重）；缺 on_pass 或否决 → 无世界效果 = V1 逐字节。goto_tick 重演靠选举日重新 spawn 确定重建。
	if bool(res["pass"]) and elections.has("on_pass"):
		var op: Dictionary = elections.get("on_pass", {})
		if op.has("object") and (op["object"] is Dictionary):
			var def: Dictionary = (op["object"] as Dictionary).duplicate(true)
			def["id"] = "civic_%s_%d" % [topic, day]
			spawn_object(def)
	var verdict := "通过" if bool(res["pass"]) else "否决"
	for ag in agents:
		if bool(ag.get("is_player", false)):
			continue
		var mine := float((ag["attitudes"] as Dictionary).get(topic, 0.0))
		var stance := "弃权" if absf(mine) < abstain_below else ("投了赞成" if mine > 0.0 else "投了反对")
		ag["memory"].add("镇上就『%s』表决，%s（%d赞成/%d反对/%d弃权）——我%s" % [
			topic, verdict, int(res["yea"]), int(res["nay"]), int(res["abstain"]), stance], 6, tick_no, [topic, "election", "civic"])

## Wave 2a+ 阶层 gossip：每夜同区邻居目击贫富 → 生成一手 belief（via=seen，inv6 豁免溯源）。
## 之后由既有 gossip 机制自然传播（_unspread_belief 会挑中它）——"财富传闻"零新管线。确定（定序遍历，无 RNG）。
func _observe_wealth() -> void:
	var wg: Dictionary = economy.get("wealth_gossip", {})
	var rich := int(wg.get("rich_line", 6))
	for aid in _nightly_active_ids():
		var A: Dictionary = _agent_by_id[aid]
		for B in _nearby_agents(A):
			if B.get("is_player", false):
				continue                     # 玩家钱冻结(M1)，传闻无意义
			var c := int(B["inventory"].get("coin", 0))
			var bid := ""
			var claim := ""
			if c >= rich:
				bid = "W:%s:rich" % B["id"]
				claim = "%s最近手头挺阔绰" % _name(B)
			elif c <= 0:
				bid = "W:%s:broke" % B["id"]
				claim = "%s最近手头紧巴巴的" % _name(B)
			if bid != "" and not A["beliefs"].has(bid):
				A["beliefs"][bid] = {"claim": claim, "subject": String(B["id"]), "source": "__seen__", "via": "seen", "tick": tick_no}

# ── Wave 1b 经济·Ledger 原语（docs/15 §3 原语#5）────────────────────────────
func _econ_on() -> bool:
	return not economy.is_empty()

## 金钱增减的【唯一通道】：整数、不足即拒、写 event_log 溯源（type=pay，note=reason）。
## from/to = agent id 或 "town"（镇库）。守恒由"只此一门"结构保证 → 硬不变量 #34 可机检。
func transfer(from_id: String, to_id: String, amt: int, reason: String) -> bool:
	if amt <= 0:
		return false
	var from_coin := _coin_of(from_id)
	if from_coin < amt:
		return false
	_set_coin(from_id, from_coin - amt)
	_set_coin(to_id, _coin_of(to_id) + amt)
	var ev := _log_event("pay", from_id, to_id, "", true, [], reason)
	var _e = ev   # 事件仅作账本溯源（不 emit social_event——经济事务非社交）
	return true

func _coin_of(id: String) -> int:
	if id == "town":
		return town_coin
	var ag: Dictionary = _agent_by_id.get(id, {})
	return int(ag.get("inventory", {}).get("coin", 0)) if not ag.is_empty() else 0

func _set_coin(id: String, v: int) -> void:
	if id == "town":
		town_coin = v
		return
	var ag: Dictionary = _agent_by_id.get(id, {})
	if not ag.is_empty():
		ag["inventory"]["coin"] = v

## 全镇货币总量（守恒不变量用）。
func money_total() -> int:
	var s := town_coin
	for ag in agents:
		s += int(ag["inventory"].get("coin", 0))
	return s

## 确定性 [0,1) 哈希（字符串→稳定小数；天生立场用）。
func _hash01(s: String) -> float:
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return float(h % 100000) / 100000.0

## S2：Friedkin-Johnsen 单步（成对/Deffuant）——i 朝 j 靠拢，按 trust·familiarity 加权，
## 固执度(1-ξ)锚定天生立场 → 持久分歧而非单一共识；高怨气→背离(signed)。
func _fj_update(i: Dictionary, j: Dictionary, t: String) -> void:
	var ro := _rel(i, j["id"])
	var backfire := float(ro["resentment"]) > BACKFIRE_RESENT
	var tw := clampf((float(ro["trust"]) + 50.0) / 100.0 * (0.5 + minf(float(ro["familiarity"]), 10.0) / 20.0), 0.05, 0.6)
	var xj := (2.0 * float(i["attitudes"][t]) - float(j["attitudes"][t])) if backfire else float(j["attitudes"][t])
	var blended := tw * xj + (1.0 - tw) * float(i["attitudes"][t])
	i["attitudes"][t] = clampf(float(i["xi"]) * blended + (1.0 - float(i["xi"])) * float(i["attitude0"][t]), -1.0, 1.0)

## 接受规则（确定性，含 _rng_at 种子抖动；非法强度永远交给引擎，模型只管选+说）。
func _acceptance_rule(actor: Dictionary, target: Dictionary, action: String, subject: String = "") -> bool:
	var rr := _rel(target, actor["id"])
	var aff := float(rr["affinity"])
	var st := float(rr["standing"]) * STANDING_K   # 声誉门：坏名声更难被接受 → 涌现放逐
	var need := float(target["needs"].get("social", 100.0))
	var jitter := (_rng_at(31, _aid(target)).randf() - 0.5) * 20.0   # 接受由 target 决定 → 用 target 的子流
	var traits: Array = target.get("persona", {}).get("traits", [])
	var fac := _faction_term(target, actor)   # S3a：同派系更易接受、跨派系更难（涌现放逐加剧）——内建修正保持内联(null-ext 等值)
	# L7 挂点(docs/15 §3 #1)：外置接受修正叠加项。ext=null → 0.0，x+0.0==x(IEEE) → 与既往逐字节一致。
	# 注：性格短路分支(爱八卦 return true)不叠 extra——modifier 只调阈值和，不推翻性格硬规则。
	var extra := 0.0
	if ext != null:
		extra = float(ext.accept_delta(self, actor, target, action, subject))
	if action == "discuss":
		# Deffuant 有界信任：观点差在信任带 ε 内才谈得拢（软门）；差太大 → 拒谈（记一笔）；同派系更谈得拢
		var diff := absf(float(actor["attitudes"].get(subject, 0.0)) - float(target["attitudes"].get(subject, 0.0)))
		var okk := (float(target["eps"]) - diff) * 30.0 + aff + st + fac + jitter + extra > _w("accept_discuss", 0.0)
		if not okk:
			refused_by_bound += 1
		return okk
	if action == "confide":
		return aff + st + jitter + extra > _w("accept_confide", -10.0)   # 一般都愿听心事（不叠 fac：吐露是私人信任）
	if action == "leak":                                      # 听秘密=收八卦：同 gossip 矜持门
		if "爱八卦" in traits:
			return true
		var reservedl := -15.0 if ("寡言" in traits or "温柔" in traits) else 0.0
		return aff + reservedl + st + jitter + extra > _w("accept_leak", 0.0)
	if action == "endorse":
		return aff + st + fac + extra > _w("accept_endorse", -50.0)  # 同派系背书：几乎必接（fac=+K）
	if action == "aid":
		return aff + st + extra > _w("accept_aid", -50.0)            # 盟友善意：几乎总收（走自己门，不叠 fac）
	if action == "give":
		return aff + st + fac + extra > _w("accept_give", -60.0)     # 一般都收礼，除非极度反感/极坏名声
	if action == "gossip" or action == "gossip_rep":
		if "爱八卦" in traits:
			return true                                      # 爱八卦者来者不拒
		var reserved := -15.0 if ("寡言" in traits or "温柔" in traits) else 0.0  # 寡言/温柔者矜持
		return aff + reserved + st + fac + jitter + extra > _w("accept_gossip", 0.0)
	if action == "invite":
		return (100.0 - need) * 0.35 + aff + st + fac + jitter + extra > _w("accept_invite", -2.0)   # 约见：缺社交/有好感/好名声/同派系更易答应
	# greet: 对方越缺社交/越有好感/名声越好/同派系越易接受
	return (100.0 - need) * 0.4 + aff + st + fac + jitter + extra > _w("accept_greet", 0.0)

# ── 关系账本 / belief / 事件账本 / 工具 ─────────────────────────────────────
func _rel(ag: Dictionary, other_id: String) -> Dictionary:
	if not ag["relationships"].has(other_id):
		ag["relationships"][other_id] = {"affinity": 0.0, "trust": 0.0, "resentment": 0.0, "familiarity": 0.0, "standing": 0.0, "last_pos": 0, "last_neg": 0}
	return ag["relationships"][other_id]

## L3 Simple Standing 二阶范式（docs/10 §A1）：观察者据「动作+对象声誉」更新对行动者的 standing。
func _judge_actor(observer: Dictionary, actor_id: String, is_help: bool, recipient_id: String) -> void:
	if observer["id"] == actor_id:
		return
	var r := _rel(observer, actor_id)
	var d := 0.0
	if is_help:
		d = 1.0
	else:
		var recipient_good := true if recipient_id == observer["id"] else float(_rel(observer, recipient_id)["standing"]) >= 0.0
		d = -1.0 if recipient_good else 1.0   # 冒犯好人=坏；教训坏人=正当
	if d < 0.0:
		st_neg_events += 1
	_adjust_standing(observer, actor_id, d)   # 经跨机制 per-tick 守卫

## actor 已知、但 target 还不知道的 belief（用于 gossip；体现知识边界）。
func _unspread_belief(actor: Dictionary, target: Dictionary) -> String:
	for cid in actor["beliefs"]:
		var b: Dictionary = actor["beliefs"][cid]
		if bool(b.get("secret", false)):
			continue                                         # S3c：秘密走专道(confide/leak)，不经普通 gossip
		if actor["stifled"].has(cid):
			continue                                         # Maki-Thompson：已停传(变冷)的谣言不再扩散
		if String(b["subject"]) == String(target["id"]):
			continue                                         # 不当面议论本人
		if not target["beliefs"].has(cid):
			return cid
	return ""

func _log_event(type: String, actor_id: String, target_id: String, subject: String, accepted: bool, witnesses: Array, note: String = "") -> Dictionary:
	var wids: Array = []
	for w in witnesses:
		wids.append(w["id"])
	var ev := {"id": _next_event_id, "tick": tick_no, "type": type, "actor": actor_id,
		"target": target_id, "subject": subject, "accepted": accepted, "witnesses": wids, "note": note}
	_next_event_id += 1
	event_log.append(ev)
	# L4 增量滚动摘要：每事件 O(1) 折叠 → 不必末尾遍历整条 event_log 即得全程确定性见证（大规模/长跑友好）。
	var es := "%d:%s:%s:%s:%d:%s:%d" % [int(ev["id"]), type, actor_id, target_id, int(accepted), subject, tick_no]
	event_digest = ((event_digest * 1099511628211) ^ es.hash()) & 0x7FFFFFFFFFFFFFFF
	return ev

## importance 写入期派生（评审一致：别恒为常数）。
func _impt(self_ag: Dictionary, other: Dictionary, aff_delta: float, negative: bool) -> int:
	var v := 2 + int(round(abs(aff_delta)))
	var r := _rel(self_ag, other["id"])
	if float(r["familiarity"]) <= 1.0:
		v += 2                                               # 首次接触更显著
	if negative:
		v += 2
	return mini(10, v)

# ── 建筑/室内（docs/16 阶段1）：房间=独立 rooms dict 的矩形，_area_at 的孪生纯函数 ───────
## 返回 pos 所在房间 id（rooms 字典书写序=定序，首个命中；无则 ""）。rooms 是独立 dict，不与 areas 重叠 → 无插入序陷阱。
func _room_at(pos: Vector2i) -> String:
	for id in world.get("rooms", {}):
		var r: Array = world["rooms"][id].get("rect", [0, 0, 0, 0])
		if pos.x >= int(r[0]) and pos.x < int(r[0]) + int(r[2]) and pos.y >= int(r[1]) and pos.y < int(r[1]) + int(r[3]):
			return id
	return ""

## actor 与 target 是否同处一个 enclosed 房间（秘密的私密门；rooms 缺失时调用方走顶层数据门跳过）。
func _same_enclosed_room(ag: Dictionary, o: Dictionary) -> bool:
	var rid := String(ag.get("room", ""))
	if rid == "" or String(o.get("room", "")) != rid:
		return false
	return bool(world.get("rooms", {}).get(rid, {}).get("enclosed", false))

## 秘密可私下吐露/说漏的隐私判定（docs/16 隐私门·广义版）：
##   • 无 rooms 数据 → 恒 true（旧行为，同区即可）→ 逐字节不变（off 门）。
##   • 有 rooms → 同一封闭房间(墙保证私密，哪怕人多) 或 "独处"(同区且无第三者在场=没人偷听)。
## 起因：稀疏地图上"仅同封闭房间"把 confide 卡死（实测 6 就绪对→仅 1 吐露，卡点在同室共处）；
## 广义"无旁人偷听"既解卡又更真实，且墙仍有意义(闹市中也私密)。仅读 area/room 缓存 → 确定性。
func _secret_private(ag: Dictionary, o: Dictionary) -> bool:
	if (world.get("rooms", {}) as Dictionary).is_empty():
		return true
	if _same_enclosed_room(ag, o):
		return true
	var my_area := String(ag.get("area", ""))
	if my_area == "" or String(o.get("area", "")) != my_area:
		return false
	# earshot：说话者 EARSHOT 格内无第三者才算独处（闹市一角也能私语，比"整片区无人"更真实/解卡）。
	var apos: Vector2i = ag.get("pos", Vector2i.ZERO)
	for x in agents:
		if String(x["id"]) == String(ag["id"]) or String(x["id"]) == String(o["id"]):
			continue
		if not _same_plane(x, ag):
			continue                     # P3：跨平面(不同 floor)的人听不见——café-local 坐标会和 town 坐标撞，必须先按平面门
		var xp: Vector2i = x.get("pos", Vector2i.ZERO)
		if absi(apos.x - xp.x) + absi(apos.y - xp.y) <= EARSHOT:
			return false                 # 有旁人在耳边 → 会被听见 → 不算私密
	return true

func _area_at(pos: Vector2i) -> String:
	for id in world.get("areas", {}):
		var a: Dictionary = world["areas"][id]
		var r: Array = a.get("rect", [0, 0, 0, 0])
		if pos.x >= int(r[0]) and pos.x < int(r[0]) + int(r[2]) and pos.y >= int(r[1]) and pos.y < int(r[1]) + int(r[3]):
			return id
	return ""

## P3 Tier-B 平面感知 area：town/outdoor → 原镇上 area 矩形；非-town floor → 整层作一个命名空间 area
## "space:floor"。这样所有"同 area 才共处"的社交/见证/赴约判定【自动按楼层隔离】——楼上楼下互不感知、
## 咖啡馆里的人和镇上的人不会隔着墙社交。town 恒等于旧 _area_at → 全员 town 时逐字节不变。
func _area_key(space: String, floor: String, pos: Vector2i) -> String:
	if space == "town" and floor == "outdoor":
		return _area_at(pos)
	return space + ":" + floor

## L1：移动 agent 并刷新缓存的所在区（让 _nearby_agents 无需每次 _area_at）。
func _move_agent(ag: Dictionary, newpos: Vector2i) -> void:
	ag["pos"] = newpos
	ag["area"] = _area_key(String(ag.get("space", "town")), String(ag.get("floor", "outdoor")), newpos)  # P3：平面感知
	ag["room"] = _room_at(newpos)   # docs/16：与 area 同址刷新（缺 rooms→""）

## P3 Tier-B：同平面判定（space+floor）。town 居民彼此恒同平面 → 全员 town 时所有下游判定逐字节不变。
func _same_plane(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("space", "town")) == String(b.get("space", "town")) \
		and String(a.get("floor", "outdoor")) == String(b.get("floor", "outdoor"))

## 同区其他 agent（用缓存 area，去掉 _area_at 的 areas 内循环；遍历仍按 agents 固定序 → 字节一致）。
## P3：先按平面(space,floor)门，再按 area——楼上楼下/店内店外互不"在场"。town 全同平面 → 与旧版一致。
func _nearby_agents(ag: Dictionary) -> Array:
	var my_area := String(ag.get("area", ""))
	var out: Array = []
	if my_area == "":
		return out
	for o in agents:
		if o["id"] != ag["id"] and _same_plane(o, ag) and String(o.get("area", "")) == my_area:
			out.append(o)
	return out

func _best(cands: Array) -> Dictionary:
	if cands.is_empty():
		return {}
	var best: Dictionary = cands[0]
	for c in cands:
		if float(c["score"]) > float(best["score"]):
			best = c
	return best

## 内置确定性逻辑决策（logic 后端）：用 _rng_at(种子+tick*911+salt) 做平局抖动 →
## 确定可复现，且不再因严格 > 退化（俩同分候选总抢同一个）。AIBackend.decide 的 logic 档亦委托至此。
func _logic_decide(ag: Dictionary, cands: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_s := -INF
	var best_i := -1
	var who := _aid(ag)   # 决策者维 → 同 tick 不同 agent 的平局抖动不再撞同一流
	for i in cands.size():
		var c: Dictionary = cands[i]
		var s := float(c["score"]) + _rng_at(i * 7 + 1, who).randf() * 0.5
		if s > best_s:
			best_s = s
			best = c
			best_i = i
	best = best.duplicate()
	best["say"] = _canned_say(ag, best)
	if decision_sink.is_valid() and cands.size() >= 2:   # Phase-0 数据集钩子（off 默认；只读、不抽 RNG、不进 digest）
		decision_sink.call(ag, cands, best_i)
	return best

func _canned_say(ag: Dictionary, intent: Dictionary) -> String:
	var action := str(intent.get("action", ""))
	# 冻结·70B 语音库优先：取该【人设】该【动作】的台词库，按 tick/agent 确定性挑一条 → LLM 质感、零推理、逐字节可回放。
	# 缺 voicebank.json（voicebank={}）或该键无词 → 回落下方通用罐头（逐字节不变，off 门）。
	if not voicebank.is_empty():
		var bank = (voicebank.get(String(ag.get("persona_key", "")), {}) as Dictionary).get(action, [])
		if bank is Array and not (bank as Array).is_empty():
			return String(bank[_rng_at(6007, _aid(ag)).randi() % bank.size()])   # 6007=voice 专用盐；独立 RNG 流，不扰其他抖动
	match action:
		"吃饭": return "有点饿了，去吃点东西。"
		"睡觉": return "困了，回去歇会儿。"
		"社交", "闲聊": return "去找人唠两句。"
		"玩耍", "晒太阳": return "忙里偷个闲。"
		"洗澡": return "该去冲个澡了。"
		"做活": return "去工坊忙活忙活。"
		"greet": return "嗨，最近怎么样？"
		"give": return "这个送你，小意思。"
		"gossip": return "跟你说个事儿……"
		"invite": return "回头一起聚聚？"
		"confront": return "咱们得谈谈。"
		"apologize": return "对不起，是我不对。"
		_: return ""

func _context(ag: Dictionary) -> Dictionary:
	return {"day": day, "tod": time_of_day(), "tick": tick_no, "pos": ag["pos"]}

func _step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var p := from
	if p.x != to.x:
		p.x += signi(to.x - p.x)
	elif p.y != to.y:
		p.y += signi(to.y - p.y)
	return p

## ── 导航（town-world P2 增量1）──────────────────────────────────────────────
## 静态 walkability：家具占用格阻挡（fest_/civic_ 动态对象 v1 不入 nav → 每局同一张确定网）。
func _build_nav() -> void:
	_blocked = {}
	_nav_grids = {}
	var W := int(world.get("width", GRID.x))
	var H := int(world.get("height", GRID.y))
	for b in world.get("blockers", []):            # 64×48 显式阻挡层(墙/水/树)，缺则空
		_blocked[int(b[1]) * W + int(b[0])] = true
	for oid in world.get("objects", {}):
		if String(oid).begins_with("fest_") or String(oid).begins_with("civic_"):
			continue
		var o: Dictionary = world["objects"][oid]
		if String(o.get("space", "town")) != "town":   # P3：非-town 家具进各自平面网，绝不进 town _blocked（坐标会撞）
			continue
		var p: Vector2i = o.get("pos", Vector2i.ZERO)
		_blocked[p.y * W + p.x] = true
	_nav_grids["town"] = {"outdoor": {"w": W, "h": H, "blocked": _blocked}}   # town 网复用 _blocked 引用（逐字节同旧）
	_build_interior_grids()                        # 各非-town Space/Floor 独立网（P3 Tier-B）

## 每个非-town (space,floor) 建导航网：spaces.json bounds 外墙边框(门口那格放行) + interiors 家具挡格
## (楼梯/装饰 slot 可踩、portal 格必放行)。纯 f(数据)，无 RNG/Time。缺 spaces/interiors → 无非-town 网。
func _build_interior_grids() -> void:
	const WALKABLE_SLOTS := ["stairs", "rug", "window"]
	for space in _spaces:
		if String(space) == "town" or not (_spaces[space] is Dictionary):
			continue
		var b: Array = _as_arr((_spaces[space] as Dictionary).get("bounds", []))
		if b.size() < 4:
			continue
		var w := int(b[2]); var h := int(b[3])
		for floor in _as_arr((_spaces[space] as Dictionary).get("floors", [])):
			var fl := String(floor)
			var portal_cells := {}                 # portal 端点落在本层 → 必可走(门缺口+楼梯)
			for p in _portals:
				for side in ["from", "to"]:
					var e: Dictionary = p.get(side, {})
					if String(e.get("space", "")) == String(space) and String(e.get("floor", "")) == fl:
						var ep: Array = _as_arr(e.get("pos", [0, 0]))
						if ep.size() >= 2:
							portal_cells[int(ep[1]) * w + int(ep[0])] = true
			var blocked := {}
			for x in range(w):                     # 外墙边框
				for y in range(h):
					if x == 0 or x == w - 1 or y == 0 or y == h - 1:
						var idx := y * w + x
						if not portal_cells.has(idx):
							blocked[idx] = true
			var content: Dictionary = (_interiors_data.get(space, {}) as Dictionary).get(fl, {}) if _interiors_data.get(space, {}) is Dictionary else {}
			for fu in _as_arr(content.get("furniture", [])):
				if not (fu is Dictionary) or String((fu as Dictionary).get("slot", "")) in WALKABLE_SLOTS:
					continue
				var fp: Array = _as_arr((fu as Dictionary).get("pos", [0, 0]))
				if fp.size() < 2:
					continue
				var fi := int(fp[1]) * w + int(fp[0])
				if not portal_cells.has(fi):
					blocked[fi] = true
			if not _nav_grids.has(space):
				_nav_grids[space] = {}
			_nav_grids[space][fl] = {"w": w, "h": h, "blocked": blocked}

## agent 当前平面的导航网；缺 → 回落 town/全图（兼容期）。
func _grid_for(space: String, floor: String) -> Dictionary:
	var sg = _nav_grids.get(space, {})
	if sg is Dictionary and (sg as Dictionary).has(floor):
		return sg[floor]
	return {"w": int(world.get("width", GRID.x)), "h": int(world.get("height", GRID.y)), "blocked": _blocked}

# ── P3 Tier-B：Portal 跨平面 ─────────────────────────────────────────────────
func _v2i(a) -> Vector2i:
	var arr := _as_arr(a)
	return Vector2i(int(arr[0]), int(arr[1])) if arr.size() >= 2 else Vector2i.ZERO

## 从 (space,floor) 出发能走的 portal（含双向反向边）：[{from_pos(本层格),to_space,to_floor,to_pos,cost}]。spaces.json 顺序=确定序。
## access="owner" 的 portal（如咖啡馆私人楼梯）只有【该室内的主人】(home_space==该 Space)能走 → 顾客进不了阿丽的 2F 私宅。
## ag 缺省(空)=不设访问门(渲染/校验用)；带 ag 走访问门(导航/决策用)。
func _portals_from(space: String, floor: String, ag: Dictionary = {}) -> Array:
	var out: Array = []
	for p in _portals:
		var fr: Dictionary = p.get("from", {})
		var to: Dictionary = p.get("to", {})
		if String(p.get("access", "public")) == "owner" and not ag.is_empty():
			var owned := String(fr.get("space", "")) if String(fr.get("space", "")) != "town" else String(to.get("space", ""))
			if String(ag.get("home_space", "town")) != owned:
				continue                    # 非主人 → 私有 portal(楼梯)走不了
		if String(fr.get("space", "")) == space and String(fr.get("floor", "")) == floor:
			out.append({"from_pos": _v2i(fr.get("pos")), "to_space": String(to.get("space", "")), "to_floor": String(to.get("floor", "")), "to_pos": _v2i(to.get("pos")), "cost": int(p.get("traversal_cost", 1))})
		elif bool(p.get("bidirectional", false)) and String(to.get("space", "")) == space and String(to.get("floor", "")) == floor:
			out.append({"from_pos": _v2i(to.get("pos")), "to_space": String(fr.get("space", "")), "to_floor": String(fr.get("floor", "")), "to_pos": _v2i(fr.get("pos")), "cost": int(p.get("traversal_cost", 1))})
	return out

## 从 (fromS,fromF) 到 (toS,toF) 的【下一跳 portal】（BFS，FIFO+portal 文件序 → 确定）。同层→{}。不可达→{}。
## 带 ag → BFS 只走该 agent 有权限的 portal（顾客路不到阿丽的 owner-only 2F → 那床对顾客"不可达"→ 不会去睡）。
func _route_next_hop(fromS: String, fromF: String, toS: String, toF: String, ag: Dictionary = {}) -> Dictionary:
	var start := fromS + "/" + fromF
	var goal := toS + "/" + toF
	if start == goal:
		return {}
	var q: Array = [start]
	var parent := {start: ""}
	var via := {}                                   # node -> 到达它所走的 hop
	while not q.is_empty():
		var node: String = q.pop_front()
		if node == goal:
			break
		var pr := node.split("/")
		for hop in _portals_from(pr[0], pr[1], ag):
			var nb := String(hop["to_space"]) + "/" + String(hop["to_floor"])
			if not parent.has(nb):
				parent[nb] = node
				via[nb] = hop
				q.append(nb)
	if not parent.has(goal):
		return {}
	var cur := goal                                 # 回溯到"父==start"的那个节点 → 它的 hop 即第一跳
	while String(parent.get(cur, "")) != start and String(parent.get(cur, "")) != "":
		cur = String(parent[cur])
	return via.get(cur, {})

## 跨 portal：原子改 (space,floor,pos) 到对面，刷新平面感知缓存，清该 agent 路径缓存。整数格、无 RNG。
func _traverse_portal(ag: Dictionary, hop: Dictionary) -> void:
	ag["space"] = String(hop["to_space"])
	ag["floor"] = String(hop["to_floor"])
	_move_agent(ag, hop["to_pos"])                  # 更新 pos + _area_key 平面感知 area/room
	_path_cache.erase(String(ag["id"]))

func _cell_walkable(grid: Dictionary, c: Vector2i) -> bool:
	var W := int(grid.get("w", 0)); var H := int(grid.get("h", 0))
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return false
	return not (grid.get("blocked", {}) as Dictionary).has(c.y * W + c.x)

func _manh(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

## 确定性 A*：起点/终点恒可入(终点=家具交互格)；中间须 walkable。tie-break 全序 (f,h,idx) → 同 seed 逐字节同路径。
## 返回含端点的完整格路径；不可达返回 []。二叉最小堆 open set + 懒删除 → O(E log V)/次(64×48 也够快)。
## 堆项 [f,h,idx,cell]，全序 (f,h,idx) → 与旧 O(open²) 版逐格同路径，纯提速。
func _heap_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]: return a[0] < b[0]
	if a[1] != b[1]: return a[1] < b[1]
	return a[2] < b[2]
func _heap_push(heap: Array, e: Array) -> void:
	heap.append(e); var i := heap.size() - 1
	while i > 0:
		var par := (i - 1) >> 1
		if _heap_less(heap[i], heap[par]):
			var t: Array = heap[i]; heap[i] = heap[par]; heap[par] = t; i = par
		else: break
func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]; var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last; var i := 0; var n := heap.size()
		while true:
			var l := 2 * i + 1; var r := 2 * i + 2; var s := i
			if l < n and _heap_less(heap[l], heap[s]): s = l
			if r < n and _heap_less(heap[r], heap[s]): s = r
			if s == i: break
			var t: Array = heap[i]; heap[i] = heap[s]; heap[s] = t; i = s
	return top
func _astar_path(grid: Dictionary, start: Vector2i, goal: Vector2i) -> Array:
	var W := int(grid.get("w", 0)); var H := int(grid.get("h", 0))
	var gi := goal.y * W + goal.x
	var si := start.y * W + start.x
	var g0 := _manh(start, goal)
	var gscore := {si: 0}
	var came := {}          # idx -> 前驱 cell
	var closed := {}
	var heap: Array = []
	_heap_push(heap, [g0, g0, si, start])
	while not heap.is_empty():
		var e: Array = _heap_pop(heap)
		var ci := int(e[2])
		if closed.has(ci): continue         # 懒删除：过期项跳过
		closed[ci] = true
		var cur: Vector2i = e[3]
		if ci == gi:
			var path: Array = [cur]; var k := ci
			while came.has(k):
				var pc: Vector2i = came[k]; path.push_front(pc); k = pc.y * W + pc.x
			return path
		var cg := int(gscore[ci])
		for d in NAV_DIRS:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= W or nb.y >= H:
				continue
			var ni := nb.y * W + nb.x
			if closed.has(ni):
				continue
			if ni != gi and not _cell_walkable(grid, nb):    # 终点豁免
				continue
			var ng := cg + 1
			if not gscore.has(ni) or ng < int(gscore[ni]):
				gscore[ni] = ng; came[ni] = cur
				var hh := _manh(nb, goal)
				_heap_push(heap, [ng + hh, hh, ni, nb])
	return []

## 朝 to 走一格：绕开阻挡的确定性 A* 次步；不可达则 Manhattan 兜底(不冻结)。
func _nav_step(ag: Dictionary, to: Vector2i) -> Vector2i:
	var from: Vector2i = ag["pos"]
	if not NAV_PATHFIND or from == to:
		return _step_toward(from, to)
	var grid := _grid_for(String(ag.get("space", "town")), String(ag.get("floor", "outdoor")))   # P3：agent 当前平面网
	var aid := String(ag["id"])
	# 缓存复用：算一次跟着走(大图 O(open²) A* 不能每步重算)。有效条件=同目标+当前格正好在缓存路径 i 处+下一格仍可走。
	var c: Dictionary = _path_cache.get(aid, {})
	if not c.is_empty() and c["goal"] == to:
		var pth: Array = c["path"]; var i := int(c["i"])
		if i < pth.size() - 1 and pth[i] == from:
			var nxt: Vector2i = pth[i + 1]
			if nxt == to or _cell_walkable(grid, nxt):
				c["i"] = i + 1
				return nxt
	# 重算并缓存：返回 path[1]、i 记为 1（=agent 下一 tick 所在格，令后续走缓存命中）
	var path := _astar_path(grid, from, to)
	if path.size() >= 2:
		_path_cache[aid] = {"goal": to, "path": path, "i": 1}
		return path[1]
	_path_cache.erase(aid)
	return _step_toward(from, to)

func _name(ag: Dictionary) -> String:
	if ag.is_empty():
		return "?"                     # 空 dict（如社交对象已离场/id 查空）→ 安全占位，不崩
	return str(ag.get("persona", {}).get("name", ag.get("id", "?")))

func _area_label(pos: Vector2i) -> String:
	var a := _area_at(pos)
	return str(world.get("areas", {}).get(a, {}).get("label", "镇上")) if a != "" else "镇上"

func _verb(action: String) -> String:
	match action:
		"greet": return "聊天"
		"give": return "送了点东西"
		"gossip": return "说了会儿悄悄话"
		"gossip_rep": return "说了说别人的事"
		"discuss": return "聊起了看法"
		"invite": return "约了见面"
		"confront": return "当面理论"
		"apologize": return "道歉"
		"confide": return "吐露了心事"
		"leak": return "说漏了秘密"
		"endorse": return "统一了口径"
		"rally_oust": return "施压"
		"aid": return "雪中送炭"
		_: return action

# ── S3 辅助函数（逻辑镜像 tools/sim_social_port.mjs）────────────────────────
## 跨机制 standing 守卫：单 tick 内每 (观察者→对象) 总移动量封顶 ±STANDING_DELTA_CAP，再 clamp ±STANDING_CAP。
func _adjust_standing(observer: Dictionary, target_id: String, delta: float) -> void:
	var r := _rel(observer, target_id)
	var k := String(observer["id"]) + ">" + target_id
	var e: Dictionary = _st_delta.get(k, {})
	if e.is_empty() or int(e.get("tick", -1)) != tick_no:
		e = {"tick": tick_no, "acc": 0.0}
		_st_delta[k] = e
	var d := delta
	if float(e["acc"]) + d > STANDING_DELTA_CAP:
		d = STANDING_DELTA_CAP - float(e["acc"])
	if float(e["acc"]) + d < -STANDING_DELTA_CAP:
		d = -STANDING_DELTA_CAP - float(e["acc"])
	e["acc"] = float(e["acc"]) + d
	r["standing"] = clampf(float(r["standing"]) + d, -STANDING_CAP, STANDING_CAP)

## S3a 派系：对齐判据 = ≥FACTION_MIN_AGREE 个话题"同号(非骑墙)且 |Δ|<FACTION_BAND"
func _aligned(a: Dictionary, b: Dictionary) -> bool:
	var agree := 0
	for t in TOPICS:
		var xa := float(a["attitudes"][t])
		var xb := float(b["attitudes"][t])
		if absf(xa) < FACTION_SALIENT or absf(xb) < FACTION_SALIENT:
			continue
		if signf(xa) == signf(xb) and absf(xa - xb) < FACTION_BAND:
			agree += 1
	return agree >= FACTION_MIN_AGREE

## 每夜从 attitudes 单遍贪心派生派系（sorted id 固定序，确定性、非显式 join）。
## R1(docs/14 §3)：激进 LOD 下只聚类 near 集(O(cap²))；far→factionless(attitudes 冻结、行为上不用派系、near 不引用其派系)。全量配置逐字节不变。
func _recompute_factions() -> void:
	factions.clear()
	var ids: Array = _nightly_active_ids()   # 全量(全/保守) 或 near 集(激进)，均已定序
	var medoids: Array = []
	var assign := {}
	for id in ids:
		var placed := ""
		for m in medoids:
			if _aligned(_agent_by_id[id], _agent_by_id[m]):
				placed = m; break
		if placed != "":
			assign[id] = placed; (factions[placed] as Array).append(id)
		else:
			medoids.append(id); assign[id] = id; factions[id] = [id]
	for a in agents:
		var aid := String(a["id"])
		if assign.has(aid):
			var members: Array = factions[assign[aid]]
			if members.size() >= 2:
				a["faction"] = assign[aid]; a["faction_size"] = members.size()
			else:
				a["faction"] = ""; a["faction_size"] = 1
		else:
			a["faction"] = ""; a["faction_size"] = 1   # far：不参与聚类 → factionless
	for m in factions.keys():
		if (factions[m] as Array).size() < 2:
			factions.erase(m)

func _faction_term(target: Dictionary, actor: Dictionary) -> float:
	var tf := String(target["faction"])
	var af := String(actor["faction"])
	if tf != "" and tf == af:
		return FACTION_ACCEPT_K
	if tf != "" and af != "" and tf != af:
		return -FACTION_ACCEPT_K
	return 0.0

## S3a rally_oust：同派系协同对外群目标施压；只对"在该支持者眼中确有恶感/冲突"的 o 降名声（L3 不冤枉好人）
func _resolve_rally_oust(ag: Dictionary, o: Dictionary, witnesses: Array) -> void:
	var fac := String(ag["faction"])
	if fac == "" or not factions.has(fac):
		return
	var backers := 0
	for mid in (factions[fac] as Array):
		if String(mid) == String(o["id"]):
			continue
		var m: Dictionary = _agent_by_id[mid]
		var sees := float(_rel(m, o["id"])["standing"]) < 0.0 or not _find_conflict(String(mid), String(o["id"]), ["simmering", "escalated", "confronted", "lingering"]).is_empty()
		if not sees:
			continue
		backers += 1
		_judge_actor(m, o["id"], false, ag["id"])
		oust_neg_events += 1
	oust_events += 1
	var ev := _log_event("rally_oust", ag["id"], o["id"], "", backers > 0, witnesses, "backers:%d" % backers)
	_rel(ag, o["id"])["last_neg"] = ev["id"]
	ag["memory"].add("带着自己人去找%s说理" % _name(o), 6, tick_no, [o["id"], "faction", "oust"])
	o["memory"].add("被一伙人施压", 6, tick_no, [ag["id"], "faction", "oust"])
	emit_signal("social_event", ev)

## S3c 秘密通道：owner==actor 的未传秘密(可吐露) / owner!=actor 且 confidedBy 非空的未传秘密(可外泄)
func _confidable_secret(actor: Dictionary, target: Dictionary) -> String:
	for cid in actor["beliefs"]:
		var b: Dictionary = actor["beliefs"][cid]
		if bool(b.get("secret", false)) and String(b.get("owner", "")) == String(actor["id"]) and String(b["subject"]) != String(target["id"]) and not target["beliefs"].has(cid):
			return cid
	return ""
func _leakable_secret(actor: Dictionary, target: Dictionary) -> String:
	for cid in actor["beliefs"]:
		var b: Dictionary = actor["beliefs"][cid]
		if bool(b.get("secret", false)) and String(b.get("owner", "")) != String(actor["id"]) and (b.get("confidedBy", {}) as Dictionary).size() > 0 and String(b["subject"]) != String(target["id"]) and not target["beliefs"].has(cid):
			return cid
	return ""

## S3b 互助盟约
func _pact_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)
func _active_pact_count(ag: Dictionary) -> int:
	var n := 0
	for k in ag["pacts"]:
		if String(ag["pacts"][k]["status"]) == "active":
			n += 1
	return n
func _accrue_complement(ag: Dictionary, o: Dictionary) -> void:
	var comp := false
	for nid in ag["needs"]:
		var an := float(ag["needs"][nid])
		var on := float(o["needs"].get(nid, 100.0))
		if (an < COMPLEMENT_LOW and on >= COMPLEMENT_HIGH) or (on < COMPLEMENT_LOW and an >= COMPLEMENT_HIGH):
			comp = true
	if comp:
		ag["complementSeen"][o["id"]] = int(ag["complementSeen"].get(o["id"], 0)) + 1
		o["complementSeen"][ag["id"]] = int(o["complementSeen"].get(ag["id"], 0)) + 1
func _record_aid(giver: Dictionary, receiver: Dictionary) -> void:
	if giver["pacts"].has(receiver["id"]):
		giver["pacts"][receiver["id"]]["given"] = int(giver["pacts"][receiver["id"]]["given"]) + 1
		giver["pacts"][receiver["id"]]["lastAidTick"] = tick_no
	if receiver["pacts"].has(giver["id"]):
		receiver["pacts"][giver["id"]]["received"] = int(receiver["pacts"][giver["id"]]["received"]) + 1
func _dissolve_freeriders() -> void:
	for p in pacts_index:
		if String(p["status"]) != "active":
			continue
		var A: Dictionary = _agent_by_id.get(p["a"], {})
		var B: Dictionary = _agent_by_id.get(p["b"], {})
		if A.is_empty() or B.is_empty():
			continue
		var pa = A["pacts"].get(p["b"])
		var pb = B["pacts"].get(p["a"])
		if pa == null or pb == null:
			continue
		var gap_a := int(pa["given"]) - int(pa["received"])
		var gap_b := int(pb["given"]) - int(pb["received"])
		var gap := maxi(gap_a, gap_b)
		var total := int(pa["given"]) + int(pa["received"])
		if gap >= FREERIDER_GAP and total >= PACT_MIN_EXCHANGES:
			p["defect_streak"] = int(p.get("defect_streak", 0)) + 1
		else:
			p["defect_streak"] = 0
		if int(p["defect_streak"]) >= FREERIDER_STREAK:
			var victim := A if gap_a >= gap_b else B
			var freerider := B if gap_a >= gap_b else A
			_dissolve_pact(p, victim, freerider, gap)
func _dissolve_pact(p: Dictionary, victim: Dictionary, freerider: Dictionary, gap: int) -> void:
	p["status"] = "broken"; p["brokenTick"] = tick_no; p["reason"] = "freerider:" + String(freerider["id"]); p["breakGap"] = gap
	victim["pacts"].erase(freerider["id"]); freerider["pacts"].erase(victim["id"])
	last_broken_with[p["key"]] = tick_no
	var rv := _rel(victim, freerider["id"])
	rv["trust"] = clampf(float(rv["trust"]) - PACT_BREAK_TRUST, -100.0, 100.0)
	rv["affinity"] = clampf(float(rv["affinity"]) - 8.0, -100.0, 100.0)
	_judge_actor(victim, freerider["id"], false, victim["id"])
	var ev := _log_event("pact", victim["id"], freerider["id"], "", false, [], "dissolved:freerider")
	rv["last_neg"] = ev["id"]
	_bump_resentment(victim, freerider["id"], PACT_BREAK_RESENT)
	freerider_dissolves += 1
	victim["memory"].add("和%s的盟约散了，被白嫖了" % _name(freerider), 7, tick_no, [freerider["id"], "pact", "dissolve"])
	freerider["memory"].add("背弃了和%s的盟约" % _name(victim), 6, tick_no, [victim["id"], "pact", "dissolve"])
## 夜间机制的活跃 id 集（docs/14 §3 R1）：激进 LOD 下只含 near 集 → 把夜间 O(N²)(结盟/派系) 降到 O(cap²)。
## 语义：far=背景群演，关系冻结(不社交→trust/fam 不涨)，本就到不了结盟门 → 只跑 near 与全量等价、但便宜。确定(near 集每 tick 定序算)。
func _nightly_active_ids() -> Array:
	var out: Array = []
	if lod_aggregate and lod_near_cap > 0 and not _near_set.is_empty():
		for k in _near_set:
			if String(k) != "player":
				out.append(String(k))
	else:
		for a in agents:
			if not a.get("is_player", false):
				out.append(String(a["id"]))
	out.sort()   # 确定序（不依赖 _near_set 字典插入序）
	# 玩家豁免（对抗审查#9）：冻结需求会造"互补"假证据 → 结成永不解体的死盟约占 PACT_CAP；attitudes 也不经 discuss 演化
	# → 派系归属徒有其表。玩家的盟约/派系是后续设计（真互助/真观点玩法），M1 先不入夜间聚类。
	return out

func _form_pacts_greedy() -> void:
	var ids: Array = _nightly_active_ids()
	for id in ids:
		var ag: Dictionary = _agent_by_id[id]
		if _active_pact_count(ag) >= PACT_CAP:
			continue
		var best_o: Dictionary = {}
		var best_score := -INF
		for oid in ids:
			if oid == id:
				continue
			var o: Dictionary = _agent_by_id[oid]
			if ag["pacts"].has(oid) and String(ag["pacts"][oid]["status"]) == "active":
				continue
			if _active_pact_count(o) >= PACT_CAP:
				continue
			var key := _pact_key(id, oid)
			if last_broken_with.has(key) and tick_no - int(last_broken_with[key]) < PACT_RECONCILE_COOLDOWN * TICKS_PER_DAY:
				continue
			if float(_rel(ag, oid)["trust"]) < PACT_TRUST_TH or float(_rel(o, id)["trust"]) < PACT_TRUST_TH:
				continue
			if float(_rel(ag, oid)["familiarity"]) < PACT_FAM_TH:
				continue
			if int(ag["complementSeen"].get(oid, 0)) < PACT_COMPLEMENT_TH:
				continue
			var score := float(_rel(ag, oid)["affinity"]) + float(_rel(o, id)["affinity"]) + float(_rel(ag, oid)["trust"]) + float(_rel(o, id)["trust"]) + float(int(ag["complementSeen"].get(oid, 0))) * 2.0 + _hash01(key) * 0.5
			if score > best_score:
				best_score = score; best_o = o
		if not best_o.is_empty():
			_form_pact(ag, best_o)
func _form_pact(ag: Dictionary, o: Dictionary) -> void:
	var key := _pact_key(String(ag["id"]), String(o["id"]))
	ag["pacts"][o["id"]] = {"partner": o["id"], "key": key, "formedTick": tick_no, "status": "active", "given": 0, "received": 0, "lastAidTick": 0}
	o["pacts"][ag["id"]] = {"partner": ag["id"], "key": key, "formedTick": tick_no, "status": "active", "given": 0, "received": 0, "lastAidTick": 0}
	pacts_index.append({"id": _next_pact_id, "key": key, "a": ag["id"], "b": o["id"], "formed": tick_no, "status": "active", "defect_streak": 0,
		"formTrustA": float(_rel(ag, o["id"])["trust"]), "formTrustB": float(_rel(o, ag["id"])["trust"]), "formFam": float(_rel(ag, o["id"])["familiarity"]), "formComplement": int(ag["complementSeen"].get(o["id"], 0))})
	_next_pact_id += 1
	_rel(ag, o["id"])["trust"] = clampf(float(_rel(ag, o["id"])["trust"]) + 2.0, -100.0, 100.0)
	_rel(o, ag["id"])["trust"] = clampf(float(_rel(o, ag["id"])["trust"]) + 2.0, -100.0, 100.0)
	_log_event("pact", ag["id"], o["id"], "", true, [], "formed")
	ag["memory"].add("和%s结成了互助盟约" % _name(o), 6, tick_no, [o["id"], "pact", "form"])
	o["memory"].add("和%s结成了互助盟约" % _name(ag), 6, tick_no, [ag["id"], "pact", "form"])

# ── S4：模型决策记录 / 确定性回放（LLM 输出当外部输入，引擎主体保持纯确定）──────
## P2-1 候选稳定身份：**完整字段**（旧版只折 action/partner/subject → 多张床这类"同 action 不同 target"
## 无法区分）。与 AIBackend._cand_key 同义（那边守异步回包，这边守回放）。
func _cand_key(c: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(c.get("kind", "object")), str(c.get("action", "")), str(c.get("partner", "")),
		str(c.get("target", "")), str(c.get("subject", "")), str(c.get("need", "")),
		str(c.get("amount", "")), str(c.get("dur_total", ""))]

## 候选集稳定哈希（回放 drift 检测）。P2-1：**不排序**——顺序也是身份的一部分；旧版排序后重排也算"没变"，
## 而 _resolve_replay 却按下标取 → 静默取错候选。
func _cand_hash(cands: Array) -> int:
	var parts := PackedStringArray()
	for c in cands:
		parts.append(_cand_key(c))
	return "|".join(parts).hash()

## 记录一条落地的模型决策：pick 下标 + cand_hash（回放靠下标精确复现，hash 检 drift；不记 prompt/思维链）。
func _record_decision(ag: Dictionary, cands: Array, intent: Dictionary) -> void:
	var key := _cand_key(intent)              # P2-1：记 stable key（回放按 key 找，不靠脆弱下标）
	var idx := -1
	for i in cands.size():
		if _cand_key(cands[i]) == key:
			idx = i
			break
	decision_trace.append({
		"tick": tick_no, "agent": String(ag["id"]), "pick": idx, "key": key,
		"action": str(intent.get("action", "")), "say": str(intent.get("say", "")), "cand_hash": _cand_hash(cands)})

## 回放：**按记录的 stable key 在当前候选里找**（P2-1：不再按脆弱下标——候选重排/同 action 换 target 会静默取错）。
## 找到→精确复现；找不到（引擎逻辑改了→候选集变）→ drift 计数 + 引擎兜底。无 key 的旧 trace 走下标+hash 兼容路。
func _resolve_replay(ag: Dictionary, cands: Array, rec: Dictionary) -> Dictionary:
	var key := str(rec.get("key", ""))
	if key != "":
		for c in cands:
			if _cand_key(c) == key:
				var it: Dictionary = (c as Dictionary).duplicate()
				it["say"] = str(rec.get("say", ""))
				return it
	else:                                     # 兼容：旧 trace 无 key → 下标 + hash 门
		var pick := int(rec.get("pick", -1))
		if int(rec.get("cand_hash", 0)) == _cand_hash(cands) and pick >= 0 and pick < cands.size():
			var it2: Dictionary = (cands[pick] as Dictionary).duplicate()
			it2["say"] = str(rec.get("say", ""))
			return it2
	replay_drift += 1
	return _logic_decide(ag, cands)

## 从 decision_trace 构建回放表（"tick:agent" → 记录）。供回放前注入 replay_trace。
func build_replay_trace(trace: Array) -> Dictionary:
	var m := {}
	for rec in trace:
		m["%d:%s" % [int(rec["tick"]), String(rec["agent"])]] = rec
	return m
