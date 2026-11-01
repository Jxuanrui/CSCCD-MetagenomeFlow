# PCyc — 磷循环功能基因注释

**环境**: `envs/assembly`（DIAMOND）| **脚本**: `scripts/31_bac_pcyc.sh`

## 功能
使用 DIAMOND blastp 将蛋白序列比对到 PCyc 磷循环功能基因数据库，检测参与有机磷矿化、无机磷溶解、磷转运等过程的功能基因。

## 用法

```bash
bash scripts/31_bac_pcyc.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| PCyc 命中 | `result/pcyc/pcyc_hits.tsv` |

## 覆盖的磷循环过程

| 过程 | 关键基因 | 意义 |
|------|---------|------|
| 有机磷矿化 | phoA, phoD, phoX | 有机磷→PO₄³⁻ |
| 植酸降解 | appA, phy | 植酸磷释放 |
| 无机磷溶解 | pqq, gdh | 不溶磷→可溶磷 |
| 磷转运 | pst, pit | PO₄³⁻ 跨膜转运 |
| 磷调控 | phoB, phoR, phoU | 磷饥饿响应调控 |

## 注意事项
- 数据库位于 `db/pcyc/*.dmnd`
- 与 NCyc 互补分析土壤/肠道微生态营养循环

## 官方链接
- PCyc 数据库参考: Dai et al. 2022 (磷循环功能基因)
