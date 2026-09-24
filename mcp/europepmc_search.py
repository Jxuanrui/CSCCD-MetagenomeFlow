#!/usr/bin/env python

import json
import re
import sys
import tempfile
import time
from pathlib import Path

import requests


BASE_URL = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
USER_AGENT = "MaxMetagenome/1.0"
PAGE_SIZE = 50
REQUEST_TIMEOUT = 60
RETRY_INTERVAL_SECONDS = 5
RATE_LIMIT_SECONDS = 0.5
MAX_RETRIES = 2
YEAR_RANGE = "PUB_YEAR:[2018 TO 2026]"
MICROBIOME_CONTEXT = (
    '("gut microbiome" OR "gut microbiota" OR "intestinal microbiome" OR '
    '"human gut" OR microbiome OR metagenom* OR metatranscriptom* OR stool OR fecal)'
)
METHODS_PRIORITY = (
    "(method* OR methods OR workflow OR benchmark* OR protocol* OR pipeline OR "
    "profiling OR analysis OR classifier OR integration)"
)
JOURNAL_WHITELIST = [
    "Nature",
    "Cell",
    "Science",
    "Nature Methods",
    "Nature Microbiology",
    "Nature Biotechnology",
    "Nature Communications",
    "Cell Host Microbe",
    "Cell Reports",
    "Genome Biology",
    "Microbiome",
    "ISME Journal",
    "Gut Microbes",
    "mSystems",
    "mBio",
    "PLOS Computational Biology",
    "Bioinformatics",
    "Nucleic Acids Research",
    "Briefings in Bioinformatics",
]
SEARCH_TOPICS = [
    {
        "id": "metaphlan4_methods",
        "terms": '("MetaPhlAn4" OR "MetaPhlAn 4" OR MetaPhlAn)',
    },
    {
        "id": "humann3_methods",
        "terms": '("HUMAnN3" OR "HUMAnN 3" OR HUMAnN)',
    },
    {
        "id": "kraken2_bracken_methods",
        "terms": '("Kraken 2" OR Kraken2 OR Bracken)',
    },
    {
        "id": "megahit_assembly_methods",
        "terms": "(MEGAHIT AND assembly)",
    },
    {
        "id": "binning_benchmark_metabat_maxbin_semibin",
        "terms": '("MetaBAT" OR "MaxBin" OR SemiBin) AND (binning OR benchmark*)',
    },
    {
        "id": "checkm2_quality",
        "terms": '("CheckM2" OR "CheckM 2" OR CheckM) AND ("genome quality" OR completeness OR contamination)',
    },
    {
        "id": "gtdbtk_taxonomy",
        "terms": '("GTDB-Tk" OR GTDBTk OR "Genome Taxonomy Database Toolkit")',
    },
    {
        "id": "drep_dereplication",
        "terms": "(dRep AND dereplication)",
    },
    {
        "id": "strainphlan_tracking",
        "terms": '("StrainPhlAn" OR "strain tracking")',
    },
    {
        "id": "centrifuger_gtdb",
        "terms": "(Centrifuger AND GTDB)",
    },
    {
        "id": "genomad_virsorter2",
        "terms": '("geNomad" OR "VirSorter2" OR "VirSorter 2")',
    },
    {
        "id": "checkv_viral_quality",
        "terms": '(CheckV AND ("viral quality" OR completeness OR contamination))',
    },
    {
        "id": "iphop_host_prediction",
        "terms": '(iPHoP AND ("host prediction" OR host assignment))',
    },
    {
        "id": "votu_95_ani",
        "terms": '("vOTU" OR "viral operational taxonomic unit") AND ("95% ANI" OR ANI)',
    },
    {
        "id": "pharokka_phage_annotation",
        "terms": '(PHAROKKA AND ("phage annotation" OR annotation))',
    },
    {
        "id": "mycobiome_its_wgs_profiling",
        "terms": "(mycobiome AND ITS AND WGS profiling)",
    },
    {
        "id": "funomic_fungi_marker",
        "terms": '(FunOMIC AND ("fungi marker" OR fungal marker))',
    },
    {
        "id": "ccmetagen_eukaryote_classification",
        "terms": '(CCMetagen AND ("eukaryote classification" OR eukaryotic classification))',
    },
    {
        "id": "microfisher_its_extraction",
        "terms": '(MicroFisher AND ("ITS extraction" OR ITS))',
    },
    {
        "id": "alpha_beta_diversity_vegan_phyloseq",
        "terms": '("alpha diversity" OR "beta diversity" OR vegan OR phyloseq)',
    },
    {
        "id": "differential_abundance_ancombc2_deseq2_lefse",
        "terms": '("ANCOM-BC2" OR DESeq2 OR LEfSe) AND ("differential abundance" OR biomarker)',
    },
    {
        "id": "batch_correction_mmuphin_conqur",
        "terms": '(MMUPHin OR ConQuR) AND "batch correction"',
    },
    {
        "id": "siamcat_disease_classifier",
        "terms": '(SIAMCAT AND ("disease classifier" OR classification))',
    },
    {
        "id": "curatedmetagenomicdata_cross_cohort",
        "terms": '(curatedMetagenomicData AND ("cross-cohort" OR meta-analysis OR cross study))',
    },
    {
        "id": "cami_benchmark",
        "terms": '(CAMI AND benchmark*)',
    },
    {
        "id": "cami2_results",
        "terms": '("CAMI 2" OR CAMI2) AND results',
    },
    {
        "id": "multiomics_integration",
        "terms": '("multi-omics integration" OR "multiomics integration")',
    },
    {
        "id": "metagenomics_metabolomics_correlation",
        "terms": '(metagenomics AND metabolomics AND correlation)',
    },
    {
        "id": "ibd_gut_dysbiosis",
        "terms": '(IBD OR "inflammatory bowel disease") AND dysbiosis',
    },
    {
        "id": "crc_colorectal_cancer",
        "terms": '("colorectal cancer" OR CRC)',
    },
    {
        "id": "t2d_diabetes",
        "terms": '("type 2 diabetes" OR T2D OR diabetes)',
    },
    {
        "id": "obesity_bmi",
        "terms": '(obesity OR BMI)',
    },
    {
        "id": "cvd_tmao",
        "terms": '("cardiovascular disease" OR cardiovascular OR CVD OR TMAO)',
    },
    {
        "id": "nafld_masld_liver",
        "terms": '(NAFLD OR MASLD OR "fatty liver")',
    },
    {
        "id": "gut_brain_axis_neuropsychiatric",
        "terms": '(Parkinson OR Alzheimer OR depression OR "gut-brain axis")',
    },
    {
        "id": "amr_resistome",
        "terms": '("antimicrobial resistance" OR AMR OR resistome)',
    },
    {
        "id": "cazyme_dbcan",
        "terms": '("CAZyme" OR dbCAN OR "carbohydrate-active enzyme")',
    },
    {
        "id": "scfa_butyrate",
        "terms": '("short-chain fatty acid" OR SCFA OR butyrate)',
    },
    {
        "id": "bile_acid_metabolism",
        "terms": '("bile acid metabolism" OR "bile acids")',
    },
    {
        "id": "mag_quality_mimag",
        "terms": '("MIMAG" OR "minimum information about a metagenome-assembled genome") AND ("MAG quality" OR completeness OR contamination OR standards)',
    },
    {
        "id": "crispr_spacer_host",
        "terms": '(CRISPR AND spacer AND ("host prediction" OR "host assignment" OR phage))',
    },
    {
        "id": "eukfinder_fungal_mag",
        "terms": '("Eukfinder" OR EukFinder) AND (fungal OR eukaryotic OR binning OR MAG)',
    },
    {
        "id": "eggnog_functional_annotation",
        "terms": '("eggNOG-mapper" OR eggNOG OR "eggNOG mapper") AND ("functional annotation" OR COG OR KEGG OR GO)',
    },
    {
        "id": "kegg_pathway_gut",
        "terms": '(KEGG AND pathway AND gut AND metagenomics)',
    },
    {
        "id": "fastp_kneaddata_qc",
        "terms": '("fastp" OR KneadData) AND ("quality control" OR preprocessing OR "host removal")',
    },
    {
        "id": "dastool_bin_refinement",
        "terms": '("DAS Tool" OR DAS_Tool OR DASTool) AND ("bin refinement" OR binning OR integration)',
    },
    {
        "id": "vrhyme_vmag_binning",
        "terms": '(vRhyme OR "viral MAG" OR vMAG) AND (binning OR "genome binning" OR "multi-sample" OR metagenome)',
    },
    {
        "id": "vcontact3_phage_taxonomy",
        "terms": '(vConTACT OR vConTACT2 OR vConTACT3) AND ("gene sharing" OR "phage taxonomy" OR classification OR network)',
    },
    {
        "id": "bacphlip_lifestyle_prediction",
        "terms": '(BACPHLIP OR "lytic" OR "lysogenic") AND ("lifestyle prediction" OR "phage lifestyle" OR "temperate phage" OR virome)',
    },
    {
        "id": "gut_virome_disease",
        "terms": '("gut virome" OR "gut phageome" OR bacteriophage) AND (disease OR IBD OR CRC OR dysbiosis OR diversity)',
    },
    {
        "id": "phage_bacteria_interaction",
        "terms": '(phage OR bacteriophage) AND bacteria AND (coevolution OR interaction OR "gut microbiome" OR infection OR predation)',
    },
    {
        "id": "fungal_cazyme_gut",
        "terms": '(fungal OR fungi OR mycobiome) AND (CAZyme OR "carbohydrate-active" OR "glycoside hydrolase") AND (gut OR metagenomics)',
    },
    {
        "id": "antifungal_resistance_gut",
        "terms": '("antifungal resistance" OR "antifungal AMR" OR azole OR echinocandin) AND (Candida OR Aspergillus OR gut OR metagenomics)',
    },
    {
        "id": "gut_candida_colonization",
        "terms": '(Candida AND gut AND (colonization OR dysbiosis OR disease OR "microbiome" OR IBD OR CRC))',
    },
    {
        "id": "fungi_bacteria_crossdomain",
        "terms": '(fungi OR mycobiome) AND bacteria AND ("cross-kingdom" OR "interkingdom" OR "co-occurrence" OR interaction OR gut)',
    },
    {
        "id": "viral_dark_matter_phold",
        "terms": '("viral dark matter" OR PHOLD OR "phage annotation" OR VOG OR VOGDB) AND ("structural protein" OR "unknown function" OR metagenomics)',
    },
]


