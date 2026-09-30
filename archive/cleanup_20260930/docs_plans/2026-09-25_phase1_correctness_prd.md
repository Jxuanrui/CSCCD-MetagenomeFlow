# Phase 1 Correctness & Stability PRD

- **日期**: 2026-09-25 · **状态**: DRAFT — 待用户批准后进入 Step 0
- **上游文档**: [2026-09-25_system_optimization_plan.md](./2026-09-25_system_optimization_plan.md) + 用户 2026-09-25 十七项决定
- **最高约束**: 我们不是在让 pipeline 产生"看起来更好的结果",而是在让 pipeline 忠实地产生它本来应该产生的结果。不优化数字(MAG 数/vOTU 数/注释率/AUC/显著结果数),除非变化自然来自已被证明的 correctness fix。

---

## 1. 范围

**In scope(16 张 ticket)**:4 张程序性(T-00…T-03)+ 12 张 P0(T-10…T-21)。
**Out of scope(Phase 1 禁止/延后)**:
- 一切软件/数据库升级、环境重建、方法/冻结参数切换(用户 §十四清单,含 MetaPhlAn/GTDB/sylph 升级、Binette/UHGV/Phanta/MaAsLin3/FungiGut/GToTree/Bakta/BiG-SCAPE/新 binner 等);
- MAG-6 QuickBin 旁路 QC(**决定已记录: diagnostic challenger,不进 production union**;实现排 Phase 2);
- ML 分组切分接线(T-03 审计已完成,接线排 Phase 3,依 NEEDS CONFIRMATION 结果);
- P1 各项(哨兵语义统一/antiSMASH 分块/MAG 分层/病毒证据分层/真菌共识表等,排 Phase 2);
- 若某 P0 fix 在冻结环境内无法实现:**停止并报告,不自行升级**。

## 2. 决定记录(用户 17 点 → 执行规则)

| 决定 | 执行规则 |
|---|---|
| 先复现后修复 | 每张 ticket Step 2 必须先产出复现证据文件;NEEDS REPRODUCTION 类未复现即标 NOT REPRODUCED 不改码 |
| C 类一票一 commit | 见 §7 纪律;禁止混合科学结果修改 |
| QuickBin=A(严格旁路) | Phase 2 实现,身份=diagnostic challenger |
| VIR-4② 保持 `-p meta` | 本 PRD 仅含文档修正(ticket T-18 附带),meta_gv 入未来候选 |
| Tier A 强制 baseline/Tier C 批准/Tier B 暂缓 | T-01/T-02/T-00;Tier B 由验证需求驱动另行提案 |
| ML-1 先自动审计 | T-03 已执行,结果见 §5.4 |
| VIR-3 验收=join failed≈0 | T-17 验收采用四分类表,不以 Unclassified 率为目标 |
| vOTU 身份=canonical map | T-16 产出 votu_id_map.tsv,全下游禁用字符串切割推导身份 |
| H2 验收=funnel 可解释 | T-15 产出 Detected→QC_pass→Final 漏斗计数+删除原因 |
| H4 验收=可追溯 | T-19 采用 20-MAG 溯源抽查,不以"TPM 非零"为标准 |
| antiSMASH DONE/FAILED | T-11 |
| 真菌 flag=heuristic 置信标注 | Phase 2 FUN-3 实现口径(不删除数据) |
| ML 验收=AUC 方向不作正确性标准 | Phase 3 验收改用 fold 无重叠+seed+split manifest |
| PRD 粒度 16 字段 | §4 模板,每 ticket 标 CONFIRMED / NEEDS REPRODUCTION |
| Step 0–6 顺序 | §3 |

## 3. 执行顺序(硬性,不得跳步)

```
Step 0  Freeze          冻结 code commit/env/db/config/benchmark 输入 → baseline manifest   [T-00]
Step 1  Golden baseline 冻结 Tier A 既有 outputs+logs+checksums(可再生成性盘点)            [T-01]
Step 2  Reproduction    逐 ticket 复现,产出证据文件;NEEDS REPRODUCTION 未复现→NOT REPRODUCED [T-19 先行]
Step 3  Correctness     只修已确认问题;一 issue 一 commit;每 commit 过 targeted+integration 测试
Step 4  Regression      Tier A 全量回归(A 类:原值逐字节不变;C 类:定向验证+漏斗解释)
Step 5  Tier C validate Project01 2–3 只读代表样本,输出仅写隔离 workdir,原始数据零改动
Step 6  Report          Fixed / Not reproduced / Deferred / Unexpected findings 四类报告
```

