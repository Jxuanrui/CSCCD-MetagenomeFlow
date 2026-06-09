# Bakta — 原核生物基因组精细注释

**版本**: 1.12.0 | **环境**: `envs/bakta` | **脚本**: `scripts/41_bac_bakta.sh`

## 功能
Bakta 对原核生物（细菌/古菌）基因组进行端到端快速精细注释，覆盖蛋白编码基因、rRNA/tRNA/ncRNA、CRISPR 位点、信号肽、跨膜螺旋等要素，输出多种标准格式（GFF3/GenBank/TSV/FASTA/JSON）。是 MAG 全基因组注释的推荐工具，也是泛基因组分析（Roary）的前置步骤。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 MAGs | `result/binning/drep/dereplicated_genomes/*.fa` |
| 输出目录 | `result/binning/bakta/{mag_name}/` |
| GFF3 注释 | `result/binning/bakta/{mag_name}/{mag_name}.gff3` |
| GenBank | `result/binning/bakta/{mag_name}/{mag_name}.gbff` |
| 蛋白序列 | `result/binning/bakta/{mag_name}/{mag_name}.faa` |
| 汇总 TSV | `result/binning/bakta/bakta_summary.tsv` |

## 数据库（`db/bakta/`）
约 30 GB（完整版），包含 UniRef90、RefSeq 非冗余、NCBI AMR Gene Family、KEGG 等。

```bash
# 下载数据库（如缺失）
bakta_db download --output db/bakta --type full
```

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--db` | `db/bakta` | 数据库路径 |
| `--output` | 每个 MAG 独立目录 | 输出目录 |
| `--prefix` | MAG 名称 | 输出文件前缀 |
| `--genus` | （自动/不指定） | 属名提示（提高 locus tag 质量） |
| `--species` | （自动/不指定） | 种名提示 |
| `--threads` | CPUS | 线程数 |
| `--force` | — | 覆盖已有输出 |
| `--keep-contig-headers` | on | 保留原始 contig 名 |

## 示例命令

```bash
# 聚合注释所有 dRep MAGs
bash scripts/41_bac_bakta.sh -t 16 -w /path/to/workdir -r ~/Course/Maxmetagenome

# 单 MAG 手动运行
conda run --prefix envs/bakta bakta \
    --db db/bakta \
    --output result/binning/bakta/bin001 \
    --prefix bin001 \
    --threads 16 \
    result/binning/drep/dereplicated_genomes/bin001.fa

# 查看注释统计（TSV 汇总）
cut -f1,4,5 result/binning/bakta/bakta_summary.tsv | head -20
```

## GFF3 输出（供 Roary 使用）
Bakta 输出标准 GFF3，Roary 直接读取 `.gff3` 文件进行泛基因组分析：

```
##gff-version 3
contig_1  Bakta  CDS  100  450  .  +  0  ID=BAKTA_00001;gene=dnaA;...
contig_1  Bakta  tRNA 500  600  .  -  0  ID=BAKTA_00002;product=tRNA-Ala;...
```

## Bakta vs Prokka

| 特性 | Bakta | Prokka |
|------|-------|--------|
| 维护状态 | 积极维护 | 不再主动更新 |
| 数据库 | 更新频繁（月级） | 数据库较旧 |
| 功能覆盖 | 更全（CRISPR, AMR, 信号肽） | 基础 |
| 速度 | 稍慢 | 较快 |
| 推荐 | **新项目推荐** | 历史项目兼容 |

## 注意事项
- Bakta 对基因组质量要求：完整性 ≥ 50%，污染 ≤ 10%（CheckM2 过滤后的 MAGs）
- GFF3 文件可直接用于 Roary（泛基因组），无需格式转换
- 若数据库下载慢，可先用 `--type light` 轻量版（5 GB）

## 官方链接
- GitHub: https://github.com/oschwengers/bakta
- Web Server: https://bakta.computational.bio
- 论文: Schwengers et al. 2021, Microbial Genomics 7:000685
