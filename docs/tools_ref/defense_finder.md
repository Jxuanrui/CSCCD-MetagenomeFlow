# DefenseFinder — 细菌防御系统检测

**版本**: 1.x | **环境**: `envs/defense-finder` | **脚本**: `scripts/29_bac_defense_finder.sh`

## 功能
DefenseFinder 使用 MacSyFinder 和 HMM profiles 检测细菌基因组中的防御系统，包括 CRISPR-Cas、限制修饰系统（RM）、毒素-抗毒素（TA）系统和其他抗病毒免疫系统。

## 用法

```bash
bash scripts/29_bac_defense_finder.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| 防御系统汇总 | `result/defense_finder/defense_finder_systems.tsv` |
| 基因级别注释 | `result/defense_finder/defense_finder_genes.tsv` |

## 检测的主要防御系统

| 系统 | 类型 | 说明 |
|------|------|------|
| CRISPR-Cas | I–VI 型 | 适应性免疫 |
| Restriction-Modification | I–IV 型 | 限制性内切酶 |
| Toxin-Antitoxin | 多种 | 质粒维持/程序性死亡 |
| Abi | 多种 | 感染后流产 |
| BREX | 噬菌体排除 | 甲基化标记 |
| DISARM | 防御岛 | 多组分系统 |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--models-dir` | `db/defense-finder/...` | HMM 模型目录 |
| `--db-type` | unordered | 宏基因组模式（无连续基因组座标） |
| `--workers` | CPUS | 线程数 |

## 注意事项
- 对宏基因组使用 `--db-type unordered`（NR 蛋白没有连续基因组座标）
- DefenseFinder 结果依赖于输入蛋白集的完整性
- 输出覆盖约 40+ 种已知防御系统

## 官方链接
- GitHub: https://github.com/mdmparis/defense-finder
- 论文: Tesson et al. 2022, Nature Communications
