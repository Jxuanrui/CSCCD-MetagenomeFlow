# envs-pixi/ 环境锁定覆盖口径（review 16th review P2-1）

## 覆盖率：53/53 适用域全锁（100%）

**口径定义**：pixi 适用域 = 所有可被 pixi 解析依赖的 conda 环境（有 pixi.toml 的目录）。

**验证命令**：
```bash
ls envs-pixi/*/pixi.toml | wc -l  # → 53
ls envs-pixi/*/pixi.lock  | wc -l  # → 53
```

## 4 个例外目录（设计性无锁，非缺锁）

| 目录 | 原因 | 证据 |
|---|---|---|
| kneaddata/ | pixi 无法解析 samtools==0.1.19 依赖链（openssl 1.1.x 已从 conda-forge 移除），conda-pack 轨道 2 保底 | NOTE.md 在盘 |
| prokka/ | 同上 | NOTE.md 在盘 |
| virsorter2-sif/ | SIF 容器交付方案（轨道 1 不适用） | NOTE.md 在盘 |
| r_stat_supplement/ | 非独立 pixi 环境，仅含 R 补充安装脚本 | 目录内容 |

> 注：kneaddata/prokka 的 pixi.toml 删除已在 c954ed7 作为 intentional deletions 提交。
