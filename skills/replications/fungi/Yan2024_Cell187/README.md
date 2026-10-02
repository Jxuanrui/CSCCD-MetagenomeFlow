---
# Yan et al. 2024, Cell 187 — 肠道真菌图谱：方法复现技能包

**PMID**: 38307030 | **DOI**: 10.1016/j.cell.2024.01.034 | **IF**: 45.5

## 核心贡献

760个培养肠道真菌基因组（CGF + PHF）→ 构建第一个综合肠道真菌基因目录 → Singular/Escrow算法实现核酸水平精准丰度定量。

## 与本项目的对应关系

| 论文步骤 | 项目脚本 | 保真度 |
|----------|----------|--------|
| Database construction (760 genomes) | `74a_fun_gut_db_build.sh` | ✅ 高 |
| 5-step Bowtie2 filter + mapping | `74e_fun_phf_profiler.sh` | ✅ 高（完全对应） |
| Singular/Escrow abundance (GPA.py) | `74e_fun_phf_profiler.sh` | ✅ 高（identity=0.95, k=1000） |
| Abundance matrix + taxonomy join | `74f_fun_phf_aggregate.sh` | ✅ 高 |
| SMGC annotation | ❌ 缺口（antiSMASH fungi mode） | — |
| Cross-kingdom co-occurrence | ❌ 缺口（Fig5路线） | — |

## 数据库资源

- `db/gut_fungi_db/db.fungi.fa.gz` — 真菌基因集（760基因组，1.3G gz）
- `db/gut_fungi_db/db.fungi.taxonomy.tsv` — 317簇7级分类注释
- `db/gut_fungi_db/GPA.py` — Singular/Escrow丰度计算器（原作者提供）
- `Reference/Gut_Fungi_DB/` — 原始参考资料（原作者百度网盘资源）

## 原作者代码

- **原始代码**: `code/original/` (git clone from GitHub，不修改)
- **适配版本**: `code/adapted/profiling/` — 路径变量化，`${PROJ_DIR}` 替换硬编码路径
- 关键文件：`GPA.py`（Singular/Escrow核心），`flow_fungi.map.sh`（5步过滤流程）

## 快速运行

```bash
# 前置：建索引（一次性，约3-5小时）
bash scripts/74a_fun_gut_db_build.sh -t 16 -r ~/Course/CSCCD-MetagenomeFlow

# Per-sample 真菌丰度定量
bash scripts/74e_fun_phf_profiler.sh \
    -s SAMPLE_ID -t 16 \
    -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \
    -r ~/Course/CSCCD-MetagenomeFlow

# 多样本聚合
bash scripts/74f_fun_phf_aggregate.sh \
    -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \
    -r ~/Course/CSCCD-MetagenomeFlow
```

## 验证

```bash
bash skills/replications/fungi/Yan2024_Cell187/validate.sh ~/Course/CSCCD-MetagenomeFlow
```

## 未实现的缺口

1. **SMGC annotation** (低优先级) — antiSMASH fungi mode，需要完整基因组作为输入
2. **Cross-kingdom co-occurrence** (中优先级) — 需要同批样本的细菌+真菌丰度数据

## RAG 关键词

`gut mycobiome`, `cultivated gut fungi`, `PHF`, `CGF`, `Singular/Escrow`, `Bowtie2 profiling`, `GPA.py`, `genus-level abundance`, `IBD mycobiome`, `760 fungal genomes`
