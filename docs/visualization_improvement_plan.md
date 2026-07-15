# 差异丰度分析可视化改进方案

**日期**: 2026-07-09  
**基于**: Reference/可视化资源库 分析结果

---

## 1. 可视化资源库概览

### 1.1 资源统计
- **总文件数**: ~100+ 个 RAR 压缩包
- **期刊级别**: Nature, Nature Communications, Nature Genetics, Nature Microbiology 等顶刊图表复现
- **核心技术栈**: ggplot2 + ggrepel + ggtext + ggprism + ComplexHeatmap
- **覆盖范围**: 微生物组学、转录组学、多组学整合分析

### 1.2 火山图相关资源
```
1. 简洁通用的基础火山图代码_20250826.rar          ✅ 已解压分析
2. 多分组火山图的系统绘制方法_20251223.rar        ✅ 已解压分析
3. ggplot2绘制双变量火山图展示基因表达差异_20250407.rar
4. nature同款_火山图与三元相图_20251107.rar
```

### 1.3 差异分析相关资源
```
- NC图表复现一图掌握柱状图显著性标记_20250718.rar
- ggplot2绘制炫彩柱状图_20250404.rar
- NC图表复现-探索哑铃图进阶用法_可视化差异的新思路_20250714.rar
- nature图表复现维恩图与棒棒糖图展示差异基因富集_20250613.rar
- microeco包实现Lefse分析_20250908.rar
```

### 1.4 微生物组特色可视化
```
- 16s_α多样性和组成分析图_20251216.rar
- NC图表复现_从物种组成到多样性_20250906.rar
- nature图表复现_多重注释物种组成图_20250506.rar
- 轻松搞定分组物种组成图_20250822.rar
- NC同款PCoA分析_Loop类别饼图及序列长度排序可视化_20251129.rar
```

---

## 2. 当前火山图实现分析

### 2.1 现有实现 (scripts/04_differential_abundance.R)
```r
# 当前火山图代码片段
ggplot(res_plot, aes(x = log2FoldChange, y = -log10(padj))) +
  geom_point(aes(color = sig), alpha = 0.6, size = 2) +
  scale_color_manual(
    values = c("TRUE" = "#E64B35", "FALSE" = "grey70"),
    labels = c("TRUE" = "Significant", "FALSE" = "Non-significant")
  ) +
  geom_vline(xintercept = c(-opt$lfc, opt$lfc), linetype = "dashed", color = "grey40") +
  geom_hline(yintercept = -log10(opt$fdr), linetype = "dashed", color = "grey40") +
  labs(title = sprintf("%s Volcano Plot", method),
       x = "log2 Fold Change", y = "-log10(FDR)",
       color = "Significance") +
  theme_minimal() +
  theme(legend.position = "top")
```

**问题**:
1. ❌ 配色不够精致 (只有红灰两色，不如参考的红蓝灰三色方案)
2. ❌ 无基因标签 (参考资源使用 ggrepel 标注 top genes)
3. ❌ 点大小固定 (参考资源按 -log10(P) 调整点大小)
4. ❌ 主题简陋 (theme_minimal 不如 theme_test + 自定义)
5. ❌ 无显著性分层标注 (up/down/non-sig 三态)

---

## 3. 参考资源核心设计模式

### 3.1 基础火山图模板 (简洁通用版)
**文件**: `简洁通用的基础火山图代码_20250826/plot.R`

**核心特征**:
```r
# 1. 三态分类
mutate(trend = case_when(
  log2FC > log2(1.5) & `-log10(P.Value)` > -log10(0.05) ~ "up",
  log2FC < -log2(1.5) & `-log10(P.Value)` > -log10(0.05) ~ "down",
  TRUE ~ "non-sig"))

# 2. 精致配色 (红-蓝-灰)
scale_color_manual(values = c(
  "up" = "#C6295C",      # 酒红色
  "down" = "#2C6DB2",    # 深蓝色
  "non-sig" = "grey"))

# 3. 点大小映射显著性
geom_point(alpha = 0.7, aes(size = `-log10(P.Value)`))
scale_size_continuous(range = c(1, 3))

# 4. ggrepel 智能标注 (top genes)
geom_text_repel(
  data = df %>% filter(P.Value < 0.05, abs(log2FC) > log2(1.5)),
  aes(label = geneID),
  size = 3, segment.size = 0, max.overlaps = 10,
  box.padding = 0.5)

# 5. HTML 风格坐标轴标题 (ggtext)
labs(x = "log<sub>2</sub>(Fold Change)",
     y = "-log<sub>10</sub>(P.Value)")
theme(axis.title = element_markdown())
```

