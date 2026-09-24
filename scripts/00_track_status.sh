#!/bin/bash
# Task: Script execution status tracking
# Author: CSCCD-MetagenomeFlow team
# Date: 2026-08-20
# Description: Track and report execution status of all analysis scripts

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh"

# Parse arguments
SHOW_HELP=false
PROJECT_DIR=""
SUMMARY_ONLY=false
SHOW_PENDING=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    -p|--project)
      PROJECT_DIR="$2"
      shift 2
      ;;
    -s|--summary)
      SUMMARY_ONLY=true
      shift
      ;;
    --pending)
      SHOW_PENDING=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then
  cat << 'EOF'
Usage: 00_track_status.sh [OPTIONS]

Track and report execution status of all analysis scripts.

OPTIONS:
  -h, --help           Show this help message
  -p, --project DIR    Project directory to check (e.g., Project/Project01)
  -s, --summary        Show summary only (no per-script details)
  --pending            Show only pending/incomplete scripts

STATUS INDICATORS:
  ✓ DONE      - Output files exist and are recent
  ⚠ PARTIAL   - Some output files exist, but incomplete
  ✗ PENDING   - No output files found
  ⏱ RUNNING   - Log file actively being written

EXAMPLES:
  # Check status for a project
  bash scripts/00_track_status.sh -p Project/Project01

  # Show summary only
  bash scripts/00_track_status.sh -p Project/Project01 -s

  # Show only pending scripts
  bash scripts/00_track_status.sh -p Project/Project01 --pending

OUTPUT:
  Per-script status with expected output paths and completion indicators
EOF
  exit 0
fi

if [ -z "$PROJECT_DIR" ]; then
  echo "Error: --project DIR is required"
  echo "Example: bash scripts/00_track_status.sh -p Project/Project01"
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[ERROR] Project directory not found: $PROJECT_DIR"
  exit 1
fi

echo "========================================"
echo "Script Execution Status Tracker"
echo "========================================"
echo "Project: $PROJECT_DIR"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Define key checkpoint scripts and their expected outputs
declare -A SCRIPT_OUTPUTS

# Bacteria
SCRIPT_OUTPUTS["11_bac_kraken2.sh"]="${PROJECT_DIR}/temp/11_kraken2"
SCRIPT_OUTPUTS["12_bac_strainphlan4.sh"]="${PROJECT_DIR}/temp/12_strainphlan4"
SCRIPT_OUTPUTS["13_bac_humann.sh"]="${PROJECT_DIR}/temp/13_humann"
SCRIPT_OUTPUTS["21_bac_megahit.sh"]="${PROJECT_DIR}/temp/21_assembly"
SCRIPT_OUTPUTS["31_bac_metabat2.sh"]="${PROJECT_DIR}/temp/31_metabat2"
SCRIPT_OUTPUTS["32_bac_maxbin2.sh"]="${PROJECT_DIR}/temp/32_maxbin2"
SCRIPT_OUTPUTS["33_bac_semibin2.sh"]="${PROJECT_DIR}/temp/33_semibin2"
SCRIPT_OUTPUTS["34_bac_concoct.sh"]="${PROJECT_DIR}/temp/34_concoct"
SCRIPT_OUTPUTS["35_bac_dastool.sh"]="${PROJECT_DIR}/temp/35_dastool"
SCRIPT_OUTPUTS["36_bac_bin_refine.sh"]="${PROJECT_DIR}/temp/36_refine"
SCRIPT_OUTPUTS["37_bac_checkm2.sh"]="${PROJECT_DIR}/temp/37_checkm2"
SCRIPT_OUTPUTS["38_bac_drep.sh"]="${PROJECT_DIR}/temp/38_drep"
SCRIPT_OUTPUTS["39_bac_instrain.sh"]="${PROJECT_DIR}/temp/39_instrain"
SCRIPT_OUTPUTS["40_bac_gtdbtk.sh"]="${PROJECT_DIR}/temp/40_gtdbtk"
SCRIPT_OUTPUTS["41_bac_prokka.sh"]="${PROJECT_DIR}/temp/41_prokka"

# Virus
SCRIPT_OUTPUTS["53_vir_virsorter2.sh"]="${PROJECT_DIR}/temp/53_virsorter2"
SCRIPT_OUTPUTS["54_vir_checkv.sh"]="${PROJECT_DIR}/temp/54_checkv"
SCRIPT_OUTPUTS["56_vir_votu.sh"]="${PROJECT_DIR}/temp/56_votu"
SCRIPT_OUTPUTS["57_vir_genomad.sh"]="${PROJECT_DIR}/temp/57_genomad"
SCRIPT_OUTPUTS["61_vir_iphop.sh"]="${PROJECT_DIR}/temp/61_iphop"
SCRIPT_OUTPUTS["65_vir_phold.sh"]="${PROJECT_DIR}/temp/65_phold"

# Fungi
SCRIPT_OUTPUTS["71_fun_kraken2.sh"]="${PROJECT_DIR}/temp/71_kraken2_fungi"
SCRIPT_OUTPUTS["81_fun_eukcc2.sh"]="${PROJECT_DIR}/temp/81_eukcc2"

# Statistics
SCRIPT_OUTPUTS["91_diversity.R"]="${PROJECT_DIR}/result/diversity"
SCRIPT_OUTPUTS["96_stat_functional.sh"]="${PROJECT_DIR}/result/functional"

# Count status
TOTAL=0
DONE=0
PARTIAL=0
PENDING=0
RUNNING=0

