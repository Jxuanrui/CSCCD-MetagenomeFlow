---
tool: "bacmet"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [bacmet, metal-resistance, biocide-resistance, co-selection]
scenario: [gut-microbiome, gene-catalog, environmental-exposure]
---

# BacMet 金属与杀生剂抗性注释建议

## Scenario

> 关键参数速查：适用于 step 18 的 `protein_nr.fa`，关注重金属和杀生剂抗性及其与 AMR 共选择问题；脚本 `27_bac_bacmet.sh` 为聚合注释：`-t CPUS -w WORKDIR -r REPO`；使用 `diamond blastp` 比对 `db/bacmet/*.dmnd`；关键阈值 `--evalue 1e-5`；输出 `result/annotation/bacmet/bacmet_hits.tsv`；重点覆盖 `Hg/Cd/Cu/As` 等金属抗性相关蛋白。

BacMet 适合回答“环境暴露是否可能推动群落中金属/杀生剂耐受与抗生素耐药共同富集”这一类研究问题。

在肠道宏基因组场景里，它通常不是最核心的主结论来源，但对于解释共暴露、共选择和移动元件传播具有明显补充价值。

## Recommendation

推荐把 BacMet 与 AMRFinder/CARD 并列放在 `protein_nr.fa` 聚合注释层执行，再在结果整合阶段分析共选择信号。

```bash
# Run BacMet annotation on the merged non-redundant protein catalog.
bash scripts/27_bac_bacmet.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

输出文件是 `result/annotation/bacmet/bacmet_hits.tsv`。建议后续与 ARG 注释表按基因 ID 或 contig 来源做联动，优先关注同时落在同一功能模块、同一 contig 或同一富集样本中的金属抗性与 AMR 命中。

如果研究问题涉及重金属暴露、消毒剂使用或环境污染输入，BacMet 应视为必跑项目；如果只是做基础 gut taxonomy 描述，它可以放在第二优先级。

## Rationale

- **为什么值得做 BacMet**：重金属和杀生剂抗性基因经常与 AMR 基因共同选择，能补充单纯 ARG 注释看不到的环境选择压力。
- **为什么适合聚合到 `protein_nr.fa`**：脚本和其他功能注释保持一致，都是围绕非冗余蛋白目录一次性完成，避免重复搜索。
- **为什么使用 `diamond blastp`**：大规模蛋白数据库搜索更高效，适合和 VFDB、NCyc、PCyc 采用同一技术路线。
- **为什么默认 `--evalue 1e-5`**：这是脚本固定阈值，适合作为跨项目统一起点，先压制弱命中噪声。
- **为什么重点关注 `Hg/Cd/Cu/As`**：这些金属抗性系统在共选择文献中最常见，也最容易与污染暴露和耐药传播联系起来。
- **为什么不能把 BacMet 命中直接等同于环境暴露证明**：序列命中只说明存在潜在耐受相关蛋白，不直接证明表达、活性或实际选择压力。
- **为什么要与 AMRFinder/CARD 联动**：真正有研究价值的是金属/杀生剂抗性与 ARG 在同一群落或基因背景中的共现，而不是孤立命中数量。
- **为什么在基础项目中可作为第二优先级**：如果研究问题不涉及环境共选择，BacMet 通常不是最先需要解释的层面。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/27_bac_bacmet.sh`
- BacMet
- Pal et al. 2014
