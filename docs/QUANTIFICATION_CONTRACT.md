# Quantification Semantics & Unit Contract (E-DOC-01)

- **日期**: 2026-09-26 · **状态**: DRAFT → 冻结为 Phase 2 契约
- **基线**: phase1-correctness-stable · **方法**: 先只读审计各层 producer 的真实参数与输出形态,再形成 contract(不改任何代码/表)
- **目的**: 回答"每个现有数字究竟代表什么",并显式声明禁止直接混比的组合

---

## 1. Quantity vs Unit 契约 schema

每个定量输出必须可表达 5 维:`entity_type`(实体)/ `quantity_type`(生物量纲)/ `unit`(表示)/ `normalization`(归一方式)/ `source_step`(producer)。下表是当前系统的权威登记——**新增列或新表时必须按此 schema 声明**。

## 2. 当前系统定量语义登记表(审计依据:producer 脚本参数 + 输出实样)

| # | 输出(producer) | entity_type | quantity_type | unit | normalization | source_step | 审计证据 |
|---|---|---|---|---|---|---|---|
| Q1 | `quant.sf` TPM(20 Salmon) | NR gene | relative RNA abundance(转录本比例) | TPM | within-sample, ΣTPM=10⁶ | 20_bac_salmon_quant | `salmon quant --validateMappings`,无 seqBias/gcBias(20:119);TPM 取自 salmon 直接输出 |
| Q1b | `quant.sf` NumReads(20) | NR gene | estimated read count | reads | 无(绝对计数估计) | 同上 | salmon 估计计数,非原始 mapped count |
| Q2 | CoverM `-m relative_abundance`(39:66) | MAG | **genome-relative read fraction**(比对到该基因组的 read 占该样本总比对 read 比例) | fraction(0-1,**单样本内全基因组列和≈1**) | by mapped reads | 39_bac_coverm_quant | CoverM relative_abundance 语义=reads(mapped to genome)/total mapped reads |
| Q2b | CoverM `rpkm / tpm / count / covered_bases`(39:66) | MAG | coverage 族 | RPKM/TPM/bases | 各按 CoverM 定义 | 39_bac_coverm_quant | 同一命令输出五列,98d 消费的是 **TPM 列** |
| Q3 | vOTU TPM(59 salmon→60 聚合) | vOTU(canonical,经 T-16 map) | relative RNA abundance | TPM(vOTU 级=CDS TPM 之和) | within-sample | 59+60 | `salmon quant -l A` 无 bias 校正(59:50-53);60 按 canonical 聚合,总量守恒(Phase 1 已证) |
| Q4 | MetaPhlAn4 merged `taxonomy.tsv`(11b) | taxon(species 等) | relative abundance | fraction(0-100,mpa 惯例 ×100) | within-sample | 11+11b | 表实样:`UNCLASSIFIED 0.0 3.626199`(0-100 量纲) |
| Q5 | Kraken2/Bracken(14+14b) | taxon | estimated read count → Bracken abundance | reads | 无 | 14+14b | Bracken 输出 abundance=估计 reads |
| Q6 | 真菌 FunOMIC count(75b) | fungal species | **detection count(检测计数)** | count(存在性/次数) | 无 | 75+75b | `funomic_species_count.tsv`(75b:6) |
| Q6b | FunOMIC relab/clr(75b:7) | fungal species | relative abundance | fraction / CLR | within-sample / CLR | 75b normalized/ | 同 producer 派生 |
| Q7 | PHF 簇 .rc → merged(74f) | fungal cluster(760 基因组基因集簇) | read 分配计数 | reads(Singular/Escrow 分配) | 无(绝对) | 74e+74f | .rc 矩阵,GPA 相对丰度为派生 |
| Q8 | HUMAnN3 pathabundance_relab(13b) | pathway | relative abundance | fraction(0-1) | within-sample | 13+13b | humann relab 输出 |
| Q9 | 统计层 microeco `cal_abund(rel=TRUE)`(92:172) | taxon | relative abundance | fraction(0-1) | within-sample(微生态按 OTU 表列和归一) | 91/92 R | 92:172-174;**92:184 的 DESeq2 输入=round(relab×1000) 伪计数(已知局限,STAT-4 文档化)** |
| Q10 | 真菌 98d gene 检出表 | fungal gene | **detection(存在性)** | binary/count | 无 | 81-86+98d_fun | 98d:7-15 注释自述 count 语义 |
| Q11 | 跨域 98g 输入 | 各域 entity | 先 TSS 后 CLR | CLR 值 | compositional 变换 | 98g | 98g:5,116(两域各自 TSS+CLR 后 Spearman) |
| Q12 | ML 96 输入(96:55-59) | 特征(细菌 relab/病毒 vOTU TPM/真菌 relab) | 混合(见禁止混比) | 混合 | 各源不同 | 96 | **unit 混合喂入同一 CV——已知语义债,Phase 3 ML 层处理** |

## 3. 禁止直接混比清单(Hard Rules)

以下数值**不因都是"丰度"而直接比较/拼接进同一矩阵**:

1. `Q1 gene TPM` vs `Q3 vOTU TPM`:同 unit 不同 entity(基因集不同:NR gene catalog vs vOTU CDS 并集);
2. `Q2 MAG TPM`(CoverM) vs `Q1/Q3 Salmon TPM`:**不同工具不同语义**(CoverM TPM=覆盖度换算,salmon=转录本比例;参考组不同);
3. `Q4/Q9 relab`(0-100 与 0-1 两种量纲并存!)vs `Q5/Q7 reads`:相对 vs 绝对;
4. `Q6 fungal count(检测计数)` vs 任何丰度:**存在性语义,非数量**;
5. `Q2 relative_abundance`(genome read fraction) vs `Q4 taxon relab`:分母不同(mapped reads vs classifier total);
6. 任何跨 unit 联合建模,必须先显式定义 transformation(如统一到 CLR),Phase 2 不自动执行。

**特别声明**:Q4 的 0-100 与 Q9 的 0-1 是当前系统内**同一 quantity 的两种量纲**,任何 join 必须显式换算——此点登记为长期契约。

## 4. 发现的语义债(登记,不在本 ticket 修)

| 编号 | 内容 | 处置 |
|---|---|---|
| D-1 | 92:184 DESeq2 输入 relab×1000 伪计数(丢失文库大小) | STAT-4 已文档化,主结论排序以 ANCOM-BC2/MaAsLin2 为准 |
| D-2 | 96 ML 输入 unit 混合(relab+vOTU TPM) | Phase 3 ML 层(feature standardization 审计) |
| D-3 | Q4(0-100)与 Q9(0-1)量纲并存 | 本契约 §3.6 声明;新表一律 0-1 |

## 5. Contract 落地方式(最小实现)

- 本文档 = 权威登记;`docs/` 内新增定量表时的引用标准。
- 后续 E-类 ticket 的表头注释加一行 `# unit-contract: Qn(引用本表)`,不机械加列。
- 96f 输出表头已由 E-FUNC 系列联动补 `unit` 行(Q6/Q6b/Q8 分支)。

## 6. 验收

- 审计覆盖 12 类定量输出(全部 producer 参数+实样核对);
- 禁止混比清单显式;语义债 3 项登记并有去向;
- 零代码改动,零表结构变化(符合 Evidence-first 原则)。
