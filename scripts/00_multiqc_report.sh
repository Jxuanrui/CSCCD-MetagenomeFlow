#!/bin/bash
# Task: MultiQC global quality control report
# Author: CSCCD-MetagenomeFlow team
# Date: 2026-08-20
# Description: Generate comprehensive MultiQC report from all analysis outputs

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJ_DIR}/scripts/activate.sh"
source "${PROJ_DIR}/scripts/utils/libcommon.sh"

show_help() {
cat << 'EOF'
Usage: 00_multiqc_report.sh [OPTIONS]

Generate comprehensive MultiQC report from all analysis outputs.

OPTIONS:
  -h, --help           Show this help message
  -p, --project DIR    Project directory (e.g., Project/Project01)
  -o, --output DIR     Output directory for report (default: PROJECT/result/qc_report)
  -t, --title TEXT     Report title (default: "CSCCD-MetagenomeFlow Quality Control Report")

INTEGRATED MODULES:
  - FastQC (raw reads quality)
  - Kraken2 (taxonomic classification)
  - MetaPhlAn4 (taxonomic profiling)
  - HUMAnN (functional profiling)
  - MEGAHIT (assembly statistics)
  - CheckM2 (MAG quality)
  - GTDB-Tk (taxonomy assignment)
  - CheckV (viral contig quality)
  - EukCC2 (eukaryotic MAG quality)

EXAMPLES:
  # Generate report for a project
  bash scripts/00_multiqc_report.sh -p Project/Project01

  # Custom output directory
  bash scripts/00_multiqc_report.sh -p Project/Project01 -o custom_qc

OUTPUT:
  - multiqc_report.html: Interactive HTML report
  - multiqc_data/: Raw data tables
EOF
}

REPORT_TITLE="CSCCD-MetagenomeFlow Quality Control Report"

# MGX_* tables are consumed by mgx_parse (libcommon.sh); short + long aliases map to the same vars
export MGX_OPTS_STRING="p:PROJECT_DIR o:OUTPUT_DIR t:REPORT_TITLE"
export MGX_OPTS_LONG="project:PROJECT_DIR output:OUTPUT_DIR title:REPORT_TITLE"
mgx_parse "$@"
mgx_require PROJECT_DIR

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[ERROR] Project directory not found: $PROJECT_DIR"
  exit 1
fi

# Default output directory
if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="${PROJECT_DIR}/result/qc_report"
fi

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "MultiQC Report Generation"
echo "========================================"
echo "Project: $PROJECT_DIR"
echo "Output: $OUTPUT_DIR"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Activate MultiQC environment
echo "[1/4] Activating MultiQC environment..."
conda activate "${PROJ_DIR}/envs/multiqc"

# Create MultiQC config
echo "[2/4] Creating MultiQC configuration..."
MULTIQC_CONFIG="${OUTPUT_DIR}/multiqc_config.yaml"

cat > "$MULTIQC_CONFIG" << EOF
title: "$REPORT_TITLE"
subtitle: "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
intro_text: "Comprehensive quality control report for CSCCD-MetagenomeFlow analysis pipeline."

report_header_info:
  - Project: "$PROJECT_DIR"
  - Analysis Date: "$(date '+%Y-%m-%d')"

extra_fn_clean_exts:
  - .krakenreport
  - .profile
  - .log
  - _stats
  - type: remove
    pattern: ".sorted"

module_order:
  - fastqc
  - kraken
  - metaphlan
  - humann
  - quast
  - checkm

table_columns_visible:
  FastQC:
    percent_duplicates: False
    percent_gc: True
    avg_sequence_length: True
    total_sequences: True

top_modules:
  - fastqc
  - kraken
  - metaphlan

show_analysis_paths: True
show_analysis_time: True

custom_logo: null
custom_logo_url: null
custom_logo_title: "CSCCD-MetagenomeFlow"

report_comment: "This report aggregates QC metrics from bacteria, virus, and fungi analysis modules."
EOF

echo "[3/4] Collecting QC data from analysis outputs..."

# Search paths for different modules
SEARCH_PATHS=(
  "${PROJECT_DIR}/temp/01_qc"
  "${PROJECT_DIR}/temp/11_kraken2"
  "${PROJECT_DIR}/temp/12_strainphlan4"
  "${PROJECT_DIR}/temp/13_humann"
  "${PROJECT_DIR}/temp/21_assembly"
  "${PROJECT_DIR}/temp/37_checkm2"
  "${PROJECT_DIR}/temp/40_gtdbtk"
  "${PROJECT_DIR}/temp/54_checkv"
  "${PROJECT_DIR}/temp/71_kraken2_fungi"
  "${PROJECT_DIR}/temp/81_eukcc2"
)

# Count available data sources
FOUND_MODULES=0
for PATH in "${SEARCH_PATHS[@]}"; do
  if [ -d "$PATH" ]; then
    FILE_COUNT=$(find "$PATH" -type f 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
      echo "  Found data: $PATH ($FILE_COUNT files)"
      FOUND_MODULES=$((FOUND_MODULES + 1))
    fi
  fi
done

if [ $FOUND_MODULES -eq 0 ]; then
  echo ""
  echo "[WARN] No QC data found in any analysis directories"
  echo "[WARN] Have you run the analysis scripts yet?"
  echo ""
  echo "Expected data directories:"
  for PATH in "${SEARCH_PATHS[@]}"; do
    echo "  - $PATH"
  done
  exit 1
fi

echo ""
echo "[4/4] Running MultiQC..."

# Run MultiQC
multiqc \
  --config "$MULTIQC_CONFIG" \
  --outdir "$OUTPUT_DIR" \
  --force \
  --verbose \
  --dirs \
  --dirs-depth 2 \
  --fullnames \
  "${SEARCH_PATHS[@]}" \
  2>&1 | tee "${OUTPUT_DIR}/multiqc.log"

# Check if report was generated
if [ -f "${OUTPUT_DIR}/multiqc_report.html" ]; then
  REPORT_SIZE=$(du -h "${OUTPUT_DIR}/multiqc_report.html" | awk '{print $1}')
  echo ""
  echo "========================================"
  echo "Report Generated Successfully"
  echo "========================================"
  echo "HTML Report: ${OUTPUT_DIR}/multiqc_report.html"
  echo "Report Size: $REPORT_SIZE"
  echo "Data Tables: ${OUTPUT_DIR}/multiqc_data/"
  echo ""
  echo "Open the report with:"
  echo "  firefox ${OUTPUT_DIR}/multiqc_report.html"
  echo ""
else
  echo ""
  echo "[ERROR] MultiQC report generation failed"
  echo "Check log file: ${OUTPUT_DIR}/multiqc.log"
  exit 1
fi

# Generate summary statistics
echo "## Report Summary"
echo ""

if [ -d "${OUTPUT_DIR}/multiqc_data" ]; then
  GENERAL_STATS="${OUTPUT_DIR}/multiqc_data/multiqc_general_stats.txt"
  if [ -f "$GENERAL_STATS" ]; then
    SAMPLE_COUNT=$(tail -n +2 "$GENERAL_STATS" | wc -l)
    echo "Total samples: $SAMPLE_COUNT"
    echo "Integrated modules: $FOUND_MODULES"
    echo ""
  fi
fi

echo "========================================"
echo "Complete"
echo "========================================"
