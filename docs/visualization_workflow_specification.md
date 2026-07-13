# 功能分析可视化流程规范文档

**版本**: v2.0  
**日期**: 2026-07-13  
**项目**: MaxMetagenome 宏基因组分析平台  
**更新内容**: 简化为基于DESeq2/MaAsLin2/Wilcoxon的轻量级流程，移除Maaslin3依赖

---

## 1. 概述 (Overview)

### 1.1 流程目的
对肠道微生物组三大维度（细菌、真菌、病毒）的功能注释结果进行差异分析和可视化，生成符合 SCI 出版标准的统计图表。

### 1.2 支持的维度和功能类型

| 维度 | 功能类型数 | 具体类型 |
|------|-----------|---------|
| **Bacteria** | 9 | pathway, kegg_ko, cog, cazyme, arg, vfdb, defense, ncyc, pcyc |
| **Fungi** | 6 | kegg_ko, cog, cazyme, vfdb, amr, merops |
| **Virus** | 5 | phrog, vog, lifestyle, host_genus, viral_family |

### 1.3 核心输出物
- **差异分析结果**：3种方法（DESeq2/MaAsLin2/Wilcoxon）× 每表1个TSV
- **核心可视化**：volcano plot + barplot（Nature风格，每方法1套）
- **ML可解释性**（可选）：SHAP waterfall + dependence plots + KO enrichment + cross-omics networks

---

## 2. 数据流向图 (Data Flow)

```
┌─────────────────────────────────────────────────────────────┐
│ 上游分析 (Upstream Analysis)                                 │
│  - 细菌: HUMAnN3, eggNOG, dbCAN, ARG, VFDB, DefenseFinder    │
│  - 真菌: Prodigal → eggNOG, dbCAN, VFDB, AMRFinder, MEROPS  │
│  - 病毒: Pharokka, VOG, BacPhlip, iPHoP, vConTACT3          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 整合表生成 (Integration Tables)                              │
│  - 脚本: 98_integration_tables.sh (细菌)                     │
│         98d_fun_integration_tables.sh (真菌)                │
│         98c_vir_integration_tables.sh (病毒)                │
│  - 输出: result/integration/{dimension}/{type}_abundance.tsv │
│  - 格式: 行=feature, 列=sample_id, 值=abundance              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 差异分析 (Differential Abundance Analysis)                   │
│  - 脚本: scripts/04b_functional_differential.R               │
│  - 方法: DESeq2 (负二项模型) + MaAsLin2 (线性模型) +        │
│         CLR-Wilcoxon (非参数检验)                           │
│  - 输出: temp/04_differential/{dimension}/{type}/            │
│    ├── deseq2_results.tsv                                   │
│    ├── maaslin2_results/results.tsv                         │
│    ├── wilcoxon_results.tsv                                 │
│    └── differential_summary.tsv                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 可视化生成 (Visualization)                                   │
│  - 脚本: scripts/04c_visualize_functional_differential.R     │
│  - 复用: scripts/R/plot_differential.R 函数库               │
│  - 输出: result/04_differential/{dimension}/{type}/          │
│    ├── volcano_deseq2_{dimension}_{type}.pdf               │
│    ├── volcano_maaslin2_{dimension}_{type}.pdf             │
│    ├── volcano_wilcoxon_{dimension}_{type}.pdf             │
│    ├── barplot_deseq2_{dimension}_{type}.pdf (top 20)      │
│    ├── barplot_maaslin2_{dimension}_{type}.pdf             │
│    └── barplot_wilcoxon_{dimension}_{type}.pdf             │
│  - 风格: Nature三色显著性标注, ggrepel标签, theme_classic   │
└─────────────────────────────────────────────────────────────┘
                            ↓ (可选扩展)
┌─────────────────────────────────────────────────────────────┐
│ ML可解释性分析 (Machine Learning Interpretability)           │
│  - 前置: scripts/97_ml_mlr3/{01-10}*.R (6步ML流程)         │
│  - 扩展脚本:                                                 │
│    ├── 11_shap_waterfall_representatives.R (个体解释)       │
│    ├── 12_shap_dependence_top.R (特征交互)                 │
│    ├── 13_kegg_enrichment.R (KO富集)                       │
│    └── 14_cross_omics_network.R (物种-功能关联)            │
│  - 输出: result/97_ml_mlr3/{dimension}/{type}/              │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 核心脚本说明

### 3.1 差异分析引擎 (04b_functional_differential.R)

**功能**: 对单个功能整合表执行3种互补的差异分析方法

**方法对比**:
| 方法 | 适用场景 | 统计模型 | 优势 | 劣势 |
|------|---------|---------|------|------|
| **DESeq2** | 计数数据 | 负二项模型 | 控制假阳性最严格 | 对小表可能过于保守 |
| **MaAsLin2** | 连续/计数混合 | 线性混合模型 | 支持协变量控制 | 需要足够样本量 |
| **CLR-Wilcoxon** | 组成数据 | 非参数秩检验 | 无分布假设 | 检出数可能过多 |

**关键参数**:
```r
--abundance-file    # 输入TSV (行=feature, 列=sample)
--metadata-file     # 样本元数据 (必须含sample_id和group列)
--output-dir        # 输出目录
--min-prevalence 0.1  # 最小流行度过滤 (默认10%)
--padj-threshold 0.05 # FDR校正阈值
```

**输出文件**:
- `deseq2_results.tsv`: 含 baseMean, log2FoldChange, pvalue, padj
- `maaslin2_results/results.tsv`: 含 coef, stderr, pval_individual, qval
- `wilcoxon_results.tsv`: 含 mean_case, mean_control, mean_diff, pvalue, padj
- `differential_summary.tsv`: 汇总表 (各方法显著feature数统计)

**容错机制**:
- DESeq2小表自动降级到 `fitType="mean"`
- MaAsLin2失败时生成空结果但不中断流程
- 所有方法失败时输出标准格式空文件

---

### 3.2 可视化调度器 (04c_visualize_functional_differential.R)

**功能**: 批量生成volcano plot和barplot，复用Nature风格函数库

**调用流程**:
```r
source("scripts/R/plot_differential.R")  # 加载 plot_volcano_nature() 和 plot_barplot_enhanced()

