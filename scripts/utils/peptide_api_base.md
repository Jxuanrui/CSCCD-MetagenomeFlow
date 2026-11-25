# PEPTIDE_API_BASE 环境变量覆写机制（46/47 号）

日期：2026-11-25
适用：`scripts/46_smorf_screen.sh`、`scripts/47_smorf_nn.sh`
性质：纯环境变量覆写点，不改变任何默认行为

## 机制

两个脚本的 Python 段原先将 miProbe API base 硬编码为生产地址。现改为
`os.environ.get` 读取 `PEPTIDE_API_BASE`，未设置时回退到原生产 URL（字节级
等价于改动前行为）：

```python
API = os.environ.get("PEPTIDE_API_BASE", "https://www.biosino.org/iMAC/miProbe/api")
```

- 46 号：`prediction/{bioactivity,amp,phychem}` 三个端点走该 base
- 47 号：`embedding-search/search` 端点走该 base
- 改动各仅 1 行；除此之外无任何逻辑改动（`git diff` 可核）

## 用途与用法

仅用于**隔离演练**（故障注入 / 断点续传测试），生产运行严禁设置该变量：

```bash
# 演练：指向本地 mock（需先启动 mock 服务器）
PEPTIDE_API_BASE=http://127.0.0.1:18102/iMAC/miProbe/api \
  bash scripts/46_smorf_screen.sh -w <workdir> -r <repo> -i <input.fasta>

# 生产：不设置，自动回退 https://www.biosino.org/iMAC/miProbe/api
bash scripts/46_smorf_screen.sh -w <workdir> -r <repo> -i <input.fasta>
```

注意：mock 服务器的路由前缀需与生产一致（`/iMAC/miProbe/api/...`），因为
脚本按 `{API}/prediction/<endpoint>` 拼接完整 URL。

## 默认回退的验证（2026-11-25 演练）

不设置 `PEPTIDE_API_BASE` 跑 46 号（1 条序列，3 次真实小调用，≤5 次上限内）：
三端点均返回真实生产响应结构（bioactivity 含 `models_info`，amp 含
`raw_score`，phychem 含 `properties`），exit 0——默认回退路径无回归。

## 演练记录（mock 均在 /tmp，隔离 workdir /tmp/peptide_dbtest/）

- T4 场景 A（全 200）：16/16 批次成功，state 游标推进，batch JSON 可解析
- T4 场景 B（前 2 次 504）：重试 2 次后成功，`[retry 1/2]` 落日志
- T4 场景 C（持续 504）：16 个 `batch_*.error` 落盘、state 不推进；但发现
  运行器仍写 `screen.done` 成功哨兵且 exit 0（见交付报告 F1，未在本改动
  边界内修复）
- T2 断点续传：47 号游标检查点粒度为每 50 条，<50 条的运行 kill 后无游标
  可续（见交付报告 F2）；跨检查点 kill 证实游标续传机制本身有效
  （resume_from=50，已提交条目零重复调用）
