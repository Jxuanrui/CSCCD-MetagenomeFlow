# CSCCD-MetagenomeFlow 全链演示走查（Project_demo）

> **启动本项目（复制给 AI 助手）**：
> 「请继续执行 CSCCD-MetagenomeFlow 演示项目 Project_demo 的下一步骤（模式一、
> `MGX_MONITOR=1` 开启监控），完成后用 `run_monitor.py --text` 采集监控快照，
> 同步更新 walkthrough.md 的执行结果，并请质量审核对本步结果做点评。」

| 事项 | 内容 |
|---|---|
| 数据 | 6 样本（treat=Sample<N>/2/10，control=Sample<N>/4/11），自 Project01 只读拷出，62G，与源逐字节一致 |
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
| Sample<N> | treat | 84,563,768 | 84,560,980 | 100.0% | 97.9% | 45.8% |
| Sample<N> | treat | 95,234,276 | 95,229,224 | 100.0% | 97.8% | 45.5% |
| Sample<N> | control | 104,606,294 | 104,602,366 | 100.0% | 98.0% | 45.1% |
| Sample<N> | treat | 84,158,864 | 84,155,472 | 100.0% | 98.2% | 43.1% |
| Sample<N> | control | 111,775,904 | 111,770,134 | 100.0% | 98.2% | 43.4% |
| Sample<N> | control | 78,708,096 | 78,561,970 | 99.8% | 97.2% | 40.6% |

产出：`result/fastp/<样本>/`（清洁 reads 双端 ~4.4–5.6G/样本 + JSON/HTML 报告）；监控事件 12 条（6 开始 + 6 终态 ✓）全部成对落盘。

**质量审核点评**（执行方按五维度起草，预处理段关口由质量审核复核）：
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
| Sample<N> | treat | 42,280,490 | 13,233 | 0.031% |
| Sample<N> | treat | 42,077,736 | 12,832 | 0.030% |
| Sample<N> | treat | 47,614,612 | 12,525 | 0.026% |
| Sample<N> | control | 55,885,067 | 15,935 | 0.029% |
| Sample<N> | control | 39,280,985 | 75,854 | 0.193% |
| Sample<N> | control | 52,301,183 | 22,831 | 0.044% |

计时：Sample<N> 131min、Sample<N> 143min、Sample<N> 159min、Sample<N> 129min、Sample<N> 171min、Sample<N> 121min（合计 14.3 小时）。产出：`result/kneaddata/<样本>/`（清洁 reads 双端 + orphan + 污染 reads + log/stats）。

**执行点评**（执行方起草）：（执行方按五维度起草，预处理段关口由质量审核复核；HEAD: 050f1c6）:
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
| Sample<N> | 41,962,400 | 41,962,400 | 0 | 363s |
| Sample<N> | 41,751,756 | 41,751,756 | 0 | 353s |
| Sample<N> | 46,906,471 | 46,906,471 | 0 | 400s |
| Sample<N> | 55,411,039 | 55,411,039 | 0 | 471s |
| Sample<N> | 38,900,065 | 38,900,065 | 0 | 338s |
| Sample<N> | 51,631,260 | 51,631,260 | 0 | 438s |

产出：新增 `_1.kneaddata.fastq.gz` / `_2.kneaddata.fastq.gz`（严格配对新文件）；`_kneaddata_raw` 原件保留（是 02 的哨兵，不可删）；哨兵 `.pair_repair_done.txt` ✓。磁盘额外增 ~58G。

**执行点评**（执行方起草）：（执行方按五维度起草，预处理段关口由质量审核复核；HEAD: 050f1c6）:
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

**执行点评**（执行方起草）：运算时间合理（bowtie2 比对全库索引为瓶颈）；产出标准 MetaPhlAn4 格式。

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

**执行点评**（执行方起草）：秒级完成，无性能问题。

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

**执行点评**（执行方起草）：默认只做检测（--print_clades_only），要得到菌株系统发育树需带 `-c <clade_id>` 再跑一次。本段演示到此为止。

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
- **必须用绝对路径 -w**——相对路径 + cd 嵌套导致首次运行全失败（详见 `.CLI tool/reviews/incident_20261005_humann_relpath.md`）。
- HUMAnN 双泳道加速 = 48.2h ÷ 25.4h ≈ 1.9×（仅 HUMAnN 步骤；全段墙钟 63.5h 含三线并行间隔）。

**执行点评**（执行方起草）：运算时间是最长步骤（瓶颈待 HUMAnN log 分阶段计时确认；脚本注释认为最大性能收益点是 bowtie2-build custom ChocoPhlAn DB，非 DIAMOND）；按脚本注释 `--speed-mode balanced` 可提速约 5–10×（standard 8–15h → balanced 1–2h/样本，代价：unstratified 社区通路精度损失 <5%，<1% 丰度物种的 stratified 通路丢失）。

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

**执行点评**（执行方起草）：合并表只包含**非分层数据**（无 `|` 分层行）。

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

**执行点评**（执行方起草）：速度极快（k-mer 直接匹配，无比对）；数据库 77GB 常驻内存是 IO 瓶颈。

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

**执行点评**（执行方起草）：三个层级均产出标准 TSV 矩阵（行=物种，列=样本）。

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

**执行点评**（执行方起草）：速度最快（MinHash sketch 比对，GTDB-R220 全库 110k+ 基因组）；内存仅需 ~15GB。

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

**执行点评**（执行方起草）：秒级完成，无性能问题。

---

**⚠️ 冻结清单标注说明**：15（centrifuger）、15b（centrifuger merge）、15e（metax）标注为"opt-in 未运行"——本段演示未执行，留待后续按需运行。

**⚠️ 2×3 设计说明**：6 样本（treat ×3 / control ×3）仅作流程演示用途，统计功效有限，差异分析结果不作科学结论。


---

## ⚠️ 三界段空产出披露（质量审核 P0-5，2026-10-09）

### 真菌 MetaPhlAn4（72）空产出
5/6 样本的真核生物分类群 = 0（仅 UNCLASSIFIED 100.0%）。**这不是错误**——肠道
宏基因组样本的真菌载量通常极低（<0.1% reads），低于 MetaPhlAn4 的检出阈值。
仅 Sample<N> 检出 8 个真核分类群（S. cerevisiae 0.71% + S. boulardii）。

### 真菌 HUMAnN 通路（73）空产出
5/6 样本的真菌通路表只有表头（无数据行）。原因同上——HUMAnN 的分层输出中
没有真菌 clade 的通路行。仅 Sample<N> 有 185 行真菌通路（全部 S. cerevisiae）。

### 四种方法交叉验证一致
Kraken2、MetaPhlAn4、HUMAnN、PHF 四种方法在 Sample<N> 均检出显著的 S. cerevisiae
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
| Sample<N> | 5710s（10-08 重跑） | 30,674 | 203M |
| Sample<N> | 4905s | 22,991 | 173M |
| Sample<N> | 7304s | 38,130 | 228M |
| Sample<N> | 6542s | 32,194 | 239M |
| Sample<N> | 5801s | 25,654 | 153M |
| Sample<N> | 6604s | 32,683 | 202M |

4905–7304 秒/样本（1.4–2.0h），六样本串行合计约 10.2 小时；合计 contigs 约 1.2G。

**⚠️ 注意事项**：
- **重复启动事故（2026-10-07）**：LANE-V 与 LANE-F 的启动脚本各被执行一遍，Sample<N> 的 megahit 被同时启动两次（run_events.jsonl 03:24:07 / 03:24:31 两条启动记录）；两进程共用同一输出目录且 51 号传了 `--force`，中间文件互相覆盖导致 SIGSEGV（exit 245，信号 -11），浪费约 12 分钟；10-08 以完全相同参数干净重跑成功。详见 `.CLI tool/reviews/incident_20261007_megahit_dup_launch.md`，并由此建立防重复启动规程（NOTES.md 质量审核 P0-3）与组装器互斥纪律（P0-6：全局同一时刻只允许一个 megahit/metaSPAdes 运行）。
- **必须用绝对路径 -w**（13 步 HUMAnN 相对路径事故的教训延续；51 起病毒/真菌泳道监控事件中 `-w` 全部为绝对路径）。

**执行点评**（执行方起草）：
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
| Sample<N> | 964 | 1,245 | 2048s |
| Sample<N> | 654 | 808 | 1819s |
| Sample<N> | 1,017 | 1,348 | 2222s |
| Sample<N> | 1,151 | 1,062 | 2191s |
| Sample<N> | 734 | 1,577 | 1657s |
| Sample<N> | 1,058 | 1,149 | 1979s |

产出：`result/virus/genomad/<样本>/<样本>.contigs_summary/`（virus/plasmid summary + 分类注释）。

**执行点评**（执行方起草）：`--sensitivity 7.5` 为推荐区间（4.2–7.5）上限，灵敏度最高也最耗时；`--splits 4` 分块降内存，`--cleanup` 删中间文件。检出病毒 contigs 占组装总量约 2–4%，量级合理。与 53 VirSorter2 结果取并集（cat + rmdup）构成候选池供 54 号质检；最终病毒判定以**双工具交集为主结果**（严格），**并集仅作敏感性分析**（2026-10-11 用户拍板口径；并集敏感性产物待补做）。

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
| Sample<N> | 3,200 | 3,258 | 19729s |
| Sample<N> | 2,308 | 2,346 | 17240s |
| Sample<N> | 3,862 | 3,932 | 20006s |
| Sample<N> | 3,590 | 3,635 | 21633s |
| Sample<N> | 2,168 | 2,214 | 15879s |
| Sample<N> | 3,534 | 3,589 | 20030s |

**⚠️ 注意事项**：
- **首轮 6 连败**（2026-10-09 06:37）：全部 exit 1、3–4 秒即退——宿主机 miniforge3 的 PATH 泄入 SIF 容器触发 pkg_resources 报错。修复（commit 2270c3b）：`env -i` 清空环境仅传 HOME/PATH/APPTAINER_CACHEDIR。修复验证含 3 次 Sample<N> 短测试（0–3 秒），正式重跑当日全部成功。质量审核 C1 已更正失败事件构成（virsorter2 ×6 非 ×2）。

**执行点评**（执行方起草）：病毒链最耗时步骤（比 51 组装本身更慢），瓶颈在跨 5 个病毒组（dsDNAphage/ssDNA/RNA/NCLDV/lavidaviridae）的 hallmark 搜索与评分；单样本内 16 线程已并行，样本级再并行需考虑 CPU 配额。产出 final-viral-boundary/score/combined.fa，与 52 geNomad 交叉验证。

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
| Sample<N> | 523 | ~0.00% | 607/636s（重复启动跑两次，均成功） |
| Sample<N> | 29 | ~0.00% | 369s |
| Sample<N> | 27 | ~0.00% | 426s |
| Sample<N> | 11 | ~0.00% | 442s |
| Sample<N> | 261,370 | 0.67% | 367s |
| Sample<N> | 8 | ~0.00% | 491s |

**⚠️ 注意事项**：
- **结果口径**：PlusPF 库覆盖细菌/古菌/病毒/真菌/原生动物，`.report` 与 bracken 表是**全群落**结果（种级 434–682 行，以细菌为主），真菌行需另行提取——目录名 `fungi/` 不代表只含真菌。
- Sample<N> 在 10-07 重复启动事故中被同时启动两次（两条记录均 exit 0），`output.gz` 经 `gzip -t` 核实完整。
- 真菌信号仅 Sample<N> 显著（Fungi clade 0.67%，bracken 种级 S. cerevisiae fraction 0.98%），其余 5 样本接近零——与上文"三界段空产出披露"的四方法交叉验证一致。

**执行点评**（执行方起草）：k-mer 直接匹配速度极快（77G 库常驻内存为 IO 瓶颈）；产出 report + output.gz + bracken×3 层级；后续可用于提取真菌 reads（78 号实际用了全量 reads，见 78 章披露）；多样本可并行；内存需容纳 77G 数据库。

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

**执行结果**（2026-10-07 实测，6/6 成功，78–99 秒/样本——mapout 复用免比对所以秒级）：5/6 样本仅 `UNCLASSIFIED 100.0%`（真核分类群 = 0，肠道宏基因组真菌载量低于检出阈值的**预期空产出**，非错误）；仅 Sample<N> 检出 8 个真核分类群（k__Eukaryota → s__Saccharomyces_cerevisiae → t__EUK4932，0.7096%）。详见上文"三界段空产出披露"。

**执行点评**（执行方起草）：`--ignore_bacteria --ignore_archaea` 只保留真核；复用 11 步 mapout 是本步快的关键（否则需 2h+/样本 重新比对）。空产出样本的 profile 文件仍正常落盘（UNCLASSIFIED 行），供 72b 合并。

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

**执行结果**（2026-10-11 实测，3 秒完成）：taxonomy.tsv 9 个数据行（UNCLASSIFIED + Sample<N> 的 8 个真核层级，其余 5 样本全 0）× 6 样本；taxonomy_species.tsv / taxonomy_genus.tsv 各 1 个数据行；taxonomy_species.csv 仅 1 行数据（Saccharomyces cerevisiae，仅 Sample<N> 非零）。

**执行点评**（执行方起草）：秒级完成；矩阵绝大部分为 0（5/6 样本无真核信号），统计分析需按披露口径注明真菌维度功效受限。

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

**执行结果**（2026-10-09 实测，6/6 成功，每样本 0–1 秒）：5/6 样本 0 数据行（仅表头，预期空产出）；Sample<N> 提取到 **184 条**真菌分层通路（全部 S. cerevisiae，文件 185 行含表头），与上文披露一致。

**执行点评**（执行方起草）：过滤键是 `g__<属名>.`（ChocoPhlAn stratified 行的命名格式）而非 `|k__Eukaryota`——原始过滤条件曾写错，脚本注释已记录修正。ChocoPhlAn 仅覆盖约 70+ 种临床常见肠道真菌；全谱真菌定量需 75 FunOMIC（本演示未运行，classification 文件缺失时自动跳过）。

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

**执行结果**（2026-10-09 实测，6/6 成功，488–657 秒/样本 = 8–11 分钟；Sample<N> 首跑 885 秒含三线并行负载）：

| 样本 | 真菌簇数 | 耗时 |
|---|---|---|
| Sample<N> | 43 | 885s |
| Sample<N> | 31 | 488s |
| Sample<N> | 33 | 539s |
| Sample<N> | 23 | 657s |
| Sample<N> | **72**（最高簇 c86 = S. cerevisiae，92.57%） | 548s |
| Sample<N> | 25 | 585s |

产出：`result/fungi/phf_profiler/<样本>/<样本>.rc`（cluster<TAB>value，**无表头行**）+ `.rc.cmd.log`。

**执行点评**（执行方起草）：五次 bowtie2 `--fast` 过滤链设计合理（真菌基因集 → 去人 → 去细菌 → 去 rRNA → -k 1000 重比对），Singular（唯一比对）直接计数 + Escrow（多重比对）按比例分配是 Cell 187 原方法；tmp 目录用后即删；`.rc` 无表头这一格式约定后来在 74f 踩坑（见下章）。Sample<N> 簇数（72）与其 S. cerevisiae 信号一致。

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
- **表头误判 bug（质量审核 P0 抓出，commit 351952d 修复）**：旧代码把 `.rc` 第一行**数据**当表头跳过，导致每个样本的最高丰度簇被丢掉（例：Sample<N> c86 S. cerevisiae 92.57% → 0）。修复：`.rc` 按无表头格式解析全部行；修复后 `--force` 重跑，矩阵恢复。内联修复无独立事故档案（NOTES.md 事故索引有录）。

**执行点评**（执行方起草）：秒级完成；教训——自定义文本格式必须显式定义并文档化表头约定，读取端/写入端应有一对一致性测试覆盖。

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
| Sample<N> | 6262s | 46,609 | 225M |
| Sample<N> | 5505s | 36,446 | 191M |
| Sample<N> | 8442s | 61,534 | 262M |
| Sample<N> | 7454s | 46,033 | 260M |
| Sample<N> | 6703s | 40,728 | 175M |
| Sample<N> | 7360s | 50,907 | 228M |

**⚠️ 注意事项**：
- **输入口径披露**：本步用**全部清洁 reads（全群落）**组装，非仅真菌 reads——脚本内提示可先用 71/72 提取真菌 reads 提高纯度，但本次演示未提取。所谓"真菌组装"实为全群落 meta-sensitive 组装（contigs 4.6–6.2 万条，多于 51 号的 meta-large + 1.5kb 组合）。科学口径见 NOTES.md"真菌功能注释科学口径披露"。

**执行点评**（执行方起草）：meta-sensitive + 1kb 下限是为低丰度真菌覆盖付出的代价（更慢、更多短 contig）；下游 79 Eukfinder 从中筛真核 contig；受组装器互斥纪律约束不可与其他 megahit 并行；`-m 0.9` 为内存比例上限，实际峰值远低于此。

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
| Sample<N> | 29 | 11489s |
| Sample<N> | 50 | 9895s |
| Sample<N> | 18 | 13009s |
| Sample<N> | 11 | 11990s |
| Sample<N> | **3,270** | 7938s |
| Sample<N> | 11 | 10044s |

产出：`Eukfinder_results/<样本>.{Euk,Bact,Arch,EUnk,Unk}.fasta` 五分组（细菌占绝对多数，如 Sample<N> Bact 40,911 / Sample<N> Bact 31,857）。Centrifuge DB 为自建 EukDB（4 个 .cf，`db/eukfinder_db/centrifuge_db/`），PLAST 蛋白级分类已启用。

**执行点评**（执行方起草）：真菌链最耗时步骤（Centrifuge 全库 k-mer 分类每条 contig）；Sample<N> 的 3,270 条真核 contig 与其 S. cerevisiae 强信号一致，其余样本 11–50 条为噪声水平；下游 79b 只消费 `.Euk.fasta`；多样本并行可线性提速（非组装器）。

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

**执行结果**（2026-10-10 实测，6/6 完成）：**5/6 空产出（预期行为，非失败）**——Sample<N>/11 空在 Tiara 域确认阶段（各 13 秒），Sample<N>/2/10 空在 BUSCO 阶段（30–55 秒，序列量过低无法评估）；均落 `.veba_qc_empty.flag` 正常退出。仅 **Sample<N>** 走完全程（362 秒），产出唯一一份 `veba_qc_summary.tsv`：

```
sample    lineage                    complete_pct  duplicated_pct  missing_pct
Sample<N>   saccharomycetaceae_odb12.2  75.2          0.5             14.7
```

**执行点评**（执行方起草）：空结果与上游信号一致（5 样本真核 contig 本就只有 11–50 条）；Sample<N> 完整度 75.2% / 重复 0.5%，佐证其 S. cerevisiae contig 集已接近基因组级组装质量。empty.flag（跑了没货）与 summary.tsv（有货）双标志设计正确区分了"未运行"与"预期空产出"，是低深度样本处理的正确姿势。

---

（后续步骤章节随执行增量添加，格式同上：启动提示词 → 核心命令 → 执行结果 → 质量审核点评）

<!-- ======== 以下章节为 CP3 收尾批次补写（2026-10-18，五路取证草稿单人合稿）======== -->

<!-- 批次①片段：步骤 16-31e（细菌组装/基因目录/目录级注释链）。
     证据来源：scripts/NN_*.sh 源码（参数逐条核实）、Project/Project_demo/result/ 产物计数、
     logs/run_events.jsonl 事件流（16-31e 全部 exit 0，无失败记录）。
     拼接位置：15d 之后、⚠️ 三界段空产出披露章节之前。
     另：24b_bac_card_summary 未在演示中执行（无事件、无产物），章节留白待补，特此记录。 -->

## 16 · MEGAHIT 细菌从头组装（meta-large 预设，≥500 bp contigs，通用目录口径）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 16 细菌组装步骤（MEGAHIT meta-large，threads 16），完成后汇报各样本 contig 数、总碱基与 N50。」

**核心执行命令**（摘自 `scripts/16_bac_megahit.sh`，`{sample}` 为样本变量）：

```bash
megahit \
    -1 result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
    -2 result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
    -o result/assembly/megahit/{sample}/_megahit_tmp \
    -t 16 \
    -m 0.9 \
    --presets meta-large \
    --min-contig-len 500
# 完成后 mv final.contigs.fa → result/assembly/megahit/{sample}/{sample}.contigs.fa，
# 保留 log 副本，rm -rf _megahit_tmp（intermediate_contigs 占 >80% 磁盘）
```

**执行结果**（2026-10-10 实测，6/6 成功，4606–7266 秒/样本，串行合计约 10.0 小时）：

| 样本 | 耗时 | contigs（≥500bp） | 总碱基 (bp) | N50 | 文件大小 |
|---|---|---|---|---|---|
| Sample<N> | 5583s | 110,328 | 274,422,780 | 7,589 | 267M |
| Sample<N> | 4606s | 91,223 | 233,544,095 | 9,986 | 227M |
| Sample<N> | 7266s | 151,240 | 327,405,081 | 5,336 | 319M |
| Sample<N> | 6513s | 103,211 | 305,791,075 | 11,354 | 296M |
| Sample<N> | 5608s | 108,879 | 223,081,556 | 4,852 | 218M |
| Sample<N> | 6523s | 131,738 | 287,583,301 | 5,681 | 280M |

k 值阶梯以 megahit.log 实录为准：`k list: 27,37,...,127`（meta-large 按读长自动截断，非脚本头注释里的 21–141 通版阶梯）。脚本内置 kneaddata trailing-garbage 检测（gzip -t 不过则静默重压缩后再组装）。

**执行点评**（执行方起草）：
- **运算时间**：4606–7266 秒/样本（16 线程、-m 0.9），串行合计 36,099 秒 ≈ 10.0 小时；为细菌泳道第一瓶颈。
- **输出文件**：每样本 1 个 `{sample}.contigs.fa`（218–319M，合计约 1.6G）+ megahit.log；_megahit_tmp 中间目录已删。
- **后续使用**：contigs 双向分流——供 17 Prodigal 基因预测（目录链）与 28 antiSMASH（BGC 链，自行预过滤 ≥1000bp）、32+ 分箱链（binning 推荐更长 contig，本目录口径取 500）。
- **加速空间**：受组装器互斥纪律（P0-6）限制，同一时刻只允许一个 megahit/metaSPAdes 运行，样本级并行不可用；16 线程已近收益拐点。16b metaSPAdes 为叶子步骤无下游，演示中不执行（用户批准）。
- **内存/硬盘**：-m 0.9 上限 90% 可用内存；maxRSS 未计量（ENG-6 遗留项），参照 51 章事故档案 megahit 峰值约 15G 量级；磁盘净增约 1.6G。

---

## 17 · Prodigal 宏基因组基因预测（-p meta 单线程，faa/fna/gff 三输出）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 17 基因预测步骤（Prodigal -p meta，单线程），完成后汇报各样本预测基因数与完整基因比例。」

**核心执行命令**（摘自 `scripts/17_bac_prodigal.sh`；Prodigal 无多线程参数，`-t` 仅占位）：

```bash
prodigal \
    -i result/assembly/megahit/{sample}/{sample}.contigs.fa \
    -a result/assembly/prodigal/{sample}/{sample}.faa \
    -d result/assembly/prodigal/{sample}/{sample}.fna \
    -f gff \
    -o result/assembly/prodigal/{sample}/{sample}.gff \
    -p meta
```

**执行结果**（2026-10-11 实测，6/6 成功，`-t 1`，1012–1775 秒/样本，合计约 2.5 小时）：

| 样本 | 耗时 | 预测基因数 | 完整基因（partial=00） | 完整率 | faa 大小 |
|---|---|---|---|---|---|
| Sample<N> | 1386s | 333,204 | 183,612 | 55.1% | 117M |
| Sample<N> | 1283s | 278,049 | 154,659 | 55.6% | 99M |
| Sample<N> | 1775s | 411,006 | 205,207 | 49.9% | 141M |
| Sample<N> | 1773s | 350,989 | 210,725 | 60.0% | 128M |
| Sample<N> | 1012s | 280,121 | 139,050 | 49.6% | 95M |
| Sample<N> | 1628s | 360,985 | 182,013 | 50.4% | 124M |

六样本合计预测基因 **2,014,354** 条（18 号合并输入的真实基数）。完整率 49.6–60.0%，宏基因组 contig 截断效应下属正常区间。

**执行点评**（执行方起草）：
- **运算时间**：1012–1775 秒/样本（单线程，CPU 密集），合计 8857 秒 ≈ 2.5 小时。
- **输出文件**：每样本 faa（蛋白，95–141M）/fna（核苷酸）/gff（坐标，含 partial 标记）三件套，路径规范。
- **后续使用**：fna 供 18 CD-HIT 跨样本去冗余；faa 供 31e FeGenie（per-sample 模式）；gff 留作基因坐标溯源。
- **加速空间**：大——单线程工具，样本级并行（6 样本同跑即可约 6 倍），亦可将 contigs 拆分后并行（脚本注释中的备选方案）；演示期按泳道串行执行未启用。
- **内存/硬盘**：单线程内存占用温和（未计量）；磁盘净增约 700M（faa+fna+gff 合计）。

---

## 18 · CD-HIT-EST 非冗余基因目录构建（95%/90% 国际标准，聚合步骤）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 18 跨样本基因目录构建步骤（CD-HIT-EST，95% identity / 90% coverage，threads 16），完成后汇报合并基因数、NR 目录规模与去冗余率。」

