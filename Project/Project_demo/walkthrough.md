# CSCCD-MetagenomeFlow 全链演示走查（Project_demo）

> **启动本项目（复制给 AI 助手）**：
> 「请继续执行 CSCCD-MetagenomeFlow 演示项目 Project_demo 的下一步骤（模式一、
> `MGX_MONITOR=1` 开启监控），完成后用 `run_monitor.py --text` 采集监控快照，
> 同步更新 walkthrough.md 的执行结果，并请质量审核对本步结果做点评。」

| 事项 | 内容 |
|---|---|
| 数据 | 6 样本（treat=Sample1/2/10，control=Sample3/4/11），自 Project01 只读拷出，62G，与源逐字节一致 |
| 样本表/分组 | `samplesheet.csv`（五列惯例）/ `metadata.csv`（treat ×3，control ×3） |
| 锚点/基线 | git tag `new-project-demo-v1.2.1` / `step_checklist.md`（142 步冻结清单） |
| 策略 | 空产出继续 + 如实记录（见 NOTES.md） |

---

## 01 · fastp 质量控制（接头去除、低质修剪、配对校正）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 01 质量控制步骤（fastp，threads 16），
> 完成后汇报各样本通行率、Q30 与产出文件。」

**核心执行命令**（摘自 `scripts/01_qc_fastp.sh`，`{sample}` 为样本变量）：

```bash
fastp \
  --in1  data/{sample}_1.fastq.gz \
  --in2  data/{sample}_2.fastq.gz \
  --out1 result/fastp/{sample}/{sample}_1.fastq.gz \
  --out2 result/fastp/{sample}/{sample}_2.fastq.gz \
  --json result/fastp/{sample}/{sample}.json \
  --html result/fastp/{sample}/{sample}.html \
  --detect_adapter_for_pe \
  --qualified_quality_phred 20 \
  --length_required 50 \
  --correction \
  -w 16
```

**执行结果**（2026-10-03 实测，6/6 成功；耗时含三线并行负载）：

> ⚠️ 通行率 99.8-100% 表明输入可能是测序公司已处理过的 clean data，非原始 raw reads。


| 样本 | 组 | 原始 reads | 清洁 reads | 通行率 | Q30 | GC |
|---|---|---|---|---|---|---|
| Sample1 | treat | 84,563,768 | 84,560,980 | 100.0% | 97.9% | 45.8% |
| Sample10 | treat | 95,234,276 | 95,229,224 | 100.0% | 97.8% | 45.5% |
| Sample11 | control | 104,606,294 | 104,602,366 | 100.0% | 98.0% | 45.1% |
| Sample2 | treat | 84,158,864 | 84,155,472 | 100.0% | 98.2% | 43.1% |
| Sample3 | control | 111,775,904 | 111,770,134 | 100.0% | 98.2% | 43.4% |
| Sample4 | control | 78,708,096 | 78,561,970 | 99.8% | 97.2% | 40.6% |

产出：`result/fastp/<样本>/`（清洁 reads 双端 ~4.4–5.6G/样本 + JSON/HTML 报告）；监控事件 12 条（6 开始 + 6 终态 ✓）全部成对落盘。

**质量审核点评**（主代理按五维度起草，预处理段关口由质量审核复核）：
- **运算时间**：442–493 秒/样本（16 线程、62G 真实数据、三线并行负载下）；纯 IO 密集，6 样本串行约 47 分钟。
- **输出文件**：每样本清洁 reads 双端（4.4–5.6G）+ JSON/HTML 报告，合计约 30G，路径规范 ✓。
- **后续使用**：清洁 reads 直接供 02 去宿主；fastp JSON 是 MultiQC（00_multiqc_report.sh）的输入，勿删。
- **加速空间**：有——①多样本并行（模式二 `-j 2` 或双终端，磁盘允许时可近线性）；②threads 提至 32（48 核机器、并行期不建议）；瓶颈主要在磁盘读写而非 CPU。
- **内存/硬盘**：内存占用温和（fastp 16 线程典型 <2G，本步未计量——maxRSS 记录为 ENG-6 遗留项）；磁盘净增约 30G（原始 62G 保留，总计 +30G 中间产物）。


---

## 02 · kneaddata 去宿主（人源 reads 去除）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 02 去宿主步骤（kneaddata，threads 16），完成后汇报各样本的人源污染比例与产出。」

**核心执行命令**（摘自 `scripts/02_qc_kneaddata.sh`）：

```bash
kneaddata \
  --input1 result/fastp/{sample}/{sample}_1.fastq.gz \
  --input2 result/fastp/{sample}/{sample}_2.fastq.gz \
  --output temp/kneaddata/{sample} \
  --reference-db $REPO/db/kneaddata/human \
  --bypass-trim \
  --remove-intermediate-output \
  --threads 16
# 完成后将 temp 内的 _kneaddata_raw.fastq.gz 移至 result/kneaddata/{sample}/
```

**执行结果**（2026-10-03/04 实测，6/6 成功）：

| 样本 | 组 | 原始 pairs | 人源 contam reads | 真实人源比 |
|---|---|---|---|---|
| Sample1 | treat | 42,280,490 | 13,233 | 0.031% |
| Sample2 | treat | 42,077,736 | 12,832 | 0.030% |
| Sample10 | treat | 47,614,612 | 12,525 | 0.026% |
| Sample3 | control | 55,885,067 | 15,935 | 0.029% |
| Sample4 | control | 39,280,985 | 75,854 | 0.193% |
| Sample11 | control | 52,301,183 | 22,831 | 0.044% |

计时：Sample1 131min、Sample10 143min、Sample11 159min、Sample2 129min、Sample3 171min、Sample4 121min（合计 14.3 小时）。产出：`result/kneaddata/<样本>/`（清洁 reads 双端 + orphan + 污染 reads + log/stats）。

