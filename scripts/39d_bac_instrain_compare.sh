#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 39d_bac_instrain_compare.sh
# 功  能: 跨样本菌株群体 ANI 比较（inStrain compare，popANI 聚类）
#         工具版本：inStrain 1.10+（conda env: instrain）
# 依  赖: 39c_bac_instrain_profile.sh 全部样本的输出（profile 目录）
# 输  入: ${WORKDIR}/result/binning/instrain_profile/*/（所有样本 profile）
#         ${WORKDIR}/result/binning/instrain_map/combined_mags.stb
# 输  出: ${WORKDIR}/result/binning/instrain_compare/output/
#           instrain_compare_comparisonsTable.tsv     — 成对样本比较结果（popANI、覆盖重叠等）
#           instrain_compare_genomeWide_compare.tsv   — 基因组级跨样本 popANI 长表
#           strain_comparison_summary.tsv             — 汇总宽矩阵（本脚本新增后处理）：
#             每行一个 genome，列为各样本对 popANI + is_same_strain（popANI≥0.99999）
#
# ── 说明 ──────────────────────────────────────────────────────────────────────
#   本步骤为 aggregate，聚合所有样本的 inStrain profile，计算群体内 ANI
#   （popANI），判断跨样本/跨受试者是否为同一菌株（ANI ≥99.999% = 同株）。
#   样本数 < 2 时优雅跳过（单样本项目无需比较）。
#
# 参  考: Olm et al. 2021 Nat Biotechnol (inStrain)
# 用  法: bash 39d_bac_instrain_compare.sh -t CPUS -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 39d_bac_instrain_compare.sh -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -t  线程数
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
PROFILE_BASE="${WORKDIR}/result/binning/instrain_profile"
COMBINED_STB="${WORKDIR}/result/binning/instrain_map/combined_mags.stb"
OUTDIR="${WORKDIR}/result/binning/instrain_compare"
OUTPUT_COMPARISONS="${OUTDIR}/output/instrain_compare_comparisonsTable.tsv"
GENOMEWIDE_TSV="${OUTDIR}/output/instrain_compare_genomeWide_compare.tsv"
SUMMARY_TSV="${OUTDIR}/output/strain_comparison_summary.tsv"
STRAIN_ANI_THRESHOLD="0.99999"

if [ ! -f "${COMBINED_STB}" ]; then
    echo "[ERROR] scaffold-to-bin 文件不存在: ${COMBINED_STB}"; exit 1
fi

PROFILE_DIRS=()
if [ -d "${PROFILE_BASE}" ]; then
    for pdir in "${PROFILE_BASE}"/*; do
        if [ -d "${pdir}/output" ]; then
            GENOME_INFO="${pdir}/output/$(basename "${pdir}")_genome_info.tsv"
            if [ -f "${GENOME_INFO}" ] && [ -s "${GENOME_INFO}" ]; then
                PROFILE_DIRS+=("${pdir}")
            fi
        fi
    done
fi

N_PROFILES=${#PROFILE_DIRS[@]}
if [ "${N_PROFILES}" -lt 2 ]; then
    echo "[instrain_compare] WARNING: 样本数 < 2（共 ${N_PROFILES} 个有效 profile），跳过跨样本比较"
    mkdir -p "${OUTDIR}/output"
    : > "${OUTPUT_COMPARISONS}"
    : > "${SUMMARY_TSV}"
    exit 0
fi

if [ ${FORCE} -eq 0 ] && [ -f "${OUTPUT_COMPARISONS}" ] && [ -s "${OUTPUT_COMPARISONS}" ]; then
    echo "[instrain_compare] 结果已存在，跳过: ${OUTPUT_COMPARISONS}"; exit 0
fi

mkdir -p "${OUTDIR}"

echo "[instrain_compare] 跨样本 popANI 比较 | ${N_PROFILES} 个样本 | 线程: ${CPUS}"
EXIT_CODE=0
mgx_try mgx_conda instrain inStrain compare \
        -i "${PROFILE_DIRS[@]}" \
        -o "${OUTDIR}" \
        -s "${COMBINED_STB}" \
        -p "${CPUS}" || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then echo "[ERROR] inStrain compare 失败"; exit ${EXIT_CODE}; fi

N_COMPARISONS=0
if [ -f "${OUTPUT_COMPARISONS}" ]; then
    N_COMPARISONS=$(($(wc -l < "${OUTPUT_COMPARISONS}") - 1))
fi

# 后处理：genomeWide 长表（genome × 样本对一行）→ 宽矩阵汇总，直接给出每个 genome
# 跨所有样本对的最小 popANI 及是否全部判定为同株（popANI >= 阈值）
if [ -f "${GENOMEWIDE_TSV}" ] && [ -s "${GENOMEWIDE_TSV}" ]; then
    python3 - "${GENOMEWIDE_TSV}" "${SUMMARY_TSV}" "${STRAIN_ANI_THRESHOLD}" << 'PYEOF'
import csv
import sys

in_path, out_path, threshold = sys.argv[1], sys.argv[2], float(sys.argv[3])

genome_pairs = {}  # genome -> {pair_label: popani}
pair_labels = []
seen_pairs = set()

with open(in_path) as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        genome = row["genome"]
        pair_label = f"{row['name1']}_vs_{row['name2']}"
        if pair_label not in seen_pairs:
            seen_pairs.add(pair_label)
            pair_labels.append(pair_label)
        popani = float(row["popANI"]) if row["popANI"] not in ("", "NA") else float("nan")
        genome_pairs.setdefault(genome, {})[pair_label] = popani

with open(out_path, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(["genome", "n_pairs_compared", "min_popANI", "all_same_strain"] + pair_labels)
    for genome in sorted(genome_pairs):
        values = genome_pairs[genome]
        popanis = [v for v in values.values() if v == v]  # drop NaN
        min_popani = min(popanis) if popanis else float("nan")
        all_same = bool(popanis) and all(v >= threshold for v in popanis)
        row = [genome, len(popanis),
               f"{min_popani:.6f}" if min_popani == min_popani else "NA",
               "yes" if all_same else "no"]
        row += [f"{values.get(p, float('nan')):.6f}" if p in values and values[p] == values[p] else "NA"
                for p in pair_labels]
        writer.writerow(row)
PYEOF
    N_GENOMES=$(($(wc -l < "${SUMMARY_TSV}") - 1))
    echo "[instrain_compare] 汇总矩阵已生成: ${SUMMARY_TSV}（${N_GENOMES} 个基因组）"
else
    echo "[instrain_compare] WARNING: genomeWide 长表不存在，跳过汇总矩阵生成"
    : > "${SUMMARY_TSV}"
fi

echo "[instrain_compare] ${N_PROFILES} 样本 → ${N_COMPARISONS} 成对比较"
echo "[提示] 查看 ${OUTDIR}/output/ 下的 instrain_compare_comparisonsTable.tsv、instrain_compare_genomeWide_compare.tsv 获取原始 popANI 结果，strain_comparison_summary.tsv 获取汇总结论表"
mgx_end "instrain_compare"