for (method in c("deseq2", "maaslin2", "wilcoxon")) {
  # 1. 读取结果并标准化列名
  data <- standardize_columns(read_results(method))
  
  # 2. 生成volcano plot (3色显著性标注 + ggrepel前10标签)
  plot_volcano_nature(data, title=paste(dimension, type, method))
  
  # 3. 生成barplot (仅显著feature, top 20, diverging color)
  plot_barplot_enhanced(data[data$padj < 0.05, ], top_n=20)
}
```

**关键参数**:
```r
--result-dir       # 04b输出的差异分析结果目录
--output-dir       # PDF输出目录
--dimension        # bacteria/fungi/virus (用于标题)
--type             # kegg_ko/arg/vog等 (用于标题)
```

**列名映射** (统一为`log2fc`, `pvalue`, `padj`):
| 原始方法 | 效应量列 | P值列 | 校正P值列 |
|---------|---------|-------|----------|
| DESeq2  | log2FoldChange | pvalue | padj |
| MaAsLin2| coef | pval_individual | qval |
| Wilcoxon| mean_diff | pvalue | padj |

---

### 3.3 ML可解释性扩展 (scripts/97_ml_mlr3/)

详见 `docs/downstream_analysis_audit_report.md` §4-5节。

---

## 4. 快速启动指南

### 4.1 单表差异分析 (最小可运行示例)

```bash
# 激活环境
source ${PROJ_DIR}/scripts/activate.sh

# 示例: 分析bacteria的kegg_ko表
Rscript scripts/04b_functional_differential.R \
  --abundance-file result/integration/bacteria/kegg_ko_abundance.tsv \
  --metadata-file Project/Test_100samples/metadata.csv \
  --output-dir temp/04_differential/bacteria/kegg_ko \
  --min-prevalence 0.1

# 生成可视化
Rscript scripts/04c_visualize_functional_differential.R \
  --result-dir temp/04_differential/bacteria/kegg_ko \
  --output-dir result/04_differential/bacteria/kegg_ko \
  --dimension bacteria \
  --type kegg_ko
