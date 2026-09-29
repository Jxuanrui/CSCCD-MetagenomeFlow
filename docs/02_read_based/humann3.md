# HUMAnN 3 — 功能通路定量

**版本**: v3.9 | **环境**: `envs/humann4` | **脚本**: `scripts/13_bac_humann3.sh`

## 功能
将宏基因组读段映射到 UniRef 功能数据库，输出通路丰度（PathwayAbundance）、通路覆盖度（PathwayCoverage）和基因家族丰度（GeneFamilies），支持按物种分层（stratified）。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 R1 | `result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz` |
| MetaPhlAn profile | `result/metaphlan4/{sample}/{sample}_profile.txt`（复用） |
| 通路丰度 | `result/humann3/{sample}/{sample}_pathabundance.tsv` |
| 通路丰度（relab）| `result/humann3/{sample}/{sample}_pathabundance_relab.tsv` |
| 通路覆盖度 | `result/humann3/{sample}/{sample}_pathcoverage.tsv` |
| 基因家族 | `result/humann3/{sample}/{sample}_genefamilies.tsv` |

## 数据库（`db/humann3/`）

| 数据库 | 大小 | 用途 |
|--------|------|------|
| `uniref90_diamond/` | ~60G | UniRef90 全蛋白 Diamond 索引 |
| `chocophlan/` | ~15G | 泛基因组核酸数据库（精确比对） |
| `utility_mapping/` | ~2G | EC/GO/MetaCyc 通路映射 |

## 速度模式（`--speed-mode`）

| 模式 | 耗时（16 线程）| 精度 | 适用场景 |
|------|-------------|------|---------|
| `standard` | 2-6h | 最高 | 发表级分析 |
| `balanced` | 1-3h | 高 | 常规研究 |
| `fast` | 0.5-1h | 中 | 初步探索 |

详见 `docs/02_read_based/humann3_speed_optimization.md`。

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--threads` | CPUS | 线程数 |
| `--nucleotide-database` | `db/humann3/chocophlan` | 核酸数据库 |
| `--protein-database` | `db/humann3/uniref90_diamond` | 蛋白数据库 |
| `--taxonomic-profile` | MetaPhlAn profile 路径 | 复用分类结果加速 |
| `--output-format` | `tsv` | 输出格式 |

## 示例命令

```bash
# 标准模式
bash scripts/13_bac_humann3.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 快速模式
bash scripts/13_bac_humann3.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow --speed-mode fast

# 合并多样本通路矩阵（脚本聚合步骤）
humann_join_tables -i result/humann3/ -o result/humann3/merged_pathabundance.tsv --file_name pathabundance
humann_renorm_table -i result/humann3/merged_pathabundance.tsv -o merged_pathabundance_relab.tsv --units relab
```

## 输出格式
```tsv
# Pathway                              SAMPLE01_Abundance-RPKs
UNMAPPED                               12345.67
UNINTEGRATED                           8901.23
PWY-5695: urea cycle                   234.56|g__Bacteroides.s__uniformis: 123.45
```

## 注意事项
- 复用 MetaPhlAn profile（`--taxonomic-profile`）可跳过分类步骤，减少 30-50% 运行时间
- 真菌通路提取见 `73_fun_humann4_fungi.sh`（从 stratified 矩阵中过滤真菌）
- 输出 `_pathabundance_relab.tsv`（相对丰度版本）由 Snakemake 显式追踪

## 官方链接
- GitHub: https://github.com/biobakery/humann
- 文档: https://huttenhower.sph.harvard.edu/humann
- 论文: Beghini et al. 2021, eLife 10:e65088
