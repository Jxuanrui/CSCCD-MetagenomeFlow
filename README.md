# MaxMetagenome — 宏基因组深度挖掘分析平台

**作者**: Jxuanrui  
**版本**: 0.1  **日期**: 2026-06-02  
**平台**: Linux x86_64 (Ubuntu 22.04+)  
**环境管理**: Miniforge3（自包含，支持跨服务器迁移）

---

## 项目概述

MaxMetagenome 是一个综合性宏基因组深度挖掘分析平台，整合了以下三个参考项目的分析模块：

- **EasyMetagenome**：标准宏基因组分析流程（质控→读长分析→组装→分箱）
- **Metagenomics_Apptainer_pipline**：基于 Apptainer 的宏基因组序列和功能注释流程
- **Binning_Apptainer_pipline**：MAG 挖掘及深度功能注释流程

覆盖从原始测序数据到功能注释、MAG 挖掘、深度生态学解析的完整分析体系。

---

## 快速启动

```bash
# 每次分析前执行（激活项目环境）
source ~/Course/Maxmetagenome/scripts/activate.sh

# 首次迁移到新服务器后执行一次
bash ~/Course/Maxmetagenome/scripts/checkm_config.sh
```

---

## 分析流程总览

```
原始测序数据（*.fq.gz）
        │
        ▼
  ┌──────────────────────┐
  │  第一阶段：数据预处理  │  fastp + KneadData
  └──────────────────────┘
        │
   ┌────┴────┐
   ▼         ▼
Read-based  Assembly-based
 分析        分析
   │         │
   │         ├── 基因预测+功能注释
   │         ├── MAG 挖掘（Binning）
   │         └── MAG 深度注释
   │
   └── 物种+功能+多样性+差异分析
        │
        ▼
   深度挖掘（宏病毒组/AMR/共现网络）
        │
        ▼
   统计分析与可视化（R）
```

---

## 第一阶段：数据预处理

### 1.1 质量控制
- **工具**: fastp 0.22.0（`envs/fastp`）
- **功能**: 双端测序质控、接头去除、低质量碱基修剪
- **输入**: `seq/*.fq.gz` → **输出**: `temp/fastp/`

### 1.2 宿主去除
- **工具**: KneadData v0.12.4 + Bowtie2（`envs/kneaddata`）
- **支持物种**: 人类（hg37，`db/kneaddata/human/`）、小鼠（C57BL/6NJ，`db/kneaddata/mouse/`）、大鼠（Rnor_6.0，`db/kneaddata/rat/`）
- **输出**: `temp/kneaddata/`（clean reads）

---

## 第二阶段：Read-based 分析

### 2.1 物种组成

| 工具 | 版本 | 环境 | 数据库 | 特点 |
|------|------|------|--------|------|
| HUMAnN v3.9 | + MetaPhlAn4 v4.2.4 | `envs/humann4` | `db/humann4/`（52G）+ `db/metaphlan4/`（40G） | 物种+功能联合分析 |
| Kraken2 2.1.3 | + Bracken 3.1 | `envs/kraken2` | `db/kraken2/pluspf/`（77G） | k-mer 高速分类 |
| Centrifuger 1.0.5 | — | `envs/assembly` | `db/centrifuger/`（166G，GTDB R226+RefSeq） | 蛋白级别精确分类 |

### 2.2 多样性分析
- **Alpha 多样性**: Shannon、Simpson、Chao1、ACE、Richness
- **Beta 多样性**: Bray-Curtis PCoA、Jaccard NMDS
- **工具**: vegan 2.7.5、phyloseq 1.54.2（R，`Rlib/`）

### 2.3 差异分析
- **ANCOM-BC2** 2.12.0：组分偏差校正（推荐）
- **DESeq2** 1.50.2 / **edgeR** 4.8.2：负二项分布模型
- **LEfSe** 1.1.2（`envs/lefse`）：线性判别分析
- **MaAsLin2** 1.24.1：多变量关联分析

### 2.4 菌株级分辨率
- **StrainPhlAn4** v4.2.4（复用 `envs/humann4`）

---

## 第三阶段：Assembly-based 分析

### 3.1 基因组组装

| 工具 | 版本 | 环境 | 说明 |
|------|------|------|------|
| MEGAHIT | 1.2.9 | `envs/assembly` | 主要组装，内存高效 |
| metaSPAdes | 3.15.5 | `envs/assembly` | 精细组装（可选） |
| QUAST | 5.0.2 | `envs/assembly` | 组装质量评估 |

### 3.2 基因预测与定量

