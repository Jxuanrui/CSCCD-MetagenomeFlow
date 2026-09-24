# mining/ — 肠道宏基因组自动挖掘子系统

> 状态（2026-09-23）：五层全部建成并贯通——**发现 → 策展 → 索引 → 处理(试点) → 挖掘**。
> 首份科学输出：克罗恩病丁酸产生菌减少签名（独立复现已知生物学，4/4 与 BugSigDB 方向一致）。
> 治理：根 CLAUDE.md；里程碑锚点：git tag `mining-m3-pilot-v1.2.1`。

## 设计来源：参考 scBaseCount（Arc Institute, Cell 2026）的分层架构

scBaseCount 用层级式 AI 代理自动发现、策展、统一处理单细胞数据。本子系统的对应关系：

| scBaseCount 的层 | 我们的对应 | 我们的增强 |
|---|---|---|
| SRAgent 发现/策展代理 | seqout MCP + `incremental.py` + `curate.py`（ZOOMA 确定性优先、GLM 兜底） | 覆盖中国 GSA；策展结果入 SQLite 而非一次性发布 |
| STAR 统一处理流水线 | 平台自身 Snakemake 轻链 + `run_dataset.py` 编排 | 三界分析能力远超单工具；三道分诊闸 |
| 周期性自动更新 | 每周一 03:00 cron：发现 → 策展自动链 | MGnify `order=-updated_at` 可增量同步 |
| （无） | **M4 挖掘层：疾病指纹比对 BugSigDB** | 本项目独有闭环：验证已知 + 发现新关联 |

## 如何使用（scBaseCount 式循环的操作手册）

```bash
PY=envs/rag/bin/python3

# ① 发现：每周 cron 自动执行；手动补跑/追赶：
$PY mining/incremental.py --dry-run                  # 预演
$PY mining/incremental.py --max-candidates 3000       # 追赶积压（断点安全）

# ② 策展：给样本填标准卡片（ZOOMA 免费通路 + GLM 兜底，断点续跑）
$PY mining/curate.py --scope all                      # 全库（含增量）
$PY mining/curate.py --scope incremental              # 仅新增（cron 自动链的后半段）

# ③ 处理：单研究端到端（本机小规模；批量见下方新服务器手册）
$PY mining/run_dataset.py --study ERP187412 --n 8 --with-humann --threads 16 --jobs 3

# ④ 挖掘（零计算路线）：用现成分析表跑疾病指纹比对
$PY mining/m4/prepare.py scan                         # 队列可行性扫描（不下载）
$PY mining/m4/prepare.py download                     # 下载现成剖析表（礼貌限速）
$PY mining/m4/compare.py                              # 比对 BugSigDB → results/
```

**输出位置**：登记/增量 → `seed_registry.sqlite`；策展卡片 → `curation.sqlite`（快照在 `snapshots/`，入 git）；处理结果 → `projects/<study>/result/`；挖掘报告 → `m4/results/<disease>/`。

**当前库容**：66,607 样本（存量 63,803 + 增量 2,804，每周自动增长）；疾病标准编号覆盖患病人群 94.5%；MGnify 82,021 条分析索引（其中 5,517 命中库内样本）；AGP 42,340 深表型；iMSMS 1,638 IBD 纵深。

## 新服务器批量重启手册（五步）

1. **装厨房**：`git clone` 本仓库 + `bash 0Install.sh`（环境 + 1.2T 数据库，约 1–2 天）
2. **带菜谱**：`rsync` 拷贝整个 `mining/`（<200MB：两库 + 快照 + 脚本 + m4 结果）
3. **试做一道菜**：`scripts/tests/run_ci_checks.sh` 三层 + `run_dataset.py --samples <ERS> --smoke`
4. **照订单开火**：从 `curation.sqlite` 选队列（疾病非空 + 优先级排序），批量驱动循环调 `run_dataset.py`
5. **边做边清**：批量模式启用中间产物即用即删

## 已知边界（诚实清单）

- **本机吞吐上限 ≈300 样本/月**（完整轻链实测 5.2 h/样本）；全量批处理延迟至新服务器
- **库内样本的 MGnify 免费分析多为旧版管线（V1–V5）**：仅 rRNA-OTU 表，V1 只到科级；高质量 V6 mOTUs 属于未入库的 331 个新研究（M4 v2 的入库候选）
- **跨研究比对受批次效应污染**（M4 已实测标注）：须同研究内 case/control 设计 + 平台 95a/b 批次校正
- 增量队列年龄/国家/BMI 源头缺失（研究级才有）；部位多为粗粒度 UBERON:0001007（上下文推断）
- 疾病编号含复合值（`;` 连接，IBD 类）与跨本体前缀（HP:/NCIT:，症状类）——下游解析按 `;` 拆分
- 98b 整合表需注释层（重链）输入，轻量层下部分交付属预期

## 外部依赖

seqout（统一检索，含中国 GSA；MCP 已接入 `.mcp.json`）· ENA portal API · ZOOMA / OLS4（本体）· MGnify API v2（预计算剖析；FTP 限速 45s/请求，用 `www.ebi.ac.uk` 文件代理）· BugSigDB（签名基准，`mcp/data/` 只读）· GLM（`glm-5.3-flash`；密钥走 `GLM_API_KEY` 或 `~/.glm_router_api_key`，永不入库）
