# Phase 2 Evidence & Interpretation PRD

- **日期**: 2026-09-26 · **状态**: DRAFT — 待用户批准后进入执行
- **基线**: tag `phase1-correctness-stable`(54c28fe)+ hygiene commit `fa9817f`(P1.5 已收口)
- **Phase 1 遗产**: 12 CONFIRMED_FIXED / 1 NOT_REPRODUCED / 6 audit corrections / Unexpected=0 / Tier C 泛化 PASS;golden baseline + manifest + recovery snapshot + defect ledger 全部在位
- **核心命题**: Phase 1 建立了 Correctness;Phase 2 建立 **Evidence + Interpretation**——同一个结果,任何人都能看懂它为什么存在、证据有多强、来自哪里、哪些是观测事实、哪些只是模型预测或统计关联。

---

## 1. 稳定基线与执行前提

- 生产代码起点 = `phase1-correctness-stable`;Phase 2 每个 commit 可回溯到该 tag。
- 冻结延续:软件/数据库版本不动;canonical identity、join、QC funnel、fail-fast、failure semantics、paths、provenance **不得重新设计**。
- 纪律延续:先审计 → 定义语义 → 实现 → targeted validation → regression → commit;一 ticket 一个解释问题,一个 commit。
- 不以任何"更多阳性"为成功指标;成功 = 证据结构更清楚。

## 2. Scope(六个方向)

1. MAG 证据与质量分层;2. 病毒 evidence hierarchy(host/detection/AMG);3. 真菌可信度与低生物量证据分层;4. taxonomy 多来源一致性;5. 功能结果 evidence provenance;6. 跨域结果与统计解释层 + 统一定量语义。

## 3. Out of Scope

- QuickBin challenger 进入 production(保留 diagnostic challenger;benchmark ticket 定义在 P3,不实现);
- ML 患者级 leakage 防护(Phase 3;Phase 2 只做 feature provenance);
- 任何版本/数据库升级、新工具接入 production;
- 阴性对照污染建模(无对照数据;只落 `negative_control_available=false` + future hook);
- 78 号真菌 reads 提取接入主链(先审计"解决哪个已观察到的问题",默认维持 P2);
- 任何"过滤掉低置信结果"的操作——所有分层的默认行为是**标注,不删除**。

## 4. Evidence Model(统一概念,非机械字段)

三层概念,各模块实现自己的 profile,不强行统一数值分数:

- **Entity**:被解释的对象(entity_id/entity_type;vOTU、MAG、fungal species、gene、edge、feature)。
- **Evidence**:实际观测到的证据,保留原始形态——sequence match、HMM hit、CRISPR spacer、tRNA、classifier prediction、coverage、abundance correlation、DA method result。字段族:`evidence_type / evidence_source(工具或表) / evidence_method(算法) / support_count / source_sample / source_table / source_step / provenance_reference`。
- **Confidence**:由一条或多条 evidence 依**显式规则**导出的分层,永不覆盖 evidence;必须可从 confidence 反查证据(rule 记录在表头注释与文档)。禁止黑箱综合分(`MAG_score=87.3` 一类)。

三条硬规则:
1. **Exclusivity**:不同 evidence type 不混列(§十一:predicted_host ≠ sequence_supported_host ≠ ecological_association)。
2. **Preservation**:多来源证据全部保留;可另加 best_confidence_level,但不丢细节(§十)。
3. **Traceability**:任何 confidence 可回答"为什么是这个等级?删掉某条 evidence 会变成什么?"(§三十八)。

## 5. 模块级 Evidence Gaps(基于 Phase 1 审计,file:line 溯源)

