#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tests/level2/test_validate_peptide_rules.sh
# Purpose: Level-2 test for the peptide-branch step rules (steps 44-50)
#          registered in scripts/utils/validate_step.py. Contract points come
#          from docs/plans/peptide_contract.md ("validate_step rules" section).
#
#   Positive suite: the real pilot products under Project/Project_demo must
#     PASS every registered check. validate() is invoked in-process (no CLI)
#     so the real workdir's logs/validation_log.jsonl is not polluted with
#     test entries. SKIPs (not FAILs) when the pilot products are absent.
#
#   Negative suite: a minimal synthetic fixture is built under /tmp, asserted
#     to PASS via the CLI, then mutated per scenario; each scenario must exit 1
#     with the TARGETED check flipped to false (other checks may also fail).
#     CLI runs exercise the 0/1 exit-code semantics; validation logs land in
#     the /tmp fixture only. All checks are local file reads: the validator
#     must not trigger any API/network traffic.
#
# Usage:   bash scripts/tests/level2/test_validate_peptide_rules.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VALIDATE="${REPO_ROOT}/scripts/utils/validate_step.py"
REAL_W="${REPO_ROOT}/Project/Project_demo"
STEPS=(44_pep_smorf_catalog 45_pep_ref_registry 46_pep_smorf_screen
       47_pep_smorf_nn 49a_pep_antismash_harvest 49b_pep_macrel
       50_pep_smorf_integrate)

fail() { echo "[FAIL] $1"; exit 1; }

# Snapshot/restore helpers for per-scenario file mutations (suffix-marked).
sb() { cp -a "$1" "$1.tbak"; }
sr() { [ -e "$1.tbak" ] && mv "$1.tbak" "$1" || true; }

cli_run() { python3 "${VALIDATE}" "$1" all "$2"; }

expect_step_pass() { # $1=step $2=workdir $3=label
    local out rc
    out="$(cli_run "$1" "$2")" && rc=0 || rc=$?
    [ "${rc}" -eq 0 ] || fail "$3: expected PASS (exit 0), got exit ${rc}
${out}"
}

expect_check_fail() { # $1=step $2=workdir $3=targeted-check $4=label
    local out rc
    out="$(cli_run "$1" "$2")" && rc=0 || rc=$?
    [ "${rc}" -eq 1 ] || fail "$4: expected FAIL (exit 1), got exit ${rc}
${out}"
    printf '%s' "${out}" | TARGETED="${3}" python3 -c '
import json, os, sys
v = json.load(sys.stdin)
name = os.environ["TARGETED"]
checks = {c["check"]: c["passed"] for c in v["checks"]}
if v["verdict"] != "FAIL" or checks.get(name) is not False:
    sys.stderr.write("targeted check %s not failed; verdict=%s checks=%s\n"
                     % (name, v["verdict"], checks))
    sys.exit(3)
' || fail "$4: targeted check '$3' did not fail as expected"
}

# ── Positive suite: real pilot products ──────────────────────────────────────
if [ ! -d "${REAL_W}/result/peptide" ]; then
    echo "[SKIP] real peptide products not present: ${REAL_W}/result/peptide"
else
    echo "[INFO] Positive suite: real pilot products must PASS all checks"
    for step in "${STEPS[@]}"; do
        echo "[INFO] step ${step}:"
        if ! python3 - "${step}" "${REAL_W}" "${REPO_ROOT}/scripts/utils" <<'PY'
import sys
sys.path.insert(0, sys.argv[3])
import validate_step
ok, results, verdict = validate_step.validate(sys.argv[1], "all", sys.argv[2], "")
for r in results:
    print("   %s %s" % ("OK " if r["passed"] else "BAD", r["check"]))
print("   verdict=%s" % verdict)
sys.exit(0 if ok else 1)
PY
        then
            fail "positive suite failed for step ${step}"
        fi
    done
    echo "[PASS] positive suite: ${#STEPS[@]}/7 steps PASS on real pilot products"
fi

# ── Negative suite: synthetic fixture under /tmp ─────────────────────────────
FX="$(mktemp -d /tmp/mgx_pep_validate_XXXXXX)"
cleanup() { rm -rf "${FX}" "${FX}.pristine"; }
trap cleanup EXIT

echo "[INFO] Negative suite: building synthetic fixture at ${FX}"
python3 - "${FX}" <<'PY'
import json, os, sys

