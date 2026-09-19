#!/usr/bin/env python3
"""glm_router — MCP server exposing the configured GLM models for agent use.

Wraps the OpenAI-compatible endpoint configured in ~/.config/opencode/opencode.json
(provider "xianyu-temp": glm-5.3, glm-5.3-flash). Credentials are read from
(1) env GLM_API_KEY / GLM_API_BASE if set, else (2) the opencode config file —
never from this repo, never logged.

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

DEFAULT_BASE = "https://llm.goaichat.top/v1"
MODELS = ("glm-5.3", "glm-5.3-flash")
OPENCODE_CONFIG = os.path.expanduser("~/.config/opencode/opencode.json")


def _credentials():
    """API key/base: env first, then the user's opencode config. Never print."""
    base = os.environ.get("GLM_API_BASE")
    key = os.environ.get("GLM_API_KEY")
    if key:
        return base or DEFAULT_BASE, key
    try:
        cfg = json.load(open(OPENCODE_CONFIG))
        prov = cfg.get("provider", {}).get("xianyu-temp", {}).get("options", {})
        key = prov.get("apiKey")
        base = base or prov.get("baseURL") or DEFAULT_BASE
    except Exception:
        base = base or DEFAULT_BASE
    return base, key


def chat(model, prompt, system=None, temperature=None, max_tokens=None):
    base, key = _credentials()
    if not key:
        raise RuntimeError(
            "GLM API key not found: set GLM_API_KEY or configure "
            'provider "xianyu-temp" in ~/.config/opencode/opencode.json'
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
    return (
        data["choices"][0]["message"]["content"],
        {
            "model": data.get("model", model),
            "prompt_tokens": usage.get("prompt_tokens"),
            "completion_tokens": usage.get("completion_tokens"),
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
