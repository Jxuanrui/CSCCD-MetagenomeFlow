# Project_demo — 模式一全链演示走查项目

- 创建：2026-10-03 ｜ 锚点 tag：new-project-demo-v1.2.1 ｜ Tech Spec：docs/plans/2026-10-03_demo_walkthrough_techspec.md
- 数据：自 Project01 只读拷出 6 样本（treat=Sample1/2/10；control=Sample3/4/11），实体复制非软链。
- **全短样本策略（§10.2，质量审核 P0-1）**：空产出继续 + 如实记录（keep-going 语义）——
  任何步骤产出为空/跳过时，walkthrough 显式成章记录原因，不静默省略、不视为失败。
- 监控：全程 MGX_MONITOR=1；快照采集 `python3 scripts/utils/run_monitor.py Project/Project_demo --text`。
- 产出：walkthrough.md（教程式，章节↔脚本编号一一对应）。

## 执行红线与口径（质量审核 2026-10-03 并行计划条件）
- **74a 禁止 `--force`**：索引齐全时会跳过；加 --force 会把 fungi_target/
  human_chm13v2 两个 .bt2 索引重建并写入 db/，违反 §10.5-2 数据库冻结
  （74a_fun_gut_db_build.sh:55,85 的判断结构所致，质量审核 C2）。
- **计时口径**：三线并行期间 A 线记录的时长含 B/C 线负载，供预期管理时
  需注明并行背景（质量审核），收尾段出"净时长"修正说明。
- **commit 纪律**：按线分开、逐文件清单提交；A 线每审核批次记录当时 HEAD
  （质量审核 C5）。

## 三界段执行计划（质量审核 2026-10-08 修订，P0-5）

### 步骤计数修正
- 病毒链：24 步（非 23）
- 真菌链：26 步可跑（非 16；76 已移除）
- 细菌组装/分箱链：16-43c 约 50 步（此前完全遗漏）

### 组装器互斥纪律（P0-6）
全局同一时刻只允许一个组装器运行（megahit/metaSPAdes）。三界泳道可并行，
但组装步骤必须排队。

### 真菌功能注释科学口径披露
78 号组装用全部清洁 reads（非仅真菌 reads）；80 号用 Prodigal（原核基因预测）。
81-86 号实际是以细菌为主的全群落注释，放在 fungi/ 目录下。文档此前未说明。

## 防重复启动规程（质量审核 P0-3，2026-10-09）
1. 每次启动泳道前：`pgrep -af "<脚本名>"` 确认无同步骤残留进程
2. 启动后 60 秒：`grep "<step>.*<sample>.*-1" logs/run_events.jsonl | wc -l` 确认只有 1 条启动记录
3. 如发现重复：立即 kill 较新的进程（保留先启动的），清除后重启
4. 教训来源：megahit Sample1 SIGSEGV（incident_20261007_megahit_dup_launch.md）

## 失败事件构成更正（质量审核 C1，2026-10-10；2026-10-13 增补）
✗ 的实际构成：megahit 重复启动 ×2（exit 245）+ virsorter2 conda 失败 ×6（exit 1）+ 55 假成功 ×6（2026-10-13 增补：54 交集 `--force` 重跑后下游 55 未带 `--force`，走跳过分支记 ✓，实为旧产物；教训见事故 #13）。
**计数口径警示（事故 #14）**：被 SIGKILL 的进程 EXIT trap 仍记 exit=0（如 74/Sample11 被清杀记为 ✓ 且 params 字段被污染）——✓ 计数含少量假成功，以文件新鲜度为准。

## 执行红线增补（质量审核 2026-10-13；四审 2026-10-14 修订）
- **上游 `--force` 重跑后，下游一律 `--force`**（下游哨兵不因上游失效，事故 #13 根因）。
- **文档同步红线（用户 2026-10-16 提醒，立为规程）**：每条泳道收官/关口事件，当回合内同步更新 NOTES 进度索引与 step_checklist（事件流核证法），质量审核报告当回合归档 .claude/reviews/；不得隔日补账。
- ~~高内存步骤不同波次同时运行~~ → **放宽（用户 2026-10-14 批准）**：仅 gtdbtk 与 iphop 须错峰；其余按核预算排（755GB 内存实测仅用 20GB，瓶颈在核不在内存）。