**执行点评**（主代理起草）：（主代理按五维度起草，预处理段关口由质量审核复核；HEAD: 050f1c6）:
- **运算时间**：121–171 分钟/样本（16 线程，bowtie2 --very-sensitive-local 比对 ~42M reads vs 人基因组）；串行合计 14.3 小时。
- **输出文件**：每样本 4 个主要文件（clean paired ×2 + orphan + stats），~8–12G/样本。
- **后续使用**：清洁 reads 供 02b 配对修复 → 三界分析链；stats 是 MultiQC 输入。
- **加速空间**：大——多样本并行（模式二 `-j 3` 总时长 14.3h → ~5h）；threads >16 收益递减（IO 密集）。
- **内存/硬盘**：内存高峰 ~24G（bowtie2 人基因组索引常驻）；磁盘净增 ~58G 清洁 reads（temp/ 下的 bowtie2 中间文件 ~60G 可安全清除）。


---

## 02b · seqkit pair 配对修复（R1/R2 读取顺序严格重配对）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 02b 配对修复步骤，完成后汇报各样本配对前后 reads 数一致性。」

**核心执行命令**（摘自 `scripts/02b_qc_pair_repair.sh`）：

```bash
seqkit pair \
  -1 result/kneaddata/{sample}/{sample}_1.kneaddata_raw.fastq.gz \
  -2 result/kneaddata/{sample}/{sample}_2.kneaddata_raw.fastq.gz \
  -O temp/pair_repair/{sample} \
  --id-regexp '^(\S+)\/[12]'
# 完成后将配对输出 mv 为 _kneaddata.fastq.gz（新文件，raw 保留作哨兵）
```

**执行结果**（2026-10-04 实测，6/6 成功）：

| 样本 | 配对前 | 配对后 | 丢失 | 耗时 |
|---|---|---|---|---|
| Sample1 | 41,962,400 | 41,962,400 | 0 | 363s |
| Sample2 | 41,751,756 | 41,751,756 | 0 | 353s |
| Sample10 | 46,906,471 | 46,906,471 | 0 | 400s |
| Sample3 | 55,411,039 | 55,411,039 | 0 | 471s |
| Sample4 | 38,900,065 | 38,900,065 | 0 | 338s |
| Sample11 | 51,631,260 | 51,631,260 | 0 | 438s |

产出：新增 `_1.kneaddata.fastq.gz` / `_2.kneaddata.fastq.gz`（严格配对新文件）；`_kneaddata_raw` 原件保留（是 02 的哨兵，不可删）；哨兵 `.pair_repair_done.txt` ✓。磁盘额外增 ~58G。

**执行点评**（主代理起草）：（主代理按五维度起草，预处理段关口由质量审核复核；HEAD: 050f1c6）:
- **运算时间**：338–471 秒/样本（IO 密集：读写 4–5G 压缩 fastq），合计 ~39 分钟。
- **输出文件**：新增配对文件（raw 保留作哨兵，磁盘额外 ~58G）；哨兵 6/6 落位。配对前后 reads 数完全一致（零丢失）。
- **后续使用**：严格配对的清洁 reads 供三界分析链首步（11 metaphlan4 / 14 kraken2 等）；不配对修复则下游 bwa/metaphlan 会因 R1/R2 顺序错位而崩溃（v1.1.4 教训）。
- **加速空间**：有限——瓶颈在磁盘 IO（gzip 解压/重压）；多样本并行可按比例缩减。
- **内存/硬盘**：内存温和（seqkit 流式处理）；temp/ 临时空间需 ~10G/样本（完成后可清除）。


---

## 11 · MetaPhlAn4 物种分类

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 11 MetaPhlAn4 物种分类（threads 16），完成后汇报各样本检出的物种数。」

**核心执行命令**（摘自 `scripts/11_bac_metaphlan4.sh`）：
```bash
# MetaPhlAn4 v4.2.4 双端输入需先合并为单文件
zcat result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
      result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
  | gzip -c > temp/metaphlan4/{sample}/{sample}_merged.fastq.gz

metaphlan temp/metaphlan4/{sample}/{sample}_merged.fastq.gz \
  --input_type fastq \
  --db_dir $REPO/db/metaphlan4 \
  -x mpa_vOct22_CHOCOPhlAnSGB_202212 \
  --nproc 16 \
  --mapout temp/metaphlan4/{sample}/{sample}.mapout.bz2 \
  --samout result/metaphlan4/{sample}/{sample}.sam \
  -o result/metaphlan4/{sample}/{sample}_profile.txt \
  --offline
# 完成后 bzip2 压缩 SAM 文件（StrainPhlAn4 需要 .sam.bz2）
```

**执行结果**：6/6 成功，7380–10299 秒/样本（2.0–2.9h）。

**执行点评**（主代理起草）：运算时间合理（bowtie2 比对全库索引为瓶颈）；产出标准 MetaPhlAn4 格式。

---

## 11b · MetaPhlAn4 多样本合并

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 11b MetaPhlAn4 合并，生成项目级丰度矩阵。」

**核心执行命令**（摘自 `scripts/11b_bac_metaphlan4_merge.sh`）：
```bash
merge_metaphlan_tables.py ${PROFILE_LIST} \
  | tail -n+2 \
  | sed '1 s/clade_name/ID/' \
  | sed '2i #metaphlan4' \
  > result/metaphlan4/merged/taxonomy.tsv
# 再由 grep 提取菌种级/菌属级 TSV，python3 生成 taxonomy_species.csv
```

**执行结果**：4 秒完成。产出：属级 TSV + 种级 CSV。

**执行点评**（主代理起草）：秒级完成，无性能问题。

---

## 12 · StrainPhlAn4 菌株追踪（clades 检测模式）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 12 StrainPhlAn4 菌株检测（threads 16），完成后汇报检出的 clades 数量。」

