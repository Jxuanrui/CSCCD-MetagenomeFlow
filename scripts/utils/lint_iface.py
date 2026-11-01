#!/usr/bin/env python3
"""Interface-consistency lint: help text vs MGX_OPTS registry (supervisor final
review P0-3, 2026-10-15).

Catches the "option documented in usage but never registered" class (43/43b -t
incident, commit 36f8b29) that shellcheck is structurally blind to (SC2154
exempts all-caps variables; mgx_parse assigns indirectly).

Blocking: a single-letter option (-x) documented in the usage/help block but
absent from MGX_OPTS_STRING.
Advisory (stderr only): registered option never mentioned in help.
"""
import re
import sys


def registry(path):
    """Extract registered short options and long options from MGX_* tables."""
    txt = open(path, encoding="utf-8", errors="replace").read()
    short, longs = set(), set()
    m = re.search(r'MGX_OPTS_STRING="([^"]*)"', txt)
    if m:
        for spec in m.group(1).split():
            tok = spec.split(":")[0]
            if len(tok) == 1:
                short.add(tok)
    for var in ("MGX_OPTS_LONG", "MGX_OPTS_FLAG"):
        m = re.search(var + r'="([^"]*)"', txt)
        if m:
            longs.update(x.split(":")[0] for x in m.group(1).split())
    return short, longs, txt


def documented(txt):
    """Options documented in the show_help heredoc: usage line (-X UPPERCASE
    pairs) and option-description blocks (indented '-x  label' lines)."""
    m = re.search(r"show_help\(\)\s*\{\s*cat\s*<<\s*'??EOF'??\s*\n(.*?)\nEOF\b", txt, re.S)
    help_txt = m.group(1) if m else ""
    short, longs = set(), set()
    # usage line: bash NN_x.sh -s SAMPLE -t CPUS ... (flag + UPPERCASE param)
    for line in help_txt.splitlines():
        if "用法" in line or "Usage" in line:
            for mm in re.finditer(r"-(\w)\s+[A-Z][A-Z_0-9]*(\]|$|\s)", line):
                short.add(mm.group(1))
    # option blocks: indented '-x  description' lines
    for line in help_txt.splitlines():
        mm = re.match(r"\s{2,}-(\w)\s{2,}\S", line)
        if mm:
            short.add(mm.group(1))
        mm = re.match(r"\s{2,}--([a-z][a-z0-9-]+)\s+\S", line)
        if mm:
            longs.add(mm.group(1))
    return short, longs


def main(paths):
    failed = False
    for p in paths:
        try:
            reg_short, reg_long, txt = registry(p)
        except OSError as e:
            print(f"[lint_iface] cannot read {p}: {e}", file=sys.stderr)
            continue
        # only lint scripts that use the mgx_parse machinery
        if "MGX_OPTS_STRING" not in txt and "MGX_OPTS_LONG" not in txt:
            continue
        doc_short, doc_long = documented(txt)
        doc_short.discard("h")  # -h handled by mgx_parse itself
        missing = doc_short - reg_short
        if missing:
            print(f"[lint_iface] FAIL {p}: usage documents option(s) "
                  f"{sorted('-' + c for c in missing)} not registered in MGX_OPTS_STRING",
                  file=sys.stderr)
            failed = True
        silent = reg_short - doc_short
        if silent:
            print(f"[lint_iface] WARN {p}: registered option(s) "
                  f"{sorted('-' + c for c in silent)} never documented in help text",
                  file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
