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

**Project01 执行进度（MEGAHIT — per-sample 策略）**：

| 阶段 | 执行方式 | 完成样本 | 状态 |
|------|---------|---------|------|
| ① 单样本测试 | 模式一，手动 | Sample1 | ✅ 审核通过（N50=7,022 bp，111,599 contigs，耗时 ~156 min）|
| ② rush 并行9样本 | 模式二，rush -j 2 | Sample2-4, Sample10-15 | ✅ 全部完成（10/10 样本，contigs 范围 84,672–270,847）|
| ③ 剩余40样本 | Snakemake | Sample16-51 | ⏳ 10样本所有步骤通过后启动 |

> MEGAHIT CPU+内存密集（~30-80 GB/样本），-j 2 并发。~156 min/样本，9 个样本约 12 小时完成。

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
bash ~/Course/Maxmetagenome/scripts/18_bac_cdhit.sh \
  -t 48 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome

# ── 方式 B：MMseqs2 Linclust（>500万基因，50样本全量推荐）───────────
bash ~/Course/Maxmetagenome/scripts/18_bac_cdhit.sh \
  --tool mmseqs \
  -t 48 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
```

> `envs/assembly` 中已同时安装 CD-HIT v4.8.1 和 MMseqs2 v13.45111，无需额外配置。

**LLM 调用示例**：
```
请帮我运行步骤 9（基因去冗余），当前 Project01 有 10 个样本，使用默认 CD-HIT 后端。
工作目录：~/Course/Maxmetagenome/Project/Project01
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
bash ~/Course/Maxmetagenome/scripts/19_bac_salmon_build.sh \
  -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
bash ~/Course/Maxmetagenome/scripts/20_bac_salmon_quant.sh \
  -s Sample1 -t 16 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome

# ② rush 并行 9 样本（Sample2-4, Sample10-15）
PROJ=~/Course/Maxmetagenome
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
bash ~/Course/Maxmetagenome/scripts/21_bac_eggnog.sh \
  -t 48 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
bash ~/Course/Maxmetagenome/scripts/22_bac_kegg.sh \
  -t 48 \
  -w ~/Course/Maxmetagenome/Project/Project01 \
  -r ~/Course/Maxmetagenome
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
PROJ=~/Course/Maxmetagenome && WORKDIR=$PROJ/Project/Project01
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

### 步骤 22：功能注释补充（SCyc / Pfam-A / UniProt Swiss-Prot / FeGenie）

**新增（2026-06-30）**：补全硫循环维度 + 高精度蛋白功能域注释 + 铁代谢基因预测，覆盖 eggNOG/KEGG 未命中区域。

```bash
# 31b SCyc 硫循环（与 NCyc/PCyc 完全对称，DIAMOND，~10 分钟）
bash scripts/31b_bac_scyc.sh -t 16 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome

# 31c Pfam-A 蛋白域（hmmscan --cut_ga，建议 32+ 线程，~1-3 小时）
bash scripts/31c_bac_pfam.sh -t 32 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome

# 31d UniProt Swiss-Prot（MMseqs2 easy-search，~20-40 分钟）
bash scripts/31d_bac_uniprot.sh -t 16 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome

# 31e FeGenie 铁代谢（per-sample 模式，推荐）
bash scripts/31e_bac_fegenie.sh -s S01 -t 8 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome
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
conda run --prefix ~/Course/Maxmetagenome/envs/fegenie FeGenie.py -h

# 验证 HMM 数据库
ls -lh ~/Course/Maxmetagenome/envs/fegenie/share/fegenie-1.2/hmms/iron/
```

**执行方式**：
```bash
# 单样本运行（per-sample 模式，推荐）
bash scripts/31e_bac_fegenie.sh -s S01 -t 8 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome

# 批量运行（rush 并行）
cat [WORKDIR]/samplesheet.csv | grep -v "^sample" | cut -d',' -f1 | \
rush -j 2 'bash scripts/31e_bac_fegenie.sh -s {} -t 8 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome'

# NR 模式（单次运行，所有样本共享结果，适合 MAG-level 分析）
bash scripts/31e_bac_fegenie.sh -s NR -t 16 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome --input-type nr
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
     -w [WORKDIR] -r ~/Course/Maxmetagenome

# 批量运行（rush 并行）
cat [WORKDIR]/samplesheet.csv | grep -v "^sample" | cut -d',' -f1 | \
rush -j 2 'bash scripts/42_bac_mge.sh -s {} -t 16 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome'
```