**核心执行命令**（摘自 `scripts/18_bac_cdhit.sh`，聚合步骤无 -s 参数，自动发现 prodigal/*/*.fna）：

```bash
# Step 1 合并（加 样本名| 前缀防 ID 冲突）→ Step 2 seqkit seq -m 100 过滤 <100bp
cd-hit-est \
    -i  result/assembly/cdhit/all_genes_min100.fna \
    -o  result/assembly/cdhit/nucleotide_nr.fa \
    -c  0.95 \
    -aS 0.9 \
    -G  0 \
    -g  1 \
    -r  1 \
    -n  10 \
    -T  16 \
    -M  0 \
    -d  0
# Step 4 seqkit translate --trim 核酸→蛋白，再 seqkit seq -m 1 过滤空翻译 → protein_nr.fa
```

**执行结果**（2026-10-11 实测，1/1 成功，1510 秒 ≈ 25 分钟）：

| 指标 | 数值 |
|---|---|
| 合并基因数（6 样本） | 2,014,354 |
| NR 核酸目录（nucleotide_nr.fa） | **995,242** 条 / 899MB |
| NR 蛋白目录（protein_nr.fa） | **995,199** 条 / 384MB |
| 去冗余率（对合并基数） | 50.6% |
| 聚类信息 | nucleotide_nr.fa.clstr 112MB |

> ⚠️ **双口径差异 43 条（质量审核终审 2026-10-15 要求注明）**：核酸目录 995,242 vs 蛋白目录 995,199，差 43 条。来源：Step 4 的 `seqkit translate --trim` 会把终止密码子裁掉，43 条基因翻译后为空序列，被 `seqkit seq -m 1` 过滤。下游两条消费链口径不同——19/20 Salmon 定量用核酸口径（995,242 行 quant.sf），21-31d 全部目录级注释用蛋白口径（995,199）。做注释×丰度 join 时以蛋白口径为准，差 43 条属设计内行为而非数据丢失。

**执行点评**（执行方起草）：
- **运算时间**：1510 秒（16 线程，200 万基因规模处于 CD-HIT 舒适区）；合并/过滤两步合计占比小。
- **输出文件**：nucleotide_nr.fa（899MB）+ protein_nr.fa（384MB）+ .clstr（112MB）；中间合并文件（all_genes*.fna）已清理。
- **后续使用**：整个目录级注释链的根输入——19 建 Salmon 索引（核酸）、21-31e 蛋白目录级注释链（15 步，含 31e）（蛋白）；NR 目录是 CP1 关口的核对对象。
- **加速空间**：有——`--tool mmseqs`（MMseqs2 Linclust，O(n) 线性，同阈值语义）在 200 万基因上预计 5–15 分钟；>500 万基因规模时为推荐后端。演示采用 cdhit 后端（同行认可度优先）。
- **内存/硬盘**：`-M 0` 不限内存，实际峰值未计量（2M 序列 95% 聚类典型 10–30G）；磁盘净增约 1.4G（含 clstr）。

---

## 19 · Salmon 索引构建（NR 核酸目录，聚合步骤，--force 备份钩子）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 19 Salmon 索引构建步骤（threads 16），完成后汇报索引规模与耗时。」

**核心执行命令**（摘自 `scripts/19_bac_salmon_build.sh`）：

```bash
salmon index \
    -t result/assembly/cdhit/nucleotide_nr.fa \
    -i result/assembly/salmon/index \
    -p 16
# 唯一副本高危步骤之一：--force 时先 mgx_force_backup 备份旧索引再重建
# （质量审核终审 P0 防线：备份钩子挂 19/37/38/38b/54 五步）
```

**执行结果**（2026-10-12 实测，1/1 成功）：索引构建 944 秒（≈15.7 分钟）；索引目录 15G（hash.bin 11.4G 为主），info.json 哨兵齐备。995,242 条目标转录本， Salmon 自动选择 word size。

**执行点评**（执行方起草）：
- **运算时间**：944 秒（16 线程），一次性成本，供全部样本的 20 号复用。
- **输出文件**：`result/assembly/salmon/index/`（15G，含 info.json/versionInfo.json/duplicate_clusters.tsv 等）；duplicate_clusters 哨兵检查通过（近冗余转录本由 Salmon 内部去重机制处理）。
- **后续使用**：20 号每样本定量的唯一索引输入；基因 ID 即 NR 目录 ID，注释 join 零映射成本。
- **加速空间**：无实质空间（单次构建，线程已给足）；若重建目录（18 重跑）则本步必须连带重跑。
- **内存/硬盘**：构建期内存中等（SA 索引分块写盘）；磁盘净增 15G——是注释链前最大的单体产物，长期归档时注意配额。

---

## 20 · Salmon 基因丰度定量（--meta 宏基因组模式，TPM + NumReads）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 20 基因定量步骤（Salmon --meta，threads 16），完成后汇报各样本比对率与检出基因数。」

**核心执行命令**（摘自 `scripts/20_bac_salmon_quant.sh`，`{sample}` 为样本变量）：

```bash
salmon quant \
    -i result/assembly/salmon/index \
    -l A \
    -p 16 \
    --meta \
    --validateMappings \
    -1 result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
    -2 result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
    -o result/assembly/salmon/{sample}
```

**执行结果**（2026-10-12 实测，6/6 成功，207–317 秒/样本，串行合计约 26 分钟）：

| 样本 | 耗时 | 比对率 | 检出基因（TPM>0） | 定量行数 |
|---|---|---|---|---|
| Sample<N> | 221s | 73.3%（30.74M/41.96M） | 371,098 | 995,242 |
| Sample<N> | 301s | 76.6%（31.98M/41.75M） | 333,650 | 995,242 |
| Sample<N> | 225s | 72.5%（34.01M/46.91M） | 462,272 | 995,242 |
| Sample<N> | 276s | 74.9%（41.51M/55.41M） | 389,120 | 995,242 |
| Sample<N> | 207s | 70.3%（27.34M/38.90M） | 305,185 | 995,242 |
| Sample<N> | 317s | 73.6%（37.98M/51.63M） | 420,466 | 995,242 |

比对率 70.3–76.6%，符合肠道宏基因组对样本内组装目录的预期区间（跨样本目录含约 1/3 非本样本基因）。

**执行点评**（执行方起草）：
- **运算时间**：207–317 秒/样本（16 线程），合计 1547 秒 ≈ 26 分钟——得益于 19 号的选择性比对索引，是全链性价比最高的定量步骤。
- **输出文件**：每样本 `quant.sf`（Name/Length/TPM/NumReads）+ aux_info/lib_format_counts/logs；多样本合并由下游消费方按需 quantmerge 或直接逐样本 join（integration 段直接消费 quant.sf）。
- **后续使用**：TPM 列是 `result/integration/bacteria/gene_annotation_matrix.tsv`（995,242 行基因 × TPM_6样本 + 全部注释列）的丰度来源；各循环/ARG/CAZyme 丰度表（arg_abundance.tsv 等 16 张）均由本步 TPM 与注释 join 而来。
- **加速空间**：有——样本级并行（IO+CPU 混合，6 并行约 5 分钟）；threads >16 收益有限。
- **内存/硬盘**：运行时需 mmap 15G 索引（多进程并行时共享页缓存，实际内存压力小于 N×15G）；磁盘每样本约 50M（quant.sf + aux）。

---

## 21 · eggNOG-mapper 综合功能注释（COG/KO/GO/EC/CAZy 一表出）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 21 eggNOG 综合注释步骤（emapper diamond，threads 16，--dbmem），完成后汇报注释基因数、COG 与 KO 覆盖。」

**核心执行命令**（摘自 `scripts/21_bac_eggnog.sh`）：

```bash
emapper.py \
    -m diamond \
    --itype proteins \
    --data_dir db/eggnog \
    --dbmem \
    -i result/assembly/cdhit/protein_nr.fa \
    --cpu 16 \
    -o eggnog \
    --output_dir result/annotation/eggnog \
    --temp_dir result/annotation/eggnog/tmp \
    --override
```

**执行结果**（2026-10-12 实测，1/1 成功，5029 秒 ≈ 84 分钟）：

| 指标 | 数值 | 占蛋白目录 |
|---|---|---|
| 输入蛋白（protein_nr.fa） | 995,199 | — |
| seed ortholog 命中（注释表行数） | 885,624 | 89.0% |
| COG 注释（COG_category ≠ "-"） | **816,668** | 82.1% |
| KEGG KO 注释（KEGG_ko ≠ "-"） | 456,884 | 45.9% |
| 主注释表体积 | **302MB**（316,961,023 字节） | — |

`eggnog.emapper.annotations` 单表 302MB 为目录级注释链最大文本产物；另有 seed_orthologs 77MB、hits 208MB。NOTES.md 执行进度索引记录本步 **validate PASS**（质量审核核证）。

**执行点评**（执行方起草）：
- **运算时间**：5029 秒（16 线程 + --dbmem 注释库全内存加载），一次性聚合步骤。
- **输出文件**：annotations/seed_orthologs/hits 三件套（合计约 590MB）；temp_dir 已清理。
- **后续使用**：COG/KEGG_KO/EC/GO 列直接进 gene_annotation_matrix.tsv；CAZy 列与 25 dbCAN 交叉印证。
- **加速空间**：两步工作流（--no_annot 先搜、-m no_search 再注释）适合 HPC 分段排队；样本级无并行空间（聚合步骤）。
- **内存/硬盘**：--dbmem 需约 30G RAM 常驻注释库（755G 机器无压力，瓶颈在核）；磁盘净增约 590MB。

---

## 22 · KEGG KO 注释（diamond blastp vs 48G 蛋白库）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 22 KEGG 注释步骤（diamond blastp，threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/22_bac_kegg.sh`，库文件自动发现 db/kegg/*.dmnd）：

```bash
diamond blastp \
    --db     db/kegg/<first>.dmnd \
    --query  result/assembly/cdhit/protein_nr.fa \
    --out    result/annotation/kegg/kegg_diamond.tsv \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 \
    --max-target-seqs 1 \
    --sensitive \
    --threads 16 \
    --quiet
```

**执行结果**（2026-10-12 实测，1/1 成功，16,606 秒 ≈ 4.6 小时）：命中 **903,807** 条（每 query 至多 1 条，unique query 数亦为 903,807，占蛋白目录 90.8%）；输出 70MB。NOTES.md 记录本步与 21 号同批 **validate PASS**。

**执行点评**（执行方起草）：
- **运算时间**：16,606 秒——注释链中最重的 diamond 搜索（48G 库 + --sensitive），约为 21 号 eggNOG 的 3.3 倍。
- **输出文件**：kegg_diamond.tsv（m6 12 列，70MB），单文件无中间产物。
- **后续使用**：sseqid 解析 KO 号后进 gene_annotation_matrix 的 KEGG_KO 列；与 21 号 eggNOG 的 KO 列（456,884）口径不同——本步仅相似度阈值（evalue 1e-5 + best hit），eggNOG 走直系同源推断，两者差异属方法论互补而非矛盾。
- **加速空间**：有——threads 提至 32/48（核充足时可近线性）；或 --sensitive 降为默认（灵敏度换速度，不建议）。
- **内存/硬盘**：diamond blob 内存中等（数十 M×线程）；磁盘净增 70MB，无清理负担。

---

## 23 · AMRFinderPlus 耐药基因检测（NCBI 严格阈值 + --plus 应激/毒力/点突变）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 23 耐药基因检测步骤（AMRFinderPlus，threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/23_bac_amrfinder.sh`）：

```bash
amrfinder \
    --protein result/assembly/cdhit/protein_nr.fa \
    --database db/amrfinder/latest \
    --output result/annotation/amrfinder/amrfinder_results.tsv \
    --threads 16 \
    --ident_min 0.9 \
    --coverage_min 0.6 \
    --plus
```

**执行结果**（2026-10-13 实测，1/1 成功，618 秒 ≈ 10 分钟）：命中 **363** 条（含 --plus 的应激/毒力/点突变元素），输出 90KB。NCBI 推荐严格阈值（ident 0.9 / coverage 0.6）下量级克制，与 24 号 RGI 的宽松口径形成层次。

**执行点评**（执行方起草）：
- **运算时间**：618 秒（16 线程，库小搜索快）。
- **输出文件**：amrfinder_results.tsv（90KB，含 element_type/gene_symbol/HMM 族等列）。
- **后续使用**：gene_annotation_matrix 的 ARG_AMRFinder 列与 arg_abundance.tsv 的严格口径来源。
- **加速空间**：无需求（已够快）。
- **内存/硬盘**：温和；净增 90KB。

---

## 24 · CARD/RGI 耐药基因综合注释（DIAMOND 加速，--include_loose 宽口径）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 24 CARD 注释步骤（RGI，DIAMOND 比对，threads 16），完成后汇报 Perfect/Strict/Loose 分布。」

**核心执行命令**（摘自 `scripts/24_bac_card.sh`；先 `rgi load --card_json --local` 载入本地库，cd 到结果目录使 localDB 落位一致）：

```bash
rgi main \
    --input_sequence result/assembly/cdhit/protein_nr.fa \
    --output_file    result/annotation/card/rgi_results \
    --input_type protein \
    --alignment_tool DIAMOND \
    --num_threads 16 \
    --local \
    --clean \
    --include_loose
```

**执行结果**（2026-10-13 实测，1/1 成功，409 秒 ≈ 7 分钟；含 rgi load 前置）：

| Cut_Off 分级 | 条数 |
|---|---|
| Perfect | 41 |
| Strict | 917 |
| Loose（--include_loose 引入） | 68,947 |
| 合计 | 69,905 |

> ⚠️ **列位注意**：脚本内置摘要 awk 取 `$24=="Strict"` 计数，但 RGI 6.x 输出中第 24 列实为 Nudged、Cut_Off 在第 6 列，故运行时屏显 "Perfect: 0 | Strict: 0"；上表为按第 6 列重计的真实分布。消费 rgi_results.txt 时以 Cut_Off 列为准。

**执行点评**（执行方起草）：
- **运算时间**：409 秒（DIAMOND 后端；BLAST 后端会慢两个数量级）。
- **输出文件**：rgi_results.txt（84MB）+ rgi_results.json（**5.5GB**，含比对可视化详情）+ localDB/。
- **后续使用**：Perfect+Strict 进 gene_annotation_matrix 的 ARG_CARD 列；Loose 层供敏感性分析（默认不进主表）。24b 汇总步骤未在演示中执行（无事件无产物，章节留白）。
- **加速空间**：无需求。
- **内存/硬盘**：内存温和；**磁盘注意**——rgi_results.json 单文件 5.5GB 是注释链最大单体，长期归档建议 gzip（可压至约 1/4）或仅归档 txt。

---

## 25 · dbCAN CAZyme 注释（仅 --tools diamond 单工具，披露）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 25 CAZyme 注释步骤（run_dbcan，threads 16），完成后汇报注释条数。」

**核心执行命令**（摘自 `scripts/25_bac_dbcan.sh`）：

```bash
run_dbcan \
    result/assembly/cdhit/protein_nr.fa \
    protein \
    --tools diamond \
    --db_dir db/dbcan3 \
    --out_dir result/annotation/dbcan \
    --dia_cpu 16 \
    --hmm_cpu 16
```

**执行结果**（2026-10-13 实测，1/1 成功，199 秒）：overview.txt **35,891** 条 CAZyme 注释（占蛋白目录 3.6%），`#ofTools=1`（DIAMOND 列有值，HMMER/eCAMI 列全 "-"）；diamond.out 2.8MB；uniInput（384MB，工具回写的输入副本）残留于结果目录。

> ⚠️ **单工具披露（NOTES.md 待披露清单落实项）**：脚本头注释宣称 dbCAN3 三工具投票（HMMER+DIAMOND+eCAMI），实际命令固定 `--tools diamond` 单工具——overview.txt 的 #ofTools 列实证为 1。质量审核 2026-10-13 拍板 C：保持单工具 + 文档披露，不改代码。消费 CAZy 结论时应知晓无 HMMER 交叉投票层（与 21 号 eggNOG 的 CAZy 列互为参照可部分弥补）。
> ⚠️ **--force 语义修复史实**：原 25:57-59 存在无条件哨兵跳过（先于 FORCE 判断），--force 会被架空；commit `7b2e9ab`（2026-10-13 质量审核 P0 整改）删除该块，现哨兵跳过受 `FORCE -eq 0` 约束。本轮实际运行（07:30）发生在修复提交（08:11）之前，为正常首轮运行未受影响。

**执行点评**（执行方起草）：
- **运算时间**：199 秒（单工具的代价优势；若开三工具投票，HMMER 层预计增加小时级耗时）。
- **输出文件**：overview.txt（1.3MB）+ diamond.out + uniInput（384MB 残留中间件，可安全清除）。
- **后续使用**：CAZyme 列进 gene_annotation_matrix 与 cazyme_abundance.tsv；GH/GT/CE/PL/CBM 家族分布供碳水化合物代谢分析。
- **加速空间**：无需求。
- **内存/硬盘**：温和；清理 uniInput 可回收 384MB。

---

## 26 · VFDB 毒力因子注释（diamond blastp）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 26 毒力因子注释步骤（diamond blastp vs VFDB，threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/26_bac_vfdb.sh`，参数与 22 号 KEGG 完全同构）：

```bash
diamond blastp \
    --db     db/vfdb/<first>.dmnd \
    --query  result/assembly/cdhit/protein_nr.fa \
    --out    result/annotation/vfdb/vfdb_hits.tsv \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 \
    --max-target-seqs 1 \
    --sensitive \
    --threads 16 \
    --quiet
```

**执行结果**（2026-10-13 实测，1/1 成功，65 秒）：命中 **163,039** 条（unique query 同数，占蛋白目录 16.4%），输出 12MB。

**执行点评**（执行方起草）：
- **运算时间**：65 秒（库小、线程足）。
- **输出文件**：vfdb_hits.tsv（12MB，m6 12 列）。
- **后续使用**：VFDB 列进 gene_annotation_matrix 与 vfdb_abundance.tsv。
- **加速空间**：无需求。
- **内存/硬盘**：温和；净增 12MB。

---

## 27 · BacMet 重金属抗性注释（diamond blastp）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 27 重金属抗性注释步骤（diamond blastp vs BacMet，threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/27_bac_bacmet.sh`，与 22/26 同构）：

```bash
diamond blastp \
    --db     db/bacmet/<first>.dmnd \
    --query  result/assembly/cdhit/protein_nr.fa \
    --out    result/annotation/bacmet/bacmet_hits.tsv \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 \
    --max-target-seqs 1 \
    --sensitive \
    --threads 16 \
    --quiet
```

**执行结果**（2026-10-13 实测，1/1 成功，37 秒）：命中 **69,760** 条（占蛋白目录 7.0%），输出 4.8MB。

**执行点评**（执行方起草）：
- **运算时间**：37 秒——注释链最快步骤。
- **输出文件**：bacmet_hits.tsv（4.8MB）。
- **后续使用**：BacMet 列进 gene_annotation_matrix（重金属/消毒剂抗性维度，与 ARG 双抗联动分析）。
- **加速空间**：无需求。
- **内存/硬盘**：温和；净增 4.8MB。

---

## 28 · antiSMASH BGC 预测（chunked 24 分块，哨兵门控，per-sample）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 28 BGC 预测步骤（antiSMASH 8，threads 8，chunked 模式），完成后汇报各样本 region 数与 chunk 完成情况。」

**核心执行命令**（摘自 `scripts/28_bac_antismash.sh`；chunked 执行=可靠性/失败隔离手段，科学参数与冻结的单体命令逐字节一致，E-HARD-02-ADOPT）：

```bash
# 预过滤 <1000bp（T-22/C2）→ 按长度贪心均衡分 24 chunk（原子单位=完整 record）
antismash chunk_XX.fa \
    --taxon bacteria \
    --output-dir result/annotation/antismash/{sample}/chunk_XX \
    --cpus 8 \
    --databases db/antismash8 \
    --genefinding-tool prodigal-m \
    --minimal \
    --enable-nrps-pks
# 全 chunk 成功后平铺 *.region*.gbk 至样本层（副本数=原件数校验，T-11：
# 执行失败/平铺不完整绝不伪装成功），touch antismash_done.txt
```

**执行结果**（2026-10-14 至 10-16 实测，6/6 成功，-t 8 插空负载（W3-C 排程），16,771–27,940 秒/样本，合计约 40.6 小时）：

| 样本 | 耗时 | BGC regions | chunks |
|---|---|---|---|
| Sample<N> | 27835s | 294 | 24 |
| Sample<N> | 16771s | 241 | 24 |
| Sample<N> | 27940s | 373 | 24 |
| Sample<N> | 26133s | 345 | 24 |
| Sample<N> | 24337s | 234 | 24 |
| Sample<N> | 23145s | 291 | 24 |

合计 **1,778** 个 BGC region。每 chunk 含完整 gbk/json/zip/index.html；region GBK 平铺至样本层满足 28b 的 maxdepth-1 消费契约。

**执行点评**（执行方起草）：
- **运算时间**：16,771–27,940 秒/样本（8 线程）——注释链总耗时之最；-t 8 系 W3-C 插空排程决定（避开主线 16t），满线程可显著缩短。
- **输出文件**：每样本 antismash_done.txt 哨兵 + 平铺 region GBK（234–373 个）+ 24 个 chunk 目录 + _chunks/ 输入分块；单样本数百 MB 量级。
- **后续使用**：region GBK 供 28b 新颖度评分；BGC 类型分布供次级代谢分析（RiPP/terpene/NRP 等由 json 可提）。
- **加速空间**：大——chunk 级并行（rush/多进程跑 chunk_XX）或样本级并行；chunked 模式当前为 chunk 串行（resume 为 backlog 项 T-23，重跑须重建全部分块）。
- **内存/硬盘**：antiSMASH 内存中等（--minimal 已裁剪 NCBI 分类查询等重步骤）；磁盘为注释链最大增量之一（六样本 chunk 全存，可只留平铺 GBK + json 归档压缩）。

---

## 28b · BGC 新颖度评分（MIBiG 最佳命中，novelty_score = 1 − 命中覆盖率）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 28b BGC 新颖度评分步骤（threads 8），完成后汇报各样本 region 评分分布。」

**核心执行命令**（摘自 `scripts/28b_bgc_novelty.sh` + `28b_bgc_novelty_score.py`；消费 28 号平铺 region GBK，输出每 region 一行）：

```bash
# 对每个 *.region*.gbk 提取 CDS 与 MIBiG 最佳命中簇，计算
# novelty_score = 1 − best_mibig_hit_fraction；无命中记 NA/1.0
# 输出: result/annotation/antismash/{sample}/{sample}.bgc_novelty.tsv
```

**执行结果**（2026-10-16 实测，6/6 成功，11–14 秒/样本）：合计 1,778 行（与 28 号 region 数逐一闭合）：novelty_score ≥ 0.9 的**高新颖** BGC **815** 个（45.8%）；无任何 MIBiG 命中（score=1.0）**270** 个（15.2%）。

| 样本 | regions | novelty ≥ 0.9 | 无 MIBiG 命中 |
|---|---|---|---|
| Sample<N> | 294 | 129 | 37 |
| Sample<N> | 241 | 116 | 34 |
| Sample<N> | 373 | 174 | 63 |
| Sample<N> | 345 | 167 | 54 |
| Sample<N> | 234 | 82 | 30 |
| Sample<N> | 291 | 147 | 52 |

**执行点评**（执行方起草）：
- **运算时间**：11–14 秒/样本（纯表解析，无搜索）。
- **输出文件**：每样本 `{sample}.bgc_novelty.tsv`（10 列，含 best_mibig_cluster/organism/product/hit_fraction/novelty_score）。
- **后续使用**：novelty 排序筛选候选新 BGC（≥0.9 层优先），供后续靶向挖掘/人工核验。
- **加速空间**：无需求。
- **内存/硬盘**：忽略不计。

---

## 29 · DefenseFinder 防御系统检测（unordered 模式，空产出如实记录）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 29 防御系统检测步骤（DefenseFinder，threads 16），完成后汇报系统检出数。」

**核心执行命令**（摘自 `scripts/29_bac_defense_finder.sh`；NR 蛋白无连续基因组坐标，用 unordered 绕过 replicon 上下文依赖）：

```bash
defense-finder run \
    --models-dir db/defense-finder/defense-finder-db/models \
    --db-type unordered \
    --workers 16 \
    --out-dir result/annotation/defense_finder \
    result/assembly/cdhit/protein_nr.fa
```

**执行结果**（2026-10-13 实测，1/1 成功，1272 秒 ≈ 21 分钟）：**检出防御系统 0 个**——defense_finder_systems.tsv 为空表头（脚本在无系统检出时写空 sentinel，非报错）；genes.tsv 同为空；hmmer 层单基因命中 **42,181** 条真实存在（4.2MB）。

> ⚠️ **空产出定性（全短样本策略 §10.2：空产出继续 + 如实记录）**：42,181 条单基因 HMM 命中未能组装成任何多基因防御系统——unordered 模式下 MacSyFinder 仍要求系统成员基因在同一"replicon"（此处整目录蛋白被视作单一无名 replicon）内按模型配置聚集计数，NR 目录打散了原基因组邻接关系，多基因系统（如 CRISPR-Cas 完整级联、限制修饰系统对）的共定位证据已不可恢复。此为方法学结构性限制而非生物学"无防御系统"结论；如需防御系统分析，应对 33-36 号产出的 MAG（有连续坐标）重跑 DefenseFinder。

**执行点评**（执行方起草）：
- **运算时间**：1272 秒（16 workers，HMM 搜索本身正常完成）。
- **输出文件**：systems/genes 空表 + hmmer.tsv（42,181 行单基因证据，保留供 MAG 层比对参照）。
- **后续使用**：gene_annotation_matrix 的 Defense_system 列为空值来源即此；MAG 层重跑（ordered-replicon 模式）是拿到系统级结论的正道。
- **加速空间**：无意义（结论已定性）。
- **内存/硬盘**：温和；净增约 4.2MB。

---

## 30 · NCyc 氮循环基因注释（diamond blastp）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 30 氮循环注释步骤（diamond blastp vs NCyc，threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/30_bac_ncyc.sh`，与 22/26/27 同构）：

```bash
diamond blastp \
    --db     db/ncyc/<first>.dmnd \
    --query  result/assembly/cdhit/protein_nr.fa \
    --out    result/annotation/ncyc/ncyc_hits.tsv \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 \
    --max-target-seqs 1 \
    --sensitive \
    --threads 16 \
    --quiet
```

**执行结果**（2026-10-13 实测，1/1 成功，225 秒）：命中 **113,187** 条（占蛋白目录 11.4%），输出 9.2MB。

**执行点评**（执行方起草）：
- **运算时间**：225 秒。
- **输出文件**：ncyc_hits.tsv（9.2MB）。
- **后续使用**：NCyc_gene 列进 gene_annotation_matrix 与 ncyc_abundance.tsv（氮循环各通路基因丰度）。
- **加速空间**：无需求。
- **内存/硬盘**：温和。

---

## 31 · PCyc 磷循环基因注释（diamond blastp）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 31 磷循环注释步骤（diamond blastp vs PCyc，threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/31_bac_pcyc.sh`，与 30 号对称）：

```bash
diamond blastp \
    --db     db/pcyc/<first>.dmnd \
    --query  result/assembly/cdhit/protein_nr.fa \
    --out    result/annotation/pcyc/pcyc_hits.tsv \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 \
    --max-target-seqs 1 \
    --sensitive \
    --threads 16 \
    --quiet
```

**执行结果**（2026-10-13 实测，1/1 成功，1008 秒）：命中 **303,587** 条（占蛋白目录 30.5%——三循环中最高，磷代谢基因家族庞大所致），输出 25MB。

**执行点评**（执行方起草）：
- **运算时间**：1008 秒（库规模大于 NCyc 约 4.5 倍耗时）。
- **输出文件**：pcyc_hits.tsv（25MB）。
- **后续使用**：PCyc_gene 列进 gene_annotation_matrix 与 pcyc_abundance.tsv。
- **加速空间**：无需求。
- **内存/硬盘**：温和。

---

## 31b · SCyc 硫循环基因注释（diamond --more-sensitive，保守双阈值）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 31b 硫循环注释步骤（diamond blastp vs SCyc，threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/31b_bac_scyc.sh`；与 30/31 同构但灵敏度与阈值收紧，库路径为固定式非自动发现）：

```bash
diamond blastp \
    --db     db/scyc/scyc-db/scyc.dmnd \
    --query  result/assembly/cdhit/protein_nr.fa \
    --out    result/annotation/scyc/scyc_hits.tsv \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 \
    --id 60 \
    --min-score 30 \
    --max-target-seqs 1 \
    --more-sensitive \
    --threads 16 \
    --quiet
```

**执行结果**（2026-10-13 实测，1/1 成功，7371 秒 ≈ 2.0 小时）：命中 **112,795** 条（占蛋白目录 11.3%），输出 8.7MB。

**执行点评**（执行方起草）：
- **运算时间**：7371 秒——同构 diamond 步骤中最慢（--more-sensitive 双重敏感模式代价；命中量与 NCyc 相当，耗时为其 33 倍，灵敏度档位差异所致）。
- **输出文件**：scyc_hits.tsv（8.7MB）。
- **后续使用**：SCyc_gene 列进 gene_annotation_matrix 与 scyc_abundance.tsv（提示语：结合 Salmon TPM 计算硫循环基因丰度，integration 段已落实）。
- **加速空间**：有——若与 30/31 对齐用 --sensitive 可大幅提速（SCyc 官方推荐保守参数，保持现状为口径一致性让步，已在脚本头注明）。
- **内存/硬盘**：温和。

---

## 31c · Pfam-A 结构域注释（hmmscan --cut_ga，seqkit 分块 + rush 并行）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 31c Pfam 结构域注释步骤（hmmscan --cut_ga，threads 16 总预算），完成后汇报基因级/域级命中数。」

**核心执行命令**（摘自 `scripts/31c_bac_pfam.sh`；-t 16 → 8 chunks × 2 threads/chunk，rush -j 8 进程级并行）：

```bash
# seqkit split2 -p 8 拆分 protein_nr.fa → rush 并行：
hmmscan \
    --cpu 2 \
    --cut_ga \
    --noali \
    --tblout    chunk_XX.fa.tblout \
    --domtblout chunk_XX.fa.domtblout \
    db/pfam/Pfam-A.hmm \
    chunk_XX.fa
# 全 chunk .ok 哨兵齐备后合并（剥 # 注释行）→ pfam_hits.tblout / .domtblout
```

**执行结果**（2026-10-14 实测，1/1 成功，58,238 秒 ≈ **16.2 小时**——目录级注释链最耗时步骤）：

| 指标 | 数值 |
|---|---|
| 基因×HMM 行（tblout 行数） | 1,320,713 |
| 命中蛋白（unique query，tblout 第 3 列） | 711,526（占目录 71.5%） |
| 覆盖 Pfam 家族数（unique HMM，tblout 第 1 列） | 11,680 |
| 域级行（domtblout） | 1,276,862 |
| 输出体积 | tblout 224MB + domtblout 262MB |

> 口径提示：hmmscan tblout 每行=一个 query×HMM 命中（一蛋白可命中多家族），脚本屏显"蛋白命中数"实为行数口径；真实蛋白覆盖以 unique query 711,526 为准。

**执行点评**（执行方起草）：
- **运算时间**：58,238 秒（8 进程 × 2 线程的并行已生效，但 hmmscan 对 2 万+ HMM 全库扫描本质昂贵）；比 31b SCyc 还慢 8 倍。
- **输出文件**：pfam_hits.tblout（基因级）+ pfam_hits.domtblout（域坐标级）；temp/pfam_split 已清理。
- **后续使用**：pfam_evidence.tsv 与 gene_annotation_matrix 的结构域层；与 21 号 eggNOG 的 PFAM 列交叉（eggNOG 只给家族名，本步给分值/覆盖率/域边界）。
- **加速空间**：大——总线程提至 32/48（chunk 数随 -t 自动放大至 32 上限）；或改 hmmsearch 反转 query/target（大 query 小库场景官方推荐，可数倍提速）；--noali 已减输出负担。
- **内存/硬盘**：每 hmmscan 进程需 mmap Pfam-A 索引（多进程共享页缓存）；磁盘净增约 486MB。

---

## 31d · UniProt Swiss-Prot 注释（MMseqs2 easy-search，人工审核库兜底）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 31d Swiss-Prot 注释步骤（MMseqs2 easy-search，threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/31d_bac_uniprot.sh`）：

```bash
mmseqs easy-search \
    --threads    16 \
    --max-accept 1 \
    -e           1e-5 \
    --format-output "query,target,fident,alnlen,mismatch,gapopen,qstart,qend,tstart,tend,evalue,bits,qcov" \
    -v 1 \
    result/assembly/cdhit/protein_nr.fa \
    db/uniprot_sprot/mmseqs/uniprot_sprot \
    result/annotation/uniprot_sprot/sprot_hits.tsv \
    temp/uniprot_sprot
```

**执行结果**（2026-10-14 实测，1/1 成功，857 秒 ≈ 14 分钟）：命中 **554,865** 条（占蛋白目录 55.7%），输出 41MB、13 列（含 qcov 覆盖率列）。紧随 31c 完成（02:04 → 02:18）。

**执行点评**（执行方起草）：
- **运算时间**：857 秒——MMseqs2 预建索引 + easy-search 的速度优势 vs 同规模 diamond 步骤明显。
- **输出文件**：sprot_hits.tsv（41MB）；temp/uniprot_sprot 已清理。
- **后续使用**：识别 eggNOG（885,624）未覆盖但 Swiss-Prot 有高置信描述的基因（人工审核库的功能命名兜底层）；脚本提示语即此交叉用法。
- **加速空间**：无需求。
- **内存/硬盘**：温和；净增 41MB。

---

## 31e · FeGenie 铁代谢基因预测（per-sample .faa，HMM GA 阈值，W3-C 插空）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 31e 铁代谢预测步骤（FeGenie，threads 8，per-sample prodigal 模式），完成后汇报各样本命中数与类别分布。」

**核心执行命令**（摘自 `scripts/31e_bac_fegenie.sh`；per-sample 模式读 17 号 .faa，NR 模式（--input-type nr）供 MAG 级分析备选）：

```bash
# 蛋白拷入临时 bin 目录（FeGenie 要求 -bin_dir 一文件一"bin"）
FeGenie.py \
    -bin_dir temp/fegenie/{sample} \
    -bin_ext faa \
    -out     result/annotation/fegenie/{sample} \
    -t       8 \
    --orfs
# 主结果: FeGenie-geneSummary.csv（基因 ID + 功能分类 + HMM 得分，GA 阈值）
```

**执行结果**（2026-10-14 实测，6/6 成功，-t 8（W3-C 插空排程），269–326 秒/样本，合计约 30 分钟）：

| 样本 | 耗时 | 铁代谢基因命中 |
|---|---|---|
| Sample<N> | 306s | 2,222 |
| Sample<N> | 270s | 2,026 |
| Sample<N> | 314s | 2,798 |
| Sample<N> | 269s | 1,525 |
| Sample<N> | 326s | 2,537 |
| Sample<N> | 303s | 2,307 |

合计 **13,415** 条，覆盖铁载体合成/转运、血红素、铁储存（ferritin）、调控（Fur）、磁小体等类别。

**执行点评**（执行方起草）：
- **运算时间**：269–326 秒/样本（8 线程 HMM 搜索，env 内嵌 iron HMM 集）。
- **输出文件**：每样本 FeGenie-geneSummary.csv + 各类别明细表 + 样本级 summary。
- **后续使用**：Iron 列进 gene_annotation_matrix 与 iron_abundance.tsv；与 eggNOG KO（如 K02013 铁转运）、Pfam（PF01032 FecA）三层互证可细分亚型。
- **加速空间**：样本级并行即可（未启用，插空负载让位主线）。
- **内存/硬盘**：温和；临时 bin 目录已清理。

---

## 32 · CoverM contig 深度计算（minimap2-sr 比对 + metabat 深度表）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 32 contig 深度计算（CoverM make + contig，threads 16），完成后汇报各样本 contig 数与产出文件。」

**核心执行命令**（摘自 `scripts/32_bac_coverm_depth.sh`）：

```bash
# 步骤 1/2: minimap2 短读比对生成排序 BAM（SemiBin2 备用输入）
coverm make \
    -p minimap2-sr \
    -t 16 \
    -r result/assembly/megahit/{sample}/{sample}.contigs.fa \
    -1 result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
    -2 result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
    -o result/binning/coverm/{sample}
# 产物 BAM 统一重命名为 {sample}.bam

# 步骤 2/2: 生成 MetaBAT2/MaxBin2 格式深度表
coverm contig \
    -t 16 \
    --methods metabat \
    --bam-files result/binning/coverm/{sample}/{sample}.bam \
    -o result/binning/coverm/{sample}/depth.txt
```

**执行结果**（2026-10-11 实测，6/6 成功）：

| 样本 | 耗时 | 深度表 contigs | BAM 大小 |
|---|---|---|---|
| Sample<N> | 526s | 110,328 | 5.4G |
| Sample<N> | 490s | 91,223 | 5.1G |
| Sample<N> | 560s | 151,240 | 6.2G |
| Sample<N> | 659s | 103,211 | 6.8G |
| Sample<N> | 470s | 108,879 | 5.4G |
| Sample<N> | 619s | 131,738 | 6.3G |

产出：`result/binning/coverm/<样本>/`（depth.txt + 排序 BAM），合计约 35G。

**执行点评**（执行方起草）：
- **运算时间**：470–659 秒/样本（16 线程，瓶颈在 minimap2 比对 4–5G 清洁 reads 回 9–15 万条 contigs）。
- **输出文件**：每样本 depth.txt（contig 级平均深度+方差，metabat 格式）+ 排序 BAM（5.1–6.8G）。
- **后续使用**：depth.txt 是 33/34/35 三个 binner 的共同输入（abundance 信号）；BAM 为 SemiBin2 自监督模式的备用输入（本演示生产口径走 `--depth-metabat2` 预训练模型，未用 BAM）。
- **加速空间**：多样本可并行（IO/CPU 均非独占）；单样本 threads 提升收益有限。
- **内存/硬盘**：minimap2 索引常驻内存温和（数 G）；磁盘是主要成本——BAM 合计 ~35G，若下游不用 SemiBin2 BAM 自监督模式可考虑归档压缩（本演示保留）。

---

## 33 · MetaBAT2 分箱（tetranucleotide + 丰度）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 33 MetaBAT2 分箱（threads 16），完成后汇报各样本 bin 数。」

**核心执行命令**（摘自 `scripts/33_bac_metabat2.sh`）：

```bash
metabat2 \
    --numThreads 16 \
    -m 1500 \
    -i result/assembly/megahit/{sample}/{sample}.contigs.fa \
    -a result/binning/coverm/{sample}/depth.txt \
    -o result/binning/metabat2/{sample}/bin
# 完成后由 metabat2-utils（或 FASTA 解析回退）生成 contig2bin 表 {sample}.tsv
```

**执行结果**（2026-10-11 实测，6/6 成功）：

| 样本 | 耗时 | bins | contig 分配数 |
|---|---|---|---|
| Sample<N> | 458s | 92 | 16,470 |
| Sample<N> | 754s | 77 | 14,811 |
| Sample<N> | 615s | 120 | 22,752 |
| Sample<N> | 467s | 123 | 19,356 |
| Sample<N> | 381s | 75 | 16,458 |
| Sample<N> | 520s | 97 | 20,088 |

六个样本合计 584 bins（目录 ~976M）。

**执行点评**（执行方起草）：
- **运算时间**：381–754 秒/样本（16 线程，tetranucleotide 频率计算为 CPU 密集）。
- **输出文件**：每样本 `bin.*.fa` + contig2bin 表（tsv，供 36 DAS_Tool 消费）。
- **后续使用**：三路 binner 之一，进 36 DAS_Tool 整合；`-m 1500` 只对 ≥1.5kb contig 分箱（与 16 号组装下限一致）。
- **加速空间**：样本间可并行；脚本对 exit 139（SEGFAULT）有防御（写空 contig2bin 优雅退出，本次未触发）。
- **内存/硬盘**：内存温和；磁盘 ~1G/六样本。

---

## 34 · MaxBin2 分箱（EM 算法 + tetranucleotide）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 34 MaxBin2 分箱（threads 16），完成后汇报各样本 bin 数。」

**核心执行命令**（摘自 `scripts/34_bac_maxbin2.sh`）：

```bash
# depth.txt 提取 2 列 abundance（contig, depth）；depth 更新时强制重生成，
# 防止旧 contig-ID 丰度配新组装导致 bins 错位（下游 DAS_Tool 报错）
tail -n +2 result/binning/coverm/{sample}/depth.txt | cut -f1,4 > abundance.txt

run_MaxBin.pl \
    -contig result/assembly/megahit/{sample}/{sample}.contigs.fa \
    -max_iteration 50 \
    -thread 16 \
    -abund abundance.txt \
    -out result/binning/maxbin2/{sample}/bin
# 完成后由 bin.*.fasta 解析生成 {sample}.maxbin2.tsv（contig2bin 表）
```

**执行结果**（2026-10-12 实测，6/6 成功；实际执行顺序 35 → 34，MaxBin2 殿后）：

| 样本 | 耗时 | bins | contig 分配数 |
|---|---|---|---|
| Sample<N> | 1376s | 81 | 45,612 |
| Sample<N> | 946s | 68 | 34,356 |
| Sample<N> | 2210s | 104 | 58,473 |
| Sample<N> | 1536s | 91 | 45,096 |
| Sample<N> | 1019s | 63 | 40,112 |
| Sample<N> | 1582s | 90 | 49,451 |

六个样本合计 497 bins（目录 ~1.7G）。

**执行点评**（执行方起草）：
- **运算时间**：946–2210 秒/样本（16 线程 EM 迭代 ≤50 轮，三 binner 中最慢）。
- **输出文件**：每样本 `bin.*.fasta` + `.maxbin2.tsv` contig2bin 表。
- **后续使用**：三路 binner 之一，进 36 DAS_Tool 整合。
- **加速空间**：样本间可并行；EM 收敛轮数决定耗时，`-max_iteration` 已是默认 50。
- **内存/硬盘**：内存温和；磁盘 ~1.7G。MaxBin2 contig 分配数显著多于 MetaBAT2（H1 45,612 vs 16,470），风格偏"多分"——整合权交给 DAS_Tool 的 SCG 评分。

---

## 35 · SemiBin2 分箱（human_gut 预训练深度模型）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 35 SemiBin2 分箱（human_gut 预训练模型，threads 16），完成后汇报各样本 bin 数。」

**核心执行命令**（摘自 `scripts/35_bac_semibin2.sh`）：

```bash
# 前置 guard：≥2500bp contig 需 ≥2 条，否则写空哨兵优雅退出
SemiBin2 single_easy_bin \
    -t 16 \
    --environment human_gut \
    --input-fasta result/assembly/megahit/{sample}/{sample}.contigs.fa \
    --depth-metabat2 result/binning/coverm/{sample}/depth.txt \
    -o result/binning/semibin2/{sample}
# 完成后从 output/contig_bins.tsv 拷贝生成 {sample}.semibin2.tsv
```

**执行结果**（2026-10-11 实测，6/6 成功，SemiBin 2.5.0）：

| 样本 | 耗时 | bins | contig 分配数 |
|---|---|---|---|
| Sample<N> | 528s | 97 | 17,980 |
| Sample<N> | 400s | 82 | 13,290 |
| Sample<N> | 549s | 126 | 21,449 |
| Sample<N> | 471s | 126 | 19,481 |
| Sample<N> | 290s | 78 | 15,030 |
| Sample<N> | 386s | 117 | 18,716 |

六个样本合计 626 bins（目录 ~566M）。

**执行点评**（执行方起草）：
- **运算时间**：290–549 秒/样本（16 线程）——预训练模型免自监督训练，比 34 MaxBin2 快 2–4×。
- **输出文件**：每样本 `output_bins/*.fa.gz` + `.semibin2.tsv` contig2bin 表。
- **后续使用**：三路 binner 之一，进 36 DAS_Tool 整合；最终 353 MAG 中 SemiBin2 来源占 193（55%），是主力 binner。
- **加速空间**：样本间可并行；生产口径 `--environment human_gut + --depth-metabat2` 保持与历史结果可比（SemiBin 1.5.0 的 BAM coverage bug 与 0-bin 崩溃已在 2.5.0 修复，见脚本注释）。
- **内存/硬盘**：内存温和；磁盘 ~566M。

---

## 36 · DAS_Tool 三算法整合（SCG 评分择优）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 36 DAS_Tool 整合分箱（threads 16），完成后汇报各样本整合 bin 数。」

**核心执行命令**（摘自 `scripts/36_bac_dastool.sh`；输入表先清洗表头并按当前 contigs 白名单过滤）：

```bash
# R_LIBS_USER（全局 Rlib，R 4.5.3 编译）与环境内 R 4.4.3 ABI 不兼容会崩
# DAS_Tool 内部 R 脚本，故 env -u 剥离
env -u R_LIBS_USER conda run --prefix envs/dastool --no-capture-output \
    DAS_Tool \
        --threads 16 \
        -i metabat2.tsv,maxbin2.tsv,semibin2.tsv \
        -l metabat2,maxbin2,semibin2 \
        -c result/assembly/megahit/{sample}/{sample}.contigs.fa \
        -o result/binning/dastool/{sample}/{sample} \
        --score_threshold 0.3 \
        --write_bins
```

**执行结果**（2026-10-12 实测，6/6 成功，107–192 秒/样本）：

| 样本 | 耗时 | 整合 bins | 来源构成（semibin2/maxbin2/metabat2） |
|---|---|---|---|
| Sample<N> | 139s | 56 | 35/11/10 |
| Sample<N> | 133s | 51 | 26/18/7 |
| Sample<N> | 192s | 74 | 40/17/17 |
| Sample<N> | 177s | 65 | 34/22/9 |
| Sample<N> | 107s | 48 | 23/19/6 |
| Sample<N> | 161s | 59 | 35/16/8 |

**合计 353 MAGs**（semibin2 193 + maxbin2 103 + metabat2 57；目录 ~1.7G）。汇总表（`*_DASTool_summary.tsv`）抽查：多数入选 bin SCG completeness 98–100、redundancy 0–2。

**执行点评**（执行方起草）：
- **运算时间**：107–192 秒/样本（SCG HMM 搜索 + 贪心择优，轻量）。
- **输出文件**：`{sample}_DASTool_contig2bin.tsv` + `{sample}_DASTool_bins/*.fa` + summary/proteins 中间件。
- **后续使用**：353 bins 是 36b 重组装与 37 CheckM2 的输入；33b QuickBin 刻意不入 ensemble（2026-09-16 四样本对照实验显示加入第 4 个 binner 对高质量 MAG 恢复净有害，见脚本注释）。
- **加速空间**：秒级步骤无需优化；运行前清空 `_DASTool_bins/` 防 DAS_Tool 残留旧文件污染（Project01 实证：52 bins 的运行留下 123 个文件、71 个陈旧）。
- **内存/硬盘**：均温和。

---

## 36b · metaWRAP 重组装（strict/permissive 双变体择优）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 36b bin 重组装（metaWRAP reassemble_bins，threads 16，严格串行），完成后核对各样本哨兵 N_FALLBACK。」

**核心执行命令**（摘自 `scripts/36b_bac_bin_reassembly.sh`；bin FASTA 先做 header 简化绕开 metaWRAP 整行匹配 bug）：

```bash
# MEGAHIT header ">k127_x flag=.. multi=.. len=.." 会使 metaWRAP 的
# contig→bin 映射与 SAM RNAME 不匹配（全部 reads 被丢弃）；喂前先
# sed 成 ">k127_x" 简化 header 的临时拷贝
metaWRAP reassemble_bins \
    -b bins_clean_header/ \
    -o metawrap_work/ \
    -1 {sample}_1.kneaddata.fastq.gz \
    -2 {sample}_2.kneaddata.fastq.gz \
    -t 16 -m 64 \
    --skip-checkm          # 跳过内建 CheckM(1.x)，下游 37 用 CheckM2 统一评估
# 完成后在 {bin}.strict.fa / {bin}.permissive.fa 间按组装总长度择优，
# 两变体皆缺才回退原始 bin；哨兵记 N_INPUT/N_REASSEMBLED/N_FALLBACK/FALLBACK_BINS
```

**执行结果**（2026-10-13/14 实测，6/6 成功，R 泳道严格串行——组装器互斥纪律 P0-6）：

| 样本 | 耗时 | 输入 bins | 真重组装 | 回退 |
|---|---|---|---|---|
| Sample<N> | 12,066s（3.4h） | 56 | 56 | 0 |
| Sample<N> | 16,086s（4.5h） | 51 | 51 | 0 |
| Sample<N> | 22,737s（6.3h） | 65 | 65 | 0 |
| Sample<N> | 19,855s（5.5h） | 48 | 48 | 0 |
| Sample<N> | 20,635s（5.7h） | 74 | 73 | 1 |
| Sample<N> | 22,624s（6.3h） | 59 | 59 | 0 |

**352/353 真重组装**；唯一回退 H10 `semibin2_271`（CP2-MAG 字节级比对确认其与 DAS_Tool 原件逐字节一致）。串行合计约 31.7 小时。产出：`result/binning/reassembly/<样本>/reassembled_bins/*.fa`（与输入 bin 集一一对应，~873M）。

**⚠️ 注意事项**：
- **静默回退风险**（NOTES.md 待披露项）：metaWRAP 失败时回退原始 bin 且 exit 0——CP2-MAG 逐样本核对哨兵 N_FALLBACK 兜底；H1–H4 为 0（四审 P1-5），H10 的 1 例回退身份由字节比对确认（该哨兵产生于 P2 修复前，无 FALLBACK_BINS 行；此后哨兵已记 FALLBACK_BINS，commit 002e3ae）。
- 组装器互斥：同一时刻全局只允许一个 megahit/metaSPAdes/SPAdes 系进程，故六样本串行。

**执行点评**（执行方起草）：
- **运算时间**：3.4–6.3 小时/样本（每 bin 一次 SPAdes 精细组装，串行合计 31.7h，MAG 链最耗时环节之一）。
- **输出文件**：`reassembled_bins/`（353 个 bin：352 重组装 + 1 回退），哨兵 `.reassembly_done.txt` 记录回退明细。
- **后续使用**：37 CheckM2 优先消费本目录（无 reassembly 时回退读 DAS_Tool 原件，脚本对旧项目状态兼容）。
- **加速空间**：`--parallel` 可多 bin 并行 SPAdes（各 1 线程）但内存翻倍；受组装器互斥纪律约束，样本级并行需排队。
- **内存/硬盘**：`-m 64` 上限；MW_WORKDIR 组装临时目录体量大（已清理），净增 ~873M。

---

## 37 · CheckM2 质量评估（comp≥50 / cont≤10 过滤）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 37 CheckM2 MAG 质量评估（threads 16），完成后汇报输入 bin 数与高质量 MAG 数。」

**核心执行命令**（摘自 `scripts/37_bac_checkm2.sh`；跨样本收集时 bin 名加 `样本__` 前缀防重名）：

```bash
# 输入 temp/checkm2_input/：reassembled_bins 优先（36b 产物），符号链 + 样本前缀
checkm2 predict \
    --threads 16 \
    --force \
    --input temp/checkm2_input \
    -x fa \
    --output-directory result/binning/checkm2 \
    --database_path db/checkm2/CheckM2_database/uniref100.KO.1.dmnd

# 过滤：完整度 ≥50% 且 污染度 ≤10% → checkm2_filtered/ + drep_input/
awk -F'\t' 'NR==1 || ($2>=50 && $3<=10)' quality_report.tsv > filtered_report.tsv
```

**执行结果**（两次实测：10-13 首跑 981s（重组装前原 bins，即 W1 原始基线）；10-14 `--force` 重跑 1042s（36b 重组装后正式版），16 线程）：

| 口径 | 输入 bins | 通过（comp≥50/cont≤10） | 淘汰 |
|---|---|---|---|
| 正式版（重组装后，10-14） | 353 | **269** | 84 |
| W1 原始基线（重组装前，10-13） | 353 | 269 | 84 |

产出：`result/binning/checkm2/quality_report.tsv`（353 行 + 表头，含 Completeness_Model_Used/Translation_Table_Used 等 12 列）+ `checkm2_filtered/filtered_report.tsv`（269）+ `drep_input/`（269 个 MAG 副本）。Neural Network (Specific Model) 为主预测模型。

**执行点评**（执行方起草）：
- **运算时间**：981–1042 秒/轮（16 线程 DIAMOND uniref100 KO 检索 + NN 推理，353 bins）。
- **输出文件**：quality_report（全量）、filtered_report + drep_input（269）。
- **后续使用**：269 个过滤 MAG 供 38 dRep 去冗余；filtered_report 的 comp/cont 亦被 38 复用为 genomeInfo（免 dRep 内部重跑 CheckM1）。
- **加速空间**：单轮 17 分钟已很快；`--force` 有备份钩子（mgx_force_backup，质量审核 P0 防线 ④）。
- **内存/硬盘**：CheckM2 数据库（uniref100 KO dmnd）常驻；checkm2 目录 ~1.1G（含 protein_files/diamond_output 中间件）。

---

## 38 · dRep 去冗余（95% ANI 物种级，skani 二级聚类）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 38 dRep MAG 去冗余（-sa 0.95，skani，threads 16），完成后汇报代表基因组数。」

**核心执行命令**（摘自 `scripts/38_bac_drep.sh`）：

```bash
# genomeInfo 复用 37 的 CheckM2 comp/cont，避免 dRep 内部重跑 checkm lineage_wf
# genome,completeness,contamination ← filtered_report.tsv
dRep dereplicate \
    result/binning/drep \
    -g result/binning/checkm2/drep_input/*.fa \
    -sa 0.95 \
    --S_algorithm skani \
    -pa 0.9 \
    -nc 0.30 \
    -p 16 \
    --genomeInfo checkm2_genomeInfo.csv
```

**执行结果**（两次实测：10-13 首跑 96s（W1 基线）；10-14 `--force` 79s 正式版，16 线程）：

| 口径 | 输入 | 参与聚类 | 代表 MAGs |
|---|---|---|---|
| 正式版（重组装后） | 269 | 233 | **128** |
| W1 基线（重组装前） | 269 | 234 | 127 |

正式版 128 代表 = **HQ 96（comp≥90/cont≤5）+ MQ 32**（全部达 MIMAG medium，CP2-MAG 核真）。聚类构成：78 单例 + 19×2 + 16×3 + 7×4 + 7×5 + 1×6（233 个基因组归 128 簇）。

**⚠️ 注意事项（NOTES.md 待披露项落实）**：
- **实际质量门槛为 comp≥75 / cont<25，非 ≥50/≤10**：dRep 对 genomeInfo 施加内建默认过滤，269 个（50/10 口径）MAG 中 36 个被挡在聚类之外（以 filtered_report 重算 comp≥75/cont<25 恰为 233，与 Cdb.csv 行数吻合）。即 38 的有效输入比 37 的过滤产出更严。
- dRep 拒绝写入已有人口的工作目录——脚本先行 `rm -rf` 输出目录（Project01 三次陈旧 MAG 计数假成功的教训）。

**执行点评**（执行方起草）：
- **运算时间**：79–96 秒（skani 二级聚类远快于 fastANI）。
- **输出文件**：`dereplicated_genomes/`（128 .fa，~352M）、`data_tables/Cdb.csv`（233 行聚类表）。
- **后续使用**：128 代表是 38b GUNC、39/39b–d 定量与菌株分析、40 GTDB-Tk、41 系注释、43 GEM 链的统一 MAG 集。
- **加速空间**：分钟级，无需优化。
- **内存/硬盘**：温和。

---

## 38b · GUNC 嵌合/污染二次质检（CheckM2 互补层）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 38b GUNC 嵌合检测（progenomes2.1 库，threads 16），完成后汇报 pass/fail 计数。」

**核心执行命令**（摘自 `scripts/38b_bac_gunc.sh`；timeout 外层守卫防 diamond 子进程挂起空转）：

```bash
timeout --signal=TERM --kill-after=60 21600 \
    conda run --prefix envs/gunc --no-capture-output \
    gunc run \
        -d result/binning/drep/dereplicated_genomes \
        -e .fa \
        -r db/gunc/gunc_db_progenomes2.1.dmnd \
        -t 16 \
        -o result/binning/gunc \
        --temp_dir temp/gunc \
        --detailed_output
```

**执行结果**（两次实测：10-13 首跑 1475s（W1 基线，127 MAGs）；10-14 `--force` 1510s 正式版，16 线程）：

| 口径 | MAGs | GUNC pass | GUNC fail |
|---|---|---|---|
| 正式版（128 代表） | 128 | **81** | **47** |
| W1 基线（127 代表） | 127 | — | — |

fail 组 CSS（clade separation score）中位数 0.57、范围 0.46–1.0（嵌合/跨谱系污染信号）。主结果表：`result/binning/gunc/GUNC.progenomes_2.1.maxCSS_level.tsv`。

**⚠️ 注意事项（GUNC 披露，拍板 #2）**：
- **全量保留，不做二次过滤**：47 个 fail MAG 不从 128 代表集中剔除——演示定位为如实记录 GUNC 信号；**下游消费 GUNC 一律以汇总 TSV 为准**（per-MAG 判读回溯 `GUNC.*.tsv`）。
- gunc_output 目录曾混入 16 个 W1 陈旧文件（计数 144≠128），P1 修复后 `--force` 前清空旧产物（commit 002e3ae）；对已存旧产物不追溯，以汇总 TSV 为唯一事实源。

**执行点评**（执行方起草）：
- **运算时间**：1475–1510 秒/轮（16 线程 diamond vs progenomes2.1 全库，128 MAGs ~25 分钟）。
- **输出文件**：`GUNC.progenomes_2.1.maxCSS_level.tsv`（主表，128 行）+ 各 taxlevel 明细。
- **后续使用**：与 37 CheckM2 互补的嵌合层；统计/解读时按上表披露口径标注 47 个嵌合信号 MAG。
- **加速空间**：分钟级；`--sensitive` 可换更严格模式（本次默认档）。
- **内存/硬盘**：progenomes2.1 dmnd ~10G 常驻；输出 ~191M。

---

## ⚠️ W1 基线对照（CP2-MAG 拍板 A：重组装前后对照）

CP2-MAG 关口 C1 要求的原始基线（重组装前口径）由影子工作目录重建（`/tmp/lane_w1_baseline.sh`：
symlink dastool bins 进隔离 workdir 跑 37/38/38b，现行路径零接触；产物归档于 2026-10-15）：

| 指标 | W1 基线（重组装前） | 正式版（重组装后） |
|---|---|---|
| CheckM2 过滤（50/10） | 269 | 269 |
| dRep 代表 | **127** | **128** |
| 代表集构成 | — | 与正式版交集 111；+17 新入 / −16 出局 |

重组装净效应：+1 代表（127→128），33 个代表席位易主（17 新入 / 16 出局，六样本均有轮换）——
重组装对边缘 MAG 的 comp/cont 改写足以改变 dRep 择优结果，佐证 36b 真实生效（352/353 字节级改写）。
基线产物：`checkm2_w1_baseline/`、`drep_w1_baseline/`、`gunc_w1_baseline/`。

---

## 39 · CoverM genome MAG 丰度定量

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 39 MAG 丰度定量（CoverM genome，threads 16），完成后汇报各样本定量 MAG 数。」

**核心执行命令**（摘自 `scripts/39_bac_coverm_quant.sh`）：

```bash
coverm genome \
    -p minimap2-sr \
    -t 16 \
    -x fa \
    --min-covered-fraction 0 \
    -m relative_abundance rpkm tpm count covered_bases \
    -d result/binning/drep/dereplicated_genomes \
    -1 {sample}_1.kneaddata.fastq.gz \
    -2 {sample}_2.kneaddata.fastq.gz \
    -o result/binning/coverm_quant/{sample}.tsv
```

**执行结果**（2026-10-16 实测，6/6 成功，542–734 秒/样本）：每样本 128 个 MAG ×5 种度量（Relative Abundance/RPKM/TPM/Read Count/Covered Bases）+ 1 行 unmapped（合计 129 数据行 × 6 样本）。产出：`result/binning/coverm_quant/<样本>.tsv`（六文件合计 ~64K）。

**执行点评**（执行方起草）：
- **运算时间**：542–734 秒/样本（reads 比对回 330M 合并参考为瓶颈）。
- **输出文件**：每样本一个宽表（行=MAG，列=5 度量）。
- **后续使用**：MAG 相对丰度矩阵直接供差异分析与 98 系统计；TPM 列可用于跨样本归一。
- **加速空间**：样本间可并行。
- **内存/硬盘**：温和；表格文本量极小。

---

## 39b · inStrain 比对准备（合并参考 + .stb + 排序 BAM）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 39b inStrain 比对准备（threads 16），完成后汇报合并参考与各样本 BAM。」

**核心执行命令**（摘自 `scripts/39b_bac_instrain_map.sh`；合并参考用 mkdir 原子锁防多样本并行竞争）：

```bash
# 128 个 MAG 拼接为单一参考：scaffold 加 "MAG名__" 前缀并剥离 header 附加字段，
# 同时生成 scaffold-to-bin 映射 combined_mags.stb（scaffold<TAB>MAG）
coverm make \
    -p minimap2-sr \
    -t 16 \
    -r result/binning/instrain_map/combined_mags.fa \
    -1 {sample}_1.kneaddata.fastq.gz \
    -2 {sample}_2.kneaddata.fastq.gz \
    -o result/binning/instrain_map/{sample}
# BAM 重命名 + samtools index（inStrain profile 需索引）
```

**执行结果**（2026-10-16 实测，6/6 成功，486–656 秒/样本）：合并参考 `combined_mags.fa` 330M + `combined_mags.stb` 1.8M（跨样本共享只建一次）；每样本 `{sample}.sorted.bam(+.bai)`，目录合计 ~42G。

**执行点评**（执行方起草）：
- **运算时间**：486–656 秒/样本（比对回 128 基因组合并参考）。
- **输出文件**：合并参考 + .stb + 六样本排序索引 BAM。
- **后续使用**：39c inStrain profile 的直接输入；.stb 使 profile 结果能按 MAG 聚合。
- **加速空间**：样本间可并行（合并参考构建有原子锁保护）。
- **内存/硬盘**：42G BAM 是 inStrain 链主要磁盘成本，profile 完成后可归档。

---

## 39c · inStrain profile 样本内菌株微多样性（×6）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 39c inStrain profile（threads 16），完成后汇报各样本覆盖基因组数与 SNV 数。」

**核心执行命令**（摘自 `scripts/39c_bac_instrain_profile.sh`）：

```bash
inStrain profile \
    result/binning/instrain_map/{sample}/{sample}.sorted.bam \
    result/binning/instrain_map/combined_mags.fa \
    -o result/binning/instrain_profile/{sample} \
    -s result/binning/instrain_map/combined_mags.stb \
    -p 16 \
    --pairing_filter all_reads
```

**执行结果**（2026-10-16/17 实测，6/6 成功，11,606–16,105 秒/样本 = 3.2–4.5h，六样本串行合计约 24h）：

| 样本 | 耗时 | 覆盖基因组 | SNVs |
|---|---|---|---|
| Sample<N> | 14,454s | 128 | 1,259,280 |
| Sample<N> | 11,606s | 128 | 707,867 |
| Sample<N> | 16,105s | 128 | 1,427,850 |
| Sample<N> | 15,748s | 128 | 1,347,599 |
| Sample<N> | 12,250s | 128 | 905,103 |
| Sample<N> | 15,727s | 128 | 1,409,582 |

产出：每样本 `output/{sample}_{genome_info,scaffold_info,SNVs,linkage,mapping_info}.tsv(.gz)`（目录合计 ~28G）。

**执行点评**（执行方起草）：
- **运算时间**：3.2–4.5 小时/样本（逐 scaffold 逐位点扫描 128 基因组，inStrain 链最耗时步骤）。
- **输出文件**：genome_info（覆盖度/微多样性/popANI 就绪统计）、SNV 表（0.71–1.43M 位点/样本）、linkage 连锁表。
- **后续使用**：39d 跨样本 compare 的输入；`_genome_info.tsv` 亦用于按 MAG 过滤有效覆盖。
- **加速空间**：样本间可并行（内存允许时）；`--pairing_filter all_reads` 已是宽松档。
- **内存/硬盘**：~28G 输出 + 上游 42G BAM；SNV/linkage 表为主要增量。

---

## 39d · inStrain compare 跨样本 popANI（同株判定）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 39d inStrain 跨样本比较（threads 16），完成后汇报成对样本数与同株判定结果。」

**核心执行命令**（摘自 `scripts/39d_bac_instrain_compare.sh`；后处理把 genomeWide 长表折成宽矩阵）：

```bash
inStrain compare \
    -i result/binning/instrain_profile/Sample<N> ... Sample<N> \
    -o result/binning/instrain_compare \
    -s result/binning/instrain_map/combined_mags.stb \
    -p 16
# python3 后处理：每 genome 汇总各样本对 popANI，
# all_same_strain = 全部样本对 popANI ≥ 0.99999
```

**执行结果**（2026-10-17 实测，成功，7399 秒 = 2.06h）：6 样本 → 15 个样本对；comparisonsTable 237,170 行（scaffold 级），genomeWide 长表 1,920 行（= 128 基因组 × 15 对），汇总矩阵 `strain_comparison_summary.tsv` 128 基因组。**全 15 对样本均判同株（popANI≥0.99999）的基因组数 = 0**（全跨样本共存 MAG 均存在菌株替换/漂移，如 Sample<N>__maxbin2_bin.021_sub 最小 popANI 0.9948）。

**执行点评**（执行方起草）：
- **运算时间**：7399 秒（两两 profile 重建比对，15 对组合）。
- **输出文件**：comparisonsTable / genomeWide / strain_clusters（751 行）/ summary 宽矩阵（~97M 合计）。
- **后续使用**：同株判定列（all_same_strain）与 min_popANI 可直接进统计段做 treat/control 菌株更替分析。
- **加速空间**：`-p` 已 16 线程；样本对数为组合增长，样本多时可分块。
- **内存/硬盘**：温和。

---

## 40 · GTDB-Tk 分类（R214，identify→align→classify 三步）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 40 GTDB-Tk MAG 分类（threads 16），完成后汇报分类 MAG 数与物种/属级多样性。」

**核心执行命令**（摘自 `scripts/40_bac_gtdbtk.sh`；分步执行避开 classify_wf 的 skani 依赖）：

```bash
export GTDBTK_DATA_PATH=$REPO/db/gtdbtk   # GTDB R214
gtdbtk identify --genome_dir result/binning/drep/dereplicated_genomes \
                --out_dir result/binning/gtdbtk -x fa --cpus 16
gtdbtk align   --identify_dir result/binning/gtdbtk --out_dir ... --cpus 16
gtdbtk classify --genome_dir result/binning/drep/dereplicated_genomes \
                --align_dir result/binning/gtdbtk --out_dir ... -x fa --cpus 16
```

**执行结果**（2026-10-15 实测，成功，3054 秒 = 51 分钟，16 线程）：**128/128 MAGs 全部获分类**（`gtdbtk.bac120.summary.tsv`，无古菌命中）。分类深度：全部止步属级——**128 个 MAG 无一获得种级指派（s__ 空）**，可作"潜在新种候选集"解读口径；distinct 属 81 个。门级构成：Bacillota_A 77、Bacteroidota 17、Actinomycetota 10、Bacillota 8、Bacillota_C 7、Pseudomonadota 6、Fusobacteriota 1、Desulfobacterota 1。

**执行点评**（执行方起草）：
- **运算时间**：3054 秒（identify 的 marker 检索为主；genomeInfo 无关，128 MAGs 规模友好）。
- **输出文件**：`classify/gtdbtk.bac120.summary.tsv`（128 行）+ MSA/树文件（目录 ~781M）。
- **后续使用**：属名喂 41 Prokka `--genus`（全部 128 个 MAG 命中）；分类列供 98 系按门/属聚合。
- **加速空间**：线程已 16；与 iphop 等高内存步骤错峰即可（四审放宽令）。
- **内存/硬盘**：R214 库索引常驻数十 G 内存；输出 ~781M。

---

## 41 · Prokka 批量注释（GTDB 属名增强）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 41 Prokka 批量 MAG 注释（threads 16），完成后汇报注释 MAG 数与 CDS 总数。」

**核心执行命令**（摘自 `scripts/41_bac_prokka.sh`；对 128 个 MAG 逐个循环调用）：

```bash
prokka --outdir result/binning/prokka/{mag} \
       --prefix {mag} --locustag {mag} --cpus 16 \
       --kingdom Bacteria --metagenome \
       --mincontiglen 200 --rfam --force \
       --genus {GTDB属名}            # 从 40 的 summary.tsv 提取
       result/binning/drep/dereplicated_genomes/{mag}.fa
# 全部完成后合并各 MAG 的 .tsv 为 prokka_summary.tsv
```

**执行结果**（2026-10-15 实测，成功，批日志耗时 20,778 秒 = 5.8h）：**128/128 MAG 注释成功、失败 0**；合并表 `prokka_summary.tsv` 307,798 条 CDS 注释行；128 个 MAG 全部用上 GTDB-Tk 属名（batch.log 计数 128）。产出目录 ~3.5G（每 MAG gff/faa/ffn/gbk/tsv）。

**⚠️ 注意事项**：
- **首跑即炸（2026-10-15 01:34，exit 1、1 秒）**：`MAG_FILTER` 在 `set -u` 下未初始化（不传 `-m` 即触发 unbound variable）。修复：预初始化 `MAG_FILTER=""`（commit 639b750；同日 43/43b 的"-t 声明未注册"同属首跑接口缺陷家族，36f8b29）。此后 P0 防线 ①（mgx_parse 预初始化全部带值选项）从源头消灭此类。
- `--force` 会清空整个 prokka 输出目录重建（防上一轮孤儿目录残留）。

**执行点评**（执行方起草）：
- **运算时间**：20,778 秒/128 MAGs ≈ 2.7 分钟/MAG（16 线程，`--rfam` 的 Infernal 扫描占大头）。
- **输出文件**：每 MAG 七件套 + prokka_summary.tsv + prokka_done.txt。
- **后续使用**：gff 供 41c Roary；faa/ffn 供后续功能查询；`--genus` 使 locus 命名带分类语义。
- **加速空间**：MAG 级并行（目录级注释互斥安全）；或去掉 `--rfam` 换速度（损失 ncRNA 注释）。
- **内存/硬盘**：温和；~3.5G 输出。

---

## 41b · MLST 分型（mlst 聚合扫描）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 41b MLST 分型（threads 16），完成后汇报分型结果。」

**核心执行命令**（摘自 `scripts/41b_bac_mlst.sh`）：

```bash
mlst --nopath --quiet --threads 16 \
     result/binning/drep/dereplicated_genomes/*.fa > mlst_raw.txt
# 后处理为 FILE/SCHEME/ST/ALLELES 四列表
```

**执行结果**（2026-10-15 实测，成功，102 秒）：128 MAGs 全部扫描，**scheme 与 ST 全部为 "-"（0 个 MAG 命中任何 MLST 方案）**——GTDB 门级构成以 Bacillota_A 等肠道共生菌为主，多数种不在 PubMLST 病原 scheme 覆盖内，属宏基因组 MAG 集的**预期空产出**（非错误）。

**执行点评**（执行方起草）：
- **运算时间**：102 秒（blast 同源扫描，极快）。
- **输出文件**：`result/wgs/mlst/mlst.tsv`（128 行全 "-"）+ mlst_raw.txt。
- **后续使用**：无下游消费（空产出）；如实成章记录。
- **加速空间**：无需。
- **内存/硬盘**：极小。

---

## 41c · Roary 泛基因组（多物种 MAG 集，预期早退）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 41c Roary 泛基因组分析（threads 16），完成后汇报 core/accessory 基因统计。」

**核心执行命令**（摘自 `scripts/41c_bac_pangenome.sh`）：

```bash
roary -p 16 -e --mafft -i 95 -cd 99 \
      -f result/wgs/pangenome \
      result/binning/prokka/*/*.gff
