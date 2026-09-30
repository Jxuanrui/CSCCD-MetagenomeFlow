#!/bin/bash
# Task: Provenance script snapshot
# Author: CSCCD-MetagenomeFlow team
# Date: 2026-08-20
# Description: Capture and archive script versions used for each analysis run

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh"
source "${PROJ_DIR}/scripts/utils/libcommon.sh"

show_help() {
cat << 'EOF'
Usage: 00_snapshot_provenance.sh [OPTIONS]

Capture and archive script versions used for each analysis run.

OPTIONS:
  -h, --help           Show this help message
  -p, --project DIR    Project directory (e.g., Project/Project01)
  -n, --name NAME      Snapshot name (default: auto-generated from date)
  --auto               Auto-generate snapshot name from current git commit + timestamp

PURPOSE:
  Records exact script versions, conda environments, and parameters used in an
  analysis run, enabling full reproducibility and result traceability.

CAPTURED DATA:
  1. All scripts (scripts/*.sh, scripts/*.R, scripts/*.py)
  2. Snakemake workflow (pipeline/Snakefile, pipeline/rules/*.smk)
  3. Conda environment specifications (envs/*.yaml frozen versions)
  4. Git commit hash and diff status
  5. Database versions (db/ directory checksums)
  6. Analysis configuration (pipeline/config/config.yaml)

OUTPUT:
  Project/PROJECT_NAME/provenance/SNAPSHOT_NAME/
    ├── scripts/           (copy of all scripts)
    ├── pipeline/          (copy of Snakemake workflow)
    ├── envs/              (frozen conda env exports)
    ├── manifest.json      (metadata: timestamp, git commit, versions)
    └── checksums.txt      (SHA256 of all captured files)

EXAMPLES:
  # Create snapshot with auto-generated name
  bash scripts/00_snapshot_provenance.sh -p Project/Project01 --auto

  # Create snapshot with custom name
  bash scripts/00_snapshot_provenance.sh -p Project/Project01 -n "run_20260820_v1"

  # Compare two snapshots (use diff)
  diff -r Project/Project01/provenance/run1 Project/Project01/provenance/run2

RECOMMENDED WORKFLOW:
  1. Before starting analysis: create "pre-run" snapshot
  2. After analysis completes: create "post-run" snapshot
  3. Archive snapshots alongside published results
EOF
}

# MGX_* tables are consumed by mgx_parse (libcommon.sh); short + long aliases map to the same vars
export MGX_OPTS_STRING="p:PROJECT_DIR n:SNAPSHOT_NAME"
export MGX_OPTS_LONG="project:PROJECT_DIR name:SNAPSHOT_NAME"
export MGX_OPTS_FLAG="auto"
mgx_parse "$@"
mgx_require PROJECT_DIR

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[ERROR] Project directory not found: $PROJECT_DIR"
  exit 1
fi

# Auto-generate snapshot name if not provided
if [ -z "$SNAPSHOT_NAME" ]; then
  if [ ${AUTO} -eq 1 ]; then
    GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SNAPSHOT_NAME="snapshot_${GIT_COMMIT}_${TIMESTAMP}"
  else
    SNAPSHOT_NAME="snapshot_$(date +%Y%m%d_%H%M%S)"
  fi
fi

PROVENANCE_DIR="${PROJECT_DIR}/provenance"
SNAPSHOT_DIR="${PROVENANCE_DIR}/${SNAPSHOT_NAME}"

echo "========================================"
echo "Provenance Snapshot Utility"
echo "========================================"
echo "Project: $PROJECT_DIR"
echo "Snapshot: $SNAPSHOT_NAME"
echo "Output: $SNAPSHOT_DIR"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check if snapshot already exists
if [ -d "$SNAPSHOT_DIR" ]; then
  echo "[ERROR] Snapshot already exists: $SNAPSHOT_DIR"
  echo "[ERROR] Use a different name or remove the existing snapshot"
  exit 1
fi

# Create snapshot directory structure
echo "[1/7] Creating snapshot directory structure..."
mkdir -p "$SNAPSHOT_DIR"/{scripts,pipeline,envs,db_info}

# Capture scripts
echo "[2/7] Capturing analysis scripts..."
SCRIPT_COUNT=0
for SCRIPT in "${PROJ_DIR}"/scripts/*.{sh,R,py}; do
  if [ -f "$SCRIPT" ]; then
    cp "$SCRIPT" "${SNAPSHOT_DIR}/scripts/"
    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
  fi
done
echo "        Captured $SCRIPT_COUNT script files"

# Capture Snakemake workflow
echo "[3/7] Capturing Snakemake workflow..."
if [ -f "${PROJ_DIR}/pipeline/Snakefile" ]; then
  cp "${PROJ_DIR}/pipeline/Snakefile" "${SNAPSHOT_DIR}/pipeline/"
fi
if [ -d "${PROJ_DIR}/pipeline/rules" ]; then
  mkdir -p "${SNAPSHOT_DIR}/pipeline/rules"
  cp -r "${PROJ_DIR}/pipeline/rules"/*.smk "${SNAPSHOT_DIR}/pipeline/rules/" 2>/dev/null || true
fi
if [ -f "${PROJ_DIR}/pipeline/config/config.yaml" ]; then
  mkdir -p "${SNAPSHOT_DIR}/pipeline/config"
  cp "${PROJ_DIR}/pipeline/config/config.yaml" "${SNAPSHOT_DIR}/pipeline/config/"
fi
WORKFLOW_FILES=$(find "${SNAPSHOT_DIR}/pipeline" -type f 2>/dev/null | wc -l)
echo "        Captured $WORKFLOW_FILES workflow files"

# Capture conda environment specs
echo "[4/7] Exporting conda environment specifications..."
ENV_COUNT=0
if [ -d "${PROJ_DIR}/envs" ]; then
  for ENV_DIR in "${PROJ_DIR}"/envs/*/; do
    if [ -d "$ENV_DIR" ]; then
      ENV_NAME=$(basename "$ENV_DIR")
      conda list -p "$ENV_DIR" --export > "${SNAPSHOT_DIR}/envs/${ENV_NAME}_frozen.txt" 2>/dev/null || true
      ENV_COUNT=$((ENV_COUNT + 1))
    fi
  done
fi
echo "        Exported $ENV_COUNT conda environments"

# Capture git information
echo "[5/7] Capturing git repository state..."
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "not-a-git-repo")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=$(git diff --quiet 2>/dev/null && echo "clean" || echo "dirty")

# Capture database checksums (sample only, full checksum would take too long)
echo "[6/7] Capturing database version information..."
DB_VERSION_FILE="${SNAPSHOT_DIR}/db_info/database_versions.txt"
{
  echo "# Database Versions and Checksums (sampled)"
  echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  for DB_PATH in "${PROJ_DIR}"/db/*/*/; do
    if [ -d "$DB_PATH" ]; then
      DB_NAME=$(basename "$(dirname "$DB_PATH")")/$(basename "$DB_PATH")
      DB_SIZE=$(du -sh "$DB_PATH" 2>/dev/null | awk '{print $1}')
      FILE_COUNT=$(find "$DB_PATH" -type f 2>/dev/null | wc -l)
      # Sample checksum: first 5 files only (full checksum too slow)
      SAMPLE_CHECKSUM=$(find "$DB_PATH" -type f 2>/dev/null | head -5 | xargs sha256sum 2>/dev/null | sha256sum | awk '{print $1}')
      echo "$DB_NAME | Size: $DB_SIZE | Files: $FILE_COUNT | Sample SHA256: $SAMPLE_CHECKSUM"
    fi
  done
} > "$DB_VERSION_FILE"

# Create manifest
echo "[7/7] Creating manifest..."
MANIFEST_FILE="${SNAPSHOT_DIR}/manifest.json"
cat > "$MANIFEST_FILE" << EOF
{
  "snapshot_name": "$SNAPSHOT_NAME",
  "project_dir": "$PROJECT_DIR",
  "created_at": "$(date -Iseconds)",
  "created_by": "$(whoami)@$(hostname)",
  "git": {
    "commit": "$GIT_COMMIT",
    "branch": "$GIT_BRANCH",
    "status": "$GIT_DIRTY"
  },
  "captured_files": {
    "scripts": $SCRIPT_COUNT,
    "workflow_files": $WORKFLOW_FILES,
    "conda_envs": $ENV_COUNT
  },
  "system": {
    "kernel": "$(uname -r)",
    "platform": "$(uname -m)",
    "os": "$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
  }
}
EOF

# Generate checksums for all captured files
echo ""
echo "Generating checksums for all captured files..."
CHECKSUM_FILE="${SNAPSHOT_DIR}/checksums.sha256"
(cd "$SNAPSHOT_DIR" && find . -type f ! -name "checksums.sha256" -exec sha256sum {} \;) > "$CHECKSUM_FILE"

CHECKSUM_COUNT=$(wc -l < "$CHECKSUM_FILE")

# Summary
echo ""
echo "========================================"
echo "Snapshot Complete"
echo "========================================"
echo "Location: $SNAPSHOT_DIR"
echo ""
echo "Captured content:"
echo "  - Scripts: $SCRIPT_COUNT files"
echo "  - Workflow: $WORKFLOW_FILES files"
echo "  - Conda envs: $ENV_COUNT environments"
echo "  - Database info: $(wc -l < "$DB_VERSION_FILE") entries"
echo "  - Checksums: $CHECKSUM_COUNT files verified"
echo ""
echo "Git state:"
echo "  - Commit: $GIT_COMMIT"
echo "  - Branch: $GIT_BRANCH"
echo "  - Status: $GIT_DIRTY"
echo ""
echo "[INFO] To verify snapshot integrity later:"
echo "       cd $SNAPSHOT_DIR && sha256sum -c checksums.sha256"
echo ""
echo "========================================"
