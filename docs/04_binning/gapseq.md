# gapseq — 基于通路的基因组规模代谢模型重建

**版本**: 1.3 | **环境**: `envs/gapseq` | **脚本**: `scripts/43_bac_gem_gapseq.sh`

## 功能
gapseq 是专为原核生物（细菌/古菌）设计的代谢模型重建工具，基于 KEGG 反应数据库和代谢通路模板，通过三步法（find → draft → fill）自动从基因组序列构建高质量 SBML 格式的 GEM（Genome-Scale Metabolic Model）。相比 CarveMe，gapseq 更注重通路完整性验证和生物学可解释性，适合研究级代谢能力预测。

**三步工作流**:
1. **find**: 通路预测（pathway prediction） — 从基因组中识别完整/不完整的代谢通路
2. **draft**: 模型构建（model construction） — 基于通路数据生成初始 SBML 模型
3. **fill**: 缺口填补（gap-filling） — 通过比较基因组学补全模型缺口，确保生物量合成可行

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 MAGs | `result/binning/drep/dereplicated_genomes/*.fa` |
| 输出目录 | `result/gem/gapseq/{mag_name}/` |
| 通路预测结果 | `result/gem/gapseq/{mag_name}/{mag_name}-Pathways.tbl` |
| 反应权重 | `result/gem/gapseq/{mag_name}/{mag_name}-rxnWeights.RDS` |
| 基因-反应映射 | `result/gem/gapseq/{mag_name}/{mag_name}-rxnXgenes.RDS` |
| 初始模型（draft） | `result/gem/gapseq/{mag_name}/{mag_name}-draft.RDS` |
| 最终模型（SBML） | `result/gem/gapseq/{mag_name}/{mag_name}.xml` |
| 运行日志 | `result/gem/gapseq/{mag_name}/gapseq.log` |

## 数据库（自动管理）
gapseq 首次运行时自动下载数据库至 `~/.gapseq/` 目录：
- **seq-DBs**: 序列同源性数据库（~8 GB）
- **dat-files**: KEGG 反应/化合物/通路定义（~500 MB）

无需手动干预，首次下载后自动缓存。

## 关键参数

### find 阶段（通路预测）
| 参数 | 默认 | 含义 |
|------|------|------|
| `-p all` | — | 预测所有代谢通路（不限定类别） |
| `-b 200` | 100 | BLAST bit score 阈值（提高可减少假阳性） |
| `-m Bacteria` | — | 指定域（Bacteria/Archaea） |

### draft 阶段（模型构建）
| 参数 | 默认 | 含义 |
|------|------|------|
| `-r {mag_name}-Pathways.tbl` | — | 输入通路表 |
| `-p {mag_name}-Pathways.tbl` | — | 同时提供通路表（必需） |
| `-c {mag_name}` | — | 输出模型文件前缀 |

### fill 阶段（缺口填补）
| 参数 | 默认 | 含义 |
|------|------|------|
| `-m {mag_name}-draft.RDS` | — | 输入初始模型 |
| `-n medium` | — | 培养基条件（minimal/medium/rich） |
| `-c {mag_name}-rxnWeights.RDS` | — | 反应权重（优先选择有基因支持的反应） |
| `-g {mag_name}-rxnXgenes.RDS` | — | 基因-反应映射 |
| `-b 100` | 100 | 最大填补反应数（防止过度填补） |

## 示例命令