# 脚本对 "cluster count exceeds --group_limit" 的 Roary 零退出早退
# 有专门检测，写 FAILED 哨兵（此为设计内路径，非脚本缺陷）
```

**执行结果**（2026-10-15 实测，exit 0，22,572 秒 = 6.3h）：Roary 聚出 **280,555 簇 > --group_limit 50,000**，按官方语义提前退出（"Multifastas not created"），写 FAILED 哨兵（`summary_statistics.txt` 记 WARNING + INPUT_GFFS=128）。**原因定性：128 个 MAG 是跨属多物种集合（81 属），泛基因组分析对象错位**——Roary 适用于同种近缘基因组组，本结果不代表污染（哨兵文案已注明）。

**执行点评**（执行方起草）：
- **运算时间**：22,572 秒（绝大部分耗在聚类到达 5 万簇上限前的 CD-HIT/BLAST 全比对）。
- **输出文件**：summary_statistics.txt（WARNING 哨兵）、roary.log、presence_absence_matrix.txt（NA）。
- **后续使用**：无（预期空产出）；如需真正泛基因组，应对单物种内多 MAG 子集单独运行（按 40 的属标签过滤后重跑）。
- **加速空间**：提高 `--group_limit` 可跑完但产出无解释意义，不建议。
- **内存/硬盘**：温和。

---

## 41d · Snippy 核心 SNP（跨样本 MAG 集零核心位点）

**启动本步骤（复制给 AI 助手）**：
> 「请执行 41d Snippy SNP 分析（threads 16），完成后汇报核心 SNP 数。」

**核心执行命令**（摘自 `scripts/41d_bac_snippy.sh`；不传 -R 时取最大 MAG 作参考）：

```bash
snippy --cpus 16 --ref Sample<N>__metabat2_bin.120.fa \
       --ctgs {mag}.fa --outdir result/wgs/snippy/{mag} --force   # ×128