**核心执行命令**（摘自 `scripts/12_bac_strainphlan4.sh`，默认 --print_clades_only 模式）：
```bash
# 预处理：SAM header @SQ 去重（vOct22 库含重复 @SQ，pysam 解析报错的已知 bug）
bzip2 -dk {sample}.sam.bz2 -c | \
  awk '/^@SQ/{sn=$2; if(!seen[sn]++) print; next} {print}' | bzip2 -c \
  > temp/strainphlan4/dedup_sam/{sample}.sam.bz2

# Step1: sample2markers — 提取每样本 consensus markers（.json.bz2）
sample2markers.py -i ${DEDUP_SAM_LIST} \
  -d $REPO/db/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202212.pkl \
  -o result/strainphlan4/consensus_markers \
  -f bz2 -n 16

# Step2: strainphlan — 列出可分析 clades（检测模式）
strainphlan \
  -s result/strainphlan4/consensus_markers/*.json.bz2 \
  -d $REPO/db/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202212.pkl \
  -o result/strainphlan4/trees \
  --print_clades_only \
  --non_interactive \
  -n 16
```

**执行结果**：3857 秒（64 分钟）。检测到 50 个可分析 clades，其中 7 个在全部 6 个样本中出现。

**执行点评**（主代理起草）：默认只做检测（--print_clades_only），要得到菌株系统发育树需带 `-c <clade_id>` 再跑一次。本段演示到此为止。

---

## 13 · HUMAnN v3.9 功能通路定量（环境名 humann4，实际版本 3.9）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 13 功能通路定量（HUMAnN v3.9，threads 16），**必须用绝对路径 -w**。」

**核心执行命令**（摘自 `scripts/13_bac_humann3.sh`）：
```bash
# 输入为 zcat 合并 R1+R2 的单文件（standard 模式，物种阈值 0.01%）
humann \
  --input temp/humann3/{sample}/{sample}_input.fq.gz \
  --output $TEMP_DIR \
  --output-basename {sample} \
  --threads 16 \
  --nucleotide-database $REPO/db/humann4/chocophlan \
  --protein-database $REPO/db/humann4/uniref \
  --o-log $TEMP_DIR/{sample}.log \
  --prescreen-threshold 0.01 \
  --memory-use minimum \
  --metaphlan-options "-t rel_ab --tmp_dir $TEMP_DIR" \
  --taxonomic-profile result/metaphlan4/{sample}/{sample}_profile.txt
```

**执行结果**：6/6 成功（重跑后），23851–31675 秒/样本（6.6–8.8h）。

**⚠️ 注意事项**：
- 本环境使用 **HUMAnN v3.9**（非 HUMAnN4），数据库为 **vOct22 CHOCOPhlAnSGB_202212**；config.py 打过补丁（vJun23→vOct22，0Install.sh:798-800）。
- **必须用绝对路径 -w**——相对路径 + cd 嵌套导致首次运行全失败（详见 `.claude/reviews/incident_20261005_humann_relpath.md`）。
- HUMAnN 双泳道加速 = 48.2h ÷ 25.4h ≈ 1.9×（仅 HUMAnN 步骤；全段墙钟 63.5h 含三线并行间隔）。

**执行点评**（主代理起草）：运算时间是最长步骤（瓶颈待 HUMAnN log 分阶段计时确认；脚本注释认为最大性能收益点是 bowtie2-build custom ChocoPhlAn DB，非 DIAMOND）；按脚本注释 `--speed-mode balanced` 可提速约 5–10×（standard 8–15h → balanced 1–2h/样本，代价：unstratified 社区通路精度损失 <5%，<1% 丰度物种的 stratified 通路丢失）。

---

## 13b · HUMAnN 多样本合并

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 13b HUMAnN 合并，生成项目级功能矩阵。」

**核心执行命令**（摘自 `scripts/13b_bac_humann3_merge.sh`）：
```bash
humann_join_tables --input $STAGE_DIR \
  --file_name pathabundance_relab.tsv \
  --output result/humann3/merged/pathabundance_relab.tsv
sed -i 's/_Abundance//g' result/humann3/merged/pathabundance_relab.tsv

humann_join_tables --input $STAGE_DIR \
  --file_name genefamilies_relab.tsv \
  --output result/humann3/merged/genefamilies_relab.tsv
sed -i 's/_Abundance-RPKs//g' result/humann3/merged/genefamilies_relab.tsv
```

**执行结果**：15 秒完成。pathabundance 524 行、genefamilies 995,738 行。

**执行点评**（主代理起草）：合并表只包含**非分层数据**（无 `|` 分层行）。

---

## 14 · Kraken2 k-mer 分类

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 14 Kraken2 分类（threads 16），完成后汇报各样本的分类检出率。」

**核心执行命令**（摘自 `scripts/14_bac_kraken2.sh`）：
```bash
kraken2 \
  --db $REPO/db/kraken2/pluspf \
  --threads 16 \
  --paired result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
           result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
  --use-names \
  --report-zero-counts \
  --confidence 0.1 \
  --report result/kraken2/{sample}/{sample}.report \
  --output - | gzip -c > result/kraken2/{sample}/{sample}.output.gz

# Bracken 丰度重估（S/G/P 三个层级各跑一次，此处以种级 S 为例）
bracken \
  -d $REPO/db/kraken2/pluspf \
  -i result/kraken2/{sample}/{sample}.report \
  -r 150 -l S -t 10 \
  -o result/kraken2/{sample}/bracken/{sample}_S.bracken \
  -w result/kraken2/{sample}/bracken/{sample}_S.report
```

**执行结果**：6/6 成功，380–585 秒/样本。

**执行点评**（主代理起草）：速度极快（k-mer 直接匹配，无比对）；数据库 77GB 常驻内存是 IO 瓶颈。

---

## 14b · Bracken 多样本合并

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 14b Kraken2/Bracken 合并，生成三个分类层级的多样本矩阵。」

**核心执行命令**（摘自 `scripts/14b_bac_kraken2_merge.sh`，combine_bracken_outputs.py 合并）：
```bash
# 对 S/G/P 三个层级分别运行（kraken2 环境自带工具 combine_bracken_outputs.py）
combine_bracken_outputs.py \
  --files ${BRACKEN_FILE_LIST} \
  --names ${SAMPLE_NAME_LIST} \
  -o result/kraken2/merged/bracken_S.tsv
# G/P 层级同参数再各跑一次，输出 bracken_G.tsv（属级）、bracken_P.tsv（门级）
```

