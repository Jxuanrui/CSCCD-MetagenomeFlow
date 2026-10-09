# 冻结步骤清单（开跑前基线；质量审核 P0-2）

| 脚本 | 维度 | 计划 | 标注 |
|---|---|---|---|
| 01_qc_fastp | shared | ✓ 已完成 |  |
| 02_qc_kneaddata | shared | ✓ 已完成 |  |
| 02b_qc_pair_repair | shared | ✓ 已完成 |  |
| 11_bac_metaphlan4 | bacteria | ✓ 已完成 |  |
| 11b_bac_metaphlan4_merge | bacteria | ✓ 已完成 |  |
| 12_bac_strainphlan4 | bacteria | ✓ 已完成（aggregate：须等 11 全部完成） | 依赖 11 ×6 样本 |
| 13_bac_humann3 ¹ | bacteria | 运行 |  |
| 13b_bac_humann3_merge | bacteria | ✓ 已完成 |  |
| 14_bac_kraken2 | bacteria | ✓ 已完成 |  |
| 14b_bac_kraken2_merge | bacteria | ✓ 已完成 |  |
| 15_bac_centrifuger | bacteria | opt-in 未运行 | 本段留待后续按需运行（未执行） |
| 15b_bac_centrifuger_merge | bacteria | opt-in 未运行 | 本段留待后续按需运行（未执行） |
| 15c_bac_sylph | bacteria | ✓ 已完成 |  |
| 15d_bac_sylph_merge | bacteria | ✓ 已完成 |  |
| 15e_bac_metax | cross-domain | opt-in 未运行 | 本段留待后续按需运行 |
| 16_bac_megahit | bacteria | 运行 |  |
| 16b_bac_metaspades | bacteria | 运行 |  |
| 17_bac_prodigal | bacteria | 运行 |  |
| 18_bac_cdhit | bacteria | 运行 |  |
| 19_bac_salmon_build | bacteria | 运行 |  |
| 20_bac_salmon_quant | bacteria | 运行 |  |
| 21_bac_eggnog | bacteria | 运行 |  |
| 22_bac_kegg | bacteria | 运行 |  |
| 23_bac_amrfinder | bacteria | 运行 |  |
| 24_bac_card | bacteria | 运行 |  |
| 24b_bac_card_summary | bacteria | 运行 |  |
| 25_bac_dbcan | bacteria | 运行 |  |
| 26_bac_vfdb | bacteria | 运行 |  |
| 27_bac_bacmet | bacteria | 运行 |  |
| 28_bac_antismash | bacteria | 运行 |  |
| 28b_bac_bgc_novelty | bacteria | 运行 |  |
| 29_bac_defense_finder | bacteria | 运行 |  |
| 30_bac_ncyc | bacteria | 运行 |  |
| 31_bac_pcyc | bacteria | 运行 |  |
| 31b_bac_scyc | bacteria | 运行 |  |
| 31c_bac_pfam | bacteria | 运行 |  |
| 31d_bac_uniprot | bacteria | 运行 |  |
| 31e_bac_fegenie | bacteria | 运行 |  |
| 32_bac_coverm_depth | bacteria | 运行 |  |
| 33_bac_metabat2 | bacteria | 运行 |  |
| 33b_bac_quickbin | bacteria | 运行 |  |
| 34_bac_maxbin2 | bacteria | 运行 |  |
| 35_bac_semibin2 | bacteria | 运行 |  |
| 36_bac_dastool | bacteria | 运行 |  |
| 36b_bac_bin_reassembly | bacteria | 运行 |  |
| 37_bac_checkm2 | bacteria | 运行 |  |
| 38_bac_drep | bacteria | 运行 |  |
| 38b_bac_gunc | bacteria | 运行 |  |
| 39_bac_coverm_quant | bacteria | 运行 |  |
| 39b_bac_instrain_map | bacteria | 运行 |  |
| 39c_bac_instrain_profile | bacteria | 运行 |  |
| 39d_bac_instrain_compare | bacteria | 运行 |  |
| 40_bac_gtdbtk | bacteria | 运行 |  |
| 41_bac_prokka | bacteria | 运行 |  |
| 41b_bac_mlst | bacteria | 运行 |  |
| 41c_bac_pangenome | bacteria | 运行 |  |
| 41d_bac_snippy | bacteria | 运行 |  |
| 42_bac_mge | bacteria | 运行 |  |
| 42b_bac_plasmidfinder | bacteria | 运行 |  |
| 43_bac_gem_gapseq | bacteria | 运行 |  |
| 43b_bac_gem_carveme | bacteria | 运行 |  |
| 43c_bac_gem_cobrapy_fba | bacteria | 运行 |  |
| 51_vir_megahit | virome | ✓ 已完成 |  |
| 52_vir_genomad | virome | ✓ 已完成 |  |
| 53_vir_virsorter2 | virome | 运行 |  |
| 54_vir_checkv_contig | virome | 运行 |  |
| 54b_vir_checkv_filter | virome | 运行 |  |
| 55_vir_prodigal_gv | virome | 运行 |  |
| 56_vir_votu_gen | virome | 运行 |  |
| 57_vir_votu_genomad | virome | 运行 |  |
| 58_vir_salmon_build | virome | 运行 |  |
| 59_vir_salmon_quant | virome | 运行 |  |
| 60_vir_votu_table | virome | 运行 |  |
| 61_vir_vmag | virome | 运行 |  |
| 62_vir_checkv_mag | virome | 待核/预期空 | 不适用候选：vMAG 依赖深链产出（Tutorial:1901 Project01 先例 0 vMAG，跑后核） |
| 63_vir_coverm_quant | virome | 待核/预期空 | 同 62 |
| 64_vir_pharokka | virome | 运行 |  |
| 65_vir_phold | virome | 运行 |  |
| 66_vir_vog | virome | 运行 |  |
| 67_vir_bacphlip | virome | 运行 |  |
| 67b_vir_phastyle | virome | 运行 |  |
| 68_vir_iphop | virome | 运行 |  |
| 69_vir_vcontact3 | virome | 运行 |  |
| 70_vir_phabox2 | virome | 运行 |  |
| 71_vir_dram | virome | 待核/预期空（依赖 vMAG，见 62/63） |  |
| 72_vir_phagcn3 | virome | 运行 |  |
| 71_fun_kraken2_fungi | fungi | ✓ 已完成 |  |
| 72_fun_metaphlan4_euk | fungi | ✓ 已完成 |  |
| 72b_fun_metaphlan4_merge | fungi | ✓ 已完成 |  |
| 73_fun_humann4_fungi | fungi | ✓ 已完成 |  |
| 74_fun_blast_gutdb | fungi | ✓ 已完成 |  |
| 74a_fun_gut_db_build | fungi | 运行 |  |
| 74e_fun_phf_profiler |  | 运行 |  |
| 74f_fun_phf_aggregate |  | 运行 |  |
| 75_fun_funomics | fungi | 运行 |  |
| 75b_fun_funomics_aggregate | fungi | 运行 |  |
| 76_fun_ccmetagen | fungi | 不适用（registry removed，脚本已删除） |  |
| 77_fun_microfisher | fungi | 运行 |  |
| 78_fun_megahit | fungi | 运行 |  |
| 79_fun_eukfinder | fungi | 运行 |  |
| 79b_fun_veba_qc | fungi | 运行 |  |
| 79c_fun_coverm_depth | fungi | 运行 |  |
| 79d_fun_metabat2 | fungi | 运行 |  |
| 79e_fun_euk_qc_per_bin | fungi | 运行 |  |
| 79f_fun_metaeuk_per_bin | fungi | 运行 |  |
| 80_fun_prodigal | fungi | 运行 |  |
| 80b_fun_metaeuk | fungi | 运行 |  |
| 81_fun_eggnog | fungi | 运行 |  |
| 82_fun_kegg | fungi | 运行 |  |
| 83_fun_dbcan | fungi | 运行 |  |
| 84_fun_vfdb | fungi | 运行 |  |
| 85_fun_amr | fungi | 运行 |  |
| 86_fun_merops | fungi | 运行 |  |
| 91_stat_diversity | stats | 运行 |  |
| 92_stat_differential | stats | 运行 |  |
| 93_stat_cooccurrence | stats | 运行 |  |
| 94_stat_visualization | stats | 运行 |  |
| 95a_stat_batch_correct | stats | 运行 |  |
| 95b_stat_batch_evaluate | stats | 运行 |  |
| 96_stat_ml_siamcat | stats | 运行 | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96b_pathway_activity | stats | 运行 | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96c_functional_redundancy | stats | 运行 | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 98_stat_report | stats | 运行 |  |
| 98b_bac_integration_tables | bacteria | 运行 |  |
| 98c_vir_integration_tables | virome | 运行 |  |
| 98d_fun_integration_tables | fungi | 运行 |  |
| 99a_core_microbiome | stats | 运行 |  |
| 99b_lefse | stats | 运行 | n 下限 4（本组 6 贴近下限） |
| 01_metadata_qc | stats | 运行 |  |
| 96_stat_functional | stats | 运行 | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96_functional_permanova | stats | 运行 | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96_functional_integrated | stats | 运行 | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 96_functional_cross_dimension | stats | 运行 | permanova 下限 3；SIAMCAT 3v3 未验证，如实记录 |
| 98c_bac_mge_summary | bacteria | 运行 |  |
| 98d_bac_mag_integration | bacteria | 运行 |  |
| downstream_summary | stats | 运行 |  |
| rag_build_experience | shared | 待approve/暂不跑 | 写入 mcp/chromadb_data（§10.1 禁改）；须 C1 approve且 B 线 RAG 重跑冻结后 |
| rag_refresh_literature | shared | 待approve/暂不跑 | 同 rag_build_experience（质量审核 C1） |
| 97_stat_crosscohort | stats | 待核/预期空 | 不适用：跨队列复现需第二队列，单项目演示不适用 |
| 98e_cross_domain_ani_cluster | stats | 运行 |  |
| 98f_cross_domain_orthogroup | stats | 运行 |  |
| 98g_cross_domain_correlation | stats | 运行 |  |

> ¹ 13_bac_humann3 依赖同一样本的 11 metaphlan4 profile（质量审核 E1 2026-10-04），不可先跑。

> ⚠️ 病毒 71/72（vir_dram/vir_phagcn3）与真菌 71/72（fun_kraken2/metaphlan4_euk）编号重复——分属不同维度。
