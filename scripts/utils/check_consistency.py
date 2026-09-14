#!/usr/bin/env python3
"""Registry/scripts/skills/rules consistency checker.

Verifies that every entry in agents/registry.yaml has a matching script file,
that every top-level analysis script is registered, and that every skill card's
snakemake_rule points at a real rule in an existing rule file.

Exit 0 on clean, 1 on any discrepancy. Deterministic (sorted) output.
"""

import argparse
import glob
import os
import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]

# Scripts not tracked in the registry (orchestrators, diagnostics, utilities)
REGISTRY_EXEMPT_PREFIXES = ("00_",)
REGISTRY_EXEMPT_FILES = {
    "activate.sh",
    "checkm_config.sh",
    "install_git_hooks.sh",
    "auto_start_new_annotations.sh",
    "benchmark_functional_analysis.sh",
    "monitor_antismash_and_trigger.sh",
    "parse_benchmark_logs.py",
    "run_functional_analysis.sh",
    "batch_provenance_backfill.py",
    "write_provenance.py",
    "check_project_cleanliness.sh",
}
EXEMPT_DIRS = {"deprecated", "tests", "utils", "hooks", "R", "__pycache__"}
# Skill cards that are intentionally not tied to a registry entry
SKILL_EXEMPT_NAMES = {"_template"}
# Registry entries whose purpose is a Snakemake rule, not a standalone script
RULE_ONLY_ENTRIES = {"downstream_summary", "rag_build_experience", "rag_refresh_literature"}


def load_registry():
    with open(REPO / "agents/registry.yaml") as fh:
        data = yaml.safe_load(fh)
    return {entry["id"]: entry for entry in data.get("scripts", [])}


def iter_analysis_scripts():
    script_dir = REPO / "scripts"
    for path in sorted(script_dir.glob("*")):
        if not path.is_file() or path.suffix not in (".sh", ".R", ".py"):
            continue
        if path.stem.startswith(REGISTRY_EXEMPT_PREFIXES):
            continue
        if path.name in REGISTRY_EXEMPT_FILES:
            continue
        yield path.stem


def load_skills():
    skills = {}
    for path in sorted((REPO / "agents/skills").glob("*.yaml")):
        with open(path) as fh:
            data = yaml.safe_load(fh)
        if not data:
            continue
        rule_ref = data.get("snakemake_rule")
        card_id = data.get("id") or data.get("script_id")
        if card_id:
            skills[card_id] = {"file": path.stem, "rule_ref": rule_ref}
        else:
            skills[path.stem] = {"file": path.stem, "rule_ref": rule_ref, "no_id": True}
    return skills


def resolve_rule(rule_ref):
    """Return (rule_file, rule_name) or (None, None) for a rule reference."""
    if not rule_ref:
        return None, None
    if "::" in rule_ref:
        rule_file, rule_name = rule_ref.split("::", 1)
        if not rule_file.startswith("pipeline/"):
            rule_file = f"pipeline/rules/{rule_file}"
        return rule_file, rule_name
    # Bare rule name: search all rule files for a matching rule.
    for rule_file in sorted((REPO / "pipeline/rules").glob("*.smk")):
        if re.search(rf"^rule\s+{re.escape(rule_ref)}\s*:", rule_file.read_text(), re.M):
            return f"pipeline/rules/{rule_file.name}", rule_ref
    return None, rule_ref


def check_rule_exists(rule_file, rule_name):
    if not rule_file or not rule_name:
        return True  # no rule reference or unresolved bare name handled by caller
    if not (REPO / rule_file).exists():
        return False
    text = (REPO / rule_file).read_text()
    return bool(re.search(rf"^rule\s+{re.escape(rule_name)}\s*:", text, re.M))


def _is_companion_script(stem, registry):
    """True if stem is a helper (.R/.py) sharing the numeric prefix of a registered script."""
    match = re.match(r"^(\d+[a-z]?)_", stem)
    if not match:
        return False
    prefix = match.group(1)
    return any(registered.startswith(prefix + "_") for registered in registry)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--quiet", action="store_true", help="only print failures")
    ap.add_argument("--verbose", action="store_true", help="print every check line")
    args = ap.parse_args()

    issues = []
    info = [] if args.verbose else None

    registry = load_registry()
    scripts = set(iter_analysis_scripts())
    skills = load_skills()

    for script in sorted(scripts):
        if script not in registry and not _is_companion_script(script, registry):
            issues.append(f"[script] {script}: 已存在于 scripts/ 但未在 registry 注册")
    for entry_id, entry in sorted(registry.items()):
        if entry_id in REGISTRY_EXEMPT_FILES:
            continue
        if entry.get("status") in ("deprecated",) or entry_id in RULE_ONLY_ENTRIES:
            continue
        if entry_id not in scripts:
            issues.append(f"[registry] {entry_id}: 已注册但 scripts/ 下无对应文件")
    for skill_id, card in sorted(skills.items()):
        if card["file"].startswith("_"):
            continue
        if skill_id not in registry:
            issues.append(f"[skill] {card['file']}: 技能卡 id 未在 registry 注册")
        rule_file, rule_name = resolve_rule(card["rule_ref"])
        if rule_name and not rule_file:
            issues.append(
                f"[skill] {card['file']}: snakemake_rule '{card['rule_ref']}' 未匹配任何 .smk 规则"
            )
        elif rule_file and not check_rule_exists(rule_file, rule_name):
            issues.append(
                f"[skill] {card['file']}: 规则文件 {rule_file} 中无规则 '{rule_name}'"
            )
        elif rule_file and args.verbose:
            info.append(f"[ok] {card['file']}: {rule_file}::{rule_name}")

    for line in info or []:
        print(line)
    for line in sorted(issues):
        print(line)

    summary = (
        f"registry={len(registry)} scripts={len(scripts)} "
        f"skills={len(skills)} issues={len(issues)}"
    )
    if args.quiet and not issues:
        print(summary)
    elif not args.quiet:
        print(summary)
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