**执行结果**：9 秒完成。门级 26 行、属级 414 行、种级 1055 行（含表头）。

**执行点评**（主代理起草）：三个层级均产出标准 TSV 矩阵（行=物种，列=样本）。

---

## 15c · sylph 超快物种分类

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 15c sylph 物种分类（threads 16），完成后汇报各样本检出的物种数。」

**核心执行命令**（摘自 `scripts/15c_bac_sylph.sh`）：
```bash
sylph profile \
  $REPO/db/sylph/gtdb-r220-c200-dbv1.syldb \
  -1 result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
  -2 result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
  -t 16 \
  -m 95 \
  -o result/sylph/{sample}/{sample}.sylph_profile.tsv

# sylph-tax 物种名标注（genome ID → MetaPhlAn 风格物种 profile）
sylph-tax taxprof result/sylph/{sample}/{sample}.sylph_profile.tsv \
  -t $REPO/db/sylph/gtdb_r220_metadata.tsv.gz \
  -o result/sylph/{sample}/{sample}_ \
  --overwrite
# taxprof 输出按 fastq 文件名命名，脚本随后统一 mv 为 {sample}.sylphmpa
```

**执行结果**：6/6 成功，228–338 秒/样本。

**执行点评**（主代理起草）：速度最快（MinHash sketch 比对，GTDB-R220 全库 110k+ 基因组）；内存仅需 ~15GB。

---

## 15d · sylph 多样本合并

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 15d sylph 合并，生成项目级物种矩阵。」

**核心执行命令**（摘自 `scripts/15d_bac_sylph_merge.sh`，sylph-tax merge 合并）：
```bash
# sylph 环境自带 sylph-tax merge 合并全部样本的 .sylphmpa
sylph-tax merge ${SYLPHMPA_FILE_LIST} \
  --column relative_abundance \
  -o result/sylph/merged/sylph_profile_merged.tsv
# 产出：sylph_profile_merged.tsv（物种级多样本相对丰度表）
```

**执行结果**：5 秒完成。1859 行 × 7 列。

**执行点评**（主代理起草）：秒级完成，无性能问题。

---

**⚠️ 冻结清单标注说明**：15（centrifuger）、15b（centrifuger merge）、15e（metax）标注为"opt-in 未运行"——本段演示未执行，留待后续按需运行。

**⚠️ 2×3 设计说明**：6 样本（treat ×3 / control ×3）仅作流程演示用途，统计功效有限，差异分析结果不作科学结论。


---

## ⚠️ 三界段空产出披露（质量审核 P0-5，2026-10-09）

### 真菌 MetaPhlAn4（72）空产出
5/6 样本的真核生物分类群 = 0（仅 UNCLASSIFIED 100.0%）。**这不是错误**——肠道
宏基因组样本的真菌载量通常极低（<0.1% reads），低于 MetaPhlAn4 的检出阈值。
仅 Sample4 检出 8 个真核分类群（S. cerevisiae 0.71% + S. boulardii）。

### 真菌 HUMAnN 通路（73）空产出
5/6 样本的真菌通路表只有表头（无数据行）。原因同上——HUMAnN 的分层输出中
没有真菌 clade 的通路行。仅 Sample4 有 185 行真菌通路（全部 S. cerevisiae）。

### 四种方法交叉验证一致
Kraken2、MetaPhlAn4、HUMAnN、PHF 四种方法在 Sample4 均检出显著的 S. cerevisiae
信号，在其他 5 个样本均接近零——**结果一致，非方法问题**。

### 科学口径
- "真菌分析结果为空"应表述为"真菌载量低于检测阈值"
- 后续统计分析时需注明：真菌维度的统计功效受限于极低的非零样本数

---

## 51 · MEGAHIT 病毒优化组装（meta-large 预设，≥1.5 kb contigs）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 51 病毒组装步骤（MEGAHIT meta-large，threads 16，**必须用绝对路径 -w**），完成后汇报各样本 contig 数与耗时。」

**核心执行命令**（摘自 `scripts/51_vir_megahit.sh`，`{sample}` 为样本变量）：

```bash
megahit -1 result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
        -2 result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
        -o result/virus/assembly/{sample}/_megahit_tmp \
        --out-prefix {sample} \
        -t 16 \
        --presets meta-large \
        --min-contig-len 1500 \
        --force
# 完成后 mv contigs → result/virus/assembly/{sample}/{sample}.contigs.fa，
# 并删除 _megahit_tmp（省 ~80% 磁盘）
```

**执行结果**（2026-10-07/08 实测，6/6 成功）：

| 样本 | 耗时 | contigs（≥1.5kb） | 大小 |
|---|---|---|---|
| Sample1 | 5710s（10-08 重跑） | 30,674 | 203M |
| Sample2 | 4905s | 22,991 | 173M |
| Sample10 | 7304s | 38,130 | 228M |
| Sample3 | 6542s | 32,194 | 239M |
| Sample4 | 5801s | 25,654 | 153M |
| Sample11 | 6604s | 32,683 | 202M |

4905–7304 秒/样本（1.4–2.0h），六样本串行合计约 10.2 小时；合计 contigs 约 1.2G。

**⚠️ 注意事项**：
- **重复启动事故（2026-10-07）**：LANE-V 与 LANE-F 的启动脚本各被执行一遍，Sample1 的 megahit 被同时启动两次（run_events.jsonl 03:24:07 / 03:24:31 两条启动记录）；两进程共用同一输出目录且 51 号传了 `--force`，中间文件互相覆盖导致 SIGSEGV（exit 245，信号 -11），浪费约 12 分钟；10-08 以完全相同参数干净重跑成功。详见 `.claude/reviews/incident_20261007_megahit_dup_launch.md`，并由此建立防重复启动规程（NOTES.md 质量审核 P0-3）与组装器互斥纪律（P0-6：全局同一时刻只允许一个 megahit/metaSPAdes 运行）。
- **必须用绝对路径 -w**（13 步 HUMAnN 相对路径事故的教训延续；51 起病毒/真菌泳道监控事件中 `-w` 全部为绝对路径）。

