# run_monitor 配对回归矩阵（CP3 复审 P0-2 修订版，2026-10-18）

**语义**：精确身份优先；样本不匹配的 end 仅在「真唯一」时回退关闭——
候选 key 数 = 1 **且** 该 key 下 pending start 总数 = 1（两个计数分别命名
n_candidate_keys / n_candidate_starts，key 唯一 ≠ 事件唯一）。其余一律歧义未决
（保持可见），不按新近度猜测。

**测试命令**：`python3 <内嵌 9 例构造事件列表，调用 pair_step_starts，打印 预期/实际/判定>`
（构造与断言代码见原始输出文件头部注释；事件结构与 run_events.jsonl 的
step_id/sample_id/exit_code 三字段一致）。

**原始运行输出**：`scripts/tests/pairing_raw_output_20261018.txt`（2026-10-18 实跑，
9/9 PASS；含两例复审新增：同身份连续 start+mismatched end 双未决、A/B start+C end 未决）。

**真实事件流核验**：`run_monitor.py <demo> --text` → 终态 513（✓480 ✗33）运行中 0。

| # | 用例 | 预期(配对,未决) | 实际 | 判定 |
|---|---|---|---|---|
| 1 | 跨样本并发精确配对 | (2,0) | (2,0) | PASS |
| 2 | LIFO 重跑：被杀者保持可见 | (1,1) | (1,1) | PASS |
| 3 | 遗留空 start/带样本 end（98e）真唯一 | (1,0) | (1,0) | PASS |
| 4 | 带 start/空 end 真唯一 | (1,0) | (1,0) | PASS |
| 5 | 双 start+单 mismatched end | (0,2) | (0,2) | PASS |
| 6 | 大小写变体=不同身份 | (1,1) | (1,1) | PASS |
| 7 | 路径前缀变体=不同身份 | (1,1) | (1,1) | PASS |
| 8 | 同身份连续 start+mismatched end→双未决 | (0,2) | (0,2) | PASS |
| 9 | A/B start+C(不匹配) end→未决 | (0,2) | (0,2) | PASS |
