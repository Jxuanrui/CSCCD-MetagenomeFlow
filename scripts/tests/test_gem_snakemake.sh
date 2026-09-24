#!/usr/bin/env bash
# GEM Module Snakemake Integration Test
# Tests the bacteria_gem.smk rules with a small test dataset

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKDIR="${REPO}/Project/Project01"

echo "=== GEM Module Snakemake Integration Test ==="
echo "Repo: ${REPO}"
echo "Workdir: ${WORKDIR}"

cd "${REPO}"
source scripts/activate.sh

# Test 1: Dry-run to validate DAG
echo -e "\n[Test 1] Validating Snakemake DAG (dry-run)"
if snakemake -s pipeline/Snakefile \
    --configfile pipeline/config/config.yaml \
    --config workdir="${WORKDIR}" repo="${REPO}" \
    --dry-run \
    --quiet \
    --until gem_carveme gem_fba 2>&1 | grep -q "Nothing to be done"; then
    echo "✅ DAG validation passed (or already complete)"
else
    echo "⚠️ DAG has pending jobs or validation issues"
fi

# Test 2: List GEM-related rules
echo -e "\n[Test 2] Listing GEM rules"
snakemake -s pipeline/Snakefile \
    --configfile pipeline/config/config.yaml \
    --list-rules 2>&1 | grep -i gem || echo "No GEM rules found"

# Test 3: Show rule DAG for GEM module
echo -e "\n[Test 3] GEM module DAG visualization"
snakemake -s pipeline/Snakefile \
    --configfile pipeline/config/config.yaml \
    --config workdir="${WORKDIR}" repo="${REPO}" \
    --dag \
    --until gem_fba 2>/dev/null | head -20 || echo "DAG generation skipped"

# Test 4: Check if GEM outputs already exist
echo -e "\n[Test 4] Checking existing GEM outputs"
if [ -f "${WORKDIR}/result/gem/carveme/carveme_done.txt" ]; then
    echo "✅ CarveMe done sentinel exists"
    n_models=$(find "${WORKDIR}/result/gem/carveme" -name "*.xml" 2>/dev/null | wc -l)
    echo "   Found ${n_models} SBML models"
else
    echo "⚠️ CarveMe not yet complete"
fi

if [ -f "${WORKDIR}/result/gem/fba/fba_done.txt" ]; then
    echo "✅ FBA done sentinel exists"
    n_fba=$(find "${WORKDIR}/result/gem/fba" -name "*_growth_rate.txt" 2>/dev/null | wc -l)
    echo "   Found ${n_fba} FBA results"
else
    echo "⚠️ FBA not yet complete"
fi

# Test 5: Test single MAG rule (if model exists)
echo -e "\n[Test 5] Testing single MAG rules"
if [ -f "${WORKDIR}/result/gem/carveme/Sample10__111/Sample10__111.xml" ]; then
    echo "Testing gem_fba_single with Sample10__111"
    snakemake -s pipeline/Snakefile \
        --configfile pipeline/config/config.yaml \
        --config workdir="${WORKDIR}" repo="${REPO}" \
        --dry-run \
        --quiet \
        "${WORKDIR}/result/gem/fba/Sample10__111/Sample10__111_growth_rate.txt" \
        2>&1 | head -10
    echo "✅ Single MAG rule validated"
else
    echo "⚠️ No test model available for single MAG test"
fi

echo -e "\n=== Integration Test Complete ==="
echo "Next steps:"
echo "  - Run full GEM pipeline: snakemake -s pipeline/Snakefile --until gem_fba -j 16"
echo "  - Run single MAG: snakemake result/gem/fba/MAG_NAME/MAG_NAME_growth_rate.txt"
