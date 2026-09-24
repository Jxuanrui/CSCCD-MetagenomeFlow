#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 72b_fun_metaphlan4_merge.sh
# 功  能: 合并所有样本的真菌 MetaPhlAn4 物种丰度表，生成项目级多样本矩阵
# 依  赖: 72_fun_metaphlan4_euk.sh 的输出（每个样本的 _profile.txt）
# 输  入: ${WORKDIR}/result/fungi/metaphlan4/*/  （扫描所有已完成样本）
# 输  出: ${WORKDIR}/result/fungi/metaphlan4/merged/taxonomy.tsv     （全层级丰度表，供统计分析）
#         ${WORKDIR}/result/fungi/metaphlan4/merged/taxonomy_species.tsv  （仅菌种级）
#         ${WORKDIR}/result/fungi/metaphlan4/merged/taxonomy_genus.tsv    （仅菌属级）
#         ${WORKDIR}/result/fungi/metaphlan4/merged/taxonomy_species.csv  （菌种级 CSV，列=样本，行=物种）
# 用  法: bash 72b_fun_metaphlan4_merge.sh -w /path/to/Project_example -r /path/to/CSCCD-MetagenomeFlow
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

# --- 参数解析 ---

show_help() { cat << EOF

用法: bash 72b_fun_metaphlan4_merge.sh -w WORKDIR -r REPO

参数说明:
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

示例:
  bash 72b_fun_metaphlan4_merge.sh \\
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

PROFILE_DIR="${WORKDIR}/result/fungi/metaphlan4"
MERGED_DIR="${PROFILE_DIR}/merged"

TAXONOMY_TSV="${MERGED_DIR}/taxonomy.tsv"
SPECIES_TSV="${MERGED_DIR}/taxonomy_species.tsv"
GENUS_TSV="${MERGED_DIR}/taxonomy_genus.tsv"
SPECIES_CSV="${MERGED_DIR}/taxonomy_species.csv"

# --- 收集所有已完成的 profile 文件 ---

PROFILE_LIST=()
for sample_dir in "${PROFILE_DIR}"/*/; do
    sample=$(basename "${sample_dir}")
    # 跳过 merged 目录本身
    [ "${sample}" = "merged" ] && continue
    profile="${sample_dir}/${sample}_profile.txt"
    if [ -f "${profile}" ]; then
        PROFILE_LIST+=("${profile}")
    fi
done

if [ ${#PROFILE_LIST[@]} -eq 0 ]; then
    echo "[ERROR] 未找到任何 MetaPhlAn4 profile 文件"
    echo "        期望路径: ${PROFILE_DIR}/<SAMPLE>/<SAMPLE>_profile.txt"
    echo "        请先运行 72_fun_metaphlan4_euk.sh"
    exit 1
fi

echo "[metaphlan4_merge] 找到 ${#PROFILE_LIST[@]} 个样本 profile:"
for p in "${PROFILE_LIST[@]}"; do
    echo "    $(basename "$(dirname "${p}")")"
done

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${TAXONOMY_TSV}" ] && [ -f "${SPECIES_CSV}" ]; then
    echo "[INFO] 合并结果已存在，跳过。如需重新合并请先删除 ${MERGED_DIR}"
    exit 0
fi

mkdir -p "${MERGED_DIR}"

# --- Step 1: 合并所有样本，生成全层级丰度表 ---
# merge_metaphlan_tables.py 输出：
#   第1行: #mpa_vXxx 数据库版本注释
#   第2行: clade_name  sample1  sample2 ...
#   后续行: 数据
# 处理：
#   - tail -n+2 去掉数据库版本注释行
#   - sed '1 s/clade_name/ID' 将列头改为 ID（与下游统计脚本兼容）
#   - sed '2i #metaphlan4' 插入工具标识注释行

echo "[INFO] 合并多样本丰度表..."
mgx_conda humann4 \
    merge_metaphlan_tables.py "${PROFILE_LIST[@]}" \
    | tail -n+2 \
    | sed '1 s/clade_name/ID/' \
    | sed '2i #metaphlan4' \
    > "${TAXONOMY_TSV}"

if [ ! -f "${TAXONOMY_TSV}" ] || [ ! -s "${TAXONOMY_TSV}" ]; then
    echo "[ERROR] 合并失败，未生成 ${TAXONOMY_TSV}"
    exit 1
fi

NROW=$(grep -v "^#" "${TAXONOMY_TSV}" | wc -l)
NCOL=$(head -1 "${TAXONOMY_TSV}" | awk -F'\t' '{print NF-1}')
echo "[INFO] taxonomy.tsv: ${NROW} 行（含所有分类层级）× ${NCOL} 个样本"

# --- Step 2: 提取菌种级别（s__ 不含 t__）---

echo "[INFO] 提取菌种级丰度表..."
{
    grep "^#\|^ID" "${TAXONOMY_TSV}"
    grep -v "^#" "${TAXONOMY_TSV}" | grep "s__" | grep -v "t__"
} > "${SPECIES_TSV}"

NSPECIES=$(grep -v "^#" "${SPECIES_TSV}" | wc -l)
echo "[INFO] taxonomy_species.tsv: ${NSPECIES} 个菌种"

# --- Step 3: 提取菌属级别（g__ 不含 s__）---

echo "[INFO] 提取菌属级丰度表..."
{
    grep "^#\|^ID" "${TAXONOMY_TSV}"
    grep -v "^#" "${TAXONOMY_TSV}" | grep "g__" | grep -v "s__"
} > "${GENUS_TSV}"

NGENUS=$(grep -v "^#" "${GENUS_TSV}" | wc -l)
echo "[INFO] taxonomy_genus.tsv: ${NGENUS} 个菌属"

# --- Step 4: 生成菌种级 CSV（只含物种名+相对丰度，不含完整层级路径）---
# 从 clade_name 中提取最末尾的 s__xxx，转为简洁物种名

echo "[INFO] 生成菌种级 CSV..."
python3 - <<PYEOF
import csv, sys

tsv_path = "${SPECIES_TSV}"
csv_path = "${SPECIES_CSV}"

rows = []
header = None

with open(tsv_path) as f:
    for line in f:
        line = line.rstrip('\n')
        if line.startswith('#'):
            continue
        parts = line.split('\t')
        if parts[0] == 'ID':
            # 样本名列头
            header = ['species'] + parts[1:]
            continue
        clade = parts[0]
        # 提取最末级物种名（s__之后的部分），去掉前缀 s__
        species_tag = [x for x in clade.split('|') if x.startswith('s__')]
        if not species_tag:
            continue
        species_name = species_tag[-1][3:].replace('_', ' ')
        rows.append([species_name] + parts[1:])

if header is None:
    print("ERROR: header not found", file=sys.stderr)
    sys.exit(1)

# 按第一样本丰度降序排列
if len(header) > 1:
    rows.sort(key=lambda x: float(x[1]) if x[1] else 0, reverse=True)

with open(csv_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(header)
    writer.writerows(rows)

print(f"[INFO] taxonomy_species.csv: {len(rows)} 个菌种 × {len(header)-1} 个样本")
PYEOF

# --- 统计摘要 ---

echo ""
echo "[metaphlan4_merge] 合并完成"
echo "[metaphlan4_merge] 输出目录: ${MERGED_DIR}"
echo "    taxonomy.tsv         — 全层级丰度表（供统计分析脚本 91+ 使用）"
echo "    taxonomy_species.tsv — 菌种级 TSV"
echo "    taxonomy_genus.tsv   — 菌属级 TSV"
echo "    taxonomy_species.csv — 菌种级 CSV（列=样本，行=物种，可直接导入 Excel/R）"
mgx_end "metaphlan4_merge"
