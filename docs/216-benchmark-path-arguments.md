# 216 · 基准命令缺路径时立即报错

2026-09-18。接续 [215](215-p4c8-creperie-seller.md) §四记录的真实问题。

`--bake-golden` / `--bake-anchor` 缺少路径时，旧解析器忽略该选项，
继续跑比较或普通模拟。结果看起来像行为回归，实际没有烘任何锚。
如果下一个参数是 `--days`，旧解析器还会把它当成输出路径。

现在 Harness、DetGate、ModelPathGate 在运行基准、打开输出文件之前，
共同检查路径参数。缺值、空白值、下一个选项充当值都会打印
`<gate> CLI: FAIL: <flag> requires a non-empty path argument` 并请求退出码 2。
Windows Godot 的退出码存在历史差异，所以自动检查同时要求明确的失败行，
并确认没有进入基准主体。正常命令仍必须显式提供路径；不默认覆盖提交中的锚。

同样保护 Harness 的 `--shadow-dump`、`--chain-dump`、`--chain-ref`，
以及三个入口的 `--golden` / `--anchor`。

## 验证

```sh
godot --headless --path game --import
python tools/test_bench_args.py --godot godot
python tools/assert_ci_lanes.py
```

- 27 个真实入口的非法参数组合：末尾缺值、后接选项、全空白值。
- 29 个正常解析对照：相对路径、`res://`、`user://`、含空格的绝对路径、没有路径选项。
- 检查两份提交锚的 SHA-256 没有改变。
- 已接入 `tools/ci.sh` 的 lint lane，第 3a 步，在 import 后运行。
- 本机 Godot 4.6.2 import、上述参数测试和 CI lane 对账通过。
- 负对照：临时让路径校验恒返回通过，真实 Harness 入口的测试立即失败；随后按字节恢复校验文件。
- 未跑完整社会模拟网格；本次没有修改模拟逻辑、数据或重烘锚。

## 接手后的下一步

先追踪 [214](214-two-negatives-catch-and-exports.md) 留下的糕点 seed 24 供给问题，
区分出勤不足与消耗压力，再推进 [194](194-town-economy-and-society-design.md) 的后续相位。
不把历史 N=40 的硬红继续当作现状，也不把单个种子的改善归因于机制。

用户指定后续新美术使用 **PixelLab MCP**。已验证安装的 PixelLab 插件能够认证并列出
map object、character、tileset、building kit 工具；继续沿用
[183](183-pixellab-seaside-props.md) 的原生像素尺寸与入库流程。
本次没有生成或替换美术。
