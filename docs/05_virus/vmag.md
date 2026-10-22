# vMAG — 病毒 MAG 生成（vRhyme）

**版本**: vRhyme 1.1+ | **环境**: `envs/vrhyme` | **脚本**: `scripts/61_vir_vmag.sh`

## 功能
使用 vRhyme 基于多样本覆盖度和蛋白特征信息对病毒 contigs 进行分箱（binning），生成病毒 MAG（vMAGs）。vRhyme 利用跨样本的丰度变异实现比单一覆盖深度更准确的分箱。

## 用法

```bash
bash scripts/61_vir_vmag.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 vOTU 序列 | `result/virus/votu/contigs/virus.fasta` |
| 输入 BAM | `result/virus/votu/bam/{sample}.bam`（自动生成） |
| vMAG 输出 | `result/virus/vmag/bins/vMAG/*.fasta` |
| 伪 vMAG 输出 | `result/virus/vmag/bins/pseudo/*.fasta` |

## 工作流程

1. **BAM 生成**：若无现成 BAM，使用 CoverM 对 vOTU 序列产生跨样本 BAMs
2. **vRhyme 分箱**：基于序列组成 + 覆盖度变异进行聚类
3. **vMAG 提取**：从 vRhyme 输出提取高质量 vMAGs

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | vOTU FASTA | 输入序列 |
| `-b` | BAM 目录 | 跨样本 BAM 文件 |
| `-l` | 10000 | 最小序列长度 |
| `--iter` | 15 | 聚类迭代次数 |

## 下游分析

vMAGs → **62 CheckV**（质量评估）→ **64 PHAROKKA**（功能注释）

## 注意事项
- 这是 aggregate 步骤（无 `-s` 参数）
- BAM 自动生成使用 minimap2（`coverm make -p minimap2-sr`）
- vRhyme 分箱失败时脚本不会退出，会生成空的哨兵文件

## 官方链接
- vRhyme: https://github.com/AnantharamanLab/vRhyme
- 论文: Kieft et al. 2022, Nucleic Acids Research