## 后续执行计划（质量审核 2026-10-13 设计，W1-W6；用户approve项见表）
| 波次 | 泳道 A(16t) | 泳道 B(16t) | 泳道 C(16t) | 关口 |
|---|---|---|---|---|
| W1 当前 | 38→38b（作原始基线） | B3轻:24→24b→26→27→29 | B3重:31→31b→31c→31d | CP1+CP2-病毒（只读，已呈质量审核） |
| W2 | 36b ×6 严格串行（互斥） | 病毒下游 64→65→66→67→67b→72→70→69→68（iphop 最后） | 真菌 80/80b×6→75→75b→77→81→86 | — |
| W3 | 清空 drep_input/temp→37 --force→38 --force→38b --force | 28 antismash（分块）→28b | 31e×6→42→42b×6 | CP2-MAG（含 36b 回退核对） |
| W4 | 40 gtdbtk→41 prokka→41b→41c/41d | 39→39b→39c×6→39d | 43 gapseq→43b→43c | — |
| W5 | 98b/98c/98d、98c_mge、98d_mag | 98e→98f→98g | — | CP3 全量对齐 |
| W6 | 91→92→93→94→96 系→99a/99b→98 | | | 统计附 3v3 功效披露 |
串行：36b→37→38→38b→MAG 尾链；39b→c→d；43→43c；80→81-86；75→75b。并行：目录级注释互斥安全；**病毒下游依赖修正（质量审核四审）：65/66 真实依赖 64（pharokka.gbk/phanotate.faa），67/67b/68/69/70/72 仅依赖 virus.fasta**；28/31e/42/42b 与 MAG 链无依赖（读 16/17 号产物）。

## 质量审核通道架构（2026-10-16 起，用户提供中转站）
- **当前默认：sicoding.ai 中转 + gpt-6-astra**（用户提供；实测可用但慢——首包 1-2 分钟；Cloudflare 按 TLS 指纹拦 urllib（403/1010），传输层已改 curl 子进程）。
- 调用：`SUPERVISOR_TODAY=YYYY-MM-DD python3 scripts/utils/supervisor_api.py "<审核请求>"`；带只读工具循环（read_file/grep/glob，限仓库根），质量审核自行核证文件证据；冒烟测试通过（自主读文件+五段式报告+文件:行号证据）。
- **多站切换**：`.claude/supervisor_relays.local.json`（gitignored，含密钥）登记站点；`--station 名` / `SUPERVISOR_STATION` / `default_station` 三选一切换；新增站点=加一条 JSON。
- 既有通道保留：ZCode 子代理加载章程（中转故障后备）；claude CLI（环境恢复则用）。通道裁决力等价，均按 supervisor.md 章程出五段式报告。

## 质量审核终审（2026-10-15，用户三问：完成度/复发根因/防复发保证）→ **用户批准后 P0 防线已落地（f7f6edb）**
- **已上**：① mgx_parse 预初始化全部带值选项（41 号 unbound 家族源头消灭）；② mgx_conda 调用点级 PYTHONNOUSERSITE=1（53→70 宿主污染家族终结）；③ 接口一致性 lint 挂 pre-commit 门 4（43 号"-t 声明未注册"类；回归测试验证可抓，全库扫描现零违例，已发现 38 号 -A/-a 注册未文档化漂移）；④ --force 备份钩子挂 5 个唯一副本高危步骤（19/37/38/38b/54）；⑤ validate_step 补 4 组高价值不变式（60 TPM 守恒/join 闭合、38/40 计数闭合、74f 簇闭合）——全部对现产出 PASS。
- **缓上（按质量审核排期）**：flock 单实例锁（演示收尾后）；泳道脚本模板化迁入版本库（W2-W4 收尾后统一）。
- pre-commit 对本次提交自身抓出 1 个 SC2155（修复后过）——门禁有效性活证。
- **主代理过程失误披露（2026-10-15 晨）**：① pgrep/pkill 自匹配第三次杀自身命令（kill 循环含目标字符串）——已确立括号防匹配法为规程；② gapseq"挂起 80 分钟"系误诊（进程检查只 grep 工具名，漏看 tblastn/parallel 阶段进程）——教训：判挂起前必须按进程树（PPID 链）全量枚举而非按工具名过滤。运行中的 W4-C 未受影响。
- **完成度**：属实通过（CP1/分箱/dRep/GTDB-Tk/vOTU 六样本 ΣTPM=10⁶ 全核真；核酸目录 995,242 vs 蛋白 995,199 双口径须在 walkthrough 注明）。
- **复发根因（结构性）**：① 模式一=145 脚本首次全量实跑（CI 只测过环境组装，从未测接口与数据语义）——测试期与生产期被合并；② 环境策略挂在会话层（activate.sh）而非调用点（mgx_conda），会话漂移必绕过（53→70 同根因 6 天二爆为实证）；③ 编排层（38 个 /tmp 泳道脚本）无版本无锁无模板，是 E 类事故温床；④ 修复以点修为主（公共层修复仅 1/15），而唯一一次制度修（8f90d4b realpath）恰好是唯一零复发的类。
- **防复发保证（诚实结论）**：当前**不能保证**。shellcheck 对 A 类原理性失明（实测 bug 版 41 号零告警）；validate_step 仅覆盖 13/76 步；flock 建议（10-07 事故档案提出）从未落地。要"不再犯"须补 4 条公共层防线（约 20 行）：mgx_parse 预初始化 string 选项 / mgx_conda 内置 PYTHONNOUSERSITE / 接口一致性 lint / flock 锁 + --force 备份钩子。补齐前诚实预期：剩余 60+ 未首跑步骤仍会以每周 1-2 个炸点频率复发。
- 报告全文：.claude/reviews/supervisor_20261015_final_review.md（含点修 vs 制度修矩阵、P0-P2 清单、4 项待approve）。

