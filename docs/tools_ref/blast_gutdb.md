# BLAST GutDB — 肠道真菌参考库比对

**版本**: DIAMOND BLAST | **环境**: `envs/assembly` | **脚本**: `scripts/74_fun_blast_gutdb.sh`

## 功能
使用 DIAMOND blastx 将宏基因组 reads 比对到肠道真菌参考数据库（GutDB，47 GB），进行高精度真菌物种鉴定。适合对分类学精度要求高的场景，但计算资源消耗大。

## 用法

```bash
bash scripts/74_fun_blast_gutdb.sh -s SAMPLE -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-s` | 是 | — | 样本 ID |
| `-t` | 否 | 8 | 线程数 |
| `-w` | 是 | — | 工作目录 |
| `-r` | 是 | — | 项目根目录 |

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 cleaned reads | `temp/{sample}/02_kneaddata/{sample}_kneaddata_clean.fastq.gz` |
| BLAST 输出 | `result/fungi/blast_gutdb/{sample}_blast.tsv` |

## 输出格式（BLAST m8）

```
qseqid   sseqid   pident   length   mismatch   gapopen   qstart   qend   sstart   send   evalue   bitscore
```

## 与 FunOMIC / CCMetagen 的对比

| 工具 | 方法 | 数据库 | 速度 | 精度 |
|------|------|--------|------|------|
| FunOMIC（75） | marker + 功能蛋白 | 1.6M markers + 3.4M proteins | 中 | 高（推荐） |
| CCMetagen（76） | KMA | NCBI nt 全库 | 较慢 | 全面 |
| **BLAST GutDB**（74） | DIAMOND blastx | 肠道真菌库 47G | 最慢 | 高（参考依赖） |

建议优先级：FunOMIC > CCMetagen > BLAST GutDB（含计算时间与精度权衡）

## 注意事项
- 数据库 47 GB，位于 `db/gutdb/`
- DIAMOND blastx（核酸 → 蛋白比对）比 blastn 更敏感
- 单样本约需 2-4 小时（16 线程）

## 官方链接
- DIAMOND: https://github.com/bbuchfink/diamond
- GutDB: 参考肠道真菌基因组集合（非独立工具）