**优势**:
- ✅ 视觉层次分明 (三色系统 + 大小映射)
- ✅ 信息密度高 (自动标注差异基因)
- ✅ 美学符合 Nature 系期刊标准

### 3.2 多分组火山图模板 (高级版)
**文件**: `多分组火山图的系统绘制方法_20251223/plot.R`

**核心特征**:
```r
# 1. 分组背景色块
geom_rect(data = bg_vertical,
          aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
          inherit.aes = FALSE, fill = "grey95")
geom_rect(data = bg_df,
          aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = cluster),
          inherit.aes = FALSE)

# 2. 分组内 top N 标注
label_df <- df %>%
  filter(p_val_adj < 0.05, abs(avg_log2FC) > 1) %>%
  group_by(chr) %>%
  group_modify(~ bind_rows(
    slice_max(.x, avg_log2FC, n = 5),
    slice_min(.x, avg_log2FC, n = 5))) %>%
  ungroup()

# 3. ggprism 主题 (期刊级)
theme_prism(base_line_size = 0.3)
scale_y_continuous(guide = "prism_offset_minor")
```

**适用场景**: 
- 多时间点差异分析
- 多疾病组差异比较
- 多维度物种差异 (bacteria/fungi/virus 并排展示)

---

## 4. 改进方案

### 4.1 立即改进 (Priority 1)
**目标**: 将当前火山图提升到期刊级水准

**实施步骤**:
1. **配色升级**:
   ```r
   # 替换为 Nature 风格配色
   scale_color_manual(values = c(
     "up" = "#C6295C",      # 酒红色 (上调)
     "down" = "#2C6DB2",    # 深蓝色 (下调)
     "non-sig" = "grey70")) # 灰色 (非显著)
   ```

2. **三态分类**:
   ```r
   # 添加显式分类列
   mutate(change = case_when(
     padj < opt$fdr & log2FoldChange > opt$lfc ~ "up",
     padj < opt$fdr & log2FoldChange < -opt$lfc ~ "down",
     TRUE ~ "non-sig"))
   ```

3. **点大小映射**:
   ```r
   # 按显著性调整点大小
   geom_point(aes(size = -log10(padj)), alpha = 0.7)
   scale_size_continuous(range = c(1, 3))
   ```

4. **Top genes 标注**:
   ```r
   # 自动标注 top 10 up + top 10 down
   library(ggrepel)
   top_genes <- res_plot %>%
     filter(sig == TRUE) %>%
     group_by(log2FoldChange > 0) %>%
     slice_max(abs(log2FoldChange), n = 10) %>%
     ungroup()
   
   geom_text_repel(
     data = top_genes,
     aes(label = feature_name),  # 需要从 clade name 提取 species 名
     size = 3, max.overlaps = 20,
     box.padding = 0.5, segment.size = 0.3)
   ```

5. **主题精致化**:
   ```r
   theme_test() +
   theme(
     axis.text = element_text(color = "black", size = 11),
     axis.title = element_text(size = 12, face = "bold"),
     legend.position = c(0.85, 0.85),
     legend.background = element_rect(fill = "white", color = "grey80"),
     panel.grid.major = element_line(color = "grey95"))
   ```

### 4.2 中期优化 (Priority 2)
**目标**: 添加更多可视化类型

1. **差异物种柱状图升级**:
   - 参考: `NC图表复现一图掌握柱状图显著性标记_20250718.rar`
   - 添加显著性星号 (*, **, ***)
   - 添加误差线 (如果有重复样本)
   - 配色与火山图统一

2. **添加棒棒糖图** (Lollipop plot):
   - 更现代的差异物种展示方式
   - 参考: `nature图表复现维恩图与棒棒糖图展示差异基因富集_20250613.rar`
   - 适合展示 top 20 物种

