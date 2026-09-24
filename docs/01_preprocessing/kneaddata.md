# KneadData — 宿主序列去除

**版本**: v0.12.4 | **环境**: `envs/kneaddata` | **脚本**: `scripts/02_qc_kneaddata.sh`

## 功能
使用 Bowtie2 将读段比对到宿主基因组（人/小鼠/大鼠），去除比对成功的宿主序列，保留非宿主微生物读段，同时用 Trimmomatic 进行补充质控。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 R1 | `result/fastp/{sample}/{sample}_1.fastp.fastq.gz` |
| 输入 R2 | `result/fastp/{sample}/{sample}_2.fastp.fastq.gz` |
| 输出 R1 | `result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz` |
| 输出 R2 | `result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz` |
| 日志 | `result/kneaddata/{sample}/{sample}.log` |

## 数据库（`db/kneaddata/`）

| 数据库 | 用途 |
|--------|------|
| `human_hg38_index/` | 人类基因组 GRCh38 Bowtie2 索引 |
| `mouse_C57BL_6NJ/`（可选）| 小鼠基因组 |
| `rat_mRatBN7_2/`（可选）| 大鼠基因组 |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--reference-db` | `db/kneaddata/human_hg38_index` | Bowtie2 宿主索引路径 |
| `--trimmomatic` | auto | Trimmomatic jar 路径（conda 自动检测） |
| `--trimmomatic-options` | `SLIDINGWINDOW:4:20 MINLEN:50` | Trimmomatic 参数 |
| `-t` | CPUS | 线程数 |
| `--bypass-trf` | on | 跳过串联重复滤除（加速） |

## 示例命令

```bash
# 独立运行（单样本）
bash scripts/02_qc_kneaddata.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 检查去宿主效率（看 kneaddata.log 第一行）
head -5 result/kneaddata/SAMPLE01/SAMPLE01.log
```

## 注意事项
- 宿主去除率通常 1-15%（肠道样本）；若 >50% 说明样本质量差或选错宿主数据库
- 输出 R1/R2 文件名含 `kneaddata_paired` 中间态，脚本已自动重命名为标准格式
- 若无宿主数据库，脚本跳过比对直接链接 fastp 输出

## 官方链接
- GitHub: https://github.com/biobakery/kneaddata
- 文档: https://huttenhower.sph.harvard.edu/kneaddata
