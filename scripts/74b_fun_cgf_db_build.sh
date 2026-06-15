#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74b_fun_cgf_db_build.sh
# 功  能: 构建 CGF 真菌蛋白 DIAMOND 数据库（一次性数据库构建，不按样本运行）
#
# WARNING: This script runs for several hours on 709 genomes.
#          Run in a screen/tmux session.
#
# Runtime estimate:
#   MetaEuk on 709 genomes with 16 CPU: ~2-4 hours
#   MMseqs2 clustering: ~30 min
#   DIAMOND makedb: ~5 min
#
# 输  入:
#   ${REPO}/db/cgf/genomes/GCA_*.fna
#   ${REPO}/db/funomic/P/FunOMIC.P.v1.dmnd
#   ${REPO}/db/cgf/assembly_report.jsonl
# 输  出:
#   ${REPO}/db/cgf/metaeuk_predictions/*.fas
#   ${REPO}/db/cgf/cgf_proteins_all.faa
#   ${REPO}/db/cgf/cgf_clusters_rep_seq.fasta
#   ${REPO}/db/cgf/cgf_proteins.dmnd
#   ${REPO}/db/cgf/cgf_species_map.tsv
# 用  法: bash 74b_fun_cgf_db_build.sh -t CPUS -r REPO
#     注: -r 默认使用脚本所在目录的父目录（MaxMetagenome 项目根目录）
# ==============================================================================

set -euo pipefail

show_help() {
cat << EOF
用法: bash 74b_fun_cgf_db_build.sh -t CPUS -r REPO

参数:
  -t  线程数（默认: 1）
  -r  MaxMetagenome 项目根目录（默认: 脚本所在目录的父目录）

示例:
  bash 74b_fun_cgf_db_build.sh -t 16 -r ~/Course/Maxmetagenome

WARNING:
  This script runs for several hours on 709 genomes. Run in screen/tmux.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"

CPUS="1"
REPO="${DEFAULT_REPO}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) CPUS="$2"; shift 2 ;;
        -r) REPO="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if ! [[ "${CPUS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] -t 必须是正整数: ${CPUS}"
    exit 1
fi

if [ ! -d "${REPO}" ]; then
    echo "[ERROR] REPO 不存在: ${REPO}"
    exit 1
fi
REPO="$(cd "${REPO}" && pwd)"

SECONDS=0

CGF_DIR="${REPO}/db/cgf"
GENOME_DIR="${CGF_DIR}/genomes"
PRED_DIR="${CGF_DIR}/metaeuk_predictions"
METAEUK_TMP_DIR="${CGF_DIR}/metaeuk_tmp"
MMSEQS_TMP_DIR="${CGF_DIR}/mmseqs_tmp"
FUNOMIC_DB="${REPO}/db/funomic/P/FunOMIC.P.v1.dmnd"
ASSEMBLY_REPORT="${CGF_DIR}/assembly_report.jsonl"
ALL_PROTEINS="${CGF_DIR}/cgf_proteins_all.faa"
CLUSTER_PREFIX="${CGF_DIR}/cgf_clusters"
REP_SEQ="${CGF_DIR}/cgf_clusters_rep_seq.fasta"
DIAMOND_DB="${CGF_DIR}/cgf_proteins.dmnd"
SPECIES_MAP="${CGF_DIR}/cgf_species_map.tsv"

if [ -s "${DIAMOND_DB}" ] && [ -s "${SPECIES_MAP}" ]; then
    echo "DB already built"
    echo "[INFO] DIAMOND DB: ${DIAMOND_DB}"
    echo "[INFO] Species map: ${SPECIES_MAP}"
    exit 0
fi

