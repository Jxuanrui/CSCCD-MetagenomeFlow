#!/bin/bash
# Task: Sample metadata validation
# Author: CSCCD-MetagenomeFlow team
# Date: 2026-08-20
# Description: Validate sample metadata completeness and format

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh"
source "${PROJ_DIR}/scripts/utils/libcommon.sh"

show_help() {
cat << 'EOF'
Usage: 00_validate_metadata.sh [OPTIONS]

Validate sample metadata completeness and format.

OPTIONS:
  -h, --help              Show this help message
  -m, --metadata FILE     Path to metadata CSV/TSV file
  --strict                Enable strict validation (fail on warnings)

VALIDATION CHECKS:
  1. Required columns: sample_id, group, fastq_1, fastq_2
  2. Sample ID format: alphanumeric + underscore/dash only
  3. FASTQ file existence
  4. Duplicate sample IDs
  5. Empty values in required fields
  6. Group name consistency

EXAMPLES:
  # Validate metadata file
  bash scripts/00_validate_metadata.sh -m Project/Project01/metadata.csv

  # Strict mode (fail on warnings)
  bash scripts/00_validate_metadata.sh -m metadata.csv --strict

OUTPUT:
  - [OK] All validations passed
  - [WARN] Non-critical issues found
  - [ERROR] Critical issues that will cause pipeline failure
EOF
}

# MGX_* tables are consumed by mgx_parse (libcommon.sh); short + long aliases map to the same vars
export MGX_OPTS_STRING="m:METADATA_FILE"
export MGX_OPTS_LONG="metadata:METADATA_FILE"
export MGX_OPTS_FLAG="strict"
mgx_parse "$@"
mgx_require METADATA_FILE

if [ ! -f "$METADATA_FILE" ]; then
  echo "[ERROR] Metadata file not found: $METADATA_FILE"
  exit 1
fi

echo "========================================"
echo "Sample Metadata Validation Report"
echo "========================================"
echo "File: $METADATA_FILE"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Detect delimiter
FIRST_LINE=$(head -1 "$METADATA_FILE")
if [[ "$FIRST_LINE" == *","* ]]; then
  DELIMITER=","
  echo "Detected format: CSV (comma-separated)"
elif [[ "$FIRST_LINE" == *$'\t'* ]]; then
  DELIMITER=$'\t'
  echo "Detected format: TSV (tab-separated)"
else
  echo "[ERROR] Cannot detect delimiter (expected CSV or TSV)"
  exit 1
fi
echo ""

# Extract header
HEADER=$(head -1 "$METADATA_FILE")
IFS="$DELIMITER" read -ra COLUMNS <<< "$HEADER"

echo "## Column Check"
echo ""
echo "Found columns: ${#COLUMNS[@]}"
for i in "${!COLUMNS[@]}"; do
  echo "  [$((i+1))] ${COLUMNS[$i]}"
done
echo ""

# Check required columns
REQUIRED_COLS=("sample_id" "group" "fastq_1" "fastq_2")
MISSING_COLS=()

for REQ_COL in "${REQUIRED_COLS[@]}"; do
  FOUND=false
  for COL in "${COLUMNS[@]}"; do
    if [ "$COL" = "$REQ_COL" ]; then
      FOUND=true
      break
    fi
  done
  if [ "$FOUND" = false ]; then
    MISSING_COLS+=("$REQ_COL")
  fi
done

if [ ${#MISSING_COLS[@]} -gt 0 ]; then
  echo "[ERROR] Missing required columns: ${MISSING_COLS[*]}"
  echo ""
  exit 1
else
  echo "[OK] All required columns present"
  echo ""
fi

# Find column indices
SAMPLE_ID_IDX=-1
GROUP_IDX=-1
FASTQ1_IDX=-1
FASTQ2_IDX=-1

for i in "${!COLUMNS[@]}"; do
  case "${COLUMNS[$i]}" in
    sample_id) SAMPLE_ID_IDX=$i ;;
    group) GROUP_IDX=$i ;;
    fastq_1) FASTQ1_IDX=$i ;;
    fastq_2) FASTQ2_IDX=$i ;;
  esac
done

# Validate data rows
echo "## Data Row Validation"
echo ""

