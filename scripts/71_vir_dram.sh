#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 71_vir_dram.sh
# 功  能: vMAG 病毒功能注释（DRAM-v annotate + distill）
#         工具版本：DRAM 1.5.0（conda env: dram）
# 依  赖: 61_vir_vmag.sh / 62_vir_checkv_mag.sh 的 vMAG FASTA
# 输  入: ${WORKDIR}/result/virus/vmag/ 下的 vMAG FASTA
# 输  出: ${WORKDIR}/result/virus/dram/
#           all_vmags.fa             — 合并后的 vMAG 序列
#           annotate/                — DRAM-v 注释结果
#           distill/                 — DRAM-v AMG 汇总结果
#           DRAM_annotations.tsv     — 注释结果汇总
#           DRAM_amg_summary.tsv     — AMG 汇总表
#
# 参  考: Shaffer et al. 2020 Nucleic Acids Research (DRAM)
# 用  法: bash 71_vir_dram.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 71_vir_dram.sh -t CPUS -w WORKDIR -r REPO
必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
VMAG_DIR="${WORKDIR}/result/virus/vmag"
OUTDIR="${WORKDIR}/result/virus/dram"
ANNOTATE_DIR="${OUTDIR}/annotate"
DISTILL_DIR="${OUTDIR}/distill"
MERGED_VMAG_FA="${OUTDIR}/all_vmags.fa"
SENTINEL="${OUTDIR}/DRAM_annotations.tsv"
AMG_SUMMARY="${OUTDIR}/DRAM_amg_summary.tsv"
DRAM_DB="${REPO}/db/dram_db"
DRAM_ENV="${REPO}/envs/dram"
DRAM_CONFIG="${OUTDIR}/dram_config.json"

if [ ! -d "${VMAG_DIR}" ]; then echo "[WARN] vMAG 目录不存在: ${VMAG_DIR}"; exit 0; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[dram] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

_db_path() { [ -f "$1" ] && echo "\"$1\"" || echo "null"; }

build_dram_config() {
    local db_root="$1"
    local config_path="$2"
    cat > "${config_path}" << EOF
{
  "search_databases": {
    "kegg": null,
    "kofam_hmm": $(_db_path "${db_root}/kofam_profiles.hmm"),
    "kofam_ko_list": $(_db_path "${db_root}/kofam_ko_list.tsv"),
    "uniref": null,
    "pfam": $(_db_path "${db_root}/pfam.mmspro"),
    "dbcan": $(_db_path "${db_root}/dbCAN-HMMdb-V11.txt"),
    "viral": $(_db_path "${db_root}/refseq_viral.20260528.mmsdb"),
    "peptidase": $(_db_path "${db_root}/peptidases.20260528.mmsdb"),
    "vogdb": $(_db_path "${db_root}/vog_latest_hmms.txt"),
    "camper_fa_db": null,
    "camper_fa_db_cutoffs": null,
    "camper_hmm": null
  },
  "custom_dbs": null,
  "database_descriptions": {
    "pfam_hmm": $(_db_path "${db_root}/Pfam-A.hmm.dat.gz"),
    "dbcan_fam_activities": $(_db_path "${db_root}/CAZyDB.08062022.fam-activities.txt"),
    "dbcan_subfam_ec": $(_db_path "${db_root}/CAZyDB.08062022.fam.subfam.ec.txt"),
    "vog_annotations": $(_db_path "${db_root}/vog_annotations_latest.tsv.gz")
  },
  "dram_sheets": {
    "camper_distillate": null,
    "genome_summary_form": $(_db_path "${db_root}/genome_summary_form.20260527.tsv"),
    "module_step_form": $(_db_path "${db_root}/module_step_form.20260527.tsv"),
    "etc_module_database": $(_db_path "${db_root}/etc_mdoule_database.20260527.tsv"),
    "function_heatmap_form": $(_db_path "${db_root}/function_heatmap_form.20260527.tsv"),
    "amg_database": $(_db_path "${db_root}/amg_database.20260527.tsv")
  },
  "description_db": $(_db_path "${db_root}/description.db"),
  "dram_version": "1.5.0",
  "log_path": "${OUTDIR}/dram_db_setup.log"
}
EOF
}

