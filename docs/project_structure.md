# MaxMetagenome 项目结构

本文档描述 MaxMetagenome 项目的完整目录结构及各部分功能。最后更新：2026-06-06。

---

## 根目录结构

```
MaxMetagenome/
├── 0Install.sh              # 环境 & 数据库安装主脚本（分节，§1-§9）
├── CLAUDE.md                # CC + Codex 开发手册（内部）
├── README.md                # 用户手册（对外）
│
├── scripts/                 # 分析脚本（单步骤一文件，编号 01-98）
│   ├── activate.sh                   # 环境激活（每次分析前执行）
│   ├── checkm_config.sh              # CheckM2 路径配置（迁移后执行）
│   ├── 00_pipeline_bacteria.sh       # 细菌维度一站式 Bash 流程
│   ├── 00_pipeline_virome.sh         # 病毒维度一站式 Bash 流程（待完善）
│   ├── 00_pipeline_fungi.sh          # 真菌维度一站式 Bash 流程（待完善）
│   ├── 00_pipeline_full.sh           # 三维度全流程 Bash 脚本
│   ├── 01_qc_fastp.sh                # 质控（fastp）
│   ├── 02_qc_kneaddata.sh            # 去宿主（KneadData + bowtie2）
│   ├── 11_bac_metaphlan4.sh          # 细菌物种组成（MetaPhlAn4，菌株级）
│   ├── 11b_bac_metaphlan4_merge.sh   # 多样本 profile 合并
│   ├── 12_bac_strainphlan4.sh        # 菌株追踪与系统发育（StrainPhlAn4）
│   ├── 13_bac_humann3.sh             # 功能通路定量（HUMAnN3 v3.9，支持 speed-mode）
│   └── ...                           # 14-98 待开发（见 CLAUDE.md §14.2）
│
├── pipeline/                # Snakemake 生产级流程（Mode 3）
│   ├── Snakefile            # 入口（-s pipeline/Snakefile 调用）
│   ├── config/
│   │   └── config.yaml      # 运行参数（samples / workdir / cpus / humann_speed）
│   └── rules/
│       ├── preprocessing.smk       # 规则：fastp_qc, kneaddata
│       └── bacteria_taxonomy.smk   # 规则：metaphlan4, metaphlan4_merge, strainphlan4, humann3, kraken2
│
├── agents/                  # Agent Skills 系统（CC 交互式驱动）
│   ├── registry.yaml        # 全局脚本状态（78 条目：7 integrated / 71 not_started）
│   ├── skills/              # 工具卡片（每个已集成脚本一份 YAML）
│   │   ├── _template.yaml
│   │   ├── 01_qc_fastp.yaml
│   │   ├── 02_qc_kneaddata.yaml
│   │   ├── 11_bac_metaphlan4.yaml
│   │   ├── 11b_bac_metaphlan4_merge.yaml
│   │   ├── 12_bac_strainphlan4.yaml
│   │   ├── 13_bac_humann3.yaml
│   │   └── 14_bac_kraken2.yaml
│   └── provenance/          # 运行记录（exit_code / runtime / memory，/mgx-learn 写入）
│
├── .claude/
│   └── skills/              # Claude Code 可调用技能（/mgx-* 前缀）
│       ├── mgx-integrate.md # 新脚本集成工作流
│       ├── mgx-review.md    # Snakemake rule 验证
│       ├── mgx-run.md       # 通过 Codex 执行分析步骤
│       ├── mgx-plan.md      # 分析计划生成
│       ├── mgx-status.md    # 项目进度报告
│       └── mgx-learn.md     # 运行后写入 provenance 记录
│
├── docs/                    # 工具文档与技术说明
│   ├── project_structure.md         # 本文件
│   ├── 01_preprocessing/            # fastp, kneaddata 文档
│   ├── 02_read_based/               # 物种分类 & 功能分析文档
│   │   └── humann3_speed_optimization.md
│   ├── 03_assembly/                 # 组装流程文档
│   ├── 04_binning/                  # MAG 挖掘文档
│   ├── 05_deep_mining/              # 深度挖掘文档
│   ├── 06_multiomics/               # 多组学整合文档
│   └── tools_ref/                   # 工具知识文档（WebSearch 学习后缓存）
│       └── WGS_integration.md       # WGS 模块融入说明
│
├── envs/                    # Conda 工具环境（23 个独立环境，已在 .gitignore）
├── db/                      # 分析数据库（~700G，已在 .gitignore）
├── miniforge3/              # 项目自包含 Python/Conda 环境（已在 .gitignore）
├── Rlib/                    # R 语言包库（已在 .gitignore）
├── Project/                 # 分析项目目录（每个项目一个子目录）
│   └── Project_example/
│       ├── data/            # 原始测序数据（*.fastq.gz，已在 .gitignore）
│       ├── temp/            # 中间文件（按脚本编号子目录，已在 .gitignore）
│       └── result/          # 结果文件（按分析类型子目录，已在 .gitignore）
├── mcp/                     # MCP 服务器（§9，规划中）
├── Reference/               # 参考资料（内部开发用，已在 .gitignore）
└── Rlib/                    # R 包库（.gitignore 排除）
```

