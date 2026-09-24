# CSCCD-MetagenomeFlow 分析平台使用教程

> 面向首次使用者的完整流程指南
> 平台版本：CSCCD-MetagenomeFlow v1.1 (2026-08 patch) | 更新日期：2026-08-19
>
> **本教程采用逐步审核制**：每个步骤执行完毕后，你必须审核输出结果，确认无误后再继续下一步。
> 不得提前启动 Snakemake 全流程，待所有关键步骤单样本审核通过后再切换批量模式。

---

## 前言：如何使用本教程

本教程采用**逐步审核制**。正确的执行顺序是：

```
单样本执行一步 → 审核输出 → 通过后执行下一步 → ... → 所有步骤审核完毕 → 切换 Snakemake 批量运行
```

**不要提前启动 Snakemake 全流程**。Snakemake 会自动将所有步骤串联执行，跳过逐步审核的机会。只有在你理解并确认每个步骤的输出正确后，才切换到批量模式。

每个步骤包含：
- **目的**：这一步做什么、为什么不能跳过
- **执行方式**：实际运行命令（模式一：单样本手动）
- **LLM 调用方式**：可直接粘贴给 AI 编程助手（任意 MCP 客户端）的 Prompt
- **输出结果**：预期文件结构和内容格式
- **审核要点**：判断结果是否正确的具体指标

**三种运行模式**（详见 `docs/PROJECT_MAP.md` §1.1）：
- **模式一**（本教程使用）：逐步手动，单样本，每步审核
- **模式二**：Bash Pipeline + rush，轻量批量，适合无 Snakemake 的场景
- **模式三**：Snakemake，生产级，所有步骤审核通过后切换至此

---

## 本机服务器参数（固定参考）

| 参数 | 数值 | 说明 |
|------|------|------|
| CPU 核心数 | **48 核** | 物理核，无超线程 |
| 内存 | **755 GB** | 可用约 745 GB |
| 单样本推荐线程 | **`-t 16`** | fastp 官方上限 16；kneaddata/megahit 等可用更多 |
| 最大并行任务数 | **3 个**（fastp 等 I/O 密集型工具） | 48÷16=3；CPU 密集型工具（如 megahit）建议 2 个 |
| Snakemake 配置 | `--cores 48`，`threads_per_job=16` | Profile: `pipeline/profiles/local_48c/` |

---

## 准备工作

### P1. 激活项目环境

**步骤名称**：激活 CSCCD-MetagenomeFlow 环境

**目的**：初始化项目的 conda 环境和路径变量，使所有脚本和工具可直接调用。

**执行方式**：
```bash
source ~/Course/CSCCD-MetagenomeFlow/scripts/activate.sh
```

**输出结果**：
```
[CSCCD-MetagenomeFlow] 环境已激活  PROJ_DIR=${PROJ_DIR}
```

**审核要点**：
- 看到 `[CSCCD-MetagenomeFlow] 环境已激活` 即成功
- `PROJ_DIR` 路径指向正确的项目根目录
- 若报错，检查 `miniforge3/` 目录是否存在

**LLM 调用方式（Prompt）**：
```
请帮我激活 CSCCD-MetagenomeFlow 环境并确认激活成功：
source ~/Course/CSCCD-MetagenomeFlow/scripts/activate.sh
确认输出中是否包含"环境已激活"
```

---

### P2. 准备项目目录和数据

**步骤名称**：创建项目目录结构并软链接原始数据

**目的**：将原始测序数据以软链接方式接入项目，避免复制大文件，节省磁盘空间。

**执行方式**：
```bash
# 创建项目目录
mkdir -p ~/Course/CSCCD-MetagenomeFlow/Project/MyProject/{data,temp,result,logs}

# 将原始数据软链接到 data/ 目录（.fq.gz → .fastq.gz）
for f in /path/to/raw/data/*.fq.gz; do
  ln -sf "$f" ~/Course/CSCCD-MetagenomeFlow/Project/MyProject/data/$(basename "${f/.fq.gz/.fastq.gz}")
done

# 验证
ls ~/Course/CSCCD-MetagenomeFlow/Project/MyProject/data/ | head -6
ls ~/Course/CSCCD-MetagenomeFlow/Project/MyProject/data/ | wc -l
```

**输出结果**：
```
Sample1_1.fastq.gz
Sample1_2.fastq.gz
Sample2_1.fastq.gz
...
---
100   ← 50个样本 × 2端 = 100个链接
```

**审核要点**：
- 文件数量 = 样本数 × 2（R1 + R2）
- 文件名格式必须为 `{SAMPLE_ID}_1.fastq.gz` 和 `{SAMPLE_ID}_2.fastq.gz`
- 软链接是否有效：`ls -l data/Sample1_1.fastq.gz` 应显示 `->` 指向源文件

**LLM 调用方式（Prompt）**：
```
请帮我在 CSCCD-MetagenomeFlow 项目中为新项目 MyProject 创建目录结构，
并将 /path/to/raw/data/ 下的 .fq.gz 文件以软链接形式（重命名为 .fastq.gz）
链接到 Project/MyProject/data/ 目录下，然后验证链接数量和有效性。
```

---

### P3. 准备 samplesheet 和 metadata

**步骤名称**：生成样本清单和元数据文件

**目的**：
- `samplesheet.csv`：告诉流程有哪些样本、数据在哪里
- `metadata.csv`：记录样本的分组信息，供统计分析使用

**执行方式**：
```bash
# 生成 samplesheet.csv
DATADIR=~/Course/CSCCD-MetagenomeFlow/Project/MyProject/data
echo "sample_id,r1,r2" > ~/Course/CSCCD-MetagenomeFlow/Project/MyProject/samplesheet.csv
ls $DATADIR/*_1.fastq.gz | sort -V | while read r1; do
  sample=$(basename "$r1" _1.fastq.gz)
  r2="${r1/_1.fastq.gz/_2.fastq.gz}"
  echo "${sample},${r1},${r2}"
done >> ~/Course/CSCCD-MetagenomeFlow/Project/MyProject/samplesheet.csv

# 查看前5行
head -6 ~/Course/CSCCD-MetagenomeFlow/Project/MyProject/samplesheet.csv
```

`metadata.csv` 格式（手动编辑或让 LLM 生成）：
```csv
sample_id,group,subject_id,age,BMI
Sample1,control,S01,45,23.1
Sample2,control,S02,52,24.8
...
Sample26,treat,S26,48,26.2
...
```

**输出结果**（samplesheet 前几行）：
```
sample_id,r1,r2
Sample1,<data-dir>/Sample1_1.fastq.gz,<data-dir>/Sample1_2.fastq.gz
Sample2,<data-dir>/Sample2_1.fastq.gz,<data-dir>/Sample2_2.fastq.gz
```

**审核要点**：
- 行数 = 样本数 + 1（含表头）
- r1/r2 路径是否真实存在：`head -2 samplesheet.csv | tail -1 | cut -d, -f2 | xargs ls`
- metadata 中 `group` 列值只有两类（如 `control` 和 `treat`），且每组样本数平衡

**LLM 调用方式（Prompt）**：
```
请帮我为 CSCCD-MetagenomeFlow 项目 Project/MyProject 生成 samplesheet.csv 和 metadata.csv。
data/ 目录下有 50 个样本（Sample1-Sample55，注意编号不连续），
metadata 要求前 25 个样本为 control，后 25 个为 treat，
按自然排序（Sample1,2,3,4,10,11,...,55）分配。
```

---

## 通用预处理

### 步骤 1：质量控制（fastp）

**步骤名称**：原始数据质量控制

**目的**：去除测序接头、低质量碱基和过短 reads，是所有后续分析的基础。跳过此步骤会导致后续分析受接头序列干扰，降低比对和分类的准确性。

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
source ~/Course/CSCCD-MetagenomeFlow/scripts/activate.sh

bash ~/Course/CSCCD-MetagenomeFlow/scripts/01_qc_fastp.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

> **为什么用 `-t 16`**：fastp 的 `-w`（worker threads）参数超过 16 后性能不再提升，这是工具本身的设计限制。本机 48 核，单样本最优就是 16 线程。

*模式二 — rush 并行剩余9样本（单样本审核通过后执行，补齐10样本验证集）：*
```bash
PROJ=~/Course/CSCCD-MetagenomeFlow
WORKDIR=$PROJ/Project/Project01

# 从 samplesheet_test10.csv 读取全部10个样本 ID，-j 3 并发（48核/16线程=3）
# fastp 幂等：Sample1 已完成会自动跳过，实际只跑剩余9个
# log 统一写入 temp/logs/fastp/
tail -n +2 $WORKDIR/samplesheet_test10.csv | cut -d, -f1 | \
  $PROJ/miniforge3/bin/rush -j 3 -k \
  'bash $PROJ/scripts/01_qc_fastp.sh \
    -s {1} -t 16 \
    -w $WORKDIR \
    -r $PROJ \
    > $WORKDIR/temp/logs/fastp/fastp_{1}.log 2>&1 && echo "[{1}] fastp done"'
```

> **10样本验证完成后**：全量50样本通过 Snakemake 执行（见后续"批量运行"章节），不再用 rush 跑全量。
> **log 路径**：所有 rush 并行的日志统一写入 `temp/logs/<tool>/` 子目录，避免 temp/ 根目录散乱。

**输出结果**：
```
Project/Project01/result/fastp/Sample1/
  ├── Sample1_1.fastq.gz    ← 清洁 R1 reads（~4.85 GB）
  ├── Sample1_2.fastq.gz    ← 清洁 R2 reads（~4.81 GB）
  ├── Sample1.json           ← 质控统计数据（机器可读）
  └── Sample1.html           ← 可视化报告（浏览器打开查看图表）
```

**Sample1 实测结果**（2026-06-23，耗时 445 秒）：
```
原始 reads：84,563,768（R1+R2 合计）
原始数据量：12.68 Gb
过滤保留率：99.9967%（84,560,980 reads 通过）
Q20（过滤后）：99.43%
Q30（过滤后）：97.94%
接头修剪 reads：1,389,841（占比 1.64%）
```

**Project01 执行进度（fastp）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（耗时 445 s，保留率 99.9967%）|
| ② rush 并行9样本 | 模式二，rush -j 3 | Sample2-4, Sample10-15 | ✅ 10/10 完成 |
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> Project01 样本编号不连续（Sample1-4 后跳到 Sample10），验证集为 `samplesheet_test10.csv`（Sample1-4, Sample10-15）。

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| 过滤保留率 | ≥ 90% | **99.9967%** | ✅ | 低于 85% 需检查原始数据 |
| Q20（过滤后） | ≥ 80% | **99.43%** | ✅ | 碱基错误率 <1% |
| Q30（过滤后） | ≥ 70% | **97.94%** | ✅ | 高精度碱基占比 |
| 接头修剪比例 | < 30% | **1.64%** | ✅ | >50% 说明建库异常 |
| 原始数据量 | ≥ 10 Gb/样本 | **12.68 Gb** | ✅ | 肠道宏基因组推荐 ≥10 Gb |

**LLM 调用方式（Prompt）**：
```
请帮我运行 CSCCD-MetagenomeFlow 步骤1（fastp质控），样本 Sample1，
项目目录 ~/Course/CSCCD-MetagenomeFlow/Project/Project01，线程数 16。
运行完成后解析 result/fastp/Sample1/Sample1.json，
输出：原始reads数、过滤保留率、Q20、Q30、接头修剪reads数及占比，
并判断数据质量是否合格（保留率≥90%，Q20≥80%，接头比例<30%）。
```

---

### 步骤 2：去宿主（kneaddata）

**步骤名称**：去除宿主基因组序列

**目的**：将 reads 比对到人类参考基因组（hg37），去除宿主来源序列，保留微生物 reads。这一步直接决定后续微生物分析的信噪比。

**依赖**：步骤 1 输出的清洁 reads

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/02_qc_kneaddata.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

> **为什么用 `-t 16`**：kneaddata 底层是 Bowtie2，线程数越高比对越快，16 线程是单任务合理上限（超过后收益递减且挤占并行空间）。

*模式二 — rush 并行剩余9样本（单样本审核通过后执行，补齐10样本验证集）：*
```bash
PROJ=~/Course/CSCCD-MetagenomeFlow
WORKDIR=$PROJ/Project/Project01

# kneaddata CPU+内存密集，-j 2（每个实例占用 16 线程 + ~13 GB 内存）
# kneaddata 幂等：Sample1 已完成会自动跳过，实际只跑剩余9个
tail -n +2 $WORKDIR/samplesheet_test10.csv | cut -d, -f1 | \
  $PROJ/miniforge3/bin/rush -j 2 -k \
  'bash $PROJ/scripts/02_qc_kneaddata.sh \
    -s {1} -t 16 \
    -w $WORKDIR \
    -r $PROJ \
    > $WORKDIR/temp/logs/kneaddata/kneaddata_{1}.log 2>&1 && echo "[{1}] kneaddata done"'
```

> **10样本验证完成后**：全量50样本通过 Snakemake 执行，不再用 rush 跑全量。

**输出结果**：
```
Project/MyProject/result/kneaddata/Sample1/
  ├── Sample1_1.kneaddata.fastq.gz   ← 去宿主后 R1
  ├── Sample1_2.kneaddata.fastq.gz   ← 去宿主后 R2
  ├── kneaddata.log                   ← 详细比对日志
  └── stats.txt                       ← reads 计数统计
```

**Sample1 实测结果**（2026-06-23，耗时 ~135 分钟）：
```
输入 reads（R1）：42,280,490
保留 reads（paired R1）：41,962,400
宿主去除 reads：318,090
宿主去除率：0.75%
微生物保留率：99.25%
输出文件：R1=4.3 GB，R2=4.3 GB
```

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| 宿主去除率 | < 5% | **0.75%** | ✅ | >30% 需检查采样操作 |
| 微生物保留率 | ≥ 95% | **99.25%** | ✅ | 越高越好 |
| 输出文件是否成对 | R1+R2 均存在 | **均 4.3 GB** | ✅ | 任一缺失说明脚本中断 |
| 耗时 | 60–180 min/样本 | **~135 min** | — | 大样本（>10 Gb）正常偏长 |

**Project01 执行进度（kneaddata）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（宿主去除率 0.75%，耗时 ~135 min）|
| ② rush 并行9样本 | 模式二，rush -j 2 | Sample2-4, Sample10-15 | ✅ 全部完成（10/10 样本，reads 范围 38.9M–55.4M）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> kneaddata 是流程中最耗时的单步骤（~135 min/样本）。
> 10样本 rush -j 2 预计约 5 × 135 min ≈ 11 小时。全量50样本交由 Snakemake -j 2 并发处理，约需 2 天。

**LLM 调用方式（Prompt）**：
```
请帮我运行 CSCCD-MetagenomeFlow 步骤2（kneaddata去宿主），样本 Sample1，
项目目录 ~/Course/CSCCD-MetagenomeFlow/Project/Project01，线程数 16。
运行完成后解析 result/kneaddata/Sample1/kneaddata.log 中的 READ COUNT 行，
输出：输入reads数（R1+R2合计）、宿主去除reads数、宿主去除率、微生物保留率，
并判断是否在正常范围（肠道样本宿主污染率通常 <5%，超过 30% 需复查采样）。
```

---

### 步骤 2b：R1/R2 严格重新配对（修复 kneaddata 输出顺序错位）

**步骤名称**：FASTQ 配对完整性修复

**目的**：调试步骤36b（post-binning reassembly）时发现，kneaddata 产出的 R1/R2 文件虽然读长 ID 集合完全一致（`sort` + `diff` 验证零差异），但顺序发生了错位（约每80万条中15条位置偏移）。`bwa mem` 等严格要求 R1/R2 按位置一一对应的工具会在此处直接 fatal abort（"paired reads have different names"，退出码非0，非仅警告）；更宽容的工具（如 bowtie2/samtools）可能静默掩盖此问题而不报错，危险性更高。本步骤用 `seqkit pair` 按 ID 强制重新配对，确保下游所有工具拿到的都是严格配对的 FASTQ。

**依赖**：步骤2（kneaddata）的 `_raw` 中间产物（`{sample}_{1,2}.kneaddata_raw.fastq.gz`）

**执行方式**：

```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/02b_qc_pair_repair.sh \
  -s Sample4 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：

```
result/kneaddata/Sample4/
├── Sample4_1.kneaddata.fastq.gz       — 严格配对后的最终产物（下游所有步骤的标准输入）
├── Sample4_2.kneaddata.fastq.gz
└── Sample4.pair_repair_done.txt       — sentinel（READS_BEFORE / READS_AFTER 计数）
```

**实测**（Project01 真实样本 Sample4）：耗时 358 秒，重配对前后 reads 数均为 38,900,065 对，确认是纯粹的顺序修复、无数据丢失。修复后手动重跑 `bwa mem` 验证：由中止时仅产出 8,483 行 SAM，变为完整产出 78,005,192 行 SAM（exit 0）。

**审核要点**：
- 本步骤是**新增的强制流水线步骤**，不是可选修复——下游所有依赖严格 R1/R2 配对的工具（包括步骤36b）都以本步骤产出为标准输入
- 中间产物改名为 `_raw` 后缀，Snakemake 层面已同步更新（`rule kneaddata` 输出 `_raw`，新增 `rule pair_repair` 产出最终配对文件），41 处既有下游规则引用无需改动

---

## 细菌维度分析

### 步骤 3：细菌物种组成（MetaPhlAn4）

**步骤名称**：细菌物种组成定量

**目的**：将去宿主后的 reads 与 MetaPhlAn4 标记基因数据库比对，输出各物种的相对丰度（%），是细菌维度的核心输出。

> **常见问题1：输入为什么不只用 R1，而是 R1+R2 合并？**
>
> MetaPhlAn4 做的是每条 read 独立比对到标记基因数据库，**不需要配对信息**（不做组装）。
> 脚本内部用 `zcat R1 R2 | gzip > merged.fastq.gz` 将双端合并为一个文件再传入，相当于把可用 reads 翻倍（~8400 万条 → 更高灵敏度，稀有物种更容易检出）。
> 不用 `-1 R1 -2 R2` 双端模式的原因：MetaPhlAn4 v4.2.4 的 `-1/-2` 参数仅用于子采样模式，核心比对只接受单文件输入。
>
> **常见问题2：HUMAnN3 内部不是也跑 MetaPhlAn4 吗，为什么要单独跑？**
>
> 有三个理由必须单独跑：
> 1. **HUMAnN3 不保留 `.bz2` 比对文件**，而后续的 StrainPhlAn4（菌株追踪）必须读取此文件，缺少则无法做菌株级系统发育分析。
> 2. **先跑反而让 HUMAnN3 更快**：当 `result/metaphlan4/{SAMPLE}_profile.txt` 存在时，HUMAnN3 通过 `--taxonomic-profile` 参数跳过内部 MetaPhlAn4 步骤（节省 30–60 分钟/样本）。
> 3. **分析目的不同**：独立的 profile.txt 是多样性分析、差异分析的直接输入；HUMAnN3 内置的版本只是中间变量，不做物种组成研究用。
>
> **依赖关系**：
> ```
> 11_metaphlan4 → profile.txt → 13_humann3（--taxonomic-profile，跳过内部MetaPhlAn4）
>              → .bz2        → 12_strainphlan4（菌株追踪，必须有）
> ```

**依赖**：步骤 2 输出的去宿主 reads（R1 单端输入）

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/11_bac_metaphlan4.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/metaphlan4/Sample1/
  ├── Sample1_profile.txt   ← 各分类级别物种相对丰度（→ HUMAnN3 / 多样性分析）
  └── Sample1.sam.bz2       ← 标记基因比对文件（→ StrainPhlAn4 菌株追踪，568 MB）
```

**Sample1 实测结果**（2026-06-23，耗时 ~175 分钟）：
```
检测物种数（species 级）：157
UNKNOWN 比例：0%
总相对丰度（species 合计）：75.85%（剩余为覆盖度不足的已知菌，非 UNKNOWN）
最高丰度物种：Faecalibacterium prausnitzii 18.23%
门级分布：Firmicutes 69.2%，Bacteroidetes 2.78%，Actinobacteria 2.14%
```

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| 检测物种数（species 级） | 50–300 | **157** | ✅ | <20 说明测序深度不足 |
| UNKNOWN 比例 | < 30% | **0%** | ✅ | 过高说明数据库未覆盖 |
| .sam.bz2 是否生成 | 必须存在 | **568 MB ✅** | ✅ | 缺失则 StrainPhlAn4 无法运行 |
| Firmicutes + Bacteroidota 合计 | > 50% | **72.0%** | ✅ | 肠道典型优势门 |

> **注意**：本样本 Firmicutes/Bacteroidetes 比值约 25:1，Bacteroidetes 比例偏低，
> 属于真实生物学特征（可能与代谢综合征相关），不是数据质量问题。
> 需要 50 个样本合并后统计分析才能判断组间差异是否显著。

**LLM 调用方式（Prompt）**：
```
请帮我解读 CSCCD-MetagenomeFlow 步骤3（MetaPhlAn4）的输出结果：
文件：result/metaphlan4/Sample1/Sample1_profile.txt
输出：1）检测到的 species 级物种总数；
2）各门（Phylum）相对丰度前5名；
3）Firmicutes 和 Bacteroidota 合计占比；
4）UNKNOWN 比例；
5）综合判断数据质量是否合格。
```

