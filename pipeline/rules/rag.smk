# MaxMetagenome — RAG Knowledge Base Maintenance Rules
# ==============================================================================
# Builds and updates the ChromaDB-powered RAG knowledge base.
#
# Two collections:
#   experience_kb — team analysis experience (docs, scripts, skill cards)
#   literature_kb — literature methods sections (via PubTator 3.0 + PMC OA)
#
# Usage:
#   snakemake -s pipeline/Snakefile --config rag_refresh=true
# ==============================================================================

REPO = config["repo"]


rule build_experience_kb:
    """Index docs/, scripts/, agents/skills/ into ChromaDB experience_kb collection."""
    output:
        REPO + "/mcp/chromadb_data/experience_kb_ready.sentinel"
    params:
        repo = REPO
    log:
        REPO + "/logs/rag/build_experience_kb.log"
    threads: 4
    shell:
        "conda run --prefix {params.repo}/envs/rag "
        "python {params.repo}/mcp/indexer.py "
        "--repo {params.repo} --force "
        "> {log} 2>&1 && touch {output}"


rule refresh_literature_kb:
    """Query PubTator 3.0, download PMC OA full texts, extract Methods sections,
       annotate with PubTator, embed, and index into ChromaDB literature_kb.
       Requires internet access to NCBI/PubTator APIs."""
    output:
        REPO + "/mcp/chromadb_data/literature_kb_ready.sentinel"
    params:
        repo = REPO
    log:
        REPO + "/logs/rag/refresh_literature_kb.log"
    threads: 2
    shell:
        "conda run --prefix {params.repo}/envs/rag "
        "python {params.repo}/mcp/literature_pipeline.py "
        "--repo {params.repo} --max-articles 100 "
        "> {log} 2>&1 && touch {output}"
