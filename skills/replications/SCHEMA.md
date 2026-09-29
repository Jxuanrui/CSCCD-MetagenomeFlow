# Skills/Replications — Skill Package Schema

> 融合标准：nf-core meta.yml 2025 + xKG节点分类 + MCP inputSchema + RO-Crate provenance
> 每个技能包 = 一篇高分文献的可执行知识单元

## 目录结构

```
skills/replications/
  registry.yaml                        ← 全局索引（所有技能包摘要）
  SCHEMA.md                            ← 本文件，格式规范
  fungi/
    Yan2024_Cell187/
      manifest.yaml                    ← 元数据（必须）
      method_graph.yaml                ← 分析 DAG（必须）
      params.yaml                      ← 文献推荐参数（必须）
      validate.sh                      ← 可运行的验证命令（必须）
      README.md                        ← 方法摘要，供 RAG 索引（必须）
      code/
        original/                      ← 原作者代码，不修改
        adapted/                       ← 项目适配版本
  bacteria/
  virome/
  statistics/
```

## manifest.yaml 字段规范

```yaml
# ── 文献标识（RO-Crate provenance 层）──────────────────────────
id: "Yan2024_Cell187"                  # 唯一标识：作者年份_期刊卷号
pmid: "38307030"                       # PubMed ID（可选）
doi: "10.1016/j.cell.2024.01.034"      # DOI（必须）
title: "A cultivated gut fungal catalog..."  # 完整标题（必须）
journal: "Cell"                        # 期刊名（必须）
year: 2024                             # 发表年份（必须）
impact_factor: 45.5                    # 影响因子（可选）
paper_type: "application_paper"        # 必须：tool_paper | benchmark_paper | application_paper | review
primary_dimension: fungi               # 必须：fungi | bacteria | virome | statistics | multiomics
cross_dimensions: []                   # 必须：跨维度引用列表，如 [bacteria, statistics]
citation_in_scripts: [74a, 74e, 74f]  # 必须：本文献方法对应的项目脚本编号

# ── 代码可用性（ARTS框架）──────────────────────────────────────
code_availability:
  github: "https://github.com/yexianingyue/Cultivated-Gut-Fungi"
  zenodo: null
  local_path: "skills/replications/fungi/Yan2024_Cell187/code/"

# ── 复现状态（PaperBench rubric四维）────────────────────────────
replication:
  replicated_by: "JiXuanRui"
  replicated_date: "2026-06-15"
  data_accessibility: "partial"        # full | partial | none
  code_accessibility: "partial"        # full | partial | none
  environment_reproducibility: "high"  # high | medium | low
  result_verifiability: "medium"       # high | medium | low
  method_fidelity: "high"             # high | medium | low

# ── 项目覆盖度 ──────────────────────────────────────────────────
coverage:
  implemented: [74a, 74e, 74f]        # 已对应的项目脚本
  new_scripts: []                      # 本次新增脚本
  gaps:
    - name: "SMGC annotation"
      reason: "antiSMASH fungi mode not integrated"
      priority: low
```

## method_graph.yaml 字段规范（xKG节点分类）

```yaml
# 节点类型：method_node | config_node | code_node | db_node
nodes:
  - id: read_qc
    type: method_node
    tool: fastp
    version: "0.22.0"
    script: scripts/01_qc_fastp.sh
    paper_section: "Methods > Read quality control"

  - id: fungi_profiling
    type: method_node
    tool: "bowtie2 + GPA.py"
    script: scripts/74e_fun_phf_profiler.sh
    paper_section: "Methods > Metagenomics mapping"
    config:
      type: config_node
      identity_threshold: 0.95
      algorithm: "Singular+Escrow"
      index: "db/gut_fungi_db/bwt.index.gut_fungi_geneset"

edges:
  - from: read_qc
    to: host_removal
  - from: host_removal
    to: fungi_profiling
```

## params.yaml 字段规范（用于跨文献参数对比）

```yaml
tool: bowtie2
paper_recommended:
  mode: "--end-to-end --fast"
  multimapping: "-k 1000"
  identity_filter: 0.95       # applied in GPA.py -s 0.95
project_current:
  script: scripts/74e_fun_phf_profiler.sh
  matches_paper: true
  deviation_notes: null
```

## 触发规则（写入 CLAUDE.md）

| 用户说 | CC 行为 |
|--------|---------|
| 把这篇文献整进项目 / 技能库 / 复现 | 调用 `/mgx-replicate` 完整流程 |
| 把这篇文献整进RAG / 知识库 | 调用 `/mgx-index` 轻量索引 |
| 把这个GitHub / 代码整进项目 | 触发代码整合子流程 |
| 更新 XXX 的技能包 | `/mgx-replicate` update模式 |
