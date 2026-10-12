# 217 · P4c 当前基线复核：seed 24 的糕点红已经不在

> 触发：接续 P4c-8 后复核 [214](214-two-negatives-catch-and-exports.md) 与
> [215](215-p4c8-creperie-seller.md) 留下的「seed 24 糕点 0.43、尚未查」说法。
> 本文是 2026-09-18 对当前 `f204276` 树的补充；不改写两篇历史实验记录。

## 结果

这不是当前 bug。当前默认港口沙盘包含 12 名核心居民和 2 名 affiliate；在它的真实默认口径下：

| 网格 | #40 | 结论 |
|---|---:|---|
| held-out N=12 core，seeds 13-30，60 天 | **18/18** | 全绿 |
| seed 24，60 天 | **绿** | 糕点满足率 **0.771**（155 / 201），不是 0.43 |

seed 24 的糕点仍然有稀缺性：酒店掌柜完成 9 个在班批次、产 210 件、坏 44 件，
18 天出现缺货；但它远高于 #40 的 0.50 下限，并且不是该网格的失败点。

因此，不能再把「追 seed 24 的 0.43」当作下一片的理由，也不能据此加产量、减保质期或再给
酒店掌柜收入。后两种改法都会掩盖真实问题或重碰 [215](215-p4c8-creperie-seller.md) 已测出的
「唯一产者的额外收入削弱上工」结构风险。

## 为什么要写这一片

[214](214-two-negatives-catch-and-exports.md) 的「master 今天」是当时树的测量语言，
不是长期不变的基线。后续 P4c 的菜单、嘴馋与卖家改动都能移动消费/工作轨迹；
跨版本搬运逐 seed 数字本来就不安全（见 [05](05-路线图与里程碑.md) 的过期说明）。

这次复核也说明当前最安全的继续方向不是凭一颗旧红去配平糕点，而是回到 P4 仍未完成的
治理切片：选人、任期、镇长公务时段与可读的政绩读数。那一片应先建可观测的候选/计票/任期
底座，再让镇长改救济和营业旋钮；不能把 [204](204-p4a-town-hall-finances.md) 已撤回的救济窗口直接重新打开。

## 可复现命令

```powershell
godot --headless --path game --script res://bench/Harness.gd -- `
  --seeds 13-30 --days 60 --det 1 --golden game/bench/golden_digests.json

godot --headless --path game --script res://bench/ScaleSupply.gd -- `
  --seeds 24 --days 60 --checkpoints 10,20,30,40,50,60 `
  --out ../build/pastry-seed24.jsonl
```

第一条的金标表没有 13-30 段，所以它会明确报「0 条可比」；这次验证的是不变量与同进程确定性，
不是跨提交 digest 相同。