**执行点评**（主代理起草）：
- **运算时间**：4905–7304 秒/样本（16 线程 meta-large），串行合计约 10.2 小时。
- **输出文件**：每样本 1 个 contigs.fa（153–239M，2.3–3.8 万条 ≥1.5kb contigs），路径规范；_megahit_tmp 中间文件已删。
- **后续使用**：contigs 供 52 geNomad 与 53 VirSorter2 病毒鉴定（双工具交叉验证）。
- **加速空间**：多样本并行受组装器互斥纪律限制（P0-6），不可同时跑两个组装器；单样本 16 线程已接近收益拐点。
- **内存/硬盘**：megahit 峰值内存约 15G（事故档案实测 14.9G / 755G 机器）；磁盘净增约 1.2G。

---

## 52 · geNomad 病毒/质粒鉴定（end-to-end）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 52 geNomad 病毒/质粒鉴定（threads 16），完成后汇报各样本检出的病毒/质粒 contig 数。」

**核心执行命令**（摘自 `scripts/52_vir_genomad.sh`）：

```bash
genomad end-to-end \
    --cleanup \
    --threads 16 \
    --sensitivity 7.5 \
    --splits 4 \
    result/virus/assembly/{sample}/{sample}.contigs.fa \
    result/virus/genomad/{sample} \
    $REPO/db/genomad/genomad/genomad_db
```

**执行结果**（2026-10-09 实测，6/6 成功，1657–2222 秒/样本 = 28–37 分钟）：

| 样本 | 病毒 contigs | 质粒 contigs | 耗时 |
|---|---|---|---|
| Sample1 | 964 | 1,245 | 2048s |
| Sample2 | 654 | 808 | 1819s |
| Sample10 | 1,017 | 1,348 | 2222s |
| Sample3 | 1,151 | 1,062 | 2191s |
| Sample4 | 734 | 1,577 | 1657s |
| Sample11 | 1,058 | 1,149 | 1979s |

产出：`result/virus/genomad/<样本>/<样本>.contigs_summary/`（virus/plasmid summary + 分类注释）。

**执行点评**（主代理起草）：`--sensitivity 7.5` 为推荐区间（4.2–7.5）上限，灵敏度最高也最耗时；`--splits 4` 分块降内存，`--cleanup` 删中间文件。检出病毒 contigs 占组装总量约 2–4%，量级合理。与 53 VirSorter2 结果取并集（cat + rmdup）构成候选池供 54 号质检；最终病毒判定以**双工具交集为主结果**（严格），**并集仅作敏感性分析**（2026-10-11 用户approve口径；并集敏感性产物待补做）。

---

## 53 · VirSorter2 病毒序列预测（SIF 容器，env -i 隔离）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 53 VirSorter2 病毒预测（threads 16），完成后汇报各样本 final-viral-boundary 行数。」

**核心执行命令**（摘自 `scripts/53_vir_virsorter2.sh`，SIF 容器需 env -i 隔离宿主机 Python）：

```bash
# activate.sh 把 miniforge3/bin 加入 PATH，SIF 容器继承后会拾取宿主机
# pkg_resources（Python 版本不匹配）导致 DistributionNotFound；
# 解决：env -i 清空环境，只传必要变量（commit 2270c3b）
env -i \
    HOME="${HOME}" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" \
    APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-${HOME}/.apptainer}" \
    $REPO/envs/virsorter2/bin/virsorter run --use-conda-off \
    -w result/virus/virsorter2/{sample} \
    -i result/virus/assembly/{sample}/{sample}.contigs.fa \
    --db-dir $REPO/db/virsorter2 \
    --min-length 1000 \
    --include-groups "dsDNAphage,ssDNA,RNA,NCLDV,lavidaviridae" \
    -j 16 \
    --verbose
```

**执行结果**（2026-10-09/10 实测，6/6 成功，15879–21633 秒/样本 = 4.4–6.0h）：

| 样本 | boundary 行数 | score 行数 | 耗时 |
|---|---|---|---|
| Sample1 | 3,200 | 3,258 | 19729s |
| Sample2 | 2,308 | 2,346 | 17240s |
| Sample10 | 3,862 | 3,932 | 20006s |
| Sample3 | 3,590 | 3,635 | 21633s |
| Sample4 | 2,168 | 2,214 | 15879s |
| Sample11 | 3,534 | 3,589 | 20030s |

**⚠️ 注意事项**：
- **首轮 6 连败**（2026-10-09 06:37）：全部 exit 1、3–4 秒即退——宿主机 miniforge3 的 PATH 泄入 SIF 容器触发 pkg_resources 报错。修复（commit 2270c3b）：`env -i` 清空环境仅传 HOME/PATH/APPTAINER_CACHEDIR。修复验证含 3 次 Sample1 短测试（0–3 秒），正式重跑当日全部成功。质量审核 C1 已更正失败事件构成（virsorter2 ×6 非 ×2）。

**执行点评**（主代理起草）：病毒链最耗时步骤（比 51 组装本身更慢），瓶颈在跨 5 个病毒组（dsDNAphage/ssDNA/RNA/NCLDV/lavidaviridae）的 hallmark 搜索与评分；单样本内 16 线程已并行，样本级再并行需考虑 CPU 配额。产出 final-viral-boundary/score/combined.fa，与 52 geNomad 交叉验证。

---

## 71 · Kraken2+Bracken 真菌分类（PlusPF 全库，实为全群落结果）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 71 真菌 Kraken2 分类（PlusPF 库，threads 16），完成后汇报各样本真菌检出量。」

**核心执行命令**（摘自 `scripts/71_fun_kraken2_fungi.sh`，confidence/read-len 用脚本默认值）：

