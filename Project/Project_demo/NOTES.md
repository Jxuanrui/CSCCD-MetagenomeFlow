# Project_demo — 模式一全链演示走查项目

- 创建：2026-10-03 ｜ 锚点 tag：new-project-demo-v1.2.1 ｜ Tech Spec：docs/plans/2026-10-03_demo_walkthrough_techspec.md
- 数据：自 Project01 只读拷出 6 样本（treat=Sample1/2/10；control=Sample3/4/11），实体复制非软链。
- **全短样本策略（§10.2，质量审核 P0-1）**：空产出继续 + 如实记录（keep-going 语义）——
  任何步骤产出为空/跳过时，walkthrough 显式成章记录原因，不静默省略、不视为失败。
- 监控：全程 MGX_MONITOR=1；快照采集 `python3 scripts/utils/run_monitor.py Project/Project_demo --text`。
- 产出：walkthrough.md（教程式，章节↔脚本编号一一对应）。

## 执行红线与口径（质量审核 2026-10-03 并行计划条件）
- **74a 禁止 `--force`**：索引齐全时会跳过；加 --force 会把 fungi_target/
  human_chm13v2 两个 .bt2 索引重建并写入 db/，违反 §10.5-2 数据库冻结
  （74a_fun_gut_db_build.sh:55,85 的判断结构所致，质量审核 C2）。
- **计时口径**：三线并行期间 A 线记录的时长含 B/C 线负载，供预期管理时
  需注明并行背景（质量审核），收尾段出"净时长"修正说明。
- **commit 纪律**：按线分开、逐文件清单提交；A 线每审核批次记录当时 HEAD
  （质量审核 C5）。

## 三界段执行计划（质量审核 2026-10-08 修订，P0-5）

### 步骤计数修正
- 病毒链：24 步（非 23）
- 真菌链：26 步可跑（非 16；76 已移除）
- 细菌组装/分箱链：16-43c 约 50 步（此前完全遗漏）

### 组装器互斥纪律（P0-6）
全局同一时刻只允许一个组装器运行（megahit/metaSPAdes）。三界泳道可并行，
但组装步骤必须排队。

### 真菌功能注释科学口径披露
78 号组装用全部清洁 reads（非仅真菌 reads）；80 号用 Prodigal（原核基因预测）。
81-86 号实际是以细菌为主的全群落注释，放在 fungi/ 目录下。文档此前未说明。

## 防重复启动规程（质量审核 P0-3，2026-10-09）
1. 每次启动泳道前：`pgrep -af "<脚本名>"` 确认无同步骤残留进程
2. 启动后 60 秒：`grep "<step>.*<sample>.*-1" logs/run_events.jsonl | wc -l` 确认只有 1 条启动记录
3. 如发现重复：立即 kill 较新的进程（保留先启动的），清除后重启
4. 教训来源：megahit Sample1 SIGSEGV（incident_20261007_megahit_dup_launch.md）

## 失败事件构成更正（质量审核 C1，2026-10-10；2026-10-13 增补）
✗ 的实际构成：megahit 重复启动 ×2（exit 245）+ virsorter2 conda 失败 ×6（exit 1）+ 55 假成功 ×6（2026-10-13 增补：54 交集 `--force` 重跑后下游 55 未带 `--force`，走跳过分支记 ✓，实为旧产物；教训见事故 #13）。
**计数口径警示（事故 #14）**：被 SIGKILL 的进程 EXIT trap 仍记 exit=0（如 74/Sample11 被清杀记为 ✓ 且 params 字段被污染）——✓ 计数含少量假成功，以文件新鲜度为准。

## 执行红线增补（质量审核 2026-10-13）
- **上游 `--force` 重跑后，下游一律 `--force`**（下游哨兵不因上游失效，事故 #13 根因）。
- 高内存步骤（gtdbtk/iphop/36b/antismash）不同波次同时运行；启动前 `free -g` 核对。

