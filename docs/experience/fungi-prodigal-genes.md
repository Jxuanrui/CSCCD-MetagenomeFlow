---
tool: "prodigal"
dimension: "mycobiome"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [gene-prediction, fungal-assembly, downstream-annotation]
scenario: [gut-microbiome, assembled-contigs, per-sample-analysis]
---

# Prodigal 真菌组装基因预测建议

## Scenario

> 适用于 `78_fun_megahit.sh` 已产出每样本真菌 contigs，希望直接用标准 Prodigal `-p meta` 预测基因；输入 `result/fungi/assembly/{sample}/{sample}.contigs.fa`，输出 `result/fungi/prodigal/{sample}/{sample}.faa/.fna/.gff`，并供 81-86 自动汇总全部 FAA。

这里处理的是 fungi assembly，不是病毒 contig。虽然分析对象换成真菌，但在这个流程里仍使用标准遗传密码和 `-p meta` 匿名模式。

## Recommendation

推荐保持脚本默认，直接对每个样本 contig 跑标准 Prodigal。它是单线程工具，`-t` 参数只是为了和 pipeline 调用接口保持一致。

```bash
# Per-sample gene prediction from fungal assembly contigs.
bash scripts/80_fun_prodigal.sh \
  -s sample \
  -t 1 \
  -w Project/Project_example \
  -r ${PROJ_DIR}
```

如果只是为了让后续 eggNOG、KEGG、dbCAN、VFDB、AMR 和 MEROPS 注释顺利接上，最关键的是确保 `.faa` 完整生成；`.fna` 和 `.gff` 也应保留，便于后续追踪基因来源和核酸层分析。

## Outputs

每样本结果目录为：

```text
result/fungi/prodigal/{sample}/
```

关键文件包括：

```text
{sample}.faa
{sample}.fna
{sample}.gff
```

下游 `81_fun_eggnog.sh` 到 `86_fun_merops.sh` 不要求逐样本单独指定输入，而是会自动收集 `result/fungi/prodigal/*/*.faa` 并汇总分析。

## Rationale

- **为什么继续用标准 Prodigal**：当前流程把真菌这一步视作标准遗传密码、匿名宏基因组 contig 的基因预测任务，不需要病毒专用模型。
- **为什么 `-p meta` 仍然合适**：这些 contig 来自样本级 metagenome assembly，不是高质量完整真菌基因组，匿名模式更稳。
- **为什么 `.faa` 最关键**：后续 81-86 的功能注释基本都以蛋白序列为入口，`.faa` 直接决定流程能否继续。
- **为什么要和 `prodigal-gv` 区分**：`55_vir_prodigal_gv.sh` 面向病毒特异遗传密码与病毒场景；真菌不该套用 virus-specific 解释框架。
- **为什么保留 `.fna` 和 `.gff`**：一个保留核苷酸层序列，一个保留坐标与结构信息，后续做追踪、筛选或手工复核都会用到。
- **为什么它适合逐样本稳定批处理**：Prodigal 资源占用低、接口简单，作为真菌 assembly 到功能注释之间的桥梁很稳。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/80_fun_prodigal.sh`
- `scripts/55_vir_prodigal_gv.sh`
- `scripts/81_fun_eggnog.sh`
- `docs/experience/prodigal-gene-prediction.md`
