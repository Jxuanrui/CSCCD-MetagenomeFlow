#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 72_vir_phagcn3.sh
# 功  能: 噬菌体分类预测（PhaGCN3）
#         工具版本：PhaGCN3 3.1（conda env: phagcn3）
# 依  赖: 56_vir_votu_gen.sh 的 vOTU 序列
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/phagcn3/
#           phagcn3_prediction.tsv  — PhaGCN3 分类结果
#
# 参  考: Shang et al. 2023 (PhaGCN2/PhaGCN3)
# 用  法: bash 72_vir_phagcn3.sh -t CPUS -w WORKDIR -r REPO
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 72_vir_phagcn3.sh -t CPUS -w WORKDIR -r REPO
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
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
OUTDIR="${WORKDIR}/result/virus/phagcn3"
SENTINEL="${OUTDIR}/phagcn3_prediction.tsv"
PHAGCN3_DB="${REPO}/db/phagcn3_db"
RUNROOT="${OUTDIR}/run"
RUNDIR="${RUNROOT}/phagcn3_db"
PRED_DIR="${RUNDIR}/pred"
FINAL_CSV="${PRED_DIR}/final_prediction.csv"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
if [ ! -d "${PHAGCN3_DB}" ]; then echo "[ERROR] PhaGCN3 数据库不存在: ${PHAGCN3_DB}"; exit 1; fi
if [ ${FORCE} -eq 0 ] && [ -f "${SENTINEL}" ] && [ -s "${SENTINEL}" ]; then echo "[phagcn3] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"
rm -rf "${RUNROOT}"
mkdir -p "${RUNROOT}"
cp -r "${PHAGCN3_DB}" "${RUNROOT}/"
cp "${VOTU_FA}" "${RUNDIR}/virus.fasta"

echo "[phagcn3] 噬菌体分类预测 ..."

# 上游源码将 diamond/mcl 线程数写死为 128；在运行副本中改为用户指定线程数。
sed -i "s/--threads 128/--threads ${CPUS}/g; s/make_diamond_db(128)/make_diamond_db(${CPUS})/g; s/run_diamond(proteins_aa_fp, db_fp, 128, diamond_out_fp)/run_diamond(proteins_aa_fp, db_fp, ${CPUS}, diamond_out_fp)/g; s/-te 128/-te ${CPUS}/g; s/python3\\.13t/python/g" \
    "${RUNDIR}/run_Speed_up.py" \
    "${RUNDIR}/run_KnowledgeGraph.py"

# 用稀疏矩阵替换上游 network_compute.py 的超几何密集计算，避免在示例数据上耗时过长。
cat > "${RUNDIR}/network_compute.py" <<'PY'
import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import sparse

parser = argparse.ArgumentParser(description="Build a sparse contig-PC network")
parser.add_argument("--outpath", type=str, default="result")
args = parser.parse_args()

outdir = Path(args.outpath) / "out"
contigs = pd.read_csv(outdir / "merged_df.csv")
profiles = pd.read_csv(outdir / "Cyber_profiles.csv", usecols=["contig_id", "pc_id"])

contigs["contig_id"] = contigs["contig_id"].astype(str).str.replace(" ", "~", regex=False)
profiles["contig_id"] = profiles["contig_id"].astype(str).str.replace(" ", "~", regex=False)

row_map = contigs.set_index("contig_id")["pos"].to_dict()
rows = profiles["contig_id"].map(row_map)
valid = rows.notna() & profiles["pc_id"].notna()
rows = rows[valid].astype(np.int32).to_numpy()
pc_codes, _ = pd.factorize(profiles.loc[valid, "pc_id"], sort=False)
cols = pc_codes.astype(np.int32)
data = np.ones(len(rows), dtype=np.uint8)

matrix = sparse.csr_matrix((data, (rows, cols)), shape=(len(contigs), len(np.unique(cols))), dtype=np.uint8)
shared = (matrix @ matrix.T).astype(np.float32)
shared.setdiag(0)
shared.eliminate_zeros()

edge_count = shared.nnz // 2
if edge_count == 0:
    raise ValueError("No edge in the similarity network!")

S = shared.toarray()
S[S > 0] = 1.0
print(f"Contig similarity network: {S.shape[0]} contigs, {edge_count} edges")

with open(outdir / "output_network.npz", "wb") as handle:
    np.savez(handle, S=S.astype(np.float32, copy=False))
PY

export OMP_NUM_THREADS="${CPUS}"
export OPENBLAS_NUM_THREADS="${CPUS}"
export MKL_NUM_THREADS="${CPUS}"
export NUMEXPR_NUM_THREADS="${CPUS}"
export VECLIB_MAXIMUM_THREADS="${CPUS}"
export TORCH_NUM_THREADS="${CPUS}"

# 运行块保留原始 set +e 形式：conda run 位于 ( cd ... ) 子 shell 内，mgx_try 无法等价包装
set +e
(
    cd "${RUNDIR}" || exit 1
    conda run --prefix "${REPO}/envs/phagcn3" --no-capture-output \
        python run_Speed_up.py \
            --contigs virus.fasta \
            --outpath pred
)

EXIT_CODE=$?
set -e
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] phagcn3 运行失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

if [ ! -f "${FINAL_CSV}" ] || [ ! -s "${FINAL_CSV}" ]; then
    echo "[ERROR] 未找到输出文件: ${FINAL_CSV}"
    exit 1
fi

python - << PY
import csv
from pathlib import Path
src = Path(${FINAL_CSV@Q})
dst = Path(${SENTINEL@Q})
with src.open(newline="") as fin, dst.open("w", newline="") as fout:
    reader = csv.reader(fin)
    writer = csv.writer(fout, delimiter="\t", lineterminator="\n")
    writer.writerows(reader)
PY

if [ ! -f "${SENTINEL}" ] || [ ! -s "${SENTINEL}" ]; then
    echo "[ERROR] 运行完成，但未找到 ${SENTINEL}"
    exit 1
fi

rm -rf "${RUNROOT}"

mgx_end "phagcn3"
