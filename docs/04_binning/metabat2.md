# MetaBAT2 — 宏基因组 Binning

**版本**: 2.12.1 | **环境**: `envs/metawrap` | **脚本**: `scripts/33_bac_metabat2.sh`

## 功能
MetaBAT2 使用 contig 序列组成（四核苷酸频率，TNF）与跨样本覆盖度（coverage depth）的组合特征，通过聚类将宏基因组 contig 划分为微生物基因组 bin（MAG）。是 DAS_Tool 集成的三种 binning 算法之一。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/assembly/megahit/{sample}/{sample}.contigs.fa` |
| 覆盖深度表 | `result/binning/coverm/{sample}/depth.txt` |
| 输出 bins | `result/binning/metabat2/{sample}/bins/bin.*.fa` |
| contig2bin TSV | `result/binning/metabat2/{sample}/{sample}.tsv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | contigs FASTA | 输入序列 |
| `-a` | 深度文件路径 | jgi_summarize_bam_contig_depths 输出 |
| `-o` | bin 输出前缀 | 输出路径 |
| `-m` | 2500 | 最短 contig 长度（bp，推荐 ≥1500） |
| `-t` | CPUS | 线程数 |
| `--minClsSize` | 200000 | 最小 bin 大小（bp） |
| `-s` | 100000 | 基于覆盖度分裂的种子大小 |

## 深度文件生成
MetaBAT2 需要 `jgi_summarize_bam_contig_depths` 工具从 BAM 文件生成深度表（由 `32_bac_coverm_depth.sh` 完成）：

```bash
# 32 脚本内部执行（无需手动）
jgi_summarize_bam_contig_depths \
    --outputDepth depth.txt \
    result/binning/coverm/SAMPLE01/SAMPLE01.bam
```

## 示例命令

```bash
# 运行 MetaBAT2
bash scripts/33_bac_metabat2.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 统计 bin 数量和大小
for f in result/binning/metabat2/SAMPLE01/bins/bin.*.fa; do
    echo -e "$(basename $f)\t$(grep -c '^>' $f) contigs"
done
```

## 注意事项
- MetaBAT2 对低覆盖度样本（<5× 平均深度）效果差；建议与 MaxBin2 和 SemiBin2 联用
- `-m 2500` 可提高 bin 质量但减少 contig 数量；若样本较差可降至 1500
- contig2bin TSV 格式为两列：`contig_ID\tbin_ID`，DAS_Tool 需要此格式

## 三种 Binning 算法对比

| 工具 | 优势 | 劣势 |
|------|------|------|
| MetaBAT2 | 成熟稳定，覆盖度利用好 | 对单样本效果一般 |
| MaxBin2 | 不需要覆盖度（可选）| 精度略低 |
| SemiBin2 | 机器学习，高精度 | 需要训练时间 |
| **DAS_Tool 整合** | 取三者交集最优 | 三倍计算量 |

## 官方链接
- GitHub: https://bitbucket.org/berkeleylab/metabat
- 论文: Kang et al. 2019, PeerJ 7:e7359
