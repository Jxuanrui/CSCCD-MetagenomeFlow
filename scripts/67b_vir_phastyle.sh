#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 67b_vir_phastyle.sh
# 功  能: 噬菌体生活方式预测交叉验证（裂解/溶原，第三票）
#         工具版本：ProkBERT 0.0.48 + PhaStyle fine-tune（conda env: prokbert）
# 依  赖: 56_vir_votu_gen.sh 的 vOTU 序列
# 输  入: ${WORKDIR}/result/virus/votu/contigs/virus.fasta
# 输  出: ${WORKDIR}/result/virus/phastyle/
#           phastyle_results.tsv  — 生活方式预测（逐 vOTU：label + temperate/virulent 概率）
#           phastyle_done.txt     — sentinel（virulent/temperate 计数）
#
# ── 定位说明 ──────────────────────────────────────────────────────────────────
#
#   生活方式预测的第三票验证层：67 BACPHLIP（随机森林，HMM 特征）与 72 PhaGCN3
#   （图卷积）之外，ProkBERT-PhaStyle 用基因组语言模型直接从序列判读。对同一
#   vOTU 三票并排，2/3 及以上一致的生活方式可视为稳健；分歧样本（如
#   BACPHLIP=virulent 而 PhaStyle=temperate 且概率接近 0.5）值得人工复核。
#   本步骤默认不入 Snakemake rule all（验证层，同 15e MetaX / 16b metaSPAdes），
#   按需显式请求 sentinel 目标触发。
#
# ── 模型与网络 ────────────────────────────────────────────────────────────────
#
#   模型: neuralbioinfo/PhaStyle-mini（HF，约 25M 参数，~80MB 权重）。基于
#   ProkBERT-mini 在 BACPHLIP 数据集（去除 E. coli）上微调；序列按 512bp
#   连续切段（不足 256bp 的尾段丢弃），段级 logits 经 weighted voting 聚合为
#   序列级预测：class_0=temperate / class_1=virulent。
#   参考: Juhász et al. 2025 Bioinformatics (ProkBERT-PhaStyle)
#
#   首次运行需联网从 HuggingFace 下载权重到 HF_HOME（默认 ~/.cache/huggingface，
#   约 80MB，之后离线复用）。本机 huggingface.co 不可达时自动改用 hf-mirror.com
#   镜像；也可用环境变量 HF_ENDPOINT / HF_HOME 显式指定。
#
# ── 环境安装（一次性）────────────────────────────────────────────────────────
#
#   conda create --prefix ${REPO}/envs/prokbert python=3.10 -y
#   conda run --prefix ${REPO}/envs/prokbert pip install prokbert
#   conda run --prefix ${REPO}/envs/prokbert pip install \
#       torch torchvision --index-url https://download.pytorch.org/whl/cpu
#   conda run --prefix ${REPO}/envs/prokbert pip install transformers==4.53.2
#
#   （prokbert 0.0.48 与 transformers>=5 不兼容；CPU 版 torch 免去 ~4.5GB CUDA
#    轮子，env 从 6.3G 降至 1.8G）
#
# ── 注意事项 ──────────────────────────────────────────────────────────────────
#
#   1. CPU 推理按总碱基线性 scaling：Project01（163MB vOTU，~31 万段）8 线程
#      预计数小时~十余小时；GPU 环境把 HF_HUB_OFFLINE=0 跑同脚本自动加速
#   2. 模型线程数封顶 8（torch.set_num_threads），即使 -t 传入更大值
#   3. 输入为空/无有效段时 WARN + 写空表 sentinel 优雅退出（验证层不阻塞队列）
#
# 用  法: bash 67b_vir_phastyle.sh -t CPUS -w WORKDIR -r REPO [--model ID] [--batch-size N] [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() { cat << EOF
用法: bash 67b_vir_phastyle.sh -t CPUS -w WORKDIR -r REPO [选项]

必需参数:
  -t  线程数（模型推理封顶 8）
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  --model        PhaStyle 模型 ID（默认 neuralbioinfo/PhaStyle-mini）
  --batch-size   推理批大小（默认 32）
  --force        强制重跑（忽略已存在的 sentinel）
  -h             显示帮助

示例:
  bash 67b_vir_phastyle.sh -t 8 \\
       -w ~/Course/CSCCD-MetagenomeFlow/Project/Project01 -r ~/Course/CSCCD-MetagenomeFlow

  # 显式触发 Snakemake 规则（默认不在 rule all 中）:
  snakemake -s pipeline/Snakefile --configfile pipeline/config/config.yaml -R phastyle
