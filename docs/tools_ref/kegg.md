# KEGG — KEGG KO 通路注释

**环境**: `envs/assembly`（DIAMOND）| **脚本**: `scripts/22_bac_kegg.sh` / `82_fun_kegg.sh`

## 功能
使用 DIAMOND blastp 将蛋白序列比对到 KEGG 蛋白数据库，获取 KO（KEGG Orthology）注释，用于将基因映射到 KEGG 代谢和信号通路。

## 用法

```bash
# 细菌功能注释
bash scripts/22_bac_kegg.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 真菌功能注释
bash scripts/82_fun_kegg.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa`（细菌）/ `result/fungi/cdhit/protein_nr.fa`（真菌） |
| DIAMOND 命中 | `result/kegg/kegg_diamond.tsv` |

## 输出格式（BLAST m6）

```
qseqid  sseqid  pident  length  mismatch  gapopen  qstart  qend  sstart  send  evalue  bitscore
gene_1  K00001  98.5    300     2         1        1       300   100     399    1e-150  550.0
```

## 注意事项
- KEGG 数据库约 48 GB，位于 `db/kegg/*.dmnd`
- 使用 `--max-target-seqs 1` 仅保留每个基因的最佳匹配
- 结果可与 eggNOG 输出的 KO 注释交叉验证
- 依赖 CD-HIT 的 `protein_nr.fa`

## 官方链接
- KEGG: https://www.kegg.jp
- DIAMOND: https://github.com/bbuchfink/diamond
