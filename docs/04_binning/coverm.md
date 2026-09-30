# CoverM — 覆盖深度与 MAG 丰度定量

**版本**: 0.7.0 | **环境**: `envs/coverm` | **脚本**: `scripts/32_bac_coverm_depth.sh` / `39_bac_coverm_quant.sh` / `63_vir_coverm_quant.sh`

## 功能
CoverM 对基因组序列（contigs 或 MAGs）计算跨样本覆盖深度，兼顾速度和内存效率。有两种使用场景：（1）Binning 前置步骤，计算每个 contig 的深度；（2）dRep 去冗余后，对代表性 MAGs 进行样本间丰度定量。

## 两种运行模式

### 模式 A：Contig 深度计算（脚本 32，Binning 前置）

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/assembly/megahit/{sample}/{sample}.contigs.fa` |
| 输入读段 | `result/kneaddata/{sample}/` |
| 输出 BAM | `result/binning/coverm/{sample}/{sample}.bam` |
| 输出深度表 | `result/binning/coverm/{sample}/depth.txt` |

```bash
bash scripts/32_bac_coverm_depth.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

### 模式 B：MAG 丰度定量（脚本 39/63，聚合后）

| 项目 | 路径 |
|------|------|
| 输入 MAGs | `result/binning/drep/dereplicated_genomes/*.fa` |
| 输入读段 | `result/kneaddata/{sample}/` |
| 输出丰度表 | `result/binning/coverm_quant/{sample}.tsv` |

```bash
bash scripts/39_bac_coverm_quant.sh -s SAMPLE01 -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 关键参数

| 参数 | 模式 | 含义 |
|------|------|------|
| `contig` / `genome` | 子命令 | 按 contig 或全基因组计算覆盖 |
| `-r` | 参考序列 | contig/MAG FASTA |
| `-1` / `-2` | 读段 | 输入读段 |
| `-m` | `mean` / `rpkm` | 覆盖度计算方法 |
| `-t` | CPUS | 线程数 |
| `--min-covered-fraction` | 0.1 | 最低覆盖比例（< 阈值则报 0） |
| `--bam-file-cache-directory` | BAM 目录 | 保存 BAM 供复用 |

## 覆盖度指标选择

| 指标 | 用途 |
|------|------|
| `mean` | 原始平均覆盖深度（用于 MetaBAT2 深度文件） |
| `rpkm` | RPKM 标准化（基因长度+测序量归一化） |
| `tpm` | TPM 标准化（样本间可比较，推荐用于 MAG 丰度） |
| `covered_fraction` | 基因组覆盖比例（检测 MAG 是否真实存在于样本） |

## 注意事项
- 模式 A 生成 BAM 文件，MetaBAT2 的 `jgi_summarize_bam_contig_depths` 需要此 BAM
- 模式 B 中建议同时输出 `rpkm` 和 `covered_fraction`，便于过滤低丰度/低覆盖 MAGs
- CoverM 内置 minimap2 或 BWA-MEM 比对；宏基因组推荐使用 `minimap2-sr`（短读段模式）

## 官方链接
- GitHub: https://github.com/wwood/CoverM
- 文档: https://github.com/wwood/CoverM#usage
