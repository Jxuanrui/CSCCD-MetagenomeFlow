#!/usr/bin/env python3
"""mgx-vis core: detection + orchestration for metagenomic figure rendering.

This module NEVER plots anything itself. It (1) scans a project workdir for
chart-input tables produced by the stable orbit-0 pipeline, (2) re-invokes the
orbit-0 wrapper scripts to (re)render figures (injecting
MGX_FIGURE_FORMATS=pdf,png for the parallel R-backend track), and (3) prepares
mining-overview TSVs and delegates their drawing to mcp/vis/render_mining.R
(owned by a parallel track; its absence is reported, never a crash).

Pure stdlib. Importing this module has no side effects.
"""

from __future__ import annotations

import glob
import json
import os
import sqlite3
import subprocess
import tempfile
import time

DIMENSIONS = ("bacteria", "virus", "fungi")
CHART_FAMILIES = (
    "composition_bar",
    "composition_heatmap",
    "alpha_box",
    "pcoa_scatter",
    "diff_lollipop",
    "network_graph",
    "lefse_bar",
)
MINING_CHARTS = ("mining_attrs", "mining_overlap")
MINING_ATTR_COLUMNS = ("body_site", "disease", "platform", "country")
RELABUND_PRIORITY = ("species", "genus", "family", "phylum", "order", "class", "domain")
TOP_N = 12
FIGURE_CAP = 50
INPUT_CAP = 8
LOG_TAIL_CHARS = 2000
DEFAULT_TIMEOUT = 1800
MINING_TIMEOUT = 600
FIGURE_FORMATS = "pdf,png"

HINTS = (
    "Additional reusable figure tracks: figure-library MCP (FigureYa 39-module "
    "catalog: search/preview/materialize) and tools/Paper2Agent (literature "
    "figure reproduction)."
)


def find_repo_root(start: str | None = None) -> str:
    """Walk up from `start` (default: this file) to the dir holding mcp/ and scripts/."""
    current = os.path.dirname(os.path.abspath(os.path.expanduser(start or __file__)))
    while True:
        if os.path.isdir(os.path.join(current, "mcp")) and os.path.isdir(
            os.path.join(current, "scripts")
        ):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            raise RuntimeError(
                "repository root not found: no ancestor of "
                f"{start or __file__} contains both mcp/ and scripts/"
            )
        current = parent


# ---------------------------------------------------------------------------
# scan
# ---------------------------------------------------------------------------


def _stat_root(workdir: str) -> str:
    return os.path.join(workdir, "result", "stat")


def _detect_metadata(workdir: str) -> str | None:
    meta = os.path.join(_stat_root(workdir), "metadata.tsv")
    return meta if os.path.isfile(meta) else None


def _family_inputs(workdir: str) -> dict[str, list[str]]:
    """Map each chart family to the input tables that exist for it (abs paths)."""
    root = _stat_root(workdir)
    composition: list[str] = []
    for dim in DIMENSIONS:
        composition.extend(
            sorted(glob.glob(os.path.join(root, dim, "abundance", "*_relabund.tsv")))
        )
    alpha = [
        os.path.join(root, dim, "diversity", "alpha_diversity.tsv")
        for dim in DIMENSIONS
        if os.path.isfile(os.path.join(root, dim, "diversity", "alpha_diversity.tsv"))
    ]
    pcoa = [
        os.path.join(root, dim, "diversity", "pcoa_coordinates.tsv")
        for dim in DIMENSIONS
        if os.path.isfile(os.path.join(root, dim, "diversity", "pcoa_coordinates.tsv"))
    ]
    diff = [
        os.path.join(root, dim, "differential", "wilcox_results.tsv")
        for dim in DIMENSIONS
        if os.path.isfile(os.path.join(root, dim, "differential", "wilcox_results.tsv"))
    ]
    network_path = os.path.join(root, "network", "cross_bac_vir_nodes.tsv")
    network = [network_path] if os.path.isfile(network_path) else []
    lefse: list[str] = []
    for dim in DIMENSIONS:
        lefse.extend(
            sorted(glob.glob(os.path.join(root, dim, "lefse", "*", "lefse_results.tsv")))
        )
    return {
        "composition_bar": composition,
        "composition_heatmap": list(composition),
        "alpha_box": alpha,
        "pcoa_scatter": pcoa,
        "diff_lollipop": diff,
        "network_graph": network,
        "lefse_bar": lefse,
    }


