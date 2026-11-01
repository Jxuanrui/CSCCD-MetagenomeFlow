# fastp — 读段质量控制

**版本**: 0.22.0 | **环境**: `envs/fastp` | **脚本**: `scripts/01_qc_fastp.sh`

## 功能
对原始 paired-end FASTQ 进行质量控制：接头自动识别和去除、低质量碱基修剪、polyX 去除、质量过滤，输出 JSON+HTML 报告。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 原始 R1 | `data/{sample}_1.fastq.gz`（或 `.R1.fastq.gz`） |
| 原始 R2 | `data/{sample}_2.fastq.gz` |
| 输出 R1 | `result/fastp/{sample}/{sample}_1.fastp.fastq.gz` |
| 输出 R2 | `result/fastp/{sample}/{sample}_2.fastp.fastq.gz` |
| JSON 报告 | `result/fastp/{sample}/{sample}.json` |
| HTML 报告 | `result/fastp/{sample}/{sample}.html` |

## 关键参数（脚本默认值）

| 参数 | 默认 | 含义 |
|------|------|------|
| `--cut_front` | on | 从 5' 端滑窗修剪低质量碱基 |
| `--cut_tail` | on | 从 3' 端滑窗修剪 |
| `--cut_mean_quality` | 20 | 滑窗均质阈值 |
| `--qualified_quality_phred` | 15 | 每碱基最低质量 |
| `--unqualified_percent_limit` | 40 | 低质量碱基比例上限 |
| `--length_required` | 50 | 过滤后最短读长 |
| `--thread` | CPUS | 线程数 |

## 示例命令

```bash
# 独立运行
bash scripts/01_qc_fastp.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 查看报告
firefox result/fastp/SAMPLE01/SAMPLE01.html
```

## 下游依赖
输出 fastq.gz 由 `02_qc_kneaddata.sh` 消费。

## 官方链接
- GitHub: https://github.com/OpenGene/fastp
- 论文: Chen et al. 2018, Bioinformatics 34(17):i884-i890
