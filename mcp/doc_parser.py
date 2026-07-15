#!/usr/bin/env python

import re
import sys
from pathlib import Path

import yaml


_TOKENIZER = None


def set_tokenizer(tokenizer):
    """Register a tokenizer for chunk sizing."""
    global _TOKENIZER
    _TOKENIZER = tokenizer


def _warn(filepath, message):
    print(f"[doc_parser] WARNING {filepath}: {message}", file=sys.stderr)


def _safe_read(filepath):
    return Path(filepath).read_text(encoding="utf-8")


def _stringify_items(items):
    if not items:
        return ""
    values = []
    for item in items:
        if isinstance(item, dict):
            label = item.get("name") or item.get("id") or item.get("path_pattern") or item.get("path")
            detail = item.get("path_pattern") or item.get("description") or item.get("path") or ""
            if label and detail and label != detail:
                values.append(f"{label}={detail}")
            elif label:
                values.append(str(label))
            elif detail:
                values.append(str(detail))
        else:
            values.append(str(item))
    return ", ".join([value for value in values if value])


def _normalize_scalar(value):
    if value is None:
        return ""
    if isinstance(value, list):
        return ", ".join([str(item) for item in value if str(item).strip()])
    return str(value).strip()


def _strip_markdown_title(text):
    return re.sub(r"^#\s+.+?(?:\n|$)", "", text, count=1, flags=re.M).lstrip()


def _extract_first_h1(text, fallback):
    match = re.search(r"^#\s+(.+?)\s*$", text, re.M)
    return match.group(1).strip() if match else fallback


def _split_markdown_sections(text):
    sections = []
    current_section = "Overview"
    current_lines = []
    for line in text.splitlines():
        heading = re.match(r"^##\s+(.+?)\s*$", line)
        if heading:
            chunk_text_value = "\n".join(current_lines).strip()
            if chunk_text_value:
                sections.append((current_section, chunk_text_value))
            current_section = heading.group(1).strip()
            current_lines = []
            continue
        current_lines.append(line)
    tail = "\n".join(current_lines).strip()
    if tail:
        sections.append((current_section, tail))
    return sections