| 模块 | 现状(Phase 1 审计证据) | Gap |
|---|---|---|
| MAG | 98d 仅 GTDB+CheckM2+dRep+CoverM(98d:280-283);GUNC 不回流(38b 不在 rule all);无 N50/size/contig count/来源样本/binner;inStrain(39b-d)未回连 | 无 quality tier、无 evidence profile |
| 病毒 host | 98g 有 type=host_prediction/correlation 分列(98g_corr.py:203,252)但 confidence 缺失曾默认 1.0(Phase 1 XDOM-1 未实施);70 PhaBox2 CHERRY/HostG 输出弃用(70:44,66);68 iPHoP 仅 genus m90;CRISPR/tRNA 证据未读取 | 无 host evidence 层级,多来源不保留 |
| 病毒 detection | "交集"实为并集+去重(54:63-69);无 per-tool 归属统计 | union 语义未文档化、无 detected_by 列 |
| 病毒 AMG | aux score 缺列补 5(71:161-169)反向降级;无 Defense-Finder 排除;DRAM_amg_summary 无消费者 | 无 evidence 分层,假阳性不可评估 |
| 真菌 | 71-77 五分类器并列无对照;三丰度来源互不校验(statistics.smk:135 / 98d:351 / 74f);低丰度无置信标记;74f 丢弃 cluster_reads | 无 per-species evidence、无 confidence |
| taxonomy | read-level 6 来源零交叉验证;15e readfrac 无消费者;GTDB/NCBI 双命名无映射;MAG vs read 无对照 | 一致性/分歧不可见 |
| 功能 | 98b 丢弃 evalue/bitscore;DIAMOND>HMMER 择优隐式(98b:338-343,590-596);Pfam 未入矩阵;无 gene→MAG 列 | evidence provenance 缺失 |
| 跨域 | 98g 边有 type 分列但无 evidence_type/score 语义说明;网络边无统一 schema | edge 语义不可区分 |
| 统计 | 5 种 DA 方法并存,summary 只有 n_sig(92:71-80);99b 无 FDR | 无 consensus evidence 表 |
| 全局 | 定量单位(TPM/rpkm/coverage/relab/count)无 schema 文档 | 跨表混比风险 |

## 6. Ticket 清单(P1/P2/P3,E/I/M 分类)

分类定义:**E**=Evidence-only(只加证据/解释字段,不改 entity universe);**I**=Interpretation(分层/consensus 规则,可能改变报告解释,需 validation);**M**=Method challenger(独立 benchmark,P3)。

### P1 第一批(E 类优先)

#### E-MAG-01 MAG evidence profile
1. **Module**: MAG
2. **Current**: 98d 表 213 行 × (GTDB/CheckM2/dRep/TPM)(98d:280-283)
3. **Evidence gap**: 无 GUNC/N50/size/contig count/来源样本/binner
4. **Scientific meaning**: MAG 质量不止 CheckM2;嵌合风险(GUNC)、组装质量(N50)、来源(binner/sample)决定解释强度
5. **Proposed layer**: 98d 加列 GUNC_pass/CSS、genome_size、N50、contig_count、source_sample(从 MAG 名前缀)、binner_source(名中 binner 段)
6. **Source data**: 37 quality_report.tsv、38b GUNC 表、dRep Cdb、CoverM、faidx
7. **New fields**: 上列 6 项
8. **Existing values**: 不变(只加列)
9. **Production logic**: 不改(98d 纯后处理追加)
10. **Validation**: 列值与源文件逐行抽查 20 MAG;row/keys 不变
11. **Acceptance**: 全部新列可溯源到源表;Phase 1 invariants 通过
12. **Rollback**: revert 单 commit
13. **Priority**: P1(E)

#### I-MAG-02 HQ/MQ/Exploratory tier(依赖 E-MAG-01)
14 字段要点: **layer**=tier 列(HQ/MQ/exploratory);**rule**=MIMAG(HQ≥90%/≤5%,MQ≥50%/<10%,其余 exploratory)——执行前核对项目既有标准(MIMAG 为领域默认,若项目文档另有定义以项目为准);**不变**=不删除任何 MAG(§八);**validation**=tier 可由 CheckM2 comp/cont 复算(100% 可复算性测试);**acceptance**=每个 MAG 的 tier 反查通过。P1(I)。

#### E-VIR-01 viral host evidence hierarchy
**gap**: 68 iPHoP(confidence 数值)/70 PhaBox2(弃用)/29 spacer 未消费;98g host 边无 confidence(Phase 1 XDOM-1 未做)。**layer**: per-vOTU host_evidence 表,列区分 `predicted_host`(模型)/`sequence_supported_host`(CRISPR/tRNA/直接同源)/`ecological_association`(丰度相关)——**四类分列,永不合并进单一 host 字段**;全部来源证据保留;`best_host_confidence_level`(A/B/C/D 按审计后实际证据定义,先审计 68/70 的输出语义再定,不预设)。**source**: 68 iPHoP 输出、70 PhaBox2(70 号顺带拷贝 CHERRY/HostG 文件)、98g、29。**validation**: 每个 host 断言可反查来源行;A-D 规则文档化;抽查 20 vOTU。P1(E+I 复合,先 E 后 I)。

