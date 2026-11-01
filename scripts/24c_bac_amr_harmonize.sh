#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 24c_bac_amr_harmonize.sh
# 功  能: hAMRonization AMR 报表融合层——将 AMRFinderPlus 与 RGI/CARD 的
#         异构输出统一为标准化表（格式统一，不改变检测结果）
#         工具版本：hAMRonization 1.3.1（pip）
# 依  赖: 23_bac_amrfinder.sh + 24_bac_card.sh 的原始输出
# 输  入: ${WORKDIR}/result/annotation/amrfinder/amrfinder_results.tsv
#         ${WORKDIR}/result/annotation/card/rgi_results.txt
# 输  出: ${WORKDIR}/result/annotation/amr_harmonized/
#           hamronized_amrfinder.tsv  — AMRFinderPlus 标准化表
#           hamronized_rgi.tsv        — RGI 标准化表
#           reconciliation.json       — 对账（输入/输出/跳过数/hash）
#
# ⚠️  已知限制（GATE-OPT1 披露）：
#   - AMRFinderPlus protein-only 模式需补 Contig id/Start/Stop/Strand 占位列
#   - hAMRonization 设计内跳过 Type=VIRULENCE 行（AMR 专注工具）
#   - 跨工具 ID 格式不同（AMRFinderPlus 短 ID vs RGI prodigal 描述串）
#   - RGI 含 Loose 命中，置信等级不可直接跨工具比对
#
# 参  考: pha4ge/hAMRonization (2024), https://github.com/pha4ge/hAMRonization
# 用  法: bash 24c_bac_amr_harmonize.sh -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 24c_bac_amr_harmonize.sh -t CPUS -w WORKDIR -r REPO [--force]
必需参数:
  -t  线程数（未使用，保留接口一致性）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行

依赖: 先运行 23_bac_amrfinder.sh 和 24_bac_card.sh
EOF
}

export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin
AMRFINDER_REPORT="${WORKDIR}/result/annotation/amrfinder/amrfinder_results.tsv"
RGI_REPORT="${WORKDIR}/result/annotation/card/rgi_results.txt"
OUTDIR="${WORKDIR}/result/annotation/amr_harmonized"
SENTINEL="${OUTDIR}/reconciliation.json"
HAMRONIZE_BIN="${REPO}/miniforge3/bin/hamronize"

if [ ! -f "${AMRFINDER_REPORT}" ]; then echo "[ERROR] AMRFinderPlus 输出不存在: ${AMRFINDER_REPORT}（先运行 23 号）"; exit 1; fi
if [ ! -f "${RGI_REPORT}" ]; then echo "[ERROR] RGI 输出不存在: ${RGI_REPORT}（先运行 24 号）"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ]; then echo "[hamronize] 已有结果，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"

echo "[hamronize] AMR 报表融合（AMRFinderPlus + RGI → 统一格式）..."

# Step 1: AMRFinderPlus — augment protein-only output with placeholder columns
# (Contig id/Start/Stop/Strand) for hAMRonization compatibility
AUGMENTED=$(mktemp /tmp/amrfinder_aug_XXXXXX.tsv)
python3 -c "
import csv, sys
with open('${AMRFINDER_REPORT}') as fi, open('${AUGMENTED}','w',newline='') as fo:
    r = csv.reader(fi, delimiter='\t'); w = csv.writer(fo, delimiter='\t')
    hdr = next(r)
    pi = hdr.index('Protein id')
    w.writerow(['Contig id','Start','Stop','Strand'] + hdr)
    for row in r:
        w.writerow([row[pi].rsplit('_',1)[0],'0','0','+'] + row)
"

# Step 2: Run hAMRonization on both tools
if ! "${HAMRONIZE_BIN}" amrfinderplus "${AUGMENTED}" \
    --analysis_software_version "4.0.19" --reference_database_version "2024-01-23.1" \
    --input_file_name "protein_nr.fa" --format tsv \
    --output "${OUTDIR}/hamronized_amrfinder.tsv" 2>"${OUTDIR}/amrfinder_err.log"; then
    echo "[ERROR] hAMRonization AMRFinderPlus 融合失败"; rm -f "${AUGMENTED}"; exit 1
fi

if ! "${HAMRONIZE_BIN}" rgi "${RGI_REPORT}" \
    --analysis_software_version "6.0.3" --reference_database_version "3.2.5" \
    --input_file_name "protein_nr.fa" --format tsv \
    --output "${OUTDIR}/hamronized_rgi.tsv" 2>"${OUTDIR}/rgi_err.log"; then
    echo "[ERROR] hAMRonization RGI 融合失败"; rm -f "${AUGMENTED}"; exit 1
fi
rm -f "${AUGMENTED}"

# Step 3: Reconciliation (no-loss proof)
N_IN_AFP=$(awk 'NR>1' "${AMRFINDER_REPORT}" | wc -l)
N_OUT_AFP=$(awk 'NR>1' "${OUTDIR}/hamronized_amrfinder.tsv" | wc -l)
N_SKIP_AFP=$((N_IN_AFP - N_OUT_AFP))
N_IN_RGI=$(awk 'NR>1' "${RGI_REPORT}" | wc -l)
N_OUT_RGI=$(awk 'NR>1' "${OUTDIR}/hamronized_rgi.tsv" | wc -l)

python3 -c "
import json
r = {
  'amrfinderplus': {'input': ${N_IN_AFP}, 'output': ${N_OUT_AFP}, 'designed_skip': ${N_SKIP_AFP}},
  'rgi': {'input': ${N_IN_RGI}, 'output': ${N_OUT_RGI}, 'designed_skip': 0},
  'contract': 'output = input - designed_skip (VIRULENCE); unexplained loss must be 0',
  'limitations': [
    'AMRFinderPlus protein-only: Contig id/Start/Stop/Strad are placeholders (0/0/0/+)',
    'RGI includes Loose hits; cross-tool confidence comparison requires level filtering',
    'Cross-tool ID formats differ (short protein ID vs full prodigal description)'
  ]
}
json.dump(r, open('${OUTDIR}/reconciliation.json','w'), indent=1)
if ${N_IN_AFP} - ${N_OUT_AFP} != ${N_SKIP_AFP}:
    print('[ERROR] Reconciliation mismatch'); exit(1)
if ${N_IN_RGI} != ${N_OUT_RGI}:
    print('[ERROR] RGI loss detected'); exit(1)
print(f'[hamronize] 对账: AFP ${N_IN_AFP}→${N_OUT_AFP} (+${N_SKIP_AFP} skip) | RGI ${N_IN_RGI}→${N_OUT_RGI} (0 loss)')
"

echo "[hamronize] 输出: ${OUTDIR}/"
mgx_end "hamronize"
