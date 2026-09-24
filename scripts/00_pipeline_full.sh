#!/usr/bin/env bash
# ==============================================================================
# CSCCD-MetagenomeFlow 宏基因组分析主流程
# 版本: 0.1  日期: 2026/06/03
# 作者: Xuanrui Ji
# 说明: 本脚本串联 scripts/ 下所有分析步骤，支持单样本测试和多样本并行执行
#       涵盖三大物种维度：细菌（11-41）/ 病毒（51-72）/ 真菌（71-86）
# ==============================================================================

set -euo pipefail

# ==============================================================================
# 0. 初始化 — 每次分析前必须先运行本节
# ==============================================================================

    # 激活项目环境（设置 PROJ_DIR / envs / db 等变量）
    PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source ${PROJ_DIR}/scripts/activate.sh

    # 设置工作目录（每个项目独立一个目录）
    wd=${PROJ_DIR}/Project/Project_example

    # 线程数
    t=16
    # 多样本并行任务数（建议 = CPU总数 / t，避免超载）
    j=2

    # 统计分析阶段（步骤91-98）所需的样本元数据
    # 注意：本示例 metadata.csv 只有 group/host_type 两列，属于单批次数据，
    # 因此第五阶段跳过依赖 batch 列的步骤95a/95b（批次校正），
    # 多批次/多队列项目请在自己的 metadata.csv 中补充 batch 列后再启用
    meta=${wd}/metadata.csv
    group_col=group

    # 确认样本列表（metadata.txt 第一列为 SampleID，无表头）
    # 格式示例：
    #   SRR28210342
    #   SRR28210343
    find ${wd}/data -maxdepth 1 -name "*_1.fastq.gz" -exec basename {} \; | sed 's/_1.fastq.gz//' > ${wd}/samples.txt
    echo "样本列表（共 $(wc -l < ${wd}/samples.txt) 个）:"
    cat ${wd}/samples.txt

    # 快速查看单个样本（测试用，验证数据格式）
    i=$(head -1 ${wd}/samples.txt)
    echo "测试样本: ${i}"
    zcat ${wd}/data/${i}_1.fastq.gz | head -8


# ==============================================================================
# 第一阶段：数据预处理（通用，三维度共享）
# ==============================================================================

# --- 步骤 01：质量控制（fastp）---

    # 单样本测试
    bash ${PROJ_DIR}/scripts/01_qc_fastp.sh \
        -s ${i} -t ${t} -w ${wd} -r ${PROJ_DIR}

    # 多样本并行（依赖 rush，推荐并发数 j=2-4）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/01_qc_fastp.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 结果位置：${wd}/result/fastp/{sample}/
    # 下游输入：${wd}/result/fastp/{sample}/{sample}_1.fastq.gz


# --- 步骤 02：去宿主（KneadData）---

    # 单样本测试（kneaddata 固定使用 human 数据库，不需额外参数）
    bash ${PROJ_DIR}/scripts/02_qc_kneaddata.sh \
        -s ${i} -t ${t} -w ${wd} -r ${PROJ_DIR}

    # 多样本并行
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/02_qc_kneaddata.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 结果位置：${wd}/result/kneaddata/{sample}/{sample}_{1,2}.kneaddata_raw.fastq.gz


# --- 步骤 02b：R1/R2 严格重新配对（修复 kneaddata 输出顺序错位，见脚本头注释）---

    bash ${PROJ_DIR}/scripts/02b_qc_pair_repair.sh \
        -s ${i} -w ${wd} -r ${PROJ_DIR}

    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/02b_qc_pair_repair.sh \
             -s {} -w ${wd} -r ${PROJ_DIR}"

    # 结果位置：${wd}/result/kneaddata/{sample}/
    # 下游输入：${wd}/result/kneaddata/{sample}/{sample}_1.kneaddata.fastq.gz (注意文件名含 .kneaddata 后缀)


# ==============================================================================
# 第二阶段：细菌维度分析（Bacteria，步骤 11-41）
# ==============================================================================