## W4-C GEM 链尺寸approve（用户批准"按建议执行"，2026-10-15）
- **取 CheckM2 质量前 10 的代表 MAG 跑全链**（43 gapseq → 43b carveme → 43c cobrapy FBA），非全量 128——128 全跑约 2-4 天（carveme 30-60 分钟/MAG），超出演示需要。
- **披露**：名单按 comp−cont 排序取前 10（全部 comp≥99.7、cont≤0.22，见 /tmp/gem_top10.txt 与 walkthrough 待补章节）；其余 118 个代表的 GEM 建模不在演示范围。
- 泳道：/tmp/lane_w4c_gem.sh（-t 8，插空负载）。

## CP2-MAG 关口（质量审核 2026-10-15：有条件通过 → C1 整改执行中）
- 数字全核真：353→269→128 闭合；重组装真实生效（352/353 字节级改写，唯一回退 H10 semibin2_271）；128 代表 = HQ 96 + MQ 32（全部 MIMAG medium）。
- **C1（P0）**：W1 基线被 --force 覆盖丢失——影子工作目录重建执行中（/tmp/lane_w1_baseline.sh，产出 → checkm2_w1_baseline/drep_w1_baseline/gunc_w1_baseline/），现行路径零接触。
- P1/P2 已修（002e3ae）：38b --force 清空旧产物；36b 哨兵记 FALLBACK_BINS。
- **GUNC 披露（approve #2 采纳）**：128 代表中 pass 81 / fail 47（嵌合信号）；演示定位全量保留不做二次过滤，消费 GUNC 一律以汇总 TSV 为准（gunc_output 目录曾混入 16 个 W1 陈旧文件，P1 修复对已存旧产物不追溯）。
- 报告：.claude/reviews/supervisor_20261015_cp2mag.md。

## 四审决议落实（质量审核 2026-10-14，有条件通过 → 用户批示后全部执行）
- **91/92/93 烟测复验钉入排程（P0-2）**：V3 泳道完成后立即执行（16t 空闲窗口，单次 <1h），通过前**禁止 W5 任何 98 系**（93/91/92 修复代码尚未跑过任何数据）。watcher：/tmp/lane_w5_gate.sh。
- **36b 回退哨兵逐样本核对（P1-5）**：H1-H4 已核——N_FALLBACK 全 0（56/51/65/48 bins 全部真重组装，220/220）；H10/H11 完成后即核。
- **磁盘处置（P0-3，用户批准）**：temp/humann3 447GB 已删（6 样本 ×7 结果文件确认在 result/humann3 归档后），磁盘 90%→88%。
- **高内存互斥放宽（用户批准）**：仅 gtdbtk/iphop 错峰。
- **Project01 披露落地（用户批准）**：Project/Project01/NOTES_VIRUS_QUANT_BIAS.md 已建。
- **79c-79f 真菌 MAG 链（用户批准跑）**：watcher /tmp/lane_fungi_mag.sh 挂在 F 泳道完成后自动执行（全 6 样本 continue-on-error，仅 Sample4 有料为设计内披露）。
- **W3-C 插空执行（P1-8）**：31e×6 + 42×6 + 42b×6 以 -t 8 已启动（/tmp/lane_w3c_fillin.sh，实际负载余量内）；28/28b antismash（16t 重）等泳道空位。
- **git 异动上报（非 A 线所为）**：envs-pixi/kneaddata{pixi.lock,pixi.toml}、envs-pixi/prokka/pixi.toml 被删（C 线领域）；mining/snapshots/curation_snapshot.csv.gz 变更（B 线 cron）；未跟踪 tools/、feishu_notes/、samples.txt。均不代提交。

