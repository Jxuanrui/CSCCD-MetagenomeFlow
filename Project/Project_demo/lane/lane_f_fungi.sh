#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# F-fungi lane (review W2-C): waits for B3-light lane to free its 16 threads,
# then runs fungi chain. Per-sample steps continue-on-error (5/6 samples have
# empty fungal assemblies by design disclosure); aggregate steps strict.
export MGX_MONITOR=1
WD="${REPO}/Project/Project_demo"
cd "$REPO"
SAMPLES="Sample1 Sample2 Sample3 Sample4 Sample10 Sample11"

while ! grep -q "B3-light DONE" /tmp/lane_b3l_annot.log 2>/dev/null; do sleep 60; done
echo "=== [$(date +%T)] F: B3L ended, fungi chain starts ==="

for s in $SAMPLES; do echo "=== [$(date +%T)] F: 80_prodigal $s ==="; bash scripts/80_fun_prodigal.sh -s "$s" -t 16 -w "$WD" -r "$REPO" && echo "[80/$s] OK" || echo "[80/$s] FAIL"; done
for s in $SAMPLES; do bash scripts/80b_fun_metaeuk.sh -s "$s" -t 16 -w "$WD" -r "$REPO" && echo "[80b/$s] OK" || echo "[80b/$s] FAIL"; done
for s in $SAMPLES; do bash scripts/75_fun_funomics.sh -s "$s" -t 16 -w "$WD" -r "$REPO" && echo "[75/$s] OK" || echo "[75/$s] FAIL"; done
bash scripts/75b_fun_funomics_aggregate.sh -w "$WD" -r "$REPO" -t 16 || { echo "=== F-ABORTED at 75b ==="; exit 1; }
for s in $SAMPLES; do bash scripts/77_fun_microfisher.sh -s "$s" -t 16 -w "$WD" -r "$REPO" && echo "[77/$s] OK" || echo "[77/$s] FAIL"; done

for step in 81_fun_eggnog 82_fun_kegg 83_fun_dbcan 84_fun_vfdb 85_fun_amr 86_fun_merops; do
    echo "=== [$(date +%T)] F: $step ==="
    bash "scripts/${step}.sh" -t 16 -w "$WD" -r "$REPO" && echo "[$step] OK" || { echo "=== F-ABORTED at $step ==="; exit 1; }
done
echo "=== F-LANE DONE $(date +%T) ==="
