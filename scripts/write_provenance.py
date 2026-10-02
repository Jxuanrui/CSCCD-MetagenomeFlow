#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import re
import sys
from collections.abc import Callable, Iterable
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import yaml


MetricsExtractor = Callable[[Path, str], dict[str, Any]]

REQUIRED_FIELDS = (
    "wf_run_id",
    "step_id",
    "tool",
    "tool_version",
    "user",
    "sample_id",
    "workdir",
    "repo",
    "inputs",
    "outputs",
    "params",
    "metrics",
    "started_at",
    "duration_sec",
    "exit_code",
    "status",
    "error_message",
    "enriched_into_skill",
)


def eprint(message: str) -> None:
    print(message, file=sys.stderr)


def warn(message: str) -> None:
    eprint(f"Warning: {message}")


def error(message: str) -> None:
    eprint(f"Error: {message}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a provenance record for a CSCCD-MetagenomeFlow workflow step."
    )
    parser.add_argument("--step-id", required=True)
    parser.add_argument("--sample", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--exit-code", required=True, type=int)
    parser.add_argument("--duration-sec", required=True, type=int)
    parser.add_argument("--repo")
    parser.add_argument("--started-at")
    parser.add_argument("--user", dest="user_name")
    parser.add_argument("--threads", type=int)
    parser.add_argument("--params", nargs="+", action="append", default=[])
    parser.add_argument("--metrics", nargs="+", action="append", default=[])
    parser.add_argument("--auto-extract", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args(argv)


def default_repo() -> Path:
    return Path(__file__).resolve().parent.parent


def flatten_key_value_groups(groups: list[list[str]]) -> list[str]:
    items: list[str] = []
    for group in groups:
        items.extend(group)
    return items


def parse_typed_value(raw_value: str) -> Any:
    try:
        return yaml.safe_load(raw_value)
    except yaml.YAMLError:
        return raw_value


def parse_key_value_pairs(items: Iterable[str], label: str) -> dict[str, Any]:
    parsed: dict[str, Any] = {}
    for item in items:
        if "=" not in item:
            raise ValueError(f"{label} entry must be KEY=VALUE: {item}")
        key, value = item.split("=", 1)
        key = key.strip()
        if not key:
            raise ValueError(f"{label} key cannot be empty: {item}")
        parsed[key] = parse_typed_value(value)
    return parsed


def parse_started_at(raw_started_at: str | None, duration_sec: int) -> datetime:
    if raw_started_at:
        started_at = datetime.fromisoformat(raw_started_at)
        if started_at.tzinfo is None:
            started_at = started_at.astimezone()
        return started_at
    return datetime.now().astimezone() - timedelta(seconds=duration_sec)


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"YAML root must be a mapping: {path}")
    return data


def substitute_path_pattern(path_pattern: str, workdir: Path, sample: str) -> str:
    return (
        path_pattern.replace("{workdir}", str(workdir)).replace("{sample}", sample)
    )


def build_io_map(
    entries: Any,
    workdir: Path,
    sample: str,
) -> dict[str, str]:
    resolved: dict[str, str] = {}
    if not isinstance(entries, list):
        return resolved

    for entry in entries:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name")
        path_pattern = entry.get("path_pattern")
        if not isinstance(name, str) or not isinstance(path_pattern, str):
            continue
        resolved[name] = substitute_path_pattern(path_pattern, workdir, sample)
    return resolved


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def round4(value: float) -> float:
    return round(value, 4)


def first_existing(paths: Iterable[Path]) -> Path | None:
    for path in paths:
        if path.exists():
            return path
    return None


def parse_float(text: str) -> float:
    return float(text.strip())


def parse_int(text: str) -> int:
    return int(float(text.strip()))


def extract_fastp_metrics(workdir: Path, sample: str) -> dict[str, Any]:
    report_path = workdir / "result" / "fastp" / sample / f"{sample}.json"
    if not report_path.exists():
        warn(f"fastp report not found: {report_path}")
        return {}

    try:
        payload = read_json(report_path)
        before = int(payload["summary"]["before_filtering"]["total_reads"])
        after = int(payload["summary"]["after_filtering"]["total_reads"])
        return {
            "total_reads_before": before,
            "total_reads_after": after,
            "pass_rate": round4(after / before) if before else 0.0,
            "q30_rate": payload["summary"]["after_filtering"]["q30_rate"],
            "gc_content": payload["summary"]["after_filtering"]["gc_content"],
        }
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        warn(f"failed to parse fastp report {report_path}: {exc}")
        return {}


def parse_kneaddata_count_table(path: Path) -> dict[str, Any]:
    metrics: dict[str, Any] = {}
    with path.open("r", encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter="\t")
        for row in reader:
            if len(row) < 2:
                continue
            key = row[0].strip().lower().replace(" ", "_")
            value = row[1].strip()
            if "input" in key and "pair" in key:
                metrics["input_reads_per_mate"] = parse_int(value)
            elif "output" in key and "pair" in key:
                metrics["output_reads_per_mate"] = parse_int(value)
    if (
        "input_reads_per_mate" in metrics
        and "output_reads_per_mate" in metrics
        and metrics["input_reads_per_mate"] > 0
    ):
        metrics["host_removal_rate"] = round4(
            1 - (metrics["output_reads_per_mate"] / metrics["input_reads_per_mate"])
        )
    return metrics


def parse_kneaddata_log(path: Path) -> dict[str, Any]:
    input_reads: int | None = None
    output_reads: int | None = None
    contaminated_reads: int | None = None

    raw_pair_pattern = re.compile(r"READ COUNT: raw pair1 .*?: ([0-9.]+)")
    final_pair_pattern = re.compile(r"READ COUNT: final pair1 .*?: ([0-9.]+)")
    contaminated_pattern = re.compile(r"Final contaminated pair.*?:\s*([0-9.]+)")

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if input_reads is None:
                match = raw_pair_pattern.search(line)
                if match:
                    input_reads = parse_int(match.group(1))
                    continue
            if output_reads is None:
                match = final_pair_pattern.search(line)
                if match:
                    output_reads = parse_int(match.group(1))
                    continue
            if contaminated_reads is None:
                match = contaminated_pattern.search(line)
                if match:
                    contaminated_reads = parse_int(match.group(1))

    metrics: dict[str, Any] = {}
    if input_reads is not None:
        metrics["input_reads_per_mate"] = input_reads
    if output_reads is not None:
        metrics["output_reads_per_mate"] = output_reads
    if "input_reads_per_mate" in metrics and "output_reads_per_mate" in metrics:
        input_value = metrics["input_reads_per_mate"]
        output_value = metrics["output_reads_per_mate"]
        if input_value > 0:
            metrics["host_removal_rate"] = round4(1 - (output_value / input_value))
    elif contaminated_reads is not None and input_reads:
        metrics["host_removal_rate"] = round4(contaminated_reads / input_reads)
    return metrics


def extract_kneaddata_metrics(workdir: Path, sample: str) -> dict[str, Any]:
    sample_dir = workdir / "result" / "kneaddata" / sample
    table_path = sample_dir / "kneaddata_read_count_table.tsv"
    if table_path.exists():
        try:
            return parse_kneaddata_count_table(table_path)
        except (OSError, ValueError, csv.Error) as exc:
            warn(f"failed to parse KneadData count table {table_path}: {exc}")

    log_candidates = sorted(sample_dir.glob("*.log"))
    if not log_candidates:
        warn(f"KneadData metrics source not found under: {sample_dir}")
        return {}

    metrics: dict[str, Any] = {}
    for log_path in log_candidates:
        try:
            metrics.update(parse_kneaddata_log(log_path))
        except OSError as exc:
            warn(f"failed to read KneadData log {log_path}: {exc}")
    if not metrics:
        warn(f"could not extract KneadData metrics from logs in: {sample_dir}")
    return metrics


def deepest_rank(clade_name: str) -> str:
    parts = [part for part in clade_name.split("|") if part]
    if not parts:
        return ""
    return parts[-1]


def extract_metaphlan_metrics(workdir: Path, sample: str) -> dict[str, Any]:
    profile_path = workdir / "result" / "metaphlan4" / sample / f"{sample}_profile.txt"
    if not profile_path.exists():
        warn(f"MetaPhlAn profile not found: {profile_path}")
        return {}

    counts = {
        "n_species": 0,
        "n_genus": 0,
        "total_taxa": 0,
    }

    try:
        with profile_path.open("r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("UNCLASSIFIED"):
                    continue
                fields = line.split("\t")
                if not fields:
                    continue
                counts["total_taxa"] += 1
                rank = deepest_rank(fields[0])
                if rank.startswith("g__"):
                    counts["n_genus"] += 1
                elif rank.startswith("s__"):
                    counts["n_species"] += 1
    except OSError as exc:
        warn(f"failed to read MetaPhlAn profile {profile_path}: {exc}")
        return {}
    return counts


def extract_humann_metrics(workdir: Path, sample: str) -> dict[str, Any]:
    path = workdir / "result" / "humann3" / sample / f"{sample}_pathabundance.tsv"
    if not path.exists():
        warn(f"HUMAnN pathabundance file not found: {path}")
        return {}

    n_pathways = 0
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for line_number, line in enumerate(handle):
                if line_number == 0 or not line.strip():
                    continue
                if "UNMAPPED" in line or "UNINTEGRATED" in line or "|" in line:
                    continue
                n_pathways += 1
    except OSError as exc:
        warn(f"failed to read HUMAnN pathabundance file {path}: {exc}")
        return {}
    return {"n_pathways": n_pathways}


def extract_kraken2_metrics(workdir: Path, sample: str) -> dict[str, Any]:
    candidates = (
        workdir / "result" / "kraken2" / sample / f"{sample}_report.txt",
        workdir / "result" / "kraken2" / sample / f"{sample}.report",
    )
    report_path = first_existing(candidates)
    if report_path is None:
        warn(f"Kraken2 report not found for sample {sample}")
        return {}

    total_count = 0
    n_species = 0
    pct_classified: float | None = None

    try:
        with report_path.open("r", encoding="utf-8", errors="replace") as handle:
            reader = csv.reader(handle, delimiter="\t")
            for row_index, row in enumerate(reader):
                if len(row) < 4:
                    continue
                try:
                    pct = float(row[0].strip())
                    clade_count = parse_int(row[1])
                    direct_count = parse_int(row[2])
                except ValueError:
                    continue
                rank_code = row[3].strip().lower()
                total_count += clade_count
                if row_index == 0:
                    pct_classified = pct
                if rank_code == "s" and direct_count > 0:
                    n_species += 1
        metrics: dict[str, Any] = {"n_species": n_species}
        if pct_classified is not None:
            metrics["pct_classified"] = round4(pct_classified)
        return metrics
    except OSError as exc:
        warn(f"failed to read Kraken2 report {report_path}: {exc}")
        return {}


def compute_n50(lengths: list[int]) -> int:
    if not lengths:
        return 0
    total_bp = sum(lengths)
    half = total_bp / 2
    running = 0
    for length in sorted(lengths, reverse=True):
        running += length
        if running >= half:
            return length
    return 0


def extract_megahit_metrics(workdir: Path, sample: str) -> dict[str, Any]:
    candidates = (
        workdir / "result" / "megahit" / sample / "final.contigs.fa",
        workdir / "result" / "assembly" / "megahit" / sample / f"{sample}.contigs.fa",
    )
    contigs_path = first_existing(candidates)
    if contigs_path is None:
        warn(f"MEGAHIT contigs file not found for sample {sample}")
        return {}

    lengths: list[int] = []
    current_length = 0
    try:
        with contigs_path.open("r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                if line.startswith(">"):
                    if current_length:
                        lengths.append(current_length)
                    current_length = 0
                    continue
                current_length += len(line)
        if current_length:
            lengths.append(current_length)
    except OSError as exc:
        warn(f"failed to read contigs file {contigs_path}: {exc}")
        return {}

    return {
        "n_contigs": len(lengths),
        "total_assembly_bp": sum(lengths),
        "n50_bp": compute_n50(lengths),
    }


def extract_metabat2_metrics(workdir: Path, sample: str) -> dict[str, Any]:
    candidates = (
        workdir / "result" / "metabat2" / sample,
        workdir / "result" / "binning" / "metabat2" / sample,
    )
    bin_dir = first_existing(candidates)
    if bin_dir is None:
        warn(f"MetaBAT2 bin directory not found for sample {sample}")
        return {}

    n_bins_raw = sum(1 for path in bin_dir.glob("*.fa") if path.is_file())
    return {"n_bins_raw": n_bins_raw}


def extract_checkm2_metrics(workdir: Path, sample: str) -> dict[str, Any]:
    candidates = (
        workdir / "result" / "checkm2" / sample / "quality_report.tsv",
        workdir / "result" / "binning" / "checkm2" / sample / "quality_report.tsv",
        workdir / "result" / "binning" / "checkm2" / "quality_report.tsv",
    )
    report_path = first_existing(candidates)
    if report_path is None:
        warn(f"CheckM2 quality report not found for sample {sample}")
        return {}

    n_hq_bins = 0
    n_mq_bins = 0
    n_total_bins = 0

    try:
        with report_path.open("r", encoding="utf-8", errors="replace") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            for row in reader:
                try:
                    completeness = float(row["Completeness"])
                    contamination = float(row["Contamination"])
                except (KeyError, TypeError, ValueError) as exc:
                    warn(f"skipping malformed CheckM2 row in {report_path}: {exc}")
                    continue
                n_total_bins += 1
                if completeness >= 90 and contamination <= 5:
                    n_hq_bins += 1
                if completeness >= 50 and contamination <= 10:
                    n_mq_bins += 1
    except OSError as exc:
        warn(f"failed to read CheckM2 report {report_path}: {exc}")
        return {}

    return {
        "n_hq_bins": n_hq_bins,
        "n_mq_bins": n_mq_bins,
        "n_total_bins": n_total_bins,
    }


EXTRACTORS: dict[str, MetricsExtractor] = {
    "01_qc_fastp": extract_fastp_metrics,
    "02_qc_kneaddata": extract_kneaddata_metrics,
    "11_bac_metaphlan4": extract_metaphlan_metrics,
    "13_bac_humann3": extract_humann_metrics,
    "14_bac_kraken2": extract_kraken2_metrics,
    "16_bac_megahit": extract_megahit_metrics,
    "33_bac_metabat2": extract_metabat2_metrics,
    "37_bac_checkm2": extract_checkm2_metrics,
}


def auto_extract_metrics(step_id: str, workdir: Path, sample: str) -> dict[str, Any]:
    extractor = EXTRACTORS.get(step_id)
    if extractor is None:
        return {}
    try:
        return extractor(workdir, sample)
    except Exception as exc:  # noqa: BLE001
        warn(f"unexpected auto-extract failure for {step_id}: {exc}")
        return {}


def path_has_wildcards(path_text: str) -> bool:
    return any(char in path_text for char in "*?[]") or ("{" in path_text and "}" in path_text)


def path_exists(path_text: str) -> bool:
    if path_has_wildcards(path_text):
        glob_pattern = re.sub(r"\{[^}]+\}", "*", path_text)
        return any(glob.iglob(glob_pattern))
    return Path(path_text).exists()


def outputs_exist(outputs: dict[str, str]) -> bool:
    if not outputs:
        return False
    return all(path_exists(path_text) for path_text in outputs.values())


def derive_status(exit_code: int, outputs: dict[str, str]) -> str:
    return "success" if exit_code == 0 and outputs_exist(outputs) else "failed"


def derive_error_message(exit_code: int, status: str, outputs: dict[str, str]) -> str | None:
    if status == "success":
        return None
    if exit_code != 0:
        return f"Step exited with code {exit_code}"
    missing = [name for name, path_text in outputs.items() if not path_exists(path_text)]
    if missing:
        return f"Missing expected outputs: {', '.join(missing)}"
    return "Step did not meet success criteria"


def tool_name_from_skill(skill_card: dict[str, Any], step_id: str) -> str:
    for key in ("tool", "name"):
        value = skill_card.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    warn(f"tool name missing in skill card for {step_id}; using step_id")
    return step_id


def tool_version_from_skill(skill_card: dict[str, Any], step_id: str) -> str:
    for key in ("tool_version", "version"):
        value = skill_card.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    warn(f"tool_version missing in skill card for {step_id}; using 'unknown'")
    return "unknown"


def validate_provenance_record(record: dict[str, Any]) -> None:
    missing = [field for field in REQUIRED_FIELDS if field not in record]
    if missing:
        raise ValueError(f"provenance record missing required fields: {', '.join(missing)}")


def build_provenance_record(
    *,
    step_id: str,
    sample: str,
    workdir: Path,
    repo: Path,
    user_name: str,
    started_at: datetime,
    duration_sec: int,
    exit_code: int,
    inputs: dict[str, str],
    outputs: dict[str, str],
    params: dict[str, Any],
    metrics: dict[str, Any],
    skill_card: dict[str, Any],
) -> dict[str, Any]:
    run_date = started_at.strftime("%Y%m%d")
    status = derive_status(exit_code, outputs)
    record = {
        "wf_run_id": f"{run_date}_{step_id}_{sample}",
        "step_id": step_id,
        "tool": tool_name_from_skill(skill_card, step_id),
        "tool_version": tool_version_from_skill(skill_card, step_id),
        "user": user_name,
        "sample_id": sample,
        "workdir": str(workdir),
        "repo": str(repo),
        "inputs": inputs,
        "outputs": outputs,
        "params": params,
        "metrics": metrics,
        "started_at": started_at.isoformat(),
        "duration_sec": duration_sec,
        "exit_code": exit_code,
        "status": status,
        "error_message": derive_error_message(exit_code, status, outputs),
        "enriched_into_skill": False,
    }
    validate_provenance_record(record)
    return record


def output_filename(started_at: datetime, step_id: str, sample: str) -> str:
    return f"{started_at.strftime('%Y%m%d')}_{step_id}_{sample}.json"


def write_record(path: Path, record: dict[str, Any], force: bool) -> None:
    if path.exists() and not force:
        raise FileExistsError(f"provenance file already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def resolve_repo(raw_repo: str | None) -> Path:
    return Path(raw_repo).expanduser().resolve() if raw_repo else default_repo()


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        params = parse_key_value_pairs(flatten_key_value_groups(args.params), "params")
        metrics_overrides = parse_key_value_pairs(
            flatten_key_value_groups(args.metrics), "metrics"
        )
    except ValueError as exc:
        error(str(exc))
        return 1

    repo = resolve_repo(args.repo)
    workdir = Path(args.workdir).expanduser().resolve()
    started_at = parse_started_at(args.started_at, args.duration_sec)
    user_name = args.user_name or os.environ.get("USER") or "unknown"

    skill_path = repo / "agents" / "skills" / f"{args.step_id}.yaml"
    if not skill_path.exists():
        error(f"skill card not found: {skill_path}")
        return 1

    try:
        skill_card = load_yaml(skill_path)
    except (OSError, ValueError, yaml.YAMLError) as exc:
        error(f"failed to load skill card {skill_path}: {exc}")
        return 1

    if args.threads is not None:
        params["threads"] = args.threads

    inputs = build_io_map(skill_card.get("inputs"), workdir, args.sample)
    outputs = build_io_map(skill_card.get("outputs"), workdir, args.sample)

    metrics = auto_extract_metrics(args.step_id, workdir, args.sample) if args.auto_extract else {}
    metrics.update(metrics_overrides)

    record = build_provenance_record(
        step_id=args.step_id,
        sample=args.sample,
        workdir=workdir,
        repo=repo,
        user_name=user_name,
        started_at=started_at,
        duration_sec=args.duration_sec,
        exit_code=args.exit_code,
        inputs=inputs,
        outputs=outputs,
        params=params,
        metrics=metrics,
        skill_card=skill_card,
    )

    filename = output_filename(started_at, args.step_id, args.sample)
    output_path = repo / "agents" / "provenance" / filename

    if args.dry_run:
        print(json.dumps(record, indent=2, ensure_ascii=False))
        return 0

    try:
        write_record(output_path, record, args.force)
    except FileExistsError as exc:
        error(str(exc))
        return 1
    except OSError as exc:
        error(f"failed to write provenance file {output_path}: {exc}")
        return 1

    relative_path = Path("agents") / "provenance" / filename
    print(f"Written: {relative_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
