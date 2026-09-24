#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98b_bac_integration_tables.sh
# 功  能: 细菌维度功能整合 — 生成三类共 13 张整合表格
#
#   类型 A (10 张): 功能聚合表 (行=功能条目, 列=样本, 值=Σ TPM)
#     1. kegg_ko_abundance.tsv      KEGG KO × 样本
#     2. cog_abundance.tsv          COG category × 样本
#     3. arg_abundance.tsv          ARG gene (AMRFinder+CARD) × 样本
#     4. cazyme_abundance.tsv       CAZyme family × 样本
#     5. vfdb_abundance.tsv         Virulence factor × 样本
#     6. ncyc_abundance.tsv         氮循环功能基因 × 样本
#     7. pcyc_abundance.tsv         磷循环功能基因 × 样本
#     8. scyc_abundance.tsv         硫循环功能基因 × 样本 (可选)
#     9. iron_abundance.tsv         铁代谢功能类别 × 样本 (可选)
#    10. defense_abundance.tsv      防御系统类型 × 样本
#
#   类型 B (1 张): 基因级宽表 (行=NR基因, 列=样本TPM+全注释字段)
#    11. gene_annotation_matrix.tsv NR基因 × (TPM样本列 + 15类注释)
#         新增列: SCyc_gene, Iron_category, UniProt_SwissProt
#
#   类型 C (2 张): 通路-物种关联表
#    12. pathway_community.tsv      社区整体通路丰度 (来自 humann3 merged unstratified)
#    13. pathway_species_contrib.tsv 物种分层通路贡献 (来自 humann3 stratified)
#
# 依  赖:
#   - scripts/19/20: Salmon quant (result/assembly/salmon/{sample}/quant.sf)
#   - scripts/21: eggNOG (result/annotation/eggnog/eggnog.emapper.annotations)
#   - scripts/22: KEGG (result/annotation/kegg/kegg_diamond.tsv)
#   - scripts/23: AMRFinder (result/annotation/amrfinder/amrfinder_results.tsv)
#   - scripts/24: CARD (result/annotation/card/rgi_results.txt)
#   - scripts/25: dbCAN (result/annotation/dbcan/overview.txt)
#   - scripts/26: VFDB (result/annotation/vfdb/vfdb_hits.tsv)
#   - scripts/27: BacMet (result/annotation/bacmet/bacmet_hits.tsv)
#   - scripts/30: NCyc (result/annotation/ncyc/ncyc_hits.tsv)
#   - scripts/31: PCyc (result/annotation/pcyc/pcyc_hits.tsv)
#   - scripts/31b: SCyc (result/annotation/scyc/scyc_hits.tsv, 可选)
#   - scripts/31d: UniProt Swiss-Prot (result/annotation/uniprot_sprot/sprot_hits.tsv, 可选)
#   - scripts/31e: FeGenie NR (result/annotation/fegenie/NR/FeGenie-geneSummary.csv, 可选)
#   - scripts/29: Defense-Finder (result/annotation/defense_finder/defense_finder_genes.tsv)
#   - scripts/13b: HUMAnN3 merged (result/humann3/merged/)
#
# 输  出: ${WORKDIR}/result/integration/bacteria/
# 用  法: bash 98b_bac_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/utils/libcommon.sh"

show_help() {
cat << EOF
用法: bash 98b_bac_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]

必需参数:
  -w  工作目录（Project_example 路径）
  -r  CSCCD-MetagenomeFlow 项目根目录

可选参数:
  -t  线程数（默认 4，Python 脚本暂未并行化）
  -h  显示帮助
EOF
}

CPUS=4
# -t 为保留接口（Python 侧暂未并行化）；export 供子进程读取
export CPUS

# MGX_* 表由 libcommon.sh 的 mgx_parse 读取；export 避免单文件扫描误报未使用
export MGX_OPTS_STRING="w:WORKDIR r:REPO t:CPUS"
export MGX_OPTS_FLAG="force"
mgx_parse "$@"
mgx_require WORKDIR REPO

mgx_begin

