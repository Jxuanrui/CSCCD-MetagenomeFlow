# MetaPhlAn 4 — 物种组成分析

**版本**: 4.2.4 | **环境**: `envs/humann4` | **脚本**: `scripts/11_bac_metaphlan4.sh`

## 功能
基于物种特异性标记基因（clade-specific markers）对宏基因组读段进行精确分类，输出物种相对丰度 profile（菌株级分辨率）。MetaPhlAn 4 使用 ChocoPhlAn 数据库，包含真核生物、原核生物、病毒标记。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 R1 | `result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz` |
| 输入 R2 | `result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz` |
| 分类 Profile | `result/metaphlan4/{sample}/{sample}_profile.txt` |
| BowtieDB 比对 | `result/metaphlan4/{sample}/{sample}.bowtie2.bz2` |
| 合并矩阵 | `result/metaphlan4/merged/taxonomy.tsv`（聚合步骤） |

## 数据库
路径：`db/metaphlan/`（ChocoPhlAn v3.1 / mpa_vOct22_CHOCOPhlAnSGB_202212）

```bash
# 确认数据库版本
metaphlan --version
ls db/metaphlan/
```

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--input_type` | `fastq` | 输入格式 |
| `--bowtie2db` | `db/metaphlan` | 数据库路径 |
| `--nproc` | CPUS | 线程数 |
| `--read_min_len` | 70 | 最短读长过滤 |
| `--stat_q` | 0.2 | 定量统计阈值 |
| `-t` | `rel_ab_w_read_stats` | 输出类型（相对丰度+读数统计） |

## 示例命令

```bash
# 单样本分类
bash scripts/11_bac_metaphlan4.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 手动合并多样本（脚本自动执行）
merge_metaphlan_tables.py result/metaphlan4/*/\*_profile.txt > result/metaphlan4/merged/taxonomy.tsv

# 提取门级丰度
grep -E "^#|p__" result/metaphlan4/merged/taxonomy.tsv | grep -v "|" > phylum_abundance.tsv
```

## Profile 格式
```
# MetaPhlAn version 4.2.4
# Database: mpa_vOct22_CHOCOPhlAnSGB_202212
#clade_name      NCBI_tax_id      relative_abundance      coverage      ...
k__Bacteria|p__Firmicutes|c__Bacilli|...     12345    45.32   0.87
```

## 注意事项
- `envs/humann4` 同时包含 MetaPhlAn 4 和 HUMAnN 3，共享同一环境
- bowtie2.bz2 比对文件可被 HUMAnN 直接复用，避免重复比对
- 真菌分类见 `72_fun_metaphlan4_euk.sh`（不过滤真核生物）

## 官方链接
- GitHub: https://github.com/biobakery/MetaPhlAn
- 文档: https://github.com/biobakery/MetaPhlAn/wiki
- 论文: Blanco-Míguez et al. 2023, Nature Methods
