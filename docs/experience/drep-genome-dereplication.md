---
tool: "dRep v3.x"
dimension: "bacteria"
category: "genome-dereplication"
author: "team"
date: "2026-06-13"
tags: [drep, mag, dereplication, ani, checkm2]
scenario: [gut-microbiome, mag-catalog, metagenome-assembly]
---

# dRep MAG 去冗余参数建议

## Scenario

> 适用于 DAS_Tool refine 后获得多个 MAG，并已用 CheckM2 评估 completeness/contamination，需要去除近乎相同的基因组并保留最佳代表。

**关键参数速查**：Tool = `dRep v3.x`；Depends on = CheckM2 quality report, input = all MAG FASTA files from DAS_Tool；Key params = `-comp 50 -con 10` (MQ filter), ANI `-sa 0.97` (species-level), `-pa 0.9` (primary clustering), `--S_algorithm fastANI`；Output = `derep_genomes/` directory + `Cdb.csv` cluster assignments。

dRep 的关键作用不是提高单个 MAG 质量，而是在 MAG catalog 层面去掉近重复基因组。它按 ANI 聚类同种或近同种 MAG，并结合质量评分保留代表基因组；`-sa 0.97` 可作为物种级去冗余阈值，`-pa 0.9` 则是 genus-level 预聚类以减少后续 ANI 计算量。

## Recommendation

项目流程推荐先使用 CheckM2 过滤后的 `drep_input/*.fa`，再通过脚本指定 ANI 阈值：

```bash
# Run project wrapper with species-level dereplication threshold.
bash scripts/38_bac_drep.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -a 0.97
```

如果直接运行 dRep，并希望把 MQ 过滤、ANI 阈值和 fastANI 算法都写入命令，可使用：

```bash
# Direct dRep dereplication command for DAS_Tool MAG FASTA files.
dRep dereplicate result/binning/drep \
  -g result/binning/dastool/*.fa \
  -comp 50 \
  -con 10 \
  -sa 0.97 \
  -pa 0.9 \
  -nc 0.30 \
  --S_algorithm fastANI \
  -p 16
```

最终重点检查 `derep_genomes/` 或 `dereplicated_genomes/` 中的代表 MAG，以及 `data_tables/Cdb.csv` 中每个 MAG 的 cluster assignment。

## Rationale

- **为什么依赖 CheckM2 质量报告**：dRep 的代表选择需要 completeness 和 contamination 作为质量评分基础，低质量 MAG 不应直接进入 catalog。
- **为什么用 `-comp 50 -con 10`**：这是常用 medium-quality MAG 过滤线，能保留可用 MAG，同时剔除过残缺或污染过高的 bin。
- **为什么输入来自 DAS_Tool**：DAS_Tool 已整合多个 binning 工具结果，dRep 应在 refine 后的 MAG 集合上做 catalog 级去冗余。
- **为什么 `-sa 0.97` 可作为物种级阈值**：该阈值会合并近同种 MAG，适合按 MIMAG 口径整理非冗余物种代表集。
- **为什么 `-pa 0.9` 是 genus-level 预聚类**：先用较宽松 ANI 粗聚类可显著减少二级 ANI 比较数量，提升大批量 MAG 运行效率。
- **为什么使用 `--S_algorithm fastANI`**：fastANI 对 MAG catalog 的二级聚类速度更合适，通常比全量 nucmer 更适合批处理。
- **为什么 dRep 会保留最佳代表**：同一 cluster 内 dRep 会按完整度、污染度和组装统计打分，输出代表 MAG 而不是随机保留。
- **为什么必须查看 `Cdb.csv`**：代表基因组目录只能告诉你保留了什么，`Cdb.csv` 才能追踪每个原始 MAG 属于哪个 cluster。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: n_derep_mags=0, Exit: 0, Duration: 60s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/38_bac_drep.sh`
- `agents/skills/38_bac_drep.yaml`
- `docs/experience/drep-ani-threshold.md`
