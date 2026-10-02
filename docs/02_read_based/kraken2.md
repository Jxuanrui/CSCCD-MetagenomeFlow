# Kraken2 + Bracken — 快速物种分类

**版本**: Kraken2 2.1.3 | **环境**: `envs/kraken2` | **脚本**: `scripts/14_bac_kraken2.sh`

## 功能
Kraken2 使用 k-mer 精确匹配对读段进行快速分类学分类；Bracken 在 Kraken2 结果基础上重新估算各物种丰度（消除 k-mer 分配偏差）。两者组合是宏基因组快速分类的首选方案。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 R1/R2 | `result/kneaddata/{sample}/` |
| Kraken2 报告 | `result/kraken2/{sample}/{sample}.report` |
| Kraken2 输出 | `result/kraken2/{sample}/{sample}.kraken2` |
| Bracken 丰度 | `result/kraken2/{sample}/{sample}.bracken` |
| Bracken 报告 | `result/kraken2/{sample}/{sample}.bracken.report` |

## 数据库（`db/kraken2/`）

| 数据库 | 大小 | 特点 |
|--------|------|------|
| `standard_8G/` | 8G | 精简版，适合内存受限环境 |
| `standard/` | ~60G | 全库，精度更高 |
| `PlusPF/` | ~140G | 含真菌、植物，用于真菌脚本 71 |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--db` | `db/kraken2/standard` | 数据库路径 |
| `--paired` | on | 成对读段模式 |
| `--threads` | CPUS | 线程数 |
| `--confidence` | 0.05 | 置信度阈值（降低假阳性） |
| `--minimum-base-quality` | 0 | 最低碱基质量 |
| Bracken `-r` | 150 | 读长（调整为实际测序读长） |
| Bracken `-l` | S | 分类级别（S=种，G=属） |

## 示例命令

```bash
# 细菌物种分类
bash scripts/14_bac_kraken2.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 合并多样本 Bracken 结果
combine_bracken_outputs.py \
    --files result/kraken2/*/\*.bracken \
    -o result/kraken2/merged/bracken_species.tsv
```

## MetaPhlAn4 vs Kraken2 选择指南

| 场景 | 推荐 |
|------|------|
| 高精度、菌株级分类 | MetaPhlAn4 |
| 快速探索性分析 | Kraken2+Bracken |
| 病毒/真菌检测 | Kraken2（PlusPF 库） |
| 发表级分析 | MetaPhlAn4 |

## 官方链接
- Kraken2 GitHub: https://github.com/DerrickWood/kraken2
- Bracken GitHub: https://github.com/jenniferlu717/Bracken
- 论文: Wood et al. 2019, Genome Biology 20:257
