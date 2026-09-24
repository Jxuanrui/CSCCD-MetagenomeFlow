#!/usr/bin/env python3
"""
score.py — Skills 相关性评分引擎
从 raw_findings.json 读取原始发现数据，应用关键词 + 质量 + 生态评分，
输出排序后的候选列表和月报。

用法:
    python3 score.py --input raw_findings.json --output report/
    python3 score.py --input raw_findings.json --output report/ --dry-run
"""

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# === 配置 ===
# 关键词分层（与 config.yaml 保持一致）
TIER1 = ["microbiome", "metagenom", "gut", "bacteria", "fungus", "fungi", "virus", "virome"]
TIER2 = ["taxonomy", "diversity", "abundance", "annotation", "pathway", "assembly",
         "binning", "kegg", "cazy", "amr", "lipid", "metabolom"]
TIER3 = ["kraken", "metaphlan", "humann", "qiime", "dada2", "phyloseq",
         "picrust", "lefse", "maaslin", "vegan", "spieceasi"]
WRITING_KEYWORDS = ["academic writing", "paper", "manuscript", "polish", "writing",
                    "reviewer", "response letter", "abstract"]
VIZ_KEYWORDS = ["figure", "plot", "visualization", "chart", "graph",
                "scientific figure", "publication figure", "color"]

SCORE_WEIGHTS = {
    "domain": 0.40,
    "quality": 0.30,
    "ecosystem": 0.20,
    "negative": -0.10,
}

DOMAIN_SCORES = {"tier1": 30, "tier2": 15, "tier3": 10, "writing": 25, "viz": 20}
QUALITY_MAX_STARS = 20
STARS_PER_POINT = 100
RECENT_SCORE = 10
RECENT_MONTHS = 3
LICENSE_SCORE = 5
STALE_PENALTY = -10
STALE_MONTHS = 12
SHORT_DESC_PENALTY = -5
SHORT_DESC_CHARS = 50


def match_keywords(text, keywords):
    """模糊关键词匹配（大小写不敏感）"""
    text_lower = text.lower()
    count = 0
    for kw in keywords:
        if kw.lower() in text_lower:
            count += 1
    return count


def score_domain(item):
    """领域关键词评分"""
    desc = item.get("description", "") + " " + item.get("name", "")
    tags_text = " ".join(item.get("tags", []))
    combined = desc + " " + tags_text

    score = 0
    score += match_keywords(combined, TIER1) * DOMAIN_SCORES["tier1"]
    score += match_keywords(combined, TIER2) * DOMAIN_SCORES["tier2"]
    score += match_keywords(combined, TIER3) * DOMAIN_SCORES["tier3"]
    score += match_keywords(combined, WRITING_KEYWORDS) * DOMAIN_SCORES["writing"]
    score += match_keywords(combined, VIZ_KEYWORDS) * DOMAIN_SCORES["viz"]
    return score


def score_quality(item):
    """质量信号评分"""
    score = 0

    # Stars
    stars = item.get("stars", 0)
    score += min(stars / STARS_PER_POINT, QUALITY_MAX_STARS)

    # 最近更新
    updated = item.get("updated_at", "")
    if updated:
        try:
            updated_dt = datetime.fromisoformat(updated.replace("Z", "+00:00"))
            delta = datetime.now(timezone.utc) - updated_dt
            if delta.days < RECENT_MONTHS * 30:
                score += RECENT_SCORE
        except (ValueError, TypeError):
            pass

    # 开源许可
    license_name = item.get("license", "")
    if license_name.lower() in ("mit", "apache-2.0", "bsd-2-clause", "bsd-3-clause", "bsd"):
        score += LICENSE_SCORE

    return score


def score_ecosystem(item):
    """生态影响力评分"""
    score = 0
    # SkillsMP or skills.sh ranking
    ranking = item.get("ranking", 0)
    if ranking > 0:
        score += min(ranking / 10, 10)

    # 被多少聚合仓库收录
    collected_by = item.get("collected_by", 0)
    score += min(collected_by * 3, 10)

    return score


def score_negative(item):
    """负向信号评分"""
    score = 0

    # 过时
    updated = item.get("updated_at", "")
    if updated:
        try:
            updated_dt = datetime.fromisoformat(updated.replace("Z", "+00:00"))
            delta = datetime.now(timezone.utc) - updated_dt
            if delta.days > STALE_MONTHS * 30:
                score += STALE_PENALTY
        except (ValueError, TypeError):
            pass

    # description 过短
    desc = item.get("description", "")
    if len(desc) < SHORT_DESC_CHARS:
        score += SHORT_DESC_PENALTY

    return score


def classify_category(item):
    """根据关键词自动分类"""
    desc = item.get("description", "") + " " + item.get("name", "")
    text_lower = desc.lower()

    if any(kw in text_lower for kw in WRITING_KEYWORDS):
        return "writing"
    if any(kw in text_lower for kw in VIZ_KEYWORDS):
        return "visualization"
    if any(kw in text_lower for kw in ["citation", "reference", "bibliography", "paper search"]):
        return "citation"
    if any(kw in text_lower for kw in ["literature", "paper reader", "read paper"]):
        return "literature"
    if any(kw in text_lower for kw in ["data", "fair", "metadata", "availability"]):
        return "data"
    if any(kw in text_lower for kw in TIER1 + TIER2 + TIER3):
        return "analysis"
    if any(kw in text_lower for kw in ["statistical", "experimental design", "power analysis"]):
        return "methodology"
    return "other"