#### E-VIR-02 detection consensus 统计
**gap**: 54 并集+去重语义未文档化、无 per-tool 归属。**layer**: 54 输出 detected_by_geNomad/detected_by_VirSorter2/support_tool_count 三列+统计行;文档明确写 **union + exact dedup**(纠正"交集"误导)。**不变**: Final vOTU universe 不动(§十二)。**validation**: support_tool_count 与 52/53 原始输出对账。P1(E)。

#### E-VIR-03 AMG evidence layer
**gap**: aux 缺列补 5(71:161-169)、无防御基因排除、DRAM_amg_summary 无消费者。**layer**: 98c AMG 呈现层加 `AMG_flag / auxiliary_score(缺失→unassessed,不再补 5)/ Defense-Finder-overlap / amg_evidence_tier(stronger/candidate/exploratory)`;tier 规则:flag=A/M + aux≤3 = stronger(依 DRAM 语义);与 Defense-Finder 命中重叠 → 标记 potential_defense/misleading(降级到 exploratory 并保留原注释)。**文档**: annotation ≠ mechanistic interpretation(§十四)写入表头注释。**validation**: 与 71/29 源表逐行可溯;不删任何 AMG 行。P1(E+I)。

#### E-FUN-01 fungal per-species evidence table
**gap**: 五分类器并列无对照(§五真菌行)。**layer**: 新表 per-sample×species:detected_by_Kraken2/MetaPHlAn4/BLAST-gutdb/FunOMIC/MicroFisher、read_count、relab、sample_prevalence、cross_method_support_count、`low_read_support / low_relative_abundance` heuristic flag(reads<10 或 relab<0.01%,**标注不删除**,表头注明 heuristic 非污染真值)。**source**: 71 Bracken/72/74/75b/77 既有输出(纯汇总)。**canonical 源不换**(统计仍以 MetaPhlAn4 为锚,冻结)。**validation**: 每个检出可反查源表;heuristic flag 可复算。P1(E)。

#### I-FUN-02 fungal confidence tiers(依赖 E-FUN-01)
high_confidence(≥2 方法支持或 PHF 高 reads)/supported(1 方法+非低支持)/exploratory(仅单方法+low flag)——规则表随表输出;**不删除低丰度结果**(§十六);`negative_control_available=false` 落表+future hook 占位(§十七)。P1(I)。

#### E-TAX-01 read-level taxonomy cross-validation report
**gap**: 6 来源零交叉验证;15e readfrac 无消费者。**layer**: 只读报告:每样本 MetaPHlAn4 vs Bracken_S vs MetaX readfrac 按属(经 taxid/名归一)join → shared/specific 清单、Jaccard、丰度 Spearman、top discordant taxa、unmatched names。**不改任何生产表**;挂 98_stat_report。**validation**: 与三源原始输出对账。P1(E)。

#### E-TAX-02 MAG vs read taxonomy 对照表
四象限标签:read_detected+MAG_recovered / read_detected+no_MAG / MAG_recovered+low_read / naming_mismatch。**source**: 98d GTDB 名(经 GTDB↔NCBI 双列保留,§二十:输出 taxonomy_name+taxonomy_system,映射行含 source/target/mapping evidence/unmapped 状态,不造"唯一真名") vs 11b/14b。P1(E)。

#### E-FUNC-01 functional evidence provenance
**gap**: 98b 丢弃 evalue/bitscore,择优隐式。**layer**: gene_annotation_matrix 加 `*_evalue/*_bitscore/*_method/*_source_table` 列族 + 补 Pfam(31c 输出)+ eggNOG description(已解析未用,98b:248);DIAMOND/HMMER/BLAST 择优规则显式写入注释。**validation**: 每条注释反查 hits 文件;row/key universe 不变。P1(E)。

#### E-GENE-01 gene→MAG→species→sample 追溯列
**gap**: 无 gene→bin 关联。**layer**: 98b 加 MAG 列(经 36/38 contig→bin 映射 + 17 GFF 坐标 join,嵌合 contig 归属标注 approx);vOTU/fungal 链已有 map(T-16/T-20)。**validation**: 抽查 20 gene 全链回溯。P1(E)。

#### E-XDOM-01 cross-domain edge schema
**gap**: 98g 边缺 evidence_type。**layer**: edges 表加 `edge_type(host|correlation)/evidence_type(CRISPR|tRNA|homology|model|abundance_correlation)/score/p/method/direction/provenance` 列(§二十八);host 与 correlation 永不合并为 `relationship`。**validation**: 每条边反查源表;与 98g 既有 type 列兼容迁移。P1(E)。