def warn(message):
    print(f"[europepmc_search] WARNING {message}", file=sys.stderr)


def _normalize_pmcid(value):
    if value is None:
        return ""
    text = str(value).strip()
    if not text:
        return ""
    if text.upper().startswith("PMC"):
        return text.upper()
    if text.isdigit():
        return f"PMC{text}"
    match = re.search(r"PMC\d+", text, flags=re.I)
    return match.group(0).upper() if match else text


def _normalize_year(value):
    if value is None:
        return ""
    text = str(value).strip()
    match = re.search(r"(19|20)\d{2}", text)
    return match.group(0) if match else text


def _normalize_authors(result):
    authors = []
    author_items = ((result.get("authorList") or {}).get("author") or [])
    for item in author_items:
        if isinstance(item, dict):
            name = item.get("fullName") or item.get("collectiveName") or item.get("lastName")
            if name and str(name).strip():
                authors.append(str(name).strip())
        elif str(item).strip():
            authors.append(str(item).strip())
    if authors:
        return authors

    author_string = str(result.get("authorString") or "").strip()
    if not author_string:
        return []
    return [part.strip() for part in author_string.split(",") if part.strip()]


def _as_int(value, default=0):
    try:
        return int(value)
    except Exception:
        return default


def _has_fulltext(result):
    if _normalize_pmcid(result.get("pmcid")):
        return True
    if str(result.get("inPMC") or "").upper() == "Y":
        return True
    full_text_ids = ((result.get("fullTextIdList") or {}).get("fullTextId") or [])
    return bool(full_text_ids)