```bash
kraken2 \
    --db $REPO/db/kraken2/pluspf \
    --threads 16 \
    --paired result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
             result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
    --use-names \
    --report-zero-counts \
    --confidence 0.1 \
    --report result/fungi/kraken2/{sample}/{sample}.report \
    --output - | gzip -c > result/fungi/kraken2/{sample}/{sample}.output.gz

# Bracken 丰度重估（S/G/P 三个层级各跑一次，此处以种级 S 为例）
bracken \
    -d $REPO/db/kraken2/pluspf \
    -i result/fungi/kraken2/{sample}/{sample}.report \
    -r 150 -l S -t 10 \
    -o result/fungi/kraken2/{sample}/bracken/{sample}_S.bracken \
    -w result/fungi/kraken2/{sample}/bracken/{sample}_S.report
```

**执行结果**（2026-10-07 实测，6/6 成功，367–491 秒/样本 = 6–8 分钟）：

| 样本 | Fungi clade reads | 占比 | 耗时 |
|---|---|---|---|
| Sample1 | 523 | ~0.00% | 607/636s（重复启动跑两次，均成功） |
| Sample2 | 29 | ~0.00% | 369s |
| Sample10 | 27 | ~0.00% | 426s |
| Sample3 | 11 | ~0.00% | 442s |
| Sample4 | 261,370 | 0.67% | 367s |
| Sample11 | 8 | ~0.00% | 491s |

**⚠️ 注意事项**：
- **结果口径**：PlusPF 库覆盖细菌/古菌/病毒/真菌/原生动物，`.report` 与 bracken 表是**全群落**结果（种级 434–682 行，以细菌为主），真菌行需另行提取——目录名 `fungi/` 不代表只含真菌。
- Sample1 在 10-07 重复启动事故中被同时启动两次（两条记录均 exit 0），`output.gz` 经 `gzip -t` 核实完整。
- 真菌信号仅 Sample4 显著（Fungi clade 0.67%，bracken 种级 S. cerevisiae fraction 0.98%），其余 5 样本接近零——与上文"三界段空产出披露"的四方法交叉验证一致。

**执行点评**（主代理起草）：k-mer 直接匹配速度极快（77G 库常驻内存为 IO 瓶颈）；产出 report + output.gz + bracken×3 层级；后续可用于提取真菌 reads（78 号实际用了全量 reads，见 78 章披露）；多样本可并行；内存需容纳 77G 数据库。

---

## 72 · MetaPhlAn4 真核生物分析（复用步骤 11 mapout）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 72 真核 MetaPhlAn4 分析（threads 16），完成后汇报各样本真核分类群数。」

**核心执行命令**（摘自 `scripts/72_fun_metaphlan4_euk.sh`，实际走 mapout 复用分支）：

```bash
# 复用步骤 11 的 mapout 比对结果（跳过 bowtie2 重新比对）
bunzip2 -c temp/metaphlan4/{sample}/{sample}.mapout.bz2 \
    > temp/fungi/metaphlan4/{sample}/{sample}.mapout

metaphlan temp/fungi/metaphlan4/{sample}/{sample}.mapout \
    --input_type mapout \
    --db_dir $REPO/db/metaphlan4 \
    -x mpa_vOct22_CHOCOPhlAnSGB_202212 \
    --nproc 16 \
    --ignore_bacteria \
    --ignore_archaea \
    -o result/fungi/metaphlan4/{sample}/{sample}_profile.txt \
    --offline
```

**执行结果**（2026-10-07 实测，6/6 成功，78–99 秒/样本——mapout 复用免比对所以秒级）：5/6 样本仅 `UNCLASSIFIED 100.0%`（真核分类群 = 0，肠道宏基因组真菌载量低于检出阈值的**预期空产出**，非错误）；仅 Sample4 检出 8 个真核分类群（k__Eukaryota → s__Saccharomyces_cerevisiae → t__EUK4932，0.7096%）。详见上文"三界段空产出披露"。

**执行点评**（主代理起草）：`--ignore_bacteria --ignore_archaea` 只保留真核；复用 11 步 mapout 是本步快的关键（否则需 2h+/样本 重新比对）。空产出样本的 profile 文件仍正常落盘（UNCLASSIFIED 行），供 72b 合并。

---

## 72b · MetaPhlAn4 真核谱合并

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 72b 真核 MetaPhlAn4 合并，生成项目级真核丰度矩阵。」

**核心执行命令**（摘自 `scripts/72b_fun_metaphlan4_merge.sh`）：

```bash
merge_metaphlan_tables.py ${PROFILE_LIST} \
    | tail -n+2 \
    | sed '1 s/clade_name/ID/' \
    | sed '2i #metaphlan4' \
    > result/fungi/metaphlan4/merged/taxonomy.tsv
# 再由 grep 提取种级/属级 TSV（s__/g__），python3 生成 taxonomy_species.csv
```

**执行结果**（2026-10-11 实测，3 秒完成）：taxonomy.tsv 9 个数据行（UNCLASSIFIED + Sample4 的 8 个真核层级，其余 5 样本全 0）× 6 样本；taxonomy_species.tsv / taxonomy_genus.tsv 各 1 个数据行；taxonomy_species.csv 仅 1 行数据（Saccharomyces cerevisiae，仅 Sample4 非零）。

**执行点评**（主代理起草）：秒级完成；矩阵绝大部分为 0（5/6 样本无真核信号），统计分析需按披露口径注明真菌维度功效受限。

---

## 73 · HUMAnN 真菌通路提取（stratified 后处理）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 73 真菌 HUMAnN 通路提取，完成后汇报各样本真菌通路行数。」

**核心执行命令**（摘自 `scripts/73_fun_humann4_fungi.sh`，无 conda 环境，纯 grep/awk 后处理）：

```bash
# ChocoPhlAn v201901_v31 中真菌属名列表（基于数据库实际内容验证）
FUNGI_PATTERN="g__(Candida|Aspergillus|Saccharomyces|Malassezia|Cryptococcus|Pichia|Nakaseomyces|Pneumocystis|Clavispora|Lodderomyces|Yarrowia|Cutaneotrichosporon|Trichosporon|Debaryomyces|Kluyveromyces|Rhodotorula|Fusarium|Penicillium|Cladosporium|Alternaria|Mucor|Rhizopus)"

{
    head -1 result/humann3/{sample}/stratified/{sample}_pathabundance_relab_stratified.tsv
    grep -E "\|${FUNGI_PATTERN}\." \
        result/humann3/{sample}/stratified/{sample}_pathabundance_relab_stratified.tsv || true
} > result/fungi/humann4/{sample}/{sample}_fungi_pathabundance.tsv
```