EOF
}

PHASTYLE_MODEL="neuralbioinfo/PhaStyle-mini"
BATCH_SIZE="32"

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="t:CPUS w:WORKDIR r:REPO"
export MGX_OPTS_FLAG="force"
export MGX_OPTS_LONG="model:PHASTYLE_MODEL batch-size:BATCH_SIZE"
mgx_parse "$@"
mgx_require CPUS WORKDIR REPO

mgx_begin
VOTU_FA="${WORKDIR}/result/virus/votu/contigs/virus.fasta"
OUTDIR="${WORKDIR}/result/virus/phastyle"
RESULTS="${OUTDIR}/phastyle_results.tsv"
SENTINEL="${OUTDIR}/phastyle_done.txt"

if [ ! -f "${VOTU_FA}" ] || [ ! -s "${VOTU_FA}" ]; then echo "[ERROR] vOTU 序列不存在"; exit 1; fi
if [ "${FORCE}" -eq 0 ] && [ -f "${SENTINEL}" ]; then echo "[phastyle] 结果已存在，跳过"; exit 0; fi

mkdir -p "${OUTDIR}"
rm -f "${RESULTS}" "${SENTINEL}"

# --- HuggingFace 网络环境 ---
# 首次运行下载 ~80MB 权重到 HF_HOME（默认 ~/.cache/huggingface）；huggingface.co
# 不可达时回退 hf-mirror.com 镜像（HF_ENDPOINT 可外部覆盖）。HF_HUB_DISABLE_XET
# 避免 hf-xet 传输在镜像端不可用。
export HF_HOME="${HF_HOME:-${HOME}/.cache/huggingface}"
if [ -z "${HF_ENDPOINT:-}" ]; then
    if timeout 8 curl -sf -o /dev/null https://huggingface.co; then
        export HF_ENDPOINT="https://huggingface.co"
    else
        echo "[phastyle] huggingface.co 不可达，使用镜像 hf-mirror.com"
        export HF_ENDPOINT="https://hf-mirror.com"
    fi
fi
export HF_HUB_DISABLE_XET=1

# 模型线程封顶 8（任务约束：模型运行 CPU ≤8 线程）
TORCH_THREADS=$(( CPUS < 8 ? CPUS : 8 ))

echo "[phastyle] 噬菌体生活方式预测（ProkBERT-PhaStyle，第三票验证层）..."
echo "[phastyle] 模型: ${PHASTYLE_MODEL}，torch 线程: ${TORCH_THREADS}，HF_ENDPOINT: ${HF_ENDPOINT}"

# --- 推理驱动 ---
# prokbert 0.0.48 wheel 不含上游 bin/PhaStyle.py（GitHub-only），此处内嵌等价实现：
# 512bp contiguous 分段 → LCA tokenizer → ProkBertForSequenceClassification 推理 →
# 段级 weighted voting 聚合（prokbert.training_utils）→ class_1=virulent / class_0=temperate
cat > "${OUTDIR}/_phastyle_driver.py" <<'PY'
import argparse
import os

import numpy as np
import torch
from datasets import Dataset
from transformers import DataCollatorWithPadding, Trainer, TrainingArguments

from prokbert.models import ProkBertForSequenceClassification
from prokbert.sequtils import load_contigs, segment_sequences
from prokbert.tokenizer import LCATokenizer
from prokbert.training_utils import inference_binary_sequence_predictions

MAX_LEN = 512


