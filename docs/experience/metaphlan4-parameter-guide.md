---
tool: "metaphlan4"
dimension: "bacteria"
category: "taxonomy"
author: "team"
date: "2026-06-11"
tags: [parameter-tuning, species-profiling, strain-analysis]
scenario: [gut-microbiome, high-depth, paired-end]
---

# MetaPhlAn4 双端样本参数与输出保留建议

## Scenario

> 适用于经去宿主后的双端宏基因组样本，需要稳定获得物种组成，并为后续 StrainPhlAn4 与 HUMAnN3 复用分类结果。

推荐场景是肠道、口腔或粪便等中高深度样本，单样本常见在 10M 到 80M reads。

如果目标只是快速粗分类，Kraken2 更快；如果目标是标志基因驱动的稳健物种谱与后续菌株分析，优先保留 MetaPhlAn4。

脚本默认数据库是 `mpa_vOct22_CHOCOPhlAnSGB_202212`，与后续 HUMAnN3 的 prescreen 逻辑是配套的。

## Recommendation

核心推荐是保留脚本默认运行方式，不要在当前流程里强行改回 `-1/-2` 直接输入。

当前版本推荐参数与流程如下：

```bash
metaphlan merged.fastq.gz \
  --input_type fastq \
  --db_dir db/metaphlan4 \
  -x mpa_vOct22_CHOCOPhlAnSGB_202212 \
  --nproc 16 \
  --mapout sample.mapout.bz2 \
  --samout sample.sam \
  --offline
```

线程数建议 `8-16`；在共享节点上，`16` 往往已经接近 bowtie2 阶段的有效上限。

双端样本建议继续先合并为单个 FASTQ 再运行；这是脚本对 MetaPhlAn4 v4.2.4 输入行为做的兼容处理。

`--mapout` 建议始终保留到 `temp/metaphlan4/`，因为它避免同一样本在调参或重跑时重复比对。

`--samout` 建议始终生成并压缩为 `.sam.bz2`；只要团队还保留 StrainPhlAn4 路径，这个文件就是必要中间件，不应省略。

数据库版本建议与 HUMAnN3 绑定，不要在本项目内混用 vJun23 和 vOct22 的 profile。

如果样本很低深度，仍可运行 MetaPhlAn4，但更适合把它当作保守参考，不要把极低丰度物种用于后续差异分析。

对于批量项目，建议先完成全部样本的 MetaPhlAn4，再启动 `11b` 合并矩阵和 `13` 功能分析，减少重复 I/O。

## Rationale

- **为什么不直接用双文件输入**：该脚本明确说明当前部署的 MetaPhlAn4 v4.2.4 在这里采用“先合并再分析”的兼容方案，继续沿用最稳妥。
- **为什么线程不需要过高**：MetaPhlAn4 主要瓶颈是 marker 比对与后处理，超过 `16` 线程后加速通常不再线性。
- **为什么保留 `mapout`**：它缓存了 bowtie2 的中间结果，后续若需复查 profile 或比较参数，能减少重复计算。
- **为什么保留 `samout`**：StrainPhlAn4 需要 `.sam.bz2`，如果前一步不存，后面只能整步重跑。
- **为什么强调数据库版本一致**：HUMAnN3 prescreen 会读取 MetaPhlAn4 profile 头部版本标记；版本不一致会导致过滤逻辑和兼容性问题。
- **为什么适合做稳健物种谱**：MetaPhlAn4 基于特异 marker，而不是全基因组 k-mer，全局假阳性通常比宽松 k-mer 分类更低。
- **为什么低深度样本要保守解释**：marker 命中数量不足时，相对丰度估计更容易受随机采样影响，低丰度分类尤其不稳定。
- **为什么建议先跑完全队列再合并**：合并矩阵和下游功能分析都依赖单样本 profile，先把基础 taxonomy 层做完整，整体调度更清晰。
- **为什么 `--offline` 可以保留**：项目数据库是本地固定安装，离线模式避免运行时意外访问外部资源。

## Verified

**Status**: validated — 已通过实际运行验证

- 2026-06-12 — User: local, Sample: S01, Params: database=mpa_vOct22_CHOCOPhlAnSGB_202212, threads=16, input_type=fastq, Exit: 0, Duration: 84s, Workdir: ${PROJ_DIR}/Project/Project_example
  - Metrics: n_species=28, n_genus=45, total_taxa=125, top_phylum=Firmicutes (78.9%)
  - 合并双端后单文件输入方式工作正常，SAM 文件已保留供 StrainPhlAn4 使用
- 2026-06-12 — User: local, Sample: S01, Params: threads=16, database=mpa_vOct22_CHOCOPhlAnSGB_202212, input_type=fastq, analysis_type=rel_ab, Exit: 0, Duration: 84s, Workdir: ${PROJ_DIR}/Project/Project_example

## References（可选）

- `scripts/11_bac_metaphlan4.sh`
- `agents/skills/11_bac_metaphlan4.yaml`
- `scripts/12_bac_strainphlan4.sh`
- `scripts/13_bac_humann3.sh`