fx = sys.argv[1]
pep = os.path.join(fx, "result", "peptide")
# Pilot sample IDs built programmatically (six samples, two of them 2-digit).
samples = ["Harbin" + n for n in ("1", "2", "3", "4", "10", "11")]

def w(rel, text):
    path = os.path.join(pep, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)

AA20 = "ACDEFGHIKLMNPQRSTVWY"
def seq(n, star=False):
    s = (AA20 * ((n // 20) + 1))[:n]
    return s + ("*" if star else "")

# ── 44: smorf catalog (6 samples x 2 rows, lengths 63/46, valid partials) ──
lens, partials = (63, 46), ("partial_g5", "complete")
total = 0
for sid in samples:
    rows = []
    for k, i in enumerate((1, 3)):
        rows.append("k9_%d_1\tk9_%d\t%d\t%d\t1\t%s\t%d\tATG\tabc123def456"
                    % (i, i, 3 + k * 100, 100 + k * 100, partials[k], lens[k]))
        total += 1
    w(f"smorf/{sid}.smorf.tsv",
      "gene_id\tcontig_id\tstart\tend\tstrand\tpartial\tlength_aa\tstart_type\tseq_sha1_12\n"
      + "\n".join(rows) + "\n")
    w(f"smorf/{sid}.smorf.faa",
      "".join(">k9_%d_1\n%s\n" % (i, seq(lens[0] if i == 1 else lens[1], star=(i == 1)))
              for i in (1, 3)))
w("smorf/smorf_catalog.stats.md",
  "# smorf pilot fixture\n\n| sample | candidates | complete | ratio |\n|---|---|---|---|\n"
  + "".join("| %s | 2 | 1 | 50.0%% |\n" % sid for sid in samples)
  + "| **\u5408\u8ba1** | **%d** | **6** | - |\n" % total)
w("smorf/smorf_catalog.done", "ok\n")

# ── 45: reference registry ──
w("refs/registry.json",
  json.dumps({"miProbe": {"api_version": "0.1.0", "base_url": "https://example.invalid/api"}}))
w("refs/registry.done", "ok\n")

# ── 46: screen batches + state.json cursor ──
counts = {"bioactivity": 1667, "amp": 500, "phychem": 500}
state = {}
for ep, n in counts.items():
    state[ep] = {"done_batches": [str(i) for i in range(n)]}
    for i in range(n):
        w(f"screen/{ep}/batch_{i:05d}.json", "{}")
w("screen/state.json", json.dumps(state))
w("screen/screen.done", "ok\n")

# ── 47: NN results (15000 rows = 5000 queries x 3), cursor 5000 ──
nn_rows = ["p%d\t%d\th%d\t0.900" % (i % 5000, 1 + i // 5000, i) for i in range(15000)]
w("nn/nn_results.tsv",
  "query_id\trank\thit_internal_id\tsimilarity\n" + "\n".join(nn_rows) + "\n")
w("nn/nn_cursor.txt", "5000")
w("nn/nn.done", "ok\n")

# ── 49a: antiSMASH precursors (TSV rows == FAA headers) ──
w("broute/antismash_precursors.tsv",
  "peptide_id\tsample\tregion_file\tlocus_tag\tproduct\tcds_location\tproto_core_coords\tlength_aa\textraction_rule\n"
  "a1\tsampleA\tk9.region001.gbk\tctg9_1\tlassopeptide\t1..120\t[(1, 120)]\t40\tprecursor:proto_core_overlapping_cds\n"
  "a2\tsampleA\tk9.region002.gbk\tctg9_2\tRiPP-like\t10..130\t[(10, 130)]\t40\tprecursor:proto_core_overlapping_cds\n")
w("broute/antismash_precursors.faa", ">a1\n%s\n>a2\n%s\n" % (seq(40), seq(40)))
w("broute/broute_antismash.done", "ok\n")

# ── 49b: macrel candidates (TSV ids are a subset of the raw smorfs FAA) ──
w("broute/macrel_precursors.tsv",
  "peptide_id\tsequence\tamp_family\tamp_probability\themolytic\themolytic_probability\tevidence_type\ttool_version\n"
  "m1\t%s\tCDP\t0.574\tHemo\t0.802\tmodel_prediction\tmacrel 1.6.0\n"
  "m2\t%s\tCLP\t0.535\tNonHemo\t0.168\tmodel_prediction\tmacrel 1.6.0\n"
  % (seq(25), seq(30)))
w("broute/macrel_raw/macrel.out.smorfs.faa",
  ">m1\n%s\n>m2\n%s\n>m3\n%s\n" % (seq(25, star=True), seq(30), seq(20)))
w("broute/macrel.done", "ok\n")

# ── 50: integration (pilot cursor 5000, nn_status full coverage 450320) ──
CURSOR = 5000
w("cluster_test/pilot5000.faa", "".join(">p%d\n%s\n" % (i, seq(50)) for i in range(CURSOR)))
w("integration/peptide_main.tsv",
  "peptide_id\tsample\tgene_id\tcontig_id\tstart\tend\tstrand\tpartial\tlength_aa\tseq_sha1_12\tcluster_representative_id\tis_cluster_representative\n"
  + "".join("p%d\tsampleA\tg%d\tc%d\t9\t58\t1\tcomplete\t50\th%012d\tp%d\ttrue\n" % (i, i, i, i, i)
            for i in range(CURSOR)))
w("integration/bioactivity_predictions.tsv",
  "peptide_id\tmodel_name\tdisplay_name\tcategory_label\tauc\tpredicted_class_label\tpredicted_label_id\tprobability\tfilter_usable\tevidence_type\tapi_version\n"
  "p0\tanti_inflammatory\tX\tY\t0.775\tAIP\t1\t0.8\tfalse\tmodel_prediction\tmiProbe API v0.1.0\n"
  "p1\tantioxidant\tX\tY\t0.879\tAO\t1\t0.7\ttrue\tmodel_prediction\tmiProbe API v0.1.0\n")
w("integration/amp_predictions.tsv",
  "peptide_id\tamp_raw_score\tamp_rounded_score\tevidence_type\tapi_version\n"
  + "".join("p%d\t0.8%d\t1\tmodel_prediction\tmiProbe API v0.1.0\n" % (i, i % 10) for i in range(CURSOR)))
w("integration/phychem_properties.tsv",
  "peptide_id\tcharge\thydrophobicity\tboman_index\taliphatic_index\tevidence_type\tapi_version\n"
  + "".join("p%d\t1.0\t0.5\t0.1\t100.0\tmodel_prediction\tmiProbe API v0.1.0\n" % i for i in range(CURSOR)))
w("integration/nn_hits.tsv",
  "query_id\trank\thit_internal_id\tsimilarity\tevidence_type\tapi_version\n"
  + "".join("p%d\t1\t%d\t0.84\tsimilarity_transfer\tmiProbe API v0.1.0\n" % (i, i) for i in range(CURSOR)))
# nn_status: 450320 unique keys over the 6-state vocabulary; queried == cursor.
outside, part = 150000, 18659
mapped = 450320 - CURSOR - outside - part  # 276661
ns = ["p%d\tqueried_complete_representative\tok" % i for i in range(CURSOR)]
ns += ["q%d\tnot_queried_outside_pilot\tNA" % i for i in range(outside)]
ns += ["q%d\tnot_queried_representative_mapped\tNA" % i for i in range(outside, outside + mapped)]
ns += ["q%d\tnot_queried_partial_policy\tNA" % i for i in range(outside + mapped, outside + mapped + part)]
assert len(ns) == 450320, len(ns)
w("integration/nn_status.tsv", "peptide_id\tnn_status\tnote\n" + "\n".join(ns) + "\n")
w("integration/abundance.tsv",
  "peptide_id\tsample\ttpm\tcaliber\tcatalog_representative_id\np0\tsampleA\t1.0\tdirect_gene_tpm\tp0\n")
w("integration/qc_summary.md", "# qc summary fixture\n")
w("integration/integrate.done", "ok\n")
print("fixture built")
PY

echo "[INFO] Pristine fixture must PASS for every step"
for step in "${STEPS[@]}"; do
    expect_step_pass "${step}" "${FX}" "pristine fixture ${step}"
done
echo "[PASS] pristine fixture: 7/7 steps PASS"

SAMPLE1="$(python3 -c "print(['Harbin' + n for n in ('1','2','3','4','10','11')][0])")"

# ── 44 scenarios ──
echo "[INFO] 44_pep_smorf_catalog scenarios"
SENT44="${FX}/result/peptide/smorf/smorf_catalog.done"
sb "${SENT44}"; rm -f "${SENT44}"
expect_check_fail 44_pep_smorf_catalog "${FX}" done_sentinel "44: missing done sentinel"
sr "${SENT44}"

T44="${FX}/result/peptide/smorf/${SAMPLE1}.smorf.tsv"
sb "${T44}"
printf 'k9_9_1\tk9_9\t1\t61\t1\tcomplete\t59\tATG\taaa111bbb222\n' >> "${T44}"
expect_check_fail 44_pep_smorf_catalog "${FX}" tsv_faa_count_closure "44: TSV row count != FAA headers"
sr "${T44}"

sb "${T44}"
python3 - "${T44}" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
f = lines[1].split("\t")
f[6] = "105"  # outside the 20-99 window
lines[1] = "\t".join(f)
open(p, "w").write("\n".join(lines) + "\n")
PY
expect_check_fail 44_pep_smorf_catalog "${FX}" length_bounds_20_99 "44: length_aa 105 out of bounds"
sr "${T44}"

sb "${T44}"
python3 - "${T44}" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
f = lines[2].split("\t")
f[5] = "unknown"  # not in the partial whitelist
lines[2] = "\t".join(f)
open(p, "w").write("\n".join(lines) + "\n")
PY
expect_check_fail 44_pep_smorf_catalog "${FX}" partial_whitelist "44: partial value outside whitelist"
sr "${T44}"

S44="${FX}/result/peptide/smorf/smorf_catalog.stats.md"
sb "${S44}"
sed -i "\\#^| ${SAMPLE1} |#d" "${S44}"
expect_check_fail 44_pep_smorf_catalog "${FX}" stats_md_six_samples "44: stats.md missing a sample row"
sr "${S44}"

# ── 45 scenarios ──
echo "[INFO] 45_pep_ref_registry scenarios"
R45="${FX}/result/peptide/refs/registry.json"
sb "${R45}"
printf '{bad json' > "${R45}"
expect_check_fail 45_pep_ref_registry "${FX}" registry_json_parses "45: registry.json unparseable"
sr "${R45}"

sb "${R45}"
python3 - "${R45}" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["miProbe"]["api_version"] = ""
json.dump(d, open(p, "w"))
PY
expect_check_fail 45_pep_ref_registry "${FX}" miprobe_api_version_nonempty "45: empty miProbe.api_version"
sr "${R45}"

# ── 46 scenarios ──
echo "[INFO] 46_pep_smorf_screen scenarios"
B46="${FX}/result/peptide/screen/amp/batch_00499.json"
ST46="${FX}/result/peptide/screen/state.json"

sb "${B46}"; rm -f "${B46}"
expect_check_fail 46_pep_smorf_screen "${FX}" batch_files_match_state "46: amp batch file missing vs state cursor"
sr "${B46}"

E46="${FX}/result/peptide/screen/bioactivity/batch_00000.error"
printf 'upstream 502\n' > "${E46}"
expect_check_fail 46_pep_smorf_screen "${FX}" no_unrecovered_batch_errors "46: unrecovered batch_*.error present"
rm -f "${E46}"

sb "${B46}"; sb "${ST46}"
python3 - "${ST46}" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["amp"]["done_batches"] = [str(i) for i in range(499)]  # trim cursor to 499
json.dump(d, open(p, "w"))
PY
rm -f "${B46}"  # files and cursor now agree at 499, below the 500 baseline
expect_check_fail 46_pep_smorf_screen "${FX}" batch_counts_pilot_baseline "46: amp batches below 500 baseline (state and files agree)"
sr "${ST46}"; sr "${B46}"

# ── 47 scenarios ──
echo "[INFO] 47_pep_smorf_nn scenarios"
SENT47="${FX}/result/peptide/nn/nn.done"
sb "${SENT47}"; rm -f "${SENT47}"
expect_check_fail 47_pep_smorf_nn "${FX}" nn_done_sentinel "47: missing nn.done"
sr "${SENT47}"

C47="${FX}/result/peptide/nn/nn_cursor.txt"
sb "${C47}"; printf '4999\n' > "${C47}"
expect_check_fail 47_pep_smorf_nn "${FX}" cursor_at_pilot_target "47: cursor 4999 != 5000"
sr "${C47}"

N47="${FX}/result/peptide/nn/nn_results.tsv"
sb "${N47}"
python3 - "${N47}" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
lines[-1] = "pX\tERR\t0\t0.0"  # row count kept, ERR marker injected
open(p, "w").write("\n".join(lines) + "\n")
PY
expect_check_fail 47_pep_smorf_nn "${FX}" no_err_rows "47: ERR row present"
sr "${N47}"

sb "${N47}"
sed -i '$d' "${N47}"
expect_check_fail 47_pep_smorf_nn "${FX}" nn_results_row_count "47: nn_results short of 15000 rows"
sr "${N47}"

# ── 49a scenarios ──
echo "[INFO] 49a_pep_antismash_harvest scenarios"
SENT49="${FX}/result/peptide/broute/broute_antismash.done"
sb "${SENT49}"; rm -f "${SENT49}"
expect_check_fail 49a_pep_antismash_harvest "${FX}" antismash_done_sentinel "49a: missing done sentinel"
sr "${SENT49}"

FA49="${FX}/result/peptide/broute/antismash_precursors.faa"
sb "${FA49}"
python3 - "${FA49}" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()[:-2]  # drop last record (header + seq)
open(p, "w").write("\n".join(lines) + "\n")
PY
expect_check_fail 49a_pep_antismash_harvest "${FX}" precursor_tsv_faa_closure "49a: FAA records != TSV rows"
sr "${FA49}"

sb "${FA49}"
sed -i '2s/^A/AZ/' "${FA49}"  # Z is non-canonical (fixture seqs start with A)
expect_check_fail 49a_pep_antismash_harvest "${FX}" precursor_aa_alphabet "49a: non-canonical AA char in FAA"
sr "${FA49}"

# ── 49b scenarios ──
echo "[INFO] 49b_pep_macrel scenarios"
SENT49B="${FX}/result/peptide/broute/macrel.done"
sb "${SENT49B}"; rm -f "${SENT49B}"
expect_check_fail 49b_pep_macrel "${FX}" macrel_done_sentinel "49b: missing done sentinel"
sr "${SENT49B}"

M49="${FX}/result/peptide/broute/macrel_precursors.tsv"
sb "${M49}"
sed -i '3s/^m2\t/m999\t/' "${M49}"  # candidate id no longer traceable in raw FAA
expect_check_fail 49b_pep_macrel "${FX}" candidates_traced_to_raw_faa "49b: candidate id missing from raw smorfs FAA"
sr "${M49}"

sb "${M49}"
python3 - "${M49}" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
f = lines[2].split("\t")
f[1] = f[1][:-1] + "B"  # non-canonical AA in the sequence column
lines[2] = "\t".join(f)
open(p, "w").write("\n".join(lines) + "\n")
PY
expect_check_fail 49b_pep_macrel "${FX}" macrel_aa_alphabet "49b: non-canonical AA in candidate sequence"
sr "${M49}"

sb "${M49}"
{ head -n 2 "${M49}"; sed -n '2p' "${M49}"; } > "${M49}.tmp" && mv "${M49}.tmp" "${M49}"
expect_check_fail 49b_pep_macrel "${FX}" candidate_ids_unique "49b: duplicate candidate peptide_id"
sr "${M49}"

# ── 50 scenarios ──
echo "[INFO] 50_pep_smorf_integrate scenarios"
QC50="${FX}/result/peptide/integration/qc_summary.md"
sb "${QC50}"; rm -f "${QC50}"
expect_check_fail 50_pep_smorf_integrate "${FX}" integration_nine_files "50: missing qc_summary.md (nine-file set broken)"
sr "${QC50}"

PM50="${FX}/result/peptide/integration/peptide_main.tsv"
sb "${PM50}"
sed -n '2p' "${PM50}" > "${PM50}.dupline" && cat "${PM50}.dupline" >> "${PM50}" && rm -f "${PM50}.dupline"
expect_check_fail 50_pep_smorf_integrate "${FX}" peptide_main_pk_unique "50: duplicate peptide_main primary key"
sr "${PM50}"

NS50="${FX}/result/peptide/integration/nn_status.tsv"
sb "${NS50}"
python3 - "${NS50}" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
f = lines[1].split("\t")
f[1] = "bogus_state"  # outside the 6-state vocabulary, row count kept
lines[1] = "\t".join(f)
open(p, "w").write("\n".join(lines) + "\n")
PY
expect_check_fail 50_pep_smorf_integrate "${FX}" nn_status_full_coverage "50: nn_status state outside vocabulary"
sr "${NS50}"

CE="${FX}/result/peptide/integration/candidate_evidence.tsv"
CE_HDR="$(printf 'candidate_id\tsource_tool\ttool_version\tsample\tgene_id\tcontig_id\tcoords\tcoords_note\tfamily\tprobability\tremap_status\tremap_note\tevidence_type\tnn_status')"

printf '%s\na1\tantismash\tv1\tsampleA\tg1\tc1\t1..120\tantismash_1based_closed\tlassopeptide\tNA\texact_mapped\tseq contained\tannotation_rule\tnot_applicable_b_route\na1\tantismash\tv1\tsampleA\tg2\tc2\t5..125\tantismash_1based_closed\tlassopeptide\tNA\tcontained_mapped\tseq contained\tannotation_rule\tnot_applicable_b_route\n' \
    "${CE_HDR}" > "${CE}"
expect_check_fail 50_pep_smorf_integrate "${FX}" candidate_evidence_contract "50: duplicate candidate_id"
rm -f "${CE}"

printf '%s\na1\tbagel4\tv1\tsampleA\tg1\tc1\t1..120\tantismash_1based_closed\tlassopeptide\tNA\texact_mapped\tseq contained\tannotation_rule\tnot_applicable_b_route\n' \
    "${CE_HDR}" > "${CE}"
expect_check_fail 50_pep_smorf_integrate "${FX}" candidate_evidence_contract "50: source_tool outside {antismash, macrel}"
rm -f "${CE}"

printf '%s\na1\tantismash\tv1\tsampleA\tg1\tc1\t1..120\tantismash_1based_closed\tlassopeptide\tNA\tmaybe_mapped\tseq contained\tannotation_rule\tnot_applicable_b_route\n' \
    "${CE_HDR}" > "${CE}"
expect_check_fail 50_pep_smorf_integrate "${FX}" candidate_evidence_contract "50: remap_status outside the 5-state set"
rm -f "${CE}"

printf '%s\na1\tantismash\tv1\tsampleA\tg1\tc1\t1..120\tantismash_1based_closed\tlassopeptide\tNA\texact_mapped\tseq contained\tmodel_prediction\tnot_applicable_b_route\n' \
    "${CE_HDR}" > "${CE}"
expect_check_fail 50_pep_smorf_integrate "${FX}" candidate_evidence_contract "50: evidence_type inconsistent with source_tool"
rm -f "${CE}"

BP50="${FX}/result/peptide/integration/bioactivity_predictions.tsv"
sb "${BP50}"
sed -i 's/\tfalse\t/\ttrue\t/' "${BP50}"  # contract point 5 violated: no unfiltered rows left
expect_check_fail 50_pep_smorf_integrate "${FX}" bioactivity_has_unfiltered_rows "50: no filter_usable=false rows in bioactivity_predictions"
sr "${BP50}"

AP50="${FX}/result/peptide/integration/amp_predictions.tsv"
sb "${AP50}"
sed -i '$d' "${AP50}"
expect_check_fail 50_pep_smorf_integrate "${FX}" prediction_rows_match_pilot "50: amp rows != pilot cursor"
sr "${AP50}"

# Positive branch of the conditional contract: a well-formed candidate_evidence
# table (49c product) must keep step 50 at PASS.
printf '%s\na1\tantismash\tv1\tsampleA\tg1\tc1\t1..120\tantismash_1based_closed\tlassopeptide\tNA\texact_mapped\tseq contained\tannotation_rule\tnot_applicable_b_route\na2\tmacrel\t1.6.0\tNA\tNA\tc2\t10..35\tmacrel_1based_closed\tCDP\t0.574\tcontained_mapped\tseq contained\tmodel_prediction\tnot_applicable_b_route\n' \
    "${CE_HDR}" > "${CE}"
expect_step_pass 50_pep_smorf_integrate "${FX}" "50: valid candidate_evidence keeps PASS"
rm -f "${CE}"
echo "[PASS] 50: candidate_evidence contract enforcement verified (4 negatives + 1 positive)"

echo ""
echo "=============================================================================="
echo "[PASS] peptide validate_step rules: positive suite (real products) +"
echo "       negative suite (fixture mutations, targeted checks all flipped)."
echo "=============================================================================="
