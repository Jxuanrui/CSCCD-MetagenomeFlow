# Snakemake Pipeline

> 完整宏基因组分析一站式流程

---

## Overview

该 Snakemake 流程整合了 CSCCD-MetagenomeFlow 平台的 181 个分析脚本，支持**细菌、病毒、真菌**三维度并行分析。

**特性**:
- ✅ 141 个规则，覆盖从质控到统计分析的完整流程
- ✅ 自动依赖解析和任务调度
- ✅ 支持断点续跑和增量更新
- ✅ 硬件自适应配置 (local_16c / local_48c / local_96c / hpc_slurm)
- ✅ 详细日志和进度追踪

---

## Quick Start

### 1. 配置参数

编辑 `config/config.yaml`：

```yaml
# 必填字段
samplesheet: "/path/to/samplesheet.csv"  # CSV，必需包含 sample_id 列
workdir: "${PROJ_DIR}/Project/MyAnalysis"
cpus: 16

# 可选字段
force: false                    # 强制重新运行所有任务
threads_per_job: 16          # 每个规则内部线程数
max_jobs: 3                   # 并行作业数
```

### 2. 运行流程

```bash
# 自动检测硬件配置
snakemake -s pipeline/Snakefile --profile profiles/auto

# 手动指定配置
snakemake -s pipeline/Snakefile --profile profiles/local_48c -j 3

# 预览执行计划（dry-run）
snakemake -s pipeline/Snakefile --profile profiles/auto --dry-run
```

### 3. 查看结果

```
Project/MyAnalysis/result/
├── bacteria/       # 细菌维度
├── virome/         # 病毒维度
├── fungi/          # 真菌维度
└── stats/          # 统计分析
```

---

## Usage

### 基本命令

```bash
# 完整流程
snakemake -s pipeline/Snakefile --profile profiles/auto

# 运行到指定规则
snakemake -s pipeline/Snakefile --until metaphlan_profiler

# 仅运行指定规则
snakemake -s pipeline/Snakefile -R metaphlan_profiler

# 重新运行失败任务
snakemake -s pipeline/Snakefile --rerun-incomplete

# 查看 DAG 图
snakemake -s pipeline/Snakefile --dag | dot -Tpng > dag.png
```

### Profile 选择

| Profile | 硬件要求 | 并行度 | 适用场景 |
|---------|---------|-------|---------|
| `auto` | 自动检测 | 自动 | 首选（推荐） |
| `local_16c` | 16 核 / 64GB | `-j 2` | 小批量样本 |
| `local_48c` | 48 核 / 192GB | `-j 3` | 中等批量 |
| `local_96c` | 96 核 / 512GB | `-j 6` | 大批量 |
| `hpc_slurm` | SLURM 集群 | 动态 | HPC 环境 |

---

## Advanced Usage

### --force 参数：何时使用、何时避免

#### ✅ 合适的使用场景

1. **数据库版本更新**
   ```bash
   # MetaPhlAn 数据库从 vJan21 升级到 vOct22
   snakemake -R metaphlan_profiler --force
   ```

2. **参数调整后强制重算**
   ```bash
   # 修改了 config.yaml 中的敏感度参数
   snakemake -R humann_profiler --force
   ```

3. **外部文件被手动修改**
   ```bash
   # 手动编辑了中间结果文件
   snakemake --force
   ```

#### ❌ 不应使用的场景

1. **依赖冲突问题**
   ```bash
   # ❌ 错误：--force 不解决规则输出冲突
   snakemake --force  # 仍会报错

   # ✅ 正确：修改规则定义
   # 编辑 rules/*.smk，修复冲突的 output 路径
   ```

2. **任务执行失败**
   ```bash
   # ❌ 错误：失败任务应诊断原因
   snakemake --force  # 会重跑所有任务，浪费时间

   # ✅ 正确：重跑失败任务
   snakemake --rerun-incomplete
   ```