## 后续执行计划（质量审核 2026-10-13 设计，W1-W6；用户approve项见表）
| 波次 | 泳道 A(16t) | 泳道 B(16t) | 泳道 C(16t) | 关口 |
|---|---|---|---|---|
| W1 当前 | 38→38b（作原始基线） | B3轻:24→24b→26→27→29 | B3重:31→31b→31c→31d | CP1+CP2-病毒（只读，已呈质量审核） |
| W2 | 36b ×6 严格串行（互斥） | 病毒下游 64→65→66→67→67b→72→70→69→68（iphop 最后） | 真菌 80/80b×6→75→75b→77→81→86 | — |
| W3 | 清空 drep_input/temp→37 --force→38 --force→38b --force | 28 antismash（分块）→28b | 31e×6→42→42b×6 | CP2-MAG（含 36b 回退核对） |
| W4 | 40 gtdbtk→41 prokka→41b→41c/41d | 39→39b→39c×6→39d | 43 gapseq→43b→43c | — |
| W5 | 98b/98c/98d、98c_mge、98d_mag | 98e→98f→98g | — | CP3 全量对齐 |
| W6 | 91→92→93→94→96 系→99a/99b→98 | | | 统计附 3v3 功效披露 |
串行：36b→37→38→38b→MAG 尾链；39b→c→d；43→43c；80→81-86；75→75b。并行：目录级注释互斥安全；64-72 互不依赖；28/31e/42/42b 与 MAG 链无依赖（读 16/17 号产物）。

## 待用户approve（质量审核 2026-10-13 两轮合并，共 6 项，详见 .claude/reviews/supervisor_20261013_*.md）
| # | 事项 | 质量审核建议 |
|---|---|---|
| A | 36b 重组装照跑（37/38 重做，现结果作对照）vs 撤销 36b 接受现状 | 倾向照跑（教程价值高），耗时待估 |
| B | 54 并集敏感性：修 `54:102` 表头归一化 bug 后补做 vs 撤回"已完成"表述 | 修复补做（约 1h） |
| C | dbCAN 仅 diamond 单工具（头注释写三工具投票） | 演示阶段保留+披露，不改三工具 |
| D | vOTU 丰度层级：现表 contig 级与基因级 TPM 混加，须二选一 | 只用 contig 级（一条 vOTU 一个数） |
| E | 病毒基因 ID 加样本前缀（修 55/58，重跑 58→59→60） | 批准，与细菌侧 `样本|` 格式统一 |
| F | 基于现 vOTU 表的下游统计（98c/98g/93/96）处置 | 60 复审通过后统一重算，之前冻结引用 |

**冻结令**：votu_table.tsv 现版本不得作为统计输入（60 号打回）；64-72 注释步骤不受影响（不消费该表）。

## 待披露清单（写入 walkthrough 对应章节时落实）
- 25 dbCAN：实际仅 `--tools diamond` 单工具（overview.txt #ofTools=1）；`25:57-59` 无条件跳过破坏 --force 语义。
- 60 vOTU 表：`length` 列实为首个基因长度非 vOTU 长度；305 行基因级记录（~0.6%）因 ID 歧义未并入任何 vOTU（votu_join_stats.tsv:3）。
- 38 dRep 实际质量门槛以 38 号日志为准（可能 comp≥75 非 ≥50，candidate_research）。
- 36b 静默回退风险：metaWRAP 失败回退原始 bin 且 exit 0，CP2-MAG 须逐样本核对 sentinel N_FALLBACK。

## 执行进度索引（2026-10-13 更新）

