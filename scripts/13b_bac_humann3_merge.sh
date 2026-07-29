#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 13b_bac_humann3_merge.sh
# 功  能: 合并所有样本的 HUMAnN3 非分层功能丰度表，生成项目级多样本矩阵
# 依  赖: 13_bac_humann3.sh 的输出（每个样本的 unstratified relab 表）
# 输  入: ${WORKDIR}/result/humann3/*/  （扫描所有已完成样本）
# 输  出: ${WORKDIR}/result/humann3/merged/pathabundance_relab.tsv   （非分层通路丰度表）
#         ${WORKDIR}/result/humann3/merged/genefamilies_relab.tsv    （非分层基因家族丰度表）
# 用  法: bash 13b_bac_humann3_merge.sh -w /path/to/Project_example -r /path/to/MaxMetagenome
# ==============================================================================

# --- 参数解析 ---

if [ $# -lt 4 ]; then
    echo ""
    echo "用法: bash 13b_bac_humann3_merge.sh -w WORKDIR -r REPO"
    echo ""
    echo "参数说明:"
    echo "  -w  工作目录（Project_example 路径）"
    echo "  -r  MaxMetagenome 项目根目录"
    echo ""
    echo "示例:"
    echo "  bash 13b_bac_humann3_merge.sh \\"
    echo "       -w ~/Course/Maxmetagenome/Project/Project_example \\"
    echo "       -r ~/Course/Maxmetagenome"
    echo ""
    echo "可选参数:"
    echo "  --force  强制重新运行（忽略已存在的结果）"
    exit 1
fi

FORCE=0
ARGS=()
for arg in "$@"; do
    if [ "${arg}" = "--force" ]; then
        FORCE=1
    else
        ARGS+=("${arg}")
    fi
done
set -- "${ARGS[@]}"

while getopts w:r: option; do
    case "${option}" in
        w) WORKDIR=${OPTARG} ;;
        r) REPO=${OPTARG} ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-w/-r）"
    exit 1
fi

SECONDS=0

# --- 路径设置 ---

PROFILE_DIR="${WORKDIR}/result/humann3"
MERGED_DIR="${PROFILE_DIR}/merged"
STAGE_DIR="${PROFILE_DIR}/merge_stage"

PATHABUNDANCE_TSV="${MERGED_DIR}/pathabundance_relab.tsv"
GENEFAMILIES_TSV="${MERGED_DIR}/genefamilies_relab.tsv"

# --- 收集所有已完成的 HUMAnN3 非分层表 ---

SAMPLE_LIST=()
for sample_dir in "${PROFILE_DIR}"/*/; do
    sample=$(basename "${sample_dir}")
    [ "${sample}" = "merged" ] && continue
    [ "${sample}" = "merge_stage" ] && continue
    profile="${sample_dir}/${sample}_pathabundance_relab.tsv"
    if [ -f "${profile}" ]; then
        SAMPLE_LIST+=("${sample}")
    fi
done

if [ ${#SAMPLE_LIST[@]} -eq 0 ]; then
    echo "[ERROR] 未找到任何 HUMAnN3 非分层 relab 文件"
    echo "        期望路径: ${PROFILE_DIR}/<SAMPLE>/unstratified/<SAMPLE>_pathabundance_relab_unstratified.tsv"
    echo "        请先运行 13_bac_humann3.sh"
    exit 1
fi

mapfile -t SAMPLE_LIST < <(printf '%s\n' "${SAMPLE_LIST[@]}" | sort)

echo "[humann3_merge] 找到 ${#SAMPLE_LIST[@]} 个样本 profile:"
for sample in "${SAMPLE_LIST[@]}"; do
    echo "    ${sample}"
done

# --- 幂等性检查 ---

if [ ${FORCE} -eq 0 ] && [ -f "${PATHABUNDANCE_TSV}" ] && [ -f "${GENEFAMILIES_TSV}" ]; then
    echo "[INFO] 合并结果已存在，跳过。如需重新合并请先删除 ${MERGED_DIR}"
    exit 0
fi

mkdir -p "${MERGED_DIR}"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"

# --- Step 1: 收集非分层 relab 表到临时目录 ---

echo "[INFO] 准备 HUMAnN3 非分层输入文件..."
for sample in "${SAMPLE_LIST[@]}"; do
    path_unstratified="${PROFILE_DIR}/${sample}/unstratified/${sample}_pathabundance_relab_unstratified.tsv"
    gene_unstratified="${PROFILE_DIR}/${sample}/unstratified/${sample}_genefamilies_relab_unstratified.tsv"

    if [ ! -f "${path_unstratified}" ] || [ ! -f "${gene_unstratified}" ]; then
        echo "[ERROR] 缺少 HUMAnN3 非分层输入文件: ${sample}"
        echo "        期望路径: ${path_unstratified}"
        echo "        期望路径: ${gene_unstratified}"
        rm -rf "${STAGE_DIR}"
        exit 1
    fi

    cp "${path_unstratified}" "${STAGE_DIR}/${sample}_pathabundance_relab.tsv"
    cp "${gene_unstratified}" "${STAGE_DIR}/${sample}_genefamilies_relab.tsv"
done

# --- Step 2: 合并通路丰度表 ---

echo "[INFO] 合并多样本 pathabundance relab 表..."
conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
    humann_join_tables \
        --input "${STAGE_DIR}" \
        --file_name pathabundance_relab.tsv \
        --output "${PATHABUNDANCE_TSV}"

if [ ! -f "${PATHABUNDANCE_TSV}" ] || [ ! -s "${PATHABUNDANCE_TSV}" ]; then
    echo "[ERROR] 合并失败，未生成 ${PATHABUNDANCE_TSV}"
    rm -rf "${STAGE_DIR}"
    exit 1
fi

sed -i 's/_Abundance//g' "${PATHABUNDANCE_TSV}"

# --- Step 3: 合并基因家族丰度表 ---


echo "[INFO] 合并多样本 genefamilies relab 表..."
conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
    humann_join_tables \
        --input "${STAGE_DIR}" \
        --file_name genefamilies_relab.tsv \
        --output "${GENEFAMILIES_TSV}"

if [ ! -f "${GENEFAMILIES_TSV}" ] || [ ! -s "${GENEFAMILIES_TSV}" ]; then
    echo "[ERROR] 合并失败，未生成 ${GENEFAMILIES_TSV}"
    rm -rf "${STAGE_DIR}"
    exit 1
fi

sed -i 's/_Abundance-RPKs//g' "${GENEFAMILIES_TSV}"


# --- Step 4: 清理临时目录 ---

rm -rf "${STAGE_DIR}"

# --- 统计摘要 ---

echo ""
echo "[humann3_merge] 合并完成，耗时 ${SECONDS}s"
echo "[humann3_merge] 输出目录: ${MERGED_DIR}"
echo "    pathabundance_relab.tsv — $(wc -l < "${PATHABUNDANCE_TSV}") 行"
echo "    genefamilies_relab.tsv  — $(wc -l < "${GENEFAMILIES_TSV}") 行"
