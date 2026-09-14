#!/bin/bash
# Batch test script for 4 new modules
# Generated: 2026-07-13

set -e

PROJ_DIR="/home/labuser/Course/Maxmetagenome"
TEST_DATA="${PROJ_DIR}/Project/Test_100samples"
METADATA="${TEST_DATA}/metadata.csv"

echo "=== Batch Testing 4 New Modules ==="
echo "Start time: $(date)"
echo ""

# Check metadata exists
if [[ ! -f "$METADATA" ]]; then
    echo "ERROR: metadata.csv not found at $METADATA"
    exit 1
fi

# Batch 1: LEfSe analysis (22 tables)
echo "=== Batch 1: LEfSe Analysis ==="
mkdir -p ${TEST_DATA}/result/99b_lefse

for dim in bacteria fungi virus; do
    echo "  Processing ${dim}..."

    # Find all abundance tables
    tables=$(find ${TEST_DATA}/result/integration/${dim} -name "*_abundance.tsv" 2>/dev/null || true)

    if [[ -z "$tables" ]]; then
        echo "    WARNING: No abundance tables found for ${dim}"
        continue
    fi

    for tsv in $tables; do
        type=$(basename $tsv _abundance.tsv)
        outdir="${TEST_DATA}/result/99b_lefse/${dim}/${type}"

        echo "    - ${dim}/${type}"

        bash ${PROJ_DIR}/scripts/99b_lefse.sh \
            -i "$tsv" \
            -m "$METADATA" \
            -o "$outdir" \
            -d "$dim" \
            -y "$type" \
            2>&1 | grep -E "(ERROR|WARNING|significant)" || true
    done
done

echo ""
echo "=== Batch 2: Core Microbiome ==="
mkdir -p ${TEST_DATA}/result/99a_core_microbiome

for dim in bacteria fungi virus; do
    # Find taxonomy table
    tax_table=$(find ${TEST_DATA}/result/${dim} -name "taxonomy.tsv" -o -name "merged_taxonomy.tsv" 2>/dev/null | head -1)

    if [[ -z "$tax_table" ]]; then
        echo "  WARNING: No taxonomy table found for ${dim}"
        continue
    fi

    echo "  Processing ${dim} taxonomy..."

    bash ${PROJ_DIR}/scripts/99a_core_microbiome.sh \
        -i "$tax_table" \
        -m "$METADATA" \
        -o "${TEST_DATA}/result/99a_core_microbiome/${dim}" \
        -d "$dim" \
        2>&1 | grep -E "(Global core|Case core|Control core)" || true
done

echo ""
echo "=== Batch 3: Functional Redundancy ==="
mkdir -p ${TEST_DATA}/result/96c_functional_redundancy

for dim in bacteria fungi virus; do
    # Check if kegg_ko table exists
    func_table="${TEST_DATA}/result/integration/${dim}/kegg_ko_abundance.tsv"
    tax_table=$(find ${TEST_DATA}/result/${dim} -name "taxonomy.tsv" -o -name "merged_taxonomy.tsv" 2>/dev/null | head -1)
    ml_importance="${TEST_DATA}/result/deprecated/97_ml_mlr3/${dim}/kegg_ko/shap_importance.csv"

    if [[ ! -f "$func_table" ]]; then
        echo "  WARNING: No kegg_ko table for ${dim}"
        continue
    fi

    if [[ -z "$tax_table" ]]; then
        echo "  WARNING: No taxonomy table for ${dim}"
        continue
    fi

    echo "  Processing ${dim}/kegg_ko..."

    extra_args=""
    if [[ -f "$ml_importance" ]]; then
        extra_args="--ml-importance $ml_importance"
    fi

    bash ${PROJ_DIR}/scripts/96c_functional_redundancy.sh \
        -f "$func_table" \
        -t "$tax_table" \
        -o "${TEST_DATA}/result/96c_functional_redundancy/${dim}/kegg_ko" \
        -d "$dim" \
        -y "kegg_ko" \
        $extra_args \
        2>&1 | grep -E "(Average FDI|correlation|keystone)" || true
done

echo ""
echo "=== Summary ==="
echo "LEfSe results:"
find ${TEST_DATA}/result/99b_lefse -name "lefse_results.tsv" 2>/dev/null | wc -l
echo "Core microbiome results:"
find ${TEST_DATA}/result/99a_core_microbiome -name "core_microbiome_summary.txt" 2>/dev/null | wc -l
echo "Functional redundancy results:"
find ${TEST_DATA}/result/96c_functional_redundancy -name "function_dispersion_index.csv" 2>/dev/null | wc -l

echo ""
echo "End time: $(date)"
echo "=== Batch Test Complete ==="
