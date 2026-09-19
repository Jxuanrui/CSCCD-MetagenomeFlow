#!/usr/bin/env python3
"""glm_router — MCP server exposing the official GLM models for agent use.

Calls the official Zhipu open platform (OpenAI-compatible). Credentials are
read from (1) env GLM_API_KEY / GLM_API_BASE if set, else (2) the local
key file ~/.glm_router_api_key (chmod 600, OUTSIDE the repo) — never from
this repo, never logged, never printed.

Tool: glm_call(model, prompt, system?, temperature?, max_tokens?)
  model: "glm-5.3" (flagship: planning/review/deep coding) or "glm-5.3-flash"
         (high-frequency, cost-sensitive, multimodal-friendly).
Routing policy lives in CLAUDE.md §5.3; this server is transport only.
"""
import argparse
import asyncio
import json
import os
import sys

import requests

DEFAULT_BASE = "https://open.bigmodel.cn/api/paas/v4"
MODELS = ("glm-5.3", "glm-5.3-flash")
KEY_FILE = os.path.expanduser("~/.glm_router_api_key")


def _credentials():
    """API key/base: env first, then the local key file. Never print."""
    base = os.environ.get("GLM_API_BASE") or DEFAULT_BASE
    key = os.environ.get("GLM_API_KEY")
    if not key and os.path.isfile(KEY_FILE):
        try:
            key = open(KEY_FILE).read().strip()
        except OSError:
            key = None
    return base, key


def chat(model, prompt, system=None, temperature=None, max_tokens=None):
    base, key = _credentials()
    if not key:
        raise RuntimeError(
            "GLM API key not found: set GLM_API_KEY or create "
            f"{KEY_FILE} (chmod 600)"
        )
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    payload = {"model": model, "messages": messages}
    if temperature is not None:
        payload["temperature"] = temperature
    if max_tokens:
        payload["max_tokens"] = max_tokens
    resp = requests.post(
        f"{base.rstrip('/')}/chat/completions",
        headers={"Authorization": f"Bearer {key}"},
        json=payload,
        timeout=300,
    )
    resp.raise_for_status()
    data = resp.json()
    usage = data.get("usage", {})
    message = data["choices"][0]["message"]
    content = message.get("content") or ""
    reasoning = message.get("reasoning_content") or ""
    # glm-5.3 is a hybrid-reasoning model: small max_tokens budgets can be
    # consumed entirely by reasoning_content, leaving content empty. Surface
    # the reasoning in that case (flagged) instead of returning "".
    if not content.strip() and reasoning:
        content = reasoning
        meta_content_source = "reasoning"
    else:
        meta_content_source = "final"
    details = usage.get("completion_tokens_details") or {}
    return (
        content,
        {
            "model": data.get("model", model),
            "prompt_tokens": usage.get("prompt_tokens"),
            "completion_tokens": usage.get("completion_tokens"),
            "reasoning_tokens": details.get("reasoning_tokens"),
            "content_source": meta_content_source,
        },
    )


def main():
    from mcp.server.lowlevel import NotificationOptions, Server
    from mcp.server.stdio import stdio_server
    import mcp.types as types

    server = Server("glm-router")

    @server.list_tools()
    async def list_tools():
        return [
            types.Tool(
                name="glm_call",
                description=(
                    "Call a configured GLM model. model='glm-5.3' for complex "
                    "planning / review / deep multi-round coding; "
                    "model='glm-5.3-flash' for high-frequency, cost-sensitive "
                    "or bulk mechanical execution. See CLAUDE.md 5.3 for the "
                    "routing policy."
                ),
                inputSchema={
                    "type": "object",
                    "properties": {
                        "model": {"type": "string", "enum": list(MODELS)},
                        "prompt": {"type": "string"},
                        "system": {"type": "string"},
                        "temperature": {"type": "number"},
                        "max_tokens": {"type": "integer"},
                    },
                    "required": ["model", "prompt"],
                },
            )
        ]

    @server.call_tool()
    async def call_tool(name, arguments):
        if name != "glm_call":
            raise ValueError(f"unknown tool: {name}")
        text, meta = chat(
            arguments["model"],
            arguments["prompt"],
            system=arguments.get("system"),
            temperature=arguments.get("temperature"),
            max_tokens=arguments.get("max_tokens"),
        )
        return [types.TextContent(type="text", text=json.dumps(
            {"content": text, **meta}, ensure_ascii=False))]

    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()

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