snippy-core --ref Sample<N>__metabat2_bin.120.fa --prefix core {snippy_dirs}
snippy-clean_full_aln core.full.aln > core.clean.aln
```

**执行结果**（2026-10-15 实测，成功，2050 秒 = 34 分钟）：参考 = 最大 MAG `Sample<N>__metabat2_bin.120`（4.56Mb）；**128/128 MAG 单独比对全部成功，核心 SNP 总数 = 0**（core.tsv 仅表头）。这是宏基因组场景的**预期结果**：跨样本独立组装的 MAG 本质是不同基因组（81 属集合），core 区域无共同多态位点——脚本对 snippy-core 尾部 snp-sites "No SNPs" 非零退出有专门豁免（core.full.aln/core.tab 齐全即算成功，见脚本注释）。

**执行点评**（执行方起草）：
- **运算时间**：2050 秒（128 次 minimap2 比对为主）。
- **输出文件**：core.tsv（空表头）、core.full.aln、core.clean.aln、summary.txt、每 MAG snps.tab 子目录。
- **后续使用**：无统计意义（预期空产出）；菌株级差异请用 39d popANI 口径。
- **加速空间**：无需。
- **内存/硬盘**：~6.1G（wgs 目录，主要为 128 个 snippy 子目录中间件）。

---

## 42 · MGE 可移动元件综合注释（五工具）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 42 MGE 注释（ISfinder/ICEberg/integrall/transposase/mobileOG，threads 8），完成后汇报各样本各工具命中数。」

**核心执行命令**（摘自 `scripts/42_bac_mge.sh`；W3-C 插空泳道 -t 8）：

```bash
# 1) ISfinder：蛋白级 mmseqs（--min-seq-id 0.9 -e 1e-5）
mmseqs easy-search --threads 8 --max-accept 1 -e 1e-5 --min-seq-id 0.9 \
    result/assembly/prodigal/{sample}/{sample}.faa db/ISfinder/... isfinder_hits.tsv
# 2) ICEberg：contig 级 blastn（-perc_identity 70 -evalue 1e-5 -max_target_seqs 5）
# 3) integrall：基因核酸级 blastn（-perc_identity 90 -evalue 1e-5）
# 4) transposase：hmmscan vs transposase.hmm（--tblout）
# 5) mobileOG：NR 蛋白集 diamond blastp（--id 60 --min-score 30，aggregate 仅一次）
```

**执行结果**（2026-10-14 实测，6/6 成功，1,176–2,738 秒/样本）：

| 样本 | 耗时 | ISfinder | ICEberg | integrall | transposase |
|---|---|---|---|---|---|
| Sample<N> | 2,738s | 401 | 33,874 | 298,983 | 9,183 |
| Sample<N> | 1,206s | 229 | 25,761 | 249,538 | 7,595 |
| Sample<N> | 1,716s | 323 | 39,694 | 370,291 | 11,300 |
| Sample<N> | 1,559s | 245 | 33,361 | 315,958 | 9,519 |
| Sample<N> | 1,176s | 642 | 31,422 | 248,662 | 8,114 |
| Sample<N> | 1,530s | 181 | 33,675 | 324,620 | 10,325 |

mobileOG NR 级（六样本共享一份）：**65,291** 条命中。

**执行点评**（执行方起草）：
- **运算时间**：1,176–2,738 秒/样本（8 线程插空负载；contig/基因级 blastn 与蛋白级比对混合负载）。
- **输出文件**：`result/mge/{isfinder,iceberg,integrall,transposase}/<样本>/*_hits.tsv` + `mobileog/mobileog_nr_hits.tsv`（~150M）。
- **后续使用**：结合 Salmon TPM 与 mobileOG 层级可量化各 MGE 类型丰度（脚本尾注提示）；integrall 命中为基因级计数（25–37 万行/样本），统计时需先按基因去重/按 contig 聚合。
- **加速空间**：mobileOG 是 aggregate 一次成本；样本级四工具可并行。
- **内存/硬盘**：温和。

---

## 42b · PlasmidFinder 质粒 replicon 识别

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 42b PlasmidFinder 质粒识别（threads 8），完成后汇报各样本 replicon 命中数。」

**核心执行命令**（摘自 `scripts/42b_bac_plasmidfinder.sh`；conda 包内置 DB，覆盖度 60%/相似度 95% 官方阈值）：

```bash
plasmidfinder.py \
    -i  result/assembly/megahit/{sample}/{sample}.contigs.fa \
    -o  result/mge/plasmidfinder/{sample} \
    -p {conda内置database路径} \
    -l  0.60 \
    -t  0.95 \
    -x -q
```

**执行结果**（2026-10-14 实测，6/6 成功，513–895 秒/样本；W3-C 插空 -t 8）：

| 样本 | 耗时 | replicon 命中 |
|---|---|---|
| Sample<N> | 613s | 16 |
| Sample<N> | 513s | 4 |
| Sample<N> | 895s | 8 |
| Sample<N> | 605s | 7 |
| Sample<N> | 616s | 25 |
| Sample<N> | 775s | 4 |

命中 4–25 条/样本（Sample<N> 最多，与其全链微生物负载最高的样本特征一致）。产出：`results_tab.tsv`（replicon 类型 + 不相容群）+ 命中 contig 序列。

**执行点评**（执行方起草）：
- **运算时间**：513–895 秒/样本（对全 contig 集做短序列库 blastn）。
- **输出文件**：每样本 results_tab.tsv + Hit_in_genome_seq.fsa。
- **后续使用**：与 26/27 AMR 结果关联（质粒携带耐药基因定位）；与 42 mobileOG 质粒基因维度互补（基因为何、质粒为何型）。
- **加速空间**：样本间可并行。
- **内存/硬盘**：温和。

---

## 43 · gapseq GEM 重建（首选路径，10/10 未产出 SBML——披露）

**启动本步骤（复制给 AI 助手）**：
> 「请对 GEM 前 10 名单（CheckM2 comp−cont 排序，logs/evidence/gem_top10.txt）逐一执行 43 gapseq 建模（-t 8，插空负载），完成后汇报各 MAG 模型产出。」

**核心执行命令**（摘自 `scripts/43_bac_gem_gapseq.sh`；单 MAG 模式循环）：

```bash
# < /dev/null：gapseq_find.sh 会读 stdin，nohup 泳道的常开管道会令其永久阻塞
conda run --prefix envs/gapseq gapseq find -p all -b 200 {mag}.fa < /dev/null
conda run --prefix envs/gapseq gapseq draft \
    -r {mag}-all-Reactions.tbl -t {mag}-all-Transporter.tbl \
    -p {mag}-all-Pathways.tbl -c {mag}.fa -u 200 -l 100 < /dev/null
conda run --prefix envs/gapseq gapseq fill \
    -m {mag}-draft.RDS -n medium -c rxnWeights.RDS -g rxnXgenes.RDS
Rscript convert_sbml.R {mag}-gapfilled.RDS {mag}.xml   # RDS → SBML
```

**前 10 名单**（CheckM2 comp−cont 降序；comp 99.73–100、cont 0–0.22）：
Sample<N>__bin.019_sub（100/0）、Sample<N>__bin.009、Sample<N>__92、Sample<N>__metabat2_bin.120、Sample<N>__137、Sample<N>__154、Sample<N>__76、Sample<N>__bin.025_sub、Sample<N>__27、Sample<N>__semibin2_91。

**执行结果**（2026-10-15 → 10-18 实测，10 个 MAG 逐一单跑，22,471–31,128 秒/MAG = 6.2–8.6h，累计 269,304 秒 ≈ 74.8h）：

> ⚠️ **gapseq 路径 10/10 未产出 SBML**：每 MAG 燃尽 6–9 小时后止步 draft 阶段——`gapseq find` 只产出 Pathways/Reactions 两表（Transporter.tbl 缺失），且 `gapseq draft` 报 `there is no package called 'cobrar'`（envs/gapseq 缺 gapseq 1.3+ 所需的 R cobrar 包）。脚本按"部分失败 exit 0"语义放行（批日志：成功 0 / 失败 1/MAG）。GEM 链的实际 SBML 全部来自 43b CarveMe（见下章）；gapseq 各 MAG 目录仅留 gapseq.log + 两张 tbl。

**⚠️ 注意事项**：
- **首跑接口事故（2026-10-15）**：43/43b 的 `-t` 声明未注册进解析表，首次实跑即"未知参数"退出（commit 36f8b29 修复）；43c 因此连带 10 连空跑（run_events 00:56 十条 exit=1、0–1 秒）。
- **stdin 挂起教训（2026-10-15）**：gapseq find 读 stdin，泳道 nohup 管道令其挂起——一度误诊"挂起 80 分钟"（实为漏看 tblastn/parallel 阶段进程）；修复为 `< /dev/null`，并确立"判挂起前必须按进程树 PPID 链全量枚举"规程（NOTES.md）。

**执行点评**（执行方起草）：
- **运算时间**：6.2–8.6 小时/MAG（find 的全通路 homology 搜索为主；gapseq 无线程控制，-t 仅接口占位）。
- **输出文件**：`result/gem/gapseq/<MAG>/`（本演示实际只含 log + Pathways/Reactions tbl）。
- **后续使用**：43c 优先找 gapseq XML，缺失时回退 carveme——本链全部走了回退分支。
- **加速空间**：修复路径 = 补装 R cobrar + 排查 Transporter 搜索缺失（TCdb 库未配置的嫌疑最大）；单 MAG 串行 6–9h，多 MAG 需并行才可控。
- **内存/硬盘**：温和（~134M GEM 总目录）。

---

## 43b · CarveMe GEM 重建（BiGG 快速路径，9/10）

**启动本步骤（复制给 AI 助手）**：
> 「请对 GEM 前 10 名单执行 43b CarveMe 建模（--dna --gapfill auto），完成后汇报成功数与失败明细。」

**核心执行命令**（摘自 `scripts/43b_bac_gem_carveme.sh`）：

```bash
conda run --prefix envs/carveme carve \
    --dna \
    --fbc2 \
    --gapfill auto \
    --output result/gem/carveme/{mag}/{mag}.xml \
    result/binning/drep/dereplicated_genomes/{mag}.fa
# 少数 per-MAG solver 失败（reframed/SCIP 空解）是多物种 MAG 集的预期内事件，
# 仅当全部失败才整体报错；失败清单落 failed_mags.txt
```

**执行结果**（2026-10-18 实测，10 MAG 逐一执行，622–632 秒/MAG ≈ 10.4 分钟，合计 ~1.7h）：**9/10 成功产出 SBML（fbc2 格式）**。

> ⚠️ **披露：Sample<N>__bin.025_sub 失败**——CarveMe gapfill 阶段 reframed SCIP 求解器返回空解（`scip_solver.py` 抛 TypeError: 'NoneType' object is not subscriptable，工具内部数值问题），无 SBML 产出；按演示口径**不重试**，其 43c FBA 连带缺席（GEM 链 9/10 全通的由来）。

产出：`result/gem/carveme/<MAG>/<MAG>.xml` ×9 + carveme.log ×10。

**⚠️ 注意事项（副作用披露）**：CarveMe 把内部 diamond 比对中间表写到了输入 FASTA 同目录——`drep/dereplicated_genomes/` 下因此混入 10 个 `<MAG>.tsv`（47KB 级，2026-10-18 04:12 起）。不影响下游按 `*.fa` 消费，但该目录已非纯 MAG 目录；建议后续泳道输出隔离或在 43b 内显式 `--tmp`。

**执行点评**（执行方起草）：
- **运算时间**：~10.4 分钟/MAG（vs gapseq 6–8.6h，BiGG universe carve 是数量级更快的路径；NOTES 拍板按此估算全量 128 需 2–4 天）。
- **输出文件**：9 个 SBML + failed_mags.txt 清单。
- **后续使用**：43c FBA 的实际模型来源（find_sbml_model 优先 gapseq、回退 carveme）。
- **加速空间**：MAG 间可并行；solver 失败不可预测，重试或换 gapfill=none 是备选。
- **内存/硬盘**：温和。

---

## 43c · COBRApy FBA 模拟（生长速率/必需基因/底物利用）

**启动本步骤（复制给 AI 助手）**：
> 「请对已有 SBML 模型的 MAG 执行 43c COBRApy FBA（生长速率+通量分布+单基因敲除+底物利用），完成后汇报各 MAG 生长速率。」

**核心执行命令**（摘自 `scripts/43c_bac_gem_cobrapy_fba.sh` + `43c_fba_simulate.py`）：

```bash
# 自动搜索模型：优先 gapseq、回退 carveme（本链实际全部命中 carveme）
conda run --prefix envs/cobrapy python3 scripts/43c_fba_simulate.py \
    --model result/gem/carveme/{mag}/{mag}.xml \
    --output-dir result/gem/fba/{mag} \
    --threads 8
# python3 内部四连：FBA 优化 → 通量表 → single_gene_deletion（生长<WT 1% 判必需）
#                        → 底物利用（自动检出模型交换反应，关闭其他碳源单测）
```

**执行结果**（2026-10-18 实测，9/10 成功——Sample<N>__bin.025_sub 因 43b 无模型缺席；首个 14 秒、其后 6–7 秒/MAG）：

| MAG | FBA 生长速率 |
|---|---|
| Sample<N>__bin.009 | 18.442522 |
| Sample<N>__92 | 17.633499 |
| Sample<N>__metabat2_bin.120 | 17.429489 |
| Sample<N>__27 | 17.273713 |
| Sample<N>__semibin2_91 | 13.170058 |
| Sample<N>__154 | 10.115609 |
| Sample<N>__bin.019_sub | 9.113902 |
| Sample<N>__76 | 9.104111 |
| Sample<N>__137 | 7.724565 |

每 MAG 产出四件：`_growth_rate.txt`（上表）、`_flux_distribution.tsv`（全反应通量）、`_essential_genes.tsv`（例 Sample<N>__bin.019_sub 10 个必需基因）、`_substrate_utilization.tsv`（自动检出碳源逐一单测，例 8 项）。至此 GEM 链收官（2026-10-18 05:36，NOTES W4-C 收官记录）。

**⚠️ 注意事项**：
- 10-15 首轮 10 连空跑（exit 1、0–1 秒）系 43/43b `-t` 未注册事故连带（见 43 章）；本轮为修复后正式执行。

**执行点评**（执行方起草）：
- **运算时间**：6–14 秒/MAG（LP 求解 + 单基因敲除批量 LP；线程参数作用于敲除并行）。
- **输出文件**：每 MAG 四表 + fba_batch.log + fba_done.txt。
- **后续使用**：生长速率/必需基因/底物谱可进入 MAG 功能解读与群落代谢讨论；9/10 口径须与 Sample<N>__bin.025_sub 缺席披露同引。
- **加速空间**：秒级无需优化；模型来自 CarveMe 的口径需在方法学描述中注明（gapseq 路径未产出）。
- **内存/硬盘**：极小。

## 54 · CheckV 病毒 contig 质检（geNomad∩VirSorter2 交集主结果 + 并集敏感性）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 54 CheckV 病毒 contig 质检（geNomad∩VirSorter2 交集为主结果，同时产出并集敏感性 FASTA，threads 16），完成后汇报各样本交集/并集 contig 数与前病毒保留数。」

**核心执行命令**（摘自 `scripts/54_vir_checkv_contig.sh`；判定层先做交集，再交 CheckV）：

```bash
# 交集按"基础 contig ID"匹配（剥 |provirus 后缀；sed 不用 cut——GNU cut 不接受多字符分隔符）
comm -12 \
    <(grep '^>' "${GENOMAD_VIRUS}" | sed 's/^>//; s/ .*//; s/|.*//' | sort -u) \
    <(grep '^>' "${VS2_VIRUS}"  | sed 's/^>//; s/||.*//' | sort -u) \
    > common_ids.txt
