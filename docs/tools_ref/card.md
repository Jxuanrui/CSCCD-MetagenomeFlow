# CARD / RGI — 抗生素耐药基因综合注释

**版本**: RGI 6.x + CARD 3.x | **环境**: `envs/amr` | **脚本**: `scripts/24_bac_card.sh`

## 功能
CARD（Comprehensive Antibiotic Resistance Database）结合 RGI（Resistance Gene Identifier），使用 DIAMOND 比对对蛋白序列进行耐药基因注释，输出抗性机制分类、药物类别和严格/宽松匹配级别。支持 Perfect / Strict / Loose 三级匹配标准。

## 用法

```bash
bash scripts/24_bac_card.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入蛋白 | `result/assembly/cdhit/protein_nr.fa` |
| 文本报告 | `result/card/rgi_results.txt` |
| JSON 报告 | `result/card/rgi_results.json` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--alignment_tool` | DIAMOND | 比对工具（比 BLAST 快 100×） |
| `--input_type` | protein | 输入类型 |
| `--include_loose` | on | 包含宽松匹配（补充信息） |
| `--local` | on | 本地 CARD 数据库（离线） |
| `--clean` | on | 删除中间文件 |

## CARD 匹配级别

| 级别 | 含义 | 使用建议 |
|------|------|---------|
| **Perfect** | 100% 一致性，全长匹配 | 确凿耐药基因 |
| **Strict** | ≥95% 一致性，覆盖部分序列 | 高置信度耐药基因 |
| **Loose** | 低于 Strict 标准 | 参考信息，需谨慎解读 |

## 输出字段

文本报告包含：ARO_term, Best_Hit_ARO, Model_type, Nudged, Drug_class, Resistance_mechanism, AMR_gene_family, Identity, Alignment_length, Cut_off 等。

## 注意事项
- 运行 `rgi load` 加载 CARD 数据库（`db/card/card.json`）
- 自动从工作目录加载 localDB（同一目录复用）
- 建议与 AMRFinderPlus 交叉验证

## 官方链接
- CARD: https://card.mcmaster.ca
- RGI: https://github.com/arpcard/rgi
- 论文: Alcock et al. 2023, Nucleic Acids Research (CARD)