# --- 路径定义 ---
ANNO_DIR="${WORKDIR}/result/annotation"
SALMON_DIR="${WORKDIR}/result/assembly/salmon"
HUMANN_DIR="${WORKDIR}/result/humann3"
OUT_DIR="${WORKDIR}/result/integration/bacteria"
NCYC_MAP="${REPO}/db/ncyc/misc/annotation.txt"
PCYC_MAP="${REPO}/db/pcyc/misc/annotation.txt"
SCYC_MAP="${REPO}/db/scyc/scyc-db/misc/annotation.txt"

# 幂等检查
if [ ${FORCE} -eq 0 ] && [ -f "${OUT_DIR}/gene_annotation_matrix.tsv" ] && \
   [ -f "${OUT_DIR}/kegg_ko_abundance.tsv" ]; then
    echo "[INFO] 整合表已存在，跳过。如需重建请先删除 ${OUT_DIR}"
    exit 0
fi

mkdir -p "${OUT_DIR}"

# --- 检查必需输入 ---
MISSING=0
for f in \
    "${ANNO_DIR}/eggnog/eggnog.emapper.annotations" \
    "${ANNO_DIR}/kegg/kegg_diamond.tsv" \
    "${ANNO_DIR}/amrfinder/amrfinder_results.tsv" \
    "${ANNO_DIR}/card/rgi_results.txt" \
    "${ANNO_DIR}/dbcan/overview.txt" \
    "${ANNO_DIR}/vfdb/vfdb_hits.tsv" \
    "${ANNO_DIR}/bacmet/bacmet_hits.tsv" \
    "${ANNO_DIR}/ncyc/ncyc_hits.tsv" \
    "${ANNO_DIR}/pcyc/pcyc_hits.tsv" \
    "${ANNO_DIR}/defense_finder/defense_finder_genes.tsv" \
    "${HUMANN_DIR}/merged/pathabundance_relab.tsv"; do
    if [ ! -f "${f}" ]; then
        echo "[ERROR] 缺少输入文件: ${f}"; MISSING=1
    fi
done
[ ${MISSING} -eq 1 ] && exit 1

# --- 检查可选输入（缺失只影响对应新增表/列） ---
for f in \
    "${ANNO_DIR}/scyc/scyc_hits.tsv" \
    "${ANNO_DIR}/uniprot_sprot/sprot_hits.tsv"; do
    if [ ! -f "${f}" ]; then
        echo "[WARNING] 缺少可选输入文件: ${f}"
    fi
done

FEGENIE_GENE_SUMMARY="${ANNO_DIR}/fegenie/NR/FeGenie-geneSummary.csv"
if [ ! -f "${FEGENIE_GENE_SUMMARY}" ]; then
    FEGENIE_FALLBACK_COUNT=$(find "${ANNO_DIR}/fegenie/NR" -maxdepth 1 -type f \
        -name "*-summary.csv" ! -name "FeGenie-summary.csv" ! -name "FinalSummary*" \
        2>/dev/null | wc -l)
    if [ "${FEGENIE_FALLBACK_COUNT}" -gt 0 ]; then
        echo "[WARNING] 缺少可选输入文件: ${FEGENIE_GENE_SUMMARY}; 将尝试合并 FeGenie per-category *-summary.csv"
    else
        echo "[WARNING] 缺少可选输入文件: ${FEGENIE_GENE_SUMMARY}"
    fi
fi

# 检查至少有一个 Salmon quant 文件
QUANT_FOUND=$(find "${SALMON_DIR}" -name "quant.sf" 2>/dev/null | wc -l)
if [ "${QUANT_FOUND}" -eq 0 ]; then
    echo "[ERROR] 未找到 Salmon quant.sf 文件: ${SALMON_DIR}"
    exit 1
fi

echo "[integration] 开始细菌维度功能整合"
echo "[integration] 输出目录: ${OUT_DIR}"
echo "[integration] 找到 ${QUANT_FOUND} 个 quant.sf 文件"

# ==============================================================================
# Python 整合主逻辑
# ==============================================================================

mgx_conda assembly python3 - \
    "${WORKDIR}" \
    "${REPO}" \
    "${OUT_DIR}" \
    "${NCYC_MAP}" \
    "${PCYC_MAP}" \
    "${SCYC_MAP}" \
