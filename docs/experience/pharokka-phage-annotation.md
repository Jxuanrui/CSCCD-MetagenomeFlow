---
tool: "pharokka"
dimension: "virome"
category: "annotation"
author: "team"
date: "2026-06-13"
tags: [parameter-tuning, phage-annotation, gene-prediction, functional-annotation]
scenario: [gut-microbiome, assembled-contigs, virus-catalogue]
---

# PHAROKKA 噬菌体基因组端到端注释建议

## Scenario

> 适用于已生成 vOTU 代表序列（脚本 56 输出）的肠道病毒组研究，需要对病毒序列做端到端注释（基因预测、功能数据库比对、ARG 检测）。核心参数：`-d pharokka_db`（PHROG 数据库路径）；`--skip_extra_annotations`（跳过辅助注释，加速）；`--skip_mash`（跳过菌株比对）；`-t 16`；输出三大文件：`pharokka.gff`、`prodigal-gv.faa`（蛋白序列供 vConTACT3/PHOLD 使用）、`pharokka_cds_final_merged_output.tsv`（CDS 汇总）。

PHAROKKA 以 prodigal-gv 做基因预测（支持病毒遗传密码子），并与 PHROG、CARD（ARG）、VFDB（毒力）数据库比对，是病毒组下游功能分析的必要前置步骤。

## Recommendation

正式分析建议运行完整 PHAROKKA 流程，`--skip_extra_annotations` 跳过非核心步骤以加速：

```bash
# Run PHAROKKA through the project wrapper.
bash scripts/64_vir_pharokka.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接调用时，指定 PHROG 数据库路径，添加 `--skip_mash` 避免与 mash database 的额外比对：

```bash
# Direct PHAROKKA command.
pharokka.py \
  -i result/virus/votu/contigs/virus.fasta \
  -o result/virus/pharokka \
  -d db/pharokka \
  -t 16 \
  -f \
  --skip_extra_annotations \
  --skip_mash
```

PHAROKKA 输出的 `prodigal-gv.faa` 是 vConTACT3 基因共享网络分析（脚本 69）和 PHOLD 暗物质注释（脚本 65）的必要输入；运行前确保 vOTU 序列存在。

## Rationale

- **为什么用 prodigal-gv**：PHAROKKA 内部使用 prodigal-gv 做基因预测，专为病毒遗传密码子设计，比标准 prodigal 对噬菌体基因组更准确。
- **为什么加 `--skip_extra_annotations`**：可跳过 PYRODIGAL 的扩展注释步骤，在 vOTU 数量较多时显著提速，不影响核心功能预测。
- **为什么加 `--skip_mash`**：mash 近邻搜索耗时但对功能注释贡献有限；发现级研究不需要，只有物种命名时才需要开启。
- **为什么 PHROG 比 pVOGs 更好**：PHROG（PHage Reference Genes）数据库专为噬菌体蛋白功能分类设计，比通用数据库对头尾纤维、衣壳、整合酶等噬菌体功能蛋白的分辨率更高。
- **为什么必须先运行 vOTU**：PHAROKKA 针对代表性序列注释，对每个 vOTU 只运行一次，避免对冗余序列重复计算。
- **文献依据**：Terzian et al. 2023 Microb Genom 验证 PHAROKKA 在 PHROG 比对精度和速度上显著优于同类工具。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: n_cds=565, Exit: 0, Duration: 3600s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/64_vir_pharokka.sh`
- `scripts/65_vir_phold.sh`（PHOLD 暗物质注释，依赖本步骤输出）
- `scripts/69_vir_vcontact3.sh`（vConTACT3，依赖 prodigal-gv.faa）
- Terzian et al. 2023 Microb Genom (PHAROKKA)
