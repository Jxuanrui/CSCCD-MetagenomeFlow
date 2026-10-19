# MLST — 多位点序列分型

**版本**: 2.11 | **环境**: `envs/prokaWGS` | **脚本**: `scripts/41b_bac_mlst.sh`

## 功能
多位点序列分型（Multi-Locus Sequence Typing，MLST）通过比较多个管家基因的等位基因谱来确定细菌菌株型别（ST, Sequence Type），广泛用于流行病学溯源和克隆谱系分析。本脚本对 dRep 产出的 MAGs 批量执行 MLST 分型。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 MAGs | `result/binning/drep/dereplicated_genomes/*.fa` |
| MLST 结果 | `result/wgs/mlst/mlst.tsv` |
| 原始输出 | `result/wgs/mlst/mlst_raw.txt` |

## 支持的 MLST 方案
涵盖 >100 个物种（senterica, ecoli, campylobacter, kpneumoniae, efaecium, sau, cdifficile 等）。

```bash
# 查看支持的所有方案
conda run --prefix envs/prokaWGS mlst --list
```

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--scheme` | auto | 自动检测物种匹配方案 |
| `--nopath` | on | 输出中不显示文件完整路径 |
| `--quiet` | on | 减少冗余输出 |
| `--threads` | CPUS | 线程数 |

## 示例命令

```bash
# 聚合 MLST 分型
bash scripts/41b_bac_mlst.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 指定物种方案（如大肠杆菌）
bash scripts/41b_bac_mlst.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow --scheme ecoli

# 手动运行
conda run --prefix envs/prokaWGS mlst --nopath --quiet --threads 16 \
    result/binning/drep/dereplicated_genomes/*.fa > mlst_raw.txt
```

## 输出格式（mlst.tsv）
```
FILE            SCHEME         ST    ALLELES
bin.001.fa      efaecium       203   adk(3);atpA(1);...
bin.002.fa      -              -     (方案未匹配)
```

## 注意事项
- 自动检测（`--scheme auto`）需 MAG 中有足够覆盖度的标记基因
- MAGs 若质量差（< 70% completeness），部分等位基因可能缺失，ST 显示 `-`
- MLST 主要对单一物种有意义；混合样本 MAG 文库不适合直接比较不同物种的 ST

## 官方链接
- GitHub: https://github.com/tseemann/mlst
- PubMLST 数据库: https://pubmlst.org
