# Roary — 泛基因组分析

**版本**: 3.13.0（in prokaWGS env） | **环境**: `envs/prokaWGS` | **脚本**: `scripts/41c_bac_pangenome.sh`

## 功能
Roary 对多个 GFF 格式注释基因组进行快速泛基因组分析，鉴定核心基因组（core genome，存在于所有/大多数菌株）和附属基因组（accessory genome），输出基因存在/缺失矩阵用于下游进化和功能多样性分析。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 GFF | `result/binning/bakta/*.gff`（Bakta 注释产出）|
| Pan-genome 统计 | `result/wgs/pangenome/summary_statistics.txt` |
| 存在/缺失矩阵 | `result/wgs/pangenome/gene_presence_absence.csv` |
| 核心基因比对 | `result/wgs/pangenome/core_gene_alignment.aln`（加 `-e` 时）|

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-p` | CPUS | 线程数 |
| `-e` | on | 对核心基因进行多序列比对 |
| `--mafft` | on | 用 MAFFT 做比对（`-e` 时使用） |
| `-i` | 95 | 蛋白序列同一性阈值（%） |
| `-cd` | 99 | 核心基因定义（存在于 ≥CD% 菌株） |
| `-f` | 输出目录 | 输出路径 |

## 示例命令

```bash
# 聚合泛基因组分析（需要 ≥3 个 GFF 文件）
bash scripts/41c_bac_pangenome.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 手动运行
conda run --prefix envs/prokaWGS roary \
    -p 16 -e --mafft -i 95 -cd 99 \
    -f result/wgs/pangenome/ \
    result/binning/bakta/*.gff

# 可视化存在/缺失矩阵（Roary 自带）
roary_plots.py result/wgs/pangenome/accessory_binary_genes.fa.newick \
               result/wgs/pangenome/gene_presence_absence.csv
```

## 输出格式（summary_statistics.txt）
```
Core genes  (99% <= strains <= 100%)    1234
Soft core genes (95% <= strains < 99%)  89
Shell genes (15% <= strains < 95%)      456
Cloud genes (0% <= strains < 15%)       789
Total genes (0% <= strains <= 100%)     2568
```

## Pan-genome 概念

| 类型 | 定义（默认阈值） | 生物学意义 |
|------|----------------|----------|
| 核心基因 | ≥99% 菌株携带 | 基本代谢、生长必需 |
| 软核心 | 95-99% | 高度保守但非绝对必需 |
| 附属（壳） | 15-95% | 适应性基因 |
| 云（稀有）| <15% | 移动元件、环境特异基因 |

## 注意事项
- 需要至少 3 个同物种的 GFF 文件；跨物种比较意义有限
- Bakta 输出的 GFF3 格式与 Roary 兼容；Prokka 的 GFF 也兼容
- `-cd 99` 很严格；若菌株数量少（<5），建议降至 90 以避免核心基因组过小
- 核心基因比对（`core_gene_alignment.aln`）可直接输入 FastTree/IQ-TREE 建系统发育树

## 官方链接
- GitHub: https://github.com/sanger-pathogens/Roary
- 文档: https://sanger-pathogens.github.io/Roary
- 论文: Page et al. 2015, Bioinformatics 31(22):3691-3693