# 用 awk 按基础 ID 抽取（seqkit grep 匹配完整 ID 会静默丢弃全部 |provirus 条目，P0-2）
awk 'NR==FNR{k[$1];next} /^>/{id=substr($1,2);sub(/\|.*/,"",id);p=(id in k)} p' \
    common_ids.txt "${GENOMAD_VIRUS}" > virus_contigs.fasta
# CheckV end-to-end（conda env: checkv，CheckV 1.0.3）
checkv end_to_end virus_contigs.fasta ${OUTDIR} -d ${REPO}/db/checkv -t ${CPUS}
```

**执行结果**（2026-10-11 首跑，10-13/10-14 两轮整改重跑后为终态；各样本 call_stats.tsv 实测）：

| 样本 | geNomad | VirSorter2 | 交集（基础 ID） | 交集 FASTA 条目 | 前病毒保留 | 并集敏感性 | 并集去重键 |
|---|---|---|---|---|---|---|---|
| Sample<N> | 964 | 3,258 | 700 | 700 | 48 | 3,522 | base |
| Sample<N> | 654 | 2,346 | 466 | 466 | 51 | 2,534 | base |
| Sample<N> | 1,017 | 3,932 | 709 | 710 | 59 | 4,949 | **full**（1 条多前病毒） |
| Sample<N> | 1,151 | 3,635 | 828 | 830 | 61 | 4,786 | **full**（2 条多前病毒） |
| Sample<N> | 734 | 2,214 | 481 | 481 | 21 | 2,466 | base |
| Sample<N> | 1,058 | 3,589 | 764 | 764 | 52 | 3,883 | base |

合计交集 3,948 个基础 ID → 3,951 条 FASTA 条目（3 条多前病毒 contig 各贡献 2 段 provirus）；并集合计 22,140。CheckV 产出 quality_summary.tsv（3,951 行）、viruses.fna（3,711）、proviruses.fna（241）。首跑耗时 238–379 秒/样本。

**⚠️ 注意事项（三轮整改史，保留真实过程）**：
- **判定口径（2026-10-11 用户拍板）**：52 章原披露"并集敏感性产物待补做"即在本步落实——**交集做主结果**（严格，双工具共同判定）、**并集仅作敏感性分析**（`viruses_union_sensitivity.fna`）。前病毒按基础 contig ID 匹配保留 provirus 区域序列（质量审核 P0-1 方案 A；seqkit grep 曾静默丢弃全部前病毒条目，改 awk 实现，commit 3268f0b）。
- **第一轮（commit 193c7b2，10-12）**：并集敏感性输出首次落地，但实现有缺陷。
- **第二轮（commit 7b2e9ab，10-13，质量审核 P0-3 + 拍板 B）**：修复"**重复表头只丢表头、不丢序列行**"的 bug——旧实现 `awk '!/^>/{print;next} !seen[$1]++{print}'` 会把被跳过记录的序列行拼进上一条记录，FASTA 结构损坏；同时去重键从完整 ID 改为基础 ID（与交集同一规则，同 contig 的 provirus 变体与原序列合并）。
- **第三轮（commit d08d034，10-13 复审 P0）**：发现基础 ID 去重在"同一 contig 带多段 provirus"时会把交集里两段都保留的 provirus 在并集里合并掉一条，**并集不再 ⊇ 交集**（实测 Sample<N>=2 条、Sample<N>=1 条多前病毒）。改为条件逻辑：先统计交集内多前病毒 contig 数（`union_multi_provirus_contigs`），>0 则自动切换完整 ID 去重并把 `union_dedup_key=full` 写入 call_stats 审计，=0 则仍用 base 键。10-14 V3 泳道对 H1/H2/H4/H11 四样本 `--force` 补齐（首样本一次 exit=127 环境瞬时失败，1 分钟后重跑成功）。
- 另有 CheckV 断点续跑陷阱防御：输入 FASTA 比 tmp/ 新时自动清空旧中间结果（曾致 contamination.py KeyError）；`--force` 走 mgx_force_backup 备份旧产物（f7f6edb）。

**执行点评**（执行方起草）：
- **运算时间**：238–379 秒/样本（16 线程），整改期共 6 轮重跑（10-11×2、10-12×2、10-13×2、10-14×1 批）。
- **输出文件**：每样本 quality_summary.tsv（14 列 MIUVIG 口径）、viruses.fna、proviruses.fna+bed、viruses_union_sensitivity.fna、call_stats.tsv（审计：工具计数/交集数/去重键/多前病毒数）。
- **后续使用**：quality_summary 供 54b 过滤；交集病毒集供 55 基因预测与 56 vOTU 聚类；并集敏感性 FASTA 留作审稿人质询时的稳健性对照（不进主链）。
- **加速空间**：CheckV 本体不重；重跑成本来自上游判定口径变更，非计算瓶颈。
- **内存/硬盘**：每样本产物 10–40M 级；diamond 比对峰值内存 <10G。

---

## 54b · MIUVIG 质量过滤（CheckV 分级 + ≥2 kb + 病毒基因非零）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 54b MIUVIG 质量过滤（threads 16），完成后汇报各样本 TOTAL/PASSED/EXCLUDED。」

**核心执行命令**（摘自 `scripts/54b_vir_checkv_filter.sh`，纯 awk/seqkit 无重计算）：

```bash
awk -F '\t' 'NR==1{for(i=1;i<=NF;i++)idx[$i]=i;next}
{
    q=$(idx["checkv_quality"]); vg=$(idx["viral_genes"])+0; len=$(idx["contig_length"])+0
    keep_quality=(q=="Complete"||q=="High-quality"||q=="Medium-quality"||q=="Low-quality")
    keep_nd=(q=="Not-determined" && vg>0)          # 无 completeness 估计者须有病毒基因
    if ((keep_quality||keep_nd) && len>=2000) print $(idx["contig_id"])
}' quality_summary.tsv > viruses_filtered.ids
seqkit grep -f viruses_filtered.ids virus_contigs.fasta -o viruses_filtered.fna
```

**执行结果**（2026-10-11 首跑，后续随 54 整改联动重跑；各样本 viruses_filtered.stats 实测）：

| 样本 | TOTAL | PASSED | EXCLUDED |
|---|---|---|---|
| Sample<N> | 700 | 535 | 165 |
| Sample<N> | 466 | 354 | 112 |
| Sample<N> | 710 | 548 | 162 |
| Sample<N> | 830 | 650 | 180 |
| Sample<N> | 481 | 380 | 101 |
| Sample<N> | 764 | 595 | 169 |
| **合计** | **3,951** | **3,062** | **889** |

通过率 77.5%。单样本 2–3 秒。

**⚠️ 注意事项**：本步是 MIUVIG 质控门在病毒宇宙的强制接入点（T-15 整改，commit 5e243f1）——历史上 Snakemake 曾把未过滤的 viruses.fna 直喂 55/56，54b 形同虚设；现 55/56 均只认 `viruses_filtered.fna`，缺失即硬退出（56 的旧回退链 viruses.fna→virus_contigs.fasta 已删除）。

**执行点评**（执行方起草）：
- **运算时间**：2–3 秒/样本，可忽略。
- **输出文件**：viruses_filtered.fna（3,062 条，即下游全链的病毒宇宙）+ .ids + .stats。
- **后续使用**：55 基因预测、56 vOTU 聚类的唯一入口；质量审核 CP2 链路计数闭合验证 3,951→3,062→46,300（基因）即引用本步数字。
- **加速空间**：不适用。
- **内存/硬盘**：忽略不计。

---

## 55 · 前病毒基因预测（Prodigal -p meta；gv 为历史命名）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 55 病毒基因预测（Prodigal meta 模式，threads 16，上游有变更时必须带 --force），完成后汇报各样本预测基因数。」

**核心执行命令**（摘自 `scripts/55_vir_prodigal_gv.sh`；输入为 54b 的 MIUVIG 过滤集）：

```bash
prodigal -i result/virus/checkv/{sample}/viruses_filtered.fna \
         -a result/virus/prodigal/{sample}/{sample}.faa \
         -d result/virus/prodigal/{sample}/{sample}.fna \
         -f gff -o result/virus/prodigal/{sample}/{sample}.gff \
         -p meta
```

**执行结果**（2026-10-12/13 终态实测）：

| 样本 | contigs（54b 后） | 预测基因 | 耗时 |
|---|---|---|---|
| Sample<N> | 535 | 8,740 | 39s |
| Sample<N> | 354 | 6,542 | 30s |
| Sample<N> | 548 | 7,995 | 45s |
| Sample<N> | 650 | 9,215 | 44s |
| Sample<N> | 380 | 5,732 | 22s |
| Sample<N> | 595 | 8,076 | 42s |

合计 46,300 个基因（质量审核 CP2 闭合链第三环）。

**⚠️ 注意事项（真实失败史）**：
- **首轮 6 连败**（10-11 03:37）：紧跟 54 重跑后立即启动，0–1 秒全部 exit 1——当时 54b 尚未首跑（成功在当日 05:15），输入 viruses_filtered.fna 不存在与秒退一致；05:15 先补 54b 后 55 全部成功。
- **假成功事件（事故 #13，10-12 08:45）**：54 带 `--force` 重跑后，55 未带 `--force`，哨兵命中走跳过分支照记 ✓，实为旧产物——由此立红线"**上游 --force 重跑后，下游一律 --force**"（10-13），10-12 09:39 与 10-13 08:20 两轮带 --force 重跑为终态。
- 命名披露：标题中的 gv 为历史命名，实际未用密码表 15（meta_gv 属未来候选，未经 benchmark 不得切换）；`-p meta` 即遗传密码 11 的宏基因组模式（Prodigal 2.6.3）。

**执行点评**（执行方起草）：
- **运算时间**：22–53 秒/样本，病毒链最轻步骤。
- **输出文件**：每样本 .faa/.fna/.gff 三件套；0 条通过 contig 的样本写空哨兵优雅退出（T-15）。
- **后续使用**：曾供 58 旧版构建基因级索引（整改后 58 已不消费，见 58 章）；现主要为基因目录口径披露保留。
- **加速空间**：无需。
- **内存/硬盘**：<1G 内存；三件套每样本数 M。

---

## 56 · vOTU 聚类（vclust：prefilter→align→cluster，95% ANI / 85% qcov）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 56 vOTU 生成（vclust 跨样本 95% ANI 聚类，threads 16），完成后汇报 vOTU 数与成员 contig 数。」

**核心执行命令**（摘自 `scripts/56_vir_votu_gen.sh`；全项目级步骤，无 -s）：

```bash
# 合并 6 样本 viruses_filtered.fna，header 加 "样本__" 前缀（MEGAHIT 的 k127_* 仅样本内唯一）
sed "s/^/>${sample}__/" >> result/virus/votu/contigs/virus.fasta
vclust prefilter -i virus.fasta -o fltr.txt --min-ident 0.95
vclust align     -i virus.fasta -o ani.tsv --filter fltr.txt -t ${CPUS}
vclust cluster   -i ani.tsv -o clusters.tsv --out-repr --ids ani.ids.tsv \
                 --algorithm leiden --metric ani --ani 0.95 --qcov 0.85
```

**执行结果**（2026-10-13 终态实测）：合并后 **3,062 条**成员 contig（virus.fasta，含样本前缀）→ 聚成 **2,622 个 vOTUs**（votu_representatives.tsv）；votu_id_map.tsv 3,062 行（每个原始 ID 唯一映射到一个代表 vOTU，重复对象即硬失败 exit 3）。耗时 18 秒（10-12 首跑 18 秒）。

**⚠️ 注意事项**：
- votu_id_map.tsv 是 T-16 建立**canonical 身份映射**：下游（分类/丰度/功能/宿主/网络）一律经此表 join，禁止再用字符串截断（如剥 `_<数字>` 后缀会把 k127_1717 截成 k127）自行推导身份。
- 样本前缀 `SAMPLE__` 双下划线是 57 号 safe-ID 方案与 60 号基因行判定的锚点。

**执行点评**（执行方起草）：
- **运算时间**：18 秒（prefilter 先剔除明显不相似对，3 千条规模 align 很快）。
- **输出文件**：virus.fasta（成员全集）、vclust/clusters.tsv（3,062 行映射）、votu_id_map.tsv、votu_representatives.tsv。
- **后续使用**：病毒链下半场（58–72 全部注释/定量步骤）的唯一序列输入。
- **加速空间**：-t 线程已够；万条级 contig 时 align 才成瓶颈。
- **内存/硬盘**：votu/ 目录约 1.0G（含 vclust 中间表与 votu_fasta）。

---

## 57 · vOTU 分类学注释（geNomad 对代表全集，safe-ID 中转）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 57 vOTU 分类注释（geNomad end-to-end，threads 16），完成后汇报 taxonomy 行数。」

**核心执行命令**（摘自 `scripts/57_vir_votu_genomad.sh`）：

```bash
# 先把带样本前缀+下划线的 ID 替换成无下划线安全编号 seq1/seq2/...（geNomad 内部
# rsplit("_",N) 反推 contig 名，"Sample<N>__k127_116589" 会被拆错致 KeyError）
awk '/^>/{orig=substr($1,2); safe="seq"(++n); map[safe]=orig; print ">"safe; next}{print}' \
    virus.fasta > virus_safeid.fasta
genomad end-to-end --cleanup --threads ${CPUS} --sensitivity 4.2 --splits 4 \
    virus_safeid.fasta ${OUTDIR} ${REPO}/db/genomad/genomad/genomad_db
# 跑完按 id_map.tsv 把 seq_name 整段替换回原始 ID（|provirus 坐标后缀原样保留）
```

**执行结果**（2026-10-13 终态实测）：virus_taxonomy.tsv **2,959 行**（3,062 条成员中 geNomad 二次判定为病毒者）；科级以上注释稀疏（肠道宏基因组 contig 以新颖类群为主，17 条 Unclassified，其余多为 Caudoviricetes 未细分）。10-12 首跑 251 秒，10-13 终版 28 秒。

**⚠️ 注意事项**：灵敏度取 4.2（默认，复查场景），**低于** 52 章样本级鉴定用的 7.5——此处只做代表序列的复核注释，不再承担高灵敏召回职责。

**执行点评**（执行方起草）：
- **运算时间**：28–251 秒。
- **输出文件**：votu/genomad/virus_taxonomy.tsv（列名 taxonomy，10-14 三审后 91/92 的 R 代码已兼容此列名）。
- **后续使用**：60 号分类注释 join 的唯一来源。
- **加速空间**：不必要。
- **内存/硬盘**：--splits 4 分块降内存，峰值 <20G。

---

## 58 · Salmon vOTU 定量索引（只放 vOTU contigs——混合索引整改史）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 58 vOTU Salmon 索引构建（threads 16），完成后汇报索引规模。」

**核心执行命令**（摘自 `scripts/58_vir_salmon_build.sh` 终版）：

```bash
# 索引只含 vOTU contigs（拍板 D + 质量审核 2026-10-13 复审 P0-1）；
# 不传 -d（Salmon 0.14.1 与 decoy-aware 索引在 quant 时有 segfault 兼容问题，统一标准索引）
salmon index -t result/virus/votu/contigs/virus.fasta \
             -i result/virus/salmon/index -p ${CPUS} --keepDuplicates
```

**执行结果**（终态实测）：标准索引 621M，3,062 条 target（=vOTU 成员全集）；构建 36–58 秒。decoys.txt 保留（phase1_tierA_golden 基线 sha256 引用此文件，标准索引本身不消费）。

**⚠️ 注意事项（索引策略整改史——病毒链最重要的定量层修正）**：
- **旧策略（10-12 首版）**：gentrome = 55 号全部 CDS（.fna，加 `样本|` 前缀，拍板 E）+ vOTU contigs，同放索引，声称"同时支持基因级和 contig 级定量"。
- **问题实证（质量审核 10-13 复审 P0-1）**：Salmon EM 会把落在基因区的 reads **分摊给基因和 contig 两条 target**；60 号按拍板 D 只取 contig 级行时，分摊给基因的那部分 reads 一并丢失——**单条 vOTU 实测损失 35–77% reads**。三对照（Sample<N> 样本 reads 对 Sample<N> 来源 contig，取 Sample<N>/quant.sf）：`k127_45051` NumReads 420.99→**1,614.48**（+283%）、`k127_59936` 2,597.61→**3,995.86**（+54%）、`k127_224456` 1,511.06→**2,553.89**（+69%）；修复前后基线分别归档 `logs/evidence/vir_numreads_prefix_20261013.txt` 与 `vir_numreads_surviving_quant_sf_20261014.tsv`（10-14 复核一致）。注意 Sample<N> 自身 quant.sf 对同名 contig 是另一定量，数值不同属预期（质量审核四审曾因此误判证据链断裂，实为跨样本混淆）。
- **新策略（commit d08d034，10-13）**：索引只放 vOTU contigs；基因级病毒定量无下游消费方，CDS 收集与 gentrome 拼接整体移除（基因 ID 样本前缀逻辑随之删除——索引中已无基因行）。58→59 不再产生基因级定量。
- 教训沉淀：Project01 冻结基线用的正是混合索引，已发布结论带同源偏差（系统性偏低且 vOTU 间不可比），按拍板不重跑、偏差写入论文方法部分（Project01/NOTES_VIRUS_QUANT_BIAS.md）。

**执行点评**（执行方起草）：
- **运算时间**：36–58 秒。
- **输出文件**：result/virus/salmon/index/（621M，info.json 哨兵；--keepDuplicates 保留重复序列）。
- **后续使用**：59 号六样本定量共用此单一索引。
- **加速空间**：不必要。
- **内存/硬盘**：索引 621M；k-mer 构建峰值内存 ~10G。

---

## 59 · Salmon vOTU 样本定量（六样本比对率 3.4–6.6%）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 59 Salmon vOTU 定量（threads 16），完成后汇报各样本比对率与 mapped reads。」

**核心执行命令**（摘自 `scripts/59_vir_salmon_quant.sh`；输入为 02 号 kneaddata 清洁 reads）：

```bash
salmon quant -i result/virus/salmon/index -l A -p ${CPUS} \
             -1 result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz \
             -2 result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz \
             -o result/virus/salmon/{sample}