def _existing_figures(workdir: str, cap: int = FIGURE_CAP) -> tuple[int, list[str]]:
    root = _stat_root(workdir)
    found: list[str] = []
    for pattern in ("*.pdf", "*.png"):
        found.extend(glob.glob(os.path.join(root, "**", pattern), recursive=True))
    relative = sorted(os.path.relpath(path, workdir) for path in found if os.path.isfile(path))
    return len(relative), relative[:cap]


def scan(workdir: str) -> dict:
    """Describe chart readiness for a project workdir (detection only, no plotting)."""
    workdir = os.path.abspath(os.path.expanduser(workdir))
    inputs = _family_inputs(workdir)
    charts = {}
    for family in CHART_FAMILIES:
        paths = inputs[family]
        charts[family] = {
            "available": bool(paths),
            "input_count": len(paths),
            "inputs": [os.path.relpath(p, workdir) for p in paths[:INPUT_CAP]],
        }
    total, files = _existing_figures(workdir)
    return {
        "workdir": workdir,
        "metadata": (
            os.path.relpath(_detect_metadata(workdir), workdir)
            if _detect_metadata(workdir)
            else None
        ),
        "charts": charts,
        "figures": {"count": total, "files": files},
        "hints": HINTS,
    }


# ---------------------------------------------------------------------------
# render (orbit-0 delegation)
# ---------------------------------------------------------------------------