def _count_tokens(text):
    if not text or not text.strip():
        return 0
    if _TOKENIZER is not None:
        try:
            return len(_TOKENIZER.encode(text, add_special_tokens=False))
        except Exception:
            pass
    chinese_chars = len(re.findall(r"[\u4e00-\u9fff]", text))
    other_chars = len(re.sub(r"\s+", "", re.sub(r"[\u4e00-\u9fff]", "", text)))
    return max(1, (chinese_chars + 1) // 2 + (other_chars + 3) // 4)


def _tail_overlap_text(text, overlap):
    if not text or overlap <= 0:
        return ""
    if _TOKENIZER is not None:
        try:
            token_ids = _TOKENIZER.encode(text, add_special_tokens=False)
            if len(token_ids) <= overlap:
                return text
            return _TOKENIZER.decode(token_ids[-overlap:], skip_special_tokens=True).strip()
        except Exception:
            pass
    approx_chars = max(overlap * 3, overlap)
    return text[-approx_chars:].strip()


def _split_large_text(text, chunk_size, overlap):
    sentences = [
        part.strip()
        for part in re.split(r"(?<=[。！？!?；;])\s*|(?<=\.)\s+|\n", text)
        if part and part.strip()
    ]
    if not sentences:
        sentences = [text.strip()]

    chunks = []
    current = ""
    for sentence in sentences:
        if _count_tokens(sentence) > chunk_size:
            if current:
                chunks.append(current.strip())
                current = ""
            chunks.extend(_split_by_chars(sentence, chunk_size, overlap))
            continue

        candidate = sentence if not current else f"{current}\n{sentence}"
        if current and _count_tokens(candidate) > chunk_size:
            chunks.append(current.strip())
            overlap_text = _tail_overlap_text(current, overlap)
            current = sentence if not overlap_text else f"{overlap_text}\n{sentence}".strip()
            if _count_tokens(current) > chunk_size:
                current = sentence
        else:
            current = candidate

    if current:
        chunks.append(current.strip())
    return [chunk for chunk in chunks if chunk]


def _split_by_chars(text, chunk_size, overlap):
    approx_chars = max(chunk_size * 4, 240)
    overlap_chars = max(overlap * 3, 0)
    step = approx_chars - overlap_chars
    if step <= 0:
        step = approx_chars

    chunks = []
    start = 0
    while start < len(text):
        piece = text[start:start + approx_chars].strip()
        if piece:
            chunks.append(piece)
        start += step
    return chunks


def chunk_text(text, chunk_size=512, overlap=80):
    """按段落优先切分文本，必要时降级到句子或字符窗口。"""
    try:
        if not text or not text.strip():
            return []

        paragraphs = [
            paragraph.strip()
            for paragraph in re.split(r"\n\s*\n+", text.strip())
            if paragraph and paragraph.strip()
        ]
        if not paragraphs:
            return []

        chunks = []
        current = ""
        for paragraph in paragraphs:
            if _count_tokens(paragraph) > chunk_size:
                if current:
                    chunks.append(current.strip())
                    current = ""
                chunks.extend(_split_large_text(paragraph, chunk_size, overlap))
                continue

            candidate = paragraph if not current else f"{current}\n\n{paragraph}"
            if current and _count_tokens(candidate) > chunk_size:
                chunks.append(current.strip())
                current = paragraph
            else:
                current = candidate

        if current:
            chunks.append(current.strip())

        return [chunk for chunk in chunks if chunk]
    except Exception:
        return []


def parse_experience_doc(filepath):
    """Parse docs/experience/*.md into section-aware chunks."""
    try:
        raw_text = _safe_read(filepath)
        match = re.match(r"^\s*---\s*\n(.*?)\n---\s*\n?(.*)$", raw_text, re.S)
        if not match:
            _warn(filepath, "missing YAML frontmatter")
            return []

        frontmatter = yaml.safe_load(match.group(1)) or {}
        body = match.group(2).strip()
        title = _extract_first_h1(body, Path(filepath).stem)
        sections = _split_markdown_sections(_strip_markdown_title(body))
        if not sections:
            sections = [("Overview", _strip_markdown_title(body))]

        base_metadata = {
            "doc_type": "experience",
            "tool": _normalize_scalar(frontmatter.get("tool")),
            "dimension": _normalize_scalar(frontmatter.get("dimension")),
            "category": _normalize_scalar(frontmatter.get("category")),
            "author": _normalize_scalar(frontmatter.get("author")),
            "date": _normalize_scalar(frontmatter.get("date")),
            "tags": frontmatter.get("tags") or [],
            "scenario": frontmatter.get("scenario") or [],
            "source_path": str(Path(filepath)),
            "title": title,
        }

        parsed_chunks = []
        for section_name, section_text in sections:
            for section_chunk in chunk_text(section_text):
                chunk_body = f"# {title}\n## {section_name}\n\n{section_chunk}".strip()
                metadata = dict(base_metadata)
                metadata["section"] = section_name
                parsed_chunks.append((chunk_body, metadata))
        return parsed_chunks
    except Exception as exc:
        _warn(filepath, f"failed to parse experience doc: {exc}")
        return []


def parse_tool_doc(filepath):
    """Parse docs/**/*.md into title/section chunks."""
    try:
        raw_text = _safe_read(filepath)
        title = _extract_first_h1(raw_text, Path(filepath).stem)
        body = _strip_markdown_title(raw_text)
        sections = _split_markdown_sections(body)
        if not sections:
            sections = [("Overview", body.strip())]

        category = Path(filepath).parent.name
        parsed_chunks = []
        for section_name, section_text in sections:
            if not section_text.strip():
                continue
            has_table = bool(re.search(r"^\|.+\|\s*$", section_text, re.M))
            has_code_block = "```" in section_text
            for section_chunk in chunk_text(section_text):
                chunk_body = f"# {title}\n## {section_name}\n\n{section_chunk}".strip()
                metadata = {
                    "doc_type": "tool_doc",
                    "tool_name": title,
                    "category": category,
                    "section": section_name,
                    "has_table": has_table,
                    "has_code_block": has_code_block,
                    "source_path": str(Path(filepath)),
                }
                parsed_chunks.append((chunk_body, metadata))
        return parsed_chunks
    except Exception as exc:
        _warn(filepath, f"failed to parse tool doc: {exc}")
        return []


def _extract_script_tool_name(header_lines, filepath):
    for line in header_lines:
        match = re.search(r"工具版本[:：]\s*([A-Za-z0-9._+-]+(?:\s+[A-Za-z0-9._+-]+)*)", line)
        if match:
            return match.group(1).strip().split("（")[0].split("(")[0].strip()
    stem_parts = Path(filepath).stem.split("_", 2)
    if len(stem_parts) == 3:
        return stem_parts[2]
    return Path(filepath).stem


def _extract_header_block(filepath):
    lines = _safe_read(filepath).splitlines()
    header_lines = []
    started = False
    for line in lines:
        if line.startswith("#!"):
            continue
        if not started and not line.strip():
            continue
        if line.startswith("#"):
            started = True
            header_lines.append(re.sub(r"^#\s?", "", line).rstrip())
            continue
        if started:
            break
        break
    return header_lines


def parse_script_header(filepath):
    """Parse shell script comment headers into summary and parameter chunks."""
    try:
        script_path = Path(filepath)
        header_lines = _extract_header_block(filepath)
        if not header_lines:
            _warn(filepath, "missing comment header block")
            return []

        fields = {}
        sections = {"关键参数": [], "推荐": [], "注意": []}
        current_field = ""
        current_section = ""
        label_pattern = re.compile(
            r"^(脚本名|功\s*能|功能|依\s*赖|依赖|输\s*入|输入|输\s*出|输出|参\s*考|参考|用\s*法|用法|数\s*据|数据)\s*[:：]\s*(.*)$"
        )

        for raw_line in header_lines:
            line = raw_line.strip()
            if not line:
                continue

            section_match = re.search(r"(关键参数|推荐|注意)", line)
            if line.startswith("──") or line.startswith("─") or "──" in line:
                current_field = ""
                current_section = section_match.group(1) if section_match else ""
                continue

            field_match = label_pattern.match(line)
            if field_match:
                current_section = ""
                current_field = field_match.group(1).replace(" ", "")
                fields.setdefault(current_field, [])
                if field_match.group(2).strip():
                    fields[current_field].append(field_match.group(2).strip())
                continue

            if current_section in sections:
                sections[current_section].append(line)
                continue

            if current_field:
                fields.setdefault(current_field, []).append(line)

        script_id = script_path.stem
        tool_name = _extract_script_tool_name(header_lines, filepath)
        function_text = ""
        for key in fields:
            if "功能" in key:
                function_text = "\n".join(fields.get(key, [])).strip()
                if function_text:
                    break

        inputs_text = ""
        outputs_text = ""
        usage_text = ""
        for key in fields:
            if "输入" in key and not inputs_text:
                inputs_text = "\n".join(fields[key]).strip()
            if "输出" in key and not outputs_text:
                outputs_text = "\n".join(fields[key]).strip()
            if "用法" in key and not usage_text:
                usage_text = "\n".join(fields[key]).strip()

        parsed_chunks = []
        summary_lines = [
            f"Script: {script_id}",
            f"Tool: {tool_name}",
        ]
        if function_text:
            summary_lines.append(f"Function: {function_text}")
        if inputs_text:
            summary_lines.append(f"Inputs: {inputs_text}")
        if outputs_text:
            summary_lines.append(f"Outputs: {outputs_text}")
        if usage_text:
            summary_lines.append(f"Usage: {usage_text}")

        summary_metadata = {
            "doc_type": "parameter_guidance",
            "script_id": script_id,
            "tool_name": tool_name,
            "source_path": str(script_path),
            "section": "summary",
        }
        parsed_chunks.append(("\n".join(summary_lines), summary_metadata))

        for section_name in ["关键参数", "推荐", "注意"]:
            section_lines = sections.get(section_name, [])
            if not section_lines:
                continue
            section_text = "\n".join(section_lines).strip()
            if not section_text:
                continue
            metadata = {
                "doc_type": "parameter_guidance",
                "script_id": script_id,
                "tool_name": tool_name,
                "source_path": str(script_path),
                "section": section_name,
            }
            parsed_chunks.append((f"Script: {script_id}\nSection: {section_name}\n{section_text}", metadata))

        seen_params = {}
        for raw_line in header_lines:
            if "--" not in raw_line:
                continue
            for match in re.finditer(r"(--[A-Za-z0-9][A-Za-z0-9_-]*)(?:[=\s]+([^\s,;，。]+))?", raw_line):
                param_name = match.group(1)
                if param_name in seen_params:
                    continue
                seen_params[param_name] = raw_line.strip()

        for param_name, param_line in seen_params.items():
            metadata = {
                "doc_type": "parameter_guidance",
                "script_id": script_id,
                "tool_name": tool_name,
                "param_name": param_name,
                "source_path": str(script_path),
                "section": "parameter",
            }
            parsed_chunks.append((f"Script: {script_id}\nParameter: {param_name}\n{param_line}", metadata))

        return parsed_chunks
    except Exception as exc:
        _warn(filepath, f"failed to parse script header: {exc}")
        return []


def parse_skill_card(filepath):
    """Parse YAML skill cards into summary chunks plus known issues."""
    try:
        skill_data = yaml.safe_load(_safe_read(filepath)) or {}
        base_metadata = {
            "doc_type": "skill_card",
            "tool": _normalize_scalar(skill_data.get("tool")),
            "dimension": _normalize_scalar(skill_data.get("dimension")),
            "category": _normalize_scalar(skill_data.get("category")),
            "script_id": _normalize_scalar(skill_data.get("id")),
            "source_path": str(Path(filepath)),
        }

        summary_text = (
            f"Tool: {_normalize_scalar(skill_data.get('tool'))} "
            f"v{_normalize_scalar(skill_data.get('tool_version'))}, "
            f"Dimension: {_normalize_scalar(skill_data.get('dimension'))}, "
            f"Category: {_normalize_scalar(skill_data.get('category'))}, "
            f"Environment: {_normalize_scalar(skill_data.get('conda_env'))}, "
            f"Inputs: {_stringify_items(skill_data.get('inputs') or [])}, "
            f"Outputs: {_stringify_items(skill_data.get('outputs') or [])}"
        )

        parsed_chunks = [(summary_text, dict(base_metadata))]
        known_issues = skill_data.get("known_issues") or []
        for issue_index, issue_text in enumerate(known_issues, start=1):
            metadata = dict(base_metadata)
            metadata["issue_index"] = issue_index
            metadata["section"] = "known_issue"
            parsed_chunks.append(
                (
                    f"Tool: {_normalize_scalar(skill_data.get('tool'))}\nKnown issue {issue_index}: {issue_text}",
                    metadata,
                )
            )
        return parsed_chunks
    except Exception as exc:
        _warn(filepath, f"failed to parse skill card: {exc}")
        return []


def parse_snakemake_rule(filepath):
    """Extract each rule block from a Snakemake rules file."""
    try:
        raw_text = _safe_read(filepath)
        rule_pattern = re.compile(r"(^rule\s+([A-Za-z0-9_]+):.*?)(?=^rule\s+[A-Za-z0-9_]+:|\Z)", re.M | re.S)
        parsed_chunks = []

        for match in rule_pattern.finditer(raw_text):
            block = match.group(1).strip()
            rule_name = match.group(2).strip()

            input_match = re.search(r"^\s*input:\s*(.*?)(?=^\s*(output|params|threads|resources|log|benchmark|shell|script|run):|\Z)", block, re.M | re.S)
            output_match = re.search(r"^\s*output:\s*(.*?)(?=^\s*(input|params|threads|resources|log|benchmark|shell|script|run):|\Z)", block, re.M | re.S)

            input_paths = re.findall(r"['\"]([^'\"]+)['\"]", input_match.group(1) if input_match else "")
            output_paths = re.findall(r"['\"]([^'\"]+)['\"]", output_match.group(1) if output_match else "")

            summary_lines = [
                f"Rule: {rule_name}",
                f"Inputs: {', '.join(input_paths) if input_paths else 'N/A'}",
                f"Outputs: {', '.join(output_paths) if output_paths else 'N/A'}",
                block,
            ]
            metadata = {
                "doc_type": "snakemake_rule",
                "rule_name": rule_name,
                "source_path": str(Path(filepath)),
            }
            parsed_chunks.append(("\n".join(summary_lines), metadata))

        return parsed_chunks
    except Exception as exc:
        _warn(filepath, f"failed to parse snakemake rule file: {exc}")
        return []


def parse_agent_skill_doc(filepath):
    """Parse native Agent Skill markdown docs into section-aware chunks."""
    try:
        raw_text = _safe_read(filepath)
        match = re.match(r"^\s*---\s*\n(.*?)\n---\s*\n?(.*)$", raw_text, re.S)
        if not match:
            _warn(filepath, "missing YAML frontmatter")
            return []

        frontmatter = yaml.safe_load(match.group(1)) or {}
        if not isinstance(frontmatter, dict):
            _warn(filepath, "malformed YAML frontmatter")
            return []

        body = match.group(2)
        skill_name = _normalize_scalar(frontmatter.get("name")) or Path(filepath).stem
        description = _normalize_scalar(frontmatter.get("description"))
        sections = _split_markdown_sections(body)
        if not sections:
            sections = [("Overview", body.strip())]

        parsed_chunks = []
        for section_name, section_text in sections:
            for section_chunk in chunk_text(section_text):
                chunk_body = f"# {skill_name}\n## {section_name}\n\n{section_chunk}".strip()
                metadata = {
                    "doc_type": "agent_skill",
                    "skill_name": skill_name,
                    "description": description,
                    "section": section_name,
                    "source_path": str(Path(filepath)),
                }
                parsed_chunks.append((chunk_body, metadata))
        return parsed_chunks
    except Exception as exc:
        _warn(filepath, f"failed to parse agent skill doc: {exc}")
        return []