**门禁**:Step 3 的每个 commit 前,该 ticket 证据文件齐备;Step 3→4 需全部 ticket 关闭(修复/不修复/延后三态);任何无法解释的连带变化 → 停止该项,不向后推进。

---

## 4. Ticket 模板(16 字段)

`ID · Severity · Current behavior · Evidence(file:line+runtime) · Reproduction procedure · Root cause · Proposed change · Files affected · Expected output changes · Outputs that must remain unchanged · Unit/targeted test · Integration test · Benchmark requirement · Rollback method · Acceptance criteria · Commit boundary` + 状态标记。

证据文件统一落 `docs/plans/phase1_evidence/TXX_*.md`(含修改前输入/输出、错误表现、root cause、修改后输出、字段级变化说明、为何变化、不应变化项、连带变化检查)。

---

## 5. 程序性 Ticket

### 5.1 T-00 Freeze & Baseline Manifest(P0/Critical,程序性)
- **内容**: 记录当前 git commit hash;`docs/manifests/`(57 env + databases.yaml) checksum;db/ 目录身份清单(复用 databases.yaml);pipeline/config 快照;Tier A/C benchmark 输入清单。
- **产出**: `scripts/tests/benchmark/phase1_baseline_manifest.yaml`。
- **验收**: manifest 可独立回答"Phase 1 全程在哪个冻结态上执行"。
- **Commit boundary**: 单独 commit(仅新增 manifest;若 scripts/tests/benchmark/ 目录新建,同 commit)。

### 5.2 T-01 Golden Baseline — Tier A(强制)
- **输入**: Project_example(6 样本)+ Test_CI_fixture。
- **做法**: ①对既有 result/ 全量 checksum 冻结(sha256 清单入库 benchmark 目录);②可再生成性盘点:标注每个受影响输出(98b/98c/98d、votu 表、真菌合并 FAA)是否有完整输入可重跑;③对 98 系整合步骤做一次"当前态复跑",确认与冻结值一致(排除陈旧输出干扰对比)。
- **不做**: 全管线重跑(耗时且非必要;受影响步骤的重跑在各 ticket 的 reproduction 中完成)。
- **验收**: checksum 清单 + 再生成性表 + 98 系复跑一致性结论。
- **Commit boundary**: 单独 commit(checksum 清单较大时放 scripts/tests/benchmark/ 下独立文件)。

### 5.3 T-02 Tier C 选样与 Benchmark Manifest
- **选样程序(全部只读既有结果)**: 候选=metadata 覆盖的 10 样本(Sample1/2/3/4/10–15);①普通代表=MAG 数/组装量中位数样本;②高复杂度=组装 contig 总长最高样本;③病毒/真菌丰富=per-sample CheckV 通过 contig 数最高样本(真菌信号以 metaphlan4 真菌检出深度为代理)。
- **已知约束**: Project01 结果目录存在 13 个样本文件而 metadata 只登记 10(见 §8 意外发现 U-1);选样仅限 metadata 覆盖样本。
- **产出**: 选样依据写入 `phase1_baseline_manifest.yaml`(benchmark manifest 部分);Tier C 验证输出**只写** `Project/Phase1_Validation/`(新隔离 workdir),Project01 原始数据零写入。
- **验收**: manifest 含每样本选择指标数值与理由。

