# Centrifuger — 蛋白级精确物种分类

**版本**: v1.0.5 | **环境**: `envs/assembly` | **脚本**: `scripts/15_bac_centrifuger.sh`

## 功能
Centrifuger 使用 FM-index + 无损压缩技术进行蛋白级精确物种分类。其数据库覆盖 GTDB R226 + RefSeq HVFC，同时支持细菌、古菌、病毒和真菌。相比 Kraken2 精度更高（尤其种/属级），但速度慢约 2.3 倍。分类结果输出 Kraken2 兼容格式供下游分析。

## 用法

```bash
bash scripts/15_bac_centrifuger.sh -s SAMPLE -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 R1 | `result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz` |
| 输入 R2 | `result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz` |
| 分类报告 | `result/centrifuger/{sample}/{sample}.kreport.tsv` |
| 每 reads 分类 | `result/centrifuger/{sample}/{sample}.classifications.tsv.gz` |

## 三种分类工具对比

| 工具 | 索引方法 | 数据库 | 精度 | 速度 | 推荐场景 |
|------|---------|--------|------|------|---------|
| MetaPhlAn4 | Marker gene | ~1 万基因组 | 最高（种/菌株级） | 快 | 精确分类 |
| Kraken2 | k-mer | PlusPF ~20G | 中等 | **最快** | 快速筛查 |
| **Centrifuger** | FM-index | GTDB+RefSeq 166G | **最高（蛋白级）** | 慢 2.3× | 正式精准分析 |

## 注意事项
- 数据库约 166 GB，内存需求 ≥100 GB
- 输出 `.kreport.tsv` 格式与 Kraken2 完全兼容
- 每条 read 的详细分类结果（`.classifications.tsv.gz`）压缩存储以节省磁盘
- 分类输出管道直接压缩为 gzip，避免大文件中间占用

## 官方链接
- GitHub: https://github.com/mourisl/centrifuger
- 论文: Song & Langmead, Genome Biology 2024
