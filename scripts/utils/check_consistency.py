#!/usr/bin/env python3
"""Registry/scripts/skills/rules consistency checker.

Verifies that every entry in agents/registry.yaml has a matching script file,
that every top-level analysis script is registered, and that every skill card's
snakemake_rule points at a real rule in an existing rule file.

Exit 0 on clean, 1 on any discrepancy. Deterministic (sorted) output.

With --update-readme-badges, additionally rewrites the count tokens in
README.md (badges, ASCII banner, Platform table) to live repo values.
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
    "benchmark_functional_analysis.sh",
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
        card = {
            "file": path.stem,
            "rule_ref": rule_ref,
            "deps": list(data.get("depends_on") or []) + list(data.get("required_by") or []),
        }
        if card_id:
            skills[card_id] = card
        else:
            card["no_id"] = True
            skills[path.stem] = card
    return skills


class DuplicateKeyLoader(yaml.SafeLoader):
    """记录同层重复键的 SafeLoader 子类。

    yaml.safe_load 遇重复键会静默取最后一个值；本 loader 额外把重复键
    记录到实例属性 duplicates（(键, 首次行号, 重复行号) 元组列表），
    构造行为与 SafeLoader 完全一致，对无重复键的文件零干扰。
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.duplicates = []

    def construct_mapping(self, node, deep=False):
        first_line = {}
        for key_node, _value_node in node.value:
            if key_node.tag == "tag:yaml.org,2002:merge":
                continue  # 合并键 "<<" 允许出现多次，不计入重复
            key = self.construct_object(key_node, deep=True)
            if isinstance(key, list):
                key = tuple(key)
            try:
                hash(key)
            except TypeError:
                continue  # 不可哈希键交给基类按原行为报错
            line = key_node.start_mark.line + 1
            if key in first_line:
                self.duplicates.append((key, first_line[key], line))
            else:
                first_line[key] = line
        return super().construct_mapping(node, deep=deep)


def check_yaml_duplicate_keys():
    """用 DuplicateKeyLoader 检查 registry 与全部技能卡的同层重复键。"""
    issues = []
    paths = [REPO / "agents/registry.yaml"]
    paths += sorted((REPO / "agents/skills").glob("*.yaml"))
    for path in paths:
        loader = DuplicateKeyLoader(path.read_text())
        try:
            loader.get_single_data()
        finally:
            loader.dispose()
        for key, first_line, dup_line in loader.duplicates:
            issues.append(
                f"[yaml] {path.relative_to(REPO)}: 重复键 '{key}' "
                f"(首次出现在第 {first_line} 行, 重复出现在第 {dup_line} 行)"
            )
    return issues


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


def load_rule_names():
    names = set()
    for rule_file in sorted((REPO / "pipeline/rules").glob("*.smk")):
        names.update(re.findall(r"^rule\s+([A-Za-z0-9_]+)\s*:", rule_file.read_text(), re.M))
    return names


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


def count_repo_assets():
    """Live counts for README badge sync: scripts by type, total, rules, env dirs.

    envs is None when envs/ is absent (gitignored, e.g. on a fresh clone).
    """
    per_type = {".sh": 0, ".R": 0, ".py": 0}
    for path in (REPO / "scripts").iterdir():
        if path.is_file() and path.suffix in per_type:
            per_type[path.suffix] += 1
    n_rules = sum(
        len(re.findall(r"^rule\s", rule_file.read_text(), re.M))
        for rule_file in sorted((REPO / "pipeline/rules").glob("*.smk"))
    )
    envs_dir = REPO / "envs"
    n_envs = (
        sum(1 for child in envs_dir.iterdir() if child.is_dir())
        if envs_dir.is_dir()
        else None
    )
    return {
        "sh": per_type[".sh"],
        "R": per_type[".R"],
        "py": per_type[".py"],
        "scripts": sum(per_type.values()),
        "rules": n_rules,
        "envs": n_envs,
    }


# README.md count tokens kept in sync by --update-readme-badges.
# Each pattern has one named group "n" covering exactly the stale digits.
README_TOKENS = (
    ("scripts badge", r"scripts-(?P<n>\d+)-blue", "scripts"),
    ("conda envs badge", r"conda%20envs-(?P<n>\d+)-orange", "envs"),
    ("banner scripts", r"(?P<n>\d+)\s+scripts(?=\s+·)", "scripts"),
    ("banner rules", r"(?P<n>\d+)\s+Snakemake rules", "rules"),
    ("banner conda envs", r"(?P<n>\d+)\s+conda envs", "envs"),
)


def update_readme_badges():
    """Rewrite the README_TOKENS digits in README.md to live values (idempotent)."""
    counts = count_repo_assets()
    text = (REPO / "README.md").read_text()
    for label, pattern, key in README_TOKENS:
        value = counts[key]
        if value is None:
            print(f"[badge] {label}: envs/ not found, token left unchanged")
            continue
        match = re.search(pattern, text)
        if not match:
            print(f"[badge] {label}: token not found in README.md")
            continue
        old = match.group("n")
        if old != str(value):
            text = text[: match.start("n")] + str(value) + text[match.end("n"):]
            print(f"[badge] {label}: {old} -> {value}")
    (REPO / "README.md").write_text(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--quiet", action="store_true", help="only print failures")
    ap.add_argument("--verbose", action="store_true", help="print every check line")
    ap.add_argument(
        "--update-readme-badges",
        action="store_true",
        help="also sync README.md count tokens (badges/banner/table) to live values",
    )
    args = ap.parse_args()

    issues = []
    info = [] if args.verbose else None

    registry = load_registry()
    scripts = set(iter_analysis_scripts())
    skills = load_skills()
    rule_names = load_rule_names()

    issues.extend(check_yaml_duplicate_keys())

    for script in sorted(scripts):
        if script not in registry and not _is_companion_script(script, registry):
            issues.append(f"[script] {script}: 已存在于 scripts/ 但未在 registry 注册")
    for entry_id, entry in sorted(registry.items()):
        if entry_id in REGISTRY_EXEMPT_FILES:
            continue
        if entry.get("status") in ("deprecated", "removed") or entry_id in RULE_ONLY_ENTRIES:
            if entry.get("status") == "removed":
                ap = entry.get("archive_path")
                if ap and not (REPO / ap).exists():
                    issues.append(
                        f"[registry] {entry_id}: archive_path 不存在: {ap}"
                    )
            continue
        if entry_id not in scripts:
            issues.append(f"[registry] {entry_id}: 已注册但 scripts/ 下无对应文件")
    for skill_id, card in sorted(skills.items()):
        if card["file"].startswith("_"):
            continue
        if skill_id not in registry:
            issues.append(f"[skill] {card['file']}: 技能卡 id 未在 registry 注册")
        for dep in card["deps"]:
            if dep not in registry and dep not in rule_names:
                issues.append(
                    f"[skill] {card['file']}: 依赖 id '{dep}' 不在 registry 也不匹配任何规则名"
                )
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

    if args.update_readme_badges:
        update_readme_badges()

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
