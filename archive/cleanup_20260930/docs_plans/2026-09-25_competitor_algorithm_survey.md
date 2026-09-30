# 竞品与算法调研评估报告(任务 1)

- **日期**: 2026-09-25
- **执行模型**: 主代理 GLM5.3(规划/综合/核验)+ 4×ZCode Explore 子代理并行检索。
  本会话未注册 glm-router MCP,Flash 未参与;调研属规划类任务,符合 CLAUDE.md §6 路由矩阵。
- **调研方式**: 4 路并行(竞品平台 / 细菌+MAG / 病毒+真菌 / 统计+ML+数据库),
  主代理对 5 条支撑性论断做了独立抽查核验(MetaPhlAn vJan25、GTDB-Tk R232、MaAsLin 3、
  Binette、UHGV,全部属实)。标 [未验证] 者未核验,决策时按不确定处理。
- **用途**: 任务 1 交付物,供讨论取舍后进入任务 2(迁移性)与任务 3(PRD)。

---

## 0. 一句话结论

平台生态位独特(三界一体 + 统计 + RAG/挖掘,无单一竞品覆盖),**竞争威胁低**;
真正的风险是**内部版本漂移**(分类学骨架落后 1-2 代)与**两块能力短板**
(病毒参考层无锚定库、真菌定量精度弱)。建议分三档处理:
A1 版本刷新包(低成本高确定性)→ A2 结构性增强(中成本高价值,逐项讨论)→ A3 观察项(不进本周期)。

---

## 一、竞品平台对照

| 平台 | 最新版本(日期) | 引擎/许可 | 覆盖 | 与我们重叠 | 健康度 | 值得借鉴 |
|---|---|---|---|---|---|---|
| **VEBA** | v2.5.3(2026-03) | Snakemake/GenoPype, **AGPL-3.0** | 三域 MAG 恢复+聚类+BGC | **高**(定位最接近) | 活跃 | **环境↔数据库绑定 fail-fast**(环境失效即锁死,防止误用错误 DB 静默产出错注释);仅可借鉴机制,**不可复用源码** |
| **nf-core/mag** | v3.x 起 hybrid,2025-2026 持续大版本(具体版本号未逐一核验) | Nextflow, MIT | 细菌 MAG 全链+长读混合 | 高(细菌链) | 活跃 | nf-test 端到端测试框架;DAS Tool+GUNC 集成模式 |
| **nf-core/taxprofiler** | v2.0.x(2025) | Nextflow, MIT | 多 profiler×多 DB 矩阵 | 中(我们的 11/14/15 系列) | 活跃 | profiler×DB 组合矩阵化运行+统一汇总 |
| **nf-core/funcscan** | v1.1.2(2023-11) | Nextflow, MIT | AMR+BGC 筛选 | 中 | 维护迟滞 | **hAMRonization 统一 AMR 报告格式** |
| nf-core/viralrecon | v1.6.0(2023-04) | Nextflow | SARS-CoV-2 定向 | 低 | 停滞 | — |
| **Metagenome-Atlas** | v3.0.0(2024-11) | Snakemake, GPL-3.0 | 细菌全链 | 高 | 低强度维护 | 快速自动化测试+分层默认配置 |
| SqueezeMeta | v1.5.1(2022-08) | 条带式 | 全链含统计 | 高 | 代码停滞(2025 仍发方法论论文) | **co-assembly 策略**(2025 BMC Bioinf:低丰度基因/MAG 恢复增益) |
| MetaWRAP | v1.2.4(2022-11) | — | MAG 环节 | 中 | 停滞 | bin_refinement 思路已被 **Binette** 现代化 |
| metashot | v2.16.x(2025) | Snakemake 8+Singularity | 细菌链 | 中 | 活跃 | 无 root 极简部署(与我们场景同) |
| anvi'o | v9(2026-01) | **部分 AGPL** | 交互式基因组中心分析 | 中 | 活跃 | MAG 精修交互层;范式不同,不引入 |
| bioBakery | MetaPhlAn 4.2.6(2026-07-28) | MIT | 物种+功能生态 | **高**(我们直接使用者) | 活跃 | 见 A1:vJan25 DB 升级 |
| QIIME 2 → "Rachis" | 2026.4.0(2026-04)[未验证改名细节] | BSD-3 | 16S 为主 | 低 | 重构动荡期 | 不依赖 |
| MG-RAST / MGnify / MetaStorm / MSE2 / GMrepo | 2025-2026 各异 | web/DB | 公共服务与数据 | 低 | 各异 | MGnify 的 DocBot(RAG 助手挂在平台侧)与我们 MCP RAG 同思路;GMrepo/MSE 作挖掘层参照数据源 |
| EasyMetagenome | v1.24(2025-11) | GPL-3.0 | 中文社区三段式 | 中 | 活跃 | 中文文档生态(我们 README 已对齐此生态) |

