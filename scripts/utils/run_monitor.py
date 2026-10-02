#!/usr/bin/env python3
"""Zero-dependency HTML dashboard renderer for MGX run events.

Usage:
    python3 scripts/utils/run_monitor.py <workdir> [--repo <repo>]
        [--out <html>] [--interval <sec>] [--watch]

Reads {workdir}/logs/run_events.jsonl (one JSON object per line, appended by
the libcommon.sh MGX_MONITOR=1 EXIT-trap hook; unparsable/partial trailing
lines are skipped) and writes a fully self-contained HTML dashboard (inline
CSS only, no external references) to {workdir}/logs/run_monitor.html.

--watch regenerates the dashboard every --interval seconds until interrupted.
In one-shot mode the HTML still carries <meta http-equiv="refresh"> so a
browser tab stays fresh while an outer loop regenerates the file.

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
import sys
import time
from datetime import datetime
from pathlib import Path

try:  # optional; sole third-party import, guarded
    import yaml
except ImportError:  # pragma: no cover - depends on host env
    yaml = None

GLOB_CAP = 10000  # max glob entries per output pattern (antiSMASH-tree safety)
BANNER_TEXT = "仅显示已接入钩子的步骤（未调用 mgx_begin 的脚本与 Snakemake 脚本前失败不在此列）"
DEFAULT_INTERVAL = 5


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


def parse_ts(raw) -> datetime | None:
    """Parse the hook's date +%FT%T%z output (e.g. 2026-10-02T15:04:05+0800)."""
    if not isinstance(raw, str) or not raw.strip():
        return None
    text = raw.strip()
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        pass
    if len(text) >= 5 and text[-5] in "+-" and ":" not in text[-5:]:
        try:
            return datetime.fromisoformat(text[:-2] + ":" + text[-2:])
        except ValueError:
            return None
    return None


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


def event_card(index: int, event: dict, card, fallback_workdir: str) -> str:
    step_id = str(event.get("step_id") or "—")
    sample = str(event.get("sample") or "")
    argv = str(event.get("argv") or "")
    workdir = str(event.get("workdir") or fallback_workdir)
    try:
        exit_code = int(event.get("exit_code"))
    except (TypeError, ValueError):
        exit_code = -1
    duration = event.get("duration_sec")
    ts = str(event.get("ts") or "—")

    passed = exit_code == 0
    cls = "pass" if passed else "fail"
    badge = "PASS" if passed else f"FAIL ({exit_code})"

    purpose = "—"
    if isinstance(card, dict):
        desc = card.get("description")
        if isinstance(desc, str) and desc.strip():
            purpose = desc.strip()

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

    argv_html = (
        f'<details><summary>展开命令行</summary><pre>{h(argv)}</pre></details>'
        if argv
        else '<span class="empty">—</span>'
    )

    return (
        f'<div class="card {cls}">'
        f'<div class="head"><span class="step">#{index} {h(step_id)}</span>'
        f'<span class="badge {cls}">{badge}</span>'
        f'<span class="meta">耗时 {h(duration)} 秒</span>'
        f'<span class="meta">{h(ts)}</span></div>'
        f'<div class="row"><span class="k">目的：</span>{h(purpose)}</div>'
        f'<div class="row"><span class="k">样本：</span>{h(sample) if sample else "—"}</div>'
        f'<div class="row"><span class="k">命令行：</span>{argv_html}</div>'
        f'<div class="row"><span class="k">产生了多少文件 / 如何查看：</span>{outputs_html}</div>'
        f"</div>"
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
.card { background: #fff; border: 1px solid #e2e4e8; border-left: 4px solid #ccc;
        border-radius: 8px; padding: 14px 16px; margin-bottom: 12px; }
.card.pass { border-left-color: #2e9e5b; }
.card.fail { border-left-color: #d64545; }
.head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.step { font-weight: 600; font-size: 15px; font-family: monospace; }
.badge { font-size: 12px; font-weight: 700; padding: 2px 10px;
         border-radius: 10px; color: #fff; }
.badge.pass { background: #2e9e5b; }
.badge.fail { background: #d64545; }
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
"""


def render_html(events: list, repo: Path, refresh_sec: int, workdir: str) -> str:
    total = len(events)
    ok = sum(1 for ev in events if str(ev.get("exit_code")) == "0")
    fail = total - ok
    last_ts = str(events[-1].get("ts") or "—") if events else "—"
    first_dt = parse_ts(events[0].get("ts")) if events else None
    last_dt = parse_ts(events[-1].get("ts")) if events else None
    if first_dt is not None and last_dt is not None and last_dt >= first_dt:
        elapsed = fmt_elapsed((last_dt - first_dt).total_seconds())
    else:
        elapsed = "—"

    fallback_workdir = workdir
    skill_cache: dict = {}
    cards = []
    for idx, ev in enumerate(events, 1):
        step_id = str(ev.get("step_id") or "")
        if step_id not in skill_cache:
            skill_cache[step_id] = load_skill_card(repo, step_id)
        cards.append(event_card(idx, ev, skill_cache[step_id], fallback_workdir))
    cards_html = "".join(cards) if cards else (
        '<div class="card"><span class="empty">暂无事件记录</span></div>'
    )

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
<h1>MGX 运行监控看板</h1>
<div class="sub">事件来源：logs/run_events.jsonl（MGX_MONITOR=1 时由各步骤 EXIT 钩子追加）</div>
<div class="banner">{BANNER_TEXT}</div>
<div class="stats">
  <div class="stat"><div class="num">{total}</div><div class="lbl">总步骤</div></div>
  <div class="stat ok"><div class="num">{ok}</div><div class="lbl">通过</div></div>
  <div class="stat bad"><div class="num">{fail}</div><div class="lbl">失败</div></div>
  <div class="stat"><div class="num">{h(last_ts)}</div><div class="lbl">最近事件时间</div></div>
  <div class="stat"><div class="num">{h(elapsed)}</div><div class="lbl">累计耗时</div></div>
</div>
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


def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render an HTML dashboard for MGX_MONITOR run events."
    )
    parser.add_argument("workdir", help="project workdir containing logs/run_events.jsonl")
    parser.add_argument("--repo", help="repository root (default: parent of this script)")
    parser.add_argument("--out", help="output HTML path (default: {workdir}/logs/run_monitor.html)")
    parser.add_argument("--interval", type=int, default=DEFAULT_INTERVAL,
                        help="watch/regenerate interval in seconds (default: 5)")
    parser.add_argument("--watch", action="store_true",
                        help="regenerate every --interval seconds until interrupted")
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
    if not events_path.is_file():
        print(
            f"Error: events file not found: {events_path} "
            "(run steps with --monitor / MGX_MONITOR=1 first)",
            file=sys.stderr,
        )
        return 1
    out_path = Path(args.out).expanduser() if args.out else (
        workdir / "logs" / "run_monitor.html"
    )
    repo = Path(args.repo).expanduser().resolve() if args.repo else default_repo()

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