if [ ! -d "${GENOME_DIR}" ]; then echo "[ERROR] CGF genome directory 不存在: ${GENOME_DIR}"; exit 1; fi
if [ ! -s "${FUNOMIC_DB}" ]; then echo "[ERROR] FunOMIC protein DB 不存在或为空: ${FUNOMIC_DB}"; exit 1; fi
if [ ! -s "${ASSEMBLY_REPORT}" ]; then echo "[ERROR] assembly_report.jsonl 不存在或为空: ${ASSEMBLY_REPORT}"; exit 1; fi
if [ ! -d "${REPO}/envs/metaeuk" ]; then echo "[ERROR] MetaEuk conda env 不存在: ${REPO}/envs/metaeuk"; exit 1; fi
if [ ! -d "${REPO}/envs/assembly" ]; then echo "[ERROR] assembly conda env 不存在: ${REPO}/envs/assembly"; exit 1; fi

N_GENOMES=$(find "${GENOME_DIR}" -maxdepth 1 -type f -name 'GCA_*.fna' | wc -l | tr -d ' ')
if [ "${N_GENOMES}" -eq 0 ]; then
    echo "[ERROR] 未找到输入基因组: ${GENOME_DIR}/GCA_*.fna"
    exit 1
fi

if [ "${CPUS}" -lt 8 ]; then
    META_JOBS=1
    META_THREADS="${CPUS}"
else
    META_JOBS=$((CPUS / 4))
    META_THREADS=4
fi

echo "WARNING: This script runs for several hours on ${N_GENOMES} genomes. Run in a screen/tmux session."
echo "[cgf_db_build] REPO: ${REPO}"
echo "[cgf_db_build] CPUS: ${CPUS} | MetaEuk parallel jobs: ${META_JOBS} | threads/job: ${META_THREADS}"

mkdir -p "${PRED_DIR}" "${METAEUK_TMP_DIR}" "${CGF_DIR}"

echo "[cgf_db_build] Step 1/5: MetaEuk gene prediction (${N_GENOMES} genomes)..."
N_PRED_DONE=$(find "${PRED_DIR}" -maxdepth 1 -type f -name 'GCA_*.fas' -size +0c | wc -l | tr -d ' ')
if [ "${N_PRED_DONE}" -ge "${N_GENOMES}" ]; then
    echo "[INFO] MetaEuk predictions already complete: ${N_PRED_DONE}/${N_GENOMES}"
else
    find "${GENOME_DIR}" -maxdepth 1 -type f -name 'GCA_*.fna' -print0 | \
        xargs -0 -n 1 -P "${META_JOBS}" bash -c '
            set -euo pipefail
            pred_dir="$1"
            tmp_root="$2"
            funomic_db="$3"
            repo="$4"
            threads="$5"
            genome="$6"

            base="$(basename "${genome}" .fna)"
            out_prefix="${pred_dir}/${base}"
            out_fas="${out_prefix}.fas"
            tmp_dir="${tmp_root}/${base}"

            if [ -s "${out_fas}" ]; then
                echo "[INFO] MetaEuk skip existing: ${base}.fas"
                exit 0
            fi

            echo "[INFO] MetaEuk start: ${base}"
            mkdir -p "${tmp_root}"
            rm -rf "${tmp_dir}"

            conda run --prefix "${repo}/envs/metaeuk" --no-capture-output \
                metaeuk easy-predict \
                    "${genome}" \
                    "${funomic_db}" \
                    "${out_prefix}" \
                    "${tmp_dir}" \
                    --threads "${threads}" \
                    -s 7.5 \
                    --min-length 100 \
                    --translation-table 1

            if [ ! -s "${out_fas}" ]; then
                echo "[ERROR] MetaEuk did not create protein FASTA: ${out_fas}" >&2
                rm -f "${out_fas}" "${out_prefix}.codon.fas"
                exit 1
            fi

            rm -rf "${tmp_dir}"
            n_seq=$(grep -c "^>" "${out_fas}" 2>/dev/null || true)
            echo "[INFO] MetaEuk done: ${base} | proteins: ${n_seq:-0}"
        ' _ "${PRED_DIR}" "${METAEUK_TMP_DIR}" "${FUNOMIC_DB}" "${REPO}" "${META_THREADS}"

    N_PRED_DONE=$(find "${PRED_DIR}" -maxdepth 1 -type f -name 'GCA_*.fas' -size +0c | wc -l | tr -d ' ')
    if [ "${N_PRED_DONE}" -lt "${N_GENOMES}" ]; then
        echo "[ERROR] MetaEuk predictions incomplete: ${N_PRED_DONE}/${N_GENOMES}"
        exit 1
    fi
