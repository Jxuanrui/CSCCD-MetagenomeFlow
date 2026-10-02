# vConTACT3 — 病毒分类基因共享网络

**版本**: 3.0+ | **环境**: `envs/vcontact3` | **脚本**: `scripts/69_vir_vcontact3.sh`

## 功能
vConTACT3 基于病毒蛋白基因共享网络进行病毒分类学分析，通过比对病毒蛋白组间的相似性构建网络，使用参考数据库辅助推断新病毒的科/属级分类。

## 用法

```bash
bash scripts/69_vir_vcontact3.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 vOTU 序列 | `result/virus/votu/contigs/virus.fasta` |
| 输入蛋白 | `result/virus/pharokka/prodigal-gv.faa` |
| 基因-基因组映射 | `result/virus/votu/votu_gene2genome.tsv`（自动生成） |
| 分类汇总 | `result/virus/vcontact3/genome_by_genome_overview.csv` |
| 网络图 | `result/virus/vcontact3/vConTACT3_*.graphml / .cyjs` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--nucleotide` | vOTU FASTA | 输入核酸序列 |
| `--output` | vcontact3 目录 | 输出路径 |
| `--db-path` | `db/vcontact3` | 参考数据库 |
| `-e` | graphml cytoscape d3js completeness | 输出格式 |

## 输出格式

| 格式 | 用途 |
|------|------|
| graphml | 网络可视化（Gephi/Cytoscape） |
| cyjs | Cytoscape.js Web 可视化 |
| d3js | D3.js 交互式图表 |
| completeness | 分类完整性评估 |

## 与 vOTU 聚类的关系

| 方法 | 聚类依据 | 用途 |
|------|---------|------|
| vclust（脚本 56） | 序列 ANI（95%） | 定义 vOTU 边界 |
| **vConTACT3**（本脚本） | 蛋白基因共享 | 分类学分配（科/属级） |

两者互补：vclust 定义 vOTU，vConTACT3 通过参考数据库推断病毒分类。

## 注意事项
- 依赖 PHAROKKA 的输出蛋白序列进行基因共享网络分析
- gene2genome 映射表自动从 PHAROKKA 的 GFF 文件提取
- 若 vConTACT3 参考数据库未配置，脚本会尝试自动下载

## 官方链接
- GitHub: https://github.com/RyanCook94/vcontact3
- 论文: Bin Jang et al. 2019, Nature Biotechnology (vConTACT2); vConTACT3 2025, Nature Biotechnology
