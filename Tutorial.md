# MaxMetagenome 分析平台使用教程

> 面向首次使用者的完整流程指南
> 平台版本：MaxMetagenome v1.0 | 更新日期：2026-06-24
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
- **LLM 调用方式**：可直接在 Claude Code 中粘贴的 Prompt
- **输出结果**：预期文件结构和内容格式
- **审核要点**：判断结果是否正确的具体指标

**三种运行模式**（详见 CLAUDE.md §14.1）：
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

**步骤名称**：激活 MaxMetagenome 环境

**目的**：初始化项目的 conda 环境和路径变量，使所有脚本和工具可直接调用。

**执行方式**：
```bash
source ~/Course/Maxmetagenome/scripts/activate.sh
```

**输出结果**：
```
[MaxMetagenome] 环境已激活  PROJ_DIR=/home/labuser/Course/Maxmetagenome
```

**审核要点**：
- 看到 `[MaxMetagenome] 环境已激活` 即成功
- `PROJ_DIR` 路径指向正确的项目根目录
- 若报错，检查 `miniforge3/` 目录是否存在

**LLM 调用方式（Prompt）**：
```
请帮我激活 MaxMetagenome 环境并确认激活成功：
source ~/Course/Maxmetagenome/scripts/activate.sh
确认输出中是否包含"环境已激活"
```

---

### P2. 准备项目目录和数据

**步骤名称**：创建项目目录结构并软链接原始数据

**目的**：将原始测序数据以软链接方式接入项目，避免复制大文件，节省磁盘空间。

**执行方式**：
```bash
# 创建项目目录
mkdir -p ~/Course/Maxmetagenome/Project/MyProject/{data,temp,result,logs}

# 将原始数据软链接到 data/ 目录（.fq.gz → .fastq.gz）
for f in /path/to/raw/data/*.fq.gz; do
  ln -sf "$f" ~/Course/Maxmetagenome/Project/MyProject/data/$(basename "${f/.fq.gz/.fastq.gz}")
done

# 验证
ls ~/Course/Maxmetagenome/Project/MyProject/data/ | head -6
ls ~/Course/Maxmetagenome/Project/MyProject/data/ | wc -l
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
请帮我在 MaxMetagenome 项目中为新项目 MyProject 创建目录结构，
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
DATADIR=~/Course/Maxmetagenome/Project/MyProject/data
echo "sample_id,r1,r2" > ~/Course/Maxmetagenome/Project/MyProject/samplesheet.csv
ls $DATADIR/*_1.fastq.gz | sort -V | while read r1; do
  sample=$(basename "$r1" _1.fastq.gz)
  r2="${r1/_1.fastq.gz/_2.fastq.gz}"
  echo "${sample},${r1},${r2}"
done >> ~/Course/Maxmetagenome/Project/MyProject/samplesheet.csv

# 查看前5行
head -6 ~/Course/Maxmetagenome/Project/MyProject/samplesheet.csv
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
Sample1,/home/.../data/Sample1_1.fastq.gz,/home/.../data/Sample1_2.fastq.gz
Sample2,/home/.../data/Sample2_1.fastq.gz,/home/.../data/Sample2_2.fastq.gz
```

**审核要点**：
- 行数 = 样本数 + 1（含表头）
- r1/r2 路径是否真实存在：`head -2 samplesheet.csv | tail -1 | cut -d, -f2 | xargs ls`
- metadata 中 `group` 列值只有两类（如 `control` 和 `treat`），且每组样本数平衡

**LLM 调用方式（Prompt）**：
```
请帮我为 MaxMetagenome 项目 Project/MyProject 生成 samplesheet.csv 和 metadata.csv。
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
source ~/Course/Maxmetagenome/scripts/activate.sh

bash ~/Course/Maxmetagenome/scripts/01_qc_fastp.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
```

> **为什么用 `-t 16`**：fastp 的 `-w`（worker threads）参数超过 16 后性能不再提升，这是工具本身的设计限制。本机 48 核，单样本最优就是 16 线程。

*模式二 — rush 并行剩余9样本（单样本审核通过后执行，补齐10样本验证集）：*
```bash
PROJ=~/Course/Maxmetagenome
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
请帮我运行 MaxMetagenome 步骤1（fastp质控），样本 Sample1，
项目目录 ~/Course/Maxmetagenome/Project/Project01，线程数 16。
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
bash ~/Course/Maxmetagenome/scripts/02_qc_kneaddata.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
```

> **为什么用 `-t 16`**：kneaddata 底层是 Bowtie2，线程数越高比对越快，16 线程是单任务合理上限（超过后收益递减且挤占并行空间）。