tail -n +2 quant.sf | awk '{print $1"\t"$2"\t"$4"\t"$5}' > report.tsv
```

**执行结果**（2026-10-13 V2 泳道终态实测，Salmon 0.14.1，aux_info/meta_info.json）：

| 样本 | num_processed | num_mapped | mapping rate | 耗时 |
|---|---|---|---|---|
| Sample<N> | 41,962,400 | 2,217,385 | 5.28% | 328s |
| Sample<N> | 41,751,756 | 1,581,124 | 3.79% | 245s |
| Sample<N> | 46,906,471 | 1,607,441 | 3.43% | 251s |
| Sample<N> | 55,411,039 | 2,426,206 | 4.38% | 301s |
| Sample<N> | 38,900,065 | 2,579,403 | 6.63% | 206s |
| Sample<N> | 51,631,260 | 1,930,642 | 3.74% | 262s |

**⚠️ 注意事项**：3–7% 的 reads 比对到病毒索引属肠道宏基因组预期量级（病毒 reads 占比低 + 交集严格判定 + 3,062 条 target 宇宙有限）；**不可**与 20 号细菌全基因目录 70%+ 的比对率直接类比（索引规模与冗余度不同）。

**执行点评**（执行方起草）：
- **运算时间**：172–328 秒/样本（10-12 旧索引首跑 172–247 秒，10-13 终版略慢因索引 target 语义变化，量级相同）。
- **输出文件**：每样本 quant.sf（Name/Length/EffectiveLength/TPM/NumReads）+ report.tsv（无表头四列）+ aux_info。
- **后续使用**：60 号丰度矩阵的唯一来源；Sample<N> quant 与 votu_table H10_count 逐位一致是 60 号聚合无损的交叉验证。
- **加速空间**：样本级可并行（非组装器，不受 P0-6 互斥限制）。
- **内存/硬盘**：每样本输出 <10M；内存 <8G。

---

## 60 · vOTU 丰度矩阵 + 分类注释汇总（contig 级 TPM，拍板 D；五缺陷三轮整改）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 60 vOTU 丰度表生成（contig 级 TPM 聚合 + geNomad 注释 join），完成后核对 join 闭合与六样本 ΣTPM=10⁶。」

**核心执行命令**（摘自 `scripts/60_vir_votu_table.sh` 终版，Python 内嵌两段）：

```bash
# 第 1 段：六样本 report.tsv 合并为 contig 级原始矩阵（首行按"第 2 列是否数值"判表头，
# 不再无条件跳首行——旧实现每样本静默丢一条）
# 第 2 段：经 votu_id_map.tsv 把 contig 级 TPM 聚合到 canonical vOTU（拍板 D）：
#   基因行（"|" 在任何 __ 之前）按设计跳过；contig 级行 join 失败 → 非零退出（拒绝静默丢弃）
#   length 列 = 代表 contig 自身实长（从 virus.fasta 数碱基，非"第一条归入行"）
# 第 3 段：taxonomy 列按表头名取（列名 taxonomy），代表关系只用完整 ID；
#   输出追加 lineage + annotation_status 两列（真未分类 ≠ join 失败）
```

**执行结果**（2026-10-13 V2 终态实测）：
- 中间表 `vOTU_table.txt`：3,062 行（contig 级，12 列 tpm/count）。
- **canonical 表 `votu_table.tsv`：2,622 行 vOTU**；`votu_join_stats.tsv`：joined_contig_rows=**3,062**，gene_rows_skipped_by_design=**0**，failed_contig_rows=**0**，canonical_votus=**2,622**（join 完全闭合）。
- **六样本 ΣTPM 均精确 = 1,000,000**（TPM 守恒，已入 validate_step 不变式）。
- 注释表 `vOTU_table_ann.txt`（哨兵，16 列含 lineage）：annotated **2,513**（真分类）/ source_truly_unclassified **15** / source_missing **94**（代表 contig 无 geNomad 行，旧代码会把后两类混标 Unclassified）。
- length 抽查 3/3 与 virus.fasta 实长一致（旧版曾出现 66 bp 假 vOTU）。

**⚠️ 注意事项（三轮整改史——质量审核 CP2-病毒关口全过程）**：
- **第一轮打回（2026-10-13，supervisor_20261013_cp_audit）**：60 号五缺陷定性 FAIL：① 病毒基因 ID 跨样本重名（k127_124496_1 同现于两样本索引）② 重名致 305 行基因（22 个 contig）无法归属，仅 stderr 警告后 exit 0 ③ length 列语义错（出现 66 bp"vOTU"）④ report.tsv 无表头却跳首行，每样本静默丢一条 ⑤ contig 级与基因级 TPM 混加，vOTU 间不可比。**冻结令**：votu_table.tsv 不得作为统计输入。
- **第二轮整改（7b2e9ab + d08d034，用户拍板 D/E/B/A 落地）**：D=vOTU 丰度只用 contig 级（一条 vOTU 一个数）；E=基因 ID 加样本前缀（后又随 58 混合索引废除而整体消失——基因行归零是更彻底的解）；length 改代表实长；join 失败硬退出；首行按内容判表头。V2 泳道重跑（54 H3+H10→58→59×6→60）产出上表终态。
- **第三轮三审（2026-10-14，supervisor_20261014_v2_audit）**：**有条件通过**——六条验收证据全核真（基因行 0 / ΣTPM=10⁶ / NumReads 三对照回升 / join 3062-0-2622 / annotated 2,513 / length 抽查 3/3），另揪出 91/92 列名与 93 样本列三处下游隐患（当日修复）。**分级解冻**：votu_table.tsv 对 98c/98g 即时解冻；93/91/92/94/96 待修复复验后解冻。
- 披露：ann 表的 source_missing 94 行是"join 证据缺失"而非"确认无分类"，统计引用时按 Unclassified 处理须注明。

**执行点评**（执行方起草）：
- **运算时间**：约 1 秒（纯文本聚合）。
- **输出文件**：table/vOTU_table.txt（中间）、votu_table.tsv（canonical，消费者 98c/98g/93/96）、vOTU_table_ann.txt（带 lineage）、votu_join_stats.tsv（闭合审计）。
- **后续使用**：病毒维度全部统计（多样性/差异/网络/核心微生物组）的唯一丰度正源。
- **加速空间**：不适用。
- **内存/硬盘**：忽略不计；TPM 守恒与 join 闭合两不变式已挂 validate_step（f7f6edb）。

---

## 61 · vMAG 分箱（vRhyme）——决定不执行

**决策记录（NOTES"决定不执行"，2026-10-13）**：61 vRhyme vMAG 分箱与下游 62（CheckV-MAG）/63（coverm 定量）**不执行**，依据 Project01 先例——同等深度的宏基因组样本 vMAG 产出为 0（肠道病毒 contig 平均 ~4–6 kb，远低于 vMAG 组装要求）。71_vir_dram（DRAM-v）依赖 vMAG 产物，同样未跑。事件流无 61 记录、result/virus/ 无 vmag/ 目录，与决策一致。step_checklist 中 61 行状态滞后未同步（已知清单失真项，CP3 终版重建时修正）。

**若执行的命令形态**（`scripts/61_vir_vmag.sh`，仅供教程完整性）：`vRhyme` 基于 coverm make 生成的跨样本 BAM（minimap2-sr）+ 蛋白特征分箱，产出 bins/vMAG/ 与 bins/pseudo/。

**执行点评**（执行方起草）：跳过是演示项目"空产出如实成章记录"纪律的正面应用——先例数据已证明产出为零的步骤不消耗机时，把预算留给 64–72 注释链与统计段。

---

## 64 · PHAROKKA 病毒基因组注释（3,062 contigs，PHROG+ARG）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 64 PHAROKKA 端到端病毒注释（threads 16；先以 55 条试批验证 ID 回传率，55/55 通过后再跑全量），完成后汇报 CDS 总数与耗时。」

**核心执行命令**（摘自 `scripts/64_vir_pharokka.sh`；输入为 56 号成员全集）：

```bash
pharokka.py -i result/virus/votu/contigs/virus.fasta \
            -o result/virus/pharokka -d ${REPO}/db/pharokka \
            -t ${CPUS} -f --skip_extra_annotations --skip_mash
```

**执行结果**（2026-10-14 03:46–09:47 实测，log 自报 elapsed 21,652.36s ≈ **6.0 小时**）：

| 指标 | 数值 |
|---|---|
| 输入 vOTU contigs | 3,062 |
| phanotate 预测 CDS | **55,564**（全部获 PHROG 编号映射，mmseqs2+pyhmmer 双通道） |
| pharokka.gff 行数 | 605,938 |
| 输出体积 | 198M |
| 试批验证 | 55 条 contigs 试跑，GFF sequence-region 回传 **55/55**（logs/evidence/pharokka_trial_55.fasta + pharokka_trial.gff） |

耗时构成：phanotate 两轮（fasta+tabular）占约 5.5h，是绝对瓶颈。

**⚠️ 注意事项**：
- **试批先行验证（质量审核 10-14 三审放行条件）**：全量 6 小时投入前，先抽 55 条跑通并核对"输入 ID 集合 == GFF sequence-region 集合"，确认无静默丢序列后再放行 64–72 全链（V3 泳道）。
- `--skip_extra_annotations --skip_mash` 跳过 tRNA 之外的可选注释与 mash 距离，换取全量可控时长；ARG（card）注释保留。

**执行点评**（执行方起草）：
- **运算时间**：21,658 秒（~6.0h），病毒注释链最长单步。
- **输出文件**：pharokka.gbk（65 号输入）、phanotate.faa/.ffn（66/69 号输入）、pharokka.gff、pharokka_cds_final_merged_output.tsv（55,565 行）、pharokka_cds_functions.tsv。
- **后续使用**：四审依赖修正后明确——65/66 真实依赖本步产物；67/67b/68/69/70/72 仅依赖 virus.fasta（与本步无依赖，可并行）。
- **加速空间**：phanotate 单线程内核难以并行压缩；可按 contig 分块多进程（未做，演示非必要）。
- **内存/硬盘**：峰值 <32G；198M 落盘。

---

## 65 · PHOLD 结构暗物质注释（消费 pharokka.gbk）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 65 PHOLD 注释（threads 16），完成后汇报注释表行数。」

**核心执行命令**（摘自 `scripts/65_vir_phold.sh`；输入为 64 号 pharokka.gbk——保证 gene 坐标/ID 与 64 一致并复用其 tRNA/tmRNA/CRISPR 注释）：

```bash
phold run -i result/virus/pharokka/pharokka.gbk \
          -o result/virus/phold -d ${REPO}/db/phold \
          -t ${CPUS} -p vOTU -f --cpu
```

**执行结果**（2026-10-14 09:47–21:02 实测，**40,493 秒 ≈ 11.2 小时**，V3 链第二长）：vOTU_phold.tsv 48,992 行（55,564 CDS 中 48,992 获结构域/远程同源注释）；附带 vOTU_aa.fasta、3di 序列与 per-CDS 预测表；189M。

**⚠️ 注意事项**：脚本内置孤儿进程防御——检测到已有 phold run 写同一输出目录时等待复用而非抢占（-f 会删除正在生成的目录）。

**执行点评**（执行方起草）：
- **运算时间**：40,493 秒（11.2h）；ProstT5 3di 编码 + 远程同源搜索双重开销。
- **输出文件**：vOTU_phold.tsv（哨兵）、vOTU_per_cds_predictions.tsv、vOTU_3di.fasta。
- **后续使用**：与 64 的 PHROG 互补——PHROG 无命中的"暗物质"ORF 由此获得结构域级功能线索。
- **加速空间**：--cpu 单机已并行；GPU 版 ProstT5 可显著加速（未部署）。
- **内存/硬盘**：峰值 ~40G（3di 模型加载）；189M。

---

## 66 · VOGDB HMM 扫描（hmmsearch，跨界病毒直系同源群）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 66 VOG HMM 扫描（threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/66_vir_vog.sh`；输入为 64 号 phanotate.faa）：

```bash
hmmsearch -E 1e-5 --cpu ${CPUS} \
         --tblout result/virus/vog/vog_hits.tsv \
         ${REPO}/db/vogdb/VOG.hmm result/virus/pharokka/phanotate.faa
# 再按 VOG 编号 join vog_annotations.tsv 得功能注释
```

**执行结果**（2026-10-14 21:02–21:52 实测，**3,018 秒 ≈ 50 分钟**）：**44,924 条 HMM 命中**（E<1e-5），vog_annot.tsv 44,923 行功能注释（含 tail length tape measure protein 等经典噬菌体功能类）。

**执行点评**（执行方起草）：
- **运算时间**：3,018 秒。
- **输出文件**：vog_hits.tsv（hmmsearch 原始 tblout）、vog_annot.tsv（VOG 编号→蛋白→功能描述）。
- **后续使用**：与 PHROG（64）/PHOLD（65）构成三库功能注释交叉；VOGDB 覆盖跨界病毒（含 RNA 病毒），是 PHROG 的互补证据。
- **加速空间**：HMMER 线程扩展良好，--cpu 已用满 16。
- **内存/硬盘**：峰值 <10G；输出 <50M。

---

## 67 · BACPHLIP 生活方式预测（裂解/溶原第一票）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 67 BACPHLIP 生活方式预测（threads 16），完成后汇报裂解/溶原分布。」

**核心执行命令**（摘自 `scripts/67_vir_bacphlip.sh`；多序列模式逐条预测）：

```bash
bacphlip -i result/virus/votu/contigs/virus.fasta --multi_fasta -f
# 收集每条序列的 *.bacphlip 输出合并为 bacphlip_results.tsv
```

**执行结果**（2026-10-14 21:52–23:05 实测，**4,385 秒 ≈ 73 分钟**）：3,062/3,062 vOTU 全部得双概率输出——裂解倾向 **2,455**、溶原倾向 **607**（按 Virulent 概率 >0.5 划分）。

**⚠️ 注意事项**：BACPHLIP 随机森林基于 HMM 特征，对 <10 kb contig 精度有限；结论应与 67b（PhaStyle）、72（PhaGCN3 附带生活方式信号）三票并排，2/3 一致方视为稳健，分歧且概率接近 0.5 者值得人工复核。

**执行点评**（执行方起草）：
- **运算时间**：4,385 秒（逐条序列 HMM 扫描为主要开销）。
- **输出文件**：bacphlip_results.tsv（3,063 行含表头：Virulent/Temperate 概率）。
- **后续使用**：生活方式第一票；溶原比例是肠道温和噬菌体生态学的关键读出。
- **加速空间**：multi_fasta 已批处理；分块并行可再压缩（未做）。
- **内存/硬盘**：<10G；输出 <1M。

---

## 67b · PhaStyle 生活方式第三票（ProkBERT 基因组语言模型）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 67b PhaStyle 生活方式预测（ProkBERT fine-tune，threads 16），完成后汇报 virulent/temperate 计数。」

**核心执行命令**（摘自 `scripts/67b_vir_phastyle.sh`；验证层步骤，默认不入 Snakemake rule all，按需显式触发）：

```bash
# 环境锁定：prokbert 0.0.48 + transformers==4.53.2（>=5 不兼容）+ CPU 版 torch
# （免 ~4.5GB CUDA 轮子，env 从 6.3G 降至 1.8G）
# 内嵌推理驱动（wheel 不含上游 bin/PhaStyle.py）：
#   512bp contiguous 分段 → LCATokenizer → ProkBertForSequenceClassification
#   → 段级 weighted voting 聚合 → class_1=virulent / class_0=temperate
python _phastyle_driver.py --fastain virus.fasta --out phastyle_results.tsv \
       --ftmodel neuralbioinfo/PhaStyle-mini --batch-size 32
```

**执行结果**（2026-10-14 23:05–10-15 00:53 实测，**6,469 秒 ≈ 1.8 小时**，CPU 8 线程封顶）：sentinel `phastyle_done.txt`：total=**3,062** virulent=**1,147** temperate=**1,915**——与 67 BACPHLIP（2,455 裂解主导）分歧显著，溶原读出更高，印证"三票并排、分歧人工复核"的设计。

**⚠️ 注意事项**：模型权重 ~80MB 首次从 HuggingFace 下载（HF_HOME 缓存），huggingface.co 不可达时自动回退 hf-mirror.com 镜像；推理线程 torch.set_num_threads 封顶 8，-t 传更大值无效。

**执行点评**（执行方起草）：
- **运算时间**：6,469 秒（CPU 按总碱基线性扩展；GPU 环境同脚本自动加速）。
- **输出文件**：phastyle_results.tsv（3,062 行：label + temperate/virulent 概率）+ sentinel。
- **后续使用**：生活方式第三票验证层（同 15e/16b 定位，不阻塞主队列）。
- **加速空间**：CPU 8 线程是任务约束上限；换 GPU 是唯一大幅加速路径。
- **内存/硬盘**：峰值 ~16G（模型+分段缓存）；输出 <1M。

---

## 68 · iPHoP 宿主预测（最重步骤，与 gtdbtk 错峰）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 68 iPHoP 宿主预测（threads 16；与 40 gtdbtk 错峰执行），完成后汇报获属级宿主预测的 vOTU 数。」

**核心执行命令**（摘自 `scripts/68_vir_iphop.sh`；数据库 Jun_2025_pub_rw）：

```bash
iphop predict --fa_file result/virus/votu/contigs/virus.fasta \
              --db_dir ${REPO}/db/iphop/Jun_2025_pub_rw \
              --out_dir result/virus/iphop --num_threads ${CPUS}
```

**执行结果**（2026-10-15 02:02–16:26 实测，**51,815 秒 ≈ 14.4 小时**，V3 链压轴）：Host_prediction_to_genus_m90.csv **2,714 行**（3,062 vOTU 中 88.7% 获属级宿主，m90 口径），**194 个宿主属**。Top5：*Faecalibacterium* 265、*Bacteroides* 253、*Blautia_A* 192、*Phocaeicola* 159、*Escherichia* 101——与肠道群落优势菌谱一致。

**⚠️ 注意事项**：错峰纪律（用户 2026-10-14 批准放宽后的保留项）——高内存互斥现仅约束 **gtdbtk 与 iphop** 两步（755G 内存实测仅用 20G，瓶颈在核不在内存）；V3 泳道把 iphop 排在链尾（68 最后）即为此设计。失败时 touch 哨兵降级为 WARN 不阻塞（验证层语义）。

**执行点评**（执行方起草）：
- **运算时间**：51,815 秒（14.4h）——病毒注释链乃至全链最重单步。
- **输出文件**：Host_prediction_to_genus_m90.csv（哨兵）+ 到基因组级预测 + 各工具明细（blast/RaFAH 等）。
- **后续使用**：病毒-宿主互作网络、温和噬菌体-宿主共丰度分析的宿主侧标签。
- **加速空间**：数据库比对（多工具集成）主导，难压缩；核预算允许时可与 69/70 并行（无目录冲突）。
- **内存/硬盘**：数据库常驻内存较大（错峰依据）；输出 <100M。

---

## 69 · vConTACT3 基因共享网络分类

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 69 vConTACT3 网络分类（threads 16），完成后汇报进入网络的 contig 数与属级预测数。」

**核心执行命令**（摘自 `scripts/69_vir_vcontact3.sh`；用 64 号 phanotate.faa 构建 gene2genome）：

```bash
vcontact3 run --nucleotide result/virus/votu/contigs/virus.fasta \
              --output result/virus/vcontact3 \
              --db-path ${REPO}/db/vcontact3 -t ${CPUS} \
              -e graphml cytoscape completeness
```

**执行结果**（2026-10-15 01:47–02:02 实测，**917 秒 ≈ 15 分钟**）：exports/final_assignments.csv 共 8,381 行（含 5,286 参考基因组）；本队列 **3,062 条 vOTU contig 全部进入网络**，其中 **2,324（75.9%）获属级（genus）预测**（含 novel_genus_n_of_X 形式的簇级新属定位）。

**⚠️ 注意事项**：输出含 networks/part1.cyjs 与 .graphml（Cytoscape 可直接导入）；completeness/performance_metrics.csv 供网络质量自查。

**执行点评**（执行方起草）：
- **运算时间**：917 秒（蛋白聚类+网络嵌入为主）。
- **输出文件**：exports/final_assignments.csv（哨兵）、networks/、completeness/。
- **后续使用**：与 57 geNomad、72 PhaGCN3 三路分类互证；网络簇（含参考基因组的 cluster 归属）是 contig 级分类最有力的上下文证据。
- **加速空间**：-t 已并行；参考库规模主导。
- **内存/硬盘**：峰值 ~20G；输出 <500M。

---

## 70 · PhaBox2 端到端复检（PYTHONNOUSERSITE 整改）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 70 PhaBox2 端到端分析（threads 16），完成后汇总 predict 结果。」

**核心执行命令**（摘自 `scripts/70_vir_phabox2.sh`）：

```bash
# PYTHONNOUSERSITE=1：隔离 ~/.local 用户级 pip 包（2026-10-15 修复）
env PYTHONNOUSERSITE=1 phabox2 --task end_to_end \
    --dbdir ${REPO}/db/phabox2_db \
    --outpth result/virus/phabox2/predict \
    --contigs result/virus/votu/contigs/virus.fasta \
    --len 500 --threads ${CPUS}
cp predict/final_prediction/final_prediction_summary.tsv phabox2_summary.tsv
```

**执行结果**（2026-10-15 实测）：phabox2_summary.tsv **3,062 行**——每 vOTU 一行集成 PhaMer（识别）、PhaGCN（谱系）、PhaTYO（生活方式）、CHERRY（宿主）四模块输出（如 `k127_100252`：virus / Caudoviricetes / temperate / 含宿主 lineage）。终跑 673 秒 ≈ 11 分钟。

**⚠️ 注意事项（整改史）**：首跑 9 秒 exit 1（10-15 01:27:33）——宿主 `~/.local` 的 **numpy 2.2.6 遮蔽环境内 numpy 1.26.4**，pyarrow ABI 断裂致 ImportError。这是 53 号 SIF 容器宿主 Python 污染的**同根因二次发生**（间隔 6 天），点修教训催生制度修：commit 2e6f6cc 先在本步调用点加 `PYTHONNOUSERSITE=1`，f7f6edb（质量审核终审 P0-2）进一步下沉到公共层 `mgx_conda`——所有 conda 调用点级隔离用户站点包，该家族问题就此终结。

**执行点评**（执行方起草）：
- **运算时间**：673 秒（修复后；含失败首跑共两次尝试）。
- **输出文件**：phabox2_summary.tsv（哨兵）+ predict/ 原始目录。
- **后续使用**：与 69（网络）、72（PhaGCN3）、67/67b（生活方式）、68（宿主）逐模块互证的一致性面板。
- **加速空间**：多模块串行集成，单模块内部已并行。
- **内存/硬盘**：峰值 ~30G；predict/ <500M。

---

## 72 · PhaGCN3 图卷积分类预测（PyTorch CPU 线程特性披露）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 72 PhaGCN3 分类预测（threads 16），完成后汇报预测行数。」

**核心执行命令**（摘自 `scripts/72_vir_phagcn3.sh`；数据库整体拷入运行副本后打补丁）：

```bash
# 上游源码把 diamond/mcl 线程写死 128 —— sed 改为用户线程数（48 核机防超订）
sed -i "s/--threads 128/--threads ${CPUS}/g; s/-te 128/-te ${CPUS}/g ..." \
    run_Speed_up.py run_KnowledgeGraph.py
# 用 scipy 稀疏矩阵重写 network_compute.py（上游超几何密集计算 O(n²) 内存爆炸）
# 线程环境夹紧（PyTorch/BLAS 家族）：
export OMP_NUM_THREADS=$CPUS MKL_NUM_THREADS=$CPUS TORCH_NUM_THREADS=$CPUS ...
conda run --prefix envs/phagcn3 python run_Speed_up.py --contigs virus.fasta --outpath pred
```

**执行结果**（2026-10-15 00:53–01:27 实测，**2,025 秒 ≈ 34 分钟**）：phagcn3_prediction.tsv **2,795 行**（3,062 vOTU 中 91.3% 获 ICTV 谱系预测，prediction_score 附信度；如 Bronfenbrennervirinae、Andromedavirus）。

**⚠️ 注意事项（PyTorch 26 核特性披露）**：环境内 torch 2.3.1 在未设环境变量时默认 `torch.get_num_threads()=48`（=cpu_count，无视 -t 声明）；实测运行期其 python 进程占用约 **26 核**（超过 -t 16 声明值）——CPU 版 PyTorch 的 intra-op 线程池与底层 BLAS 线程叠加的已知特性。本脚本已用 OMP/MKL/TORCH_NUM_THREADS 环境变量夹紧声明值；**排程时按实际观测核数预留预算，勿按 -t 名义值**。另：稀疏矩阵重写版 network_compute.py 是对本仓库 3 千 contig 规模的必要适配（上游密集实现在此规模即 OOM）。

**执行点评**（执行方起草）：
- **运算时间**：2,025 秒（diamond+MCL 蛋白聚类 + GCN 训练/推理）。
- **输出文件**：phagcn3_prediction.tsv（contig/prediction/score/full_path 四列族）。
- **后续使用**：与 57 geNomad、69 vConTACT3 构成三路分类互证；与 67/67b 的生活方式输出联合判读。
- **加速空间**：线程补丁+稀疏化后已贴近线性扩展；再快需 GPU torch。
- **内存/硬盘**：峰值 ~40G（GCN 邻接矩阵）；运行副本用毕即删（rm -rf RUNROOT）。

---

**批次③补写说明**：本片段覆盖步骤 54/54b/55/56/57/58/59/60/61/64/65/66/67/67b/68/69/70/72（62/63/71_vir_dram 因 61 决定不执行而连带跳过，已并入 61 章披露）。V3 注释链总账：2026-10-14 03:46（64 启动）→ 2026-10-15 16:26（68 收官）≈ 36.7 小时。三轮整改史实来源：`Project/Project_demo/NOTES.md`（复审跟踪/事故索引/拍板表）、`.CLI tool/reviews/supervisor_20261013_cp_audit.md`（第一轮打回）、`supervisor_20261013_full_review_excerpt.md`（P0-3）、`supervisor_20261014_v2_audit.md`（第三轮有条件通过）；commit 7b2e9ab / d08d034 / 2e6f6cc / f7f6edb；数字均自 `result/virus/` 与 `logs/run_events.jsonl` 现值复核。

<!-- 批次④草稿片段：步骤 75-86（真菌链后段）。插入位置：79b 章末分隔线之后、"（后续步骤章节随执行增量添加…）"收尾行之前。 -->

> **74 号无章节说明**：74 blast_gutdb 已废弃，不设教程章节——2026-10-12 该步 /tmp 泳道孤儿循环空转、4 样本产出全 0 字节再证 gut 数据库无效，循环+脚本+产物（8.3GB）整树清除（NOTES.md 事故索引 2026-10-12 条目）；依赖它的 74a_fun_gut_db_build 随之不再排期（step_checklist.md:96）。74e/74f（PHF 定量）不受影响，见前两章。

## 75 · FunOMIC 真菌分类（funomic 命令缺失，DIAMOND marker 回退分支实测）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 75 FunOMIC 真菌分类（threads 16），完成后汇报各样本检出行数。」

**核心执行命令**（摘自 `scripts/75_fun_funomics.sh`；实际走 DIAMOND 回退分支——`envs/funomic` 环境存在但无 `funomic` 可执行文件，日志 `[WARN] 未检测到 funomic 命令，回退到 DIAMOND marker 分类`）：

```bash
# 官方分支（本次未行使）：funomic classify --forward R1 --reverse R2 --threads N --output OUTDIR
# 回退分支（实际执行）：
DB_FILE=$(find $REPO/db/funomic -maxdepth 2 -name "*.dmnd" | head -1)
#   → db/funomic/P/FunOMIC.P.v1.dmnd（341 万蛋白 / 18.8 亿氨基酸，日志核证）

zcat {sample}_1.kneaddata.fastq.gz {sample}_2.kneaddata.fastq.gz | gzip -c > {sample}_merged.fastq.gz

diamond blastx \
    --db $DB_FILE --query {sample}_merged.fastq.gz \
    --out result/fungi/funomic/{sample}/{sample}_classification.tsv \
    --outfmt 6 qseqid sseqid pident length evalue bitscore \
    --evalue 1e-5 --max-target-seqs 1 --sensitive --threads 16
```

**执行结果**（2026-10-13~15 实测，6/6 成功，真菌链最长跑：每样本 24,252–35,815 秒 = **6.7–9.9 小时**，泳道内串行共约 2.2 天墙钟）：

| 样本 | 检出行数（reads×最佳命中） | 耗时 |
|---|---|---|
| Sample<N> | 8,922,122 | 27,874s（7.7h） |
| Sample<N> | 8,738,820 | 26,284s（7.3h） |
| Sample<N> | 12,134,808 | 35,815s（9.9h） |
| Sample<N> | 8,691,101 | 24,252s（6.7h） |
| Sample<N> | 9,902,473 | 31,973s（8.9h） |
| Sample<N> | 10,782,363 | 35,560s（9.9h） |

六样本合计 59,171,687 行。产出 `result/fungi/funomic/<样本>/<样本>_classification.tsv`（diamond 表格：qseqid/sseqid/pident/length/evalue/bitscore，无表头）。

**⚠️ 注意事项**：
- **分支口径**：官方 FunOMIC 分类器未安装，本步结果是 DIAMOND blastx 对 FunOMIC.P 蛋白 marker 库的**宽松单命中普查**（evalue 1e-5、无 identity 下限；实测头部命中 pident 低至 46–56%、比对长度 36–50 aa）。检出行数≠真菌 reads 数，更≠丰度。
- **输入为全量清洁 reads**（未按 71/72 先提取真菌 reads），全群落背景命中占大头——这正是 75b 聚合后出现 11,941 个"物种"的口径根源，见下章披露。

**执行点评**（执行方起草）：回退分支设计让"工具未装"降级为可运行的近似方案而非硬失败，代价是口径放宽必须显式披露；blastx 对 340 万蛋白库 + 6.7–9.9h/样本是本链仅次于 83 号的耗时项，根因是 reads 级 blastx（六线程亿级比对）而非库规模本身；多样本理论可并行（非组装器），本次按泳道串行。

---

## 75b · FunOMIC 物种丰度聚合（count / relab / CLR 三矩阵）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 75b FunOMIC 聚合，生成项目级真菌物种 count/relab/CLR 三矩阵。」

**核心执行命令**（摘自 `scripts/75b_fun_funomics_aggregate.sh`，内联 Python 聚合）：

