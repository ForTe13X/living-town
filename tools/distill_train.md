# L3 蒸馏训练配方（QLoRA → GGUF → 接 NobodyWho）

> 前两步（造样本）已搭好并小批验证：`bench/DistillDump.gd`（导真实决策上下文）+ `tools/distill_label.py`（teacher 8B 打 label，实测 15/15 合法率 100%）。
> 本文档是**第 3–5 步（训练/转换/验收）**——需 GPU + PyTorch，**一次性离线成本，运行时仍 100% 本地**。
> ⚠️ 触发条件（docs/11 §6 L3）：仅当 prompt 工程触顶后 1.5B 质量仍不达 bench 门槛、且明确要「3B/8B 质量塞进 1.5B 体积/速度」时才做。**当前更划算的零训练选项 = 默认升 3B**（中端 ~2.9s 实测，质量肉眼更好）。

## 0. 决策：先考虑零训练换 3B
- 实测（docs/11 §12.2b）：3B-Q4 中端 780M ~2.9s、395 GPU 更快，质量明显优于 1.5B。
- 把 `AIBackend.slm_model_path` 指向 `res://models/qwen2.5-3b-instruct-q4_k_m.gguf`（下个 ~2GB GGUF 放进 `game/models/`）即可，无需训练。
- **蒸馏只在「要 1.5B 的速度/体积 + 接近 3B/8B 的质量」时才值得**（如要塞进 Steam Deck/移动/极致包体）。

## 1. 放大造样本
```bash
# A 类（状态→决策 JSON）：多 seed 各导，去重后合并到几千条
for s in 20260626 11 22 33 44; do
  godot --headless --path game res://scenes/distill_dump.tscn -- --n 800 --seed $s --out res://bench/ctx_$s.jsonl
done
cat game/bench/ctx_*.jsonl > game/bench/contexts_all.jsonl   # 再去重（distill_label 不去重）
# teacher 打 label（teacher=本机 8B，同族迁移损失小；可换更强云端老师但 schema 必须一致）
python3 tools/distill_label.py game/bench/contexts_all.jsonl game/bench/sft_decide.jsonl <teacher-host> 1234 qwen-3-8b-instruct
# B 类（玩家对话）：另写一个 chat 上下文 dumper（persona+记忆+玩家话术），同法用 8B 打 label → sft_chat.jsonl
```
- 目标量级：A ~10k–30k（覆盖各需求组合 + 各社交事件触发态：gossip/放逐/宽恕/谣言/冲突），B ~3k–8k。
- **难负样本**：多构造「候选集很小、诱导越界」的状态，强化只在合法集内 pick。
- 标签已由 `distill_label.py` 过 `pick∈[0,n)` 校验（100% 合法），schema 已烤进训练目标。

## 2. QLoRA 训练（student = Qwen2.5-1.5B-Instruct）
环境：单 GPU + PyTorch。**AMD ROCm 在 Windows 训练支持弱** → 建议 Linux(ROCm/CUDA) 或一次性云 GPU。推荐 unsloth（省显存、快）或 peft+bitsandbytes。
```python
# 关键配置（基线）
base        = "Qwen/Qwen2.5-1.5B-Instruct"   # 与路C 推理栈一致，避免再踩 GGUF/解码坑
load_in_4bit = True                          # NF4
lora_r, lora_alpha = 32, 64
target_modules = ["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"]
lr, epochs, max_seq = 2e-4, 3, 2048
# 数据：sft_decide.jsonl + sft_chat.jsonl，用 Qwen chat template 拼 messages
# 训练目标只算 assistant 段 loss（mask 掉 system/user）
```
- 可分离实验：JSON-格式 LoRA 与 口吻 LoRA 各训一版，对比 bench 分。

## 3. 合并 + 转 GGUF
```bash
# 合并 LoRA → fp16 HF
python merge_lora.py --base Qwen/Qwen2.5-1.5B-Instruct --lora out/adapter --out out/merged_fp16
# HF → GGUF fp16 → 量化 Q4_K_M（与路C 现用量化对齐，保 ~1s 量级延迟）
python llama.cpp/convert_hf_to_gguf.py out/merged_fp16 --outfile out/town-1.5b-f16.gguf
./llama.cpp/llama-quantize out/town-1.5b-f16.gguf game/models/town-1.5b-instruct-q4_k_m.gguf Q4_K_M
```

## 4. 接入 + 验收（全部由 bench 判定）
1. `AIBackend.slm_model_path = "res://models/town-1.5b-instruct-q4_k_m.gguf"`。
2. 跑 `BackendBench`（res://scenes/backend_bench.tscn，--backend slm --gpu）：
   - **合法率 ≥ 99%** 且 ≥ prompt 工程后的原始 1.5B。
   - 决策延迟 ≤ 1.5s、对话 ≤ 0.5s（不劣于路C），且 **prompt token 数显著下降**（schema/few-shot 已内化 → 可缩短 system prompt 再测）。
3. 跑 `CausalHarness`（S5）+ `Harness`（S0）：**PI/cascade/Gini 相对 logic 基线偏移 ≤ ε**、20 条不变量全过（证明换模型没篡改确定性地板宏观行为）。
4. 口吻：LLM-judge 或人评，世界观一致性 ≥ 路A 8B 的 90%。
5. **回滚条件**：任一门红 → 退回 prompt 工程 + 原始 1.5B（或直接用 3B）。

> 保留运行时 GBNF/json_schema 受限解码作格式保险（蒸馏后几乎用不上，但仍兜底）。