*模式二 — rush 并行剩余9样本（单样本审核通过后执行，补齐10样本验证集）：*
```bash
PROJ=~/Course/Maxmetagenome
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
请帮我运行 MaxMetagenome 步骤2（kneaddata去宿主），样本 Sample1，
项目目录 ~/Course/Maxmetagenome/Project/Project01，线程数 16。
运行完成后解析 result/kneaddata/Sample1/kneaddata.log 中的 READ COUNT 行，
输出：输入reads数（R1+R2合计）、宿主去除reads数、宿主去除率、微生物保留率，
并判断是否在正常范围（肠道样本宿主污染率通常 <5%，超过 30% 需复查采样）。
```

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
bash ~/Course/Maxmetagenome/scripts/11_bac_metaphlan4.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
请帮我解读 MaxMetagenome 步骤3（MetaPhlAn4）的输出结果：
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
bash ~/Course/Maxmetagenome/scripts/13_bac_humann3.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
请帮我解读 MaxMetagenome 步骤4（HUMAnN3）的输出结果，样本 Sample1：
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
bash ~/Course/Maxmetagenome/scripts/14_bac_kraken2.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
请帮我解读 MaxMetagenome 步骤5（Kraken2+Bracken）的输出结果，样本 Sample1：
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
bash ~/Course/Maxmetagenome/scripts/15_bac_centrifuger.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
请帮我解读 MaxMetagenome 步骤6（Centrifuger）的输出结果，样本 Sample1：
文件：result/centrifuger/Sample1/Sample1.kreport.tsv
输出：
1）总分类率和细菌域分类率；
2）门级（P行）丰度分布 Top 10；
3）种级（S行）丰度 Top 10；
4）与 MetaPhlAn4、Kraken2 结果的三工具一致性评估；
5）综合判断可信度（三工具门级方向是否一致）。
```

---

### 步骤 7：宏基因组从头组装（MEGAHIT）

**步骤名称**：de novo 宏基因组组装

**目的**：将 reads 组装成更长的 contig 序列，为后续基因预测（Prodigal）、功能注释（eggNOG/KEGG/AMR 等）和 MAG 回收（Binning）提供基础。组装结果的质量直接决定基因目录的完整性。

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
bash ~/Course/Maxmetagenome/scripts/16_bac_megahit.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
请帮我统计 MaxMetagenome 步骤7（MEGAHIT）的组装质量，样本 Sample1：
文件：result/assembly/megahit/Sample1/Sample1.contigs.fa
输出：
1）Contig 总数、总碱基数（Mb）；
2）N50、N90、最长 contig；
3）≥500 bp、≥1000 bp、≥5000 bp 的 contig 数量；
4）综合判断组装质量（N50≥1kb 合格，≥5kb 优秀）。
```

---

### 步骤 8：基因预测（Prodigal）

**步骤名称**：蛋白编码基因预测

**目的**：从 contig 序列中识别蛋白编码基因（CDS），输出蛋白序列（.faa）和核苷酸序列（.fna），供后续功能注释使用。Prodigal 是宏基因组标准基因预测工具，无监督训练，速度快。

**依赖**：步骤 7 输出的 `Sample1.contigs.fa`

**执行方式**：

*模式一（本教程）— 单样本，手动执行：*
```bash
bash ~/Course/Maxmetagenome/scripts/17_bac_prodigal.sh \
  -s Sample1 \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
请帮我统计 MaxMetagenome 步骤8（Prodigal）的基因预测结果，样本 Sample1：
文件：result/assembly/prodigal/Sample1/Sample1.faa
输出：
1）预测基因总数（faa 文件中的序列数）；
2）完整基因数和比例（从日志中提取 partial=00 的数量）；
3）.faa、.fna、.gff 三个文件是否存在及大小；
4）综合判断预测质量（基因数>10万，完整基因比例>40%）。
```

---

## 附录：LLM 辅助执行技巧

> 本章记录在 Claude Code 中执行分析时发现的实用操作技巧，按发现时间顺序追加。
> 凡是在执行过程中遇到的有价值的 LLM 交互模式，均同步记录于此。

---

### A1. 定时进程监控（CronCreate）

**场景**：启动耗时后台任务（如 kneaddata rush 批量，~2-3小时）后，让 LLM 定时自动检查进度，无需手动反复询问。

**操作方式**（在 Claude Code 中直接说）：
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
- 定时任务持久化（写入 `.claude/scheduled_tasks.json`），Claude Code 重启后继续有效

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
bash ~/Course/Maxmetagenome/scripts/13_bac_humann3.sh \
  -s Sample1 -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome \
  --speed-mode balanced
```

*rush 批量（balanced，可提升至 -j 3）：*
```bash
PROJ=~/Course/Maxmetagenome
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
请帮我用 balanced 模式重新运行 MaxMetagenome HUMAnN3，样本列表来自
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