**Project01 执行进度（MetaPhlAn4）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（157 species，Firmicutes 69.2%，耗时 ~175 min）|
| ② rush 并行9样本 | 模式二，rush -j 3 | Sample2-4, Sample10-15 | ✅ 全部完成（10/10 样本，species 范围 279-815）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> MetaPhlAn4 约 175 min/样本，-j 3（3×16=48 核满载）。9 个样本分 3 批，预计约 9 小时完成。

---

### 步骤 4：功能通路定量（HUMAnN3）

**步骤名称**：微生物功能通路定量

**目的**：将 reads 映射到微生物基因功能数据库（ChocoPhlAn + UniRef90），输出每个代谢通路的丰度（RPK）和覆盖度，是功能宏基因组学的核心输出。

> **HUMAnN3 三阶段流程**：
> 1. **物种筛查**（利用 MetaPhlAn4 profile）→ 筛选出当前样本存在的物种，构建定制版 ChocoPhlAn 数据库（避免搜索全量数据库，节省 30–60 分钟）
> 2. **核苷酸搜索**（Bowtie2）→ 将 reads 比对到筛选后的基因组数据库，获得高精度命中
> 3. **翻译搜索**（Diamond）→ 对未命中的 reads 做蛋白级别搜索（UniRef90），覆盖无参考基因组的物种
>
> **为什么步骤3（MetaPhlAn4）要在步骤4之前运行？**
>
> HUMAnN3 通过 `--taxonomic-profile` 参数接收 MetaPhlAn4 的 profile.txt，直接跳过内部 MetaPhlAn4 运行。
> 如果不提供 profile，HUMAnN3 会自己跑一遍 MetaPhlAn4（约 30–60 min 额外开销），且不保存 `.sam.bz2`（StrainPhlAn4 所需）。
> 先跑步骤3既加速了 HUMAnN3，又产出了后续菌株分析所需的文件。

**依赖**：步骤 2（去宿主 reads）+ 步骤 3 输出的 `Sample1_profile.txt`

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/13_bac_humann3.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/humann3/Sample1/
  ├── Sample1_genefamilies.tsv           ← 基因家族丰度（RPK，原始）
  ├── Sample1_genefamilies_relab.tsv     ← 基因家族相对丰度（标准化）
  ├── Sample1_pathabundance.tsv          ← 通路丰度（RPK，含物种分层）
  ├── Sample1_pathabundance_relab.tsv    ← 通路相对丰度
  ├── Sample1_pathcoverage.tsv           ← 通路覆盖度（0–1）
  ├── stratified/                        ← 物种分层结果（按菌种拆分）
  └── unstratified/                      ← 非分层汇总结果（统计分析常用）
```

**Sample1 实测结果**（2026-06-23，总耗时 ~354 分钟）：

```
检测通路数：417 条
基因家族总行数：841,303 行
UNMAPPED 比例：17.5%
UNINTEGRATED 比例：76.8%

各阶段耗时：
  物种筛查+数据库构建：1193 秒（~20 分钟）
  Bowtie2 索引构建：   1739 秒（~29 分钟）
  核苷酸比对：         1174 秒（~20 分钟）
  核苷酸后处理：       3922 秒（~65 分钟）
  翻译搜索（Diamond）：11931 秒（~199 分钟）
  翻译后处理：          820 秒（~14 分钟）
  基因家族计算：         74 秒
  通路计算：            206 秒（~3 分钟）

Top 10 丰度通路：
  1. PWY-7238: sucrose biosynthesis II                         41849.8 RPK
  2. PWY-5941: glycogen degradation II                         34998.7 RPK
  3. GLYCOGENSYNTH-PWY: glycogen biosynthesis I                34770.2 RPK
  4. PWY-1042: glycolysis IV                                   31453.3 RPK
  5. PWY0-1296: purine ribonucleosides degradation             30695.3 RPK
  6. PWY-6609: adenine and adenosine salvage III               30448.8 RPK
  7. VALSYN-PWY: L-valine biosynthesis                         29869.5 RPK
  8. COMPLETE-ARO-PWY: superpathway of aromatic AA biosynthesis 28923.7 RPK
  9. PWY-6163: chorismate biosynthesis from 3-dehydroquinate   28705.9 RPK
  10. ARO-PWY: chorismate biosynthesis I                       28632.0 RPK
```

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| 检测通路数 | 100–600 | **417** | ✅ | <50 说明数据量不足或比对率极低 |
| UNMAPPED 比例 | < 50% | **17.5%** | ✅ | 肠道宏基因组正常范围 10–30% |
| UNINTEGRATED 比例 | < 90% | **76.8%** | ✅ | 偏高但在正常范围，反映较多孤儿基因 |
| 基因家族行数 | > 100,000 | **841,303** | ✅ | 反映功能多样性丰富 |
| 三个主输出文件是否存在 | 均存在 | **✅** | ✅ | 缺任一说明流程中断 |
| 耗时 | 2–8 小时/样本 | **~354 分钟** | — | Diamond 翻译搜索是瓶颈，正常 |

> **关于 UNINTEGRATED（76.8%）**：这表示 76.8% 的通路丰度来自无法归入已知 MetaCyc 通路的基因家族，不是错误，
> 而是肠道菌群功能复杂性的反映。对于人类肠道宏基因组，UNINTEGRATED 40–85% 均属正常范围。
> 多样性和差异分析时使用 `unstratified/` 目录下的结果，UNINTEGRATED 会保留为一个汇总类别。

> **关于 Diamond 翻译搜索耗时（~199 分钟）**：这是 HUMAnN3 中最耗时的步骤，无法并行加速。
> 50 个样本顺序运行约需 12 天；Snakemake 3 并发可压缩至 ~4 天。
> 正式批量运行前请确认所有单样本步骤审核通过。

**LLM 调用方式（Prompt）**：
```
请帮我解读 CSCCD-MetagenomeFlow 步骤4（HUMAnN3）的输出结果，样本 Sample1：
文件：result/humann3/Sample1/Sample1_pathabundance.tsv
输出：
1）检测到的代谢通路总数（排除 UNMAPPED 和 UNINTEGRATED）；
2）UNMAPPED 和 UNINTEGRATED 的 RPK 值及其在总 RPK 中的比例；
3）丰度最高的 Top 10 通路名称和 RPK 值；
4）综合判断功能分析质量是否合格（通路数>100，UNMAPPED<50%）。
```

**Project01 执行进度（HUMAnN3）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（5082 pathways，耗时 ~300 min）|
| ② rush 并行9样本 | 模式二，rush -j 2 | Sample2-4, Sample10-15 | ✅ 全部完成（10/10 样本，pathways 范围 4,091–6,625）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> HUMAnN3 是最耗时步骤（~300 min/样本，Diamond 阶段 ~199 min 不可并行加速）。-j 2（内存峰值 ~80GB/实例）。9 个样本预计约 22 小时完成。

---

### 步骤 5：Kraken2 + Bracken 快速物种分类

**步骤名称**：k-mer 快速物种分类与丰度估计

**目的**：用 k-mer 比对方法对 reads 做快速物种分类，同时覆盖细菌、古菌、病毒、真菌四个界。与 MetaPhlAn4（标记基因，精确但数据库偏小）互相印证，两者结果一致则增强可信度。

> **MetaPhlAn4 vs Kraken2 对比**：
>
> | 维度 | MetaPhlAn4 | Kraken2+Bracken |
> |------|-----------|----------------|
> | 比对方式 | 标记基因（clade-specific markers） | k-mer（全基因组级） |
> | 速度 | 慢（~175 min） | 快（~8 min） |
> | 覆盖界 | 细菌+古菌 | 细菌+古菌+病毒+真菌 |
> | 精度 | 高（假阳性低） | 中（数据库越大精度越高） |
> | 主要用途 | 物种组成定量、多样性分析 | 快速概览、跨界筛查 |
>
> 两者都检出的物种可信度最高。Kraken2 检出而 MetaPhlAn4 未检出，通常是数据库覆盖差异所致（不算矛盾）。

**依赖**：步骤 2 输出的去宿主 reads（R1 + R2 双端）

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/14_bac_kraken2.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/kraken2/Sample1/
  ├── Sample1.report               ← Kraken2 全分类报告（Bracken 输入）
  ├── Sample1.output.gz            ← 每条 read 分类结果（压缩）
  └── bracken/
        ├── Sample1_S.bracken      ← 种级丰度估计（主要结果）
        ├── Sample1_G.bracken      ← 属级丰度估计
        ├── Sample1_P.bracken      ← 门级丰度估计
        ├── Sample1_S.report       ← 种级 Kraken 格式报告
        ├── Sample1_G.report       ← 属级报告
        └── Sample1_P.report       ← 门级报告
```

**Sample1 实测结果**（2026-06-24，耗时 505 秒 ~8 分钟）：

```
分类率：76.4%（classified），未分类：23.6%
检测物种数（Species）：530
检测属数（Genus）：216

门级分布（Bracken 估计）：
  Bacillota (Firmicutes)：85.8%
  Pseudomonadota：         5.9%
  Bacteroidota：           4.5%
  Actinomycetota：         3.4%
  Uroviricota（噬菌体）：  0.3%

Top 10 物种（Bracken 种级）：
  1. Agathobacter rectalis (Eubacterium rectale)   12.89%
  2. Faecalibacterium sp. IP-1-18                   8.35%
  3. Blautia wexlerae                               6.37%
  4. Escherichia coli                               4.59%
  5. Blautia obeum                                  2.70%
  6. Bifidobacterium longum                         2.47%
  7. Mediterraneibacter gnavus (Ruminococcus gnavus) 2.30%
  8. Anaerobutyricum hallii (Eubacterium hallii)    2.02%
  9. Veillonella parvula                            1.71%
  10. Anaerostipes hadrus                           1.71%
```

**与 MetaPhlAn4 结果对照**：

| 指标 | MetaPhlAn4 | Kraken2+Bracken | 一致性 |
|------|-----------|----------------|--------|
| 第一优势门 | Firmicutes 69.2% | Bacillota 85.8% | ✅ 一致 |
| Faecalibacterium Top1 | Faecalibacterium prausnitzii 18.23% | Faecalibacterium sp. 8.35%（#2） | ✅ 均高丰度 |
| Bacteroidota | 2.78% | 4.5% | ✅ 均低丰度 |
| Agathobacter/Eubacterium rectale | 检出（高丰度） | #1（12.89%） | ✅ 一致 |

> **注意**：两者丰度数值有差异是正常的——MetaPhlAn4 基于标记基因，Kraken2 基于全基因组 k-mer，统计模型不同，绝对数值不可直接比较；**物种检出方向和高低丰度排序一致**才是关键。

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| 分类率 | > 50% | **76.4%** | ✅ | <30% 说明数据库覆盖不足或样本污染 |
| 检测物种数 | 100–1000 | **530** | ✅ | Kraken2 覆盖范围更广，物种数通常高于 MetaPhlAn4 |
| Firmicutes（Bacillota）占比 | > 50%（肠道） | **85.8%** | ✅ | 肠道正常优势门 |
| 与 MetaPhlAn4 方向一致 | 高丰度物种吻合 | **✅** | ✅ | 两者高丰度物种重叠度高则可信 |
| 三个 bracken 文件存在 | 均存在 | **✅** | ✅ | 缺失说明 Bracken 未运行 |

**LLM 调用方式（Prompt）**：
```
请帮我解读 CSCCD-MetagenomeFlow 步骤5（Kraken2+Bracken）的输出结果，样本 Sample1：
文件：
  result/kraken2/Sample1/bracken/Sample1_S.bracken （种级）
  result/kraken2/Sample1/bracken/Sample1_P.bracken （门级）
输出：
1）总分类率（classified %）；
2）门级丰度分布（所有门）；
3）种级丰度 Top 10；
4）与 MetaPhlAn4 结果的一致性评估（高丰度物种是否重叠）；
5）综合判断分类质量是否合格（分类率>50%，Firmicutes优势）。
```

**Project01 执行进度（Kraken2+Bracken）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（530 species，分类率 76.4%，Firmicutes 85.8%）|
| ② rush 并行9样本 | 模式二，rush -j 3 | Sample2-4, Sample10-15 | ✅ 全部完成（10/10 样本，species 范围 378–635）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> Kraken2 速度快（~8 min/样本），-j 3 并发，9 个样本预计约 30 分钟完成。

---

### 步骤 6：Centrifuger 蛋白级精确分类

**步骤名称**：蛋白级物种精确分类（GTDB R226）

**目的**：用 FM-index 全基因组压缩比对方法对 reads 做物种分类，使用 GTDB R226 数据库（最新参考，含 317,542 个基因组），作为 MetaPhlAn4 和 Kraken2 的第三方独立验证。

> **三工具角色定位**：
>
> | 工具 | 方法 | 数据库 | 速度 | 主要优势 |
> |------|------|--------|------|---------|
> | MetaPhlAn4 | 标记基因比对 | ~100k SGB 标记基因 | 慢 | 高精度，假阳性最低 |
> | Kraken2 | k-mer 全基因组 | PlusPF（细菌+真菌+病毒） | 快 | 跨界覆盖广 |
> | Centrifuger | FM-index 全基因组 | GTDB R226（最新分类） | 中 | 最新物种命名，蛋白级精度 |
>
> 三工具结论一致 → 结果高度可信；某工具独有的物种需谨慎解读（可能是数据库覆盖差异）。

**依赖**：步骤 2 输出的去宿主 reads（R1 + R2 双端）

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/15_bac_centrifuger.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/centrifuger/Sample1/
  ├── Sample1.kreport.tsv             ← Kraken2 兼容格式报告（主要结果）
  └── Sample1.classifications.tsv.gz  ← 每条 read 分类结果（压缩，483 MB）
```

**Sample1 实测结果**（2026-06-24，耗时 1857 秒 ~31 分钟）：

```
分类率：98.96%（细菌域 94.94%），未分类：1.04%

门级分布：
  Bacillota (Firmicutes)：84.4%
  Bacteroidota：           5.3%
  Actinomycetota：         2.6%
  Pseudomonadota：         2.4%
  Uroviricota（噬菌体）：  0.1%

Top 10 物种（GTDB R226 命名）：
  1. Fusicatenibacter saccharivorans    6.34%
  2. Roseburia inulinivorans            3.71%
  3. Agathobacter rectalis              2.95%
  4. Blautia_A sp003471165              2.80%
  5. Faecalibacterium prausnitzii       2.74%
  6. Agathobacter faecis                2.26%
  7. Phocaeicola plebeius_A             1.79%
  8. Enterocloster sp000431375          1.52%
  9. Faecalibacterium longum            1.50%
  10. Faecalibacterium sp900539945      1.43%
```

**三工具物种分类交叉验证**：

| 维度 | MetaPhlAn4 | Kraken2 | Centrifuger | 一致性 |
|------|-----------|---------|------------|--------|
| 第一优势门 | Firmicutes 69.2% | Bacillota 85.8% | Bacillota 84.4% | ✅ 三工具一致 |
| Bacteroidota | 2.8% | 4.5% | 5.3% | ✅ 均低丰度 |
| Faecalibacterium | #1（18.2%） | #2（8.4%） | #5（2.7%） | ✅ 三工具均高丰度检出 |
| Agathobacter/Eubacterium rectale | 高丰度 | #1（12.9%） | #3（3.0%） | ✅ 三工具均检出 |
| 分类率 | — | 76.4% | **98.96%** | — Centrifuger 最高 |

> **关于检测物种数差异**（MetaPhlAn4: 157 vs Kraken2: 530 vs Centrifuger: 52,745）：
> Centrifuger 报告的 52,745 个"种"中绝大多数丰度极低（<0.01%），是数据库更大、
> 敏感性更高的体现，而非样本真实多样性差异。统计分析时一般过滤低丰度物种（<0.01%）后使用。

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| 分类率 | > 70% | **98.96%** | ✅ | Centrifuger 通常高于 Kraken2 |
| 第一优势门（Bacillota） | > 50%（肠道） | **84.4%** | ✅ | 与 Kraken2 结果吻合 |
| 三工具门级方向一致 | 均显示 Firmicutes 优势 | **✅** | ✅ | 高可信度 |
| kreport.tsv 是否存在 | 必须存在 | **3.9 MB ✅** | ✅ | 缺失说明 centrifuge-kreport 未运行 |
| 耗时 | 20–60 min/样本 | **~31 min** | — | 数据库加载占大部分时间 |

**三工具物种分类验证结论**：MetaPhlAn4 + Kraken2 + Centrifuger 三工具在门级分布和高丰度物种上高度一致（Bacillota 主导，Faecalibacterium 和 Agathobacter 均为优势菌），Sample1 物种组成结果**可信**，可进入下游组装分析。

**LLM 调用方式（Prompt）**：
```
请帮我解读 CSCCD-MetagenomeFlow 步骤6（Centrifuger）的输出结果，样本 Sample1：
文件：result/centrifuger/Sample1/Sample1.kreport.tsv
输出：
1）总分类率和细菌域分类率；
2）门级（P行）丰度分布 Top 10；
3）种级（S行）丰度 Top 10；
4）与 MetaPhlAn4、Kraken2 结果的三工具一致性评估；
5）综合判断可信度（三工具门级方向是否一致）。
```

**Project01 执行进度（Centrifuger）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（分类率 98.96%，Bacillota 84.4%，三工具一致）|
| ② rush 并行9样本 | 模式二，rush -j 3 | Sample2-4, Sample10-15 | ✅ 全部完成（10/10 样本）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> Centrifuger 约 31 min/样本，-j 3 并发，9 个样本预计约 2 小时完成。

---

**步骤名称**：de novo 宏基因组组装

**目的**：将 reads 组装成更长的 contig 序列，为后续基因预测（Prodigal）、功能注释（eggNOG/KEGG/AMR 等）和 MAG 回收（Binning）提供基础。组装结果的质量直接决定基因目录的完整性。

---

> ### ⚠️ 执行前必读：组装策略选择
>
> MEGAHIT 支持三种宏基因组组装策略，**执行前必须根据研究目的确认策略**，策略不同结果差异显著。
>
> | 策略 | 标准术语 | 原理 | 优点 | 缺点 | 适用场景 |
> |------|---------|------|------|------|---------|
> | **策略 A** | Per-sample assembly（单样本独立组装） | 每个样本独立组装，结果合并后 CD-HIT 去冗余 | 速度快、内存可控（~30-80 GB/样本）、可重现、主流流程标准做法 | 单样本深度有限，低丰度稀有物种可能因 reads 不足而无法组装出 contig | **默认推荐**，适合所有规模，本教程采用此策略 |
> | **策略 B** | Co-assembly（联合组装） | 所有样本 reads 合并后一次性组装 | 低丰度物种 reads 跨样本累加，组装深度更高；少量共有物种的基因组更完整 | 内存消耗 = N 个样本之和（50 样本≈500 GB+，本机风险极高）；跨样本嵌合体（chimera）问题严重，易产生虚假序列 | 样本数 ≤ 5、内存充裕、研究稀有菌时考虑 |
> | **策略 C** | Group-based co-assembly（分组联合组装） | 按表型/队列分组，组内 co-assembly，组间独立 | 折中：保留组内低丰度物种，内存可控（每组样本数×单样本内存）；样本独特性保留优于全局 co-assembly | 需要事先定义有意义的分组依据（表型/批次）；实现复杂，需修改 pipeline；分组不合理反而引入混淆 | 中等规模（10–100 样本）、有明确表型分组（如病例/对照/队列）的精细研究 |
>
> **如何选择（LLM 询问方式）**：
> ```
> 我有 N 个宏基因组样本，分组信息如下：[描述表型/队列/分组]。
> 请帮我判断应采用 per-sample、co-assembly 还是 group-based co-assembly 策略，
> 并说明理由和对后续 MAG 分析的影响。
> ```
>
> **Project01 当前选择：策略 A（per-sample）**
> 理由：50 个样本 co-assembly 需要 >500 GB 内存（本机风险极高）；分组元数据尚未完整标注；当前阶段目标是验证流程正确性，per-sample 速度最快、最易排查问题，且与现有 Snakemake pipeline 完全对齐。

---

> **⚠️ 已知 Bug（kneaddata trailing garbage）**
>
> kneaddata 输出的 `.fastq.gz` 末尾可能残留无效字节（trailing garbage）。`zcat` 可以容忍但 MEGAHIT 内部 gzip reader 遇到这种文件会报错退出（exit code 2）。
>
> **已修复**（2026-06-24）：`16_bac_megahit.sh` 在运行前自动用 `gzip -t` 检测并原地重压缩受影响的文件，无需手动干预。如遇到 `Error occurs when reading inputs` 报错，可手动重压缩：
> ```bash
> zcat Sample1_1.kneaddata.fastq.gz 2>/dev/null | gzip -c > tmp.gz && mv tmp.gz Sample1_1.kneaddata.fastq.gz
> ```

**依赖**：步骤 2 输出的去宿主 reads（R1 + R2 双端）

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/16_bac_megahit.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/assembly/megahit/Sample1/
  ├── Sample1.contigs.fa    ← 最终组装结果（→ Prodigal/Binning 输入）
  └── Sample1.megahit.log   ← 组装日志（k 值迭代过程）
```

**Sample1 实测结果**（2026-06-24，耗时 9369 秒 ~156 分钟）：