def main():
    ap = argparse.ArgumentParser(description="ProkBERT PhaStyle inference")
    ap.add_argument("--fastain", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ftmodel", default="neuralbioinfo/PhaStyle-mini")
    ap.add_argument("--batch-size", type=int, default=32)
    ap.add_argument("--threads", type=int, default=8)
    args = ap.parse_args()

    torch.set_num_threads(min(args.threads, 8))

    try:
        model = ProkBertForSequenceClassification.from_pretrained(
            args.ftmodel, trust_remote_code=True
        )
        tokenizer = LCATokenizer.from_pretrained(args.ftmodel, trust_remote_code=True)
    except Exception as e:
        print(f"[phastyle][driver] network load failed ({e}); retrying local cache")
        model = ProkBertForSequenceClassification.from_pretrained(
            args.ftmodel, trust_remote_code=True, local_files_only=True
        )
        tokenizer = LCATokenizer.from_pretrained(
            args.ftmodel, trust_remote_code=True, local_files_only=True
        )

    sequences = load_contigs(
        [args.fastain],
        IsAddHeader=True,
        adding_reverse_complement=False,
        AsDataFrame=True,
        to_uppercase=True,
        is_add_sequence_id=True,
    )
    if len(sequences) == 0:
        print("[phastyle][driver] no sequences parsed; writing header-only output")
        with open(args.out, "w") as fh:
            fh.write("sequence_id\tfasta_id\tpredicted_label\tscore_temperate\tscore_virulent\n")
        return

    try:
        seg_df = segment_sequences(
            sequences,
            {"max_length": MAX_LEN, "min_length": MAX_LEN // 2, "type": "contiguous"},
            AsDataFrame=True,
        )
    except KeyError:
        # upstream sequtils raises KeyError when no sequence reaches min_length
        seg_df = None
    if seg_df is None or len(seg_df) == 0:
        print("[phastyle][driver] no segments (all sequences < min_length); writing header-only output")
        with open(args.out, "w") as fh:
            fh.write("sequence_id\tfasta_id\tpredicted_label\tscore_temperate\tscore_virulent\n")
        return
    hf_dataset = Dataset.from_pandas(seg_df)

    def _tok(batch):
        t = tokenizer(batch["segment"], padding="longest", truncation=True, max_length=MAX_LEN)
        for m in t["attention_mask"]:
            m[0] = 0
            m[-1] = 0
        return {"input_ids": t["input_ids"], "attention_mask": t["attention_mask"]}

    tokenized = hf_dataset.map(
        _tok, batched=True, remove_columns=hf_dataset.column_names
    )

    trainer = Trainer(
        model=model,
        args=TrainingArguments(
            output_dir=os.path.join(os.path.dirname(args.out), "_trainer_tmp"),
            do_train=False,
            do_eval=False,
            per_device_eval_batch_size=args.batch_size,
            fp16=torch.cuda.is_available(),
            remove_unused_columns=False,
        ),
        processing_class=tokenizer,
        data_collator=DataCollatorWithPadding(tokenizer=tokenizer),
    )
    preds = trainer.predict(tokenized)
    table = inference_binary_sequence_predictions(preds, hf_dataset)
    table["predicted_label"] = np.where(
        table["predicted_label"] == "class_1", "virulent", "temperate"
    )
    table = table.merge(sequences[["sequence_id", "fasta_id"]], on="sequence_id", how="left")
    table = table[["sequence_id", "fasta_id", "predicted_label", "p_class_0", "p_class_1"]]
    table.columns = [
        "sequence_id", "fasta_id", "predicted_label", "score_temperate", "score_virulent",
    ]
    table.to_csv(args.out, sep="\t", index=False)
    print(f"[phastyle][driver] {len(table)} sequences written to {args.out}")


if __name__ == "__main__":
    main()
PY

EXIT_CODE=0
mgx_try mgx_conda prokbert \
    python "${OUTDIR}/_phastyle_driver.py" \
        --fastain "${VOTU_FA}" \
        --out "${RESULTS}" \
        --ftmodel "${PHASTYLE_MODEL}" \
        --batch-size "${BATCH_SIZE}" \
        --threads "${TORCH_THREADS}" \
        || EXIT_CODE=$?
rm -f "${OUTDIR}/_phastyle_driver.py"
rm -rf "${OUTDIR}/_trainer_tmp"

if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "[ERROR] phastyle 运行失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

# --- 空结果优雅降级（验证层不阻塞队列）---
N_TOTAL=$(( $(wc -l < "${RESULTS}") - 1 ))
if [ "${N_TOTAL}" -le 0 ]; then
    echo "[phastyle] [WARN] 无预测结果（输入序列均短于分段阈值），写空表 sentinel 优雅退出"
    echo "empty_input" > "${SENTINEL}"
    exit 0
fi
N_VIR=$(awk -F'\t' '$3=="virulent"' "${RESULTS}" | wc -l)
N_TEM=$(awk -F'\t' '$3=="temperate"' "${RESULTS}" | wc -l)
echo "total=${N_TOTAL} virulent=${N_VIR} temperate=${N_TEM}" > "${SENTINEL}"

echo "[phastyle] 完成：virulent=${N_VIR} / temperate=${N_TEM}（共 ${N_TOTAL}）"
echo "[提示] 本步骤为生活方式预测第三票（67 BACPHLIP / 72 PhaGCN3 / 67b PhaStyle）；"
echo "       与 ${WORKDIR}/result/virus/bacphlip/bacphlip_results.tsv 并排比对，2/3 一致为稳健"
mgx_end "phastyle"
