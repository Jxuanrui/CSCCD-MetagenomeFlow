# Deprecated 2026-07-16: superseded by 92_stat_differential.sh due to directory-convention duplication.
#!/bin/bash
# Step 4: Differential Abundance Analysis Wrapper
# Usage: bash 04_differential_abundance.sh -w <workdir> -r <repo> -d <dimension> [options]

set -euo pipefail

# Default values
WORKDIR=""
REPO=""
DIMENSION=""
GROUP_COL="group"
FDR=0.05
LFC=1.0
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -w|--workdir)
      WORKDIR="$2"
      shift 2
      ;;
    -r|--repo)
      REPO="$2"
      shift 2
      ;;
    -d|--dimension)
      DIMENSION="$2"
      shift 2
      ;;
    -g|--group)
      GROUP_COL="$2"
      shift 2
      ;;
    --fdr)
      FDR="$2"
      shift 2
      ;;
    --lfc)
      LFC="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [[ -z "$WORKDIR" ]] || [[ -z "$REPO" ]] || [[ -z "$DIMENSION" ]]; then
  echo "Usage: $0 -w <workdir> -r <repo> -d <dimension> [-g group_col] [--fdr <value>] [--lfc <value>] [--force]"
  echo "  -w, --workdir    Working directory (required)"
  echo "  -r, --repo       Repository root (required)"
  echo "  -d, --dimension  Dimension: bacteria/fungi/virus/all (required)"
  echo "  -g, --group      Group column name [default: group]"
  echo "  --fdr            FDR threshold [default: 0.05]"
  echo "  --lfc            Log2 fold-change threshold [default: 1.0]"
  echo "  --force          Force re-run even if sentinel exists"
  exit 1
fi

# Convert to absolute paths
WORKDIR=$(cd "$WORKDIR" && pwd)
REPO=$(cd "$REPO" && pwd)

# Metadata path
METADATA="${WORKDIR}/result/stat/metadata.tsv"
if [[ ! -f "$METADATA" ]]; then
  echo "[ERROR] Metadata not found: $METADATA"
  exit 1
fi

# Log directory
LOG_DIR="${WORKDIR}/logs/stat/differential_abundance"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/04_differential_abundance_${TIMESTAMP}.log"

# Function to run differential abundance for one dimension
run_differential() {
  local dim=$1
  echo "[INFO] Running ${dim} differential abundance"

  local output_dir="${WORKDIR}/result/stat/${dim}/differential"
  local sentinel="${output_dir}/${dim}_differential_abundance_done.txt"

  # Check sentinel
  if [[ -f "$sentinel" ]] && [[ "$FORCE" != "true" ]]; then
    echo "[INFO] ${dim} differential abundance already completed (sentinel exists)"
    echo "[INFO] Use --force to re-run"
    echo "[INFO] Sentinel: $sentinel"
    return 0
  fi

  echo "[INFO] Output directory: $output_dir"
  mkdir -p "$output_dir"

  # Run R script
  conda run --prefix "${REPO}/envs/r_stat" --no-capture-output \
    Rscript "${REPO}/scripts/04_differential_abundance.R" \
      -w "$WORKDIR" \
      -r "$REPO" \
      -m "$METADATA" \
      -d "$dim" \
      -g "$GROUP_COL" \
      --fdr "$FDR" \
      --lfc "$LFC"

  if [[ -f "$sentinel" ]]; then
    echo "[INFO] ${dim} differential abundance completed"
    echo "[INFO] Sentinel: $sentinel"
  else
    echo "[ERROR] ${dim} differential abundance failed - sentinel not created"
    return 1
  fi
}

# Main execution
{
  echo "=============================================================================="
  echo "Differential Abundance Analysis"
  echo "Start time: $(date)"
  echo "=============================================================================="
  echo "[INFO] Workdir: $WORKDIR"
  echo "[INFO] Repo: $REPO"
  echo "[INFO] Metadata: $METADATA"
  echo "[INFO] Group column: $GROUP_COL"
  echo "[INFO] Dimension request: $DIMENSION"
  echo "[INFO] FDR threshold: $FDR"
  echo "[INFO] LFC threshold: $LFC"
  echo "------------------------------------------------------------------------------"

  START_TIME=$(date +%s)

  if [[ "$DIMENSION" == "all" ]]; then
    for dim in bacteria fungi virus; do
      echo ""
      run_differential "$dim"
      echo "------------------------------------------------------------------------------"
    done
  else
    run_differential "$DIMENSION"
  fi

  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))

  echo "=============================================================================="
  echo "[SUCCESS] Differential abundance analysis completed in ${ELAPSED}s"
  echo "Results: ${WORKDIR}/result/stat/{bacteria,fungi,virus}/differential"
  echo "Log: $LOG_FILE"
  echo "=============================================================================="

} 2>&1 | tee -a "$LOG_FILE"
