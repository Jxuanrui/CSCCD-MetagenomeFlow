# FunOMIC — 真菌分类与功能分析

**环境**: `envs/funomic`（已创建，但当前无 `funomic` 命令） / `envs/assembly`（DIAMOND 回退执行环境） | **脚本**: `scripts/75_fun_funomics.sh`

## 功能
FunOMIC 使用真菌 marker 与功能蛋白数据库进行真菌 WGS 分类和功能分析。当前项目已部署两套本地数据库，脚本 75 优先尝试 `funomic classify`，若未检测到命令则自动回退到 `diamond blastx`。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 R1 | `result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz` |
| 输入 R2 | `result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz` |
| 分类结果 | `result/fungi/funomic/{sample}/{sample}_classification.tsv` |
| 输出目录 | `result/fungi/funomic/{sample}/` |

## 数据库部署状态

| 数据库 | 路径 | 内容 | 当前用途 |
|------|------|------|---------|
| FunOMIC-P | `db/funomic/P/` | `FunOMIC.P.v1.dmnd` + 注释表 | `75_fun_funomics.sh` 的 DIAMOND 回退数据库 |
| FunOMIC-T | `db/funomic/T/` | `FunOMIC.T.v1.*.bt2l` + `FunOMIC.T.v1.fasta` | FunOMIC 原生分类流程使用的 Bowtie2 taxonomy index |

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
FunOMIC (conda envs/funomic) → FunOMIC (系统 PATH) → DIAMOND blastx + db/funomic/P/FunOMIC.P.v1.dmnd
```

| 模式 | 触发条件 | 速度 | 精度 |
|------|---------|------|------|
| FunOMIC classify | `envs/funomic/` 中存在 `funomic` 命令 | 快 | 高 |
| DIAMOND blastx | 当前实际路径（GitHub 安装失败） | 中 | 中（取决于 `.dmnd` 库质量） |

## 与其他真菌分类工具对比

| 工具 | 方法 | 数据库 | 推荐场景 |
|------|------|--------|---------|
| **FunOMIC** | 标记基因 + 功能蛋白 | 160万 marker + 340万蛋白 | **推荐**，如果已安装 |
| CCMetagen | KMA + NCBI nt 全库 | NCBI nt | 无近缘参考也可检测 |
| MetaPhlAn4 真核 | 标记基因 | 约 1 万真核基因组 | 与细菌分析保持一致 |

## 注意事项
- `envs/funomic/` 已创建，但 `pip install git+https://github.com/zhanglab/FunOMIC.git` 返回 `Repository not found`
- 因此当前运行路径是 DIAMOND 回退模式，需要 `db/funomic/P/FunOMIC.P.v1.dmnd`
- `db/funomic/T/` 中的 `.bt2l` 索引已部署，后续若拿到可安装的 FunOMIC 包可直接复用
- FunOMIC 输出为 `classification.tsv`，包含 feature / classification / abundance 三列
- 建议与 CCMetagen（76）和 MicroFisher（77）结果取共识

## 官方链接
- 安装尝试：`https://github.com/zhanglab/FunOMIC.git`（2026-06-11 实测返回 `Repository not found`）
- 论文: Ren et al. 2023, Genome Biology (FunOMIC)
