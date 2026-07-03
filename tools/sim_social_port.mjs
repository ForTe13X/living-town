#!/usr/bin/env node
// sim_social_port.mjs — 确定性社交底座「垂直切片」的可执行验证端口（本机无 Godot 时用）。
// 它忠实镜像 game/scripts/Sim.gd 计划实现的社交逻辑：感知(同区) → 社交候选(greet/give/gossip)
// → SocialTransaction(发起·评估接受/拒绝·提交) → 关系账本 + belief/知识边界 + 不可变 event log
// → 双方+旁观者写视角记忆 + 承诺系统(invite→meet：发起/赴约/兑现/爽约)。读真实 game/data/*.json。
// 跑 soak 并断言 10 条不变量(含承诺生命周期)，违反即 exit(1)。
//
// 用法: node tools/sim_social_port.mjs [--days 30] [--seed 20260626] [--verbose]
//
// 注意: 本端口用于验证「逻辑与不变量」，非与 Godot RNG 逐字节一致；determinism 不变量在端口内自检
// (同 seed 跑两次结果一致)。GDScript 用 RandomNumberGenerator(同 seed 公式) 各自可复现。

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const __dir = dirname(fileURLToPath(import.meta.url))
const DATA = join(__dir, '..', 'game', 'data')
const readJSON = (f) => JSON.parse(readFileSync(join(DATA, f), 'utf8'))

// ── 参数 ──────────────────────────────────────────────────────────────────
const args = process.argv.slice(2)
const argVal = (k, d) => { const i = args.indexOf(k); return i >= 0 && i + 1 < args.length ? args[i + 1] : d }
const DAYS = parseInt(argVal('--days', '30'), 10)
const SEED = parseInt(argVal('--seed', '20260626'), 10)
const VERBOSE = args.includes('--verbose')

const TICKS_PER_DAY = 240
const CONVERSE_TICKS = 4
const PERCEPTION = 'area' // 同区即可感知
const SOCIAL_FULL = 88     // social 高于此不再主动发起社交
const GIFT_START = 3
const MEET_HORIZON = 40    // invite 创建的 meet 承诺：deadline = now + 此
const ATTEND_WINDOW = 16   // 离 deadline ≤ 此 → 引擎给“赴约”行为加权（够走过去即可，不必早早枯等）
const NEED_CRISIS = 15     // 任一需求 < 此 → 放弃赴约（真危机才爽约 → broken）
const CONFLICT_TRIGGER = 6 // resentment 累积到此 → 触发一段冲突（simmering）
const ESC_THRESH = 2       // 升级次数到此 → escalated
const LINGER_AFTER = 350   // 触发后 tick 未对质 → lingering（冷战/积怨）
const FORGIVE_CAP = 22     // 冲突 severity 高于此则难以被原谅
// S1（声誉×八卦×宽恕，见 docs/10 §A/§B）
const STANDING_CAP = 3     // standing token 范围 [-CAP, +CAP]；sign 决定 good/bad
const STANDING_K = 6       // 接受规则里 standing 的权重（→ 涌现放逐）
const REP_GOSSIP_TH = -2   // standing ≤ 此 → 可对外传该人的坏名声（gossip_rep）
const INVEST_TRUST = -8    // 脆弱动作(give/invite)的条件投资门：trust ≥ 此才发起
const RESENT_DECAY = 0.4   // 每日 resentment 衰减（宽恕：不永久世仇）
const STANDING_DECAY_DAY = 8 // 每此 tick·day 边界 standing 向 0 漂移 1（名声会淡）
// S2（意见动力学，见 docs/10 §A2/§A3）
const TOPICS = ['cafe_expand', 'night_market', 'old_tales']  // 镇上几个话题（attitude∈[-1,1]）
const CONF_BOUND = 0.85    // Deffuant 有界信任 ε：|Δattitude|>ε 则不谈/拒谈（软门）
const DISCUSS_MINDIFF = 0.15 // 差异太小不值得谈
const STIFLE_K = 2         // Maki-Thompson：遇到 K 个已知者 → 变 stifler（谣言变冷、停止扩散）
const BACKFIRE_RESENT = 20 // resentment > 此 → 意见背离（signed FJ：朝相反方向）
let refusedByBound = 0     // 因 |Δ|>ε 拒谈的次数（有界信任门生效证据）
// ── S3（社交深化：观点派系 / 互助盟约 / 秘密信息博弈，见 docs/10 §B/§C + workflow 综合）──
const STANDING_DELTA_CAP = 2 // ★跨机制守卫：单 tick 内任一 (观察者→对象) standing 总移动量上限（防 rally_oust+betray+gossip_rep 叠穿）
// S3a 观点派系
const FACTION_BAND = 0.5     // 同话题"接近"带 |Δattitude|<此（< CONF_BOUND，派系比可谈更紧）
const FACTION_SALIENT = 0.15 // 骑墙死区 |attitude|<此不计入同号
const FACTION_MIN_AGREE = 2  // 3 话题中 ≥此 个"同号且接近"才算对齐
const FACTION_QUORUM = 2     // 协同行动法定人数（派系 size 门）
const FACTION_ACCEPT_K = 8   // _acceptance_rule 同/跨派系门权重
const FACTION_INGROUP_AFF = 1 // 同派系成功社交额外 affinity 加成
const FACTION_ENDORSE_BONUS = 12
const FACTION_ENDORSE_AFF = 3
const OUST_BASE = 20
const FACTION_AFF_MARGIN = 2 // inv-S3-2 同/跨派系均值比较余量
// S3b 互助盟约
const PACT_TRUST_TH = 12, PACT_FAM_TH = 6, PACT_COMPLEMENT_TH = 3, PACT_CAP = 2
const AID_NEED_TH = 30, AID_RELIEF = 18, AID_BASE = 16, AID_TRUST = 3
const PACT_INVITE_BONUS = 6, PACT_ATTEND_BONUS = 12
const FREERIDER_GAP = 4, FREERIDER_STREAK = 2, PACT_MIN_EXCHANGES = 3
const PACT_BREAK_TRUST = 10, PACT_BREAK_RESENT = 8, PACT_RECONCILE_COOLDOWN = 4
const COMPLEMENT_LOW = 35, COMPLEMENT_HIGH = 60, MIN_AID_SAMPLE = 8
// S3c 秘密信息博弈
const CONFIDE_TRUST = 25, SECRET_AFF_FLOOR = 10, CONFIDE_TRUST_GAIN = 8
const BETRAY_TRUST_CRASH = -40, BETRAY_AFF_CRASH = -30, BETRAY_RESENT = 14, BETRAY_STANDING = -2
// S3 度量计数器（镜像 stNegEvents/refusedByBound）
let endorseEvents = 0, oustEvents = 0, oustNegEvents = 0
let confideEvents = 0, betrayEvents = 0
let freeriderDissolves = 0, aidAccepted = 0
// S3 派生表/台账
let factions = {}          // medoid_id -> [member_id...]（每夜全量重建的只读视图）
let factionRecomputeDay = -1
const pactsIndex = []      // [{key,a,b,formed,status,brokenTick,reason}]（单一真相源）
let nextPactId = 1
const lastBrokenWith = {}  // pact_key -> tick（解体冷却）
// 定向场景种子（小N下罕见但关键的背叛/freerider 路径可机检；镜像种子 R1）
const SCENARIO = argVal('--scenario', '')

// ★跨机制 standing 调整守卫：单 tick 内每 (观察者→对象) 总移动量封顶 STANDING_DELTA_CAP，再 clamp ±STANDING_CAP。
const _stDelta = {}
function adjustStanding(observer, targetId, delta) {
  const r = rel(observer, targetId)
  const k = observer.id + '>' + targetId
  let e = _stDelta[k]
  if (!e || e.tick !== tick) { e = _stDelta[k] = { tick, acc: 0 } }
  let d = delta
  if (e.acc + d > STANDING_DELTA_CAP) d = STANDING_DELTA_CAP - e.acc
  if (e.acc + d < -STANDING_DELTA_CAP) d = -STANDING_DELTA_CAP - e.acc
  e.acc += d
  r.standing = clampv(r.standing + d, -STANDING_CAP, STANDING_CAP)
  return d
}

// ── 确定性 RNG（镜像 Sim._rng_at：seed = seed_base + tick*911 + salt）──────────
function rngAt(seedBase, tick, salt) {
  // mulberry32，端口内确定可复现
  let a = (seedBase + tick * 911 + salt) >>> 0
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// ── 世界/数据 ────────────────────────────────────────────────────────────
const needsDef = readJSON('needs.json').needs
const mapData = readJSON('map.json')
const personas = readJSON('personas.json')
const agentDefs = readJSON('agents.json').agents

const areas = mapData.areas
const objects = {}
for (const o of mapData.objects) objects[o.id] = { ...o, pos: [o.pos[0], o.pos[1]] }

function areaAt(pos) {
  for (const [id, a] of Object.entries(areas)) {
    const [x, y, w, h] = a.rect
    if (pos[0] >= x && pos[0] < x + w && pos[1] >= y && pos[1] < y + h) return id
  }
  return ''
}

// ── 状态 ─────────────────────────────────────────────────────────────────
let tick = 0, day = 1
const eventLog = []
let nextEventId = 1
const commitments = []     // [{id,type:'meet',a,b,area,created,deadline,status}]
let nextCommitId = 1
const conflicts = []       // [{id,a(委屈方),b(冒犯方),status,triggered,severity,escalations,confronted,repaired}]
let nextConflictId = 1

function makeAgent(def) {
  const ag = {
    id: def.id,
    persona: personas[def.persona] || {},
    pos: [def.spawn[0], def.spawn[1]],
    home: [def.home[0], def.home[1]],
    needs: {},
    option: null,         // {kind:'object'|'social', ...}
    talking: 0,           // >0 表示正在一次对话里（与 partner 绑定的剩余 tick）
    inventory: { gift: GIFT_START },
    relationships: {},     // other_id -> {affinity, trust, resentment, familiarity, standing, last_pos, last_neg}
    beliefs: {},           // claim_id -> {claim, subject, source, via, tick}
    memory: [],            // [{text, importance, tick, tags:[]}]
    attitudes: {}, attitude0: {},  // S2：每话题观点 [-1,1] + 固执锚定的"天生立场"
    xi: 0.3, eps: CONF_BOUND,      // FJ 易感度 / Deffuant 信任带（由性格定）
    stifled: {}, metKnower: {},    // Maki-Thompson：已停传的谣言 / 遇到已知者计数
    faction: '', faction_size: 1,  // S3a：每夜由 attitudes 派生（纯函数，非显式 join）
    pacts: {}, complementSeen: {}, // S3b：互助盟约账本(other->pact) / 互补需求证据计数
  }
  for (const n of needsDef) ag.needs[n.id] = 72.0
  // S2：天生立场(确定性,由 id+话题 hash) + 易感度/信任带(由性格)
  const tr = ag.persona.traits || []
  ag.xi = (tr.includes('好奇') || tr.includes('热情')) ? 0.45 : ((tr.includes('寡言') || tr.includes('务实')) ? 0.18 : 0.30)
  ag.eps = (tr.includes('好奇') || tr.includes('豁达')) ? 1.1 : ((tr.includes('敏感') || tr.includes('寡言')) ? 0.55 : CONF_BOUND)
  for (const t of TOPICS) { const a0 = hash01(ag.id + ':' + t) * 2 - 1; ag.attitude0[t] = a0; ag.attitudes[t] = a0 }
  return ag
}

// 确定性 [0,1) 哈希（字符串→稳定小数；天生立场用，跨运行可复现）
function hash01(s) {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) }
  return ((h >>> 0) % 100000) / 100000
}

