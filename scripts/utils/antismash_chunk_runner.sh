#!/usr/bin/env bash
# antismash_chunk_runner.sh — E-HARD-02 validation runner (NOT production 28号)
# Full-record chunking only (never splits a sequence record); identical
# scientific params to frozen production; per-chunk DONE/FAILED sentinels;
# merge only when all chunks DONE; resume skips DONE chunks.
set -euo pipefail
CPUS="$1"; BASE="$2"; CONTIGS="$3"; REPO="$4"  # (sample 名由路径携带)
CHUNKS=24
MONO="${BASE}/monolithic"; CHUNK="${BASE}/chunked"
AS_ENV="${REPO}/envs/antismash8"; AS_DB="${REPO}/db/antismash8"
COMMON=(--taxon bacteria --cpus "${CPUS}" --databases "${AS_DB}" --genefinding-tool prodigal-m --minimal --enable-nrps-pks)

run_antismash () {  # $1=in $2=outdir
    conda run --prefix "${AS_ENV}" antismash "$1" --output-dir "$2" "${COMMON[@]}" || return $?
}

# --- monolithic (frozen production command; isolated workdir) ---
if [ ! -f "${MONO}/antismash_done.txt" ]; then
    rm -rf "${MONO}"; mkdir -p "${MONO}"
    if run_antismash "${CONTIGS}" "${MONO}"; then touch "${MONO}/antismash_done.txt";
    else echo "status=FAILED" > "${MONO}/antismash_FAILED.txt"; exit 1; fi
fi

# --- chunked: full-record split into ${CHUNKS} bp-balanced chunks ---
if [ ! -f "${CHUNK}/merge_done.txt" ]; then
    mkdir -p "${CHUNK}/chunks"
    python3 - "${CONTIGS}" "${CHUNK}/chunks" "${CHUNKS}" <<'PYSPLIT'
import sys, os
src, outdir, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
recs = []
name, seq = None, []
for line in open(src):
    if line.startswith(">"):
        if name: recs.append((name, "".join(seq)))
        name, seq = line, []
    else: seq.append(line.strip())
if name: recs.append((name, "".join(seq)))
recs.sort(key=lambda r: -len(r[1]))  # bp-balanced greedy (largest-first)
total = sum(len(s) for _, s in recs); target = total // k
bins = [([], 0) for _ in range(k)]
for name, s in recs:
    bins.sort(key=lambda b: b[1])
    lst, load = bins[0]; lst.append((name, s)); bins[0] = (lst, load + len(s))
for i, (lst, _) in enumerate(bins):
    with open(os.path.join(outdir, f"chunk_{i:02d}.fa"), "w") as f:
        for name, s in lst: f.write(name + "\n" + s + "\n")
print(f"records={len(recs)} split={k} chunks")
PYSPLIT
    # per-chunk run with resume + failure isolation
    FAILED=0
    for c in "${CHUNK}"/chunks/chunk_*.fa; do
        cid=$(basename "$c" .fa); od="${CHUNK}/runs/${cid}"
        if [ -f "${od}/antismash_done.txt" ]; then echo "[chunk] ${cid} DONE (resume skip)"; continue; fi
        rm -rf "${od}"; mkdir -p "${od}"
        if run_antismash "${c}" "${od}"; then touch "${od}/antismash_done.txt"; echo "[chunk] ${cid} DONE";
        else echo "status=FAILED" > "${od}/antismash_FAILED.txt"; FAILED=1; echo "[chunk] ${cid} FAILED"; fi
    done
    [ ${FAILED} -eq 1 ] && { echo "[merge] blocked: failed chunks present"; exit 1; }
    touch "${CHUNK}/merge_done.txt"
fi
echo "BOTH_RUNS_COMPLETE"
