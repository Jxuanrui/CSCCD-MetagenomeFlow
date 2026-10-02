# NCyc — 氮循环功能基因注释

**环境**: `envs/assembly`（DIAMOND）| **脚本**: `scripts/30_bac_ncyc.sh`

## 功能
使用 DIAMOND blastp 将蛋白序列比对到 NCyc 氮循环功能基因数据库，检测参与氮固定、硝化、反硝化等过程的功能基因。

## 用法

```bash
bash scripts/30_bac_ncyc.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| NCyc 命中 | `result/ncyc/ncyc_hits.tsv` |

## 覆盖的氮循环过程

| 过程 | 关键基因 | 意义 |
|------|---------|------|
| 氮固定 | nifH, nifD, nifK | N₂ → NH₃ |
| 硝化（氨氧化） | amoA, amoB, amoC | NH₃ → NO₂⁻ |
| 硝化（亚硝酸氧化） | nxrA, nxrB | NO₂⁻ → NO₃⁻ |
| 反硝化 | narG, nirK/nirS, norB, nosZ | NO₃⁻ → N₂ |
| 厌氧氨氧化 | hzo, hdh | NH₃ + NO₂⁻ → N₂ |
| 异化硝酸盐还原 | nrfA, nirB | NO₃⁻ → NH₄⁺ |

## 注意事项
- 数据库位于 `db/ncyc/*.dmnd`，基于 Tu et al. 2019
- 输出 BLAST m6 格式

## 官方链接
- 论文: Tu et al. 2019, mBio (NCyc)
