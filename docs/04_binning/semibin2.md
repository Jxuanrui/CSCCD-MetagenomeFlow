# SemiBin2 — 自监督 ML 分箱

**版本**: 2.x | **环境**: `envs/semibin` | **脚本**: `scripts/35_bac_semibin2.sh`

## 功能
SemiBin2 使用自监督机器学习方法（对比学习 + 变分自编码器）进行宏基因组分箱。它利用 contig 的序列组成和丰度特征训练样本特异性模型，无需外部参考基因组，是三种 binning 算法中精度最高的。

## 用法

```bash
bash scripts/35_bac_semibin2.sh -s SAMPLE -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/assembly/megahit/{sample}/{sample}.contigs.fa` |
| 输入 BAM | `result/binning/coverm/{sample}/{sample}.bam`（**原始 BAM，非深度表**） |
| SemiBin2 输出 | `result/binning/semibin2/{sample}/output/` |
| contig2bin TSV | `result/binning/semibin2/{sample}/{sample}.semibin2.tsv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--self-supervised` | on | 自监督模式（无需参考基因组） |
| `--input-fasta` | contigs FASTA | 输入序列 |
| `--input-bam` | BAM 文件 | **原始 BAM（非深度表）** |
| `-t` | CPUS | 线程数 |

## SemiBin2 与其他 binning 的关键区别

- **MetaBAT2 / MaxBin2**：使用预定义的深度特征 + 覆盖度
- **SemiBin2**：自监督学习，从数据中自动学习特征表示
- SemiBin2 使用 BAM 而不是深度表，因为它需要原始比对信息（CIGAR、MAPQ 等）训练模型

## 注意事项
- SemiBin2 **需要原始 BAM 文件**（非 CoverM 生成的深度表），由 32 脚本生成
- 自监督模式在样本间独立训练模型，比跨样本模式更慢但可能更准确
- 常作为 DAS_Tool 的第三个输入（与 MetaBAT2 和 MaxBin2 互补）

## 官方链接
- GitHub: https://github.com/BigDataBiology/SemiBin2
- 论文: Pan et al. 2023, Nature Communications
