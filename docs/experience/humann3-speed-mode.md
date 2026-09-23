---
tool: "humann3"
dimension: "bacteria"
category: "functional"
author: "team"
date: "2026-06-11"
tags: [speed-mode, pathway-profiling, prescreen-threshold]
scenario: [gut-microbiome, high-depth, paired-end]
---

# HUMAnN3 standard、balanced 与 fast 模式选择建议

## Scenario

> 适用于去宿主后的双端宏基因组样本，需要在功能通路精度、运行时间和队列吞吐之间做明确取舍。

本项目脚本已经把 HUMAnN3 的关键决策点集中到 `--speed-mode`，因此经验文档的重点不是“能不能跑”，而是“什么场景切到哪一档”。

当样本深度超过约 20M reads、且队列规模较大时，速度模式的收益会非常明显。

如果项目目标是发表级通路结果、稀有物种分层通路或病例对照功能解释，不能只看速度，必须考虑 prescreen 的信息损失。

## Recommendation

默认推荐：`--speed-mode balanced`。

对应关键参数如下：

```bash
humann \
  --prescreen-threshold 1.0 \
  --memory-use maximum \
  --taxonomic-profile sample_profile.txt \
  --remove-temp-output
```

`standard` 只建议用于两类情况：样本深度低于约 `20M reads`，或者最终要尽可能完整保留低丰度物种的 stratified 通路。

`balanced` 适合大多数肠道宏基因组正式分析；推荐阈值就是脚本默认的 `1.0`，不要误写成 `0.01` 或 `0.05`。

`fast` 适合探索性筛选、超大队列预分析、或只关心社区层面主效应的任务；使用时接受 `R1-only + threshold 3.0` 的信息折损。

已有 MetaPhlAn4 profile 时，优先传 `--taxonomic-profile`，不要让 HUMAnN3 再内部重复跑一次 MetaPhlAn4。

在 `balanced` 与 `fast` 模式下保留 `--remove-temp-output` 是合理的；若需要排障，再局部关闭做单样本复盘。

通路统计分析优先使用 `unstratified/` 结果；`stratified/` 更适合做来源解释，而不是首选的组间检验矩阵。

## Rationale

- **阈值单位为什么容易出错**：脚本明确指出 HUMAnN3 将 MetaPhlAn4 的相对丰度按 `0-100` 百分比尺度比较，而不是 `0-1` 分数尺度。
- **为什么 `balanced=1.0` 是主推荐**：它把待建库物种从约 `126` 个降到约 `21` 个，自定义 ChocoPhlAn 库从约 `60G` 压到约 `2-5G`，是性能收益最大的拐点。
- **为什么 `fast=3.0` 还能保住主通路**：大部分高丰度核心物种仍会留下，社区层面的主通路通常比稀有物种分层结果更稳定。
- **为什么 `fast` 不适合发表级结论**：它只使用 `R1`，同时把物种阈值提到 `3%`，低丰度物种及其 stratified pathway 很容易整体消失。
- **为什么低深度样本不一定要 `balanced`**：低深度时本来可识别物种就少，再提高阈值可能把有限信息进一步压缩。
- **为什么建议复用 MetaPhlAn4 profile**：避免重复分类只是表层收益，更重要的是保证 taxonomy 与功能 prescreen 的输入完全一致。
- **为什么不使用 `--bypass-prescreen`**：脚本已经说明，这会跳过按物种过滤的小数据库构建，直接把大库整体纳入，反而拖慢并破坏模式设计。
- **为什么优先看 unstratified**：组学统计往往需要更稳定、更少稀疏性的矩阵；物种分层通路虽然信息丰富，但零值和批次敏感性更高。
- **为什么 `maximum` 内存模式值得开**：这里的主要收益不是占满内存，而是减少频繁磁盘交换与数据库构建开销。

## Verified

- validated — 已通过实际运行验证
- 2026-06-14 — User: local, Sample: S01-S06 ×6, Params: none, Durations: S01=1988s S02=2111s S03=1843s S04=2384s S05=1934s S06=2032s, Exit: 0, Duration: 1988s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/13_bac_humann3.sh`
- `agents/skills/13_bac_humann3.yaml`
- `scripts/11_bac_metaphlan4.sh`
- HUMAnN3 输出目录中的 `unstratified/` 与 `stratified/`
