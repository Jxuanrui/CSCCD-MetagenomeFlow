#!/usr/bin/env bash
# Wrapper for metadata QC

set -euo pipefail

WORKDIR=""
REPO="$(cd "$(dirname "$0")/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w) WORKDIR="$2"; shift 2 ;;
    -r) REPO="$2"; shift 2 ;;
    -t) shift 2 ;;
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
WORKDIR="$PWD" REPO="$REPO" Rscript "${REPO}/scripts/01_metadata_qc.R" "$PWD"
