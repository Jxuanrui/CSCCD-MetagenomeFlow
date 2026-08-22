#!/usr/bin/env bash
# Wrapper for metadata QC

set -euo pipefail

WORKDIR=""
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w) WORKDIR="$2"; shift 2 ;;
    -r) REPO="$2"; shift 2 ;;
    -t) shift 2 ;;
    --force) FORCE=1; shift ;;
    *)
      if [[ -z "$WORKDIR" ]]; then WORKDIR="$1"; else REPO="$1"; fi
      shift
      ;;
  esac
done

WORKDIR="${WORKDIR:-Project/Test_100samples}"

if [[ ! -d "$WORKDIR" && -d "${REPO}/${WORKDIR}" ]]; then
  WORKDIR="${REPO}/${WORKDIR}"
fi

cd "$WORKDIR"
WORKDIR="$PWD"

OUTPUT_TSV="${WORKDIR}/metadata.tsv"
if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_TSV}" ] && [ -s "${OUTPUT_TSV}" ]; then
  echo "[metadata_qc] 结果已存在，跳过: ${OUTPUT_TSV}"
  exit 0
fi

# 直接用系统 Rscript（miniforge3 base env）会缺 readr/tibble——这两个包只装在
# envs/r_stat 专用环境里，其它 R 脚本均通过 conda run --prefix 调用，此处补齐同样约定
export REPO
conda run --prefix "${REPO}/envs/r_stat" --no-capture-output \
    Rscript "${REPO}/scripts/01_metadata_qc.R" "$PWD"
