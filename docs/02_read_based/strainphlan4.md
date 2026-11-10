# StrainPhlAn4 — 菌株追踪与系统发育

**环境**: `envs/humann4` | **脚本**: `scripts/12_bac_strainphlan4.sh`

## 功能
StrainPhlAn4 使用 MetaPhlAn4 的标记基因（marker genes）对微生物组样本进行菌株级追踪与系统发育树构建。通过比对 consensus markers，可以分辨在种水平上相同的菌株间的细微差异。

**三步流程**：sample2markers → extract_markers → strainphlan

## 用法

```bash
# 第一步：自动检测可分析菌株
bash scripts/12_bac_strainphlan4.sh -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 8

# 第二步：对指定菌株建树
bash scripts/12_bac_strainphlan4.sh -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 8 -c t__SGB10068
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 工作目录 |
| `-r` | 是 | — | 项目根目录 |
| `-t` | 否 | 8 | 线程数 |
| `-c` | 否 | — | 目标菌株 ID（如 t__SGB1877） |

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 SAM | `result/metaphlan4/{sample}/{sample}.sam.bz2` |
| Consensus markers | `result/strainphlan4/consensus_markers/*.json.bz2` |
| 系统发育树 | `result/strainphlan4/trees/{CLADE}/RAxML_bestTree.{CLADE}.StrainPhlAn4.tre` |
| 可分析菌株列表 | `result/strainphlan4/clades_detected.txt` |

## 关键参数

| 阈值参数 | 默认 | 含义 |
|---------|------|------|
| `--sample_with_n_markers` | 20 | 样本至少有 N 个 markers |
| `--marker_in_n_samples_perc` | 50 | marker 出现在 ≥50% 样本中 |
| `--breadth_thres` | 80 | 标记覆盖度 ≥80% |
| `--phylophlan_mode` | fast | 使用 FastTree 建树 |

## 注意事项
- StrainPhlAn4 需要至少 2 个样本才能构建系统发育树
- SAM 文件中的重复 @SQ 条目会自动去重（MetaPhlAn4 vOct22 数据库的已知问题）
- 分析分两步：先自动检测可用菌株，再对选定菌株建树
- `.tre` 文件为 Newick 格式，可用 iTOL (https://itol.embl.de) / FigTree / ggtree 可视化

## 官方链接
- 文档: https://github.com/biobakery/MetaPhlAn/wiki/StrainPhlAn-4
- 论文: Blanco-Miguez et al. 2023, Nature Biotechnology (PMID 36823356)
