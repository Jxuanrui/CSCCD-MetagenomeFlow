#!/usr/bin/env bash
# ==============================================================================
# 脚本名: 98b_bac_integration_tables.sh
# 功  能: 细菌维度功能整合 — 生成两类共 11 张整合表格
#
#   类型 A (8 张): 功能聚合表 (行=功能条目, 列=样本, 值=Σ TPM)
#     1. kegg_ko_abundance.tsv      KEGG KO × 样本
#     2. cog_abundance.tsv          COG category × 样本
#     3. arg_abundance.tsv          ARG gene (AMRFinder+CARD) × 样本
#     4. cazyme_abundance.tsv       CAZyme family × 样本
#     5. vfdb_abundance.tsv         Virulence factor × 样本
#     6. ncyc_abundance.tsv         氮循环功能基因 × 样本
#     7. pcyc_abundance.tsv         磷循环功能基因 × 样本
#     8. defense_abundance.tsv      防御系统类型 × 样本
#
#   类型 B (1 张): 基因级宽表 (行=NR基因, 列=样本TPM+全注释字段)
#     9. gene_annotation_matrix.tsv 8623基因 × (TPM×6 + 10类注释)
#
#   类型 C (2 张): 通路-物种关联表
#    10. pathway_community.tsv      社区整体通路丰度 (来自 humann3 merged unstratified)
#    11. pathway_species_contrib.tsv 物种分层通路贡献 (来自 humann3 stratified)
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
#   - scripts/29: Defense-Finder (result/annotation/defense_finder/defense_finder_genes.tsv)
#   - scripts/13b: HUMAnN3 merged (result/humann3/merged/)
#
# 输  出: ${WORKDIR}/result/integration/bacteria/
# 用  法: bash 98b_bac_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]
# ==============================================================================

show_help() {
cat << EOF
用法: bash 98b_bac_integration_tables.sh -w WORKDIR -r REPO [-t CPUS]

必需参数:
  -w  工作目录（Project_example 路径）
  -r  MaxMetagenome 项目根目录

可选参数:
  -t  线程数（默认 4，Python 脚本暂未并行化）
  -h  显示帮助
EOF
}

WORKDIR=""
REPO=""
CPUS=4

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORKDIR="$2"; shift 2 ;;
        -r) REPO="$2";    shift 2 ;;
        -t) CPUS="$2";    shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "[ERROR] 未知参数: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "${WORKDIR}" ] || [ -z "${REPO}" ]; then
    echo "[ERROR] 缺少必需参数（-w/-r）"; show_help; exit 1
fi

SECONDS=0

# --- 路径定义 ---
ANNO_DIR="${WORKDIR}/result/annotation"
SALMON_DIR="${WORKDIR}/result/assembly/salmon"
HUMANN_DIR="${WORKDIR}/result/humann3"
OUT_DIR="${WORKDIR}/result/integration/bacteria"
NCYC_MAP="${REPO}/db/ncyc/misc/annotation.txt"
PCYC_MAP="${REPO}/db/pcyc/misc/annotation.txt"

# 幂等检查
if [ -f "${OUT_DIR}/gene_annotation_matrix.tsv" ] && \
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

conda run --prefix "${REPO}/envs/assembly" --no-capture-output \
python3 - \
    "${WORKDIR}" \
    "${REPO}" \
    "${OUT_DIR}" \
    "${NCYC_MAP}" \
    "${PCYC_MAP}" \
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

# 2j. Defense-Finder: gene → type (col 23) + subtype (col 24)
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
# Step 3: 生成类型 A — 功能聚合表 (8 张)
# ──────────────────────────────────────────────────────────────────────────────
print("\n[Step3] 生成类型 A 功能聚合表（8 张）")

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
                 "VFDB", "BacMet", "NCyc_gene", "PCyc_gene", "Defense_system"]

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
echo "[integration] 细菌维度整合表生成完成，耗时 ${SECONDS}s"
echo "[integration] 输出目录: ${OUT_DIR}"
