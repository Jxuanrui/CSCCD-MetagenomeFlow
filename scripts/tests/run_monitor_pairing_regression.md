# run_monitor 配对回归矩阵（CP3 P0-2，2026-10-18）

> 语义：精确身份优先；样本不匹配的 end 仅在唯一候选（无歧义双射）时回退关闭；多候选=歧义未决（保持可见），不按新近度猜测。

| 用例 | 预期配对 | 实际配对 | 预期未决 | 实际未决 | 判定 |
|---|---|---|---|---|---|
| exact pair, cross-sample concurrency | 2 | 2 | 0 | 0 | PASS |
| LIFO rerun: killed run stays visible | 1 | 1 | 1 | 1 | PASS |
| legacy empty-start/typed-end (98e): unambiguous bijection closes | 1 | 1 | 0 | 0 | PASS |
| typed-start/empty-end: unambiguous closes | 1 | 1 | 0 | 0 | PASS |
| AMBIGUOUS: two starts, one mismatched end -> unresolved | 0 | 0 | 2 | 2 | PASS |
| case-variant sample ids: distinct identities | 1 | 1 | 1 | 1 | PASS |
| path-prefixed vs bare: distinct identities | 1 | 1 | 1 | 1 | PASS |
| pipeline events excluded upstream (not passed here) | 1 | 1 | 0 | 0 | PASS |

**总判定：ALL PASS**
