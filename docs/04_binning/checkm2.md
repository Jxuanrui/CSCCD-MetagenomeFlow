# CheckM2 — MAG 质量评估

**版本**: 1.0.1 | **环境**: `envs/checkm2` | **脚本**: `scripts/37_bac_checkm2.sh`

## 功能
使用机器学习模型（基于 Diamond 蛋白比对特征）评估 MAG 的完整性（Completeness）和污染率（Contamination），取代依赖 lineage-specific marker genes 的 CheckM v1。对所有系统发育分支均有良好覆盖，特别适合新物种。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 bins | `result/binning/dastool/*/bins/*.fa` |
| 质量报告 | `result/binning/checkm2/quality_report.tsv` |
| 过滤报告 | `result/binning/checkm2/checkm2_filtered/filtered_report.tsv` |

## 数据库
路径：`db/checkm2/uniref100.KO.1.dmnd`（~3G）

```bash
# 下载数据库（如缺失）
checkm2 database --download --path db/checkm2/
```

## 质量标准（默认过滤阈值）

| 质量级别 | 完整性 | 污染率 |
|---------|-------|-------|
| 高质量（HQ） | ≥90% | ≤5% |
| 中质量（MQ） | ≥50% | ≤10% |
| 低质量（LQ） | <50% | - |

脚本默认保留 Completeness ≥ 50%, Contamination ≤ 10%（MQ+HQ）。

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--input` | bin 目录 | 输入 FASTA 目录 |
| `--output-directory` | `result/binning/checkm2/` | 输出目录 |
| `--threads` | CPUS | 线程数 |
| `--database_path` | `db/checkm2/` | 数据库路径 |
| `--extension` | `fa` | 输入文件后缀 |

## 示例命令

```bash
# 聚合运行（脚本自动收集所有样本 bins）
bash scripts/37_bac_checkm2.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 查看 HQ MAGs
awk -F'\t' '$2 >= 90 && $3 <= 5' result/binning/checkm2/quality_report.tsv | head
```

## 输出格式（quality_report.tsv 关键列）
```
Name    Completeness    Contamination    Contamination_Model_Used    ...
bin.1   95.2            2.3              Gradient Boost               ...
```

## 注意事项
- CheckM2 内置深度学习模型，需要 TensorFlow；`conda run` 时 TF 会打印 GPU 未找到警告（正常，CPU 模式运行）
- 与 CheckM v1 的结果不完全一致，发表时应标明工具版本

## 官方链接
- GitHub: https://github.com/chklovski/CheckM2
- 论文: Chklovski et al. 2023, Nature Methods 20:1203-1212