```

**预期输出** (单表):
- 4个TSV (3个方法结果 + 1个summary)
- 6个PDF (3个volcano + 3个barplot)

---

### 4.2 批量分析所有功能表

```bash
# 遍历所有整合表
for dimension in bacteria fungi virus; do
  for tsv in result/integration/${dimension}/*_abundance.tsv; do
    type=$(basename $tsv _abundance.tsv)
    
    # 差异分析
    Rscript scripts/04b_functional_differential.R \
      --abundance-file $tsv \
      --metadata-file Project/Test_100samples/metadata.csv \
      --output-dir temp/04_differential/${dimension}/${type}
    
    # 可视化
    Rscript scripts/04c_visualize_functional_differential.R \
      --result-dir temp/04_differential/${dimension}/${type} \
      --output-dir result/04_differential/${dimension}/${type} \
      --dimension $dimension \
      --type $type
  done
done
```

**预期产出** (19表):
- 76个TSV (19×4)
- 114个PDF (19×6)

---

## 5. 与旧流程对比

| 维度 | 旧流程 (Maaslin3) | 新流程 (04b/04c) |
|------|------------------|-----------------|
| **依赖复杂度** | Maaslin3 v1.5.3 (需编译) | DESeq2/MaAsLin2 (CRAN/BioConductor) |
| **方法数量** | 1种 (线性混合模型) | 3种 (负二项/线性/非参数) |
| **容错性** | 失败即停 | 自动降级 + 空结果生成 |
| **可视化风格** | 基础ggplot | Nature风格 (3色+ggrepel) |
| **批量执行** | 需手动循环 | 单脚本支持 |
| **文档化** | 参数硬编码 | 完整optparse + --help |

**迁移建议**: 新分析项目直接使用新流程；旧项目结果无需重跑（方法学不同，不可直接比较）。

---

## 6. 常见问题 (FAQ)

**Q1: 为什么DESeq2显著feature数比Wilcoxon少很多？**  
A: DESeq2控制假阳性最严格（负二项模型 + Cook距离过滤），Wilcoxon只做秩检验。建议优先关注DESeq2结果，用Wilcoxon补充弱信号。

**Q2: 小表（<10 features）如何处理？**  
A: 04b脚本自动检测并调用 `scripts/97_ml_mlr3/10_effect_size.R` 执行CLR+Wilcoxon+效应量可视化，生成diverging bar chart而非volcano plot。

**Q3: MaAsLin2报错"singular convergence"怎么办？**  
A: 这是样本量不足或协变量共线性导致的，脚本会自动生成空结果并继续执行其他方法，不影响DESeq2和Wilcoxon。

**Q4: 如何调整显著性阈值？**  
A: 修改 `--padj-threshold` 参数 (默认0.05)，同时需修改 `plot_differential.R` 中的阈值常量。

**Q5: 可以只运行某一种方法吗？**  
A: 当前04b脚本固定运行3种方法，如需单独运行需修改源码注释掉其他方法。建议保留全部方法以增强结果鲁棒性。

---

## 7. 输出文件索引 (Test_100samples实测)

**差异分析TSV** (76个):
```
temp/04_differential/
├── bacteria/
│   ├── arg/{deseq2,maaslin2,wilcoxon}_results.tsv + summary.tsv
│   ├── kegg_ko/...
│   └── ... (共8个功能类型)
├── fungi/
│   ├── kegg_ko/...
│   └── ... (共6个功能类型)
└── virus/
    ├── vog/...
    └── ... (共5个功能类型)
```

**可视化PDF** (114个):
```
result/04_differential/
├── bacteria/
│   ├── arg/
│   │   ├── volcano_deseq2_bacteria_arg.pdf
│   │   ├── volcano_maaslin2_bacteria_arg.pdf
│   │   ├── volcano_wilcoxon_bacteria_arg.pdf
│   │   ├── barplot_deseq2_bacteria_arg.pdf
│   │   ├── barplot_maaslin2_bacteria_arg.pdf
│   │   └── barplot_wilcoxon_bacteria_arg.pdf
│   └── ... (共8×6=48个PDF)
├── fungi/ (共6×6=36个PDF)
└── virus/ (共5×6=30个PDF)
```

---

## 8. 方法学说明 (用于Methods撰写)

### 8.1 差异丰度分析

功能丰度差异分析采用3种互补方法：

1. **DESeq2** (v1.42.0): 采用负二项广义线性模型，通过几何均数标准化和收缩估计控制离散度估计偏差，适用于计数数据的差异分析。显著性阈值设为校正后 P < 0.05 (Benjamini-Hochberg FDR)。

2. **MaAsLin2** (v1.16.0): 线性混合效应模型，支持连续和分类协变量控制，采用TSS标准化后LOG转换。当样本量不足导致收敛失败时自动跳过。

3. **CLR-Wilcoxon**: 针对组成数据，先进行中心对数比(CLR)变换消除组成约束，再用Wilcoxon秩和检验进行非参数比较，适用于非正态分布数据。

所有方法在分析前均进行流行度过滤 (prevalence ≥ 10%)，以去除低丰度噪声特征。

### 8.2 可视化规范

- **Volcano plot**: X轴为log2 fold change，Y轴为-log10(P值)，采用三色编码 (上调/下调/不显著)，用ggrepel标注前10个最显著特征，避免标签重叠。
- **Bar plot**: 仅展示显著特征 (FDR < 0.05) 的top 20，使用diverging color scale (RdBu)，正值表示病例组富集，负值表示对照组富集。

所有图表采用 `theme_classic()` 主题，符合Nature系列期刊出版标准。

---

## 9. 版本变更日志

### v2.0 (2026-07-13)
- ✅ 新增 04b/04c 脚本替代旧的 96_stat_functional.sh 流程
- ✅ 集成3种差异分析方法 (DESeq2/MaAsLin2/Wilcoxon)
- ✅ 移除Maaslin3依赖，改用标准BioConductor包
- ✅ 新增Nature风格可视化函数库 (scripts/R/plot_differential.R)
- ✅ 补充ML可解释性扩展模块 (scripts/97_ml_mlr3/11-14)
- ✅ 完整批量测试 (19表×3方法，196个输出文件验证通过)

### v1.0 (2026-07-07)
- 初始版本，基于Maaslin3的单一方法流程

---

**文档生成日期**: 2026-07-13  
**适用项目**: MaxMetagenome v1.0 + Phase 2扩展  
**维护者**: JXR1314 + Claude (Kiro AI)

