# VOGDB — 跨界病毒 HMM 扫描

**环境**: `envs/assembly`（HMMER）| **脚本**: `scripts/66_vir_vog.sh`

## 功能
使用 HMMER 将病毒蛋白序列扫描 VOGDB（Viral Orthologous Groups）HMM 数据库，进行跨界（细菌/古菌/真核病毒）病毒功能注释。VOGDB 包含保守病毒蛋白家族，可注释 PHAROKKA 未能覆盖的功能。

## 用法

```bash
bash scripts/66_vir_vog.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/virus/pharokka/prodigal-gv.faa` |
| HMM 命中表 | `result/virus/vog/vog_hits.tsv` |
| 功能注释表 | `result/virus/vog/vog_annot.tsv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--cut_ga` | on | 使用 gathering cutoff（严格阈值） |
| `--cpu` | CPUS | 线程数 |
| `--tblout` | 命中表 | 结果输出（表格格式） |

## 输出内容

`vog_annot.tsv` 包含：
```
vog_id    query_protein    function_description
VOG00001  gene_123         DNA polymerase family B
VOG00023  gene_456         major capsid protein
```

## 注意事项
- 依赖 PHAROKKA 的输出蛋白序列（`prodigal-gv.faa`）
- VOGDB 数据库约 3 GB，位于 `db/vogdb/`
- 若数据库不存在，脚本会创建空输出而非报错退出
- 使用 `--cut_ga` 确保高通量扫描时减少假阳性

## 官方链接
- VOGDB: https://vogdb.org
- HMMER3: http://hmmer.org
- 论文: Eddy 2011, PLoS Computational Biology (HMMER)
