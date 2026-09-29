# dbCAN3 — CAZyme 碳水化合物酶注释

**版本**: run_dbcan 4.x | **环境**: `envs/dbcan` | **脚本**: `scripts/25_bac_dbcan.sh`

## 功能
dbCAN3 使用 HMMER + DIAMOND 两种方法对蛋白序列进行碳水化合物活性酶（CAZyme）注释，覆盖 GH/GT/CE/CBM/AA/PL 六大 CAZy 家族。采用多工具投票策略提高注释准确率。

## 用法

```bash
bash scripts/25_bac_dbcan.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| 综述结果 | `result/dbcan/overview.txt` |
| HMMER 结果 | `result/dbcan/hmmer.out` |
| DIAMOND 结果 | `result/dbcan/diamond.out` |

## CAZy 六大类

| 类别 | 全称 | 功能 |
|------|------|------|
| GH | Glycoside Hydrolases | 糖苷水解酶（最常见） |
| GT | GlycosylTransferases | 糖基转移酶 |
| CE | Carbohydrate Esterases | 碳水化合物酯酶 |
| CBM | Carbohydrate-Binding Modules | 碳水化合物结合模块 |
| AA | Auxiliary Activities | 辅助活性酶 |
| PL | Polysaccharide Lyases | 多糖裂解酶 |

## 注意事项
- dbCAN 数据库约 5 GB，位于 `db/dbcan3/`
- 使用 `--tools diamond` 加快速度（默认同时运行 HMMER + DIAMOND + eCAMI）

## 官方链接
- 数据库: http://bcb.unl.edu/dbCAN2
- 论文: Zheng et al. 2023, Nucleic Acids Research (dbCAN3)