| 工具 | 版本 | 环境 | 功能 |
|------|------|------|------|
| Prodigal | 2.6.3 | `envs/assembly` | 蛋白编码基因预测 |
| CD-HIT | 4.8.1 | `envs/assembly` | 基因去冗余（95% 同一性） |
| Salmon | 1.2.0 | `envs/assembly` | 基因丰度定量（TPM） |
| mmseqs2 | 13.45 | `envs/assembly` | 高效序列搜索 |
| seqtk | 1.4 | `envs/assembly` | FASTA/FASTQ 处理 |
| CoverM | 0.7.0 | `envs/coverm` | 覆盖度计算 |

### 3.3 功能基因注释

所有注释基于预测蛋白序列，使用 diamond/mmseqs2 同源搜索：

| 注释类型 | 工具/数据库 | 路径 | 大小 |
|---------|-----------|------|------|
| 综合功能（COG/KEGG/GO/EC） | eggNOG-mapper 2.1.13 | `db/eggnog/` | 48G |
| 代谢通路（KO） | KEGG diamond | `db/kegg/` | 48G |
| 抗生素耐药 | AMRFinder 3.10.1 | `db/amrfinder/` | 488M |
| 抗生素耐药 | RGI 4.0.3 + CARD | `db/card/` | 48M |
| 重金属抗性 | BacMet | `db/bacmet/` | 867M |
| 污水抗性 | SARG+ | `db/sarg/` | 264M |
| 毒力因子 | VFDB | `db/vfdb/` | 2.0G |
| 植物-微生物互作 | PHI | `db/phi/` | 946M |
| 微生物病毒 | mVIRdb | `db/mvirdb/` | 1.2G |
| 蛋白酶 | MEROPS | `db/merops/` | 3.7G |
| 碳水化合物酶 | dbCAN3 3.0.7 | `db/dbcan3/` | 3.5G |
| 转运载体 | TCDB | `db/tcdb/` | 982M |
| 氮循环 | NCyc | `db/ncyc/` | 214M |
| 磷循环 | PCyc | `db/pcyc/` | 846M |
| 碳循环 | CCyc | `db/ccyc/` | 12G |
| 甲烷循环 | MCyc | `db/mcyc/` | 638M |
| 硫循环 | SCyc | `db/scyc/` | 642M |
| 次级代谢产物 | antiSMASH 7.1.0 | `db/antismash/` | 9.4G |
| 可移动遗传元素 | MobileOG-db | `db/mobileog/` | 19G |

---

## 第四阶段：MAG 挖掘（Binning）

### 4.1 多算法并行分箱

| 工具 | 版本 | 环境 | 算法原理 |
|------|------|------|----------|
| MetaBAT2 | 2.12.1 | `envs/metawrap` | 深度+四核苷酸频率 |
| MaxBin2 | 2.2.6 | `envs/metawrap` | 丰度+组成信息 |
| SemiBin2 | 1.5.0 | `envs/semibin` | 机器学习（自训练模型） |
| MetaWRAP | 1.3.2 | `envs/metawrap` | 多算法整合框架 |
| DAS_Tool | 1.1.7 | `envs/dastool` | 综合优化，去除冗余 bins |

### 4.2 MAG 质量评估与去冗余

| 工具 | 版本 | 环境 | 数据库 | 功能 |
|------|------|------|--------|------|
| CheckM2 | 1.0.1 | `envs/checkm2` | `db/checkm2/`（2.9G） | 完整度/污染率评估（ML） |
| CheckM（内置） | 1.2.5 | `envs/metawrap` | `db/checkm/`（1.7G） | MetaWRAP 内部调用 |
| dRep | 3.6.2 | `envs/drep` | — | ANI 97% 去冗余 |

**MAG 质量标准**：高质量（完整度≥90%，污染率<5%）/ 中等质量（完整度≥50%，污染率<10%）

### 4.3 MAG 分类学注释
- **GTDB-Tk** 2.5.2（`envs/gtdbtk`），数据库 `db/gtdbtk/`（160G，GTDB R214）

### 4.4 MAG 定量
- **CoverM** 0.7.0（`envs/coverm`）：各样本 MAG 相对丰度
- **Salmon** 1.2.0（`envs/assembly`）：基因 TPM 定量

### 4.5 MAG 深度功能注释

对每个高质量 MAG 进行全面功能注释（共用 §3.3 工具库），额外包括：

| 工具 | 版本 | 环境 | 功能 |
|------|------|------|------|
| Bakta | 1.12.0 | `envs/bakta` | 全基因组精细注释（含 `db/bakta/` 3.8G） |
| Defense-Finder | 3.0.0 | `envs/defense-finder` | CRISPR/防御系统（`db/defense-finder/` 320M） |
| geNomad | 1.12.0 | `envs/genomad` | 病毒/质粒鉴定（`db/genomad/` 3.7G） |
| antiSMASH | 7.1.0 | `envs/antismash` | BGC 鉴定与分类（`db/antismash/` 9.4G） |