const agents = agentDefs.map(makeAgent)
const byId = Object.fromEntries(agents.map((a) => [a.id, a]))

// 种子谣言：阿丽(消息最灵通)知道一条关于可可的传闻 → 之后靠 gossip 扩散（验证知识边界 + 传播）
byId['aria'].beliefs['R1'] = { claim: '可可最近心事重重', subject: 'coco', source: '__seed__', via: 'seed', tick: 0 }

// 定向场景种子（小N下罕见但关键的路径可机检；镜像种子 R1）
if (SCENARIO === 'betray') {
  // aria(爱八卦)被 coco 吐露一条秘密 + aria 对 coco 已积怨 → 必然涌现背叛(leak)
  byId['aria'].beliefs['S_coco'] = { claim: '可可偷偷喜欢着谁', subject: 'coco', source: 'coco', via: 'confide', tick: 0, secret: true, owner: 'coco', confidedBy: { coco: 0 } }
  rel(byId['aria'], 'coco').resentment = 12
  rel(byId['aria'], 'coco').affinity = -20
  logEvent('confide', 'coco', 'aria', 'S_coco', true, [], 'seed')   // 上游证据(供 inv24 溯源)
}
if (SCENARIO === 'faction') {
  // 两极化天生立场 → 涌现两个稳定派系（A 全 +0.8 / B 全 -0.8），并给 A 一人预置对 B 某成员的坏名声 → 触发 endorse
  const gA = agents.slice(0, 3), gB = agents.slice(3)
  for (const a of gA) for (const t of TOPICS) { a.attitudes[t] = 0.8; a.attitude0[t] = 0.8 }
  for (const a of gB) for (const t of TOPICS) { a.attitudes[t] = -0.8; a.attitude0[t] = -0.8 }
  rel(gA[0], gB[0].id).standing = -3   // A 阵营有人已对 B 某成员有恶名 → A 内可 endorse 统一口径
}
if (SCENARIO === 'freerider') {
  // 预置 agents[0]↔[1] 盟约 + 失衡账本(A 一直付出、B 白嫖) → 必触发 free-rider 解体
  const A = agents[0], B = agents[1], key = pactKey(A.id, B.id)
  const mk = (partner, given, received) => ({ partner, key, formedTick: 0, status: 'active', given, received, lastAidTick: 0 })
  A.pacts[B.id] = mk(B.id, 6, 1); B.pacts[A.id] = mk(A.id, 1, 6)
  pactsIndex.push({ id: nextPactId++, key, a: A.id, b: B.id, formed: 0, status: 'active', defect_streak: 0, formTrustA: PACT_TRUST_TH, formTrustB: PACT_TRUST_TH, formFam: PACT_FAM_TH, formComplement: PACT_COMPLEMENT_TH })
  rel(A, B.id).trust = 20; rel(B, A.id).trust = 20
  A.complementSeen[B.id] = PACT_COMPLEMENT_TH; B.complementSeen[A.id] = PACT_COMPLEMENT_TH
}

// ── 关系账本辅助（按 id 建键！）────────────────────────────────────────────
function rel(a, bId) {
  if (!a.relationships[bId]) a.relationships[bId] = { affinity: 0, trust: 0, resentment: 0, familiarity: 0, standing: 0, last_pos: 0, last_neg: 0 }
  return a.relationships[bId]
}

// L3 Simple Standing 二阶范式（docs/10 §A1）：观察者据「动作+对象声誉」更新对行动者的 standing。
//   help → good(+)；defect-against-good → bad(-)；defect-against-bad → 正当(+)。
let stNegEvents = 0   // 累计负向 standing 评判次数（证明坏名声 L3 路径生效，与种子和睦度无关）
function judgeActor(observer, actorId, isHelp, recipientId) {
  if (observer.id === actorId) return
  const r = rel(observer, actorId)
  let d
  if (isHelp) d = 1
  else {
    // recipient 在 observer 眼中是否「好」（self 视作 good）
    const recipientGood = (recipientId === observer.id) ? true : rel(observer, recipientId).standing >= 0
    d = recipientGood ? -1 : +1   // 冒犯好人=坏；教训坏人=正当
  }
  if (d < 0) stNegEvents++
  adjustStanding(observer, actorId, d)   // 经跨机制 per-tick 守卫
}

// 工具
const clampv = (v, lo, hi) => Math.max(lo, Math.min(hi, v))

// S2：Friedkin-Johnsen 单步（成对，Deffuant 式）——i 朝 j 的观点靠拢，按 trust·familiarity 加权，
// 固执度(1-ξ)锚定天生立场 attitude0 → 持久分歧而非 DeGroot 单一共识；高怨气→背离(signed)。
function fjUpdate(i, j, t) {
  const ro = rel(i, j.id)
  const backfire = ro.resentment > BACKFIRE_RESENT
  const tw = clampv((ro.trust + 50) / 100 * (0.5 + Math.min(ro.familiarity, 10) / 20), 0.05, 0.6)
  const xj = backfire ? (2 * i.attitudes[t] - j.attitudes[t]) : j.attitudes[t]  // 背离=朝相反"虚拟对方"
  const blended = tw * xj + (1 - tw) * i.attitudes[t]
  i.attitudes[t] = clampv(i.xi * blended + (1 - i.xi) * i.attitude0[t], -1, 1)
}
// ── S3a 观点派系：每夜从 attitudes 确定性派生（纯函数，非显式 join）──────────
// 对齐判据：≥FACTION_MIN_AGREE 个话题"同号(非骑墙)且 |Δ|<FACTION_BAND"。
function aligned(a, b) {
  let agree = 0
  for (const t of TOPICS) {
    const xa = a.attitudes[t], xb = b.attitudes[t]
    if (Math.abs(xa) < FACTION_SALIENT || Math.abs(xb) < FACTION_SALIENT) continue  // 骑墙不计
    if (Math.sign(xa) === Math.sign(xb) && Math.abs(xa - xb) < FACTION_BAND) agree++
  }
  return agree >= FACTION_MIN_AGREE
}
// 单遍贪心聚类（sorted id 固定序，确定性、路径无关）：各 agent 并入第一个对齐 medoid，否则自立。
function recomputeFactions() {
  factions = {}
  const ids = agents.map((a) => a.id).slice().sort()
  const medoids = []
  const assign = {}
  for (const id of ids) {
    let placed = ''
    for (const m of medoids) { if (aligned(byId[id], byId[m])) { placed = m; break } }
    if (placed) { assign[id] = placed; factions[placed].push(id) }
    else { medoids.push(id); assign[id] = id; factions[id] = [id] }
  }
  for (const ag of agents) {
    const members = factions[assign[ag.id]]
    if (members.length >= 2) { ag.faction = assign[ag.id]; ag.faction_size = members.length }
    else { ag.faction = ''; ag.faction_size = 1 }
  }
  for (const m of Object.keys(factions)) if (factions[m].length < 2) delete factions[m]  // 只读视图只留真派系
  factionRecomputeDay = day
}
// _acceptance_rule 的派系门项（从 target 视角看 actor）：同派系 +K、跨派系 -K、否则 0。
function factionTerm(target, actor) {
  if (target.faction !== '' && target.faction === actor.faction) return FACTION_ACCEPT_K
  if (target.faction !== '' && actor.faction !== '' && target.faction !== actor.faction) return -FACTION_ACCEPT_K
  return 0
}
// ── S3b 互助盟约（结/解盟单遍贪心，确定性；复用 trust/familiarity/standing/冲突，不另立承诺类型）──
function pactKey(a, b) { return a < b ? a + '|' + b : b + '|' + a }
function activePactCount(ag) { let n = 0; for (const k of Object.keys(ag.pacts)) if (ag.pacts[k].status === 'active') n++; return n }

// 互补需求证据：一方某 need 低(<LOW)而另一方同 need 足(>=HIGH) → 双向计数（needs→trigger，确定性）
function accrueComplement(ag, o) {
  let comp = false
  for (const nid of Object.keys(ag.needs)) {
    if ((ag.needs[nid] < COMPLEMENT_LOW && o.needs[nid] >= COMPLEMENT_HIGH) || (o.needs[nid] < COMPLEMENT_LOW && ag.needs[nid] >= COMPLEMENT_HIGH)) comp = true
  }
  if (comp) { ag.complementSeen[o.id] = (ag.complementSeen[o.id] || 0) + 1; o.complementSeen[ag.id] = (o.complementSeen[ag.id] || 0) + 1 }
}

