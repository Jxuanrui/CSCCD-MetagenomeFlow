# MaxMetagenome — 完整宏基因组多维度分析平台

**作者**: Jxuanrui  
**版本**: v1.0.0  **日期**: 2026-06-12  
**平台**: Linux x86_64 (Ubuntu 22.04+)  
**环境管理**: Miniforge3（自包含，支持跨服务器迁移）

---

## 项目概述

MaxMetagenome 是一个面向肠道微生物组研究的**完整多维度宏基因组分析平台**，覆盖从原始测序数据到论文级统计可视化的全流程，支持三大生命域并行分析。

**核心指标**:
- **87 个分析脚本**（01-98 编号，逐步执行）
- **83 条 Snakemake 规则**（全流程 DAG，8 个规则文件）
- **37 个独立 conda 环境**（工具隔离，避免依赖冲突）
- **~700G 分析数据库**（含 ChocoPhlAn、UniRef90、GTDB R226、VOGDB 等）
- **15 个 Claude Code 斜杠命令**（`/mgx-*` 前缀，AI 辅助分析）
- **RAG 知识库**（经验文档 + 文献 Methods 索引，ChromaDB + bge-small-zh-v1.5）

**设计原则**：一套脚本库，三种运行模式，零重复劳动。

---

## 三大分析维度

| 维度 | 脚本范围 | 覆盖内容 |
|------|----------|----------|
| **🦠 细菌（Bacteria）** | 11 – 41d | 物种分类 · 菌株追踪 · 功能通路 · 组装 · MAG 挖掘 · 耐药 · 毒力 · CAZyme · 次级代谢 · WGS 融合 |
| **🦠 病毒（Virome）** | 51 – 69 | 病毒鉴定 · vOTU 聚类 · 宿主预测 · 生活方式 · 基因组注释 · 宿主范围 |
| **🍄 真菌（Mycobiome）** | 71 – 86 | 多策略分类 · 真菌组装 · MAG 回收 · CAZyme · 毒力因子 · 蛋白酶 · AMR |
| **📊 统计分析** | 91 – 98 | Alpha/Beta 多样性 · 差异分析 · 批次校正 · ML 分类器 · 跨队列验证 · 报告生成 |

---

## 快速启动

### 1. 激活项目环境（每次分析前执行）

```bash
source ~/Course/Maxmetagenome/scripts/activate.sh

# 首次迁移到新服务器后额外执行一次
bash ~/Course/Maxmetagenome/scripts/checkm_config.sh
```

### 2. 三种运行模式

**模式一：逐步运行（研究级精细调控）**

每步独立运行，参数可精细调控，适合单步调试或探索性分析。

```bash
# 质控
bash scripts/01_qc_fastp.sh       -s SAMPLE_ID -t 16 -w /path/to/workdir -r ~/Course/Maxmetagenome
# 去宿主
bash scripts/02_qc_kneaddata.sh   -s SAMPLE_ID -t 16 -w /path/to/workdir -r ~/Course/Maxmetagenome
# 物种分类
bash scripts/11_bac_metaphlan4.sh -s SAMPLE_ID -t 16 -w /path/to/workdir -r ~/Course/Maxmetagenome
```

**模式二：Bash 一站式流程（轻量，无额外依赖）**

无需 Snakemake，传入 samplesheet.csv 串联步骤，支持断点续跑。

```bash
# 运行完整细菌流程
bash scripts/00_pipeline_bacteria.sh \
     -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16

# 断点续跑（从 metaphlan4 步骤开始）
bash scripts/00_pipeline_bacteria.sh \
     -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 --from metaphlan4

# 多样本并行（需要 rush）
bash scripts/00_pipeline_bacteria.sh \
     -i samplesheet.csv -r ~/Course/Maxmetagenome -t 16 -j 2
```

可用流程脚本：

| 脚本 | 覆盖步骤 |
|------|---------|
| `00_pipeline_bacteria.sh` | 01-02 + 11-41 |
| `00_pipeline_virome.sh` | 01-02 + 51-69 |
| `00_pipeline_fungi.sh` | 01-02 + 71-86 |
| `00_pipeline_full.sh` | 三维度完整流程 |

**模式三：Snakemake Pipeline（生产级，推荐大批量）**

基于 DAG 的自动依赖追踪，原生断点续跑，支持 HPC。

