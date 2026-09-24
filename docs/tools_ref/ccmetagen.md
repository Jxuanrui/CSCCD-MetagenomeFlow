# CCMetagen — 真核 + 原核综合分类

**环境**: `envs/assembly` | **脚本**: `scripts/76_fun_ccmetagen.sh`

## 功能
CCMetagen 使用 KMA（k-mer 自适应对齐）将宏基因组 reads 比对到 NCBI nt 全库，实现真核和原核的分类鉴定。KMA 的 concatemer 比对策略能提高低覆盖率物种的检测灵敏度，适合无近缘参考基因组时的广谱分类。脚本 76 封装了 KMA + CCMetagen 两步流程。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 R1 | `result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz` |
| 输入 R2 | `result/kneaddata/{sample}/{sample}_2.kneaddata.fastq.gz` |
| 物种分类 | `result/fungi/ccmetagen/{sample}/{sample}_species.txt` |
| Krona HTML | `result/fungi/ccmetagen/{sample}/{sample}_krona.html` |

## 关键参数

### KMA 比对

| 参数 | 默认 | 含义 |
|------|------|------|
| `-ipe` | R1 R2 | interleaved paired-end reads |
| `-t_db` | `db/kma/nt/*` | NCBI nt 数据库索引 |
| `-t` | CPUS | 线程数 |
| `-1t1` | on | 仅保留最佳匹配 |
| `-mem_mode` | on | 内存模式（加快速度） |
| `-and` | on | R1 和 R2 都需匹配 |
| `-apm f` | on | 精确匹配模式 |
| `-ef` | on | 评估过滤 |

## 自动回退机制

1. 优先使用 KMA + CCMetagen.py 完整流程
2. 若 CCMetagen.py 未安装，回退到仅 KMA 分类结果整理
3. 两种模式都会生成 `{sample}_species.txt`

## 与 FunOMIC 对比

| 特性 | CCMetagen | FunOMIC |
|------|-----------|---------|
| 比对算法 | KMA（k-mer 自适应） | DIAMOND / blastx |
| 数据库 | NCBI nt（全部核酸序列） | 真菌标记基因 + 功能蛋白 |
| 真核覆盖 | **完整（含原核）** | 仅真菌 |
| 无近缘参考 | 仍能检测（全库覆盖） | 有限（依赖标记基因库） |
| 计算资源 | 高（全 nt 库，>100 GB） | 中 |

## 注意事项
- KMA 索引数据库（NCBI nt）约 100+ GB，位于 `db/kma/nt/`，首次运行前确保已下载构建
- `-mem_mode` 将数据库加载到内存，需要 ≥64 GB RAM 推荐；若内存不足可移除该标志
- CCMetagen.py 可在以下环境获取：`pip install ccmetagen` 或 `conda install -c bioconda ccmetagen`
- 若 CCMetagen.py 未安装，脚本会输出纯 KMA 的 `.res` 文件解析结果，分类深度略低于 CCMetagen 整合输出

## 官方链接
- GitHub: https://github.com/SorenKarstLab/CCMetagen
- KMA: https://github.com/SorenKarstLab/kma
- 论文: Marcelino et al. 2020, NAR Genomics and Bioinformatics 2:lqaa043