**定位结论**:最接近的同类是 VEBA,但无统计链/真菌定量链且 AGPL 传染;nf-core 系引擎不同。
我们的差异化(三界一体、单服务器无 root、MCP RAG+疾病指纹挖掘、CNS 出版级图件体系)没有直接对手。
**工程层面最值得抄的两个机制**:① VEBA 式 env↔DB 绑定校验(可低成本落入
`00_check_database.sh` + `docs/manifests/`,与我们已有的 manifest 锁清单天然契合);
② hAMRonization 式统一报告层(我们已有 24b 自研 CARD 汇总,可泛化格式而非引入工具)。

---

## 二、细菌维 / MAG(对照现有 11-43c)

### 已过时/落后项(核实过的版本差)
| 现状 | 最新 | 说明 |
|---|---|---|
| GTDB-Tk R214(40) | 2.7.x + **R232** | 官方 releases 核验:DB 198→**98GB**(skani 预 sketch,反而省盘),但需 **≥140GB RAM**;分类骨架落后 2 个大版本,所有下游报告受影响 |
| MetaPhlAn mpa_vJan21_202403(11/72) | 4.2.6 + **vJan25** | 58,331 SGB(+21,509 vs vJun23),130 万 MAG 底座,GTDB r220 对齐,长读支持;零新工具成本。**注意**:HUMAnN 3.9 独立 DB,兼容性需验证后再动 |
| sylph 0.x(15c) | **1.0**(2026-09) | .syl2db 新格式断代;原核 profiling 数倍提速,需重建 sketch |
| dRep 3.4.x(38) | 3.7.1(2026-06) | 大量修复 |
| eggNOG-mapper(21/81) | 2.1.14(2026-05);3.0-beta(eggNOG 7) | 稳定线直接升;eggNOG 7 beta 体积未核,观察 |
| CheckM2 / GUNC / inStrain / eggNOG / EukCC2 / UNITE | 1.1.0 / 1.1.1 / 1.10 / … | 常规小版本刷新 |

### 新能力候选
| 候选 | 是什么 | 增量价值 | 成本/风险 |
|---|---|---|---|
| **Binette**(v1.2.x,活跃) | 多 binner 输出的**精修层**(集合运算造混合 bin,CheckM2 打分,metaWRAP 精修思路现代化) | **高**:与 QuickBin"DAS Tool 集成净有害"发现直接互补——给 5 binner 组一个现代集成/精修层 | 轻量无大 DB;"优于 DAS Tool"需在我们数据上 head-to-head 自测(README 无直接基准) |
| **UHGV** 参考层(见 §三) | 873,995 肠道病毒基因组 | 高(病毒维) | 见 §三 |
| **GToTree**(1.8.19) | 单命令按域选 SCG 建树 | **高**:MAG↔参考混合系统发育树是我们明显缺口(GTDB-Tk 只给分类),CPU 低、DB 极小 | 轻量 |
| **BiG-SCAPE 2.0**(2025-10) + MIBiG 4 | BGC GCF 家族聚类(提速 8×) | 中-高:把 28b 自研新颖性打分锚定到全局家族,可解释性大增 | 需要 antiSMASH 结果即可,计算轻 |
| **Bakta**(1.12.1,DB light 3.9GB / full 84GB) | Prokka 的现代替代 | 中-高:CDS 质量/结构化注释更好;**建议 light DB 并行试用,不动生产链** | GPL-3.0;full DB 占盘 |
| **MIDAS 3 + StrainPGC**(2025,snayfach 组) | pangenome 式株级基因含量定量 | 中:现有栈(StrainPhlAn4+inStrain)无"株级基因含量/拷贝数"能力 | DB 数十 GB;按需 |
| **gplas2 + Plasmer**(2025 基准最佳组合) | 宏基因组质粒**重建**(contigs 归组到质粒单元) | 中:MGE 链(42/42b)有识别无重建;CRC-ARG 移动性叙事加分 | gplas2 在 GitLab,GPLv3 |
| KofamScan(1.3.0) | KO 的 HMM+自适应阈值 | 中:可与 22 KEGG diamond 互验(精度↑) | 可选项 |
| COMEBin 1.1.0(2026-08)/ VAMB 5.x(TaxVamb)/ MetaCAT(2026 Nat Microbiol[未验证]) | 第 5/6 个 binner | **低**:QuickBin 论文已含对比;binning 冗余 | 不加 |
| Metabuli / KMCP / Woltka / fmh-funprofiler(原 Mantis) | 分类/功能定量 | 低:与 4 分类器+Salmon 链冗余 | 不加 |

