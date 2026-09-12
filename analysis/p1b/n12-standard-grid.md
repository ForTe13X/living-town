# P1-b CargoManifest · standard N=12-core grid

- **用途**：P1-b CargoManifest kernel 的第一份完整标准网格证据，供后续 held-out、scale、golden/modelpath/complement 重烘门按需复用。
- **精确来源树**：`codex/p1a-takeover@fbbf6f0506500275292b6fe005f45b4f721cbe29`；运行前后 `HEAD` 相同、工作树 clean。该 commit 在采样时仅存在本地，`origin/codex/p1a-takeover` / draft PR #6 仍停在 `5fb2686`，不得写成 published CI receipt。
- **运行环境**：Windows / Godot `4.6.2.stable.official.71f334935`；默认 shipping 场景为 12 core + 1 logistics affiliate，生产池口径仍为 `12/12`。
- **命令**：`C:\Users\yp\.local\bin\godot.cmd --headless --path game --log-file $env:TEMP\p1b_n12_seeds1_12_60d.log --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3`
- **输出 / 验证**：exit `0`，`S0 GATE: PASS`；hard 全部 `12/12`，含 #44 import provenance `12/12`、#46 export atomicity `12/12`；soft 仅 seed 6 为 `[40]`，故 #40=`11/12`，满足 `>=11/12`。seed 6 首违为糕点满足率 `0.46`（98/211）、断供 `42/60` 天，`produce=127 / consume=337`。
- **活性 / 确定性**：17 个门控事件类全部发生；aid `102` 次、覆盖 `12/12`（门槛 `>=6`）；import `155`、export `49`、world_other `409`，三者均覆盖 `12/12`；批量 + 增量滚动 + 逐 tick 前缀链 `det 3/3`。无 `signal 11` / `FATAL` / `out of bounds`；只有退出时 `ObjectDB instances leaked` warning。
- **可复用位置**：本卡为 canonical 摘要；原始日志在 `C:\Users\yp\AppData\Local\Temp\p1b_n12_seeds1_12_60d.log`，标记 `generated/rebuildable`，可由上方命令和 commit 重建，不作为长期 tracked artifact。
- **来源 / 许可证**：项目自身 committed 仿真与测试输出；未复制外部代码或资产，无新增第三方许可证义务。
- **已知限制**：只覆盖标准 seeds 1–12；没有 `--golden`，不是 held-out 13–30、total-N 16/24/60、full CI、synthetic merge 或 exact integration-tip receipt。seed 6 的 #40 边缘失败必须进入 held-out/scale 对照，不能凭本卡授权重烘或合入。
