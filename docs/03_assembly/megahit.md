# MEGAHIT — 宏基因组组装

**版本**: v1.2.9 | **环境**: `envs/assembly` | **脚本**: `scripts/16_bac_megahit.sh` / `51_vir_megahit.sh` / `78_fun_megahit.sh`

## 功能
MEGAHIT 使用多 k-mer 策略（successive k-mer sizes）和内存高效的稀疏图（SDBG）对宏基因组 shotgun 数据进行组装，兼顾速度和内存效率，是目前宏基因组 de novo 组装的主流选择。

## 输入 / 输出

| 项目 | 路径（细菌维度） |
|------|----------------|
| 输入 R1/R2 | `result/kneaddata/{sample}/` |
| 组装 contigs | `result/assembly/megahit/{sample}/{sample}.contigs.fa` |
| 日志 | `result/assembly/megahit/{sample}/log` |

病毒维度输出至 `result/virus/assembly/{sample}/`，真菌维度至 `result/fungi/assembly/{sample}/`。

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-1` / `-2` | R1/R2 路径 | 成对读段输入 |
| `--k-list` | `21,29,39,59,79,99,119,141` | 多 k-mer 阶梯（含 k=141 可提升连续性） |
| `--min-contig-len` | 500（病毒 1500）| 最短输出 contig 长度 |
| `--num-cpu-threads` | CPUS | 线程数 |
| `--memory` | 0.85 | 最大内存占比（相对系统总内存） |
| `--out-dir` | 输出目录 | 结果目录 |

病毒维度额外参数：`--presets meta-sensitive`，适合低丰度病毒序列。

## 示例命令

```bash
# 细菌维度组装
bash scripts/16_bac_megahit.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 查看组装统计
awk '/^>/{next} {len=length($0); total+=len; n++; if(len>500)n500++}
     END{print "contigs:", n, "| total bp:", total, "| N>=500:", n500}' \
    result/assembly/megahit/SAMPLE01/SAMPLE01.contigs.fa

# assembly-stats (若已安装)
assembly-stats result/assembly/megahit/SAMPLE01/SAMPLE01.contigs.fa
```

## 质量评估指标

| 指标 | 参考范围（肠道宏基因组） |
|------|----------------------|
| 总 contig 数 | 50,000–500,000 |
| N50 | 1,000–10,000 bp |
| 最长 contig | 50,000–500,000 bp |
| 总长度 | 100 Mb–2 Gb |

## 注意事项
- 宏基因组复杂度高，组装 N50 远低于单菌基因组；N50 > 1 kb 即为良好结果
- `--presets meta-sensitive` 增加低丰度序列召回，代价是组装时间增加约 2×
- 若样本测序深度 < 5G bases，建议先用 `--k-list 21,41,61,81,99` 降低 k-mer 范围
- 输出 contigs 直接用于后续基因预测（Prodigal）和 Binning

## 官方链接
- GitHub: https://github.com/voutcn/megahit
- 论文: Li et al. 2015, Bioinformatics 31(10):1674-1676
