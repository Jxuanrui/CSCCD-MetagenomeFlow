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
