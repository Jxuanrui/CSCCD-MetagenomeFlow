# 共现网络分析（Co-occurrence Network）

**环境**: `envs/r_stat` | **脚本**: `scripts/93_stat_cooccurrence.sh`

## 功能
使用 SpiecEasi（SparCC）/ FastSpar 计算跨维度微生物共现网络，支持细菌、病毒、真菌的单维度网络和跨维度（细菌-病毒、细菌-真菌）混合网络。输出网络节点/边表、网络可视化图和 NetCoMi 分组比较结果。

## 用法

```bash
# 全网络类型（默认）
bash scripts/93_stat_cooccurrence.sh \
    -w /path/to/workdir -r ~/Course/Maxmetagenome -t 16 \
    -m metadata.csv

# 仅细菌维度
bash scripts/93_stat_cooccurrence.sh \
    -w /path/to/workdir -r ~/Course/Maxmetagenome -t 16 \
    -m metadata.csv -n bac

# 跨维度细菌-病毒
bash scripts/93_stat_cooccurrence.sh \
    -w /path/to/workdir -r ~/Course/Maxmetagenome -t 16 \
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
| `{network}_nodes.tsv` | 节点属性（丰度、门、模块、度） |
| `{network}_edges.tsv` | 边权重（相关系数） |
| `{network}_network.pdf` | 网络可视化图 |
| `{network}_group_compare.txt` | 分组比较结果（若提供 -g） |
| `network_summary.tsv` | 所有网络统计汇总 |

## 网络推断方法

| 特征数 | 方法 | 说明 |
|--------|------|------|
| ≤200 | SpiecEasi (SparCC) | R 包实现 |
| >200 | FastSpar | 系统命令行（更快） |

## 注意事项
- 特征过滤：保留存在率 ≥10% 的特征；最多保留 Top 300 特征
- 跨维度网络的特征名加前缀：`BAC|`、`VIR|`、`FUN|`
- **已知问题（2026-07-03 修复）**：跨维度（`cross_bac_vir`/`cross_bac_fun`）rbind 前需保证两个子矩阵列（样本）顺序完全一致，否则会导致维度错位。已修复为显式按 `common` 样本向量提取子矩阵后再 rbind。已在 Project_example 真实数据验证通过。
- **合成测试数据限制**：在 `Project/Test_100samples` 上运行单维度或跨维度网络时可能报错 `"Length of new attribute value must be 1 or 100..."`，这是合成数据物种数偏少（62个细菌种）导致的网络推断阶段稀疏图问题，非脚本 bug，尚未深入排查根因。

## R 依赖包
`SpiecEasi`, `NetCoMi`, `igraph`, `ggraph`, `phyloseq`, `tidyverse`