# --- Read-based 分类与功能（步骤 11-15）---

    # 步骤 11：MetaPhlAn4 物种组成（精确分类）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/11_bac_metaphlan4.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    # 结果：${wd}/result/metaphlan4/

    # 步骤 12：StrainPhlAn4 菌株追踪（依赖步骤 11 的 sam.bz2 输出）
    bash ${PROJ_DIR}/scripts/12_bac_strainphlan4.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}
    # 结果：${wd}/result/strainphlan4/

    # 步骤 13：HUMAnN3 功能通路定量
    cat ${wd}/samples.txt | rush -j 1 \
        "bash ${PROJ_DIR}/scripts/13_bac_humann3.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    # 结果：${wd}/result/humann3/

    # 步骤 14：Kraken2 + Bracken 物种分类
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/14_bac_kraken2.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    # 结果：${wd}/result/kraken2/

    # 步骤 15：Centrifuger 蛋白级精确分类
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/15_bac_centrifuger.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    # 结果：${wd}/result/centrifuger/


# --- Assembly + 基因预测与定量（步骤 16-20）---

    # 步骤 16：MEGAHIT 宏基因组组装
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/16_bac_megahit.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    # 结果：${wd}/result/megahit/{sample}/

    # 步骤 17：Prodigal 基因预测
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/17_bac_prodigal.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 步骤 18：CD-HIT 基因去冗余（95% ANI，汇总所有样本后运行一次）
    bash ${PROJ_DIR}/scripts/18_bac_cdhit.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}

    # 步骤 19 + 20：Salmon 构建索引 + 样本定量（TPM）
    bash ${PROJ_DIR}/scripts/19_bac_salmon_build.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/20_bac_salmon_quant.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    # 结果：${wd}/result/salmon/


# --- 功能注释（步骤 21-31，依赖步骤 17 的蛋白序列）---

    # 步骤 21：eggNOG-mapper 综合功能注释（COG/KEGG/GO/EC）
    bash ${PROJ_DIR}/scripts/21_bac_eggnog.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}

    # 步骤 22-27, 29-31：聚合注释（不依赖单个样本）
    for script in \
        22_bac_kegg 23_bac_amrfinder 24_bac_card 25_bac_dbcan \
        26_bac_vfdb 27_bac_bacmet \
        29_bac_defense_finder 30_bac_ncyc 31_bac_pcyc; do
        bash ${PROJ_DIR}/scripts/${script}.sh \
            -t ${t} -w ${wd} -r ${PROJ_DIR}
    done

    # 步骤 28：antiSMASH 次级代谢产物（per-sample，基于单样本组装）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/28_bac_antismash.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    # 结果：${wd}/result/{eggnog,kegg,amrfinder,card,dbcan,vfdb,bacmet,antismash,defense_finder,ncyc,pcyc}/


# --- MAG 挖掘（步骤 32-41，依赖步骤 16 组装结果）---

    # 步骤 32：CoverM 计算测序深度（Binning 前置）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/32_bac_coverm_depth.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 步骤 33-35：三种算法并行分箱（MetaBAT2 / MaxBin2 / SemiBin2）
    for script in 33_bac_metabat2 34_bac_maxbin2 35_bac_semibin2; do
        cat ${wd}/samples.txt | rush -j ${j} \
            "bash ${PROJ_DIR}/scripts/${script}.sh \
                 -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    done

    # 步骤 36：DAS_Tool 整合优化（依赖步骤 33-35 输出）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/36_bac_dastool.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 步骤 36b：metaWRAP post-binning reassembly（用原始 reads 重组装每个 bin）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/36b_bac_bin_reassembly.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 步骤 37：CheckM2 质量评估
    bash ${PROJ_DIR}/scripts/37_bac_checkm2.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}

    # 步骤 38：dRep 去冗余（ANI 97%）
    bash ${PROJ_DIR}/scripts/38_bac_drep.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}

    # 步骤 39-41：MAG 定量 + 分类 + 精细注释
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/39_bac_coverm_quant.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    bash ${PROJ_DIR}/scripts/40_bac_gtdbtk.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}
    bash ${PROJ_DIR}/scripts/41_bac_prokka.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}
    # 结果：${wd}/result/binning/