```bash
# 逐行读 {sample}_classification.tsv，从 sseqid（JGI 蛋白 ID）提取基因组编码：
#   jgi_HypCO275_1_... → "HypCO275"
# 再左连 db/funomic/P/taxonomy_for_function.csv（编码→"g__属.s__种"），
# 缺映射时直接用基因组编码作标签
write_matrix(count_tsv, "species", species_rows, samples, matrix, int)      # 计数矩阵
# relab = 物种计数 / 样本列合计；CLR = ln(计数+0.01) 去均值（伪计数 0.01）
```

**执行结果**（2026-10-15 实测，111 秒完成）：`result/integration/fungi/` 下三矩阵均为 **11,941 物种行 × 6 样本**——`funomic_species_count.tsv` / `normalized/funomic_species_relab.tsv` / `normalized/funomic_species_clr.tsv`。

**⚠️ 注意事项（检测计数口径披露，P0 级）**：
- **11,941 taxa 是宽松口径下的基因组编码普查数**：≥1 条 read 命中即计入，无 identity/coverage 门槛。其中 4,306 个"物种"在全部 6 样本同时出现、且计数量级相当（如 Aspergillus zonatus 每样本 1.2–1.8M 行、Pecoramyces sp. 0.8–1.2M 行）——真实真菌信号应如 Sample<N> 的 S. cerevisiae 般样本间悬殊，六样本均匀的"背景高原"是全群落 reads 非特异命中的签名。
- 该矩阵只可作方法学演示，**不得直接当真菌丰度表用于统计**；严肃分类结论以 71/72/74e（Kraken2/MetaPhlAn/PHF）为准。

**执行点评**（执行方起草）：聚合逻辑本身正确（外连接补 0、relab 列内归一、CLR 加伪计数），问题出在上游口径被原样继承并放大——"能算出 11,941 行"恰恰证明宽松命中的噪声底有多厚；CLR 对计数矩阵的零膨胀结构（4011 个物种仅出现于单样本）也偏脆弱，若复用此模板建议先做行过滤。

---

## 77 · microfisher 真菌分类概览（复用 71 Kraken2 report 的 awk 过滤）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 77 microfisher 真菌概览（threads 16），完成后汇报各样本真菌条目与 reads。」

**核心执行命令**（摘自 `scripts/77_fun_microfisher.sh`，MicroFisher 风格近似实现：71 report 的 awk 谱系过滤；71 report 缺失时可补跑 Kraken2，本次全部命中复用分支）：

```bash
awk 'BEGIN { FS = OFS = "\t"; print "taxon","taxid","reads","abundance_level" }
{
    # 按 Kraken report 缩进深度重建谱系栈，行谱系含 Fungi 或已知真菌门则保留
    # 仅输出 rank 为 S/G/P 的行 → species/genus/phylum 三级
}' result/fungi/kraken2/{sample}/{sample}.report \
    > result/fungi/microfisher/{sample}/{sample}_fungal_profile.tsv
```

**执行结果**（2026-10-15 实测，6/6 成功，每样本 1 秒——纯文本过滤）：每样本固定 **152 个真菌条目**（species 95 / genus 54 / phylum 3，`--report-zero-counts` 使零读行也落盘）。门级 reads：

| 样本 | Ascomycota | Basidiomycota | 合计（约） |
|---|---|---|---|
| Sample<N> | 522 | 0 | 522 |
| Sample<N> | 25 | 4 | 29 |
| Sample<N> | 16 | 10 | 26 |
| Sample<N> | 10 | 1 | 11 |
| Sample<N> | **261,359** | 9 | 261,368 |
| Sample<N> | 7 | 1 | 8 |

Sample<N> 种级首位 S. cerevisiae（taxid 4932）258,022 reads，其次近缘种 S. paradoxus 388 reads——与 71 章 Bracken 数字一致。Microsporidia 三行全零。

**⚠️ 注意事项**：5/6 样本真菌 reads 仅 8–29 条，属"三界段空产出披露"的设计内近零信号（Sample<N> 唯一有分类数据：MetaPhlAn 口径 0.71% S. cerevisiae）；本步数字与 71 章同源（同一 report 的另一种切法），不是独立验证。

**执行点评**（执行方起草）：复用 71 report 免重跑是正确取舍（Kraken2 全库要 6–8 分钟/样本而 awk 只要 1 秒）；谱系栈按缩进深度重建的实现值得复用；产出 P/G/S 三级宽表可直接进 98 系汇总。它做的是"提取"而非"检测"，解读时应引用 71 章口径说明。

---

## 80 · Prodigal 真菌基因预测（-p meta，全群落 contigs 输入）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 80 真菌 Prodigal 基因预测（threads 16），完成后汇报各样本基因数。」

**核心执行命令**（摘自 `scripts/80_fun_prodigal.sh`；Prodigal 单线程，-t 仅占位）：

```bash
prodigal \
    -i result/fungi/assembly/{sample}/{sample}.contigs.fa \
    -a result/fungi/prodigal/{sample}/{sample}.faa \
    -d result/fungi/prodigal/{sample}/{sample}.fna \
    -f gff -o result/fungi/prodigal/{sample}/{sample}.gff \
    -p meta
```

**执行结果**（2026-10-13 实测，6/6 成功，929–1,728 秒/样本 = 15–29 分钟）：

| 样本 | 预测基因 | 耗时 |
|---|---|---|
| Sample<N> | 247,986 | 1,282s |
| Sample<N> | 204,583 | 1,202s |
| Sample<N> | 275,131 | 1,722s |
| Sample<N> | 192,918 | 929s |
| Sample<N> | 292,799 | 1,728s |
| Sample<N> | 252,293 | 1,505s |

六样本合计 **1,465,710 条蛋白**（与下游各步 combined_fungi.faa 计数核证一致）。

**⚠️ 注意事项（科学口径披露，NOTES"真菌功能注释科学口径披露"节）**：
- **输入是 78 号的全群落 contigs**（全部清洁 reads 组装产物），不是 79 号筛出的 `.Euk.fasta`（3,270/11–50 条）——若用后者，基因数会少三个数量级且以 Sample<N> 为主。
- **Prodigal 是原核基因预测器**（-p meta，标准遗传密码）：不建模内含子/可变剪接，真核基因会被切碎或多段预测。因此本步及下游 81–86 的"真菌注释"实为**以细菌基因为主体的全群落注释**，目录名 fungi/ 只代表链路归属。

**执行点评**（执行方起草）：以 26 万条/样本的基因体量换 15–29 分钟/样本的单线程速度，性价比高；faa/fna/gff 三件套齐全，faa 是 81–86 全部注释步骤的唯一输入源；口径披露比结果本身更重要——这是真菌链里最容易被误读的一步。

---

## 80b · MetaEuk 真核基因预测（--method 默认 prodigal，MetaEuk 分支未行使）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 全部 6 个样本执行 80b 真核基因预测（threads 16），完成后汇报各样本预测基因数与方法。」

**核心执行命令**（摘自 `scripts/80b_fun_metaeuk.sh`，双方法包装器）：

```bash
# 默认分支（实际执行）：与 80 号等价的 Prodigal（多 -g 11 显式遗传密码、-q 静默）
prodigal -i {sample}.contigs.fa -a {sample}_metaeuk.faa -g 11 -p meta -f gff -o {sample}.gff -q

# MetaEuk 分支（本次未行使，需 --method metaeuk --db db/metaeuk_db/fungi_refseq_mmseqs）：
metaeuk easy-predict {sample}.contigs.fa $DB {sample} tmp_{sample} \
    --threads 16 -s 7.5 --min-length 100 --translation-table 1
```

**执行结果**（2026-10-13 实测，6/6 成功，921–1,707 秒/样本）：泳道以默认参数调用，六样本全部走 Prodigal 分支，预测基因数与 80 号**逐样本完全一致**（247,986/204,583/292,799/275,131/192,918/252,293），产出 `result/fungi/metaeuk/<样本>/<样本>_metaeuk.faa` + `.gff`。

**⚠️ 注意事项**：
- **MetaEuk 本体本次未运行**：MMseqs2 库 `db/metaeuk_db/fungi_refseq_mmseqs` 与 `envs/metaeuk` 均已就绪，但泳道未传 `--method metaeuk`。80b 实为 80 的重复计算 + 命名兼容层（`_metaeuk.faa` 后缀），下游 81–86 消费的是 80 号的 `result/fungi/prodigal/*/*.faa`，本步产物无下游消费者。
- 若补跑真 MetaEuk 分支，预期基因数会显著少于 Prodigal（内含子感知 + 蛋白同源锚定），且 Sample<N> 占比升高——那才是更贴真科学口径的真菌基因集。

**执行点评**（执行方起草）：双方法包装器把"真核工具"留成选项而非默认，演示里就成了干跑重复；教训——默认值即文档：想让 MetaEuk 被用，应把 `--method metaeuk` 设为默认或在泳道里显式传参；重复计算 15–29 分钟/样本的代价尚小，真正损失的是口径对照机会。

---

## 81 · eggNOG-mapper 真菌功能注释（diamond 模式，合并 6 样本蛋白）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 81 真菌 eggNOG 注释（threads 16），完成后汇报注释行数与命中数。」

**核心执行命令**（摘自 `scripts/81_fun_eggnog.sh`，项目级步骤：先合并再注释）：

```bash
# T-20 规范 ID 方案：SAMPLE__raw 前缀去重 + 显式身份映射表（下游一切 join 的唯一 ID 源）
python3 $REPO/scripts/utils/mgx_prefix_fasta.py result/fungi/prodigal \
        result/fungi/eggnog/combined_fungi.faa result/fungi/eggnog/fungal_gene_id_map.tsv

conda run --prefix $REPO/envs/eggnog emapper.py \
    -m diamond --itype proteins \
    --data_dir $REPO/db/eggnog --dbmem \
    -i result/fungi/eggnog/combined_fungi.faa \
    --cpu 16 -o eggnog \
    --output_dir result/fungi/eggnog --temp_dir result/fungi/eggnog/tmp --override
```

**执行结果**（2026-10-15 实测，7,043 秒 ≈ 2 小时）：查询 **1,465,710 条蛋白**（6 样本合并，映射表 1,465,710 行），`eggnog.emapper.annotations` **1,340,375 行**（注释率 91.5%），`eggnog.emapper.hits` 3,465,033 行（seed ortholog 预筛原始命中），`eggnog.emapper.seed_orthologs` 1,340,395 行。主表含 COG/KO/GO/EC/CAZy 列。

**⚠️ 注意事项**：注释对象是 80 号 Prodigal 全群落基因集（见 80 章口径披露），"真菌功能注释"实为全群落功能普查；--dbmem 全库入内存（eggnog_proteins.dmnd），峰值内存按 60G+ 预算。

**执行点评**（执行方起草）：先合并后注释省了六次数据库装载；91.5% 注释率对 meta 基因预测集偏乐观（宽松 e-value 传导），做通路定量时建议再按 bitscore/COG 类别过滤；T-20 的 `SAMPLE__raw` 规范 ID 让六样本同 ID 基因（k141_ 重名）冲突在源头消解，映射表是后续 98 系 join 的关键资产。

---

## 82 · KEGG KO 注释（diamond blastp）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 82 真菌 KEGG 注释（threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/82_fun_kegg.sh`，合并蛋白 → 单库比对）：

```bash
diamond blastp \
    --db $REPO/db/kegg/diamond/kegg.dmnd \
    --query result/fungi/kegg/combined_fungi.faa \
    --out result/fungi/kegg/kegg_diamond.tsv \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 --max-target-seqs 1 --sensitive --threads 16 --quiet
```

**执行结果**（2026-10-15~16 实测，26,090 秒 ≈ 7.2 小时）：**1,362,802 命中行** / 1,465,710 查询蛋白（92.98%）。

**⚠️ 注意事项**：同样基于全群落蛋白集（80 章口径）；单命中 + evalue 1e-5 是普查口径，未做 KO 特异过滤（部分 sseqid 为非 KO 的 KEGG 蛋白），统计前需按 `K` 编号正则再筛。

**执行点评**（执行方起草）：同为 blastp 单库比对，本步 7.2h 对 84 号 108s 的差距全在库规模（KEGG 全蛋白 vs VFDB setB）；--sensitive 档位是耗时主因，若只要 KO 概览可降 --mid-sensitive；命中表直接带 12 列标准格式，与 21 号（细菌链 eggNOG/KEGG）产物的消费方式一致，98 系可直接复用聚合逻辑。

---

## 83 · dbCAN CAZyme 注释（HMMER+DIAMOND 双工具）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 83 真菌 CAZyme 注释（threads 16），完成后汇报 CAZyme 数。」

**核心执行命令**（摘自 `scripts/83_fun_dbcan.sh`；eCAMI 对超大规模合并蛋白集不可行已禁用）：

```bash
run_dbcan result/fungi/dbcan/combined_fungi.faa protein \
    --tools diamond hmmer \
    --dia_cpu 16 --hmm_cpu 16 \
    --db_dir $REPO/db/dbcan3 \
    --out_dir result/fungi/dbcan
# 库构成：CAZyDB.dmnd（diamond）+ dbCAN-HMMdb-V8.txt.h3*（hmmscan，V8 版）
```

**执行结果**（2026-10-16 实测，**51,226 秒 ≈ 14.2 小时**，真菌链单步最长）：`overview.txt` **71,416 行 CAZyme**（合并集 1,465,710 蛋白的 4.9%）；分工具原始命中 diamond.out 62,043 行、hmmer.out 51,186 行；双工具一致（#ofTools=2）38,278 行，单工具 33,138 行（53.6% 双确认）。

**⚠️ 注意事项（与细菌版 25 号的口径差异，必须披露）**：
- **工具集不同**：细菌版 25 号实际仅 `--tools diamond` 单工具（overview #ofTools=1，NOTES 待披露清单），本步是 HMMER+DIAMOND 双工具——两链 CAZyme 数**不可直接对比**。
- **耗时口径不同**：25 号 diamond 单工具 199 秒完成；本步 51,226 秒（约 14.2h），HMMER（hmmscan 对 V8 全 HMM 库逐 profile 扫描）阶段占绝对大头（run_dbcan 未输出分阶段计时，库日志仅有 DIAMOND/HMMER 起止标记）。同为"dbCAN 步骤"，199s 与 14.2h 的差异是工具配置差异，不是数据量差异（查询集同为百万级蛋白）。
- 输入同 为全群落蛋白集（80 章口径）。

**执行点评**（执行方起草）：HMMER 慢但能抓远缘糖苷水解家族，diamond 快但偏保守，双工具 + #ofTools 列让使用者可按严格度自行切片（建议下游只用 #ofTools=2 子集做主结果）；若时间预算紧，可先跑 diamond 再对命中集补 hmmscan；eCAMI 禁用决策正确——百万级蛋白上其内存/时间均不可行。

---

## 84 · VFDB 毒力因子注释（diamond blastp，setB 核心库）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 84 真菌 VFDB 毒力因子注释（threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/84_fun_vfdb.sh`，与 82 号同构）：

```bash
diamond blastp \
    --db $REPO/db/vfdb/vfdb_setB.dmnd \
    --query result/fungi/vfdb/combined_fungi.faa \
    --out result/fungi/vfdb/vfdb_hits.tsv \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
    --evalue 1e-5 --max-target-seqs 1 --sensitive --threads 16 --quiet
```

**执行结果**（2026-10-16 实测，108 秒）：**259,460 命中行**（1,465,710 蛋白的 17.7%），sseqid 为 VFG 编号（如 VFG043491）。

**⚠️ 注意事项**：宽松口径警报——实测头部命中 pident 可低至 24.8%（e-value 1.95e-23，长比对拉低 e-value）；VFDB setB 为核心库本已收紧，但单命中 + 无 identity 下限仍会产生大量远缘命中，"17.7% 基因是毒力因子"绝不可直接陈述，建议按 pident≥40 且 coverage≥50% 重筛后再谈数量级。库主体为细菌毒力基因，全群落口径下命中也以细菌基因为主。

**执行点评**（执行方起草）：108 秒的单库 blastp 是注释链里最快的重活，说明 82 号的 7.2h 纯粹是库规模问题；阈值后置（先宽松搜、下游按需收紧）在探索阶段合理，但教程必须给出重筛建议，否则 259,460 这个数会被误引。

---

## 85 · AMRFinderPlus 耐药基因检测（--plus 扩库）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 85 真菌耐药基因检测（threads 16），完成后汇报检出数。」

**核心执行命令**（摘自 `scripts/85_fun_amr.sh`）：

```bash
# 合并后去重兜底（T-20 前缀下实测零重复，1,465,710 不变，安全网性质）
awk '/^>/{...按 ID 首 token 去重...}' combined_fungi.faa > combined_fungi.faa.dedup

amrfinder \
    --protein result/fungi/amr/combined_fungi.faa \
    --database $REPO/db/amrfinder/latest \
    --output result/fungi/amr/amrfinder_results.tsv \
    --threads 16 --ident_min 0.9 --coverage_min 0.6 --plus
```

**执行结果**（2026-10-16 实测，967 秒 ≈ 16 分钟）：**684 行检出**。逐样本（按基因 ID 前缀）：Sample<N> 106、Sample<N> 90、Sample<N> 120、Sample<N> 197、Sample<N> 103、Sample<N> 68。头部元素为 erm(52)、tetB(46)/tetA(46)、lnu(C) 等——**全部是细菌耐药基因**（大环内酯/四环素/林可酰胺类）。

**⚠️ 注意事项**：脚本头注写"抗真菌药物耐药基因检测（CYP51/FKS 等）"，但 AMRFinderPlus 数据库以原核 AMR 为主，实测 684 行中未见 CYP51/FKS 类真核耐药靶标——"真菌耐药"在本步口径下实质为全群落细菌 AMR 普查（80 章口径的又一次体现）；脚本对 amrfinder 失败有"写空表头 + exit 0"的降级分支，引用结果前应先确认非空壳。

**执行点评**（执行方起草）：ident 0.9 / coverage 0.6 + --plus 是本批注释步骤里唯一带硬阈值的，684 行的量级因此可信度远高于 84 号的 259,460；Sample<N> 检出最多（197）与其群落规模一致而非真菌信号；真正的抗真菌耐药（ERG11/CYP51 突变、FKS1 hot-spot）需要专门的点突变库，超出本工具能力，教程如实记为口径缺口。

---

## 86 · MEROPS 蛋白酶注释（diamond blastp）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 86 真菌 MEROPS 注释（threads 16），完成后汇报命中数。」

**核心执行命令**（摘自 `scripts/86_fun_merops.sh`，六列精简输出）：

```bash
diamond blastp \
    --db $REPO/db/merops/*.dmnd \
    --query result/fungi/merops/combined_fungi.faa \
    --out result/fungi/merops/merops_hits.tsv \
    --outfmt 6 qseqid sseqid pident length evalue bitscore \
    --evalue 1e-5 --max-target-seqs 1 --sensitive --threads 16
```

**执行结果**（2026-10-16 实测，392 秒 ≈ 6.5 分钟）：查询蛋白 1,465,710，**73,030 命中行**（5.0%），sseqid 为 MER 编号（如 MER0107872）。

**⚠️ 注意事项**：同 84 号的宽松口径（单命中、无 identity 下限，实测命中 pident 低至 48%）；MEROPS 覆盖各界蛋白酶（含真菌分泌蛋白酶家族），全群落口径下细菌丝氨酸蛋白酶占主导；家族聚合（MER→clan/家族）留给 98 系做。

**执行点评**（执行方起草）：六列精简格式够用但丢了 qcov/slen，后续按覆盖率重筛时只能回炉重跑或估算——注释类 blastp 建议一律存 12 列标准格式；392 秒的耗时说明 MEROPS 库规模适中，是真菌链注释段收官的轻量步骤。

---

<!-- 批次⑤片段：统计段 90-99 + GEM 43-43c 章节草稿（2026-10-18 取证自 result/stat/、logs/run_events.jsonl、NOTES.md、docs/08_statistics/POWER_DISCLOSURE.md）。插入位置：79b 章节之后、"后续步骤章节随执行增量添加"收尾行之前。 -->

## 91 · 多样性统计（microeco alpha/beta + PERMANOVA，细菌/病毒双维度）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 91 多样性统计（metadata.csv，group 列，threads 16），
> 完成后汇报各维度 alpha 指数、PCoA 与 PERMANOVA 结果。」

**核心执行命令**（摘自 `scripts/91_stat_diversity.sh` + `scripts/91_diversity.R`）：

```bash
bash scripts/91_stat_diversity.sh \
  -w Project/Project_demo -r . -t 16 -m Project/Project_demo/metadata.csv -g group
# R 侧关键调用（91_diversity.R）：
#   mt$cal_alphadiv()                                   # Observed/Chao1/ACE/Shannon/Simpson/Fisher/Pielou/Coverage
#   vegan::vegdist(t(rel_otu), method = "bray")         # beta 距离
#   stats::cmdscale(as.dist(bray), k = 3, eig = TRUE)   # PCoA 坐标
#   vegan::adonis2(bray ~ group)                        # PERMANOVA
```

输入：细菌 `result/metaphlan4/merged/taxonomy.tsv`（种级 454 特征）、病毒
`result/virus/votu/table/vOTU_table_ann.txt`（geNomad 注释宽表）、真菌 `result/fungi/metaphlan4/`。

**执行结果**（2026-10-16 实测；事件流两跑：00:14 首跑 exit 1 / 22s，00:16 修复后 exit 0 / **48s**）：

- **病毒分类过滤（整改后新增关卡）**：`[INFO] virus filter: 2521 / 2615 vOTUs have taxonomy;
  dropping 94 unclassified`。修复前 `enrich_virus_taxonomy()` 只认 geNomad 原始表的 `lineage`
  列，而实际列名为 `taxonomy`——注解整段**静默跳过**（`[INFO] geNomad taxonomy not found,
  skipping virus annotation`），下游 vOTU 全部无 Domain 标签。质量审核三审（2026-10-14）拍板修复：
  列名检查兼容 `taxonomy`，并新增 `filter_unclassified_virus()` 把 94 条无分类 vOTU 显式剔除并留痕。
- **alpha 多样性**（`result/stat/diversity_alpha_summary.tsv`）：

| 维度 | Observed 范围 | Shannon 范围 | Coverage |
|---|---|---|---|
| bacteria（6 样本） | 151–230 | 3.08–3.32 | ≥0.9997 |
| virus（6 样本） | 1,054–1,630 | 4.90–5.81 | ≥0.9999 |

- **PERMANOVA**（bray-curtis，`permanova_results.tsv`）：细菌 R²=0.124、**Pr(>F)=1**；
  病毒 R²=0.165、**Pr(>F)=0.8**。
- **真菌维度如实 FAILED**：`fungi_mt: < 2 overlapping samples (fungi)`——metaphlan4 谱仅
  Sample<N> 有内容（1/6），common=1<2 正确拒绝（双源口径见 POWER_DISCLOSURE §四）。
- 产出：`result/stat/{bacteria,virus}/{abundance,diversity,phyloseq}/`（7 个分类级丰度表 ×2 维、
  alpha/beta/PCoA/PERMANOVA 表、boxplot/pcoa_scatter 双格式图、phyloseq RDS）+ 顶层
  `diversity_status.tsv`（细菌/病毒全 OK、真菌 1 条 FAILED）。

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：48s（16 线程，6 样本 ×2 维度纯统计；首跑 22s exit 1 是 gate v1 把 GROUP_COL
  预初始化清空的编排层参数家族事故，af66706 修复后一次通过）。
- **输出文件**：丰度/多样性表 + SVG/PDF 图 + RDS，路径规范 ✓；哨兵 `diversity_alpha_summary.tsv` ✓。
- **后续使用**：alpha/PCoA 表供 94 可视化直读；phyloseq RDS 是 92/96 的分析对象；PERMANOVA
  结果进 98 报告 Diversity 节。
- **加速空间**：无需求——分钟级；若加样到数百个，瓶颈会转到 `vegdist`（可换 BigData 系实现）。
- **内存/硬盘**：R 进程 <2G；产出 <50M。**披露（POWER_DISCLOSURE §一）**：6 样本 3v3 下独立
  标签置换仅 10 种，任何置换检验双侧最小 p≈0.05——PERMANOVA Pr(>F)=1/0.8 是功效上限的诚实
  体现，非流程故障；本步全部组间比较仅具探索性。

---

## 92 · 差异丰度统计（Wilcoxon/DESeq2/MaAsLin2/ANCOM-BC2/LEfSe 五法横评）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 92 差异丰度统计（group 列，dimension=all），完成后汇报各维度
  各方法显著特征数。」

**核心执行命令**（摘自 `scripts/92_stat_differential.sh`）：

```bash
bash scripts/92_stat_differential.sh \
  -w Project/Project_demo -r . -t 16 -m Project/Project_demo/metadata.csv -g group -d all
# 哨兵治理（质量审核 5 审 E1 整改）：哨兵须 ≥1 数据行才允许短路重跑
if [ ${FORCE} -eq 0 ] && [ -s "${SENTINEL}" ] && [ "$(wc -l < "${SENTINEL}")" -ge 2 ]; then
    echo "[INFO] Existing outputs detected, skipping rerun"; exit 0
fi
```

**执行结果**（2026-10-17 02:24 修复版实测 exit 0 / **125s**；`differential_summary.tsv`）：

| 维度 | 方法 | n_sig | top feature |
|---|---|---|---|
| bacteria | wilcox | 0 | — |
| bacteria | **deseq2** | **2** | `g__GGB33469|s__GGB33469_SGB15236`（log2FC=20.99，**p=7.87e-08**，padj=2.65e-05；第二条 GGB9634_SGB15097 p=1.49e-07） |
| bacteria | maaslin2 | 0 | — |
| virus | wilcox | 0 | — |
| virus | **deseq2** | **2** | `Sample<N>__k127_34328`（p=1.45e-16，log2FC=−26.8） |
| virus | maaslin2 | 0 | — |

- 92 内置 LEfSe（microeco 实现，p 校正后）三水平均如实报 "No significant feature found"；
  ANCOM-BC2 在 n=3/组下退化 FAILED（`arguments imply differing number of rows`，记录于
  `differential_status.tsv` 不中断）；病毒 LEfSe SKIPPED（仅配置细菌）；真菌 SKIPPED（RDS 缺失）。
- **假通过整改史（质量审核 2026-10-16 cp2_review P0，commit 1b9e566）**：首跑（10-16 00:14:18，
  exit 0 / 仅 6s）发生在 91 的 RDS 生成之前，跑的是空表并写出**仅表头**的
  `differential_summary.tsv` 后 exit 0；旧哨兵只查"文件非空"，表头也算非空，于是后续重跑全部被
  短路。修复：① 哨兵须 ≥1 数据行（`wc -l ≥ 2`）方可短路；② 全部 dimension 失败时脚本
  exit 1 不再假通过。
