# Agent Skills 系统

> MaxMetagenome 工具调用和经验追踪系统

---

## Overview

Agent Skills 系统提供**工具卡片** (134 个) 和**运行记录追踪** (188 条 provenance)，支持：
- ✅ 标准化工具调用 (统一输入输出规范)
- ✅ 历史运行记录查询
- ✅ 自动参数推荐
- ✅ 故障诊断和问题复现

---

## Directory Structure

```
agents/
├── registry.yaml           # 全局脚本状态追踪（138 个脚本）
├── skills/                 # 工具卡片（134 个 YAML 文件）
│   ├── 11_bac_fastp.yaml
│   ├── 12_bac_kneaddata.yaml
│   └── ...
└── provenance/             # 运行记录（188 条）
    ├── run_20260615_001.yaml
    ├── run_20260616_002.yaml
    └── ...
```

---

## Skills

### 结构说明

每个工具卡片包含：

```yaml
id: "11_bac_fastp"
name: "Fastp Quality Control"
category: "质控 (QC)"
dimension: "bacteria"
status: "✅ ready"

purpose: |
  对原始测序数据进行质量控制和过滤

inputs:
  - name: "fastq_1"
    type: "file"
    pattern: "*.fastq.gz"
    required: true

outputs:
  - name: "clean_fastq_1"
    path: "result/fastp/{sample}_1.clean.fastq.gz"

parameters:
  - name: "threads"
    type: "int"
    default: 16
    description: "线程数"

command_template: |
  bash scripts/11_bac_fastp.sh -s {sample} -t {threads} -w {workdir} -r {repo}

documentation:
  official: "https://github.com/OpenGene/fastp"
  local: "docs/tools/fastp.md"
```

### 使用方法

**通过 Claude Code 技能调用**:
```bash
# 自动查找最佳工具并推荐参数
/mgx-tune

# 学习工具使用经验
/mgx-learn --tool fastp

# 复现文献分析
/mgx-replicate --doi 10.1038/s41586-024-12345-6
```

**直接查询工具卡片**:
```bash
# 查看所有细菌维度工具
grep "dimension: bacteria" agents/skills/*.yaml

# 查找质控工具
grep "category: 质控" agents/skills/*.yaml

# 查看特定工具详情
cat agents/skills/11_bac_fastp.yaml
```

---

## Provenance Tracking

### 什么是 Provenance？

Provenance（起源/血统）记录每次工具运行的**完整上下文**：
- 输入数据（文件路径、大小、MD5）
- 参数配置（所有命令行参数）
- 输出结果（生成文件列表）
- 执行环境（conda 环境、工具版本、系统信息）
- 性能指标（运行时间、内存峰值、CPU 使用率）
- 错误诊断（退出码、错误信息）

**目的**: 可重现性 (Reproducibility) 和故障追溯 (Debugging)

---

### Provenance 记录结构

```yaml
run_id: "run_20260615_001"
timestamp: "2026-06-15T14:32:10"
script: "11_bac_fastp"
tool: "fastp"
version: "0.23.4"

context:
  project: "Project01"
  sample: "Sample1"
  dimension: "bacteria"
  
inputs:
  - path: "Project01/data/Sample1_1.fastq.gz"
    size_mb: 1234.5
    md5: "abc123..."
    
parameters:
  threads: 16
  qualified_quality_phred: 20
  length_required: 50
  
outputs:
  - path: "Project01/result/fastp/Sample1_1.clean.fastq.gz"
    size_mb: 987.3
    records: 12500000
    
performance:
  duration_seconds: 320
  peak_memory_mb: 2048
  cpu_percent: 95.3
  
environment:
  conda_env: "fastp"
  conda_prefix: "${PROJ_DIR}/envs/fastp"
  hostname: "localhost"
  
status: "success"  # success / failed / timeout
error: null
```

---

### 使用场景

#### 1. 查询特定工具的历史运行

```bash
# 查找所有 MetaPhlAn 运行记录
grep -l "tool: metaphlan" agents/provenance/*.yaml

# 示例输出：
# agents/provenance/run_20260615_023.yaml
# agents/provenance/run_20260616_045.yaml
# agents/provenance/run_20260617_078.yaml
```

#### 2. 提取成功运行的参数配置

```bash
# 查看 Sample1 样本的 MetaPhlAn 参数
grep -A 20 "sample: Sample1" agents/provenance/run_20260615_023.yaml | grep -A 10 "parameters:"

# 示例输出：
# parameters:
#   threads: 16
#   bowtie2_db: "${PROJ_DIR}/db/metaphlan"
#   index: "latest"
#   min_abundance: 0.0
```

#### 3. 对比不同参数的性能差异

