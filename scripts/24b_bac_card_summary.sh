#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 24b_bac_card_summary.sh
# 功  能: 对 24_bac_card.sh（RGI/CARD）原始输出做置信度分层+突变证据+药物类别汇总
#         纯统计聚合，不调用任何新外部工具
# 依  赖: 24_bac_card.sh 的输出（rgi_results.txt）
# 输  入: ${WORKDIR}/result/annotation/card/rgi_results.txt
# 输  出: ${WORKDIR}/result/annotation/card/summary/
#           card_confidence_tier_summary.tsv     — 按 Cut_Off（Perfect/Strict/Loose）分层基因数统计
#           card_drug_class_summary.tsv          — 按 Drug Class（多值字段拆分）统计命中数
#           card_resistance_mechanism_summary.tsv — 按 Resistance Mechanism（多值字段拆分）统计命中数
#           card_snp_evidence_summary.tsv        — 有突变证据支持的耐药决定因子清单
#           card_summary_report.txt              — 人类可读摘要
#
# ── 范围说明 ──────────────────────────────────────────────────────────────────
#   CARD/RGI 是对合并去冗余蛋白质编目跑一次（非按样本），因此本汇总不涉及
#   跨样本丰度关联（如需按样本 ARG 丰度矩阵，参考 98b_bac_integration_tables.sh
#   的 arg_abundance.tsv）。也不计算加权综合"致病性分数"——现有 Cut_Off 三档
#   置信度分层 + SNP突变证据本身已是有科学依据的信息呈现，不引入额外主观权重。
#
# 用  法: bash 24b_bac_card_summary.sh -w WORKDIR -r REPO [--force]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 24b_bac_card_summary.sh -w WORKDIR -r REPO [选项]

必需参数:
  -w  工作目录
  -r  CSCCD-MetagenomeFlow 项目根目录

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

RGI_TXT="${WORKDIR}/result/annotation/card/rgi_results.txt"
OUT_DIR="${WORKDIR}/result/annotation/card/summary"
REPORT_TXT="${OUT_DIR}/card_summary_report.txt"

if [ ! -f "${RGI_TXT}" ] || [ ! -s "${RGI_TXT}" ]; then
    echo "[ERROR] CARD/RGI 结果文件不存在或为空: ${RGI_TXT}"
    echo "        请先运行 24_bac_card.sh"
    exit 1
fi

if [ ${FORCE} -eq 0 ] && [ -f "${REPORT_TXT}" ] && [ -s "${REPORT_TXT}" ]; then
    echo "[INFO] CARD 汇总报表已存在，跳过: ${REPORT_TXT}"
    exit 0
fi

mkdir -p "${OUT_DIR}"

echo "[card_summary] 开始汇总 CARD/RGI 结果: ${RGI_TXT}"

# ==============================================================================
# Python 汇总主逻辑（标准库，无需额外依赖）
# ==============================================================================

python3 - "${RGI_TXT}" "${OUT_DIR}" <<'PYEOF'
import sys
import csv
from collections import defaultdict

RGI_TXT = sys.argv[1]
OUT_DIR = sys.argv[2]

TIERS = ["Perfect", "Strict", "Loose"]


def split_multivalue(value):
    """CARD multi-value fields are '; '-separated; single values pass through unchanged."""
    value = value.strip()
    if not value or value == "n/a":
        return []
    return [v.strip() for v in value.split(";") if v.strip()]


rows = []
with open(RGI_TXT, "r", encoding="utf-8") as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        rows.append(row)

total_rows = len(rows)

# --- 1. 置信度分层统计 ---
tier_counts = defaultdict(int)
tier_unique_aro = defaultdict(set)
for row in rows:
    tier = row.get("Cut_Off", "").strip() or "Unknown"
    tier_counts[tier] += 1
    aro = row.get("Best_Hit_ARO", "").strip()
    if aro:
        tier_unique_aro[tier].add(aro)

with open(f"{OUT_DIR}/card_confidence_tier_summary.tsv", "w", newline="", encoding="utf-8") as out:
    writer = csv.writer(out, delimiter="\t")
    writer.writerow(["Cut_Off", "N_hits", "N_unique_Best_Hit_ARO", "Pct_of_total"])
    for tier in TIERS + sorted(set(tier_counts) - set(TIERS)):
        if tier not in tier_counts:
            continue
        pct = (tier_counts[tier] / total_rows * 100) if total_rows else 0.0
        writer.writerow([tier, tier_counts[tier], len(tier_unique_aro[tier]), f"{pct:.2f}"])

