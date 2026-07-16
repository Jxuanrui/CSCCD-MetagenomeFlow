#!/usr/bin/env bash
# ==============================================================================
# Script: run_functional_analysis.sh
# Purpose: Batch execution of functional analysis for all dimensions
# Usage:   bash run_functional_analysis.sh [WORKDIR] [REPO]
# ==============================================================================

set -euo pipefail

WORKDIR="${1:-$(pwd)}"
REPO="${2:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "[INFO] Starting functional analysis batch run"
echo "[INFO] Workdir: ${WORKDIR}"
echo "[INFO] Repo: ${REPO}"
echo "[INFO] Start time: $(date)"

# Bacteria dimension (9 databases)
echo ""
echo "=========================================="
echo "Processing bacteria dimension (9 databases)"
echo "=========================================="
for func_type in pathway kegg_ko cog cazyme arg vfdb defense ncyc pcyc; do
  echo "[bacteria/${func_type}] Starting..."
  bash "${REPO}/scripts/96_stat_functional.sh" \
    -w "${WORKDIR}" \
    -r "${REPO}" \
    -d bacteria \
    -t ${func_type} 2>&1 | grep -E "^\[INFO\]|^\[ERROR\]" | tail -3
done

echo "[bacteria] Generating cross-database summary..."
bash "${REPO}/scripts/96_functional_integrated.sh" -d bacteria 2>&1 | grep -E "^\[INFO\]|^\[ERROR\]" | tail -3
echo "[bacteria] ✓ Completed"

# Fungi dimension (6 databases)
echo ""
echo "=========================================="
echo "Processing fungi dimension (6 databases)"
echo "=========================================="
for func_type in kegg_ko cog cazyme vfdb amr merops; do
  echo "[fungi/${func_type}] Starting..."
  bash "${REPO}/scripts/96_stat_functional.sh" \
    -w "${WORKDIR}" \
    -r "${REPO}" \
    -d fungi \
    -t ${func_type} 2>&1 | grep -E "^\[INFO\]|^\[ERROR\]" | tail -3
done

echo "[fungi] Generating cross-database summary..."
bash "${REPO}/scripts/96_functional_integrated.sh" -d fungi 2>&1 | grep -E "^\[INFO\]|^\[ERROR\]" | tail -3
echo "[fungi] ✓ Completed"

# Virus dimension (5 databases)
echo ""
echo "=========================================="
echo "Processing virus dimension (5 databases)"
echo "=========================================="
for func_type in phrog vog lifestyle host_genus viral_family; do
  echo "[virus/${func_type}] Starting..."
  bash "${REPO}/scripts/96_stat_functional.sh" \
    -w "${WORKDIR}" \
    -r "${REPO}" \
    -d virus \
    -t ${func_type} 2>&1 | grep -E "^\[INFO\]|^\[ERROR\]" | tail -3
done

echo "[virus] Generating cross-database summary..."
bash "${REPO}/scripts/96_functional_integrated.sh" -d virus 2>&1 | grep -E "^\[INFO\]|^\[ERROR\]" | tail -3
echo "[virus] ✓ Completed"

echo ""
echo "=========================================="
echo "All functional analyses completed"
echo "=========================================="
echo "[INFO] End time: $(date)"
echo "[INFO] Results location: ${WORKDIR}/result/stat/{bacteria,fungi,virus}/functional/"
echo ""
echo "Summary:"
echo "  - Bacteria: 9 databases + cross-database summary"
echo "  - Fungi: 6 databases + cross-database summary"
echo "  - Virus: 5 databases + cross-database summary"
echo "  - Total: 20 single-database analyses + 3 summaries"

