#!/usr/bin/env python3
"""mgx-vis — MCP stdio server for MaxMetagenome figure orchestration.

Three tools: vis_scan / vis_render / vis_mining. The server NEVER plots
anything itself. vis_render delegates drawing to the stable orbit-0 pipeline
scripts (scripts/94_visualization, 91_diversity, 92_differential,
93_cooccurrence, 99b_lefse wrappers) with MGX_FIGURE_FORMATS=pdf,png injected;
vis_mining prepares TSVs from mining/seed_registry.sqlite (read-only) and
delegates drawing to mcp/vis/render_mining.R. Core logic: mcp/vis/extract.py.
"""
import asyncio
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from vis.extract import CHART_FAMILIES, MINING_CHARTS, mining, render, scan  # noqa: E402


def _require_workdir(arguments: dict) -> tuple[str | None, dict | None]:
    workdir = str(arguments.get("workdir") or "").strip()
    if not workdir:
        return None, {"error": "workdir is required"}
    workdir = os.path.abspath(os.path.expanduser(workdir))
    if not os.path.isdir(workdir):
        return None, {"error": f"workdir not found: {workdir}"}
    return workdir, None


def _handle_scan(arguments: dict) -> dict:
    workdir, error = _require_workdir(arguments)
    if error:
        return error
    return scan(workdir)


def _handle_render(arguments: dict) -> dict:
    workdir, error = _require_workdir(arguments)
    if error:
        return error
    charts = arguments.get("charts")
    if charts is not None and not isinstance(charts, list):
        return {"error": "charts must be an array of chart family names"}
    try:
        return render(
            workdir,
            charts=charts,
            group_col=arguments.get("group_col"),
            force=bool(arguments.get("force", False)),
        )
    except ValueError as exc:
        return {"error": str(exc)}


def _handle_mining(arguments: dict) -> dict:
    charts = arguments.get("charts")
    if charts is not None and not isinstance(charts, list):
        return {"error": "charts must be an array of mining chart names"}
    try:
        return mining(db_path=arguments.get("db_path"), charts=charts)
    except ValueError as exc:
        return {"error": str(exc)}


def main() -> None:
    from mcp.server.lowlevel import NotificationOptions, Server
    from mcp.server.stdio import stdio_server
    import mcp.types as types

    server = Server("mgx-vis")

    @server.list_tools()
    async def list_tools():
        return [
            types.Tool(
                name="vis_scan",
                description=(
                    "Scan a project workdir for chart-ready input tables "
                    "(composition, alpha diversity, PCoA, differential, network, "
                    "LEfSe) and already-rendered figures under result/stat/. "
                    "Detection only; all plotting is delegated to existing "
                    "pipeline scripts (orbit-0 reuse policy)."
                ),
                inputSchema={
                    "type": "object",
                    "properties": {
                        "workdir": {
                            "type": "string",
                            "description": "Absolute project workdir containing result/stat/.",
                        },
                    },
                    "required": ["workdir"],
                },
            ),
            types.Tool(
                name="vis_render",
                description=(
                    "(Re)render figure families by re-invoking the stable orbit-0 "
                    "pipeline scripts (94 visualization, 91 diversity, 92 "
                    "differential, 93 co-occurrence network, 99b LEfSe); injects "
                    "MGX_FIGURE_FORMATS=pdf,png and GROUP_COL. This server "
                    "orchestrates only — every plot is drawn by the pipeline "
                    "scripts' R backends."
                ),
                inputSchema={
                    "type": "object",
                    "properties": {
                        "workdir": {
                            "type": "string",
                            "description": "Absolute project workdir containing result/stat/.",
                        },
                        "charts": {
                            "type": "array",
                            "items": {"type": "string", "enum": list(CHART_FAMILIES)},
                            "description": "Chart families to render; default: every family with detected inputs.",
                        },
                        "group_col": {
                            "type": "string",
                            "description": "Group column in the metadata (default: group).",
                        },
                        "force": {
                            "type": "boolean",
                            "description": "Pass --force so orbit-0 scripts rerun past their sentinels.",
                        },
                    },
                    "required": ["workdir"],
                },
            ),
            types.Tool(
                name="vis_mining",
                description=(
                    "Render seed-registry mining overview charts (attribute value "
                    "counts, source overlap matrix). Computes TSVs read-only from "
                    "mining/seed_registry.sqlite and delegates drawing to "
                    "mcp/vis/render_mining.R (R renderer owned by a parallel "
                    "track; if absent, status renderer_not_found is reported "
                    "with the prepared TSV/spec paths — not an error)."
                ),
                inputSchema={
                    "type": "object",
                    "properties": {
                        "db_path": {
                            "type": "string",
                            "description": "Path to seed_registry.sqlite (default: <repo>/mining/seed_registry.sqlite).",
                        },
                        "charts": {
                            "type": "array",
                            "items": {"type": "string", "enum": list(MINING_CHARTS)},
                            "description": "Mining charts to render (default: both).",
                        },
                    },
                },
            ),
        ]

    @server.call_tool()
    async def call_tool(name, arguments):
        arguments = arguments or {}
        try:
            if name == "vis_scan":
                payload = _handle_scan(arguments)
            elif name == "vis_render":
                payload = _handle_render(arguments)
            elif name == "vis_mining":
                payload = _handle_mining(arguments)
            else:
                payload = {"error": f"unknown tool: {name}"}
        except Exception as exc:  # never crash the stdio server
            payload = {"error": f"{type(exc).__name__}: {exc}"}
        content = [types.TextContent(type="text", text=json.dumps(payload, ensure_ascii=False))]
        if isinstance(payload, dict) and "error" in payload:
            return types.CallToolResult(content=content, isError=True)
        return content

    async def _run():
        async with stdio_server() as (read_stream, write_stream):
            await server.run(
                read_stream,
                write_stream,
                server.create_initialization_options(NotificationOptions()),
            )

    asyncio.run(_run())


if __name__ == "__main__":
    main()