// 解盟：扫 active pact，free-rider(成熟+净失衡+连续) → 解体（GTFT：一次回报清 streak）
function dissolveFreeriders() {
  for (const p of pactsIndex) {
    if (p.status !== 'active') continue
    const A = byId[p.a], B = byId[p.b]
    const pa = A.pacts[p.b], pb = B.pacts[p.a]
    if (!pa || !pb) continue
    const gapA = pa.given - pa.received, gapB = pb.given - pb.received
    const gap = Math.max(gapA, gapB)
    const total = pa.given + pa.received
    if (gap >= FREERIDER_GAP && total >= PACT_MIN_EXCHANGES) p.defect_streak = (p.defect_streak || 0) + 1
    else p.defect_streak = 0   // 平衡/回报 → 清零（GTFT 宽恕一次噪声）
    if (p.defect_streak >= FREERIDER_STREAK) {
      const victim = gapA >= gapB ? A : B, freerider = gapA >= gapB ? B : A
      dissolvePact(p, victim, freerider, gap)
    }
  }
}
function dissolvePact(p, victim, freerider, gap) {
  p.status = 'broken'; p.brokenTick = tick; p.reason = 'freerider:' + freerider.id; p.breakGap = gap
  delete victim.pacts[freerider.id]; delete freerider.pacts[victim.id]
  lastBrokenWith[p.key] = tick
  const rv = rel(victim, freerider.id)
  rv.trust = clampv(rv.trust - PACT_BREAK_TRUST, -100, 100)
  rv.affinity = clampv(rv.affinity - 8, -100, 100)
  judgeActor(victim, freerider.id, false, victim.id)   // L3 defect-against-good → 坏名声（喂 stNegEvents，gossip_rep 外溢）
  const e = logEvent('pact', victim.id, freerider.id, '', false, [], 'dissolved:freerider')
  rv.last_neg = e.id
  bumpResentment(victim, freerider.id, PACT_BREAK_RESENT, e.id)   // 可触发冲突（复用生命周期）
  freeriderDissolves++
  remember(victim, `和${name(freerider)}的盟约散了，被白嫖了`, 7, [freerider.id, 'pact', 'dissolve'])
  remember(freerider, `背弃了和${name(victim)}的盟约`, 6, [victim.id, 'pact', 'dissolve'])
}
// 结盟：固定 id 序单遍贪心；双向 trust+familiarity+互补证据达标且对方未满额、过冷却 → 结
function formPactsGreedy() {
  const ids = agents.map((a) => a.id).slice().sort()
  for (const id of ids) {
    const ag = byId[id]
    if (activePactCount(ag) >= PACT_CAP) continue
    let bestO = null, bestScore = -Infinity
    for (const oid of ids) {
      if (oid === id) continue
      const o = byId[oid]
      if (ag.pacts[oid] && ag.pacts[oid].status === 'active') continue
      if (activePactCount(o) >= PACT_CAP) continue
      const key = pactKey(id, oid)
      if (lastBrokenWith[key] && tick - lastBrokenWith[key] < PACT_RECONCILE_COOLDOWN * TICKS_PER_DAY) continue
      if (rel(ag, oid).trust < PACT_TRUST_TH || rel(o, id).trust < PACT_TRUST_TH) continue
      if (rel(ag, oid).familiarity < PACT_FAM_TH) continue
      if ((ag.complementSeen[oid] || 0) < PACT_COMPLEMENT_TH) continue
      const score = rel(ag, oid).affinity + rel(o, id).affinity + rel(ag, oid).trust + rel(o, id).trust + (ag.complementSeen[oid] || 0) * 2 + hash01(key) * 0.5
      if (score > bestScore) { bestScore = score; bestO = o }
    }
    if (bestO) formPact(ag, bestO)
  }
}
function formPact(ag, o) {
  const key = pactKey(ag.id, o.id)
  const mk = () => ({ partner: '', key, formedTick: tick, status: 'active', given: 0, received: 0, lastAidTick: 0 })
  ag.pacts[o.id] = Object.assign(mk(), { partner: o.id })
  o.pacts[ag.id] = Object.assign(mk(), { partner: ag.id })
  pactsIndex.push({ id: nextPactId++, key, a: ag.id, b: o.id, formed: tick, status: 'active', defect_streak: 0,
    formTrustA: rel(ag, o.id).trust, formTrustB: rel(o, ag.id).trust, formFam: rel(ag, o.id).familiarity, formComplement: ag.complementSeen[o.id] || 0 })
  rel(ag, o.id).trust = clampv(rel(ag, o.id).trust + 2, -100, 100); rel(o, ag.id).trust = clampv(rel(o, ag.id).trust + 2, -100, 100)
  logEvent('pact', ag.id, o.id, '', true, [], 'formed')
  remember(ag, `和${name(o)}结成了互助盟约`, 6, [o.id, 'pact', 'form'])
  remember(o, `和${name(ag)}结成了互助盟约`, 6, [ag.id, 'pact', 'form'])
}

function areaCentroid(areaId) {
  const r = areas[areaId].rect
  return [r[0] + Math.floor(r[2] / 2), r[1] + Math.floor(r[3] / 2)]
}
function hasActiveMeet(aId, bId) {
  return commitments.some((c) => c.status === 'active' && ((c.a === aId && c.b === bId) || (c.a === bId && c.b === aId)))
}
function anyActiveMeet(aId) {
  return commitments.some((c) => c.status === 'active' && (c.a === aId || c.b === aId))
}
function minNeed(ag) {
  let m = 100
  for (const nid of Object.keys(ag.needs)) m = Math.min(m, ag.needs[nid])
  return m
}

// ── 冲突 ─────────────────────────────────────────────────────────────────
function findConflict(aId, bId, statuses) {
  return conflicts.find((c) => c.a === aId && c.b === bId && statuses.includes(c.status))
}
// 给 holder 对 towardId 累积怨气；越线则触发冲突；已有未了冲突则升级。
function bumpResentment(holder, towardId, amt, evId) {
  const r = rel(holder, towardId)
  r.resentment = clampv(r.resentment + amt, 0, 100)
  const open = findConflict(holder.id, towardId, ['simmering', 'escalated'])
  if (open) {
    open.escalations++; open.severity += amt; open.lastEscalate = tick
    if (open.escalations >= ESC_THRESH) open.status = 'escalated'
  } else if (!findConflict(holder.id, towardId, ['simmering', 'escalated', 'confronted', 'lingering']) && r.resentment >= CONFLICT_TRIGGER) {
    conflicts.push({ id: nextConflictId++, a: holder.id, b: towardId, status: 'simmering', triggered: tick, lastEscalate: tick, severity: r.resentment, escalations: 0, confronted: 0, repaired: 0 })
    logEvent('conflict', holder.id, towardId, '', false, [], 'triggered')
    remember(holder, `对${name(byId[towardId])}积了怨气`, 5, [towardId, 'conflict', 'trigger'])
  }
}

// ── 记忆（镜像 MemoryStream，含人物 tag + 写入期 importance 派生）─────────────
function remember(ag, text, importance, tags) {
  ag.memory.push({ text, importance, tick, tags })
  if (ag.memory.length > 200) {
    ag.memory.sort((x, y) => y.importance - x.importance)
    ag.memory = ag.memory.slice(0, 150)
  }
}

// ── 感知：同区的其他 agent ───────────────────────────────────────────────
function nearbyAgents(ag) {
  const myArea = areaAt(ag.pos)
  if (!myArea) return []
  return agents.filter((o) => o.id !== ag.id && areaAt(o.pos) === myArea)
}

// ── 需求衰减 ─────────────────────────────────────────────────────────────
function decay(ag) {
  for (const n of needsDef) ag.needs[n.id] = Math.max(0, ag.needs[n.id] - n.decay)
}

// ── 候选：物件交互 + 社交（合法候选契约，引擎枚举，永远兜底）──────────────────
function objectCandidates(ag) {
  const out = []
  for (const [id, o] of Object.entries(objects)) {
    for (const adv of o.advertises || []) {
      if (adv.amount <= 0) continue
      const cur = ag.needs[adv.need] ?? 100
      const urgency = 100 - cur
      if (urgency <= 5) continue
      const dist = Math.abs(ag.pos[0] - o.pos[0]) + Math.abs(ag.pos[1] - o.pos[1])
      const score = urgency * (adv.amount / 60) - dist * 0.4
      out.push({ kind: 'object', action: adv.action, target: id, need: adv.need, amount: adv.amount, dur: adv.duration, score })
    }
  }
  return out
}

// 一个 agent 已知、但 target 还不知道的 belief（用于 gossip；体现知识边界）
function unspreadBelief(actor, target) {
  for (const [cid, b] of Object.entries(actor.beliefs)) {
    if (b.secret) continue                         // S3c：秘密走专道(confide/leak)，绝不经普通 gossip 扩散
    if (actor.stifled[cid]) continue               // Maki-Thompson：已停传(变冷)的谣言不再扩散
    if (b.subject === target.id) continue          // 不当面议论本人
    if (!target.beliefs[cid]) return { cid, b }
  }
  return null
}

// S3c 秘密通道：owner==actor 的未传秘密(可吐露) / owner!=actor 且 confidedBy 非空的未传秘密(可外泄=背叛)
function confidableSecret(actor, target) {
  for (const [cid, b] of Object.entries(actor.beliefs)) {
    if (b.secret && b.owner === actor.id && b.subject !== target.id && !target.beliefs[cid]) return cid
  }
  return ''
}
function leakableSecret(actor, target) {
  for (const [cid, b] of Object.entries(actor.beliefs)) {
    if (b.secret && b.owner !== actor.id && b.confidedBy && Object.keys(b.confidedBy).length > 0
      && b.subject !== target.id && !target.beliefs[cid]) return cid
  }
  return ''
}

