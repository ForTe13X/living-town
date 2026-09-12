# P1-ab observatory bounded history

日期：2026-08-20

## 单一目标

关闭 completed review 指出的观测室 projection 性能债：每次 redraw 不应按完整 `event_log` 长度重复扫描。只处理历史回执读取；不改变货运权威、聊天权限、证据文档或 anchor。

## 实现

- `_latest_cargo_unload_receipt` 只回看最近 1024 条事件。观测室是“近况”视图，不是全量审计器；超出窗口的旧回执不伪装成最新消息。
- `_cargo_unload_receipt_at` 按 append-only 事务合同只检查回执前最多两行，覆盖 `pay → stock → world` / `stock → world`，避免对每个 projection 再扫全历史。
- 增加 focused contract，固定上限并保留 paid/free exact-chain 负控。

## 验收与边界

使用固定 `living-town-visual:p1z`、Godot 4.6.2：P1-v、P1-b、P1-g、save/load、save migration、space 相关 integration loop 均通过；本批不产生 hosted visual receipt，不重烘 golden/modelpath/complement。该上限不证明全量历史查询能力；需要完整审计时仍应使用事件账本/专用工具，而不是玩家 redraw 路径。

Narrative packet 仍无当前 runtime consumer：ACCEPT=无，REJECT=无，DEFER=全部直接接入。
