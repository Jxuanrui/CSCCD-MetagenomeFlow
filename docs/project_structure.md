# MaxMetagenome 项目结构

本文档描述 MaxMetagenome 项目的完整目录结构及各部分功能。

---

## 根目录结构

```
MaxMetagenome/
├── 0Install.sh              # 环境安装主脚本
├── 1Pipeline.sh             # 参考式完整流程脚本（带详细注释）
├── CLAUDE.md                # CC 开发手册（内部）
├── README.md                # 用户手册（对外）
│
├── scripts/                 # 可执行脚本目录
│   ├── activate.sh          # 环境激活脚本
│   ├── checkm_config.sh     # CheckM 配置脚本（迁移服务器后执行）
│   ├── 00_pipeline_bacteria.sh   # 细菌维度一站式流程
│   ├── 01_qc_fastp.sh            # 质控（fastp）
│   ├── 02_qc_kneaddata.sh        # 去宿主（KneadData）
│   ├── 11_bac_metaphlan4.sh      # 细菌物种组成
│   ├── 11b_bac_metaphlan4_merge.sh # 多样本合并
│   ├── 12_bac_strainphlan4.sh    # 菌株级系统发育
│   ├── 13_bac_humann4.sh         # 功能通路定量
│   └── ...                        # 其他分析脚本
│
├── envs/                    # Conda 环境（23 个独立环境）
│   ├── humann4/
│   ├── metaphlan4/
│   ├── kneaddata/
│   └── ...
│
├── db/                      # 数据库目录
│   ├── metaphlan4/          # MetaPhlAn4 mpa_vOct22_CHOCOPhlAnSGB_202212
│   ├── humann4/
│   │   ├── chocophlan/      # 核酸数据库
│   │   ├── uniref/          # UniRef90 蛋白数据库
│   │   └── utility_mapping/ # 功能映射文件
│   ├── kneaddata/           # 宿主基因组（hg37dec_v0.1）
│   └── ...
│
├── Project/                 # 项目工作目录
│   └── Project_example/     # 示例项目
│       ├── data/            # 原始测序数据（*.fastq.gz）
│       ├── result/          # 结果输出目录
│       │   ├── qc/          # 质控结果（fastp, kneaddata）
│       │   ├── taxonomy/    # 物种分类（metaphlan4, strainphlan4）
│       │   ├── functional/  # 功能分析（humann4）
│       │   └── ...
│       ├── temp/            # 临时文件（可删除）
│       ├── samples.txt      # 样本列表
│       └── samplesheet.csv  # Pipeline 模式输入表
│
├── docs/                    # 文档目录
│   ├── WGS_integration.md   # WGS 模块融入说明
│   ├── 01_preprocessing/
│   ├── 02_read_based/
│   ├── 03_assembly/
│   ├── 04_binning/
│   ├── 05_deep_mining/
│   └── ...
│
├── Reference/               # 内部资料（仅开发用）
│   ├── EasyMetagenome.zip
│   ├── bioSkills.zip
│   ├── MetaflowX.zip
│   └── WGS_prokaryote.pipeline.v0.7.sh
│
└── Rlib/                    # R 语言包库（可选）
```

---

## 目录说明

### 核心脚本（`scripts/`）

**通用模块（01-09）**：
- `01_qc_fastp.sh`：质控（fastp）
- `02_qc_kneaddata.sh`：去宿主（KneadData + bowtie2）

**细菌维度（11-41）**：
- **物种分类**：11 MetaPhlAn4，11b 多样本合并，12 StrainPhlAn4
- **功能分析**：13 HUMAnN4
- **组装**：21 MEGAHIT，22 metaSPAdes
- **基因预测**：31 Prodigal，32 MetaGeneMark
- **MAG 挖掘**：37 MetaBAT2，38 MaxBin2，39 CONCOCT，40 DAS_Tool，41 Bakta
- **WGS 模块**：41b MLST，41c 泛基因组，41d SNP 检测

**病毒维度（51-69）**：
- 51 geNomad，52 VirSorter2，53 CheckV，54 iPHoP

**真菌维度（71-86）**：
- 71 Kraken2，72 Bracken，73 ITS 分析

### 工作目录（`Project/`）

每个项目独立一个目录，包含：
- `data/`：原始数据（软链接或实际文件）
- `result/`：分步输出结果
- `temp/`：临时文件（可定期清理）
- `samples.txt`：样本列表（逐步模式用）
- `samplesheet.csv`：样本表（Pipeline 模式用）

### 环境目录（`envs/`）

23 个独立 conda 环境，避免依赖冲突：
- `humann4`：HUMAnN4 + MetaPhlAn4 + StrainPhlAn4 + samtools + mafft + fasttree
- `metaphlan4`：MetaPhlAn4 单独环境（可选，humann4 已包含）
- `kneaddata`：KneadData + bowtie2 + trimmomatic
- `checkm2`：CheckM2 + GTDB-Tk
- `quast`：QUAST + MetaQUAST
- ...（其他专用环境）

### 数据库（`db/`）

**必需数据库**：
- `metaphlan4/`：~10 GB，mpa_vOct22_CHOCOPhlAnSGB_202212
- `humann4/chocophlan/`：~16 GB
- `humann4/uniref/`：~11 GB（uniref90_diamond）
- `kneaddata/`：~3 GB（hg37dec_v0.1 人类基因组）

**可选数据库**（按需下载）：
- `checkm2/`：CheckM2 数据库
- `gtdbtk/`：GTDB-Tk 参考数据
- `kraken2/`：Kraken2 标准库
- ...

---

## 文件命名规范

**原始数据**：
- 双端测序：`{SAMPLE}_1.fastq.gz`、`{SAMPLE}_2.fastq.gz`
- 单端测序：`{SAMPLE}.fastq.gz`

**中间结果**：
- fastp 输出：`{SAMPLE}_1.fastq.gz`（与原始数据同名，但在不同目录）
- kneaddata 输出：`{SAMPLE}_1.kneaddata.fastq.gz`

**最终结果**：
- MetaPhlAn4：`{SAMPLE}_profile.txt`
- HUMAnN4：`{SAMPLE}_pathabundance.tsv`、`{SAMPLE}_genefamilies.tsv`

---

## 磁盘空间需求

**最小配置（示例数据集，3 个样本，每样本 6GB）**：
- 环境：~30 GB
- 数据库：~45 GB
- 项目数据：~50 GB（原始 + 中间 + 结果）
- **合计**：~125 GB

**生产环境（100 个样本，每样本 10GB）**：
- 环境：~30 GB
- 数据库：~45 GB
- 项目数据：~2 TB（原始 1TB + 中间/结果 1TB）
- **合计**：~2.1 TB

**建议**：
- 系统盘（/）：≥ 100 GB
- 数据盘：≥ 实际数据量 × 2.5（原始 + 中间 + 结果）

---

## 迁移与备份

**跨服务器迁移**：
1. 打包整个项目目录（tar + rsync）
2. 解包后执行 `bash scripts/checkm_config.sh`（重新配置 CheckM）
3. 执行 `source scripts/activate.sh`

**备份策略**：
- **必须备份**：`scripts/`、`Project/*/result/`、`CLAUDE.md`、`README.md`
- **可选备份**：`envs/`、`db/`（可从源重新下载）
- **不备份**：`Project/*/temp/`、`Reference/`

---

## 参考

- 用户手册：[README.md](../README.md)
- 开发手册：[CLAUDE.md](../CLAUDE.md)（内部）
- WGS 模块融入：[docs/WGS_integration.md](WGS_integration.md)
