# P1-aa observatory plane authority

日期：2026-08-20
批次：观测室聊天与选择权限收口（单一 coherent integration batch）

## 目标与输入

最新 completed review（`9dff325`，REQUEST CHANGES）指出：货运观测室的 `C` 键仍可绕过只读语义，选择/程序化 focus 未统一按当前 `space/floor` 过滤；同一报告还列出无界历史扫描、evidence 工资字段和 readiness 授权绑定问题。本批只关闭前两项共享 authority blocker，不扩展到性能、文档或锚点。

最新 narrative integration packet 仍是 proposal/source，当前没有可消费的 runtime contract。逐项判定：

- ACCEPT：无；本批没有把 proposal 直接接入 runtime。
- REJECT：无；没有足够证据否定 narrative 内容本身。
- DEFER：全部 narrative runtime 接入，直到出现明确 consumer、save/UI/canon 契约与 focused test。

## 实现合同

- 玩家位于 `port_warehouse/1f` 时，真实 `KEY_C` 路径与直接 `_on_player_say` 调用均只留下明确的“货运观测室只读”反馈；不写聊天记忆、事件、Sim 状态或货运权威。
- `_focus_agent`、键盘循环选择和世界点击选择共用 `_agent_on_active_plane`；`space` 与 `floor` 任一不相等都拒绝，避免跨 plane 观察/控制。
- 非玩家 Probe 的演示聊天仍保留；本批不改变普通居民对话语义。

## 验证矩阵

固定容器 `living-town-visual:p1z`（Godot 4.6.2，已存在本地固定 digest；缺少 nobodywho 扩展的启动 warning 为已知 runner 限制）：

- `p1v_warehouse_observatory_test`：PASS；覆盖实际 C 键、直调聊天、跨 plane 点选与程序化 focus。
- `save_load_test`：PASS（0 fail）。
- `save_migration_test`：PASS（0 fail）。
- `player_touch_test`：PASS（0 fail）。
- `space_test`：PASS（0 fail）。

以上是 focused/integration evidence；本批没有新的 hosted visual receipt，也没有重烘 golden/modelpath/complement。

## 边界与下一步

未关闭的 review 项：projection 无界历史扫描、evidence card 的工资字段、readiness verifier 的密码学绑定；PR #6 继续 draft/不可合并。下一可调度 Beat 应是一个有真实玩家动作、反馈和持久后果的短纵切，或在不扩张框架的前提下为观测室 projection 加受限缓存并配 perf negative control。
