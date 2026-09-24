#!/bin/bash
# Task: Database preloading and index optimization
# Author: CSCCD-MetagenomeFlow team
# Date: 2026-08-20
# Description: Preload frequently accessed databases into filesystem cache to reduce I/O latency

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh"

# Parse arguments
SHOW_HELP=false
PRELOAD_ALL=false
PRELOAD_BACTERIA=false
PRELOAD_VIRUS=false
PRELOAD_FUNGI=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    -a|--all)
      PRELOAD_ALL=true
      shift
      ;;
    -b|--bacteria)
      PRELOAD_BACTERIA=true
      shift
      ;;
    -v|--virus)
      PRELOAD_VIRUS=true
      shift
      ;;
    -f|--fungi)
      PRELOAD_FUNGI=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
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
Usage: 00_preload_database.sh [OPTIONS]

Preload frequently accessed databases into filesystem cache to reduce I/O latency.

OPTIONS:
  -h, --help        Show this help message
  -a, --all         Preload all databases (default if no specific option given)
  -b, --bacteria    Preload bacterial analysis databases only
  -v, --virus       Preload viral analysis databases only
  -f, --fungi       Preload fungal analysis databases only
  --dry-run         Show what would be preloaded without actually doing it

MECHANISM:
  Uses `cat file > /dev/null` to read database files into the Linux page cache.
  Subsequent access to these files will be served from RAM instead of disk,
  significantly reducing I/O latency for the first samples in a batch.

RECOMMENDED TIMING:
  - Run once after server reboot
  - Run before starting a new analysis batch
  - Run periodically on long-running servers (e.g., daily via cron)

EXAMPLES:
  # Preload all databases
  bash scripts/00_preload_database.sh -a

  # Preload only bacterial databases before a bacteria-only analysis
  bash scripts/00_preload_database.sh -b

  # Dry run to see what would be preloaded
  bash scripts/00_preload_database.sh -a --dry-run

NOTES:
  - Preloading is I/O intensive but CPU-light
  - Total time depends on database size and disk speed
  - Effect persists until files are evicted from cache (memory pressure or reboot)
  - Use `vmtouch -v <path>` to check if files are cached (requires vmtouch package)
EOF
  exit 0
fi

# If no specific option given, default to --all
if [ "$PRELOAD_ALL" = false ] && [ "$PRELOAD_BACTERIA" = false ] && [ "$PRELOAD_VIRUS" = false ] && [ "$PRELOAD_FUNGI" = false ]; then
  PRELOAD_ALL=true
fi

echo "========================================"
echo "Database Preloading Utility"
echo "========================================"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Mode: $([ "$DRY_RUN" = true ] && echo 'DRY RUN' || echo 'EXECUTE')"
echo ""

DB_DIR="${PROJ_DIR}/db"
TOTAL_SIZE=0
TOTAL_FILES=0
START_TIME=$(date +%s)

preload_directory() {
  local DB_PATH=$1
  local DB_NAME=$2
  local PRIORITY=$3  # high, medium, low

  if [ ! -d "$DB_PATH" ]; then
    echo "[SKIP] $DB_NAME: Directory not found at $DB_PATH"
    return
  fi

  DB_SIZE_BYTES=$(du -sb "$DB_PATH" 2>/dev/null | awk '{print $1}')
  DB_SIZE_HUMAN=$(du -sh "$DB_PATH" 2>/dev/null | awk '{print $1}')
  FILE_COUNT=$(find "$DB_PATH" -type f 2>/dev/null | wc -l)

  if [ "$FILE_COUNT" -eq 0 ]; then
    echo "[SKIP] $DB_NAME: No files to preload"
    return
  fi

  echo "[$PRIORITY] $DB_NAME"
  echo "        Path: $DB_PATH"
  echo "        Size: $DB_SIZE_HUMAN | Files: $FILE_COUNT"

  if [ "$DRY_RUN" = true ]; then
    echo "        [DRY RUN] Would preload $FILE_COUNT files"
  else
    echo -n "        Preloading..."

    # Use find + cat to read all files into cache
    # Redirect stderr to suppress "Is a directory" warnings
    find "$DB_PATH" -type f -exec cat {} \; > /dev/null 2>&1

    echo " done"
  fi

  TOTAL_SIZE=$((TOTAL_SIZE + DB_SIZE_BYTES))
  TOTAL_FILES=$((TOTAL_FILES + FILE_COUNT))
  echo ""
}

# Bacteria databases
if [ "$PRELOAD_BACTERIA" = true ] || [ "$PRELOAD_ALL" = true ]; then
  echo "## Bacterial Analysis Databases"
  echo ""

  # High priority: frequently accessed, size-critical
  preload_directory "${DB_DIR}/kraken2/k2_standard_20240605" "Kraken2 Standard" "HIGH"
  preload_directory "${DB_DIR}/metaphlan4/mpa_vJan21_CHOCOPhlAnSGB_202103" "MetaPhlAn4" "HIGH"

  # Medium priority: used in downstream analysis
  preload_directory "${DB_DIR}/humann/chocophlan" "HUMAnN ChocoPhlAn" "MED"
  preload_directory "${DB_DIR}/humann/uniref" "HUMAnN UniRef90" "MED"
  preload_directory "${DB_DIR}/checkm2/uniref100.KO.1.dmnd" "CheckM2" "MED"

  # Low priority: large but accessed only once per MAG
  preload_directory "${DB_DIR}/gtdbtk/release220" "GTDB-Tk r220" "LOW"
  preload_directory "${DB_DIR}/prokka" "Prokka" "LOW"
fi

# Virus databases
if [ "$PRELOAD_VIRUS" = true ] || [ "$PRELOAD_ALL" = true ]; then
  echo "## Viral Analysis Databases"
  echo ""

  preload_directory "${DB_DIR}/virsorter2/db" "VirSorter2" "HIGH"
  preload_directory "${DB_DIR}/checkv/checkv-db-v1.5" "CheckV" "HIGH"
  preload_directory "${DB_DIR}/genomad/genomad_db" "geNomad" "MED"
  preload_directory "${DB_DIR}/iphop/iPHoP_db" "iPHoP" "MED"
  preload_directory "${DB_DIR}/pharokka/pharokka_db" "Pharokka" "LOW"
fi

# Fungi databases
if [ "$PRELOAD_FUNGI" = true ] || [ "$PRELOAD_ALL" = true ]; then
  echo "## Fungal Analysis Databases"
  echo ""

  preload_directory "${DB_DIR}/kraken2/k2_fungi_20240605" "Kraken2 Fungi" "HIGH"
  preload_directory "${DB_DIR}/eukcc2" "EukCC2" "MED"
fi

# Summary
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024 / 1024" | bc)

echo "========================================"
echo "Summary"
echo "========================================"
echo "Total files processed: $TOTAL_FILES"
echo "Total size: ${TOTAL_SIZE_GB} GB"
echo "Elapsed time: ${ELAPSED} seconds"

if [ "$DRY_RUN" = false ]; then
  echo ""
  echo "[INFO] Database preloading complete."
  echo "[INFO] Subsequent database access will be faster (served from RAM)."
  echo "[INFO] Effect persists until memory pressure or reboot."
else
  echo ""
  echo "[INFO] Dry run complete. Use without --dry-run to actually preload."
fi

echo "========================================"