3. **单样本数据更新**
   ```bash
   # ❌ 错误：触发全流程重跑
   snakemake --force  # 影响所有样本

   # ✅ 正确：精确重跑单个样本
   snakemake -R fastp_qc --forcerun --config samples="Sample1"
   ```

#### ⚠️ 常见陷阱

| 陷阱 | 后果 | 避免方法 |
|-----|------|---------|
| 全局 `force: true` | 每次都重跑所有任务 | 仅在 `config.yaml` 中临时启用，用后立即注释 |
| `--force` + 大批量样本 | 数小时工作被清空 | 先 `--dry-run` 检查影响范围 |
| 误以为 `--force` 等同于 `--rerun-incomplete` | 重跑不必要的任务 | 理解差异（见下表） |

#### 参数对比

| 参数 | 作用 | 何时使用 |
|-----|------|---------|
| `--force` | 强制重新生成所有输出文件 | 外部变化 Snakemake 无法检测时 |
| `--rerun-incomplete` | 重跑失败或不完整的任务 | 任务执行失败后 |
| `-R rule_name` | 重跑指定规则及其下游 | 精确控制重跑范围 |
| `--forcerun` | 强制运行指定规则（不影响其他） | 单个规则需重算 |

#### 最佳实践

1. **检查影响范围**
   ```bash
   # 先预览哪些任务会被重跑
   snakemake --force --dry-run | grep "reason"
   ```

2. **精确定位规则**
   ```bash
   # 仅重跑 MetaPhlAn 及其下游（HUMAnN）
   snakemake -R metaphlan_profiler --forcerun
   ```

3. **临时启用后立即禁用**
   ```yaml
   # config.yaml - 用完立即注释
   # force: true  # ⚠️ 临时启用，2026-07-30
   ```

4. **保护已完成的工作**
   ```bash
   # 备份关键结果（避免误删）
   cp -r Project/MyAnalysis/result Project/MyAnalysis/result.backup
   snakemake --force
   ```

#### 典型错误示例

**错误 1: 单样本更新触发全流程重跑**
```bash
# 场景：Sample4 的数据有问题，需重新分析
# ❌ 错误做法
snakemake --force  # 影响 Sample1-3

# ✅ 正确做法
rm Project/MyAnalysis/result/metaphlan/Sample4_profile.tsv
snakemake  # 仅重跑 Sample4
```

**错误 2: 参数调整后盲目 --force**
```bash
# 场景：调整了 MetaPhlAn 的 --min_abundance 参数
# ❌ 错误做法
snakemake --force  # 重跑所有维度（包括病毒、真菌）

# ✅ 正确做法
snakemake -R metaphlan_profiler --forcerun  # 仅重跑 MetaPhlAn
```

**错误 3: 混淆 --force 和 --rerun-incomplete**
```bash
# 场景：Megahit 组装任务因 OOM 失败
# ❌ 错误做法
snakemake --force  # 重跑所有任务（包括已完成的质控）

# ✅ 正确做法
# 1. 诊断问题：降低并行度或增加内存
# 2. 仅重跑失败任务
snakemake --rerun-incomplete
```

---

## Architecture

### 文件组织

```
pipeline/
├── Snakefile               # 主入口
├── config/
│   └── config.yaml         # 运行参数
├── profiles/               # 硬件预设
│   ├── auto/
│   ├── local_16c/
│   ├── local_48c/
│   ├── local_96c/
│   └── hpc_slurm/
└── rules/                  # 规则定义（按维度组织）
    ├── preprocessing.smk   # 通用预处理
    ├── bacteria_*.smk      # 细菌分类、组装、注释、分箱、GEM
    ├── virome.smk          # 病毒维度规则
    ├── mycobiome.smk       # 真菌维度规则
    └── crosscohort.smk     # 跨队列分析
```

### 规则依赖关系