shopt -s nullglob
VMAG_FASTAS=("${VMAG_DIR}/vmag_filtered"/*.fasta)
if [ ${#VMAG_FASTAS[@]} -eq 0 ]; then
    VMAG_FASTAS=("${VMAG_DIR}/bins/vMAG"/*.fasta)
fi
if [ ${#VMAG_FASTAS[@]} -eq 0 ]; then
    while IFS= read -r fa; do
        VMAG_FASTAS+=("$fa")
    done < <(find "${VMAG_DIR}" -type f \( -name "*.fa" -o -name "*.fasta" -o -name "*.fna" \) | sort)
fi
shopt -u nullglob

# 若无 vMAG bins，fallback 到 vOTU 代表序列（56 步输出）
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
if [ ${#VMAG_FASTAS[@]} -eq 0 ]; then
    if [ -f "${VOTU_FA}" ] && [ -s "${VOTU_FA}" ]; then
        echo "[dram] 未找到 vMAG bins，使用 vOTU 代表序列代替"
        VMAG_FASTAS=("${VOTU_FA}")
    else
        echo "[WARN] 未找到 vMAG FASTA 且 vOTU 序列不存在，跳过"
        exit 0
    fi
fi

echo "[dram] 合并 vMAG FASTA ..."
rm -f "${MERGED_VMAG_FA}"
for fa in "${VMAG_FASTAS[@]}"; do
    cat "${fa}" >> "${MERGED_VMAG_FA}"
done

if [ ! -s "${MERGED_VMAG_FA}" ]; then
    echo "[WARN] 合并后的 vMAG FASTA 为空: ${MERGED_VMAG_FA}"
    exit 0
fi

if [ ! -d "${DRAM_DB}" ]; then
    echo "[ERROR] DRAM 数据库目录不存在: ${DRAM_DB}"
    exit 1
fi

for req in \
    "${DRAM_DB}/amg_database.20260527.tsv" \
    "${DRAM_DB}/vog_latest_hmms.txt" \
    "${DRAM_DB}/CAZyDB.08062022.fam-activities.txt" \
    "${DRAM_DB}/CAZyDB.08062022.fam.subfam.ec.txt" \
    "${DRAM_DB}/dbCAN-HMMdb-V11.txt" \
    "${DRAM_DB}/description.db"; do
    if [ ! -f "${req}" ]; then
        echo "[ERROR] DRAM 数据库文件缺失: ${req}"
        exit 1
    fi
done

build_dram_config "${DRAM_DB}" "${DRAM_CONFIG}"

echo "[dram] DRAM-v annotate ..."
mgx_conda dram \
    DRAM-v.py annotate \
        -i "${MERGED_VMAG_FA}" \
        -o "${ANNOTATE_DIR}" \
        --threads "${CPUS}" \
        --config_loc "${DRAM_CONFIG}"

# Patch: DRAM-v distill crashes when viral DB is absent and auxiliary_score column is missing
conda run --prefix "${DRAM_ENV}" python3 -c "
import pandas as pd
df = pd.read_csv('${ANNOTATE_DIR}/annotations.tsv', sep='\t', index_col=0)
if 'auxiliary_score' not in df.columns:
    rank_idx = df.columns.get_loc('rank') if 'rank' in df.columns else 0
    df.insert(rank_idx + 1, 'auxiliary_score', 5)
    df.to_csv('${ANNOTATE_DIR}/annotations.tsv', sep='\t')
" 2>/dev/null

echo "[dram] DRAM-v distill ..."
rm -rf "${DISTILL_DIR}"
mgx_conda dram \
    DRAM-v.py distill \
        -i "${ANNOTATE_DIR}/annotations.tsv" \
        -o "${DISTILL_DIR}" \
        --config_loc "${DRAM_CONFIG}"

cp "${ANNOTATE_DIR}/annotations.tsv" "${SENTINEL}"
cp "${DISTILL_DIR}/amg_summary.tsv" "${AMG_SUMMARY}"

mgx_end "dram"