3. **添加哑铃图** (Dumbbell plot):
   - 展示各组丰度差异
   - 参考: `NC图表复现-探索哑铃图进阶用法_20250714.rar`

### 4.3 长期集成 (Priority 3)
**目标**: 构建完整的差异分析可视化套件

1. **多维度整合展示**:
   - 参考: `多分组火山图的系统绘制方法_20251223.rar`
   - 一张图展示 bacteria/fungi/virus 三维度差异
   - 背景色块区分维度

2. **交互式可视化**:
   - 使用 plotly 生成交互式火山图
   - 鼠标悬停显示物种详细信息
   - 可点击跳转到 NCBI/GTDB 数据库

3. **差异分析仪表盘**:
   - 集成所有 5 个方法的结果
   - Venn 图展示方法间一致性
   - 共识物种列表

---

## 5. 技术问题修复计划

### 5.1 ANCOM-BC 修复
**当前错误**: `is.data.frame(df) is not TRUE`

**诊断**:
- ANCOM-BC v2.8.0 返回结果结构变化
- `ancom_out$res` 可能不再是简单的 data.frame

**修复思路**:
```r
# 检查 ancom_out 结构
str(ancom_out)
# 可能需要从 ancom_out$res$lfc_* 等分别提取
# 或使用新版本的 ancombc2() 函数
```

### 5.2 MaAsLin2 修复
**当前错误**: `cannot xtfrm data frames`

**诊断**:
- metadata 中有 data.frame 类型列 (嵌套结构)
- MaAsLin2 期望所有列都是向量

**修复思路**:
```r
# 方案 1: 转换所有列为向量
metadata_maaslin <- metadata %>%
  mutate(across(everything(), as.character)) %>%
  mutate(across(where(is.character), as.factor))

# 方案 2: 只选择需要的列
metadata_maaslin <- metadata %>%
  select(all_of(c("sample_id", opt$group)))
```

### 5.3 MaAsLin3 配置
**状态**: 尚未安装

**安装方案**:
```bash
# 检查是否有 MaAsLin3 (可能尚未正式发布)
conda search maaslin3

# 或从 GitHub 安装开发版
Rscript -e "devtools::install_github('biobakery/Maaslin3')"
```

**集成策略**:
- 保持 MaAsLin2 作为 fallback
- MaAsLin3 作为可选方法 (if available)
- 结果格式统一化处理

### 5.4 Virus 维度适配
**当前错误**: 找不到 `result/virus/metaphlan4/merged_abundance_table.txt`

**根本原因**: virus 使用 vOTU 格式，不是 metaphlan4

**修复方案**:
```r
# 在脚本中添加维度检测
if (opt$dimension == "virus") {
  # Virus: 使用 vOTU 表
  abund_file <- file.path(opt$workdir, "result", "virus", "votu", 
                          "votu_abundance_table.tsv")
  # vOTU 表格式: OTU_ID × samples, 需要转换为 species-like 格式
  # 或直接构建 OTU-level phyloseq
} else {
  # Bacteria/Fungi: 使用 metaphlan4
  abund_file <- file.path(opt$workdir, "result", opt$dimension, 
                          "metaphlan4", "merged_abundance_table.txt")
}
```

**vOTU 特殊处理**:
1. vOTU ID 不含分类学层级 → 跳过 species 筛选
2. taxonomy 表可能缺失 → 使用 vOTU clustering 信息作为伪分类
3. 丰度值可能是 read counts → 需要标准化 (TPM / CPM)

---

## 6. 实施顺序

### Phase 1: 火山图美学升级 (今天完成)
- [ ] 应用 Nature 风格配色
- [ ] 添加点大小映射
- [ ] 集成 ggrepel 标注
- [ ] 主题精致化
- [ ] 重新生成 bacteria + fungi 火山图

### Phase 2: 技术问题修复 (明天)
- [ ] 修复 ANCOM-BC 错误
- [ ] 修复 MaAsLin2 错误
- [ ] 适配 virus 维度 (vOTU)
- [ ] 测试 MaAsLin3 (if available)

### Phase 3: 可视化扩展 (本周)
- [ ] 添加棒棒糖图
- [ ] 差异物种柱状图加显著性标记
- [ ] 多维度整合火山图

### Phase 4: 完整套件 (下周)
- [ ] 交互式可视化
- [ ] 差异分析仪表盘
- [ ] 方法一致性 Venn 图

