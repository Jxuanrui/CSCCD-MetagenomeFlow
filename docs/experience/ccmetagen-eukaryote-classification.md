---
tool: "ccmetagen"
dimension: "mycobiome"
category: "taxonomy"
author: ""
date: "2026-06-13"
tags: [parameter-tuning, eukaryote-classification, fungi-profiling, kma-alignment]
scenario: [gut-microbiome, low-abundance-fungi, paired-end, comprehensive-profiling]
---

# CCMetagen KMA 全域真核+原核分类建议

## Scenario

> 适用于需要对宏基因组 reads 做全分类域（原核+真核）精确分类，尤其关注真菌、原虫等真核微生物的肠道样本。KMA 核心参数：`-1t1`（最佳命中单一比对）；`-mem_mode`（内存模式，加速长读段）；`-and -apm f -ef`（过滤低质量比对）；数据库使用 NCBI nt KMA 索引（约 300G）。若安装 CCMetagen.py，KMA 结果自动进入分类学解析，输出标准物种分类表和 Krona 图；否则保留 KMA .res 原始结果。CCMetagen 是无近缘参考也可分类的全域工具，与 FunOMIC 互补。

该策略无需真菌特异数据库，通过比对 NCBI nt 全库识别任意真核微生物（包括稀有真菌、原虫、寄生虫），特别适合研究非 Candida/Aspergillus 的真菌物种组成。

## Recommendation

正式分析建议通过项目脚本运行，每个样本独立分析：

```bash
# Run CCMetagen through the project wrapper.
bash scripts/76_fun_ccmetagen.sh \
  -s S01 \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

直接调用时，先运行 KMA 比对再进入 CCMetagen：

```bash
# Step 1: KMA alignment to NCBI nt database.
kma \
  -ipe result/kneaddata/S01/S01_1.kneaddata.fastq.gz \
       result/kneaddata/S01/S01_2.kneaddata.fastq.gz \
  -o result/fungi/ccmetagen/S01/temp/kma_out \
  -t_db db/kma/nt/nt \
  -t 16 \
  -1t1 \
  -mem_mode \
  -and \
  -apm f \
  -ef

# Step 2: CCMetagen classification (if available).
CCMetagen.py \
  -i result/fungi/ccmetagen/S01/temp/kma_out.res \
  -o result/fungi/ccmetagen/S01/
```

CCMetagen 输出 `*_species.txt`（物种表）和 Krona HTML 可视化；若仅有 KMA `.res` 结果，提取 template 字段也可做物种统计。

## Rationale

- **为什么用 NCBI nt 全库**：FunOMIC 和 Kraken2 PlusPF 针对特定物种有专用标记库，但真菌物种多样，近缘参考稀少；nt 全库通过全局比对有效扩大真核微生物检测范围。
- **为什么加 `-1t1`**：每条 read 仅保留最佳模板比对，避免多重比对导致的分类混淆；在参考数据库很大时尤其重要。
- **为什么加 `-mem_mode`**：内存模式把数据库索引加载到 RAM，避免频繁 I/O，在有足够内存（≥ 200G）的服务器上显著加速。
- **为什么需要 CCMetagen 而不只是 KMA**：KMA 输出是比对结果，CCMetagen 按 NCBI taxonomy 整理为标准分类层级（界/门/纲/目/科/属/种），对后续差异分析和多样性计算更友好。
- **CCMetagen 的互补定位**：FunOMIC 用物种特异 marker 做真菌定量（灵敏度高），CCMetagen 用 nt 全库做全域分类（覆盖广）；两者联合可实现互相验证，尤其是对 FunOMIC 数据库不包含的物种。
- **已知限制**：NCBI nt 全库（>300 G）对磁盘和内存要求高；首次运行需要确认数据库已建立 KMA 索引（`db/kma/nt/*.idx`）。
- **文献依据**：Marcelino et al. 2020 Bioinformatics 展示 CCMetagen 在复杂宏基因组中对真核微生物的识别优势，尤其是无近缘参考的罕见物种。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/76_fun_ccmetagen.sh`
- `scripts/02_qc_kneaddata.sh`（依赖去宿主后 reads）
- `scripts/75_fun_funomics.sh`（互补真菌标记分类）
- Marcelino et al. 2020 Bioinformatics (CCMetagen)
