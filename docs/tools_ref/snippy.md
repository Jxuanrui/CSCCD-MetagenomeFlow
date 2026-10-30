# Snippy — SNP/InDel 变异检测

**版本**: 4.0.2 | **环境**: `envs/snippy` | **脚本**: `scripts/41d_bac_snippy.sh`

## 功能
Snippy 对细菌基因组进行快速 SNP 和 small InDel 检测，通过将查询序列（MAGs 或原始读段）与参考基因组比对来鉴定变异位点，支持 `snippy-core` 提取跨菌株的核心 SNP 矩阵，用于系统发育树构建。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 MAGs | `result/binning/drep/dereplicated_genomes/*.fa` |
| 参考基因组 | 自动选最大 MAG 或 `-R` 指定 |
| 核心 SNP 表 | `result/wgs/snippy/core.tsv` |
| 核心比对 | `result/wgs/snippy/core.clean.aln` |
| 运行摘要 | `result/wgs/snippy/summary.txt` |

## 运行模式
本脚本使用**装配模式**（`--ctgs`，contig-vs-reference），而非读段比对模式（`--pe1/--pe2`）。适用于 MAG 对参考基因组的 SNP 检测。

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--cpus` | CPUS | 线程数 |
| `--ref` | 参考基因组路径 | 参考序列（.fa/.fasta/.gbk/.gbff） |
| `--ctgs` | MAG 路径 | 装配对比模式 |
| `--outdir` | 每个 MAG 独立目录 | 输出路径 |
| snippy-core `--ref` | 同上 | 汇总各 MAG 结果 |

## 示例命令

```bash
# 聚合 SNP 分析（自动以最大 MAG 为参考）
bash scripts/41d_bac_snippy.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 指定外部参考基因组
bash scripts/41d_bac_snippy.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow \
    -R /path/to/reference.fasta

# 手动：单 MAG 比对
conda run --prefix envs/snippy snippy \
    --cpus 16 --ref reference.fa \
    --ctgs bin.001.fa --outdir result/wgs/snippy/bin001

# 提取核心 SNP 矩阵
conda run --prefix envs/snippy snippy-core \
    --ref reference.fa \
    --prefix result/wgs/snippy/core \
    result/wgs/snippy/*/

# 清理比对（去除重复碱基位置）
conda run --prefix envs/snippy snippy-clean_full_aln \
    result/wgs/snippy/core.full.aln > result/wgs/snippy/core.clean.aln
```

## 输出文件说明

| 文件 | 含义 |
|------|------|
| `core.tsv` | 每个 SNP 位点的注释（位置、类型、影响） |
| `core.tab` | 核心 SNP 矩阵（SNP×样本） |
| `core.clean.aln` | 清洗后的多序列比对，直接用于建树 |
| `summary.txt` | 统计摘要（参考基因组、MAG 数、SNP 总数） |

## 下游分析
```bash
# 用 FastTree 快速建系统发育树
conda run --prefix envs/prokaWGS FastTree -nt -gtr core.clean.aln > core.tree

# 用 snp-dists 计算 SNP 距离矩阵
conda run --prefix envs/snippy snp-dists core.clean.aln > snp_distance_matrix.tsv
```

## 注意事项
- 版本说明：snippy 4.6.0 因 samtools/libdeflate 依赖冲突无法安装，使用 4.0.2，功能等价
- 装配模式（`--ctgs`）适合 MAG 分析；若有原始读段建议用 `--pe1/--pe2` 模式获得更高精度
- 参考基因组选择影响 SNP 结果：应选最完整、最接近研究菌株的序列

## 官方链接
- GitHub: https://github.com/tseemann/snippy
- snp-dists: https://github.com/tseemann/snp-dists
