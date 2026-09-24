#!/usr/bin/env python3
"""
recommend.py — Skills 自动推荐引擎
基于项目当前脚本完成状态，动态推荐最相关的外部技能。
纯算法匹配，零映射表维护。

用法:
    python3 skills/recommend/recommend.py
"""

import os
import re
import yaml
from pathlib import Path

# === 路径配置 ===
PROJ_DIR = Path(__file__).resolve().parents[2]
AGENTS_REGISTRY = PROJ_DIR / "agents" / "registry.yaml"
CLAUDES_SKILLS = Path.home() / ".claude" / "skills"

# 分析阶段定义（编号段 → 阶段名）
PHASES = [
    (1, 2, "shared", "预处理 (QC/去宿主)"),
    (11, 13, "bacteria", "细菌 — 物种分类与功能谱"),
    (14, 15, "bacteria", "细菌 — 快速分类"),
    (16, 20, "bacteria", "细菌 — 组装与基因定量"),
    (21, 31, "bacteria", "细菌 — 功能注释"),
    (32, 36, "bacteria", "细菌 — Binning"),
    (37, 41, "bacteria", "细菌 — MAG 精炼"),  # 含 41b-41d
    (51, 55, "virome", "病毒 — 鉴定与组装"),
    (56, 60, "virome", "病毒 — vOTU 定量"),
    (61, 69, "virome", "病毒 — vMAG 与注释"),
    (71, 77, "fungi", "真菌 — 分类谱"),
    (78, 80, "fungi", "真菌 — 组装与 Binning"),
    (81, 86, "fungi", "真菌 — 功能注释"),
    (91, 98, "stats", "统计 — 分析与可视化"),
]

# 每阶段的通用推荐关键词（用于未精确匹配时的后备推荐）
PHASE_GENERIC_TIPS = {
    "预处理 (QC/去宿主)": ["fastp", "kneaddata", "quality", "contamination", "read-qc"],
    "细菌 — 物种分类与功能谱": ["metaphlan", "humann", "taxonomy", "abundance", "pathway"],
    "细菌 — 快速分类": ["kraken", "centrifuger", "classification", "bracken"],
    "细菌 — 组装与基因定量": ["assembly", "megahit", "salmon", "quantification", "gene"],
    "细菌 — 功能注释": ["kegg", "eggnog", "annotation", "cazy", "amr", "pathway", "enrichment"],
    "细菌 — Binning": ["binning", "metabat", "maxbin", "semibin", "dastool", "checkm"],
    "细菌 — MAG 精炼": ["drep", "gtdb", "bakta", "mlst", "pangenome", "phylogenetic"],
    "病毒 — 鉴定与组装": ["genomad", "virsorter", "checkv", "virus"],
    "病毒 — vOTU 定量": ["votu", "vclust", "salmon", "abundance"],
    "病毒 — vMAG 与注释": ["pharokka", "phold", "vog", "iphop", "phage"],
    "真菌 — 分类谱": ["kraken2", "metaphlan", "blast", "funomic", "ccmetagen"],
    "真菌 — 组装与 Binning": ["eukfinder", "megahit", "assembly"],
    "真菌 — 功能注释": ["kegg", "eggnog", "cazy", "vfdb", "amr", "merops"],
    "统计 — 分析与可视化": ["diversity", "differential", "visualization", "batch", "ml", "siamcat"],
}


def parse_script_id(script_id):
    """从脚本ID提取编号、维度、工具名。"""
    # 匹配: 11_bac_kraken2 或 11b_bac_metaphlan4_merge
    m = re.match(r"(\d+)([a-z]?)_([a-z]+)_(.+)", script_id)
    if not m:
        return None
    seq = int(m.group(1))
    suffix = m.group(2)
    dimension = m.group(3)
    tool_part = m.group(4)
    return {"seq": seq, "suffix": suffix, "dimension": dimension, "tool_part": tool_part}


def extract_tool_names(tool_part):
    """从工具部分提取核心工具名。"""
    # 去除后缀
    tool_part = re.sub(r"_(merge|build|quant|table|gen|depth)$", "", tool_part)
    # 分区名
    parts = tool_part.split("_")
    return parts


def get_phase_for_seq(seq):
    """通过编号找到所属阶段。"""
    for start, end, dim, name in PHASES:
        if start <= seq <= end:
            return name
    return None


def load_completed_scripts():
    """从 agents/registry.yaml 加载已完成的脚本列表。"""
    with open(AGENTS_REGISTRY) as f:
        data = yaml.safe_load(f)

    completed = []
    for script in data.get("scripts", []):
        sid = script["id"]
        parsed = parse_script_id(sid)
        if parsed:
            completed.append({
                "id": sid,
                "seq": parsed["seq"],
                "dimension": parsed["dimension"],
                "tool_names": extract_tool_names(parsed["tool_part"]),
                "status": script.get("status", "unknown"),
            })
    return completed


def scan_installed_skills():
    """扫描 ~/.claude/skills/ 下所有 SKILL.md，提取 frontmatter。"""
    skills = []
    if not CLAUDES_SKILLS.exists():
        return skills

    for skill_dir in sorted(CLAUDES_SKILLS.iterdir()):
        if not skill_dir.is_dir():
            continue
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            continue

        with open(skill_md) as f:
            content = f.read()

        parts = content.split("---", 2)
        if len(parts) < 3:
            continue

        try:
            fm = yaml.safe_load(parts[1])
        except Exception:
            continue

        if not fm or "name" not in fm:
            continue

        skills.append({
            "id": skill_dir.name,
            "name": fm.get("name", ""),
            "description": fm.get("description", ""),
            "primary_tool": str(fm.get("primary_tool", "")).lower(),
            "tags": [t.lower() for t in fm.get("tags", [])],
            "dir_name": skill_dir.name.lower(),
        })

    return skills


