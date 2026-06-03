# MCP 服务器（§9，待实现）

本目录将存放 MaxMetagenome 的 MCP（Model Context Protocol）服务器代码，
用于将 docs/ 知识库索引到 ChromaDB，并通过 stdio 向 Claude Code / Codex 暴露 RAG 检索接口。

## 规划内容

- `server.py`  — MCP stdio 服务器
- `indexer.py` — docs/ 文档 → ChromaDB 索引构建
- `requirements.txt` — 依赖（sentence-transformers, chromadb, fastapi）

## 挂载方式

```bash
claude mcp add meta-server -- python mcp/server.py
```