**执行结果**（2026-10-09 实测，6/6 成功，每样本 0–1 秒）：5/6 样本 0 数据行（仅表头，预期空产出）；Sample4 提取到 **184 条**真菌分层通路（全部 S. cerevisiae，文件 185 行含表头），与上文披露一致。

**执行点评**（主代理起草）：过滤键是 `g__<属名>.`（ChocoPhlAn stratified 行的命名格式）而非 `|k__Eukaryota`——原始过滤条件曾写错，脚本注释已记录修正。ChocoPhlAn 仅覆盖约 70+ 种临床常见肠道真菌；全谱真菌定量需 75 FunOMIC（本演示未运行，classification 文件缺失时自动跳过）。

---

## 74e · PHF 肠道真菌丰度定量（Yan et al. 2024 Cell，Singular+Escrow）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 74e PHF 肠道真菌定量（threads 16），完成后汇报各样本检出的真菌簇数。」

**核心执行命令**（摘自 `scripts/74e_fun_phf_profiler.sh`，五步 Bowtie2 过滤链 + GPA.py）：

```bash
# Step 1: 比对真菌基因集 → 提取真菌 reads
bowtie2 --end-to-end --mm --fast --no-head --no-unal --no-sq \
    -U {IN} -x $REPO/db/gut_fungi_db/bwt.index.gut_fungi_geneset \
    -S /dev/null --al-gz step1_fungi.fq.gz -p 16

# Step 2–4: 依次过滤人类（bwt.index.human_chm13v2）/ 细菌（bwt.index.uhgg）/
#           rRNA（bwt.index.fungi_target）reads（同参数，改用 --un-gz）

# Step 5: 重比对真菌基因集，-k 1000 允许多重比对（Escrow reads）
bowtie2 --end-to-end --mm --fast --no-head --no-unal --no-sq \
    -U step4_rmrRNA.fq.gz -x $REPO/db/gut_fungi_db/bwt.index.gut_fungi_geneset \
    -S step5_fungi.sam -k 1000 -p 16

# Step 6: GPA.py Singular+Escrow 丰度计算
python $REPO/db/gut_fungi_db/GPA.py -i step5_fungi.sam -o {sample}.rc -s 0.95
```

**执行结果**（2026-10-09 实测，6/6 成功，488–657 秒/样本 = 8–11 分钟；Sample1 首跑 885 秒含三线并行负载）：

| 样本 | 真菌簇数 | 耗时 |
|---|---|---|
| Sample1 | 43 | 885s |
| Sample2 | 31 | 488s |
| Sample10 | 33 | 539s |
| Sample3 | 23 | 657s |
| Sample4 | **72**（最高簇 c86 = S. cerevisiae，92.57%） | 548s |
| Sample11 | 25 | 585s |

产出：`result/fungi/phf_profiler/<样本>/<样本>.rc`（cluster<TAB>value，**无表头行**）+ `.rc.cmd.log`。

**执行点评**（主代理起草）：五次 bowtie2 `--fast` 过滤链设计合理（真菌基因集 → 去人 → 去细菌 → 去 rRNA → -k 1000 重比对），Singular（唯一比对）直接计数 + Escrow（多重比对）按比例分配是 Cell 187 原方法；tmp 目录用后即删；`.rc` 无表头这一格式约定后来在 74f 踩坑（见下章）。Sample4 簇数（72）与其 S. cerevisiae 信号一致。

---

## 74f · PHF 真菌丰度聚合（.rc → 合并矩阵 + 分类表 join）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 74f PHF 聚合，生成项目级真菌簇丰度矩阵。」

**核心执行命令**（摘自 `scripts/74f_fun_phf_aggregate.sh`，Python 外连接 + 分类表左连接）：

```bash
find result/fungi/phf_profiler -maxdepth 2 -name '*.rc' -size +0c | sort

python3 - merged_abundance.tsv merged_abundance_with_taxonomy.tsv \
        $REPO/db/gut_fungi_db/db.fungi.taxonomy.tsv ${RC_FILES} << 'PY'
# .rc 格式：cluster<TAB>value —— 无表头行（关键修复点，见 ⚠️）
for line in lines:
    parts = line.split('\t')
    d[parts[0]] = parts[1]        # 全部行按数据解析（外连接，缺失补 0）
PY
```

**执行结果**（2026-10-09 实测）：首次运行 0 秒产出（后确认数据损坏）；修复后 `--force` 重跑 1 秒完成。merged_abundance.tsv = **91 簇 × 6 样本**；merged_abundance_with_taxonomy.tsv 追加 7 级分类列（Phylum→species）。

**⚠️ 注意事项**：
- **表头误判 bug（质量审核 P0 抓出，commit 351952d 修复）**：旧代码把 `.rc` 第一行**数据**当表头跳过，导致每个样本的最高丰度簇被丢掉（例：Sample4 c86 S. cerevisiae 92.57% → 0）。修复：`.rc` 按无表头格式解析全部行；修复后 `--force` 重跑，矩阵恢复。内联修复无独立事故档案（NOTES.md 事故索引有录）。

**执行点评**（主代理起草）：秒级完成；教训——自定义文本格式必须显式定义并文档化表头约定，读取端/写入端应有一对一致性测试覆盖。

---

## 78 · MEGAHIT 真菌组装（meta-sensitive，≥1 kb）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 78 真菌组装步骤（MEGAHIT meta-sensitive，threads 16），完成后汇报各样本 contig 数。」

**核心执行命令**（摘自 `scripts/78_fun_megahit.sh`）：

```bash
megahit \
    -1 result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
    -2 result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
    -o result/fungi/assembly/{sample}/_megahit_tmp \
    -t 16 \
    -m 0.9 \
    --presets meta-sensitive \
    --min-contig-len 1000
# 完成后 mv final.contigs.fa → result/fungi/assembly/{sample}/{sample}.contigs.fa
# （megahit log 一并保留为 {sample}.megahit.log，_megahit_tmp 删除）
```

