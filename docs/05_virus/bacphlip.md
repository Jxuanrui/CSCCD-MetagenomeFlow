# BACPHLIP — 噬菌体生活方式预测

**版本**: 0.9+ | **环境**: `envs/bacphlip` | **脚本**: `scripts/67_vir_bacphlip.sh`

## 功能
BACPHLIP 使用随机森林分类器基于蛋白序列特征预测噬菌体的生活方式（裂解/溶原）。它是基于序列组成而非标记基因的方法，适用于未培养噬菌体的生活方式预测。

## 用法

```bash
bash scripts/67_vir_bacphlip.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 vOTU 序列 | `result/virus/votu/contigs/virus.fasta` |
| 生活方式预测 | `result/virus/bacphlip/bacphlip_results.tsv` |

## 预测输出格式

```
Sequence_ID    Virulent_probability    Temperate_probability    Prediction
vOTU_0001      0.92                    0.08                     Virulent
vOTU_0002      0.15                    0.85                     Temperate
```

## 与 geNomad 生活方式预测的对比

| 工具 | 方法 | 输入 | 覆盖范围 |
|------|------|------|---------|
| **BACPHLIP** | 随机森林（蛋白特征） | 核酸序列 | 仅噬菌体（裂解/溶原） |
| geNomad | 神经网络 + 标记基因 | 核酸序列 | 病毒+质粒（裂解/溶原/原前病毒） |

两者结果可交叉验证：同时被预测为溶原的序列可纳入温和噬菌体分析。

## 注意事项
- 使用 vOTU 代表序列而非单样本病毒 contigs
- 支持 `--multi_fasta` 模式批量预测

## 官方链接
- GitHub: https://github.com/adamhockenberry/bacphlip
- 论文: Hockenberry et al. 2021, BMC Genomics
