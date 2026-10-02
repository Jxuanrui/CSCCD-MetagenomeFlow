# vOTU — 病毒操作分类单元（vOTU）生成与分类

**工具**: vclust 1.3+ | **环境**: `envs/vclust` | **脚本**: `scripts/56_vir_votu_gen.sh` / `57_vir_votu_genomad.sh` / `58_vir_salmon_build.sh` / `59_vir_salmon_quant.sh` / `60_vir_votu_table.sh`

## 功能
vclust 通过三阶段流程（prefilter → align → cluster）对跨样本病毒 contigs 进行 95% ANI（核苷酸一致性）+ 85% qcov（查询覆盖度）聚类，生成 vOTU（病毒操作分类单元）。代表序列用于后续分类注释、丰度定量。类比于细菌分析的 97% OTU / 95% ASV 聚类，但 vOTU 采用更为严格的 ANI 阈值。

## 工作流程

```
全样本病毒 contigs → vclust prefilter → vclust align → vclust cluster → vOTU 代表序列
                                                              ↓
                                            57 分类注释（geNomad）→ 58-60 Salmon 定量
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 合并病毒 contigs | `result/virus/votu/contigs/virus.fasta` |
| prefilter 输出 | `result/virus/votu/vclust/fltr.txt` |
| ANI 矩阵 | `result/virus/votu/vclust/ani.tsv` |
| 聚类结果 | `result/virus/votu/vclust/clusters.tsv` |
| 代表序列列表 | `result/virus/votu/votu_representatives.tsv` |

## 关键参数

### vclust prefilter

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | 合并 FASTA | 输入序列 |
| `--min-ident` | 0.95 | 最低 ANI 阈值过滤 |

### vclust align

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | 合并 FASTA | 输入序列 |
| `--filter` | prefilter 结果 | 预过滤文件 |
| `-t` | CPUS | 线程数 |

### vclust cluster

| 参数 | 默认 | 含义 |
|------|------|------|
| `--algorithm` | `leiden` | 聚类算法（Leiden 社区检测） |
| `--metric` | `ani` | 聚类指标 |
| `--ani` | 0.95 | 聚类 ANI 阈值 |
| `--qcov` | 0.85 | 最低查询覆盖度 |
| `--out-repr` | on | 输出代表序列 |

## 聚类参数选择

| 场景 | ANI | qcov | 说明 |
|------|-----|------|------|
| 标准 vOTU（推荐） | 0.95 | 0.85 | 本流程默认 |
| 宽松（species 级） | 0.95 | 0.70 | 增加聚类规模 |
| 严格（strain 级） | 0.99 | 0.85 | 更多 vOTU，更大计算量 |
| vConTACT3 兼容 | 依赖基因共享 | — | 不通过 vclust，使用 69 脚本 |

## 下游分析

- **58 Salmon build**: 构建 vOTU 代表序列的 Salmon 索引
- **59 Salmon quant**: 每个样本定量 vOTU 丰度
- **60 vOTU table**: 合并所有样本的 Salmon 定量，生成 vOTU 丰度矩阵
- **57 geNomad**: vOTU 代表序列的分类学注释

## 注意事项
- 脚本 56 是 aggreagate 步骤（无 `-s` 参数），需要所有样本的 CheckV 输出就位
- 若样本数少（<3），vclust 可能产生的 vOTU 数量接近输入序列数，聚类意义有限
- vclust 使用的 Leiden 算法比传统 Markov clustering（MCL）速度更快，对大样本更友好
- Salmon 索引在 vOTU 序列确定后构建一次，所有样本共用

## 官方链接
- vclust: https://github.com/audy/vclust
- Salmon: https://github.com/COMBINE-lab/salmon
- vOTU 标准: Roux et al. 2019, Nature Biotechnology 37:632–639
