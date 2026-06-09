# FunOMIC — 真菌分类与功能分析

**环境**: `envs/assembly`（首选 `envs/funomic` 若存在） | **脚本**: `scripts/75_fun_funomics.sh`

## 功能
FunOMIC 使用 160 万真菌标记基因和 340 万功能蛋白数据库进行真菌 WGS 物种分类和功能通路定量。脚本 75 封装了 FunOMIC 的 classify 子命令，当 FunOMIC 未安装时自动回退到 DIAMOND blastx marker 分类。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 R1 | `result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz` |
| 输入 R2 | `result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz` |
| 分类结果 | `result/fungi/funomic/{sample}/{sample}_classification.tsv` |
| 输出目录 | `result/fungi/funomic/{sample}/` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--forward` | INPUT_R1 | R1 输入 |
| `--reverse` | INPUT_R2 | R2 输入 |
| `--threads` | CPUS | 线程数 |
| `--output` | 样本目录 | 输出目录 |

## 自动回退机制

脚本检测 FunOMIC 是否安装，按优先级选择：

```
FunOMIC (conda envs/funomic) → FunOMIC (系统 PATH) → DIAMOND blastx + 真菌数据库
```

| 模式 | 触发条件 | 速度 | 精度 |
|------|---------|------|------|
| FunOMIC classify | `envs/funomic/` 存在 | 快 | 高（160万 marker） |
| DIAMOND blastx | FunOMIC 未安装 | 中 | 中（取决于数据库质量） |

## 与其他真菌分类工具对比

| 工具 | 方法 | 数据库 | 推荐场景 |
|------|------|--------|---------|
| **FunOMIC** | 标记基因 + 功能蛋白 | 160万 marker + 340万蛋白 | **推荐**，如果已安装 |
| CCMetagen | KMA + NCBI nt 全库 | NCBI nt | 无近缘参考也可检测 |
| MetaPhlAn4 真核 | 标记基因 | 约 1 万真核基因组 | 与细菌分析保持一致 |

## 注意事项
- FunOMIC 安装较复杂，若首次安装遇到困难，脚本会自动回退到 DIAMOND 模式
- DIAMOND 回退模式需要 `db/funomic/` 目录中存在 `.dmnd` 格式的蛋白数据库
- FunOMIC 输出为 `classification.tsv`，包含 feature / classification / abundance 三列
- 建议与 CCMetagen（76）和 MicroFisher（77）结果取共识

## 官方链接
- GitHub: https://github.com/ragpanda/FunOMIC
- 论文: Ren et al. 2023, Genome Biology (FunOMIC)