### 5.4 T-03 ML Metadata 患者标识审计(已执行,2026-09-25,只读)
- **结果**:
  - **Project01/metadata.csv**: 存在 `subject_id`(S01–S10);10 样本/10 唯一值/**1:1 无重复采样**;age/BMI 全 NA。→ **情况 B 偏 A**:字段命名明确、当前无重复结构;**NEEDS CONFIRMATION**:未来队列是否含纵向/重复采样。
  - **Test_CI_fixture**: `subject_id`(C01–C04)同样 1:1。
  - **Project_example/metadata.csv**: 无任何 patient 类字段 → 该项目 ML 运行属情况 C(warning 模式)。
  - 代码侧: 96 号当前完全不读 subject_id(96:341 预过滤/96:362 create.data.split 均无分组参数)。
- **后续(Phase 3,非本阶段)**: metadata 含 subject_id 时接线 `inseparable=subject_id`(当前 1:1 下行为中性,面向未来队列防护);情况 C 强制 warning + provenance 记录;语义确认问题列入 Phase 1 报告向用户提出。
- **验收**: 本 ticket 产出即审计记录本身(入 phase1_evidence/);无代码改动。

---

## 6. Correctness Ticket(T-10…T-21)

> 类别: A=安全(不改变科学结果定义) B=参数/输入 C=方法/正确性(改变科学结果数字)。
> 顺序: T-19(复现)→ T-10/T-11/T-12/T-13/T-14(A 类先行)→ T-16→T-17(映射先于 join)→ T-15→T-18 → T-20→T-21。

### T-10 Snakemake config 失效路径 — **CONFIRMED** [A]
1. **Severity**: Critical(模式三不可用)
2. **Current**: config.yaml 指向已改名旧仓 `~/Course/CSCCD-MetagenomeFlow`(共 8 处引用)
3. **Evidence**: `pipeline/config/config.yaml:1-4`(代码证据;运行时证据=Step 2 dry-run 失败记录)
4. **Reproduction**: `snakemake -s pipeline/Snakefile --profile pipeline/profiles/local_48c --dry-run` → 记录报错
5. **Root cause**: 仓库更名 Maxmetagenome 后 config 未同步
6. **Change**: 修正为当前路径(顺带核对 profiles/ 内是否有同类硬编码)
7. **Files**: `pipeline/config/config.yaml`(+profiles 若有)
8. **Expected changes**: 模式三 dry-run/实跑恢复可用;无任何分析输出变化
9. **Unchanged**: 全部 result 输出
10. **Unit test**: 无(配置)
11. **Integration test**: `run_ci_checks.sh --level 3`(DAG dry-run)PASS
12. **Benchmark**: 无
13. **Rollback**: git revert 单 commit
14. **Acceptance**: level 3 PASS;Tier A 任一 rule dry-run 解析正常
15. **Commit boundary**: 单 commit,仅 config 路径

### T-11 antiSMASH DONE/FAILED 语义 — **CONFIRMED** [A]
2. **Current**: 失败分支 `touch SENTINEL; exit 0`(28:82-86),"执行失败"被伪装成"完成且无 BGC"
3. **Evidence**: 代码 28:82-86;运行时=Step 2 失败注入演示
4. **Reproduction**: /tmp 副本上构造坏输入强制 antiSMASH 失败 → 观察哨兵被 touch 且 exit 0
5. **Root cause**: 错误分支与"成功但空结果"共用同一哨兵语义
6. **Change**: 失败→写 `FAILED` 哨兵(内容:时间戳/exit code/log 尾部)+exit 非 0;成功空结果→DONE(空语义文档化);28b 消费前检查哨兵状态
7. **Files**: `scripts/28_bac_antismash.sh`、`scripts/28b_bac_bgc_novelty.sh`(守卫);技能卡 28 known_issues 同步
8. **Expected**: 仅失败路径行为变化(阻塞而非静默)
9. **Unchanged**: 成功路径输出逐字节不变
10. **Unit test**: 失败注入 → FAILED 哨兵+非零退出;空成功 → DONE
11. **Integration**: Tier A 28 号重跑输出与 baseline 一致
12. **Benchmark**: 无(失败路径)
13. **Rollback**: revert
14. **Acceptance**: "没有检测到 BGC"仅在"程序成功完成+结果为空"时出现
15. **Commit boundary**: 单 commit

### T-12 DB 校验器 MetaPhlAn 条目失配 — **CONFIRMED** [A]
2. **Current**: 00_check_database.sh:163 期望 `mpa_vJan21_CHOCOPhlAnSGB_202103.pkl`;实际 `db/metaphlan4/` 为 `mpa_vOct22_CHOCOPhlAnSGB_202212*`(2026-09-25 实查)→ 校验恒误报,事实上被弃用
4. **Reproduction**: `bash scripts/00_check_database.sh -b` → MetaPhlAn 行报 MISSING(记录输出)
5. **Root cause**: DB 轮换后校验器条目未同步
6. **Change**: 期望标记改为 mpa_vOct22_CHOCOPhlAnSGB_202212(bt2l 标记文件);同屏快查其余条目,**只修正可证实失配的字符串**(逐条给证据)
7. **Files**: `scripts/00_check_database.sh`
8/9. **Expected/Unchanged**: 校验报告 [OK];不触碰 db 本体
10. **Unit**: 逐条目运行输出比对
11. **Integration**: CI level 1(shellcheck)
12. **Benchmark**: 无
13. **Rollback**: revert
14. **Acceptance**: `-b/-v/-f` 三模式下 MetaPhlAn 相关条目 [OK];无误报
15. **Commit boundary**: 单 commit(仅字符串修正,不重构校验器)

### T-13 32 号退出码错位 — **CONFIRMED** [A]
2. **Current**: `set +e` 后 `GENERATED_BAM=$(ls …)` 再 `EXIT_CODE=$?`——捕获 ls/mv 而非 coverm make(32:69-78)
4. **Reproduction**: /tmp 构造缺失参考/坏 BAM 强制 coverm 失败 → 脚本仍 exit 0
6. **Change**: 退出码紧贴 mgx_conda 调用采集(照抄 01:101-105 模式)
7. **Files**: `scripts/32_bac_coverm_depth.sh`
8/9. **Expected**: 失败正确传播;成功路径输出不变
10. **Unit**: 失败注入;11. **Integration**: CI level 2(若覆盖 32)/Tier A 重跑一致;12. **Benchmark**: 无
14. **Acceptance**: coverm 失败→脚本非零退出且不产出假 BAM
15. **Commit boundary**: 单 commit

### T-14 元数据校验接线 — **CONFIRMED** [A]
2. **Current**: 00_validate_metadata.sh(6 类检查)零调用点;00_pipeline_*.sh 入口仅 `tr -d ' "'`(00_pipeline_bacteria.sh:152-156)
4. **Reproduction**: 构造含重名/缺列/不成对 samplesheet 于 /tmp → 三条管线均照常起跑
6. **Change**: 三条 00_pipeline_*.sh 在参数检查后调用校验(复用现成脚本,失败即中止);Snakemake 侧加 `validate_inputs` rule(产哨兵,被 rule all 依赖),逻辑同源
7. **Files**: `scripts/00_pipeline_{bacteria,virome,fungi}.sh`(full 视复现结果)、`pipeline/Snakefile` 或 preprocessing.smk(+1 rule)
8/9. **Expected**: 坏输入在入口被拒;合法输入下游零变化
10. **Unit**: 坏表注入三种形态(重名/缺 R2/非法字符)全部中止
11. **Integration**: CI level 3 + Tier A 起跑不变
12. **Benchmark**: 无(仅门禁)
14. **Acceptance**: 任何维度管线入口不再接受未过检 samplesheet
15. **Commit boundary**: bash 接线与 smk rule 可各一 commit(均为 A 类)

### T-16 vOTU canonical 身份映射 — **CONFIRMED** [C]
2. **Current**: 98c:274-275 等用 `re.sub("_[0-9]+$")` 由基因 ID 推导 contig/vOTU 身份;MEGAHIT contig ID 自身以数字结尾 → `k127_1717`→`k127`
3. **Evidence(运行时,2026-09-25 实查)**: `Project_example/result/integration/virus/votu_annotation_matrix.tsv` 首数据行即 `k127`,聚合 S02=62360/S04=49269 TPM,注释列全 `-`;98g 经同一表继承错误
4. **Reproduction**: Step 2 用既有输出统计截断行数与错位聚合质量(与 baseline 对账,产出证据文件)
5. **Root cause**: 用字符串切割而非映射表决定 biological entity identity
6. **Change**: 56 号落盘 `votu_id_map.tsv`(列: original_contig_id / cluster_id / representative_votu_id / sample_id / source_step,源自 vclust clusters.tsv+样本前缀还原);98c/98g/60 一律经 map join;删除正则推导;91 号已正确,保持
7. **Files**: `scripts/56_vir_votu_gen.sh`、`scripts/60_vir_votu_table.sh`、`scripts/98c_vir_integration_tables.sh`、`scripts/98g_cross_domain_corr.py`
8. **Expected**: 整合/相关表键全部为 canonical vOTU(或基因→vOTU 经 map);`k127` 型截断行消失;原被错误聚合的 TPM 归位到正确 vOTU
9. **Unchanged**: 每样本 TPM 总量守恒(会计恒等式,old vs new 按样本求和相等);未受截断影响的原有行值不变
10. **Unit test**: 截断行计数归零;样本 TPM 总量 old==new;map 表覆盖率=contig 全集
11. **Integration**: Tier A 病毒整合全链重跑+diff
12. **Benchmark**: C 类必做——old vs new 表 diff+字段级解释
13. **Rollback**: revert+重跑受影响步骤恢复旧输出
14. **Acceptance(§八)**: 全下游(taxonomy/abundance/function/host/network)以 votu_id_map 为唯一身份源;`grep -rn '_\[0-9\]+\$' scripts/` 病毒身份相关命中=0;以后不得通过字符串切割重新推导 identity
15. **Commit boundary**: 单 commit(56 产 map 与三个消费方同 commit,防中间态)

### T-17 前缀对称与 taxonomy join 修复 — **CONFIRMED** [C,依赖 T-16]
2. **Current**: 56 给 contig 加 `SAMPLE__` 前缀而 55 CDS/54 checkv 无前缀;60:113-116 join 取 taxonomy 文件第 2 列(实为 n_genes 数值列)
3. **Evidence(运行时)**: `vOTU_table_ann.txt` 532 行中 477 行 Unclassified(≈90%);91 ORF→cluster 映射全 NA
4. **Reproduction**: Step 2 对既有输出做四分类统计(annotated / source-unclassified / source-missing / **join-failed**),量化 join-failed 基线占比
5. **Root cause**: 命名空间不对称+join 列索引错误
6. **Change**: 经 T-16 的 map 完成前缀归一(map 同时含带前缀与原始 contig ID);60 的 taxonomy join 改读正确 lineage 列;91 的 ORF→cluster 改走 map
7. **Files**: `scripts/60_vir_votu_table.sh`、`scripts/91_stat_diversity.sh`(病毒分支映射)、必要时 `58` 合并处一行归一
8. **Expected**: 源数据中确有注释的条目恢复注释;join-failed→≈0
9. **Unchanged**: 源头本就 Unclassified 的保持 Unclassified(**不以降低 Unclassified 率为目标**);丰度数值不变(仅注释列恢复)
10. **Unit**: 四分类表;join-failed 计数=0(或逐条解释为 source-missing)
11. **Integration**: Tier A 重跑+四分类报告
12. **Benchmark**: C 类 old vs new 注释列 diff(仅注释列变化)
13. **Rollback**: revert
14. **Acceptance(§七)**: 每个 vOTU 可回答"真无分类"vs"没 join 上";**join failed ≈ 0**;人工抽查 20 个 vOTU 溯源到 57 号原始输出
15. **Commit boundary**: 单 commit

### T-15 接线 54b MIUVIG 过滤 — **CONFIRMED** [C,建议在 T-16/17 后]
2. **Current**: 54b 输出 viruses_filtered.fna 无任何消费方(virome.smk:76-89 后无引用;00_pipeline_virome.sh:146-149 直跳 55);56:62-69 fallback 到未过滤 virus_contigs.fasta → QC 整体绕过;54 空结果假 summary 列名与真实 checkv schema 不符(54:74)
4. **Reproduction**: Step 2 于 Project01(病毒信号丰富,clusters.tsv 17,558 行)统计 filtered vs unfiltered contig 数差 = 被 QC 拦截规模;确认 56 实际消费的输入文件(Tier A 日志/文件时间戳)
5. **Root cause**: 规则存在但从未进入 DAG/管线序
6. **Change**: virome.smk 中 56 的 input 改为 viruses_filtered.fna;删除 56 的 fallback 分支;00_pipeline_virome.sh 在 54 与 55 之间插入 54b;54 空表头改为真实 checkv 列名
7. **Files**: `pipeline/rules/virome.smk`、`scripts/56_vir_votu_gen.sh`、`scripts/00_pipeline_virome.sh`、`scripts/54_vir_checkv_contig.sh`
8. **Expected**: 最终 vOTU 集缩小(<2kb 与低质量 contig 剔除);下游丰度/注释表相应变化;**funnel 报告**: Detected→QC_pass→Final 每步 输入数/保留数/删除数/删除原因
9. **Unchanged**: 存活条目的定量语义;细菌/真菌/统计其余维度
10. **Unit**: funnel 计数自洽(输入=上步保留);空输入全链哨兵级联正常
11. **Integration**: Tier A 病毒链端到端重跑
12. **Benchmark**: C 类 old vs new——vOTU 数变化必须可由 funnel 完整解释(差值=被过滤数),不得有未解释差值
13. **Rollback**: revert+重跑
14. **Acceptance(§九)**: Detected/QC_pass/Final 三集合建立;"QC rule 存在但下游用全集"不再可能;vOTU clustering 阈值语义(95% ANI/0.85 qcov)不变
15. **Commit boundary**: 单 commit

### T-18 vMAG 定量 reads 路径 + 55 号文档对齐 — **CONFIRMED**(路径)/文档 [B/A]
2. **Current**: 63:42-43 reads 路径 `temp/qc/...` 与 02 实际输出 `result/kneaddata/...` 不符;55 实际 `-p meta` 与标题"Prodigal-gv"不符(**决定:保持 -p meta,只修文档**)
4. **Reproduction**: 63 号独立 dry 运行显示输入不存在;virome.smk 63 rule 的 input 实参核对(Snakefile 可能传参覆盖脚本默认——复现时确认)
6. **Change**: 修正 63 默认路径;55 脚本头/标题/技能卡改为 Prodigal meta 模式真实描述
7. **Files**: `scripts/63_vir_coverm_quant.sh`、`scripts/55_vir_prodigal_gv.sh`(仅注释/标题)、技能卡 55/63
8. **Expected**: vMAG 丰度可计算(Project_example 无 vMAG 属预期;Tier C 病毒丰富样本验证);**蛋白预测结果零变化**(-p meta 不动)
9. **Unchanged**: 55 输出、全部既有病毒表
12. **Benchmark**: Tier C 病毒样本上 63 号可用性验证(若 vMAG>0)
14. **Acceptance**: 63 可独立运行;文档与实际方法一致;meta_gv 留在未来候选清单
15. **Commit boundary**: 路径修复与文档对齐各一 commit

### T-19 98d CoverM join 复现 — **NEEDS REPRODUCTION**(初步证据指向 NOT REPRODUCED)
2. **Current(audit 静态怀疑)**: 98d:213 `row["Genome"]` 未 strip `.fa` vs 98d:232 mags 列表已 strip → 疑似 join 全 miss/TPM 全零
3. **初步证据(2026-09-25 只读实查,非正式复现)**: Project01 CoverM Genome 键=`Sample1__139_sub`(无 .fa);98d MAG_id=`Sample10__maxbin2_bin.021`(同格式);98d 表 213 行 TPM 全部非零(示例 2349.171/18650.336…)→ **疑似不成立**
4. **Reproduction(正式,Step 2)**: 13 个 coverm_quant TSV 逐一:提取 Genome 键集 ↔ 98d MAG_id 集双向比对;统计 unmatched(两向);随机 20 MAG 从 CoverM 原始值逐列追到 98d 表值
5. **判定**: unmatched=0 且 20/20 值一致 → **NOT REPRODUCED**,不改码,记录关闭;发现失配 → 按 §十修复(验收=20-MAG 全链可追溯,**不以"TPM 非零"为标准**——真 0 也可能是合法数据)
6-15. 仅在复现成立后填写;rollback=revert
16. **Commit boundary**: 复现证据单独归档;如需修复,独立 commit

### T-20 真菌注释样本前缀 — **CONFIRMED** [C]
2. **Current**: 81:57-60(及 82-86 同模式)直接 cat 合并各样本 .faa,无样本前缀 → 跨样本基因 ID 冲突
4. **Reproduction**: 统计 Project_example 合并 FAA 中重复 gene ID 数(预期>0,记录具体冲突对);98d 真菌表按 ID join 的错配演示
5. **Root cause**: 合并处未沿用 18:139 的 `SAMPLE|` 前缀惯例
6. **Change**: 合并处加前缀(照抄 18 号模式);82-86 与 98d_fun 的键期望同步
7. **Files**: `scripts/81_fun_eggnog.sh`、82/83/84/85/86 同点、`scripts/98d_fun_integration_tables.sh`
8. **Expected**: 真菌基因 ID 全局唯一;表键重命名
9. **Unchanged**: 注释命中值本身、丰度/计数数值
10. **Unit**: 合并 FAA ID 唯一性断言(重复=0)
11. **Integration**: Tier A 真菌功能链重跑+diff(值同键变)
12. **Benchmark**: C 类(键空间变化),diff 须显示"仅键变值不变"
14. **Acceptance**: 跨样本同 ID 冲突=0;下游统计可按样本+基因唯一寻址
15. **Commit boundary**: 单 commit(全部真菌注释脚本+98d 同步,防中间态)

### T-21 FeGenie NR 路径失配 — **CONFIRMED**(修复方案含一个小决策点)[B]
2. **Current**: 31e 产出 per-sample(`result/annotation/fegenie/S02/…`,2026-09-25 实查存在;基因 ID 无样本前缀);98b 只读 `fegenie/NR/`(实查**不存在**)→ Iron 列恒空
4. **Reproduction**: NR/ 目录缺失证据 + Project_example 98b gene_annotation_matrix Iron 列空值统计
5. **Root cause**: 31e 从未生成 NR 层结果;98b 假设其存在
6. **Change(推荐方案,请批)**: 最小接线——①18 号顺带导出 clstr→NR 基因映射(awk 解析既有 .clstr,零新计算);②98b 读 per-sample FeGenie 输出,经 `sample + 基因ID → SAMPLE|基因ID →(clstr map)→ NR 代表` join 进 Iron 列。备选:仅把 Iron 列标为 `per-sample only, NR join pending`(纯标注)。两案均不动 FeGenie 版本/参数
7. **Files**: `scripts/18_bac_cdhit.sh`(导映射)、`scripts/98b_bac_integration_tables.sh`
8. **Expected**: Iron 列由空变为 per-sample 汇总(推荐案)或明确标注(备选案)
9. **Unchanged**: 其他全部列
10. **Unit**: 映射表覆盖率=NR 成员全集;join 命中率报告
11. **Integration**: Tier A 98b 重跑,除 Iron 列外逐字节一致
12. **Benchmark**: B 类——仅 Iron 列 diff
14. **Acceptance**: Iron 列每个非空值可回溯到 per-sample FeGenie 原始行
15. **Commit boundary**: 映射导出与 98b join 各一 commit(顺序依赖)

---

## 7. C 类修改纪律(每 ticket 强制)

1. 顺序固定: baseline → reproduce → fix → targeted test → integration test → output diff → manual spot check → commit;**一次只修一个逻辑问题,禁止混合**。
2. 证据文件必须含: 修改前输入/输出、错误表现、root cause、代码、修改后输出、字段级变化(哪些变/为何变/哪些不应变/连带变化检查)。
3. **无法解释的连带变化 → 停止该项,不向后推进**,升级至用户。
4. 所有 commit 过 `run_ci_checks.sh --level 1`(涉 smk 加 level 3);改 registry/技能卡的过 check_consistency。
5. 回滚一律 git revert 单 commit+受影响步骤重跑,不手改输出。
6. 执行模型: 子代理按 §8 模板派发(一 ticket 一派发),主代理 §4.4 审核门;glm-router 若仍不可用则主代理降级执行并在每 ticket 证据文件注明执行模型。

## 8. Phase 1 报告模板与已登记的意外发现

**报告四类**: Fixed(含漏斗/四分类/溯源证据)/ Not reproduced(含复现数据)/ Deferred(原因+去向)/ Unexpected findings。

已登记(截至 PRD):
- **U-1**: Project01 结果目录含 13 个样本文件(coverm_quant 有 Sample18 等),metadata.csv 仅登记 10 样本;Tier C 选样限 metadata 覆盖样本;差异原因待查(历史批次?遗留?)。
- **U-2**: MAG-1 初步证据指向 NOT REPRODUCED(98d TPM 非零且键格式一致)——正式判定以 Step 2 为准。
- **U-3**: T-03 审计发现 Project01 的 subject_id 当前 1:1 无重复;未来队列纵向语义 NEEDS CONFIRMATION(向用户提出)。

## 9. 待用户确认事项(PRD 批准时一并答复)

1. **T-21 修复方案**: 推荐案(clstr 映射+98b join,2 个小 commit)还是备选案(仅标注 per-sample only)?
2. **T-18 文档对齐范围**: 55 号标题含"Prodigal-gv"字样,建议同步改技能卡与 PROJECT_MAP 对应行,是否授权(纯文档)?
3. **U-1**: 13 vs 10 样本差异是否需要在本阶段追查,还是仅记录?
4. Phase 1 执行期间若 glm-router 仍不可用,确认按"主代理降级执行"处理(标准不降)。