```bash
# 对比不同线程数的运行时间
for f in agents/provenance/run_*_metaphlan.yaml; do
  echo -n "$(grep 'threads:' $f | awk '{print $2}') threads: "
  grep 'duration_seconds:' $f | awk '{print $2 " seconds"}'
done

# 示例输出：
# 8 threads: 1820 seconds
# 16 threads: 980 seconds
# 32 threads: 650 seconds
```

#### 4. 从 Provenance 记录重现分析

```bash
# 读取历史运行记录
run_id="run_20260615_001"
prov_file="agents/provenance/${run_id}.yaml"

# 提取关键信息
script=$(grep "script:" $prov_file | awk '{print $2}')
sample=$(grep "sample:" $prov_file | awk '{print $2}')
threads=$(grep "threads:" $prov_file | awk '{print $2}')

# 使用相同参数重新运行
bash scripts/${script}.sh -s $sample -t $threads -w Project01 -r ~/Course/Maxmetagenome
```

#### 5. 诊断失败任务

```bash
# 查找所有失败的运行
grep -l "status: failed" agents/provenance/*.yaml

# 查看失败原因
failed_run="agents/provenance/run_20260618_099.yaml"
grep -A 5 "error:" $failed_run

# 示例输出：
# error: |
#   Command failed with exit code 137
#   Error message: Killed (OOM)
#   Last log line: Building BWT...
```

---

### 与 `/mgx-learn` 技能的关系

`/mgx-learn` 技能会**自动写入 provenance 记录**：

```bash
# 运行分析
/mgx-learn --tool metaphlan --sample Sample1

# 自动生成记录
agents/provenance/run_$(date +%Y%m%d)_$(seq).yaml
```

**记录内容来源**:
1. **输入/输出**: 从脚本执行前后的文件系统快照获取
2. **参数**: 从命令行参数解析
3. **性能**: 从 `/usr/bin/time -v` 输出解析
4. **环境**: 从 `conda list` 和 `uname -a` 获取
5. **错误**: 从脚本退出码和 stderr 捕获

---

### Provenance 查询速查表

| 需求 | 命令 |
|-----|------|
| 查找工具所有运行 | `grep -l "tool: <tool_name>" agents/provenance/*.yaml` |
| 查找样本所有运行 | `grep -l "sample: <sample_id>" agents/provenance/*.yaml` |
| 查找成功运行 | `grep -l "status: success" agents/provenance/*.yaml` |
| 查找失败运行 | `grep -l "status: failed" agents/provenance/*.yaml` |
| 统计运行次数 | `ls agents/provenance/run_*_<tool>.yaml \| wc -l` |
| 查看最近运行 | `ls -t agents/provenance/*.yaml \| head -5` |
| 查找高内存任务 | `grep -h "peak_memory_mb:" agents/provenance/*.yaml \| sort -k2 -n \| tail -10` |
| 查找慢任务 | `grep -h "duration_seconds:" agents/provenance/*.yaml \| sort -k2 -n \| tail -10` |

---

### Provenance 统计分析示例

```bash
# 统计每个工具的运行次数
for tool in metaphlan humann fastp megahit kraken2; do
  count=$(grep -l "tool: $tool" agents/provenance/*.yaml | wc -l)
  echo "$tool: $count runs"
done

# 示例输出：
# metaphlan: 23 runs
# humann: 18 runs
# fastp: 45 runs
# megahit: 12 runs
# kraken2: 8 runs
```

```bash
# 计算平均运行时间
tool="metaphlan"
grep "duration_seconds:" agents/provenance/*_${tool}.yaml | \
  awk '{sum+=$2; count++} END {print "Average: " sum/count " seconds"}'

# 示例输出：
# Average: 1025.3 seconds
```

---

## Registry

`agents/registry.yaml` 追踪所有脚本的集成状态：

```yaml
scripts:
  - id: "11_bac_fastp"
    status: "✅ integrated"
    snakemake_rule: "fastp_qc"
    skill_card: "agents/skills/11_bac_fastp.yaml"
    last_updated: "2026-06-15"
    
  - id: "53_vir_virsorter2"
    status: "⚠️ known_issue"
    issue: "Apptainer conflict in sandboxed executor"
    workaround: "Use CC Bash tool"
    skill_card: "agents/skills/53_vir_virsorter2.yaml"
```

**状态类型**:
- `✅ integrated`: 已集成到 Snakemake
- `⚠️ known_issue`: 已知问题，有解决方案
- `🚧 in_progress`: 开发中
- `❌ blocked`: 阻塞，等待依赖

---

## More Help

- 📖 项目架构: [docs/PROJECT_MAP.md](../docs/PROJECT_MAP.md)
- 📖 快速启动: [docs/QUICK_START.md](../docs/QUICK_START.md)
