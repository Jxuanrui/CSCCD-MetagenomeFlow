---
tool: "iphop-host"
dimension: "virome"
category: "annotation"
author: "team"
date: "2026-06-11"
tags: [host-prediction, virus-host, database-size]
scenario: [gut-microbiome, high-depth, cross-cohort]
---

# iPHoP 宿主预测结果的使用边界与推荐做法

## Scenario

> 适用于已经完成 vOTU 构建的病毒序列集合，需要推断潜在宿主并用于生态解释或宿主-病毒网络分析。

iPHoP 的优势是整合多种证据做宿主预测，但它高度依赖数据库规模和参考覆盖。

本项目脚本把这一步定义为聚合分析，而不是单样本常规产物，说明它更适合 catalogue 层面使用。

## Recommendation

推荐对去重后的 vOTU 序列统一运行 iPHoP，而不是对每个样本散装 contig 分别预测。

主调用建议保持如下：

```bash
iphop predict \
  --fa_file result/virus/votu/contigs/virus.fasta \
  --db_dir db/iphop/Jun_2025_pub_rw \
  --out_dir result/virus/iphop \
  --num_threads 16
```

数据库不存在时，保留脚本的“空结果退出”策略是合理的，但正式项目不应把空表误判成“没有宿主”。

结果解释优先从属级表开始，再视需要下钻到基因组级预测；不建议直接把 genome-level 结果当作确定宿主。

若团队需要构建稳健病毒-宿主网络，建议只保留 iPHoP 高置信预测，并与 GTDB-Tk 的宿主 MAG taxonomy 做名称统一。

对于数据库覆盖可能不足的环境样本，iPHoP 更适合作为“候选关联生成器”，而不是最终证据。

## Rationale

- **为什么对 vOTU 而不是单样本 contig 运行**：vOTU 层面更去冗余、噪声更低，也更符合宿主关联分析的 catalogue 视角。
- **为什么数据库大小是核心约束**：脚本注明数据库约 `279 GB` 量级，说明方法性能与参考覆盖强绑定；无库或旧库都会直接削弱结果。
- **为什么空表不等于无宿主**：脚本在缺少数据库或失败时会优雅退出并创建占位文件，这只是流程兼容策略，不是生物学结论。
- **为什么先看属级再看基因组级**：属级预测通常更稳，基因组级分辨率更高但也更依赖参考匹配质量。
- **为什么要与 GTDB-Tk 对齐命名**：宿主侧如果使用 MAG catalogue，taxonomy 命名体系不统一会导致后续网络图和统计表难以连接。
- **为什么高置信过滤很重要**：宿主预测错误会直接影响生态解释，例如把噬菌体归给错误门类或错误生活型宿主。
- **为什么环境样本要更保守**：偏远生态位的宿主参考代表性不足时，iPHoP 的“未预测”与“低置信预测”都比硬判定更诚实。
- **为什么这一步适合聚合层运行**：单样本 contig 会有更多碎片和重复，聚合后的 vOTU 代表序列更适合做稳定宿主推断。
- **为什么线程数只是次要参数**：这里真正决定质量的是数据库和输入序列质量，线程主要影响 wall time，不改变证据强度。

## Verified

- validated — 已通过实际运行验证
- 2026-06-15 — User: local, Sample: all, Params: n_host_predictions=31, Exit: 0, Duration: 7200s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/68_vir_iphop.sh`
- `agents/skills/68_vir_iphop.yaml`
- 输入：`result/virus/votu/contigs/virus.fasta`
- 相关宿主 taxonomy：`scripts/40_bac_gtdbtk.sh`
