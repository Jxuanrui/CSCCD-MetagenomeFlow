# MaxMetagenome 项目结构

本文档描述 MaxMetagenome 项目的完整目录结构及各部分功能。最后更新：2026-06-12。

---

## 根目录结构

```
MaxMetagenome/
├── 0Install.sh              # 环境 & 数据库安装主脚本（§1-§15，含 Snakemake/RAG/Graphify）
├── CLAUDE.md                # CC + Codex 开发手册（§1-§15）
├── README.md                # 用户手册（v1.0.0，含完整脚本索引）
│
├── scripts/                 # 87 个分析脚本（01-98 编号，含 sub-scripts 41b/41c/41d）
│   ├── activate.sh                   # 环境激活（每次分析前执行）
│   ├── checkm_config.sh              # CheckM2 路径配置（迁移后执行一次）
│   ├── 00_pipeline_bacteria.sh       # 细菌维度一站式 Bash 流程（01-02 + 11-41）
│   ├── 00_pipeline_virome.sh         # 病毒维度一站式 Bash 流程（01-02 + 51-69）
│   ├── 00_pipeline_fungi.sh          # 真菌维度一站式 Bash 流程（01-02 + 71-86）
│   ├── 00_pipeline_full.sh           # 三维度全流程 Bash 脚本
│   ├── 01_qc_fastp.sh                # 质控（fastp）
│   ├── 02_qc_kneaddata.sh            # 去宿主（KneadData + bowtie2）
│   ├── 11_bac_metaphlan4.sh          # 细菌物种组成（MetaPhlAn4，菌株级）
│   ├── 11b_bac_metaphlan4_merge.sh   # 多样本 profile 合并
│   ├── 12_bac_strainphlan4.sh        # 菌株追踪与系统发育（StrainPhlAn4）
│   ├── 13_bac_humann3.sh             # 功能通路定量（HUMAnN3 v3.9，支持 speed-mode）
│   ├── 14_bac_kraken2.sh             # 快速物种分类（Kraken2 + Bracken）
│   ├── 15_bac_centrifuger.sh         # 蛋白级精确分类（Centrifuger，GTDB R226）
│   ├── 16_bac_megahit.sh             # 宏基因组组装（MEGAHIT）
│   ├── 17_bac_prodigal.sh            # 蛋白编码基因预测（Prodigal）
│   ├── 18_bac_cdhit.sh               # 基因去冗余（CD-HIT 95% ANI）
│   ├── 19_bac_salmon_build.sh        # 构建基因定量索引（Salmon）
│   ├── 20_bac_salmon_quant.sh        # 基因丰度定量 TPM（Salmon）
│   ├── 21_bac_eggnog.sh              # 综合功能注释 COG/KEGG/GO/EC（eggNOG-mapper）
│   ├── 22_bac_kegg.sh                # KEGG KO 通路注释（diamond）
│   ├── 23_bac_amrfinder.sh           # 抗生素耐药基因（AMRFinder+）
│   ├── 24_bac_card.sh                # 抗性基因综合（CARD/RGI）
│   ├── 25_bac_dbcan.sh               # 碳水化合物酶 CAZyme（dbCAN3）
│   ├── 26_bac_vfdb.sh                # 毒力因子（VFDB）
│   ├── 27_bac_bacmet.sh              # 重金属抗性基因（BacMet）
│   ├── 28_bac_antismash.sh           # 次级代谢产物/BGC（antiSMASH）
│   ├── 29_bac_defense_finder.sh      # CRISPR/防御系统（Defense-Finder）
│   ├── 30_bac_ncyc.sh                # 氮循环功能基因（NCyc）
│   ├── 31_bac_pcyc.sh                # 磷循环功能基因（PCyc）
│   ├── 32_bac_coverm_depth.sh        # 测序深度（CoverM，Binning 前置）
│   ├── 33_bac_metabat2.sh            # MetaBAT2 分箱
│   ├── 34_bac_maxbin2.sh             # MaxBin2 分箱
│   ├── 35_bac_semibin2.sh            # SemiBin2 分箱（ML 自训练）
│   ├── 36_bac_dastool.sh             # 多算法分箱整合优化（DAS_Tool）
│   ├── 37_bac_checkm2.sh             # MAG 质量评估（CheckM2 ML）
│   ├── 38_bac_drep.sh                # MAG 去冗余（dRep ANI 97%）
│   ├── 39_bac_coverm_quant.sh        # MAG 丰度定量（CoverM）
│   ├── 40_bac_gtdbtk.sh              # MAG 系统发育分类（GTDB-Tk R214）
│   ├── 41_bac_bakta.sh               # MAG 全基因组精细注释（Bakta）
│   ├── 41b_bac_mlst.sh               # MLST 多位点序列分型（mlst 2.11，WGS 融入）
│   ├── 41c_bac_pangenome.sh          # 泛基因组分析（Roary 3.12.0，WGS 融入）
│   ├── 41d_bac_snippy.sh             # SNP/InDel 变异检测（Snippy 4.0.2，WGS 融入）
│   ├── 51_vir_megahit.sh             # 病毒组装（MEGAHIT，≥1.5kb）
│   ├── 52_vir_genomad.sh             # 病毒/质粒鉴定（geNomad，神经网络）
│   ├── 53_vir_virsorter2.sh          # 病毒序列预测（VirSorter2，与 geNomad 取交集）
│   ├── 54_vir_checkv_contig.sh       # 病毒 contig 质量评估（CheckV）
│   ├── 55_vir_prodigal_gv.sh         # 病毒蛋白预测（Prodigal-gv，病毒密码子）
│   ├── 56_vir_votu_gen.sh            # vOTU 聚类（vclust，95% ANI）
│   ├── 57_vir_votu_genomad.sh        # vOTU 分类学注释（geNomad）
│   ├── 58_vir_salmon_build.sh        # 构建 vOTU 定量索引（Salmon）
│   ├── 59_vir_salmon_quant.sh        # vOTU 丰度定量（Salmon）
│   ├── 60_vir_votu_table.sh          # vOTU 丰度矩阵生成
│   ├── 61_vir_vmag.sh                # vMAG 生成（病毒基因组重建）
│   ├── 62_vir_checkv_mag.sh          # vMAG 质量评估与过滤（CheckV）
│   ├── 63_vir_coverm_quant.sh        # vMAG 丰度定量（CoverM）
│   ├── 64_vir_pharokka.sh            # 病毒基因组端到端注释（PHAROKKA + PHROG）
│   ├── 65_vir_phold.sh               # 结构暗物质 ORF 注释（PHOLD + PDB）
│   ├── 66_vir_vog.sh                 # VOG HMM 扫描（VOGDB）
│   ├── 67_vir_bacphlip.sh            # 噬菌体生活方式预测（BACPHLIP）
│   ├── 68_vir_iphop.sh               # 病毒-宿主关联预测（iPHoP）
│   ├── 69_vir_vcontact3.sh           # 病毒分类基因共享网络（vConTACT3）
│   ├── 71_fun_kraken2_fungi.sh       # Kraken2 真菌分类（PlusPF 含真菌）
│   ├── 72_fun_metaphlan4_euk.sh      # MetaPhlAn4 真菌分类（不过滤真核）
│   ├── 73_fun_humann4_fungi.sh       # 从 HUMAnN stratified 提取真菌通路
│   ├── 74_fun_blast_gutdb.sh         # DIAMOND 比对肠道真菌参考库（47G）
│   ├── 75_fun_funomics.sh            # FunOMIC 专用真菌 WGS 流程（推荐）
│   ├── 77_fun_microfisher.sh         # MicroFisher 多超变区提取（ITS1/2/18S/28S）
│   ├── 78_fun_megahit.sh             # 真菌 reads 提取 + 重新组装（MEGAHIT）
│   ├── 79_fun_eukfinder.sh           # 真核生物 MAG 回收（Eukfinder 2025）
│   ├── 80_fun_prodigal.sh            # 真菌蛋白编码基因预测（真核密码子）
│   ├── 81_fun_eggnog.sh              # 真菌综合功能注释（COG/KEGG/GO）
│   ├── 82_fun_kegg.sh                # 真菌 KEGG KO 通路注释
│   ├── 83_fun_dbcan.sh               # 真菌 CAZyme 注释（dbCAN3）
│   ├── 84_fun_vfdb.sh                # 真菌毒力因子（VFDB，念珠菌/曲霉）
│   ├── 85_fun_amr.sh                 # 抗真菌药物耐药基因（AMRFinder）
│   ├── 86_fun_merops.sh              # 真菌蛋白酶注释（MEROPS，侵袭相关）
│   ├── 91_stat_diversity.sh          # Alpha/Beta 多样性（vegan/phyloseq）
│   ├── 92_stat_differential.sh       # 差异分析（LEfSe/ANCOM-BC2/DESeq2/MaAsLin2）
│   ├── 93_stat_cooccurrence.sh       # 跨维度共现网络（FastSpar）
│   ├── 94_stat_visualization.sh      # 统一可视化（ggplot2）
│   ├── 95a_stat_batch_correct.sh     # 批次校正 Top10 方法（ConQuR/MMUPHin）
│   ├── 95b_stat_batch_evaluate.sh    # 批次校正评估报告（MBECS）
│   ├── 96_stat_ml_siamcat.sh         # ML 筛选 + ROC（SIAMCAT，10 折交叉验证）
│   ├── 97_stat_curatedMGD.sh         # 跨队列一致性验证（curatedMetagenomicData）
│   └── 98_stat_report.sh             # 带时间戳的 Markdown 快照报告
│
├── pipeline/                # Snakemake 生产级流程（Mode 3）
│   ├── Snakefile            # 入口（include 8 个规则文件）
│   ├── config/
│   │   └── config.yaml      # 运行参数（samples / workdir / cpus，每次分析前编辑）
│   └── rules/
│       ├── preprocessing.smk          # rules: fastp_qc, kneaddata（2 条）
│       ├── bacteria_taxonomy.smk      # rules: metaphlan4, metaphlan4_merge,
│       │                              #         strainphlan4, humann3,
│       │                              #         kraken2, centrifuger（6 条）
│       ├── bacteria_assembly.smk      # rules: megahit, prodigal, cdhit,
│       │                              #         salmon_build, salmon_quant（5 条）
│       ├── bacteria_annotation.smk    # rules: eggnog, kegg, amrfinder, card,
│       │                              #         dbcan, vfdb, bacmet, antismash,
│       │                              #         defense_finder, ncyc, pcyc（11 条）
│       ├── bacteria_binning.smk       # rules: coverm_depth, metabat2, maxbin2,
│       │                              #         semibin2, dastool, checkm2, drep,
│       │                              #         coverm_quant, gtdbtk, bakta,
│       │                              #         bac_mlst, bac_pangenome,
│       │                              #         bac_snippy（13 条）
│       ├── virome.smk                 # 19 条（51-69 全集成）
│       ├── mycobiome.smk              # 15 条（71-86，76 已移除）
│       ├── statistics.smk             # 9 条（91-98）
│       └── rag.smk                    # 2 条（build_experience_kb,
│                                      #        refresh_literature_kb）
│
├── agents/                  # Agent Skills 系统（脚本状态 + 技能卡）
│   ├── registry.yaml        # 全局脚本状态追踪（87 条目，6 状态字段）
│   ├── skills/              # 82 个工具卡片（YAML，76_ccmetagen 已移除）
│   └── provenance/          # 运行记录（/mgx-learn 自动写入）
│
├── .claude/                 # Claude Code 集成（不进入 git）
│   ├── commands/            # 15 个用户斜杠命令（/mgx-* 前缀）
│   │   ├── mgx-welcome.md
│   │   ├── mgx-ask.md
│   │   ├── mgx-integrate.md
│   │   ├── mgx-review.md
│   │   ├── mgx-learn.md
│   │   ├── mgx-plan.md
│   │   ├── mgx-run.md
│   │   ├── mgx-status.md
│   │   ├── mgx-plot-ordination.md
│   │   ├── mgx-plot-composition.md
│   │   ├── mgx-plot-diversity.md
│   │   ├── mgx-plot-heatmap.md
│   │   ├── mgx-plot-network.md
│   │   ├── mgx-plot-phylotree.md
│   │   └── mgx-plot-volcano.md
│   └── skills/              # 15 个 CC 内部技能文件（同名 .md）
│
├── docs/                    # 轻量工具文档 + 知识库
│   ├── 01_preprocessing/    # fastp.md, kneaddata.md
│   ├── 02_read_based/       # metaphlan4.md, humann3.md, kraken2.md, centrifuger.md
│   ├── 03_assembly/         # megahit.md, prodigal.md, cdhit.md, salmon.md
│   ├── 04_binning/          # metabat2.md, checkm2.md, drep.md, gtdbtk.md
│   ├── 05_virus/            # genomad.md, virsorter2.md, checkv.md, pharokka.md
│   ├── 05_stats/            # diversity.md, differential.md, siamcat.md
│   ├── 05_deep_mining/      # eggnog.md, amrfinder.md, dbcan.md
│   ├── experience/          # 12 个可编辑团队经验文档（RAG 经验知识库源）
│   │   ├── TEMPLATE.md      # 经验文档标准模板（含 YAML frontmatter 说明）
│   │   └── *.md             # 各工具/维度的实际经验记录
│   ├── tools_ref/           # 工具知识（WebSearch 动态学习后缓存，*.auto.md）
│   └── project_structure.md # 本文件
│
├── mcp/                     # RAG MCP 服务
│   ├── server.py            # MCP stdio 服务器（meta-server_rag_search tool）
│   ├── query.py             # Python CLI 查询接口
│   ├── indexer.py           # 经验 KB 构建器（6 类知识源 → ChromaDB）
│   ├── doc_parser.py        # 文档/脚本/技能卡解析工具集
│   ├── pubtator_search.py   # PubTator 3.0 API 文献发现（12 个预定义查询）
│   ├── pmc_fetch.py         # NCBI efetch PMC XML 下载
│   ├── methods_extractor.py # PMC XML → Methods 节提取
│   ├── literature_pipeline.py # 文献 KB 编排器
│   ├── chromadb_data/       # ChromaDB 持久化目录（gitignored）
│   └── data/literature/     # PMC 全文缓存（gitignored）
│
├── skills/                  # 外部技能发现系统
│
├── envs/                    # 37 个 conda 独立工具环境
│   ├── base (miniforge3)    # Python + Snakemake + graphifyy + RAG 依赖
│   ├── qc/                  # fastp, kneaddata
│   ├── biobakery/           # metaphlan4, humann3, strainphlan4
│   ├── kraken2/             # kraken2, bracken
│   ├── centrifuger/         # centrifuger
│   ├── megahit/             # megahit
│   ├── prodigal/            # prodigal
│   ├── cdhit/               # cd-hit
│   ├── salmon/              # salmon
│   ├── eggnog/              # eggnog-mapper
│   ├── amrfinder/           # amrfinderplus
│   ├── card/                # rgi (CARD)
│   ├── dbcan/               # dbcan3
│   ├── antismash/           # antismash
│   ├── defense_finder/      # defense-finder
│   ├── metabat2/            # metabat2
│   ├── maxbin2/             # maxbin2
│   ├── semibin2/            # semibin2
│   ├── dastool/             # das_tool
│   ├── checkm2/             # checkm2
│   ├── drep/                # drep
│   ├── coverm/              # coverm
│   ├── gtdbtk/              # gtdbtk
│   ├── bakta/               # bakta
│   ├── prokaWGS/            # mlst 2.11, roary 3.12.0
│   ├── snippy/              # snippy 4.0.2
│   ├── genomad/             # genomad
│   ├── virsorter2/          # virsorter2
│   ├── checkv/              # checkv
│   ├── prodigal_gv/         # prodigal-gv
│   ├── salmon_vir/          # salmon (virome)
│   ├── pharokka/            # pharokka
│   ├── phold/               # phold
│   ├── bacphlip/            # bacphlip
│   ├── iphop/               # iphop
│   ├── vcontact3/           # vcontact3
│   ├── fungi_tools/         # eukfinder, microfisher, funomics
│   └── R/                   # vegan, phyloseq, DESeq2, edgeR, SIAMCAT, ggplot2
│
├── db/                      # 分析数据库（~700G，已部署，不进 git）
│   ├── chocophlan/          # HUMAnN3 核酸库（~15G）
│   ├── uniref/              # HUMAnN3 蛋白库（~40G）
│   ├── metaphlan4/          # MetaPhlAn4 数据库（~20G）
│   ├── kraken2_standard/    # Kraken2 标准库（~100G）
│   ├── kraken2_plusPF/      # Kraken2 含真核（~120G）
│   ├── GTDB_R226/           # Centrifuger 蛋白索引（~90G）
│   ├── gtdbtk_r214/         # GTDB-Tk MAG 分类库（~75G）
│   ├── checkm2/             # CheckM2 ML 模型（~2G）
│   ├── bakta/               # Bakta 注释数据库（~70G）
│   ├── eggnog/              # eggNOG-mapper 数据库（~60G）
│   ├── kegg_dmnd/           # KEGG 蛋白 diamond 索引（~25G）
│   ├── amrfinderplus/       # AMRFinder 数据库（~1G）
│   ├── card/                # CARD 数据库（~3G）
│   ├── dbcan3/              # dbCAN3 HMM 库（~5G）
│   ├── vfdb/                # VFDB 毒力因子库（~1G）
│   ├── bacmet/              # BacMet 重金属抗性库（<1G）
│   ├── ncyc_pcyc/           # NCyc/PCyc 氮磷循环库（<1G）
│   ├── genomad/             # geNomad 病毒数据库（~15G）
│   ├── checkv/              # CheckV 病毒质量库（~3G）
│   ├── pharokka/            # PHAROKKA + PHROG 数据库（~10G）
│   ├── phold/               # PHOLD 结构数据库（~30G）
│   ├── vogdb/               # VOGDB HMM 库（~3G）
│   ├── iphop/               # iPHoP 宿主预测库（~150G）
│   ├── gut_fungi/           # 肠道真菌 DIAMOND 库（~47G，74 脚本）
│   ├── merops/              # MEROPS 蛋白酶 DIAMOND 库（<1G）
│   └── eukfinder/           # Eukfinder 数据库（~20G）
│
├── Project/                 # 分析项目目录（不进 git）
│   └── Project_example/
│       ├── samples.txt          # 样本 ID 列表（每行一个）
│       ├── data/                # 原始测序数据（*.fastq.gz）
│       ├── temp/                # 中间文件（按脚本编号子目录）
│       └── result/              # 结果文件（按分析类型子目录）
│
└── Reference/               # 参考资料（本地文档，不进 git）
    ├── EasyMetagenome.zip   # 宏基因组全流程参考（已解压至 /tmp/EasyMetagenome_ref/）
    └── WGS_prokaryote.pipeline.v0.7.sh  # 单菌/分离株 WGS 参考流程
```

