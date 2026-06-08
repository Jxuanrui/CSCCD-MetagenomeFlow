#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 72_fun_metaphlan4_euk.sh
# 功  能: MetaPhlAn4 真核（真菌）物种组成分析，保留真核生物分类
#         工具版本：MetaPhlAn4 4.2.4+（conda env: humann4）
# 依  赖: 02_qc_kneaddata.sh 的输出（clean reads）
# 输  入: ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz
#         ${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz
# 输  出: ${WORKDIR}/result/fungi/metaphlan4/${SAMPLE}/${SAMPLE}_profile.txt
#         ${WORKDIR}/result/fungi/metaphlan4/${SAMPLE}/${SAMPLE}.sam.bz2
# 用  法: bash 72_fun_metaphlan4_euk.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO
#
# 说  明: MetaPhlAn4 默认过滤真核生物分类。本脚本通过保留所有 bowtie2
#         比对结果，确保真核生物（真菌）marker 可被正确识别。
#         参考: https://github.com/biobakery/MetaPhlAn4
# ==============================================================================

if [ $# -lt 8 ]; then
    echo "用法: bash 72_fun_metaphlan4_euk.sh -s SAMPLE -t CPUS -w WORKDIR -r REPO"
    echo "  -s  样本名"
    echo "  -t  线程数"
    echo "  -w  工作目录"
    echo "  -r  MaxMetagenome 根目录"
    exit 1
fi

while getopts s:t:w:r: option; do
    case "${option}" in
        s) SAMPLE=${OPTARG} ;;
        t) CPUS=${OPTARG} ;;
        w) WORKDIR=${OPTARG} ;;
        r) REPO=${OPTARG} ;;
    esac
done

if [ -z "${SAMPLE}" ] || [ -z "${CPUS}" ] || [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数"; exit 1
fi

SECONDS=0

INPUT_R1="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_1.kneaddata.fastq.gz"
INPUT_R2="${WORKDIR}/result/kneaddata/${SAMPLE}/${SAMPLE}_2.kneaddata.fastq.gz"

TEMP_DIR="${WORKDIR}/temp/fungi/metaphlan4/${SAMPLE}"
RESULT_DIR="${WORKDIR}/result/fungi/metaphlan4/${SAMPLE}"
PROFILE_OUT="${RESULT_DIR}/${SAMPLE}_profile.txt"
DB_DIR="${REPO}/db/metaphlan4"
DB_INDEX="mpa_vOct22_CHOCOPhlAnSGB_202212"

if [ ! -f "${INPUT_R1}" ]; then echo "[ERROR] R1 不存在: ${INPUT_R1}"; exit 1; fi
if [ ! -f "${INPUT_R2}" ]; then echo "[ERROR] R2 不存在: ${INPUT_R2}"; exit 1; fi
if [ ! -d "${DB_DIR}" ]; then echo "[ERROR] 数据库目录不存在: ${DB_DIR}"; exit 1; fi
if ! ls "${DB_DIR}/${DB_INDEX}"*.bt2l &>/dev/null; then
    echo "[ERROR] 数据库索引未找到: ${DB_DIR}/${DB_INDEX}*.bt2l"; exit 1
fi

if [ -f "${PROFILE_OUT}" ]; then
    echo "[INFO] 结果已存在，跳过: ${SAMPLE}"; exit 0
fi

mkdir -p "${TEMP_DIR}" "${RESULT_DIR}"

MERGED_FASTQ="${TEMP_DIR}/${SAMPLE}_merged.fastq.gz"
echo "[fun_metaphlan4] 合并双端 reads..."
zcat "${INPUT_R1}" "${INPUT_R2}" | gzip -c > "${MERGED_FASTQ}"

echo "[fun_metaphlan4] 运行 MetaPhlAn4（保留真核生物）| 线程: ${CPUS}"

conda run --prefix "${REPO}/envs/humann4" --no-capture-output \
    metaphlan \
        "${MERGED_FASTQ}" \
        --input_type fastq \
        --db_dir "${DB_DIR}" \
        -x "${DB_INDEX}" \
        --nproc "${CPUS}" \
        --samout "${RESULT_DIR}/${SAMPLE}.sam" \
        -o "${PROFILE_OUT}" \
        --offline

EXIT_CODE=$?
rm -f "${MERGED_FASTQ}"
if [ ${EXIT_CODE} -ne 0 ]; then echo "[ERROR] metaphlan4 失败（exit: ${EXIT_CODE}）"; exit ${EXIT_CODE}; fi
if [ ! -f "${PROFILE_OUT}" ]; then echo "[ERROR] Profile 未生成"; exit 1; fi

if [ -f "${RESULT_DIR}/${SAMPLE}.sam" ]; then
    bzip2 "${RESULT_DIR}/${SAMPLE}.sam"
fi

FUNGI_COUNT=$(grep -v "^#" "${PROFILE_OUT}" | grep -c "k__Fungi" 2>/dev/null || echo "0")
echo "[fun_metaphlan4] ${SAMPLE} 完成，耗时 ${SECONDS}s"
echo "[fun_metaphlan4] 结果: ${PROFILE_OUT} | 真菌分类群数: ${FUNGI_COUNT}"
echo "[提示] Profile 文件可作为 73_fun_humann4_fungi.sh 的 taxonomic profile 输入"
