---
tool: "StrainPhlAn4"
dimension: "bacteria"
category: "taxonomy"
author: ""
date: "2026-06-13"
tags: [strain-tracking, phylogeny, metaphlan4, cross-sample]
scenario: [gut-microbiome, strain-level, shotgun-metagenomics]
---

# StrainPhlAn4 菌株追踪与系统发育重建建议

## Scenario

> 适用于已经完成 MetaPhlAn4 的多样本 shotgun metagenomics 项目，需要从 marker 层面追踪同一物种或 SGB 在不同样本间的菌株差异。

**关键参数速查**：Tool = `StrainPhlAn4`；Depends on = MetaPhlAn4 `sam.bz2` output（必须保留 `sam.bz2`）；Key params = `--nprocs 16`, `--phylophlan_mode accurate`, minimum 4 samples recommended, `--sample_with_n_markers 10`；Scenario = strain-level tracking, phylogenetic reconstruction, cross-sample comparison。

核心判断是：`sam.bz2` 是 MetaPhlAn4 给 StrainPhlAn4 的不可替代输入。没有 `sam.bz2` 就无法从 reads 到 marker consensus 复原菌株信息，只能重新运行 MetaPhlAn4 并确保 `--samout` 输出被压缩保留。

## Recommendation

推荐先用项目脚本完成候选 clade 检测，再选择目标菌株建树：

```bash
# Step 1: extract consensus markers and list candidate clades.
bash scripts/12_bac_strainphlan4.sh \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -t 16

# Step 2: build tree for a selected clade from clades_detected.txt.
bash scripts/12_bac_strainphlan4.sh \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -t 16 \
  -c t__SGB10068
```

如果需要更严格的系统发育树质量，可在直接运行 `strainphlan` 时使用 accurate 模式，并在样本数不足或 marker 偏少时把 marker 门槛放宽到 `10`：

```bash
# Direct StrainPhlAn4 command after sample2markers.py and extract_markers.py.
strainphlan \
  -s result/strainphlan4/consensus_markers/*.json.bz2 \
  -m result/strainphlan4/db_markers/t__SGB10068/*.fna \
  -d db/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202212.pkl \
  -o result/strainphlan4/trees/t__SGB10068 \
  -c t__SGB10068 \
  --nprocs 16 \
  --sample_with_n_markers 10 \
  --phylophlan_mode accurate \
  --non_interactive
```

建议至少 4 个样本再解释跨样本菌株结构；2-3 个样本可以生成树，但拓扑稳定性和分组解释都偏弱。

## Rationale

- **为什么必须保留 `sam.bz2`**：StrainPhlAn4 不是读取 MetaPhlAn4 的物种丰度表，而是从 SAM 里抽取 marker 覆盖信息并生成 consensus markers。
- **为什么没有 `sam.bz2` 必须重跑 MetaPhlAn4**：profile、biom 或 merged abundance table 都不包含 read-to-marker alignment，无法反推出菌株序列。
- **为什么建议最少 4 个样本**：菌株树是跨样本比较任务，样本数太少时只能看到两两距离，难以判断群体结构或批次聚类是否稳定。
- **为什么使用 `--sample_with_n_markers 10`**：肠道真实样本中低丰度菌经常 marker 不完整，适度放宽样本 marker 数能减少候选样本被全部过滤。
- **为什么可选 `--phylophlan_mode accurate`**：accurate 模式更适合最终报告或发表级树构建，代价是运行时间高于 fast 模式。
- **为什么仍推荐先跑脚本自动检测 clade**：未指定 `-c` 时脚本会生成 `clades_detected.txt`，能避免盲目选择不存在或样本覆盖不足的物种。
- **为什么优先使用 `t__SGB` clade**：SGB 级 marker 通常比宽泛的 `s__Species` 更贴近 MetaPhlAn4 v4 的数据库组织，菌株分辨率更高。
- **为什么要先做 SAM header 去重**：当前脚本已处理 MetaPhlAn4 vOct22 数据库中重复 `@SQ` 的兼容问题，直接复用脚本比手写流程更稳。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/12_bac_strainphlan4.sh`
- `agents/skills/12_bac_strainphlan4.yaml`
- `docs/experience/metaphlan4-parameter-guide.md`