---

## 脚本集成状态（agents/registry.yaml）

| 维度 | 脚本数 | 已集成 | 状态 |
|------|--------|--------|------|
| 共享预处理 | 2 | 2 | 100% |
| 细菌（11-41d） | 35 | 35 | 100% |
| 病毒（51-69） | 19 | 19 | 100% |
| 真菌（71-86，76 已移除）| 15 | 15 | 100% |
| 统计分析（91-98）| 8 | 8 | 100% |
| RAG 规则 | 2 | 2 | 100% |
| **合计** | **81** | **81** | **100%** |

> 注：76_fun_ccmetagen 永久排除（KMA nt index 未部署），registry 保留 removed 记录。

---

## Snakemake 规则汇总

| 规则文件 | 规则数 | 对应脚本 |
|----------|--------|---------|
| `preprocessing.smk` | 2 | 01, 02 |
| `bacteria_taxonomy.smk` | 6 | 11, 11b, 12, 13, 14, 15 |
| `bacteria_assembly.smk` | 5 | 16-20 |
| `bacteria_annotation.smk` | 11 | 21-31 |
| `bacteria_binning.smk` | 13 | 32-41, 41b, 41c, 41d |
| `virome.smk` | 19 | 51-69 |
| `mycobiome.smk` | 15 | 71-86（无 76） |
| `statistics.smk` | 9 | 91-98 |
| `rag.smk` | 2 | build_experience_kb, refresh_literature_kb |
| **合计** | **83** | |