## 待用户approve（质量审核 2026-10-13 两轮合并 6 项 → **用户批示"按质量审核建议执行"，全部落实施中**）
| # | 事项 | 处置 |
|---|---|---|
| A | 36b 重组装照跑，37/38/38b 重做，现结果作对照 | ✅ R 泳道（/tmp/lane_r_36b.sh） |
| B | 54 并集敏感性修复补做 | ✅ 54 已修（7b2e9ab），V 泳道重跑中 |
| C | dbCAN 保持单工具+披露 | ✅ 已披露；25 号 --force 语义已修 |
| D | vOTU 丰度只用 contig 级 | ✅ 60 号重写为 contig 级聚合 |
| E | 病毒基因 ID 加样本前缀 | ✅ 58 号索引构建时加 `样本|` 前缀 |
| F | 现表下游统计冻结，60 复审后重算 | ✅ 冻结令维持；V 完成后呈质量审核复审 |

**冻结令**：votu_table.tsv 现版本不得作为统计输入（60 号打回）；64-72 注释步骤不受影响（不消费该表）。

## 复审跟踪（质量审核 2026-10-13 两轮打回 → 2026-10-14 三审**有条件通过**）
- **口径更正（主代理自纠）**：此前报告"输出列名 lineage 后 91/92 R 兼容"不实——91/92 读的是 geNomad 原始表（列名 taxonomy），60 的 lineage 列与彼无关；三审揪出并已修（91/92 列名检查兼容 taxonomy、91 build_mt_virus 重写为直接消费 canonical 行、93 样本列只取 _tpm 防 length/count 混入）。
- V2 验收全部核证：六样本基因行 0、ΣTPM=10⁶、三对照 contig（Sample1 样本 reads 对 Sample10 来源 contig）NumReads 回升 420.99→1614.48 / 2597.61→3995.86 / 1511.06→2553.89（**取值来源：Sample1/quant.sf**，2026-10-14 复核一致并归档 logs/evidence/vir_numreads_surviving_quant_sf_20261014.tsv；注意 Sample10 自身 quant.sf 对同名 contig 是另一定量，数值不同属预期——质量审核四审曾因此误判证据链断裂，实为跨样本混淆）、join 3062/0/2622、annotated=2,513 真分类（数值假分类 0）、length 抽查 3/3 与实长一致。Sample10 quant 与 votu_table H10_count 逐位一致（60 号聚合无损的交叉验证）。
- **分级解冻（质量审核 2026-10-14 approve）**：`votu_table.tsv`/`vOTU_table_ann.txt` 对 **98c/98g 即时解冻**；**93/91/92/94/96 已全部修复复验通过（CP2 收口 2026-10-17）**（93/91/92 的 R 修复已提交，复验排 CP2 收口）。
- 64-72 病毒下游全量已获质量审核放行（pharokka 55 条试批 ID 回传 55/55），V3 泳道运行中（含 H1/H2/H4/H11 union 补齐 4×54 --force）。
- 三审报告：.claude/reviews/supervisor_20261014_v2_audit.md（注：claude CLI 环境变更不可用，本轮以子代理加载质量审核章程执行，已在报告中披露）。
- **Project01 披露（approve #2）**：Project01 冻结基线的病毒丰度用同一"基因+contig 混合索引"，已发布结论带同源偏差（系统性偏低且 vOTU 间不可比）；按approve不重跑，此偏差须写入论文方法部分与 Project01 notes。
- 91/92/94 若曾跑过病毒分类层，其结果作废待重算（污染扩散清单在 CP3 前核对）。

