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

**质量审核点评**：（主代理按五维度起草，预处理段关口由质量审核复核；HEAD: 050f1c6）:
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

**质量审核点评**：（主代理按五维度起草，预处理段关口由质量审核复核；HEAD: 050f1c6）:
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

**质量审核点评**：运算时间合理（bowtie2 比对全库索引为瓶颈）；产出标准 MetaPhlAn4 格式。

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

**质量审核点评**：秒级完成，无性能问题。

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

**质量审核点评**：默认只做检测（--print_clades_only），要得到菌株系统发育树需带 `-c <clade_id>` 再跑一次。本段演示到此为止。

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

**质量审核点评**：运算时间是最长步骤（瓶颈待 HUMAnN log 分阶段计时确认；脚本注释认为最大性能收益点是 bowtie2-build custom ChocoPhlAn DB，非 DIAMOND）；按脚本注释 `--speed-mode balanced` 可提速约 5–10×（standard 8–15h → balanced 1–2h/样本，代价：unstratified 社区通路精度损失 <5%，<1% 丰度物种的 stratified 通路丢失）。

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

**质量审核点评**：合并表只包含**非分层数据**（无 `|` 分层行）。

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

**质量审核点评**：速度极快（k-mer 直接匹配，无比对）；数据库 77GB 常驻内存是 IO 瓶颈。

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

**质量审核点评**：三个层级均产出标准 TSV 矩阵（行=物种，列=样本）。

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

**质量审核点评**：速度最快（MinHash sketch 比对，GTDB-R220 全库 110k+ 基因组）；内存仅需 ~15GB。

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

**质量审核点评**：秒级完成，无性能问题。

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

（后续步骤章节随执行增量添加，格式同上：启动提示词 → 核心命令 → 执行结果 → 质量审核点评）
