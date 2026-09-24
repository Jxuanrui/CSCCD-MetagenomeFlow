# PHOLD — 结构暗物质 ORF 注释

**版本**: 1.0+ | **环境**: `envs/phold` | **脚本**: `scripts/65_vir_phold.sh`

## 功能
PHOLD 对 PHAROKKA 注释结果中的暗物质 ORFs（缺乏已知同源性的 ORFs）进行结构蛋白补充注释，尤其针对膜蛋白、结构蛋白和有 PDB 结构可比较的 ORFs，降低病毒基因组中未知功能 ORF 的比例。

## 用法

```bash
bash scripts/65_vir_phold.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 vOTU 序列 | `result/virus/votu/contigs/virus.fasta` |
| PHOLD 注释表 | `result/virus/phold/vOTU_phold.tsv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-i` | vOTU FASTA | 输入序列 |
| `-o` | 输出目录 | 注释目录 |
| `-d` | `db/phold` | 数据库路径 |
| `-p` | vOTU | 序列前缀命名空间 |
| `-f` | on | 覆盖现有输出 |

## PHOLD vs PHAROKKA 互补

| 工具 | 覆盖 | 优势 |
|------|------|------|
| PHAROKKA | PHROG 功能分类 | 功能覆盖全面 |
| **PHOLD** | 结构蛋白 + 膜蛋白 | 降低暗物质比例 |

建议：先运行 PHAROKKA（64），再运行 PHOLD 补充注释。

## 注意事项
- PHOLD 数据库约 2 GB，位于 `db/phold/`
- 汇总输出自动合并所有结果文件到 `vOTU_phold.tsv`
- 输出格式与 PHAROKKA 兼容，便于下游合并处理

## 官方链接
- GitHub: https://github.com/gbouras13/phold