---

## 7. 可借用的可视化流程清单

### 7.1 立即可用
| 资源包 | 用途 | 优先级 |
|--------|------|--------|
| 简洁通用的基础火山图代码_20250826 | 火山图模板 | ⭐⭐⭐⭐⭐ |
| 多分组火山图的系统绘制方法_20251223 | 三维度整合火山图 | ⭐⭐⭐⭐ |
| NC图表复现一图掌握柱状图显著性标记_20250718 | 差异柱状图 | ⭐⭐⭐⭐ |
| ggplot2绘制炫彩柱状图_20250404 | 柱状图美化 | ⭐⭐⭐ |
| nature图表复现维恩图与棒棒糖图_20250613 | 棒棒糖图 + Venn | ⭐⭐⭐ |

### 7.2 中期参考
| 资源包 | 用途 | 优先级 |
|--------|------|--------|
| microeco包实现Lefse分析_20250908 | LEfSe 集成 | ⭐⭐⭐ |
| 相关性热图的多样化拓展_20250815 | 物种-环境因子热图 | ⭐⭐⭐ |
| NC图表复现_从物种组成到多样性_20250906 | 组成+差异整合 | ⭐⭐⭐ |
| 进阶综合类热图_20250509 | ComplexHeatmap | ⭐⭐ |

### 7.3 高级扩展
| 资源包 | 用途 | 优先级 |
|--------|------|--------|
| Nature同款多层整合的结果总览图_20251102 | 多组学整合 | ⭐⭐ |
| NG图表复现_气泡热图_连线图_20250912 | 物种-功能网络 | ⭐⭐ |
| 环形网络图进阶绘制_20251222 | 物种共现网络 | ⭐⭐ |

---

## 8. 代码模块化设计

### 8.1 核心可视化函数库
**新建文件**: `scripts/R/plot_differential.R`

```r
# 函数 1: Nature 风格火山图
plot_volcano_nature <- function(df, method, fdr = 0.05, lfc = 1.0, top_n = 10) {
  # 实现 Nature 风格火山图
  # 返回 ggplot 对象
}

# 函数 2: 多维度整合火山图
plot_volcano_multi <- function(df_list, dimension_names, colors) {
  # 实现多分组火山图
}

# 函数 3: 差异物种棒棒糖图
plot_lollipop <- function(df, top_n = 20, color_by = "direction") {
  # 实现棒棒糖图
}

# 函数 4: 显著性柱状图
plot_barplot_sig <- function(df, top_n = 20, add_stars = TRUE) {
  # 实现带显著性标记的柱状图
}
```

### 8.2 主脚本调用
**修改**: `scripts/04_differential_abundance.R`

```r
source("scripts/R/plot_differential.R")

# 生成火山图
p_volcano <- plot_volcano_nature(
  results_list$DESeq2,
  method = "DESeq2",
  top_n = 10)
ggsave(file.path(output_dir, "volcano_DESeq2_enhanced.pdf"), p_volcano)

# 生成棒棒糖图
p_lollipop <- plot_lollipop(
  results_list$DESeq2 %>% filter(sig),
  top_n = 20)
ggsave(file.path(output_dir, "lollipop_DESeq2.pdf"), p_lollipop)
```

---

## 9. 参考文献与资源

### 9.1 方法学参考
- DESeq2: Love et al. (2014) Genome Biology
- ANCOM-BC: Lin & Peddada (2020) Nature Communications
- MaAsLin2: Mallick et al. (2021) eLife
- LEfSe: Segata et al. (2011) Genome Biology

### 9.2 可视化参考
- ggplot2: Wickham (2016) Springer
- ggrepel: Slowikowski (2021) CRAN
- ggprism: Charlotte Dawson (2021) CRAN
- ComplexHeatmap: Gu et al. (2016) Bioinformatics

### 9.3 期刊图表风格指南
- Nature Methods 可视化标准
- Nature Communications 图表规范
- Nature Microbiology 微生物组可视化最佳实践

---

**下一步行动**: 
1. 执行 Phase 1 火山图美学升级
2. 解决 ANCOM-BC + MaAsLin2 技术问题
3. 适配 virus 维度 (vOTU 格式)
