# FeGenie 铁代谢基因预测使用说明

## 工具概述

**FeGenie** (Feature-based Gene Identification for Iron-related metabolism) 是专门用于预测微生物铁代谢相关基因的工具。

- **版本**: 1.2
- **环境**: `envs/fegenie` (Python 3.13, hmmer 3.4, prodigal 2.6.3)
- **HMM 数据库**: 内嵌于 `envs/fegenie/share/fegenie-1.2/hmms/iron/`
- **参考文献**: Garber et al. 2020 *Frontiers in Microbiology*
- **官网**: https://github.com/Arkadiy-Garber/FeGenie

---

## 功能类别（10 类）

| 类别 | 描述 | 肠道微生物研究意义 |
|------|------|-------------------|
| **Siderophore synthesis** | 铁载体合成（如 enterobactin, vibriobactin） | 肠道菌与宿主竞争铁资源的主要策略 |
| **Siderophore transport** | 铁载体转运（TonB-dependent receptors） | 摄取铁载体-铁复合物进入细胞 |
| **Heme transport** | 血红素转运 | 利用宿主血红素作为铁源（致病菌关键） |
| **Heme oxygenase** | 血红素分解酶 | 从血红素中释放游离铁 |
| **Iron transport** | 铁直接转运（FeoAB, FbpABC） | 厌氧肠道环境中的 Fe²⁺ 转运 |
| **Iron oxidation** | 铁氧化（Cyc2, MtoA） | 氧化 Fe²⁺ → Fe³⁺ 用于能量代谢 |
| **Iron reduction** | 铁还原（Ndh2, Cyc2） | 还原 Fe³⁺ → Fe²⁺ 用于呼吸链 |
| **Iron storage** | 铁储存（Ferritin, Bfr） | 细胞内铁库，应对铁波动 |
| **Iron gene regulation** | 铁调控（Fur, DtxR, IdeR） | 感应铁浓度，调控铁代谢基因表达 |
| **Magnetosome formation** | 磁小体形成 | 肠道菌较少见（趋磁细菌特有） |

---

## 输入输出

### 输入
- **Per-sample 模式**（推荐）：`result/assembly/prodigal/{SAMPLE}/{SAMPLE}.faa`（蛋白预测文件）
- **NR 模式**：`result/assembly/cdhit/protein_nr.fa`（去冗余蛋白集，适合 MAG-level 分析）

### 输出目录结构
```
result/annotation/fegenie/{SAMPLE}/
├── FeGenie-geneSummary.csv           — 主结果（基因级注释 + 功能类别）
├── FeGenie-geneSummary-clusters.csv  — 基因簇级汇总
├── FeGenie-heatmap-data.csv          — 热图格式（样本×功能矩阵）
├── HMM_results/                      — 原始 hmmsearch 输出
│   ├── iron_reduction.tbl
│   ├── iron_aquisition-siderophore_synthesis.tbl
│   └── ...（共 10 个功能类别）
└── ORF_calls/                        — Prodigal 预测（如使用 --orfs 选项）
```

---

## 输出文件解读

### 1. FeGenie-geneSummary.csv（主结果）

**示例行**：
```csv
category,genome/assembly,orf,HMM,bitscore,bitscore_cutoff,clusterID,heme_c_binding_motifs,protein_sequence
iron_reduction,S02.faa,k127_415_1,Ndh2,87.8,40,10,0,FPPLIYQIASAGIDPS...
```

**字段说明**：
- `category`: 功能类别（10 类之一）
- `genome/assembly`: 样本名（如 S02.faa）
- `orf`: 基因 ID（来自 Prodigal，格式 `{contig}_{gene_num}`）
- `HMM`: 命中的 HMM 模型名（如 Ndh2 = NADH 脱氢酶 II，铁还原相关）
- `bitscore`: HMM 比对得分（越高越可信）
- `bitscore_cutoff`: 阈值（默认 40，gathering cutoff）
- `clusterID`: 基因簇编号（用于追踪基因组岛）
- `heme_c_binding_motifs`: c-型血红素结合基序数量（0 表示非细胞色素）
- `protein_sequence`: 蛋白序列

---

### 2. FeGenie-heatmap-data.csv（样本间比较）

**格式**（行=样本，列=功能类别）：
```csv
sample,iron_reduction,iron_oxidation,siderophore_synthesis,...
S01.faa,0,0,2,...
S02.faa,1,0,0,...
```

**用途**：
- 可视化样本间铁代谢功能差异
- 结合宿主表型（如贫血、炎症）做关联分析
- 与 Salmon TPM 结合，量化功能基因的表达丰度

---

## 使用示例

### 单样本运行
```bash
bash scripts/31e_bac_fegenie.sh -s S01 -t 8 \
     -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \
     -r ~/Course/CSCCD-MetagenomeFlow
```

### 批量运行（6 个样本，2 并发）
```bash
cat Project/Project_example/samplesheet.csv | grep -v "^sample" | cut -d',' -f1 | \
rush -j 2 'bash scripts/31e_bac_fegenie.sh -s {} -t 8 \
     -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \
     -r ~/Course/CSCCD-MetagenomeFlow'
```