def score_all(findings):
    """对全部发现进行评分"""
    scored = []
    for item in findings:
        domain_s = score_domain(item)
        quality_s = score_quality(item)
        eco_s = score_ecosystem(item)
        neg_s = score_negative(item)

        total = (
            domain_s * SCORE_WEIGHTS["domain"]
            + quality_s * SCORE_WEIGHTS["quality"]
            + eco_s * SCORE_WEIGHTS["ecosystem"]
            + neg_s * SCORE_WEIGHTS["negative"]
        )

        item["scores"] = {
            "domain": round(domain_s, 1),
            "quality": round(quality_s, 1),
            "ecosystem": round(eco_s, 1),
            "negative": round(neg_s, 1),
            "total": round(total, 1),
        }
        item["category"] = item.get("category", classify_category(item))
        scored.append(item)

    scored.sort(key=lambda x: x["scores"]["total"], reverse=True)
    return scored


def render_markdown_report(scored, month_str, stats):
    """渲染月报 Markdown"""
    lines = []
    lines.append(f"# Skills 发现月报 — {month_str}")
    lines.append("")
    lines.append("## 📌 摘要")
    lines.append(f"- **扫描范围**: GitHub topic 搜索, SkillsMP, skills.sh, 聚合仓库")
    lines.append(f"- **原始匹配**: {stats.get('total_raw', 0)} 个技能")
    lines.append(f"- **去重后**: {stats.get('total_deduped', 0)} 个")
    lines.append(f"- **评分阈值以上**: {len(scored)} 个进入本报告")
    lines.append("")

    # 强烈推荐（总分 >= 60）
    top = [s for s in scored if s["scores"]["total"] >= 60]
    if top:
        lines.append("## ⭐ 强烈推荐")
        lines.append(f"| 名称 | 来源 | 分类 | ⭐ | 分 | 说明 |")
        lines.append(f"|------|------|------|----|----|------|")
        for s in top:
            lines.append(
                f"| {s.get('name', s.get('id', '?'))} "
                f"| {s.get('source', {}).get('repo', '?')} "
                f"| {s.get('category', '?')} "
                f"| {s.get('stars', 0)} "
                f"| {s['scores']['total']} "
                f"| {s.get('description', '')[:40]} |"
            )
        lines.append("")

    # 候选列表
    lines.append("## 📋 候选列表")
    lines.append(f"| # | 名称 | 来源 | 分类 | 评分 | 安装方式 |")
    lines.append(f"|---|------|------|------|------|---------|")
    for i, s in enumerate(scored, 1):
        install = s.get("install_method", s.get("source", {}).get("repo", "?"))
        lines.append(
            f"| {i} "
            f"| {s.get('name', s.get('id', '?'))[:25]} "
            f"| {s.get('source', {}).get('repo', '?')[:20]} "
            f"| {s.get('category', '?')} "
            f"| {s['scores']['total']} "
            f"| {install[:30]} |"
        )
    lines.append("")

    # 按类别统计
    lines.append("## 📊 类别分布")
    cat_counts = {}
    for s in scored:
        cat = s.get("category", "other")
        cat_counts[cat] = cat_counts.get(cat, 0) + 1
    for cat, count in sorted(cat_counts.items(), key=lambda x: -x[1]):
        lines.append(f"- **{cat}**: {count} 个")
    lines.append("")

    # 安装建议
    lines.append("## 📦 一键采纳建议")
    for s in scored[:3]:
        lines.append(f"```bash")
        lines.append(f"# {s.get('name', s.get('id', '?'))}")
        lines.append(f"{s.get('install_method', '# 手动安装')}")
        lines.append(f"```")
    lines.append("")
    lines.append(f"---")
    lines.append(f"*生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M')}*")

    return "\n".join(lines)


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Skills 相关性评分引擎")
    parser.add_argument("--input", required=True, help="原始发现 JSON 文件路径")
    parser.add_argument("--output", required=True, help="输出目录（月报存放位置）")
    parser.add_argument("--dry-run", action="store_true", help="预览模式，不写入文件")
    args = parser.parse_args()

    # 读取原始数据
    with open(args.input) as f:
        findings = json.load(f)

    stats = {
        "total_raw": len(findings),
        "total_deduped": len(findings),
    }

    # 评分
    scored = score_all(findings)

    # 按阈值过滤
    min_score = 30  # 对应 lifecycle.yaml 的 min_relevance_score
    scored = [s for s in scored if s["scores"]["total"] >= min_score]

    # 取 Top N
    top_n = 15
    scored = scored[:top_n]

    # 生成月报
    now = datetime.now()
    month_str = now.strftime("%Y-%m")
    report_content = render_markdown_report(scored, month_str, stats)

    if args.dry_run:
        print("=== Dry-Run: 候选列表 ===")
        for s in scored:
            print(f"  [{s['scores']['total']:5.1f}] {s.get('name', s.get('id', '?')):30s} "
                  f"| {s.get('category', '?'):15s} | {s.get('source', {}).get('repo', '?')}")
        print(f"\n=== 月报预览（前 20 行）===")
        for line in report_content.split("\n")[:20]:
            print(line)
        return

    # 写入月报
    output_dir = Path(args.output)
    month_dir = output_dir / month_str
    month_dir.mkdir(parents=True, exist_ok=True)

    report_path = month_dir / "monthly_report.md"
    with open(report_path, "w") as f:
        f.write(report_content)

    # 写入候选 JSON
    candidates_path = month_dir / "candidates.json"
    with open(candidates_path, "w") as f:
        json.dump(scored, f, ensure_ascii=False, indent=2)

    print(f"[score] 月报已生成: {report_path}")
    print(f"[score] 候选 JSON: {candidates_path}")
    print(f"[score] 共 {len(scored)} 个候选进入月报")


if __name__ == "__main__":
    main()