```bash
# 1. 编辑运行参数
vim pipeline/config/config.yaml     # 填写 samples / workdir / cpus

# 2. 预演（检查 DAG，不实际运行）
snakemake -s pipeline/Snakefile \
  --configfile pipeline/config/config.yaml --dry-run

# 3. 正式运行
snakemake -s pipeline/Snakefile \
  --configfile pipeline/config/config.yaml \
  -j 16 --rerun-incomplete
```

> Snakemake 已安装在项目内 miniforge3 base 环境中，`source activate.sh` 后直接可用。

---

## 分析脚本索引

### 通用预处理（共享）

| 编号 | 功能 | 工具 |
|------|------|------|
| 01 | 质量控制（接头去除、低质碱基修剪） | fastp |
| 02 | 去宿主（人/鼠/大鼠） | KneadData + bowtie2 |

### 🦠 细菌维度（11-41）

| 编号 | 功能 | 工具 |
|------|------|------|
| 11/11b | 物种组成 + 多样本合并 | MetaPhlAn4 |
| 12 | 菌株追踪与系统发育 | StrainPhlAn4 |
| 13 | 功能通路定量 | HUMAnN3 v3.9 |
| 14 | 快速物种分类（k-mer） | Kraken2 + Bracken |
| 15 | 蛋白级精确分类（GTDB R226） | Centrifuger |
| 16-20 | 组装 → 基因预测 → 去冗余 → 定量 | MEGAHIT · Prodigal · CD-HIT · Salmon |
| 21-31 | 综合功能注释（COG/KEGG/GO/EC/AMR/CAZyme/毒力/BGC） | eggNOG · KEGG · AMRFinder · CARD · dbCAN · VFDB · BacMet · antiSMASH · Defense-Finder · NCyc · PCyc |
| 32-41 | MAG 挖掘（分箱→整合→质控→去冗余→定量→分类→注释） | CoverM · MetaBAT2 · MaxBin2 · SemiBin2 · DAS_Tool · CheckM2 · dRep · GTDB-Tk · Bakta |
| 41b | MLST 多位点序列分型（WGS 融入） | mlst 2.11 |
| 41c | 泛基因组分析（WGS 融入） | Roary 3.12.0 |
| 41d | SNP/InDel 变异检测（WGS 融入） | Snippy 4.0.2 |

### 🦠 病毒维度（51-69）

| 编号 | 功能 | 工具 |
|------|------|------|
| 51-55 | 组装 → 鉴定（双引擎共识）→ 质控 → 蛋白预测 | MEGAHIT · geNomad · VirSorter2 · CheckV · Prodigal-gv |
| 56-60 | vOTU 聚类 → 分类 → 丰度定量 → 丰度矩阵 | vclust · geNomad · Salmon |
| 61-63 | vMAG 重建 → 质控 → 丰度定量 | vmag · CheckV · CoverM |
| 64-69 | 全面注释（含结构暗物质）→ 生活方式 → 宿主 → 分类网络 | PHAROKKA · PHOLD · VOGDB · BACPHLIP · iPHoP · vConTACT3 |

### 🍄 真菌维度（71-86）

| 编号 | 功能 | 工具 |
|------|------|------|
| 71-77 | 多策略分类（5 种互补方法） | Kraken2 · MetaPhlAn4 · HUMAnN4 · BLAST · FunOMIC · MicroFisher |
| 78-80 | 真菌组装 → MAG 回收 → 基因预测 | MEGAHIT · Eukfinder · Prodigal |
| 81-86 | 功能注释（COG/KEGG/CAZyme/毒力/AMR/蛋白酶） | eggNOG · KEGG · dbCAN3 · VFDB · AMRFinder · MEROPS |

### 📊 统计分析（91-98）

| 编号 | 功能 | 工具 |
|------|------|------|
| 91 | Alpha/Beta 多样性 | vegan/phyloseq (R) |
| 92 | 差异分析（LEfSe/ANCOM-BC2/DESeq2/edgeR/MaAsLin2） | R |
| 93 | 跨维度共现网络 | FastSpar/SparCC |
| 94 | 统一可视化（热图/PCoA/桑基图/UpSet） | ggplot2 (R) |
| 95a/95b | 批次校正（Top10 方法）→ 评估报告 | MBECS/ConQuR/MMUPHin (R) |
| 96 | ML 筛选 + ROC 评估（lasso/RF/SVM/enet） | SIAMCAT (R) |
| 97 | 跨队列一致性验证 | curatedMetagenomicData/SIAMCAT (R) |
| 98 | Markdown 快照报告 | bash + Rscript |

---

## Claude Code AI 辅助功能

