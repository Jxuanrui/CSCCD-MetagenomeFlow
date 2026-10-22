#!/usr/bin/env python3
"""Zero-dependency HTML dashboard renderer for MGX run events.

Usage:
    python3 scripts/utils/run_monitor.py <workdir> [--repo <repo>]
        [--out <html>] [--interval <sec>] [--watch]
    python3 scripts/utils/run_monitor.py <workdir> --serve [--port <port>]
    python3 scripts/utils/run_monitor.py <workdir> --text | --follow

File mode (one-shot / --watch) reads {workdir}/logs/run_events.jsonl (one JSON
object per line, appended by the libcommon.sh MGX_MONITOR=1 hook; unparsable/
partial trailing lines are skipped) and writes a fully self-contained HTML
dashboard (inline CSS only, no external references) to
{workdir}/logs/run_monitor.html. --watch regenerates every --interval seconds;
one-shot HTML carries <meta http-equiv="refresh"> so a browser tab stays fresh
while an outer loop regenerates the file.

Step events come in start/end pairs since ENG-6 phase 3: mgx_begin writes a
start event (exit_code=-1, a negative-only "running" marker — real exit codes
are 0-255 so no genuine failure can collide with it; user-approved 2026-10-02,
marker corrected same day per supervisor stage-3 P0-1) and the EXIT trap
writes the end event. Each start pairs with the LATEST unmatched end of the
same (step_id, sample_id) (LIFO: a rerun's end closes its own start);
unpaired starts render as 运行中 cards whose elapsed
span carries data-started="<epoch-ms>" for client-side ticking. A step
killed by SIGKILL/OOM stays 运行中 forever in that jsonl (honest display).

--serve starts a real-time SSE dashboard (stdlib only, review P0
constraints): ThreadingHTTPServer bound to 127.0.0.1 ONLY (no --host), route
whitelist GET / and GET /events (else 404), Host header restricted to
127.0.0.1:<port>/localhost:<port> (else 403), in-memory page, server-side
rendering reused from this module (client JS only inserts HTML and ticks
elapsed numbers), daemon threads, <=8 SSE connections (else 503), 15s pings,
full-snapshot `reset` pushes on every new event (always consistent; volumes
are small), truncation-size rotation guard, and zero file writes.

Param readability (rendering side only; jsonl untouched): the card head shows
the canonical scripts/<step_id> path when that file exists, a rebuilt
`bash <script> <params>` command (quotes lost / possibly truncated — labeled
non-copyable), and per-script parameter chips with a 3-tier fallback: script
help-text lines, then MGX_OPTS_STRING/LONG variable names, then raw.

Mode-3 pipeline-level events (step_id "__pipeline__", written by the
Snakefile onstart/onsuccess/onerror handlers) are shown as a header status
pill driven by the last such event and are excluded from step statistics.

Python 3.8+, stdlib only. PyYAML is the sole guarded optional import: it
enriches step cards (purpose description + output path patterns) from
{repo}/agents/skills/{step_id}.yaml; when absent or the card is missing the
renderer degrades to "—" and never crashes.
"""
from __future__ import annotations

import argparse
import glob as globmod
import html
import json
import os
import re
import shlex
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

try:  # optional; sole third-party import, guarded
    import yaml
except ImportError:  # pragma: no cover - depends on host env
    yaml = None

GLOB_CAP = 10000  # max glob entries per output pattern (antiSMASH-tree safety)
PIPELINE_STEP_ID = "__pipeline__"  # mode-3 pipeline-level events (Snakefile handlers)
BANNER_TEXT = ("仅显示已接入钩子的步骤与管线级终态；Snakefile 加载期失败、未接钩脚本"
               "（01_metadata_qc，bash 壳但未 source libcommon）与进程被杀/调度器"
               "异常的运行不在其中")
DEFAULT_INTERVAL = 5
# ENG-6 phase-3 serve mode (review P0): loopback only, no --host anywhere.
SERVE_BIND_HOST = "127.0.0.1"
SERVE_DEFAULT_PORT = 8790
SSE_MAX_CONNECTIONS = 8
SSE_PING_SEC = 15
SSE_POLL_SEC = 0.2

# Tier-1 param legend: a line counts as flag documentation only when its FIRST
# non-space token is exactly a flag, followed by whitespace and a description.
FLAG_LINE_RE = re.compile(r"^\s+(-[a-zA-Z]\b|--?[a-zA-Z][\w-]*)\s{1,}(\S.*)$")
# Tier-2 param legend: MGX_OPTS_STRING="s:SAMPLE ..." / MGX_OPTS_LONG="read-len:READ_LEN ..."
MGX_OPTS_RE = re.compile(r'MGX_OPTS_(STRING|LONG)\s*=\s*"([^"]*)"')
FLAG_TOKEN_RE = re.compile(r"-[a-zA-Z]\b|--?[a-zA-Z][\w-]*\Z")
# Per-script (help_map, opts_map), cached by step_id for the process lifetime.
_SCRIPT_LEGEND_CACHE: dict = {}


def default_repo() -> Path:
    # scripts/utils/../.. == repository root
    return Path(__file__).resolve().parents[2]


def read_events(path: Path) -> list:
    events = []
    if not path.is_file():
        return events
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue  # skip unparsable / partial trailing lines
            if isinstance(obj, dict):
                events.append(obj)
    return events


def skill_card_name(step_id: str) -> str:
    # Hook writes basename "$0" (e.g. 01_qc_fastp.sh); cards drop the suffix.
    return step_id[:-3] if step_id.endswith(".sh") else step_id


def load_skill_card(repo: Path, step_id: str):
    """Return the skill card dict, or None (never raises)."""
    if yaml is None or not step_id:
        return None
    name = skill_card_name(step_id)
    path = repo / "agents" / "skills" / f"{name}.yaml"
    if not path.is_file():
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001 - degrade, never crash
        return None
    return data if isinstance(data, dict) else None