---

## 三、病毒维(对照现有 51-72)

| 候选/更新 | 是什么 | 增量价值 | 成本/风险 |
|---|---|---|---|
| **UHGV**(2025-11 bioRxiv,JGI/Zenodo 存档,MIT 式) | 12 个肠病毒目录统一(**873,995 基因组/168,536 vOTU**),含 ICTV 分类、Caudoviricetes 树、5.3M CRISPR spacers、宿主表;配套 UHGV-classifier | **高**:我们 vOTU(56/57/68)完全缺"分类/宿主锚定参考",这是病毒维最大结构性缺口;与 geNomad/CheckV 同团队同格式;**Phanta/sylph 的 DB 均由它派生** | 下载体积未核(分级 Full/HQ);建议先取 metadata+classifier |
| **Phanta**(Nat Biotechnol 2024,Bhatt lab) | read 级"噬菌体包容"定量(不经组装,病毒+细菌+真核同框) | 高:救回组装丢失的低丰度噬菌体;病毒-细菌同框丰度直接喂 98g 跨域网络;与组装路线正交可交叉验证 | DB 中等;推荐用 UHGV 派生版 |
| cnGVC(2025,PMC11938785) | 中国人群肠道病毒目录(93,462,>70% 新) | 中-高:人群匹配(我们是中国 CRC 中心),CGVR 研究称 89.7% vOTU 为中国人群特有 | 叠加于 UHGV 之上按需 |
| 版本刷新:geNomad 1.12+DB v1.9(**MSL40 全谱系**)、PHAROKKA 1.10.1+PHOLD 1.3.0(PHROG v4[未验证])、VOGDB 232、PhaBOX 2.1.13(**CHERRY tRNA 宿主证据**,需提供 MAG——我们正好有)、vConTACT3 正式版(Nat Biotechnol 2025 已发表,可引用)、iPHoP 1.4.2、CheckV 维持 | 常规升级 | **中-高**(其中 MSL40 谱系+tRNA 宿主证据有实质精度增量) | 低;PhaBOX/vConTACT3 需重跑 DB |
| VirSorter2(53) | 事实停更(2023 后无版),社区转向 geNomad | 低 | **保留交集策略但不再投入**;中长期可评估 geNomad 主导 |
| DRAM2(beta37) | Nextflow 重写 | 低(beta,无 conda 包) | 观察;AMG 环节维持 DRAM-v 1.5.0 + Martin et al. 2025 的 AVG 严格人工筛(方法学加强,零软件成本) |
| CHVD / GVD / IMG/VR v4 全库 | 旧目录/过大 | 低(CHVD 2021 后未更新,**被 UHGV 覆盖**;IMG/VR >15M 基因组对 1.2TB 预算不友好) | 不加 |

---

## 四、真菌维(对照现有 71-86)

| 候选/更新 | 是什么 | 增量价值 | 成本/风险 |
|---|---|---|---|
| **FungiGut / FungiGutDB**(bioRxiv 2025-12-03,**预印本**) | 策展式肠道真菌分类库+流水线,内嵌 MiCoP(文献称对真菌优于 Kraken2/MetaPhlAn4) | **高**:正中真菌定量短板(71-77 多工具共识仍以通用分类器为主) | 预印本风险;小库,先试点后定 |
| **MycobiomeDB**(decodebiome,16,365 策展基因组) | 按身体部位分层的真菌基因组目录 | 中-高:把 gut_fungi_db(760)升级一个量级,供 74/74a 比对锚定 | 与现 47G BLAST 库/PHF 库的取舍需讨论 |
| **低生物量污染控制方法学**(Fierer 2025 Nat Microbiol 污染共识;Agudelo 2025 mSystems;Brunner 2024 CoDA) | 阴性对照/decontam 式流程+报告规范 | **高**:真菌组可信度是我们明显缺的一环,纯方法学改造,审稿收益大 | 零 DB 成本;但"阴性对照"涉及采样端,需队列配合 |
| EukCC2 2.2.0(2026-08) | 真核 MAG 完整性评估(现为诊断脚本用) | 中:建议纳入 79 后主链正式 QC | 轻量 |
| Eukfinder 1.2.4 | 正式发表(2025),基准胜过 EukRep/Tiara | 低(已集成,补可引用性) | — |
| FunOMIC / MicroFisher / CCMetagen | 2025 无实质更新 | 低 | 维持现状;CCMetagen nt 库继续不配置 |