def _normalize_record(result):
    pmid = str(result.get("pmid") or result.get("id") or "").strip()
    if not pmid or not re.search(r"\d", pmid):
        return None

    journal_info = result.get("journalInfo") or {}
    journal = ((journal_info.get("journal") or {}).get("title") or result.get("journalTitle") or "").strip()

    return {
        "pmid": pmid,
        "pmcid": _normalize_pmcid(result.get("pmcid")),
        "title": str(result.get("title") or "").strip(),
        "year": _normalize_year(result.get("pubYear") or journal_info.get("yearOfPublication") or ""),
        "journal": journal,
        "authors": _normalize_authors(result),
        "cited_by": _as_int(result.get("citedByCount"), default=0),
        "has_fulltext": _has_fulltext(result),
    }


def _build_journal_clause():
    return "(" + " OR ".join([f'JOURNAL:"{journal}"' for journal in JOURNAL_WHITELIST]) + ")"


def _build_query(topic_terms):
    return f"({topic_terms}) AND {MICROBIOME_CONTEXT} AND {METHODS_PRIORITY} AND {_build_journal_clause()} AND {YEAR_RANGE}"


SEARCH_QUERIES = [
    {"id": item["id"], "query": _build_query(item["terms"])}
    for item in SEARCH_TOPICS
]