def human_size(num: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if num < 1024 or unit == "TB":
            return f"{int(num)} {unit}" if unit == "B" else f"{num:.1f} {unit}"
        num /= 1024.0
    return f"{num:.1f} TB"


def summarize_output(pattern: str, workdir: str, sample: str):
    """Lazy, renderer-side only glob of one output pattern.

    Returns (resolved_pattern, count_label, size_label). Capped at GLOB_CAP
    entries ("…" when exceeded) so huge trees cannot hang rendering.
    """
    resolved = pattern.replace("{workdir}", workdir or "").replace(
        "{sample}", sample or ""
    )
    if "{" in resolved or "}" in resolved or "$" in resolved:
        # Unresolved placeholder (e.g. {mag}, ${WORKDIR}) — globbing it would
        # misleadingly report "0 个文件". Skip counting instead (supervisor P1-4).
        return resolved, "路径含未解析占位符（不统计）", "—"
    count = 0
    total = 0
    capped = False
    try:
        for match in globmod.iglob(resolved, recursive=True):
            count += 1
            if count > GLOB_CAP:
                capped = True
                break
            try:
                total += os.path.getsize(match)
            except OSError:
                pass
    except (OSError, ValueError):
        pass
    count_label = f"≥{GLOB_CAP} …" if capped else f"{count} 个文件"
    size_label = (human_size(total) + " …") if capped else human_size(total)
    return resolved, count_label, size_label


def fmt_elapsed(seconds: float) -> str:
    sec = int(seconds)
    hours, rem = divmod(sec, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours} 时 {minutes} 分 {secs} 秒"
    if minutes:
        return f"{minutes} 分 {secs} 秒"
    return f"{secs} 秒"


def h(value) -> str:
    return html.escape(str(value))


# ==============================================================================
# Start/end event pairing (ENG-6 phase 3)
# ==============================================================================

def exit_code_of(event: dict):
    try:
        return int(event.get("exit_code"))
    except (TypeError, ValueError):
        return None


def is_step_start(event: dict) -> bool:
    """Step-level start marker: exit_code < 0 (written as -1 by mgx_begin).
    Negative-only by design: a real $? is always 0-255, so a genuine failure
    exit code (e.g. argparse's 2) can never be misread as "running"
    (supervisor stage-3 P0-1). Pipeline-level events are excluded — their
    start marker stays 2 (Snakefile-controlled, collision-free)."""
    if str(event.get("step_id") or "") == PIPELINE_STEP_ID:
        return False
    code = exit_code_of(event)
    return code is not None and code < 0


def pair_step_starts(step_events: list) -> set:
    """Indices of start events paired with a LATER end event of the same
    (step_id, sample_id). LIFO per key: a rerun's end event closes its OWN
    start (the most recent one), so a SIGKILL'd earlier run stays visible as
    运行中 instead of stealing the rerun's pairing (supervisor stage-3 P0-3);
    unpaired starts are still-running (or killed) steps.

    2026-10-18 (CP3 P0-2 revision): identity-preferred pairing with an
    AMBIGUITY GUARD — a sample-mismatched end only closes a mismatched
    start when that step has EXACTLY ONE pending candidate (unambiguous
    bijection, e.g. the legacy 98e start=''/end='Sample4' pair). With
    multiple pending candidates the pairing is left UNRESOLVED (the start
    stays visible as running) rather than guessing by recency, per the
    CP3 final-review ruling."""
    paired: set = set()
    pending: dict = {}
    for i, ev in enumerate(step_events):
        step = str(ev.get("step_id") or "")
        sample = str(ev.get("sample_id") or "")
        if is_step_start(ev):
            pending.setdefault((step, sample), []).append(i)
        else:
            stack = pending.get((step, sample))
            if stack:
                paired.add(stack.pop())
                continue
            # CP3 复审 P0-2：真唯一性 = 候选 key 数恰为 1（n_candidate_keys）
            # 且该 key 下 pending start 总数也恰为 1（n_candidate_starts）——
            # 同 key 多 start（连续重跑）或跨 key 歧义一律保持未决，防止误关旧 start
            cands = [k for k in pending if k[0] == step and pending[k]]
            n_candidate_keys = len(cands)
            n_candidate_starts = sum(len(pending[k]) for k in cands)
            if n_candidate_keys == 1 and n_candidate_starts == 1:
                paired.add(pending[cands[0]].pop())
            # otherwise: ambiguity unresolved, starts stay visible
    return paired


def parse_epoch_ms(ts: str):
    """Parse a `date +%FT%T%z` timestamp (e.g. 2026-10-03T12:34:56+0800) to
    epoch milliseconds; None when absent/unparsable."""
    if not ts:
        return None
    try:
        dt = datetime.strptime(str(ts).strip(), "%Y-%m-%dT%H:%M:%S%z")
    except (ValueError, TypeError):
        return None
    return int(dt.timestamp() * 1000)


# ==============================================================================
# Param readability: script path, rebuilt command, per-script legend
# ==============================================================================

def script_display(repo: Path, step_id: str):
    """Canonical script path from the FILESYSTEM only (skill cards are not a
    source): scripts/<step_id> when {repo}/scripts/<step_id> exists, else the
    bare step_id (already a basename). Returns (display, title_abs_path)."""
    if step_id and (repo / "scripts" / step_id).is_file():
        return f"scripts/{step_id}", str((repo / "scripts" / step_id).resolve())
    return step_id, ""


def _help_region(text: str) -> str:
    """Text of the show_help() function body when present (the line
    `show_help() {` through the next column-0 `}`), else the whole file as a
    degraded fallback. Scoping matters: a whole-file scan also harvests
    flag-positioned tokens from command lines in the script BODY (verified
    false positives: `--html "${OUT_HTML}" \\` etc. in 01_qc_fastp.sh)."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^\s*show_help\s*\(\s*\)\s*\{", line):
            start = i
            break
    if start is None:
        return text
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("}"):
            return "\n".join(lines[start + 1:j])
    return text


def script_legend(repo: Path, step_id: str):
    """(help_map, opts_map) for one script, cached by step_id.

    Tier 1 — flag→description from the script's own show_help block: a line
    counts only when its first non-space token is exactly a flag
    (FLAG_LINE_RE); first match wins per flag.
    Tier 2 — MGX_OPTS_STRING / MGX_OPTS_LONG assignments → flag→variable name
    (STRING entries map to -x, LONG entries to --long-name, matching how
    mgx_parse accepts them on the command line).
    Never sources or executes the script; read errors degrade to empty maps.
    """
    if step_id in _SCRIPT_LEGEND_CACHE:
        return _SCRIPT_LEGEND_CACHE[step_id]
    help_map: dict = {}
    opts_map: dict = {}
    try:
        text = (repo / "scripts" / step_id).read_text(
            encoding="utf-8", errors="replace"
        )
    except (OSError, ValueError):
        text = ""
    if text:
        for line in _help_region(text).splitlines():
            m = FLAG_LINE_RE.match(line)
            if m and m.group(1) not in help_map:
                help_map[m.group(1)] = m.group(2).strip()
        for m in MGX_OPTS_RE.finditer(text):
            kind, body = m.group(1), m.group(2)
            for token in body.split():
                if ":" not in token:
                    continue
                name, var = token.split(":", 1)
                if not name or not var:
                    continue
                flag = ("--" if kind == "LONG" else "-") + name
                opts_map.setdefault(flag, var)
    _SCRIPT_LEGEND_CACHE[step_id] = (help_map, opts_map)
    return help_map, opts_map


def split_params(params: str) -> list:
    """Tokenize the raw argv snapshot; shlex with a whitespace fallback
    (the snapshot may carry truncated/unbalanced quoting)."""
    try:
        return shlex.split(params, posix=True)
    except ValueError:
        return params.split()


def iter_flag_tokens(params: str):
    """Shared argv tokenizer for BOTH the HTML chips and text mode: yields
    (token, value_or_None); a flag consumes the next non-flag token as its
    value per FLAG_TOKEN_RE — one classification, no divergence."""
    tokens = split_params(params)
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if FLAG_TOKEN_RE.match(tok):
            value = None
            if i + 1 < len(tokens) and not FLAG_TOKEN_RE.match(tokens[i + 1]):
                value = tokens[i + 1]
                i += 1
            yield tok, value
        else:
            yield tok, None
        i += 1


def param_chips(params: str, repo: Path, step_id: str) -> str:
    """Render argv tokens as labeled chips (all HTML-escaped).

    Flags resolve their label through the 3-tier per-script legend; the next
    token is shown as the flag's value when present and not itself a flag.
    Non-flag stray tokens render raw."""
    pairs = list(iter_flag_tokens(params))
    if not pairs:
        return '<span class="empty">—</span>'
    help_map, opts_map = script_legend(repo, step_id)
    chips = []
    for tok, value in pairs:
        if FLAG_TOKEN_RE.match(tok):
            if tok in help_map:
                cls, label = "chip", help_map[tok]
            elif tok in opts_map:
                cls, label = "chip opts", opts_map[tok]
            else:
                cls, label = "chip raw", None
            if label is None:  # tier 3: raw
                text = h(tok + (f" {value}" if value is not None else ""))
            else:
                text = f"{h(tok)} → {h(label)}"
                if value is not None:
                    text += f' <span class="val">{h(value)}</span>'
            chips.append(f'<span class="{cls}">{text}</span>')
        else:
            chips.append(f'<span class="chip raw">{h(tok)}</span>')
    return "".join(chips)


# ==============================================================================
# Card rendering (single source for file dashboard AND SSE snapshots)
# ==============================================================================

def card_common_rows(event: dict, card, repo: Path) -> str:
    """目的 / 样本 / 完整命令 / 参数说明 rows shared by end and running cards."""
    step_id = str(event.get("step_id") or "—")
    sample = str(event.get("sample_id") or "")
    params = str(event.get("params") or "")
    purpose = "—"
    if isinstance(card, dict):
        desc = card.get("description")
        if isinstance(desc, str) and desc.strip():
            purpose = desc.strip()
    display, _title = script_display(repo, step_id)
    command = f"bash {display}" + (f" {params}" if params else "")
    return (
        f'<div class="row"><span class="k">目的：</span>{h(purpose)}</div>'
        f'<div class="row"><span class="k">样本：</span>{h(sample) if sample else "—"}</div>'
        '<div class="row"><span class="k">完整命令（依据事件重建，非可直接复制）：</span>'
        f"<pre>{h(command)}</pre></div>"
        f'<div class="row"><span class="k">参数说明：</span>{param_chips(params, repo, step_id)}</div>'
    )


def event_card(index: int, event: dict, card, repo: Path, fallback_workdir: str) -> str:
    step_id = str(event.get("step_id") or "—")
    sample = str(event.get("sample_id") or "")
    workdir = str(event.get("workdir") or fallback_workdir)
    exit_code = exit_code_of(event)
    if exit_code is None:
        exit_code = -1
    duration = event.get("duration_sec")
    ts = str(event.get("ts") or "—")
    started_at = str(event.get("started_at") or "")

    passed = exit_code == 0
    cls = "pass" if passed else "fail"
    badge = "PASS" if passed else f"FAIL ({exit_code})"

    outputs_html = '<span class="empty">—（无技能卡）</span>'
    if isinstance(card, dict):
        outputs = card.get("outputs")
        if isinstance(outputs, list) and outputs:
            items = []
            for entry in outputs:
                if not isinstance(entry, dict):
                    continue
                pattern = entry.get("path_pattern")
                if not isinstance(pattern, str) or not pattern:
                    continue
                resolved, count_label, size_label = summarize_output(
                    pattern, workdir, sample
                )
                desc = entry.get("description")
                howto = (
                    f"（如何查看：{h(desc)}）"
                    if isinstance(desc, str) and desc.strip()
                    else ""
                )
                items.append(
                    f"<li>{howto}{count_label} · {size_label}"
                    f'<br><span class="path">{h(resolved)}</span></li>'
                )
            outputs_html = (
                '<ul class="outs">' + "".join(items) + "</ul>"
                if items
                else '<span class="empty">—</span>'
            )

    display, title = script_display(repo, step_id)
    title_attr = f' title="{h(title)}"' if title else ""
    time_meta = f"开始 {h(started_at)} · 结束 {h(ts)}" if started_at else h(ts)

    return (
        f'<div class="card {cls}">'
        f'<div class="head"><span class="step"{title_attr}>#{index} {h(display)}</span>'
        f'<span class="badge {cls}">{badge}</span>'
        f'<span class="meta">耗时 {h(duration)} 秒</span>'
        f'<span class="meta">{time_meta}</span></div>'
        + card_common_rows(event, card, repo)
        + f'<div class="row"><span class="k">产生了多少文件 / 如何查看：</span>{outputs_html}</div>'
        + "</div>"
    )


def running_card(index: int, event: dict, card, repo: Path,
                 last_known_ms) -> str:
    """Card for an unpaired step-start event (still running).

    Elapsed is a lower bound against the last known event time (至少已运行);
    the live page re-ticks the span from its data-started epoch-ms attribute,
    so the server never pushes clock updates."""
    started_at = str(event.get("started_at") or "")
    started_ms = parse_epoch_ms(started_at)
    display, title = script_display(repo, str(event.get("step_id") or "—"))
    title_attr = f' title="{h(title)}"' if title else ""
    if started_ms is not None and last_known_ms is not None \
            and last_known_ms >= started_ms:
        elapsed_html = (
            f'<span data-started="{started_ms}">'
            f"至少已运行 {fmt_elapsed((last_known_ms - started_ms) / 1000)}</span>"
        )
    else:
        elapsed_html = "<span>时长未知</span>"
    return (
        f'<div class="card running">'
        f'<div class="head"><span class="step"{title_attr}>#{index} {h(display)}</span>'
        f'<span class="badge running">运行中</span>'
        f'<span class="meta">开始 {h(started_at) if started_at else "—"}</span>'
        f'<span class="meta">{elapsed_html}</span></div>'
        + card_common_rows(event, card, repo)
        # outputs row omitted: files of a running step are not final
        + "</div>"
    )


CSS = """
body { font-family: -apple-system, 'PingFang SC', 'Microsoft YaHei', sans-serif;
       background: #f5f6f8; color: #222; margin: 0; padding: 24px; }
.wrap { max-width: 980px; margin: 0 auto; }
h1 { font-size: 22px; margin: 0 0 8px 0; }
.sub { color: #666; font-size: 13px; margin-bottom: 16px; }
.banner { background: #fff8e1; border: 1px solid #e0c36a; color: #7a5c00;
          padding: 10px 14px; border-radius: 8px; font-size: 13px; margin-bottom: 16px; }
.stats { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; }
.stat { background: #fff; border: 1px solid #e2e4e8; border-radius: 8px;
        padding: 10px 16px; min-width: 130px; }
.stat .num { font-size: 20px; font-weight: 600; }
.stat .lbl { font-size: 12px; color: #777; }
.stat.ok .num { color: #2e9e5b; }
.stat.bad .num { color: #d64545; }
.stat.run .num { color: #1a66b3; }
.card { background: #fff; border: 1px solid #e2e4e8; border-left: 4px solid #ccc;
        border-radius: 8px; padding: 14px 16px; margin-bottom: 12px; }
.card.pass { border-left-color: #2e9e5b; }
.card.fail { border-left-color: #d64545; }
.card.running { border-left-color: #1a66b3; }
.head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.step { font-weight: 600; font-size: 15px; font-family: monospace; }
.badge { font-size: 12px; font-weight: 700; padding: 2px 10px;
         border-radius: 10px; color: #fff; }
.badge.pass { background: #2e9e5b; }
.badge.fail { background: #d64545; }
.badge.running { background: #1a66b3; }
.pill { font-size: 13px; font-weight: 700; padding: 3px 12px;
        border-radius: 12px; color: #fff; vertical-align: middle; margin-left: 10px; }
.pill.running { background: #1a66b3; }
.pill.ok { background: #2e9e5b; }
.pill.bad { background: #d64545; }
.meta { color: #777; font-size: 12px; }
.row { margin-top: 8px; font-size: 13px; }
.k { color: #555; font-weight: 600; }
details { margin-top: 4px; }
summary { cursor: pointer; color: #1a66b3; font-size: 13px; }
pre { background: #f0f2f5; padding: 10px; border-radius: 6px; overflow-x: auto;
      font-size: 12px; white-space: pre-wrap; word-break: break-all; }
ul.outs { margin: 6px 0 0 0; padding-left: 20px; font-size: 13px; }
ul.outs li { margin-bottom: 4px; }
.path { color: #888; font-size: 12px; font-family: monospace; word-break: break-all; }
.empty { color: #999; }
.chip { display: inline-block; background: #eef3fa; border: 1px solid #d5e2f2;
        border-radius: 6px; padding: 1px 8px; margin: 2px 4px 2px 0; font-size: 12px; }
.chip.opts { background: #f4f0e6; border-color: #e0d5b8; }
.chip.raw { background: #f0f2f5; border-color: #e2e4e8; color: #666; }
.chip .val { font-family: monospace; color: #1a66b3; word-break: break-all; }
"""


def pipeline_pill(events: list) -> str:
    """Header status pill from the LAST pipeline event in file order.

    exit_code 2 = start marker (运行中), 0 = ended successfully, anything
    else = ended with failure. No pipeline events -> no pill (mode-1/2 usage
    is unaffected)."""
    pipeline = [ev for ev in events
                if str(ev.get("step_id") or "") == PIPELINE_STEP_ID]
    if not pipeline:
        return ""
    code = exit_code_of(pipeline[-1])
    if code is None:
        code = -1
    if code == 2:
        return '<span class="pill running">运行中</span>'
    if code == 0:
        return '<span class="pill ok">已结束（成功）</span>'
    return '<span class="pill bad">已结束（失败）</span>'


def render_parts(events: list, repo: Path, workdir: str):
    """Shared rendering core for the file dashboard AND SSE snapshots.

    Returns (stats_html, cards_html, pill_html). Pipeline events are excluded
    from step statistics; start events pair with later same-key end events
    (unpaired ones become 运行中 cards and count only toward 运行中)."""
    step_events = [ev for ev in events
                   if str(ev.get("step_id") or "") != PIPELINE_STEP_ID]
    paired = pair_step_starts(step_events)
    finished = [(i, ev) for i, ev in enumerate(step_events)
                if not is_step_start(ev)]
    running_count = sum(1 for i, ev in enumerate(step_events)
                        if is_step_start(ev) and i not in paired)
    ok = sum(1 for _i, ev in finished if exit_code_of(ev) == 0)
    fail = len(finished) - ok
    total = len(finished) + running_count
    last_ts = str(events[-1].get("ts") or "—") if events else "—"
    # 口径（supervisor P2-9）: jsonl 只追加不轮转，首尾时间相减会跨越多次
    # 运行；改按已记录事件的 duration_sec 求和，标注为"已记录步骤耗时合计"。
    # Start events carry duration_sec=0, so summing all step events is safe.
    try:
        recorded_seconds = sum(int(ev.get("duration_sec") or 0) for ev in step_events)
    except (TypeError, ValueError):
        recorded_seconds = 0
    elapsed = fmt_elapsed(recorded_seconds)

    stats_html = (
        '<div class="stats">\n'
        f'  <div class="stat"><div class="num">{total}</div><div class="lbl">总步骤</div></div>\n'
        f'  <div class="stat ok"><div class="num">{ok}</div><div class="lbl">通过</div></div>\n'
        f'  <div class="stat bad"><div class="num">{fail}</div><div class="lbl">失败</div></div>\n'
        f'  <div class="stat run"><div class="num">{running_count}</div><div class="lbl">运行中</div></div>\n'
        f'  <div class="stat"><div class="num">{h(last_ts)}</div><div class="lbl">最近事件时间</div></div>\n'
        f'  <div class="stat"><div class="num">{h(elapsed)}</div><div class="lbl">已记录步骤耗时合计</div></div>\n'
        "</div>"
    )

    # Cards in strict file (append) order; paired starts render nothing —
    # their end event carries the card. Unpaired starts render 运行中 cards.
    last_known_ms = parse_epoch_ms(str(events[-1].get("ts") or "")) if events else None
    fallback_workdir = workdir
    skill_cache: dict = {}
    cards = []
    index = 0
    for i, ev in enumerate(step_events):
        step_id = str(ev.get("step_id") or "")
        if step_id not in skill_cache:
            skill_cache[step_id] = load_skill_card(repo, step_id)
        if is_step_start(ev):
            if i in paired:
                continue
            index += 1
            cards.append(running_card(index, ev, skill_cache[step_id], repo,
                                      last_known_ms))
        else:
            index += 1
            cards.append(event_card(index, ev, skill_cache[step_id], repo,
                                    fallback_workdir))
    cards_html = "".join(cards) if cards else (
        '<div class="card"><span class="empty">暂无事件记录</span></div>'
    )
    return stats_html, cards_html, pipeline_pill(events)


def render_html(events: list, repo: Path, refresh_sec: int, workdir: str) -> str:
    # ENG-6 phase-2 (supervisor C3): pipeline-level events are not step cards
    # and are excluded from step statistics / recorded-seconds totals.
    stats_html, cards_html, pill = render_parts(events, repo, workdir)
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="{refresh_sec}">
<title>MGX 运行监控看板</title>
<style>{CSS}</style>
</head>
<body>
<div class="wrap">
<h1>MGX 运行监控看板{pill}</h1>
<div class="sub">事件来源：logs/run_events.jsonl（MGX_MONITOR=1 时由各步骤 EXIT 钩子追加）</div>
<div class="banner">{BANNER_TEXT}</div>
{stats_html}
{cards_html}
</div>
</body>
</html>
"""


def write_dashboard(events_path: Path, out_path: Path, repo: Path, refresh_sec: int, workdir: str) -> None:
    events = read_events(events_path)
    text = render_html(events, repo, refresh_sec, workdir)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_name(out_path.name + ".tmp")
    tmp_path.write_text(text, encoding="utf-8")
    os.replace(tmp_path, out_path)


# ==============================================================================
# --serve: real-time SSE dashboard (review P0 constraints, stdlib only)
# ==============================================================================

SERVE_JS = """<script>
(function () {
  // Client does NO card rendering: the server sends ready-made HTML; the
  // client only inserts it and re-ticks [data-started] elapsed numbers.
  var offsetDone = false, offset = 0;
  var es = new EventSource('/events');
  function applyReset(d) {
    if (!offsetDone && typeof d.server_now_ms === 'number') {
      // one-shot server/client clock skew correction
      offset = d.server_now_ms - Date.now();
      offsetDone = true;
    }
    document.getElementById('pill').innerHTML = d.pill_html || '';
    document.getElementById('stats').innerHTML = d.stats_html || '';
    document.getElementById('cards').innerHTML = d.cards_html || '';
  }
  es.addEventListener('reset', function (e) {
    var d; try { d = JSON.parse(e.data); } catch (err) { return; }
    applyReset(d);
  });
  es.addEventListener('step', function (e) {
    var d; try { d = JSON.parse(e.data); } catch (err) { return; }
    if (d.append !== false) {
      document.getElementById('cards').insertAdjacentHTML('beforeend', d.card_html || '');
    }
    if (d.stats_html) { document.getElementById('stats').innerHTML = d.stats_html; }
  });
  function fmtElapsed(ms) {
    var s = Math.max(0, Math.floor(ms / 1000));
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
    if (h) return h + ' 时 ' + m + ' 分 ' + ss + ' 秒';
    if (m) return m + ' 分 ' + ss + ' 秒';
    return ss + ' 秒';
  }
  setInterval(function () {
    var now = Date.now() + offset;
    var nodes = document.querySelectorAll('[data-started]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var started = parseInt(el.getAttribute('data-started'), 10);
      if (started) { el.textContent = '已运行 ' + fmtElapsed(now - started); }
    }
  }, 1000);
})();
</script>"""


def serve_page_html() -> str:
    return (
        '<!DOCTYPE html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n'
        "<title>MGX 运行监控看板（实时）</title>\n<style>" + CSS + "</style>\n</head>\n"
        "<body>\n<div class=\"wrap\">\n"
        "<h1>MGX 运行监控看板<span id=\"pill\"></span></h1>\n"
        '<div class="sub">事件来源：logs/run_events.jsonl（MGX_MONITOR=1 时由各步骤钩子追加）'
        "· SSE 实时推送（断线自动重连，重连后先收全量快照）</div>\n"
        '<div class="banner">' + BANNER_TEXT + "<br>"
        "实时粒度：步骤开始即显示“运行中”，结束后 &lt;1s 更新终态（SSE）。"
        "Project01 生产 workdir 无事件，页面将保持“等待中”（属正常）。</div>\n"
        '<div id="stats"></div>\n<div id="cards"></div>\n</div>\n'
        + SERVE_JS + "\n</body>\n</html>\n"
    )


class _SSEGate:
    """Thread-safe open-SSE-connection counter with a hard limit (503 above)."""

    def __init__(self, limit: int):
        self._limit = limit
        self._count = 0
        self._lock = threading.Lock()

    def try_acquire(self) -> bool:
        with self._lock:
            if self._count >= self._limit:
                return False
            self._count += 1
            return True

    def release(self) -> None:
        with self._lock:
            if self._count > 0:
                self._count -= 1


class MonitorHTTPServer(ThreadingHTTPServer):
    # Supervisor P0: daemon threads so SIGINT exits promptly.
    daemon_threads = True

    def __init__(self, address, handler, state: dict):
        super().__init__(address, handler)
        self.mgx = state


class MonitorHandler(BaseHTTPRequestHandler):
    # HTTP/1.1 + explicit framing (Content-Length everywhere; the stream is
    # delimited by connection close) keeps SSE delivery unbuffered.
    protocol_version = "HTTP/1.1"
    server_version = "MGXMonitor"
    sys_version = ""

    def log_message(self, fmt, *args):  # keep serve stdout/stderr clean
        pass

    # ---- plumbing ----

    def _plain(self, code: int, body: str,
               ctype: str = "text/plain; charset=utf-8") -> None:
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _host_allowed(self) -> bool:
        # Anti DNS-rebinding: Host must match the bound loopback endpoint
        # exactly (case-insensitive), including the port.
        port = self.server.server_address[1]
        host = (self.headers.get("Host") or "").strip().lower()
        return host in (f"{SERVE_BIND_HOST}:{port}", f"localhost:{port}")

    def do_GET(self) -> None:
        if not self._host_allowed():
            self._plain(403, "403 Forbidden: Host header not allowed\n")
            return
        if self.path == "/":
            self._plain(200, self.server.mgx["page"], "text/html; charset=utf-8")
        elif self.path == "/events":
            self._stream_events()
        else:
            self._plain(404, "404 Not Found\n")

    # ---- SSE ----

    def _stream_events(self) -> None:
        state = self.server.mgx
        if not state["gate"].try_acquire():
            self._plain(503, "503 Too Many Connections: SSE limit "
                             f"({SSE_MAX_CONNECTIONS}) exceeded\n")
            return
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self._tail_loop()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            return  # client went away; end this thread quietly
        finally:
            state["gate"].release()

    def _tail_loop(self) -> None:
        state = self.server.mgx
        path: Path = state["events_path"]
        repo: Path = state["repo"]
        workdir: str = state["workdir"]

        def send(text: str) -> None:
            self.wfile.write(text.encode("utf-8"))
            self.wfile.flush()

        def send_reset() -> None:
            # DECISION (documented): every new event pushes a FULL reset
            # snapshot — cheap at our volumes and impossible to drift from
            # the file-mode rendering (same render_parts() source).
            snapshot = json.dumps(build_snapshot(path, repo, workdir),
                                  ensure_ascii=False)
            send(f"event: reset\ndata: {snapshot}\n\n")

        send_reset()  # initial snapshot (等待中 empty state when file missing)
        was_waiting = not path.is_file()
        handle = None
        buf = b""
        last_ping = time.monotonic()
        while True:
            if time.monotonic() - last_ping >= SSE_PING_SEC:
                send(": ping\n\n")
                last_ping = time.monotonic()
            if handle is None:
                if path.is_file():
                    # Created after connect: open positioned after the last
                    # complete line; a fresh snapshot replaces the 等待中 one.
                    handle, buf = open_tail(path)
                    if was_waiting:
                        send_reset()
                        was_waiting = False
                else:
                    time.sleep(SSE_POLL_SEC)
                continue
            line = handle.readline()
            if line:
                if line.endswith(b"\n"):
                    complete = buf + line
                    buf = b""
                    stripped = complete.strip()
                    if stripped:
                        try:
                            json.loads(stripped)
                        except (json.JSONDecodeError, ValueError):
                            pass  # bad JSON line: skip
                        else:
                            send_reset()
                else:
                    buf += line  # partial line: buffer until the newline
                continue
            # EOF — rotation guard (size check only, review-scoped):
            try:
                current_size = os.stat(path).st_size
            except OSError:
                handle.close()  # file vanished: back to the waiting state
                handle = None
                buf = b""
                send_reset()
                time.sleep(SSE_POLL_SEC)
                continue
            if current_size < handle.tell():
                handle.close()  # truncated/replaced: reopen from the start
                handle, buf = open_tail(path)
                send_reset()    # one fresh full snapshot
                continue
            time.sleep(SSE_POLL_SEC)


def open_tail(path: Path):
    """Open for tailing in binary mode. Returns (handle, partial) where
    partial is the trailing bytes after the last newline. The handle is
    positioned at END OF FILE (supervisor stage-4-r3 C1: an earlier version
    seeked to the partial's start AND returned the same bytes, so the next
    readline re-read them and the duplicated prefix failed JSON parsing)."""
    handle = path.open("rb")
    data = handle.read()
    handle.seek(0, 2)
    idx = data.rfind(b"\n")
    return handle, (data if idx == -1 else data[idx + 1:])


def build_snapshot(events_path: Path, repo: Path, workdir: str) -> dict:
    """Full-state SSE payload: server-rendered stats/cards/pill (render_parts,
    the same source as the file dashboard) plus the server clock for the
    client's one-shot skew correction."""
    if events_path.is_file():
        events = read_events(events_path)
        stats_html, cards_html, pill = render_parts(events, repo, workdir)
    else:
        _stats_html, _cards_html, pill = render_parts([], repo, workdir)
        cards_html = (
            '<div class="card"><span class="empty">等待中：尚未检测到 '
            "logs/run_events.jsonl（Project01 生产 workdir 不产生事件，属正常）"
            "</span></div>"
        )
        stats_html = _stats_html
    return {
        "stats_html": stats_html,
        "cards_html": cards_html,
        "pill_html": pill,
        "server_now_ms": int(time.time() * 1000),
    }


def run_serve(workdir: Path, repo: Path, port: int) -> int:
    """Real-time SSE mode. Binds 127.0.0.1 ONLY (no --host exists); port busy
    is a hard error (exit 1, never scans alternatives); writes NO files."""
    events_path = workdir / "logs" / "run_events.jsonl"
    state = {
        "events_path": events_path,
        "repo": repo,
        "workdir": str(workdir),
        "gate": _SSEGate(SSE_MAX_CONNECTIONS),
        "page": serve_page_html(),
    }
    try:
        httpd = MonitorHTTPServer((SERVE_BIND_HOST, port), MonitorHandler, state)
    except OSError as exc:
        print(f"Error: cannot bind {SERVE_BIND_HOST}:{port} ({exc}); "
              "pass a different --port", file=sys.stderr)
        return 1
    bound_port = httpd.server_address[1]
    print(f"[run_monitor] serving http://{SERVE_BIND_HOST}:{bound_port}/ "
          "(Ctrl-C 退出)", flush=True)
    try:
        httpd.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        print("[run_monitor] stopped", file=sys.stderr)
    finally:
        httpd.server_close()
    return 0


# ==============================================================================
# CLI
# ==============================================================================
# Text mode: --text (one-shot snapshot) / --follow (append-only) — phase 4.
# Cloud-topology delivery: the ZCode agent (or any terminal) runs --text and
# relays the result; --follow is for interactive terminals/tmux ONLY (a
# follow loop would hang an agent's Bash tool). Reuses read_events /
# pair_step_starts / script_display / script_legend / load_skill_card /
# summarize_output / open_tail — no parallel parsing or pairing logic.
# ==============================================================================

TEXT_TAIL_N = 8        # finished steps in the one-shot snapshot
TEXT_MAX_PURPOSE = 70  # chars of the skill-card description kept per line
TEXT_MAX_OUTPUTS = 3   # output patterns summarized per finished step


def _txt_params(params: str, repo: Path, step_id: str) -> str:
    """Text twin of param_chips — same iter_flag_tokens classification and
    the same 3-tier legend, plain-text rendering."""
    help_map, opts_map = script_legend(repo, step_id)
    out = []
    for tok, value in iter_flag_tokens(params):
        label = help_map.get(tok) or opts_map.get(tok)
        if label:
            out.append(f"{tok}→{label}" + (f"({value})" if value is not None else ""))
        elif value is not None:
            out.append(f"{tok} {value}")
        else:
            out.append(tok)
    return " ".join(out)


def format_text_event(event: dict, repo: Path, now_ms: int, color: bool) -> str:
    """One human-readable line: time, glyph (✓/✗/▶), canonical script path,
    sample, purpose (skill card), params legend, outputs (end events only)."""
    step_id = str(event.get("step_id") or "?")
    disp, _abs = script_display(repo, step_id)
    ts = str(event.get("ts") or "")
    hhmmss = ts[11:19] if len(ts) >= 19 else ts
    sample = str(event.get("sample_id") or "—")
    code = exit_code_of(event)

    def c(cc, s):
        return f"\033[{cc}m{s}\033[0m" if color else s

    if is_step_start(event):
        started = parse_epoch_ms(str(event.get("started_at") or ts))
        run_s = max(0, (now_ms - started) // 1000) if started is not None else 0
        head = f"{hhmmss} {c('34', '▶')} {disp} [{sample}] 已运行 {run_s} 秒(至打印时刻)"
    else:
        ok = code == 0
        head = (f"{hhmmss} {c('32', '✓') if ok else c('31', '✗')} {disp} "
                f"[{sample}] {event.get('duration_sec')} 秒"
                + ("" if ok else f" 退出码={code}"))
    parts = [head]
    card = load_skill_card(repo, step_id)
    purpose = card.get("description") if isinstance(card, dict) else None
    if isinstance(purpose, str) and purpose.strip():
        purpose = purpose.strip()
        parts.append("目的: " + (purpose[:TEXT_MAX_PURPOSE - 1] + "…"
                                 if len(purpose) > TEXT_MAX_PURPOSE else purpose))
    params_txt = _txt_params(str(event.get("params") or ""), repo, step_id)
    if params_txt:
        parts.append("参数: " + params_txt)
    if not is_step_start(event) and isinstance(card, dict):
        outs = []
        for entry in card.get("outputs") or []:
            if len(outs) >= TEXT_MAX_OUTPUTS:
                outs.append("…")
                break
            pat = entry.get("path_pattern") if isinstance(entry, dict) else None
            if isinstance(pat, str) and pat:
                _res, cnt, size = summarize_output(
                    pat, str(event.get("workdir") or ""),
                    "" if sample == "—" else sample)
                outs.append(f"{cnt}/{size}")
        if outs:
            parts.append("产出: " + "; ".join(outs))
    return " | ".join(parts)


def _pipeline_state_text(events: list) -> str:
    """Pipeline state from the last __pipeline__ event (text twin of
    pipeline_pill; supervisor C3: pipeline events never count as steps)."""
    pipe = [ev for ev in events
            if str(ev.get("step_id") or "") == PIPELINE_STEP_ID]
    if not pipe:
        return ""
    try:
        code = int(pipe[-1].get("exit_code"))
    except (TypeError, ValueError):
        code = -1
    return {2: "运行中", 0: "已结束（成功）"}.get(code, "已结束（失败）")


def _flush_stdout() -> None:
    """Force buffered stdout out NOW so a closed pipe raises here (inside a
    guarded scope) instead of at interpreter-shutdown flush (supervisor P2)."""
    try:
        sys.stdout.flush()
    except BrokenPipeError:
        pass


def _pipeline_state_line(event: dict, color: bool) -> str:
    """Text line for a NEW pipeline-level event in --follow (the snapshot
    shows it in the header; follow prints state transitions, never a step
    line — an exit_code=2 start marker must not render as a failure)."""
    code = exit_code_of(event)

    def c(cc, s):
        return f"\033[{cc}m{s}\033[0m" if color else s

    state, cc = {2: ("运行中", "34"), 0: ("已结束（成功）", "32")}.get(
        code, ("已结束（失败）", "31"))
    ts = str(event.get("ts") or "")
    hhmmss = ts[11:19] if len(ts) >= 19 else ts
    return f"{hhmmss} {c(cc, '◆')} 管线: {state}"


def run_text(events_path: Path, repo: Path, workdir: str, follow: bool) -> int:
    color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    if not events_path.is_file():
        print("等待中: 尚无事件文件（先以 --monitor / MGX_MONITOR=1 运行步骤；"
              "Project01 受写守卫不产生事件）")
        _flush_stdout()
        if not follow:
            return 0
        while not events_path.is_file():
            time.sleep(0.5)
    events = read_events(events_path)
    # Follow start offset = end of the LAST COMPLETE line at snapshot time:
    # never mid-line (a trailing partial line is skipped by read_events and
    # would otherwise be silently lost — supervisor stage-4-r2 P1), and
    # taken after the snapshot read so events are neither skipped nor
    # double-printed (residual window: sub-millisecond, documented).
    follow_from = 0
    if follow:
        with events_path.open("rb") as ftmp:
            ftmp.seek(0, 2)
            end = ftmp.tell()
            window_start = max(0, end - 65536)
            ftmp.seek(window_start)
            window = ftmp.read(end - window_start)
        idx = window.rfind(b"\n")
        follow_from = window_start + idx + 1 if idx != -1 else 0
    # Supervisor C3 (phase 2): pipeline-level events are excluded from step
    # statistics and shown as a header state instead (their exit_code=2 start
    # marker must never render as a failed step) — snapshot AND follow.
    steps = [ev for ev in events
             if str(ev.get("step_id") or "") != PIPELINE_STEP_ID]
    paired = pair_step_starts(steps)
    running = [ev for i, ev in enumerate(steps)
               if is_step_start(ev) and i not in paired]
    ends = [ev for ev in steps if not is_step_start(ev)]
    ok = sum(1 for e in ends if exit_code_of(e) == 0)
    header = (f"== {workdir} == 终态 {len(ends)}（✓{ok} ✗{len(ends) - ok}）"
              f" 运行中 {len(running)}")
    pipe_state = _pipeline_state_text(events)
    if pipe_state:
        header += f" | 管线: {pipe_state}"
    try:
        print(header)
        now_ms = int(time.time() * 1000)
        for ev in running:
            print(format_text_event(ev, repo, now_ms, color))
        if not follow:
            if ends:
                print(f"-- 最近 {min(TEXT_TAIL_N, len(ends))} 条终态 --")
                for ev in ends[-TEXT_TAIL_N:]:
                    print(format_text_event(ev, repo, now_ms, color))
            _flush_stdout()
            return 0
        print("-- 跟踪中（Ctrl-C 退出；请在 tmux/交互终端运行，勿交给代理的 Bash 工具）--")
    except BrokenPipeError:
        return 0
    fh = None
    try:
        fh = events_path.open("rb")
        fh.seek(follow_from)
        partial = b""
        while True:
            if fh is None:
                # File was deleted mid-follow: wait for (re)creation and
                # restart from the top with a visible marker. Never call
                # readline() on the closed handle (supervisor stage-4-r2 P0).
                try:
                    fh = events_path.open("rb")
                    partial = b""
                    print("-- 事件文件已（重）建，从头跟踪 --", flush=True)
                except FileNotFoundError:
                    time.sleep(0.5)
                continue
            line = fh.readline()
            if not line:
                try:
                    st = events_path.stat()
                except FileNotFoundError:
                    fh.close()
                    fh = None  # loop-top wait/reopen handles recreation
                    continue
                try:
                    same_file = os.fstat(fh.fileno()).st_ino == st.st_ino
                except OSError:
                    same_file = False
                if not same_file:
                    # atomic replace (rotation os.replace / mv): the handle
                    # points at a dead inode — restart from the top instead
                    # of silently tailing a deleted file.
                    fh.close()
                    fh = None
                    continue
                if st.st_size < fh.tell():  # truncated: re-tail from EOF
                    try:
                        fh.close()
                        fh, partial = open_tail(events_path)
                        print("-- 事件文件被截断/轮转，从末尾继续跟踪 --",
                              flush=True)
                    except FileNotFoundError:
                        fh = None
                else:
                    time.sleep(0.2)
                continue
            if not line.endswith(b"\n"):
                partial += line
                continue
            raw, partial = partial + line, b""
            try:
                ev = json.loads(raw.decode("utf-8", errors="replace"))
            except ValueError:
                continue
            if str(ev.get("step_id") or "") == PIPELINE_STEP_ID:
                print(_pipeline_state_line(ev, color), flush=True)
            else:
                print(format_text_event(ev, repo, int(time.time() * 1000),
                                        color), flush=True)
    except (KeyboardInterrupt, BrokenPipeError):
        return 0
    finally:
        if fh is not None:
            try:
                fh.close()
            except OSError:
                pass
        _flush_stdout()
    return 0


# ==============================================================================
# CLI
# ==============================================================================

def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render an HTML dashboard for MGX_MONITOR run events."
    )
    parser.add_argument("workdir", help="project workdir containing logs/run_events.jsonl")
    parser.add_argument("--repo", help="repository root (default: parent of this script)")
    parser.add_argument("--out", help="output HTML path (default: {workdir}/logs/run_monitor.html)")
    parser.add_argument("--interval", type=int, default=DEFAULT_INTERVAL,
                        help="watch/regenerate interval in seconds (default: 5)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--watch", action="store_true",
                      help="regenerate every --interval seconds until interrupted")
    mode.add_argument("--serve", action="store_true",
                      help="serve a real-time SSE dashboard on 127.0.0.1 "
                           "(loopback only; writes no files)")
    mode.add_argument("--text", action="store_true",
                      help="print a one-shot TEXT snapshot and exit "
                           "(agent/terminal friendly; writes no files)")
    mode.add_argument("--follow", action="store_true",
                      help="text mode that keeps appending new event lines "
                           "(no clear-screen; run it in a real terminal/tmux, "
                           "never hand it to an agent's Bash tool)")
    parser.add_argument("--port", type=int, default=SERVE_DEFAULT_PORT,
                        help="port for --serve (default: 8790; 0 = OS-assigned)")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    if args.interval < 1:
        print("Error: --interval must be >= 1", file=sys.stderr)
        return 1

    workdir = Path(args.workdir).expanduser()
    if not workdir.is_dir():
        print(f"Error: workdir not found: {workdir}", file=sys.stderr)
        return 1
    events_path = workdir / "logs" / "run_events.jsonl"
    out_path = Path(args.out).expanduser() if args.out else (
        workdir / "logs" / "run_monitor.html"
    )
    repo = Path(args.repo).expanduser().resolve() if args.repo else default_repo()

    if args.text or args.follow:
        # Text mode tolerates a missing events file (等待中 state).
        return run_text(events_path, repo, str(workdir), follow=args.follow)

    if args.serve:
        # Serve mode tolerates a missing events file (等待中 state).
        return run_serve(workdir, repo, args.port)

    if not events_path.is_file():
        print(
            f"Error: events file not found: {events_path} "
            "(run steps with --monitor / MGX_MONITOR=1 first)",
            file=sys.stderr,
        )
        return 1

    if args.watch:
        print(
            f"[run_monitor] watching {events_path} every {args.interval}s "
            f"(output: {out_path}; Ctrl-C to stop)",
            file=sys.stderr,
        )
        try:
            while True:
                write_dashboard(events_path, out_path, repo, args.interval, str(workdir))
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print("[run_monitor] stopped", file=sys.stderr)
            return 0
    write_dashboard(events_path, out_path, repo, args.interval, str(workdir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
