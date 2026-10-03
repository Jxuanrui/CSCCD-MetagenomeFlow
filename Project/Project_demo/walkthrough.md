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

**质量审核点评**：（待质量审核评估后填入）

---

（后续步骤章节随执行增量添加，格式同上：启动提示词 → 核心命令 → 执行结果 → 质量审核点评）
