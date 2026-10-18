# flock 实例锁回归矩阵（CP3 P0-4，2026-10-18）

锁键：`(WORKDIR realpath, 调用脚本路径, ${SAMPLE:-${SAMPLE_NAME:-${SAMPLE_ID:-}}})`；fd 生命周期随进程。

| 用例 | 操作 | 预期 | 实测 | 判定 |
|---|---|---|---|---|
| T1 同实例拒绝 | 同脚本+同样本并发 | GUARD 拒绝 exit 65 | GUARD 拒绝 | PASS |
| T2 异样本放行 | 同脚本+不同样本并发 | 双方获得锁 | ACQUIRED | PASS |
| T3 正常退出释放 | 持有者正常退出后再取 | 立即可取 | ACQUIRED | PASS |
| T4 异常退出释放 | 持有者 kill -9 后再取 | 内核回收 fd 后可取 | ACQUIRED | PASS |
| T5 SAMPLE_ID 字段 | 键含 SAMPLE_ID 回退（52 脚本用 SAMPLE，无一用 SAMPLE_ID——键已扩展为三重回退） | 重复被拒 | GUARD 拒绝 | PASS |
| T6 聚合步（空样本） | 无样本参数同脚本并发 | 聚合级互斥 | GUARD 拒绝 | PASS |

**未受锁保护的调用路径（如实清点）**：`00_*.sh` 工具类（数据库检查/诊断/报告等 8 个）与
`01_metadata_qc.sh` 不含 mgx_begin，不走 flock——均为只读/前置工具，无产物写竞争面；
52 个带样本主步骤脚本全部经 mgx_begin 受锁保护。

**模板整改**：`lane/TEMPLATE.sh` 已去除机器绝对路径（改 `${REPO:-$(cd "$(dirname ...)" && pwd)}` 自发现）。

## 测试命令与原始输出（CP3 复审 P0-3 补，2026-10-18 实跑）

命令骨架（T1-T4/T6）：
```
bash /tmp/flock_matrix_test.sh <mode> <sample>   # 内部 source libcommon; mgx_parse; mgx_begin; echo ACQUIRED / kill -9 $$
```
原始输出摘录（当轮实跑）：
```
T1: [GUARD] 同一 (workdir, step, sample) 已有实例在…      → 拒绝 ✓
T2: ACQUIRED:Sample2                                      → 放行 ✓
T3: ACQUIRED:Sample3 (second acquire after normal exit)   → 正常释放 ✓
T4: ACQUIRED:Sample4 (acquire after SIGKILL holder)       → 异常释放 ✓（内核回收 fd）
T5: [GUARD] …（SAMPLE_ID 变体重复被拒）                    → 键覆盖 ✓
T6: [GUARD] …（聚合步空样本并发被拒）                       → 聚合互斥 ✓
```
T5 命令变体：MGX_OPTS_STRING="z:SAMPLE_ID …"（键三重回退 SAMPLE→SAMPLE_NAME→SAMPLE_ID）。
测试脚本为一次性 /tmp 构造（本档记录命令骨架与输出即完整复现信息）。
