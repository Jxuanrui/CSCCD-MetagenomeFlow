---
tool: "AMRFinderPlus 3.12+"
dimension: "mycobiome"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [fungi, amr, antifungal-resistance, amrfinderplus, cyp51, fks]
scenario: [mycobiome, fungal-proteins, antifungal-resistance]
---

# 真菌抗真菌耐药注释建议

## Scenario

> 关键参数速查：`85_fun_amr.sh` 依赖 step 80，聚合真菌 FAA；Tool = AMRFinderPlus 3.12+；覆盖部分抗真菌标记如 CYP51/ERG11、FKS1/2；输出 `result/fungi/amr/amrfinder_results.tsv`；FKS1 点突变需人工复核。

AMRFinderPlus 在这里用于从真菌蛋白集合中筛查已知耐药相关标记，尤其是 azole 靶点 CYP51/ERG11 和 echinocandin 靶点 FKS1/2 等。它可以提供抗真菌耐药线索，但本质上仍主要面向细菌 AMR 工作流，真菌结果应更谨慎解释。

对真菌而言，耐药常常不仅是“有没有某个基因”，还涉及靶点位点突变、拷贝数、表达调控和物种背景。特别是 FKS1/FKS2 的 echinocandin resistance，关键点突变可能不会被蛋白同源搜索完整捕获，需要后续手工检查或专门流程验证。

## Recommendation

推荐直接运行项目脚本，先得到可审计的 AMRFinderPlus 结果表。

```bash
# Run AMRFinderPlus on merged fungal proteins.
bash scripts/85_fun_amr.sh \
  -t 16 \
  -w /path/to/project \
  -r ${PROJ_DIR}
```

脚本使用蛋白输入、NCBI AMRFinderPlus 数据库和较严格的相似性阈值。

```bash
amrfinder \
  --protein result/fungi/amr/combined_fungi.faa \
  --database db/amrfinder/latest \
  --output result/fungi/amr/amrfinder_results.tsv \
  --threads 16 \
  --ident_min 0.9 \
  --coverage_min 0.6 \
  --plus
```

建议把输出分成“可直接报告的已知抗性基因/靶点”和“需要人工复核的候选位点”两类。涉及 FKS1/FKS2、ERG11/CYP51 或物种特异热点突变时，不要只依据 AMRFinderPlus 命中给出耐药表型判断。

## Rationale

- **为什么使用 AMRFinderPlus**：它提供规范化的基因名、药物类别和机制字段，适合作为耐药线索的初筛表。
- **为什么真菌结果要保守解释**：AMRFinderPlus 主要为细菌 AMR 设计，对真菌抗性机制覆盖不如专门真菌耐药流程完整。
- **为什么关注 CYP51/ERG11**：azole resistance 常与该靶点的变异、扩增或调控改变有关，是真菌耐药解释中的核心对象。
- **为什么关注 FKS1/FKS2**：echinocandin resistance 常涉及 glucan synthase 相关热点突变，单纯基因命中不足以判断表型。
- **为什么依赖蛋白 FAA**：脚本消费 `80_fun_prodigal.sh` 的真菌蛋白预测结果，适合快速筛查已知耐药蛋白家族。
- **为什么需要人工复核点突变**：AMRFinderPlus 的蛋白同源命中可能无法完整捕捉特定 hotspot mutation，关键结论应回到序列比对确认。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/85_fun_amr.sh`
- `docs/experience/amrfinder-resistance-genes.md`