#### E-STAT-01 DA method consensus table
**gap**: 92 summary 只有 n_sig。**layer**: 新表 per feature×method:effect size/p/FDR/prevalence/mean/median/n/direction + `support_method_count`;99b 补 FDR 列。**不新增方法**(§二十五);p 不当 confidence(§二十六)。**validation**: 与 5 方法输出文件逐项对账。P1(E)。

#### E-DOC-01 quantitative unit schema
**gap**: 单位无文档(§二十四)。**layer**: docs/ 一页"定量语义表"(gene TPM/MAG coverage+vOTU TPM/relab/fungal count/prevalence 定义+禁止混比清单);96f/98 系列表头加 unit 行。P1(文档)。

### P2
- **ENG-01 antiSMASH chunking**(B 类):24 分块固化进 28;同参数同输入;1 样本 monolithic vs chunked 对账后才进 DAG。
- **E-REPORT-01**: 98 报告吸收 evidence 层(consumes P1 表)。
- **AUD-01 78 号审计**: 回答"解决哪个已观察到问题"(预期维持 P2)。
- **DOC-02**: PROJECT_MAP 历史快照标注更新(U-5 关联)。

### P3(定义不执行)
- **M-01 QuickBin challenger benchmark ticket**: production vs challenger,指标=unique HQ/MQ、completeness/contamination、GUNC、taxonomy、ANI overlap、biological relevance;未 benchmark 不进 production union。
- 版本/数据库候选(隔离区延续)。

## 7. Validation Strategy(§四十)

- **Completeness**: 每个重要结果可找到 evidence source(逐表溯源抽查)。
- **Exclusivity**: 不同 evidence type 分列(交叉检查无混列)。
- **Traceability**: confidence→evidence 反查(每规则配复算测试)。
- **Stability**: 底层数据不变(新增字段外的列逐字节一致)。
- **Generalization**: Tier A + Tier C 双跑(Phase 1 建立的隔离 workdir 模式)。

## 8. Regression Invariants(§四十一,每 ticket 后必查)

canonical key 集合不变;row universe 不意外变化;biological value 不变;新字段有源可溯;无 silent join loss;无 row multiplication;Phase 1 invariants(funnel 守恒/TPM 守恒/98d 不变)继续通过;`find|wc` 式 pipefail 陷阱不新增。

## 9. Execution Order

E-DOC-01(语义先行,零风险)→ E-MAG-01 → I-MAG-02 → E-VIR-01(先审计 68/70 语义)→ E-VIR-02 → E-VIR-03 → E-FUN-01 → I-FUN-02 → E-TAX-01 → E-TAX-02 → E-FUNC-01 → E-GENE-01 → E-XDOM-01 → E-STAT-01 → P2 批。每 ticket:审计→语义定义→实现→validation→regression→独立 commit。

## 10. Rollback

每 ticket 单 commit revert;解释层列全部为附加列,回滚后底层数据与 `phase1-correctness-stable` 逐字节一致(revert 后以 golden checksum 复验)。

## 11. Completion Criteria(§四十二)

系统可回答:MAG 质量如何/证据是什么/为何 HQ-MQ?宿主关系是哪类 evidence、几个来源、预测还是相关?真菌物种几方法支持、是否低支持?taxonomy 来自哪个体系、哪些方法一致?功能由哪个方法哪个库什么 score 支持?跨域 edge 是 host/correlation/prediction 哪种?——全部带反查路径。

## 12. 待用户确认事项

1. E-VIR-01 的 host level A–D 定义:**批准"先审计 68/70 输出语义再定级"**(不预设),还是直接采用指令中的推荐框架?
2. I-MAG-02 tier 标准:确认采用 MIMAG 默认(HQ≥90/≤5, MQ≥50/<10),或项目另有定义?
3. E-FUN-01 的 heuristic 阈值(reads<10 / relab<0.01%):确认作为 flag 口径(不删除)?
4. Ticket 粒度:14 张 P1(E-DOC-01 至 E-STAT-01)是否一次批准整批,还是逐张审批?
5. Phase 2 执行期 glm-router 已在 `.zcode/config.json` 注册:确认新会话优先 Flash 路由(机械批处理),科学判定仍主代理?