check_script_status() {
  local SCRIPT=$1
  local OUTPUT_DIR=$2

  TOTAL=$((TOTAL + 1))

  # Check if output directory exists
  if [ ! -d "$OUTPUT_DIR" ]; then
    if [ "$SHOW_PENDING" = true ] || [ "$SUMMARY_ONLY" = false ]; then
      echo "✗ PENDING   $SCRIPT"
      [ "$SUMMARY_ONLY" = false ] && echo "            Expected: $OUTPUT_DIR"
    fi
    PENDING=$((PENDING + 1))
    return
  fi

  # Count files in output directory
  FILE_COUNT=$(find "$OUTPUT_DIR" -type f 2>/dev/null | wc -l)

  if [ "$FILE_COUNT" -eq 0 ]; then
    if [ "$SHOW_PENDING" = true ] || [ "$SUMMARY_ONLY" = false ]; then
      echo "✗ PENDING   $SCRIPT"
      [ "$SUMMARY_ONLY" = false ] && echo "            Output dir exists but empty: $OUTPUT_DIR"
    fi
    PENDING=$((PENDING + 1))
    return
  fi

  # Check if log file is actively being written (modified in last 5 minutes)
  LOG_DIR="${PROJECT_DIR}/logs"
  SCRIPT_BASE=$(basename "$SCRIPT" .sh)
  RECENT_LOG=$(find "$LOG_DIR" -name "${SCRIPT_BASE}*.log" -mmin -5 2>/dev/null | head -1)

  if [ -n "$RECENT_LOG" ]; then
    if [ "$SUMMARY_ONLY" = false ]; then
      echo "⏱ RUNNING   $SCRIPT"
      echo "            Active log: $RECENT_LOG"
      echo "            Output: $OUTPUT_DIR ($FILE_COUNT files)"
    fi
    RUNNING=$((RUNNING + 1))
    return
  fi

  # Check for expected result files (heuristic: look for common output patterns)
  KEY_FILES=$(find "$OUTPUT_DIR" -type f \( -name "*.tsv" -o -name "*.csv" -o -name "*.txt" -o -name "*.fa" -o -name "*.faa" \) 2>/dev/null | wc -l)

  if [ "$KEY_FILES" -ge 5 ]; then
    if [ "$SUMMARY_ONLY" = false ] && [ "$SHOW_PENDING" = false ]; then
      echo "✓ DONE      $SCRIPT"
      echo "            Output: $OUTPUT_DIR ($FILE_COUNT files, $KEY_FILES key files)"
    fi
    DONE=$((DONE + 1))
  else
    if [ "$SUMMARY_ONLY" = false ]; then
      echo "⚠ PARTIAL   $SCRIPT"
      echo "            Output: $OUTPUT_DIR ($FILE_COUNT files, only $KEY_FILES key files)"
      echo "            May need to re-run or check logs"
    fi
    PARTIAL=$((PARTIAL + 1))
  fi
}

# Check each script
if [ "$SUMMARY_ONLY" = false ]; then
  echo "## Script Status Details"
  echo ""

  echo "### Bacteria Analysis"
  for SCRIPT in 11_bac_kraken2.sh 12_bac_strainphlan4.sh 13_bac_humann.sh \
                21_bac_megahit.sh 31_bac_metabat2.sh 32_bac_maxbin2.sh \
                33_bac_semibin2.sh 34_bac_concoct.sh 35_bac_dastool.sh \
                36_bac_bin_refine.sh 37_bac_checkm2.sh 38_bac_drep.sh \
                39_bac_instrain.sh 40_bac_gtdbtk.sh 41_bac_prokka.sh; do
    check_script_status "$SCRIPT" "${SCRIPT_OUTPUTS[$SCRIPT]}"
  done
  echo ""

  echo "### Virus Analysis"
  for SCRIPT in 53_vir_virsorter2.sh 54_vir_checkv.sh 56_vir_votu.sh \
                57_vir_genomad.sh 61_vir_iphop.sh 65_vir_phold.sh; do
    check_script_status "$SCRIPT" "${SCRIPT_OUTPUTS[$SCRIPT]}"
  done
  echo ""

  echo "### Fungi Analysis"
  for SCRIPT in 71_fun_kraken2.sh 81_fun_eukcc2.sh; do
    check_script_status "$SCRIPT" "${SCRIPT_OUTPUTS[$SCRIPT]}"
  done
  echo ""

  echo "### Statistics & Integration"
  for SCRIPT in 91_diversity.R 96_stat_functional.sh; do
    check_script_status "$SCRIPT" "${SCRIPT_OUTPUTS[$SCRIPT]}"
  done
  echo ""
else
  for SCRIPT in "${!SCRIPT_OUTPUTS[@]}"; do
    check_script_status "$SCRIPT" "${SCRIPT_OUTPUTS[$SCRIPT]}"
  done
fi

# Summary
echo "========================================"
echo "Summary"
echo "========================================"
echo "Total tracked scripts: $TOTAL"
echo "  ✓ DONE:     $DONE"
echo "  ⏱ RUNNING:  $RUNNING"
echo "  ⚠ PARTIAL:  $PARTIAL"
echo "  ✗ PENDING:  $PENDING"
echo ""

COMPLETION_RATE=$((DONE * 100 / TOTAL))
echo "Completion rate: ${COMPLETION_RATE}%"
echo ""

if [ $PENDING -gt 0 ]; then
  echo "[INFO] $PENDING scripts have not been executed yet"
fi

if [ $PARTIAL -gt 0 ]; then
  echo "[WARN] $PARTIAL scripts may need attention (partial output)"
fi

if [ $RUNNING -gt 0 ]; then
  echo "[INFO] $RUNNING scripts are currently running"
fi