---

## 三种执行模式

| 模式 | 入口 | 适用场景 |
|------|------|---------|
| 模式一：逐步 | `bash scripts/XX_xxx.sh -s SAMPLE ...` | 单步调试、参数探索 |
| 模式二：Bash Pipeline | `bash scripts/00_pipeline_bacteria.sh -i samplesheet.csv` | 单机小批量，无额外依赖 |
| 模式三：Snakemake | `snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml` | 生产级，大批量，HPC |

---

## 分析脚本编号规范

```
XX_dim_toolname.sh

XX   — 两位编号（01-98），决定执行顺序
dim  — 维度前缀：qc / bac / vir / fun / stat
tool — 工具名缩写
```

| 编号段 | 维度 | 说明 |
|--------|------|------|
| 01-09 | 通用 | 质控、去宿主（所有维度共享） |
| 11-41 | 细菌 | 物种→功能→组装→注释→Binning→MAG |
| 51-69 | 病毒 | 组装→鉴定→质控→定量→注释→宿主预测 |
| 71-86 | 真菌 | 分类→组装→MAG→功能注释 |
| 91-98 | 统计 | 多样性→差异→批次→ML→可视化→报告 |

---

## agents/ 系统说明

`agents/` 目录是 Agent Skills 系统的核心，三个子组件各司其职：

| 文件 | 更新者 | 触发时机 |
|------|--------|---------|
| `registry.yaml` | 双方 | 脚本状态变更（not_started → ready → integrated） |
| `skills/{id}.yaml` | CC（/mgx-integrate） | 新脚本 integrated 时生成 |
| `provenance/*.json` | CC（/mgx-learn） | 每次实际运行分析后记录 |

skill 卡片文件名规则：`{script_id}.yaml`，与 `registry.yaml` 中的 `id` 字段完全一致。

---

## docs/ 子目录说明

| 目录 | 存放内容 |
|------|---------|
| `01_preprocessing/` | fastp、kneaddata 用法文档 |
| `02_read_based/` | MetaPhlAn4、HUMAnN3、Kraken2 等读段级分析 |
| `03_assembly/` | MEGAHIT 组装流程 |
| `04_binning/` | MetaBAT2、MaxBin2、SemiBin2、DAS_Tool、CheckM2 |
| `05_deep_mining/` | antiSMASH、CRISPR、NCyc 等深度挖掘 |
| `06_multiomics/` | 多组学整合分析 |
| `tools_ref/` | WebSearch 动态学习的工具知识文档（`*.auto.md` 不入库） |

---

## 磁盘空间需求

| 组件 | 空间 | 备注 |
|------|------|------|
| miniforge3 + envs | ~50 GB | 23 个 conda 环境 |
| db/ | ~700 GB | 含 ChocoPhlAn、UniRef90、GTDB 等 |
| Project 数据（100 样本） | ~2 TB | 原始 1TB + 中间/结果 1TB |
| scripts + pipeline + agents | < 50 MB | 入库部分 |

---

## 迁移检查清单

新服务器部署后按顺序执行：

```bash
# 1. 激活环境
source scripts/activate.sh

# 2. 重新配置 CheckM2 路径
bash scripts/checkm_config.sh

# 3. 验证 Codex 连接（开发环境）
claude mcp list   # 应看到 codex: ✓ Connected
```

详见 CLAUDE.md §5.5 完整迁移检查清单。

---

## 参考

- 用户手册：[README.md](../README.md)
- 开发手册：[CLAUDE.md](../CLAUDE.md)（内部）
- WGS 模块融入：[docs/tools_ref/WGS_integration.md](tools_ref/WGS_integration.md)
- HUMAnN3 速度优化：[docs/02_read_based/humann3_speed_optimization.md](02_read_based/humann3_speed_optimization.md)
