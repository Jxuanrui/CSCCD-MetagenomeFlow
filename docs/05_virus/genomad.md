# geNomad — 病毒/质粒鉴定与生活方式预测

**版本**: 1.11+ | **环境**: `envs/genomad` | **脚本**: `scripts/52_vir_genomad.sh` / `57_vir_votu_genomad.sh`

## 功能
geNomad 使用神经网络模型从宏基因组 contigs 中识别病毒和质粒序列，同时预测病毒的生活方式（裂解/溶原）。端到端流程覆盖：序列鉴定 → 分类注释 → 生活方式预测（nn-classification + 标记基因）→ 质量过滤，一步完成。

## 输入 / 输出

### 脚本 52 — 病毒鉴定（per-sample）

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/virus/assembly/{sample}/{sample}.contigs.fa` |
| 病毒汇总 | `result/virus/genomad/{sample}/{sample}.contigs_virus_summary.tsv` |
| 病毒序列 | `result/virus/genomad/{sample}/{sample}.contigs_virus.fna` |
| 分类注释 | `result/virus/genomad/{sample}/{sample}.contigs_taxonomy.tsv` |

### 脚本 57 — vOTU 分类注释（aggregate）

| 项目 | 路径 |
|------|------|
| 输入 vOTU | `result/virus/votu/contigs/virus.fasta` |
| 分类注释 | `result/virus/votu_taxonomy/{sample}/{sample}.contigs_taxonomy.tsv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--sensitivity` | 7.5 | 搜索灵敏度（4.2–7.5，越高越灵敏） |
| `--splits` | 4 | 分块数（降低内存峰值） |
| `--cleanup` | on | 删除中间临时文件 |
| `--threads` | CPUS | 线程数 |

## geNomad vs VirSorter2 互补策略

| 特性 | geNomad | VirSorter2 |
|------|---------|------------|
| 算法 | 神经网络（nn-classification） | 多重分类器 + 标记基因 |
| 灵敏度 | 高（~7.5） | 高（5 组病毒群） |
| 特异度 | 极高 | 高 |
| 质粒预测 | **支持** | 不支持 |
| 生活方式预测 | **支持** | 不支持 |
| 分类注释 | **支持** | 不支持 |

本流程中 geNomad 和 VirSorter2 分别独立运行，结果取交集后输入 CheckV，最大化病毒序列召回率。

## 生活方式预测字段

geNomad 输出中包含 `provirus` / `lytic` / `temperate` 分类：
- **provirus**: 整合在宿主基因组中的原前病毒序列
- **lytic**: 裂解性噬菌体（复制后裂解宿主细胞）
- **temperate**: 温和性噬菌体（可进入溶原周期）

## 注意事项
- geNomad 数据库约 10 GB（v1.11），位于 `db/genomad/`，运行前需确保已下载
- `--sensitivity` 设为 7.5 是灵敏度和计算时间的折中；小样本可降至 4.2 加快速度
- geNomad 对短序列（<1kb）灵敏度有限，Contigs 长度建议 ≥1.5kb（已在 MEGAHIT 组装中控制）

## 官方链接
- GitHub: https://github.com/apcamargo/genomad
- 论文: Camargo et al. 2024, Nature Biotechnology 42:1303–1311
