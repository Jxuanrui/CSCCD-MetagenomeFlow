# eggNOG-mapper — 综合功能注释

**版本**: 2.1.13 | **环境**: `envs/eggnog` | **脚本**: `scripts/21_bac_eggnog.sh`

## 功能
eggNOG-mapper v2 使用 DIAMOND 同源搜索对蛋白序列进行综合功能注释，覆盖 COG 功能分类、KEGG KO 通路、GO 富集、EC 酶编号和 CAZy 碳水化合物酶。在一个运行中同时获得多种注释，是宏基因组功能注释的首选入口。

## 用法

```bash
bash scripts/21_bac_eggnog.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| 主注释表 | `result/eggnog/eggnog.emapper.annotations` |
| 同源命中 | `result/eggnog/eggnog.emapper.seed_orthologs` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-m` | diamond | 同源搜索算法 |
| `--itype` | proteins | 输入类型 |
| `--dbmem` | on | 数据库加载到内存加速 |
| `--data_dir` | `db/eggnog` | eggNOG 数据库路径 |
| `--override` | on | 覆盖现有输出 |

## 注释表格式

`.emapper.annotations` 文件包含（制表符分隔）：
```
#query    seed_ortholog  evalue  score  eggNOG_OGs  COG_cat  KEGG_KO  GO  EC  CAZy
gene_1    COGxxxx        1e-50   250   1@NOG       J         K00001   GO:...  1.1.1.1  GH1
```

## 注意事项
- eggNOG 数据库约 30 GB，需提前下载至 `db/eggnog/`
- `--dbmem` 需要约 30 GB RAM，若内存受限可移除
- 注释为 aggregate 步骤，依赖 CD-HIT 的 `protein_nr.fa`
- 运行时间 30-120 分钟，取决于基因数量

## 官方链接
- GitHub: https://github.com/eggnogdb/eggnog-mapper
- 论文: Cantalapiedra et al. 2021, Molecular Biology and Evolution