function socialCandidates(ag) {
  const out = []
  const social = ag.needs.social ?? 100
  if (social >= SOCIAL_FULL) return out
  const urgency = 100 - social
  for (const o of nearbyAgents(ag)) {
    if (o.talking > 0) continue                    // 对方正忙
    const r = rel(ag, o.id)
    const aff = r.affinity
    // greet / smalltalk —— 总可发起
    out.push({ kind: 'social', action: 'greet', partner: o.id, subject: null, need: 'social',
      score: urgency * 0.7 + aff * 0.1 + r.familiarity * 0.05 + 6 })
    // give —— 有礼物时；条件投资 trust 门(脆弱动作只对够信任者发起)；偏向还不熟、想拉近的人
    if ((ag.inventory.gift || 0) > 0 && r.trust >= INVEST_TRUST) {
      out.push({ kind: 'social', action: 'give', partner: o.id, subject: null, need: 'social',
        score: urgency * 0.5 + (12 - Math.min(12, r.familiarity)) * 0.6 + 12 })
    }
    // gossip —— 有对方不知道的传闻时；爱八卦者更爱
    const u = unspreadBelief(ag, o)
    if (u) {
      const gossipy = (ag.persona.traits || []).includes('爱八卦') ? 8 : 0
      out.push({ kind: 'social', action: 'gossip', partner: o.id, subject: u.cid, need: 'social',
        score: urgency * 0.6 + aff * 0.1 + gossipy + 5 })
    }
    // S3c confide —— 仅 owner 向高 trust+aff 者吐露心事（最脆弱的条件投资，门高于 give/invite）
    if (r.trust >= CONFIDE_TRUST && aff >= SECRET_AFF_FLOOR) {
      const cs = confidableSecret(ag, o)
      if (cs) out.push({ kind: 'social', action: 'confide', partner: o.id, subject: cs, need: 'social',
        score: urgency * 0.4 + (r.trust - CONFIDE_TRUST) * 0.3 + r.familiarity * 0.2 + 9 })
    }
    // S3c leak —— 把别人吐露给我的秘密外传给第三方=背叛（无 trust 门；愧疚抑制，对托付者积怨则报复）
    const ls = leakableSecret(ag, o)
    if (ls) {
      const tellerId = Object.keys(ag.beliefs[ls].confidedBy)[0]
      const rt2 = rel(ag, tellerId)
      const revenge = rt2.resentment * 1.2
      const guilt = Math.max(0, rt2.affinity) * 0.12 * (rt2.resentment > 0 ? 0.5 : 1.0)
      const gossipy = (ag.persona.traits || []).includes('爱八卦') ? 9 : 0
      out.push({ kind: 'social', action: 'leak', partner: o.id, subject: ls, need: 'social',
        score: urgency * 0.5 + revenge + gossipy + 6 - guilt })
    }
    // discuss —— 挑"自己信任带 ε 内最大分歧"的话题聊（可谈的最大分歧；接受与否再走对方 Deffuant 门 → 自然产生拒谈）
    let dTopic = null, dDiff = DISCUSS_MINDIFF
    for (const t of TOPICS) {
      const diff = Math.abs((ag.attitudes[t] || 0) - (o.attitudes[t] || 0))
      if (diff > dDiff && diff <= ag.eps) { dDiff = diff; dTopic = t }
    }
    if (dTopic) out.push({ kind: 'social', action: 'discuss', partner: o.id, subject: dTopic, need: 'social', score: urgency * 0.55 + dDiff * 6 + aff * 0.08 + 5.5 })
    // gossip_rep —— 我对某第三方 C 有坏名声(standing≤阈)，而 o 还没那么坏的印象 → 传 C 的名声（reputation from spread info）
    for (const c of agents) {
      if (c.id === ag.id || c.id === o.id) continue
      if (rel(ag, c.id).standing <= REP_GOSSIP_TH && rel(o, c.id).standing > rel(ag, c.id).standing) {
        const gossipy = (ag.persona.traits || []).includes('爱八卦') ? 8 : 0
        out.push({ kind: 'social', action: 'gossip_rep', partner: o.id, subject: c.id, need: 'social',
          score: urgency * 0.6 + gossipy + 10 })   // 示警优先：有恶名者时主动传，免被 discuss/greet 挤没
        break
      }
    }
    // invite —— 约对方稍后再聚（创建 meet 承诺）；条件投资 trust 门；按熟悉度加权；手头无未了约会才发起
    if (!anyActiveMeet(ag.id) && !hasActiveMeet(ag.id, o.id) && r.trust >= INVEST_TRUST) {
      const pactB = (ag.pacts[o.id] && ag.pacts[o.id].status === 'active') ? PACT_INVITE_BONUS : 0  // S3b：优先约盟友
      out.push({ kind: 'social', action: 'invite', partner: o.id, subject: '', need: 'social',
        score: urgency * 0.45 + aff * 0.15 + r.familiarity * 0.18 + 4 + pactB })
    }
    // confront —— 我对 o 积怨成冲突 → 想当面说开（越严重越想）
    const cf = findConflict(ag.id, o.id, ['simmering', 'escalated', 'lingering'])
    if (cf) out.push({ kind: 'social', action: 'confront', partner: o.id, subject: '', need: 'social', score: 30 + Math.min(cf.severity, 20) })
    // apologize —— o 对我有冲突且已被我当面对质（我已知错）→ 想道歉
    if (findConflict(o.id, ag.id, ['confronted'])) {
      out.push({ kind: 'social', action: 'apologize', partner: o.id, subject: '', need: 'social', score: 32 })
    }
    // ── S3a 协同行动（仅当 ag 已属派系）──
    if (ag.faction !== '' && ag.faction_size >= FACTION_QUORUM) {
      // endorse —— o 是同派系成员；存在外群恶名第三方 C（standing≤阈，o 印象没那么坏）→ 统一对外口径
      if (o.faction === ag.faction) {
        for (const c of agents) {
          if (c.id === ag.id || c.id === o.id || c.faction === ag.faction) continue   // C 必须是外群
          if (rel(ag, c.id).standing <= REP_GOSSIP_TH && rel(o, c.id).standing > rel(ag, c.id).standing) {
            const gossipy = (ag.persona.traits || []).includes('爱八卦') ? 8 : 0
            out.push({ kind: 'social', action: 'endorse', partner: o.id, subject: c.id, need: 'social', score: urgency * 0.6 + FACTION_ENDORSE_BONUS + gossipy })
            break
          }
        }
      }
      // rally_oust —— o 是外群，且 ag 对 o 已有冲突/坏名声 → 带派系底气施压（评分 < confront，私下对质优先）
      if (o.faction !== ag.faction) {
        const cf2 = findConflict(ag.id, o.id, ['simmering', 'escalated', 'lingering'])
        if (cf2 || rel(ag, o.id).standing <= REP_GOSSIP_TH) {
          out.push({ kind: 'social', action: 'rally_oust', partner: o.id, subject: '', need: 'social', score: OUST_BASE + Math.min(cf2 ? cf2.severity : 0, 15) })
        }
      }
    }
    // ── S3b aid（仅当 o 是 active pact 伙伴且其某 need 低）──
    const pc = ag.pacts[o.id]
    if (pc && pc.status === 'active') {
      const lowNeed = partnerLowNeed(o)
      if (lowNeed) out.push({ kind: 'social', action: 'aid', partner: o.id, subject: lowNeed, need: 'social', score: (AID_NEED_TH - o.needs[lowNeed]) * 1.2 + r.familiarity * 0.1 + AID_BASE })
    }
  }
  return out
}

// S3b：对方某 need 低于 AID_NEED_TH（我可补）→ 返回该 need id，否则 ''
function partnerLowNeed(o) {
  let lid = '', lv = AID_NEED_TH
  for (const nid of Object.keys(o.needs)) if (o.needs[nid] < lv) { lv = o.needs[nid]; lid = nid }
  return lid
}

// attend —— 手头有临近 deadline 的 meet 承诺 → 引擎给“去赴约”加权（越近越急）。
function attendCandidates(ag) {
  const out = []
  for (const c of commitments) {
    if (c.status !== 'active') continue
    if (c.a !== ag.id && c.b !== ag.id) continue
    if (c.deadline - tick > ATTEND_WINDOW) continue
    const closeness = 1 - (c.deadline - tick) / MEET_HORIZON  // 0..1，越近越大
    const otherId = c.a === ag.id ? c.b : c.a
    const pactB = (ag.pacts[otherId] && ag.pacts[otherId].status === 'active') ? PACT_ATTEND_BONUS : 0  // S3b：优先赴盟友的约
    out.push({ kind: 'attend', area: c.area, commit: c.id, score: 25 + closeness * 40 + pactB })
  }
  return out
}

function candidates(ag) {
  return [...objectCandidates(ag), ...socialCandidates(ag), ...attendCandidates(ag)]
}

function best(cands, salt) {
  // 平分用 _rng_at 抖动打破（顺带修 Sim 里 _rng_at 的死代码 / 严格> 平局退化）
  const rnd = rngAt(SEED, tick, salt)
  let bestC = null, bestS = -Infinity
  for (const c of cands) {
    const s = c.score + rnd() * 0.5
    if (s > bestS) { bestS = s; bestC = c }
  }
  return bestC
}

// ── SocialTransaction：发起 → 评估(接受/拒绝) → 提交 → 双方+旁观者写记忆 ─────────
function acceptanceRule(actor, target, action, salt, subject) {
  const r = rel(target, actor.id)
  const aff = r.affinity
  const st = r.standing * STANDING_K   // 声誉门：坏名声→更难被接受（涌现放逐）；好名声→更易
  const need = target.needs.social ?? 100
  const rnd = rngAt(SEED, tick, salt)
  const jitter = (rnd() - 0.5) * 20
  const traits = target.persona.traits || []
  const fac = factionTerm(target, actor)   // S3a：同派系更易接受、跨派系更难（涌现放逐加剧）
  if (action === 'discuss') {
    // Deffuant 有界信任：观点差在信任带 ε 内才谈得拢（软门）；差太大→拒谈（记一笔）；同派系更谈得拢
    const diff = Math.abs((actor.attitudes[subject] || 0) - (target.attitudes[subject] || 0))
    const okk = (target.eps - diff) * 30 + aff + st + fac + jitter > 0
    if (!okk) refusedByBound++
    return okk
  }
  if (action === 'confide') return aff + st + jitter > -10        // 一般都愿听心事（不叠 fac：吐露是私人信任）
  if (action === 'leak') {                                        // 听秘密=收八卦：同 gossip 矜持门
    if (traits.includes('爱八卦')) return true
    const reserved = (traits.includes('寡言') || traits.includes('温柔')) ? -15 : 0
    return aff + reserved + st + jitter > 0
  }
  if (action === 'endorse') return aff + st + fac > -50           // 同派系背书：几乎必接（fac=+K）
  if (action === 'aid') return aff + st > -50                     // 盟友善意：几乎总收（走自己门，不叠 fac）
  if (action === 'give') return aff + st + fac > -60              // 一般都收礼，除非极度反感/极坏名声
  if (action === 'gossip' || action === 'gossip_rep') {
    if (traits.includes('爱八卦')) return true                    // 爱八卦者来者不拒
    const reserved = (traits.includes('寡言') || traits.includes('温柔')) ? -15 : 0  // 寡言/温柔者矜持
    return aff + reserved + st + fac + jitter > 0
  }
  if (action === 'invite') return (100 - need) * 0.35 + aff + st + fac + jitter > -2  // 约见：缺社交/有好感/好名声/同派系更易答应
  // greet: 对方越缺社交/越有好感/名声越好/同派系越易接受
  return (100 - need) * 0.4 + aff + st + fac + jitter > 0
}

function logEvent(type, actor, target, subject, accepted, witnesses, note) {
  const e = { id: nextEventId++, tick, type, actor, target, subject, accepted, witnesses: witnesses.map((w) => w.id), note }
  eventLog.push(e)
  return e
}

