# COBRApy — 约束代谢模型分析与 FBA 模拟

**版本**: 0.29.1 | **环境**: `envs/cobrapy` | **脚本**: `scripts/43c_bac_gem_cobrapy_fba.sh`

## 功能
COBRApy (Constraint-Based Reconstruction and Analysis) 是 Python 生态中的标准代谢模型分析工具，用于对 SBML 格式的 GEM（Genome-Scale Metabolic Model）进行约束条件下的通量平衡分析（FBA, Flux Balance Analysis）。支持生长率预测、必需基因识别、底物利用测试、基因/反应敲除分析等核心功能，是代谢工程和系统生物学的基础设施。

**核心分析类型**:
1. **FBA 优化**: 最大化生物量产率，预测生长速率
2. **通量分布导出**: 获取每个反应的代谢通量
3. **必需基因分析**: 单基因敲除测试，识别生存必需基因
4. **底物利用测试**: 测试微生物在不同碳源上的生长能力

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入模型 | `result/gem/{gapseq\|carveme}/{mag_name}/{mag_name}.xml` |
| 输出目录 | `result/gem/fba/{mag_name}/` |
| 生长率 | `result/gem/fba/{mag_name}/{mag_name}_growth_rate.txt` |
| 通量分布 | `result/gem/fba/{mag_name}/{mag_name}_flux_distribution.tsv` |
| 必需基因 | `result/gem/fba/{mag_name}/{mag_name}_essential_genes.tsv` |
| 底物利用 | `result/gem/fba/{mag_name}/{mag_name}_substrate_utilization.tsv` |
| 运行日志 | `result/gem/fba/{mag_name}/fba.log` |

## 数据库（无需单独数据库）
COBRApy 直接读取 SBML 模型文件，无需外部数据库。所需信息（反应化学计量、基因-反应关联、目标函数等）全部包含在模型文件中。

## 关键参数

### FBA 优化
| 参数 | 默认 | 含义 |
|------|------|------|
| `solver` | `glpk` | 线性规划求解器（glpk/cplex/gurobi） |
| `objective` | 自动检测 | 目标函数（通常是生物量反应） |

### 必需基因分析
| 参数 | 默认 | 含义 |
|------|------|------|
| `processes` | 1 | 并行线程数（加速单基因敲除） |
| `method` | `fba` | 敲除评估方法（fba/moma/room） |

### 底物利用测试
| 参数 | 默认 | 含义 |
|------|------|------|
| `substrates` | 预定义列表 | 测试的碳源列表（glucose/acetate/propionate 等） |

## 示例命令

```bash
# 批量 FBA 分析所有已重建的模型
bash scripts/43c_bac_gem_cobrapy_fba.sh -t 8 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 单模型手动运行（调用 Python 脚本）
MAG="bin001"
REPO=~/Course/CSCCD-MetagenomeFlow
MODEL=result/gem/gapseq/${MAG}/${MAG}.xml
OUTDIR=result/gem/fba/${MAG}
mkdir -p ${OUTDIR}

conda run --prefix ${REPO}/envs/cobrapy python3 ${REPO}/scripts/43c_fba_simulate.py \
    --model ${MODEL} \
    --output-dir ${OUTDIR} \
    --threads 8 \
    --substrates glucose,acetate,propionate,butyrate

# 查看生长率
cat ${OUTDIR}/${MAG}_growth_rate.txt

# 查看必需基因数量
wc -l ${OUTDIR}/${MAG}_essential_genes.tsv

# 查看底物利用结果
cat ${OUTDIR}/${MAG}_substrate_utilization.tsv
```

## Python API 示例

```python
import cobra

# 1. 加载模型
model = cobra.io.read_sbml_model('result/gem/gapseq/bin001/bin001.xml')

# 2. 运行 FBA
solution = model.optimize()
print(f"Growth rate: {solution.objective_value:.4f} 1/h")
print(f"Status: {solution.status}")

# 3. 导出通量分布
fluxes = solution.fluxes
fluxes.to_csv('flux_distribution.tsv', sep='\t')

# 4. 必需基因分析
from cobra.flux_analysis import single_gene_deletion
deletion_results = single_gene_deletion(model, model.genes, processes=4)
essential_genes = deletion_results[deletion_results['growth'] < 0.01]
essential_genes.to_csv('essential_genes.tsv', sep='\t', index=False)

# 5. 底物利用测试
substrates = {
    'glucose': 'EX_glc__D_e',
    'acetate': 'EX_ac_e',
    'propionate': 'EX_ppa_e'
}
results = []
for name, rxn_id in substrates.items():
    with model:  # 临时修改，退出后恢复
        # 关闭所有碳源
        for ex in model.exchanges:
            if 'C' in ex.check_mass_balance():
                ex.lower_bound = 0
        # 只开这一个碳源
        model.reactions.get_by_id(rxn_id).lower_bound = -10
        solution = model.optimize()
        results.append((name, solution.objective_value))

for name, growth in results:
    print(f"{name}: {growth:.4f} 1/h")
```

## 输出文件说明