# ==============================================================================
# 第三阶段：病毒维度分析（Virome，步骤 51-72）
# ==============================================================================

# --- 病毒序列鉴定（步骤 51-55）---

    # 步骤 51：MEGAHIT 组装（病毒优化参数，≥1.5kb）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/51_vir_megahit.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 步骤 52-54：geNomad + VirSorter2 取交集 + CheckV 质控
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/52_vir_genomad.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/53_vir_virsorter2.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    bash ${PROJ_DIR}/scripts/54_vir_checkv_contig.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}

    # 步骤 55：Prodigal-gv 病毒蛋白预测
    bash ${PROJ_DIR}/scripts/55_vir_prodigal_gv.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}


# --- 病毒 OTU（步骤 56-60）---

    # 步骤 56-60：vOTU 聚类 + 分类 + 定量
    bash ${PROJ_DIR}/scripts/56_vir_votu_gen.sh -t ${t} -w ${wd} -r ${PROJ_DIR}
    bash ${PROJ_DIR}/scripts/57_vir_votu_genomad.sh -t ${t} -w ${wd} -r ${PROJ_DIR}
    bash ${PROJ_DIR}/scripts/58_vir_salmon_build.sh -t ${t} -w ${wd} -r ${PROJ_DIR}
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/59_vir_salmon_quant.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    bash ${PROJ_DIR}/scripts/60_vir_votu_table.sh -t ${t} -w ${wd} -r ${PROJ_DIR}
    # 结果：${wd}/result/virome/votu/


# --- 病毒 MAG（步骤 61-63）---

    bash ${PROJ_DIR}/scripts/61_vir_vmag.sh -t ${t} -w ${wd} -r ${PROJ_DIR}
    bash ${PROJ_DIR}/scripts/62_vir_checkv_mag.sh -t ${t} -w ${wd} -r ${PROJ_DIR}
    bash ${PROJ_DIR}/scripts/63_vir_coverm_quant.sh -t ${t} -w ${wd} -r ${PROJ_DIR}
    # 结果：${wd}/result/virome/vmag/


# --- 病毒功能注释（步骤 64-72）---

    # 步骤 64-69：PHAROKKA → PHOLD → VOG → BACPHLIP → iPHoP → vConTACT3
    for script in \
        64_vir_pharokka 65_vir_phold 66_vir_vog \
        67_vir_bacphlip 68_vir_iphop 69_vir_vcontact3; do
        bash ${PROJ_DIR}/scripts/${script}.sh \
            -t ${t} -w ${wd} -r ${PROJ_DIR}
    done
    # 步骤 70-72：PhaBox2 → DRAM-v → PhaGCN3（扩展工具）
    for script in 70_vir_phabox2 71_vir_dram 72_vir_phagcn3; do
        bash ${PROJ_DIR}/scripts/${script}.sh \
            -t ${t} -w ${wd} -r ${PROJ_DIR}
    done
    # 结果：${wd}/result/virome/annotation/


# ==============================================================================
# 第四阶段：真菌维度分析（Mycobiome，步骤 71-86）
# ==============================================================================

# --- Read-based 真菌分类（步骤 71-77，互补策略建议全跑）---

    # 步骤 71：Kraken2 真菌分类（基础快速）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/71_fun_kraken2_fungi.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 步骤 72：MetaPhlAn4 真菌分类（--ignore_eukaryotes 关闭）
    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/72_fun_metaphlan4_euk.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 步骤 73：从 HUMAnN4 stratified 矩阵提取真菌通路（依赖步骤 13）
    bash ${PROJ_DIR}/scripts/73_fun_humann4_fungi.sh \
        -w ${wd} -r ${PROJ_DIR}

    # 步骤 74：BLAST 比对肠道真菌参考库（47G，高精度）
    cat ${wd}/samples.txt | rush -j 1 \
        "bash ${PROJ_DIR}/scripts/74_fun_blast_gutdb.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"

    # 步骤 75-77：FunOMIC / CCMetagen / MicroFisher（互补分类策略）
    for script in 75_fun_funomics 76_fun_ccmetagen 77_fun_microfisher; do
        cat ${wd}/samples.txt | rush -j ${j} \
            "bash ${PROJ_DIR}/scripts/${script}.sh \
                 -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    done
    # 结果：${wd}/result/mycobiome/taxonomy/