**执行结果**（2026-10-09 实测，6/6 成功，5505–8442 秒/样本 = 1.5–2.3h）：

| 样本 | 耗时 | contigs（≥1kb） | 大小 |
|---|---|---|---|
| Sample1 | 6262s | 46,609 | 225M |
| Sample2 | 5505s | 36,446 | 191M |
| Sample10 | 8442s | 61,534 | 262M |
| Sample3 | 7454s | 46,033 | 260M |
| Sample4 | 6703s | 40,728 | 175M |
| Sample11 | 7360s | 50,907 | 228M |

**⚠️ 注意事项**：
- **输入口径披露**：本步用**全部清洁 reads（全群落）**组装，非仅真菌 reads——脚本内提示可先用 71/72 提取真菌 reads 提高纯度，但本次演示未提取。所谓"真菌组装"实为全群落 meta-sensitive 组装（contigs 4.6–6.2 万条，多于 51 号的 meta-large + 1.5kb 组合）。科学口径见 NOTES.md"真菌功能注释科学口径披露"。

**执行点评**（主代理起草）：meta-sensitive + 1kb 下限是为低丰度真菌覆盖付出的代价（更慢、更多短 contig）；下游 79 Eukfinder 从中筛真核 contig；受组装器互斥纪律约束不可与其他 megahit 并行；`-m 0.9` 为内存比例上限，实际峰值远低于此。

---

## 79 · Eukfinder 真核 contig 识别（Centrifuge + PLAST）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 79 Eukfinder 真核识别（threads 16），完成后汇报各样本真核 contig 数。」

**核心执行命令**（摘自 `scripts/79_fun_eukfinder.sh`；cd 到输出目录运行，eukfinder 日志写 cwd）：

```bash
# 运行前置：ETE3 NCBITaxa 一次性初始化（~/.etetoolkit/taxa.sqlite，
# 在 /tmp 下执行避免 taxdump.tar.gz 污染项目目录）
eukfinder long_seqs \
    -l result/fungi/assembly/{sample}/{sample}.contigs.fa \
    -o {sample} \
    -n 16 \
    --mhlen 200 \
    --cdb $REPO/db/eukfinder_db/centrifuge_db/EukDB \
    -p $REPO/db/eukfinder_db/PlastDB.fasta \
    -m $REPO/db/eukfinder_db/PlastDB_map.txt
```

**执行结果**（2026-10-10 实测，6/6 成功，7938–13009 秒/样本 = 2.2–3.6h）：

| 样本 | Euk contigs | 耗时 |
|---|---|---|
| Sample1 | 29 | 11489s |
| Sample2 | 50 | 9895s |
| Sample10 | 18 | 13009s |
| Sample3 | 11 | 11990s |
| Sample4 | **3,270** | 7938s |
| Sample11 | 11 | 10044s |

产出：`Eukfinder_results/<样本>.{Euk,Bact,Arch,EUnk,Unk}.fasta` 五分组（细菌占绝对多数，如 Sample1 Bact 40,911 / Sample4 Bact 31,857）。Centrifuge DB 为自建 EukDB（4 个 .cf，`db/eukfinder_db/centrifuge_db/`），PLAST 蛋白级分类已启用。

**执行点评**（主代理起草）：真菌链最耗时步骤（Centrifuge 全库 k-mer 分类每条 contig）；Sample4 的 3,270 条真核 contig 与其 S. cerevisiae 强信号一致，其余样本 11–50 条为噪声水平；下游 79b 只消费 `.Euk.fasta`；多样本并行可线性提速（非组装器）。

---

## 79b · Tiara + BUSCO 真核候选二次质控（VEBA 思路）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 79b 真核候选二次质控（Tiara 域确认 + BUSCO 完整度），完成后汇报各样本质控结果。」

**核心执行命令**（摘自 `scripts/79b_fun_veba_qc.sh`，参考 VEBA binning-eukaryotic 质控思路重新实现）：

```bash
# 步骤1: 长度预过滤（Tiara 官方不建议对 <1000bp 序列分类）
seqkit seq -m 1000 \
    result/fungi/eukfinder/{sample}/Eukfinder_results/{sample}.Euk.fasta \
    -o result/fungi/veba_qc/{sample}/{sample}.euk_filtered.fasta

# 步骤2: Tiara 域二次确认
tiara -i {sample}.euk_filtered.fasta \
      -o {sample}.tiara_classification.txt \
      -m 1000 -t 16 \
      --to_fasta euk --probabilities

# 步骤3: BUSCO 谱系特异完整度/污染度评估
busco -i eukarya_{sample}.euk_filtered.fasta -o {sample}.busco \
      -m genome --auto-lineage-euk -c 16 -f \
      --download_path $REPO/db/busco_downloads
```

**执行结果**（2026-10-10 实测，6/6 完成）：**5/6 空产出（预期行为，非失败）**——Sample3/11 空在 Tiara 域确认阶段（各 13 秒），Sample1/2/10 空在 BUSCO 阶段（30–55 秒，序列量过低无法评估）；均落 `.veba_qc_empty.flag` 正常退出。仅 **Sample4** 走完全程（362 秒），产出唯一一份 `veba_qc_summary.tsv`：

```
sample    lineage                    complete_pct  duplicated_pct  missing_pct
Sample4   saccharomycetaceae_odb12.2  75.2          0.5             14.7
```

**执行点评**（主代理起草）：空结果与上游信号一致（5 样本真核 contig 本就只有 11–50 条）；Sample4 完整度 75.2% / 重复 0.5%，佐证其 S. cerevisiae contig 集已接近基因组级组装质量。empty.flag（跑了没货）与 summary.tsv（有货）双标志设计正确区分了"未运行"与"预期空产出"，是低深度样本处理的正确姿势。

---

（后续步骤章节随执行增量添加，格式同上：启动提示词 → 核心命令 → 执行结果 → 质量审核点评）
