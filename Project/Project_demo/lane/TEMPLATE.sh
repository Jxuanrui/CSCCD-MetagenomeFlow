#!/usr/bin/env bash
# 泳道模板（CP3 W4b 入库）——生成泳道脚本一律复制本模板后修改。
# 内建：MGX_MONITOR、conda PATH、flock（经 mgx_begin 自动生效）、
# fail-fast 链式模式、末尾 DONE 标记（watcher 判据用文件存在性，勿 grep 日志字符串）。
# 纪律：启动前参数齐全性自检（对照各脚本 usage 的必传参）；重统计类步骤显式
# 声明 nPerm/bootstrap 上限并换算墙钟（质量审核六审规则①）。
export MGX_MONITOR=1
export PATH="/home/labuser/Course/Maxmetagenome/miniforge3/bin:$PATH"
: "${WD:=/home/labuser/Course/Maxmetagenome/Project/PROJECT_NAME}"  # 复制后改为实际项目目录名（默认值形式避免未用告警）
REPO=/home/labuser/Course/Maxmetagenome
cd "$REPO" || exit 1

fail() { echo "=== <LANE> ABORTED at \$1 (\$(date +%T)) ==="; exit 1; }

# for step in ...; do bash "scripts/\${step}.sh" <必传参齐全> || fail "\$step"; done
# for s in \$SAMPLES; do bash scripts/<per-sample.sh> -s "\$s" -t 16 -w "\$WD" -r "\$REPO" || fail "<step>/\$s"; done

echo "=== <LANE> DONE \$(date +%T) ==="
