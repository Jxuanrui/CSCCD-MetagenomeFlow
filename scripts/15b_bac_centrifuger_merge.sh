#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 15b_bac_centrifuger_merge.sh
# 功  能: 合并所有样本的 Centrifuger kreport 表，生成项目级多样本矩阵
# 依  赖: 15_bac_centrifuger.sh 的输出（每个样本的 .kreport.tsv）
# 输  入: ${WORKDIR}/result/centrifuger/*/  （扫描所有已完成样本）
# 输  出: ${WORKDIR}/result/centrifuger/merged/kreport_S.tsv  （种级多样本丰度表）
#         ${WORKDIR}/result/centrifuger/merged/kreport_G.tsv  （属级多样本丰度表）
#         ${WORKDIR}/result/centrifuger/merged/kreport_P.tsv  （门级多样本丰度表）
# 用  法: bash 15b_bac_centrifuger_merge.sh -w /path/to/Project_example -r /path/to/CSCCD-MetagenomeFlow
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

# --- 参数解析 ---

show_help() { cat << EOF

用法: bash 15b_bac_centrifuger_merge.sh -w WORKDIR -r REPO

参数说明:
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

示例:
  bash 15b_bac_centrifuger_merge.sh \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project_example \\
       -r ~/Course/CSCCD-MetagenomeFlow

可选参数:
  --force  强制重新运行（忽略已存在的结果）
EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

# --- 路径设置 ---

PROFILE_DIR="${WORKDIR}/result/centrifuger"
MERGED_DIR="${PROFILE_DIR}/merged"

KREPORT_S_TSV="${MERGED_DIR}/kreport_S.tsv"
KREPORT_G_TSV="${MERGED_DIR}/kreport_G.tsv"
KREPORT_P_TSV="${MERGED_DIR}/kreport_P.tsv"

# --- 收集所有已完成的 kreport 文件 ---

SAMPLE_LIST=()
for sample_dir in "${PROFILE_DIR}"/*/; do
    sample=$(basename "${sample_dir}")
    [ "${sample}" = "merged" ] && continue
    kreport="${sample_dir}/${sample}.kreport.tsv"
    if [ -f "${kreport}" ]; then
        SAMPLE_LIST+=("${sample}")
    fi
done

if [ ${#SAMPLE_LIST[@]} -eq 0 ]; then
    echo "[ERROR] 未找到任何 Centrifuger kreport 文件"
    echo "        期望路径: ${PROFILE_DIR}/<SAMPLE>/<SAMPLE>.kreport.tsv"
    echo "        请先运行 15_bac_centrifuger.sh"
    exit 1
fi

mapfile -t SAMPLE_LIST < <(printf '%s\n' "${SAMPLE_LIST[@]}" | sort)

echo "[centrifuger_merge] 找到 ${#SAMPLE_LIST[@]} 个样本 profile:"
for sample in "${SAMPLE_LIST[@]}"; do
    echo "    ${sample}"
done

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${KREPORT_S_TSV}" ] && [ -f "${KREPORT_G_TSV}" ] && [ -f "${KREPORT_P_TSV}" ]; then
    echo "[INFO] 合并结果已存在，跳过。如需重新合并请先删除 ${MERGED_DIR}"
    exit 0
fi

mkdir -p "${MERGED_DIR}"

# --- Step 1: 按分类级别构建多样本矩阵 ---

echo "[INFO] 合并多样本 kreport 丰度表..."
python3 - "${PROFILE_DIR}" "${MERGED_DIR}" "${SAMPLE_LIST[@]}" <<'PYEOF'
import csv
import os
import sys

profile_dir = sys.argv[1]
merged_dir = sys.argv[2]
samples = sys.argv[3:]

if not samples:
    print("[ERROR] 未收到任何样本名", file=sys.stderr)
    sys.exit(1)

levels = ["S", "G", "P"]

for level in levels:
    taxa = {}
    all_taxa = set()

    for sample in samples:
        kreport = os.path.join(profile_dir, sample, f"{sample}.kreport.tsv")
        if not os.path.isfile(kreport):
            print(f"[ERROR] 缺少 kreport 文件: {kreport}", file=sys.stderr)
            sys.exit(1)

        with open(kreport, "r", encoding="utf-8") as handle:
            for line in handle:
                line = line.rstrip("\n")
                if not line:
                    continue

                parts = line.split("\t")
                if len(parts) < 6:
                    continue

                rank = parts[3].strip()
                if rank != level:
                    continue

                taxon = parts[5].lstrip()
                if not taxon:
                    continue

                try:
                    pct = float(parts[0].strip())
                except ValueError:
                    continue

                all_taxa.add(taxon)
                taxa.setdefault(taxon, {})[sample] = pct

    output_tsv = os.path.join(merged_dir, f"kreport_{level}.tsv")
    with open(output_tsv, "w", newline="", encoding="utf-8") as out_handle:
        writer = csv.writer(out_handle, delimiter="\t")
        writer.writerow(["Taxonomy"] + samples)
        for taxon in sorted(all_taxa):
            row = [taxon]
            for sample in samples:
                value = taxa.get(taxon, {}).get(sample, 0.0)
                row.append(f"{value:g}")
            writer.writerow(row)
PYEOF

for OUTPUT_TSV in "${KREPORT_S_TSV}" "${KREPORT_G_TSV}" "${KREPORT_P_TSV}"; do
    if [ ! -f "${OUTPUT_TSV}" ] || [ ! -s "${OUTPUT_TSV}" ]; then
        echo "[ERROR] 合并失败，未生成 ${OUTPUT_TSV}"
        exit 1
    fi
done

# --- 统计摘要 ---

echo ""
echo "[centrifuger_merge] 合并完成"
echo "[centrifuger_merge] 输出目录: ${MERGED_DIR}"
for LEVEL in S G P; do
    OUTPUT_TSV="${MERGED_DIR}/kreport_${LEVEL}.tsv"
    NROW=$(wc -l < "${OUTPUT_TSV}")
    NCOL=$(awk -F'\t' 'NR==1{print NF}' "${OUTPUT_TSV}")
    echo "    kreport_${LEVEL}.tsv — ${NROW} 行 × ${NCOL} 列"
done
mgx_end "centrifuger_merge"
