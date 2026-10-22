#!/bin/bash
# Description: Identify and optionally delete safe intermediate project files

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh" >/dev/null

# Parse arguments
SHOW_HELP=false
PROJECT_DIR=""
OLDER_THAN=7
EXECUTE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    -p|--project)
      if [ $# -lt 2 ]; then
        echo "Missing directory for $1" >&2
        exit 1
      fi
      PROJECT_DIR=$2
      shift 2
      ;;
    --older-than)
      if [ $# -lt 2 ]; then
        echo "Missing number of days for $1" >&2
        exit 1
      fi
      OLDER_THAN=$2
      shift 2
      ;;
    --dry-run)
      EXECUTE=false
      shift
      ;;
    --execute)
      EXECUTE=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then
  cat << 'EOF'
Usage: cleanup_intermediate.sh -p DIR [OPTIONS]

Identify and optionally delete large, safely-removable intermediate files from
a project's temp/ directory. Dry-run mode is used unless --execute is passed.

OPTIONS:
  -p, --project DIR       Project directory to scan (required)
      --older-than DAYS   Only include files older than DAYS (default: 7)
      --dry-run           Report candidates without deleting them (default)
      --execute           Delete reported candidates
  -h, --help              Show this help message

SAFE CANDIDATES:
  Uncompressed *.sam and *.fastq files, *_tmp.* files, and files below a tmp/
  or scratch/ subdirectory. Protected result and expensive-to-regenerate output
  patterns are always excluded.

EXAMPLES:
  # Preview cleanup candidates older than seven days
  bash scripts/utils/cleanup_intermediate.sh -p Project/Project01

  # Delete cleanup candidates older than fourteen days
  bash scripts/utils/cleanup_intermediate.sh -p Project/Project01 \
    --older-than 14 --execute
EOF
  exit 0
fi

if [ -z "$PROJECT_DIR" ]; then
  echo "Error: --project DIR is required." >&2
  echo "Run with --help for usage information." >&2
  exit 1
fi

if ! [[ "$OLDER_THAN" =~ ^[0-9]+$ ]]; then
  echo "Error: --older-than DAYS must be a non-negative integer." >&2
  exit 1
fi

if [[ "$PROJECT_DIR" != /* ]]; then
  PROJECT_DIR="${PROJ_DIR}/${PROJECT_DIR}"
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: project directory does not exist: ${PROJECT_DIR}" >&2
  exit 1
fi

TEMP_DIR="${PROJECT_DIR}/temp"

format_bytes() {
  awk -v bytes="$1" 'BEGIN {
    split("B KiB MiB GiB TiB", units, " ")
    unit = 1
    while (bytes >= 1024 && unit < 5) {
      bytes /= 1024
      unit++
    }
    if (unit == 1) {
      printf "%d %s", bytes, units[unit]
    } else {
      printf "%.2f %s", bytes, units[unit]
    }
  }'
}

candidate_count=0
total_bytes=0
reclaimed_bytes=0
current_epoch=$(date +%s)
minimum_age_minutes=$((OLDER_THAN * 1440))

if [ "$EXECUTE" = true ]; then
  echo "Mode: EXECUTE"
else
  echo "Mode: DRY RUN (no files will be deleted)"
fi
echo "Project: ${PROJECT_DIR}"
echo "Scan root: ${TEMP_DIR}"
echo "Minimum age: ${OLDER_THAN} days"
echo

if [ -d "$TEMP_DIR" ]; then
  while IFS= read -r -d '' candidate_relative; do
    candidate="${TEMP_DIR}/${candidate_relative#./}"

    if ! file_size=$(stat -c '%s' -- "$candidate" 2>/dev/null); then
      echo "Skipping unreadable file: ${candidate}" >&2
      continue
    fi
    if ! modified_epoch=$(stat -c '%Y' -- "$candidate" 2>/dev/null); then
      echo "Skipping unreadable file: ${candidate}" >&2
      continue
    fi

    age_days=$(((current_epoch - modified_epoch) / 86400))
    candidate_count=$((candidate_count + 1))
    total_bytes=$((total_bytes + file_size))
    file_size_human=$(format_bytes "$file_size")

    if [ "$EXECUTE" = true ]; then
      echo "DELETE: ${candidate} | size=${file_size_human} | age=${age_days} days"
      rm -f -- "$candidate"
      reclaimed_bytes=$((reclaimed_bytes + file_size))
      echo "  Reclaimed so far: $(format_bytes "$reclaimed_bytes")"
    else
      echo "WOULD DELETE: ${candidate} | size=${file_size_human} | age=${age_days} days"
    fi
  done < <(
    cd "$TEMP_DIR"
    find . -type f -mmin "+${minimum_age_minutes}" \
      \( \
        -name '*.sam' -o \
        -name '*.fastq' -o \
        -name '*_tmp.*' -o \
        -path '*/tmp/*' -o \
        -path '*/scratch/*' \
      \) \
      ! \( \
        -iname '*.bam' -o \
        -iname '*.fasta' -o \
        -iname '*.fa' -o \
        -iname '*.faa' -o \
        -iname '*.tsv' -o \
        -iname '*.csv' -o \
        -iname '*.txt' -o \
        -iname '*.json' -o \
        -ipath '*/result/*' -o \
        -ipath '*checkm2*' -o \
        -ipath '*gtdbtk*' -o \
        -ipath '*drep*' \
      \) \
      -print0
  )
else
  echo "No temp directory found; nothing to clean."
fi

echo
echo "Summary:"
echo "  Candidate files: ${candidate_count}"
echo "  Total candidate size: $(format_bytes "$total_bytes")"
if [ "$EXECUTE" = true ]; then
  echo "  Mode: executed"
  echo "  Space reclaimed: $(format_bytes "$reclaimed_bytes")"
else
  echo "  Mode: dry-run"
  echo "  Space that would be reclaimed: $(format_bytes "$total_bytes")"
fi