### NR 模式（MAG-level，单次运行）
```bash
bash scripts/31e_bac_fegenie.sh -s NR -t 16 \
     -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \
     -r ~/Course/CSCCD-MetagenomeFlow --input-type nr
```

---

## 下游分析建议

### 1. 铁代谢功能丰度定量
结合 Salmon TPM（步骤 20）：
```R
# 读取 FeGenie 结果
fegenie <- read.csv("result/annotation/fegenie/S01/FeGenie-geneSummary.csv")

# 读取 Salmon 基因丰度
salmon <- read.table("result/assembly/salmon_quant/S01/quant.sf", header=T)

# 合并（按基因 ID）
merged <- merge(fegenie, salmon, by.x="orf", by.y="Name")

# 计算各功能类别的 TPM 总和
aggregate(TPM ~ category, data=merged, sum)
```

### 2. 宿主-菌群铁竞争分析
**场景**：肠道炎症（IBD）患者 vs 健康对照
- **假设**：炎症期间宿主释放 lactoferrin（铁螯合蛋白），限制游离铁
- **预期**：IBD 患者肠道菌群中 **siderophore synthesis/transport** 基因丰度↑
- **验证**：
  1. FeGenie 定量各样本的 siderophore 基因数量
  2. 与宿主血清铁蛋白（ferritin）水平做相关分析
  3. 结合 MetaPhlAn4 物种组成，看哪些菌种贡献了 siderophore 基因

### 3. 铁代谢与 ARG 共定位
**背景**：铁获取基因与抗生素耐药基因常共定位于质粒/整合子上
```bash
# 1. 提取铁代谢基因所在 contig
awk -F',' 'NR>1 {print $3}' result/annotation/fegenie/S01/FeGenie-geneSummary.csv | \
    sed 's/_[0-9]*$//' | sort -u > iron_contigs.txt

# 2. 与 AMRFinder 结果对比（步骤 23）
grep -f iron_contigs.txt result/annotation/amrfinder/S01/amr_hits.txt

# 3. 与 PlasmidFinder 结果交叉（步骤 24）
grep -f iron_contigs.txt result/mge/plasmidfinder/S01/results_tab.tsv
```

### 4. 铁代谢功能网络
**构建基因共现网络**：
- 节点 = 铁代谢基因（FeGenie）+ 代谢通路基因（KEGG KO）
- 边 = 基因丰度相关性（Spearman ρ > 0.6, p < 0.05）
- 识别铁代谢核心模块（如 siderophore synthesis + TonB-dependent receptor 共现簇）

---

## 常见问题

### Q1: FeGenie 检测到 0 个基因？
**可能原因**：
1. 测序深度不足（Project_example 仅为示例数据）
2. 样本中真菌/真核生物占主导（FeGenie 仅针对细菌/古菌）
3. 宿主污染较高（步骤 02 kneaddata 未充分去除）

**解决方案**：
- 检查 MetaPhlAn4 物种组成（步骤 11），确认细菌丰度
- 查看 Prodigal 预测基因数（`wc -l result/assembly/prodigal/{SAMPLE}/{SAMPLE}.faa`）
- 对于高质量真实数据（>10 Gb clean reads），通常能检测到 50-200 个铁代谢基因

### Q2: FeGenie 运行时间过长？
**典型耗时**（依赖基因数量）：
- 小样本（<1000 基因）：~5 分钟
- 中等样本（5000-10000 基因）：~20 分钟
- 大样本（>20000 基因）：~1 小时

**加速策略**：
- 增加线程数（`-t 16`）
- 使用 NR 模式（MAG-level，只运行一次）

### Q3: 与 eggNOG/KEGG 的注释有何区别？
| 维度 | eggNOG/KEGG | FeGenie |
|------|-------------|---------|
| 覆盖范围 | 全功能（代谢/信号/转录...） | 仅铁代谢（10 类） |
| 分类粒度 | KO 级别（如 K02013 = iron transport） | 亚型级别（如区分 FeoAB / FbpABC） |
| 铁氧化还原 | 缺失（需人工筛选 KO） | 明确分类（Cyc2 / MtoA 等） |
| 样本级汇总 | 需自行统计 | 内置 heatmap 矩阵 |

**推荐策略**：
- **通用注释**：eggNOG（步骤 21）+ KEGG（步骤 22）
- **铁代谢深度分析**：FeGenie（本步骤）
- **互补验证**：FeGenie 识别的铁基因可用 eggNOG 的 COG 分类交叉验证

---

## 参考文献

1. Garber AI, et al. (2020). FeGenie: A comprehensive tool for the identification of iron genes and iron gene neighborhoods in genome and metagenome assemblies. *Frontiers in Microbiology*, 11:37.
2. Andrews SC, et al. (2003). Bacterial iron homeostasis. *FEMS Microbiology Reviews*, 27(2-3):215-237.
3. Kortman GAM, et al. (2014). Iron availability increases the pathogenic potential of Salmonella typhimurium and other enteric pathogens at the intestinal epithelium. *PLoS ONE*, 9(11):e112445.

---

## 脚本路径

- **主脚本**: `scripts/31e_bac_fegenie.sh`
- **Conda 环境**: `envs/fegenie`
- **HMM 数据库**: `envs/fegenie/share/fegenie-1.2/hmms/iron/`
- **安装文档**: `0Install.sh` §15.4
