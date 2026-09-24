# CSCCD-MetagenomeFlow Project Map

> 本文件是 CLAUDE.md §14（原 "CSCCD-MetagenomeFlow Project Map"）的完整迁移版本。
> **触发时机**：当用户询问"如何启动"、"做什么分析"、"某工具怎么用"、某脚本编号/功能时，CC 读取本文件。
> 未知工具参数 → WebSearch 获取官方文档，结果缓存至 `docs/tools_ref/`。
>
> **状态标注说明**：本文件中的 ✅/⚠️ 完成状态标注是特定时间点（多为 `Project_example` 测试项目）的快照，
> 会随分析进展变化。如需了解当前最新进度，优先核对实际 `result/` 目录内容或 `agents/provenance/`，
> 而不要仅依赖本文件的历史标注。

## 1.1 快速启动

CSCCD-MetagenomeFlow 支持三种运行模式，按需选择：

### 模式一：逐步模式（Step-by-step）
研究级，每步独立运行，参数可精细调控。适合单步调试或探索性分析。

```bash
# 1. 激活项目环境
source ~/Course/CSCCD-MetagenomeFlow/scripts/activate.sh

# 2. 单步运行示例（质控 → 去宿主 → 物种分类）
bash scripts/01_qc_fastp.sh       -s SAMPLE_ID -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
bash scripts/02_qc_kneaddata.sh   -s SAMPLE_ID -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
bash scripts/11_bac_metaphlan4.sh -s SAMPLE_ID -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

### 模式二：Bash 一站式流程（轻量 Pipeline）
无额外依赖，传入 samplesheet.csv 串联步骤。支持 `--skip`/`--from`/`--only` 断点续跑。
适合单机小批量样本、不想依赖 Snakemake 的场景。

```bash
# 运行完整细菌流程
bash scripts/00_pipeline_bacteria.sh \
     -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16

# 断点续跑（从 metaphlan4 步骤开始）
bash scripts/00_pipeline_bacteria.sh \
     -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 --from metaphlan4

# 多样本并行（需要 rush）
bash scripts/00_pipeline_bacteria.sh \
     -i samplesheet.csv -r ~/Course/CSCCD-MetagenomeFlow -t 16 -j 2
```

### 模式三：Snakemake Pipeline（生产级，推荐）
基于 DAG 的自动依赖追踪，原生断点续跑，支持 HPC/多节点。
适合大批量样本、正式分析、需要完整 provenance 记录的场景。

**并行参数说明**（与模式二对齐）：
- `threads_per_job`：每个工具内部使用的线程数（对应模式二的 `-t`，在 `config/config.yaml` 中设置）
- `--cores N`：告诉 Snakemake 可用总线程数，**自动推算并发 job 数**（推荐，无需手动计算）
- 并发 job 数 = `cores / threads_per_job`，例如 `--cores 48`、`threads_per_job=16` → 自动 3 并发

**Profile 预设**（`pipeline/profiles/` 目录，按服务器配置选用）：

| Profile | 适用场景 | 核数 | 实际并发 |
|---------|---------|------|---------|
| `auto` | 由 `/mgx-tune` 根据当前机器自动生成 | 自动检测 | 自动 |
| `local_16c` | 16 核笔记本/小型工作站 | 12 | 1 |
| `local_48c` | 48 核服务器（本机） | 44 | 2 |
| `local_96c` | 96 核服务器 | 92 | 5 |
| `hpc_slurm` | HPC 集群（SLURM） | — | 20 jobs |

```bash
# 0. 首次使用：检测当前硬件并生成 profiles/auto/
/mgx-tune   # 在 Claude Code 中执行

# 1. 编辑运行参数（samplesheet 路径、workdir、threads_per_job）
vim pipeline/config/config.yaml

# 2. 预演（检查 DAG，不实际运行）
snakemake -s pipeline/Snakefile --profile pipeline/profiles/auto --dry-run

# 3. 正式运行（profile 自动传入 --cores，无需手动指定 -j）
snakemake -s pipeline/Snakefile --profile pipeline/profiles/auto

# 4. 断点续跑（profile 内已包含 rerun-incomplete: true，直接重跑即可）
snakemake -s pipeline/Snakefile --profile pipeline/profiles/auto