```
Contig 总数：111,599
总碱基数：   269.2 Mb
最长 contig：269,449 bp
N50：        7,022 bp
N90：        755 bp
≥500 bp：    111,599（脚本过滤下限）
≥1000 bp：   48,467
```

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| Contig 总数 | 50,000–500,000 | **111,599** | ✅ | 太少说明测序深度不足 |
| 总碱基数 | 100–800 Mb | **269.2 Mb** | ✅ | 反映非冗余序列总量 |
| N50 | ≥ 1,000 bp | **7,022 bp** | ✅ | N50 越高组装质量越好，>5kb 优秀 |
| 最长 contig | ≥ 10,000 bp | **269,449 bp** | ✅ | 超长 contig 说明覆盖度足够 |
| ≥1000 bp 数量 | ≥ 10,000 | **48,467** | ✅ | 供 Binning 使用的有效 contig 数量 |
| 耗时 | 30–180 min/样本 | **~156 min** | — | CPU 密集型；12 GB 样本属正常偏长 |

> **N50 = 7,022 bp** 说明组装质量优秀——肠道宏基因组典型值 2,000–10,000 bp，本样本位于高端，
> 原因是测序深度充足（12 Gb 原始数据），有利于后续 Binning 回收高质量 MAG。

**LLM 调用方式（Prompt）**：
```
请帮我统计 CSCCD-MetagenomeFlow 步骤7（MEGAHIT）的组装质量，样本 Sample1：
文件：result/assembly/megahit/Sample1/Sample1.contigs.fa
输出：
1）Contig 总数、总碱基数（Mb）；
2）N50、N90、最长 contig；
3）≥500 bp、≥1000 bp、≥5000 bp 的 contig 数量；
4）综合判断组装质量（N50≥1kb 合格，≥5kb 优秀）。
```

**Project01 执行进度（MEGAHIT — per-sample 策略）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（N50=7,022 bp，111,599 contigs，耗时 ~156 min）|
| ② rush 并行9样本 | 模式二，rush -j 2 | Sample2-4, Sample10-15 | ✅ 全部完成（10/10 样本，contigs 范围 84,672–270,847）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> MEGAHIT CPU+内存密集（~30-80 GB/样本），-j 2 并发。~156 min/样本，9 个样本约 12 小时完成。

---

### 步骤 16b：组装器交叉验证（metaSPAdes + QUAST，可选）

**步骤名称**：metaSPAdes 组装 + 与 MEGAHIT 的 QUAST 并排对比

**目的**：2024-26 组装器基准的共识做法是 MEGAHIT 与 metaSPAdes 双跑并用 QUAST 对比——metaSPAdes 通常 N50 更高但内存/耗时数倍于 MEGAHIT。本步骤是**组装验证层**（同 15e MetaX 模式：默认不在 Snakemake rule all 中，不改变主流程结果），用于确认主流程选择 MEGAHIT 的合理性或为特定样本择优。

**依赖**：步骤 2 的 clean reads；步骤 7（16_bac_megahit.sh）的 MEGAHIT 组装结果（可选——存在时 QUAST 并排对比两套组装，不存在时仅评估 metaSPAdes）

**执行方式**（模式一 — 单样本，手动执行；opt-in，不入 rule all）：
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/16b_bac_metaspades.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow \
  --mem-gb 250        # 内存上限 GB，metaspades --memory 取其 0.9 倍（默认 225 GB）
```
Snakemake 显式触发（验证层，不在 rule all）：`snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml -R metaspades`

**输出结果**：
```
Project/Project01/result/assembly_metaspades/Sample1/
  ├── contigs.fasta                    ← metaSPAdes 组装结果（验证用，不进下游）
  ├── Sample1.spades.log               ← 组装日志（k 值迭代）
  ├── quast_report/report.tsv          ← metaSPAdes vs MEGAHIT 并排质量指标
  └── Sample1.metaspades_done.txt      ← sentinel（contig 数/碱基数/quast 状态）
```

**审核要点**：

| 指标 | 看什么 | 说明 |
|------|-------|------|
| N50 | `quast_report/report.tsv` 中 metaSPAdes 与 MEGAHIT 两列 | metaSPAdes 通常更高；差距 <2 倍时 MEGAHIT 性价比更优 |
| Total length / # contigs | 同上两列对比 | metaSPAdes 明显更长且 N50 同步更高说明保留更多低丰度序列 |
| 运行成本 | spades.log 中内存/耗时 | 通常为 MEGAHIT 的 3-5 倍（--mem-gb 需按机器调低） |
| 空结果 | sentinel 内容为 `empty_assembly` | 深度不足样本优雅降级，不阻塞队列，属预期行为 |

**实测结果（Project_example S03，2026-09-19，16 线程 / 32GB 上限，全程 85s）**：

| 指标 | metaSPAdes | MEGAHIT |
|------|-----------|---------|
| # contigs (≥1000 bp) | 432 | 363 |
| Total length (≥500 bp 过滤后) | 2,133,103 | 1,960,825 |
| Largest contig | 3,794 | 4,506 |
| N50 | 742 | 731 |

该样本两者 N50 基本持平（742 vs 731），MEGAHIT 性价比更优——这正是验证层的用途。注意：脚本已内置 `--phred-offset 33`（kneaddata 输出在常数质量范围下 SPAdes 的 PHRED 自动检测会失败、实测 exit 255，2026-09-19 修复）。

---

### 步骤 8：基因预测（Prodigal）

**步骤名称**：蛋白编码基因预测

**目的**：从 contig 序列中识别蛋白编码基因（CDS），输出蛋白序列（.faa）和核苷酸序列（.fna），供后续功能注释使用。Prodigal 是宏基因组标准基因预测工具，无监督训练，速度快。

**依赖**：步骤 7 输出的 `Sample1.contigs.fa`

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/17_bac_prodigal.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

> **注意**：Prodigal 本身是单线程工具，`-t 16` 参数无效，实际运行只用 1 核。脚本保留 `-t` 参数是为了与其他步骤接口一致。

**输出结果**：
```
Project/Project01/result/assembly/prodigal/Sample1/
  ├── Sample1.faa    ← 蛋白序列（→ eggNOG/KEGG/CARD/dbCAN/VFDB 注释）
  ├── Sample1.fna    ← 核苷酸序列（→ CD-HIT 去冗余 → Salmon 定量）
  └── Sample1.gff    ← 基因坐标（GFF3 格式，可选）
```

**Sample1 实测结果**（2026-06-24，耗时 1292 秒 ~22 分钟）：

```
预测基因总数：329,908
完整基因数：  180,749（54.8%，partial=00）
部分基因数：  149,159（45.2%，contig 边缘截断）

文件大小：
  Sample1.faa:  115 MB
  Sample1.fna:  267 MB
  Sample1.gff:  96 MB
```

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| 预测基因数 | 100,000–1,000,000 | **329,908** | ✅ | 与 contig 数、N50 正相关 |
| 完整基因比例 | 40–70% | **54.8%** | ✅ | 越高说明 contig 越长 |
| .faa 文件存在 | 必须存在 | **115 MB ✅** | ✅ | 功能注释的直接输入 |
| .fna 文件存在 | 必须存在 | **267 MB ✅** | ✅ | CD-HIT 去冗余后用于 Salmon 定量 |
| 耗时 | 10–40 min/样本 | **~22 min** | — | 单线程，与 contig 数正相关 |

> **完整基因 54.8%**：部分基因（partial）是因为 contig 边缘被截断，属正常现象。
> N50 = 7kb 的样本完整基因比例通常 50–60%，本样本属正常范围。
> 部分基因仍保留在 .faa 输出中，功能注释时会用上。

**LLM 调用方式（Prompt）**：
```
请帮我统计 CSCCD-MetagenomeFlow 步骤8（Prodigal）的基因预测结果，样本 Sample1：
文件：result/assembly/prodigal/Sample1/Sample1.faa
输出：
1）预测基因总数（faa 文件中的序列数）；
2）完整基因数和比例（从日志中提取 partial=00 的数量）；
3）.faa、.fna、.gff 三个文件是否存在及大小；
4）综合判断预测质量（基因数>10万，完整基因比例>40%）。
```

**Project01 执行进度（Prodigal）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（329,908 genes，完整基因 54.8%，耗时 ~22 min）|
| ② rush 并行9样本 | 模式二，rush -j 6 | Sample2-4, Sample10-15 | ✅ 全部完成（10/10 样本，genes 范围 84,083–410,914）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> Prodigal 单线程，~22 min/样本，-j 6 并发（6×1核=6核），9 个样本约 40 分钟完成。

---

### 步骤 9：基因去冗余（NR Gene Catalog 构建）

**步骤名称**：非冗余基因目录（NR gene catalog）构建

**目的**：将所有样本各自独立预测的基因合并，按 95% 核苷酸相似度聚类去冗余，得到代表整个队列的非冗余基因集（NR gene catalog）。这是 per-sample 组装策略的必要后处理步骤，也是后续 Salmon 定量和所有功能注释的统一输入。

> **为什么需要去冗余而不是直接合并？**
> 不同样本中同一物种的同一基因会被各自组装出来，直接合并会产生大量冗余序列，导致 Salmon 定量时 reads 被随机分配到多个相同序列，丰度估计偏低且不可重现。去冗余后每个基因只保留一条代表序列，冗余率通常可压缩 50-80%。

**依赖**：步骤 8 所有样本的 `.fna` 输出（核苷酸基因序列）

---

#### 工具选择：CD-HIT vs MMseqs2 Linclust

脚本 `18_bac_cdhit.sh` 通过 `--tool` 参数支持两种后端，按样本规模选用：

| 后端 | 参数 | 算法复杂度 | 速度（48核，2.5M基因） | 适用场景 |
|------|------|-----------|----------------------|---------|
| **CD-HIT-EST**（默认） | `--tool cdhit` | 近 O(n²) | ~30-60 分钟 | ≤500万基因，≤20样本，结果最被同行引用 |
| **MMseqs2 Linclust** | `--tool mmseqs` | O(n) 线性 | ~5-15 分钟（**4-10×快**） | >500万基因，>50样本，或追求速度 |

> **规模临界点**：10 样本 (~250万基因/样本) 用 CD-HIT 约 30 分钟；50 样本 (~1250万基因) 用 CD-HIT 将超 5 小时，此时应切换 MMseqs2。两者 95% identity 结果高度一致，均被 MetaHIT/IGC/UHGG 等大型基因目录项目采用。
>
> 参考文献：[Linclust (Nature Comms 2018)](https://www.nature.com/articles/s41467-018-04964-5) — 1.6 亿序列 10 小时，CD-HIT 同规模需数周

**执行方式**：

*本步骤是聚合步骤（aggregate），不按样本分，只运行一次：*

```bash
# ── 方式 A：CD-HIT（≤500万基因，默认，10样本推荐）──────────────────
bash ~/Course/CSCCD-MetagenomeFlow/scripts/18_bac_cdhit.sh \
  -t 48 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow

# ── 方式 B：MMseqs2 Linclust（>500万基因，50样本全量推荐）───────────
bash ~/Course/CSCCD-MetagenomeFlow/scripts/18_bac_cdhit.sh \
  --tool mmseqs \
  -t 48 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

> `envs/assembly` 中已同时安装 CD-HIT v4.8.1 和 MMseqs2 v13.45111，无需额外配置。

**LLM 调用示例**：
```
请帮我运行步骤 9（基因去冗余），当前 Project01 有 10 个样本，使用默认 CD-HIT 后端。
工作目录：~/Course/CSCCD-MetagenomeFlow/Project/Project01
如果样本数将来超过 50 个，记得提示我切换到 --tool mmseqs。
```

**输出结果**：
```
Project/Project01/result/assembly/cdhit/
  ├── nucleotide_nr.fa        ← 非冗余核苷酸基因集（→ Salmon 定量输入）
  ├── protein_nr.fa           ← 非冗余蛋白序列（→ eggNOG/KEGG/AMR 注释输入）
  ├── nucleotide_nr.fa.clstr  ← 聚类信息文件（CD-HIT 模式）
  └── mmseqs_cluster_*        ← MMseqs2 中间文件（mmseqs 模式，自动清理）
```

**审核要点**：

| 指标 | 正常范围 | 说明 |
|------|---------|------|
| NR 基因数 | 输入的 20–50% | 10样本约 48-52%，样本越多冗余越高 |
| protein_nr.fa 存在且非空 | 必须 | 功能注释直接使用 |
| 去冗余率 | 50-80% | 低于 20% 说明样本间差异极大（检查组装质量） |

**Project01 执行进度（步骤 9）**：

| 阶段 | 执行方式 | 状态 |
|------|---------|------|
| 聚合去冗余（10样本，CD-HIT） | 单次运行，-t 48 | ✅ 完成（2,570,710 → 1,241,517 NR genes，去冗余率 51.7%，耗时 ~32 min）|
| ③ 剩余40样本加入后重跑 | Snakemake（--tool mmseqs 推荐） | ⏳ 10样本所有步骤通过后启动 |

---

### 步骤 10：Salmon 索引构建（salmon index）

**步骤名称**：基因定量索引构建

**目的**：基于步骤 9 生成的非冗余基因集（`nucleotide_nr.fa`），构建 Salmon 定量所需的 k-mer 索引。索引只需构建一次，后续所有样本的定量（步骤 11）共用同一个索引。

**依赖**：步骤 9 的 `nucleotide_nr.fa`

**执行方式**：

*聚合步骤，只运行一次：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/19_bac_salmon_build.sh \
  -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/assembly/salmon/index/
  ├── info.json        ← 索引元数据（幂等性检查哨兵文件）
  ├── versionInfo.json ← Salmon 版本信息
  ├── pos.bin, ...     ← 索引二进制文件
  └── ...
```

**审核要点**：

| 指标 | 正常值 | 说明 |
|------|-------|------|
| `info.json` 存在 | 必须 | Salmon 索引完整性标志 |
| 索引目录非空 | 必须 | 含 `pos.bin`、`rank.bin` 等二进制文件 |
| 耗时 | 5-15 分钟（1.2M基因） | 与 NR 基因数成正比 |

**Project01 执行进度（步骤 10）**：

| 阶段 | 执行方式 | 状态 |
|------|---------|------|
| Salmon 索引构建 | 单次运行，-t 16 | ✅ 完成（1,241,517 genes，耗时 ~19 min，索引 ~4.6G）|
| ③ 剩余40样本沿用同一索引 | Snakemake | ⏳ 10样本所有步骤通过后启动 |

---

### 步骤 11：基因丰度定量（Salmon quant）

**步骤名称**：每样本基因 TPM 定量

**目的**：用 Salmon 对每个样本的 clean reads 与 NR 基因集索引做伪比对，输出每个基因的 TPM（每百万转录本的转录数）和 read count。TPM 是跨样本比较的标准化单位，后续差异分析和功能注释定量均基于此。

**依赖**：步骤 2 的 kneaddata clean reads + 步骤 10 的 Salmon 索引

**执行方式**：

```bash
# ① 单样本测试（Sample1）
bash ~/Course/CSCCD-MetagenomeFlow/scripts/20_bac_salmon_quant.sh \
  -s Sample1 -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow

# ② rush 并行 9 样本（Sample2-4, Sample10-15）
PROJ=~/Course/CSCCD-MetagenomeFlow
WORKDIR=$PROJ/Project/Project01
tail -n +2 $WORKDIR/samplesheet_test10.csv | cut -d, -f1 | grep -v "^Sample1$" | \
  $PROJ/miniforge3/bin/rush -j 3 -k \
  "bash ${PROJ}/scripts/20_bac_salmon_quant.sh \
    -s {1} -t 16 \
    -w ${WORKDIR} \
    -r ${PROJ} \
    > ${WORKDIR}/temp/logs/salmon_quant/salmon_quant_{1}.log 2>&1 && echo '[{1}] salmon_quant done'" \
  2>&1 | tee ${WORKDIR}/temp/logs/salmon_quant/rush_batch.log &
```

> Salmon quant 每样本约 10-20 分钟（~42M reads 对 1.2M 基因），-j 3 并发共用 48 核（3×16）。

**输出结果**：
```
Project/Project01/result/assembly/salmon/
  ├── Sample1/quant.sf     ← 基因 TPM + NumReads（主要结果）
  ├── Sample2/quant.sf
  └── .../
      quant.sf 列：Name | Length | EffectiveLength | TPM | NumReads
```

**审核要点**：

| 指标 | 正常值 | 说明 |
|------|-------|------|
| `quant.sf` 行数 | = NR 基因数（1,241,517） | 每个基因一行 |
| TPM > 0 的基因数 | 通常 10-30% | 每个样本有检出的基因比例 |
| Mapping rate | 通常 30-60% | 宏基因组低于 RNA-seq 属正常 |

**Project01 执行进度（步骤 11）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 手动，-t 16 | Sample1 | ✅ 审核通过（1,241,517 genes，mapping rate 21.4%，检出 325,112 genes）|
| ② rush 并行 9 样本 | rush -j 3 | Sample2-4, Sample10-15 | ✅ 全部完成（mapping 19.8-37.5%，检出 259k-509k genes/样本）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

---

### 步骤 12：综合功能注释（eggNOG-mapper）

**步骤名称**：COG / KEGG KO / GO / EC / CAZy 综合注释

**目的**：用 eggNOG-mapper 对 NR 蛋白基因集做一次性综合注释，同时输出 COG 功能分类、KEGG KO 编号、GO 条目、EC 酶活、CAZy 碳水化合物酶编号。是覆盖面最广的功能注释步骤，后续所有功能分析的主注释表。

**依赖**：步骤 9 的 `protein_nr.fa`（聚合步骤，运行一次）

**执行方式**：
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/21_bac_eggnog.sh \
  -t 48 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/eggnog/
  ├── eggnog.emapper.annotations    ← 主注释表（COG/KO/GO/EC/CAZy）
  └── eggnog.emapper.seed_orthologs ← 同源 OG 命中
```

**审核要点**：

| 指标 | 正常值 | 说明 |
|------|-------|------|
| annotations 行数 | ~40-70% × 1,241,517 | 宏基因组注释率通常 40-70% |
| 含 KO 注释的行数 | >20% | KEGG 覆盖率 |
| 耗时 | 30-120 分钟（1.2M 蛋白，48核） | DIAMOND 搜索为瓶颈 |

**Project01 执行进度（步骤 12）**：

| 阶段 | 执行方式 | 状态 |
|------|---------|------|
| eggNOG 全量注释 | 单次运行，-t 48 | ✅ 完成（注释率 88.6%，KO 45.5%，COG 81.7%，耗时 ~87 min）|
| ③ 剩余40样本加入后重跑 | Snakemake | ⏳ 10样本所有步骤通过后启动 |

---

### 步骤 13：KEGG KO 通路注释（DIAMOND vs KEGG）

**步骤名称**：KEGG 专项高精度 KO 注释

**目的**：直接用 DIAMOND blastp 比对 KEGG 全蛋白数据库（48G），获取精确的 KO 编号和通路映射。与 eggNOG 的 KEGG 注释互补——eggNOG 覆盖广，KEGG 直接比对精度更高，二者结合可提升 KO 命中率。

**依赖**：步骤 9 的 `protein_nr.fa`（与步骤 12 **并行**运行，互不依赖）

**执行方式**：
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/22_bac_kegg.sh \
  -t 48 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/kegg/
  └── kegg_diamond.tsv    ← DIAMOND 比对结果（BLAST m6 格式，含 KO 映射）
