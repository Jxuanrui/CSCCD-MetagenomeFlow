# MaxBin2 — 基于 EM 的分箱

**版本**: 2.2.7 | **环境**: `envs/metawrap` | **脚本**: `scripts/34_bac_maxbin2.sh`

## 功能
MaxBin2 使用期望最大化（EM）算法结合四核苷酸频率（tetranucleotide）和 contig 覆盖度进行宏基因组分箱，是 DAS_Tool 集成的三种 binning 算法之一。

## 用法

```bash
bash scripts/34_bac_maxbin2.sh -s SAMPLE -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/assembly/megahit/{sample}/{sample}.contigs.fa` |
| 覆盖深度 | `result/binning/coverm/{sample}/depth.txt` |
| 输出 bins | `result/binning/maxbin2/{sample}/bin.{n}.fasta` |
| contig2bin TSV | `result/binning/maxbin2/{sample}/{sample}.maxbin2.tsv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-contig` | contigs FASTA | 输入序列 |
| `-max_iteration` | 50 | EM 最大迭代次数 |
| `-thread` | CPUS | 线程数 |
| `-abund` | depth 文件 | 覆盖度（自动从 coverm 深度表提取） |

## 三种 Binning 算法对比

| 工具 | 核心算法 | 优势 | 劣势 |
|------|---------|------|------|
| MetaBAT2 | k-mer + 覆盖度聚类 | 成熟稳定 | 对单样本效果一般 |
| **MaxBin2** | EM + tetranucleotide | 覆盖度可选，适于多样本 | bin 数量偏少 |
| SemiBin2 | 自监督 ML | 精度最高 | 训练耗时 |

## 注意事项
- MaxBin2 的 abundance 文件从 CoverM depth.txt 自动提取（第 4 列 contig 平均深度）
- bin 数量受 EM 算法初始化影响，不同样本间 bin 数差异可能大
- 输出 TSV 供 DAS_Tool 整合使用

## 官方链接
- GitHub: https://github.com/ShuhengWu/MaxBin2
- 论文: Wu et al. 2014, Microbiome
