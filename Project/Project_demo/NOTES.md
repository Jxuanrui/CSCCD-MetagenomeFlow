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
