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

## 失败事件构成更正（质量审核 C1，2026-10-10）
✗8 的实际构成：megahit 重复启动 ×2（exit 245）+ virsorter2 conda 失败 ×6（exit 1，全部 3-4 秒即退）。
此前误报为"virsorter2 ×2 + 其他早期 ×4"。
成功事件 119 条按步骤+样本去重后 = 114 个（重复 5 条：71/Sample1 ×2、53/Sample1 测试 ×3、74f --force ×1）。

## 执行进度索引（2026-10-13 更新）

### 已完成段
| 段 | 步骤 | 事件数 | 关口状态 |
|---|---|---|---|
| 预处理 | 01→02b | 18 | ✅ 已过（supervisor_20261004） |
| 细菌读式 | 11→15d | 58 | ✅ 已过（第四轮通过，C1 已销项） |
| 病毒链全段 | 51→60（2,622 vOTUs × 6 样本 TPM） | — | ⏳ 待 CP2 |
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