LINE_NUM=1
ERROR_COUNT=0
WARN_COUNT=0
declare -A SAMPLE_IDS
declare -A GROUP_NAMES

while IFS="$DELIMITER" read -ra FIELDS; do
  LINE_NUM=$((LINE_NUM + 1))

  # Skip header
  if [ $LINE_NUM -eq 2 ]; then
    continue
  fi

  SAMPLE_ID="${FIELDS[$SAMPLE_ID_IDX]}"
  GROUP="${FIELDS[$GROUP_IDX]}"
  FASTQ1="${FIELDS[$FASTQ1_IDX]}"
  FASTQ2="${FIELDS[$FASTQ2_IDX]}"

  # Check 1: Empty sample_id
  if [ -z "$SAMPLE_ID" ]; then
    echo "[ERROR] Line $LINE_NUM: Empty sample_id"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    continue
  fi

  # Check 2: Sample ID format
  if [[ ! "$SAMPLE_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "[ERROR] Line $LINE_NUM: Invalid sample_id format: $SAMPLE_ID"
    echo "        Only alphanumeric, underscore, and dash allowed"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi

  # Check 3: Duplicate sample_id
  if [ -n "${SAMPLE_IDS[$SAMPLE_ID]}" ]; then
    echo "[ERROR] Line $LINE_NUM: Duplicate sample_id: $SAMPLE_ID"
    echo "        First occurrence at line ${SAMPLE_IDS[$SAMPLE_ID]}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  else
    SAMPLE_IDS[$SAMPLE_ID]=$LINE_NUM
  fi

  # Check 4: Empty group
  if [ -z "$GROUP" ]; then
    echo "[ERROR] Line $LINE_NUM: Empty group for sample $SAMPLE_ID"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  else
    GROUP_NAMES[$GROUP]=1
  fi

  # Check 5: Empty FASTQ paths
  if [ -z "$FASTQ1" ]; then
    echo "[ERROR] Line $LINE_NUM: Empty fastq_1 for sample $SAMPLE_ID"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi

  if [ -z "$FASTQ2" ]; then
    echo "[WARN] Line $LINE_NUM: Empty fastq_2 for sample $SAMPLE_ID (single-end?)"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi

  # Check 6: FASTQ file existence (relative to metadata file directory)
  METADATA_DIR=$(dirname "$METADATA_FILE")

  if [ -n "$FASTQ1" ]; then
    FASTQ1_PATH="${METADATA_DIR}/${FASTQ1}"
    if [ ! -f "$FASTQ1_PATH" ]; then
      echo "[ERROR] Line $LINE_NUM: fastq_1 not found: $FASTQ1"
      echo "        Checked path: $FASTQ1_PATH"
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
  fi

  if [ -n "$FASTQ2" ]; then
    FASTQ2_PATH="${METADATA_DIR}/${FASTQ2}"
    if [ ! -f "$FASTQ2_PATH" ]; then
      echo "[ERROR] Line $LINE_NUM: fastq_2 not found: $FASTQ2"
      echo "        Checked path: $FASTQ2_PATH"
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
  fi

done < "$METADATA_FILE"

TOTAL_SAMPLES=$((LINE_NUM - 2))

if [ $ERROR_COUNT -eq 0 ] && [ $WARN_COUNT -eq 0 ]; then
  echo "[OK] All $TOTAL_SAMPLES samples validated successfully"
  echo ""
fi

# Summary
echo "========================================"
echo "Summary"
echo "========================================"
echo "Total samples: $TOTAL_SAMPLES"
echo "Unique groups: ${#GROUP_NAMES[@]}"
echo "  Groups: ${!GROUP_NAMES[*]}"
echo ""
echo "Errors:   $ERROR_COUNT"
echo "Warnings: $WARN_COUNT"
echo ""

if [ $ERROR_COUNT -gt 0 ]; then
  echo "[FAILED] Validation failed with $ERROR_COUNT errors"
  exit 1
elif [ $WARN_COUNT -gt 0 ] && [ ${STRICT} -eq 1 ]; then
  echo "[FAILED] Strict mode: $WARN_COUNT warnings treated as errors"
  exit 1
else
  echo "[PASSED] Metadata validation successful"
  exit 0
fi
