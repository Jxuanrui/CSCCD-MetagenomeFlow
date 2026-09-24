# CD-HIT — 基因去冗余（Gene Catalog 构建）

**版本**: v4.8.1 | **环境**: `envs/assembly` | **脚本**: `scripts/18_bac_cdhit.sh`

## 功能
CD-HIT-EST 对跨样本基因集进行 95% 核苷酸序列相似度聚类去冗余，构建非冗余基因目录（NR Gene Catalog），遵循 MetaHIT/IGC 国际标准。输出核苷酸序列用于 Salmon 定量，蛋白序列用于功能注释（eggNOG/KEGG/AMR 等）。

**四步流程**：合并 → 过滤 ≥100bp → CD-HIT-EST 聚类 → seqkit 翻译蛋白

## 用法

```bash
bash scripts/18_bac_cdhit.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入基因序列 | `result/assembly/prodigal/{sample}/{sample}.fna`（自动发现全部样本） |
| 非冗余核苷酸 | `result/assembly/cdhit/nucleotide_nr.fa` |
| 蛋白序列 | `result/assembly/cdhit/protein_nr.fa` |
| 聚类信息 | `result/assembly/cdhit/nucleotide_nr.fa.clstr` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-c` | 0.95 | 核苷酸序列相似度阈值（MetaHIT 标准） |
| `-aS` | 0.9 | 短序列比对覆盖度（以短者为基准） |
| `-G` | 0 | 局部比对模式（适合可变长度基因） |
| `-g` | 1 | 精确贪心聚类（更慢但更准确） |
| `-r` | 1 | 双链比较（++ 和 +- 两个方向） |
| `-n` | 10 | word size（对应 -c 0.95） |

## 下游依赖

- `nucleotide_nr.fa` → **19 Salmon build**（定量索引）
- `protein_nr.fa` → **21 eggNOG, 22 KEGG, 23 AMRFinder, 24 CARD, 25 dbCAN, 26 VFDB, 27 BacMet, 29 Defense-Finder, 30 NCyc, 31 PCyc**

## 注意事项
- 这是 aggregate 步骤（无 `-s` 参数），需所有样本的 Prodigal 输出就位
- 序列自动加样本名前缀防冲突：`>sample_id|gene_header`
- 遵循 MetaHIT 标准过滤 <100 bp 的 ORF
- 去冗余率通常 60-80%（10 个样本规模）

## 官方链接
- GitHub: https://github.com/weizhongli/cdhit
- 论文: Li & Godzik 2006 Bioinformatics; Fu et al. 2012 Bioinformatics
