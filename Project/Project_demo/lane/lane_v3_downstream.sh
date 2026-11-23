#!/usr/bin/env bash
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# V3 lane (supervisor 3rd review approval, 2026-10-14):
# prologue: 54 x4 union rerun with full-ID dedup for samples whose union files
# were still on the old base-ID key; then virus downstream annotation chain
# 64 -> 65 -> 66 -> 67 -> 67b -> 72 -> 70 -> 69 -> 68 (iphop heaviest, last).
export MGX_MONITOR=1
# 会话续接后 conda 不在 PATH（libcommon mgx_conda 需要）；repo 本地 miniforge3
export PATH="${REPO}/miniforge3/bin:$PATH"
WD="${REPO}/Project/Project_demo"
cd "$REPO"

fail() { echo "=== V3 ABORTED at $1 ($(date +%T)) ==="; exit 1; }

for s in Sample1 Sample2 Sample4 Sample11; do
    echo "=== [$(date +%T)] V3: 54_checkv $s (union full-ID dedup) ==="
    bash scripts/54_vir_checkv_contig.sh -s "$s" -t 16 -w "$WD" -r "$REPO" --force || fail "54/$s"
done

for step in 64_vir_pharokka 65_vir_phold 66_vir_vog 67_vir_bacphlip 67b_vir_phastyle 72_vir_phagcn3 70_vir_phabox2 69_vir_vcontact3 68_vir_iphop; do
    echo "=== [$(date +%T)] V3: $step ==="
    bash "scripts/${step}.sh" -t 16 -w "$WD" -r "$REPO" && echo "[$step] OK" || fail "$step"
done
echo "=== V3 DONE $(date +%T) ==="