## 待披露清单（写入 walkthrough 对应章节时落实）
- 25 dbCAN：实际仅 `--tools diamond` 单工具（overview.txt #ofTools=1）；`25:57-59` 无条件跳过破坏 --force 语义。
- 60 vOTU 表：`length` 列实为首个基因长度非 vOTU 长度；305 行基因级记录（~0.6%）因 ID 歧义未并入任何 vOTU（votu_join_stats.tsv:3）。
- 38 dRep 实际质量门槛以 38 号日志为准（可能 comp≥75 非 ≥50，candidate_research）。
- 36b 静默回退风险：metaWRAP 失败回退原始 bin 且 exit 0，CP2-MAG 须逐样本核对 sentinel N_FALLBACK。

## 执行进度索引（2026-10-13 更新）

### 已完成段
| 段 | 步骤 | 事件数 | 关口状态 |
|---|---|---|---|
| 预处理 | 01→02b | 18 | ✅ 已过（supervisor_20261004） |
| 细菌读式 | 11→15d | 58 | ✅ 已过（第四轮通过，C1 已销项） |
| 病毒链全段 | 51→59（60 打回） | — | ⚠️ CP2-病毒：60 号 vOTU 表 FAIL（见 supervisor_20261013_cp_audit.md），58→59→60 整改重跑待approve |
| 真菌链前段 | 71→79b | 44+ | ⏳ 段未完 |
| 细菌组装+基因目录 | 16→20 | — | ✅ CP1 已通过（supervisor_20261004） |
| eggNOG+KEGG | 21（302MB）+ 22（903,807 命中） | — | ✅ validate PASS |
| 三路分箱+整合 | 32/33/34/35 + 36（353 MAGs） | — | ✅ validate PASS（含 bins↔c2b 一致性） |

### 当前运行中（2026-10-18 终版）
**（无——项目已交付）**

> **CP3 终裁：通过（质量审核第 12 次调用，2026-10-18，报告 .claude/reviews/supervisor_20261018_cp3_pass.md）**。经过终审打回（5 P0）→ 复审收窄（4 P0）→ 全部闭合：状态账 33/33 opslog+六行decision、监控真唯一性 9 例矩阵、测试证据可追溯（命令+原始输出）、金标准逐项绑定+分级。质量审核独立复核 FASTA 计数与冻结值逐位一致。P2 残留（全 sha256 已补/注记落点已对齐）不阻断。**「0 开放行」口径=无未decision行（非全部成功），注记实际落点 failure_ledger_33.md:3。**

> **CP3 准备包（W0-W4b，d974475/6da5580/613c23f/71c1e71/f618243）**：99a 显式映射+双维验证（双边核心 140/151、1399/1467）；POWER_DISCLOSURE 四则落盘+98 banner+终版报告 report_20261018_083900.md；监控配对修复（5 例回归，运行中=0）；flock 实例锁（功能测试过）；walkthrough 110 章合稿（五路取证+单人合稿，含代理新发现披露：75 回退口径/83 双工具/43-gapseq 无 SBML/85 细菌 AMR 冒名）；step_checklist 终版 0 开放行；金标准 8/8 复核冻结；46 历史泳道入库+模板。
> **事故 #20（2026-10-18，已完全恢复）**：金标准核验脚本未引用 `^>` 致 shell 重定向截断基因目录两文件 → 18 --force 重建精确复原（995,242/995,199，CD-HIT 确定性验证）；E 类（主代理未引用特殊字符）教训入档。

### 决定不执行
- 16b metaSPAdes（叶子步骤，无下游使用，用户批准不跑）
- 62/63 vMAG（Project01 先例 0 vMAG）
- 95a/95b（无 batch 列）
- 97（跨队列不适用）