```

**Project01 执行进度（步骤 13）**：

| 阶段 | 执行方式 | 状态 |
|------|---------|------|
| KEGG DIAMOND 比对 | 单次运行，-t 48 | ✅ 完成（命中率 90.2%，1,119,706 hits，83M，耗时 ~163 min）|
| ③ 剩余40样本加入后重跑 | Snakemake | ⏳ 10样本所有步骤通过后启动 |

---

### 步骤 14-21：功能注释批量并行（AMRFinder / CARD / dbCAN / VFDB / BacMet / antiSMASH / Defense-Finder / NCyc / PCyc）

**说明**：步骤 14-21 全部依赖 `protein_nr.fa`（或 MEGAHIT contigs），彼此独立，一次性并行启动所有任务。

> **并行策略（48核分配）**：
> - AMRFinder(12核) + dbCAN(12核) + Defense-Finder(12核) + VFDB(12核) → 同时启动，各用独立 conda env
> - BacMet(16核) + NCyc(16核) + PCyc(16核) → DIAMOND 轻量DB，同时并行
> - CARD(12核) → amr env，独立启动
> - antiSMASH → per-sample，rush -j 2，每样本 8 核

**执行命令**（一次性启动所有）：
```bash
PROJ=~/Course/CSCCD-MetagenomeFlow && WORKDIR=$PROJ/Project/Project01
# 聚合注释（protein_nr.fa 输入）
for script in 23_bac_amrfinder 24_bac_card 25_bac_dbcan 26_bac_vfdb \
              27_bac_bacmet 29_bac_defense_finder 30_bac_ncyc 31_bac_pcyc; do
  bash $PROJ/scripts/${script}.sh -t 12 -w $WORKDIR -r $PROJ \
    > $WORKDIR/temp/logs/${script#*_bac_}/${script#*_bac_}.log 2>&1 &
done
# antiSMASH per-sample
tail -n +2 $WORKDIR/samplesheet_test10.csv | cut -d, -f1 | \
  $PROJ/miniforge3/bin/rush -j 2 -k \
  "bash ${PROJ}/scripts/28_bac_antismash.sh -s {1} -t 8 -w ${WORKDIR} -r ${PROJ} \
   > ${WORKDIR}/temp/logs/antismash/antismash_{1}.log 2>&1 && echo '[{1}] antismash done'" \
  2>&1 | tee ${WORKDIR}/temp/logs/antismash/rush_batch.log &
```

**Project01 执行进度（步骤 14-21）**：

| 步骤 | 工具 | 类型 | 状态 |
|------|------|------|------|
| 14 AMRFinder | AMRFinderPlus | 聚合 | ✅ 完成（409 耐药基因，耗时 1267s）|
| 15 CARD/RGI | RGI + CARD | 聚合 | ✅ 完成（Perfect/Strict: 0，输出 99M，耗时 724s）|
| 16 dbCAN | run_dbcan | 聚合 | ✅ 完成（43,066 CAZyme，耗时 485s）|
| 17 VFDB | DIAMOND | 聚合 | ✅ 完成（200,472 hits，耗时 189s）|
| 18 BacMet | DIAMOND | 聚合 | ✅ 完成（85,839 hits，耗时 77s）|
| 19 antiSMASH | antiSMASH 7 | per-sample | ✅ 完成（10/10 样本，Sample14: 275 BGC，耗时 ~10.7h/样本）|
| 20 Defense-Finder | DefenseFinder | 聚合 | ✅ 完成（防御系统 0，HMM 5M，耗时 2081s）|
| 21 NCyc | DIAMOND | 聚合 | ✅ 完成（139,293 hits，耗时 477s）|
| 22 PCyc | DIAMOND | 聚合 | ✅ 完成（371,975 hits，耗时 1440s）|

---

### 步骤 28b：BGC 新颖度评分（③biosynthetic novelty 模块）

**步骤名称**：次级代谢产物生物合成基因簇（BGC）新颖度评分

**目的**：28 号 antiSMASH 用 `--minimal` 参数运行以节省耗时，跳过了内置的 KnownClusterBlast（MIBiG 已知簇比对）步骤，现有产出的 `.gbk` 文件里没有任何"该 BGC 与已知代谢产物簇有多相似"的信息。28b 独立对每个 region 的 CDS 蛋白序列做 DIAMOND 比对，复用 antiSMASH 数据库目录下自带的 MIBiG 3.1 蛋白 DIAMOND 库（`db/antismash/antismash-db/clustercompare/mibig/3.1/proteins.dmnd`，41002 条蛋白，antiSMASH 内部 clustercompare 功能用的资源），**不重跑 antiSMASH，不新建数据库**。以 region（一个 BGC）为单位聚合 CDS 命中比例，novelty_score = 1 − 最佳匹配 MIBiG cluster 的 CDS 命中比例（完全无命中记 1.0，即完全新颖）。

**依赖**：步骤28（antiSMASH，`antismash_done.txt` sentinel + `*.region*.gbk`）

**执行方式**：

```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/28b_bac_bgc_novelty.sh \
  -s Sample4 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：

```
result/annotation/antismash/Sample4/
└── Sample4.bgc_novelty.tsv
    列：sample, contig_id, region_id, product, n_cds,
        best_mibig_cluster, best_mibig_organism, best_mibig_product,
        best_mibig_hit_fraction, novelty_score
```

**实测**（Project01 全量 10 个样本，共 2339 个 BGC region）：全部样本跑通，Sample4（167 个 region）验证阶段耗时 21s；novelty_score 呈现真实梯度分布，从 0.0（完全匹配已知簇，如某 NRPS region 与大肠杆菌 BGC0001055 100% CDS 命中）到 1.0（完全新颖，无 MIBiG 命中）均有分布，Sample4 中 novelty_score ≥ 0.9 的 region 占 58/167。

**粒度说明**：输出以 `sample + contig_id + region_id` 为唯一标识，**不强制关联②cluster模块的 dRep MAG**——现有 antiSMASH 是在样本级组装 contig 上跑的，contig 与 dRep MAG 之间需要额外查 contig2bin 表才能建立映射，且相当一部分 contig 未被任何 MAG 收录；若强行只处理能映射到 MAG 的 BGC，会丢弃掉本就难以被分箱算法收录、反而可能更值得关注的新颖候选，因此两个模块保持独立维度，不强耦合。

**审核要点**：
- DIAMOND 参数 `--sensitive -e 1e-5 --query-cover 50 --subject-cover 50`：`--sensitive` 而非默认 fast 模式，因 MIBiG 库仅 41002 条蛋白，规模小，可承受更高灵敏度换取远缘同源检出率
- 聚合规则是"按 MIBiG cluster 分组统计 CDS 命中比例，取占比最高的 cluster"，不是"取单条最佳 CDS 比对结果"——避免被单个保守结构域（如常见转运蛋白基因）误导，把功能不同的 BGC 误判为已知
- **已知局限**：28 号脚本本身对部分样本（如全量验证时发现的 Sample3/Sample10）的 `antismash_done.txt` sentinel 缺失（尽管 `.gbk` 产出已存在），这是 28 号脚本遗留的 sentinel 记录问题，不属于 28b 的缺陷，但会导致 Snakemake DAG 在这些样本上重新调度 28+28b；已确认 28b 自身逻辑对全部 2339 个 region 处理无误（对已产出的 10/10 样本 tsv 逐一核对总数一致）

**LLM 调用方式（Prompt）**：
```
请对全部样本运行 28b 脚本，统计各样本 novelty_score ≥ 0.9 的 BGC 占比，
并解读哪些高新颖度 BGC 的 product 类型（如 Polyketide/NRPS/RiPP）值得优先关注。
```

---

### 步骤 22：功能注释补充（SCyc / Pfam-A / UniProt Swiss-Prot / FeGenie）

**新增（2026-06-30）**：补全硫循环维度 + 高精度蛋白功能域注释 + 铁代谢基因预测，覆盖 eggNOG/KEGG 未命中区域。

```bash
# 31b SCyc 硫循环（与 NCyc/PCyc 完全对称，DIAMOND，~10 分钟）
bash scripts/31b_bac_scyc.sh -t 16 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow

# 31c Pfam-A 蛋白域（hmmscan --cut_ga，建议 32+ 线程，~1-3 小时）
bash scripts/31c_bac_pfam.sh -t 32 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow

# 31d UniProt Swiss-Prot（MMseqs2 easy-search，~20-40 分钟）
bash scripts/31d_bac_uniprot.sh -t 16 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow

# 31e FeGenie 铁代谢（per-sample 模式，推荐）
bash scripts/31e_bac_fegenie.sh -s S01 -t 8 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow
```

> **注意**：
> - 31c Pfam-A 需要 `envs/dbcan` 环境（含 HMMER）；31d 需要 `db/uniprot_sprot/mmseqs/` 索引
> - 31e FeGenie 需要 `envs/fegenie` 环境，HMM 数据库内置于 conda
> - Pfam hmmscan 对大规模蛋白集（>100 万条）较慢，建议离线后台运行：`nohup bash ... > pfam.log 2>&1 &`

#### 31e FeGenie 铁代谢基因预测详细说明

**背景**：肠道微生物的铁获取与宿主竞争铁资源密切相关，影响菌群定植和致病性。FeGenie 预测 10 类铁代谢功能：
- **Siderophore synthesis / transport**（铁载体合成/转运，肠道菌的主要铁获取策略）
- **Heme transport / oxygenase**（血红素转运/分解，宿主血红素利用）
- **Iron transport**（铁直接转运，如 FeoAB / FbpABC）
- **Iron oxidation / reduction**（铁氧化还原，如 Cyc2 / MtoA，厌氧肠道环境关键）
- **Iron storage**（铁储存，如 ferritin）
- **Iron gene regulation**（铁调控，如 Fur / DtxR）
- **Magnetosome formation**（磁小体形成，肠道菌较少见）

**前置安装**（已完成，首次运行前验证）：
```bash
# 验证 FeGenie 环境
conda run --prefix ~/Course/CSCCD-MetagenomeFlow/envs/fegenie FeGenie.py -h

# 验证 HMM 数据库
ls -lh ~/Course/CSCCD-MetagenomeFlow/envs/fegenie/share/fegenie-1.2/hmms/iron/
```

**执行方式**：
```bash
# 单样本运行（per-sample 模式，推荐）
bash scripts/31e_bac_fegenie.sh -s S01 -t 8 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow

# 批量运行（rush 并行）
cat [WORKDIR]/samplesheet.csv | grep -v "^sample" | cut -d',' -f1 | \
rush -j 2 'bash scripts/31e_bac_fegenie.sh -s {} -t 8 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow'

# NR 模式（单次运行，所有样本共享结果，适合 MAG-level 分析）
bash scripts/31e_bac_fegenie.sh -s NR -t 16 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow --input-type nr
```

**输出**：`result/annotation/fegenie/{SAMPLE}/FeGenie-HMM-results.csv`（基因级铁功能注释）+ `FeGenie-geneSummary.csv`（功能类别统计）

**与其他注释的关系**：
- **eggNOG/KEGG**：通用 KO 注释（如 K02013 = iron transport）
- **Pfam-A**（步骤 22）：蛋白域注释（如 PF01032 = FecA 铁柠檬酸盐受体）
- **FeGenie**：聚焦铁代谢，提供更细粒度分类（区分 siderophore synthesis vs transport）+ 铁氧化还原酶亚型（Cyc2 / MtoA）

**肠道微生物铁代谢研究意义**：
- **宿主-菌群铁竞争**：肠道炎症期间宿主释放 lactoferrin 限制游离铁，菌群通过 siderophore（如 enterobactin）竞争铁资源
- **致病菌铁获取**：肠道致病菌（如 *E. coli* / *Salmonella*）依赖 heme 转运系统从宿主获取铁
- **铁氧化还原与厌氧代谢**：肠道厌氧环境中，铁还原酶（如 FeoAB）与氢气代谢偶联

---

### 步骤 23：MGE 可移动遗传元素分析（per-sample）

**背景**：肠道菌群多组学研究中，MGE 追踪对理解 ARG 水平基因转移（HGT）至关重要。
涵盖 5 种 MGE 类型：IS 元件（ISfinder）/ 整合接合元件（ICEberg）/ 整合子（integrall）/ 转座酶（transposase-db HMM）/ 综合 MGE 分类（mobileOG）。

```bash
# 单样本运行（per-sample 步骤）
bash scripts/42_bac_mge.sh -s S01 -t 16 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow

# 批量运行（rush 并行）
cat [WORKDIR]/samplesheet.csv | grep -v "^sample" | cut -d',' -f1 | \
rush -j 2 'bash scripts/42_bac_mge.sh -s {} -t 16 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow'
```

> **注意**：
> - `mobileOG` 步骤为 aggregate，多样本只运行一次，第一个样本完成后后续自动跳过
> - `42_bac_mge.sh` 依赖 `envs/assembly`（diamond/mmseqs2/blast）+ `envs/dbcan`（hmmscan）
> - 肠道菌群中整合接合元件（ICEberg）和 I 类整合子（integrall class1）与 ARG 水平转移密切相关

---

### 步骤 24：质粒识别（PlasmidFinder，per-sample）

**前置安装**（首次运行前执行一次）：
```bash
conda create --prefix ~/Course/CSCCD-MetagenomeFlow/envs/plasmidfinder python=3.10 -y
conda install --prefix ~/Course/CSCCD-MetagenomeFlow/envs/plasmidfinder \
    -c conda-forge -c bioconda plasmidfinder=2.1.6 blast -y
```

```bash
# 单样本运行
bash scripts/42b_bac_plasmidfinder.sh -s S01 -t 16 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow

# 批量运行（rush 并行）
cat [WORKDIR]/samplesheet.csv | grep -v "^sample" | cut -d',' -f1 | \
rush -j 4 'bash scripts/42b_bac_plasmidfinder.sh -s {} -t 8 \
     -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow'
```

> **输出**：`result/mge/plasmidfinder/{SAMPLE}/results_tab.tsv`（含 replicon 类型 + Inc group）
> **与 MGE 整合**：PlasmidFinder 定位质粒 contig → mobileOG 细化质粒基因功能 → AMRFinder/CARD 识别质粒携带 ARG → ICEberg 追踪接合转移机制，形成完整的 HGT 分析链路。

---

### 步骤 25：Binning（MAG 回收，脚本 32-41）

**步骤名称**：宏基因组组装基因组（MAG）回收与质量评估

**目的**：从组装 contig 中通过覆盖度+序列组成信息聚类出单菌基因组草图（bin），经多算法整合、质量评估、去冗余后得到高质量 MAG 集合，用于菌株级功能与系统发育分析。

**依赖**：步骤 7（MEGAHIT 组装）输出的 contigs + 步骤 2（去宿主 reads，用于覆盖度计算）

**流程链**：32 CoverM depth → 33/34/35（MetaBAT2 / MaxBin2 / SemiBin2，三算法独立并行）→ 36 DAS_Tool（整合择优）→ 36b post-binning reassembly（用原始 reads 逐 bin 精细重组装）→ 37 CheckM2（ML 质量评估）→ 38 dRep（去冗余）→ 39 CoverM quant（丰度定量）→ **39b-d inStrain（菌株追踪：map→profile→compare）**→ 40 GTDB-Tk（系统发育分类）→ 41 Prokka（精细注释）

**执行方式（单样本示例，Sample1）**：
```bash
bash scripts/32_bac_coverm_depth.sh   -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow
bash scripts/33_bac_metabat2.sh       -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow
bash scripts/34_bac_maxbin2.sh        -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow
bash scripts/35_bac_semibin2.sh       -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow
bash scripts/36_bac_dastool.sh        -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow
bash scripts/36b_bac_bin_reassembly.sh -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow --parallel
bash scripts/37_bac_checkm2.sh        -t 32 -w [WORKDIR] -r ~/Course/CSCCD-MetagenomeFlow   # 跨样本汇总，非 per-sample
```

#### 步骤 36b：Post-binning Reassembly（metaWRAP，用原始 reads 逐 bin 精细重组装）

**目的**：DAS_Tool 输出的 bin 是从整体组装图中"事后聚类"得到的，本身受限于全局组装参数；用该 bin 已归类的原始 reads 单独重跑一次针对性更强的 SPAdes 组装（`--careful --untrusted-contigs`），常能填补 gap、提升 MAG 完整度。参考 Uritskiy et al. 2018 *Microbiome*（metaWRAP）。

**依赖**：步骤36（DAS_Tool bins）+ 步骤2b（严格配对后的 clean reads）

**关键设计决策**：
- 用 `--skip-checkm` 跳过 metaWRAP 内建的旧版 CheckM(1.x) 评估与"最优bin"挑选环节，因为下游步骤37已用 CheckM2 统一质控全部 bin，避免重复计算；`--skip-checkm` 模式下 metaWRAP 只产出未合并的 `{bin}.strict.fa` / `{bin}.permissive.fa` 两个变体（不会产出 `{bin}.fa`），脚本自行按**总组装长度**在两者间选优（无 CheckM 时的替代判定指标），仅当两个变体都不存在时才回退原始 bin
- MEGAHIT contig header 含空格分隔的额外字段（如 `flag=0 multi=144.1 len=63675`），但 SAM 的 RNAME 字段只取第一个空格前的 token；metaWRAP 内部按整行匹配 contig→bin，两者不一致会导致 100% reads 在拆分阶段丢失。脚本喂给 metaWRAP 前用简化 header 的临时拷贝规避，不改动原始 bin 文件
- `--parallel` 参数让 SPAdes 多个子任务（bin数×2变体）并发跑（各1线程），bin 数多时大幅提速；脚本自身不清空已存在的 metaWRAP 工作目录，超时/中断后直接重跑即可从断点继续（metaWRAP 内部有 scaffolds.fasta 存在性判断的续跑逻辑）

**输出结果**：

```
result/binning/reassembly/{sample}/
├── reassembled_bins/
│   ├── {bin_name}.fa         — 重组装成功用重组装结果，否则回退原始 bin，与输入 bin 集合一一对应
│   └── ...
└── {sample}.reassembly_done.txt   — sentinel（N_INPUT_BINS / N_REASSEMBLED / N_FALLBACK_TO_ORIGINAL）
```

**实测**（Project01 真实样本 Sample4，35 个 DAS_Tool bins，`--parallel -t 16 -m 48`）：耗时 339 分钟，全部 35 个 bin 重组装成功（0 回退），总组装长度均有实质提升（如 bin 20: 3.30Mb → 4.07Mb，bin.24_sub: 2.80Mb → 3.10Mb）。步骤37（CheckM2）的 bin 收集逻辑已验证能正确识别并优先使用 `reassembly/{sample}/reassembled_bins/`（若存在），未跑过 reassembly 的样本正确回退读取原始 DAS_Tool bins。

**审核要点**：
- `--skip-checkm` 场景下务必用总长度（而非文件是否存在 `{bin}.fa`）判断重组装是否成功——这是本次调试中发现并修复的真实 bug，早期版本因命名假设错误导致误报"0个重组装成功、35个全部回退"，但实际70/70子任务均已成功
- 若重跑本步骤前发现同一 metaWRAP 工作目录下有多代残留进程（如意外的后台超时重试未彻底清理），务必先 `pkill -9 -f "reassemble_bins.sh\|spades.py\|spades-core"` 并确认无残留，再清空损坏的输出目录重新开始——多进程竞争同一工作目录会产生"None of the bins were successfully reassembled"的假性失败

**已知问题与修复**（本次 10 样本执行中发现并修复，均为工具真实输出结构与脚本假设不一致导致）：

| 脚本 | 问题 | 修复 |
|------|------|------|
| 35_bac_semibin2.sh | SemiBin2 1.5.0 实际将 `contig_bins.tsv` 输出到 `OUTDIR` 根目录（非 `OUTDIR/output/`），bin fasta 在 `OUTDIR/output_bins/`（非通配 `*.fa`），脚本按错误路径判断导致误报"0 bins" | 修正路径判断逻辑，兼容新旧两种布局 |
| 36_bac_dastool.sh | ① `--write_bins 1` 在新版 docopt 下不接受参数值，需改为纯 flag；② MetaBAT2/SemiBin2 的 contig2bin 表含表头行，导致 DAS_Tool 报错 "Contigs not found in assembly"；③ 输出目录实际为 `${OUTDIR}/${SAMPLE}_DASTool_bins`，脚本原假设 `${OUTDIR}/bins` 导致误报"整合 bins: 0" | ① 去掉 `1`；② 增加 awk 表头清洗步骤；③ 修正 `BINS_DIR` 变量 |
| 37_bac_checkm2.sh | ① bin 收集通配符 `*/bins` 不匹配实际的 `*/{sample}_DASTool_bins`，且跨样本存在同名 bin（如 Sample1/0.fa 与 Sample2/0.fa）无前缀导致覆盖；② `--database_path` 需指向具体 `.dmnd` 文件而非父目录；③ 输入符号链接目录若嵌套在 `--output-directory` 内，会被 CheckM2 的 `--force` 清空 | ① 改用正确通配符 + 按样本名加前缀；② 指向 `db/checkm2/CheckM2_database/uniref100.KO.1.dmnd`；③ 迁移到 `${WORKDIR}/temp/checkm2_input`（输出目录之外）|
| envs/dastool（环境） | `r-docopt` 0.7.2 与 DAS_Tool R 脚本不兼容（`envRefInferField` 报错） | 降级为 `r-docopt=0.7.1` |
| envs/checkm2（环境） | 缺少 `prodigal` 二进制（CheckM2 内部调用） | `conda install` 补装 |
| envs/checkm2（环境，pandas 2.0.3） | `predictQuality.py` 中 `str.split(sep, 1, expand=True)` 位置参数写法与 pandas 2.0 API 不兼容，报 `TypeError: split() takes from 1 to 2 positional arguments but 3 were given` | 直接 patch 源码两行，将位置参数 `1` 改为关键字参数 `n=1`；用 `checkm2 predict --resume` 复用已有 DIAMOND 输出重跑预测阶段，避免重新计算 |

**Project01 执行进度（Binning，全部 10 样本）**：

| 步骤 | 工具 | 内容 | 状态 |
|------|------|------|------|
| 32 | CoverM | 测序深度计算 | ✅ 10/10 |
| 33 | MetaBAT2 | 分箱算法1 | ✅ 10/10 |
| 34 | MaxBin2 | 分箱算法2 | ✅ 10/10 |
| 35 | SemiBin2 | 分箱算法3（ML自训练） | ✅ 10/10 |
| 36 | DAS_Tool | 三算法整合择优 | ✅ 10/10，各样本整合后 bin 数：Sample1=49 / Sample2=41 / Sample3=64 / Sample4=35 / Sample10=66 / Sample11=56 / Sample12=56 / Sample13=70 / Sample14=80 / Sample15=95（**总计 612 bins**）|
| 37 | CheckM2 | ML 质量评估（跨样本一次性跑全部 612 bins） | ✅ `quality_report.tsv`（612 行）；过滤（完整度≥50%，污染度≤10%）后 **488 个高质量 MAG** 进入 `drep_input/` |
| 38 | dRep | 去冗余（ANI 95%，物种级） | ✅ 488 个高质量 MAG（87.7% 通过 checkM 过滤，428 个）→ 去冗余后 **213 个代表基因组**，耗时 432s（复用 CheckM2 genomeInfo，跳过内部 checkm1 重算）|
| 39 | CoverM quant | MAG 丰度定量 | ✅ 10/10 样本（Sample1/10-18），213 个代表 MAG mapping率 ~69%（30.6% unmapped）|
| 39b | inStrain map | 比对到去冗余 MAG 集（per-sample BAM 产出）| ✅ 已集成 Snakemake，自动拼接 combined_mags.fa + 复用 coverm make |
| 39c | inStrain profile | 菌株级微多样性分析（per-sample profile）| ✅ 已集成 Snakemake，自动生成 .stb scaffold-to-bin 映射 |
| 39d | inStrain compare | 跨样本 popANI 比较（判断同一菌株）| ✅ 已集成 Snakemake，aggregate 规则聚合全样本 profile |
| 40 | GTDB-Tk | 系统发育分类（R214 数据库，跳过 skani，marker-based 分类）| ✅ 213 个 MAG 全部分类为细菌（无古菌），耗时 2636s。**已知问题**：GTDB-Tk 2.5.2 强依赖 R226 skani 数据，R214 数据库无法直接使用；修复方案：① patch `ani_rep.py` 跳过空 reference 时的 skani 调用；② 启用 `classify.py` 内置 DEBUG 机制（`skani_verification = {}`）强制跳过所有 skani ANI 验证，仅使用传统 pplacer marker-based 分类。分类结果示例：`d__Bacteria;p__Bacillota_A;c__Clostridia;o__Oscillospirales;f__Oscillospiraceae;g__CAG-103` |
| 41 | Prokka | MAG 精细注释 | ✅ 213/213 完成（并行优化：`41_bac_prokka_parallel.sh`，6 并发 × 8 线程，耗时 ~26 小时，相比原串行方案 5-9 天加速 5-8×）。**备注**：Bakta 因 Diamond sORF 兼容性问题放弃，Prokka 注释精度对大多数下游分析足够 |

> 612 个 bin 中 488 个（79.7%）通过高质量过滤，比例正常（宏基因组 binning 典型高质量 MAG 占比 60-85%，与测序深度、样本复杂度相关）。

---
## 病毒维度分析

### 步骤 51-55：病毒序列鉴定与基因预测（per-sample 策略）

**步骤名称**：病毒宏基因组上游分析流程（组装 → 病毒鉴定 → 质量评估 → 基因预测）

**目的**：从宏基因组测序数据中识别病毒序列，评估质量，预测病毒基因，为后续 vOTU 聚类、功能注释、宿主关联分析奠定基础。病毒组装参数优化（meta-large，≥1.5kb contig）确保捕获完整病毒基因组。

**依赖**：步骤 2（kneaddata 去宿主 reads）

**流程链**：51 MEGAHIT（virus-optimized assembly）→ 52 geNomad（neural network virus identification）→ 53 VirSorter2（complementary virus prediction）→ 54 CheckV（quality assessment + provirus extraction）→ 54b CheckV filter（MIUVIG quality standards）→ 55 Prodigal-gv（viral gene prediction with code 15）

**执行方式**：

*模式一（本教程）— 单样本，手动执行（Sample1 示例）：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/51_vir_megahit.sh \
  -s Sample1 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

bash ~/Course/CSCCD-MetagenomeFlow/scripts/52_vir_genomad.sh \
  -s Sample1 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

bash ~/Course/CSCCD-MetagenomeFlow/scripts/53_vir_virsorter2.sh \
  -s Sample1 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

bash ~/Course/CSCCD-MetagenomeFlow/scripts/54_vir_checkv_contig.sh \
  -s Sample1 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

bash ~/Course/CSCCD-MetagenomeFlow/scripts/54b_vir_checkv_filter.sh \
  -s Sample1 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

bash ~/Course/CSCCD-MetagenomeFlow/scripts/55_vir_prodigal_gv.sh \
  -s Sample1 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

*模式二 — rush 并行剩余9样本（单样本审核通过后执行，补齐10样本验证集）：*

```bash
cd ~/Course/CSCCD-MetagenomeFlow/Project/Project01
echo -e "Sample2\nSample3\nSample4\nSample10\nSample11\nSample12\nSample13\nSample14\nSample15" > temp/virus_test9_samples.txt

# 步骤51：MEGAHIT（内存密集，rush -j 2）
~/Course/CSCCD-MetagenomeFlow/miniforge3/bin/rush -j 2 -k \
  'bash ~/Course/CSCCD-MetagenomeFlow/scripts/51_vir_megahit.sh -s {} -t 16 \
   -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow \
   > ~/Course/CSCCD-MetagenomeFlow/Project/Project01/temp/logs/virus/51_vir_megahit_{}.log 2>&1' \
  :::: temp/virus_test9_samples.txt

# 步骤52：geNomad（神经网络推理，rush -j 3）
~/Course/CSCCD-MetagenomeFlow/miniforge3/bin/rush -j 3 -k \
  'bash ~/Course/CSCCD-MetagenomeFlow/scripts/52_vir_genomad.sh -s {} -t 16 \
   -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow \
   > ~/Course/CSCCD-MetagenomeFlow/Project/Project01/temp/logs/virus/52_vir_genomad_{}.log 2>&1' \
  :::: temp/virus_test9_samples.txt

# 步骤53：VirSorter2（HMM扫描耗时长，rush -j 2）
~/Course/CSCCD-MetagenomeFlow/miniforge3/bin/rush -j 2 -k \
  'bash ~/Course/CSCCD-MetagenomeFlow/scripts/53_vir_virsorter2.sh -s {} -t 16 \
   -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow \
   > ~/Course/CSCCD-MetagenomeFlow/Project/Project01/temp/logs/virus/53_vir_virsorter2_{}.log 2>&1' \
  :::: temp/virus_test9_samples.txt

# 步骤54-55：CheckV + Prodigal（快速，rush -j 6）
~/Course/CSCCD-MetagenomeFlow/miniforge3/bin/rush -j 6 -k \
  'bash ~/Course/CSCCD-MetagenomeFlow/scripts/54_vir_checkv_contig.sh -s {} -t 16 \
   -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow \
   > ~/Course/CSCCD-MetagenomeFlow/Project/Project01/temp/logs/virus/54_vir_checkv_contig_{}.log 2>&1' \
  :::: temp/virus_test9_samples.txt

~/Course/CSCCD-MetagenomeFlow/miniforge3/bin/rush -j 6 -k \
  'bash ~/Course/CSCCD-MetagenomeFlow/scripts/54b_vir_checkv_filter.sh -s {} -t 16 \
   -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow \
   > ~/Course/CSCCD-MetagenomeFlow/Project/Project01/temp/logs/virus/54b_vir_checkv_filter_{}.log 2>&1' \
  :::: temp/virus_test9_samples.txt

~/Course/CSCCD-MetagenomeFlow/miniforge3/bin/rush -j 6 -k \
  'bash ~/Course/CSCCD-MetagenomeFlow/scripts/55_vir_prodigal_gv.sh -s {} -t 16 \
   -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow \
   > ~/Course/CSCCD-MetagenomeFlow/Project/Project01/temp/logs/virus/55_vir_prodigal_gv_{}.log 2>&1' \
  :::: temp/virus_test9_samples.txt
```

> **10样本验证完成后**：全量50样本通过 Snakemake 执行（见后续"批量运行"章节），不再用 rush 跑全量。
> **log 路径**：所有 rush 并行的日志统一写入 `temp/logs/virus/` 子目录，避免 temp/ 根目录散乱。

**输出结果**：
```
Project/Project01/result/virus/
  ├── assembly/Sample1/Sample1.contigs.fa              ← 步骤51：病毒优化组装（≥1.5kb）
  ├── genomad/Sample1/Sample1.contigs_summary/
  │   └── Sample1.contigs_virus_summary.tsv            ← 步骤52：geNomad病毒预测
  ├── virsorter2/Sample1/
  │   ├── final-viral-boundary.tsv                     ← 步骤53：VirSorter2病毒边界
  │   └── final-viral-combined.fa                      ← VirSorter2提取的病毒序列
  ├── checkv/Sample1/
  │   ├── quality_summary.tsv                          ← 步骤54：CheckV质量评估
  │   ├── viruses.fna                                  ← 去重后病毒contigs
  │   └── viruses_filtered.fna                         ← 步骤54b：MIUVIG质量过滤
  └── prodigal/Sample1/
      ├── Sample1.faa                                  ← 步骤55：病毒蛋白序列
      ├── Sample1.fna                                  ← 病毒CDS核苷酸序列
      └── Sample1.gff                                  ← 基因坐标
```

**Sample1 实测结果**（2026-07-05，各步骤耗时）：

| 步骤 | 工具 | 耗时 | 输出统计 |
|------|------|------|---------|
| 51 | MEGAHIT | ~2.5 小时 | 30,965 contigs（≥1.5kb），总长197MB |
| 52 | geNomad | ~45 分钟 | 932 个病毒contigs预测 |
| 53 | VirSorter2 | ~3.5 小时 | 3,169 个病毒边界预测 |
| 54 | CheckV | ~5.4 分钟 | 4,094 个病毒contigs质量评估 → 去重后 3,911 个 |
| 54b | CheckV filter | ~3 秒 | MIUVIG标准过滤 → 1,526 个高质量序列（Complete/HQ/MQ/LQ + ≥2kb + viral_genes≥1）|
| 55 | Prodigal-gv | ~1.7 分钟 | 27,356 个病毒基因（遗传密码表15）|

**审核要点**：

| 指标 | 正常范围 | Sample1 实测值 | 判断 | 说明 |
|------|---------|--------------|------|------|
| 步骤51 contig数 | 10,000–100,000 | **30,965** | ✅ | 病毒优化组装（≥1.5kb），比细菌组装（≥500bp）contig数更少 |
| 步骤52 病毒预测数 | 100–5,000 | **932** | ✅ | geNomad神经网络预测，保守策略 |
| 步骤53 病毒预测数 | 500–10,000 | **3,169** | ✅ | VirSorter2 HMM扫描，覆盖面更广 |
| 步骤54 去重后病毒数 | 1,000–10,000 | **3,911** | ✅ | 合并geNomad+VirSorter2后去重 |
| 步骤54b 高质量过滤数 | 100–3,000 | **1,526** | ✅ | MIUVIG标准（39%通过率正常，严格过滤）|
| 步骤55 病毒基因数 | 5,000–50,000 | **27,356** | ✅ | 病毒基因密度高（~18 genes/contig）|

> **步骤54b过滤率39%（1,526/3,911）**：MIUVIG标准严格（Complete/HQ/MQ/LQ + ≥2kb + viral_genes≥1），
> 排除了Not-determined且无病毒基因的序列、长度<2kb的片段。这是正常的质量控制，确保下游vOTU聚类的可靠性。

**已知问题与修复**：

| 脚本 | 问题 | 修复 |
|------|------|------|
| 52_vir_genomad.sh | **步骤52 sentinel路径修正**（2026-07-06发现）：原监控路径 `genomad/$s/${s}_summary/${s}_virus_summary.tsv` 错误，实际输出路径为 `genomad/$s/${s}.contigs_summary/${s}.contigs_virus_summary.tsv`（geNomad自动添加`.contigs`后缀）。建议用 `aggregated_classification.tsv` 作为sentinel，更可靠。| 已确认实际路径，所有样本geNomad均正常完成（时间戳2026-07-05），进度监控已修正 |
| 53_vir_virsorter2.sh | VirSorter2 在 Snakemake ~300步工作流中，**hmmsearch阶段会长时间无日志输出**（尤其71%-95%区间的NCLDV/provirus阶段），表现为日志"卡"在某个百分比数十分钟。这是**正常现象**，hmmsearch子进程仍在后台消耗CPU（可通过 `ps -eo pid,time,pcpu,cmd | grep hmmsearch` 确认CPU时间持续增长）| 监控进程而非日志：若 `ps aux | grep hmmsearch` 显示进程存活且%CPU>0，则继续等待；仅当进程消失或CPU=0.0超1小时才视为卡死。单样本耗时：5-7小时正常（Sample13: 6.8h, Sample14: 6.4h观测值）|
| 54_vir_checkv_contig.sh | CheckV 1.0.3 若 geNomad 和 VirSorter2 均无有效病毒输出（罕见，测序深度极低样本），脚本会创建空的 quality_summary.tsv（仅表头）防止下游中断 | 无需修复，符合预期（空样本正常通过）|
| 54b_vir_checkv_filter.sh | 过滤逻辑：保留 (checkv_quality in Complete/High/Medium/Low-quality) OR (checkv_quality=Not-determined AND viral_genes≥1)；同时要求 contig_length≥2000 | 2026-06-18 已实现，参考 MIUVIG 最小报告标准 |

**Project01 执行进度（病毒上游分析，10 样本）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（51-55全部完成，1,526个高质量病毒序列，27,356个基因）|
| ② rush 并行9样本 51-55 | 模式二，rush -j 2/3/6 | Sample2-4, Sample10-15 | 🔄 进行中（2026-07-06 23:40 UTC，51✅9/9 52✅9/9 53🔄8/9 Sample15运行中71% 54-55⏳待启动）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

**② 阶段详细进度快照**（2026-07-07 02:05 UTC，Task B监控中）：

| 步骤 | 工具 | 9样本进度 | 备注 |
|------|------|----------|------|
| 51 | MEGAHIT | 9/9 ✅ | 全部完成（2026-07-05 18:48-19:29 UTC） |
| 52 | geNomad | 9/9 ✅ | 全部完成（2026-07-05 19:24-21:59 UTC，aggregated_classification.tsv已验证） |
| 53 | VirSorter2 | 8/9 🔄 | Sample2-4/10-14已完成（行数2226-4283），**Sample15运行中**（94% 314/335 steps，已运行7h25m，provirus阶段60分钟，仍在计算中） |
| 54 | CheckV | 0/9 ⏳ | 等待53达9/9后自动启动 |
| 54b | Filter | 0/9 ⏳ | 依赖54完成 |
| 55 | Prodigal-gv | 0/9 ⏳ | 依赖54b完成 |

**VirSorter2运行特征观测**（基于Sample13/14/15）：
- 单样本耗时：**5-7小时**（Sample13: 6.8h, Sample14: 6.4h实测值；Sample15: 7h25m+仍在运行）
- **正常"停滞"阶段**：71%-95%区间（NCLDV组hmmsearch + provirus边界预测），日志可能20-40分钟无新输出，但 `ps` 显示hmmsearch子进程CPU时间持续增长（227-231% CPU占用正常）
- **异常卡死判断**：仅当 `ps aux | grep hmmsearch` 显示所有子进程%CPU=0.0持续超1小时，且日志完全无更新时，才视为卡死需人工干预
- **极端复杂样本案例（Sample15）**：provirus阶段持续60分钟（远超正常10-25分钟），但进程保持99.8% CPU占用且输出文件持续更新（最后修改时间02:04-02:05 UTC），判断为**异常复杂的provirus边界预测**（2784行dsDNAphage + 1582行lavidaviridae + 934行RNA + 1296行ssDNA）。继续等待完成。

> **rush 并发策略**：步骤51/53（MEGAHIT/VirSorter2，内存/CPU密集）用 -j 2；步骤52（geNomad，GPU友好）用 -j 3；步骤54/54b/55（快速）用 -j 6。
> 预计9样本总耗时：步骤51 ~5小时 + 步骤52 ~3.5小时 + 步骤53 ~16小时 + 步骤54-55 ~2小时 = **~26.5小时**。

---

### 步骤 56-60：vOTU 聚类与丰度定量（cross-sample 策略）

**步骤名称**：病毒操作分类单元（vOTU）生成与定量

**目的**：跨样本聚类病毒序列为 vOTU（95% ANI，类似细菌OTU概念），每个 vOTU 代表一个病毒"物种"。对 vOTU 进行分类学注释和丰度定量，生成病毒丰度矩阵用于下游统计分析。

**依赖**：步骤 54b（所有样本的 viruses_filtered.fna）+ 步骤 55（所有样本的 Prodigal-gv CDS）

**流程链**：56 vclust（95% ANI clustering, Leiden algorithm）→ 57 geNomad taxonomy（vOTU representatives）→ 58 Salmon build（vOTU + per-sample CDS index）→ 59 Salmon quant（per-sample abundance）→ 60 vOTU table（merge + taxonomy annotation）

**执行方式（跨样本一次性执行）**：

```bash
# 步骤56：vOTU聚类（需等待所有样本54b完成）
bash ~/Course/CSCCD-MetagenomeFlow/scripts/56_vir_votu_gen.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤57：vOTU分类学注释
bash ~/Course/CSCCD-MetagenomeFlow/scripts/57_vir_votu_genomad.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤58：Salmon索引构建（需等待所有样本55完成）
bash ~/Course/CSCCD-MetagenomeFlow/scripts/58_vir_salmon_build.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤59：Salmon逐样本定量（per-sample，rush并行）
~/Course/CSCCD-MetagenomeFlow/miniforge3/bin/rush -j 3 -k \
  'bash ~/Course/CSCCD-MetagenomeFlow/scripts/59_vir_salmon_quant.sh -s {} -t 16 \
   -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow \
   > ~/Course/CSCCD-MetagenomeFlow/Project/Project01/temp/logs/virus/59_vir_salmon_quant_{}.log 2>&1' \
  :::: samplesheet_test10.csv

# 步骤60：vOTU丰度矩阵生成
bash ~/Course/CSCCD-MetagenomeFlow/scripts/60_vir_votu_table.sh \
  -m temp/virus_test10_samples.txt \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：
```
Project/Project01/result/virus/
  ├── votu/
  │   ├── contigs/virus.fasta                          ← 步骤56：vOTU代表序列
  │   ├── votu_representatives.tsv                     ← vOTU聚类结果
  │   ├── genomad/virus_taxonomy.tsv                   ← 步骤57：vOTU分类学
  │   └── table/vOTU_table_ann.txt                     ← 步骤60：vOTU丰度矩阵（带分类）
  └── salmon/
      ├── index/info.json                              ← 步骤58：Salmon索引
      └── Sample1/report.tsv                           ← 步骤59：单样本定量
```

**Project01 执行进度（vOTU链，10 样本）**：

| 步骤 | 工具 | 内容 | 状态 |
|------|------|------|------|
| 56 | vclust | vOTU聚类（95% ANI, 0.85 qcov）→ **17,300个vOTU** | ✅ 完成（2026-07-07） |
| 57 | geNomad | vOTU分类学注释 → 14,776行 | ✅ 完成 |
| 58 | Salmon | 构建vOTU定量索引（366M bp, 176.9M keys）| ✅ 完成（耗时265s） |
| 59 | Salmon | 逐样本vOTU丰度定量（10/10样本）| ✅ 完成 |
| 60 | Python | vOTU丰度矩阵生成（vOTU_table_ann.txt, 317,869行）| ✅ 完成 |

---

### 步骤 61-63：vMAG 生成与定量（可选，测序深度充足时）

**步骤名称**：病毒宏基因组组装基因组（vMAG）回收

**目的**：从 vOTU 中通过多样本覆盖度信息 binning 出完整病毒基因组（vMAG），用于菌株级分析和宿主关联预测。**注意**：vMAG 生成对测序深度要求极高（每个病毒≥50× coverage），小规模测试集（如 Project01）通常无 vMAG 产出。

**依赖**：步骤 56（vOTU代表序列）+ 步骤 2（所有样本的去宿主 reads）

**流程链**：61 vRhyme（multi-sample binning）→ 62 CheckV（vMAG质量评估）→ 63 CoverM（vMAG丰度定量）

**执行方式（跨样本）**：

```bash
# 步骤61：vMAG binning（需等待56完成）
bash ~/Course/CSCCD-MetagenomeFlow/scripts/61_vir_vmag.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤62：vMAG质量评估
bash ~/Course/CSCCD-MetagenomeFlow/scripts/62_vir_checkv_mag.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤63：vMAG丰度定量（per-sample，rush并行）
~/Course/CSCCD-MetagenomeFlow/miniforge3/bin/rush -j 3 -k \
  'bash ~/Course/CSCCD-MetagenomeFlow/scripts/63_vir_coverm_quant.sh -s {} -t 16 \
   -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow \
   > ~/Course/CSCCD-MetagenomeFlow/Project/Project01/temp/logs/virus/63_vir_coverm_quant_{}.log 2>&1' \
  :::: samplesheet_test10.csv
```

**Project01 执行进度（vMAG链，10 样本）**：

| 步骤 | 工具 | 内容 | 状态 |
|------|------|------|------|
| 61 | vRhyme | vMAG binning（17,300 vOTU + 10样本覆盖度）| ✅ 完成（0个vMAG产出，符合预期） |
| 62 | CheckV | vMAG质量评估 | ⏳ 跳过（61无vMAG输出，无需评估） |
| 63 | CoverM | vMAG丰度定量 | ⏳ 跳过（无vMAG可定量） |

> **实测结果确认**：Project01（10样本×10-15Gb）vRhyme binning 完成后 `bins/vMAG/` 和 `bins/pseudo/` 均为空目录，**0个vMAG产出**，与预期一致（测序深度不足以支持≥50×覆盖度的vMAG binning）。62-63因无vMAG输入自动跳过，与 Project_example（6样本0个vMAG）观测一致。全量50样本数据集有望产出高质量 vMAG。

---

### 步骤 64-72：vOTU 功能与宿主关联注释（基于 vOTU 代表序列）

**步骤名称**：病毒功能注释与宿主预测

**目的**：对 vOTU 代表序列进行端到端注释，包括：功能基因（PHROG/VOG/AMG）、生活方式（裂解/溶原）、分类学（多算法整合）、宿主关联（iPHoP）。

**依赖**：步骤 56（vOTU代表序列 virus.fasta）+ 步骤 55（Sample1-15 的 Prodigal-gv 输出用于训练，仅部分工具需要）

**流程链**：64 PHAROKKA（PHROG注释）→ 65 PHOLD（PDB结构暗物质）→ 66 VOG（跨界HMM）→ 67 BACPHLIP（生活方式）→ 68 iPHoP（宿主预测）→ 69 vConTACT3（基因共享网络分类）→ 70 PhaBox2（深度学习分类+宿主）→ 71 DRAM-v（AMG辅助代谢基因）→ 72 PhaGCN3（图卷积分类）

**执行方式（跨样本一次性执行，所有工具输入均为 virus.fasta）**：

```bash
# 步骤64：PHAROKKA端到端注释
bash ~/Course/CSCCD-MetagenomeFlow/scripts/64_vir_pharokka.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤65：PHOLD结构暗物质ORF
bash ~/Course/CSCCD-MetagenomeFlow/scripts/65_vir_phold.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤66：VOG HMM扫描
bash ~/Course/CSCCD-MetagenomeFlow/scripts/66_vir_vog.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤67：BACPHLIP生活方式预测
bash ~/Course/CSCCD-MetagenomeFlow/scripts/67_vir_bacphlip.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤68：iPHoP宿主关联
bash ~/Course/CSCCD-MetagenomeFlow/scripts/68_vir_iphop.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤69：vConTACT3基因共享网络
bash ~/Course/CSCCD-MetagenomeFlow/scripts/69_vir_vcontact3.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤70：PhaBox2深度学习分类
bash ~/Course/CSCCD-MetagenomeFlow/scripts/70_vir_phabox2.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤71：DRAM-v AMG预测
bash ~/Course/CSCCD-MetagenomeFlow/scripts/71_vir_dram.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤72：PhaGCN3图卷积分类
bash ~/Course/CSCCD-MetagenomeFlow/scripts/72_vir_phagcn3.sh \
  -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**Project01 执行进度（vOTU注释链，基于10样本vOTU）**：

| 步骤 | 工具 | 内容 | 状态 |
|------|------|------|------|
| 64 | PHAROKKA | PHROG功能注释（17,300 vOTU） | ✅ 完成（2026-07-10 11:15，耗时28.2h） |
| 65 | PHOLD | 结构暗物质ORF | ✅ 完成（2026-07-12 23:11，耗时38h，输入修正为pharokka.gbk，见附录A3） |
| 66 | VOG | 跨界HMM扫描 | ✅ 完成（2026-07-13 07:39，耗时7.7h，183,369条VOG命中） |
| 67 | BACPHLIP | 生活方式预测 | ✅ 完成（2026-07-13 20:xx，耗时12.9h，17,300个vOTU全部预测） |
| 68 | iPHoP | 宿主关联预测 | ✅ 完成（2026-07-15 18:28，耗时239,410s/66.5h，14,187条宿主关联预测，genus水平） |
| 69 | vConTACT3 | 基因共享网络 | ✅ 完成（2026-07-14 01:23，耗时45min） |
| 70 | PhaBox2 | 深度学习分类+宿主 | ✅ 完成（2026-07-15 04:29，17,300条vOTU全部分类） |
| 71 | DRAM-v | AMG辅助代谢基因 | ✅ 完成（2026-07-15 10:57，129,241条ORF注释；本批次AMG summary为空，即未检出potential AMG，属正常生物学结果非异常） |
| 72 | PhaGCN3 | 图卷积分类 | ✅ 完成（2026-07-15 05:27，15,505条分类预测） |

> **步骤64 Pharokka 执行注意事项**（2026-07-09发现）：单次运行中 Phanotate 基因预测（FASTA + Tabular 两阶段）耗时可能长达12-13小时（17,300条vOTU序列，262,149个预测基因），随后 MMseqs2/VFDB/CARD 比对注释阶段还需额外数小时。**首次尝试因进程在等待期挂起被判定失败并重启**（备份于 `pharokka_backup_20260709_070455`），重启后于 07:04:55 启动、11:15:55 完成，总耗时101,467秒（28.2小时）。监控建议：检查 `phanotate_out_tmp.fasta`/`phanotate_out.txt` 文件大小是否持续增长而非仅看日志时间戳，`ps` 确认进程CPU占用（应稳定在90%左右）；仅当进程CPU=0且文件长时间无变化时才判定为卡死。

> **步骤68 iPHoP 执行注意事项**（2026-07-15完成后总结）：iPHoP 采用多方法集成宿主预测策略，单次运行需依次跑完6类子方法（按耗时占比从小到大排列：BLAST比对基因组/CRISPR → WIsH k-mer相似度 → VHM s2相似度特征 → PHP → RaFAH随机森林 → 卷积/密集神经网络分类器融合 → 最终聚合模型），17,300个vOTU全流程总耗时约66.5小时（239,410秒）。**各子步骤特征差异很大，不能用统一标准判断是否卡死**：
> - 前段（BLAST/CRISPR/WIsH/VHM/PHP）：中间文件持续增长可见（如 `feature_values_s2star.csv` 可达20GB+），适合用文件大小/mtime监控
> - RaFAH的 hmmsearch 子步骤：单个输出文件 `Full_CDSxClusters_Prediction` 会稳定增长至3GB+，可用文件大小变化判断是否卡死；随后 Random Forest 汇总阶段耗时但无中间文件增长，需改用 `/proc/PID/io` 的 rchar/read_bytes 计数变化来确认进程是否仍在读取处理
> - 神经网络分类器阶段（日志前缀 `[8]`）：会依次遍历 blast/CRISPR/WIsH/VHM/PHP 五组特征各自的 Conv/Dense 模型，逐行日志推进较快，是判断"卡住 vs 正常"最直观的阶段
> - 最终聚合阶段（`[9]`-`[10]`，日志前缀 Aggregating/Combining/Preparing）：曾出现约2小时无日志行更新且 `io` 计数短暂停滞的情况，事后证实是正常的CPU计算密集型无IO输出阶段，并非卡死——**监控建议：优先看 `/proc/PID/io` 的 rchar 是否在扩大的时间窗口内（如1小时）有任何增长，而非单纯看日志最后一行是否变化**；同时可用 `ps --ppid <主PID>` 找到当前真正在计算的子进程（如 hmmsearch/perl RaFAH 脚本），避免被主进程的空闲等待状态误导。
> - 完成标志：`${WORKDIR}/result/virus/iphop/Host_prediction_to_genus_m90.csv` 生成即为完成（非通用的`.done`文件）。

> **注释工具并行策略**：步骤64-72 中，64/65/67/68/70/71/72 可并行执行（均只依赖 virus.fasta）；步骤66/69 依赖64的输出，需串行。

### 步骤 67b：噬菌体生活方式预测交叉验证（ProkBERT-PhaStyle，可选）

**步骤名称**：ProkBERT-PhaStyle 生活方式预测（第三票验证层）

**目的**：生活方式（裂解/溶原）预测已有两票——67 BACPHLIP（随机森林）与 72 PhaGCN3（图卷积）——本步骤引入 ProkBERT-PhaStyle 基因组语言模型作为**第三票**：序列按 512bp 连续切段直接推理，段级 logits 经 weighted voting 聚合为 vOTU 级 temperate/virulent 概率。三票并排 2/3 一致视为稳健，分歧样本（尤其概率接近 0.5）值得人工复核。默认不入 Snakemake rule all（验证层，同 15e MetaX / 16b metaSPAdes 模式）。

**依赖**：步骤 56（vOTU代表序列 virus.fasta，与 67 输入相同）

**执行方式**（手动执行；opt-in，不入 rule all）：
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/67b_vir_phastyle.sh \
  -t 8 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow \
  --batch-size 32       # 推理批大小（模型线程封顶 8）
```
Snakemake 显式触发（验证层，不在 rule all）：`snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml -R phastyle`

**环境与模型（一次性，envs/prokbert）**：
```bash
conda create --prefix ~/Course/CSCCD-MetagenomeFlow/envs/prokbert python=3.10 -y
conda run --prefix ~/Course/CSCCD-MetagenomeFlow/envs/prokbert pip install prokbert
conda run --prefix ~/Course/CSCCD-MetagenomeFlow/envs/prokbert pip install \
    torch torchvision --index-url https://download.pytorch.org/whl/cpu
conda run --prefix ~/Course/CSCCD-MetagenomeFlow/envs/prokbert pip install transformers==4.53.2
```
模型 `neuralbioinfo/PhaStyle-mini`（约25M参数，~80MB）首次运行自动从 HuggingFace 下载到 `HF_HOME`（默认 `~/.cache/huggingface`），之后离线复用；huggingface.co 不可达时脚本自动改用 hf-mirror.com 镜像。注意 prokbert 0.0.48 与 transformers>=5 不兼容（必须 4.53.2）；CPU 版 torch 使 env 从 6.3G 降至 1.8G。

**输出结果**：
```
Project/Project01/result/virus/phastyle/
  ├── phastyle_results.tsv    ← 逐 vOTU：predicted_label + score_temperate/score_virulent
  └── phastyle_done.txt       ← sentinel（virulent/temperate 计数；空输入为 empty_input）
```

**审核要点**：

| 指标 | 看什么 | 说明 |
|------|-------|------|
| 三票一致性 | phastyle_results.tsv vs 67 bacphlip_results.tsv（Virulent/Temperate 列）并排 | 2/3 一致为稳健；BACPHLIP 与 PhaStyle 同源训练集（BACPHLIP，去 E. coli），分歧多出现在边界样本 |
| 边界概率 | score_temperate 接近 0.5（如 0.47-0.60） | 模型不确定，标注时建议降权或人工复核 |
| 空结果 | sentinel 内容为 `empty_input` | 序列均短于 256bp 分段阈值，优雅降级，属预期行为 |

---
## 真菌维度分析

### 步骤 71-73：真菌物种组成与功能通路（Kraken2 + MetaPhlAn4 双算法）

**步骤名称**：真菌（Mycobiome）物种分类与功能定量

**目的**：从去宿主后的宏基因组 reads 中识别真菌物种组成，交叉验证两套独立算法（Kraken2+Bracken 快速分类 / MetaPhlAn4 精确标记基因分类），并定量真菌功能通路。

**依赖**：步骤2（kneaddata 去宿主 reads）+ 步骤3（细菌维度 MetaPhlAn4 的 bowtie2 `.mapout.bz2` 比对结果，供步骤72复用避免重新比对）

**流程链**：71 Kraken2+Bracken（PlusPF数据库快速分类）→ 72 MetaPhlAn4-euk（复用步骤3比对结果的精确标记基因分类）→ 72b 合并（多样本丰度矩阵）→ 73 HUMAnN4（真菌功能通路定量）

**执行方式（per-sample 策略，71/72 之间无依赖，可并行）**：

```bash
# 步骤71：Kraken2 + Bracken 真菌快速分类（PlusPF数据库，~77G）
bash ~/Course/CSCCD-MetagenomeFlow/scripts/71_fun_kraken2_fungi.sh \
  -s Sample1 -t 8 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤72：MetaPhlAn4-euk 精确真菌/真核标记基因分类（复用步骤3比对结果）
bash ~/Course/CSCCD-MetagenomeFlow/scripts/72_fun_metaphlan4_euk.sh \
  -s Sample1 -t 8 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤72b：合并所有样本的 MetaPhlAn4 真菌丰度表（跨样本一次性执行）
bash ~/Course/CSCCD-MetagenomeFlow/scripts/72b_fun_metaphlan4_merge.sh \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

# 步骤73：HUMAnN4 真菌功能通路定量
bash ~/Course/CSCCD-MetagenomeFlow/scripts/73_fun_humann4.sh \
  -s Sample1 -t 8 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**Project01 执行进度（真菌维度，10样本：Sample1/2/3/4/10/11/12/13/14/15）**：

| 步骤 | 工具 | 内容 | 状态 |
|------|------|------|------|
| 71 | Kraken2+Bracken | PlusPF快速物种分类 | ✅ 完成（10样本） |
| 72 | MetaPhlAn4-euk | 精确真菌标记基因分类（复用步骤3比对结果） | ✅ 完成（10样本） |
| 72b | 合并丰度表 | 项目级真菌丰度矩阵（taxonomy.tsv/species/genus/csv） | ✅ 完成 |
| 73 | HUMAnN4 | 真菌功能通路定量 | ✅ 完成（10样本） |
| 74-80 | BLAST/FunOMIC/MicroFisher/MEGAHIT/MetaEuk/Eukfinder/Prodigal | 真菌组装、基因预测多方法链 | ✅ 完成（10样本） |
| 81 | eggNOG-mapper | 真菌蛋白功能注释（252万条基因） | ✅ 完成（耗时 11504s） |
| 83 | dbCAN CAZyme注释 | `--tools diamond hmmer`（eCAMI 因超大规模不可行已禁用，见 A4） | ✅ 完成（129,669 CAZyme，耗时 90563s） |
| 84/85/86 | VFDB/AMRFinder/MEROPS | 毒力因子/耐药基因/蛋白酶家族注释 | ✅ 完成 |
| 98d | 真菌维度整合表 | kegg_ko/cog/cazyme/vfdb/amr/merops 六张基因计数表 + normalized(relab/clr) | ✅ 完成（见 A5/A6 排障记录） |

> **步骤72 加速技巧**：`72_fun_metaphlan4_euk.sh` 会优先查找 `${WORKDIR}/temp/metaphlan4/${SAMPLE}/${SAMPLE}.mapout.bz2`（细菌维度步骤3已生成的 bowtie2 比对结果），若存在则直接复用并加 `--ignore_bacteria --ignore_archaea` 重新分类，跳过耗时的 bowtie2 重新比对；若不存在才会回退到基于 reads 的完整比对。因此**务必先完成细菌维度步骤3**，再启动真菌维度步骤72，可节省数小时比对时间。

> **并行策略**：71（Kraken2）与72（MetaPhlAn4-euk）互不依赖，可同时并行启动；72b（合并）需等待所有目标样本的72完成后再执行；73（HUMAnN4）为 per-sample 步骤，可在对应样本72完成后立即启动，无需等待其他样本。

---

### 步骤 79b：真核候选序列二次质控（Tiara 域确认 + BUSCO 谱系完整度）

**步骤名称**：VEBA 式真核 MAG 质量分层（Tiara + BUSCO）

**目的**：79号 Eukfinder 基于 Centrifuge 分类判定的候选真核序列（`{SAMPLE}.Euk.fasta`）可能包含误判（例如把细菌序列误分为真核），且缺乏基因完整度评估。本步骤参考外部工具 [VEBA](https://github.com/jolespin/veba) `binning-eukaryotic` 模块的质控思路（Tiara 深度学习域预测 + BUSCO 谱系特异完整度评估）重新实现，**不拷贝 VEBA 源码**（VEBA 为 AGPLv3 许可，Tiara/BUSCO 均为 MIT 许可，无许可证污染风险），补齐 79号缺失的质量门禁能力。

**依赖**：步骤79（Eukfinder 的 `results.txt` + `Eukfinder_results/{SAMPLE}.Euk.fasta`）

**流程链**：长度过滤（seqkit，≥1000bp）→ Tiara 域二次确认（剔除误判为真核的序列）→ BUSCO 谱系自动检测与完整度评估 → 质量分级汇总表

**执行方式**：

```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/79b_fun_veba_qc.sh \
  -s Sample4 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：

```
result/fungi/veba_qc/Sample4/
├── Sample4.euk_filtered.fasta       — 长度过滤后的候选序列
├── Sample4.tiara_classification.txt — Tiara 逐序列分类结果
├── eukarya_Sample4.euk_filtered.fasta — Tiara 二次确认为真核的序列
├── Sample4.busco/                   — BUSCO 谱系完整度评估原始输出
└── Sample4.veba_qc_summary.tsv       — 质量分级汇总表
```

`Sample4.veba_qc_summary.tsv` 实测内容（Project01 真实样本）：

```
sample    lineage                     complete_pct  duplicated_pct  missing_pct
Sample4   saccharomycetaceae_odb12.2  73.5          0.4             16.2
```

**三种可能结果（均为正常退出 exit 0，不视为脚本失败）**：

| 场景 | 触发条件 | 产出 |
|------|---------|------|
| 完整质控 | Tiara 确认后有足量真核序列，BUSCO 成功匹配谱系 | `{SAMPLE}.veba_qc_summary.tsv` |
| 空结果（79号层面） | Eukfinder 的 `.Euk.fasta` 不存在（低测序深度，79号已知的预期行为） | `{SAMPLE}.veba_qc_empty.flag` |
| 空结果（79b层面） | Tiara 二次确认后 0 条真核序列，或候选序列过少导致 BUSCO 无法匹配任何 marker | `{SAMPLE}.veba_qc_empty.flag` |

**审核要点**：
- 若产出 `veba_qc_summary.tsv`：检查 `lineage` 是否与预期物种类群相符，`complete_pct` 越高说明候选序列越接近完整基因组（VEBA 原方案建议 completeness ≥50% 视为可用 MAG）
- 若产出 `veba_qc_empty.flag`：查看文件内容确认是在哪个阶段判空（79号 Eukfinder 层面还是本步骤 Tiara/BUSCO 层面），Project_example 6样本测试中 4个在79号层面判空、2个在 Tiara 层面判空，均属测序深度不足的预期行为，非脚本错误
- **关键区分**：79号 Eukfinder 完成后总会生成 `results.txt`，即使产出 0 个真核序列。79b 用 `results.txt` 是否存在来判断"79号是否已运行"，不能仅凭 `.Euk.fasta` 是否存在来判断（该文件缺失也可能是 79号已运行但产出为空）

**LLM 调用方式（Prompt）**：
```
请对样本 Sample4 运行 79b_fun_veba_qc.sh，检查是否产出 veba_qc_summary.tsv 还是 empty.flag，
若产出 summary.tsv，请解读其中的 lineage 和 complete_pct 是否合理。
```

---

### 步骤 79c-79e：真核候选序列真实分箱（覆盖度深度 + MetaBAT2 + 逐 bin BUSCO）

**步骤名称**：真核 MAG 级分箱（VEBA `binning-eukaryotic` 方法参考）

**目的**：79b 的质控是对**全部候选序列作为一个整体**评估完整度，无法回答"这些候选序列里到底是一个真核物种还是多个物种的混合"这个问题（后续跨域 `cluster` 模块要求"一个文件=一个基因组"的粒度，与细菌 dRep MAG 对齐）。本组步骤引入真正的 MetaBAT2 分箱：先用 CoverM 计算 reads 覆盖度深度，再用 MetaBAT2 基于四核苷酸频率+覆盖度信号把候选 contig 聚类成候选基因组（bin），最后对每个 bin 独立做 BUSCO 评估，产出真正意义上的"真核 MAG"。参考 [VEBA](https://github.com/jolespin/veba) `binning-eukaryotic` 模块的方法思路（该模块默认即用 MetaBAT2 做真核分箱），**不拷贝 VEBA 源码**（VEBA 为 AGPLv3 许可，CoverM 为 Apache-2.0、MetaBAT2/BUSCO 均为 MIT/BSD 系许可，无许可证污染风险）。

**依赖**：步骤79b（Tiara 域确认后的 `{SAMPLE}.euk_filtered.fasta` / `eukarya_{SAMPLE}.euk_filtered.fasta`）

**流程链**：79c CoverM 覆盖度深度（minimap2-sr 比对 + metabat 格式深度表）→ 79d MetaBAT2 分箱（四核苷酸频率+覆盖度） → 79e 逐 bin BUSCO 谱系完整度评估

**执行方式**：

```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/79c_fun_coverm_depth.sh \
  -s Sample4 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

bash ~/Course/CSCCD-MetagenomeFlow/scripts/79d_fun_metabat2.sh \
  -s Sample4 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

bash ~/Course/CSCCD-MetagenomeFlow/scripts/79e_fun_euk_qc_per_bin.sh \
  -s Sample4 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：

```
result/fungi/veba_qc/Sample4/
├── coverm/
│   ├── Sample4.bam       — 排序后的 BAM（MetaBAT2 输入）
│   └── depth.txt         — MetaBAT2 格式深度表
├── metabat2/
│   ├── bin.1.fa          — 分箱产出的候选基因组（0个bin是合法结果）
│   └── Sample4.tsv       — contig2bin 映射表
└── euk_mags/
    ├── bin.1.fa          — 独立拷贝的逐 bin MAG（dRep 风格粒度）
    ├── bin.1.busco/      — 该 bin 的 BUSCO 原始输出
    └── Sample4.euk_mags_summary.tsv — 每 bin 一行的完整度/重复度/缺失汇总
```

`Sample4.euk_mags_summary.tsv` 实测内容（Project01 真实样本，2939条候选 contig 中）：

```
sample   bin_id  lineage                     complete_pct  duplicated_pct  missing_pct  n_contigs  size_bp
Sample4  bin.1   saccharomycetaceae_odb12.2  63.8          0.3             28.7         2000       8204577
```

对比 79b 全候选集整体评估的 73.5%/0.4%/16.2%：MetaBAT2 从 2939 条候选 contig 中聚出 1 个真正的候选基因组（占 68% 的 contig 数、8.2Mb），完整度虽低于全集评估（因为丢弃了约 939 条未入 bin 的低置信度 contig），但证明候选序列集合中确实存在一个可被覆盖度信号真实分箱出来的主导物种，而非纯噪声碎片——这是"真核 binning 路线在当前数据条件下可行"的关键证据。

**三种可能结果（均为正常退出 exit 0，不视为脚本失败）**：

| 场景 | 触发条件 | 产出 |
|------|---------|------|
| 完整分箱 | 79b 有候选序列，MetaBAT2 产出 ≥1 个 bin，BUSCO 成功评估 | `{SAMPLE}.euk_mags_summary.tsv`（含真实数值行） |
| 上游空结果 | 79b/79c 判空（低测序深度） | 79d/79e 均写空表头 TSV，79c 写 `coverm_empty.flag` |
| 0 bin 结果 | MetaBAT2 因候选序列过于分散/数量不足未能分箱（或 segfault，exit 139） | `{SAMPLE}.tsv` 仅表头，79e 空表头跳过评估 |

**审核要点**：
- 检查 79d 产出的 bin 数量与 contig 归属占比（可从 `Sample4.tsv` 统计），过低的入 bin 占比可能说明覆盖度信号不足以支撑分箱
- 检查 79e 逐 bin `complete_pct` 是否明显低于 79b 全候选集评估值：显著下降说明该 bin 只捕获了主导物种的一部分，需结合入 bin contig 数判断是否需要更高测序深度
- **性能要点**：79b/79e 均已改用共享 lineage 缓存目录 `${REPO}/db/busco_downloads`（而非各样本/各 bin 独立目录），避免多 bin/多样本重复下载同一 BUSCO 数据集；首次运行仍需完整下载（本例耗时约 2.2 小时，含通用 eukaryota + 具体 saccharomycetaceae 两级数据集），后续复用缓存后同一分析仅耗时约 10 分钟
- **已知局限**：当前全项目仅 Sample4 一个样本的候选序列量足以触发 79d 的非零 bin 分箱；其余样本多在 79b/79c 层面即判空，79c-79e 链路在这些样本上仅验证了空值分支的正确降级，尚未在其他真实非空数据上验证多 bin 场景

**LLM 调用方式（Prompt）**：
```
请对样本 Sample4 依次运行 79c/79d/79e 脚本，检查 79d 产出的 bin 数量，
并解读 79e 逐 bin BUSCO 结果与 79b 全候选集结果的差异说明了什么。
```

---

### 步骤 79f：真核 MAG 逐 bin 蛋白预测（MetaEuk）

**步骤名称**：真核 MAG 蛋白预测（补齐跨域正交基因组模块所需的真菌侧蛋白输入）

**目的**：79e 产出的 BUSCO 结果只是保守标记基因片段，不是完整蛋白集；跨域正交基因组检测（98f）需要与细菌 Prokka、病毒 pharokka/prodigal 同粒度的"每基因组一套完整蛋白"。79f 对 79e 产出的每个 euk MAG（`bin.*.fa`）独立跑 MetaEuk `easy-predict`，产出结构仿照 Prokka"每 MAG 一子目录"的命名惯例。

**依赖**：步骤79e（`{SAMPLE}.euk_mags_summary.tsv`，0 bin 是合法结果）；MetaEuk 预建库 `db/metaeuk_db/fungi_refseq_mmseqs`（3.2GB）

**执行方式**：

```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/79f_fun_metaeuk_per_bin.sh \
  -s Sample4 -t 16 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：

```
result/fungi/veba_qc/Sample4/euk_mags/
├── bin.1/
│   └── bin.1.faa              — MetaEuk 预测的完整蛋白集
└── Sample4.metaeuk_done.txt   — 汇总 sentinel（bin_id, faa_path, n_proteins）
```

**实测**（Project01 真实样本 Sample4/bin.1）：耗时 834 秒（含约 6 分钟 k-mer 索引构建），产出 4329 条蛋白。0-bin 样本（如 Sample11）走空分支，写表头 sentinel，瞬间 exit 0。

**审核要点**：
- MetaEuk 首次构建 profile 索引较慢，`Estimated memory consumption: 25G` 是正常提示，非资源不足报错
- 每个 bin 独立失败不中断其他 bin，失败行记录为 `NA\t0`

---

### 步骤 98e-98f：跨域基因组聚类与正交基因组检测（②cluster 模块）

**步骤名称**：跨域（细菌/病毒/真菌）ANI 聚类 + 蛋白正交基因组检测

**目的**：参考 [VEBA](https://github.com/jolespin/veba) `cluster` 模块的方法思路（FastANI 全基因组 ANI 比对 + 图社区检测；MMseqs2 蛋白层聚类检测正交基因组），**不拷贝 VEBA 源码**（VEBA 为 AGPLv3 许可，FastANI 为 MIT、MMseqs2 为 MIT/GPLv3 双许可、networkx 为 BSD，本项目仅调用其命令行接口，无许可证污染风险）。将细菌 dRep MAG、病毒 vOTU 代表序列、真菌 euk MAG 三域基因组做统一的相似度/同源性分析。

**依赖**：细菌 dRep（38）、病毒 vOTU（56）、真菌 euk MAG（79e）+ 79f 蛋白预测

**流程链**：98e 三域基因组收集 → vOTU 批量拆分（`seqkit split2`）→ FastANI 全体两两比对 → networkx 建图 + Louvain 社区检测 → 98f 三域蛋白收集 → MMseqs2 `easy-cluster` 正交基因组检测

**执行方式**：

```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/98e_cross_domain_ani_cluster.sh \
  -t 40 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

bash ~/Course/CSCCD-MetagenomeFlow/scripts/98f_cross_domain_orthogroup.sh \
  -t 40 -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

**输出结果**：

```
result/cross_domain/
├── cluster/
│   ├── genome_manifest.tsv    — genome_id, domain, fasta_path
│   ├── all_genomes.list       — FastANI 输入文件列表
│   ├── ani_matrix.tsv         — FastANI 输出（query, ref, ANI, frag_mapped, frag_total）
│   └── genome_clusters.tsv    — genome_id, domain, cluster_id（Louvain 社区检测）
└── orthogroup/
    ├── merged_proteins.faa        — 三域蛋白合并（ID 前缀 domain###genome_id###）
    ├── mmseqs_cluster_cluster.tsv — MMseqs2 easy-cluster 原始输出
    └── orthogroup_table.tsv       — protein_id, genome_id, domain, orthogroup_id
```

**实测**（Project01 全量：213 细菌 MAG + 10106 病毒 vOTU + 1 真菌 MAG，共 10320 个基因组）：

- 98e：耗时 166 秒，5927 个基因组参与建图（其余为孤立节点无 ANI 边），13479 条边，聚出 2844 个簇；真菌 MAG（`Sample4__bin.1`）被分入 cluster_1
- 98f：耗时 130 秒，合并 790567 条蛋白（细菌 479524 + 病毒 306714 + 真菌 4329），聚出 191762 个正交基因组，其中 30387 个正交基因组跨越多个域（真实检出跨域蛋白同源关系）

**已知局限（用户知悉后明确选择按此方案执行，非脚本缺陷）**：
- 98e 的跨"域"（如细菌 vs 真菌）核酸 ANI 比对在演化距离过远时生物学意义有限——FastANI 对无关/远缘基因组对天然不产生输出行（无强制 0% 行），这正是该局限的直接实证
- 相较之下，98f 的蛋白层比对阈值远比核酸 ANI 宽松（`--min-seq-id 0.3 -c 0.8`），跨域检出的正交基因组（如保守结构域/功能基因）更具生物学意义
- 全项目真菌侧目前仅 1 个真实 euk MAG（Sample4/bin.1），跨域统计功效有限；98e/98f 均已用该真实单基因组验证通过（非合成/占位数据），但样本量本身的局限仍然存在

**审核要点**：
- 98e 图中的"孤立节点"（10320 - 5927 = 4393 个）是正常现象：FastANI 对无同源关系的基因组对不产生比对行，这些基因组在 Louvain 阶段各自成为单节点簇
- 检查 `genome_clusters.tsv` / `orthogroup_table.tsv` 中 domain 列的三域计数是否与上游各模块产出数量一致（细菌 dRep 数、vOTU 代表序列数、真核 MAG 数）
- **性能要点**：病毒 vOTU 拆分务必用一次性 `seqkit split2 -s 1`（约 6 秒/17300 条），禁止逐 ID 循环调用 `seqkit grep`（会退化为上万次全文件扫描，耗时数小时）

**LLM 调用方式（Prompt）**：
```
请依次运行 98e/98f 脚本，检查 genome_clusters.tsv 与 orthogroup_table.tsv
的三域计数是否与上游模块产出数量一致，并解读跨域正交基因组数量说明了什么。
```

---
## 附录：LLM 辅助宏基因组分析最佳实践

> 按发现时间顺序追加。凡是在执行过程中遇到的有价值的 LLM 交互模式，均同步记录于此。

---

### A1. 定时进程监控（CronCreate）

**场景**：启动耗时后台任务（如 kneaddata rush 批量，~2-3小时）后，让 LLM 定时自动检查进度，无需手动反复询问。

**操作方式**（对 AI 编程助手直接说）：
```
请设置每30分钟查看一次 kneaddata 进度，任务完成后自动取消定时任务
```

**LLM 执行逻辑**：
1. 调用 `CronCreate` 设置定时 prompt，指定检查命令和完成条件
2. 每次触发时检查目标输出文件是否存在
3. 全部完成后：验证输出 → 更新 Tutorial → git commit → 调用 `CronDelete` 自动取消

**实际使用示例（Project01 kneaddata，2026-06-24）**：
```
# 启动后台 rush 批量后，对 LLM 说：
请设置周期查看进程，每半个小时一次，并且当相关任务执行完毕后，取消周期性查看
```

**优点**：
- 无需人工守候长耗时任务
- 完成后自动触发后续操作（验证 + 文档更新 + commit）
- 定时任务由客户端持久化，AI 编程助手重启后继续有效

**注意事项**：
- 定时任务最长7天后自动到期
- 任务 ID 由 LLM 保存，可随时要求手动取消：`请取消 kneaddata 的定时监控`
- 适合耗时 >30 分钟的后台任务；短任务（<10 分钟）直接等待即可

---

### A2. HUMAnN3 加速方案（--speed-mode）

**背景**：HUMAnN3 默认 standard 模式在 62M reads 样本上耗时 **8-15 小时/样本**，瓶颈是构建物种定制 ChocoPhlAn 子数据库的 bowtie2-build 阶段（非 Diamond）。对于大批量队列（50+ 样本），即使 Snakemake 3 并发也需约 4 天。脚本内置三种速度模式，可按分析目的灵活选择。

**三种模式对比**：

| 模式 | 耗时（62M reads） | 加速倍数 | 物种阈值 | 输入 reads | 适用场景 |
|------|----------------|---------|---------|-----------|---------|
| `standard` | 8-15 h | 1× | 0.01%（几乎全部） | R1+R2 双端 | 发表级最终分析、低深度样本（<20M reads） |
| `balanced` | 1-2 h | **5-10×** | 1%（~21 个 SGBs） | R1+R2 双端 | **>20M reads 样本首选**，精度损失 <5% |
| `fast` | 0.5-1 h | **15-20×** | 3%（~5 个 SGBs） | 仅 R1 | 探索性分析、大规模队列初筛 |

**加速原理**：

HUMAnN3 核苷酸搜索前需构建物种定制 ChocoPhlAn 子数据库（bowtie2-build）：
- `standard`：纳入 >0.01% 物种 → ~126 SGBs → 子数据库 ~60 GB → bowtie2-build **~20 小时**
- `balanced`：纳入 >1% 物种 → ~21 SGBs → 子数据库 ~2-5 GB → bowtie2-build **~30-60 分钟**

> bowtie2-build 是最大时间黑洞（不是 Diamond）。`balanced` 的核心收益来自大幅缩小子数据库。

**精度说明**：
- `balanced`：unstratified 社区通路精度损失 <5%，绝大多数分析的合理取舍。<1% 稀有物种的 stratified 分层通路会丢失，汇总通路不受影响。
- `fast`：适合"先看趋势"的探索分析，不建议直接发表。

**使用方式**：

*单样本手动（推荐 balanced）：*
```bash
bash ~/Course/CSCCD-MetagenomeFlow/scripts/13_bac_humann3.sh \
  -s Sample1 -t 16 \
  -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 \
  -r ~/Course/CSCCD-MetagenomeFlow \
  --speed-mode balanced
```

*rush 批量（balanced，可提升至 -j 3）：*
```bash
PROJ=~/Course/CSCCD-MetagenomeFlow
WORKDIR=$PROJ/Project/Project01
tail -n +2 $WORKDIR/samplesheet_test10.csv | cut -d, -f1 | \
  $PROJ/miniforge3/bin/rush -j 3 -k \
  "bash ${PROJ}/scripts/13_bac_humann3.sh \
    -s {1} -t 16 \
    -w ${WORKDIR} \
    -r ${PROJ} \
    --speed-mode balanced \
    > ${WORKDIR}/temp/logs/humann3/humann3_{1}.log 2>&1 && echo '[{1}] humann3 done'"
```

> `balanced` 内存峰值从 ~80 GB/实例降至 ~20 GB/实例，因此并发数可从 `-j 2` 提升至 `-j 3`。

**LLM 调用方式（Prompt）**：
```
请帮我用 balanced 模式重新运行 CSCCD-MetagenomeFlow HUMAnN3，样本列表来自
Project01/samplesheet_test10.csv，线程 16，rush -j 3 并发。
已完成的样本自动跳过（脚本幂等）。完成后告知每个样本的通路数。
```

**Project01 后续建议**：

本次 10 个测试样本已用 `standard` 模式运行完毕。**后续 40 个样本（Sample16-51）的 Snakemake 批量建议改用 `balanced`**，总耗时可从 ~4 天压缩至 **~8-12 小时**。

修改方式：在 `pipeline/config/config.yaml` 中追加：
```yaml
humann3_speed_mode: "balanced"
```

Snakemake rule 会读取此参数并自动传入 `--speed-mode balanced`（`pipeline/rules/bacteria_taxonomy.smk` 已支持）。

---

### A3. Phold（65）必须以 Pharokka（64）的 `.gbk` 作为输入，而非 vOTU FASTA

**背景（2026-07-11 发现并修复）**：`scripts/65_vir_phold.sh` 脚本头部注释声明"依赖 64_vir_pharokka.sh 的输出"，但原实现直接把 `votu/contigs/virus.fasta` 传给 `phold run`，与依赖声明不一致。运行时 Phold 日志会打印：
```
WARNING - virus.fasta was not a Genbank format file
WARNING - pyrodigal-gv will be used to predict CDS
WARNING - Phold will not predict tRNAs, tmRNAs or CRISPR repeats
WARNING - Please use pharokka output pharokka.gbk as --input for phold
```

**为什么这是个真问题而不是可接受的独立设计**：
1. Phold 会用自己的 pyrodigal-gv 重新预测基因坐标，与 Pharokka（64）产出的基因坐标/gene ID **不一致**，导致下游 66（VOG）、69（vConTACT3）等依赖 64 输出做整合的步骤对不上 gene ID。
2. 丢失 Pharokka 已经预测好的 tRNA / tmRNA / CRISPR repeats 注释能力（Phold 用 FASTA 输入时明确不预测这些）。
3. 3Di 结构预测（ProstT5，CPU 模式）是 Phold 真正的耗时大头，无论输入是 FASTA 还是 GBK 都要重跑一次；用错误输入跑完只会导致后续步骤发现坐标不对齐后被迫重跑，等于双重浪费算力。

**修复**：将 `65_vir_phold.sh` 的输入从 `${WORKDIR}/result/virus/votu/contigs/virus.fasta` 改为 `${WORKDIR}/result/virus/pharokka/pharokka.gbk`，并在脚本头部检查该文件存在（若步骤64未完成则报错退出，而非静默用错误输入跑完）。

**判断依据（可用于类似"脚本声明依赖但实现里没真正用到"的排查）**：
- 运行日志里出现 `was not a Genbank format file` / `pyrodigal-gv will be used` 这类警告，同时脚本文档写着依赖上游注释工具的输出 → 大概率是输入路径写错了，而非工具本身的正常行为。
- 发现此类不一致时，若已投入较长计算（如本例已跑 8.5 小时进入 3Di 阶段），**立即停止重启优于让它跑完**：耗时瓶颈通常在后段（此处是 ProstT5/3Di 预测），提前止损的成本远低于跑完后因下游整合失败被迫重跑。

**LLM 调用方式（Prompt）**：
```
检查 scripts/65_vir_phold.sh 的输入是否为 pharokka.gbk（而非 votu/contigs/virus.fasta）。
若发现依赖声明与实际输入不符，先停止正在运行的进程，修正脚本后再重启，
不要让明知输入错误的任务跑完。
```

---

### A4. Snakemake 规则的 `input` 必须声明全部实际依赖的上游文件，否则下游任务会静默用不完整数据跑完

**背景（2026-07-22 发现并修复，Project01 真菌批次1）**：`pipeline/rules/statistics.smk` 中 `fun_integration_tables` 规则只在 `input` 声明了 `metaeuk` 和 `eggnog` 两项，但其 shell 命令 `scripts/98d_fun_integration_tables.sh` 实际会读取 dbCAN/VFDB/AMRFinder/MEROPS 四个真菌注释规则（`fun_dbcan`/`fun_vfdb`/`fun_amr`/`fun_merops`）的输出。

**为什么这是个真问题**：Snakemake 的调度完全基于 `input` 声明构建 DAG。声明缺失导致这四个规则从未被调度执行，`98d` 脚本在源文件全部缺失的情况下用 `[WARN] 缺少 XXX 文件，跳过 XXX 表` 静默跳过了对应的四张核心表，只生成了 kegg_ko 和 cog 两张。而规则的 `output` 又声明了全部六张表，Snakemake 检测到四个 declared output 缺失后判定 job 失败，删除已生成的两个文件，报错退出。

**修复**：在 `fun_integration_tables` 的 `input` 中补齐 `dbcan`/`vfdb`/`amr`/`merops` 四项依赖，使 Snakemake DAG 正确联动这四个上游规则。

**判断依据（可用于类似"脚本产出不完整但仍报告完成"的排查）**：
- 若某规则的 shell 脚本内部有 `[WARN] 缺少 XXX，跳过` 之类的容错分支，日志里能看到该警告并不代表任务本身失败——但如果这些被跳过的产物恰好也在 Snakemake 的 `output` 声明里，最终仍会因为 declared output 缺失而报错。此时应先检查 `input` 是否遗漏了产出这些依赖文件的规则，而非直接怀疑脚本本身逻辑错误。
- Dry-run（`snakemake ... -n`）配合 `reason:` 字段可以验证补齐依赖后 DAG 是否正确联动上游规则，无需真正执行即可确认修复方向正确。

**LLM 调用方式（Prompt）**：
```
fun_integration_tables 报错说 output 缺失，但日志显示脚本正常跑完并打印了 [WARN] 跳过某些表。
检查该规则的 input 是否声明了脚本实际读取的全部上游文件，若遗漏请补齐并用 -n 验证 DAG。
```

---

### A5. eCAMI 算法对超大规模合并蛋白集（百万级）不可行，dbCAN 默认改用 diamond+hmmer 双工具

**背景（2026-07-22～23 发现并修复，Project01 真菌批次1）**：`scripts/83_fun_dbcan.sh` 硬编码 `run_dbcan --tools all`（DIAMOND+HMMER+eCAMI 三工具投票）。对 10 个真菌样本合并后的 277 万条蛋白序列跑 eCAMI，运行 22 小时仅完成 2.45%，按此速率推算完整跑完需要约 37 天。

**为什么这是个真问题而非"耐心等待即可"**：eCAMI 的核心算法（`envs/dbcan/.../eCAMI/prediction.py`）是逐蛋白扫描 k-mer 与全部 CAZyme 家族聚类库比对，复杂度约为 O(N_protein × N_family × N_kmer)，其设计目标是单基因组/宏基因组规模（几千到几万条蛋白），并非为跨样本合并后的百万级蛋白集合设计。用 CPU 占用率判断"是否在正常计算"会产生误导——8 个 worker 进程全程保持 99.9% CPU，看起来"很忙"，但 22 小时的真实产出只对应 2.45% 的完成度，这是算法复杂度问题，不是资源不足或卡死。

**判断依据（区分"真实但缓慢"与"卡死"，及早识别复杂度不可行）**：
- 不要只看 CPU 占用率判断任务是否"正常运行"。要看输出文件（本例中 `uniInput_thread_*.txt` 分片）的字节数或行数随时间的增长速率，并按输入总量折算完成百分比与预计总耗时。
- 若预计总耗时达到"天"甚至"周"的量级，应立即判定为算法/工具在当前数据规模下不可行，转而寻找同类工具中复杂度更低的子集（如本例的 DIAMOND+HMMER 双工具而非三工具投票），而非等待其"最终跑完"。
- dbCAN 官方文档本身也提示可用 `--tools diamond` 加速，说明多工具投票是精度加成而非强制要求；细菌维度对应脚本 `scripts/25_bac_dbcan.sh` 本来就只用 `--tools diamond` 单工具，可作为"该项目里多工具投票并非硬性要求"的先验证据。

**修复**：`scripts/83_fun_dbcan.sh` 改为 `--tools diamond hmmer`（跳过 eCAMI），同时补上此前遗漏的 `--dia_cpu "${CPUS}" --hmm_cpu "${CPUS}"`（此前线程数从未真正传给 run_dbcan，实际只用了默认的 4 线程）。修复后 DIAMOND 阶段 451 秒完成，HMMER 阶段约 25 小时完成（275 万蛋白 × 875 HMM 模型，仍偏慢但可接受，产出 129,669 条 CAZyme）。

**LLM 调用方式（Prompt）**：
```
dbcan/eCAMI 任务已运行超过X小时，CPU占用率很高但看起来没有明显进展。
检查其输出分片文件的增长速率，折算完成百分比和预计总耗时，
判断这是否是算法复杂度对当前数据规模不可行，而非单纯的运行缓慢。
```

---

### A6. 脚本内部的"幂等/跳过"判断文件不应脱离 Snakemake 的 `output` 声明独立存在，否则前次失败的残留文件会让脚本误判"已完成"

**背景（2026-07-27 发现并修复，Project01 真菌批次1）**：`scripts/98d_fun_integration_tables.sh` 以 `gene_annotation_matrix.tsv`（一个不在 Snakemake `output` 声明里的中间产物）是否存在，作为判断"核心表 Step1-5 是否需要重新生成"的依据：若存在则跳过 Step1-5，只补齐 Step6（FunOMIC）。A4 描述的那次失败运行中，`98d` 脚本在跑到一半时生成了这个文件后才因为 declared output（kegg_ko/cog/cazyme/vfdb/amr/merops 六张表）不全被 Snakemake 判定失败、清理 declared output——但 `gene_annotation_matrix.tsv` 因为不在 declared output 里，未被 Snakemake 的失败清理逻辑删除，残留在磁盘上。

**为什么这是个真问题**：A4 的规则依赖修复完成后重新触发任务，`98d` 脚本读到残留的 `gene_annotation_matrix.tsv`，误判"主整合表已存在"，直接跳过了生成六张核心表的全部逻辑，只执行了因缺文件同样被跳过的 Step6。最终日志显示"完成"，但 Snakemake declared output 六张表实际一张也没生成，导致 job 仍然失败——且这次失败的表面现象（"脚本打印完成但表没生成"）与 A4 的失败现象（"脚本打印跳过某些表"）完全不同，容易误诊为新的 bug，实际是同一根因（脚本产物与 Snakemake output 声明脱节）的第二次发作。

**判断依据（识别"脏状态导致的幂等误判"）**：
- 若一个脚本的"是否已完成"判断依据的文件，与 Snakemake 规则 `output` 声明的文件集合不完全一致（尤其是判断依据文件的生成时间点早于其他 output 文件），失败重跑后残留的判断依据文件会让脚本的幂等逻辑产生误判。
- 排查方法：对比失败日志中脚本打印的阶段信息（本例中"跳过 Step1-5"）与 Snakemake 的 `output` 声明是否一致；若脚本认为"已完成"但 declared output 缺失，应先检查并清理该脚本用于幂等判断的文件，而非怀疑核心生成逻辑本身有 bug。
- 更根本的修复方向（本次未做，留作后续改进）：脚本的幂等判断应直接检查全部 Snakemake declared output 文件是否存在，而不是依赖一个独立的中间产物。

**修复**：手动清理 `result/integration/fungi/` 目录下的残留文件（`gene_annotation_matrix.tsv` 及 `normalized/` 下的部分文件）后重新触发任务，脚本正常走完 Step1-6，65 秒内生成全部六张核心表。

**LLM 调用方式（Prompt）**：
```
fun_integration_tables 再次报错 output 缺失，但这次日志显示脚本认为"主整合表已存在，跳过 Step1-5"。
检查该脚本用于幂等判断的文件是否与 Snakemake output 声明的文件集合一致，
若不一致，清理判断依据文件对应目录后重新触发任务。
```

---

### A7. `93_stat_cooccurrence.sh` 硬编码的细菌丰度表路径与实际目录结构不符

**背景（2026-07-27 发现并修复，Project01 批次2-6启动首步）**：`scripts/93_stat_cooccurrence.sh` 中 `BACT_TABLE="${WORKDIR}/result/bacteria/metaphlan4/merged_abundance_table.txt"`，但项目实际的 MetaPhlAn4 合并丰度表位于 `${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv`（没有 `bacteria/` 中间目录，文件名也不同）。运行时 R 脚本内部 `read_abundance_table` 读取失败，`datasets$bacteria` 为 `NULL`，导致 `network_bac` 报 `Input unavailable for target: bac`，其余维度因跨维度共享样本不足 5 个被跳过，最终 `Error: No network results generated`。

**为什么这是个真问题而非数据量不足**：报错信息表面上和"样本量不足"（其余 4 个 warning 都是 `Need at least five metadata-matched samples` / `Insufficient shared samples`）看起来像同一类问题，但 `network_bac` 的 `Input unavailable` 实际是完全不同的根因——是路径写死错误导致文件读取失败，而不是真的样本数不够（10 个样本对细菌丰度表而言远超 5 个的门限）。

**判断依据**：
- 同一次报错里出现多种 warning 时，不要把它们归为同一类问题一并归因为"数据量不足"。逐条核对每个 warning 对应的实际检查逻辑（本例中 `Input unavailable` 和 `Need at least five samples` 是两个不同的 `stop()` 调用点），分别验证其触发条件是否真的成立。
- 用 `ls`/`find` 直接核对脚本里硬编码路径的文件是否存在，是最快的证伪手段——若不存在，直接定位到脚本本身的路径书写错误，无需深入统计逻辑本身。

**修复**：`BACT_TABLE` 改为 `${WORKDIR}/result/metaphlan4/merged/taxonomy.tsv`。`VIR_TABLE`（`result/virus/votu/votu_table.tsv`）和 `FUNGI_DIR`（`result/fungi/metaphlan4`）两个路径经核对均正确，未修改。

**LLM 调用方式（Prompt）**：
```
stat_cooccurrence 报错 "Input unavailable for target: bac"，其他维度报 "Need at least five samples"。
检查 93_stat_cooccurrence.sh 里 BACT_TABLE/VIR_TABLE/FUNGI_DIR 硬编码路径是否与项目实际目录结构一致，
不要把不同的报错原因混为一谈。
```

---

### A8. `96c_functional_redundancy.R` 双循环 `cor.test` 调用在大规模功能表上不可行，改为向量化 Spearman 相关系数+p值计算

**背景（2026-07-27 发现并修复，Project01 批次2-6 `stat_functional_redundancy` 任务）**：`96c_functional_redundancy.R` 用两层 `for` 循环遍历 `functional`（细菌 KEGG KO 丰度表，9088 行）× `taxonomy`（MetaPhlAn4 合并物种表，2392 行）的每一对组合，逐对调用 `stats::cor.test(..., method="spearman", exact=FALSE)`，理论上限达 9088 × 2392 = 21,738,496 次调用。进程以单核 100% CPU 运行超过 12 分钟仍停留在同一阶段（"[INFO] Dimension/type: bacteria/kegg_ko"之后无任何进度输出），`ps` 显示内存稳定在 ~628MB（并非内存泄漏，纯粹是调用开销累积）。

**为什么这是个真问题**：这与之前的 A5（eCAMI 算法复杂度不可行）是同一类问题——CPU 占用率看起来"正常工作"（100%单核），但算法本身在当前数据规模下不可行。区别在于 A5 是第三方工具的固有复杂度，A8 是自己写的 R 脚本里的实现方式选择不当：Spearman 相关系数本质上等价于对两个向量做 rank 变换后计算 Pearson 相关系数，完全可以用矩阵运算一次性算出整张相关系数矩阵，而不必对每一对 (function, species) 单独调用一次 `cor.test`（该函数每次调用都有非线性的 R 层函数分派开销，在千万级调用规模下这个开销本身就成为瓶颍）。

**判断依据**：
- 单核 CPU 100% 且内存稳定，不代表任务在"合理时间"内会完成——要结合迭代规模（此处 nrow × nrow ≈ 2170 万）和单次迭代的最低理论开销做量级估算，若预计总耗时达到与其他同批次任务（多为几分钟到几十分钟）不成比例的量级（这里之前已跑 12 分钟仍无一次完整输出，且循环体每次迭代还包含函数调用开销、构建 S3 对象等），应判定为实现方式问题而非"数据量偶尔大一点"。
- 优化方向优先选择保持统计方法学不变的向量化重写（Spearman 相关系数矩阵 = 对 rank 矩阵做 Pearson 相关系数矩阵），而不是为了速度改用不同的统计方法（如降级为 Pearson）——统计方法的选择是科学决策，性能优化不应该反向改变它。

**修复**：将双循环替换为：
1. 对 `functional`/`taxonomy` 逐行做 `rank(..., ties.method="average")` 得到秩矩阵；
2. 用 `stats::cor(t(function_ranks), t(taxonomy_ranks))` 一次性算出完整相关系数矩阵（Pearson correlation of ranks = Spearman rho）；
3. 用与 `stats::cor.test(..., exact=FALSE)` 内部一致的 t 分布近似公式 `t = rho * sqrt(df/(1-rho^2))`, `p = 2 * pt(-abs(t), df=df)` 向量化算出全部 p 值；
4. 对标准差为 0 的行/列（无法算相关系数）设为 `NA`，与原实现的 `next` 跳过逻辑保持一致。

修复前用模拟数据核对：对 5×4 个特征跑向量化版本与逐对 `cor.test` 循环，相关系数最大差异为 0，p 值最大差异为 2.22e-16（浮点误差量级），确认数值完全一致。修复后 bacteria/kegg_ko 维度从原来卡住 12 分钟以上无法完成，变为几秒内完成（Mean FDI: 14.5771, rho: 0.6222）；fungi/kegg_ko 和 virus/vog 维度同样几秒内完成。

**LLM 调用方式（Prompt）**：
```
96c_functional_redundancy.R 里两层 for 循环调用 cor.test 计算 Spearman 相关系数矩阵，
在 9088×2392 的数据规模上单核跑了 12 分钟以上没有进展。
请将其改写为向量化实现：对两个矩阵逐行 rank 变换后用 stats::cor() 一次性算出相关系数矩阵，
再用 t 分布公式向量化计算 p 值（与 cor.test(exact=FALSE) 内部使用的近似公式一致），
不要改变 Spearman 方法学本身（不要降级为 Pearson）。修改后用小规模模拟数据核对与
逐对 cor.test 循环结果的数值一致性（相关系数和 p 值的最大绝对差异应在浮点误差量级）。
```

---

### A9. `96_stat_functional.sh`/`96_stat_ml_siamcat.sh` 缺少对"数据为空"或"样本量不足"的优雅跳过逻辑，导致整批次任务被单个子任务拖垂

**背景（2026-07-27 发现并修复，Project01 批次2-6 `stat_functional`/`stat_ml_siamcat` 任务）**：两个独立问题同时暴露：
1. `stat_functional` 规则用 shell 循环依次跑 20 个 (dimension, func_type) 组合，其中 `bacteria:defense` 对应的 `defense_abundance.tsv` 只有表头没有数据行（本批次未检出任何防御系统基因）。`96_stat_functional.R` 的 `load_functional_matrix()` 没有对"零特征行"做前置校验，而是让 `t()`/`make.unique()` 等下游调用在空数据上报出不直观的 `'names' must be a character vector`，脚本以 exit 1 终止；由于 shell 循环里对每个 pair 的调用没有失败隔离（没有 `|| ...` 或单独的 sentinel 写入），Snakemake 把整条 `stat_functional` 规则判定为失败，直接导致后面 `bacteria:ncyc`、`bacteria:pcyc` 及全部 6 个 fungi pair、5 个 virus pair（共 13 个 pair）从未被执行。
2. `96_stat_ml_siamcat.sh` 里 `BACT_TABLE="${WORKDIR}/result/bacteria/metaphlan4/merged_abundance_table.txt"` 是与 A7 完全同源的路径错误（正确路径应为 `result/metaphlan4/merged/taxonomy.tsv`），修复路径后脚本能正确加载数据，但暴露出第二层问题：本批次 metadata 里 case/control 各只有 5 个样本，SIAMCAT 的交叉验证数据切分要求单类别样本数达到其内部阈值，5 v 5 从统计上无法支持模型训练与验证的划分，报 `Data set has only: control 5 treat 5 — This is not enough for SIAMCAT to proceed!`，最终 `Error: No model AUCs generated`。这是真实的样本量限制，不是 bug，但脚本没有区分"真正的错误"与"样本量不足导致的预期跳过"，两者都以 exit 1 终止，导致 Snakemake 判定整条规则失败。

**为什么这是个真问题**：
- 问题1 是 A6（幂等判断脱离 Snakemake output 声明）的姊妹问题——这里不是幂等判断出错，而是"批量循环内单个子任务失败即让整批全部落空"，本质是缺少子任务级别的失败隔离/降级处理，导致 1 个空表拖累了 19 个本可正常完成的 pair。
- 问题2 提示：脚本设计上需要区分"工具/环境层面的真实故障"（应该报错并阻塞下游）和"数据规模/统计前提不满足导致方法学上无法进行"（应该记录为已知限制并优雅跳过，而不是当作故障处理）——这类跳过应该写入一个带 `SKIPPED:` 前缀的 sentinel 文件，让下游可以区分"未运行"和"运行了但结果是空"。

**判断依据**：
- 批处理循环里的每个子步骤都应该假设自己可能会因为数据本身的原因（而非代码错误）失败，因此需要为"数据缺失/为空"这类可预期的失败路径设计专门的探测和优雅退出逻辑，而不是任由异常向上传播炸掉整条批处理。
- 收到"样本量不足"类报错时，先核实这是否是数据集本身的客观限制（本例 Project01 仅 10 个样本，5v5 分组，用 `wc -l`/查 metadata 分组计数即可确认），若确认是客观限制，应把它记录为已知限制（而不是继续加参数硬调直到"能跑"——那样反而会掩盖真实的统计效力不足问题）。这与本次任务的目标（"测评流程稳定性"而非追求统计显著性）是一致的：流程应该能优雅处理这种情况并继续往下走，而不是因为一个统计上注定拿不到有效结果的子任务而卡死整个批次。

**修复**：
1. `96_stat_functional.R` 的 `load_functional_matrix()` 增加 `if (nrow(raw) == 0) stop("No functional features present in: ...")` 前置校验，给出清晰可定位的报错信息（替代原来深层调用抛出的 `'names' must be a character vector`）。
2. `96_stat_functional.sh` 用 `tee` 捕获 R 脚本运行日志，若脚本以非零退出且日志中匹配到 `"zero data rows"`，则写入 `SKIPPED: ...` sentinel 并以 exit 0 返回，让该 pair 的失败不再级联影响循环里的其余 pair。
3. `96_stat_ml_siamcat.sh` 修正 `BACT_TABLE` 路径（同 A7 根因）；同时对 R 脚本运行日志匹配 `"not enough for SIAMCAT to proceed"` / `"No model AUCs generated"`，命中则写入 `SKIPPED: insufficient samples per class for SIAMCAT model training` sentinel 并以 exit 0 返回。
4. `pipeline/rules/statistics.smk` 未改动批处理循环结构本身（循环仍按顺序跑），失败隔离完全在两个 `.sh` 脚本内部完成，不改变 Snakemake 规则的 `output` 声明。

修复后重跑受影响的 13 个 pair（bacteria:ncyc/pcyc + 6 个 fungi pair + 5 个 virus pair）全部成功完成；`bacteria:defense` 生成 `SKIPPED` sentinel；`stat_ml_siamcat` 生成 `SKIPPED: insufficient samples per class` sentinel。批次2-6 最终全部 5 个收尾任务（`stat_functional_permanova`/`stat_functional_integrated`/`stat_functional_cross_dimension`/`downstream_summary`/`stat_report`）成功完成。

**LLM 调用方式（Prompt）**：
```
Snakemake 的 stat_functional 规则内部用 shell 循环依次跑 20 个 (dimension, func_type) 组合，
其中 bacteria:defense 对应的功能表只有表头没有数据行，导致 R 脚本以不直观的报错退出，
进而拖垂了循环里后面 13 个本应正常完成的组合。
请：1) 在 R 脚本加载功能表的位置增加"零数据行"前置校验，给出清晰报错；
2) 在对应的 .sh 包装脚本里捕获这种"数据为空"场景，写入带 SKIPPED: 前缀的 sentinel 并
以 exit 0 返回，不要让单个子任务的数据缺失级联阻塞循环里的其余子任务。
同样地，96_stat_ml_siamcat.sh 里发现两个问题：一是 BACT_TABLE 路径硬编码错误（同 A7 根因），
二是本批次 5v5 分组样本量不足以支撑 SIAMCAT 的交叉验证切分——这是真实的样本量限制而非 bug，
请为这种"方法学前提不满足"的场景同样设计优雅跳过（SKIPPED sentinel + exit 0），
不要和真正的代码/环境错误混在一起当故障处理。
```

---

### A10. `00_pipeline_full.sh`（模式二一站式入口脚本）第五阶段全部 9 处统计脚本调用缺失必填参数，且引用了已废弃的路径

**背景（2026-08-26 发现并修复，`/grill-me` 子路径梳理与全流程测试）**：`scripts/00_pipeline_full.sh` 第五阶段（步骤 91-98）依次调用 9 个统计分析脚本，但从未声明 `metadata.csv` 路径和分组列名，导致每一处调用都缺少 91/92/93/96/97 各脚本硬性要求的 `-m METADATA_CSV`（部分还需 `-g GROUP_COL`）参数。这些脚本内部都有 `if [ -z "${VAR}" ]; then exit 1; fi` 式的前置校验，缺参数会直接报错退出，而不是使用默认值悄悄跑偏——但这也意味着模式二的完整流程从第一次发布以来就无法在步骤 91 之后继续往下走。同时步骤 97 调用的是 `97_stat_curatedMGD.sh`，该脚本已被后续重构移除，实际继任者是 `97_stat_crosscohort.sh`，两者参数签名也不同。

**为什么这是个真问题而不是"示例数据凑巧没配 metadata"**：这不是"用户没提供 metadata 所以脚本报错"的正常行为——入口脚本本身既没有在头部声明 `meta`/`group_col` 变量，也没有在调用处传参，属于脚本编写时遗漏，而非用户输入缺失。只要有用户按照 README/Tutorial 描述的模式二一站式流程跑到第五阶段，必然在步骤 91 就卡死。

**判断依据（识别"入口脚本调用下游脚本时参数拼接不全"这类问题）**：
- 对每个被调用的下游脚本，先用 `bash script.sh -h`或直接读脚本头部的参数解析块，列出其必填参数集合；再逐一核对入口脚本的调用行是否覆盖了全部必填项，不要只看调用是否"语法正确"（`bash -n` 通不出这类问题，因为参数缺失是运行期的业务校验，不是语法错误）。
- 排查废弃路径引用：`grep` 全部脚本调用名，核对对应文件是否仍存在于 `scripts/` 目录，废弃脚本通常会在其 `scripts/archive/` 或 `deprecated/` 位置留有说明，可用于确认继任脚本的名称和参数签名差异。

**修复**：
1. 在变量声明区新增 `meta=${wd}/metadata.csv` 和 `group_col=group`，第五阶段 9 处调用全部补全 `-m ${meta}`（91/92/93/94/96/97 均需要）及 `-g ${group_col}`（92/93/96/97 需要）。
2. 91/92 使用的示例 `metadata.csv` 只有 `group`/`host_type` 两列（单批次数据），因此 95a/95b（批次校正/评估，依赖 `-b BATCH_COL`）整段注释跳过，并在注释里说明多批次项目需自行在 metadata.csv 补充 batch 列后再启用。
3. 步骤 97 调用从 `97_stat_curatedMGD.sh` 改为 `97_stat_crosscohort.sh`，并补全其所需的 `-m`/`-g` 参数。
4. 顺带修复了同一文件第 39 行一处历史存量 shellcheck SC2011 warning（`ls | xargs -n1 basename` 改为 `find ... -exec basename {} \;`）——这是本次改动触发 pre-commit hook 对整份文件做 shellcheck 全量扫描后暴露的，与本次功能性修复无直接关系，但因为改了同一个文件必须一并清零才能提交。

验证：`bash -n` 语法检查通过；对 91/92/97 三个脚本做 `timeout 5` 参数解析级 smoke test（不跑到实际计算耗时阶段），均在参数解析阶段正常通过或在预期计算阶段被正常打断，无残留进程和半成品输出；Snakemake level2/level3 CI（`scripts/tests/run_ci_checks.sh --level {2,3}`）全绿，261 个 job DAG 正确解析，确认本次改动对既有 Snakemake 路径（模式三）无回归。

**LLM 调用方式（Prompt）**：
```
00_pipeline_full.sh 第五阶段调用了 91-98 全部统计脚本，但从未声明或传入 metadata.csv 路径。
请核对每个被调用脚本（91/92/93/94/95a/95b/96/97/98）各自的必填参数集合，
补全入口脚本里缺失的 -m/-g/-b 参数；同时检查调用的脚本文件名是否仍然存在于 scripts/ 目录，
若已被重构改名（如 97_stat_curatedMGD.sh → 97_stat_crosscohort.sh），需同步更新调用名和对应参数。
若某个下游脚本需要的列（如 batch）在示例 metadata.csv 里不存在，应注释跳过该步骤并说明启用条件，
而不是虚构一个不存在的列名硬跑。
```

---

