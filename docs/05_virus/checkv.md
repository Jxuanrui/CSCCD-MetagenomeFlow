# CheckV — 病毒序列质量评估

**版本**: 1.0.3 | **环境**: `envs/checkv` | **脚本**: `scripts/54_vir_checkv_contig.sh` / `62_vir_checkv_mag.sh`

## 功能
CheckV 对病毒 contigs 或 vMAGs 进行端到端质量评估，预测完整度（completeness）和污染（contamination），并鉴定原前病毒（provirus）区域。在本流程中有两处应用：contig 级（54）和 vMAG 级（62）。

## 两种运行模式

### 模式 A：病毒 contig 评估（脚本 54）

| 项目 | 路径 |
|------|------|
| 输入 | geNomad + VirSorter2 **合并**后去重的病毒 contigs |
| 质量汇总 | `result/virus/checkv/{sample}/quality_summary.tsv` |
| 病毒 contigs | `result/virus/checkv/{sample}/viruses.fna` |
| 原前病毒 | `result/virus/checkv/{sample}/provirus.fna` |

**核心流程**：
1. 读取 geNomad 病毒序列（`result/virus/genomad/{sample}/*.fna`）和 VirSorter2 序列（`final-viral-combined.fasta`）
2. `seqkit rmdup -s` 按序列去重合并
3. `checkv end_to_end` 运行完整评估

### 模式 B：vMAG 评估（脚本 62）

| 项目 | 路径 |
|------|------|
| 输入 vMAGs | `result/virus/vmag/bins/vMAG/*.fasta` |
| 批质量汇总 | `result/virus/vmag/checkv/quality_summary.tsv` |
| 过滤后 vMAGs | `result/virus/vmag/vmag_filtered/` |

**过滤标准**：保留 Complete / High-quality / Medium-quality 级别，排除 `Not-determined` 和 `Low-quality`。

## CheckV 质量等级

| 等级 | 完整度 | 含义 |
|------|--------|------|
| Complete | ~100% | 完整病毒基因组（含末端重复/TIR） |
| High-quality | >90% | 高质量，几乎完整 |
| Medium-quality | 50–90% | 中等质量，可初步分析 |
| Low-quality | <50% | 低质量，仅可用于大类分析 |
| Not-determined | — | 无法评估（序列太短或特征不足） |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `end_to_end` | — | 一次运行完整评估 |
| `-d` | `db/checkv` | CheckV 数据库 |
| `-t` | CPUS | 线程数 |

## 注意事项
- CheckV 数据库约 15 GB（含 HMM profiles + DIAMOND 索引），位于 `db/checkv/`
- contig ≥1.5kb 时评估更可靠；<1kb 的短序列多为 `Not-determined`
- CheckV 还输出 `completeness_method`（AAI / TNR / 等）用于判断完整度估算的可靠性
- vMAG 评估是批量模式，对每个 bin 独立运行后汇总到一个 `quality_summary.tsv`

## 官方链接
- GitHub: https://github.com/chuvp/CheckV
- 论文: Nayfach et al. 2021, Nature Biotechnology 39:578–585