```
raw_fastq
  ↓
fastp_qc (质控)
  ↓
├─→ bacteria_dimension → metaphlan → humann → ...
├─→ virome_dimension → virsorter2 → checkv → ...
└─→ fungi_dimension → phf_profiler → funomic → ...
  ↓
stats_dimension (LEfSe, Core, Pathway, ...)
```

---

## Configuration

### 必填字段

```yaml
samplesheet: "/path/to/samplesheet.csv"  # CSV，必需包含 sample_id 列
workdir: "/path/to/project"    # 工作目录（绝对路径）
cpus: 16                       # CPU 核心数
```

### 常用可选字段

```yaml
# 执行控制
force: false                   # 强制重新运行（谨慎使用）
keep_temp: false               # 保留临时文件（调试用）

# 统计与并行
metadata: "/path/to/metadata.csv"
threads_per_job: 16          # 每个规则内部线程数
max_jobs: 3                   # 并行作业数

# 统计分析
group_col: "Group"             # metadata.tsv 中的分组列名
alpha_diversity_metrics: "shannon,simpson"
beta_diversity_metrics: "bray_curtis,jaccard"

# 资源限制
max_memory_mb: 163840          # 最大内存 (MB)
tmp_dir: "/tmp"                # 临时目录
```

详细配置说明见 `config/config.yaml.example`。

---

## Troubleshooting

### 常见问题

1. **任务失败如何重跑？**
   ```bash
   snakemake --rerun-incomplete
   ```

2. **如何跳过某个维度？**
   ```yaml
   # config.yaml
   # 按目标规则运行以跳过不需要的维度，例如：
   snakemake -s pipeline/Snakefile --until metaphlan_profiler
   ```

3. **内存不足 (OOM)？**
   - 降低 `-j` 并行度
   - 增加 `max_memory_mb`
   - 参考 [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)

4. **磁盘空间不足？**
   ```bash
   # 删除中间文件
   rm -rf Project/*/temp/*/intermediate_*
   ```

详细故障排查见 [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)。

---

## Performance

### 预期运行时间 (10 样本)

| 硬件配置 | 运行时间 | 建议 `-j` |
|---------|---------|----------|
| 16 核 / 64GB | 12-18 小时 | `-j 2` |
| 48 核 / 192GB | 4-6 小时 | `-j 3` |
| 96 核 / 512GB | 2-3 小时 | `-j 6` |

详细性能调优见 [docs/PERFORMANCE_TUNING.md](../docs/PERFORMANCE_TUNING.md)。

---

## More Help

- 📖 快速启动: [docs/QUICK_START.md](../docs/QUICK_START.md)
- 📖 项目架构: [docs/PROJECT_MAP.md](../docs/PROJECT_MAP.md)
- 📖 性能调优: [docs/PERFORMANCE_TUNING.md](../docs/PERFORMANCE_TUNING.md)
- 📖 故障排查: [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)

---

## Remote CI（远程持续集成）

`.github/workflows/ci.yml` 只运行**仓库自含、确定性**的两项检查：

- ✅ `lint`：对 `scripts/*.sh` 全量 shellcheck（`--severity=warning`，遵循根目录 `.shellcheckrc`）——本地 Level 1 的独立复刻
- ✅ `consistency`：运行 `python3 scripts/utils/check_consistency.py`，要求输出以 `issues=0` 结尾
- ❌ 不含 Level 2/3：集成测试与 Snakemake DAG dry-run 依赖 `Project/Test_CI_fixture` 数据（已 gitignore），远程 runner 无法复现，仍留在本地执行（`bash scripts/tests/run_ci_checks.sh --level {2,3}`）

启用方式（二选一）：

1. 镜像推送 GitHub（Actions 直接生效）：`git remote add github <github-url> && git push --mirror github`
2. 翻译为其他 CI 平台：将 `ci.yml` 改写为对应流水线，两个 job 的安装与检查命令原样保留
