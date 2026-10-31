# Salmon — 基因丰度定量

**版本**: 1.2.0 | **环境**: `envs/assembly` | **脚本**: `scripts/19_bac_salmon_build.sh` / `20_bac_salmon_quant.sh` / `58_vir_salmon_build.sh` / `59_vir_salmon_quant.sh`

## 功能
Salmon 使用准比对（quasi-mapping）或完整比对（alignment-based）方法对 RNA-seq / 宏基因组读段进行快速基因丰度定量，输出 TPM（每百万转录本数）和 NumReads 等丰度指标。宏基因组中用于基因目录（gene catalog）或 vOTU 的样本间丰度定量。

## 工作流程（两步）

### 步骤 1：建索引（19/58 脚本）

| 项目 | 路径 |
|------|------|
| 输入基因序列 | `result/assembly/cdhit/gene_catalog.fa`（去冗余后） |
| 输出索引 | `result/assembly/salmon_index/` |

```bash
bash scripts/19_bac_salmon_build.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

### 步骤 2：定量（20/59 脚本，per-sample）

| 项目 | 路径 |
|------|------|
| 输入 R1/R2 | `result/kneaddata/{sample}/` |
| 输出 TPM | `result/assembly/salmon_quant/{sample}/quant.sf` |

```bash
bash scripts/20_bac_salmon_quant.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 关键参数

### 建索引（`salmon index`）

| 参数 | 默认 | 含义 |
|------|------|------|
| `-t` | 基因序列 FASTA | 目标序列 |
| `-i` | 索引输出目录 | 索引路径 |
| `--threads` | CPUS | 线程数 |
| `-k` | 31 | k-mer 大小（短读长可降至 25） |

### 定量（`salmon quant`）

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | 索引目录 | 使用已建索引 |
| `-l` | `A` | 文库方向（A=自动检测） |
| `-1` / `-2` | R1/R2 | 成对读段 |
| `--validateMappings` | on | 严格验证比对（提高精度） |
| `--gcBias` | on | GC 偏差校正 |
| `--seqBias` | on | 序列偏差校正 |
| `-p` | CPUS | 线程数 |

## 输出格式（quant.sf）
```
Name               Length  EffectiveLength  TPM          NumReads
gene_1             850     801.234          12.345       156.000
gene_2             1200    1150.678         0.001        0.010
```

## TPM vs RPKM/FPKM

| 指标 | 特点 |
|------|------|
| TPM | 样本间可直接比较；每个样本 TPM 总和 = 1,000,000 |
| RPKM/FPKM | 样本间不可直接比较（总测序量不同） |

宏基因组分析**推荐使用 TPM**；差异分析工具（DESeq2/edgeR）使用 NumReads（原始计数）。

## 注意事项
- 索引只需构建一次，所有样本共用（aggregate 步骤）
- 宏基因组基因通常为 DNA 序列，Salmon 同样支持（`-l U` 非链特异）
- vOTU 定量流程（58/59）与基因定量完全相同，仅替换目标序列为 vOTU 代表序列

## 官方链接
- GitHub: https://github.com/COMBINE-lab/salmon
- 文档: https://salmon.readthedocs.io
- 论文: Patro et al. 2017, Nature Methods 14:417-419
