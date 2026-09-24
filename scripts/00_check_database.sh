#!/bin/bash
# Task: Database integrity self-check
# Author: CSCCD-MetagenomeFlow team
# Date: 2026-08-20
# Description: Verify integrity and accessibility of all analysis databases

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh"

# Parse arguments
SHOW_HELP=false
CHECK_ALL=false
CHECK_BACTERIA=false
CHECK_VIRUS=false
CHECK_FUNGI=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    -a|--all)
      CHECK_ALL=true
      shift
      ;;
    -b|--bacteria)
      CHECK_BACTERIA=true
      shift
      ;;
    -v|--virus)
      CHECK_VIRUS=true
      shift
      ;;
    -f|--fungi)
      CHECK_FUNGI=true
      shift
      ;;
    --verbose)
      VERBOSE=true
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
Usage: 00_check_database.sh [OPTIONS]

Verify integrity and accessibility of all analysis databases.

OPTIONS:
  -h, --help        Show this help message
  -a, --all         Check all databases (default if no specific check requested)
  -b, --bacteria    Check bacterial analysis databases only
  -v, --virus       Check viral analysis databases only
  -f, --fungi       Check fungal analysis databases only
  --verbose         Show detailed file listings

EXAMPLES:
  # Check all databases
  bash scripts/00_check_database.sh -a

  # Check only bacterial databases
  bash scripts/00_check_database.sh -b

  # Check with verbose output
  bash scripts/00_check_database.sh -a --verbose

OUTPUT:
  - [OK] Database accessible and non-empty
  - [MISSING] Database directory or key files not found
  - [EMPTY] Database directory exists but appears empty
  - [WARN] Database accessible but may have integrity issues
EOF
  exit 0
fi

# If no specific check requested, default to --all
if [ "$CHECK_ALL" = false ] && [ "$CHECK_BACTERIA" = false ] && [ "$CHECK_VIRUS" = false ] && [ "$CHECK_FUNGI" = false ]; then
  CHECK_ALL=true
fi

echo "========================================"
echo "CSCCD-MetagenomeFlow Database Integrity Check"
echo "========================================"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

DB_DIR="${PROJ_DIR}/db"
TOTAL_CHECKED=0
TOTAL_OK=0
TOTAL_MISSING=0
TOTAL_WARN=0

check_directory() {
  local DB_PATH=$1
  local DB_NAME=$2
  local REQUIRED_FILES=$3

  TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

  if [ ! -d "$DB_PATH" ]; then
    echo "[MISSING] $DB_NAME: Directory not found at $DB_PATH"
    TOTAL_MISSING=$((TOTAL_MISSING + 1))
    return 1
  fi

  FILE_COUNT=$(find "$DB_PATH" -type f 2>/dev/null | wc -l)
  DB_SIZE=$(du -sh "$DB_PATH" 2>/dev/null | awk '{print $1}')

  if [ "$FILE_COUNT" -eq 0 ]; then
    echo "[EMPTY] $DB_NAME: Directory exists but contains no files"
    TOTAL_WARN=$((TOTAL_WARN + 1))
    return 1
  fi

  if [ -n "$REQUIRED_FILES" ]; then
    MISSING_FILES=""
    for REQ_FILE in $REQUIRED_FILES; do
      if [ ! -f "${DB_PATH}/${REQ_FILE}" ] && [ ! -d "${DB_PATH}/${REQ_FILE}" ]; then
        MISSING_FILES="${MISSING_FILES} ${REQ_FILE}"
      fi
    done

    if [ -n "$MISSING_FILES" ]; then
      echo "[WARN] $DB_NAME: Missing required files:$MISSING_FILES"
      echo "       Location: $DB_PATH"
      echo "       Size: $DB_SIZE | Files: $FILE_COUNT"
      TOTAL_WARN=$((TOTAL_WARN + 1))
      return 1
    fi
  fi

  echo "[OK] $DB_NAME"
  echo "     Location: $DB_PATH"
  echo "     Size: $DB_SIZE | Files: $FILE_COUNT"

  if [ "$VERBOSE" = true ]; then
    echo "     Key files:"
    find "$DB_PATH" -maxdepth 2 -type f 2>/dev/null | head -10 | sed 's/^/       /'
  fi

  TOTAL_OK=$((TOTAL_OK + 1))
  return 0
}

# Bacteria databases
if [ "$CHECK_BACTERIA" = true ] || [ "$CHECK_ALL" = true ]; then
  echo "## Bacterial Analysis Databases"
  echo ""

  check_directory "${DB_DIR}/kraken2/k2_standard_20240605" "Kraken2 Standard" "hash.k2d opts.k2d taxo.k2d"
  echo ""

  check_directory "${DB_DIR}/metaphlan4/mpa_vJan21_CHOCOPhlAnSGB_202103" "MetaPhlAn4" "mpa_vJan21_CHOCOPhlAnSGB_202103.pkl"
  echo ""

  check_directory "${DB_DIR}/humann/chocophlan" "HUMAnN ChocoPhlAn" ""
  echo ""

  check_directory "${DB_DIR}/humann/uniref" "HUMAnN UniRef90" ""
  echo ""

  check_directory "${DB_DIR}/checkm2/uniref100.KO.1.dmnd" "CheckM2" ""
  echo ""

  check_directory "${DB_DIR}/gtdbtk/release220" "GTDB-Tk r220" "taxonomy"
  echo ""

  check_directory "${DB_DIR}/dRep/MASH_sketches" "dRep MASH" ""
  echo ""

  check_directory "${DB_DIR}/prokka" "Prokka" ""
  echo ""
fi

# Virus databases
if [ "$CHECK_VIRUS" = true ] || [ "$CHECK_ALL" = true ]; then
  echo "## Viral Analysis Databases"
  echo ""

  check_directory "${DB_DIR}/virsorter2/db" "VirSorter2" ""
  echo ""

  check_directory "${DB_DIR}/checkv/checkv-db-v1.5" "CheckV v1.5" "genome_db"
  echo ""

  check_directory "${DB_DIR}/genomad/genomad_db" "geNomad" ""
  echo ""

  check_directory "${DB_DIR}/iphop/iPHoP_db" "iPHoP" ""
  echo ""

  check_directory "${DB_DIR}/pharokka/pharokka_db" "Pharokka" ""
  echo ""
fi

# Fungi databases
if [ "$CHECK_FUNGI" = true ] || [ "$CHECK_ALL" = true ]; then
  echo "## Fungal Analysis Databases"
  echo ""

  check_directory "${DB_DIR}/kraken2/k2_fungi_20240605" "Kraken2 Fungi" "hash.k2d opts.k2d taxo.k2d"
  echo ""

  check_directory "${DB_DIR}/eukcc2" "EukCC2" ""
  echo ""
fi

# Summary
echo "========================================"
echo "Summary"
echo "========================================"
echo "Total databases checked: $TOTAL_CHECKED"
echo "  [OK]:      $TOTAL_OK"
echo "  [MISSING]: $TOTAL_MISSING"
echo "  [WARN]:    $TOTAL_WARN"
echo ""

if [ "$TOTAL_MISSING" -gt 0 ] || [ "$TOTAL_WARN" -gt 0 ]; then
  echo "[ACTION REQUIRED]"
  echo "Some databases are missing or incomplete."
  echo "Refer to docs/database_setup.md for download instructions."
  exit 1
else
  echo "All databases are accessible and appear intact."
  exit 0
fi