<<'PYEOF'
import sys
import os
import csv
import glob
from collections import defaultdict

WORKDIR   = sys.argv[1]
REPO      = sys.argv[2]
OUT_DIR   = sys.argv[3]
NCYC_MAP  = sys.argv[4]
PCYC_MAP  = sys.argv[5]
SCYC_MAP  = sys.argv[6]

ANNO_DIR   = os.path.join(WORKDIR, "result", "annotation")
SALMON_DIR = os.path.join(WORKDIR, "result", "assembly", "salmon")
HUMANN_DIR = os.path.join(WORKDIR, "result", "humann3")

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: 读取 Salmon quant — gene_id → {sample: TPM}
# ──────────────────────────────────────────────────────────────────────────────
print("[Step1] 读取 Salmon TPM 定量结果")

gene_tpm = defaultdict(dict)   # gene_id → {sample: tpm}
samples = []

for quant_file in sorted(glob.glob(os.path.join(SALMON_DIR, "*/quant.sf"))):
    sample = os.path.basename(os.path.dirname(quant_file))
    samples.append(sample)
    with open(quant_file) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            gene_tpm[row["Name"]][sample] = float(row["TPM"])

print(f"  样本: {samples}")
print(f"  基因数: {len(gene_tpm)}")

def make_abundance_table(func_map, samples, outpath, func_col_name="function"):
    """
    func_map: gene_id → function_label (str, 可含逗号分隔多功能)
    输出: function_label × sample 的 TPM 求和矩阵
    """
    func_tpm = defaultdict(lambda: defaultdict(float))
    for gene, funcs in func_map.items():
        if not funcs or funcs == "-":
            continue
        for f in funcs.split(","):
            f = f.strip()
            if not f or f == "-":
                continue
            for sample in samples:
                func_tpm[f][sample] += gene_tpm.get(gene, {}).get(sample, 0.0)

    with open(outpath, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow([func_col_name] + samples)
        for func in sorted(func_tpm):
            row = [func] + [f"{func_tpm[func][s]:.4f}" for s in samples]
            writer.writerow(row)
    n = len(func_tpm)
    print(f"  → {os.path.basename(outpath)}: {n} 行 × {len(samples)+1} 列")
    return func_tpm

def optional_file(path, label):
    if os.path.isfile(path):
        return True
    print(f"  [WARNING] {label} 可选输入缺失，相关表/列将跳过或填充 '-'：{path}")
    return False

def add_label(label_map, gene, label):
    if not gene or not label or label == "-":
        return
    labels = []
    if gene in label_map and label_map[gene] != "-":
        labels = [x.strip() for x in label_map[gene].split(",") if x.strip()]
    if label not in labels:
        labels.append(label)
    label_map[gene] = ",".join(labels)

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: 读取各注释文件
# ──────────────────────────────────────────────────────────────────────────────

print("[Step2] 解析功能注释文件")

# 2a. eggNOG: KO (field 12) and COG category (field 7)
eggnog_ko  = {}  # gene → KO list (comma sep)
eggnog_cog = {}  # gene → COG category (e.g. "M", "KM")
eggnog_ec  = {}
eggnog_go  = {}
eggnog_desc= {}

eggnog_file = os.path.join(ANNO_DIR, "eggnog", "eggnog.emapper.annotations")
with open(eggnog_file) as fh:
    for line in fh:
        if line.startswith("#"):
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 12:
            continue
        gene = parts[0]
        cog  = parts[6]  if len(parts) > 6  else "-"
        desc = parts[7]  if len(parts) > 7  else "-"
        go   = parts[9]  if len(parts) > 9  else "-"
        ec   = parts[10] if len(parts) > 10 else "-"
        ko   = parts[11] if len(parts) > 11 else "-"
        eggnog_ko[gene]   = ko.replace("ko:", "").replace("ko:", "") if ko != "-" else "-"
        eggnog_cog[gene]  = cog  if cog  != "-" else "-"
        eggnog_ec[gene]   = ec   if ec   != "-" else "-"
        eggnog_go[gene]   = go   if go   != "-" else "-"
        eggnog_desc[gene] = desc if desc != "-" else "-"

# Normalize eggnog KO: "ko:K01703,ko:K20452" → "K01703,K20452"
for gene in eggnog_ko:
    raw = eggnog_ko[gene]
    if raw and raw != "-":
        kos = [x.replace("ko:", "") for x in raw.split(",")]
        eggnog_ko[gene] = ",".join(kos)

print(f"  eggNOG: {len(eggnog_ko)} 基因, KO覆盖: {sum(1 for v in eggnog_ko.values() if v!='-')}, "
      f"COG覆盖: {sum(1 for v in eggnog_cog.values() if v!='-')}")

# 2b. KEGG diamond hits: use eggnog KO (more reliable), kegg file as backup ref
# kegg_diamond.tsv: gene | ref_gene | pident | ...
kegg_gene_ref = {}
kegg_file = os.path.join(ANNO_DIR, "kegg", "kegg_diamond.tsv")
with open(kegg_file) as fh:
    for line in fh:
        if line.startswith("#"):
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2:
            continue
        gene = parts[0]
        ref  = parts[1]  # e.g. "scaz:ACI3DN_01020"
        if gene not in kegg_gene_ref:
            kegg_gene_ref[gene] = ref

# 2c. AMRFinder: gene → ARG symbol
amr_map = {}
amr_file = os.path.join(ANNO_DIR, "amrfinder", "amrfinder_results.tsv")
with open(amr_file) as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        gene = row.get("Protein id", "").strip()
        sym  = row.get("Element symbol", "").strip()
        if gene and sym:
            amr_map[gene] = sym

# 2d. CARD/RGI: ORF_ID has trailing " # coords", extract gene_id
card_map = {}
card_file = os.path.join(ANNO_DIR, "card", "rgi_results.txt")
with open(card_file) as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        orf = row.get("ORF_ID", "").split(" ")[0].strip()
        aro = row.get("Best_Hit_ARO", "").strip()
        drug= row.get("Drug Class", "").strip()
        if orf and aro:
            card_map[orf] = aro

# Merge AMRFinder + CARD into combined ARG map
arg_map = {}
all_arg_genes = set(amr_map.keys()) | set(card_map.keys())
for gene in all_arg_genes:
    labels = []
    if gene in amr_map:
        labels.append(f"AMR:{amr_map[gene]}")
    if gene in card_map:
        labels.append(f"CARD:{card_map[gene]}")
    arg_map[gene] = ",".join(labels)

print(f"  ARG: AMRFinder={len(amr_map)}, CARD={len(card_map)}, 合并={len(arg_map)} 基因")

# 2e. dbCAN: prefer DIAMOND result (col 5), then HMMER (col 3)
cazyme_map = {}
dbcan_file = os.path.join(ANNO_DIR, "dbcan", "overview.txt")
with open(dbcan_file) as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        gene    = row.get("Gene ID", "").strip()
        diamond = row.get("DIAMOND", "-").strip()
        hmmer   = row.get("HMMER", "-").strip()
        label   = diamond if diamond != "-" else hmmer
        if gene and label != "-":
            cazyme_map[gene] = label

print(f"  CAZyme: {len(cazyme_map)} 基因")

# 2f. VFDB: gene → VFG_id
vfdb_map = {}
vfdb_file = os.path.join(ANNO_DIR, "vfdb", "vfdb_hits.tsv")
with open(vfdb_file) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            gene = parts[0].strip()
            vfg  = parts[1].strip()
            if gene and vfg:
                vfdb_map[gene] = vfg

print(f"  VFDB: {len(vfdb_map)} 基因")

# 2g. BacMet: gene → BAC_id (for gene-level table; will use for Type B)
bacmet_map = {}
bacmet_file = os.path.join(ANNO_DIR, "bacmet", "bacmet_hits.tsv")
with open(bacmet_file) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            gene = parts[0].strip()
            bac  = parts[1].strip()
            if gene and bac:
                bacmet_map[gene] = bac

print(f"  BacMet: {len(bacmet_map)} 基因")

# 2h. NCyc: gene → function via annotation.txt mapping
ncyc_acc_to_func = {}
with open(NCYC_MAP) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            ncyc_acc_to_func[parts[0].strip()] = parts[1].strip()

ncyc_map = {}
ncyc_file = os.path.join(ANNO_DIR, "ncyc", "ncyc_hits.tsv")
with open(ncyc_file) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            gene = parts[0].strip()
            ref  = parts[1].strip()
            func = ncyc_acc_to_func.get(ref, ref)  # fallback to accession
            if gene:
                ncyc_map[gene] = func

print(f"  NCyc: {len(ncyc_map)} 基因")

# 2i. PCyc: same as NCyc
pcyc_acc_to_func = {}
with open(PCYC_MAP) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            pcyc_acc_to_func[parts[0].strip()] = parts[1].strip()

pcyc_map = {}
pcyc_file = os.path.join(ANNO_DIR, "pcyc", "pcyc_hits.tsv")
with open(pcyc_file) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            gene = parts[0].strip()
            ref  = parts[1].strip()
            func = pcyc_acc_to_func.get(ref, ref)
            if gene:
                pcyc_map[gene] = func

print(f"  PCyc: {len(pcyc_map)} 基因")

# 2j. SCyc: same DIAMOND outfmt6 structure as NCyc/PCyc (optional)
scyc_acc_to_func = {}
if os.path.isfile(SCYC_MAP):
    with open(SCYC_MAP) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                scyc_acc_to_func[parts[0].strip()] = parts[1].strip()
else:
    print(f"  [WARNING] SCyc annotation map missing, falling back to hit accession: {SCYC_MAP}")

scyc_map = {}
scyc_file = os.path.join(ANNO_DIR, "scyc", "scyc_hits.tsv")
if optional_file(scyc_file, "SCyc"):
    with open(scyc_file) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                gene = parts[0].strip()
                ref  = parts[1].strip()
                func = scyc_acc_to_func.get(ref, ref)
                if gene:
                    scyc_map[gene] = func

print(f"  SCyc: {len(scyc_map)} 基因")

# 2k. FeGenie NR: gene → iron category (optional)
iron_map = {}
fegenie_dir = os.path.join(ANNO_DIR, "fegenie", "NR")
fegenie_gene_summary = os.path.join(fegenie_dir, "FeGenie-geneSummary.csv")

def add_iron_label(gene, category):
    category = category.strip() if category else ""
    gene = gene.strip() if gene else ""
    if category in ("", "-", "EMPTY", "category"):
        return False
    if gene not in gene_tpm:
        return False
    add_label(iron_map, gene, category)
    return True

def load_fegenie_category_summaries():
    summary_files = sorted(glob.glob(os.path.join(fegenie_dir, "*-summary.csv")))
    summary_files = [
        f for f in summary_files
        if os.path.basename(f) not in ("FeGenie-summary.csv", "FinalSummary.csv")
    ]
    for summary_file in summary_files:
        category = os.path.basename(summary_file).rsplit("-summary.csv", 1)[0]
        with open(summary_file, newline="") as fh:
            reader = csv.DictReader(fh)
            for row in reader:
                gene = (row.get("ORF") or row.get("orf") or row.get("gene") or
                        row.get("gene_id") or row.get("Gene ID") or "").strip()
                add_iron_label(gene, category)
    return len(summary_files)

def build_fegenie_hmm_to_category():
    hmm_root = os.path.join(REPO, "envs", "fegenie", "share", "fegenie-1.2", "hmms", "iron")
    if not os.path.isdir(hmm_root):
        return {}

    hmm_to_category = {}
    for category in os.listdir(hmm_root):
        category_dir = os.path.join(hmm_root, category)
        if not os.path.isdir(category_dir):
            continue
        for hmm_file in glob.glob(os.path.join(category_dir, "*.hmm")):
            hmm_to_category[os.path.basename(hmm_file)] = category
    return hmm_to_category

def load_fegenie_hmm_results_csv():
    hmm_results_csv = os.path.join(fegenie_dir, "FeGenie-HMM-results.csv")
    if not os.path.isfile(hmm_results_csv):
        return False
    hmm_to_category = build_fegenie_hmm_to_category()
    with open(hmm_results_csv, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            gene = (row.get("orf") or row.get("ORF") or row.get("gene") or
                    row.get("gene_id") or row.get("Gene ID") or row.get("target") or "").strip()
            category = (row.get("category") or row.get("Category") or
                        row.get("function") or row.get("Function") or "").strip()
            if not category:
                hmm = (row.get("HMM") or row.get("hmm") or row.get("related_hmm") or "").strip()
                if hmm and not hmm.endswith(".hmm"):
                    hmm = f"{hmm}.hmm"
                category = hmm_to_category.get(hmm, "")
            add_iron_label(gene, category)
    return True

def load_fegenie_hmm_results():
    hmm_to_category = build_fegenie_hmm_to_category()
    if not hmm_to_category:
        return 0

    tblout_files = []
    tblout_files.extend(glob.glob(os.path.join(fegenie_dir, "*-HMM", "*.tblout")))
    tblout_files.extend(glob.glob(os.path.join(fegenie_dir, "HMM_results", "*-HMM", "*.tblout")))

    used_files = 0
    for tblout_file in sorted(tblout_files):
        hmm_name = os.path.basename(tblout_file).rsplit(".tblout", 1)[0]
        category = hmm_to_category.get(hmm_name)
        if not category:
            continue
        used_files += 1
        with open(tblout_file) as fh:
            for line in fh:
                if line.startswith("#") or not line.strip():
                    continue
                parts = line.split()
                if parts:
                    add_iron_label(parts[0], category)
    return used_files

if os.path.isfile(fegenie_gene_summary):
    with open(fegenie_gene_summary, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            gene = (row.get("orf") or row.get("ORF") or row.get("gene") or
                    row.get("gene_id") or row.get("Gene ID") or "").strip()
            category = (row.get("category") or row.get("Category") or
                        row.get("function") or row.get("Function") or "").strip()
            add_iron_label(gene, category)
    if iron_map:
        print(f"  FeGenie: {len(iron_map)} 基因 (FeGenie-geneSummary.csv)")
    else:
        print(f"  [WARNING] FeGenie-geneSummary.csv 未提供可匹配 NR gene_id 的有效 category，尝试 fallback：{fegenie_gene_summary}")

if not iron_map:
    n_summary_files = load_fegenie_category_summaries()
    if iron_map:
        print(f"  FeGenie: {len(iron_map)} 基因 (merged {n_summary_files} per-category summary files)")

if not iron_map:
    has_hmm_csv = load_fegenie_hmm_results_csv()
    if iron_map:
        print(f"  FeGenie: {len(iron_map)} 基因 (FeGenie-HMM-results.csv)")
    elif has_hmm_csv:
        print("  [WARNING] FeGenie-HMM-results.csv 未提供可匹配 NR gene_id 的有效 category，尝试 HMM_results tblout fallback")

if not iron_map:
    n_hmm_files = load_fegenie_hmm_results()
    if iron_map:
        print(f"  FeGenie: {len(iron_map)} 基因 (parsed {n_hmm_files} HMM_results tblout files)")

if not iron_map:
    print(f"  [WARNING] FeGenie NR 可选输入缺失或无法匹配 NR gene_id，Iron_category 将填充 '-'：{fegenie_dir}")
    print("  FeGenie: 0 基因")

# 2l. UniProt Swiss-Prot: gene → best-hit accession (optional)
uniprot_map = {}
uniprot_best = {}  # gene → (bitscore, evalue, accession)
uniprot_file = os.path.join(ANNO_DIR, "uniprot_sprot", "sprot_hits.tsv")
if optional_file(uniprot_file, "UniProt Swiss-Prot"):
    with open(uniprot_file) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 12:
                continue
            gene = parts[0].strip()
            acc  = parts[1].strip()
            try:
                evalue = float(parts[10])
            except ValueError:
                evalue = float("inf")
            try:
                bits = float(parts[11])
            except ValueError:
                bits = float("-inf")
            if not gene or not acc:
                continue
            prev = uniprot_best.get(gene)
            if prev is None or bits > prev[0] or (bits == prev[0] and evalue < prev[1]):
                uniprot_best[gene] = (bits, evalue, acc)
    for gene, best in uniprot_best.items():
        uniprot_map[gene] = best[2]

print(f"  UniProt Swiss-Prot: {len(uniprot_map)} 基因")

# 2m. Defense-Finder: gene → type (col 23) + subtype (col 24)
defense_map = {}
def_file = os.path.join(ANNO_DIR, "defense_finder", "defense_finder_genes.tsv")
with open(def_file) as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        # replicon field contains the gene_id (first column)
        gene    = row.get("replicon", "").strip()
        dtype   = row.get("type", "-").strip()
        dsubtype= row.get("subtype", "-").strip()
        if gene and dtype != "-":
            label = f"{dtype}:{dsubtype}" if dsubtype and dsubtype != "-" else dtype
            defense_map[gene] = label

print(f"  Defense-Finder: {len(defense_map)} 基因")

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: 生成类型 A — 功能聚合表 (10 张；其中 2 张可选)
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step3] 生成类型 A 功能聚合表（10 张；SCyc/Iron 可选）")

make_abundance_table(eggnog_ko,  samples,
    os.path.join(OUT_DIR, "kegg_ko_abundance.tsv"),  "KEGG_KO")

make_abundance_table(eggnog_cog, samples,
    os.path.join(OUT_DIR, "cog_abundance.tsv"),      "COG_category")

# ARG: use combined label as-is for per-gene, but group by gene symbol for abundance
arg_sym_map = {}  # gene → short symbol (without prefix)
for gene, label in arg_map.items():
    # Prefer AMRFinder symbol (more canonical), fallback to CARD ARO
    if gene in amr_map:
        arg_sym_map[gene] = amr_map[gene]
    elif gene in card_map:
        arg_sym_map[gene] = card_map[gene]
make_abundance_table(arg_sym_map, samples,
    os.path.join(OUT_DIR, "arg_abundance.tsv"),      "ARG_gene")

make_abundance_table(cazyme_map, samples,
    os.path.join(OUT_DIR, "cazyme_abundance.tsv"),   "CAZyme_family")

make_abundance_table(vfdb_map,   samples,
    os.path.join(OUT_DIR, "vfdb_abundance.tsv"),     "VF_gene")

make_abundance_table(ncyc_map,   samples,
    os.path.join(OUT_DIR, "ncyc_abundance.tsv"),     "NCyc_gene")

make_abundance_table(pcyc_map,   samples,
    os.path.join(OUT_DIR, "pcyc_abundance.tsv"),     "PCyc_gene")

if scyc_map:
    make_abundance_table(scyc_map,   samples,
        os.path.join(OUT_DIR, "scyc_abundance.tsv"),     "SCyc_gene")
else:
    print("  [WARNING] 跳过 scyc_abundance.tsv：无 SCyc 注释")

if iron_map:
    make_abundance_table(iron_map,   samples,
        os.path.join(OUT_DIR, "iron_abundance.tsv"),     "Iron_category")
else:
    print("  [WARNING] 跳过 iron_abundance.tsv：无 FeGenie NR 注释")

make_abundance_table(defense_map, samples,
    os.path.join(OUT_DIR, "defense_abundance.tsv"),  "Defense_system")

# ──────────────────────────────────────────────────────────────────────────────
# Step 4: 生成类型 B — 基因级宽表 (1 张)
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step4] 生成类型 B 基因级宽表")

all_genes = sorted(gene_tpm.keys())
tpm_headers   = [f"TPM_{s}" for s in samples]
anno_headers  = ["COG_category", "KEGG_KO", "EC", "GO",
                 "ARG_AMRFinder", "ARG_CARD", "CAZyme",
                 "VFDB", "BacMet", "NCyc_gene", "PCyc_gene", "Defense_system",
                 "SCyc_gene", "Iron_category", "UniProt_SwissProt"]

outpath_b = os.path.join(OUT_DIR, "gene_annotation_matrix.tsv")
with open(outpath_b, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(["gene_id"] + tpm_headers + anno_headers)
    for gene in all_genes:
        tpm_vals = [f"{gene_tpm[gene].get(s, 0.0):.4f}" for s in samples]
        row = [gene] + tpm_vals + [
            eggnog_cog.get(gene, "-"),
            eggnog_ko.get(gene, "-"),
            eggnog_ec.get(gene, "-"),
            eggnog_go.get(gene, "-"),
            amr_map.get(gene, "-"),
            card_map.get(gene, "-"),
            cazyme_map.get(gene, "-"),
            vfdb_map.get(gene, "-"),
            bacmet_map.get(gene, "-"),
            ncyc_map.get(gene, "-"),
            pcyc_map.get(gene, "-"),
            defense_map.get(gene, "-"),
            scyc_map.get(gene, "-"),
            iron_map.get(gene, "-"),
            uniprot_map.get(gene, "-"),
        ]
        writer.writerow(row)

print(f"  → gene_annotation_matrix.tsv: {len(all_genes)} 基因 × "
      f"{len(tpm_headers)+len(anno_headers)+1} 列")

# ──────────────────────────────────────────────────────────────────────────────
# Step 5: 生成类型 C — 通路-物种关联表 (2 张)
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step5] 生成类型 C 通路表（2 张）")

# C1: 社区整体通路丰度（unstratified, 已有多样本矩阵，直接复制并标注来源）
import shutil
src_path = os.path.join(WORKDIR, "result", "humann3", "merged", "pathabundance_relab.tsv")
dst_path = os.path.join(OUT_DIR, "pathway_community.tsv")
shutil.copy2(src_path, dst_path)
n_paths = sum(1 for line in open(dst_path) if not line.startswith("#")) - 1
print(f"  → pathway_community.tsv: {max(n_paths,0)} 条通路（来自 humann3 merged unstratified）")

# C2: 通路-物种贡献矩阵 — 从 stratified 输出聚合
# 格式: pathway | contributing_species | S01 ... S06
strat_rows  = defaultdict(lambda: defaultdict(float))   # (pathway, species) → {sample: val}
pathway_species_keys = []

for sample in samples:
    strat_file = os.path.join(WORKDIR, "result", "humann3", sample,
                              "stratified", f"{sample}_pathabundance_relab_stratified.tsv")
    if not os.path.isfile(strat_file):
        continue
    with open(strat_file) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            feature = parts[0]
            if "|" not in feature:
                continue
            pathway, species = feature.split("|", 1)
            val = float(parts[1]) if parts[1] else 0.0
            key = (pathway, species)
            if key not in strat_rows:
                pathway_species_keys.append(key)
            strat_rows[key][sample] = val

dst_strat = os.path.join(OUT_DIR, "pathway_species_contrib.tsv")
with open(dst_strat, "w", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(["pathway", "species"] + samples)
    for key in pathway_species_keys:
        pathway, species = key
        vals = [f"{strat_rows[key].get(s, 0.0):.4f}" for s in samples]
        writer.writerow([pathway, species] + vals)

n_strat = len(pathway_species_keys)
print(f"  → pathway_species_contrib.tsv: {n_strat} 条 (pathway, species) 组合")

# ──────────────────────────────────────────────────────────────────────────────
# 汇总报告
# ──────────────────────────────────────────────────────────────────────────────
print("\n" + "="*70)
print("[integration] 完成！输出目录:", OUT_DIR)
print("="*70)
for fname in sorted(os.listdir(OUT_DIR)):
    fpath = os.path.join(OUT_DIR, fname)
    if os.path.isfile(fpath):
        with open(fpath) as fh:
            nrows = sum(1 for _ in fh) - 1  # subtract header
        ncols = len(open(fpath).readline().rstrip("\n").split("\t"))
        size_kb = os.path.getsize(fpath) // 1024
        print(f"  {fname:<45s}  {nrows:>6} 行 × {ncols:>3} 列  ({size_kb} KB)")

PYEOF

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] 整合脚本失败（exit: ${EXIT_CODE}）"
    exit ${EXIT_CODE}
fi

echo ""
mgx_end "integration"
echo "[integration] 输出目录: ${OUT_DIR}"
