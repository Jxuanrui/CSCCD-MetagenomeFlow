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
