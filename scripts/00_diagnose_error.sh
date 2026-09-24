#!/bin/bash
# Task: Error diagnosis and recovery mechanism
# Author: CSCCD-MetagenomeFlow team
# Date: 2026-08-20
# Description: Diagnose common pipeline errors and suggest recovery actions

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh"

# Parse arguments
SHOW_HELP=false
CHECK_RUNNING=false
CHECK_LOGS=false
CHECK_DISK=false
CHECK_ALL=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    -r|--running)
      CHECK_RUNNING=true
      shift
      ;;
    -l|--logs)
      CHECK_LOGS=true
      shift
      ;;
    -d|--disk)
      CHECK_DISK=true
      shift
      ;;
    -a|--all)
      CHECK_ALL=true
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
Usage: 00_diagnose_error.sh [OPTIONS]

Diagnose common pipeline errors and suggest recovery actions.

OPTIONS:
  -h, --help      Show this help message
  -r, --running   Check running processes (SPAdes, Snakemake, Python)
  -l, --logs      Scan recent log files for errors
  -d, --disk      Check disk space and temp directory usage
  -a, --all       Run all diagnostic checks

EXAMPLES:
  # Check running processes
  bash scripts/00_diagnose_error.sh -r

  # Check logs for errors
  bash scripts/00_diagnose_error.sh -l

  # Run all diagnostics
  bash scripts/00_diagnose_error.sh -a

OUTPUT:
  Prints diagnostic report to stdout with color-coded severity:
  - [ERROR] (red): Critical issues requiring immediate action
  - [WARN] (yellow): Potential issues to monitor
  - [INFO] (green): Normal status or suggestions
EOF
  exit 0
fi

# If no specific check requested, default to --all
if [ "$CHECK_RUNNING" = false ] && [ "$CHECK_LOGS" = false ] && [ "$CHECK_DISK" = false ]; then
  CHECK_ALL=true
fi

echo "========================================"
echo "CSCCD-MetagenomeFlow Pipeline Diagnostic Report"
echo "========================================"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check 1: Running processes
if [ "$CHECK_RUNNING" = true ] || [ "$CHECK_ALL" = true ]; then
  echo "## Check 1: Running Processes"
  echo ""

  SPADES_PROCS=$(pgrep -f 'spades.py|metaspades.py' || true)
  SNAKEMAKE_PROCS=$(pgrep -f 'snakemake' || true)
  PYTHON_PROCS=$(pgrep -f 'python.*scripts/' || true)

  if [ -n "$SPADES_PROCS" ]; then
    echo "[INFO] SPAdes processes detected:"
    ps aux | grep -E 'spades.py|metaspades.py' | grep -v grep | awk '{print "  PID "$2" | Started "$9" | Command: "$11" "$12" "$13}'
    echo ""

    for PID in $SPADES_PROCS; do
      START_TIME=$(ps -p $PID -o lstart= 2>/dev/null || echo "Unknown")
      ELAPSED=$(ps -p $PID -o etime= 2>/dev/null || echo "Unknown")
      echo "  - PID $PID: Started $START_TIME, Running for $ELAPSED"

      if [ "$ELAPSED" != "Unknown" ]; then
        DAYS=$(echo $ELAPSED | grep -oP '\d+(?=-\d+:\d+:\d+)' || echo "0")
        if [ "$DAYS" -ge 2 ]; then
          echo "    [WARN] This SPAdes process has been running for $DAYS days."
          echo "    [WARN] Check if it's stuck: look for repeating log lines or no disk I/O."
        fi
      fi
    done
    echo ""
  else
    echo "[INFO] No SPAdes processes running."
    echo ""
  fi

  if [ -n "$SNAKEMAKE_PROCS" ]; then
    echo "[INFO] Snakemake processes detected:"
    ps aux | grep snakemake | grep -v grep | awk '{print "  PID "$2" | Started "$9}'
    echo ""
  fi

  if [ -n "$PYTHON_PROCS" ]; then
    echo "[INFO] Analysis script processes detected:"
    ps aux | grep 'python.*scripts/' | grep -v grep | head -5 | awk '{print "  PID "$2" | Command: "$11" "$12}'
    echo ""
  fi
fi

# Check 2: Log file errors
if [ "$CHECK_LOGS" = true ] || [ "$CHECK_ALL" = true ]; then
  echo "## Check 2: Recent Log Errors"
  echo ""

  LOG_DIRS=(
    "${PROJ_DIR}/Project/Project01/logs"
    "${PROJ_DIR}/Project/Project_example/logs"
  )

  ERROR_FOUND=false

  for LOG_DIR in "${LOG_DIRS[@]}"; do
    if [ -d "$LOG_DIR" ]; then
      RECENT_LOGS=$(find "$LOG_DIR" -name "*.log" -mtime -1 2>/dev/null || true)

      if [ -n "$RECENT_LOGS" ]; then
        for LOG in $RECENT_LOGS; do
          ERRORS=$(grep -iE 'error|failed|exception|killed|out of memory' "$LOG" 2>/dev/null | head -5 || true)
          if [ -n "$ERRORS" ]; then
            ERROR_FOUND=true
            echo "[ERROR] Found errors in: $LOG"
            echo "$ERRORS" | sed 's/^/  /'
            echo ""
          fi
        done
      fi
    fi
  done

  if [ "$ERROR_FOUND" = false ]; then
    echo "[INFO] No recent errors found in log files."
    echo ""
  fi
fi

# Check 3: Disk space
if [ "$CHECK_DISK" = true ] || [ "$CHECK_ALL" = true ]; then
  echo "## Check 3: Disk Space"
  echo ""

  DISK_USAGE=$(df -h "${PROJ_DIR}" | tail -1 | awk '{print $5}' | sed 's/%//')
  DISK_AVAIL=$(df -h "${PROJ_DIR}" | tail -1 | awk '{print $4}')

  echo "Project directory: ${PROJ_DIR}"
  echo "  Usage: ${DISK_USAGE}% | Available: ${DISK_AVAIL}"

  if [ "$DISK_USAGE" -ge 90 ]; then
    echo "  [ERROR] Disk usage critical (>90%). Pipeline may fail due to insufficient space."
    echo "  [ERROR] Suggested actions:"
    echo "    1. Remove temp files: find Project/*/temp -type f -mtime +7 -delete"
    echo "    2. Compress old results: tar -czf old_results.tar.gz Project/*/result/*"
  elif [ "$DISK_USAGE" -ge 80 ]; then
    echo "  [WARN] Disk usage high (>80%). Monitor closely."
  else
    echo "  [INFO] Disk space sufficient."
  fi
  echo ""

  # Check temp directory sizes
  echo "Temp directory sizes (top 5):"
  du -sh "${PROJ_DIR}"/Project/*/temp 2>/dev/null | sort -hr | head -5 | sed 's/^/  /'
  echo ""
fi

echo "========================================"
echo "Diagnostic complete."
echo "========================================"