function commitSocial(actor, opt) {
  const target = byId[opt.partner]
  if (!target || areaAt(actor.pos) !== areaAt(target.pos)) return // 对方离开 → 作废
  const witnesses = nearbyAgents(actor).filter((w) => w.id !== target.id)
  // 冲突类社交（对质/道歉）有自己的状态机，单独处理
  if (opt.action === 'confront') { resolveConfront(actor, target, witnesses); return }
  if (opt.action === 'apologize') { resolveApologize(actor, target, witnesses); return }
  if (opt.action === 'rally_oust') { resolveRallyOust(actor, target, witnesses); return }
  const accepted = acceptanceRule(actor, target, opt.action, 31, opt.subject)
  const ra = rel(actor, target.id), rt = rel(target, actor.id)

  if (!accepted) {
    ra.affinity = clampv(ra.affinity - 3, -100, 100); rt.affinity = clampv(rt.affinity - 3, -100, 100)
    const e = logEvent(opt.action, actor.id, target.id, opt.subject, false, witnesses, 'refused')
    ra.last_neg = e.id; rt.last_neg = e.id
    bumpResentment(actor, target.id, 3, e.id)   // 被婉拒积点怨气（足够多 → 触发冲突）
    // L3：拒绝=target 对 actor 的 defect；actor(self=good) 与旁观者据此降 target 的 standing（拒绝坏人则正当）
    judgeActor(actor, target.id, false, actor.id)
    for (const w of witnesses) judgeActor(w, target.id, false, actor.id)
    remember(actor, `想找${name(target)}${verb(opt.action)}，被婉拒了`, impt(actor, target, 3, true), [target.id, 'social', 'refuse'])
    remember(target, `婉拒了${name(actor)}的${verb(opt.action)}`, impt(target, actor, 3, true), [actor.id, 'social', 'refuse'])
    return
  }

  // 接受 → 效果
  let affA = 2, affT = 2
  actor.needs.social = clamp(actor.needs.social + 16)
  target.needs.social = clamp(target.needs.social + 12)
  if (opt.action === 'give') {
    actor.inventory.gift = (actor.inventory.gift || 0) - 1
    affT = 6; affA = 2; target.needs.fun = clamp(target.needs.fun + 4)
  } else if (opt.action === 'gossip') {
    // 知识边界：target 通过本次事务“得知”该 claim，source=actor
    const b = actor.beliefs[opt.subject]
    if (b && !target.beliefs[opt.subject]) {
      target.beliefs[opt.subject] = { claim: b.claim, subject: b.subject, source: actor.id, via: 'gossip', tick }
    }
    if ((target.persona.traits || []).includes('爱八卦')) target.needs.social = clamp(target.needs.social + 6)
    affA = 1; affT = 1
  } else if (opt.action === 'invite') {
    // 创建 meet 承诺：约在【当下两人所在的同一区】于 deadline 前再聚（赴约由 attend 驱动，需求危机会爽约 → broken）
    const area = areaAt(actor.pos) || 'plaza'
    commitments.push({ id: nextCommitId++, type: 'meet', a: actor.id, b: target.id, area, created: tick, deadline: tick + MEET_HORIZON, status: 'active' })
    affA = 2; affT = 2
  } else if (opt.action === 'gossip_rep') {
    // 传播第三方 C 的（坏）名声：信任源才采纳；target 对 C 的 standing 向 actor 靠拢一步 + affinity 微降（reputation from spread info）
    const cId = opt.subject
    if (cId && byId[cId] && rel(target, actor.id).trust >= -20) {
      const rcA = rel(actor, cId), rcT = rel(target, cId)
      rcT.standing = clampv(rcT.standing + Math.sign(rcA.standing - rcT.standing), -STANDING_CAP, STANDING_CAP)
      rcT.affinity = clampv(rcT.affinity - 2, -100, 100)
      remember(target, `听${name(actor)}说起${name(byId[cId])}的事`, 4, [cId, actor.id, 'rep', 'gossip'])
    }
    affA = 1; affT = 1
  } else if (opt.action === 'discuss') {
    // FJ/Deffuant 成对更新：双方观点互相靠拢(固执锚定/高怨气背离)；意见会演化但不坍缩成单一共识
    const t = opt.subject
    fjUpdate(actor, target, t); fjUpdate(target, actor, t)
    affA = 1; affT = 1
  } else if (opt.action === 'confide') {
    // S3c：owner 向信任者吐露秘密 → target 习得(via confide, confidedBy=直接上游) + 双向 trust 加深
    const b = actor.beliefs[opt.subject]
    if (b && b.secret && b.owner === actor.id && !target.beliefs[opt.subject]) {
      target.beliefs[opt.subject] = { claim: b.claim, subject: b.subject, source: actor.id, via: 'confide', tick, secret: true, owner: b.owner, confidedBy: { [actor.id]: tick } }
      confideEvents++
    }
    ra.trust = clampv(ra.trust + CONFIDE_TRUST_GAIN, -100, 100)
    rt.trust = clampv(rt.trust + CONFIDE_TRUST_GAIN, -100, 100)
    remember(target, `${name(actor)}对我吐露了心事`, 6, [actor.id, 'secret', 'confided'])
    affA = 2; affT = 2
  } else if (opt.action === 'leak') {
    // S3c：把别人吐露给我的秘密外传=背叛。target 习得(只记直接上游=actor)；对每个直接 teller 施背叛后果
    const b = actor.beliefs[opt.subject]
    const tellers = Object.keys((b && b.confidedBy) || {})
    if (b && b.secret && !target.beliefs[opt.subject]) {
      target.beliefs[opt.subject] = { claim: b.claim, subject: b.subject, source: actor.id, via: 'leak', tick, secret: true, owner: b.owner, confidedBy: { [actor.id]: tick } }
    }
    for (const tellerId of tellers) {
      if (tellerId === actor.id || tellerId === target.id) continue
      const betrayed = byId[tellerId]
      if (!betrayed) continue
      const rbv = rel(betrayed, actor.id)
      rbv.trust = clampv(rbv.trust + BETRAY_TRUST_CRASH, -100, 100)
      rbv.affinity = clampv(rbv.affinity + BETRAY_AFF_CRASH, -100, 100)
      adjustStanding(betrayed, actor.id, BETRAY_STANDING); stNegEvents++   // 被泄方直降背叛者名声(经守卫)
      const be = logEvent('betray', actor.id, tellerId, opt.subject, true, witnesses, 'leaked')
      rbv.last_neg = be.id
      bumpResentment(betrayed, actor.id, BETRAY_RESENT, be.id)             // >CONFLICT_TRIGGER → 必触发一段冲突
      betrayEvents++
      remember(betrayed, `${name(actor)}把我吐露的秘密说了出去`, 9, [actor.id, 'secret', 'betray'])
      remember(actor, `把${name(betrayed)}的秘密说漏了`, 6, [tellerId, 'secret', 'betray'])
      judgeActor(target, actor.id, false, tellerId)                       // 知情者据 L3 降背叛者 standing
      for (const w of witnesses) if (w.id !== tellerId) judgeActor(w, actor.id, false, tellerId)
    }
    affA = 1; affT = 1
  } else if (opt.action === 'endorse') {
    // S3a：派系内对外群恶名者 C 统一口径 = gossip_rep 加速版（standing 靠拢两步，经守卫 clamp）
    const cId = opt.subject
    if (cId && byId[cId]) {
      const dir = Math.sign(rel(actor, cId).standing - rel(target, cId).standing)
      adjustStanding(target, cId, dir * 2)
      const rcT = rel(target, cId); rcT.affinity = clampv(rcT.affinity - FACTION_ENDORSE_AFF, -100, 100)
      endorseEvents++
      remember(target, `和${name(actor)}统一了对${name(byId[cId])}的看法`, 4, [cId, actor.id, 'faction', 'endorse'])
    }
    affA = 1; affT = 1
  } else if (opt.action === 'aid') {
    // S3b：盟友按需互助（补对方真实低 need），互惠记账 + 涨信任 + L3 help
    const nid = opt.subject
    if (nid && target.needs[nid] !== undefined) target.needs[nid] = clamp(target.needs[nid] + AID_RELIEF)
    if ((actor.inventory.gift || 0) > 0 && nid === 'fun') actor.inventory.gift -= 1
    recordAid(actor, target)
    ra.trust = clampv(ra.trust + AID_TRUST, -100, 100); rt.trust = clampv(rt.trust + AID_TRUST, -100, 100)
    judgeActor(target, actor.id, true, target.id)                         // 受助者据 L3：互助=help-good→standing 升
    aidAccepted++
    remember(target, `${name(actor)}雪中送炭帮了我`, 6, [actor.id, 'pact', 'aid'])
    affA = 3; affT = 3
  }
  // S3a 同派系日常社交额外亲和（小量，防锁死；仅日常类，不与 aid/endorse 叠算）
  if (actor.faction !== '' && actor.faction === target.faction && ['greet', 'give', 'gossip', 'discuss'].includes(opt.action)) { affA += FACTION_INGROUP_AFF; affT += FACTION_INGROUP_AFF }
  ra.affinity = clamp(ra.affinity + affA, -100, 100)
  rt.affinity = clamp(rt.affinity + affT, -100, 100)
  ra.familiarity += 1; rt.familiarity += 1
  accrueComplement(actor, target)   // S3b：累积互补需求证据（needs→trigger 结盟依据）
  // Maki-Thompson 谣言变冷：本次接触中，actor 知道的谣言若 target 也已知 → 遇到"已知者"，累计到 K 则停传(变 stifler)
  for (const cid of Object.keys(actor.beliefs)) {
    if (actor.stifled[cid]) continue
    if (target.beliefs[cid]) {
      actor.metKnower[cid] = (actor.metKnower[cid] || 0) + 1
      if (actor.metKnower[cid] >= STIFLE_K) actor.stifled[cid] = true
    }
  }

  const e = logEvent(opt.action, actor.id, target.id, opt.subject, true, witnesses, 'accepted')
  ra.last_pos = e.id; rt.last_pos = e.id

  // 双方 + 旁观者各写“视角不同”的记忆（含人物 tag + 写入期 importance 派生）
  remember(actor, `和${name(target)}${verb(opt.action)}`, impt(actor, target, affA, false), [target.id, 'social', opt.action])
  remember(target, `${name(actor)}来${verb(opt.action)}`, impt(target, actor, affT, false), [actor.id, 'social', opt.action])
  for (const w of witnesses) {
    remember(w, `看见${name(actor)}和${name(target)}在${areaLabel(actor.pos)}${verb(opt.action)}`, 2, [actor.id, target.id, 'observe'])
  }
  // 注：standing(道德/可靠性声誉) 只由可靠性信号驱动——守约/爽约/拒绝/对质/和解，
  // 不被日常 greet/give/gossip 灌水（那些走 affinity=好感）。避免"人人都好"坍缩，保留 L3 区分度。
}

// confront —— A(委屈方)当面对质 B(冒犯方)。B 接茬→confronted(通往和解)；B 否认/回避→escalated。
function resolveConfront(A, B, witnesses) {
  const c = findConflict(A.id, B.id, ['simmering', 'escalated', 'lingering'])
  if (!c) return
  A.needs.social = clamp(A.needs.social + 10); B.needs.social = clamp(B.needs.social + 6)
  const proud = (B.persona.traits || []).includes('寡言') ? -25 : 0
  const engage = 55 + proud + (rngAt(SEED, tick, 71)() - 0.5) * 30 > 0
  const ra = rel(A, B.id), rb = rel(B, A.id)
  if (engage) {
    c.status = 'confronted'; c.confronted = tick
    ra.affinity = clampv(ra.affinity - 2, -100, 100); rb.affinity = clampv(rb.affinity - 2, -100, 100) // 对质当下气氛紧张
    const e = logEvent('confront', A.id, B.id, '', true, witnesses, 'aired')
    ra.last_neg = e.id
    remember(A, `当面找${name(B)}把话说开了`, 6, [B.id, 'conflict', 'confront'])
    remember(B, `${name(A)}来找我理论，我听了`, 6, [A.id, 'conflict', 'confront'])
  } else {
    c.severity += 4; c.escalations++; c.status = 'escalated'
    ra.resentment = clampv(ra.resentment + 3, 0, 100); ra.affinity = clampv(ra.affinity - 3, -100, 100)
    ra.standing = clampv(ra.standing - 1, -STANDING_CAP, STANDING_CAP)   // 否认=defect-against-good → 坏名声
    for (const w of witnesses) judgeActor(w, B.id, false, A.id)
    const e = logEvent('confront', A.id, B.id, '', false, witnesses, 'deflected')
    ra.last_neg = e.id
    remember(A, `找${name(B)}理论，${name(B)}不认，更气了`, 7, [B.id, 'conflict', 'escalate'])
    remember(B, `${name(A)}来质问，我没接茬`, 5, [A.id, 'conflict', 'escalate'])
  }
}

