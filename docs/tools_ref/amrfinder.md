# AMRFinderPlus — 抗生素耐药基因检测

**版本**: 3.12+ | **环境**: `envs/amr` | **脚本**: `scripts/23_bac_amrfinder.sh`

## 功能
AMRFinderPlus 使用 NCBI 维护的抗性基因数据库（约 6000 个 HMM）检测抗生素耐药基因（ARGs），同时可选检测应激耐受、毒力因子和耐药点突变。采用严格的 `--ident_min 0.9 / --coverage_min 0.6` NCBI 推荐阈值，确保高特异性。

## 用法

```bash
bash scripts/23_bac_amrfinder.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| 耐药基因报告 | `result/amrfinder/amrfinder_results.tsv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--ident_min` | 0.9 | 最低序列一致性（NCBI 推荐） |
| `--coverage_min` | 0.6 | 最低 HMM 覆盖度 |
| `--plus` | on | 检测应激耐受/毒力/点突变 |
| `--database` | `db/amrfinder/latest` | 数据库路径 |

## 输出字段

TSV 输出包含：protein_id, gene_symbol, sequence_name, scope, element_type, element_subtype, class, subclass, method, target_length, query_coverage, identity, hmm_coverage 等。

## AMRFinderPlus vs CARD/RGI

| 工具 | 数据库 | 阈值策略 | 覆盖范围 |
|------|--------|---------|---------|
| AMRFinderPlus | NCBI AMR (~6000 HMM) | 严格（0.9/0.6） | ARG + 应激 + 毒力 + 点突变 |
| CARD/RGI | CARD (~2000 ARO) | 宽松（含 Loose） | ARG + 抗性机制分类 |

**建议**：AMRFinderPlus 作为主结果（高特异性），CARD 补充（更全面的抗性机制）

## 官方链接
- GitHub: https://github.com/ncbi/amr
- 论文: Feldgarden et al. 2021, Scientific Reports