def _decode_stream(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def _tail(text: str, limit: int = LOG_TAIL_CHARS) -> str:
    return (text or "").strip()[-limit:]


def _fresh_figures(workdir: str, since: float, cap: int = FIGURE_CAP) -> list[str]:
    """PDF/PNG files under result/stat/ modified at/after `since` (run window)."""
    root = _stat_root(workdir)
    out: list[str] = []
    for pattern in ("*.pdf", "*.png"):
        for path in glob.glob(os.path.join(root, "**", pattern), recursive=True):
            try:
                if os.path.getmtime(path) >= since - 1.0:
                    out.append(os.path.relpath(path, workdir))
            except OSError:
                continue
    return sorted(out)[:cap]


def _preferred_relabund(files: list[str]) -> tuple[str, str]:
    """Pick (path, feature_type) preferring species > genus > family > ..."""
    by_type: dict[str, str] = {}
    for path in files:
        stem = os.path.basename(path)
        if stem.endswith("_relabund.tsv"):
            by_type[stem[: -len("_relabund.tsv")]] = path
    for rank in RELABUND_PRIORITY:
        if rank in by_type:
            return by_type[rank], rank
    fallback = sorted(by_type.items())[0]
    return fallback[1], fallback[0]


def _lefse_job(workdir: str) -> tuple[str, str, str, str] | None:
    """Return (abundance_file, out_dir, dimension, feature_type) for 99b_lefse.sh.

    Prefers re-rendering into an existing result subdir (keeps type/layout),
    else derives type from the preferred relabund table.
    """
    root = _stat_root(workdir)
    for dim in DIMENSIONS:
        relabund = sorted(glob.glob(os.path.join(root, dim, "abundance", "*_relabund.tsv")))
        if not relabund:
            continue
        existing = sorted(glob.glob(os.path.join(root, dim, "lefse", "*", "lefse_results.tsv")))
        if existing:
            out_dir = os.path.dirname(existing[0])
            feature_type = os.path.basename(out_dir)
            preferred = os.path.join(root, dim, "abundance", f"{feature_type}_relabund.tsv")
            abundance = preferred if os.path.isfile(preferred) else _preferred_relabund(relabund)[0]
            return abundance, out_dir, dim, feature_type
        abundance, feature_type = _preferred_relabund(relabund)
        return abundance, os.path.join(root, dim, "lefse", feature_type), dim, feature_type
    return None


def render(
    workdir: str,
    charts: list[str] | None = None,
    group_col: str | None = None,
    force: bool = False,
    timeout: int = DEFAULT_TIMEOUT,
    dry_run: bool = False,
    threads: int | None = None,
) -> dict:
    """(Re)render chart families by delegating to orbit-0 wrapper scripts.

    One subprocess per script group, sequential (they share the workdir).
    Every subprocess inherits os.environ plus MGX_FIGURE_FORMATS=pdf,png and
    GROUP_COL (94 honors GROUP_COL from env; 91/92/93 also receive -g).
    """
    workdir = os.path.abspath(os.path.expanduser(workdir))
    repo = find_repo_root()
    available = _family_inputs(workdir)
    if charts is None:
        charts = [family for family, paths in available.items() if paths]
    charts = list(charts)
    unknown = [c for c in charts if c not in CHART_FAMILIES]
    if unknown:
        raise ValueError(
            f"unknown chart name(s): {unknown}; valid chart families: {list(CHART_FAMILIES)}"
        )
    group_col = group_col or "group"
    nthreads = threads or min(8, os.cpu_count() or 2)
    metadata = _detect_metadata(workdir)
    extra = ["--force"] if force else []
    env = dict(os.environ, MGX_FIGURE_FORMATS=FIGURE_FORMATS, GROUP_COL=group_col)

    scripts = repo.rstrip("/") + "/scripts/"
    cmd_94 = ["bash", scripts + "94_stat_visualization.sh", "-w", workdir, "-r", repo]
    if metadata:
        cmd_94 += ["-m", metadata]
    cmd_94 += extra
    groups: list[tuple[tuple[str, ...], list[str] | None]] = [
        # (chart families sharing one subprocess, command; None => metadata missing)
        (("composition_bar", "composition_heatmap"), cmd_94),
        (
            ("alpha_box", "pcoa_scatter"),
            _needs_metadata(metadata, ["bash", scripts + "91_stat_diversity.sh", "-w", workdir, "-r", repo, "-t", str(nthreads), "-m", metadata, "-g", group_col], extra),
        ),
        (
            ("diff_lollipop",),
            _needs_metadata(metadata, ["bash", scripts + "92_stat_differential.sh", "-w", workdir, "-r", repo, "-t", str(nthreads), "-m", metadata, "-g", group_col], extra),
        ),
        (
            ("network_graph",),
            _needs_metadata(metadata, ["bash", scripts + "93_stat_cooccurrence.sh", "-w", workdir, "-r", repo, "-t", str(nthreads), "-m", metadata, "-g", group_col, "-n", "cross_bac_vir"], extra),
        ),
    ]

    lefse = None
    job = _lefse_job(workdir)
    if job is not None and metadata:
        abundance, out_dir, dim, feature_type = job
        lefse = [
            "bash",
            scripts + "99b_lefse.sh",
            "-i",
            abundance,
            "-m",
            metadata,
            "-o",
            out_dir,
            "-d",
            dim,
            "-y",
            feature_type,
        ] + extra

    result = {
        "workdir": workdir,
        "repo": repo,
        "metadata": os.path.relpath(metadata, workdir) if metadata else None,
        "group_col": group_col,
        "force": force,
        "dry_run": dry_run,
        "env": {"MGX_FIGURE_FORMATS": FIGURE_FORMATS, "GROUP_COL": group_col},
        "charts": {},
    }

    def _record(families, **entry):
        for family in families:
            result["charts"][family] = dict(entry)

    for families, command in groups:
        chosen = [f for f in families if f in charts]
        if not chosen:
            continue
        if not any(available[f] for f in chosen):
            _record(
                chosen,
                status="missing_input",
                command=command or [],
                note="no input tables detected under result/stat/ for this chart family; run the upstream pipeline first",
            )
            continue
        if command is None:
            _record(
                chosen,
                status="missing_metadata",
                note="this orbit-0 script requires a metadata CSV; expected result/stat/metadata.tsv",
            )
            continue
        _run_group(chosen, command, workdir, env, timeout, dry_run, result, _record)

    if "lefse_bar" in charts:
        if job is None:
            result["charts"]["lefse_bar"] = {
                "status": "missing_input",
                "note": "no result/stat/{dim}/abundance/*_relabund.tsv found for any dimension; LEfSe needs an abundance table",
            }
        elif lefse is None:
            result["charts"]["lefse_bar"] = {
                "status": "missing_metadata",
                "note": "99b_lefse.sh requires a metadata CSV; expected result/stat/metadata.tsv",
            }
        else:
            _run_group(["lefse_bar"], lefse, workdir, env, timeout, dry_run, result, _record)

    return result


def _needs_metadata(metadata: str | None, command: list[str], extra: list[str]) -> list[str] | None:
    return command + extra if metadata else None


def _run_group(families, command, workdir, env, timeout, dry_run, result, _record):
    script = command[1] if len(command) > 1 else ""
    if dry_run:
        _record(families, status="dry_run", command=command, script=script)
        return
    if not os.path.isfile(script):
        _record(families, status="script_missing", command=command, script=script,
                note="orbit-0 script not found; check repository layout")
        return
    start = time.time()
    try:
        proc = subprocess.run(
            command, cwd=workdir, env=env, capture_output=True, text=True, timeout=timeout
        )
        exit_code, timed_out = proc.returncode, False
        combined = _decode_stream(proc.stdout) + "\n" + _decode_stream(proc.stderr)
    except subprocess.TimeoutExpired as exc:
        exit_code, timed_out = None, True
        combined = _decode_stream(exc.stdout) + "\n" + _decode_stream(exc.stderr)
    figures = _fresh_figures(workdir, start)
    entry = {
        "command": command,
        "script": script,
        "exit_code": exit_code,
        "duration_s": round(time.time() - start, 1),
        "figures": figures,
    }
    if timed_out:
        entry["status"] = "timeout"
        entry["log_tail"] = _tail(combined)
    elif exit_code == 0:
        entry["status"] = "ok"
    else:
        entry["status"] = "failed"
        entry["log_tail"] = _tail(combined)
    _record(families, **entry)


# ---------------------------------------------------------------------------
# mining (TSV preparation + R renderer delegation)
# ---------------------------------------------------------------------------


def _write_mining_attrs(db_path: str, attrs_tsv: str) -> int:
    """Top-N value counts for body_site/disease/platform/country -> long TSV."""
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        cursor = con.cursor()
        written = 0
        with open(attrs_tsv, "w", encoding="utf-8") as handle:
            handle.write("attribute\tvalue\tcount\n")
            for column in MINING_ATTR_COLUMNS:
                rows = cursor.execute(
                    f"SELECT {column} AS value, COUNT(*) AS n FROM seed_runs "
                    f"WHERE {column} IS NOT NULL AND TRIM({column}) NOT IN ('', 'NA') "
                    f"GROUP BY {column} ORDER BY n DESC, value ASC LIMIT ?",
                    (TOP_N,),
                ).fetchall()
                for value, count in rows:
                    value = " ".join(str(value).split())  # collapse tabs/newlines
                    handle.write(f"{column}\t{value}\t{count}\n")
                    written += 1
        return written
    finally:
        con.close()


def _parse_members(raw: str) -> list[str]:
    """Parse seed_sources_all membership. Actual DB format is a JSON array
    (e.g. '["cMD3", "Meta2DB"]'); semicolon/comma splitting is the fallback."""
    raw = (raw or "").strip()
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return [str(item).strip() for item in parsed if str(item).strip()]
    except ValueError:
        pass
    parts = raw.replace(";", ",").split(",")
    return [p.strip().strip('[]"\'') for p in parts if p.strip().strip('[]"\'')]


def _overlap_from_db(db_path: str) -> dict:
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT seed_sources_all FROM seed_runs "
            "WHERE seed_sources_all IS NOT NULL AND TRIM(seed_sources_all) != ''"
        ).fetchall()
    finally:
        con.close()
    counts: dict[str, int] = {}
    pairs: dict[tuple[str, str], int] = {}
    triple = 0
    for (raw,) in rows:
        members = sorted(set(_parse_members(raw)))
        for member in members:
            counts[member] = counts.get(member, 0) + 1
        if len(members) >= 3:
            triple += 1
        for i in range(len(members)):
            for j in range(i + 1, len(members)):
                key = (members[i], members[j])
                pairs[key] = pairs.get(key, 0) + 1
    sources = sorted(counts)
    overlap_matrix = {
        f"{a}_and_{b}": pairs.get((a, b), 0)
        for i, a in enumerate(sources)
        for b in sources[i + 1 :]
    }
    return {
        "sources": sources,
        "counts": counts,
        "overlap_matrix": overlap_matrix,
        "all_three": triple,
    }