def score_skill(skill, tool_names):
    """计算技能与工具词的匹配分数。"""
    score = 0
    name_lower = skill["name"].lower()
    desc_lower = skill["description"].lower()
    dir_lower = skill["dir_name"]
    primary_tool = skill["primary_tool"]
    tags = skill["tags"]

    for t in tool_names:
        t_lower = t.lower()
        # primary_tool 精确匹配（最高优先级）
        if t_lower == primary_tool:
            score += 50
        # 目录名包含工具词
        if t_lower in dir_lower:
            score += 30
        # name 包含工具词
        if t_lower in name_lower:
            score += 25
        # description 包含工具词
        if t_lower in desc_lower:
            score += 15
        # tags 包含工具词
        if t_lower in tags:
            score += 10

    return score


def generic_recommendations(phase_name, skills, max_count=3):
    """基于阶段通用关键词推荐技能。"""
    keywords = PHASE_GENERIC_TIPS.get(phase_name, [])
    scored = []
    for skill in skills:
        score = 0
        for kw in keywords:
            if kw in skill["dir_name"] or kw in skill["name"].lower() or kw in skill["description"].lower():
                score += 1
                # 加权：目录匹配 > name > description
                if kw in skill["dir_name"]:
                    score += 2
                elif kw in skill["name"].lower():
                    score += 1
        if score > 0:
            scored.append((score, skill))

    scored.sort(key=lambda x: -x[0])
    return [s[1] for s in scored[:max_count]]


def main():
    print("╔══════════════════════════════════════════════╗")
    print("║  CSCCD-MetagenomeFlow Skills 推荐引擎              ║")
    print("╚══════════════════════════════════════════════╝")
    print()

    # 1. 加载已完成脚本
    completed = load_completed_scripts()
    integrated = [s for s in completed if s["status"] == "integrated"]
    integrated.sort(key=lambda x: x["seq"])

    if not integrated:
        print("当前无已完成脚本。运行分析后再试。")
        return

    print(f"已集成脚本: {len(integrated)} 个")
    print()

    # 2. 扫描已安装技能
    skills = scan_installed_skills()
    print(f"已安装技能: {len(skills)} 个")
    print()

    # 3. 按阶段分组推荐
    current_phase = None
    next_phase = None
    max_seq = max(s["seq"] for s in integrated)

    for i, (start, end, dim, name) in enumerate(PHASES):
        phase_scripts = [s for s in integrated if start <= s["seq"] <= end]
        if phase_scripts:
            current_phase = name
        elif current_phase and not next_phase:
            next_phase = name

    if not current_phase:
        current_phase = "未知阶段"

    # 4. 对当前阶段已完成脚本推荐技能
    print("=" * 55)
    print(f"📌 当前阶段: {current_phase}")
    print("=" * 55)

    phase_scripts = []
    for start, end, dim, name in PHASES:
        if name == current_phase:
            phase_scripts = [s for s in integrated if start <= s["seq"] <= end]
            break

    if phase_scripts:
        # 收集当前阶段所有工具词
        current_tools = set()
        for s in phase_scripts:
            for t in s["tool_names"]:
                current_tools.add(t.lower())

        # 评分所有技能
        scored = []
        for skill in skills:
            score = score_skill(skill, list(current_tools))
            if score > 0:
                scored.append((score, skill))

        scored.sort(key=lambda x: -x[0])

        # 直接匹配推荐
        direct = scored[:5]

        # 通用补充推荐
        generic = generic_recommendations(current_phase, skills, 3)
        generic_ids = {s["id"] for s in generic}
        # 去重（已有直接匹配的不重复推荐）
        direct_ids = {s["id"] for _, s in direct}
        generic_extra = [s for s in generic if s["id"] not in direct_ids]

        print(f"已完成工具: {', '.join(s['id'] for s in phase_scripts)}")
        print()

        if direct:
            print("推荐技能（精确匹配）:")
            for score, skill in direct:
                desc_short = skill["description"][:70]
                print(f"  ★ {skill['id']}")
                print(f"    {desc_short}")
            print()

        if generic_extra:
            print("推荐技能（阶段通用）:")
            for skill in generic_extra:
                print(f"  · {skill['id']}")
            print()

    # 5. 下一阶段预告
    if next_phase:
        print("=" * 55)
        print(f"⏭ 下一阶段: {next_phase}")
        print("=" * 55)
        next_tips = generic_recommendations(next_phase, skills, 4)
        if next_tips:
            print("可提前关注的技能:")
            for skill in next_tips:
                desc_short = skill["description"][:60]
                print(f"  → {skill['id']}")
                print(f"    {desc_short}")
        print()

    # 6. 维度分布统计
    print("=" * 55)
    print("📊 维度覆盖统计")
    print("=" * 55)
    dims = {}
    for s in integrated:
        dim = s["dimension"]
        dims[dim] = dims.get(dim, 0) + 1
    for dim, cnt in sorted(dims.items()):
        print(f"  {dim}: {cnt} 个脚本")
    print()

    # 7. 推荐总结
    print("=" * 55)
    print("💡 使用建议")
    print("=" * 55)
    print("  直接调用对应技能: 在对话中输入 /<skill-name>")
    print("  查看所有技能:     /mgx-skills list")
    print("  搜索技能:         /mgx-skills search <keyword>")


if __name__ == "__main__":
    main()