本平台内置 15 个 Claude Code 斜杠命令，部署后在 Claude Code 中直接使用：

```
/mgx-welcome          — 显示欢迎页（平台概览 + 快速上手）
/mgx-ask <问题>       — 查询 RAG 知识库（经验 + 文献）
/mgx-plan             — 生成分析方案
/mgx-run              — 执行分析命令
/mgx-status           — 查看流程进度
/mgx-integrate        — 集成新分析脚本
/mgx-plot-ordination  — PCoA/NMDS 排序图
/mgx-plot-composition — 物种组成图
/mgx-plot-diversity   — Alpha 多样性图
/mgx-plot-heatmap     — 注释热图
/mgx-plot-network     — 共现网络图
/mgx-plot-phylotree   — 系统发育树
/mgx-plot-volcano     — 差异丰度图
/graphify             — 知识图谱构建
```

### RAG 知识库

- **经验知识库**：团队经验文档（`docs/experience/`）+ 工具文档 + 脚本参数 + 技能卡
- **文献知识库**：44 篇高分宏基因组方法学文献（PMC OA，Methods 节索引）
- **嵌入模型**：`BAAI/bge-small-zh-v1.5`（中英双语，384 维）

---

## 目录结构

```
MaxMetagenome/
├── scripts/          # 87 个分析脚本（01-98 编号）
├── pipeline/         # Snakemake DAG 流程（8 个规则文件）
│   ├── Snakefile
│   ├── config/config.yaml
│   └── rules/        # preprocessing · bacteria_taxonomy · bacteria_assembly
│                     # bacteria_annotation · bacteria_binning · virome
│                     # mycobiome · statistics · rag
├── agents/
│   ├── registry.yaml # 全局脚本状态追踪（87 条目）
│   └── skills/       # 82 个工具卡片（YAML）
├── .claude/
│   ├── commands/     # 15 个用户斜杠命令（/mgx-*）
│   └── skills/       # 15 个 CC 内部技能文件
├── docs/
│   ├── 01_preprocessing/ · 02_read_based/ · 03_assembly/
│   ├── 04_binning/  · 05_virus/ · 05_stats/ · 05_deep_mining/
│   ├── experience/   # 12 个团队经验文档（可编辑，自动索引到 RAG）
│   └── project_structure.md
├── mcp/              # RAG MCP 服务（ChromaDB + 文献 Pipeline）
├── skills/           # 外部技能发现系统
├── 0Install.sh       # 环境 & 数据库安装主脚本（§1-§15）
├── CLAUDE.md         # CC + Codex 协作手册
└── README.md         # 本文件
```

---

## 磁盘空间需求

| 组件 | 空间 | 说明 |
|------|------|------|
| miniforge3 + 37 envs | ~50 GB | conda 工具环境，自包含 |
| db/ 数据库 | ~700 GB | 见分析脚本索引 |
| Project 数据（100 样本） | ~2 TB | 原始 ~1TB + 中间/结果 ~1TB |
| scripts + pipeline + docs | < 50 MB | git 追踪部分 |

---

## 迁移到新服务器

```bash
# 1. 克隆仓库
git clone git@gitee.com:JXR1314/meta-servergenome.git
cd meta-servergenome

# 2. 安装环境（首次，约数小时）
bash 0Install.sh

# 3. 激活并验证
source scripts/activate.sh
bash scripts/checkm_config.sh

# 4. 验证 Claude Code 集成（开发环境）
claude mcp list   # 应看到 codex: ✓ Connected
```

---

## 经验文档贡献

在 `docs/experience/` 目录按 `TEMPLATE.md` 格式添加 `.md` 文件，保存后运行：

```bash
conda run --prefix miniforge3 python mcp/indexer.py
```

即可同步到 RAG 知识库，`/mgx-ask` 可直接检索该经验。

---

## 参考工具

MetaPhlAn4 · HUMAnN3 · Kraken2/Bracken · Centrifuger · MEGAHIT · Prodigal · CD-HIT · Salmon · eggNOG-mapper · AMRFinderPlus · CARD/RGI · dbCAN3 · antiSMASH · MetaBAT2 · SemiBin2 · DAS_Tool · CheckM2 · dRep · GTDB-Tk · Bakta · mlst · Roary · Snippy · geNomad · VirSorter2 · CheckV · iPHoP · vConTACT3 · PHAROKKA · PHOLD · VOGDB · BACPHLIP · FunOMIC · MicroFisher · Eukfinder · MEROPS · SIAMCAT · DESeq2 · MMUPHin · ConQuR
