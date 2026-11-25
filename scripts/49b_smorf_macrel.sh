#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 49b_smorf_macrel.sh
# 功  能: B 路线 · Macrel 新肽挖掘运行器——对输入 contigs（或子集）运行
#         Macrel 1.6.0 `all` 管线，产出抗菌肽候选预测，解析为候选证据表。
# 环境:   miniforge3/envs/macrel（pip 安装 macrel==1.6.0，锁定版本）
# 口  径: 输入 contigs 子集用于试点（全量运行属于使用期按需）；
#         Macrel 输出坐标为 1-based 闭区间（与 Prodigal 一致，回映射时双确认）；
#         macrel prediction 的 class 列原样保留（单/多类别）。
# 输  出: ${WORKDIR}/result/peptide/broute/macrel_precursors.tsv
#         ${WORKDIR}/result/peptide/broute/macrel_raw/（原始输出留存）
#         macrel.done / .FAILED
# 用  法: bash 49b_smorf_macrel.sh -w WORKDIR -r REPO -f INPUT_FA [-t THREADS]
# ==============================================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat <<'EOF'
Usage: bash 49b_smorf_macrel.sh -w WORKDIR -r REPO -f INPUT_FA [-t THREADS]
EOF
}

if [ $# -eq 0 ]; then
    show_help; exit 0
fi

export MGX_OPTS_STRING="w:WORKDIR r:REPO f:INPUT t:CPUS"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO INPUT
CPUS="${CPUS:-8}"
WORKDIR="$(cd "${WORKDIR}" && pwd)"
INPUT="$(cd "$(dirname "${INPUT}")" && pwd)/$(basename "${INPUT}")"

mgx_begin

MACREL_BIN="${REPO}/miniforge3/envs/macrel/bin/macrel"
[ -x "${MACREL_BIN}" ] || MACREL_BIN="$(conda info --base 2>/dev/null)/envs/macrel/bin/macrel"
if [ ! -x "${MACREL_BIN}" ]; then
    echo "[ERROR] macrel 可执行文件未找到" >&2
    exit 1
fi

OUT="${WORKDIR}/result/peptide/broute"
RAW="${OUT}/macrel_raw"
LOG="${WORKDIR}/logs/peptide/broute"
mkdir -p "${RAW}" "${LOG}"
LOG_FILE="${LOG}/49b_macrel_$(date -u +%Y%m%d_%H%M%S%N | head -c 20).log"
exec > >(tee "${LOG_FILE}") 2>&1

SENTINEL="${OUT}/macrel.done"
rm -f "${SENTINEL}" "${SENTINEL}.FAILED"

if [ ! -s "${INPUT}" ]; then
    echo "[ERROR] 输入 FASTA 不存在: ${INPUT}" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
fi

echo "[INFO] 49b Macrel 挖掘启动 $(date -u '+%F %T') | macrel=$($MACREL_BIN --version 2>&1) | input=${INPUT}"

T1=$(date +%s)
"${MACREL_BIN}" contigs --fasta "${INPUT}" --output "${RAW}" --threads "${CPUS}" --force --log-file "${RAW}/macrel.log"
RC=$?
T2=$(date +%s)
echo "[INFO] macrel 退出码=${RC} 耗时=$((T2 - T1))s"
if [ "${RC}" -ne 0 ]; then
    echo "[ERROR] macrel 运行失败" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
fi

python3 - "${RAW}" "${OUT}" <<'PYEOF'
import glob, gzip, sys

raw, out = sys.argv[1], sys.argv[2]
# macrel 1.6.0: 输出为 gzip（macrel.out.prediction.gz）；列 Access/Sequence/
# AMP_family/AMP_probability/Hemolytic/Hemolytic_probability
preds = sorted(glob.glob(f"{raw}/**/*.prediction.gz", recursive=True)) or \
        sorted(glob.glob(f"{raw}/**/macrel.out.prediction.gz", recursive=True))
rows = []
for f in preds:
    with gzip.open(f, "rt", encoding="utf-8") as fh:
        header = None
        for line in fh:
            if line.startswith("#"):
                continue
            header = line.lstrip("#").rstrip("\n").split("\t")
            break
        for line in fh:
            vals = line.rstrip("\n").split("\t")
            if len(vals) != len(header):
                continue
            rows.append(dict(zip(header, vals)))
with open(f"{out}/macrel_precursors.tsv", "w", encoding="utf-8") as o:
    o.write("peptide_id\tsequence\tamp_family\tamp_probability\themolytic\t"
            "hemolytic_probability\tevidence_type\ttool_version\n")
    for r in rows:
        o.write("\t".join([
            r.get("Access", ""), r.get("Sequence", ""),
            r.get("AMP_family", ""), r.get("AMP_probability", ""),
            r.get("Hemolytic", ""), r.get("Hemolytic_probability", ""),
            "model_prediction", "macrel 1.6.0",
        ]) + "\n")
print(f"[done] prediction files: {len(preds)} | candidates: {len(rows)}")
PYEOF

if [ ! -s "${OUT}/macrel_precursors.tsv" ]; then
    echo "[ERROR] 候选表未生成" >&2
    : > "${SENTINEL}.FAILED"
    exit 1
fi

echo "[DONE] $(date -u '+%F %T') macrel"
date -u '+%F %T' > "${SENTINEL}"
mgx_end "broute_macrel"