---

## Claude Code 命令与技能对应表

| 斜杠命令 | 技能文件 | 功能简述 |
|----------|----------|---------|
| `/mgx-welcome` | skills/mgx-welcome.md | 欢迎页 + 平台概览 |
| `/mgx-ask` | skills/mgx-ask.md | RAG 知识库查询 |
| `/mgx-integrate` | skills/mgx-integrate.md | 新脚本集成到 Snakemake + 技能卡 |
| `/mgx-review` | skills/mgx-review.md | 集成质量审查 |
| `/mgx-learn` | skills/mgx-learn.md | 分析经验写入 RAG |
| `/mgx-plan` | skills/mgx-plan.md | 生成 Tech Spec + Tasks |
| `/mgx-run` | skills/mgx-run.md | 生成并执行分析命令 |
| `/mgx-status` | skills/mgx-status.md | 流程进度与脚本状态 |
| `/mgx-plot-ordination` | skills/mgx-plot-ordination.md | PCoA/NMDS 排序图 |
| `/mgx-plot-composition` | skills/mgx-plot-composition.md | 物种组成图 |
| `/mgx-plot-diversity` | skills/mgx-plot-diversity.md | Alpha 多样性图 |
| `/mgx-plot-heatmap` | skills/mgx-plot-heatmap.md | 注释热图 |
| `/mgx-plot-network` | skills/mgx-plot-network.md | 共现网络图 |
| `/mgx-plot-phylotree` | skills/mgx-plot-phylotree.md | 系统发育树 |
| `/mgx-plot-volcano` | skills/mgx-plot-volcano.md | 差异丰度火山图 |

---

## 已排除脚本

| 脚本 | 排除原因 | 状态 |
|------|---------|------|
| 76_fun_ccmetagen | KMA nt 数据库未部署（~2TB），永久排除 | removed（2026-06-11） |

---

*最后更新: 2026-06-12 — 反映 87 脚本全集成、83 Snakemake 规则、15 CC 命令、RAG 双库、Graphify 状态*