```bash
# 批量重建所有 dRep MAGs 的代谢模型
bash scripts/43_bac_gem_gapseq.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 单 MAG 手动运行（三步法）
MAG="bin001"
REPO=~/Course/CSCCD-MetagenomeFlow
OUTDIR=result/gem/gapseq/${MAG}
mkdir -p ${OUTDIR}

# Step 1: 通路预测（最耗时，10-30 分钟）
conda run --prefix ${REPO}/envs/gapseq gapseq find \
    -p all -b 200 -m Bacteria \
    -o ${OUTDIR}/${MAG} \
    result/binning/drep/dereplicated_genomes/${MAG}.fa

# Step 2: 模型构建（2-5 分钟）
conda run --prefix ${REPO}/envs/gapseq gapseq draft \
    -r ${OUTDIR}/${MAG}-Pathways.tbl \
    -p ${OUTDIR}/${MAG}-Pathways.tbl \
    -c ${OUTDIR}/${MAG}

# Step 3: 缺口填补（5-15 分钟）
conda run --prefix ${REPO}/envs/gapseq gapseq fill \
    -m ${OUTDIR}/${MAG}-draft.RDS \
    -n medium \
    -c ${OUTDIR}/${MAG}-rxnWeights.RDS \
    -g ${OUTDIR}/${MAG}-rxnXgenes.RDS \
    -b 100

# Step 4: RDS → SBML 转换（R 脚本）
Rscript -e "
library(sybil)
mod <- readRDS('${OUTDIR}/${MAG}-draft.RDS')
writeSBMLmod(mod, '${OUTDIR}/${MAG}.xml')
"

# 检查模型统计
grep -E "(Reactions|Metabolites|Genes)" ${OUTDIR}/gapseq.log
```

## 输出文件说明

| 文件 | 用途 |
|------|------|
| `{mag_name}.xml` | 最终 SBML 模型（供 FBA 分析使用） |
| `{mag_name}-Pathways.tbl` | 识别的代谢通路列表（完整性评分） |
| `{mag_name}-draft.RDS` | R 格式模型对象（可在 R 中加载分析） |
| `{mag_name}-rxnWeights.RDS` | 反应权重（基因支持度） |
| `{mag_name}-rxnXgenes.RDS` | 基因-反应映射表 |

## gapseq vs CarveMe

| 特性 | gapseq | CarveMe |
|------|--------|---------|
| 方法论 | 通路模板 + gap-filling | 全局 BLAST + 模板网络 |
| 生物学可解释性 | 高（通路完整性评分） | 中（直接基于 BiGG） |
| 运行时间 | 慢（20-50 分钟/MAG） | 快（5-10 分钟/MAG） |
| 模型质量 | 通路连贯性好 | 反应覆盖广 |
| 数据库 | KEGG | BiGG Models |
| 推荐场景 | **研究级、需要通路解释** | 快速筛选、高通量 |

## 常见问题

### Q1: find 步骤运行很慢（>30 分钟）
**原因**: 全通路预测需要大量 BLAST/HMMER 搜索。  
**解决**: 正常现象，首次运行需下载数据库。可选择只预测特定通路（`-p amino_acid,carbohydrate` 等）或直接使用 CarveMe。

### Q2: fill 步骤报错 "gap-filling failed"
**原因**: 初始模型缺陷太多，无法在约束条件下填补。  
**解决**:
1. 检查基因组质量（完整性 < 70% 可能失败）
2. 放宽培养基条件（`-n rich` 替代 `medium`）
3. 增加最大填补反应数（`-b 200`）

### Q3: SBML 文件没有生成
**原因**: R 脚本的 `sybil` 库未正确安装。  
**解决**:
```bash
# 在 gapseq 环境中补装 sybil
conda run --prefix envs/gapseq R -e "install.packages('sybil', repos='https://cran.r-project.org')"
```

### Q4: 如何查看模型包含了哪些通路？
```bash
# 解析 Pathways.tbl
awk -F'\t' 'NR>1 && $3 >= 0.66 {print $1, $2, $3}' \
    result/gem/gapseq/bin001/bin001-Pathways.tbl
# $3 是完整性评分（0-1），≥0.66 表示通路基本完整
```

## 注意事项
- gapseq **仅支持原核生物**，真核生物需用其他工具（如 KEGGtranslator）
- 基因组质量要求：完整性 ≥ 70%，污染 ≤ 5%（更严格于一般 MAG 标准）
- 输出的 RDS 文件只能在 R 中加载，跨语言分析需使用 SBML 格式
- 通路完整性评分 < 0.5 的通路可能缺失关键酶，需人工审核

## 官方链接
- GitHub: https://github.com/jotech/gapseq
- 文档: https://gapseq.readthedocs.io
- 论文: Zimmermann et al. 2021, Genome Biology 22:81
