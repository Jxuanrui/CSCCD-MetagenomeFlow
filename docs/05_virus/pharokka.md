# PHAROKKA — 病毒基因组端到端注释

**版本**: 1.7+ | **环境**: `envs/pharokka` | **脚本**: `scripts/64_vir_pharokka.sh`

## 功能
PHAROKKA 对病毒基因组进行端到端快速注释，涵盖 CDS 预测、功能注释（PHROG / VFDB / ARG / 等）、tRNA 识别和序列特征标注。内置 Prodigal-gv（病毒遗传密码子）进行基因预测，PHROG HMM profiles 进行功能分类，输出标准 GFF3 / GenBank / TSV 格式。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 vOTU 序列 | `result/virus/votu/contigs/virus.fasta` |
| GFF 注释 | `result/virus/pharokka/pharokka.gff` |
| 预测蛋白 | `result/virus/pharokka/prodigal-gv.faa` |
| CDS 汇总 | `result/virus/pharokka/pharokka_cds_final_merged_output.tsv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | 序列 FASTA | 输入病毒基因序列 |
| `-o` | 输出目录 | 结果路径 |
| `-d` | `db/pharokka` | 数据库路径 |
| `-t` | CPUS | 线程数 |
| `-f` | on | 覆盖已有输出 |
| `--skip_extra_annotations` | on | 跳过额外注释（加快速度） |
| `--skip_mash` | on | 跳过 MASH 比对（加快速度） |

## PHROG 功能分类

PHAROKKA 使用 PHROG（Prokaryotic Virus Remote Homologous Groups）数据库进行功能分类，主要类别：

| 类别 | 代码 | 说明 |
|------|------|------|
| 噬菌体形态发生 | m | 头部/尾部/衣壳蛋白 |
| DNA 复制/修复 | d | 聚合酶/解旋酶/连接酶 |
| 裂解 | l | 内溶素/穿孔素 |
| 包装 | p | 末端酶/门户蛋白 |
| 核苷酸代谢 | n | 胸苷酸合成酶/核糖核苷酸还原酶 |
| 整合 | i | 整合酶/重组酶 |
| 转录调控 | t | RNA 聚合酶/转录因子 |
| 未知功能 | u | 功能未分配（ORFans） |

## 注释覆盖范围

| 注释类型 | 数据库 | 说明 |
|---------|--------|------|
| 蛋白功能 | PHROG HMM | 主要功能分类 |
| 抗生素抗性 | NCBI AMR | 辅助（需取消 `--skip_extra_annotations`） |
| 毒力因子 | VFDB | 病毒毒力相关 |
| tRNA | tRNAscan-SE | 病毒 tRNA 基因 |

## 与 PHOLD 的关系

脚本 `65_vir_phold.sh` 可对 PHAROKKA 结果补充注释，尤其是结构蛋白和 PDB 可比较的暗物质 ORF（缺乏已知同源性的 ORF）。两者互补：

| 工具 | 优势 |
|------|------|
| PHAROKKA | 端到端注释，PHROG 分类，功能覆盖全 |
| PHOLD | 结构蛋白和膜蛋白预测，降低未知功能比例 |

建议先运行 PHAROKKA，再运行 PHOLD 补充。

## 注意事项
- PHAROKKA 数据库约 3 GB（含 PHROG/VFDB/AMR HMMs），位于 `db/pharokka/`
- `--skip_extra_annotations` 默认开启以加速运行；如需 ARG 等额外注释，可编辑脚本关闭该标志
- Prodigal-gv 使用病毒遗传密码子表（table 4 / 11），而非细菌的标准密码子表
- PHAROKKA 输入建议使用 vOTU 代表序列（去冗余后），而非单样本病毒 contigs

## 官方链接
- GitHub: https://github.com/gbouras13/pharokka
- 论文: Terzian et al. 2023, Microbial Genomics 9:000936
- PHROG: https://phrogs.lmge.uca.fr
- Prodigal-gv: https://github.com/apcamargo/prodigal-gv
