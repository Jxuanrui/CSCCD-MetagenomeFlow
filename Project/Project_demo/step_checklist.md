# 冻结步骤清单（开跑前基线；质量审核 P0-2）

| 脚本 | 维度 | 计划 | 标注 |
|---|---|---|---|
| 01_qc_fastp | shared | ✓ 已完成 |  |
| 02_qc_kneaddata | shared | ✓ 已完成 |  |
| 02b_qc_pair_repair | shared | ✓ 已完成 |  |
| 11_bac_metaphlan4 | bacteria | ✓ 已完成 |  |
| 11b_bac_metaphlan4_merge | bacteria | ✓ 已完成 |  |
| 12_bac_strainphlan4 | bacteria | ✓ 已完成（aggregate：须等 11 全部完成） | 依赖 11 ×6 样本 |
| 13_bac_humann3 ¹ | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 13b_bac_humann3_merge | bacteria | ✓ 已完成 |  |
| 14_bac_kraken2 | bacteria | ✓ 已完成 |  |
| 14b_bac_kraken2_merge | bacteria | ✓ 已完成 |  |
| 15_bac_centrifuger | bacteria | opt-in 未运行 | 本段留待后续按需运行（未执行） |
| 15b_bac_centrifuger_merge | bacteria | opt-in 未运行 | 本段留待后续按需运行（未执行） |
| 15c_bac_sylph | bacteria | ✓ 已完成 |  |
| 15d_bac_sylph_merge | bacteria | ✓ 已完成 |  |
| 15e_bac_metax | cross-domain | opt-in 未运行 | 本段留待后续按需运行 |
| 16_bac_megahit | bacteria | ✓ 已完成 |  |
| 16b_bac_metaspades | bacteria | 不执行（用户批准，叶子步骤无下游使用） |  |
| 17_bac_prodigal | bacteria | ✓ 已完成 |  |
| 18_bac_cdhit | bacteria | ✓ 已完成 |  |
| 19_bac_salmon_build | bacteria | ✓ 已完成 |  |
| 20_bac_salmon_quant | bacteria | ✓ 已完成 |  |
| 21_bac_eggnog | bacteria | ✓ 已完成 |  |
| 22_bac_kegg | bacteria | ✓ 已完成 |  |
| 23_bac_amrfinder | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 24_bac_card | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 24b_bac_card_summary | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 24c_bac_amr_harmonize | bacteria | ⬜ 可选步骤（GATE-OPT1 通过 2026-10-21；不在默认 rule all，需显式调用） |  |
| 25_bac_dbcan | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 26_bac_vfdb | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 27_bac_bacmet | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 28_bac_antismash | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 28b_bac_bgc_novelty | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 29_bac_defense_finder | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 30_bac_ncyc | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 31_bac_pcyc | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 31b_bac_scyc | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 31c_bac_pfam | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 31d_bac_uniprot | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 31e_bac_fegenie | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 32_bac_coverm_depth | bacteria | ✓ 已完成 |  |
| 33_bac_metabat2 | bacteria | ✓ 已完成 |  |
| 33b_bac_quickbin | bacteria | 不单独执行（36 号注释：4 工具对照实测有害，见 scripts/36_bac_dastool.sh 头注） |  |
| 34_bac_maxbin2 | bacteria | ✓ 已完成 |  |
| 35_bac_semibin2 | bacteria | ✓ 已完成 |  |
| 36_bac_dastool | bacteria | ✓ 已完成 |  |
| 36b_bac_bin_reassembly | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 37_bac_checkm2 | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 38_bac_drep | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 38b_bac_gunc | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 39_bac_coverm_quant | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 39b_bac_instrain_map | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 39c_bac_instrain_profile | bacteria | ✓ 已完成（终版核证 2026-10-18） |  |
| 39d_bac_instrain_compare | bacteria | ✓ 已完成（终版核证 2026-10-18） |  |
| 40_bac_gtdbtk | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 41_bac_prokka | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 41b_bac_mlst | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 41c_bac_pangenome | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 41d_bac_snippy | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 42_bac_mge | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 42b_bac_plasmidfinder | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 43_bac_gem_gapseq | bacteria | ✓ 已完成（事件流核证 2026-10-16） |  |
| 43b_bac_gem_carveme | bacteria | ✓ 已完成（终版核证 2026-10-18） |  |
| 43c_bac_gem_cobrapy_fba | bacteria | ✓ 已完成（终版核证 2026-10-18） |  |
| 51_vir_megahit | virome | ✓ 已完成 |  |
| 52_vir_genomad | virome | ✓ 已完成 |  |
| 53_vir_virsorter2 | virome | ✓ 已完成 |  |
| 54_vir_checkv_contig | virome | ✓ 已完成 |  |
| 54b_vir_checkv_filter | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 55_vir_prodigal_gv | virome | ✓ 已完成 |  |
| 56_vir_votu_gen | virome | ✓ 已完成 |  |
| 57_vir_votu_genomad | virome | ✓ 已完成 |  |
| 58_vir_salmon_build | virome | ✓ 已完成 |  |
| 59_vir_salmon_quant | virome | ✓ 已完成 |  |
| 60_vir_votu_table | virome | ✓ 已完成 |  |
| 61_vir_vmag | x |不执行（Project01 先例 0 vMAG，连带 62/63/71） |  |
| 62_vir_checkv_mag | virome | 批准不执行 | 依据：NOTES「决定不执行」——vMAG 依赖深链产出，Project01 先例 0 vMAG（用户批准 2026-10-10 计划） |
| 63_vir_coverm_quant | virome | 批准不执行 | 同 62（同批次用户批准） |
| 64_vir_pharokka | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 65_vir_phold | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 66_vir_vog | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 67_vir_bacphlip | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 67b_vir_phastyle | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 68_vir_iphop | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 69_vir_vcontact3 | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 70_vir_phabox2 | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 71_vir_dram | virome | 批准不执行 | 依赖 vMAG（62/63 不执行连带，同批次批准） |
| 72_vir_phagcn3 | virome | ✓ 已完成（事件流核证 2026-10-16） |  |
| 71_fun_kraken2_fungi | fungi | ✓ 已完成 |  |
| 72_fun_metaphlan4_euk | fungi | ✓ 已完成 |  |
| 72b_fun_metaphlan4_merge | fungi | ✓ 已完成 |  |
| 73_fun_humann4_fungi | fungi | ✓ 已完成 |  |
| 74_fun_blast_gutdb | fungi | 已废弃（gut_fungi.dmnd 核酸库误作蛋白库，产出恒 0；勿启动） |  |
| 74a_fun_gut_db_build | x |不排期（依赖已废弃的 74） |  |
| 74e_fun_phf_profiler | fungi | ✓ 已完成 |  |
| 74f_fun_phf_aggregate |  | ✓ 已完成（事件流核证 2026-10-16） |  |
| 75_fun_funomics | fungi | ✓ 已完成（事件流核证 2026-10-16） |  |
| 75b_fun_funomics_aggregate | fungi | ✓ 已完成（事件流核证 2026-10-16） |  |
| 76_fun_ccmetagen | fungi | 不适用（registry removed，脚本已删除） |  |
| 77_fun_microfisher | fungi | ✓ 已完成（事件流核证 2026-10-16） |  |
| 78_fun_megahit | fungi | ✓ 已完成 |  |
| 79_fun_eukfinder | fungi | ✓ 已完成 |  |
| 79b_fun_veba_qc | fungi | ✓ 已完成 |  |
| 79c_fun_coverm_depth | fungi | ✓ 已完成（事件流核证 2026-10-17）|  |
| 79d_fun_metabat2 | fungi | ✓ 已完成（事件流核证 2026-10-17）|  |
| 79e_fun_euk_qc_per_bin | fungi | ✓ 已完成（事件流核证 2026-10-17）|  |
| 79f_fun_metaeuk_per_bin | fungi | ✓ 已完成（事件流核证 2026-10-17）|  |
| 80_fun_prodigal | fungi | ✓ 已完成（事件流核证 2026-10-16） |
| 80b_fun_metaeuk | fungi | ✓ 已完成（事件流核证 2026-10-16） |  |
| 81_fun_eggnog | fungi | ✓ 已完成（事件流核证 2026-10-16） |  |
| 82_fun_kegg | fungi | ✓ 已完成（事件流核证 2026-10-16） |  |
| 83_fun_dbcan | fungi | ✓ 已完成（事件流核证 2026-10-17）|  |
| 84_fun_vfdb | fungi | ✓ 已完成（事件流核证 2026-10-17）|  |
| 85_fun_amr | fungi | ✓ 已完成（事件流核证 2026-10-17）|  |
| 86_fun_merops | fungi | ✓ 已完成（事件流核证 2026-10-17）|  |
| 91_stat_diversity | stats | ✓ 已完成（事件流核证 2026-10-16） |  |
| 92_stat_differential | stats | ✓ 已完成（事件流核证 2026-10-16） |  |
| 93_stat_cooccurrence | stats | ✓ 已完成（事件流核证 2026-10-16） |  |
| 94_stat_visualization | stats | ✓ 已完成（终版核证 2026-10-18） |  |
| 95a_stat_batch_correct | x |不执行（metadata 无 batch 列） |  |
| 95b_stat_batch_evaluate | x |不执行（同上） |  |
| 96_stat_ml_siamcat | x |SKIPPED-by-guard（≥10 样本要求，n=6 设计限制，POWER_DISCLOSURE 披露） | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96b_pathway_activity | x |✓ 已完成（96 伞内执行） | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96c_functional_redundancy | x |✓ 已完成（96 伞内执行） | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 98_stat_report | stats | ✓ 已完成（终版核证 2026-10-18） |  |
| 98b_bac_integration_tables | bacteria | ✓ 已完成（终版核证 2026-10-18） |  |
| 98c_vir_integration_tables | virome | ✓ 已完成（终版核证 2026-10-18） |  |
| 98d_fun_integration_tables | fungi | ✓ 已完成（终版核证 2026-10-18） |  |
| 99a_core_microbiome | stats | ✓ 已完成（终版核证 2026-10-18） |  |
| 99b_lefse | stats | ✓ 已完成（终版核证 2026-10-18） | n 下限 4（本组 6 贴近下限） |
| 01_metadata_qc | x |✓ 已完成（项目前置，samplesheet/metadata 齐备） |  |
| 96_stat_functional | stats | ✓ 已完成（终版核证 2026-10-18） | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96_functional_permanova | x |✓ 已完成（96 伞内执行） | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96_functional_integrated | x |✓ 已完成（96 伞内执行） | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96_functional_cross_dimension | x |✓ 已完成（96 伞内执行） | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 98c_bac_mge_summary | bacteria | ✓ 已完成（终版核证 2026-10-18） |  |
| 98d_bac_mag_integration | bacteria | ✓ 已完成（终版核证 2026-10-18） |  |
| downstream_summary | stats | 不适用（占位步骤，实际由 98 系整合表承担） |  |
| rag_build_experience | shared | 本阶段排除（B 线范围） | 属 B 线 RAG 职责非本演示 A 线；写入路径 §10.1 禁改区；如需启用另行approve（当前状态=已decision非未决） |
| rag_refresh_literature | shared | 本阶段排除（B 线范围） | 同上 |
| 97_stat_crosscohort | stats | 不适用（结构性） | 跨队列复现需第二队列，单项目演示结构性不适用 |
| 98e_cross_domain_ani_cluster | x |✓ 已完成（终版核证 2026-10-18） |  |
| 98f_cross_domain_orthogroup | stats | ✓ 已完成（终版核证 2026-10-18） |  |
| 98g_cross_domain_correlation | stats | ✓ 已完成（终版核证 2026-10-18） |  |

> ¹ 13_bac_humann3 依赖同一样本的 11 metaphlan4 profile（质量审核 E1 2026-10-04），不可先跑。

> ⚠️ 病毒 71/72（vir_dram/vir_phagcn3）与真菌 71/72（fun_kraken2/metaphlan4_euk）编号重复——分属不同维度。
