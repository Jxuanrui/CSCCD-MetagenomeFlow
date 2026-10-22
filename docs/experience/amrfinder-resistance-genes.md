---
tool: "AMRFinderPlus"
dimension: "bacteria"
category: "annotation"
author: ""
date: "2026-06-13"
tags: [amr, arg, amrfinderplus, resistance-genes]
scenario: [gut-microbiome, gene-catalog, antibiotic-resistance]
---

# AMRFinderPlus 耐药基因注释建议

## Scenario

> 适用于完成组装、基因预测和去冗余后，需要在全群落基因目录中识别抗生素耐药基因，并输出可审计的 ARG 家族、机制和亚类结果。

对于环境或宿主相关宏基因组，ARG 注释最怕的是宽松相似性带来的假阳性。AMRFinderPlus 的优势在于使用 NCBI 专家整理数据库和命名体系，适合做发表级耐药基因报告，也适合作为后续与药物暴露、宿主表型或菌群失衡关联分析的基础层。

项目输入是 step 18 产生的 `result/assembly/cdhit/protein_nr.fa`，因此推荐直接在蛋白层做聚合注释，而不是重新回到核酸层搜索。`--plus` 会把核心 AMR 之外的点突变、应激和部分毒力相关信号一起纳入，这对环境样本的风险解释更完整，但也意味着结果解读时要区分“严格 ARG”与“扩展 plus 注释”。

如果后续要做群落级 resistome 汇总，最好在这一层就统一好基因名、药物类别和机制字段。

**关键参数速查**：Tool = `AMRFinderPlus`；Depends on = step `18_bac_cdhit` 产物 `protein_nr.fa`；Key params = `--protein`, `--threads 16`, `--output`, `--plus`, `--ident_min 0.9`, `--coverage_min 0.5`；DB = curated NCBI `db/amrfinder/latest`；Output = `result/amrfinder/amrfinder_results.tsv`.

## Recommendation

```bash
# Run AMRFinderPlus through the project wrapper.
THREADS=16                        # compute threads
WORKDIR=/path/to/project          # project workdir with protein_nr.fa
REPO=/path/to/CSCCD-MetagenomeFlow       # repo root with db/amrfinder and envs
bash scripts/23_bac_amrfinder.sh -t "$THREADS" -w "$WORKDIR" -r "$REPO"
```

如果目标是完全复现仓库当前包装脚本，`scripts/23_bac_amrfinder.sh` 默认使用更严格的 `--coverage_min 0.6`。本文把推荐值写为 `0.5`，是为了在环境样本里保留覆盖不完整但高相似度的候选 ARG；若你更重视保守性，可以直接沿用脚本默认值。

推荐把 AMRFinderPlus 作为主报告来源，再用 CARD 或 RGI 做交叉核验，而不是反过来。AMRFinderPlus 的命名体系更稳定，尤其适合整理“基因名-药物类别-耐药机制”三层摘要；`--plus` 则适合在补充结果中展示伴随风险信号，但正文讨论时最好把核心 ARG 和扩展注释分开。

如果你确实要手工直跑原生命令，建议在 wrapper 之外显式补回 `--ident_min 0.9`、`--coverage_min 0.5-0.6` 和 `--plus`，不要依赖环境里的历史默认值。AMR 注释最怕参数漂移，因为同一批样本在阈值稍微放宽后，候选基因数会明显膨胀。

对环境样本而言，宁可在文献里解释“阈值偏严格”，也不要提交一张高噪声的 ARG 清单。

## Rationale

- **为什么 AMRFinderPlus 优先于 CARD/VFDB 做 ARG 主结果**：AMRFinderPlus 的 NCBI 数据库经过专家审校，命名规范和家族边界更稳定，适合构建主表和论文级总结。
- **为什么启用 `--plus`**：它除了核心 AMR 外，还能提供点突变、应激耐受和部分毒力相关线索，便于做风险全景图，而不只是最窄义的抗性基因列表。
- **为什么 `--ident_min 0.9`**：环境宏基因组序列多样性高，若身份阈值过低，容易把一般转运蛋白或远缘保守酶误判为 ARG，`0.9` 能明显压低假阳性。
- **为什么 `--coverage_min 0.5`**：宏基因组组装经常出现基因截断，`0.5` 能保留高相似度但不完整的候选；若样本噪声较大或你要做保守发布，可上调到脚本默认的 `0.6`。
- **为什么优先用蛋白层输入**：耐药功能多由蛋白保守位点和家族定义，直接对 `protein_nr.fa` 搜索比在 DNA 层更贴近 AMRFinderPlus 的模型，也更省计算。
- **为什么做聚合注释**：耐药注释针对的是全项目非冗余蛋白集，先统一注释，再结合基因丰度矩阵回填到样本层，能避免样本间重复比对和注释漂移。
- **为什么建议和 CARD 交叉验证**：不同数据库在边界案例、泵类蛋白和命名标准上不完全一致，双库交叉能帮助识别高置信核心 ARG 与数据库特异命中。
- **为什么环境样本要更严格**：与临床单菌株不同，环境宏基因组里大量同源但非典型抗性蛋白会抬高背景噪声，因此高 identity cutoff 更有必要。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/23_bac_amrfinder.sh`
- `agents/skills/23_bac_amrfinder.yaml`
