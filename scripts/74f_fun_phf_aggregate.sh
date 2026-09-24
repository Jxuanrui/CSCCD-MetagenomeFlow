#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 74f_fun_phf_aggregate.sh
# 功  能: 聚合所有样本的 PHF 真菌丰度表（.rc → merged matrix + taxonomy join）
# 依  赖: 74e_fun_phf_profiler.sh 的输出（*.rc 文件）
# 输  入: ${WORKDIR}/result/fungi/phf_profiler/*/*.rc
#         ${REPO}/db/gut_fungi_db/db.fungi.taxonomy.tsv
# 输  出: ${WORKDIR}/result/fungi/phf_profiler/merged_abundance.tsv
#         ${WORKDIR}/result/fungi/phf_profiler/merged_abundance_with_taxonomy.tsv
# 用  法: bash 74f_fun_phf_aggregate.sh -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 74f_fun_phf_aggregate.sh -w WORKDIR -r REPO

参数:
  -w  工作目录（含 result/fungi/phf_profiler/）
  -r  CSCCD-MetagenomeFlow 项目根目录

输出:
  \${WORKDIR}/result/fungi/phf_profiler/merged_abundance.tsv
  \${WORKDIR}/result/fungi/phf_profiler/merged_abundance_with_taxonomy.tsv

可选参数:
  --force  强制重新运行（忽略已存在的结果）

EOF
}

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO
REPO="$(cd "${REPO}" && pwd)"

mgx_begin
PROFILER_DIR="${WORKDIR}/result/fungi/phf_profiler"
TAXONOMY="${REPO}/db/gut_fungi_db/db.fungi.taxonomy.tsv"
MERGED="${PROFILER_DIR}/merged_abundance.tsv"
MERGED_TAX="${PROFILER_DIR}/merged_abundance_with_taxonomy.tsv"

if [ ${FORCE} -eq 0 ] && [ -f "${MERGED}" ] && [ -s "${MERGED}" ]; then
    echo "[INFO] 结果已存在，跳过: ${MERGED}"; exit 0
fi

mapfile -t RC_FILES < <(find "${PROFILER_DIR}" -maxdepth 2 -name '*.rc' -size +0c | sort)
N_SAMPLES=${#RC_FILES[@]}
if [ "${N_SAMPLES}" -eq 0 ]; then
    echo "[ERROR] 未找到 .rc 文件: ${PROFILER_DIR}/*/*.rc"; exit 1
fi
echo "[phf_aggregate] 聚合 ${N_SAMPLES} 个样本的 .rc 文件..."

# Python-based merge: outer join on cluster column, fill missing with 0
python3 - "${MERGED}" "${MERGED_TAX}" "${TAXONOMY}" "${RC_FILES[@]}" << 'PY'
import sys, os, csv

out_merged, out_tax, taxonomy_file = sys.argv[1], sys.argv[2], sys.argv[3]
rc_files = sys.argv[4:]

# Load taxonomy
tax = {}
with open(taxonomy_file) as fh:
    reader = csv.DictReader(fh, delimiter='\t')
    for row in reader:
        clu = row.get('cluster', '').strip()
        if clu:
            tax[clu] = row

# Collect all clusters and per-sample data
sample_data = {}
all_clusters = set()
for f in rc_files:
    sample = os.path.basename(f).replace('.rc', '')
    with open(f) as fh:
        lines = [l.rstrip('\n') for l in fh if l.strip()]
    if not lines:
        continue
    header = lines[0].split('\t')
    # .rc format: cluster<TAB>value
    d = {}
    for line in lines[1:]:
        parts = line.split('\t')
        if len(parts) >= 2:
            d[parts[0]] = parts[1]
            all_clusters.add(parts[0])
    sample_data[sample] = d

samples = sorted(sample_data.keys())
clusters = sorted(all_clusters)

# Write merged abundance
with open(out_merged + '.tmp', 'w') as fh:
    fh.write('cluster\t' + '\t'.join(samples) + '\n')
    for clu in clusters:
        vals = [sample_data[s].get(clu, '0') for s in samples]
        fh.write(clu + '\t' + '\t'.join(vals) + '\n')
os.replace(out_merged + '.tmp', out_merged)
print(f"[INFO] Merged: {len(clusters)} clusters × {len(samples)} samples → {out_merged}")

# Write merged + taxonomy
tax_fields = ['Phylum','subPhylum','Class','Order','family','genus','species']
with open(out_tax + '.tmp', 'w') as fh:
    fh.write('cluster\t' + '\t'.join(tax_fields) + '\t' + '\t'.join(samples) + '\n')
    for clu in clusters:
        t = tax.get(clu, {})
        tax_vals = [t.get(f, '') for f in tax_fields]
        vals = [sample_data[s].get(clu, '0') for s in samples]
        fh.write(clu + '\t' + '\t'.join(tax_vals) + '\t' + '\t'.join(vals) + '\n')
os.replace(out_tax + '.tmp', out_tax)
print(f"[INFO] With taxonomy: {out_tax}")
PY

echo "[phf_aggregate] 完成"
mgx_end "phf_aggregate"