# --- 真菌组装 + MAG（步骤 78-79，依赖步骤 71/72 分类输出）---

    cat ${wd}/samples.txt | rush -j ${j} \
        "bash ${PROJ_DIR}/scripts/78_fun_megahit.sh \
             -s {} -t ${t} -w ${wd} -r ${PROJ_DIR}"
    bash ${PROJ_DIR}/scripts/79_fun_eukfinder.sh \
        -t ${t} -w ${wd} -r ${PROJ_DIR}


# --- 真菌功能注释（步骤 80-86）---

    bash ${PROJ_DIR}/scripts/80_fun_prodigal.sh -t ${t} -w ${wd} -r ${PROJ_DIR}
    for script in \
        81_fun_eggnog 82_fun_kegg 83_fun_dbcan \
        84_fun_vfdb 85_fun_amr 86_fun_merops; do
        bash ${PROJ_DIR}/scripts/${script}.sh \
            -t ${t} -w ${wd} -r ${PROJ_DIR}
    done
    # 结果：${wd}/result/mycobiome/annotation/


# ==============================================================================
# 第五阶段：统计分析（步骤 91-98，跨维度）
# ==============================================================================

    # 步骤 91：Alpha/Beta 多样性
    bash ${PROJ_DIR}/scripts/91_stat_diversity.sh \
        -w ${wd} -r ${PROJ_DIR} -t ${t} -m ${meta}

    # 步骤 92：差异分析（LEfSe/ANCOM-BC2/DESeq2/edgeR/MaAsLin2）
    bash ${PROJ_DIR}/scripts/92_stat_differential.sh \
        -w ${wd} -r ${PROJ_DIR} -t ${t} -m ${meta} -g ${group_col}

    # 步骤 93：共现网络（FastSpar/SparCC）
    bash ${PROJ_DIR}/scripts/93_stat_cooccurrence.sh \
        -w ${wd} -r ${PROJ_DIR} -t ${t} -m ${meta} -g ${group_col}

    # 步骤 94：统一可视化（热图/PCoA/桑基图/UpSet）
    bash ${PROJ_DIR}/scripts/94_stat_visualization.sh \
        -w ${wd} -r ${PROJ_DIR} -m ${meta}

    # 步骤 95a + 95b：多中心批次校正 Top10 评估（需审核后手动选择最优方法）
    # 注意：需要 metadata.csv 含 batch 列（多队列/多批次数据），
    # 本示例数据单批次，跳过；多批次项目请取消注释并设置 batch_col
    # batch_col=batch
    # bash ${PROJ_DIR}/scripts/95a_stat_batch_correct.sh \
    #     -w ${wd} -r ${PROJ_DIR} -t ${t} -m ${meta} -b ${batch_col} -g ${group_col}
    # → 查看 ${wd}/result/statistics/batch_eval.md 后手动确认方法
    # bash ${PROJ_DIR}/scripts/95b_stat_batch_evaluate.sh \
    #     -w ${wd} -r ${PROJ_DIR} -m ${meta} -b ${batch_col} -g ${group_col}

    # 步骤 96：SIAMCAT ML 筛选 + ROC 评估（Top10 特征 + AUC 对比）
    bash ${PROJ_DIR}/scripts/96_stat_ml_siamcat.sh \
        -w ${wd} -r ${PROJ_DIR} -t ${t} -m ${meta} -g ${group_col}

    # 步骤 97：跨队列一致性验证（依赖步骤 96 输出；本示例仅单队列，--source local 默认用 ${wd} 自身作队列）
    bash ${PROJ_DIR}/scripts/97_stat_crosscohort.sh \
        -w ${wd} -r ${PROJ_DIR} -m ${meta} -g ${group_col}

    # 步骤 98：生成分析结果快照报告（MD 文档，带时间戳）
    bash ${PROJ_DIR}/scripts/98_stat_report.sh \
        -w ${wd} -r ${PROJ_DIR}
    echo "报告位置: ${wd}/result/report_$(date +%Y%m%d).md"
