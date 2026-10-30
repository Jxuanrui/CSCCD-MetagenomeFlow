---
tool: "humann3"
dimension: "mycobiome"
category: "functional"
author: ""
date: "2026-06-14"
tags: [fungal-pathways, stratified-output, postprocessing]
scenario: [gut-microbiome, whole-genome-metagenomics, per-sample-analysis]
---

# HUMAnN 分层结果提取真菌通路建议

## Scenario

> 适用于步骤 13 已产出 `result/humann3/{sample}/stratified/{sample}_pathabundance_relab_stratified.tsv`，希望不重跑 HUMAnN3、只从现有 stratified 通路表中提取 `|k__Eukaryota` 对应的真菌贡献；输出为 `result/fungi/humann4/{sample}/{sample}_fungi_pathabundance.tsv`。

这不是新的 HUMAnN 计算步骤，而是对已完成 HUMAnN3 stratified 结果的后处理。只要上游分层结果存在，就能快速拿到 fungi-attributed pathways。

## Recommendation

推荐把它当作“已有 HUMAnN3 结果的真菌功能拆分层”。前提是步骤 13 已经成功运行，并且确实保留了 `stratified/` 目录；否则这个步骤没有可提取的输入。

```bash
# Extract fungal pathway rows from existing HUMAnN stratified output.
bash scripts/73_fun_humann4_fungi.sh \
  -s sample \
  -t 1 \
  -w Project/Project_example \
  -r ${PROJ_DIR}
```

如果只是想知道真菌在某些 MetaCyc pathway 中是否有贡献，这一步比重跑 HUMAnN3 更省时，也不会引入新的 prescreen 或数据库版本偏差。

## Outputs

输入固定来自已有 HUMAnN3 分层相对丰度表：

```text
result/humann3/{sample}/stratified/{sample}_pathabundance_relab_stratified.tsv
```

输出为每样本真菌通路子集：

```text
result/fungi/humann4/{sample}/{sample}_fungi_pathabundance.tsv
```

当前脚本的实现逻辑很直接：筛出所有包含 `|k__Eukaryota` 的行，再把原始 header 补回结果文件顶部。因此输出为空通常表示上游 stratified 文件里没有真核贡献，而不是脚本本身做了额外过滤。

## Rationale

- **为什么不需要重跑 HUMAnN3**：需要的信息已经在 stratified `pathabundance` 表里，后处理提取即可。
- **为什么必须依赖步骤 13**：没有 `stratified/` 结果，就不存在 species-attributed pathway，脚本也无法凭空重建真菌贡献。
- **为什么强调 stratified 而不是 unstratified**：只有 stratified 结果才记录“某条 pathway 由哪个物种贡献”，真菌提取本质上就是在利用这层归属信息。
- **为什么输出适合逐样本使用**：每个样本单独保留真菌 pathway 子集，后续合并矩阵或做 targeted review 都更清楚。
- **为什么它适合已有队列复用**：当 HUMAnN3 已全队列跑完时，这一步几乎只消耗文本过滤时间，是拿 fungal functional signal 的最低成本方式。
- **为什么解释时要注意来源限制**：它反映的是“被 HUMAnN3 和上游 taxonomy 识别到的真菌贡献”，不是独立的 fungal-only 功能分析流程。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/73_fun_humann4_fungi.sh`
- `scripts/13_bac_humann3.sh`
- `docs/experience/humann3-speed-mode.md`
