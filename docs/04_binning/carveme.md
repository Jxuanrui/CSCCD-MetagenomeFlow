# CarveMe — 快速代谢模型重建

**版本**: 1.6.0 | **环境**: `envs/carveme` | **脚本**: `scripts/43b_bac_gem_carveme.sh`

## 功能
CarveMe 是基于 BiGG Models 数据库的快速代谢模型重建工具，使用全局 BLAST 搜索和通用模板网络，一步生成 SBML 格式的 GEM（Genome-Scale Metabolic Model）。相比 gapseq 的三步法，CarveMe 速度更快（5-10 分钟/MAG），适合高通量筛选和快速原型验证。

**核心特性**:
- 单步构建（无需手动 gap-filling）
- 基于 BiGG Models（人工策展的高质量代谢网络）
- 自动 gap-filling 集成
- 支持细菌、古菌、少数真核生物

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 MAGs | `result/binning/drep/dereplicated_genomes/*.fa` |
| 输出目录 | `result/gem/carveme/{mag_name}/` |
| SBML 模型 | `result/gem/carveme/{mag_name}/{mag_name}.xml` |
| 运行日志 | `result/gem/carveme/{mag_name}/carveme.log` |

## 数据库（内置）
CarveMe 使用 BiGG Models 数据库的通用模板，数据已集成在安装包中（无需单独下载）：
- **BiGG universal model**: ~5000 反应的泛微生物模板
- **DIAMOND DB**: 用于快速序列比对（自动下载至 `~/.carveme/`）

首次运行时自动初始化数据库（~2 分钟）。

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--output` | `{mag_name}.xml` | 输出 SBML 文件路径 |
| `--fbc2` | on | 使用 SBML FBC v2 格式（COBRApy 推荐） |
| `--gapfill` | `auto` | 自动 gap-filling 模式（确保生物量可合成） |
| `--init` | 首次运行 | 初始化/更新 DIAMOND 数据库 |
| `--universe-file` | BiGG universal | 自定义反应库（高级用法） |
| `--mediadb` | `M9` | 培养基条件（M9/LB/rich） |

## 示例命令

```bash
# 批量重建所有 dRep MAGs 的代谢模型
bash scripts/43b_bac_gem_carveme.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 单 MAG 手动运行
MAG="bin001"
REPO=~/Course/CSCCD-MetagenomeFlow
OUTDIR=result/gem/carveme/${MAG}
mkdir -p ${OUTDIR}

# 首次运行（初始化数据库）
conda run --prefix ${REPO}/envs/carveme carve --init

# 构建模型（一步完成）
conda run --prefix ${REPO}/envs/carveme carve \
    --fbc2 \
    --gapfill auto \
    --output ${OUTDIR}/${MAG}.xml \
    result/binning/drep/dereplicated_genomes/${MAG}.fa \
    > ${OUTDIR}/carveme.log 2>&1

# 检查模型统计
grep -E "(reactions|metabolites|genes)" ${OUTDIR}/carveme.log
```

## 输出文件说明

| 文件 | 用途 |
|------|------|
| `{mag_name}.xml` | 最终 SBML 模型（FBC v2 格式，供 FBA 分析） |
| `carveme.log` | 构建日志（反应/代谢物/基因统计） |

## CarveMe vs gapseq

| 特性 | CarveMe | gapseq |
|------|---------|--------|
| 方法论 | 全局 BLAST + 模板网络 | 通路模板 + gap-filling |
| 运行时间 | 快（5-10 分钟/MAG） | 慢（20-50 分钟/MAG） |
| 生物学可解释性 | 中（直接基于 BiGG） | 高（通路完整性评分） |
| 模型质量 | 反应覆盖广 | 通路连贯性好 |
| 数据库 | BiGG Models | KEGG |
| Gap-filling | 自动集成 | 手动三步法 |
| 推荐场景 | **快速筛选、高通量** | 研究级、需要通路解释 |

## 常见问题

### Q1: 首次运行报错 "DIAMOND database not found"
**原因**: 数据库未初始化。  
**解决**:
```bash
conda run --prefix envs/carveme carve --init
```

### Q2: 构建失败 "No genes found in FASTA"
**原因**: 输入文件格式错误或 FASTA 文件为空。  
**解决**:
1. 确认 MAG 文件是核苷酸序列（非蛋白）
2. 检查 FASTA 格式（每个序列必须有 `>` 开头的头行）
3. 确认基因组大小 > 500 kb（过小的 MAG 可能失败）

### Q3: 如何使用不同的培养基条件？
**方法**: CarveMe 支持预定义培养基模板（M9/LB/rich）或自定义：
```bash
# 使用 LB 培养基
carve --mediadb LB --output model.xml genome.fa

# 自定义培养基（需先定义 JSON 格式的培养基文件）
carve --mediadb custom_media.json --output model.xml genome.fa
```

### Q4: 模型中反应数太少/太多怎么办？
**分析**:
- **太少** (<500): 基因组质量差或物种特殊（如共生菌、胞内寄生菌）
- **太多** (>3000): 可能包含假阳性反应，考虑提高 BLAST e-value 阈值
  
**调整**:
```bash
# 提高 e-value 阈值（减少假阳性，仅保留高置信度反应）
carve --evalue 1e-30 --output model.xml genome.fa
```

### Q5: CarveMe 和 gapseq 模型能否合并使用？
**答案**: 不推荐直接合并（数据库/命名空间不同）。  
**最佳实践**:
1. 两种方法都运行，产生两个模型
2. 用 FBA 对比生长预测的一致性
3. 对不一致的代谢能力，查阅文献确认
4. 选择其中一个作为下游分析的主模型

### Q6: 如何查看模型包含了哪些反应？
```python
# 使用 COBRApy 解析 SBML
import cobra
model = cobra.io.read_sbml_model('result/gem/carveme/bin001/bin001.xml')
print(f"Reactions: {len(model.reactions)}")
print(f"Metabolites: {len(model.metabolites)}")
print(f"Genes: {len(model.genes)}")

# 查看前 10 个反应
for rxn in model.reactions[:10]:
    print(f"{rxn.id}: {rxn.reaction}")
```

## 注意事项
- CarveMe **主要支持原核生物**，真核支持有限（少数酵母模型）
- 基因组质量要求：完整性 ≥ 60%，污染 ≤ 10%（比 gapseq 宽松）
- 输出的 SBML 文件默认使用 BiGG 命名空间（反应 ID 格式如 `EX_glc__D_e`）
- Gap-filling 是黑盒自动过程，无法像 gapseq 那样手动控制填补策略
- 对于需要严格通路解释的研究（如代谢工程），建议优先用 gapseq

## 官方链接
- GitHub: https://github.com/cdanielmachado/carveme
- 文档: https://carveme.readthedocs.io
- 论文: Machado et al. 2018, Nucleic Acids Research 46:D723-D728