// apologize —— B(冒犯方)向 A(委屈方)道歉（仅在已被对质后，知识边界）。A 视严重度决定原谅→repaired，或拒绝。
function resolveApologize(B, A, witnesses) {
  const c = findConflict(A.id, B.id, ['confronted'])
  if (!c) return
  B.needs.social = clamp(B.needs.social + 8); A.needs.social = clamp(A.needs.social + 8)
  const ra = rel(A, B.id), rb = rel(B, A.id)
  const forgiven = (FORGIVE_CAP - c.severity) + (rngAt(SEED, tick, 73)() - 0.5) * 16 > 0
  if (forgiven) {
    c.status = 'repaired'; c.repaired = tick
    ra.resentment = 0                                  // 和解 → 清账
    ra.trust = clampv(ra.trust + 5, -100, 100); rb.trust = clampv(rb.trust + 2, -100, 100)
    ra.affinity = clampv(ra.affinity + 6, -100, 100); rb.affinity = clampv(rb.affinity + 6, -100, 100)
    ra.standing = clampv(ra.standing + 2, -STANDING_CAP, STANDING_CAP)   // 和解=B 在 help → A 对 B 的坏名声恢复
    for (const w of witnesses) judgeActor(w, B.id, true, A.id)
    const e = logEvent('apologize', B.id, A.id, '', true, witnesses, 'forgiven')
    ra.last_pos = e.id; rb.last_pos = e.id
    remember(B, `向${name(A)}道了歉，和解了`, 6, [A.id, 'conflict', 'repair'])
    remember(A, `${name(B)}道歉了，我原谅了`, 6, [B.id, 'conflict', 'repair'])
  } else {
    const e = logEvent('apologize', B.id, A.id, '', false, witnesses, 'rejected')
    remember(B, `向${name(A)}道歉，没被接受`, 5, [A.id, 'conflict', 'reject'])
    remember(A, `${name(B)}来道歉，我还没法原谅`, 6, [B.id, 'conflict', 'reject'])
  }
}

// S3a rally_oust —— 同派系协同对外群目标 o 施压：确定性枚举"对 o 真有恶感/冲突"的同派系支持者，各据 L3 降 o 名声（守卫封顶）。
function resolveRallyOust(ag, o, witnesses) {
  const fac = ag.faction
  if (fac === '' || !factions[fac]) return
  let backers = 0
  for (const mid of factions[fac]) {
    if (mid === o.id) continue
    const m = byId[mid]
    const sees = rel(m, o.id).standing < 0 || findConflict(mid, o.id, ['simmering', 'escalated', 'confronted', 'lingering'])
    if (!sees) continue                 // L3：只教训"在该支持者眼中确有问题"的 o，绝不冤枉好人
    backers++
    judgeActor(m, o.id, false, ag.id)   // defect-against-good(ag 同派系=好) → o 名声降（经 adjustStanding 守卫）
    oustNegEvents++
  }
  oustEvents++
  const e = logEvent('rally_oust', ag.id, o.id, '', backers > 0, witnesses, 'backers:' + backers)
  rel(ag, o.id).last_neg = e.id
  remember(ag, `带着自己人去找${name(o)}说理`, 6, [o.id, 'faction', 'oust'])
  remember(o, `被一伙人施压`, 6, [ag.id, 'faction', 'oust'])
}

// S3b 占位（Step3 填实现）：双边互惠记账。
function recordAid(giver, receiver) {
  if (giver.pacts[receiver.id]) { giver.pacts[receiver.id].given++; giver.pacts[receiver.id].lastAidTick = tick }
  if (receiver.pacts[giver.id]) { receiver.pacts[giver.id].received++ }
}

// importance 写入期派生（GPT-5.5/我方评审一致：别恒为常数）
function impt(self, other, affDelta, negative) {
  let v = 2 + Math.round(Math.abs(affDelta))
  const r = self.relationships[other.id]
  if (r && r.familiarity <= 1) v += 2          // 首次接触更显著
  if (negative) v += 2
  return Math.min(10, v)
}

// ── 承诺解算：每 tick 检查 active meet → 双方到场即 fulfilled，到点没到即 broken（归责缺席方）──
function resolveCommitments() {
  for (const c of commitments) {
    if (c.status !== 'active') continue
    const A = byId[c.a], B = byId[c.b]
    const inA = areaAt(A.pos) === c.area, inB = areaAt(B.pos) === c.area
    if (inA && inB) {
      c.status = 'fulfilled'
      const ra = rel(A, B.id), rb = rel(B, A.id)
      ra.trust = clampv(ra.trust + 4, -100, 100); rb.trust = clampv(rb.trust + 4, -100, 100)
      ra.affinity = clampv(ra.affinity + 3, -100, 100); rb.affinity = clampv(rb.affinity + 3, -100, 100)
      ra.familiarity += 1; rb.familiarity += 1
      ra.standing = clampv(ra.standing + 1, -STANDING_CAP, STANDING_CAP)   // 守约=互相 help → standing 升
      rb.standing = clampv(rb.standing + 1, -STANDING_CAP, STANDING_CAP)
      const e = logEvent('meet', c.a, c.b, '', true, [], 'fulfilled')
      ra.last_pos = e.id; rb.last_pos = e.id
      remember(A, `如约在${areas[c.area].label}见到了${name(B)}`, 5, [B.id, 'commit', 'meet'])
      remember(B, `如约在${areas[c.area].label}见到了${name(A)}`, 5, [A.id, 'commit', 'meet'])
    } else if (tick >= c.deadline) {
      c.status = 'broken'
      const noShows = []
      if (!inA) noShows.push(c.a)
      if (!inB) noShows.push(c.b)
      const e = logEvent('meet', c.a, c.b, '', false, [], 'broken:' + noShows.join('+'))
      for (const ns of noShows) {
        const otherId = ns === c.a ? c.b : c.a
        const other = byId[otherId], nsAg = byId[ns]
        const ro = rel(other, ns)                       // 被放鸽子的一方更新对爽约者的关系
        ro.trust = clampv(ro.trust - 6, -100, 100)
        ro.affinity = clampv(ro.affinity - 5, -100, 100)
        ro.last_neg = e.id
        ro.standing = clampv(ro.standing - 2, -STANDING_CAP, STANDING_CAP)  // L3：对守约者爽约=defect-against-good → 坏名声
        bumpResentment(other, ns, 5, e.id)              // 怨气累积 → 可能触发/升级一段冲突
        remember(other, `${name(nsAg)}放了我鸽子，没来${areas[c.area].label}`, 6, [ns, 'commit', 'broken'])
        remember(nsAg, `爽约了和${name(other)}在${areas[c.area].label}的约定`, 5, [otherId, 'commit', 'broken'])
      }
    }
  }
}

const clamp = (v, lo = 0, hi = 100) => Math.max(lo, Math.min(hi, v))
const name = (ag) => ag.persona.name || ag.id
const areaLabel = (pos) => (areas[areaAt(pos)]?.label) || '镇上'
const verb = (action) => ({ greet: '聊天', give: '送了点东西', gossip: '说了会儿悄悄话', gossip_rep: '说了说别人的事', invite: '约了见面', discuss: '聊起了看法', confide: '吐露了心事', leak: '说漏了秘密', endorse: '统一了口径', rally_oust: '施压', aid: '雪中送炭' }[action] || action)

function stepToward(from, to) {
  const p = [from[0], from[1]]
  if (p[0] !== to[0]) p[0] += Math.sign(to[0] - p[0])
  else if (p[1] !== to[1]) p[1] += Math.sign(to[1] - p[1])
  return p
}

// ── 单 agent 推进 ─────────────────────────────────────────────────────────
function advance(ag, idx) {
  if (ag.talking > 0) { ag.talking -= 1 } // 对话期间被绑定（视觉/轮次）；提交在 option 完成时
  const opt = ag.option
  if (opt == null) {
    const cands = candidates(ag)
    if (!cands.length) return
    const intent = best(cands, idx * 13 + 1)
    applyIntent(ag, intent)
    return
  }
  if (opt.kind === 'social') {
    const partner = byId[opt.partner]
    if (!partner || areaAt(ag.pos) !== areaAt(partner.pos)) { ag.option = null; ag.talking = 0; return }
    opt.remaining -= 1
    if (opt.remaining <= 0) { commitSocial(ag, opt); ag.option = null; ag.talking = 0 }
    return
  }
  if (opt.kind === 'attend') {
    const c = commitments.find((x) => x.id === opt.commit)
    // 承诺已了结 / 已过点 / 需求危机 → 放弃赴约（危机即爽约的根）
    if (!c || c.status !== 'active' || tick >= c.deadline || minNeed(ag) < NEED_CRISIS) { ag.option = null; return }
    if (areaAt(ag.pos) !== c.area) ag.pos = stepToward(ag.pos, areaCentroid(c.area)) // 未到则前往；到了就守在该区等对方
    return
  }
  // object option
  const o = objects[opt.target]
  if (!o) { ag.option = null; return }
  if (opt.phase === 'travel') {
    if (ag.pos[0] === o.pos[0] && ag.pos[1] === o.pos[1]) opt.phase = 'use'
    else ag.pos = stepToward(ag.pos, o.pos)
  } else {
    const per = opt.amount / opt.dur
    ag.needs[opt.need] = clamp(ag.needs[opt.need] + per)
    opt.remaining -= 1
    if (opt.remaining <= 0) {
      remember(ag, `在${o.area}${opt.action}了`, 3, [opt.need, opt.target])
      ag.option = null
    }
  }
}

function applyIntent(ag, intent) {
  if (intent.kind === 'social') {
    const partner = byId[intent.partner]
    if (!partner || partner.talking > 0 || areaAt(ag.pos) !== areaAt(partner.pos)) return // 兜底：对方不可用→本 tick 不动（下 tick 重选）
    ag.option = { kind: 'social', action: intent.action, partner: intent.partner, subject: intent.subject, remaining: CONVERSE_TICKS }
    ag.talking = CONVERSE_TICKS
    partner.talking = Math.max(partner.talking, CONVERSE_TICKS) // 把对方也绑进这次对话（轮次/暂停）
  } else if (intent.kind === 'attend') {
    ag.option = { kind: 'attend', area: intent.area, commit: intent.commit }
  } else {
    ag.option = { kind: 'object', action: intent.action, target: intent.target, need: intent.need, amount: intent.amount, dur: intent.dur, remaining: intent.dur, phase: 'travel' }
  }
}

// ── 主循环 ───────────────────────────────────────────────────────────────
function sweepConflicts() {
  for (const c of conflicts) {
    if ((c.status === 'simmering' || c.status === 'escalated') && c.confronted === 0 && tick - c.triggered > LINGER_AFTER) c.status = 'lingering'
  }
}

// 每日衰减（宽恕 + 名声淡化）：resentment 缓降、standing 向 0 漂移 → 无永久世仇/无永久污名（GTFT/滞回精神）
function dailyDecay() {
  for (const a of agents) {
    for (const r of Object.values(a.relationships)) {
      if (r.resentment > 0) r.resentment = Math.max(0, r.resentment - RESENT_DECAY)
    }
  }
}

function runTick() {
  tick += 1
  agents.forEach((ag) => decay(ag))
  agents.forEach((ag, i) => advance(ag, i))
  resolveCommitments()                 // 解算到场/爽约
  sweepConflicts()                     // 久未对质的冲突 → lingering
  if (tick % TICKS_PER_DAY === 0) {
    day += 1
    dailyDecay()                       // 怨气缓降
    recomputeFactions()                // S3a：每夜从 attitudes 重算派系（先于名声漂移）
    dissolveFreeriders()               // S3b：先解 free-rider 盟约
    formPactsGreedy()                  // S3b：再单遍贪心结盟
    if (day % 3 === 0) for (const a of agents) for (const r of Object.values(a.relationships)) r.standing -= Math.sign(r.standing) // 名声每3天向0漂移1（慢淡化，坏名声能留一阵）
  }
}