class EuropePMCClient:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": USER_AGENT})
        self._last_request_time = 0.0

    def _wait_for_rate_limit(self):
        elapsed = time.monotonic() - self._last_request_time
        if elapsed < RATE_LIMIT_SECONDS:
            time.sleep(RATE_LIMIT_SECONDS - elapsed)

    def request(self, params):
        attempts = MAX_RETRIES + 1
        for attempt in range(attempts):
            self._wait_for_rate_limit()
            try:
                response = self.session.get(BASE_URL, params=params, timeout=REQUEST_TIMEOUT)
                self._last_request_time = time.monotonic()
                if response.status_code >= 400:
                    raise RuntimeError(f"http {response.status_code}")
                return response.json()
            except Exception as exc:
                if attempt >= MAX_RETRIES:
                    warn(f"request failed ({exc})")
                    return None
                warn(f"request failed ({exc}), retrying in {RETRY_INTERVAL_SECONDS}s")
                time.sleep(RETRY_INTERVAL_SECONDS)
        return None


def search_europepmc(query, client, max_results=50):
    rows = []
    seen = set()
    cursor_mark = "*"

    while len(rows) < max_results:
        payload = client.request(
            {
                "query": f"({query}) AND OPEN_ACCESS:Y",
                "resultType": "core",
                "pageSize": PAGE_SIZE,
                "format": "json",
                "sort": "cited desc",
                "cursorMark": cursor_mark,
            }
        )
        if payload is None:
            break

        results = ((payload.get("resultList") or {}).get("result") or [])
        if not results:
            break

        for result in results:
            record = _normalize_record(result)
            if record is None:
                continue
            unique_id = record["pmid"] or record["pmcid"]
            if unique_id in seen:
                continue
            seen.add(unique_id)
            rows.append(record)
            if len(rows) >= max_results:
                break

        next_cursor = str(payload.get("nextCursorMark") or "").strip()
        if not next_cursor or next_cursor == cursor_mark:
            break
        cursor_mark = next_cursor

    return rows[:max_results]


def search_all_queries(output_dir, max_per_query=50) -> int:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    results_path = output_path / "search_results.jsonl"
    timestamp_path = output_path / "last_update.txt"

    client = EuropePMCClient()
    merged = {}

    for item in SEARCH_QUERIES:
        query_records = search_europepmc(item["query"], client, max_results=max(1, int(max_per_query)))
        for record in query_records:
            pmid = record["pmid"]
            if pmid not in merged:
                merged[pmid] = dict(record)
                merged[pmid]["query_ids"] = [item["id"]]
                merged[pmid]["queries"] = [item["query"]]
                continue

            if item["id"] not in merged[pmid]["query_ids"]:
                merged[pmid]["query_ids"].append(item["id"])
            if item["query"] not in merged[pmid]["queries"]:
                merged[pmid]["queries"].append(item["query"])
            if not merged[pmid].get("pmcid") and record.get("pmcid"):
                merged[pmid]["pmcid"] = record["pmcid"]
            merged[pmid]["cited_by"] = max(
                _as_int(merged[pmid].get("cited_by"), default=0),
                _as_int(record.get("cited_by"), default=0),
            )
            merged[pmid]["has_fulltext"] = bool(
                merged[pmid].get("has_fulltext") or record.get("has_fulltext")
            )

    ordered_records = sorted(
        merged.values(),
        key=lambda row: (
            _as_int(row.get("cited_by"), default=0),
            row.get("year", ""),
            row.get("pmid", ""),
        ),
        reverse=True,
    )

    lines = [json.dumps(record, ensure_ascii=False) for record in ordered_records]
    results_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    timestamp_path.write_text(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), encoding="utf-8")
    return len(ordered_records)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="europepmc_search_") as temp_dir:
        total = search_all_queries(temp_dir, max_per_query=3)
        results_path = Path(temp_dir) / "search_results.jsonl"
        print(f"total_results={total}")
        if results_path.exists():
            for line in results_path.read_text(encoding="utf-8").splitlines()[:3]:
                print(line)
