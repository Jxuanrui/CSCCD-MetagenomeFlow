# Prodigal — 原核生物基因预测

**版本**: V2.6.3 | **环境**: `envs/assembly` | **脚本**: `scripts/17_bac_prodigal.sh` / `55_vir_prodigal_gv.sh` / `80_fun_prodigal.sh`

## 功能
Prodigal（PROkaryotic DYnamic programming Gene-finding Algorithm）使用动态规划和隐马尔可夫模型预测原核生物蛋白编码基因，支持宏基因组（metagenomic）模式，无需预先训练模型。病毒维度使用 Prodigal-gv（专为病毒遗传密码设计的分支版本）。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/assembly/megahit/{sample}/{sample}.contigs.fa` |
| 蛋白序列 | `result/assembly/prodigal/{sample}/{sample}.faa` |
| 核酸序列 | `result/assembly/prodigal/{sample}/{sample}.fna` |
| GFF 注释 | `result/assembly/prodigal/{sample}/{sample}.gff` |

真菌维度（80）使用 `-g 1`（标准真核密码子表）。

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-p` | `meta` | 运行模式（meta=宏基因组，single=单基因组） |
| `-f` | `gff` | 输出格式（gff/gbk/sco） |
| `-a` | `.faa` 路径 | 蛋白序列输出文件 |
| `-d` | `.fna` 路径 | 核酸序列输出文件 |
| `-g` | `11` | 遗传密码子表（11=细菌/古菌，1=真核，病毒见下） |
| `-m` | — | 跳过短 ORF 掩码（提高 contigs 断点基因召回） |

病毒维度：使用 `prodigal-gv`（`envs/assembly` 内的 `prodigal-gv` 二进制），自动处理病毒特殊密码子。

## 示例命令

```bash
# 细菌宏基因组模式
bash scripts/17_bac_prodigal.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 手动运行（元基因组模式）
conda run --prefix envs/assembly prodigal \
    -i result/assembly/megahit/SAMPLE01/SAMPLE01.contigs.fa \
    -p meta \
    -a result/assembly/prodigal/SAMPLE01/SAMPLE01.faa \
    -d result/assembly/prodigal/SAMPLE01/SAMPLE01.fna \
    -f gff \
    -o result/assembly/prodigal/SAMPLE01/SAMPLE01.gff

# 统计预测基因数
grep -c "^>" result/assembly/prodigal/SAMPLE01/SAMPLE01.faa
```

## 输出 GFF 格式
```
# Sequence Data: seqnum=1;seqlen=5238;seqhdr="k141_0..."
# Model Data: version=Metagenomic;gc_cont=0.509;...
k141_0  Prodigal_v2.6.3  CDS  168  1415  50.9  +  0  ID=1_1;...
```

## meta 模式 vs single 模式

| 模式 | 场景 | 优点 |
|------|------|------|
| `meta` | 宏基因组（必须） | 跨物种训练模型，无需先验 |
| `single` | 单一高覆盖基因组 | 在当前序列上训练，精度更高 |

宏基因组 **必须** 使用 `-p meta`；`single` 模式需要足够长的单一序列才能训练模型。

## 注意事项
- 宏基因组组装 contig 通常较短，部分 ORF 会被截断（truncated gene）
- 输出 `.faa` 中，基因 ID 格式为 `contig_ID_ORF编号`，保留上下文关联
- Prodigal-gv 位于 `envs/assembly/bin/prodigal-gv`，适用于病毒 contig

## 官方链接
- GitHub: https://github.com/hyattpd/Prodigal
- 论文: Hyatt et al. 2010, BMC Bioinformatics 11:119
- Prodigal-gv: https://github.com/apcamargo/prodigal-gv
