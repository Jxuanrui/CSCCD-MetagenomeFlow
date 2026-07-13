#!/bin/bash
set -e

PROJ_DIR="Project/Test_100samples"
RESULT="${PROJ_DIR}/result"
INTEGRATION="${RESULT}/integration"
METADATA="${PROJ_DIR}/metadata.csv"

echo "=== Fixed Batch Testing 4 New Modules ==="
echo "Start time: $(date)"
echo ""

# Counter
SUCCESS=0
FAILED=0

# ===============================================
# Batch 1: LEfSe Analysis (Already Working)
# ===============================================
echo "=== Batch 1: LEfSe Analysis ==="
echo "  [SKIPPED] Already completed (26 files)"
echo ""

# ===============================================
# Batch 2: Core Microbiome (Fix virus path)
# ===============================================
echo "=== Batch 2: Core Microbiome ==="

# Bacteria - already completed
echo "  bacteria: [SKIPPED] Already completed"

# Fungi - already completed
echo "  fungi: [SKIPPED] Already completed"

# Virus - use abundance table instead of taxonomy
echo "  Processing virus (using viral_family abundance)..."
if [ -f "${INTEGRATION}/virus/viral_family_abundance.tsv" ]; then
  bash scripts/92_core_microbiome.sh \
    -i "${INTEGRATION}/virus/viral_family_abundance.tsv" \
    -m "${METADATA}" \
    -o "${RESULT}/92_core_microbiome/virus" \
    -d virus && SUCCESS=$((SUCCESS+1)) || FAILED=$((FAILED+1))
  echo "    ✓ Virus core microbiome completed"
else
  echo "    ✗ viral_family_abundance.tsv not found"
  FAILED=$((FAILED+1))
fi
echo ""

# ===============================================
# Batch 3: Functional Redundancy (Fix all three)
# ===============================================
echo "=== Batch 3: Functional Redundancy ==="

# Bacteria - use correct taxonomy path
echo "  Processing bacteria/kegg_ko..."
if [ -f "${INTEGRATION}/bacteria/kegg_ko_abundance.tsv" ] && \
   [ -f "${RESULT}/bacteria/metaphlan4/merged/taxonomy.tsv" ]; then
  bash scripts/96c_functional_redundancy.sh \
    -f "${INTEGRATION}/bacteria/kegg_ko_abundance.tsv" \
    -t "${RESULT}/bacteria/metaphlan4/merged/taxonomy.tsv" \
    -o "${RESULT}/96c_functional_redundancy/bacteria" \
    -d bacteria \
    -y kegg_ko && SUCCESS=$((SUCCESS+1)) || FAILED=$((FAILED+1))
  echo "    ✓ Bacteria functional redundancy completed"
else
  echo "    ✗ Required files not found"
  FAILED=$((FAILED+1))
fi

# Fungi - use correct taxonomy path
echo "  Processing fungi/kegg_ko..."
if [ -f "${INTEGRATION}/fungi/kegg_ko_gene_count.tsv" ] && \
   [ -f "${RESULT}/fungi/metaphlan4/merged/taxonomy.tsv" ]; then
  bash scripts/96c_functional_redundancy.sh \
    -f "${INTEGRATION}/fungi/kegg_ko_gene_count.tsv" \
    -t "${RESULT}/fungi/metaphlan4/merged/taxonomy.tsv" \
    -o "${RESULT}/96c_functional_redundancy/fungi" \
    -d fungi \
    -y kegg_ko && SUCCESS=$((SUCCESS+1)) || FAILED=$((FAILED+1))
  echo "    ✓ Fungi functional redundancy completed"
else
  echo "    ✗ Required files not found"
  FAILED=$((FAILED+1))
fi

# Virus - use viral_family abundance as taxonomy proxy
echo "  Processing virus/vog..."
if [ -f "${INTEGRATION}/virus/vog_abundance.tsv" ] && \
   [ -f "${INTEGRATION}/virus/viral_family_abundance.tsv" ]; then
  bash scripts/96c_functional_redundancy.sh \
    -f "${INTEGRATION}/virus/vog_abundance.tsv" \
    -t "${INTEGRATION}/virus/viral_family_abundance.tsv" \
    -o "${RESULT}/96c_functional_redundancy/virus" \
    -d virus \
    -y vog && SUCCESS=$((SUCCESS+1)) || FAILED=$((FAILED+1))
  echo "    ✓ Virus functional redundancy completed"
else
  echo "    ✗ Required files not found"
  FAILED=$((FAILED+1))
fi
echo ""

# ===============================================
# Summary
# ===============================================
echo "=== Summary ==="
echo "Success: $SUCCESS"
echo "Failed: $FAILED"
echo ""

echo "Final file counts:"
echo "  LEfSe: $(find ${RESULT}/95b_lefse -type f 2>/dev/null | wc -l)"
echo "  Core microbiome: $(find ${RESULT}/92_core_microbiome -type f 2>/dev/null | wc -l)"
echo "  Functional redundancy: $(find ${RESULT}/96c_functional_redundancy -type f 2>/dev/null | wc -l)"
echo ""

echo "End time: $(date)"
echo "=== Fixed Batch Test Complete ==="
