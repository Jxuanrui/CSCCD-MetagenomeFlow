# Project_demo 终版金标准（CP3 W4b，2026-10-18 冻结）

> 全部数字当日以 awk/ls 现场复核；基因目录为事故 #20 重建后值（CD-HIT 确定性复现）。

| 指标 | 冻结值 | 复核值（2026-10-18） | 来源 |
|---|---|---|---|
| gene_catalog_nucleotide | 995242 | 995242 ✓ | cdhit/nucleotide_nr.fa; 重建后 2026-10-18（事故 #20） |
| gene_catalog_protein | 995199 | 995199 ✓ | cdhit/protein_nr.fa; 同上 |
| votus_canonical | 2622 | 2622 ✓ | votu_join_stats.tsv |
| tpm_sum_per_sample | 6x1000000.0 | 1000000.0,1000000.0,1000000.0,1000000.0,1000000.0,1000000.0, ✓ | votu_table.tsv 六列 |
| drep_representatives | 128 | 128 ✓ | dereplicated_genomes/ |
| gunc_pass_fail | 81/47 | 81/47 ✓ | GUNC tsv col13 |
| core_votus_global | 1631 | 1631 ✓ | core_global.csv |
| gem_fba_mags | 9 | 9 ✓ | fba/ MAG 目录 |

## 分母与组成绑定（CP3 P0-3 补）

| 指标 | 值 | 组成/分母证据 |
|---|---|---|
| bins_total | 353 | 56+51+65+48+74+59（六样本 dastool 整合；193 semibin2+103 maxbin2+57 metabat2） |
| checkm2_filtered | 269 | comp>=50 & cont<=10 谓词行数（filtered_report.tsv） |
| drep_input_after_internal | 233 | dRep 内建 comp>=75/cont<25 再筛（Cdb.csv 233 行） |
| hq_mq_split | 96+32 | 代表名单 join quality_report 独立复算（质量审核第 5 轮核证） |
| gunc_denominator | 128 | pass 81 + fail 47 = 128 代表 |
| votu_members | 3062 | joined_contig_rows（=virus.fasta 头数=votu_id_map 行数） |
| core_votus_denominator | 2622 | 全局核心 1631 / 2,622 canonical |
| gem_denominator | 10 | 前 10 名单（gem_top10.txt）；FBA 9/10 |
| salmon_index_compat | 兼容 | 重建目录头集合与幸存 .clstr 代表集完全一致（incident20_recovery_evidence.md） |
