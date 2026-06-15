#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74c_fun_cgf_profiler.sh
# 功  能: Per-sample CGF fungal profiler using DIAMOND blastx + Singular/Escrow
#         assignment (Yan et al. 2024 Cell 187).
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
#         74b_fun_cgf_db_build.sh 构建的 CGF DIAMOND 数据库和物种映射表
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/cgf_profiler/${SAMPLE}/${SAMPLE}_cgf_hits.tsv
#         ${WORKDIR}/result/fungi/cgf_profiler/${SAMPLE}/${SAMPLE}_cgf_abundance.tsv
# 用  法: bash 74c_fun_cgf_profiler.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 74c_fun_cgf_profiler.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO

必需参数:
  -s  样本名
  -t  线程数
  -w  工作目录
  -r  MaxMetagenome 项目根目录

输出:
  \${WORKDIR}/result/fungi/cgf_profiler/SAMPLE/SAMPLE_cgf_hits.tsv
  \${WORKDIR}/result/fungi/cgf_profiler/SAMPLE/SAMPLE_cgf_abundance.tsv
EOF
}

SAMPLE=""; CPUS=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SAMPLE="$2";  shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done
for v in SAMPLE CPUS WORKDIR REPO; do
    if [ -z "${!v}" ]; then
        echo "[ERROR] 缺少必需参数: ${v}"
        show_help
        exit 1
    fi
done

