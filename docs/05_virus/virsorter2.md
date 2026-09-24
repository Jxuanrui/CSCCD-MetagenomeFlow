# VirSorter2 — 病毒序列预测

**版本**: 2.2+ | **环境**: `envs/virsorter2` | **脚本**: `scripts/53_vir_virsorter2.sh`

## 功能
VirSorter2 使用多重分类器（随机森林 + 标记基因 + HMM 特征）对宏基因组 contigs 进行病毒序列预测，覆盖 dsDNA 噬菌体、ssDNA 病毒、RNA 病毒、NCLDV 和 Lavida 病毒等 5 组病毒。在本流程中与 geNomad 取交集后输入 CheckV，最大化病毒序列召回率的同时控制假阳性。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/virus/assembly/{sample}/{sample}.contigs.fa` |
| 病毒边界预测 | `result/virus/virsorter2/{sample}/final-viral-boundary.tsv` |
| 病毒评分 | `result/virus/virsorter2/{sample}/final-viral-score.tsv` |
| 病毒序列（合并） | `result/virus/virsorter2/{sample}/final-viral-combined.fasta` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--include-groups` | dsDNAphage,ssDNA,RNA,NCLDV,lavidaviridae | 病毒分类覆盖 |
| `--min-length` | 1000 | 最小序列长度（bp） |
| `--db-dir` | `db/virsorter2` | 数据库路径 |
| `--use-conda-off` | on | 禁止内部 conda 调用（使用项目环境） |
| `-j` | CPUS | 线程数 |
| `--verbose` | on | 详细日志输出 |

## 支持的五组病毒

| 组名 | 覆盖范围 |
|------|---------|
| `dsDNAphage` | 双链 DNA 噬菌体（最主要的组） |
| `ssDNA` | 单链 DNA 病毒 |
| `RNA` | RNA 病毒 |
| `NCLDV` | 核质大 DNA 病毒（感染真核生物） |
| `lavidaviridae` | Lavida 病毒科 |

## 与 geNomad 互补性

| 场景 | 建议 |
|------|------|
| 仅需保守预测 | geNomad 单独（特异度更高） |
| 最大化召回率 | geNomad + VirSorter2 取并集 |
| 高质量病毒集 | geNomad + VirSorter2 **取交集** → CheckV（本流程默认策略） |
| 捕获 RNA 病毒 | 必须用 VirSorter2（geNomad 不支持） |

## 注意事项
- VirSorter2 数据库约 5 GB，位于 `db/virsorter2/`
- `--use-conda-off` 是必需的。VirSorter2 默认会在运行时启动 conda 环境，但这会与项目的 conda run 冲突；该标志让 VirSorter2 使用已激活环境中的工具，而非自启动 conda
- VirSorter2 输出包含病毒边界信息（`final-viral-boundary.tsv`），标识每条 contig 上的病毒区域精确起止坐标

## 官方链接
- GitHub: https://github.com/jiarong/VirSorter2
- 论文: Guo et al. 2021, Nature Biotechnology 39:578–585
