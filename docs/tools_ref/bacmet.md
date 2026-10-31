# BacMet — 重金属抗性基因注释

**环境**: `envs/assembly`（DIAMOND）| **脚本**: `scripts/27_bac_bacmet.sh`

## 功能
使用 DIAMOND blastp 将蛋白序列比对到 BacMet 数据库（Antibacterial Biocide and Metal Resistance Genes），检测重金属和抗菌剂抗性基因。

## 用法

```bash
bash scripts/27_bac_bacmet.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| BacMet 命中 | `result/bacmet/bacmet_hits.tsv` |

## 注意事项
- BacMet 数据库位于 `db/bacmet/*.dmnd`
- 与 AMRFinderPlus/CARD 互补：BacMet 覆盖重金属，AMR 工具覆盖抗生素

## 官方链接
- BacMet: http://bacmet.biomedicine.gu.se
- 论文: Pal et al. 2014, Journal of Global Antimicrobial Resistance
