# 跨队列验证模块使用指南

## 概述

`97_stat_crosscohort.sh` 是增强版跨队列验证脚本，支持：
- ✅ **本地多队列模式**（推荐）：从多个本地项目目录读取
- ✅ **curatedMetagenomicData 模式**：从在线数据集加载（需网络）
- ✅ **8 个核心可视化**：森林图/瀑布图/ROC叠加/UpSet/特征稳定性/PCoA/校准曲线/效应相关
- ✅ **Meta-analysis**：随机效应模型合并 AUC，I² 异质性评估

---

## 依赖包（已安装）

R 包：`SIAMCAT`, `tidyverse`, `pROC`, `metafor`, `forestplot`, `UpSetR`, `ComplexHeatmap`, `patchwork`, `GGally`, `MMUPHin`（可选批次校正）

---

## 使用场景

### 场景 1：本地多队列验证（推荐）

假设有 3 个独立项目目录（不同医院/不同时间采集）：
```
Project/
├── Hospital_A/
│   ├── metadata.csv
│   └── result/metaphlan4/merged/taxonomy.tsv
├── Hospital_B/
│   ├── metadata.csv
│   └── result/metaphlan4/merged/taxonomy.tsv
└── Hospital_C/
    ├── metadata.csv
    └── result/metaphlan4/merged/taxonomy.tsv
```

**运行**：
```bash
bash scripts/97_stat_crosscohort.sh \
  -w Project/Hospital_A \
  -r ~/Course/CSCCD-MetagenomeFlow \
  -m Project/Hospital_A/metadata.csv \
  -g Group \
  --source local \
  --cohorts "Hospital_A,Hospital_B,Hospital_C" \
  --train-cohort Hospital_A \
  --meta-analysis
```

**说明**：
- `--source local`：使用本地多队列模式
- `--cohorts`：逗号分隔的队列名（对应项目目录名）
- `--train-cohort`：指定训练队列（默认第一个）
- `--meta-analysis`：启用随机效应 meta-analysis

---

### 场景 2：单队列（无外部验证）

当前只有一个项目，但想查看框架输出（用于未来扩展）：
```bash
bash scripts/97_stat_crosscohort.sh \
  -w Project/Project_example \
  -r ~/Course/CSCCD-MetagenomeFlow \
  -m Project/Project_example/metadata.csv \
  -g Group \
  --source local
```

**说明**：不指定 `--cohorts` 时，自动使用 `-w` 指定的单个队列。

---

### 场景 3：curatedMetagenomicData（需网络）

```bash
bash scripts/97_stat_crosscohort.sh \
  -w Project/Project_example \
  -r ~/Course/CSCCD-MetagenomeFlow \
  -m Project/Project_example/metadata.csv \
  -g Group \
  --source curated \
  --condition CRC
```

**说明**：
- `--source curated`：从 Bioconductor curatedMetagenomicData 加载
- `--condition`：CRC（结直肠癌）/ T2D（2型糖尿病）/ IBD（炎症性肠病）
- **限制**：需网络访问 Bioconductor，离线环境不可用

---

## 输出结构

```
${WORKDIR}/result/viz_crosscohort/
├── auc_summary.tsv                      # 队列 × AUC × CI × n_samples
├── meta_analysis_results.tsv            # Meta-analysis 合并 AUC + I² + Q统计量
├── consistent_biomarkers.tsv            # 跨队列一致性特征（未来扩展）
├── crosscohort_done.txt                 # Sentinel + 日志摘要
│
├── forest_plot_auc.pdf                  # 森林图：每队列 AUC + 95% CI
├── waterfall_auc.pdf                    # 瀑布图：队列 AUC 降序排列
├── roc_overlay_all_cohorts.pdf          # 多队列 ROC 曲线叠加
├── upset_shared_features.pdf            # UpSet：跨队列共享 top 50 特征
├── heatmap_feature_stability.pdf        # ComplexHeatmap：特征 × 队列
├── pcoa_batch_effect.pdf                # PCoA 着色 by cohort（批次评估）
├── calibration_per_cohort.pdf           # 校准曲线网格（2×N 布局）
├── effect_correlation_matrix.pdf        # GGpairs：队列间效应相关
│
└── {CohortName}_roc.pdf                 # 每队列独立 ROC 曲线（多个）
```

---

## 参数说明

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `-w` | ✅ | - | 项目工作目录（作为默认队列） |
| `-r` | ✅ | - | CSCCD-MetagenomeFlow 仓库根目录 |
| `-m` | ✅ | - | Metadata CSV（必须含 `sample_id` + `GROUP_COL` + `cohort` 列） |
| `-g` | ✅ | - | 分组列名（如 `Group`, `Disease`） |
| `--source` | ❌ | `local` | 数据源：`local` / `curated` |
| `--cohorts` | ❌ | 自动单队列 | 逗号分隔的队列名（local 模式） |
| `--train-cohort` | ❌ | 第一个队列 | 训练队列名称 |
| `--test-cohorts` | ❌ | 除训练外全部 | 测试队列（逗号分隔） |
| `--condition` | ❌ | `CRC` | curatedMGD 疾病：CRC / T2D / IBD |
| `--meta-analysis` | ❌ | 关闭 | 启用随机效应 meta-analysis |
| `--force` | ❌ | - | 覆盖现有结果重新运行 |