# 5. 指定 profile（换机器时选对应预设）
snakemake -s pipeline/Snakefile --profile pipeline/profiles/local_96c
```

> **注意**：
> - Snakemake 已安装在项目内 miniforge3 base 环境，激活 `activate.sh` 后即可直接调用。
> - 迁移到新服务器后运行 `/mgx-tune` 重新生成 `profiles/auto/`。
> - `--cores` 控制总线程预算，Snakemake 根据每个 rule 的 `threads:` 声明自动分配并发数；merge 等聚合 rule 的 DAG 依赖保证所有 per-sample job 完成后才触发，无需人工分步。

## 1.2 分析流程索引

### 📦 通用预处理（所有维度共享）

| 编号 | 脚本 | 功能 | 文档 |
|------|------|------|------|
| 01 | `scripts/01_qc_fastp.sh` | 质量控制（接头去除、低质碱基修剪） | `docs/01_preprocessing/fastp.md` |
| 02 | `scripts/02_qc_kneaddata.sh` | 去宿主（人/鼠/大鼠） | `docs/01_preprocessing/kneaddata.md` |

### 🦠 细菌维度（Bacteria，编号 11-41）

> **分析完成状态（Project_example，2026-06-18 更新）**
> - 11 MetaPhlAn4 ✅ / **12 StrainPhlAn4 ✅**（6个.json.bz2 marker生成，测试样本无可追踪菌株属预期行为）/ 13 HUMAnN3 ✅（6/6）/ 14 Kraken2 ✅ / 15 Centrifuger ✅（6/6）
> - 16 MEGAHIT ✅ / 17 Prodigal ✅ / 18 CD-HIT ✅ / 19 Salmon index ✅ / 20 Salmon quant ✅（6/6）
> - 21-31 功能注释全部完成 ✅（eggNOG/KEGG/AMRFinder/CARD/dbCAN/VFDB/BacMet/antiSMASH/Defense-Finder/NCyc/PCyc）
> - 32-36 Binning ✅（流程跑通，Project_example测序深度不足产出0个MAG，属预期行为）
> - 37 CheckM2 ✅ / 38 dRep ✅ / 39-41 MAG后处理 ✅ / 41b-41d WGS整合 ✅（0个MAG输入，sentinel文件正常）
> - **⚠️ Snakemake bug 修复（2026-06-17）**：kegg rule 缺少 log:/threads: → 双进程写入冲突；已修复，重跑完成（KEGG 48G DB + 6样本 NR蛋白，~20min）
> - **98b 细菌功能整合表（2026-07-03 补跑）**：`agents/registry.yaml` 中 `integrated_date: "2026-06-16"` 仅代表脚本已接入 Snakemake，Project_example 实际从未运行过 98b（无 log 记录）。已补跑：先运行 `13b_bac_humann3_merge.sh` 生成缺失的 `result/humann3/merged/pathabundance_relab.tsv`，再运行 `98b_bac_integration_tables.sh`，11 张整合表全部生成成功，输出 `result/integration/bacteria/`。

| 编号 | 脚本 | 功能 | 工具 |
|------|------|------|------|
| 11 | `scripts/11_bac_metaphlan4.sh` | 物种组成（精确分类，菌株级） | MetaPhlAn4 |
| 12 | `scripts/12_bac_strainphlan4.sh` | 菌株追踪与系统发育 | StrainPhlAn4 |
| 13 | `scripts/13_bac_humann3.sh` | 功能通路定量（PathwayAbundance） | HUMAnN3（v3.9） | 支持 `--speed-mode balanced/fast` 提速；输出到 `result/humann3/` |
| 14 | `scripts/14_bac_kraken2.sh` | 快速物种分类（k-mer） | Kraken2+Bracken |
| 15 | `scripts/15_bac_centrifuger.sh` | 蛋白级精确分类（GTDB R226） | Centrifuger |
| 15c | `scripts/15c_bac_sylph.sh` | 超快速物种分类（minhash sketch，GTDB-R220），可选快速预筛选，非替代 MetaPhlAn4/Kraken2 | sylph+sylph-tax |
| **15e** | **`scripts/15e_bac_metax.sh`** | **跨域统一分类（2026-09-15 新增）**：单次运行同时分类细菌/古菌/真核/病毒/宿主，coverage-informed OEBR/COEBR 过滤 reference 污染、同源误配与 kitome 伪阳性 + EM 丰度细化。作为**跨域验证层**与单域工具（11/14/15/52/68）交叉验证，默认**不入 rule all**（请求 `result/metax/<sample>/<sample>.profile.txt` 触发）。版本锁定 metax 0.9.22 + 预构建 RefSeq 库（2.x 的 DB 格式不兼容） | MetaX (envs/metax) |
| 16 | `scripts/16_bac_megahit.sh` | 宏基因组组装 | MEGAHIT |
| 17 | `scripts/17_bac_prodigal.sh` | 蛋白编码基因预测 | Prodigal |
| 18 | `scripts/18_bac_cdhit.sh` | 基因去冗余（95% ANI） | CD-HIT |
| 19 | `scripts/19_bac_salmon_build.sh` | 构建基因定量索引 | Salmon |
| 20 | `scripts/20_bac_salmon_quant.sh` | 基因丰度定量（TPM） | Salmon |
| 21 | `scripts/21_bac_eggnog.sh` | 综合功能注释（COG/KEGG/GO/EC） | eggNOG-mapper |
| 22 | `scripts/22_bac_kegg.sh` | KEGG KO 通路注释 | KEGG diamond |
| 23 | `scripts/23_bac_amrfinder.sh` | 抗生素耐药基因 | AMRFinder |
| 24 | `scripts/24_bac_card.sh` | 抗性基因综合 | CARD/RGI |
| **24b** | **`scripts/24b_bac_card_summary.sh`** | **CARD/RGI置信度分层+药物类别+SNP突变证据汇总（纯统计聚合，无新工具）** | **Python（标准库）** |
| 25 | `scripts/25_bac_dbcan.sh` | 碳水化合物酶（CAZyme） | dbCAN3 |
| 26 | `scripts/26_bac_vfdb.sh` | 毒力因子 | VFDB |
| 27 | `scripts/27_bac_bacmet.sh` | 重金属抗性基因 | BacMet |
| 28 | `scripts/28_bac_antismash.sh` | 次级代谢产物/BGC | antiSMASH |
| 29 | `scripts/29_bac_defense_finder.sh` | CRISPR/防御系统 | Defense-Finder |
| 30 | `scripts/30_bac_ncyc.sh` | 氮循环功能基因 | NCyc |
| 31 | `scripts/31_bac_pcyc.sh` | 磷循环功能基因 | PCyc |
| **31b** | **`scripts/31b_bac_scyc.sh`** | **硫循环功能基因（SCyc，补全 N/P/C/S 循环）** | **SCyc + DIAMOND** |
| **31c** | **`scripts/31c_bac_pfam.sh`** | **Pfam-A 蛋白域注释（hmmscan，--cut_ga）** | **HMMER + Pfam-A** |
| **31d** | **`scripts/31d_bac_uniprot.sh`** | **UniProt Swiss-Prot 高精度注释（补充 eggNOG 未命中）** | **MMseqs2 easy-search** |
| **31e** | **`scripts/31e_bac_fegenie.sh`** | **铁代谢基因预测（iron uptake/storage/cycling，10 类功能）** | **FeGenie 1.2** |
| 32 | `scripts/32_bac_coverm_depth.sh` | 测序深度计算（Binning前置） | CoverM |
| 33 | `scripts/33_bac_metabat2.sh` | MetaBAT2 分箱 | MetaBAT2 |
| **33b** | **`scripts/33b_bac_quickbin.sh`** | **QuickBin 高保真分箱（2026-09-15 新增）**：CPU-only、marker-free；GC-覆盖度空间索引 + Oracle 相似度级联。论文在 297 真实宏基因组中高保真 MAG（≥95%/≤1%）产出优于 MetaBAT2/SemiBin2/VAMB/COMEBin 且全部跑完。复用 `32` 的 contig BAM（无需重复映射）。**独立使用**：4 样本对照（2026-09-16）证明加入 DAS_Tool 集成对高质 MAG 回收**净有害**（-3 高保真 / -2 MIMAG-high），故**不并入 36** | QuickBin（BBTools 39.81，envs/busco） |
| 34 | `scripts/34_bac_maxbin2.sh` | MaxBin2 分箱 | MaxBin2 |
| 35 | `scripts/35_bac_semibin2.sh` | SemiBin2 分箱（ML自训练） | SemiBin2 |
| 36 | `scripts/36_bac_dastool.sh` | 多算法分箱整合优化（2026-09-16 修复：运行前清空输出目录，防陈旧 bin 累积） | DAS_Tool |
| 37 | `scripts/37_bac_checkm2.sh` | MAG 质量评估（ML） | CheckM2 |
| 38 | `scripts/38_bac_drep.sh` | MAG 去冗余（默认 95% ANI；二级聚类默认 skani，`-A` 可切 fastANI/ANImf） | dRep |
| 39 | `scripts/39_bac_coverm_quant.sh` | MAG 丰度定量 | CoverM |
| 39b | `scripts/39b_bac_instrain_map.sh` | MAG 读段映射（菌株追踪前置） | CoverM (minimap2-sr) |
| 39c | `scripts/39c_bac_instrain_profile.sh` | 单样本菌株微多样性分析 | inStrain |
| 39d | `scripts/39d_bac_instrain_compare.sh` | 跨样本 popANI 菌株比较 | inStrain |
| 40 | `scripts/40_bac_gtdbtk.sh` | MAG 系统发育分类（GTDB R214） | GTDB-Tk |
| 41 | `scripts/41_bac_prokka.sh` | MAG 全基因组精细注释（2026-09-16 修复：--force 时清空输出目录，防孤儿目录累积） | Prokka |
| 41b | `scripts/41b_bac_mlst.sh` | MAG MLST 多位点序列分型（WGS 融入模块） | mlst | envs/prokaWGS (mlst 2.11) |
| 41c | `scripts/41c_bac_pangenome.sh` | 同种 MAG 泛基因组分析（WGS 融入模块） | Roary | envs/prokaWGS (roary 3.12.0) |
| 41d | `scripts/41d_bac_snippy.sh` | MAG SNP/InDel 变异检测（WGS 融入模块） | Snippy | envs/snippy (snippy 4.0.2) |
| **42** | **`scripts/42_bac_mge.sh`** | **MGE 综合注释（ISfinder/ICEberg/integrall/transposase/mobileOG，HGT 追踪）** | **MMseqs2 + BLAST + HMMER + DIAMOND** |
| **42b** | **`scripts/42b_bac_plasmidfinder.sh`** | **质粒识别与分类（replicon 类型 + Inc group，conda 内置 DB）** | **PlasmidFinder 2.1.6** |
| **43** | **`scripts/43_bac_gem_gapseq.sh`** | **MAG 代谢模型重建（gapseq 三步法：find/draft/fill）** | **gapseq (R 包)** |
| **43b** | **`scripts/43b_bac_gem_carveme.sh`** | **MAG 代谢模型重建（CarveMe 快速通路）** | **CarveMe** |
| **43c** | **`scripts/43c_bac_gem_cobrapy_fba.sh`** | **代谢模型 FBA 模拟（生长率/通量/必需基因/底物利用）** | **COBRApy** |

### 🦠 病毒维度（Virome，编号 51-69）

> **分析完成状态（Project_example，2026-06-18 更新）**
> - 51-72 全部完成 ✅（含新增脚本 54b/70/71/72）；Snakemake 全流程验证通过（2026-06-17）
> - **54b** (`54b_vir_checkv_filter.sh`): MIUVIG标准质量过滤 — 42个contigs（S01=0, S02=21, S03=4, S04=8, S05=1, S06=8）
> - **55** Prodigal-gv：6/6样本完成，输出 `result/virus/prodigal/`
> - **57** vOTU geNomad分类：`result/virus/votu/genomad/virus_taxonomy.tsv`（42行）✅
> - **59** Salmon quant：6/6样本完成 ✅（修复：Salmon 0.14.1 decoy-aware 索引 segfault → 标准索引）
> - **60** vOTU丰度矩阵：`result/virus/votu/table/vOTU_table_ann.txt`（533行）✅
> - **65** PHOLD：输出路径修复（`vOTU_all_cds_functions.tsv` 正确拷贝为 sentinel）✅
> - **67** BACPHLIP：Snakemake rule 补加 `-t {threads}` 参数 ✅
> - **70** PhaBox2 2.1.12：`result/virus/phabox2/phabox2_summary.tsv` ✅
> - **71** DRAM-v 1.5.0：`result/virus/dram/DRAM_annotations.tsv` ✅（无viral DB时auxiliary_score=5填充）
> - **72** PhaGCN3 3.1：`result/virus/phagcn3/phagcn3_prediction.tsv` ✅
> - vOTU聚类：42个filtered contigs → **20个cluster representatives**（95% ANI, 0.85 qcov）
> - 61-63 vMAG链：Project_example测序深度不足，无vMAG产出（预期行为）；62/63脚本已修复0-vMAG sentinel创建
> - **98c 病毒功能整合表（2026-07-03 补跑）**：`98c_vir_integration_tables.sh` 已成功运行，输出 `result/integration/virus/`（7张聚合/宽表 + 8张标准化表）。`host_genus_abundance.tsv` 为0行（iPHoP在Project_example无命中，属预期行为）。

| 编号 | 脚本 | 功能 | 工具 |
|------|------|------|------|
| 51 | `scripts/51_vir_megahit.sh` | 组装（病毒优化参数，≥1.5kb） | MEGAHIT |
| 52 | `scripts/52_vir_genomad.sh` | 病毒/质粒鉴定（神经网络+生活方式预测） | geNomad |
| 53 | `scripts/53_vir_virsorter2.sh` | 病毒序列预测（与geNomad取交集） | VirSorter2 |
| 54 | `scripts/54_vir_checkv_contig.sh` | 病毒contig质量评估 | CheckV |
| **54b** | **`scripts/54b_vir_checkv_filter.sh`** | **MIUVIG质量过滤**（Complete/HQ/MQ/LQ + Not-det+viral_genes≥1，长度≥2000bp） | **seqkit** |
| 55 | `scripts/55_vir_prodigal_gv.sh` | 病毒蛋白预测（病毒遗传密码子） | Prodigal-gv |
| 56 | `scripts/56_vir_votu_gen.sh` | vOTU 生成（95% ANI, 0.85 qcov；优先读54b filtered输出） | vclust |
| 57 | `scripts/57_vir_votu_genomad.sh` | vOTU 分类学注释 | geNomad |
| 58 | `scripts/58_vir_salmon_build.sh` | 构建 vOTU 定量索引（per-sample CDS + vOTU representatives） | Salmon |
| 59 | `scripts/59_vir_salmon_quant.sh` | vOTU 样本间丰度定量 | Salmon |
| 60 | `scripts/60_vir_votu_table.sh` | 生成 vOTU 丰度矩阵（CDS-level Salmon输出→合并） | Python |
| 61 | `scripts/61_vir_vmag.sh` | vMAG 生成（病毒基因组重建） | vmag pipeline |
| 62 | `scripts/62_vir_checkv_mag.sh` | vMAG 质量评估与过滤 | CheckV |
| 63 | `scripts/63_vir_coverm_quant.sh` | vMAG 样本间丰度定量 | CoverM |
| 64 | `scripts/64_vir_pharokka.sh` | 病毒基因组端到端注释（含ARG） | PHAROKKA + PHROG |
| 65 | `scripts/65_vir_phold.sh` | 结构暗物质ORF注释（PHAROKKA补充） | PHOLD + PDB |
| 66 | `scripts/66_vir_vog.sh` | VOG HMM 扫描（跨界病毒注释） | VOGDB |
| 67 | `scripts/67_vir_bacphlip.sh` | 噬菌体生活方式预测（裂解/溶原） | BACPHLIP |
| 68 | `scripts/68_vir_iphop.sh` | 病毒-宿主关联预测 | iPHoP |
| 69 | `scripts/69_vir_vcontact3.sh` | 病毒分类基因共享网络 | vConTACT3 |
| 70 | `scripts/70_vir_phabox2.sh` | 端到端分类（virus/质粒+完整lineage+宿主+生活方式） | PhaBox2 2.1.12 | envs/phabox2, db/phabox2_db ✅ 2026-06-16 |
| 71 | `scripts/71_vir_dram.sh` | 病毒功能注释 + AMG预测（辅助代谢基因） | DRAM 1.5.0 | envs/dram, db/dram_db ✅ 2026-06-16 |
| 72 | `scripts/72_vir_phagcn3.sh` | 深度学习图卷积病毒分类（补充vConTACT3） | PhaGCN3 3.1 | envs/phagcn3, db/phagcn3_db ✅ 2026-06-16 |

### 🍄 真菌维度（Mycobiome，编号 71-86）

> **分析路线说明（对应 Yan et al. 2024 Cell 187）**
>
> 真菌维度分为三条并行子路线，互相补充：
>
> **路线 A — PHF 丰度定量（论文原方法，推荐首选）✅ Project_example 已完成**
> `74a`（一次性建库）→ `74e`（per-sample Bowtie2+Singular/Escrow）→ `74f`（多样本聚合）
> - 数据库：`db/gut_fungi_db/`（760基因组基因集，4个Bowtie2索引，已构建完成）
> - 算法：5步Bowtie2过滤（去宿主/细菌/rRNA）+ Singular/Escrow reads分配 + GPA.py 相对丰度
> - 输出：`result/fungi/phf_profiler/merged_abundance_with_taxonomy.tsv`（8簇×6样本，317簇分类注释）
> - **与论文一致性**：✅ 完全对应（Yan et al. 2024 Cell 187 完整实现，identity=0.95，-k 1000）
>
> **路线 B — 多工具分类（互补，取共识）✅ Project_example 已完成**
> `71`（Kraken2）/ `72`（MetaPhlAn4）/ `73`（HUMAnN4真菌通路提取）/ `74`（BLAST备用）/ `75`（FunOMIC）/ `77`（MicroFisher）
> - 71：`result/fungi/kraken2/` — Bracken多分类级别输出（S/G/P），6/6样本 ✅
> - 72：`result/fungi/metaphlan4/` — 真菌物种组成，6/6样本 ✅
> - 73：`result/fungi/humann4/` — 真菌功能通路丰度，6/6样本 ✅
> - 74：`result/fungi/blast_gutdb/` — BLAST比对肠道真菌库，6/6样本 ✅
> - 75：`result/fungi/funomic/` — FunOMIC分类，6/6样本 ✅（75b多样本聚合待运行）
> - 76：**CCMetagen — 未运行**（依赖NCBI nt全库，数据库未配置）
> - 77：`result/fungi/microfisher/` — ITS/18S/28S多超变区，6/6样本 ✅
>
> **路线 C — 组装+MAG+注释（深度功能分析）✅ 流程全部跑通**
> `78`（reads提取+组装）→ `79`（Eukfinder MAG）→ `80b`（Prodigal基因预测）→ `81-86`（功能注释）
> - 78：`result/fungi/assembly/` — MEGAHIT组装，6/6样本 .contigs.fa ✅
> - 79：`result/fungi/eukfinder/` — EukDB构建完成（628/667基因组，12.8GB），S01测试通过（exit 0，0个真核contig，低测序深度预期行为）✅ 2026-06-17
> - 80/80b：`result/fungi/prodigal/` — Prodigal基因预测（.faa/.fna/.gff），6/6样本 ✅（基于78组装contigs）
> - 81：`result/fungi/eggnog/` — eggNOG注释（combined_fungi.faa合并） ✅
> - 82：`result/fungi/kegg/` — KEGG KO通路注释 ✅
> - 83：`result/fungi/dbcan/` — CAZyme注释（diamond+hmmer+eCAMI三工具） ✅
> - 84：`result/fungi/vfdb/` — 毒力因子 ✅
> - 85：`result/fungi/amr/` — 抗真菌药物耐药基因 ✅
> - 86：`result/fungi/merops/` — 蛋白酶注释 ✅
>
> **⚠️ 待完成项**：
> - **75b FunOMIC聚合** ✅ 2026-06-22：`result/integration/fungi/funomic_species_count.tsv` + `normalized/funomic_species_relab.tsv` + `funomic_species_clr.tsv`（3544 species × 6 samples）
> - **76 CCMetagen**：需要NCBI nt全库（>200G），暂未配置

| 编号 | 脚本 | 功能 | 工具 |
|------|------|------|------|
| 71 | `scripts/71_fun_kraken2_fungi.sh` | Kraken2 真菌分类（PlusPF含真菌，基础快速） | Kraken2+Bracken |
| 72 | `scripts/72_fun_metaphlan4_euk.sh` | MetaPhlAn4 真菌分类（不过滤真核生物） | MetaPhlAn4 |
| 73 | `scripts/73_fun_humann4_fungi.sh` | 从HUMAnN4 stratified矩阵提取真菌通路 | HUMAnN4 |
| 74 | `scripts/74_fun_blast_gutdb.sh` | BLAST 比对肠道真菌参考库（47G，高精度，备用） | BLAST |
| 74a | `scripts/74a_fun_gut_db_build.sh` | **一次性建库**：Bowtie2 索引（4个，来自 db/gut_fungi_db/） | Bowtie2 |
| 74e | `scripts/74e_fun_phf_profiler.sh` | **论文方法** per-sample：5步过滤+Singular/Escrow（Yan et al. 2024 Cell 187） | Bowtie2+GPA.py |
| 74f | `scripts/74f_fun_phf_aggregate.sh` | **论文方法** 聚合：多样本.rc矩阵+物种分类注释 | Python |
| 75 | `scripts/75_fun_funomics.sh` | FunOMIC 专用真菌WGS流程（1.6M marker+3.4M功能蛋白） | FunOMIC |
| 75b | `scripts/75b_fun_funomics_aggregate.sh` | FunOMIC 多样本结果聚合 | Python |
| 76 | `scripts/76_fun_ccmetagen.sh` | CCMetagen 真核+原核综合分类（NCBI nt全库） | CCMetagen |
| 77 | `scripts/77_fun_microfisher.sh` | MicroFisher 多超变区提取（ITS1/ITS2/18S/28S） | MicroFisher |
| 78 | `scripts/78_fun_megahit.sh` | 真菌reads提取（依赖71/72输出）+重新组装 | MEGAHIT |
| 79 | `scripts/79_fun_eukfinder.sh` | 真核生物MAG回收（Eukfinder，2025，专用真核binning） | Eukfinder |
| 80 | `scripts/80_fun_prodigal.sh` | 真菌蛋白编码基因预测（真核密码子表） | Prodigal |
| 80b | `scripts/80b_fun_metaeuk.sh` | 真菌基因预测双模式（`--method prodigal\|metaeuk`，默认Prodigal） | Prodigal/MetaEuk |
| 81 | `scripts/81_fun_eggnog.sh` | 真菌综合功能注释（COG/KEGG/GO） | eggNOG-mapper |
| 82 | `scripts/82_fun_kegg.sh` | 真菌 KEGG KO 通路注释 | KEGG diamond |
| 83 | `scripts/83_fun_dbcan.sh` | 真菌 CAZyme 注释 | dbCAN3 |
| 84 | `scripts/84_fun_vfdb.sh` | 真菌毒力因子（念珠菌/曲霉等） | VFDB |
| 85 | `scripts/85_fun_amr.sh` | 抗真菌药物耐药基因 | AMRFinder |
| 86 | `scripts/86_fun_merops.sh` | 真菌蛋白酶注释（侵袭相关） | MEROPS |

### 📊 统计分析（编号 91-98）

> **分析完成状态（Project_example，2026-06-22 更新）**
> - 91 多样性 ✅ / 92 差异分析 ✅ / 93 共现网络 ✅ / 94 可视化 ✅ / 95a/b 批次校正 ✅ / 96 SIAMCAT ML ✅
> - **统计分析管道已重设计（2026-06-22）**：去除可视化 PDF 输出，专注数据表格输出（TSV矩阵）
>   - `result/stat/{bacteria,virus,fungi}/{abundance,diversity,differential}/` — 三维度分层数据表格
>   - Snakemake rule all 仅追踪 4 个 TSV sentinel（diversity/diff/network/ml），PDF 按需手动运行
>   - 真菌维度：Project_example 测序深度不足，fungi_mt SKIPPED（预期行为）；现在会写 3 个 sentinel 文件标记跳过原因
>   - 病毒 vOTU 丰度表行名已清理为 `vOTU_N` 格式（原为 microeco compound label `k127_XXX|...`）
>   - 未分类 vOTU（Domain=NA）已从所有统计分析中过滤（22/49 有分类，27 已过滤）
> - **97 跨队列验证（本地多队列）**：97_stat_crosscohort.sh ✅（8个可视化+meta-analysis，支持本地多队列）
> - **✅ R 统计包依赖（envs/r_stat，2026-07-02 更新）**：
>   - 核心：phyloseq, microeco, vegan, microbiome, ggplot2, tidyverse
>   - 差异分析：ANCOMBC, Maaslin2, DESeq2, edgeR
>   - 机器学习：SIAMCAT, curatedMetagenomicData, caret, randomForest, glmnet
>   - 批次校正：MMUPHin, ConQuR, sva, MBECS, limma
>   - 网络分析：NetCoMi, SpiecEasi, igraph
>   - 新增：**file2meco**（microeco↔phyloseq转换桥梁）、**indicspecies**（指示物种分析）
>   - 其他：DirichletMultinomial（肠型分析）, patchwork, ggpubr, RColorBrewer

| 编号 | 脚本 | 功能 | 工具 |
|------|------|------|------|
| 01(stat) | `scripts/01_metadata_qc.sh` | **Metadata QC**：校验并标准化 `metadata.csv`（group/sample-id 一致性），生成 QC 报告与状态表，供下游全部统计模块消费。Snakemake rule：`stat_metadata_qc` | R (tidyverse) |
| 91 | `scripts/91_stat_diversity.sh` | Alpha/Beta 多样性计算与可视化。**新增（Phase 1）**：自动导出标准 phyloseq RDS 到 `result/stat/{dimension}/phyloseq/` 供下游所有 R 包使用 | vegan/phyloseq/microeco/file2meco (R) |
| 92 | `scripts/92_stat_differential.sh` | 差异分析（LEfSe/ANCOM-BC2/DESeq2/edgeR/MaAsLin2）。**2026-07-16**：从已废弃的 `04_differential_abundance.R` 移植补充 DESeq2/MaAsLin2 方法实现；同时接入 `scripts/R/plot_differential.R`（Nature风格火山图函数库，此前无人引用），为DESeq2结果生成 `volcano_deseq2.pdf`（依赖ggplot2/ggrepel/ggtext，缺失时优雅跳过） | R |
| 93 | `scripts/93_stat_cooccurrence.sh` | 跨维度共现网络 | FastSpar/SparCC |
| 94 | `scripts/94_stat_visualization.sh` | 统一可视化（热图/PCoA/桑基图/UpSet）。Snakemake rule：`stat_visualization`（**2026-07-16 修正**：registry 曾误报此 rule 自2026-06-08已集成，实际直到2026-07-16才真正接入 `rule all`） | ggplot2 (R) |
| 95a | `scripts/95a_stat_batch_correct.sh` | 多中心批次校正 Top10 方法（**Phase 2b 验证**：包依赖齐全，ComBat-seq 正常；其他方法因 API 变更需修复） | MBECS/ConQuR/MMUPHin (R) |
| 95b | `scripts/95b_stat_batch_evaluate.sh` | 批次校正评估报告（**Phase 2b**：存在 vegan::adonis2 公式拼接 bug，待 Phase 3 修复） | MBECS (R) |
| 96 | `scripts/96_stat_ml_siamcat.sh` | ML筛选+ROC评估（lasso/RF/SVM/enet 10折交叉验证，Top10特征+AUC对比），输出至 result/stat/ml/ | SIAMCAT (R) |
| 96(func) | `scripts/96_stat_functional.sh` | **功能差异分析**：对细菌/真菌/病毒各类功能表（KEGG-KO/COG/CAZyme/ARG/VFDB等，共20个 dimension×func_type 组合）执行差异分析。配套脚本 `96_stat_functional.R`（2026-07-16 由 `96_functional.R` 改名对齐）。Snakemake rule：`stat_functional` | R |
| 96(permanova) | `scripts/96_functional_permanova.sh` | 对96_stat_functional的功能组成结果执行 PERMANOVA 检验。Snakemake rule：`stat_functional_permanova` | vegan (R) |
| 96(integrated) | `scripts/96_functional_integrated.sh` | 多数据库整合可视化，按维度汇总96_stat_functional各func_type结果。Snakemake rule：`stat_functional_integrated` | R |
| 96(cross_dim) | `scripts/96_functional_cross_dimension.sh` | 三维度（细菌/真菌/病毒）功能显著信号联合对比。Snakemake rule：`stat_functional_cross_dimension` | R |
| 96b | `scripts/96b_pathway_activity.sh` | **Pathway Activity（通路活性分析）**：整合 HUMAnN3 分层通路丰度与覆盖度，评估通路完整性、主要物种贡献者及通路活性与群落组成的相关性，适用于定位驱动功能变化的关键物种。依赖：15；Snakemake rule：`stat_pathway_activity` | HUMAnN3 + R |
| 96c | `scripts/96c_functional_redundancy.sh` | **Functional Redundancy（功能冗余度分析）**：联合功能与物种丰度矩阵计算功能分散指数（FDI）和物种功能多样性，识别低冗余、潜在脆弱的关键功能，并可结合 ML 重要性筛选候选功能。依赖：98b、98c、98d、11；Snakemake rule：`stat_functional_redundancy`（**2026-07-16**：真菌分支路径由 shell 级 `find`/`if` 判断改为 Snakemake `input:` 声明，DAG 可正确追踪变更） | R |
| 97 | `scripts/97_stat_crosscohort.sh` | **跨队列验证（Phase 2a 统一）**：本地多队列 ML 迁移验证（8 个可视化 + meta-analysis）。输出到 `result/viz_crosscohort/`。旧的 `statistics.smk::stat_curatedMGD` 规则已删除避免冲突；对应的 `97_stat_curatedMGD.sh` 已于 2026-09-15 移除 | SIAMCAT/MMUPHin (R) |
| 98 | `scripts/98_stat_report.sh` | 按需生成带时间戳的分析结果 Markdown 快照报告 | bash + Rscript |
| 98c(mge) | `scripts/98c_bac_mge_summary.sh` | 汇总细菌 MGE（ISFinder/ICEberg/IntegAll/transposase）与质粒（PlasmidFinder）检测结果为整合表。Snakemake rule：`bac_mge_summary` | bash + awk |
| 98d(mag) | `scripts/98d_bac_mag_integration.sh` | 整合细菌 MAG 级分类（GTDB-Tk）、质量（CheckM2）、去冗余聚类（dRep）与丰度（CoverM）为整合表。Snakemake rule：`bac_mag_integration` | bash + awk |
| 98e | `scripts/98e_cross_domain_ani_cluster.sh` | **跨域基因组 ANI 聚类**：细菌 dRep MAG + 病毒 vOTU 代表序列 + 真菌 euk MAG 全体两两 FastANI 比对，networkx Louvain 社区检测（参考 VEBA cluster 方法论，非源码复用）。已知局限：跨"域"核酸 ANI 生物学意义有限，为用户知悉后接受的既定方案。配套 `98e_cross_domain_louvain.py`。Snakemake rule：`cross_domain_ani_cluster` | FastANI + networkx (envs/cluster) |
| 98f | `scripts/98f_cross_domain_orthogroup.sh` | **跨域蛋白正交基因组检测**：合并细菌 Prokka / 病毒 pharokka-prodigal / 真菌 MetaEuk 蛋白预测，MMseqs2 easy-cluster 检测跨域正交基因群。Snakemake rule：`cross_domain_orthogroup` | MMseqs2 (envs/cluster) |
| 98g | `scripts/98g_cross_domain_correlation.sh` | **跨域丰度互作网络**（2026-08-22 新增）：细菌/病毒/真菌丰度 TSS+CLR 标准化后计算跨域 Spearman 相关性（BH-FDR 校正），叠加 iPHoP 病毒-宿主预测边（`type=host_prediction`，与相关性边分开标记）。无真菌数据或 iPHoP 文件缺失时优雅降级。配套 `98g_cross_domain_corr.py`。Snakemake rule：`cross_domain_correlation` | scipy/pandas/networkx (envs/phagcn3) |
| 99a | `scripts/99a_core_microbiome.sh` | **Core Microbiome（核心微生物组识别）**：按流行率和最低丰度阈值识别全局及 case/control 组特异核心特征，输出核心成员表、共享关系、流行率曲线和核心丰度占比图，用于发现稳定定植成员。依赖：11、98b；Snakemake rule：`stat_core_microbiome`（**2026-07-16**：真菌分支同96c一并修正为显式 `input:` 依赖） | microbiome + R |
| 99b | `scripts/99b_lefse.sh` | **LEfSe Analysis（生物标志物发现）**：对细菌、病毒和真菌的分类或功能丰度表执行组间检验与 LDA 效应量排序，输出显著生物标志物、LDA 条形图及分类层级图，用于病例-对照标志物筛选。依赖：98b、98c、98d；Snakemake rule：`stat_lefse` | LEfSe-like + R |
| — | `downstream_summary`（无独立脚本，直接以 Snakemake inline shell rule 实现） | 汇总 Core Microbiome/Functional Redundancy/Pathway Activity 共7个下游模块的完成状态为单表。**2026-07-16 新增**，替代原 `99c_batch_downstream.sh`/`99d_downstream_summary.R`（与 Snakemake DAG 本身架构性重复，已于 2026-09-15 移除）。Snakemake rule：`downstream_summary` | bash（inline） |

### 🔄 串联流程脚本

| 脚本 | 功能 |
|------|------|
| `scripts/00_pipeline_bacteria.sh` | 细菌完整流程（01-02 + 11-41） |
| `scripts/00_pipeline_virome.sh` | 病毒完整流程（01-02 + 51-69） |
| `scripts/00_pipeline_fungi.sh` | 真菌完整流程（01-02 + 71-86） |
| `scripts/00_pipeline_full.sh` | 三维度完整流程 |

### 🔧 诊断与运维工具（2026-08-20/22 新增，无编号段，独立于三维度分析流）

| 脚本 | 功能 |
|------|------|
| `scripts/00_diagnose_error.sh` | 检测运行中的 SPAdes/Snakemake/Python 进程，扫描近期日志错误，检查磁盘占用；`-r/-l/-d/-a` 可选检测项 |
| `scripts/00_check_database.sh` | 验证三维度分析数据库完整性（Kraken2/MetaPhlAn4/HUMAnN/CheckM2/GTDB-Tk/dRep/Prokka/VirSorter2/CheckV/geNomad/iPHoP/Pharokka/EukCC2） |
| `scripts/00_multiqc_report.sh` | 汇总各分析模块 QC 数据（FastQC/Kraken2/MetaPhlAn4/HUMAnN/MEGAHIT/CheckM2/GTDB-Tk/CheckV/EukCC2）生成 MultiQC 交互报告 |
| `scripts/00_validate_metadata.sh` | 校验样本 metadata CSV/TSV（必需列、sample_id 格式、重复检测、FASTQ 存在性），`--strict` 模式将警告视为错误 |
| `scripts/00_track_status.sh` | 追踪 24 个关键分析脚本的执行状态（✓完成/⚠部分/✗未开始/⏱运行中/⚠陈旧），`-p/-s/--pending` |
| `scripts/00_preload_database.sh` | 将数据库文件读入 Linux page cache 预热，三级优先级（HIGH/MED/LOW），`--dry-run` 预览 |
| `scripts/00_snapshot_provenance.sh` | 捕获脚本版本、conda 环境导出、git commit、数据库校验和，生成可复现性快照 + manifest.json + checksums.sha256 |
| `scripts/00_e2e_test.sh` | 端到端回归测试：Quick 模式（QC→Kraken2→MEGAHIT）；Full 模式待实现 |
| `scripts/utils/detect_running_jobs.sh` | 检测运行中的 SPAdes/Snakemake/Python 进程，输出 JSON（process_type/pid/cpu_percent/mem_mb） |
| `scripts/utils/recommend_resources.sh` | 结合当前占用推荐 Snakemake 可用 CPU/内存，输出可直接拼接的 `--cores N --resources mem_mb=M` |
| `scripts/utils/cleanup_intermediate.sh` | 识别并清理 `temp/` 下超期中间文件（.sam/.fastq/tmp/scratch），**默认 dry-run**，需 `--execute` 才真正删除 |

## 1.3 维度间依赖说明

- **真菌 74e/74f**（PHF丰度定量）依赖 **74a** 的 Bowtie2 索引（一次性前置建库）
- **真菌 78-79**（组装+MAG）依赖 **71/72/74/75/76/77** 的分类输出（用于真菌 reads 提取）
- **真菌 75/76/77** 为三种互补分类策略（FunOMIC/CCMetagen/MicroFisher），建议同时运行后取共识
- **病毒 65**（PHOLD）依赖 **64**（PHAROKKA）的输出
- **统计 95b** 依赖 **95a** 的输出
- **统计 97** 依赖 **96** 或 **92** 的 Top10 特征输出

## 1.4 未知工具处理规则

当用户询问某工具的参数、用法或最佳实践时：
1. 先检查 `docs/` 下是否有对应 `.md` 文件（含 `docs/tools_ref/`）
2. 若无，使用 WebSearch + WebFetch 获取官方文档
3. 将学到的知识缓存至 `docs/tools_ref/{tool_name}.md`（文件名加 `.auto.md` 后缀表示自动生成，已加入 .gitignore）
4. 基于获取的知识回答问题或生成脚本

## 1.5 脚本编写前置调研规则（必须遵守）

**编写任何分析脚本前，必须完成以下调研步骤，综合后再动笔：**

### Step 1 — 读取本地资料
优先阅读以下资料中与当前脚本功能相关的内容：

| 资料 | 路径 | 适用场景 |
|------|------|---------|
| EasyMetagenome | GitHub 重新下载（原 `Reference/EasyMetagenome.zip` 已于 2026-09-21 清理）| 宏基因组全流程，MetaPhlAn4/HUMAnN4/组装/Binning/统计 |
| Metagenomics_Apptainer_pipline | `~/Course/Metagenomics_Apptainer_pipline/` | Centrifuger 分类、宏基因组组装、功能注释 |
| Binning_Apptainer_pipline | `~/Course/Binning_Apptainer_pipline/` | MAG 挖掘、Binning、CheckM2、dRep |
| Virus_Apptainer_pipline | `~/Course/Virus_Apptainer_pipline/` | 宏病毒组全流程（geNomad/VirSorter2/CheckV/iPHoP） |
| WGS 单菌分析资料 | `~/Course/CSCCD-MetagenomeFlow/Reference/WGS_prokaryote.pipeline.v0.7.sh` | 单菌/分离株 WGS：组装、MLST、泛基因组、系统发育树、变异检测 |

### Step 2 — 网络检索最新实践
**每次编写脚本前必须检索**（使用 WebSearch 工具）：
1. **PubMed**：搜索工具名 + "metagenomics" / "pipeline" / "tutorial"，了解最新发表的使用方式和推荐参数
2. **GitHub**：搜索工具官方仓库的 README / wiki / tutorial，获取最新命令行用法和已知 issue
3. **工具官方文档**：如有官网或 ReadTheDocs，优先参考

检索关键词格式：`{tool_name} metagenomics pipeline best practice {year}`，year 填写当前年份（2026）。

### Step 3 — 综合后编写
- 对比本地参考与在线最新实践的差异
- 优先采用工具官方推荐参数（README/文档 > 发表文章 > 其他流程二手引用）
- 如有参数版本差异，以当前环境实际安装版本为准（`conda run --prefix ... tool --version`）
- 在脚本注释中注明关键参数的来源依据

## 1.6 Architecture Components（架构层说明）

> 当 CC 需要了解项目架构、各层职责或如何整合新脚本时，优先读本节。

### 双模式架构总览

```
scripts/*.sh          ← 原子执行单元（永远不变，所有模式共用）
      │
      ├── Mode 2: Bash Pipeline    scripts/00_pipeline_bacteria.sh
      │          轻量，单机，无额外依赖，--skip/--from/--only 控制步骤
      │
      └── Mode 3: Snakemake        pipeline/Snakefile
                 DAG 依赖追踪，原生断点续跑，HPC 就绪

agents/               ← Agent Skills 系统（Claude Code 交互式驱动）
  registry.yaml       全局脚本状态（not_started/in_progress/ready/integrated）
  skills/*.yaml       工具卡片（输入/输出/依赖/性能/已知问题）
  provenance/*.json   运行轨迹记录（/mgx-learn 自动写入）

```

### 各层文件职责

| 层 | 文件 | 维护者 | 触发时机 |
|---|---|---|---|
| 执行层 | `scripts/*.sh` | 脚本作者 | 编写/测试新分析步骤 |
| Snakemake 层 | `pipeline/rules/*.smk` | CC | 每次新脚本 integrated |
| 工具卡片层 | `agents/skills/*.yaml` | CC | 每次新脚本 integrated |
| 状态追踪层 | `agents/registry.yaml` | 双方 | 脚本 ready 或 integrated 时 |
| 运行记录层 | `agents/provenance/*.json` | CC (`/mgx-learn` 或 `batch_provenance_backfill.py`) | 每次实际运行后 |
| CC 技能层 | `.claude/skills/*.md` | CC | 架构演进时修改 |
| 自动挖掘层 | `mining/*.py` + `mining/m4/` | 主代理+子代理 | 周增量 cron / 策展批次 / 数据集编排 / 疾病指纹比对 |
| 挖掘数据层 | `mining/*.sqlite` + `mining/snapshots/` | mining 脚本 | cron 周一 / 策展批次（详见 `mining/README.md`，含 scBaseCount 式循环操作手册） |

### pipeline/ 目录结构

```
pipeline/
├── Snakefile                   入口（include rules/*.smk）
├── config/
│   └── config.yaml             运行时参数（每次分析前编辑）
├── profiles/
│   ├── auto/                   当前机器自动生成（/mgx-tune）
│   ├── local_16c/              16核预设
│   ├── local_48c/              48核预设（本机）
│   ├── local_96c/              96核预设
│   └── hpc_slurm/              HPC SLURM预设
└── rules/
    ├── preprocessing.smk       rules: fastp_qc, kneaddata ✅
    ├── bacteria_taxonomy.smk   rules: metaphlan4, metaphlan4_merge, strainphlan4, humann3 ✅
    ├── bacteria_assembly.smk   rules: megahit, prodigal, cdhit, salmon_build, salmon_quant ✅
    ├── bacteria_annotation.smk rules: eggnog, kegg, amrfinder, card, dbcan, vfdb, bacmet, antismash, defense_finder, ncyc, pcyc ✅ (kegg已加log:/threads:)
    ├── bacteria_binning.smk    rules: coverm_depth, metabat2, maxbin2, semibin2, dastool, checkm2, drep, coverm_quant, gtdbtk, prokka, mlst, pangenome, snippy ✅
    ├── virome.smk              rules: 51-72（含54b/58-60/70/71/72）✅ 全流程验证通过 2026-06-17
    ├── mycobiome.smk           rules: 71-86（含74a/74e/74f/75/77-86）✅
    ├── statistics.smk          rules: 91-98 ✅（已从rule all移除，R包缺失，需手动安装后运行）
    └── rag.smk                 rules: refresh_literature_kb ✅
```

### agents/skills/ 工具卡片格式（关键字段）

```yaml
id: "14_bac_kraken2"           # 脚本 ID
rule_type: "per_sample"        # per_sample | aggregate
inputs:  [{name, path_pattern, required}]
outputs: [{name, path_pattern, description}]
depends_on: [...]              # DAG 依赖
benchmarks: {typical_runtime_min, peak_memory_gb}
known_issues: [{description, workaround}]
integration_status: "integrated"
snakemake_rule: "pipeline/rules/bacteria_taxonomy.smk::rule_name"
```

## 1.7 CC 新脚本集成工作流（必须遵守）

当脚本作者在 `agents/registry.yaml` 中将某脚本状态更新为 `ready`，或直接告知 CC "XX 脚本 ready 了"时，CC 执行以下固定流程：

### Step 1 — 调用 /mgx-integrate
读取脚本 → 提取路径/依赖 → 生成工具卡片 → 写 Snakemake rule → 更新 registry

### Step 2 — 调用 /mgx-review
验证清单：
- [ ] Snakemake rule 输入路径与脚本变量完全一致
- [ ] 输出路径与脚本变量完全一致
- [ ] rule_type 正确（per_sample / aggregate）
- [ ] 聚合 rule 用 `expand()` 收集所有样本
- [ ] 聚合 rule 输出使用 sentinel `.done` 文件
- [ ] skill card 的 `snakemake_rule` 字段指向正确

### Step 3 — git commit
```
git add pipeline/rules/*.smk agents/skills/<id>.yaml agents/registry.yaml
git commit -m "feat: integrate <script_id> into Snakemake pipeline + skill library"
```

### Step 4 — 更新 Snakefile rule all（如需）
新脚本的输出如果是下游分析的必要前置，将其加入 `pipeline/Snakefile` 的 `rule all` 输入列表。

## 1.8 跨队列验证详情（脚本 97 补充说明）

**脚本 97** (`97_stat_crosscohort.sh`) 增强版跨队列验证，支持本地多队列和 curatedMetagenomicData：

**核心功能**：
- ✅ 本地多队列模式（推荐）：从多个项目目录读取数据
- ✅ 模型迁移验证：在训练队列训练 → 测试队列预测
- ✅ 8 个核心可视化：森林图/瀑布图/ROC叠加/UpSet/特征稳定性热图/PCoA批次/校准曲线/效应相关
- ✅ Meta-analysis：随机效应模型合并 AUC + I² 异质性评估

**使用场景**：
```bash
# 本地多队列（3个医院数据）
bash scripts/97_stat_crosscohort.sh \
  -w Project/Hospital_A -r ~/Course/CSCCD-MetagenomeFlow \
  -m metadata.csv -g Group \
  --source local --cohorts "Hospital_A,Hospital_B,Hospital_C" \
  --train-cohort Hospital_A --meta-analysis

# 单队列（框架测试）
bash scripts/97_stat_crosscohort.sh \
  -w Project/Project_example -r ~/Course/CSCCD-MetagenomeFlow \
  -m metadata.csv -g Group --source local
```

**输出目录**：`${WORKDIR}/result/viz_crosscohort/`（8个PDF + 2个TSV + sentinel）

**详细文档**：`docs/97_crosscohort_usage.md`

## 1.8.1 测试/CI 体系（三层金字塔）

2026-07-28 搭建，本地伪CI（不依赖远程CI平台，仓库不依赖远程 CI 平台）。

```
scripts/tests/
  level1/run_shellcheck_all.sh        — 层一：全量155脚本shellcheck静态检查
  level2/test_*.sh                    — 层二：抽样代表性脚本集成测试（3个）
  level2/generate_fixture_*.R         — 层二用的fixture中间产物生成器
  level3/test_dag_connectivity.sh     — 层三：Snakemake DAG连通性 dry-run
  run_ci_checks.sh --level {1,2,3,all} — 统一入口，PASS/FAIL汇总表

.shellcheckrc                         — exclude清单（数据驱动定稿，非拍脑袋）
scripts/hooks/pre-commit + scripts/install_git_hooks.sh — git pre-commit hook（增量检查，阻断模式）
Project/Test_CI_fixture/              — 专用4样本测试数据集（与Project01物理隔离）
pipeline/config/config.test_ci.yaml   — 层三DAG测试专用config
```

**日常使用**：
```bash
bash scripts/install_git_hooks.sh          # 一次性：安装pre-commit hook
bash scripts/tests/run_ci_checks.sh --level all   # 按需：跑全部三层
bash scripts/tests/run_ci_checks.sh --level 2     # 只跑层二集成测试
```

**层二/层三均为手动/按需触发，不设 cron**——项目仍在本地开发阶段，样本量和使用频率不足以支撑每日定时跑批的价值。

## 1.9 文献技能包存放规范

```
skills/replications/
  SCHEMA.md                         — 统一 schema 规范（nf-core+xKG+MCP+RO-Crate）
  registry.yaml                     — 全局技能包索引
  fungi/
    Yan2024_Cell187/                 — 命名规范：<Author><Year>_<Journal><Vol>
      manifest.yaml                 — PaperBench 四维复现评分
      method_graph.yaml             — xKG 分析 DAG
      params.yaml                   — 文献推荐参数（跨文献对比层）
      validate.sh                   — 可运行验证命令
      README.md                     — RAG 自动索引摘要
      code/original/               — 原作者代码（git clone，不修改）
      code/adapted/                 — 项目适配版本（路径变量化）
  bacteria/                         — 细菌维度文献
  virome/                           — 病毒维度文献
```

## 1.10 Graphify 知识图谱技能

**安装**: `pip install graphifyy && graphify install` (已完成 2026-06-12)
**Skill 文件**: `~/.claude/skills/graphify/SKILL.md`

- **graphify** (`~/.claude/skills/graphify/SKILL.md`) — 将项目文件提炼为知识图谱（NetworkX + Leiden 社区检测）。Trigger: `/graphify`
- When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.

常用命令:
- `/graphify docs/ agents/skills/ pipeline/rules/`  — 构建分析平台知识图谱
- `/graphify docs/experience/`                      — 经验文档结构导航
- `graphify query "metaphlan4 connects to humann3"` — 图路径查询
- `graphify --mcp`                                  — 启动 MCP stdio 服务（与 RAG MCP 并联）
- `graphify --update`                               — 增量更新（新脚本集成后使用）

## 1.11 Claude Code 可调用技能完整索引

`.claude/skills/` 下 18 个 `/mgx-*` 技能（不含根目录 `/graphify`，见 §1.10）：

| 技能 | 触发词/场景 | 用途 |
|------|-----------|------|
| `/mgx-welcome` | "欢迎"/"介绍一下"/"怎么用" | 项目欢迎页，首次打开项目时展示 |
| `/mgx-status` | "分析进度"/"跑到哪了" | 查看当前项目各维度脚本执行进度 |
| `/mgx-plan` | "怎么做分析"/"分析计划" | 根据数据类型规划分析路径 |
| `/mgx-run` | "运行XX脚本"/"启动分析" | 执行指定分析步骤（由编程助手执行） |
| `/mgx-review` | 脚本作者说"XX脚本ready了" | 审查新脚本质量，见 `/mgx-integrate` 前置步骤 |
| `/mgx-integrate` | 脚本作者说"XX脚本ready了" | 将审查通过的脚本集成进Snakemake+registry+skills |
| `/mgx-learn` | 分析运行完成后 | 记录provenance，供未来复用参数经验 |
| `/mgx-ask` | 询问某工具参数/用法 | 查询本地文档或WebSearch动态学习并缓存 |
| `/mgx-tune` | "推荐参数"/"调参"/"硬件配置" | 根据样本量/硬件推荐分析参数与profile |
| `/mgx-core` | 核心概念咨询 | 项目架构/维度/运行模式速查 |
| `/mgx-index` | "更新知识库"/"重建索引"/"整进RAG" | 重建 experience/literature/mechanism/skill_design 4个RAG collection索引 |
| `/mgx-replicate` | "把这篇文献整进项目/复现" + DOI/PMID/PDF | 文献复现技能包生成（见 §1.9） |
| `/mgx-lefse` | LEfSe生物标志物分析咨询 | `99b_lefse` 工具卡片与参数说明 |
| `/mgx-pathway` | 代谢通路活性分析咨询 | `96b_pathway_activity` 工具卡片与参数说明 |
| `/mgx-redundancy` | 功能冗余度分析咨询 | `96c_functional_redundancy` 工具卡片与参数说明 |
| `/mgx-plot-composition` | 物种/功能组成可视化 | 堆叠柱图/桑基图生成 |
| `/mgx-plot-diversity` | 多样性可视化 | Alpha/Beta多样性图生成 |
| `/mgx-plot-heatmap` | 热图可视化 | 丰度/差异热图生成 |
| `/mgx-plot-network` | 共现网络可视化 | 跨维度共现网络图生成 |
| `/mgx-plot-ordination` | 排序图可视化 | PCoA/NMDS排序图生成 |
| `/mgx-plot-phylotree` | 系统发育树可视化 | 菌株/物种进化树图生成 |
| `/mgx-plot-volcano` | 火山图可视化 | 差异分析火山图生成（2026-07-16起 `92_stat_differential` 也会自动生成，见该脚本条目） |

> 本索引由 2026-07-16 头脑风暴发现补齐：此前 CLAUDE.md 声称"完整技能索引见 §1.9-1.10"，但那两节实际是文献技能包规范和Graphify，并非技能列表。

## 1.12 ScientificFigureLibrary（图件模板库 MCP，项目级，2026-09-15 新增）

**定位**：本地优先的科研图件模板库（MCP server + MCP App）。导入「图 + 代码」→ 评审 → 发布不可变 Release 到本机 Library → 跨项目复用同一模板。**不执行绘图代码**（宿主 agent 检查文件，SFL 只做 hash/版本/门禁/发布）。上游 `github.com/xuzhougeng/ScientificFigureLibrary`，MIT，v0.7.0。

**与既有绘图技能的关系**：11 个 `/mgx-plot-*` 技能负责「画」；SFL 负责「沉淀可复用的图件模板资产」——分层互补，无功能重叠。

**本项目部署（全部在项目路径内，不修改服务器全局环境）**：

| 项 | 位置 |
|---|---|
| 工具本体 | `tools/ScientificFigureLibrary/`（Release ZIP 还原，已 gitignore） |
| 图件库 | `FigureLibrary/`（用户数据，已 gitignore） |
| MCP 注册 | 项目根 `.mcp.json`（**不动 `~/.claude.json`**），server 名 `figure-library` |
| Library 绑定 | 环境变量 `FIGURE_LIBRARY_DIR=<PROJ_DIR>/FigureLibrary` 与 `FIGURE_WORKSPACE_DIR=<PROJ_DIR>/FigureLibrary/workspace`（均项目内；不写 `~/.config` locator） |
| 依赖 | Node.js 22+（本机 v24.16.0） |

**还原步骤**（Release ZIP 方式，免 npm 构建）：

```bash
BASE=https://github.com/xuzhougeng/ScientificFigureLibrary/releases/download/v0.7.0
curl -sSL -o sfl.zip $BASE/scientific-figure-library-claude-0.7.0.zip
unzip -q sfl.zip -d tools/ScientificFigureLibrary
```

**主要工具**：`figure_library_search` / `figure_library_open` / `figure_library_plan_materialize`+`apply_materialize`（复用模板）/ `figure_library_plan_working_revision`+`apply_working_revision`（导入）/ `figure_library_plan_publish_working_revision`+`apply_publish_working_revision`（发布）。

**回退**：删除 `.mcp.json` 中的 `figure-library` 段（或整个 `.mcp.json`）即可。