---

## 第五阶段：深度挖掘

### 5.1 宏病毒组分析

| 工具 | 版本 | 环境 | 数据库 | 功能 |
|------|------|------|--------|------|
| VIBRANT | 1.2.1 | `envs/vibrant` | `db/vibrant/`（~11G） | 病毒序列鉴定 |
| CheckV | 1.1.1 | `envs/checkv` | `db/checkv/` | 病毒 MAG 质量评估 |
| geNomad | 1.12.0 | `envs/genomad` | `db/genomad/`（3.7G） | 病毒/质粒检测 |

### 5.2 抗性基因与移动遗传元素

| 工具/数据库 | 版本 | 环境/路径 | 说明 |
|------------|------|----------|------|
| AMRFinder | 3.10.1 | `envs/amr` / `db/amrfinder/` | NCBI 官方 AMR |
| RGI + CARD | 4.0.3 | `envs/amr` / `db/card/` | 综合抗性基因数据库 |
| BacMet | — | `db/bacmet/` | 重金属抗性基因 |
| SARG+ | — | `db/sarg/` | 污水/环境抗性基因 |
| MobileOG-db | — | `db/mobileog/`（19G） | 可移动遗传元素（diamond 搜索） |
| Defense-Finder | 3.0.0 | `envs/defense-finder` | 防御系统/CRISPR |

### 5.3 次级代谢产物
- **antiSMASH** 7.1.0（`envs/antismash`）：BGC 鉴定，数据库 `db/antismash/`（9.4G）

### 5.4 共现网络分析
- **FastSpar（SparCC）** 1.0.0（`envs/network`）：稀疏相关性共现网络

### 5.5 物种系统发育
- **Centrifuger** 1.0.5：蛋白级别精确分类，`db/centrifuger/`（166G，GTDB R226+RefSeq）

---

## 第六阶段：统计分析与可视化

### R 包环境（`Rlib/`，conda R 4.5.1）

| 包 | 版本 | 用途 |
|---|---|---|
| vegan | 2.7.5 | 多样性分析、置换检验 |
| phyloseq | 1.54.2 | 微生物组数据框架 |
| ggplot2 | 4.0.3 | 可视化基础 |
| DESeq2 | 1.50.2 | 差异丰度分析 |
| edgeR | 4.8.2 | 差异丰度分析 |
| ANCOMBC | 2.12.0 | 组分偏差校正差异分析（推荐） |
| MaAsLin2 | 1.24.1 | 多变量关联分析 |
| ggtree | 4.0.4 | 进化树可视化 |
| treeio | 1.34.0 | 进化树数据读取 |
| microbiome | 1.32.0 | 微生物组工具集 |
| dplyr / tidyr | 1.2.1 / 1.3.2 | 数据处理 |
| pheatmap | 1.0.13 | 聚类热图 |
| ggpubr | 0.6.3 | 统计图形 |
| patchwork | 1.3.2 | 图形布局 |
| ggalluvial | 0.12.6 | 桑基图 |
| UpSetR | 1.4.1 | UpSet 图 |

> **执行方式**: `~/Course/Maxmetagenome/miniforge3/bin/Rscript`（conda R 4.5.1，而非系统 R）

---

## 环境与数据库一览

### Conda 环境（23个，全部在 `envs/` 下）

| 环境 | 主要工具 | 版本 |
|------|---------|------|
| `fastp` | fastp | 0.22.0 |
| `kneaddata` | kneaddata, bowtie2, trimmomatic | v0.12.4 |
| `humann4` | humann, metaphlan, strainphlan4, diamond | v3.9 / v4.2.4 |
| `lefse` | lefse | 1.1.2 |
| `kraken2` | kraken2, bracken | 2.1.3 / 3.1 |
| `assembly` | megahit, spades, prodigal, cd-hit, salmon, centrifuger, mmseqs2, seqtk | 多版本 |
| `eggnog` | eggnog-mapper | 2.1.13 |
| `metawrap` | metawrap, metabat2, maxbin2, checkm | 1.3.2 |
| `semibin` | semibin | 1.5.0 |
| `dastool` | das_tool | 1.1.7 |
| `drep` | drep, checkm-genome | 3.6.2 |
| `coverm` | coverm | 0.7.0 |
| `gtdbtk` | gtdbtk | 2.5.2 |
| `checkm2` | checkm2 | 1.0.1 |
| `vibrant` | vibrant | 1.2.1 |
| `checkv` | checkv | 1.1.1 |
| `amr` | amrfinder, rgi | 3.10.1 / 4.0.3 |
| `dbcan` | dbcan | 3.0.7 |
| `antismash` | antismash | 7.1.0 |
| `network` | fastspar | 1.0.0 |
| `genomad` | genomad | 1.12.0 |
| `bakta` | bakta | 1.12.0 |
| `defense-finder` | defense-finder | 3.0.0 |