> **注意**：
> - `mobileOG` 步骤为 aggregate，多样本只运行一次，第一个样本完成后后续自动跳过
> - `42_bac_mge.sh` 依赖 `envs/assembly`（diamond/mmseqs2/blast）+ `envs/dbcan`（hmmscan）
> - 肠道菌群中整合接合元件（ICEberg）和 I 类整合子（integrall class1）与 ARG 水平转移密切相关

---

### 步骤 24：质粒识别（PlasmidFinder，per-sample）

**前置安装**（首次运行前执行一次）：
```bash
conda create --prefix ~/Course/Maxmetagenome/envs/plasmidfinder python=3.10 -y
conda install --prefix ~/Course/Maxmetagenome/envs/plasmidfinder \
    -c conda-forge -c bioconda plasmidfinder=2.1.6 blast -y
```

```bash
# 单样本运行
bash scripts/42b_bac_plasmidfinder.sh -s S01 -t 16 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome

# 批量运行（rush 并行）
cat [WORKDIR]/samplesheet.csv | grep -v "^sample" | cut -d',' -f1 | \
rush -j 4 'bash scripts/42b_bac_plasmidfinder.sh -s {} -t 8 \
     -w [WORKDIR] -r ~/Course/Maxmetagenome'
```

> **输出**：`result/mge/plasmidfinder/{SAMPLE}/results_tab.tsv`（含 replicon 类型 + Inc group）
> **与 MGE 整合**：PlasmidFinder 定位质粒 contig → mobileOG 细化质粒基因功能 → AMRFinder/CARD 识别质粒携带 ARG → ICEberg 追踪接合转移机制，形成完整的 HGT 分析链路。

---

### 步骤 25：Binning（MAG 回收，脚本 32-41）

**步骤名称**：宏基因组组装基因组（MAG）回收与质量评估

**目的**：从组装 contig 中通过覆盖度+序列组成信息聚类出单菌基因组草图（bin），经多算法整合、质量评估、去冗余后得到高质量 MAG 集合，用于菌株级功能与系统发育分析。

**依赖**：步骤 7（MEGAHIT 组装）输出的 contigs + 步骤 2（去宿主 reads，用于覆盖度计算）

**流程链**：32 CoverM depth → 33/34/35（MetaBAT2 / MaxBin2 / SemiBin2，三算法独立并行）→ 36 DAS_Tool（整合择优）→ 37 CheckM2（ML 质量评估）→ 38 dRep（去冗余）→ 39 CoverM quant（丰度定量）→ 40 GTDB-Tk（系统发育分类）→ 41 Bakta（精细注释）

**执行方式（单样本示例，Sample1）**：
```bash
bash scripts/32_bac_coverm_depth.sh   -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/Maxmetagenome
bash scripts/33_bac_metabat2.sh       -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/Maxmetagenome
bash scripts/34_bac_maxbin2.sh        -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/Maxmetagenome
bash scripts/35_bac_semibin2.sh       -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/Maxmetagenome
bash scripts/36_bac_dastool.sh        -s Sample1 -t 32 -w [WORKDIR] -r ~/Course/Maxmetagenome
bash scripts/37_bac_checkm2.sh        -t 32 -w [WORKDIR] -r ~/Course/Maxmetagenome   # 跨样本汇总，非 per-sample
```

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
| 40 | GTDB-Tk | 系统发育分类（R214 数据库，跳过 skani，marker-based 分类）| ✅ 213 个 MAG 全部分类为细菌（无古菌），耗时 2636s。**已知问题**：GTDB-Tk 2.5.2 强依赖 R226 skani 数据，R214 数据库无法直接使用；修复方案：① patch `ani_rep.py` 跳过空 reference 时的 skani 调用；② 启用 `classify.py` 内置 DEBUG 机制（`skani_verification = {}`）强制跳过所有 skani ANI 验证，仅使用传统 pplacer marker-based 分类。分类结果示例：`d__Bacteria;p__Bacillota_A;c__Clostridia;o__Oscillospirales;f__Oscillospiraceae;g__CAG-103` |
| 41 | Prokka | MAG 精细注释 | ✅ 213/213 完成（并行优化：`41_bac_prokka_parallel.sh`，6 并发 × 8 线程，耗时 ~26 小时，相比原串行方案 5-9 天加速 5-8×）。**备注**：Bakta 因 Diamond sORF 兼容性问题放弃，Prokka 注释精度对大多数下游分析足够 |

> 612 个 bin 中 488 个（79.7%）通过高质量过滤，比例正常（宏基因组 binning 典型高质量 MAG 占比 60-85%，与测序深度、样本复杂度相关）。

---

## 附录：LLM 辅助宏基因组分析最佳实践

> 按发现时间顺序追加。凡是在执行过程中遇到的有价值的 LLM 交互模式，均同步记录于此。

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

