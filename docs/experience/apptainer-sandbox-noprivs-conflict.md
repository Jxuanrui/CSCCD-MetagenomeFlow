---
tool: "apptainer"
dimension: "shared"
category: "infra"
author: ""
date: "2026-07-04"
tags: [apptainer, singularity, sandbox, sandbox, execution-routing, troubleshooting]
scenario: [virus-dimension, container-dependent-tools]
---

# Apptainer/Singularity 容器脚本必须在宿主 Bash 执行，不能走 沙箱执行器

## Scenario

> 适用于任何依赖 Apptainer/Singularity `.sif` 容器的分析脚本（直接调用，或通过 conda env 内的 wrapper 二进制间接调用）。首次在运行 `53_vir_virsorter2.sh`（病毒维度）时通过 沙箱执行器 触发。

`envs/virsorter2/bin/virsorter` 实际上是一个 bash wrapper：
```bash
#!/usr/bin/env bash
SIF="~/Course/Virus_Apptainer_pipline/apptainer/virsorter2-kit-0.0.4.sif"
exec apptainer exec -B "${BIND_ROOT}:${BIND_ROOT}" "${SIF}" virsorter "$@"
```
通过 沙箱执行器（`sandboxed-executor call`）运行 `53_vir_virsorter2.sh` 时报错：
```
ERROR  : Installation issue: starter-suid doesn't have setuid bit set
```
但同一条命令在 宿主 Bash里手动复现，完全正常，容器正常启动，Snakemake DAG 正常跑完。

## Recommendation

**诊断步骤**（怀疑是这个问题时，先确认，别急着改系统配置）：
```bash
# 在报错的执行环境里跑：
grep NoNewPrivs /proc/self/status
# 输出 "1" → 就是这个问题，不用继续排查 apptainer.conf / AppArmor / 文件权限

# 复现最小案例：
apptainer exec -B /some/path:/some/path some.sif echo hello
```

**处理方式**：确认脚本依赖 `.sif` 容器后，改为 宿主 Bash 直接用 Bash 工具执行，不再走 沙箱执行器：
```bash
# 不要用 mcp__sandbox__sandbox / sandbox-reply
# 直接：
bash scripts/53_vir_virsorter2.sh -s Sample1 -t 16 -w Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow
```

排查新脚本是否受影响：
```bash
grep -q "apptainer exec\|singularity exec\|\.sif" envs/<env_name>/bin/<tool> && echo "受影响，需路由给CC"
```

## Rationale

- **原理**：沙箱执行器 的执行沙箱为隔离安全边界，主动给自身进程设置了内核的 `NoNewPrivs=1` 标志（`prctl(PR_SET_NO_NEW_PRIVS)`），并运行在独立的 user namespace 里。`NoNewPrivs` 一旦置位，对该进程及其所有子进程**永久**生效、无法撤销：任何 `exec` 调用都不能再通过 setuid/setgid 位或文件 capability 获得额外权限。
- **为什么恰好打中 Apptainer**：Apptainer 的 setuid 运行模式依赖 `starter-suid`（一个真正的 `-rwsr-xr-x root root` 二进制）在 exec 时提权到 root，才能完成容器需要的 mount namespace / overlay 挂载等操作。`NoNewPrivs=1` 直接掐断了这条提权路径，Apptainer 检测到提权失败后报出这个具体的错误信息（尽管字面意思像是"文件没设 setuid"，但实际文件权限是对的）。
- **对比 宿主 Bash 执行环境**：宿主 Bash没有设置 `NoNewPrivs`（值为 0），可以正常提权，所以同一条命令在宿主 Bash 里跑没有任何问题。这是两个执行环境沙箱严格程度不同导致的行为差异，不是脚本或系统配置的 bug。
- **为什么不该"修复"**：`NoNewPrivs` 是 沙箱执行器 沙箱主动设的安全边界，属于设计特性。尝试绕过（例如给 沙箱执行器 进程本身提权、关闭沙箱限制）等于削弱隔离，风险收益不成比例。正确做法是识别出这一类工具，改变执行路径而不是改变沙箱行为。
- **代价**：这类脚本失去了 沙箱执行器 执行带来的自动化/多轮迭代能力，必须由宿主 Bash 手动跑（通常配合 `run_in_background: true` 做长任务监控）。目前项目里只有 `virsorter2` 一个工具受影响（已用 `grep -rl` 扫描过 `scripts/*.sh` 和所有 `envs/*/bin/*` wrapper，确认范围仅此一个）。

## Verified

- Project01, 2026-07-04, PASS — `53_vir_virsorter2.sh` 通过 宿主 Bash 直接执行（`run_in_background: true`），Sample1 样本 Snakemake DAG 正常执行至 46%+，无 setuid 报错。
- 诊断复现：`grep NoNewPrivs /proc/self/status` 在 沙箱执行器 环境输出 `1`，在宿主 Bash 环境输出 `0`；`apptainer exec` 同一命令分别复现失败/成功。

## References

- CLAUDE.md §5.6（Known Limitation 记录，含路由规则）
- 脚本：`scripts/53_vir_virsorter2.sh`，wrapper：`envs/virsorter2/bin/virsorter`
- Apptainer 官方文档关于 setuid 安装模式：https://apptainer.org/docs/admin/main/installation.html#setuid-installation