### 数据库一览（总计 ~700G，全部在 `db/` 下）

| 数据库 | 路径 | 大小 | 用途 |
|-------|------|------|------|
| KneadData | `db/kneaddata/` | 11G | 去宿主（人/鼠/鼠） |
| HUMAnN4 | `db/humann4/` | 52G | 物种+功能 |
| MetaPhlAn4 | `db/metaphlan4/` | 40G | 物种分类 |
| Kraken2 PlusPF | `db/kraken2/` | 77G | 快速分类 |
| Centrifuger | `db/centrifuger/` | 166G | GTDB R226+RefSeq |
| eggNOG | `db/eggnog/` | 48G | 综合功能注释 |
| KEGG | `db/kegg/` | 48G | 代谢通路 |
| CheckM | `db/checkm/` | 1.7G | MAG 质量（旧版） |
| CheckM2 | `db/checkm2/` | 2.9G | MAG 质量（ML） |
| GTDB-Tk | `db/gtdbtk/` | 160G | 系统发育分类（R214） |
| CARD | `db/card/` | 48M | 抗生素耐药 |
| AMRFinder | `db/amrfinder/` | 488M | NCBI AMR |
| BacMet | `db/bacmet/` | 867M | 重金属抗性 |
| SARG+ | `db/sarg/` | 264M | 污水 AMR |
| VFDB | `db/vfdb/` | 2.0G | 毒力因子 |
| PHI | `db/phi/` | 946M | 病原互作 |
| mVIRdb | `db/mvirdb/` | 1.2G | 微生物病毒 |
| MEROPS | `db/merops/` | 3.7G | 蛋白酶 |
| dbCAN3 | `db/dbcan3/` | 3.5G | CAZyme |
| TCDB | `db/tcdb/` | 982M | 转运载体 |
| NCyc | `db/ncyc/` | 214M | 氮循环 |
| PCyc | `db/pcyc/` | 846M | 磷循环 |
| CCyc | `db/ccyc/` | 12G | 碳循环 |
| MCyc | `db/mcyc/` | 638M | 甲烷循环 |
| SCyc | `db/scyc/` | 642M | 硫循环 |
| antiSMASH | `db/antismash/` | 9.4G | BGC（生物合成基因簇） |
| MobileOG | `db/mobileog/` | 19G | 可移动遗传元素 |
| geNomad | `db/genomad/` | 3.7G | 病毒/质粒 |
| VIBRANT | `db/vibrant/` | 11G | 病毒鉴定（HMM，KEGG+VOG+Pfam） |
| Bakta | `db/bakta/` | 3.8G | 基因组注释 |
| Defense-Finder | `db/defense-finder/` | 320M | 防御系统 |

---

## 项目结构

```
MaxMetagenome/
├── 0Install.sh          # 完整安装脚本（§0-§8，含所有工具和数据库）
├── README.md            # 本文档
├── CLAUDE.md            # CC/Codex 协作规范
│
├── scripts/             # 辅助脚本
│   ├── activate.sh      # 会话激活（每次分析前执行 source）
│   └── checkm_config.sh # CheckM 数据库路径配置（迁移新服务器后执行一次）
│
├── miniforge3/          # Miniforge3 自包含环境（27G）
├── envs/                # 23 个 conda 独立工具环境（23G）
├── db/                  # 所有分析数据库（~700G，31 个数据库）
├── Rlib/                # R 包库（conda R 4.5.1，297 个包，1.4G）
│
├── docs/                # RAG 知识库文档（待完善）
│   ├── 01_preprocessing/
│   ├── 02_read_based/
│   ├── 03_assembly/
│   ├── 04_binning/
│   ├── 05_deep_mining/
│   ├── 06_multiomics/
│   └── tools_ref/
│
├── mcp/                 # MCP 服务器（§9，待配置）
├── tools/               # 辅助工具脚本（§9 MCP 服务器将放置于此）
│
├── seq/                 # 原始测序数据（*.fq.gz）
├── temp/                # 分析中间文件（分析完成后可删）
├── result/              # 最终分析结果
└── Reference/           # 参考项目（EasyMetagenome.zip）
```

---

## 安装状态

详见 `0Install.sh` 头部进度表，最新状态（2026-06-02）：

- ✅ §0-§8.8 全部完成并测试通过（含 VIBRANT 数据库 11G，antiSMASH 数据库 9.4G）
- ⏳ §9 MCP/RAG 服务（待配置）
