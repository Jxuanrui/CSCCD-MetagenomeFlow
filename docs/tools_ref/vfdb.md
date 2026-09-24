# VFDB — 毒力因子注释

**环境**: `envs/assembly`（DIAMOND）| **脚本**: `scripts/26_bac_vfdb.sh`

## 功能
使用 DIAMOND blastp 将蛋白序列比对到 VFDB（Virulence Factors of Pathogenic Bacteria）数据库，鉴定样本中的毒力因子编码基因。

## 用法

```bash
bash scripts/26_bac_vfdb.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| VFDB 命中 | `result/vfdb/vfdb_hits.tsv` |

## 注意事项
- VFDB 数据库位于 `db/vfdb/*.dmnd`（约 2 GB）
- 输出 BLAST m6 格式，每个基因仅保留最佳匹配

## 官方链接
- VFDB: http://www.mgc.ac.cn/VFs
- 论文: Liu et al. 2022, Nucleic Acids Research (VFDB)
