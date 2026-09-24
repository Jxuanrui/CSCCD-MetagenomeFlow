# CSCCD-MetagenomeFlow MCP

本目录提供 CSCCD-MetagenomeFlow 的五知识库检索能力：

- `experience_kb`：索引 `docs/`、`scripts/`、`pipeline/rules/`、`agents/skills/` 等项目经验文档。
- `literature_kb`：索引 Europe PMC 检索到的高影响力肠道菌群文献 Methods 文本块。
- `skill_design_kb`：索引可复用的实验/分析技能设计卡片。
- `mechanism_kb`：索引 GutMGene + MicrobiomeKG 桥接表（菌群-代谢物-基因关联）。
- `signature_kb`：索引 BugSigDB 菌群签名（条件-方向-分类群，默认人类肠道子集，CC BY 4.0）。

当前 chunk 规模：`experience_kb` 1963、`literature_kb` 30826、`skill_design_kb` 130、`mechanism_kb` 5295、`signature_kb` 7669。

两套知识库都使用 `ChromaDB` 持久化，默认嵌入模型为 `BAAI/bge-small-zh-v1.5`。

## 架构概览

### experience_kb

- 入口：`indexer.py`
- 数据来源：`docs/`、`scripts/*.sh`、`pipeline/rules/*.smk`、`agents/skills/*.yaml`
- 分块逻辑：`doc_parser.py`
- 向量库：`mcp/chromadb_data/experience_kb`

### literature_kb

- 入口：`literature_pipeline.py`
- 检索：`europepmc_search.py`
- 全文抓取：`pmc_fetch.py`
- Methods 抽取：`methods_extractor.py`
- 实体补注：`pubtator_annotate.py`
- 分块逻辑：`doc_parser.py`
- 向量库：`mcp/chromadb_data/literature_kb`

文献管线的核心目标是优先收录高引用、高影响力期刊中与肠道菌群分析流程直接相关、且可抽取 Methods 章节的文章。

### mechanism_kb

- 入口：`index_mechanism_kb.py`
- 数据来源：`mcp/data/gutmgene_bridge/bridge_table.json`、`mcp/data/microbiomekg_bridge/bridge_table.json`
- 向量库：`mcp/chromadb_data/mechanism_kb`

### signature_kb

- 入口：`bugsigdb_bridge.py`（构建桥接表）+ `index_signature_kb.py`（索引）
- 数据来源：BugSigDB 官方全量导出 CSV（`https://raw.githubusercontent.com/waldronlab/BugSigDBExports/devel/full_dump.csv`，每小时刷新，CC BY 4.0），缓存于 `/tmp/bugsigdb_full_dump.csv`
- 默认过滤：State=Complete 且 Host species=Homo sapiens 且 Body site 含 gut/feces/intestin/colon/bowel/rectum 等肠道词（`--all` 可关闭过滤）
- 分块逻辑：每条签名一个 chunk（条件 + 身体部位 + 分类群摘要 + 方向 + 分组 + PMID）
- 向量库：`mcp/chromadb_data/signature_kb`，BM25：`mcp/bm25_data/signature_kb.pkl`

## 文献知识库构建

`europepmc_search.py` 使用 Europe PMC REST API：

- 接口：`https://www.ebi.ac.uk/europepmc/webservices/rest/search`
- 参数：`resultType=core`、`pageSize=50`、`format=json`、`sort=cited+desc`
- 时间范围：`PUB_YEAR:[2018 TO 2026]`
- 频率控制：每次请求至少间隔 `0.5s`，失败最多重试 `2` 次，每次间隔 `5s`

### 期刊白名单

- `Nature`
- `Cell`
- `Science`
- `Nature Methods`
- `Nature Microbiology`
- `Nature Biotechnology`
- `Nature Communications`
- `Cell Host Microbe`
- `Cell Reports`
- `Genome Biology`
- `Microbiome`
- `ISME Journal`
- `Gut Microbes`
- `mSystems`
- `mBio`
- `PLOS Computational Biology`
- `Bioinformatics`
- `Nucleic Acids Research`
- `Briefings in Bioinformatics`

