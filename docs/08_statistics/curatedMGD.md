# 跨队列验证（curatedMetagenomicData）

**环境**: `envs/r_stat` | **脚本**: `scripts/97_stat_curatedMGD.sh`

## 功能
使用 curatedMetagenomicData 公共数据库中的外部队列数据，通过 SIAMCAT 模型进行跨队列一致性的 holdout 验证。评估本分析得到的生物标志物在独立队列中的泛化能力。

## 用法

```bash
bash scripts/97_stat_curatedMGD.sh \
    -w /path/to/workdir -r ~/Course/Maxmetagenome \
    -m metadata.csv -g group \
    -c CRC --augment-n 50
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 工作目录 |
| `-r` | 是 | — | 项目根目录 |
| `-m` | 是 | — | 元数据 CSV |
| `-g` | 是 | — | 分组列 |
| `-c` | 否 | CRC | 疾病条件标签（CRC/T2D/IBD 等） |
| `--augment-n` | 否 | 50 | 从外部队列添加的对照样本数 |

## 输入

| 项目 | 路径 |
|------|------|
| ML 模型 | `result/stat/ml/siamcat_{model}.rds`（96 脚本输出） |
| 元数据 | 通过 `-m` 传入 |
| 公共队列数据 | curatedMetagenomicData 包（自动下载） |

## 分析流程

1. 从 curatedMetagenomicData 选取条件匹配的队列（如 CRC）
2. 提取外部队列的物种丰度数据，与本研究特征对齐
3. 使用 96 脚本训练的 SIAMCAT 模型进行预测
4. 评估外部 AUC，判断特征泛化能力

## 支持的疾病条件

curatedMetagenomicData 包含以下常见条件的公共队列：
CRC / T2D / IBD / 肝硬化 / 肥胖 / 高血压 / 健康对照（通用）

## 输出

| 文件 | 内容 |
|------|------|
| `crosscohort_auc.tsv` | 各模型在外部队列的 AUC |
| `crosscohort_done.txt` | 完成报告 |

## 注意事项
- curatedMetagenomicData 是 Bioconductor 包，首次运行自动下载
- 需要网络连接下载公共数据
- 外部队列的样本量和匹配度影响验证可靠性

## 官方链接
- Bioconductor: https://bioconductor.org/packages/curatedMetagenomicData
- 论文: Pasolli et al. 2017, Nature Communications