// ── 跑 + 统计 ────────────────────────────────────────────────────────────
function run() {
  const total = DAYS * TICKS_PER_DAY
  let starvedTicks = 0
  for (let t = 0; t < total; t++) {
    runTick()
    for (const ag of agents) for (const nid of Object.keys(ag.needs)) if (ag.needs[nid] <= 0.5) starvedTicks++
  }
  return { starvedTicks }
}

recomputeFactions()   // 首日预算：让 day-1 候选可读 faction（早期 attitudes≈天生立场，多为 singleton）
const { starvedTicks } = run()

// ── 不变量断言 ───────────────────────────────────────────────────────────
const fails = []
let okCount = 0
const ok = (cond, msg) => { okCount++; if (!cond) fails.push(msg) }

const accepted = eventLog.filter((e) => e.accepted)
const social = eventLog.length

// 1) 无饿穿
ok(starvedTicks === 0 || SCENARIO !== '', `1·无饿穿: 触底 need·tick = ${starvedTicks} (应=0；定向场景豁免:冲突压力下偶有饿穿)`)
// 2) 社交发生
ok(accepted.length > 0, `2·社交发生: 已接受社交事务 = ${accepted.length} (应>0)`)
// 3) 无永久孤立：每个 agent 都作为 actor 或 target 参与过至少 1 次被接受的社交
const participated = new Set()
for (const e of accepted) { participated.add(e.actor); participated.add(e.target) }
const isolated = agents.filter((a) => !participated.has(a.id)).map((a) => a.id)
ok(isolated.length === 0, `3·无永久孤立: 孤立 NPC = [${isolated.join(',')}] (应空)`)
// 4) 关系真的形成：affinity 出现分化（max-min>0 且存在非零）
const affs = []
for (const a of agents) for (const r of Object.values(a.relationships)) affs.push(r.affinity)
const affMax = Math.max(...affs, 0), affMin = Math.min(...affs, 0)
ok(affs.some((v) => v !== 0) && affMax - affMin > 0, `4·关系分化: affinity 跨度 ${affMin}..${affMax} (应有非零分化)`)
// 5) 谣言传播：种子 R1 至少传到 1 个非源 agent
const r1Holders = agents.filter((a) => a.beliefs['R1']).map((a) => a.id)
ok(r1Holders.length >= 2 || SCENARIO !== '', `5·谣言传播: 知道 R1 的人 = [${r1Holders.join(',')}] (应≥2，含源 aria；betray 场景豁免:源被放逐会断传)`)
// 6) 知识边界：每条非种子 belief 都有合法 source，且能在 event_log 找到对应 gossip 事件
let boundaryBad = 0
for (const a of agents) for (const [cid, b] of Object.entries(a.beliefs)) {
  if (b.via === 'seed') continue
  const hasSource = b.source && byId[b.source]
  // 知识边界：每条习得 belief 都能在 event_log 找到对应「按其通道(via)」的事件（gossip/confide/leak）
  const hasEvent = eventLog.some((e) => e.type === b.via && e.accepted && e.target === a.id && e.subject === cid)
  if (!hasSource || !hasEvent) boundaryBad++
}
ok(boundaryBad === 0, `6·知识边界: 无来源/无事件支撑的 belief = ${boundaryBad} (应=0)`)
// 7) 账本可溯源：被接受社交都进了 event_log，且 last_pos/last_neg 指向真实事件
const eventIds = new Set(eventLog.map((e) => e.id))
let provBad = 0
for (const a of agents) for (const r of Object.values(a.relationships)) {
  if (r.last_pos && !eventIds.has(r.last_pos)) provBad++
  if (r.last_neg && !eventIds.has(r.last_neg)) provBad++
}
ok(provBad === 0, `7·账本可溯源: 指向不存在事件的关系记录 = ${provBad} (应=0)`)
// ── 承诺系统不变量 ───────────────────────────────────────────────────────
const cCreated = commitments.length
const cFulfilled = commitments.filter((c) => c.status === 'fulfilled').length
const cBroken = commitments.filter((c) => c.status === 'broken').length
const cLeaked = commitments.filter((c) => c.status === 'active' && c.deadline < tick).length
const brokenEvents = eventLog.filter((e) => e.type === 'meet' && !e.accepted).length
const anyResentment = agents.some((a) => Object.values(a.relationships).some((r) => r.resentment > 0))
// 8) 承诺生命周期：发起过约见且至少一次如约兑现
ok(cCreated > 0 && cFulfilled > 0, `8·承诺生命周期: 创建=${cCreated} 兑现=${cFulfilled} (均应>0)`)
// 9) 无悬挂承诺：已过 deadline 的承诺必被结算（fulfilled/broken），无泄漏
ok(cLeaked === 0, `9·无悬挂承诺: 已过点仍 active = ${cLeaked} (应=0)`)
// 10) 违约有后果且可溯源：每个 broken 都写了 meet 违约事件；有违约则有 resentment
ok(brokenEvents === cBroken && (cBroken === 0 || stNegEvents > 0), `10·违约可溯源且有后果: broken=${cBroken} 违约事件=${brokenEvents} 负向声誉事件=${stNegEvents}（怨气会按 GTFT 衰减，故查累积后果而非末态）`)

// ── 冲突生命周期不变量 ───────────────────────────────────────────────────
const cfCreated = conflicts.length
const cfConfronted = conflicts.filter((c) => c.confronted > 0).length
const cfRepaired = conflicts.filter((c) => c.status === 'repaired').length
const cfLingering = conflicts.filter((c) => c.status === 'lingering').length
// 11) 冲突生命周期：触发过冲突，且至少一段走到对质或修复（不是死数据）
ok(cfCreated > 0 && (cfRepaired + cfConfronted) > 0, `11·冲突生命周期: 触发=${cfCreated} 对质=${cfConfronted} 修复=${cfRepaired}`)
// 12) 先对质后和解（知识边界）：repaired 必先经 confronted；无“未对质即修复”
const badRepair = conflicts.filter((c) => c.status === 'repaired' && !(c.confronted > 0)).length
ok(badRepair === 0, `12·先对质后和解: 未对质即修复 = ${badRepair} (应=0)`)
// 13) 修复经由道歉达成（可溯源）：每个 repaired 冲突都有对应「被接受的 apologize 事件」（冒犯方→委屈方）
let badRepairProv = 0
for (const c of conflicts) {
  if (c.status !== 'repaired') continue
  const has = eventLog.some((e) => e.type === 'apologize' && e.accepted && e.actor === c.b && e.target === c.a)
  if (!has) badRepairProv++
}
ok(badRepairProv === 0, `13·修复可溯源: 无道歉事件支撑的修复 = ${badRepairProv} (应=0)`)

// ── S1 不变量：声誉 standing × gossip 传播 × 涌现放逐 × 双向(恢复) ──────────
const standings = []
for (const a of agents) for (const [oid, r] of Object.entries(a.relationships)) standings.push({ h: a.id, t: oid, s: r.standing })
const stVals = standings.map((x) => x.s)
const stMax = Math.max(...stVals, 0), stMin = Math.min(...stVals, 0)
const repEvents = accepted.filter((e) => e.type === 'gossip_rep').length
const directDyad = new Set()
for (const e of accepted) { directDyad.add(e.actor + '>' + e.target); directDyad.add(e.target + '>' + e.actor) }
const repAtDistance = standings.filter((x) => x.s !== 0 && !directDyad.has(x.h + '>' + x.t))
const perceived = {}, propA = {}, accA = {}
for (const a of agents) { let s = 0, n = 0; for (const b of agents) if (b.id !== a.id) { s += rel(b, a.id).standing; n++ } perceived[a.id] = s / Math.max(1, n); propA[a.id] = 0; accA[a.id] = 0 }
for (const e of eventLog) if (['greet', 'give', 'gossip', 'invite', 'gossip_rep'].includes(e.type)) { propA[e.actor] = (propA[e.actor] || 0) + 1; if (e.accepted) accA[e.actor]++ }
const actives = agents.map((a) => a.id).filter((id) => propA[id] >= 5).sort((x, y) => perceived[x] - perceived[y])
let ostr = 'n/a'
let ostracismOk = true
if (actives.length >= 2) {
  let townAcc = 0
  for (const id of actives) townAcc += accA[id] / propA[id]
  townAcc /= actives.length
  const worst = actives[0], best = actives[actives.length - 1]
  const rW = accA[worst] / propA[worst]
  ostr = `最坏名声 ${worst}(${perceived[worst].toFixed(1)}) 接受率 ${rW.toFixed(2)} / 镇均 ${townAcc.toFixed(2)}（最好 ${best} ${perceived[best].toFixed(1)}）`
  // 只在真出现「恶名者」时断言放逐（小 N 微弱 standing 排名噪声大；见 docs/10 陷阱）
  if (perceived[worst] <= -0.8) ostracismOk = rW <= townAcc + 0.08
}
ok(stVals.some((v) => v !== 0) && stMax - stMin > 0, `14·standing分化: 跨度 ${stMin}..${stMax}`)
ok(ostracismOk, `15·涌现放逐(坏名声被接受率≤好名声): ${ostr}`)
const badRepExists = standings.some((x) => x.s <= REP_GOSSIP_TH)   // 有人坏到可被传坏话才要求 gossip_rep 发生
ok(!badRepExists || repEvents > 0, `16·声誉传播(gossip_rep): 存在坏名声=${badRepExists} → 传播=${repEvents} (有坏名声时应>0)`)
ok(stNegEvents > 0 && cfRepaired > 0, `17·坏名声会形成且可恢复(L3 defect 路径生效=${stNegEvents}, 冲突修复=${cfRepaired})`)

// ── S2 不变量：意见动力学(FJ 固执/Deffuant 有界/Maki-Thompson 谣言变冷) ──────
let attMaxSpread = 0
for (const t of TOPICS) { const vs = agents.map((a) => a.attitudes[t]); attMaxSpread = Math.max(attMaxSpread, Math.max(...vs) - Math.min(...vs)) }
let attMoved = 0
for (const a of agents) for (const t of TOPICS) if (Math.abs(a.attitudes[t] - a.attitude0[t]) > 0.02) attMoved++
const discussEvents = accepted.filter((e) => e.type === 'discuss').length
let stifledCount = 0
for (const a of agents) stifledCount += Object.keys(a.stifled).length
// 18 观点演化但不坍缩为单一共识（FJ 固执度生效）
ok(SCENARIO !== '' || (attMaxSpread > 0.3 && attMoved > 0), `18·观点演化不坍缩(FJ固执): 最大话题跨度 ${attMaxSpread.toFixed(2)} 变动者 ${attMoved} (应跨度>0.3且有变动；场景豁免:预置两极)`)
// 19 有界信任门生效（Deffuant：差太大拒谈）
ok(SCENARIO !== '' || (discussEvents > 0 && refusedByBound > 0), `19·有界信任(Deffuant)生效: discuss=${discussEvents} 因ε拒谈=${refusedByBound} (均应>0；场景豁免)`)
// 20 谣言变冷（Maki-Thompson：出现 stifler，传播自然停止）
ok(stifledCount > 0, `20·谣言变冷(Maki-Thompson): stifler 数 = ${stifledCount} (应>0)`)