---

## 五、统计 / ML / 数据库(对照现有 91-99、mcp/、mining/)

| 候选 | 是什么 | 增量价值 | 成本/风险 |
|---|---|---|---|
| **MaAsLin 3**(Nature Methods 2026;23:554-564,已核验) | abundance+prevalence 双模型(hurdle)、lme4 随机效应(纵向)、绝对丰度输入 | **高**:纵向/随访 + 流行率维度现体系完全缺失;R 包直接进 envs/r_stat,92 加一条方法分支 | 低 |
| **micom + MCMM**(SCFA 群落通量预测) | 从功能丰度升维到群落 FBA 通量 | 中:CRC 丁酸/丙酸机理叙事增量;与 43c COBRApy 单菌 FBA 形成"单菌-群落"两级 | 中;Python,单服务器可行 |
| DIABLO/mixOmics | 监督式三界联合变量选择 | 中:98g 相关网络之外的补充 | 低-中 |
| gutMGene v2.0(NAR 2025)+ BugSigDB 增量 dump | 知识库刷新 | 低-中:mcp/ 桥接已有,仅同步数据 | 半天内 |
| CMS/Coordinated Meta-Storms(Bioinformatics 2025)+ LAMPP 基准 | 百万级样本比对引擎;活体 ML 基准 | 中:指纹库扩到公共十万级样本时的引擎;LAMPP 可作 CRC 分类器外部评测协议 | 后期;观察 |
| pyseer/AURORA(MAG-GWAS) | 毒力/适应基因-表型关联 | 中:需某菌 ≥50-100 MAG 才可做;CRC 队列按需 | 后期 |
| Songbird/mmvec、FlashWeave、LinDA、ZicoSeq、ALDEx2 | 与现有 5 法 DA/网络栈冗余,无 2025 基准优势 | 低 | 不加 |
| 微生物组基础模型(DNABERT-MS 等) | 预印本/初创期,LAMPP 刚建 | 低(观察) | 不加 |
| workflowr/targets | 通用构建工具,无新科学能力 | 低(我们 98 快照+Snakemake 已覆盖) | 不加 |

**误传澄清(检索不存在,勿再跟踪)**:ANCOM-BC3、MIMOSA3、PolyDominance、MMUPHin 2、
UHGG v3、GMGC v2、BinRefiner(未找到同名公开工具,疑与 Binette 混淆)、VQAssess、GeoPhyler。

---

## 六、汇总分档

### A1 版本刷新包(低成本·高确定性,建议整体进 PRD)
MetaPhlAn 4.2.6+vJan25(先验 HUMAnN3 兼容)· GTDB-Tk 2.7.x+R232(140GB RAM 约束)·
sylph 1.0(重建 sketch)· geNomad 1.12+DB v1.9(MSL40)· PHAROKKA/PHOLD/PHROG·VOGDB 232·
PhaBOX 2.1.13 · vConTACT3 正式版 · iPHoP 1.4.2 · dRep 3.7.1 · GUNC 1.1.1 · CheckM2 1.1.0 ·
inStrain 1.10 · eggNOG-mapper 2.1.14 · EukCC2 2.2.0 · UNITE 2025-02 · MIBiG 4 ·
ICTV MSL40 同步 · gutMGene v2.0/BugSigDB dump 刷新。
**附带**:收敛分类学版本漂移(sylph R220 / Centrifuger R226 / GTDB-Tk R214 → R232 统一锚)。

