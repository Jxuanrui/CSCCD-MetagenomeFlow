# 共现网络分析（Co-occurrence Network）

**环境**: `envs/r_stat` | **脚本**: `scripts/93_stat_cooccurrence.sh`

## 功能
使用 `MetaNet` 组件化 API（`c_net_cal` → `c_net_build` → `c_net_annotate` → `module_detect` → `c_net_layout` → `c_net_plot`）计算跨维度微生物共现网络，支持细菌、病毒、真菌的单维度网络和跨维度（细菌-病毒、细菌-真菌，通过 `MetaNet::multi_net_build()` 构建）混合网络。分组比较仍使用 NetCoMi（`netConstruct`/`netAnalyze`/`netCompare`，底层用 SpiecEasi/FastSpar 计算分组内相关性）。输出网络节点/边表、网络可视化图和 NetCoMi 分组比较结果。

**2026-07-04 迁移说明**：此前使用 `ggClusterNet` 做网络布局，但该包存在无法规避的缺陷（`network()` 内部缺少 `%>%`/`E()` 的 NAMESPACE 导入；默认 `cluster_fast_greedy` 聚类在混合正负相关边时崩溃 `Negative weight in weight vector`，在该包自带的 `ps16s` 示例数据上均可复现）。现已完全移除 `ggClusterNet` 依赖，网络构建/绘图统一改用 `MetaNet`。

## 用法

```bash
# 全网络类型（默认）
bash scripts/93_stat_cooccurrence.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv

# 仅细菌维度
bash scripts/93_stat_cooccurrence.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -n bac

# 跨维度细菌-病毒
bash scripts/93_stat_cooccurrence.sh \
    -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
    -m metadata.csv -n cross_bac_vir
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-w` | 是 | — | 工作目录 |
| `-r` | 是 | — | 项目根目录 |
| `-t` | 是 | — | 线程数 |
| `-m` | 是 | — | 元数据 CSV |
| `-g` | 否 | — | 分组列（NetCoMi 比较用） |
| `-n` | 否 | all | 网络类型（bac/vir/fun/cross_bac_vir/cross_bac_fun/all） |

## 输入

| 维度 | 路径 |
|------|------|
| 细菌 | `result/metaphlan4/merged/taxonomy.tsv` |
| 病毒 | `result/virus/votu/table/vOTU_table_ann.txt` |
| 真菌 | `result/fungi/metaphlan4/{sample}/*_profile.txt` |

## 输出

| 文件 | 内容 |
|------|------|
| `network/{bacteria,virus,fungi,cross_bac_vir,cross_bac_fun}/nodes.tsv` | 节点属性（`MetaNet::get_v()`：name/v_group/v_class/color/module/度/完整 taxonomy 各级） |
| `network/{bacteria,virus,fungi,cross_bac_vir,cross_bac_fun}/edges.tsv` | 边属性（`MetaNet::get_e()`：from/to/weight/cor/p.value/e_type/e_class） |
| `network/{bacteria,virus,fungi,cross_bac_vir,cross_bac_fun}/network.{svg,pdf,tiff}` | 网络可视化图（`MetaNet::c_net_plot()` 输出，600dpi 出版格式） |
| `network/{bacteria,virus,fungi,cross_bac_vir,cross_bac_fun}/group_compare.txt` | 分组比较结果（若提供 -g，NetCoMi `netCompare`） |
| `network_summary.tsv` | 所有网络统计汇总 |

## 网络推断方法

单维度网络：`MetaNet::c_net_cal(method="spearman")` → `c_net_build(r_threshold=0.3, p_threshold=0.05)`。
跨维度网络：`MetaNet::multi_net_build(mode="full", method="spearman", r_threshold=0.3, p_threshold=0.05)`，自动按输入列表命名标记节点所属组学域（`v_group`）及边的 `e_class`（`intra`/`inter`）。
模块检测统一使用 `MetaNet::module_detect(method="cluster_fast_greedy")`（内部对权重取绝对值，混合正负相关边不会崩溃）。
分组比较（NetCoMi）内部相关性计算仍按特征数分档：≤200 用 SpiecEasi(SparCC)，>200 用 FastSpar（系统命令行，更快）。

## 注意事项
- 特征过滤：保留存在率 ≥10% 的特征；最多保留 Top 300 特征
- 跨维度网络不再使用 `BAC|`/`VIR|`/`FUN|` 字符串前缀拼接，改为 `MetaNet::multi_net_build()` 按命名列表自动打标签（`v_group`/`v_class`）
- 病毒摄取已修复为通过 `result/virus/votu/vclust/clusters.tsv` 做 CDS→vOTU 代表序列聚合（与 `91_diversity.R::build_mt_virus()` 逻辑一致），不再把每条 CDS 当作独立节点
- 三域摄取统一输出 `list(mat, tax)` 结构：taxon×sample 丰度矩阵 + 长格式 taxonomy 表（列：name/Kingdom/Phylum/Class/Order/Family/Genus/Species）
- 节点/边配色统一使用 NPG 出版配色（`npg_pal()`），边正负相关分别为 `#4DBBD5`/`#F39B7F`，覆盖 MetaNet 默认配色

## R 依赖包
`MetaNet`, `SpiecEasi`, `NetCoMi`, `igraph`, `phyloseq`, `tidyverse`, `svglite`, `ragg`
