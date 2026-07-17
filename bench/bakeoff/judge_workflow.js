export const meta = {
  name: 'decisive-blind-judge',
  description: 'Blind Claude pairwise judge: teacher-salient vs logic in-character decision on salient grievance cases',
  phases: [{ title: 'Judge' }],
}
// args = { tasks: [{tid,key,seed,orient,A_text,B_text,A_src,packet,...}] }
const TASKS = (args && args.tasks) ? args.tasks : []
log(`blind judge: ${TASKS.length} tasks (${TASKS.length/2} divergent cases x mirror-flip)`)

const VERDICT = {
  type: 'object', additionalProperties: false,
  properties: {
    choice: { enum: ['A', 'B', '平'], description: 'A / B / 平(旗鼓相当)' },
    reason: { type: 'string', description: '一句话理由' },
  },
  required: ['choice', 'reason'],
}

function prompt(t) {
  return `你是像素小镇里角色行为的独立评审。下面是一位【具体居民】此刻的完整处境，以及两个候选行动 A 和 B。
请判断：就这位居民此刻的性格、身份、心结与关系而言，A 与 B 哪一个更像【他/她本人此刻真会做、也更合适】的选择？

判据：
- 只看是否贴合这个具体的人此刻的性格与处境；
- 不要因为某个行动更戏剧化、更礼貌、更主动或更新奇就偏向它；
- 「心结」里的怨气数值低（远不到会翻脸的程度）时，未必非得当面理论——是否值得为这点小别扭去对质，正是要判断的；
- 「平」只在两者确实旗鼓相当、难分高下时才用。

【处境】
${t.packet}

【A】${t.A_text}
【B】${t.B_text}

给出裁决（choice = A / B / 平，reason = 一句话）。`
}

const verdicts = await parallel(TASKS.map(t => () =>
  agent(prompt(t), { label: `judge:${t.tid}`, phase: 'Judge', schema: VERDICT })
    .then(v => {
      if (!v) return null
      // generic: winner = the label of the chosen side (A_src / B_src), 平 → tie
      const winner = v.choice === '平' ? 'tie' : (v.choice === 'A' ? t.A_src : t.B_src)
      return {
        tid: t.tid, key: t.key, seed: t.seed, orient: t.orient,
        choice: v.choice, winner,
        status: t.status, severity: t.severity, persona: t.persona,
        reason: (v.reason || '').slice(0, 100),
      }
    })
))
const ok = verdicts.filter(Boolean)
// quick tally (final aggregation + cluster-bootstrap done in Python from this array)
const tally = { teacher: 0, logic: 0, tie: 0 }
for (const v of ok) tally[v.winner]++
log(`verdicts=${ok.length}/${TASKS.length}  raw tally: teacher=${tally.teacher} logic=${tally.logic} tie=${tally.tie}`)
return { verdicts: ok, tally }