### A2 结构性增强(中成本·高价值,逐项讨论后再定)
1. **UHGV(+cnGVC)病毒参考层**——vOTU 分类/宿主锚定(+可选 Phanta read 级定量)
2. **Binette 精修层**——与 36 DAS Tool 在真实数据 head-to-head 后定去留
3. **MaAsLin 3**——92 差异分析扩容(纵向+prevalence)
4. **真菌三件套**——FungiGut 试点 + MycobiomeDB 锚定库升级 + 低生物量污染控制方法学
5. **GToTree**(MAG 树缺口)· **BiG-SCAPE 2**(28b 锚定)· **Bakta light 并行试用**
6. 工程:VEBA 式 env↔DB fail-fast 校验(落 00_check_database.sh + manifests)

### A3 观察项(不进本周期 PRD)
DRAM2 beta · HUMAnN4(无正式 release,DB 走 Globus)· eggNOG 7/mapper 3 beta ·
MetaCAT · MIDAS3/StrainPGC · micom/MCMM · DIABLO · CMS/LAMPP · pyseer · gplas2/Plasmer ·
KofamScan · GECCO · co-assembly 模式(算力大改)· 基础模型。

### B 不值得跟进
- **停滞**:VirSorter2(保留不投入)· MetaWRAP · Sunbeam · MG-RAST · MetaDecoder · SCAPP/PlasClass · GraphBin2 · gplas 旧版
- **冗余**:COMEBin/VAMB5/MetaCAT(binner 已 4+1)· Metabuli/KMCP/Woltka/fmh-funprofiler · Songbird/mmvec · FlashWeave · anvi'o · QIIME2/Rachis
- **许可红线**:VEBA、anvi'o(AGPL)——机制可借鉴,源码不可复用
- **不存在**:见 §五误传清单

---

## 七、风险与定位提示

1. **GTDB R232 的 140GB RAM 门槛**与 98GB 盘是 A1 中唯一硬约束,需按本机 48c 服务器内存排期。
2. **sylph 1.0 / eggNOG 未来版本**含格式断代,升级窗口选在项目空档期。
3. A2-4 真菌"低生物量污染控制"若要完整落地需要**阴性对照样本**,超出纯软件范畴——需用户在队列层面决策。
4. 竞品无威胁,但 bioBakery 生态 DB 迭代节奏(年更)意味着 A1 类刷新应**周期化**(建议每年一次版本刷新 sprint),而非一次性。

## 八、待用户决策的讨论点

1. A1 刷新包是否全量批准?GTDB-Tk 排期受内存约束,是否单独处理?
2. Binette:head-to-head 验证方案(用 Project01 冻结集 or 新项目数据)?
3. UHGV 接入深度:仅 metadata+classifier(轻),还是含 Phanta read 级定量(中)?cnGVC 是否叠加?
4. 真菌:FungiGut 预印本风险接受度?MycobiomeDB 与现 47G BLAST 库/PHF 库是替换还是并列?阴性对照采样是否可行?
5. GToTree/BiG-SCAPE/Bakta-light 是否进 A2 首批?
6. 版本刷新"周期化"(年度 sprint)是否纳入治理(CLAUDE.md 或 manifests 流程)?

## 附:主要来源(节选)

- MetaPhlAn releases/changelog: https://github.com/biobakery/MetaPhlAn/releases
- GTDB-Tk releases(R232/98GB/140GB RAM): https://github.com/Ecogenomics/GTDBTk/releases
- Binette: https://github.com/genotoul-bioinfo/Binette (JOSS: Mainguy et al. 2024)
- UHGV: https://github.com/snayfach/UHGV · https://uhgv.jgi.doe.gov/downloads · bioRxiv 10.1101/2025.11.01.686033
- MaAsLin 3: Nature Methods 2026;23:554-564 · https://github.com/biobakery/MaAsLin3
- Phanta: https://github.com/bhattlab/phanta (Nat Biotechnol 2024)
- VEBA: https://github.com/jolespin/veba (AGPL-3.0)
- PhaBOX: https://github.com/KennthShang/PhaBOX/releases · vConTACT3: PubMed 41420049
- cnGVC: https://pmc.ncbi.nlm.nih.gov/articles/PMC11938785
- FungiGut: bioRxiv 10.64898/2025.12.03.691829 · MycobiomeDB: https://www.decodebiome.org/mycobiomedb
- 真菌污染共识: https://www.nature.com/articles/s41564-025-02035-2 · https://journals.asm.org/doi/10.1128/msystems.00408-25
- gutMGene v2.0(NAR 2025 53:D783) · BugSigDB: https://www.bugsigdb.org
- GToTree/BiG-SCAPE/sylph/inStrain 等版本: 各官方 GitHub/bioconda(详见调研记录)
