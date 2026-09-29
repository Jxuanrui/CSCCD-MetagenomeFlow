# GTDB-Tk — MAG 系统发育分类

**版本**: 2.5.2 | **环境**: `envs/gtdbtk` | **脚本**: `scripts/40_bac_gtdbtk.sh`

## 功能
基于基因组树数据库（GTDB，Genome Taxonomy Database）对 MAGs 进行系统发育分类，提供统一的细菌/古菌分类框架。使用多个单拷贝标记基因的串联比对建树，支持 de novo 放置（GTDB R214 参考树）。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 MAGs | `result/binning/drep/dereplicated_genomes/*.fa` |
| 细菌分类汇总 | `result/binning/gtdbtk/classify/gtdbtk.bac120.summary.tsv` |
| 古菌分类汇总 | `result/binning/gtdbtk/classify/gtdbtk.ar53.summary.tsv` |
| MSA 比对 | `result/binning/gtdbtk/align/gtdbtk.bac120.msa.fasta.gz` |

## 数据库（`db/gtdbtk/`）
需要 GTDB R214（r214_v2）或 R226（最新），约 85G。

```bash
# 设置数据库路径（激活环境后）
export GTDBTK_DATA_PATH=${PROJ_DIR}/db/gtdbtk
```

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `classify_wf` | - | 全流程（ani_screen + align + classify） |
| `--genome_dir` | derep genomes 路径 | 输入目录 |
| `--out_dir` | `result/binning/gtdbtk` | 输出目录 |
| `--extension` | `fa` | 输入文件后缀 |
| `--cpus` | CPUS | 线程数 |
| `--mash_db` | `db/gtdbtk/mash/` | MASH 草图数据库（加速） |

## 示例命令

```bash
# 聚合分类（等待 drep 完成）
bash scripts/40_bac_gtdbtk.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 查看细菌分类结果（关键列：user_genome, classification, fastani_reference）
cut -f1,2,18 result/binning/gtdbtk/classify/gtdbtk.bac120.summary.tsv | head -5
```

## 输出格式（summary.tsv 关键列）

```
user_genome    classification    fastani_reference    note
bin.001        d__Bacteria;p__Firmicutes;c__Bacilli;o__Lactobacillales;...    GCF_000001405    topological placement with 100.0% support
```

## GTDB 与 NCBI 分类对比
GTDB 基于基因组树重新命名，部分属级分类与 NCBI/SILVA 不一致（如 Lachnospiraceae 和 Peptostreptococcaceae 大量重组）。发表时建议同时报告 GTDB 和 NCBI 名称。

## 注意事项
- GTDB-Tk 约需 320G 内存（使用 `--reduced_tree` 降至 ~100G）
- 若 MAG 序列质量差（< 50% completeness），分类结果不可靠
- `classify_wf` 先用 MASH ANI 快筛再精确比对，约 1-2h（取决于 MAG 数量）

## 官方链接
- GitHub: https://github.com/Ecogenomics/GTDBTk
- GTDB 数据库: https://gtdb.ecogenomic.org
- 论文: Parks et al. 2022, Nature Biotechnology 40:786-794