def _load_overlap(repo: str, db_path: str) -> dict:
    """Prefer mining/seed_summary.json; fall back to computing from the DB."""
    summary_path = os.path.join(repo, "mining", "seed_summary.json")
    data = None
    try:
        with open(summary_path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        data = None
    if isinstance(data, dict) and data.get("sources") and data.get("overlap_matrix"):
        raw_sources = data["sources"]
        sources = [s for s in raw_sources if isinstance(s, str)]
        counts = {
            s: int((d or {}).get("contributed_final_rows") or 0)
            for s, d in raw_sources.items()
            if isinstance(s, str)
        }
        raw_matrix = data.get("overlap_matrix") or {}

        def pair(a: str, b: str) -> int:
            return int(raw_matrix.get(f"{a}_and_{b}", raw_matrix.get(f"{b}_and_{a}", 0)) or 0)

        overlap_matrix = {
            f"{a}_and_{b}": pair(a, b)
            for i, a in enumerate(sources)
            for b in sources[i + 1 :]
        }
        return {
            "sources": sources,
            "counts": counts,
            "overlap_matrix": overlap_matrix,
            "all_three": int(raw_matrix.get("all_three", 0) or 0),
            "origin": "mining/seed_summary.json",
        }
    fallback = _overlap_from_db(db_path)
    fallback["origin"] = "seed_registry.sqlite membership fallback"
    return fallback


def _write_overlap_tables(overlap: dict, overlap_tsv: str, sources_tsv: str) -> None:
    """Write the square overlap matrix and per-source counts.

    overlap.tsv layout is fixed by the mcp/vis/render_mining.R contract: the
    first header cell is BLANK so read.delim takes column 1 as row.names,
    yielding a square numeric matrix (source names as dimnames). The
    seed_summary "all_three" count does not fit a square matrix and is
    reported in the mining() result instead.
    """
    sources = overlap["sources"]
    matrix = overlap["overlap_matrix"]
    with open(overlap_tsv, "w", encoding="utf-8") as handle:
        handle.write("\t" + "\t".join(sources) + "\n")
        for s in sources:
            cells = [
                str(overlap["counts"].get(s, 0)) if s == t
                else str(matrix.get(f"{s}_and_{t}", matrix.get(f"{t}_and_{s}", 0)))
                for t in sources
            ]
            handle.write("\t".join([s] + cells) + "\n")
    with open(sources_tsv, "w", encoding="utf-8") as handle:
        handle.write("source\tcount\n")
        for s in sources:
            handle.write(f"{s}\t{overlap['counts'].get(s, 0)}\n")


def mining(
    db_path: str | None = None,
    charts: list[str] | tuple[str, ...] | None = MINING_CHARTS,
    out_dir: str | None = None,
    timeout: int = MINING_TIMEOUT,
) -> dict:
    """Prepare mining TSVs (temp dir) and delegate drawing to render_mining.R."""
    repo = find_repo_root()
    charts = list(charts) if charts else list(MINING_CHARTS)
    unknown = [c for c in charts if c not in MINING_CHARTS]
    if unknown:
        raise ValueError(
            f"unknown mining chart(s): {unknown}; valid mining charts: {list(MINING_CHARTS)}"
        )
    db_path = os.path.abspath(
        os.path.expanduser(db_path or os.path.join(repo, "mining", "seed_registry.sqlite"))
    )
    if not os.path.isfile(db_path):
        return {"error": f"mining database not found: {db_path}"}
    out_dir = os.path.abspath(
        os.path.expanduser(out_dir or os.path.join(repo, "mining", "vis"))
    )

    spec_dir = tempfile.mkdtemp(prefix="mgx_vis_")
    attrs_tsv = os.path.join(spec_dir, "attrs.tsv")
    overlap_tsv = os.path.join(spec_dir, "overlap.tsv")
    sources_tsv = os.path.join(spec_dir, "sources.tsv")
    attrs_rows = _write_mining_attrs(db_path, attrs_tsv)
    overlap = _load_overlap(repo, db_path)
    _write_overlap_tables(overlap, overlap_tsv, sources_tsv)

    spec = {
        "out_dir": out_dir,
        "attrs_tsv": attrs_tsv,
        "overlap_tsv": overlap_tsv,
        "sources_tsv": sources_tsv,
    }
    spec_path = os.path.join(spec_dir, "spec.json")
    with open(spec_path, "w", encoding="utf-8") as handle:
        json.dump(spec, handle, indent=2)

    renderer = os.path.join(repo, "mcp", "vis", "render_mining.R")
    rscript = os.path.join(repo, "envs", "r_stat", "bin", "Rscript")
    command = [rscript, renderer, spec_path]
    result = {
        "db_path": db_path,
        "out_dir": out_dir,
        "spec_dir": spec_dir,
        "attrs_rows": attrs_rows,
        "overlap_origin": overlap["origin"],
        "overlap_all_three": overlap.get("all_three"),
        "files": {
            "attrs_tsv": attrs_tsv,
            "overlap_tsv": overlap_tsv,
            "sources_tsv": sources_tsv,
            "spec": spec_path,
        },
        "charts": {},
    }

    if not os.path.isfile(renderer):
        for chart in charts:
            result["charts"][chart] = {
                "status": "renderer_not_found",
                "renderer": renderer,
                "command": command,
                "note": "TSVs and spec.json are ready; mcp/vis/render_mining.R is being added by a parallel track",
            }
        return result
    if not os.path.isfile(rscript):
        for chart in charts:
            result["charts"][chart] = {
                "status": "rscript_not_found",
                "rscript": rscript,
                "command": command,
            }
        return result

    os.makedirs(out_dir, exist_ok=True)
    env = dict(os.environ, MGX_FIGURE_FORMATS=FIGURE_FORMATS)
    start = time.time()
    try:
        proc = subprocess.run(
            command, cwd=spec_dir, env=env, capture_output=True, text=True, timeout=timeout
        )
        exit_code, timed_out = proc.returncode, False
        combined = _decode_stream(proc.stdout) + "\n" + _decode_stream(proc.stderr)
    except subprocess.TimeoutExpired as exc:
        exit_code, timed_out = None, True
        combined = _decode_stream(exc.stdout) + "\n" + _decode_stream(exc.stderr)
    duration = round(time.time() - start, 1)

    expected = {
        "mining_attrs": ("mining_attrs.pdf", "mining_attrs.png"),
        "mining_overlap": ("mining_overlap.pdf", "mining_overlap.png"),
    }
    for chart in charts:
        outputs = [name for name in expected[chart] if os.path.isfile(os.path.join(out_dir, name))]
        entry = {
            "command": command,
            "exit_code": exit_code,
            "duration_s": duration,
            "outputs": outputs,
        }
        if timed_out:
            entry["status"] = "timeout"
            entry["log_tail"] = _tail(combined)
        elif exit_code != 0:
            entry["status"] = "failed"
            entry["log_tail"] = _tail(combined)
        elif outputs:
            entry["status"] = "ok"
        else:
            entry["status"] = "no_output"
            entry["log_tail"] = _tail(combined)
        result["charts"][chart] = entry
    return result
