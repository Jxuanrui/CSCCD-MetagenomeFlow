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
