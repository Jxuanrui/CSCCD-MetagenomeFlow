#!/usr/bin/env bash
# scripts/43b_bac_gem_carveme.sh
# MAG GEM reconstruction using CarveMe (fast BiGG-based method)
# Author: CSCCD-MetagenomeFlow Platform
# Date: 2026-08-06

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

# ==================== Parameter parsing ====================
show_help() {
    cat << EOF
Usage: $0 -m MAG_NAME -w WORKDIR -r REPO [--force]

Required:
  -m    MAG name (or 'all' for batch mode)
  -w    Working directory (project root)
  -r    Repository root path

Optional:
  --force    Overwrite existing outputs

Example:
  $0 -m bin001 -w /path/to/project -r ~/Course/CSCCD-MetagenomeFlow
  $0 -m all -w /path/to/project -r ~/Course/CSCCD-MetagenomeFlow
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="m:MAG_NAME w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require MAG_NAME WORKDIR REPO

# Convert to absolute paths
WORKDIR=$(cd "$WORKDIR" && pwd)
REPO=$(cd "$REPO" && pwd)

# ==================== Setup ====================
DREP_DIR="${WORKDIR}/result/binning/drep/dereplicated_genomes"
OUTBASE="${WORKDIR}/result/gem/carveme"
CARVEME_ENV="${REPO}/envs/carveme"

mkdir -p "${OUTBASE}"

# ==================== Functions ====================
process_mag() {
    local mag_name=$1
    local mag_fa="${DREP_DIR}/${mag_name}.fa"
    local outdir="${OUTBASE}/${mag_name}"

    if [[ ! -f "$mag_fa" ]]; then
        echo "[ERROR] MAG file not found: $mag_fa"
        return 1
    fi

    mkdir -p "$outdir"

    # Checkpoint: skip if final SBML exists (unless --force)
    local sbml_out="${outdir}/${mag_name}.xml"
    if [[ -f "$sbml_out" && $FORCE -eq 0 ]]; then
        echo "[SKIP] ${mag_name}: SBML model already exists"
        return 0
    fi

    echo "=== [${mag_name}] Starting CarveMe reconstruction ==="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MAG: $mag_fa" | tee "${outdir}/carveme.log"

    # CarveMe one-step reconstruction
    conda run --prefix "$CARVEME_ENV" carve \
        --dna \
        --fbc2 \
        --gapfill auto \
        --output "$sbml_out" \
        "$mag_fa" \
        >> "${outdir}/carveme.log" 2>&1

    if [[ -f "$sbml_out" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: SBML model generated" | tee -a "${outdir}/carveme.log"

        # Extract model statistics from log
        grep -E "(reactions|metabolites|genes)" "${outdir}/carveme.log" || true

        return 0
    else
        echo "[ERROR] CarveMe failed for ${mag_name}, check ${outdir}/carveme.log"
        return 1
    fi
}

# ==================== Main ====================
if [[ "$MAG_NAME" == "all" ]]; then
    echo "=== Batch mode: processing all dRep MAGs ==="

    if [[ ! -d "$DREP_DIR" ]]; then
        echo "[ERROR] dRep directory not found: $DREP_DIR"
        exit 1
    fi

    mapfile -t MAG_FILES < <(find "$DREP_DIR" -maxdepth 1 -name "*.fa" -type f)

    if [[ ${#MAG_FILES[@]} -eq 0 ]]; then
        echo "[ERROR] No MAG files found in $DREP_DIR"
        exit 1
    fi

    echo "Found ${#MAG_FILES[@]} MAGs to process"

    FAILED=()
    for mag_path in "${MAG_FILES[@]}"; do
        mag_name=$(basename "$mag_path" .fa)

        if process_mag "$mag_name"; then
            echo "[OK] $mag_name"
        else
            echo "[FAIL] $mag_name"
            FAILED+=("$mag_name")
        fi
    done

    N_SUCCESS=$((${#MAG_FILES[@]} - ${#FAILED[@]}))
    echo "=== Summary ==="
    echo "Total: ${#MAG_FILES[@]}"
    echo "Success: ${N_SUCCESS}"
    echo "Failed: ${#FAILED[@]}"

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo "Failed MAGs: ${FAILED[*]}"
        FAILED_MANIFEST="${OUTBASE}/failed_mags.txt"
        {
            printf "%s\n" "${FAILED[@]}"
        } > "${FAILED_MANIFEST}"
        echo "[WARN] ${#FAILED[@]} MAG(s) failed CarveMe reconstruction (solver/gapfill errors on individual genomes); see ${FAILED_MANIFEST}"

        # A handful of per-MAG solver failures (e.g. reframed/SCIP returning no
        # solution) is expected on a large, diverse MAG set and should not block
        # downstream FBA on the MAGs that did succeed. Only treat this as a hard
        # failure when reconstruction produced no usable models at all.
        if [[ ${N_SUCCESS} -eq 0 ]]; then
            echo "[ERROR] All ${#MAG_FILES[@]} MAGs failed CarveMe reconstruction"
            exit 1
        fi
    fi
else
    # Single MAG mode
    process_mag "$MAG_NAME"
fi

echo "=== CarveMe reconstruction complete ==="