### 1. 生长率 (`_growth_rate.txt`)
```
0.8234
```
单位: 1/h（每小时倍增次数）。典型值：0.5-1.5 (快速生长菌)，0.1-0.5 (慢速生长菌)。

### 2. 通量分布 (`_flux_distribution.tsv`)
```
reaction_id	flux	reaction_name
BIOMASS_Ecoli	0.8234	Biomass objective function
EX_glc__D_e	-10.0	Glucose exchange
EX_o2_e	-18.5	Oxygen exchange
...
```
负值表示消耗，正值表示分泌。

### 3. 必需基因 (`_essential_genes.tsv`)
```
gene_id	growth	status
b0001	0.0	essential
b0002	0.0	essential
...
```
`growth < 0.01` 的基因视为必需基因（敲除后无法生长）。

### 4. 底物利用 (`_substrate_utilization.tsv`)
```
substrate	growth_rate	status
glucose	0.8234	can_grow
acetate	0.3521	can_grow
propionate	0.0	cannot_grow
lactate	0.1102	can_grow
...
```
`growth_rate > 0.01` 表示该碳源可支持生长。

## FBA 理论基础

FBA 基于以下假设：
1. **稳态假设**: 细胞内代谢物浓度不随时间变化（dX/dt = 0）
2. **质量守恒**: 每个代谢物的生成速率 = 消耗速率
3. **目标函数**: 微生物进化目标是最大化生物量合成速率

数学形式：
```
maximize: c^T · v  (生物量反应通量)
subject to: S · v = 0  (化学计量矩阵 × 通量向量 = 0)
            lb ≤ v ≤ ub  (通量上下界约束)
```

其中 S 是 m×n 矩阵（m 个代谢物，n 个反应），v 是通量向量。

## 常见问题

### Q1: FBA 优化失败 "Optimization failed: infeasible"
**原因**: 模型在给定约束下无法合成生物量。  
**排查步骤**:
1. 检查模型是否有目标函数：`model.objective`
2. 检查交换反应边界是否过严（如所有营养物摄取被关闭）
3. 检查模型质量（gapseq fill 步骤是否成功）

**修复**:
```python
# 检查目标函数
print(model.objective)
# 如果为空，手动设置为生物量反应
biomass_rxns = [r for r in model.reactions if 'biomass' in r.id.lower()]
if biomass_rxns:
    model.objective = biomass_rxns[0]
```

### Q2: 必需基因数量异常（太多或太少）
**分析**:
- **太多** (>50%): 模型过于依赖 gap-filling，冗余度不足
- **太少** (<5%): 模型可能有多条旁路途径，或培养基过于丰富

**正常范围**: 原核生物必需基因比例通常 10-20%。

### Q3: 所有底物都显示 "cannot_grow"
**原因**: 底物交换反应 ID 与模型不匹配（gapseq/CarveMe 命名差异）。  
**解决**:
```python
# 列出所有交换反应
for rxn in model.exchanges:
    print(rxn.id, rxn.name)
# 根据实际 ID 修改 substrates 字典
```

### Q4: 如何加速必需基因分析？
**方法**: 增加并行线程数（`--threads` 参数）。  
**性能**:
- 1 线程：~1 分钟/100 基因
- 8 线程：~10 秒/100 基因
- 16 线程：~5 秒/100 基因

**注意**: 线程数 > CPU 核数时收益递减。

### Q5: FBA 预测的生长率与实验值差异很大怎么办？
**原因**: FBA 是理论上限（假设完美优化），实验值受限于：
- 酶动力学限制（FBA 不考虑）
- 基因表达调控（FBA 假设所有酶同时存在）
- 环境压力（pH、温度、渗透压等）

**使用建议**:
- FBA 适合**定性比较**（A 菌能用底物 X，B 菌不能）
- 不适合**定量预测**（预测生长率 = 0.82 ± 0.01 h⁻¹）
- 对于工程改造，关注**相对变化**（敲除后生长率降低 30%）

### Q6: 如何进行双基因/三基因敲除分析？
```python
from cobra.flux_analysis import double_gene_deletion
# 双基因敲除（组合爆炸，慎用）
double_ko = double_gene_deletion(model, model.genes[:50], processes=8)
# 筛选合成致死对（单独敲除可生长，同时敲除致死）
synthetic_lethal = double_ko[
    (double_ko['growth'] < 0.01) & 
    (double_ko['gene1_growth'] > 0.1) & 
    (double_ko['gene2_growth'] > 0.1)
]
```

## 注意事项
- FBA **不模拟时间动力学**，只预测稳态通量分布
- 必需基因结果依赖培养基条件（营养丰富培养基下必需基因更少）
- 底物利用测试假设单一碳源条件（关闭其他碳源摄取）
- COBRApy 0.29+ 要求 Python ≥ 3.8，不兼容 Python 2
- 大规模敲除分析（>1000 基因）建议使用 HPC 集群

## 官方链接
- GitHub: https://github.com/opencobra/cobrapy
- 文档: https://cobrapy.readthedocs.io
- 教程: https://cobrapy.readthedocs.io/en/latest/getting_started.html
- 论文: Ebrahim et al. 2013, BMC Systems Biology 7:74