fi

echo "[cgf_db_build] Step 2/5: Merge predicted proteins and prefix headers with GCA accession..."
if [ -s "${ALL_PROTEINS}" ]; then
    N_ALL=$(grep -c '^>' "${ALL_PROTEINS}" 2>/dev/null || true)
    echo "[INFO] Merged protein FASTA already exists: ${ALL_PROTEINS} | sequences: ${N_ALL:-0}"
else
    python3 - "${PRED_DIR}" "${ALL_PROTEINS}" << 'PY'
import glob
import os
import re
import sys

pred_dir, out_faa = sys.argv[1], sys.argv[2]
fas_files = sorted(glob.glob(os.path.join(pred_dir, "GCA_*.fas")))
if not fas_files:
    raise SystemExit(f"[ERROR] No MetaEuk FASTA files found in {pred_dir}")

tmp_out = out_faa + ".tmp"
n_seq = 0
n_file = 0

with open(tmp_out, "w", encoding="utf-8") as out:
    for fas in fas_files:
        base = os.path.basename(fas)
        match = re.search(r"(GCA_\d+\.\d+)", base)
        if not match:
            raise SystemExit(f"[ERROR] Cannot parse GCA accession from {base}")
        accession = match.group(1)
        file_has_seq = False

        with open(fas, "r", encoding="utf-8", errors="replace") as handle:
            for raw in handle:
                line = raw.rstrip("\n")
                if not line:
                    continue
                if line.startswith(">"):
                    original_id = line[1:].strip().split()[0]
                    if not original_id:
                        raise SystemExit(f"[ERROR] Empty FASTA header in {fas}")
                    out.write(f">{accession}__{original_id}\n")
                    n_seq += 1
                    file_has_seq = True
                else:
                    out.write(line + "\n")

        if file_has_seq:
            n_file += 1

os.replace(tmp_out, out_faa)
print(f"[INFO] Merged {n_seq} sequences from {n_file} FASTA files: {out_faa}")
PY
fi

if [ ! -s "${ALL_PROTEINS}" ]; then
    echo "[ERROR] Merged protein FASTA missing or empty: ${ALL_PROTEINS}"
    exit 1
fi
N_ALL=$(grep -c '^>' "${ALL_PROTEINS}" 2>/dev/null || true)
if [ "${N_ALL:-0}" -eq 0 ]; then
    echo "[ERROR] Merged protein FASTA contains no sequences: ${ALL_PROTEINS}"
    exit 1
fi
echo "[INFO] Total CGF protein sequences: ${N_ALL}"

echo "[cgf_db_build] Step 3/5: MMseqs2 clustering (50% AAI, 90% coverage)..."
if [ -s "${REP_SEQ}" ]; then
    N_REP=$(grep -c '^>' "${REP_SEQ}" 2>/dev/null || true)
    echo "[INFO] Representative sequences already exist: ${REP_SEQ} | representatives: ${N_REP:-0}"
else
    rm -rf "${MMSEQS_TMP_DIR}"
    conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
        mmseqs easy-cluster \
            "${ALL_PROTEINS}" \
            "${CLUSTER_PREFIX}" \
            "${MMSEQS_TMP_DIR}" \
            --min-seq-id 0.50 \
            -c 0.90 \
            --cov-mode 0 \
            --cluster-mode 2 \
            --threads "${CPUS}"

    if [ ! -s "${REP_SEQ}" ]; then
        echo "[ERROR] MMseqs2 did not create representative FASTA: ${REP_SEQ}"
        exit 1
    fi
    rm -rf "${MMSEQS_TMP_DIR}"
fi

