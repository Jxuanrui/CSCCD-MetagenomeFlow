#!/bin/bash
# Description: Recommend available Snakemake CPU and memory resources

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh" >/dev/null

# Parse arguments
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 0
      ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then
  cat << 'EOF'
Usage: recommend_resources.sh [OPTIONS]

Recommend Snakemake CPU and memory limits based on system capacity and
resources used by currently running project analysis jobs.

OPTIONS:
  -h, --help      Show this help message

OUTPUT:
  A human-readable resource summary on stderr and a Snakemake recommendation
  on stdout in the format: --cores <N> --resources mem_mb=<M>

EXAMPLES:
  # Get resource limits for a new Snakemake run
  bash scripts/utils/recommend_resources.sh
EOF
  exit 0
fi

total_cores=$(nproc)
total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')

running_jobs_json="$("$(dirname "${BASH_SOURCE[0]}")/detect_running_jobs.sh")"

used_cpu_percent_sum=$(printf '%s\n' "$running_jobs_json" | \
  grep -oP '"cpu_percent":[0-9.]+' | \
  sed 's/"cpu_percent"://' | \
  awk '{sum += $1} END {printf "%.2f", sum + 0}')
used_mem_mb_sum=$(printf '%s\n' "$running_jobs_json" | \
  grep -oP '"mem_mb":[0-9]+' | \
  sed 's/"mem_mb"://' | \
  awk '{sum += $1} END {print sum + 0}')

used_cores=$(awk -v cpu_percent="$used_cpu_percent_sum" '
  BEGIN {
    whole_cores = int(cpu_percent / 100)
    if (cpu_percent > whole_cores * 100) {
      whole_cores++
    }
    print whole_cores
  }
')

available_cores=$((total_cores - used_cores - 2))
available_mem_mb=$((total_mem_mb - used_mem_mb_sum - 4096))

if [ "$available_cores" -lt 1 ]; then
  available_cores=1
fi

if [ "$available_mem_mb" -lt 1024 ]; then
  available_mem_mb=1024
fi

echo "Resource recommendation:" >&2
echo "  CPU cores: total=${total_cores}, used_by_jobs=${used_cores} (${used_cpu_percent_sum}%), reserved=2, available=${available_cores}" >&2
echo "  Memory MB: total=${total_mem_mb}, used_by_jobs=${used_mem_mb_sum}, reserved=4096, available=${available_mem_mb}" >&2

echo "--cores ${available_cores} --resources mem_mb=${available_mem_mb}"