### 查询覆盖范围

当前文献检索内置 39 条查询，覆盖：

- 核心工具：MetaPhlAn4、HUMAnN3、Kraken2/Bracken、MEGAHIT、MetaBAT/MaxBin/SemiBin、CheckM2、GTDB-Tk、dRep、StrainPhlAn、Centrifuger GTDB
- 病毒组：geNomad、VirSorter2、CheckV、iPHoP、vOTU 95% ANI、PHAROKKA
- 真菌组：mycobiome ITS/WGS、FunOMIC、CCMetagen、MicroFisher
- 统计分析：alpha/beta diversity、vegan、phyloseq、ANCOM-BC2、DESeq2、LEfSe、MMUPHin、ConQuR、SIAMCAT、curatedMetagenomicData
- 基准：CAMI、CAMI2
- 多组学：multi-omics integration、metagenomics-metabolomics correlation
- 疾病：IBD、CRC、T2D、obesity/BMI、CVD/TMAO、NAFLD/MASLD、Parkinson/Alzheimer/depression gut-brain axis
- 功能：AMR resistome、CAZyme/dbCAN、SCFA/butyrate、bile acid metabolism

每条查询都会叠加：

- 肠道菌群/宏基因组上下文词
- methods / workflow / benchmark / protocol / profiling 等方法学优先词
- 期刊白名单
- 2018-2026 年时间过滤

检索结果写入 `search_results.jsonl`，每行包含：

- `pmid`
- `pmcid`
- `title`
- `year`
- `journal`
- `authors`
- `query_ids`
- `queries`
- `cited_by`
- `has_fulltext`

## 运行命令

建议先激活项目 Python 环境，再执行以下命令。

```bash
source .venv/bin/activate
```

构建文献知识库：

```bash
python mcp/literature_pipeline.py --repo .
```

仅在检索到新 PMID 时刷新文献库：

```bash
python mcp/literature_pipeline.py --repo . --update
```

限制本次抓取的 PMC 文章数：

```bash
python mcp/literature_pipeline.py --repo . --max-articles 100
```

构建经验知识库：

```bash
python mcp/indexer.py --repo . --force
```

构建 BugSigDB 签名知识库（先桥接后索引）：

```bash
python mcp/bugsigdb_bridge.py
python mcp/index_signature_kb.py --repo . --force
```

## 文件结构

### 工作目录

- `mcp/data/literature/`
  - 这是当前代码实际使用的文献工作目录，可视为本项目的 `mcp_data/`
  - 包含 `search_results.jsonl`、`last_update.txt`、`pmc_xml/`、`methods/`、`annotations/`
- `mcp/chromadb_data/`
  - ChromaDB 持久化目录
  - 保存 `experience_kb`、`literature_kb`、`skill_design_kb`、`mechanism_kb`、`signature_kb`
- `mcp/data/bugsigdb_bridge/`
  - BugSigDB 桥接表（`bridge_table.json`，`{"signature": [...]}`）
  - 由 `mcp/bugsigdb_bridge.py` 生成，供 `index_signature_kb.py` 消费

### 关键脚本

- `europepmc_search.py`：Europe PMC 文献检索与聚合
- `literature_pipeline.py`：文献库总控流程
- `doc_parser.py`：文本解析与分块
- `indexer.py`：经验库构建
- `server.py`：stdio MCP / JSON-RPC 检索服务
- `query.py`：本地命令行查询工具

## MCP 挂载方式

以 stdio 方式挂载：

```bash
claude mcp add maxmeta -- python mcp/server.py --repo ${PROJ_DIR}
```

如果当前终端已经位于仓库根目录，也可以直接使用相对路径：

```bash
python mcp/server.py --repo .
```

服务启动后可检索：

- `experience_kb`
- `literature_kb`
- `signature_kb`
- `all`
