# Living Town 周期性主仓评审

本目录记录 `living-town` 的周期性、对抗性进展复核。报告分支是
`codex/main-repo-review`；评审以 `origin/integration/batons` 为主基线，同时检查
本地 Narrative、Narrative Lab 和尚未集成的 agent worktree。

规则：

- 每次先 `git fetch origin --prune`，报告具体 commit，不以分支名代替版本。
- 源分支与 `master` 只读；这里只提交报告和报告索引。
- “测试绿”只证明实际运行命令覆盖到的范围；计划、preflight 和旧构建观察不得写成实现完成。
- 每轮保留一份带时区的不可变快照，并更新下方链接。

## 最新报告

- [2026-08-06 21:00 CST：47-commit 实质跃迁、AE2 假绿通道与 AG3 实施路线](reviews/2026-08-06-2100-cst.md)
- [2026-08-06 07:22 CST](reviews/2026-08-06-0722-cst.md)
- [08:02–09:00 CST 附录：#43 合入、合同缺口与 PR/CI 闭环](addenda/2026-08-06-0802-cst.md)

## 历史报告

- [2026-08-06 08:02–09:00 CST](addenda/2026-08-06-0802-cst.md) — #43 运行时修复已合，但买家侧防线与 exact-head 收据仍有缺口；PR #5 两次被 15 分钟预算取消。
- [2026-08-06 07:22 CST](reviews/2026-08-06-0722-cst.md) — 建立周期评审分支；Integration 只有 docs/111 增量，AC1/AC2 新存为未验证 WIP，核心 gate 状态未变。
