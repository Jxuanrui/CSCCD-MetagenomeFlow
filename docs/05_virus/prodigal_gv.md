# Prodigal-gv — 病毒蛋白编码基因预测

**版本**: Prodigal 2.6.3（-p meta 模式）| **环境**: `envs/assembly` | **脚本**: `scripts/55_vir_prodigal_gv.sh`

## 功能
使用 Prodigal 的 `-p meta`（宏基因组）模式对病毒 contigs 进行蛋白编码基因预测。虽然脚本名包含 `-gv`，但实际使用标准 Prodigal 宏基因组模式（遗传密码 11）。输出蛋白序列（FAA）、基因核酸序列（FNA）和 GFF 坐标文件。

## 用法

```bash
bash scripts/55_vir_prodigal_gv.sh -s SAMPLE -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入病毒序列 | `result/virus/checkv/{sample}/viruses.fna` |
| 蛋白序列 | `result/virus/prodigal/{sample}/{sample}.faa` |
| 基因核酸序列 | `result/virus/prodigal/{sample}/{sample}.fna` |
| GFF 坐标 | `result/virus/prodigal/{sample}/{sample}.gff` |

## 注意事项
- 输入优先使用 CheckV 的 `viruses.fna`（geNomad+VirSorter2 合并去重后的病毒 contigs）
- 若 `viruses.fna` 不存在，自动回退到 `virus_contigs.fasta`
- 蛋白序列输出供下游功能注释使用（如 VOG HMM 扫描）

## 官方链接
- GitHub: https://github.com/hyattpd/Prodigal
- 论文: Hyatt et al. 2010, BMC Bioinformatics