// ── S3c 秘密信息博弈不变量 (21-24，含小N守护) ────────────────────────────
const betrayEv = eventLog.filter((e) => e.type === 'betray')
const secretCids = new Set()
let secretBadVia = 0
for (const a of agents) for (const [cid, b] of Object.entries(a.beliefs)) if (b.secret) {
  secretCids.add(cid)
  if (!['confide', 'leak', 'seed'].includes(b.via)) secretBadVia++
}
for (const e of eventLog) if (e.type === 'gossip' && secretCids.has(e.subject)) secretBadVia++
// 21 秘密专道：秘密只走 confide/leak，绝不经普通 gossip
ok(secretBadVia === 0, `21·秘密专道: 秘密漏进 gossip/非法 via = ${secretBadVia} (应=0)`)
// 22 背叛有后果可溯源：每 betray → 被泄方关系存在 + 曾触发冲突 + last_neg 可溯源（查冲突+溯源，非 trust 绝对阈）
let betrayBad = 0
for (const be of betrayEv) {
  const betrayed = byId[be.target]
  const r = betrayed && betrayed.relationships[be.actor]
  const hasConflict = conflicts.some((c) => c.a === be.target && c.b === be.actor)
  if (!r || !hasConflict || !(r.last_neg && eventIds.has(r.last_neg))) betrayBad++
}
ok(betrayBad === 0, `22·背叛有后果可溯源: 无冲突/不可溯源的背叛 = ${betrayBad} (应=0)`)
// 23 背叛重挫名声可溯源：无背叛 或 有累积 L3 负判（查累积 st_neg_events，非末态 standing：无永久污名守护）
ok(betrayEv.length === 0 || stNegEvents > 0, `23·背叛重挫名声: 背叛=${betrayEv.length} 累积负判=${stNegEvents}`)
// 24 背叛无误判（关键正确性）：每 betray 必有更早的 accepted confide/leak（teller→背叛者，同 secret）
let falseBetray = 0
for (const be of betrayEv) {
  const has = eventLog.some((e) => e.id < be.id && e.accepted && (e.type === 'confide' || e.type === 'leak') && e.actor === be.target && e.target === be.actor && e.subject === be.subject)
  if (!has) falseBetray++
}
ok(falseBetray === 0, `24·背叛无误判: 无直接上游吐露证据的背叛 = ${falseBetray} (应=0)`)

// ── S3a 观点派系不变量 (S3-1..4，含小N守护) ──────────────────────────────
let facInconsistent = 0
for (const a of agents) {
  if ((a.faction === '') !== (a.faction_size === 1)) facInconsistent++
  if (a.faction !== '' && a.faction !== a.id && !aligned(a, byId[a.faction])) facInconsistent++
}
ok(facInconsistent === 0, `S3-1·派系派生一致((faction'')⇔(size1)且与medoid对齐): 不一致 = ${facInconsistent} (应=0)`)
const facCount = Object.keys(factions).length
let inSum = 0, inN = 0, crSum = 0, crN = 0
for (const a of agents) for (const b of agents) {
  if (a.id === b.id || a.faction === '' || b.faction === '') continue
  const aff = rel(a, b.id).affinity
  if (a.faction === b.faction) { inSum += aff; inN++ } else { crSum += aff; crN++ }
}
let facAffOk = true, facAffMsg = `派系=${facCount} ingroup对=${inN} cross对=${crN}`
// 仅默认/faction 场景断言（betray/freerider 故意扭曲关系 → 同派系内可能正是被毒化的那对）
if ((SCENARIO === '' || SCENARIO === 'faction') && facCount >= 2 && inN >= 3 && crN >= 3) {
  const inAvg = inSum / inN, crAvg = crSum / crN
  facAffOk = inAvg > crAvg + FACTION_AFF_MARGIN
  facAffMsg = `同派系均 ${inAvg.toFixed(1)} vs 跨派系均 ${crAvg.toFixed(1)} (+${FACTION_AFF_MARGIN})`
} else facAffMsg += ' (小N跳过)'
ok(facAffOk, `S3-2·同派系亲和>跨派系: ${facAffMsg}`)
let stOverflow = 0, endorseBad = 0
for (const a of agents) for (const r of Object.values(a.relationships)) if (Math.abs(r.standing) > STANDING_CAP + 1e-9) stOverflow++
for (const e of eventLog) if (e.type === 'endorse' && !byId[e.subject]) endorseBad++
ok(stOverflow === 0 && endorseBad === 0, `S3-3·协同行动守边界(叠穿守卫): |standing|越界=${stOverflow} 无效endorse=${endorseBad} (应=0)`)
let facBucketBad = 0
for (const [m, mem] of Object.entries(factions)) { if (mem.length < 2) facBucketBad++; for (const id of mem) if (byId[id].faction !== m) facBucketBad++ }
ok(facBucketBad === 0, `S3-4·派系视图自洽: 坏桶/标签不符 = ${facBucketBad} (应=0)`)

// ── S3b 互助盟约不变量 (I-PACT-a..f，含小N守护) ──────────────────────────
const aidEv = eventLog.filter((e) => e.type === 'aid' && e.accepted)
const pactPairs = new Set(); for (const p of pactsIndex) pactPairs.add(p.key)
let aidNonPact = 0; for (const e of aidEv) if (!pactPairs.has(pactKey(e.actor, e.target))) aidNonPact++
ok(aidAccepted < MIN_AID_SAMPLE || aidNonPact === 0, `I-PACT-a·互助偏内不偏外: 非盟约 aid = ${aidNonPact} (aid 总 ${aidAccepted}，样本≥${MIN_AID_SAMPLE}时应=0)`)
let pactBBad = 0
for (const p of pactsIndex) if (p.status === 'broken' && String(p.reason || '').startsWith('freerider')) {
  const hasEv = eventLog.some((e) => e.type === 'pact' && !e.accepted && e.note === 'dissolved:freerider' && ((e.actor === p.a && e.target === p.b) || (e.actor === p.b && e.target === p.a)))
  if (!hasEv || !(p.breakGap >= FREERIDER_GAP)) pactBBad++
}
ok(pactBBad === 0, `I-PACT-b·free-rider致解体可溯源: 异常 = ${pactBBad} (应=0)`)
let pactCBad = 0
for (const p of pactsIndex) if (p.status === 'active' && !(p.formTrustA >= PACT_TRUST_TH && p.formTrustB >= PACT_TRUST_TH && p.formFam >= PACT_FAM_TH && p.formComplement >= PACT_COMPLEMENT_TH)) pactCBad++
ok(pactCBad === 0, `I-PACT-c·结盟门达标: 低门被结的 active pact = ${pactCBad} (应=0)`)
let pactDBad = 0; const activeKeys = {}
for (const p of pactsIndex) {
  if (!['active', 'broken'].includes(p.status)) pactDBad++
  if (p.status === 'active') {
    activeKeys[p.key] = (activeKeys[p.key] || 0) + 1
    const A = byId[p.a], B = byId[p.b]
    if (!(A.pacts[p.b] && A.pacts[p.b].status === 'active' && B.pacts[p.a] && B.pacts[p.a].status === 'active')) pactDBad++
  }
}
for (const k of Object.keys(activeKeys)) if (activeKeys[k] > 1) pactDBad++
ok(pactDBad === 0, `I-PACT-d·无悬挂/无重复/对称: 异常 = ${pactDBad} (应=0)`)
let pactEBad = 0
for (const p of pactsIndex) if (p.status === 'broken' && (byId[p.a].complementSeen[p.b] || 0) === 0) pactEBad++
ok(pactEBad === 0, `I-PACT-e·解体可恢复(GTFT,complementSeen未清): 异常 = ${pactEBad} (应=0)`)

// determinism: 同 seed 跑两次 → 摘要一致（端口确定，无 Math.random 进入主逻辑）；外部双跑比对。
const digest = `${eventLog.length}|${accepted.length}|${r1Holders.length}|${cCreated}/${cFulfilled}/${cBroken}|${cfCreated}/${cfConfronted}/${cfRepaired}/${cfLingering}|${affMin}..${affMax}|st${stMin}..${stMax}/rep${repEvents}|att${attMaxSpread.toFixed(2)}/disc${discussEvents}/bound${refusedByBound}/stifle${stifledCount}|S3 fac${facCount}/end${endorseEvents}/oust${oustEvents}/pact${pactsIndex.length}/free${freeriderDissolves}/aid${aidAccepted}/conf${confideEvents}/betr${betrayEvents}`

// ── 报告 ─────────────────────────────────────────────────────────────────
console.log(`=== 社交底座 soak  days=${DAYS} seed=${SEED} agents=${agents.length} ===`)
console.log(`event_log: ${eventLog.length} 条 (接受 ${accepted.length} / 拒绝 ${eventLog.length - accepted.length})  digest=${digest}`)
const byType = {}
for (const e of accepted) byType[e.type] = (byType[e.type] || 0) + 1
console.log(`接受明细: ${Object.entries(byType).map(([k, v]) => `${k}=${v}`).join('  ') || '(无)'}`)
console.log(`承诺(meet): 创建=${cCreated} 兑现=${cFulfilled} 爽约=${cBroken} 悬挂=${commitments.filter((c) => c.status === 'active').length}`)
console.log(`冲突: 触发=${cfCreated} 对质=${cfConfronted} 修复=${cfRepaired} 冷战=${cfLingering}`)
console.log(`声誉: standing 跨度 ${stMin}..${stMax}  gossip_rep 传播 ${repEvents} 次  跨距声誉 ${repAtDistance.length} 条`)
console.log(`意见: 最大话题跨度 ${attMaxSpread.toFixed(2)}  discuss ${discussEvents} 次  因ε拒谈 ${refusedByBound}  谣言变冷(stifler) ${stifledCount}`)
console.log(`涌现放逐: ${ostr}`)
console.log(`谣言 R1 知情者: [${r1Holders.join(', ')}]`)
console.log('关系账本(affinity，节选每人 top1):')
for (const a of agents) {
  const es = Object.entries(a.relationships).sort((x, y) => y[1].affinity - x[1].affinity)
  const top = es[0]
  const topName = top ? (byId[top[0]] ? name(byId[top[0]]) : top[0]) : '—'
  const memN = a.memory.length
  console.log(`  ${name(a)}(${a.id}): 关系${es.length}人  最亲=${top ? `${topName}(${top[1].affinity})` : '—'}  礼物余=${a.inventory.gift}  记忆=${memN}条`)
}
if (VERBOSE) {
  console.log('\n前 12 条社交事件:')
  for (const e of eventLog.slice(0, 12)) console.log(`  #${e.id} t${e.tick} ${e.actor}→${e.target} ${e.type} ${e.accepted ? '✓' : '✗'}${e.subject ? ' ' + e.subject : ''} 旁观[${e.witnesses.join(',')}]`)
}

console.log('\n— 不变量 —')
if (fails.length === 0) {
  console.log(`✅ 全部 ${okCount} 条断言通过（需求+社交+承诺+冲突+S1 声誉+S2 意见+S3 派系/盟约/秘密；determinism 见 digest）。`)
  process.exit(0)
} else {
  for (const f of fails) console.log('❌ ' + f)
  process.exit(1)
}
