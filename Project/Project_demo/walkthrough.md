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
  --output result/kneaddata/{sample} \
  --reference-db $REPO/db/kneaddata/human/hg37dec_v0.1 \
  --threads 16 \
  --trimmomatic
```

**执行结果**（2026-10-03/04 实测，6/6 成功）：

| 样本 | 组 | 清洁 reads(双端) | 保留率 | 人源污染比 |
|---|---|---|---|---|
| Sample1 | treat | 41,962,400 | 99.2% | 0.8% |
| Sample10 | treat | 46,906,471 | 98.5% | 1.5% |
| Sample11 | control | 51,631,260 | 98.7% | 1.3% |
| Sample2 | treat | 41,751,756 | 99.2% | 0.8% |
| Sample3 | control | 55,411,039 | 99.2% | 0.8% |
| Sample4 | control | 38,900,065 | 99.0% | 1.0% |

计时：Sample1 131min、Sample10 143min、Sample11 159min、Sample2 129min、Sample3 171min、Sample4 121min（合计 14.3 小时）。产出：`result/kneaddata/<样本>/`（清洁 reads 双端 + orphan + 污染 reads + log/stats）。

**质量审核点评**：（主代理按五维度起草，预处理段关口由质量审核复核）：
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
  -o temp/pair_repair/{sample}/ \
  --force
# 完成后将 temp 内文件移回原路径（原地覆盖，保持下游路径不变）
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

产出：原地覆盖 `_1.kneaddata.fastq.gz` / `_2.kneaddata.fastq.gz`（严格配对），哨兵 `.pair_repair_done.txt` ✓。

**质量审核点评**：（主代理按五维度起草，预处理段关口由质量审核复核）：
- **运算时间**：338–471 秒/样本（IO 密集：读写 4–5G 压缩 fastq），合计 ~39 分钟。
- **输出文件**：原地覆盖（无新增文件）；哨兵 6/6 落位。配对前后 reads 数完全一致（零丢失）。
- **后续使用**：严格配对的清洁 reads 供三界分析链首步（11 metaphlan4 / 14 kraken2 等）；不配对修复则下游 bwa/metaphlan 会因 R1/R2 顺序错位而崩溃（v1.1.4 教训）。
- **加速空间**：有限——瓶颈在磁盘 IO（gzip 解压/重压）；多样本并行可按比例缩减。
- **内存/硬盘**：内存温和（seqkit 流式处理）；temp/ 临时空间需 ~10G/样本（完成后可清除）。

---

（后续步骤章节随执行增量添加，格式同上：启动提示词 → 核心命令 → 执行结果 → 质量审核点评）
