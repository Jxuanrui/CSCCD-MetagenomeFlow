#!/bin/bash
# Description: Report active analysis processes and their resource usage as JSON

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
Usage: detect_running_jobs.sh [OPTIONS]

Detect active SPAdes, Snakemake, and project Python analysis processes.
Reports process resource usage as a JSON array on stdout.

OPTIONS:
  -h, --help      Show this help message

OUTPUT:
  A JSON array containing one object per detected process. Each object includes
  process_type, pid, cpu_percent, mem_mb, elapsed_time, and command.

EXAMPLES:
  # Detect currently running analysis jobs
  bash scripts/utils/detect_running_jobs.sh
EOF
  exit 0
fi

escape_json_string() {
  local value=$1

  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

printf '['
first_process=true

while IFS= read -r pid; do
  [ -n "$pid" ] || continue

  command=$(ps -p "$pid" -o args= 2>/dev/null || true)
  [ -n "$command" ] || continue

  if [[ "$command" =~ (spades\.py|metaspades\.py) ]]; then
    process_type="spades"
  elif [[ "$command" =~ snakemake ]]; then
    process_type="snakemake"
  elif [[ "$command" =~ python.*scripts/ ]]; then
    process_type="python"
  else
    continue
  fi

  cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d '[:space:]' || true)
  rss_kb=$(ps -p "$pid" -o rss= 2>/dev/null | tr -d '[:space:]' || true)
  elapsed_time=$(ps -p "$pid" -o etime= 2>/dev/null | sed 's/^[[:space:]]*//' || true)

  [[ "$cpu_percent" =~ ^[0-9]+([.][0-9]+)?$ ]] || cpu_percent=0
  [[ "$rss_kb" =~ ^[0-9]+$ ]] || rss_kb=0
  [ -n "$elapsed_time" ] || elapsed_time="Unknown"

  mem_mb=$((rss_kb / 1024))
  command=${command:0:80}
  command=$(escape_json_string "$command")

  if [ "$first_process" = false ]; then
    printf ','
  fi

  printf '{"process_type":"%s","pid":%s,"cpu_percent":%s,"mem_mb":%s,"elapsed_time":"%s","command":"%s"}' \
    "$process_type" "$pid" "$cpu_percent" "$mem_mb" "$elapsed_time" "$command"
  first_process=false
done < <(pgrep -f 'spades\.py|metaspades\.py|snakemake|python.*scripts/' || true)

printf ']\n'