if ! [[ "${CPUS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] -t 必须是正整数: ${CPUS}"
    exit 1
fi

SECONDS=0

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"
OUTDIR="${WORKDIR}/result/fungi/cgf_profiler/${SAMPLE}"
HITS_TSV="${OUTDIR}/${SAMPLE}_cgf_hits.tsv"
ABUND_TSV="${OUTDIR}/${SAMPLE}_cgf_abundance.tsv"
DB_FILE="${REPO}/db/cgf/cgf_proteins.dmnd"
SPECIES_MAP="${REPO}/db/cgf/cgf_species_map.tsv"

if [ -f "${ABUND_TSV}" ] && [ -s "${ABUND_TSV}" ]; then
    echo "[INFO] 结果已存在，跳过: ${ABUND_TSV}"
    exit 0
fi

if [ ! -s "${DB_FILE}" ]; then
    echo "[WARN] CGF DIAMOND database not found: ${DB_FILE}"
    echo "Please run 74b_fun_cgf_db_build.sh first"
    exit 0
fi
if [ ! -s "${SPECIES_MAP}" ]; then
    echo "[WARN] CGF species map not found: ${SPECIES_MAP}"
    echo "Please run 74b_fun_cgf_db_build.sh first"
    exit 0
fi
if [ ! -s "${INPUT_R1}" ]; then
    echo "[WARN] kneaddata output not found: ${INPUT_R1}"
    exit 0
fi

mkdir -p "${OUTDIR}"

TMP_R1_RAW="${OUTDIR}/${SAMPLE}_cgf_hits.R1.raw.tmp.tsv"
TMP_R1_TAGGED="${OUTDIR}/${SAMPLE}_cgf_hits.R1.tagged.tmp.tsv"
TMP_R2_RAW="${OUTDIR}/${SAMPLE}_cgf_hits.R2.raw.tmp.tsv"
TMP_R2_TAGGED="${OUTDIR}/${SAMPLE}_cgf_hits.R2.tagged.tmp.tsv"
TMP_HITS="${HITS_TSV}.tmp"
TMP_ABUND="${ABUND_TSV}.tmp"
trap 'rm -f "${TMP_R1_RAW}" "${TMP_R1_TAGGED}" "${TMP_R2_RAW}" "${TMP_R2_TAGGED}" "${TMP_HITS}" "${TMP_ABUND}"' EXIT

run_diamond_blastx() {
    local query_fastq="$1"
    local raw_out="$2"
    local tagged_out="$3"
    local mate_tag="$4"

    echo "[cgf_profiler] DIAMOND blastx ${mate_tag}: ${query_fastq}"
    if ! conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
        diamond blastx \
            --query "${query_fastq}" \
            --db "${DB_FILE}" \
            --out "${raw_out}" \
            --outfmt 6 qseqid sseqid pident length evalue bitscore \
            --threads "${CPUS}" \
            --evalue 1e-5 \
            --id 80 \
            --query-cover 50 \
            --max-target-seqs 25 \
            --block-size 4 \
            --index-chunks 1 \
            --more-sensitive
    then
        echo "[ERROR] diamond blastx failed for ${mate_tag}: ${query_fastq}"
        exit 1
    fi

    # R1/R2 FASTQ records often share qseqid; tag mates before pooling hits.
    awk -v tag="${mate_tag}" 'BEGIN{FS=OFS="\t"} NF>0 {$1=$1 tag; print}' \
        "${raw_out}" > "${tagged_out}"
}

rm -f "${TMP_R1_RAW}" "${TMP_R1_TAGGED}" "${TMP_R2_RAW}" "${TMP_R2_TAGGED}" "${TMP_HITS}" "${TMP_ABUND}"

run_diamond_blastx "${INPUT_R1}" "${TMP_R1_RAW}" "${TMP_R1_TAGGED}" "/1"

if [ -s "${INPUT_R2}" ]; then
    run_diamond_blastx "${INPUT_R2}" "${TMP_R2_RAW}" "${TMP_R2_TAGGED}" "/2"
else
    echo "[WARN] R2 not found; profiling R1 only: ${INPUT_R2}"
    : > "${TMP_R2_TAGGED}"
fi

cat "${TMP_R1_TAGGED}" "${TMP_R2_TAGGED}" > "${TMP_HITS}"
mv "${TMP_HITS}" "${HITS_TSV}"

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
    python3 - "${HITS_TSV}" "${SPECIES_MAP}" "${TMP_ABUND}" << 'PY'
import collections
import math
import sys

hits_tsv, species_map_tsv, out_tsv = sys.argv[1], sys.argv[2], sys.argv[3]

accession_to_species = {}
species_to_size_values = collections.defaultdict(list)

with open(species_map_tsv, "r", encoding="utf-8", errors="replace") as handle:
    for line_no, raw in enumerate(handle, 1):
        line = raw.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            raise SystemExit(f"[ERROR] Invalid species map row at {species_map_tsv}:{line_no}")
        accession, species, size_raw = parts[0].strip(), parts[1].strip(), parts[2].strip()
        if line_no == 1 and accession.lower() in {"accession", "gca", "gca_accession"}:
            continue
        if not accession or not species:
            raise SystemExit(f"[ERROR] Empty accession/species at {species_map_tsv}:{line_no}")
        try:
            size_mb = float(size_raw)
        except ValueError as exc:
            raise SystemExit(f"[ERROR] Invalid genome size at {species_map_tsv}:{line_no}: {size_raw}") from exc
        if not math.isfinite(size_mb) or size_mb <= 0:
            raise SystemExit(f"[ERROR] Genome size must be >0 at {species_map_tsv}:{line_no}: {size_raw}")
        accession_to_species[accession] = species
        species_to_size_values[species].append(size_mb)

if not accession_to_species:
    raise SystemExit(f"[ERROR] No usable rows in species map: {species_map_tsv}")

species_to_size = {
    species: sum(values) / len(values)
    for species, values in species_to_size_values.items()
}

read_to_species = collections.defaultdict(set)
unknown_accessions = collections.Counter()
n_hit_lines = 0

with open(hits_tsv, "r", encoding="utf-8", errors="replace") as handle:
    for line_no, raw in enumerate(handle, 1):
        line = raw.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            raise SystemExit(f"[ERROR] Invalid DIAMOND hit row at {hits_tsv}:{line_no}")
        qseqid, sseqid = parts[0], parts[1]
        accession = sseqid.split("__", 1)[0]
        species = accession_to_species.get(accession)
        if species is None:
            unknown_accessions[accession] += 1
            continue
        read_to_species[qseqid].add(species)
        n_hit_lines += 1

singular_counts = collections.Counter()
escrow_reads = []

for species_set in read_to_species.values():
    if len(species_set) == 1:
        singular_counts[next(iter(species_set))] += 1
    elif len(species_set) > 1:
        escrow_reads.append(species_set)

escrow_shares = collections.defaultdict(float)
unresolved_escrow = 0

for species_set in escrow_reads:
    denominator = sum(singular_counts.get(species, 0) for species in species_set)
    if denominator <= 0:
        unresolved_escrow += 1
        continue
    for species in species_set:
        escrow_shares[species] += singular_counts.get(species, 0) / denominator

rows = []
for species in sorted(set(singular_counts) | set(escrow_shares)):
    singular = float(singular_counts.get(species, 0))
    escrow = float(escrow_shares.get(species, 0.0))
    total = singular + escrow
    if total <= 0:
        continue
    genome_size_mb = species_to_size.get(species)
    if genome_size_mb is None or genome_size_mb <= 0:
        raise SystemExit(f"[ERROR] Missing genome size for species: {species}")
    normalized_count = total / genome_size_mb
    rows.append({
        "species": species,
        "singular": singular,
        "escrow": escrow,
        "total": total,
        "genome_size_mb": genome_size_mb,
        "normalized_count": normalized_count,
    })

norm_total = sum(row["normalized_count"] for row in rows)
for row in rows:
    row["norm_abundance"] = row["normalized_count"] / norm_total if norm_total > 0 else 0.0

rows.sort(key=lambda row: (-row["norm_abundance"], row["species"]))

tmp_out = out_tsv
with open(tmp_out, "w", encoding="utf-8") as out:
    out.write("species\tsingular\tescrow_share\ttotal\tgenome_size_mb\tnorm_abundance\n")
    for row in rows:
        singular_value = int(row["singular"]) if row["singular"].is_integer() else row["singular"]
        out.write(
            f"{row['species']}\t"
            f"{singular_value}\t"
            f"{row['escrow']:.6f}\t"
            f"{row['total']:.6f}\t"
            f"{row['genome_size_mb']:.6f}\t"
            f"{row['norm_abundance']:.12g}\n"
        )

mapped_reads = len(read_to_species)
print(f"[cgf_profiler] total reads mapped: {mapped_reads}")
print(f"[cgf_profiler] diamond hit rows used: {n_hit_lines}")
print(f"[cgf_profiler] singular reads: {sum(singular_counts.values())}")
print(f"[cgf_profiler] escrow reads: {len(escrow_reads)}")
if unresolved_escrow:
    print(f"[cgf_profiler] unresolved escrow reads with zero singular support: {unresolved_escrow}")
if unknown_accessions:
    n_unknown_hits = sum(unknown_accessions.values())
    preview = ", ".join(f"{acc}:{count}" for acc, count in unknown_accessions.most_common(5))
    print(f"[WARN] skipped hits with accessions absent from species map: {n_unknown_hits} ({preview})")

print(f"[cgf_profiler] species detected: {len(rows)}")
print("[cgf_profiler] top 5 species by norm_abundance:")
if rows:
    for row in rows[:5]:
        print(f"[cgf_profiler]   {row['species']}\t{row['norm_abundance']:.6g}")
else:
    print("[cgf_profiler]   none")
PY

mv "${TMP_ABUND}" "${ABUND_TSV}"

N_HITS=$(wc -l < "${HITS_TSV}" 2>/dev/null || echo "0")
N_SPECIES=$(awk 'NR>1{n++} END{print n+0}' "${ABUND_TSV}" 2>/dev/null || echo "0")
echo "[cgf_profiler] 完成，耗时 ${SECONDS}s | hit rows: ${N_HITS} | species: ${N_SPECIES}"