### 已完成段
| 段 | 步骤 | 事件数 | 关口状态 |
|---|---|---|---|
| 预处理 | 01→02b | 18 | ✅ 已过（supervisor_20261004） |
| 细菌读式 | 11→15d | 58 | ✅ 已过（第四轮通过，C1 已销项） |
| 病毒链全段 | 51→59（60 打回） | — | ⚠️ CP2-病毒：60 号 vOTU 表 FAIL（见 supervisor_20261013_cp_audit.md），58→59→60 整改重跑待approve |
| 真菌链前段 | 71→79b | 44+ | ⏳ 段未完 |
| 细菌组装+基因目录 | 16→20 | — | ⏳ 待 CP1 |
| eggNOG+KEGG | 21（302MB）+ 22（903,807 命中） | — | ✅ validate PASS |
| 三路分箱+整合 | 32/33/34/35 + 36（353 MAGs） | — | ✅ validate PASS（含 bins↔c2b 一致性） |

### 当前运行中（2026-10-13 07:25 起，三泳道）
| 泳道 | 步骤 | 目标 |
|---|---|---|
| B2 MAG | 37 CheckM2（353 bins）→ 38 drep → 38b gunc | MAG 质控+去冗余 |
| B3-轻 | 23 amrfinder → 24/24b card → 26 vfdb → 27 bacmet → 29 defense_finder | 目录级轻注释 |
| B3-重 | 25 dbcan → 30 ncyc → 31 pcyc → 31b scyc → 31c pfam → 31d uniprot | 目录级重注释 |

> 注：28 antismash / 31e fegenie 为按样本步骤，等 MAG 链产出后排期；真菌 75→86 等轻泳道空出。

### 决定不执行
- 16b metaSPAdes（叶子步骤，无下游使用，用户批准不跑）
- 62/63 vMAG（Project01 先例 0 vMAG）
- 95a/95b（无 batch 列）
- 97（跨队列不适用）

### 事故索引
| 日期 | 事件 | 档案 |
|---|---|---|
| 2026-10-05 | HUMAnN 相对路径 + cd 嵌套 → 6 样本全失败 | incident_20261005_humann_relpath.md |
| 2026-10-07 | megahit 重复启动 → Sample1 SIGSEGV | incident_20261007_megahit_dup_launch.md |
| 2026-10-09 | 74f 表头误判 → 合并矩阵数据损坏 | 已修复（351952d），无事故档案（内联修复） |
| 2026-10-12 | 74 blast_gutdb 孤儿循环（/tmp/lane_f_blast.sh，10-11 启动，PPID=1）空转：4 样本产出全 0 字节再证数据库无效；首次清杀 Sample4 diamond 后循环仍推进 Sample11（11:28 启动），二次定位循环根整树清除 | 内联处置：循环+脚本+进程全灭、result/fungi/blast_gutdb/（8.3GB）两删；教训：清残留须先定位循环根（/tmp/lane_*.sh），杀叶子进程只会推进迭代 |
| 2026-10-13 | 60 号 vOTU 表五缺陷被 CP2-病毒打回：基因 ID 跨样本重名（305 行丢弃）、length 列语义错、首行误删、contig/基因级 TPM 混加、exit 0 静默通过 | supervisor_20261013_cp_audit.md；整改重跑待approve D/E/F |

### 检查点计划（质量审核设计）
- CP1: 17/18 + 32 + 54b 完成后 → 核对基因目录/深度表/checkv
- CP2: 37 checkm2 + 60 vOTU 完成后 → 核对 MAG/vOTU
- CP3: 统计段启动前 → 全量 step_checklist 对齐

## BUSCO 联网行为披露（质量审核 P0-2，2026-10-11）
79b/79e 的 BUSCO 在 2026-10-10 运行时使用了 --auto-lineage-euk 但未加 --offline。
日志证实联网刷新了版本清单（busco.log:6 "Downloading information..."）。
本次运行未实际下载数据（lineage 已是最新版），但存在自动写入 db/ 的风险。
修复：已加 --offline，修复后可安全重跑。违反 §10.5-2 数据库冻结，特此披露。

## 病毒判定口径approve（2026-10-11 用户批准）
1. 病毒判定：**交集**做主结果（严格），并集作为敏感性分析——需修改 54 号代码
2. vOTU 定量算法：保留现有实现，文档中披露方法差异
3. 36b 重组装：**全跑**（6/6）