### 事故索引（注：编号≠行数——部分行压缩合并多事故，编号至 #20）
| 日期 | 事件 | 档案 |
|---|---|---|
| 2026-10-05 | HUMAnN 相对路径 + cd 嵌套 → 6 样本全失败 | incident_20261005_humann_relpath.md |
| 2026-10-07 | megahit 重复启动 → Sample1 SIGSEGV | incident_20261007_megahit_dup_launch.md |
| 2026-10-09 | 74f 表头误判 → 合并矩阵数据损坏 | 已修复（351952d），无事故档案（内联修复） |
| 2026-10-12 | 74 blast_gutdb 孤儿循环（/tmp/lane_f_blast.sh，10-11 启动，PPID=1）空转：4 样本产出全 0 字节再证数据库无效；首次清杀 Sample4 diamond 后循环仍推进 Sample11（11:28 启动），二次定位循环根整树清除 | 内联处置：循环+脚本+进程全灭、result/fungi/blast_gutdb/（8.3GB）两删；教训：清残留须先定位循环根（/tmp/lane_*.sh），杀叶子进程只会推进迭代 |
| 2026-10-13 | 60 号 vOTU 表五缺陷被 CP2-病毒打回：基因 ID 跨样本重名（305 行丢弃）、length 列语义错、首行误删、contig/基因级 TPM 混加、exit 0 静默通过 | supervisor_20261013_cp_audit.md；整改重跑待approve D/E/F |
| 2026-10-15 | 43/43b -t 声明未注册（首跑即炸，43c 连带 10 连空跑）；41 MAG_FILTER set -u 未初始化 | 36f8b29 / 639b750 |
| 2026-10-15 | 70 phabox2 ~/.local numpy 2.2.6 遮蔽环境 numpy（53 号同根因二次发生） | 2e6f6cc（PYTHONNOUSERSITE；质量审核终审判例：点修不防同类） |
| 2026-10-16 | gate v1 漏传 -m/-g 参数三连败（编排层参数缺失家族第二次）；P0-1 预初始化覆盖 91/93 解析前默认值（GROUP_COL/NET_TYPE 被清空）——被 gate 在统计段启动前拦截 | lane 脚本教训；af66706（unset-only 语义） |
| 2026-10-16 | 92 假通过（91 RDS 生成前跑空表 exit 0，哨兵仅查非空短路重跑）；93 病毒网络 _tpm 后缀未剥致元数据交集 0（伪装成"需≥5 样本"）；93 组间比较 5/5 静默跳过记 OK | supervisor_20261016_cp2_review.md；1b9e566（三处修复） |
| 2026-10-11 | 55 号首轮 6 样本 exit 1（03:37-03:50，CP2 核对时已知"首轮失败后续轮成功"但未入索引——第 9 轮审核补账） | supervisor_20261013_cp_audit.md 附注二 |
| 2026-10-14 | 54/Sample1 exit 127（03:38，环境/PATH 型瞬时失败，当轮 --force 重跑成功——第 9 轮审核补账） | 事件流 03:38 exit=127 → 03:40 起始重跑 exit 0 |
| 2026-10-17 | 99a-virus 修复版离账重跑（06:34:02，_tpm join 修复后手动重跑未走泳道无事件记录，产物被 98 报告引用——第 9 轮审核以 mtime 抓出，补记） | e93c4ca；产物 result/stat/core_microbiome/virus/ |
| 2026-10-18 | **#20 数据损毁事故（主代理自伤）**：金标准核验脚本中 `grep -c ^> file` 的 `>` 未加引号被 shell 解析为输出重定向，将 result/assembly/cdhit/{nucleotide,protein}_nr.fa（995,242/995,199 序列）截断为 2 字节 "0"；未走脚本路径故备份钩子与事件流均无记录。根因家族=未引用特殊字符（E 类）。**立即处置**：18_bac_cdhit --force 重建（prodigal 输入完好、CD-HIT 确定性、原耗时 1510s）；下游产物此前已全部完成不受影响；金标准核验改用 awk 且重建后复核 | 本条即档案；重建验证见后续提交 |

### 检查点计划（质量审核设计）
- CP1: 17/18 + 32 + 54b 完成后 → 核对基因目录/深度表/checkv
- CP2: 37 checkm2 + 60 vOTU 完成后 → 核对 MAG/vOTU
- CP3: 统计段启动前 → 全量 step_checklist 对齐

## BUSCO 联网行为披露（质量审核 P0-2，2026-10-11）
79b/79e 的 BUSCO 在 2026-10-10 运行时使用了 --auto-lineage-euk 但未加 --offline。
日志证实联网刷新了版本清单（busco.log:6 "Downloading information..."）。
本次运行未实际下载数据（lineage 已是最新版），但存在自动写入 db/ 的风险。
修复：已加 --offline，修复后可安全重跑。违反 §10.5-2 数据库冻结，特此披露。

## 病毒判定口径approve（2026-10-11 用户批准）
1. 病毒判定：**交集**做主结果（严格），并集作为敏感性分析——需修改 54 号代码
2. vOTU 定量算法：保留现有实现，文档中披露方法差异
3. 36b 重组装：**全跑**（6/6）
