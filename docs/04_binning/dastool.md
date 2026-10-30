# DAS_Tool — 多算法 Binning 整合

**版本**: 1.1.7 | **环境**: `envs/dastool` | **脚本**: `scripts/36_bac_dastool.sh`

## 功能
DAS_Tool（Dereplication, Aggregation and Scoring Tool）整合来自多种 binning 算法的结果，通过对每个 contig 的 bin 分配进行打分和去冗余，选出最高质量的非冗余 bin 集合，显著优于任何单一 binning 工具。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| contigs | `result/assembly/megahit/{sample}/{sample}.contigs.fa` |
| MetaBAT2 tsv | `result/binning/metabat2/{sample}/{sample}.tsv` |
| MaxBin2 tsv | `result/binning/maxbin2/{sample}/{sample}.maxbin2.tsv` |
| SemiBin2 tsv | `result/binning/semibin2/{sample}/{sample}.semibin2.tsv` |
| 整合 contig2bin | `result/binning/dastool/{sample}/{sample}_DASTool_contig2bin.tsv` |
| 汇总统计 | `result/binning/dastool/{sample}/{sample}_DASTool_summary.tsv` |
| 优化 bins | `result/binning/dastool/{sample}/bins/*.fa` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | 多个 tsv 路径（逗号分隔） | 输入各工具 contig2bin 文件 |
| `-c` | contigs FASTA | 输入序列 |
| `-o` | 输出前缀 | 结果路径 |
| `--score_threshold` | 0.5 | bin 质量分数阈值（0-1） |
| `--duplicate_penalty` | 0.6 | 多工具共同分配的惩罚系数 |
| `--megabin_penalty` | 0.5 | 超大 bin 惩罚（防止过度聚合） |
| `--write_bins` | 1 | 是否输出 bin FASTA 文件 |
| `-t` | CPUS | 线程数 |

## 示例命令

```bash
# 整合三种 binning 结果
bash scripts/36_bac_dastool.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 查看整合结果统计
cat result/binning/dastool/SAMPLE01/SAMPLE01_DASTool_summary.tsv | column -t
```

## 输出统计格式（summary.tsv）
```
bin        size    contigs  N50     completeness  contamination  score
bin.1      2.1Mb   45       85000   95.2          2.3            0.89
bin.2      1.8Mb   38       72000   87.4          4.1            0.78
```

## DAS_Tool 打分原理

每个 contig 根据来自多种工具的 bin 分配计算分数：
- **一致性加分**：多工具同意同一分配 → 高分
- **重复惩罚**：同一 contig 被分配到多个不同 bin → 扣分
- **大小惩罚**：异常大的 bin → 轻微扣分

最终选择 `score_threshold` 以上的 bin，确保质量门槛。

## 注意事项
- DAS_Tool 要求至少 2 种工具的 tsv 输入；若某工具完全没有输出 bin，脚本会跳过该工具
- `score_threshold 0.5` 较保守；若想保留更多 bin 可降至 0.3，但污染率会升高
- DAS_Tool 输出的 bins 即为 CheckM2 的输入，命名格式会保留原始 bin 工具前缀

## 官方链接
- GitHub: https://github.com/cmks/DAS_Tool
- 论文: Sieber et al. 2018, Nature Microbiology 3:836-843