---

## 前置条件

1. **脚本 96 已运行**：需要 SIAMCAT 模型文件 `${WORKDIR}/result/stat/ml/siamcat_lasso.rds`
2. **MetaPhlAn4 结果**：每个队列需要 `result/metaphlan4/merged/taxonomy.tsv`
3. **Metadata 格式**：必须包含以下列：
   - `sample_id`：样本 ID
   - `{GROUP_COL}`：分组标签（如 `Control` / `Case`）
   - `cohort`：队列标签（本地多队列模式必需）

---

## 本地多队列测试（使用 mock 数据）

手动搭建多队列测试布局（仓库不再内置专用测试脚本）：
1. 复制 `Project_example` 3 份 → `Cohort_A/B/C`（作为 WORKDIR 的兄弟目录）
2. 修改 metadata 添加 `cohort` 列
3. 运行本地多队列模式（3 个队列）
4. 验证 8 个可视化输出
5. 测试 meta-analysis 功能

**清理测试数据**：
```bash
rm -rf ~/Course/CSCCD-MetagenomeFlow/Project/_test_crosscohort
```

---

## 输出解读

### 1. AUC Summary (`auc_summary.tsv`)

| 列 | 说明 |
|----|------|
| `cohort` | 队列名称 |
| `auc` | 模型在该队列的 AUC |
| `auc_ci_low` / `auc_ci_high` | 95% 置信区间 |
| `n_samples` | 样本数 |

**判断标准**：
- AUC > 0.7：模型在该队列表现良好
- AUC < 0.6：模型在该队列泛化能力差
- CI 窄：样本量足够，估计稳定

---

### 2. Meta-Analysis Results (`meta_analysis_results.tsv`)

| 列 | 说明 |
|----|------|
| `pooled_auc` | 随机效应合并 AUC |
| `pooled_auc_ci_low/high` | 合并 AUC 的 95% CI |
| `I2` | 异质性指标（0-100%，0=无异质性，>75%=高异质性） |
| `Q` / `Q_pvalue` | Cochran's Q 检验（p<0.05 表示存在异质性） |
| `tau2` | 队列间方差 |

**判断标准**：
- **I² < 25%**：低异质性，队列间效应一致，可信赖合并估计
- **I² 25-75%**：中等异质性，需进一步探索异质性来源
- **I² > 75%**：高异质性，队列间差异大，合并估计需谨慎解读

---

### 3. 特征稳定性 (`heatmap_feature_stability.pdf`)

- **行**：Top 50 特征（按跨队列流行度排序）
- **列**：队列
- **颜色**：蓝色=该特征在该队列存在，白色=不存在
- **用途**：识别跨队列稳定的生物标志物

---

### 4. 批次效应 (`pcoa_batch_effect.pdf`)

- **点颜色**：队列
- **椭圆**：95% 置信椭圆
- **用途**：评估批次校正效果，如果队列分离明显 → 仍存在批次效应

---

## 故障排查

### 问题 1：`SIAMCAT model not found`
**原因**：脚本 96 未运行或 ML 模型缺失  
**解决**：
```bash
bash scripts/96_stat_ml_siamcat.sh -w ${WORKDIR} -r ~/Course/CSCCD-MetagenomeFlow \
     -t 16 -m metadata.csv -g Group
```

### 问题 2：`No common samples between abundance and metadata`
**原因**：metadata 的 `sample_id` 与 MetaPhlAn4 输出的样本名不匹配  
**解决**：检查 `result/metaphlan4/merged/taxonomy.tsv` 的列名与 `metadata.csv` 的 `sample_id` 是否一致

### 问题 3：`Cohort directory not found`
**原因**：`--cohorts` 指定的队列目录不存在  
**解决**：确认队列目录路径正确，格式为 `$(dirname ${WORKDIR})/{cohort_name}`

### 问题 4：Meta-analysis 失败
**原因**：队列数 < 3（meta-analysis 需要至少 3 个队列）  
**解决**：移除 `--meta-analysis` 标志，或增加队列数

---

## 下一步扩展

### 未来可添加功能
1. **差异分析结果整合**：从各队列的 `result/stat/diff/` 读取 LEfSe/MaAsLin2 结果 → 生成效应方向一致性检查
2. **特征稳定性评分**：计算每个特征在多少个队列中显著 → 导出 Top 20 稳定生物标志物
3. **交互式报告**：生成 HTML 报告（`rmarkdown`），包含所有图表 + 解读文本
4. **支持病毒/真菌维度**：当前仅支持细菌（MetaPhlAn4），未来扩展到 vOTU 和真菌

---

## 引用

如果使用本模块发表文章，请引用：

- **SIAMCAT**: Wirbel et al. (2021) *Genome Biology*
- **metafor**: Viechtbauer (2010) *Journal of Statistical Software*
- **MMUPHin**: Ma et al. (2020) *Nature Communications*
- **pROC**: Robin et al. (2011) *BMC Bioinformatics*