N_REP=$(grep -c '^>' "${REP_SEQ}" 2>/dev/null || true)
if [ "${N_REP:-0}" -eq 0 ]; then
    echo "[ERROR] Representative FASTA contains no sequences: ${REP_SEQ}"
    exit 1
fi
echo "[INFO] Representative sequences: ${N_REP}"

echo "[cgf_db_build] Step 4/5: Build DIAMOND database..."
if [ -s "${DIAMOND_DB}" ]; then
    echo "[INFO] DIAMOND DB already exists: ${DIAMOND_DB}"
else
    conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
        diamond makedb \
            --in "${REP_SEQ}" \
            --db "${DIAMOND_DB}" \
            --threads "${CPUS}" \
            --ignore-warnings

    if [ ! -s "${DIAMOND_DB}" ]; then
        echo "[ERROR] DIAMOND DB missing or empty after makedb: ${DIAMOND_DB}"
        rm -f "${DIAMOND_DB}"
        exit 1
    fi
fi

echo "[cgf_db_build] Step 5/5: Build GCA to species map with species-average genome size..."
if [ -s "${SPECIES_MAP}" ]; then
    N_MAP=$(wc -l < "${SPECIES_MAP}" | tr -d ' ')
    echo "[INFO] Species map already exists: ${SPECIES_MAP} | rows: ${N_MAP}"
else
    python3 - "${ASSEMBLY_REPORT}" "${GENOME_DIR}" "${SPECIES_MAP}" << 'PY'
import glob
import json
import os
import re
import statistics
import sys
from collections import defaultdict

report_jsonl, genome_dir, out_tsv = sys.argv[1], sys.argv[2], sys.argv[3]

accession_to_species = {}
with open(report_jsonl, "r", encoding="utf-8") as handle:
    for line_no, line in enumerate(handle, 1):
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"[ERROR] Invalid JSON at {report_jsonl}:{line_no}: {exc}") from exc

        accession = str(record.get("accession", "")).strip()
        organism = record.get("organism") or {}
        species = str(organism.get("organism_name", "")).strip()
        if accession and species:
            accession_to_species[accession] = species

genome_rows = []
species_sizes = defaultdict(list)
for fna in sorted(glob.glob(os.path.join(genome_dir, "GCA_*.fna"))):
    base = os.path.basename(fna)
    match = re.search(r"(GCA_\d+\.\d+)", base)
    if not match:
        raise SystemExit(f"[ERROR] Cannot parse GCA accession from {base}")

    accession = match.group(1)
    species = accession_to_species.get(accession, "Unknown")
    size_mb = os.path.getsize(fna) / 1024 / 1024
    genome_rows.append((accession, species, size_mb))
    species_sizes[species].append(size_mb)

if not genome_rows:
    raise SystemExit(f"[ERROR] No GCA_*.fna genomes found in {genome_dir}")

species_avg_mb = {
    species: statistics.fmean(sizes)
    for species, sizes in species_sizes.items()
}

tmp_out = out_tsv + ".tmp"
missing_species = 0
with open(tmp_out, "w", encoding="utf-8") as out:
    for accession, species, _size_mb in genome_rows:
        if species == "Unknown":
            missing_species += 1
        out.write(f"{accession}\t{species}\t{species_avg_mb[species]:.1f}\n")

os.replace(tmp_out, out_tsv)
print(f"[INFO] Wrote {len(genome_rows)} rows: {out_tsv}")
if missing_species:
    print(f"[WARN] Missing species names for {missing_species} accessions; wrote species as Unknown")
PY
fi

if [ ! -s "${SPECIES_MAP}" ]; then
    echo "[ERROR] Species map missing or empty: ${SPECIES_MAP}"
    exit 1
fi

N_MAP=$(wc -l < "${SPECIES_MAP}" | tr -d ' ')
echo "[cgf_db_build] 完成，耗时 ${SECONDS}s"
echo "[cgf_db_build] DIAMOND DB: ${DIAMOND_DB}"
echo "[cgf_db_build] Species map rows: ${N_MAP} | ${SPECIES_MAP}"