# --- 2. Drug Class 分布统计（按置信度分层细分） ---
drug_class_counts = defaultdict(lambda: defaultdict(int))
for row in rows:
    tier = row.get("Cut_Off", "").strip() or "Unknown"
    for cls in split_multivalue(row.get("Drug Class", "")):
        drug_class_counts[cls][tier] += 1
        drug_class_counts[cls]["Total"] += 1

with open(f"{OUT_DIR}/card_drug_class_summary.tsv", "w", newline="", encoding="utf-8") as out:
    writer = csv.writer(out, delimiter="\t")
    writer.writerow(["Drug_Class", "Total_hits"] + TIERS)
    for cls, counts in sorted(drug_class_counts.items(), key=lambda kv: -kv[1]["Total"]):
        writer.writerow([cls, counts["Total"]] + [counts.get(t, 0) for t in TIERS])

# --- 3. Resistance Mechanism 分布统计 ---
mechanism_counts = defaultdict(lambda: defaultdict(int))
for row in rows:
    tier = row.get("Cut_Off", "").strip() or "Unknown"
    for mech in split_multivalue(row.get("Resistance Mechanism", "")):
        mechanism_counts[mech][tier] += 1
        mechanism_counts[mech]["Total"] += 1

with open(f"{OUT_DIR}/card_resistance_mechanism_summary.tsv", "w", newline="", encoding="utf-8") as out:
    writer = csv.writer(out, delimiter="\t")
    writer.writerow(["Resistance_Mechanism", "Total_hits"] + TIERS)
    for mech, counts in sorted(mechanism_counts.items(), key=lambda kv: -kv[1]["Total"]):
        writer.writerow([mech, counts["Total"]] + [counts.get(t, 0) for t in TIERS])

# --- 4. SNP 突变证据清单（比单纯序列相似度更强的耐药性证据） ---
snp_rows = []
for row in rows:
    snp_best = row.get("SNPs_in_Best_Hit_ARO", "").strip()
    snp_other = row.get("Other_SNPs", "").strip()
    has_snp = (snp_best and snp_best != "n/a") or (snp_other and snp_other != "n/a")
    if has_snp:
        snp_rows.append(row)

with open(f"{OUT_DIR}/card_snp_evidence_summary.tsv", "w", newline="", encoding="utf-8") as out:
    writer = csv.writer(out, delimiter="\t")
    writer.writerow(["ORF_ID", "Best_Hit_ARO", "Cut_Off", "SNPs_in_Best_Hit_ARO", "Other_SNPs", "Drug Class"])
    for row in snp_rows:
        writer.writerow([
            row.get("ORF_ID", ""),
            row.get("Best_Hit_ARO", ""),
            row.get("Cut_Off", ""),
            row.get("SNPs_in_Best_Hit_ARO", ""),
            row.get("Other_SNPs", ""),
            row.get("Drug Class", ""),
        ])

# --- 5. 人类可读摘要 ---
top_drug_classes = sorted(drug_class_counts.items(), key=lambda kv: -kv[1]["Total"])[:10]

with open(f"{OUT_DIR}/card_summary_report.txt", "w", encoding="utf-8") as out:
    out.write("CARD/RGI 耐药基因汇总报表\n")
    out.write("=" * 60 + "\n\n")
    out.write(f"总命中数（含 Loose）: {total_rows}\n\n")
    out.write("置信度分层:\n")
    for tier in TIERS:
        n = tier_counts.get(tier, 0)
        pct = (n / total_rows * 100) if total_rows else 0.0
        out.write(f"  {tier:8s}: {n:6d} 条 ({pct:5.2f}%)，{len(tier_unique_aro.get(tier, set()))} 个唯一 Best_Hit_ARO\n")
    out.write("\n")
    out.write(f"突变证据支持的耐药决定因子: {len(snp_rows)} 条\n")
    out.write("  （SNPs_in_Best_Hit_ARO 或 Other_SNPs 非 n/a，比单纯序列相似度更强的证据）\n\n")
    out.write(f"Top {len(top_drug_classes)} 药物类别（按总命中数）:\n")
    for cls, counts in top_drug_classes:
        out.write(f"  {cls:50s} {counts['Total']:6d}\n")

print(f"[card_summary] 总命中数: {total_rows}")
print(f"[card_summary] SNP证据支持: {len(snp_rows)}")
print(f"[card_summary] 药物类别数: {len(drug_class_counts)}")
print(f"[card_summary] 耐药机制数: {len(mechanism_counts)}")
PYEOF

if [ ! -s "${REPORT_TXT}" ]; then
    echo "[ERROR] 汇总失败，未生成 ${REPORT_TXT}"
    exit 1
fi

echo ""
echo "[card_summary] 输出目录: ${OUT_DIR}/"
cat "${REPORT_TXT}"
mgx_end "card_summary"