- 产出：`result/stat/{bacteria,virus}/differential/`（wilcox/deseq2/maaslin2/ancombc2 结果表 +
  volcano_deseq2 火山图 PDF）。

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：125s（MaAsLin2 拟合占大头，细菌 2521 + 病毒 2521 输入特征）。
- **输出文件**：五法结果表 + 火山图 + 顶层 summary/status 双表；哨兵治理改造后可信 ✓。
- **后续使用**：DESeq2 结果是 94 火山图与 98 报告 Differential 节的直接输入；LEfSe 出图走 99b。
- **加速空间**：有限——MaAsLin2 单线程拟合为主；多样本队列下可按特征分块并行。
- **内存/硬盘**：R 进程 ~4G 峰值（DESeq2 2521×6 矩阵）；产出 <20M。**披露（POWER_DISCLOSURE
  §一解读纪律）**：DESeq2 的各 2 个显著特征（细菌 GGB33469_SGB15236 p=7.87e-08、病毒
  Sample<N>__k127_34328）在 n=3/组下**仅具探索性价值，不得作为生物学结论引用**；Wilcoxon/
  MaAsLin2 n_sig=0 与 LEfSe 空结果是 3v3 功效上限的诚实体现，不是流程故障。

---

## 93 · 共现网络（MetaNet 本体 5/5 + NetCoMi 组间比较有界披露）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 93 共现网络分析（net_type=all，group 列），完成后汇报 5 张网络
  的节点/边数与 NetCoMi 组间比较终态。」

**核心执行命令**（摘自 `scripts/93_stat_cooccurrence.sh` 内嵌 R）：

```r
# 网络本体（每域特征预筛上限 300，出现率≥0.1，+1e-6 伪计数）
corr <- MetaNet::c_net_cal(t(ds$mat), method = "spearman", threads = threads)
go   <- MetaNet::c_net_build(corr, r_threshold = 0.3, p_threshold = 0.05,
                             use_p_adj = FALSE, delete_single = TRUE)   # 未校正 p 筛边（披露项）
# NetCoMi 组间比较的治理参数（质量审核 6 审整改）：
perm_space <- choose(length(idx1) + length(idx2), length(idx1))          # C(6,3)=20
n_perm <- min(as.integer(Sys.getenv("NETCOMI_NPERM", "1000")), perm_space)  # nPerm 封顶
setTimeLimit(elapsed = as.integer(Sys.getenv("NETCOMI_TIMEOUT", "7200")))   # 2h 墙钟熔断
```

**执行结果**（事件流五跑：00:14 exit 1/15s → 00:17 旧代码 exit 0/59s → 修复验证期 NetCoMi
直跑 **91,042s≈25.3h** 灾难 → 10-17 02:21 build-only exit 0/**85s**（最终产物）→ 02:29–03:39
有界披露验证跑 4,225s）：

- **网络本体 5/5 成功**（`result/stat/network/network_summary.tsv`）：

| 网络 | 推断 | 节点 | 边 | 模块度 | 边密度 |
|---|---|---|---|---|---|
| bacteria | MetaNet_spearman | 300 | 3,890 | 0.610 | 0.087 |
| virus | MetaNet_spearman | 299 | 4,022 | 0.547 | 0.090 |
| fungi | MetaNet_spearman | 300 | 13,853 | 0.235 | 0.309 |
| cross_bac_vir | MetaNet_multi_spearman | 600 | 15,069 | 0.549 | 0.084 |
| cross_bac_fun | MetaNet_multi_spearman | 600 | 24,789 | 0.352 | 0.138 |

- **_tpm join 整改（质量审核 5 审 E2 / cp2_review，1b9e566）**：病毒表样本列只取 `*_tpm`（P0-B，
  旧代码把 length/_count/lineage 一并当丰度），且读入后剥 `_tpm` 后缀再对元数据行名——旧代码
  `Sample<N>_tpm` vs 元数据 `Sample<N>` 交集为 0，把失败伪装成"需≥5 样本"的误导性跳过。
- **NetCoMi 组间比较 = 有界披露（质量审核 6/7 审裁定，POWER_DISCLOSURE §二）**：
  a) 细菌域：3v3 逐组 SparCC/FastSpar 网络退化，`network/bacteria/group_compare.txt` 为退化
  诊断（"Status: unavailable"，nPerm: 20 (capped at permutation space 20)），非成功比较；
  b) 其余 4 目标：2 小时总预算点终止 = SKIPPED(overall-timeout)；
  c) 根因：NetCoMi 默认 nPerm=1000 且每次置换重建网络（数天级，实测 25.3h 灾难跑），而
  C(6,3)=20 使 ~98% 置换为重复计算；文献建议网络组间比较**每组 ≥25-30 样本**
  （Matchado et al. 2021, Front Microbiol）。调研存档
  `docs/research/2026-10-17_network_comparison_small_n.md`。
- 最终态：`NETCOMI_DISABLE=1` build-only 跑出 5/5 网络本体；`network_status.tsv` 中 5 条
  netcomi_* 均为正式 SKIPPED 终态留痕（质量审核 6 审 P0-1c：SKIPPED 不再冒充 OK）。
- **真菌网络双源口径**：91/92 用 metaphlan4 谱（1/6 样本有内容 → 正确拒绝），93 用
  `result/integration/fungi/funomic_species_count.tsv`（FunOMIC 检测计数，6 样本 ×11,941 taxa）
  → 真菌网络可建（POWER_DISCLOSURE §四：两源不可互相印证）。

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：网络本体 85s；NetCoMi 组间比较在本数据规模下不可行（25.3h 仍未完成，已被
  熔断/终止策略取代）——这是本步最重要的"预期管理"数字。
- **输出文件**：5 目录 ×（nodes/edges.tsv + network 图 SVG/PDF/TIFF）+ summary/status 双表；
  细菌退化诊断单独留档。
- **后续使用**：网络表与图直接进 94/98 报告；hub_taxa 列（度前 10%）供后续靶向解读。
- **加速空间**：nPerm 已按置换空间封顶（20）；真正提速靠加样本（每组 ≥25-30 才有比较价值）。
- **内存/硬盘**：R 进程 ~8G 峰值（MetaNet 相关矩阵）；产出 ~200M（含 TIFF）。
  **披露（POWER_DISCLOSURE §二）**：网络本体筛边使用**未校正 p 值**，全部网络为探索性描述，
  不宜解读为确证性关联。

---

## 94 · 统一可视化（composition/diversity/differential/core/network 出图串联）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 94 统一可视化（group 列），完成后汇报各维度出图清单。」

**核心执行命令**（摘自 `scripts/94_stat_visualization.sh`）：

```bash
bash scripts/94_stat_visualization.sh \
  -w Project/Project_demo -r . -t 16 -m Project/Project_demo/metadata.csv -g group
# 内部：(cd "${WORKDIR}" && mgx_conda r_stat Rscript "${REPO}/scripts/94_visualization.R")
```

**执行结果**（2026-10-17 06:31 实测 exit 0 / **41s**，completed 2/3 dimensions）：

- bacteria（454 taxa）6/6 步 OK、virus（2,521 taxa）6/6 步 OK；fungi SKIP（RDS 不存在，
  `[SKIP] microtable RDS not found: .../fungi_microtable.rds`，与 91 口径一致）。
- 产出图（SVG+PDF 双格式）：每维度 composition 三件套（`barplot_composition_by_group` /
  `barplot_genus_groupmean` / `heatmap_genus`）、diversity 两件（alpha boxplot、PCoA scatter）、
  `volcano_deseq2`；另含 `lefse/bacteria/lefse_barplot.pdf`（99b 结果）、core_microbiome 三件
  （丰度条图/流行度曲线/Venn）与 93 网络图。
- **披露（POWER_DISCLOSURE §一）**：所有按组着色的图在 3v3 下仅作组成/分布展示，不承载
  组间显著性声明——图内不添加 p 值标记。

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：41s（MicrobiotaProcess/ggplot2 渲染，真菌跳过）。
- **输出文件**：约 30 张 SVG/PDF，全部落在各维度 `composition|diversity|differential/` 下 ✓。
- **后续使用**：即取即用的论文插图层；出版主题由 `scripts/R/pub_theme.R` 统一（Arial/7pt 基准）。
- **加速空间**：无需求；图多时可按维度拆分并行。
- **内存/硬盘**：<4G；产出 ~100M。

---

## 95a / 95b · 批次校正与评估 —— **决定不执行（无 batch 列）**

**启动本步骤（复制给 AI 助手）**：
> 「（本项目不适用）如元数据含批次列，可执行：bash scripts/95a_stat_batch_correct.sh
>  -w … -b BATCH_COL -g group；评估：bash scripts/95b_stat_batch_evaluate.sh …」

**决定与依据**（NOTES.md「决定不执行」节，用户批准）：`metadata.csv` 仅含
`sample_id,group,subject_id,age,BMI` 五列，**无 batch 列**——95a 的必选参数 `-b BATCH_COL`
无值可填，强行虚构批次列会制造假变量。按「空产出继续 + 如实记录」策略，本步成章注明不执行，
98 报告 Batch 节如实输出 `Missing: result/stat/bacteria/batch/evaluation_report.tsv`。
**披露（POWER_DISCLOSURE §一）**：本项目单批次 3v3，无批次混杂可校正，与探索性定位一致。

---

## 96 · 功能差异统计（Maaslin3，bacteria:pathway 主线）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 96 功能差异统计（dimension=bacteria，func_type=pathway），
> 完成后汇报 Maaslin3 显著通路数。」

**核心执行命令**（摘自 `scripts/96_stat_functional.sh`）：

```bash
bash scripts/96_stat_functional.sh \
  -w Project/Project_demo -r . -m Project/Project_demo/metadata.csv -d bacteria -t pathway
# R 侧输入解析（96_stat_functional.R）：bacteria:pathway → result/humann3/merged/pathabundance_relab.tsv
# 上游不稳兜底：maaslin3 "subscript out of bounds" → 写 SKIPPED 哨兵（biobakery/maaslin3#25）
```

**执行结果**（2026-10-17 06:27 实测 exit 0 / **17s**）：

- Maaslin3 拟合 **874 条 MetaCyc 通路，q<0.05 显著 = 0 条**；`pathway_status.tsv` 六步全 OK；
  可视化因"Zero significant features"自动降级为 volcano-only（barplot_top20/heatmap/sankey
  跳过并留痕）。
- 产出：`result/stat/bacteria/functional/pathway/`（maaslin3_results.tsv、maaslin3_raw/ 全套
  拟合产物、figures/volcano.{svg,pdf,tiff}、`bacteria_functional_pathway_done.txt` 哨兵）。
- 96 家族其余子模块（96b 通路活性、96c 功能冗余、96 functional_permanova/network/integrated）
  未列入本演示 W6 排程，无产物（与 98 报告 ML 节 Missing 口径一致）。

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：17s（874 特征 ×6 样本）。
- **输出文件**：结果表 + 拟合残差 RDS + 火山图三格式；SKIPPED 兜底哨兵设计完备 ✓。
- **后续使用**：显著通路表（本跑为空）本应供 94/sankey 与 98 报告功能节引用。
- **加速空间**：无需求。
- **内存/硬盘**：<3G；<50M。**披露（POWER_DISCLOSURE §一）**：0 显著与 92 的
  Wilcoxon/MaAsLin2 n_sig=0 同族——3v3 功效上限的诚实体现，不是流程故障。

---

## 96 · SIAMCAT 机器学习 —— **SKIPPED-by-guard（输入治理守卫拒绝执行）**

**启动本步骤（复制给 AI 助手）**：
> 「（本项目被守卫拒绝，属预期终态）如队列 ≥10 样本/组可执行：
>  bash scripts/96_stat_ml_siamcat.sh -w … -m … -d bacteria」

**执行结果**（2026-10-17 06:29 实测：exit 1 / 10s，守卫留痕
`logs/stat/ml/96_stat_ml_siamcat.run.log`）：

```text
[INPUT-GOVERNANCE] BAC| domain filter: kept 480 k__Bacteria s__-terminal row(s) ...
Error in assert_block_samples(...):
  [INPUT-GOVERNANCE] BAC block: only 6/6 sample column(s) match metadata sample ids
  (need >=10). Input: .../result/metaphlan4/merged/taxonomy.tsv
```

守卫要求**≥10 个元数据匹配样本**，实测 6/6——按守卫拒绝执行并完整留痕（域过滤先保留了 480
条细菌种级行，说明检查发生在有效输入之上，非空跑）。**披露（POWER_DISCLOSURE 附则）**：
n=6 下 10 折交叉验证不具证据力，**不做也不应做**——与 3v3 功效上限同族的正确拒绝；
98 报告 ML 节如实输出 "Missing ML summary outputs"。

---

## 98 系 · 跨维度整合（98b/98c/98d/98e–g 八步，全部 exit 0）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 依次执行 98 系八步整合（98b 细菌表、98c 病毒表+MGE、98d MAG+真菌表、
> 98e ANI 聚类、98f 正交组、98g 跨域相关），完成后汇报各表行数。」

**核心执行命令**（八脚本，2026-10-17 03:49–03:53 串行完成，合计 ~5.5 分钟）：

```bash
bash scripts/98b_bac_integration_tables.sh  -w Project/Project_demo -r .   # 细菌三类 13 张整合表
bash scripts/98c_vir_integration_tables.sh  -w Project/Project_demo -r .   # 病毒 5 聚合表 + 2 vOTU 宽表
bash scripts/98c_bac_mge_summary.sh         -w Project/Project_demo -r .   # MGE+质粒 per-sample 汇总
bash scripts/98d_bac_mag_integration.sh     -w Project/Project_demo -r .   # MAG-level 主整合表
bash scripts/98d_fun_integration_tables.sh  -w Project/Project_demo -r .   # 真菌基因计数整合表
bash scripts/98e_cross_domain_ani_cluster.sh -t 16 -w Project/Project_demo -r .  # 跨域 ANI 聚类
bash scripts/98f_cross_domain_orthogroup.sh  -t 16 -w Project/Project_demo -r .  # MMseqs2 蛋白正交组
bash scripts/98g_cross_domain_correlation.sh -t 16 -w Project/Project_demo -r .  # 跨域 Spearman 网络
```

**执行结果**（事件流实测逐条耗时 88s/26s/5s/4s/30s/69s/74s/30s）：

| 步骤 | 关键产出与规模 |
|---|---|
| 98b | `result/integration/bacteria/` 16 文件：kegg_ko/cog/cazyme/arg/vfdb/defense/ncyc/pcyc/iron/scyc 丰度表、gene_annotation_matrix、pathway_community/species_contrib、pfam_evidence |
| 98c_vir | `votu_annotation_matrix.tsv` **2,622 vOTU × 注释**宽表 + relab 版、phrog/vog/lifestyle/viral_family/host_genus 聚合表、AMG/宿主证据表 |
| 98c_mge | `mge_plasmid_summary.tsv`（MGE+质粒 per-sample） |
| 98d_mag | `mag_integration_table.tsv` **128 MAG** 主表（CheckM2/GTDB/注释联表） |
| 98d_fun | `result/integration/fungi/` 14 文件：**funomic_species_count.tsv（6 样本 ×11,941 taxa，93 真菌网络数据源）**、vfdb/amr/merops/cazyme/cog/kegg 计数表、funomic CLR/证据表 |
| 98e | `result/cross_domain/cluster/`：**2,751 条跨域基因组**（drep 代表 MAG+vOTU+真菌）ANI 矩阵 → `genome_clusters.tsv` **913 簇** |
| 98f | `result/cross_domain/orthogroup/orthogroup_table.tsv`：**348,008 条蛋白 → 正交组（OG）映射**（MMseqs2 cluster.tsv + 全序列 fasta 存档） |
| 98g | `result/cross_domain/correlation/`：跨域网络 **17,157 节点 / 121,695 边**（相关边 107,168 + 宿主预测边 14,527，212 连通分量） |

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：单步最长 88s（98b），八步串行 ~5.5 分钟——纯表联接/轻量聚类，无重计算。
- **输出文件**：四目录（integration/{bacteria,virus,fungi} + cross_domain/{cluster,orthogroup,
  correlation}）全数落位，行数与上游产物对账一致 ✓。
- **后续使用**：98c/98g 是 CP2 分级解冻的首批受益者（votu 表对二者即时解冻）；98d_mag 是
  GEM/MAG 解读的入口表；funomic_species_count 支撑 93 真菌网络。
- **加速空间**：98f 的 MMseqs2 已 16 线程（74s）；其余步骤瓶颈在 IO。
- **内存/硬盘**：<8G；cross_domain 存档（fasta+矩阵）~2G。**披露（POWER_DISCLOSURE §二）**：
  98g 相关网络同样使用未校正口径的探索性筛边，解读纪律同 93。

---

## 99a · 双边核心微生物组（global/case/control 三层 + Venn 分解）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 99a 核心微生物组识别（细菌种级表 + 病毒 vOTU 表，prevalence 0.5），
> 完成后汇报双边核心规模。」

**核心执行命令**（摘自 `scripts/99a_core_microbiome.sh`，R 侧 case 映射整改后）：

```bash
bash scripts/99a_core_microbiome.sh \
  -i Project/Project_demo/result/metaphlan4/merged/taxonomy_species.tsv \
  -m Project/Project_demo/metadata.csv -d bacteria -o Project/Project_demo/result/stat/core_microbiome/bacteria
bash scripts/99a_core_microbiome.sh \
  -i Project/Project_demo/result/virus/votu/votu_table.tsv \
  -m Project/Project_demo/metadata.csv -d virus -o Project/Project_demo/result/stat/core_microbiome/virus
# 质量审核 CP3 计划联审 W0 整改：显式确定性分组映射（treat→case），不依赖因子首水平
for (cand in c("case", "treat", "treatment", "disease")) if (cand %in% group_values) { case_label <- cand; break }
```

**执行结果**（修复版终跑 2026-10-18 08:37 双维度 exit 0 / 各 2s；`core_microbiome_summary.txt`）：

| 维度 | 分析特征 | 全局核心 | case（treat）核心 / 特有 | control 核心 / 特有 | 共享 | 核心丰度占比 |
|---|---|---|---|---|---|---|
| bacteria | 482 | 170 | **140** / 43 | **151** / 54 | 97 | 79.53% |
| virus | 2,622 | 1,631 | **1,399** / 266 | **1,467** / 334 | 1,133 | 89.09% |

- **整改史（两处）**：① `_tpm` join 修复——病毒表列名 `Sample<N>_tpm` 对元数据 `Sample<N>` 交集
  为 0（与 93 同根因家族）；② case 映射修复——旧实现取因子首水平，在 `control` 排序靠前时
  case/control 会**静默对调**；CP3 联审 W0 拍板显式候选链映射（treat→case）。
- **离账重跑事故（NOTES 2026-10-17 条目）**：修复版于 10-17 06:34:02 手动重跑未走泳道、无事件
  记录，产物随即被当轮 98 报告引用——第 9 轮审核以 mtime 抓出并补记（e93c4ca）；10-18 08:37
  带账重跑双维度，事件流完整（此即终版报告时间戳 08:39 的直接前置）。
- 产出：每维度 `core_microbiome_{global,case,control}.csv` + summary.txt + 三图
  （丰度条图/流行度曲线/Venn）。

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：2s/维度。
- **输出文件**：三层清单 + Venn 校验行（43+97+54=194 ✓ / 266+1133+334=1733 ✓）。
- **后续使用**：核心清单是 98 报告与后续机制解读的"常驻菌群"基线；Venn 特有集仅为假设生成。
- **加速空间**：无需求。
- **内存/硬盘**：<1G；<10M。**披露（POWER_DISCLOSURE §一）**：prevalence 0.5 在组内即
  "≥2/3 样本检出"——3v3 下组核心的统计含义极弱，数字仅描述本队列组成，不外推总体。

---

## 99b · LEfSe 生物标志物（独立实现，细菌种级）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 99b LEfSe 分析（细菌种级表，LDA 阈值 2.0），完成后汇报候选
  标志物数量与验证状态。」

**核心执行命令**（摘自 `scripts/99b_lefse.sh`）：

```bash
bash scripts/99b_lefse.sh \
  -i Project/Project_demo/result/metaphlan4/merged/taxonomy_species.tsv \
  -m Project/Project_demo/metadata.csv \
  -o Project/Project_demo/result/stat/lefse/bacteria -d bacteria -y taxonomy --lda-threshold 2.0
```

**执行结果**（2026-10-17 06:31 实测 exit 0 / **3s**；`lefse_results.tsv`）：

- **9 条候选标志物**（LDA 2.61–4.48）：treat 富集 7 条（top：*Clostridiales_bacterium_KLE1615*
  LDA=4.48）、control 富集 2 条（*GGB3363_SGB4447* 4.34、*Phocaeicola_vulgatus* 4.19）。
- **验证列如实暴露局限**：筛选用 Kruskal-Wallis **名义 p** 0.037–0.050（未校正）；9 条的
  `wilcoxon_pvalue` 全部 >0.05（0.064–0.081）——LEfSe 三步走（KW→Wilcoxon→LDA）的第二步
  未通过，结果表保留行并附验证列，而非剔除。
- 与 92 内置 LEfSe（microeco、p 校正后三水平均 "No significant feature found"）构成口径
  对照：99b 保留名义 p 候选供探索，92 给校正后的零结果——两者不矛盾，是同一功效上限的
  两种诚实呈现。
- 产出：`result/stat/lefse/bacteria/lefse_results.tsv`（94 已联动渲染 `lefse_barplot.pdf`）。

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：3s。
- **输出文件**：结果表 + 联动条图；列设计（wilcoxon_validated/lda_fallback）自带防过度解读
  护栏 ✓。
- **后续使用**：仅作假设生成清单；引用时必须连同 Wilcoxon 未通过的事实。
- **加速空间**：无需求。
- **内存/硬盘**：<1G。**披露（POWER_DISCLOSURE §一解读纪律）**：n=3/组下任何名义 p<0.05
  （含这 9 条）仅具探索性价值，不得作为生物学结论引用。

---

## 98 · 统计段终版报告（快照聚合 + 披露 banner）

**启动本步骤（复制给 AI 助手）**：
> 「请为 Project_demo 执行 98 统计报告生成（--force 出新时间戳版本）。」

**核心执行命令**（摘自 `scripts/98_stat_report.sh`）：

```bash
bash scripts/98_stat_report.sh -w Project/Project_demo -r . --force
# 产出：result/stat/report/report_$(date -u +%Y%m%d_%H%M%S).md
```

**执行结果**（终版 **`result/stat/report/report_20261018_083900.md`**，2026-10-18 08:39:01
实测 exit 0 / 1s，96 行；前序版本 10-17 06:31/06:34 两版）：

- **披露 banner 置顶（质量审核 9/10 轮审核要求，POWER_DISCLOSURE 前置引用）**：
  > **统计功效与口径披露（必读）**：本项目 n=6（3v3）为流程演示设计——置换检验 p 值下限
  > ≈0.05、LEfSe/SIAMCAT/网络组间比较受小样本限制，全部组间结论仅具探索性。详见
  > `docs/08_statistics/POWER_DISCLOSURE.md`。
- 正文五节：QC（**Failed sentinels detected: 0**）、Diversity（alpha 全表 + PERMANOVA）、
  Differential（六行 summary 表）、Networks（5/5 网络表）、Batch/ML/Cross-cohort
  （如实 "Missing"，对应 95a 不执行 / SIAMCAT 守卫拒绝 / 97 跨队列不适用）。
- 终版时间点的前置链：10-18 08:37 99a 带账重跑（双维度 exit 0）→ 08:39 报告再生成——
  报告与产物新鲜度对齐（第 9 轮审核 mtime 教训的闭环）。

**执行点评**（执行方起草，统计段关口由质量审核复核）：
- **运算时间**：1s（纯文件聚合，无计算）。
- **输出文件**：单文件快照，时间戳防覆盖 ✓；banner 首次把 POWER_DISCLOSURE 从"旁置文档"
  提升为报告正文必读层。
- **后续使用**：即 CP3 终审与用户阅读的统计段唯一入口；Missing 节保留是诚实性设计而非缺陷。
- **加速空间**：不适用。
- **内存/硬盘**：可忽略。**披露（POWER_DISCLOSURE 全文）**：3v3 探索性、C(6,3)=20、网络比较
  每组 25-30 业界门槛三口径在 banner 一句话内全部锚定，正文各表不再重复显著性声明。

---

<!-- GEM 章节（43/43b/43c）见批次②完整版 -->

<!-- GEM 章节（43/43b/43c）见批次②完整版 -->

<!-- GEM 章节（43/43b/43c）见批次②完整版 -->

## 24c · AMR 报表融合层（hAMRonization，可选步骤）

**启动提示词**：将 AMRFinderPlus 和 RGI/CARD 两种异构耐药基因报告统一为标准格式表，保留原始结果不动、提供零丢失对账证明。

**核心命令**：
```bash
bash scripts/24c_bac_amr_harmonize.sh -t 16 \
  -w /absolute/path/to/Project_demo \
  -r /absolute/path/to/CSCCD-MetagenomeFlow
```

**执行结果**（2026-10-21 优化轮）：
| 来源 | 输入 | 输出 | 差异 |
|---|---|---|---|
| AMRFinderPlus | 363 | 335 | -28（VIRULENCE 设计内跳过） |
| RGI/CARD | 69,905 | 69,905 | 零丢失 |
| **合计** | **70,268** | **70,240** | **0 无解释丢失** |

**执行点评**（执行方起草）：
- **运算时间**：秒级（纯格式转换，无重计算）
- **输出文件**：`result/annotation/amr_harmonized/`（标准化表×2 + 对账 JSON）
- **后续使用**：下游消费者可用统一格式做跨工具比较，但需注意置信等级差异
- **加速空间**：无需加速
- **内存硬盘**：极轻（<1MB 临时文件）

**⚠️ 已知限制**（GATE-OPT1 披露）：
1. AMRFinderPlus protein-only 模式需补 Contig id/Start/Stop/Strand 四列占位值（0/0/0/+），非实测坐标
2. hAMRonization 设计内跳过 Type=VIRULENCE 行（AMR 专注工具）
3. 跨工具 ID 格式不同：AMRFinderPlus 短蛋白 ID vs RGI 完整 prodigal 描述串
4. RGI 含 Loose 命中（`--include_loose`），跨工具置信比较需过滤到匹配等级

**参考**：[pha4ge/hAMRonization](https://github.com/pha4ge/hAMRonization)（2024，17 种 AMR 工具输出标准化）

---

## 优化基准对照：galah vs dRep（GATE-OPT1 隔离评估）

**执行结果**（2026-10-21 优化轮，隔离目录 `result/opt_bench/galah_vs_drep/`）：
| 指标 | galah | dRep（现有） |
|---|---|---|
| 代表数 | 141 | 128 |
| 共同代表 | 93/128（72.7%） | — |
| 耗时 | 0.4s（24t） | 79s（16t） |

**⚠️ 公平性披露**：两侧线程数不同（24 vs 16），"200x 加速"仅供参考；dRep 实际使用 skani 而非 fastANI。判定为 STRUCTURAL_CONSISTENCY（非强一致），**不建议在当前 128 MAGs 规模替代 dRep**。

---

## 优化原型：MICOM 群落代谢建模（GATE-OPT2 研究型可选）

**执行结果**（2026-10-21 优化轮，隔离目录 `result/opt_bench/micom_prototype/`）：
- 10 物种个体 FBA：9/10 成功（Escherichia carveme 模型已知缺失）
- 生长率 7.7-18.4（CarveMe 默认培养基）；反应网 283-526/菌
- 交叉喂养候选筛查：8 对（以水交换为主 + 1 对鸟氨酸 Caecibacter→Megasphaera）

**⚠️ 解读纪律**：结果为**基于个体模型的候选筛查**，非群落级已确认交叉喂养。等丰度为人为假设。群落级 MICOM 社区模型延后（需逐 MAG 丰度转换 + API 兼容 + 培养基定义）。

---
