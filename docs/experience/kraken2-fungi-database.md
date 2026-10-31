---
tool: "kraken2-fungi"
dimension: "mycobiome"
category: "taxonomy"
author: ""
date: "2026-06-12"
tags: [parameter-tuning, fungi-screening, bracken, pluspf-database]
scenario: [gut-microbiome, whole-genome-metagenomics, first-pass-screen]
---

# Kraken2 PlusPF 真菌快速筛查与 Bracken 重估建议

## Scenario

> 适用于在完整 FunOMIC 分析前，快速判断肠道 WGS 样本中是否存在可检测真菌信号，并获得初步属级或种级丰度参考。

典型输入是 KneadData 或同类流程去宿主后的双端 reads。该策略适合队列预筛、样本质控和计算资源规划，不建议作为 mycobiome 最终主分析。

如果使用 Kraken2 做真菌筛查，必须使用包含 fungi 的 PlusPF 数据库，而不是只覆盖细菌、古菌和病毒的 standard 数据库。

## Recommendation

推荐使用 PlusPF 数据库、`--confidence 0.1` 和 Bracken 种级重估；`--confidence` 不建议设为 `0`，否则低复杂度或近缘误配会明显增多。

```bash
# Run Kraken2 with the PlusPF database for fungal first-pass screening.
kraken2 \
  --db db/kraken2/pluspf \
  --threads 16 \
  --paired \
  result/kneaddata/sample/sample_1.kneaddata.fastq.gz \
  result/kneaddata/sample/sample_2.kneaddata.fastq.gz \
  --use-names \
  --report-zero-counts \
  --confidence 0.1 \
  --report result/fungi/kraken2/sample/sample.report \
  --output - \
  | gzip -c > result/fungi/kraken2/sample/sample.output.gz
```

种级丰度表不要直接使用 Kraken2 report，应使用 Bracken 对 reads 分配进行重新估计。

```bash
# Re-estimate abundance at species level.
bracken \
  -d db/kraken2/pluspf \
  -i result/fungi/kraken2/sample/sample.report \
  -r 150 \
  -l S \
  -t 10 \
  -o result/fungi/kraken2/sample/bracken/sample_S.bracken \
  -w result/fungi/kraken2/sample/bracken/sample_S.report

# Also keep genus and phylum summaries for robust review.
bracken -d db/kraken2/pluspf -i result/fungi/kraken2/sample/sample.report -r 150 -l G -t 10 -o result/fungi/kraken2/sample/bracken/sample_G.bracken
bracken -d db/kraken2/pluspf -i result/fungi/kraken2/sample/sample.report -r 150 -l P -t 10 -o result/fungi/kraken2/sample/bracken/sample_P.bracken
```

项目脚本已经封装该策略，可直接指定样本、线程和读长。

```bash
bash scripts/71_fun_kraken2_fungi.sh \
  -s sample \
  -t 16 \
  -w Project/Project_example \
  -r ${PROJ_DIR} \
  --confidence 0.1 \
  --read-len 150
```

解释结果时建议把 Kraken2 PlusPF 定位为 first-pass screen：若真菌 reads 极低或只出现单个可疑物种，应优先用 FunOMIC 或组装后证据复核。

## Rationale

- **为什么必须用 PlusPF**：standard Kraken2 数据库通常不包含足够 fungi 参考，PlusPF 才覆盖 fungi 和 protozoa，适合做真菌初筛。
- **为什么不把 Kraken2 作为最终主表**：PlusPF 的真菌参考仍有限，且 k-mer 分类对近缘真菌、污染序列和数据库偏倚敏感。
- **为什么 `--confidence 0.1` 合理**：该阈值能过滤一部分弱证据分类，同时不会像高置信阈值那样过度牺牲低丰度真菌召回。
- **为什么需要 Bracken**：Kraken2 report 是分类分配结果，不是严格丰度估计；Bracken 会基于 k-mer 分布重新估计 species-level abundance。
- **为什么先做快速筛查**：Kraken2 速度快，适合在全队列中判断哪些样本存在足够真菌信号，再决定是否投入 FunOMIC、组装和 MAG 回收。
- **为什么要保留属级结果**：种级结果更容易受数据库代表性影响，属级或门级结果常更稳，适合作为低信号样本的解释层级。
- **为什么低丰度阳性要谨慎**：肠道 mycobiome 往往 reads 数低，少量命中可能来自 index hopping、环境污染或误分类，需要跨工具验证。
- **为什么 read length 要匹配**：Bracken 的 `-r` 必须接近实际 read 长度，否则重估模型与数据不匹配，物种丰度会偏移。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/71_fun_kraken2_fungi.sh`
- `agents/skills/71_fun_kraken2_fungi.yaml`
- `docs/02_read_based/kraken2.md`
