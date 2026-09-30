# Eukfinder — 真核生物 MAG 回收

**环境**: `envs/assembly` | **脚本**: `scripts/79_fun_eukfinder.sh`

## 功能
Eukfinder 从宏基因组组装 contigs 中识别真核生物序列，通过多阶段过滤策略（k-mer 组成 + HMM profiles + 序列特征）将真核 contigs 从原核背景中分离，用于后续真核 MAG（eMAG）回收。本脚本封装了 Eukfinder_long 命令，在未安装时输出占位说明。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/fungi/assembly/{sample}/{sample}.contigs.fa` |
| 输出目录 | `result/fungi/eukfinder/{sample}/` |
| 结果说明 | `result/fungi/eukfinder/{sample}/results.txt` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | contigs FASTA | 输入组装序列 |
| `-o` | 样本目录 | 输出路径 |
| `-t` | CPUS | 线程数 |

## 分析流程

```
真菌组装 contigs → Eukfinder_long 真核识别 → 真核 contigs 分类
                                            → 真核 MAG 回收 → 后续蛋白预测 + 注释
```

## 与其他 MAG 工具对比

| 工具 | 真核能力 | 训练数据 | 推荐场景 |
|------|---------|---------|---------|
| **Eukfinder** | **是（专用）** | 真核 HMM + k-mer | 真菌/真核 MAG 回收（本流程首选） |
| MetaBAT2 | 否（原核训练） | 细菌基因组 | 不适用于真核 |
| SemiBin2 | 否 | 细菌基因组 | 不适用于真核 |
| CONCOCT | 否 | 细菌基因组 | 不适用于真核 |

## 安装（如未安装）

```bash
# pip 安装
pip install eukfinder

# 或从 GitHub 安装最新版
pip install git+https://github.com/RogerLab/Eukfinder.git
```

脚本在 Eukfinder 未安装时不会报错；它会输出占位说明文件 `results.txt`（内含安装指南），不阻断 Snakemake 流程。

## 下游分析

Eukfinder 识别的真核 contigs 可输入：
- **80_fun_prodigal.sh**：蛋白编码基因预测（真核密码子表）
- **81_fun_eggnog.sh**：真核功能注释
- **82_fun_kegg.sh**：KEGG 通路注释

## 注意事项
- Eukfinder 要求输入为组装后的 contigs（≥1.5kb），来自 78_fun_megahit.sh 的输出
- 运行时间取决于 contigs 数量；10 万+ contigs 可能需要数小时
- Eukfinder 输出结果通常包括真核/原核分类文件，格式随版本变化；脚本自动解析

## 官方链接
- GitHub: https://github.com/RogerLab/Eukfinder
- 论文: Santana-Pérez & Pérez-Cobas 2025, Nature Communications（Eukfinder）
