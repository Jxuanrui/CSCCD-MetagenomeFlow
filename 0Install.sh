#!/usr/bin/env bash
# ==============================================================================
# CSCCD-MetagenomeFlow 软件和数据库安装脚本
# 版本: 1.0
# 平台: Linux x86_64 ubuntu22.04
# 作者：Xuanrui Ji
# ------------------------------------------------------------------------------
# 安装进度（已完成节在此记录，下次从 ✗ 处继续）
#   [✓] §0   初始化（Miniforge3 + 通道 + activate.sh + Rscript）测试通过
#   [✓] §1.1 fastp 0.22.0 测试通过
#   [✓] §1.2 kneaddata v0.12.4 + bowtie2 测试通过
#   [✓] §1.3 KneadData 数据库（human/mouse/rat，各 6 个 bt2）测试通过
#   [✓] §2.1 humann v3.9 + MetaPhlAn4 v4.2.4 + diamond 2.0.15 测试通过（端到端输出 3 个 tsv）
#   [✓] §2.2 HUMAnN4 数据库（chocophlan 12773 + uniref 34G + mapping 20）测试通过
#   [✓] §2.3 MetaPhlAn4 数据库（mpa_vOct22_CHOCOPhlAnSGB_202212，已识别）测试通过
#   [✓] §2.4 LEfSe（biobakery channel）测试通过
#   [✓] §2.5 Kraken2 2.1.3 + Bracken 3.1 测试通过
#   [✓] §2.6 Kraken2 数据库（pluspf_20240112，hash 77G，classify 正常）测试通过
#   [✓] §3.1 assembly（MEGAHIT 1.2.9 / SPAdes 3.15.5 / QUAST 5.0.2 / Prodigal 2.6.3 / CD-HIT 4.8.1 / salmon 1.2.0）测试通过（MEGAHIT 端到端）
#   [✓] §3.2 eggNOG-mapper 2.1.13（pip 安装，Python 3.9）测试通过
#   [✓] §3.3 eggNOG 数据库（5.0.2，39G+8.7G，--data_dir 参数指定，无软链接）测试通过（DB version 5.0.2 识别）
#   [✓] §4.1 MetaWRAP 1.3.2（--no-channel-priority 安装）测试通过
#   [✓] §4.2 CheckM 数据库（10 个文件，~/.checkm/DATA_CONFIG 配置）测试通过
#   [✓] §4.3 dRep 3.6.2 + CheckM 1.2.5（pip 安装 + networkx）测试通过
#   [✓] §4.4 CoverM 0.7.0 测试通过
#   [✓] §4.5 GTDB-Tk 2.5.2（tqdm=4.66.4 先固定）测试通过
#   [✓] §4.6 GTDB-Tk 数据库（160 GB，13 个目录/文件）测试通过
#   [✓] §4.7 CheckM2（Python 3.8 + scikit-learn=0.23.2 + numpy<1.24）测试通过
#   [✓] §4.8 CheckM2 数据库（uniref100.KO.1.dmnd 2.9 GB）测试通过
#   [✓] §5.1 VIBRANT 1.2.1（envs/vibrant）+ CheckV（envs/checkv）测试通过（zlib冲突已拆分独立环境）
#   [✓] §5.2 AMRFinderPlus 3.10.1 + RGI 4.0.3 + CARD 数据库 测试通过
#   [✓] §5.3 dbCAN3 + 数据库（3.5 GB）测试通过
#   [✓] §5.4 StrainPhlAn4 4.2.4（复用 humann4 环境）测试通过（补装 samtools/mafft/fasttree）
#   [✓] §5.5 antiSMASH 7.1.0（--no-channel-priority 安装）测试通过
#   [✓] §5.6 FastSpar（SparCC）测试通过
#   [✓] §6.2 CRAN 包（vegan 2.7.5 / ggplot2 4.0.3 / dplyr 等 16 个）测试通过
#   [✓] §6.3 Bioconductor 包（phyloseq / DESeq2 / edgeR / microbiome / treeio / Maaslin2）测试通过
#   [✓] §6.4 ANCOMBC 2.12.0 + ggtree 4.0.4（conda bioconda 安装）测试通过
#   [✓] §6.5 统计 R 包 (SIAMCAT / curatedMGD / MMUPHin / ConQuR / MBECS / sva / BatchQC) 测试通过
#   [✓] §7.1 assembly 环境扩充（centrifuger 1.0.5 / mmseqs2 13.45 / seqtk 1.4）测试通过
#   [✓] §7.3 genomad 1.12.0（独立环境，--no-channel-priority）测试通过
#   [✓] §7.5 功能注释数据库（vfdb/bacmet/merops/sarg/phi/mvirdb/tcdb/ncyc/pcyc/amrfinder/genomad）测试通过
#   [✓] §7.4 centrifuger 数据库（166 GB，7 个文件）测试通过
#   [✓] §7.5 KEGG 数据库（48 GB）测试通过
#   [✓] §8.1 MetaBAT2 2.12.1 + MaxBin2 2.2.6（追加进 metawrap）+ SemiBin2 1.5.0 测试通过
#   [✓] §8.2 DAS_Tool 1.1.7（独立环境） 测试通过
#   [✓] §8.3 Bakta 1.12.0（独立环境 + 数据库 3.8 GB） 测试通过
#   [✓] §8.4 Defense-Finder 3.0.0（独立环境 + 数据库 320 MB） 测试通过
#   [✓] §8.5 MobileOG 数据库（19 GB，diamond 搜索） 测试通过
#   [✓] §8.6 CCyc 12G + MCyc 638M + SCyc 642M 数据库（各含1个子目录） 测试通过
#   [✓] §8.7 VIBRANT 数据库（11G，KEGG 9995 + VOG 19182 + Pfam，hmmpress 完成） 测试通过
#   [✓] §8.8 antiSMASH 数据库（从 Apptainer 项目解压，9.4 GB） 测试通过（10 个模块目录）
#   [✓] §8.9 Snakemake 9.22.0（snakemake-minimal，miniforge3 base）                  测试通过（dry-run DAG 构建正常）
#   [✓] §10.1 VirSorter2 2.2.4（独立环境 + 数据库） 已安装
#   [✓] §10.2 vclust 1.3.1（独立环境，无专用数据库） 已安装
#   [✓] §10.3 vRhyme 1.1.0（独立环境，无专用数据库） 已安装
#   [✓] §10.4 PHAROKKA 1.9.1（独立环境 + 数据库 1.9G，命令：pharokka.py） 已安装
#   [✓] §10.5 PHOLD 1.2.5（独立环境 + 数据库） 已安装
#   [✓] §10.6 BACPHLIP 0.9.6（独立环境 + hmmer 3.4） 已安装
#   [✓] §10.7 iPHoP 1.4.2（独立环境 + 数据库软链接 → Virus_Apptainer_pipline） 已安装
#   [✓] §10.8 vConTACT3 3.1.6（独立环境 + 数据库 v230） 已安装
#   [✓] §10.9 CheckV 1.1.1（数据库 genome_db + hmm_db 就绪） 已安装
#   [✓] §10.10 VOG 数据库（VOG.hmm 已解压，vog.dmnd 就绪，vog_annotations.tsv） 已安装
#   [✓] §14.1 PhaBox2 2.1.12（envs/phabox2，db/phabox2_db/ 1.7G） 已安装测试通过（70_vir_phabox2.sh）
#   [✓] §14.2 PhaGCN3 3.1（envs/phagcn3，db/phagcn3_db/ 275M） 已安装测试通过（72_vir_phagcn3.sh）
#   [✓] §14.3 DRAM 1.5.0（envs/dram，db/dram_db/ rsync 完成，180G） 安装完成，测试通过（71_vir_dram.sh）
#   [✓] §11.4 FunOMIC（db/funomic/P + db/funomic/T；envs/funomic 已创建） 已安装（GitHub 包不可用，脚本走 DIAMOND 回退）
#   [✓] §11.6 WGS 融入模块（mlst 2.11 + roary 3.12.0 in envs/prokaWGS；snippy 4.0.2 in envs/snippy） 已安装
#   [✓] §12.1 CGF catalog 760 真菌基因组（db/cgf/genomes/） 已下载（709条，51条NCBI已撤回）
#   [✓] §12.2 MetaEuk 真核宏基因组基因预测（envs/metaeuk） 已安装
#   [✓] §12.3 PHF 肠道真菌数据库（db/gut_fungi_db/，760基因组基因集） 已部署（Yan et al. 2024 Cell 187，Bowtie2索引构建中）
#   [✓] §12.4 PHF 流程脚本（74a/74e/74f，Bowtie2+Singular/Escrow） 已创建（论文原方法，替代原74b/74c/74d DIAMOND方案）
#   [✓] §9   MCP / RAG 服务   ← 最终步骤 已完成
#   [✓] §15.1 UniProt Swiss-Prot（243 MB .dmnd + blast/mmseqs 索引，已从参考项目复制） 就绪
#   [✓] §15.2 Pfam-A HMM 数据库（~2.4 GB，全部 hmmpress 文件，已从参考项目复制） 就绪
#   [✓] §15.3 MGE 数据库组（ISfinder/ICEberg/integrall/transposase-db，已从参考项目复制） 就绪
#   [✗] §15.4 FeGenie（铁代谢基因预测）— 见下方 Apptainer/conda 安装说明
#   [✗] §15.5 recombinase-kit（重组酶注释）— 见下方 Apptainer/conda 安装说明
#   [✓] §15.6 PlasmidFinder 2.1.6（envs/plasmidfinder，DB 内置，exit 0 验证通过） 已安装
# ==============================================================================


# ==============================================================================
# 0. 初始化  ——  每次安装前必须先运行本节  [✓]
# ==============================================================================

# --- 0.1 项目路径 ---

    # 自动获取脚本所在目录作为项目根目录
    PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    soft=${PROJ_DIR}/miniforge3   # Miniforge3 安装目录
    envs=${PROJ_DIR}/envs         # 各工具 conda 独立环境目录
    db=${PROJ_DIR}/db             # 数据库目录
    tools=${PROJ_DIR}/tools       # 辅助脚本目录

    # --- 安装模式开关 ---
    # online（默认）：所有数据库节走官方源下载（原各节注释的"官方地址"块自动执行）
    # bank：走 DB_BANK/SIBLING_DB 本地数据库银行快装（原"方法0"复制块，行为与历史版本一致）
    # 用法：bash 0Install.sh online | bash 0Install.sh bank | INSTALL_MODE=bank bash 0Install.sh
    case "${1:-}" in
        online|bank) INSTALL_MODE="${1}" ;;
        *) : "${INSTALL_MODE:=online}" ;;
    esac
    case "${INSTALL_MODE}" in
        online) echo "[INFO] install mode: online (official sources)" ;;
        bank)   echo "[INFO] install mode: bank (local database bank)" ;;
        *) echo "[WARN] 未知 INSTALL_MODE='${INSTALL_MODE}'，回退为 online"; INSTALL_MODE=online ;;
    esac

    # 本地数据库银行（bank 模式"方法0"快装复制源）——迁移新服务器时用环境变量覆盖：
    #   INSTALL_MODE=bank DB_BANK=/path/to/dbbank SIBLING_DB=/path/to/sibling/db bash 0Install.sh
    # online 模式不使用银行；bank 模式下银行不存在时，各节 方法0 cp 会失败。
    : "${DB_BANK:=/data/mydirectory/db}"
    : "${SIBLING_DB:=$HOME/Course/Metagenomics_Apptainer_pipline/db}"
    if [ "${INSTALL_MODE}" = "bank" ]; then
        [ -d "${DB_BANK}" ]     || echo "[WARN] DB_BANK 不存在: ${DB_BANK} —— 方法0 本地快装将失败，请覆盖 DB_BANK 或改用 INSTALL_MODE=online"
        [ -d "${SIBLING_DB}" ]  || echo "[WARN] SIBLING_DB 不存在: ${SIBLING_DB} —— 方法0 本地快装将失败，请覆盖 SIBLING_DB 或改用 INSTALL_MODE=online"
    fi

    mkdir -p ${envs} ${db} ${tools}
    echo "项目根目录: ${PROJ_DIR}"


# --- 0.2 Miniforge3 安装（安装在项目目录内，不修改 ~/.bashrc） ---

    # 若已存在则跳过，否则从镜像下载安装
    if [ -f "${soft}/bin/conda" ]; then
        echo "Miniforge3 已存在: ${soft}"
    else
        wget http://mirror.xiyoucloud.pro:63332/static/Miniforge3-25.3.1-0-Linux-x86_64.sh \
            -O ${PROJ_DIR}/Miniforge-Linux-x86_64.sh
        bash ${PROJ_DIR}/Miniforge-Linux-x86_64.sh -b -f -p ${soft}
        rm -f ${PROJ_DIR}/Miniforge-Linux-x86_64.sh
        echo "Miniforge3 安装完成"
    fi

    # 激活 conda（仅当前会话，不影响系统环境）
    source ${soft}/etc/profile.d/conda.sh
    conda -V


# --- 0.3 通道和求解器配置 ---

    # 设置 conda-forge 优先，bioconda 其次
    conda config --add channels bioconda
    conda config --add channels conda-forge
    conda config --set channel_priority strict

    # 安装 libmamba 加速依赖解析（比默认求解器快 5-10 倍）
    conda install -y -n base conda-libmamba-solver -c conda-forge
    conda config --set solver libmamba

    conda config --show channels


# --- 0.4 会话激活脚本 ---

    # 激活脚本存放于 scripts/activate.sh，赋予执行权限
    # 每次分析前执行：source ${PROJ_DIR}/scripts/activate.sh
    chmod +x ${PROJ_DIR}/scripts/activate.sh
    echo "会话激活脚本: ${PROJ_DIR}/scripts/activate.sh"


# --- 0.5 R 环境检查（所有 R 脚本均通过 Rscript 命令行执行） ---

    if command -v Rscript &>/dev/null; then
        echo "Rscript 已就绪: $(Rscript --version 2>&1)"
    else
        echo "系统未找到 Rscript，通过 conda 安装..."
        conda install -y -n base r-base -c conda-forge
    fi


# ==============================================================================
# 1. 数据预处理工具  [✓]
# ==============================================================================

# --- 1.1 fastp 质量控制  [✓ fastp 0.22.0] ---

    # 创建独立 conda 环境并安装 fastp
    conda create --prefix ${envs}/fastp -y
    conda install --prefix ${envs}/fastp -y fastp -c bioconda -c conda-forge
    conda run --prefix ${envs}/fastp fastp --version


# --- 1.2 KneadData 去宿主  [✓ kneaddata v0.12.4] ---

    # 创建独立 conda 环境，同步安装依赖工具 bowtie2、trimmomatic
    conda create --prefix ${envs}/kneaddata -y
    conda install --prefix ${envs}/kneaddata -y \
        kneaddata bowtie2 trimmomatic -c bioconda -c conda-forge
    conda run --prefix ${envs}/kneaddata kneaddata --version



# --- 1.3 KneadData 数据库：人类、小鼠、大鼠参考基因组  [✓ 各 6 个 bt2 文件] ---

    # 创建数据库目录
    mkdir -p ${db}/kneaddata/{human,mouse,rat}

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从百度云链接进行下载配置（bank 模式）
        # ----
        cp ${DB_BANK}/kneaddata/human/* ${db}/kneaddata/human/
        cp ${DB_BANK}/kneaddata/mouse/* ${db}/kneaddata/mouse/
        cp ${DB_BANK}/kneaddata/rat/*   ${db}/kneaddata/rat/
    else
        # ----
        # 方法2：官方地址下载（online 模式）
        # ----
        # 人类基因组 hg37（Huttenhower Lab）
        conda run --prefix ${envs}/kneaddata kneaddata_database --download human_genome bowtie2 ${db}/kneaddata/human

        # 人类基因组 hg39/T2T（更新版本，3.6 GB）
        wget -c https://huttenhower.sph.harvard.edu/kneadData_databases/Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz \
            -O ${db}/kneaddata/human/Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz
        tar xvzf ${db}/kneaddata/human/Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz \
            -C ${db}/kneaddata/human/ && rm -f ${db}/kneaddata/human/*.tar.gz

        # 小鼠基因组 C57BL/6NJ（官方，2.83 GB）
        wget -c http://huttenhower.sph.harvard.edu/kneadData_databases/mouse_C57BL_6NJ_Bowtie2_v0.1.tar.gz \
            -O ${db}/kneaddata/mouse/mouse_C57BL_6NJ_Bowtie2_v0.1.tar.gz
        tar xvzf ${db}/kneaddata/mouse/mouse_C57BL_6NJ_Bowtie2_v0.1.tar.gz \
            -C ${db}/kneaddata/mouse/ && rm -f ${db}/kneaddata/mouse/*.tar.gz

        # 大鼠基因组 Rnor_6.0（bowtie2 index，S3）
        wget -c https://genome-idx.s3.amazonaws.com/bt/Rnor_6.0.zip \
            -O ${db}/kneaddata/rat/Rnor_6.0.zip
        unzip ${db}/kneaddata/rat/Rnor_6.0.zip -d ${db}/kneaddata/rat/ \
            && rm -f ${db}/kneaddata/rat/Rnor_6.0.zip
    fi

    # ----
    # 方法1：NMDC 国内镜像下载（备用，国内服务器较快，按需解注释）
    # ----
    # 人类基因组 hg37（3.44 GB）
    # wget -c ftp://download.nmdc.cn/tools/meta/kneaddata/human_genome/Homo_sapiens_hg37_and_human_contamination_Bowtie2_v0.1.tar.gz \
    #     -O ${db}/kneaddata/human/Homo_sapiens_hg37_Bowtie2_v0.1.tar.gz
    # tar xvzf ${db}/kneaddata/human/Homo_sapiens_hg37_Bowtie2_v0.1.tar.gz \
    #     -C ${db}/kneaddata/human/ && rm -f ${db}/kneaddata/human/*.tar.gz

    # 小鼠基因组 C57BL/6NJ（2.83 GB）
    # wget -c ftp://download.nmdc.cn/tools/meta/kneaddata/mouse/Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz \
    #     -O ${db}/kneaddata/mouse/mouse_C57BL_6NJ_Bowtie2_v0.1.tar.gz
    # tar xvzf ${db}/kneaddata/mouse/mouse_C57BL_6NJ_Bowtie2_v0.1.tar.gz \
    #     -C ${db}/kneaddata/mouse/ && rm -f ${db}/kneaddata/mouse/*.tar.gz

    echo "KneadData 参考数据库就绪: ${db}/kneaddata/"
    ls ${db}/kneaddata/human/ ${db}/kneaddata/mouse/ ${db}/kneaddata/rat/


# ==============================================================================
# 2. 基于读长的分析工具
# ==============================================================================

# --- 2.1 HUMAnN4 + MetaPhlAn4  [✓ humann v3.9 / MetaPhlAn4 v4.2.4 / diamond 2.0.15] ---

    # 创建独立 conda 环境（Python 3.9）
    conda create --prefix ${envs}/humann4 python=3.9 -y

    # 安装 bowtie2、diamond 依赖
    conda install --prefix ${envs}/humann4 -y \
        bowtie2 diamond -c bioconda -c conda-forge

    # pip 安装 humann 和 metaphlan（biobakery channel 版本与 Python 3.9 不兼容）
    # 版本固定为本仓库实测通过版本（docs/manifests/envs/humann4.txt）
    conda run --prefix ${envs}/humann4 pip install humann==3.9
    conda run --prefix ${envs}/humann4 pip install metaphlan==4.2.4

    # 安装 StrainPhlAn4 运行时必须依赖（ 补充，mamba 求解更稳定）
    # 注意：不能用 conda install ncurses=5（会破坏 python 3.9 环境），samtools 必须 >=1.15
    mamba install --prefix ${envs}/humann4 -y \
        "samtools=1.15.1" mafft fasttree \
        -c bioconda -c conda-forge

    # 版本验证
    conda run --prefix ${envs}/humann4 humann --version
    conda run --prefix ${envs}/humann4 metaphlan --version
    conda run --prefix ${envs}/humann4 diamond --version
    conda run --prefix ${envs}/humann4 samtools --version 2>&1 | head -1
    conda run --prefix ${envs}/humann4 mafft --version 2>&1
    conda run --prefix ${envs}/humann4 FastTree -help 2>&1 | head -1


# --- 2.2 HUMAnN4 数据库  [✓ chocophlan 12773 / uniref90 34G / mapping 20 / config 已写入] ---

    # 注：服务器现有 humann3 数据库（chocophlan v201901 + uniref90），humann v3.9 可直接使用
    mkdir -p ${db}/humann4/{chocophlan,uniref,utility_mapping}

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（最快，bank 模式）
        # ----
        cp -r ${DB_BANK}/humann3/chocophlan/*    ${db}/humann4/chocophlan/
        cp -r ${DB_BANK}/humann3/uniref/*        ${db}/humann4/uniref/
        cp -r ${DB_BANK}/humann3/utility_mapping/* ${db}/humann4/utility_mapping/
    else
        # ----
        # 方法1：官方下载（humann v3.9 兼容版本，online 模式）
        # ----
        # chocophlan 全库（42 GB）
        wget -c http://huttenhower.sph.harvard.edu/humann_data/chocophlan/chocophlan.v201901_v31.tar.gz \
            -O ${db}/humann4/chocophlan.tar.gz
        tar xvzf ${db}/humann4/chocophlan.tar.gz -C ${db}/humann4/chocophlan/ \
            && rm -f ${db}/humann4/chocophlan.tar.gz
        # uniref90 diamond 索引（893 MB）
        wget -c http://huttenhower.sph.harvard.edu/humann_data/uniprot/uniref_annotated/uniref90_annotated_v201901b.tar.gz \
            -O ${db}/humann4/uniref90.tar.gz
        tar xvzf ${db}/humann4/uniref90.tar.gz -C ${db}/humann4/uniref/ \
            && rm -f ${db}/humann4/uniref90.tar.gz
        # utility_mapping（2.7 GB）
        wget -c http://huttenhower.sph.harvard.edu/humann_data/full_mapping_v201901b.tar.gz \
            -O ${db}/humann4/mapping.tar.gz
        tar xvzf ${db}/humann4/mapping.tar.gz -C ${db}/humann4/utility_mapping/ \
            && rm -f ${db}/humann4/mapping.tar.gz
    fi

    # ----
    # 方法2：NMDC 国内镜像（备用，按需解注释）
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/humann3/chocophlan.v201901_v31.tar.gz \
    #     -O ${db}/humann4/chocophlan.tar.gz
    # tar xvzf ${db}/humann4/chocophlan.tar.gz -C ${db}/humann4/chocophlan/ \
    #     && rm -f ${db}/humann4/chocophlan.tar.gz
    # wget -c ftp://download.nmdc.cn/tools/meta/humann3/uniref90_annotated_v201901b.tar.gz \
    #     -O ${db}/humann4/uniref90.tar.gz
    # tar xvzf ${db}/humann4/uniref90.tar.gz -C ${db}/humann4/uniref/ \
    #     && rm -f ${db}/humann4/uniref90.tar.gz
    # wget -c ftp://download.nmdc.cn/tools/meta/humann3/full_mapping_v201901b.tar.gz \
    #     -O ${db}/humann4/mapping.tar.gz
    # tar xvzf ${db}/humann4/mapping.tar.gz -C ${db}/humann4/utility_mapping/ \
    #     && rm -f ${db}/humann4/mapping.tar.gz

    # 配置数据库路径
    conda run --prefix ${envs}/humann4 humann_config --update database_folders nucleotide ${db}/humann4/chocophlan
    conda run --prefix ${envs}/humann4 humann_config --update database_folders protein ${db}/humann4/uniref
    conda run --prefix ${envs}/humann4 humann_config --update database_folders utility_mapping ${db}/humann4/utility_mapping
    conda run --prefix ${envs}/humann4 humann_config --print
    echo "HUMAnN4 数据库就绪: ${db}/humann4/"


# --- 2.3 MetaPhlAn4 数据库  [✓ mpa_vOct22_CHOCOPhlAnSGB_202212 / metaphlan --version 识别正常] ---

    # 注：服务器现有 mpa_vOct22_CHOCOPhlAnSGB_202212 版本
    mkdir -p ${db}/metaphlan4

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（最快，bank 模式）
        # ----
        cp ${DB_BANK}/metaphlan4/* ${db}/metaphlan4/
    else
        # ----
        # 方法2：官方下载（online 模式）
        # ----
        wget -c http://cmprod1.cibio.unitn.it/biobakery4/metaphlan_databases/mpa_vOct22_CHOCOPhlAnSGB_202403.tar \
            -O ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
        tar xvf ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar -C ${db}/metaphlan4/ \
            && rm -f ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
        wget -c http://cmprod1.cibio.unitn.it/biobakery4/metaphlan_databases/bowtie2_indexes/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar \
            -O ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar
        tar xvf ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar -C ${db}/metaphlan4/ \
            && rm -f ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar
    fi

    # ----
    # 方法1：NMDC 国内镜像（备用，202403 最新版，按需解注释）
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar \
    #     -O ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
    # tar xvf ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar -C ${db}/metaphlan4/ \
    #     && rm -f ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
    # wget -c ftp://download.nmdc.cn/tools/meta/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar.gz \
    #     -O ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar.gz
    # tar xvzf ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar.gz -C ${db}/metaphlan4/ \
    #     && rm -f ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar.gz

    echo "MetaPhlAn4 数据库就绪: ${db}/metaphlan4/"


# --- 2.4 LEfSe 差异分析  [✓ biobakery channel] ---

    # 使用 biobakery channel 创建环境（直接解决依赖）
    conda create --prefix ${envs}/lefse -y -c biobakery lefse
    conda run --prefix ${envs}/lefse lefse_run.py --version


# --- 2.5 Kraken2 + Bracken 物种注释  [✓ Kraken2 2.1.3 / Bracken 3.1] ---

    # 创建独立 conda 环境
    conda create --prefix ${envs}/kraken2 -y
    conda install --prefix ${envs}/kraken2 -y kraken2 bracken -c bioconda -c conda-forge
    conda run --prefix ${envs}/kraken2 kraken2 --version
    conda run --prefix ${envs}/kraken2 conda list | grep bracken


# --- 2.6 Kraken2 数据库  [✓ pluspf_20240112 / hash 77G / classify 正常] ---

    # 注：服务器现有 k2_pluspf_20240112（pluspf 完整版）
    mkdir -p ${db}/kraken2/{pluspf,pluspf16g}

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（最快，bank 模式）
        # ----
        cp ${DB_BANK}/kraken2/pluspf/* ${db}/kraken2/pluspf/
    else
        # ----
        # 方法1：官方 S3 下载（online 模式）
        # ----
        v=20251015
        # PlusPF-16（压缩 11.2 GB，解压 14.9 GB，适合内存 ≤ 32 GB）
        wget -c https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_16_GB_${v}.tar.gz \
            -O ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz
        tar xvzf ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz -C ${db}/kraken2/pluspf16g/ \
            && rm -f ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz
        # PlusPF 完整版（压缩 77.5 GB，解压 100.6 GB，适合内存 ≥ 128 GB）
        wget -c https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_${v}.tar.gz \
            -O ${db}/kraken2/k2_pluspf_${v}.tar.gz
        tar xvzf ${db}/kraken2/k2_pluspf_${v}.tar.gz -C ${db}/kraken2/pluspf/ \
            && rm -f ${db}/kraken2/k2_pluspf_${v}.tar.gz
    fi

    # ----
    # 方法2：NMDC 国内镜像（备用，按需解注释，v 取值见方法1）
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/kraken2/k2_pluspf_16_GB_${v}.tar.gz \
    #     -O ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz
    # tar xvzf ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz -C ${db}/kraken2/pluspf16g/ \
    #     && rm -f ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz

    echo "Kraken2 数据库就绪: ${db}/kraken2/"
    ls ${db}/kraken2/pluspf/ | head -5


# ==============================================================================
# 3. 组装分析工具  [✓]
# ==============================================================================

# --- 3.1 组装和定量工具  [✓ MEGAHIT 1.2.9 / SPAdes 3.15.5 / QUAST 5.0.2 / Prodigal 2.6.3 / CD-HIT 4.8.1 / salmon 1.2.0] ---

    # 所有组装相关工具合并在一个环境内
    conda create --prefix ${envs}/assembly -y
    conda install --prefix ${envs}/assembly -y \
        megahit spades quast prodigal cd-hit emboss salmon \
        -c bioconda -c conda-forge

    # 版本验证
    conda run --prefix ${envs}/assembly megahit --version
    conda run --prefix ${envs}/assembly metaspades.py --version
    conda run --prefix ${envs}/assembly metaquast.py --version
    conda run --prefix ${envs}/assembly conda list | grep prodigal
    conda run --prefix ${envs}/assembly cd-hit -v 2>&1 | grep version
    conda run --prefix ${envs}/assembly salmon --version


# --- 3.2 eggNOG 功能注释  [✓ emapper 2.1.13 / Python 3.9 / pip 安装] ---

    # 创建独立 conda 环境（Python 3.9），通过 pip 安装（conda channel 版本绑定 Python 2.7）
    conda create --prefix ${envs}/eggnog python=3.9 -y
    conda run --prefix ${envs}/eggnog pip install eggnog-mapper==2.1.13
    conda run --prefix ${envs}/eggnog emapper.py --data_dir ${db}/eggnog --version 2>&1 | grep "Installed eggNOG DB"


# --- 3.3 eggNOG 数据库  [✓ 5.0.2 / eggnog.db 39G / eggnog_proteins.dmnd 8.7G / --data_dir 参数指定] ---

    mkdir -p ${db}/eggnog

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（最快，约 59 GB，bank 模式）
        # ----
        cp ${DB_BANK}/eggnog/eggnog.db                    ${db}/eggnog/
        cp ${DB_BANK}/eggnog/eggnog_proteins.dmnd          ${db}/eggnog/
        cp ${DB_BANK}/eggnog/eggnog.taxa.db                ${db}/eggnog/
        cp ${DB_BANK}/eggnog/eggnog.taxa.db.traverse.pkl   ${db}/eggnog/
    else
        # ----
        # 方法2：官方脚本下载（eggnog.db 6.3G + eggnog_proteins.dmnd 4.9G，解压后约 48 GB，online 模式）
        # ----
        conda run --prefix ${envs}/eggnog \
            download_eggnog_data.py -y -f --data_dir ${db}/eggnog
    fi

    # ----
    # 方法1：NMDC 国内镜像（备用，按需解注释）
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/eggnog/eggnog.tar.gz \
    #     -O ${db}/eggnog/eggnog.tar.gz
    # tar xvzf ${db}/eggnog/eggnog.tar.gz -C ${db}/eggnog/ \
    #     && rm -f ${db}/eggnog/eggnog.tar.gz

    # 数据库通过 --data_dir 参数在运行时指定，无需软链接或复制至 site-packages
    # 使用示例：
    #   conda run --prefix ${envs}/eggnog emapper.py \
    #       --data_dir ${db}/eggnog \
    #       -i proteins.faa --output result
    echo "eggNOG 数据库就绪: ${db}/eggnog/"
    ls -lh ${db}/eggnog/


# ==============================================================================
# ← 下次从此处开始：§4 Binning 工具
# ==============================================================================

# ==============================================================================
# 4. Binning 工具  [✓]
# ==============================================================================

# --- 4.1 MetaWRAP 分箱  [✓ MetaWRAP 1.3.2] ---

    # 注：metawrap-mg 依赖 maxbin2=2.2.6，需要 --no-channel-priority 绕过 strict 限制
    conda create --prefix ${envs}/metawrap -y
    conda install --prefix ${envs}/metawrap -y \
        metawrap-mg=1.3.2 maxbin2=2.2.6 \
        -c ursky -c bioconda -c conda-forge \
        --no-channel-priority
    conda run --prefix ${envs}/metawrap metawrap -h 2>&1 | head -3


# --- 4.2 CheckM 数据库  [✓ 10 个文件 / ~/.checkm/DATA_CONFIG 配置] ---

    mkdir -p ${db}/checkm

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（1.7 GB，bank 模式）
        # ----
        cp -r ${DB_BANK}/checkm/* ${db}/checkm/
    else
        # ----
        # 方法1：官方下载（275 MB 压缩，解压 1.4 GB，online 模式）
        # ----
        wget -c https://data.ace.uq.edu.au/public/CheckM_databases/checkm_data_2015_01_16.tar.gz \
            -O ${db}/checkm/checkm_data_2015_01_16.tar.gz
        tar xvf ${db}/checkm/checkm_data_2015_01_16.tar.gz -C ${db}/checkm/ \
            && rm -f ${db}/checkm/checkm_data_2015_01_16.tar.gz
    fi

    # ----
    # 方法2：NMDC 镜像（备用，按需解注释）
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/checkm/checkm_data_2015_01_16.tar.gz \
    #     -O ${db}/checkm/checkm_data_2015_01_16.tar.gz
    # tar xvf ${db}/checkm/checkm_data_2015_01_16.tar.gz -C ${db}/checkm/ \
    #     && rm -f ${db}/checkm/checkm_data_2015_01_16.tar.gz

    # CheckM 数据库路径配置脚本（迁移到新服务器后执行一次，避免硬编码 ~/.checkm）
    mkdir -p ${PROJ_DIR}/scripts
    cat > ${PROJ_DIR}/scripts/checkm_config.sh << 'CHECKM_CFG'
#!/usr/bin/env bash
# CheckM 数据库路径配置 — 由 0Install.sh 生成
PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p ~/.checkm
echo "dataRoot: ${PROJ_DIR}/db/checkm" > ~/.checkm/DATA_CONFIG
echo "manifestType: CheckM" >> ~/.checkm/DATA_CONFIG
echo "CheckM 数据库路径已配置: ${PROJ_DIR}/db/checkm"
CHECKM_CFG
    chmod +x ${PROJ_DIR}/scripts/checkm_config.sh
    bash ${PROJ_DIR}/scripts/checkm_config.sh
    echo "CheckM 数据库就绪: ${db}/checkm/"


# --- 4.3 dRep 基因组去冗余  [✓ dRep 3.6.2 / CheckM 1.2.5] ---

    # 注：pip 安装 drep 后需补装 networkx；checkm-genome 需要 checkm 数据库路径（~/.checkm/DATA_CONFIG）
    conda create --prefix ${envs}/drep python=3.9 -y
    conda install --prefix ${envs}/drep -y \
        hmmer prodigal mash fastani -c bioconda -c conda-forge
    conda run --prefix ${envs}/drep pip install drep==3.6.2 checkm-genome==1.2.5 networkx==3.2.1
    # 设置 checkm 数据库路径（drep 内部调用 checkm）
    bash ${PROJ_DIR}/scripts/checkm_config.sh
    conda run --prefix ${envs}/drep dRep -h 2>&1 | head -3


# --- 4.4 CoverM 基因组定量  [✓ CoverM 0.7.0] ---

    conda create --prefix ${envs}/coverm -y
    conda install --prefix ${envs}/coverm -y coverm -c bioconda -c conda-forge
    conda run --prefix ${envs}/coverm coverm -V


# --- 4.5 GTDB-Tk 物种注释  [✓ GTDB-Tk 2.5.2] ---

    # 注：gtdbtk 依赖 tqdm，需先固定 tqdm 版本再安装（新版 tqdm 有 __win 依赖冲突）
    conda create --prefix ${envs}/gtdbtk -y
    conda install --prefix ${envs}/gtdbtk -y "tqdm=4.66.4" -c conda-forge
    conda install --prefix ${envs}/gtdbtk -y gtdbtk=2.5.2 -c bioconda -c conda-forge
    conda run --prefix ${envs}/gtdbtk gtdbtk -v


# --- 4.6 GTDB-Tk 数据库  [✓ 160 GB / 13 个目录 / GTDBTK_DATA_PATH 已配置] ---

    mkdir -p ${db}/gtdbtk

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（160 GB，bank 模式）
        # ----
        cp -r ${DB_BANK}/gtdbtk-2.3.2/* ${db}/gtdbtk/
    else
        # ----
        # 方法1：官方下载（online 模式）
        # ----
        wget -c https://data.gtdb.ecogenomic.org/releases/latest/auxillary_files/gtdbtk_package/full_package/gtdbtk_data.tar.gz \
            -O ${db}/gtdbtk/gtdbtk_data.tar.gz
        tar xvzf ${db}/gtdbtk/gtdbtk_data.tar.gz -C ${db}/gtdbtk/ --strip 1 \
            && rm -f ${db}/gtdbtk/gtdbtk_data.tar.gz
    fi

    # ----
    # 方法2：NMDC 镜像（备用，按需解注释）
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/gtdbtk/gtdbtk_data.tar.gz \
    #     -O ${db}/gtdbtk/gtdbtk_data.tar.gz
    # tar xvzf ${db}/gtdbtk/gtdbtk_data.tar.gz -C ${db}/gtdbtk/ --strip 1 \
    #     && rm -f ${db}/gtdbtk/gtdbtk_data.tar.gz

    # GTDB-Tk 数据库路径已写入 scripts/activate.sh，source 后自动生效
    echo "GTDB-Tk 数据库就绪: ${db}/gtdbtk/"


# --- 4.7 CheckM2 基因组质量评估  [✓ CheckM2 1.0.1 / Python 3.8 + scikit-learn=0.23.2] ---

    # 注：checkm2 依赖 scikit-learn=0.23.2 + numpy<1.24 + tensorflow-cpu，需分步安装
    conda create --prefix ${envs}/checkm2 python=3.8 -y
    conda install --prefix ${envs}/checkm2 -y \
        "scikit-learn=0.23.2" "numpy<1.24" h5py diamond pandas scipy \
        -c conda-forge -c bioconda
    conda run --prefix ${envs}/checkm2 pip install \
        checkm2==1.0.1 tensorflow-cpu==2.13.1 wrapt==2.0.1 requests==2.32.3
    conda run --prefix ${envs}/checkm2 checkm2 -h 2>&1 | grep -v "tensorflow\|cuda\|CPU\|Warning\|AVX" | head -5


# --- 4.8 CheckM2 数据库  [✓ uniref100.KO.1.dmnd 2.9 GB] ---

    mkdir -p ${db}/checkm2

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（2.9 GB，bank 模式）
        # ----
        cp -r ${DB_BANK}/checkm2/* ${db}/checkm2/
    else
        # ----
        # 方法1：官方下载（online 模式）
        # ----
        conda run --prefix ${envs}/checkm2 \
            checkm2 database --download --path ${db}/checkm2
    fi

    # ----
    # 方法2：NMDC 镜像（备用，按需解注释）
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/checkm2/uniref100.KO.1.dmnd.tar.gz \
    #     -O ${db}/checkm2/uniref100.KO.1.dmnd.tar.gz
    # tar xvzf ${db}/checkm2/uniref100.KO.1.dmnd.tar.gz -C ${db}/checkm2/ \
    #     && rm -f ${db}/checkm2/uniref100.KO.1.dmnd.tar.gz

    # CheckM2 数据库路径已写入 scripts/activate.sh，source 后自动生效
    echo "CheckM2 数据库就绪: ${db}/checkm2/"
    ls ${db}/checkm2/CheckM2_database/

# ==============================================================================
# 5. 深度挖掘工具  [✓]
# ==============================================================================

# --- 5.1 宏病毒组：VIBRANT 1.2.1 + CheckV  [✓ 独立环境 envs/vibrant + envs/checkv] ---

    # 注：vibrant 和 checkv 存在 zlib/wget 依赖冲突，需分开创建独立环境
    # 注：VIBRANT 可执行文件名为 VIBRANT_run.py（大写），非 vibrant-run.py

    # VIBRANT 环境
    conda create --prefix ${envs}/vibrant -y
    conda install --prefix ${envs}/vibrant -y \
        vibrant -c bioconda -c conda-forge --no-channel-priority
    conda run --prefix ${envs}/vibrant VIBRANT_run.py --version 2>&1 | head -1

    # CheckV 环境
    conda create --prefix ${envs}/checkv -y
    conda install --prefix ${envs}/checkv -y \
        checkv -c bioconda -c conda-forge --no-channel-priority
    conda run --prefix ${envs}/checkv checkv -h 2>&1 | head -2

    # VIBRANT 数据库
    mkdir -p ${db}/vibrant
    # ----
    # 方法0：本服务器无现成数据库，无 bank 快装路径 —— online/bank 两种模式均走官方下载
    # ----
    # 方法1：官方自动下载（约 12 GB）
    # 注：VIBRANT 数据库下载脚本为 download-db.sh，不是 vibrant-setup.py
    conda run --prefix ${envs}/vibrant download-db.sh ${db}/vibrant
    # 方法2：NMDC 镜像
    # wget -c ftp://download.nmdc.cn/tools/meta/vibrant/databases.tar.gz \
    #     -O ${db}/vibrant/databases.tar.gz
    # tar xvzf ${db}/vibrant/databases.tar.gz -C ${db}/vibrant/ \
    #     && rm -f ${db}/vibrant/databases.tar.gz
    echo "VIBRANT 数据库就绪: ${db}/vibrant/"

    # CheckV 数据库
    mkdir -p ${db}/checkv
    # ----
    # 方法0：本服务器无现成数据库，无 bank 快装路径 —— online/bank 两种模式均走官方下载
    # ----
    # 方法1：官方自动下载（约 2 GB）
    conda run --prefix ${envs}/checkv checkv download_database ${db}/checkv
    # 方法2：NMDC 镜像
    # wget -c ftp://download.nmdc.cn/tools/meta/checkv/checkv-db-v1.5.tar.gz \
    #     -O ${db}/checkv/checkv-db-v1.5.tar.gz
    # tar xvzf ${db}/checkv/checkv-db-v1.5.tar.gz -C ${db}/checkv/ \
    #     && rm -f ${db}/checkv/checkv-db-v1.5.tar.gz
    echo "CheckV 数据库就绪: ${db}/checkv/"


# --- 5.2 AMR + MGE：AMRFinderPlus 3.10.1 + RGI 4.0.3 (CARD)  [✓] ---

    conda create --prefix ${envs}/amr -y
    conda install --prefix ${envs}/amr -y \
        ncbi-amrfinderplus rgi -c bioconda -c conda-forge
    conda run --prefix ${envs}/amr amrfinder --version 2>&1 | head -1
    conda run --prefix ${envs}/amr rgi main --version 2>&1 | head -1

    # CARD 数据库
    mkdir -p ${db}/card
    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（48 MB，bank 模式）
        # ----
        cp ${DB_BANK}/card/* ${db}/card/
    else
        # ----
        # 方法1：官方下载（online 模式）
        # ----
        wget -c https://card.mcmaster.ca/latest/data \
            -O ${db}/card/card-data.tar.gz
        tar xvf ${db}/card/card-data.tar.gz -C ${db}/card/ \
            && rm -f ${db}/card/card-data.tar.gz
    fi
    # 方法2：NMDC 镜像（备用，按需解注释）
    # wget -c ftp://download.nmdc.cn/tools/meta/card/card-data.tar.gz \
    #     -O ${db}/card/card-data.tar.gz
    # tar xvf ${db}/card/card-data.tar.gz -C ${db}/card/ \
    #     && rm -f ${db}/card/card-data.tar.gz
    conda run --prefix ${envs}/amr rgi load \
        -i ${db}/card/card.json --local
    echo "CARD 数据库就绪: ${db}/card/"

    # AMRFinder 数据库（需要网络，迁移到无网络服务器时注释此行）
    # conda run --prefix ${envs}/amr amrfinder -u
    echo "AMRFinder 数据库：如需更新请运行 conda run --prefix ${envs}/amr amrfinder -u"


# --- 5.3 CAZy 碳水化合物酶：dbCAN3  [✓ 数据库 3.5 GB] ---

    conda create --prefix ${envs}/dbcan -y
    conda install --prefix ${envs}/dbcan -y dbcan -c bioconda -c conda-forge
    conda run --prefix ${envs}/dbcan run_dbcan --version 2>&1 | head -1

    # dbCAN3 数据库
    mkdir -p ${db}/dbcan3
    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制（3.5 GB，bank 模式）
        # ----
        cp ${DB_BANK}/dbcan3/* ${db}/dbcan3/
    else
        # ----
        # 方法1：官方下载（online 模式）
        # ----
        wget -c https://bcb.unl.edu/dbCAN2/download/CAZyDB.07262023.fa \
            -O ${db}/dbcan3/CAZyDB.07262023.fa
        wget -c https://bcb.unl.edu/dbCAN2/download/dbCAN-HMMdb-V12.txt \
            -O ${db}/dbcan3/dbCAN-HMMdb-V12.txt
    fi
    # 方法2：NMDC 镜像（备用，按需解注释）
    # wget -c ftp://download.nmdc.cn/tools/meta/dbcan3/CAZyDB.07262023.fa \
    #     -O ${db}/dbcan3/CAZyDB.07262023.fa
    echo "dbCAN3 数据库就绪: ${db}/dbcan3/"


# --- 5.4 菌株级分析：StrainPhlAn4 4.2.4  [✓ 复用 humann4 环境] ---

    # StrainPhlAn4 是 MetaPhlAn4 套件的一部分，复用 humann4 环境，无需单独安装
    # 前置依赖（已在 §2.1 中安装）：samtools=1.15.1、mafft、fasttree
    #   - samtools: sample2markers.py 内部调用，必须 >=1.15（<1.15 与 ncurses 有版本冲突）
    #   - mafft + fasttree: strainphlan 通过 phylophlan 构建系统发育树时调用
    #   - 安装时必须用 mamba（conda solver 无法解决 samtools + python3.9 + ncurses 的三方约束）
    conda run --prefix ${envs}/humann4 strainphlan --version 2>&1 | head -1
    conda run --prefix ${envs}/humann4 sample2markers.py --version 2>&1 | head -1
    echo "StrainPhlAn4 就绪（复用 humann4 环境）"

    # ——— HUMAnN3.9 + MetaPhlAn4 vOct22 数据库兼容性修复 ———
    # HUMAnN3.9 默认只接受 MetaPhlAn4 vJun23 数据库生成的 profile，
    # 而本项目使用 vOct22 数据库，需要修改 humann/config.py 中的版本检测字符串
    # 此修改是幂等的（sed -i 不会重复修改）
    CONFIG_PY="${envs}/humann4/lib/python3.9/site-packages/humann/config.py"
    cp "${CONFIG_PY}" "${CONFIG_PY}.bak.$(date +%Y%m%d)"
    sed -i 's/metaphlan_v4_db_version="vJun23"/metaphlan_v4_db_version="vOct22"/' "${CONFIG_PY}"
    grep "metaphlan_v4_db_version" "${CONFIG_PY}"
    echo "HUMAnN config.py 已更新：vJun23 → vOct22（适配本项目 MetaPhlAn4 数据库版本）"


# --- 5.5 次级代谢产物：antiSMASH 7.1.0  [✓ --no-channel-priority 安装] ---

    # 注：antismash 依赖 biopython=1.78 和 perl-xml-parser，需 --no-channel-priority
    conda create --prefix ${envs}/antismash python=3.9 -y
    conda install --prefix ${envs}/antismash -y \
        antismash=7.1.0 -c bioconda -c conda-forge \
        --no-channel-priority
    conda run --prefix ${envs}/antismash antismash --version 2>&1 | head -1

    # antiSMASH 数据库（自动下载，约 10 GB）
    mkdir -p ${db}/antismash
    # ----
    # 方法0：本服务器无现成数据库，无 bank 快装路径 —— online/bank 两种模式均走官方下载
    # ----
    # 方法1：官方自动下载
    conda run --prefix ${envs}/antismash \
        download-antismash-databases --database-dir ${db}/antismash
    # 方法2：NMDC 镜像
    # wget -c ftp://download.nmdc.cn/tools/meta/antismash/antismash_db.tar.gz \
    #     -O ${db}/antismash/antismash_db.tar.gz
    # tar xvzf ${db}/antismash/antismash_db.tar.gz -C ${db}/antismash/ \
    #     && rm -f ${db}/antismash/antismash_db.tar.gz
    echo "antiSMASH 数据库就绪: ${db}/antismash/"


# --- 5.6 共现网络：FastSpar (SparCC)  [✓] ---

    conda create --prefix ${envs}/network -y
    conda install --prefix ${envs}/network -y fastspar -c bioconda -c conda-forge
    conda run --prefix ${envs}/network fastspar --version 2>&1 | head -1


# ==============================================================================
# ← 下次从此处开始：§6 统计 R 包
# ==============================================================================

# ==============================================================================
# 6. 统计分析 R 包
# ==============================================================================

# --- 6.1 R 环境说明 ---

    # 所有 R 包安装至项目内 Rlib 目录（${PROJ_DIR}/Rlib），不依赖系统写权限
    # 通过 Rscript 命令行执行，不依赖 RStudio
    # 使用前需设置 R_LIBS_USER（已写入 scripts/activate.sh）
    mkdir -p ${PROJ_DIR}/Rlib
    Rscript --version


# --- 6.2 CRAN 基础统计包 ---

    Rscript -e "
    lib <- '${PROJ_DIR}/Rlib'
    dir.create(lib, showWarnings=FALSE, recursive=TRUE)
    .libPaths(c(lib, .libPaths()))
    pkgs <- c(
        'vegan',        # 生态多样性分析（alpha/beta diversity）
        'ggplot2',      # 可视化基础
        'dplyr',        # 数据处理
        'tidyr',        # 数据整形
        'reshape2',     # 数据宽长转换
        'pheatmap',     # 热图
        'RColorBrewer', # 配色
        'ggpubr',       # 统计图形
        'cowplot',      # 图形拼接
        'scales',       # 坐标轴格式化
        'optparse',     # 命令行参数解析
        'stringr',      # 字符串处理
        'readr',        # 数据读取
        'patchwork',    # 图形布局
        'ggalluvial',   # 桑基图
        'UpSetR'        # UpSet 图
    )
    missing <- pkgs[!pkgs %in% installed.packages()[,'Package']]
    if (length(missing) > 0)
        install.packages(missing, lib=lib,
            repos='https://mirrors.ustc.edu.cn/CRAN/',
            dependencies=TRUE, quiet=TRUE)
    cat('CRAN 包安装完成\n')
    "


# --- 6.3 Bioconductor 包 ---

    ${PROJ_DIR}/miniforge3/bin/Rscript -e "
    lib <- '${PROJ_DIR}/Rlib'
    .libPaths(c(lib, .libPaths()))
    if (!requireNamespace('BiocManager', quietly=TRUE))
        install.packages('BiocManager', lib=lib, repos='https://mirrors.ustc.edu.cn/CRAN/')
    BiocManager::install(c(
        'phyloseq',     # 微生物组数据结构和分析
        'DESeq2',       # 差异丰度分析
        'edgeR',        # 差异丰度分析
        'microbiome',   # 微生物组工具集
        'treeio',       # 进化树数据读取
        'Maaslin2'      # 多变量关联分析
    ), lib=lib, ask=FALSE, quiet=TRUE)
    cat('Bioconductor 包安装完成\n')
    "


# --- 6.4 ANCOMBC + ggtree（conda 安装，绕过 CVXR/cairo 编译依赖）---

    # 注：ANCOMBC 依赖 CVXR::solve 接口，BiocManager 安装有版本冲突
    # 注：ggtree 依赖 ggiraph，需要 cairo-ft.h 系统库
    # 两者均通过 conda bioconda channel 安装，无需编译
    conda install --prefix ${PROJ_DIR}/miniforge3 -y \
        bioconductor-ancombc=2.12.0 bioconductor-ggtree=4.0.4 \
        -c bioconda -c conda-forge --no-channel-priority
    ${PROJ_DIR}/miniforge3/bin/Rscript -e "
    cat('ANCOMBC:', as.character(packageVersion('ANCOMBC')), '\n')
    cat('ggtree:',  as.character(packageVersion('ggtree')),  '\n')
    "


# --- 6.5 统计 R 包（SIAMCAT / curatedMetagenomicData / MMUPHin / ConQuR / MBECS / sva / BatchQC）---

    # 注：全部安装到项目内 Rlib，不写入系统库
    # 注：ConQuR 依赖 GUniFrac，需编译 C++；当前 conda R 的 Makeconf 指向
    #     x86_64-conda-linux-gnu-c++，故在项目内创建同名 wrapper 到系统 gcc/g++
    mkdir -p ${PROJ_DIR}/Rlib ${PROJ_DIR}/.tmp/r-toolchain/bin
    ln -sf /usr/bin/gcc ${PROJ_DIR}/.tmp/r-toolchain/bin/x86_64-conda-linux-gnu-cc
    ln -sf /usr/bin/g++ ${PROJ_DIR}/.tmp/r-toolchain/bin/x86_64-conda-linux-gnu-c++
    ln -sf /usr/bin/cpp ${PROJ_DIR}/.tmp/r-toolchain/bin/x86_64-conda-linux-gnu-cpp

    PATH="${PROJ_DIR}/.tmp/r-toolchain/bin:${PATH}" \
    ${PROJ_DIR}/miniforge3/bin/Rscript -e "
    options(repos = c(CRAN = 'https://cloud.r-project.org'))
    lib <- '${PROJ_DIR}/Rlib'
    .libPaths(c(lib, .libPaths()))
    if (!requireNamespace('BiocManager', quietly=TRUE))
        install.packages('BiocManager', lib=lib)
    BiocManager::install(c(
        'SIAMCAT',
        'curatedMetagenomicData',
        'MMUPHin',
        'MBECS',
        'sva',
        'BatchQC'
    ), lib=lib, update=FALSE, ask=FALSE)
    if (!requireNamespace('remotes', quietly=TRUE))
        install.packages('remotes', lib=lib)
    if (!requireNamespace('ConQuR', quietly=TRUE)) {
        remotes::install_github('wdl2459/ConQuR', lib=lib, upgrade='never')
    }
    "


# --- 6.6 activate.sh 中加入 Rlib 路径 ---

    # 将 Rlib 路径写入 activate.sh，每次 source 后 R 自动找到项目包
    echo "export R_LIBS_USER=\"${PROJ_DIR}/Rlib\"" \
        >> ${PROJ_DIR}/scripts/activate.sh


# --- 6.7 版本验证 ---

    ${PROJ_DIR}/miniforge3/bin/Rscript -e "
    lib <- '${PROJ_DIR}/Rlib'
    .libPaths(c(lib, .libPaths()))
    pkgs <- c(
        'vegan','ggplot2','phyloseq','DESeq2','ANCOMBC','ggtree','Maaslin2',
        'SIAMCAT','curatedMetagenomicData','MMUPHin','ConQuR','MBECS','sva','BatchQC'
    )
    for (p in pkgs) {
        v <- tryCatch(as.character(packageVersion(p)), error=function(e) 'NOT INSTALLED')
        cat(sprintf('  %-15s %s\n', p, v))
    }
    "


# ==============================================================================
# 7. Apptainer 流程融合工具（来自 Metagenomics_Apptainer_pipline）
# ==============================================================================
# 融合说明：
#   - 已有工具（trimmomatic/diamond/megahit/prodigal/coverm/antismash/dbcan/amrfinder/rgi）
#     均已安装在对应环境中，无需重复安装
#   - 新增工具优先安装进已有环境，避免创建新环境
#   - 所有数据库从 Apptainer 项目路径复制，避免重复下载

# --- 7.1 assembly 环境扩充（centrifuger / mmseqs2 / seqtk）---

    # centrifuger：高速分类学（替代 Kraken2 用于蛋白数据库）
    # mmseqs2：高效序列搜索（多功能注释流程依赖）
    # seqtk：FASTA/FASTQ 处理工具
    conda install --prefix ${envs}/assembly -y \
        centrifuger mmseqs2 seqtk \
        -c bioconda -c conda-forge
    conda run --prefix ${envs}/assembly conda list | grep centrifuger
    conda run --prefix ${envs}/assembly mmseqs version 2>&1 | head -1
    conda run --prefix ${envs}/assembly conda list | grep seqtk


# --- 7.2 amr 环境扩充（mobileOG 相关工具）---

    # mobileOG-db 通过 diamond 搜索，amr 环境已有 diamond，无需额外安装工具
    # 直接复制数据库即可


# --- 7.3 genomad 病毒/质粒检测（独立环境）---

    # genomad 依赖较复杂，需独立环境
    if [ -d "${envs}/genomad" ]; then
        echo "genomad 环境已存在，跳过"
    else
        conda create --prefix ${envs}/genomad -y
        conda install --prefix ${envs}/genomad -y genomad -c bioconda -c conda-forge
    fi
    conda run --prefix ${envs}/genomad genomad --version 2>&1 | head -1


# --- 7.4 Centrifuger 数据库（GTDB R226 + RefSeq，166 GB）---

    mkdir -p ${db}/centrifuger

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从 Apptainer 项目复制（最快，bank 模式）
        # ----
        cp -r ${SIBLING_DB}/centrifuger/* ${db}/centrifuger/
    else
        # ----
        # 方法1：官方下载（online 模式）
        # ----
        wget -c https://genome-idx.s3.amazonaws.com/centrifuger/cfr_gtdb_r226+refseq_hvfc.tar.gz \
            -O ${db}/centrifuger/cfr_gtdb_r226+refseq_hvfc.tar.gz
        tar xvzf ${db}/centrifuger/cfr_gtdb_r226+refseq_hvfc.tar.gz -C ${db}/centrifuger/ \
            && rm -f ${db}/centrifuger/*.tar.gz
    fi
    echo "Centrifuger 数据库就绪: ${db}/centrifuger/"


# --- 7.5 功能注释数据库（从 Apptainer 项目复制）---
# 注：本组数据库（vfdb/bacmet/merops/kegg/amrfinder/sarg/phi/mvirdb/tcdb/ncyc/pcyc）
#     脚本内无官方在线下载源，online/bank 两种模式均从 ${SIBLING_DB} 本地复制；
#     外部部署需自备 SIBLING_DB 或按各数据库官网手工下载。

    # VFDB 毒力因子（2.0 GB）
    mkdir -p ${db}/vfdb
    cp -r ${SIBLING_DB}/vfdb/* ${db}/vfdb/
    echo "VFDB 就绪: ${db}/vfdb/"

    # BacMet 重金属抗性基因（867 MB）
    mkdir -p ${db}/bacmet
    cp -r ${SIBLING_DB}/bacmet-db/* ${db}/bacmet/
    echo "BacMet 就绪: ${db}/bacmet/"

    # MEROPS 蛋白酶（3.7 GB）
    mkdir -p ${db}/merops
    cp -r ${SIBLING_DB}/merops/* ${db}/merops/
    echo "MEROPS 就绪: ${db}/merops/"

    # KEGG diamond 索引（48 GB）
    mkdir -p ${db}/kegg
    cp -r ${SIBLING_DB}/kegg/* ${db}/kegg/
    echo "KEGG 就绪: ${db}/kegg/"

    # NCBI AMRFinder 数据库（488 MB，amr 环境已有工具）
    mkdir -p ${db}/amrfinder
    cp -r ${SIBLING_DB}/amrfinder-db/* ${db}/amrfinder/
    echo "AMRFinder 数据库就绪: ${db}/amrfinder/"

    # SARG+ 污水抗性基因库（264 MB）
    mkdir -p ${db}/sarg
    cp -r ${SIBLING_DB}/sarg+-db/* ${db}/sarg/
    echo "SARG+ 就绪: ${db}/sarg/"

    # PHI 植物-微生物互作（946 MB）
    mkdir -p ${db}/phi
    cp -r ${SIBLING_DB}/phi/* ${db}/phi/
    echo "PHI 就绪: ${db}/phi/"

    # mVIRdb 微生物病毒数据库（1.2 GB）
    mkdir -p ${db}/mvirdb
    cp -r ${SIBLING_DB}/mvirdb/* ${db}/mvirdb/
    echo "mVIRdb 就绪: ${db}/mvirdb/"

    # TCDB 转运载体数据库（982 MB）
    mkdir -p ${db}/tcdb
    cp -r ${SIBLING_DB}/tcdb/* ${db}/tcdb/
    echo "TCDB 就绪: ${db}/tcdb/"

    # NCyc 氮循环（214 MB）
    mkdir -p ${db}/ncyc
    cp -r ${SIBLING_DB}/ncyc-db/* ${db}/ncyc/
    echo "NCyc 就绪: ${db}/ncyc/"

    # PCyc 磷循环（846 MB）
    mkdir -p ${db}/pcyc
    cp -r ${SIBLING_DB}/pcyc-db/* ${db}/pcyc/
    echo "PCyc 就绪: ${db}/pcyc/"


# --- 7.6 genomad 数据库（2.6 GB）---

    mkdir -p ${db}/genomad

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从压缩包解压（Apptainer 项目有 tar.gz，bank 模式）
        # ----
        tar xvzf ${SIBLING_DB}/genomad.tar.gz \
            -C ${db}/genomad/ 2>/dev/null \
            || echo "genomad.tar.gz 解压失败，请使用方法1"
    else
        # ----
        # 方法1：官方下载（online 模式）
        # ----
        conda run --prefix ${envs}/genomad genomad download-database ${db}/genomad
    fi
    echo "genomad 数据库就绪: ${db}/genomad/"


# ==============================================================================
# ← 下次从此处开始：§8 MCP / RAG 服务
# ==============================================================================

# ==============================================================================
# 8. Binning 流程新增工具（来自 Binning_Apptainer_pipline）
# ==============================================================================

# --- 8.1 分箱算法扩充（MetaBAT2 + MaxBin2 + SemiBin2）---

    # MetaBAT2 和 MaxBin2 安装进 metawrap 环境（与 MetaWRAP 配合使用）
    conda install --prefix ${envs}/metawrap -y \
        metabat2 maxbin2 \
        -c bioconda -c conda-forge --no-channel-priority
    conda run --prefix ${envs}/metawrap conda list | grep -E "metabat2|maxbin2"

    # SemiBin2：机器学习分箱，需独立环境（依赖较复杂）
    conda create --prefix ${envs}/semibin -y
    conda install --prefix ${envs}/semibin -y semibin -c bioconda -c conda-forge
    conda run --prefix ${envs}/semibin SemiBin2 --version 2>&1 | head -1


# --- 8.2 DAS_Tool 分箱整合优化 ---

    # 注：das_tool 需要 --no-channel-priority（R 相关依赖有版本冲突）
    conda create --prefix ${envs}/dastool -y
    conda install --prefix ${envs}/dastool -y das_tool -c bioconda -c conda-forge \
        --no-channel-priority
    conda run --prefix ${envs}/dastool DAS_Tool --version 2>&1 | head -1


# --- 8.3 Bakta 基因组注释 ---

    # 注：bakta 需要 --no-channel-priority（xopen 依赖有冲突）
    conda create --prefix ${envs}/bakta -y
    conda install --prefix ${envs}/bakta -y bakta -c bioconda -c conda-forge \
        --no-channel-priority
    conda run --prefix ${envs}/bakta bakta --version 2>&1 | head -1

    # Bakta 数据库（从 Binning 项目解压，约 1.6 GB）
    mkdir -p ${db}/bakta
    tar xvzf $HOME/Course/Binning_Apptainer_pipline/db/bakta.tar.gz \
        -C ${db}/bakta/ 2>/dev/null && echo "Bakta 数据库就绪: ${db}/bakta/" \
        || echo "bakta.tar.gz 解压失败"


# --- 8.4 Defense-Finder 防御系统检测（独立环境）---

    # 注：defense-finder 与 amr 环境有依赖冲突，需独立环境
    conda create --prefix ${envs}/defense-finder -y
    conda install --prefix ${envs}/defense-finder -y defense-finder -c bioconda -c conda-forge
    conda run --prefix ${envs}/defense-finder conda list | grep "^defense-finder"

    # Defense-Finder 数据库
    mkdir -p ${db}/defense-finder
    tar xvzf $HOME/Course/Binning_Apptainer_pipline/db/defense-finder-db.tar.gz \
        -C ${db}/defense-finder/ 2>/dev/null && echo "Defense-Finder 数据库就绪" \
        || echo "defense-finder-db.tar.gz 解压失败"


# --- 8.5 MobileOG-db 可移动遗传元素数据库 ---

    # MobileOG 无 conda 包，通过 pip 安装；数据库直接解压使用
    conda run --prefix ${envs}/amr pip install mobileog -q 2>/dev/null \
        || echo "mobileog pip 安装失败，可通过 diamond 直接搜索数据库"

    # MobileOG 数据库（从 Binning 项目解压，约 5.8 GB）
    mkdir -p ${db}/mobileog
    tar xvzf $HOME/Course/Binning_Apptainer_pipline/db/mobileOG-db.tar.gz \
        -C ${db}/mobileog/ 2>/dev/null && echo "MobileOG 数据库就绪: ${db}/mobileog/" \
        || echo "mobileOG-db.tar.gz 解压失败"


# --- 8.6 代谢通路数据库（CCyc / MCyc / SCyc）---

    # 从 Binning 项目解压（碳循环/甲烷循环/硫循环）
    mkdir -p ${db}/ccyc ${db}/mcyc ${db}/scyc

    tar xvzf $HOME/Course/Binning_Apptainer_pipline/db/ccyc-db.tar.gz \
        -C ${db}/ccyc/ 2>/dev/null && echo "CCyc 就绪: ${db}/ccyc/" \
        || echo "ccyc-db.tar.gz 解压失败"

    tar xvzf $HOME/Course/Binning_Apptainer_pipline/db/mcyc-db.tar.gz \
        -C ${db}/mcyc/ 2>/dev/null && echo "MCyc 就绪: ${db}/mcyc/" \
        || echo "mcyc-db.tar.gz 解压失败"

    tar xvzf $HOME/Course/Binning_Apptainer_pipline/db/scyc-db.tar.gz \
        -C ${db}/scyc/ 2>/dev/null && echo "SCyc 就绪: ${db}/scyc/" \
        || echo "scyc-db.tar.gz 解压失败"


# --- 8.7 VIBRANT 数据库  [✓ 11G / KEGG 9995 + VOG 19182 + Pfam / hmmpress 完成] ---

    # 注：官方 download-db.sh 依赖 KEGG FTP（日本），速度极慢（~16 KB/s）
    # 推荐方法0：使用本服务器已有 kofam_profiles 直接构建（约 30 分钟）
    mkdir -p ${db}/vibrant

    if [ "${INSTALL_MODE}" = "bank" ]; then
    # ----
    # 方法0：使用已有 kofam_profiles 构建（需 ViOTUcluster 或类似项目的 kofam 数据）
    # ----
    # 第1步：用 VIBRANT_setup.py 下载 Pfam + VOG（来自欧洲服务器，较快）
    cd ${db}/vibrant/databases 2>/dev/null || mkdir -p ${db}/vibrant/databases
    conda run --prefix ${envs}/vibrant VIBRANT_setup.py -d ${db}/vibrant 2>/dev/null &
    SETUP_PID=$!
    sleep 120 && kill $SETUP_PID 2>/dev/null || true
    # 第2步：从已有 kofam_profiles 重建 KEGG HMM（替代 KEGG FTP 下载）
    # 将下面路径替换为你服务器上的 kofam_profiles 位置
    KOFAM_DIR=$HOME/Course/ViOTUcluster/db/DRAM/kofam_profiles/profiles
    cd ${db}/vibrant/databases || exit
    cat ${KOFAM_DIR}/K*.hmm > kegg_temp_full.HMM
    conda run --prefix ${envs}/vibrant \
        hmmfetch -o KEGG_profiles_prokaryotes.HMM \
        -f kegg_temp_full.HMM profile_names/VIBRANT_kegg_profiles.txt
    conda run --prefix ${envs}/vibrant hmmpress KEGG_profiles_prokaryotes.HMM
    conda run --prefix ${envs}/vibrant hmmpress VOGDB94_phage.HMM
    conda run --prefix ${envs}/vibrant hmmpress Pfam-A_v32.HMM
    rm -f kegg_temp_full.HMM kegg_temp.HMM vog_temp.HMM vog.hmm.tar.gz profiles.tar.gz Pfam-A.hmm
    rm -rf profiles/ VOG*.hmm
    echo "VIBRANT 数据库就绪: ${db}/vibrant/ ($(du -sh ${db}/vibrant/ | awk '{print $1}'))"
    else
    # ----
    # online 模式：db/vibrant 已由 §5.1 的官方 download-db.sh 下载完成，此处不重复
    # ----
    echo "[INFO] online 模式：VIBRANT 数据库由 §5.1 官方 download-db.sh 获取，跳过本地 kofam 重建"
    fi

    # ----
    # 方法1：官方自动下载（KEGG 来自日本 FTP，可能极慢）
    # ----
    # conda run --prefix ${envs}/vibrant download-db.sh ${db}/vibrant

    # ----
    # 方法2：NMDC 镜像
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/vibrant/databases.tar.gz \
    #     -O ${db}/vibrant/databases.tar.gz
    # tar xvzf ${db}/vibrant/databases.tar.gz -C ${db}/vibrant/ \
    #     && rm -f ${db}/vibrant/databases.tar.gz


# --- 8.8 antiSMASH 数据库 ---

    # 注：从 Apptainer 项目解压（3.9 GB），无需网络下载
    mkdir -p ${db}/antismash

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从 Apptainer 项目解压（推荐，bank 模式）
        # ----
        # 注：解压后数据库实际路径为 ${db}/antismash/antismash-db/
        # 使用时：antismash --databases ${db}/antismash/antismash-db
        tar xzf ${SIBLING_DB}/antismash-db.tar.gz \
            -C ${db}/antismash/ \
            && echo "antiSMASH 数据库就绪: ${db}/antismash/antismash-db/ ($(ls ${db}/antismash/antismash-db/ | wc -l) 个模块)"
    else
        # ----
        # 方法1：官方自动下载（约 10 GB，online 模式；§5.5 已下载过则此处为幂等更新）
        # ----
        conda run --prefix ${envs}/antismash \
            download-antismash-databases --database-dir ${db}/antismash
    fi

    # ----
    # 方法2：NMDC 镜像
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/antismash/antismash_db.tar.gz \
    #     -O ${db}/antismash/antismash_db.tar.gz
    # tar xvzf ${db}/antismash/antismash_db.tar.gz -C ${db}/antismash/ \
    #     && rm -f ${db}/antismash/antismash_db.tar.gz


# --- 8.9 Snakemake ---

    # §8.9 — Snakemake（snakemake-minimal，项目内 miniforge3 base）
    ${soft}/bin/conda install -y -n base -c conda-forge -c bioconda "snakemake-minimal>=9.0.0"


# ==============================================================================
# §9 MCP / RAG 服务（已完成）
# ==============================================================================


# ==============================================================================
# 9. MCP / RAG 知识库服务
# ==============================================================================
# 说明：
#   - 安装 rag conda 环境，含 ChromaDB（向量库）+ sentence-transformers（嵌入）
#   - 建立经验知识库（docs/experience/ + docs/ + 脚本注释）
#   - 建立文献知识库（PubTator 3.0 + PMC OA）
#   - 启动 MCP stdio 服务器，供 Claude Code 调用
# ==============================================================================

# --- 9.1 创建 RAG conda 环境 ---

    conda create --prefix ${envs}/rag python=3.10 -y 2>/dev/null
    conda run --prefix ${envs}/rag pip install -q chromadb==1.5.9 sentence-transformers==5.5.1 requests==2.34.2

    # 验证安装
    conda run --prefix ${envs}/rag python -c "
import chromadb; print(f'ChromaDB: {chromadb.__version__}')
import sentence_transformers; print(f'sentence-transformers: {sentence_transformers.__version__}')
import requests; print(f'requests: {requests.__version__}')
" 2>/dev/null

# --- 9.2 构建经验知识库 ---

    conda run --prefix ${envs}/rag python mcp/indexer.py --repo ${PROJ_DIR} 2>/dev/null

# --- 9.3 构建文献知识库（可选，需网络）---

    # 首次构建（建议选择非高峰时段运行）
    # conda run --prefix ${envs}/rag python mcp/literature_pipeline.py --repo ${PROJ_DIR} --max-articles 100

# --- 9.4 注册 MCP 服务器（可选）---

    # 在 Claude Code 中注册：
    # claude mcp add maxmeta-rag -- python ${PROJ_DIR}/mcp/server.py

echo "§9 MCP / RAG 服务安装完成"

# ==============================================================================
# ← 下次从此处开始：§10 Virome 流程工具（已安装）
# ==============================================================================
# ==============================================================================
# 说明：
#   - Virus_Apptainer_pipline 使用 Apptainer 容器；CSCCD-MetagenomeFlow 使用 conda 环境
#   - 数据库从 Virus 项目压缩包解压，避免重复下载（除 virsorter2 需在线 setup）
#   - iphop 数据库（294 GB）直接引用 Virus 项目已解压目录，不复制（节省磁盘）
#   - 所有环境路径：${envs}/<工具名>
#   - 所有数据库路径：${db}/<工具名>
# ==============================================================================

VIRUS_PROJ="$HOME/Course/Virus_Apptainer_pipline"


# --- 10.1 VirSorter2 2.2.4  [✓ 已完成] ---
# 说明：virsorter2 需要先安装再通过 `virsorter setup` 下载数据库（约 1.5 GB）

    conda create --prefix ${envs}/virsorter2 -y
    conda install --prefix ${envs}/virsorter2 -y \
        virsorter=2 "python>=3.8" scikit-learn imbalanced-learn pandas \
        -c bioconda -c conda-forge --no-channel-priority
    conda run --prefix ${envs}/virsorter2 virsorter --version 2>&1 | head -1

    # VirSorter2 数据库（约 1.5 GB，需要网络）
    mkdir -p ${db}/virsorter2
    # ----
    # 方法1：官方在线 setup（推荐，自动下载所有模型文件）
    # 注：无 bank 快装路径 —— online/bank 两种模式均走官方下载
    # ----
    conda run --prefix ${envs}/virsorter2 \
        virsorter setup -d ${db}/virsorter2 -j 4
    # ----
    # 方法2：如无网络，从已有 virsorter run 过的 db 目录复制
    # ----
    # cp -r <已有 virsorter2 数据库目录>/* ${db}/virsorter2/
    echo "VirSorter2 数据库就绪: ${db}/virsorter2/"


# --- 10.2 vclust 1.3.1  [✓ 已完成] ---
# 说明：vclust 仅用于序列聚类（vOTU 生成），无需独立数据库

    conda create --prefix ${envs}/vclust -y
    conda install --prefix ${envs}/vclust -y vclust -c bioconda -c conda-forge
    conda run --prefix ${envs}/vclust vclust --version 2>&1 | head -1
    echo "vclust 环境就绪: ${envs}/vclust/"


# --- 10.3 vRhyme 1.1.0  [✓ 已完成] ---
# 说明：vRhyme 用于病毒 MAG 聚合（61_vir_vmag.sh），无需独立数据库

    conda create --prefix ${envs}/vrhyme -y
    conda install --prefix ${envs}/vrhyme -y vrhyme -c bioconda -c conda-forge
    conda run --prefix ${envs}/vrhyme vRhyme --version 2>&1 | head -1
    echo "vRhyme 环境就绪: ${envs}/vrhyme/"


# --- 10.4 PHAROKKA 1.9.1  [✓ 已完成] ---
# 说明：病毒基因组端到端注释工具，数据库 550 MB

    conda create --prefix ${envs}/pharokka -y
    conda install --prefix ${envs}/pharokka -y \
        pharokka -c bioconda -c conda-forge --no-channel-priority
    conda run --prefix ${envs}/pharokka pharokka.py --version 2>&1 | head -1

    # PHAROKKA 数据库（从 Virus 项目解压，550 MB）
    mkdir -p ${db}/pharokka
    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从 Virus_Apptainer_pipline 解压（推荐，bank 模式）
        # ----
        tar xzf ${VIRUS_PROJ}/db/pharokka-db.tar.gz \
            -C ${db}/pharokka/ --strip-components=1 \
            && echo "PHAROKKA 数据库就绪: ${db}/pharokka/"
    else
        # ----
        # 方法1：官方自动下载（online 模式）
        # ----
        conda run --prefix ${envs}/pharokka install_databases.py -d ${db}/pharokka
    fi
    echo "PHAROKKA 数据库就绪: ${db}/pharokka/"


# --- 10.5 PHOLD 1.2.5  [✓ 已完成] ---
# 说明：病毒 ORF 结构注释（补充 PHAROKKA），数据库 32 GB（Virus 项目有压缩包）

    conda create --prefix ${envs}/phold -y
    conda install --prefix ${envs}/phold -y \
        phold -c bioconda -c conda-forge --no-channel-priority
    conda run --prefix ${envs}/phold phold --version 2>&1 | head -1

    # PHOLD 数据库（从 Virus 项目解压，解压约 32 GB，耗时较长）
    mkdir -p ${db}/phold
    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从 Virus_Apptainer_pipline 解压（推荐，约 20-30 分钟，bank 模式）
        # ----
        tar xzf ${VIRUS_PROJ}/db/phold-db.tar.gz \
            -C ${db}/phold/ --strip-components=1 \
            && echo "PHOLD 数据库就绪: ${db}/phold/"
    else
        # ----
        # 方法1：官方自动下载（online 模式）
        # ----
        conda run --prefix ${envs}/phold phold install -d ${db}/phold
    fi
    echo "PHOLD 数据库就绪: ${db}/phold/"


# --- 10.6 BACPHLIP 0.9.6  [✓ 已完成] ---
# 说明：噬菌体生活方式预测（裂解/溶原），无需独立数据库（内置 HMM 模型）

    conda create --prefix ${envs}/bacphlip -y
    # 注：bacphlip 官方 conda 包名为 bacphlip，python 3.8 更稳定
    conda install --prefix ${envs}/bacphlip -y \
        python=3.8 -c conda-forge
    conda run --prefix ${envs}/bacphlip pip install bacphlip==0.9.6
    # 安装 hmmer（bacphlip 依赖 hmmscan）
    conda install --prefix ${envs}/bacphlip -y hmmer -c bioconda -c conda-forge
    conda run --prefix ${envs}/bacphlip python -m bacphlip --version 2>&1 | head -1
    echo "BACPHLIP 环境就绪: ${envs}/bacphlip/"


# --- 10.7 iPHoP 1.4.2  [✓ 已完成] ---
# 说明：病毒-宿主关联预测，数据库 294 GB（Virus 项目已解压，直接引用）

    conda create --prefix ${envs}/iphop -y
    conda install --prefix ${envs}/iphop -y \
        iphop -c bioconda -c conda-forge --no-channel-priority
    conda run --prefix ${envs}/iphop iphop --version 2>&1 | head -1

    # iPHoP 数据库（294 GB，Virus 项目已解压，直接软链接节省磁盘）
    # 注：目录结构为 iphop-db/Jun_2025_pub_rw/
    mkdir -p ${db}/iphop
    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：软链接 Virus 项目已解压目录（推荐，节省 294 GB，bank 模式）
        # ----
        ln -sfn ${VIRUS_PROJ}/db/iphop-db/Jun_2025_pub_rw \
            ${db}/iphop/Jun_2025_pub_rw \
            && echo "iPHoP 数据库软链接就绪: ${db}/iphop/"
    else
        # ----
        # 方法1：官方下载（online 模式；需要大量时间和磁盘，约 294 GB）
        # ----
        conda run --prefix ${envs}/iphop iphop download --db_dir ${db}/iphop
    fi
    echo "iPHoP 数据库就绪: ${db}/iphop/"


# --- 10.8 vConTACT3 3.1.6  [✓ 已完成] ---
# 说明：病毒分类基因共享网络，数据库 3.4 GB

    conda create --prefix ${envs}/vcontact3 -y
    conda install --prefix ${envs}/vcontact3 -y \
        vcontact3 -c bioconda -c conda-forge --no-channel-priority
    conda run --prefix ${envs}/vcontact3 vcontact3 --version 2>&1 | head -1

    # vConTACT3 数据库（从 Virus 项目解压，3.4 GB）
    mkdir -p ${db}/vcontact3
    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从 Virus_Apptainer_pipline 解压（推荐，bank 模式）
        # ----
        tar xzf ${VIRUS_PROJ}/db/vcontact3-db.tar.gz \
            -C ${db}/vcontact3/ --strip-components=1 \
            && echo "vConTACT3 数据库就绪: ${db}/vcontact3/"
    else
        # ----
        # 方法1：官方构建（online 模式）
        # ----
        conda run --prefix ${envs}/vcontact3 \
            vcontact3 prepare_databases --db-path ${db}/vcontact3/
    fi
    echo "vConTACT3 数据库就绪: ${db}/vcontact3/"


# --- 10.9 CheckV 数据库  [✓ 已完成] ---
# 说明：envs/checkv 已安装（§5.1），仅缺数据库（2 GB）

    mkdir -p ${db}/checkv
    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从 Virus_Apptainer_pipline 解压（推荐，2.1 GB tar.gz，bank 模式）
        # 注：tar 内顶层目录为 checkv-db/，用 --strip-components=1 直接解压到 ${db}/checkv/
        # ----
        tar xzf ${VIRUS_PROJ}/db/checkv-db.tar.gz \
            -C ${db}/checkv/ --strip-components=1 \
            && echo "CheckV 数据库就绪: ${db}/checkv/"
    else
        # ----
        # 方法1：官方自动下载（online 模式；§5.1 已执行过 checkv download_database，
        # 此处不重复下载，如需强制重建可手动运行下面命令）
        # ----
        # conda run --prefix ${envs}/checkv checkv download_database ${db}/checkv
        echo "[INFO] online 模式：CheckV 数据库已由 §5.1 官方 checkv download_database 获取"
    fi
    ls ${db}/checkv/ 2>/dev/null | head -5


# --- 10.10 VOG 数据库  [✓ 已完成] ---
# 说明：VOG HMM 数据库（2.4 GB），供 66_vir_vog.sh 使用

    mkdir -p ${db}/vogdb
    # ----
    # 方法0：从 Virus_Apptainer_pipline 解压（推荐，2.4 GB tar.gz）
    # 注：解压后结构为 vog/vog.hmm.gz, vog/vog.dmnd, vog/misc/ 等
    # 注：脚本内无官方在线下载源，online/bank 两种模式均走本地 tar 解压
    # ----
    tar xzf ${VIRUS_PROJ}/db/vog.tar.gz \
        -C ${db}/vogdb/ --strip-components=1 \
        && echo "VOG 数据库就绪: ${db}/vogdb/"
    # 解压 VOG HMM（压缩格式需先解压）
    if [ -f "${db}/vogdb/vog.hmm.gz" ]; then
        gunzip -k ${db}/vogdb/vog.hmm.gz
        mv ${db}/vogdb/vog.hmm ${db}/vogdb/VOG.hmm
        echo "VOG HMM 解压完成: ${db}/vogdb/VOG.hmm"
    fi
    ls -lh ${db}/vogdb/ 2>/dev/null
    echo "VOG 数据库就绪: ${db}/vogdb/"


# ==============================================================================
# §11 真菌分析数据库（Mycobiome）
# ==============================================================================


# --- 11.1 肠道真菌参考数据库（gut_fungi DIAMOND DB） [✓ 已完成] ---
# 说明：供 74_fun_blast_gutdb.sh 使用，基于 NCBI 肠道真菌基因组（19G fasta）
#       使用 diamond blastn 模式比对 reads → 鉴定真菌物种
# 数据源：${DB_BANK}/fungi_human_gut_reference/combined.fasta

    mkdir -p ${db}/fungi

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ----
        # 方法0：从本服务器复制并构建 DMND（推荐，19G fasta → ~8G DMND，需数小时，bank 模式）
        # ----
        if [ ! -f "${db}/fungi/gut_fungi.dmnd" ]; then
            cp ${DB_BANK}/fungi_human_gut_reference/combined.fasta ${db}/fungi/combined.fasta
            conda run --prefix ${envs}/assembly diamond makedb \
                --in ${db}/fungi/combined.fasta \
                -d ${db}/fungi/gut_fungi \
                --threads "$(nproc)" --ignore-warnings
            echo "肠道真菌 DIAMOND DB 构建完成"
        fi
    else
        # ----
        # 方法1：官方 NCBI 数据集下载（online 模式）
        # ----
        # 使用 ncbi_datasets 工具下载肠道真菌基因组集合，合并后构建 DMND
        # 注：以下命令需在 ${db}/fungi 目录下执行（ncbi_datasets 工具位于 envs/assembly）
        datasets download genome taxon fungi --refseq --annotated --include genome
        unzip ncbi_dataset.zip && cat ncbi_dataset/data/*/*.fna > combined.fasta
        conda run --prefix ${envs}/assembly diamond makedb --in combined.fasta -d gut_fungi --threads "$(nproc)" --ignore-warnings
    fi

    ls -lh ${db}/fungi/gut_fungi.dmnd 2>/dev/null


# --- 11.2 MEROPS 蛋白酶 DIAMOND 索引 [✓ 已完成] ---
# 说明：供 86_fun_merops.sh 使用，从 peptidases.fasta.gz 构建 DIAMOND 蛋白索引
#       1,227,939 条序列，287M 氨基酸，308M .dmnd

    # 构建 DIAMOND 索引（去除 fasta 中可能存在的空格字符）
    if [ ! -f "${db}/merops/peptidases.dmnd" ]; then
        gzip -dc ${db}/merops/peptidases.fasta.gz \
            | sed '/^[^>]/s/ //g' \
            | conda run --prefix ${envs}/assembly diamond makedb \
                --in /dev/stdin -d ${db}/merops/peptidases --threads "$(nproc)"
        echo "MEROPS DIAMOND 索引构建完成"
    fi

    ls -lh ${db}/merops/peptidases.dmnd 2>/dev/null


# --- 11.3 Eukfinder 真核生物 MAG 回收工具 [✓ 已完成] ---
# 说明：供 79_fun_eukfinder.sh 使用，已安装至 envs/assembly
#       版本：1.2.4（bioconda），Python 3.6+
#       功能：从宏基因组中回收真核生物基因组（真菌、原生动物等）

    if ! conda run --prefix ${envs}/assembly bash -lc 'command -v Eukfinder_long' 2>/dev/null; then
        conda install -p ${envs}/assembly -y eukfinder -c bioconda -c conda-forge
        echo "Eukfinder 安装完成"
    fi
    conda run --prefix ${envs}/assembly eukfinder -h 2>&1 | head -3


# --- 11.4 FunOMIC 真菌专用 WGS 流程 [✓ 已完成] ---
# 说明：供 75_fun_funomics.sh 使用
#       脚本含自动回退：未检测到 funomic 命令时 → 使用 DIAMOND blastx 标记基因分类
# 数据源：本地 tarball
#   - ~/FunOMIC-P.tar.xz  → 功能蛋白 DIAMOND 数据库
#   - ~/FunOMIC-T.tar.xz  → Bowtie2 分类索引
# 当前状态：数据库已部署；envs/funomic 已创建，但 GitHub 包仓库不可用，脚本当前走 DIAMOND 回退

    mkdir -p "${db}/funomic/P"
    tar -xJf ~/FunOMIC-P.tar.xz \
        --strip-components=6 \
        -C "${db}/funomic/P"
    ls -lh "${db}/funomic/P/"
    ls -lh "${db}/funomic/P/"*.dmnd

    mkdir -p "${db}/funomic/T"
    tar -xJf ~/FunOMIC-T.tar.xz \
        --strip-components=1 \
        -C "${db}/funomic/T"
    ls -lh "${db}/funomic/T/"

    ${soft}/bin/conda create -y -p "${envs}/funomic" \
        python=3.9 -c conda-forge
    "${envs}/funomic/bin/pip" install \
        git+https://github.com/zhanglab/FunOMIC.git || \
        echo "[WARN] FunOMIC GitHub 仓库不可用，75_fun_funomics.sh 将使用 DIAMOND 回退"


# --- 11.5 CCMetagen + KMA/NCBI nt 数据库 [✗ 永久跳过 — 用户确认不需要] ---
# 说明：76_fun_ccmetagen.sh 已从 Snakemake pipeline rule all 中移除
#       registry.yaml 中状态已更新为 removed
#       真菌分类由 71/72/75/77 四条路径覆盖，CCMetagen 不影响分析完整性



# --- 11.6 WGS 融入模块：MLST / 泛基因组 / SNP 变异检测 [✓ 已完成] ---
# 说明：供 41b_bac_mlst.sh、41c_bac_pangenome.sh、41d_bac_snippy.sh 使用
#       工具均安装在项目内 conda 环境（envs/prokaWGS、envs/snippy）
#
# 工具清单：
#   - mlst     v2.11   (envs/prokaWGS)  — MAG 多位点序列分型，PubMLST 自动检测
#   - roary    v3.12.0 (envs/prokaWGS)  — 泛基因组分析，需 ≥3 个 GFF（Prokka 注释输出）
#   - snippy   v4.0.2  (envs/snippy)    — SNP/InDel 变异检测 + snippy-core + snippy-clean_full_aln
#
# 安装命令（首次部署时运行）：
    # ${soft}/bin/conda create -y -p ${envs}/prokaWGS \
    #     -c bioconda -c conda-forge \
    #     mlst=2.11 roary=3.12.0 blast any2fasta mafft perl-bioperl

    # ${soft}/bin/conda create -y -p ${envs}/snippy \
    #     -c bioconda -c conda-forge \
    #     snippy=4.0.2 snp-sites snp-dists

# 验证：
    # conda run --prefix ${envs}/prokaWGS mlst --version  # mlst 2.11
    # conda run --prefix ${envs}/prokaWGS roary -w        # roary version line
    # conda run --prefix ${envs}/snippy snippy --version  # snippy 4.0.2

# ==============================================================================
# ← §11 全部完成。
# ==============================================================================


# ==============================================================================
# §12. 真菌精准定量增强（PHF 数据库 + MetaEuk + CGF catalog）
# ==============================================================================

# --- §12.1 CGF catalog 基因组（PRJNA833221）[✓ 已下载] ---
# 说明：Yan et al. 2024 Cell 187 发布的肠道真菌培养基因组
#       用途：参考基因组存档（db/cgf/genomes/），不直接用于分析流程
#       当前状态：709 个 .fna 文件（51 个 NCBI 已撤回，跳过）
# 安装命令（确认空间后解注释运行）：
    # mkdir -p ${db}/cgf/genomes
    # conda run --prefix ${envs}/assembly \
    #     datasets download genome accession --inputfile ${db}/cgf/PRJNA833221_accessions.txt \
    #     --include genome --filename ${db}/cgf/cgf_genomes.zip
    # unzip ${db}/cgf/cgf_genomes.zip -d ${db}/cgf/genomes/
    # ls ${db}/cgf/genomes/ | wc -l   # 应约为 709


# --- §12.2 MetaEuk 真菌宏基因组真核基因预测 [✓ 已安装] ---
# 说明：供 80b_fun_metaeuk.sh --method metaeuk 使用（默认为 Prodigal，MetaEuk 为可选增强）
#       MetaEuk 专为宏基因组真核生物 ORF 预测设计，支持含内含子的真菌基因组
#       数据库：db/metaeuk_db/fungi_refseq_mmseqs（MMseqs2 格式，由 NCBI RefSeq 真菌蛋白构建）
#       论文：Levy Karin et al. 2020, Microbiome
# 安装命令（在 envs/metaeuk 中）：
    # ${soft}/bin/conda create -y -p ${envs}/metaeuk \
    #     -c bioconda -c conda-forge metaeuk
    # conda run --prefix ${envs}/metaeuk metaeuk --version


# --- §12.3 PHF 肠道真菌数据库 [✓ 已部署] ---
# 说明：Yan et al. 2024 Cell 187 完整实现（Bowtie2 + Singular/Escrow 算法）
#       数据库来源：来自论文作者百度网盘资源（Reference/Gut_Fungi_DB/）
#       包含：760 基因组核酸基因集 + 人类/细菌/rRNA 过滤库 + GPA.py
#       运行时文件已整理至 db/gut_fungi_db/：
#         db.fungi.fa.gz          — 真菌基因集（1.3G gz，760基因组来源）
#         db.uhgg.fa.gz           — 细菌过滤库（UHGG，3.3G gz）
#         db.fungi_target.fa.gz   — rRNA 过滤库（3.8M gz）
#         db.human_chm13v2.fa.gz  — 人类宿主过滤库（916M gz）
#         GPA.py                  — Singular/Escrow 丰度计算器
#         gene2clu.map            — 基因→物种簇映射（87M）
#         clu.uniq_gene.sum       — 物种簇基因长度（4.8K）
#         db.fungi.taxonomy.tsv   — 317 簇 7 级分类注释（40K）
# Bowtie2 索引构建（一次性，约 3-5 小时，建议 screen 运行）：
    # bash scripts/74a_fun_gut_db_build.sh -t 16 -r ${PROJ_DIR}
    # # 验证：
    # ls db/gut_fungi_db/bwt.index.gut_fungi_geneset.*.bt2l
    # ls db/gut_fungi_db/bwt.index.uhgg.*.bt2
    # ls db/gut_fungi_db/bwt.index.fungi_target.*.bt2
    # ls db/gut_fungi_db/bwt.index.human_chm13v2.*.bt2


# --- §12.4 PHF 流程脚本 [✓ 已创建] ---
# 脚本：74a_fun_gut_db_build.sh  — 一次性 Bowtie2 建索引
#       74e_fun_phf_profiler.sh   — per-sample：5步过滤+Singular/Escrow（论文原方法）
#       74f_fun_phf_aggregate.sh  — 多样本 .rc 聚合 + taxonomy join
# 使用示例：
    # # 步骤1（一次性，索引已构建则跳过）：
    # bash scripts/74a_fun_gut_db_build.sh -t 16 -r ${PROJ_DIR}
    # # 步骤2（per-sample）：
    # bash scripts/74e_fun_phf_profiler.sh -s SAMPLE -t 16 \
    #      -w ${PROJ_DIR}/Project/Project_example -r ${PROJ_DIR}
    # # 步骤3（聚合）：
    # bash scripts/74f_fun_phf_aggregate.sh \
    #      -w ${PROJ_DIR}/Project/Project_example -r ${PROJ_DIR}


# ==============================================================================
# §13. Eukfinder 数据库（79_fun_eukfinder.sh 依赖）
# ==============================================================================
# 说明：Eukfinder v1.2.4 long_seqs 工作流程：
#       1. Centrifuge 初步分类（【必须】--cdb，4 个 .cf 文件）
#       2. PLAST 蛋白精确比对（【推荐】-p/-m，2.1 GB，提高注释精度）
#
# 数据库策略（本地构建，替代下载官方 70 GB）：
#   官方 Centrifuge DB 70 GB，国内下载需 5 天（~150 KB/s）
#   → 改为本地构建专用轻量 DB：NCBI RefSeq 真菌代表基因组 + 人类基因组
#     序列来源：datasets download（NCBI，速度正常）+ 已有 CHM13v2
#     构建时间：~2-4 小时（centrifuge-build -t 16）
#     最终 DB 体积：~15-20 GB
#
# 安装状态：
#   [✓ 完成] PLAST DB  — PlastDB.fasta 6.7G + PlastDB_map.txt 10M
#   [✓ 完成] 本地 Centrifuge DB — 628个真菌基因组（553成功+75跳过，39失败为含空格路径）
#     下载完成: db/eukfinder_db/centrifuge_db/raw_genomes/fungi_ftp/ (628 .gz)
#     构建中: centrifuge-build PID 759441，EukDB.{1,2,3,4}.cf 写入中（预计完成）
#     完成后验证: ls -lh ${db}/eukfinder_db/centrifuge_db/EukDB.*.cf

# --- §13.1 PLAST 数据库（已完成）---
# 验证：
    # ls -lh ${db}/eukfinder_db/PlastDB.fasta      # 6.7G ✓
    # ls -lh ${db}/eukfinder_db/PlastDB_map.txt    # 10M  ✓

# --- §13.2 本地构建 Centrifuge DB（当前使用方案）---
# 方法：从 NCBI HTTPS 逐个下载 667 个 RefSeq 真菌参考基因组 + 人类 CHM13v2
#       URL 格式: https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/{d1}/{d2}/{d3}/{acc}_{asm}/{acc}_{asm}_genomic.fna.gz
#       速度: ~1 MB/s，总下载量 ~6-7 GB，预计 ~1.5 小时

# 第一步：下载真菌基因组（后台运行，PID 3918944）
    # nohup bash ${db}/eukfinder_db/centrifuge_db/download_fungi_ftp.sh \
    #   > ${db}/eukfinder_db/centrifuge_db/download_fungi_ftp.log 2>&1 &
    # tail -f ${db}/eukfinder_db/centrifuge_db/download_fungi_ftp.log  # 监控进度

# 第二步：下载完成后一键构建索引（自动合并 fna.gz → 构建 centrifuge DB）
    # bash ${db}/eukfinder_db/centrifuge_db/build_centrifuge_db.sh
    # tail -f ${db}/eukfinder_db/centrifuge_db/build.log
    # # 构建完成后生成：EukDB.{1,2,3,4}.cf
    # ls -lh ${db}/eukfinder_db/centrifuge_db/EukDB*.cf

# --- §13.3 备用方案：官方 Centrifuge DB 下载（70 GB，~5 天）---
# 仅在无法正常访问 NCBI 时使用：
    # nohup wget -c --progress=dot:giga --tries=0 --timeout=60 --waitretry=30 \
    #   -O "${db}/eukfinder_db/centrifuge_db/centrifuge_db.tar.gz" \
    #   "https://perun.biochem.dal.ca/Eukfinder/compressed_db/centrifuge_db.tar.gz" \
    #   > "${db}/eukfinder_db/centrifuge_db/download_official.log" 2>&1 &
    # # 下载完成后解压：
    # tar -xzf "${db}/eukfinder_db/centrifuge_db/centrifuge_db.tar.gz" \
    #     -C "${db}/eukfinder_db/centrifuge_db/"

# --- §13.4 运行 79_fun_eukfinder.sh ---
# 本地构建 DB 完成后，--cdb 指向 EukDB 前缀：
    # CDB="${PROJ_DIR}/db/eukfinder_db/centrifuge_db/EukDB"
    # for s in S01 S02 S03 S04 S05 S06; do
    #   bash ${PROJ_DIR}/scripts/79_fun_eukfinder.sh \
    #     -s ${s} -t 16 \
    #     -w ${PROJ_DIR}/Project/Project_example \
    #     -r ${PROJ_DIR} \
    #     --cdb "${CDB}"
    # done

# ==============================================================================
# §13 状态：PLAST [✓] | 本地CentrifugeDB [↓ HTTPS下载中, PID 3918944]
# ==============================================================================


# ==============================================================================
# §14. 病毒维度扩展工具（70_vir_phabox2 / 71_vir_dram / 72_vir_phagcn3）
# ==============================================================================
# 说明：对比 Virus_Apptainer_pipline + ViOTUcluster 参考项目，补充三类缺口分析：
#   70 PhaBox2   — 端到端病毒/质粒分类 + 完整宿主+生活方式（比BACPHLIP更全）
#   71 DRAM-v    — 病毒功能注释 + AMG（辅助代谢基因）预测（ViOTUcluster DRAM移植）
#   72 PhaGCN3   — 深度学习图卷积病毒分类（补充vConTACT3）
#
# DB 来源：
#   PhaBox2 DB ← $HOME/Course/Virus_Apptainer_pipline/db/phabox2-db/ (已复制)
#   PhaGCN3 DB ← $HOME/Course/Virus_Apptainer_pipline/db/phagcn3-db/ (已复制)
#   DRAM DB    ← $HOME/Course/ViOTUcluster/db/DRAM/ (rsync 中，180G)

# --- §14.1 PhaBox2 [✓ 已完成] ---
# 安装：conda install -c bioconda phabox=2.1.12 (Python 3.10)
# 验证：conda run --prefix ${envs}/phabox2 phabox2 --version
    # conda create --prefix ${envs}/phabox2 python=3.10 -y
    # conda install --prefix ${envs}/phabox2 -c conda-forge -c bioconda phabox=2.1.12 -y
    # cp -r $HOME/Course/Virus_Apptainer_pipline/db/phabox2-db ${db}/phabox2_db
    # bash scripts/70_vir_phabox2.sh -t 8 -w Project/Project_example -r ${PROJ_DIR}

# --- §14.2 PhaGCN3 [✓ 已完成] ---
# 安装：conda + pytorch (CPU) + diamond + MCL + 上游源码适配
# 验证：conda run --prefix ${envs}/phagcn3 python -c "import phagcn3; print('ok')"
    # conda create --prefix ${envs}/phagcn3 python=3.10 pytorch cpuonly diamond mcl seqkit blast -y
    # cp -r $HOME/Course/Virus_Apptainer_pipline/db/phagcn3-db ${db}/phagcn3_db
    # bash scripts/72_vir_phagcn3.sh -t 8 -w Project/Project_example -r ${PROJ_DIR}

# --- §14.3 DRAM 1.5.0 [✓ 完成] ---
# 安装：conda-forge dram=1.5.0 + setuptools<81（pinned，规避 pkg_resources 移除）
# DB: db/dram_db/（180G，refseq_viral + peptidases + kofam + genome_summary_form 等）
# 测试验证：
    # bash scripts/71_vir_dram.sh -t 8 -w Project/Project_example -r ${PROJ_DIR}
# 输出：result/virus/dram/DRAM_annotations.tsv + DRAM_amg_summary.tsv ✓

# ==============================================================================
# §14 状态：PhaBox2 [✓] | PhaGCN3 [✓] | DRAM [✓]
# ==============================================================================


# ==============================================================================
# §15. 补充功能注释数据库（UniProt Swiss-Prot / Pfam / MGE 数据库组 / FeGenie / recombinase）
# ==============================================================================
# 背景：上一轮数据库梳理（）发现以下数据库在 db/ 中缺失：
#   UniProt Swiss-Prot — 高质量人工注释蛋白，DIAMOND 搜索
#   Pfam-A             — 蛋白功能域 HMM 数据库，HMMER 搜索
#   ISfinder           — 插入序列数据库（MGE 可移动遗传元素）
#   ICEberg            — 整合接合元件数据库（MGE）
#   integrall          — 整合子数据库（MGE）
#   transposase-db     — 转座酶 HMM 数据库（MGE）
#   FeGenie            — 铁代谢基因（iron uptake / cycling）预测
#   recombinase-kit    — 位点特异性重组酶注释
#
# 数据来源：
#   §15.1-15.3 均从 ${SIBLING_DB}/ 复制 ✓
#   §15.4-15.5 原参考项目使用 Apptainer 容器（DB 内嵌），本项目改用 conda 安装

# --- §15.1 UniProt Swiss-Prot [✓ 已完成] ---
# 用途：高可信度全功能蛋白注释（全长比对），补充 eggNOG/KEGG 未注释条目
# 工具：DIAMOND blastp（envs/assembly 已有 diamond 2.0.15）
# 大小：~564 MB（.dmnd 243M + .fasta 234M + .fasta.gz 87M + blast/mmseqs 索引）

    mkdir -p ${db}/uniprot_sprot

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ---- 方法0：从参考项目复制（推荐，已完成，bank 模式）----
        cp -r ${SIBLING_DB}/uniprot_sprot/* \
            ${db}/uniprot_sprot/
        echo "UniProt Swiss-Prot 就绪: ${db}/uniprot_sprot/"
    else
        # ---- 方法1：官方下载 + DIAMOND 建库（online 模式）----
        wget -c https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz \
            -O ${db}/uniprot_sprot/uniprot_sprot.fasta.gz
        gzip -dk ${db}/uniprot_sprot/uniprot_sprot.fasta.gz
        conda run --prefix ${envs}/assembly diamond makedb \
            --in ${db}/uniprot_sprot/uniprot_sprot.fasta \
            --db ${db}/uniprot_sprot/uniprot_sprot.dmnd \
            --threads 16
    fi
    ls -lh ${db}/uniprot_sprot/

# --- §15.2 Pfam-A HMM 数据库 [✓ 已完成] ---
# 用途：蛋白功能域注释（已在 VIBRANT §8.7 中使用，此处为独立注释脚本提供）
# 工具：HMMER hmmscan（envs/assembly 或 hmmer 相关环境）
# 大小：~2.4 GB（Pfam-A.hmm.gz 332M + hmmpress 4 文件共 ~2.0G）

    mkdir -p ${db}/pfam

    if [ "${INSTALL_MODE}" = "bank" ]; then
        # ---- 方法0：从参考项目复制（推荐，已完成，含 hmmpress 索引，bank 模式）----
        cp -r ${SIBLING_DB}/pfam/* \
            ${db}/pfam/
        echo "Pfam-A 就绪: ${db}/pfam/"
    else
        # ---- 方法1：官方下载 + hmmpress（online 模式）----
        wget -c https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz \
            -O ${db}/pfam/Pfam-A.hmm.gz
        gzip -dk ${db}/pfam/Pfam-A.hmm.gz
        conda run --prefix ${envs}/assembly hmmpress ${db}/pfam/Pfam-A.hmm
    fi
    ls -lh ${db}/pfam/

# --- §15.3 MGE 可移动遗传元素数据库组 [✓ 已完成] ---
# 用途：移动遗传元素（插入序列/整合接合元件/整合子/转座酶）注释
# 工具：DIAMOND blastp（ISfinder/ICEberg/integrall）+ HMMER hmmscan（transposase-db）

    # ── ISfinder（插入序列，2.7 MB .faa + 16 MB .udb）──
    mkdir -p ${db}/ISfinder
    if [ "${INSTALL_MODE}" = "bank" ]; then
        cp -r ${SIBLING_DB}/ISfinder/* \
            ${db}/ISfinder/
        echo "ISfinder 就绪: ${db}/ISfinder/"
    else
        # ---- 方法1：官方下载 + DIAMOND 建库（online 模式）----
        wget -c https://isfinder.biotoul.fr/download/ISfinder.faa -O ${db}/ISfinder/ISfinder.faa
        conda run --prefix ${envs}/assembly diamond makedb \
            --in ${db}/ISfinder/ISfinder.faa \
            --db ${db}/ISfinder/ISfinder.dmnd --threads 16
    fi

    # ── ICEberg（整合接合元件，33 MB .fasta）──
    mkdir -p ${db}/ICEberg
    if [ "${INSTALL_MODE}" = "bank" ]; then
        cp -r ${SIBLING_DB}/ICEberg/* \
            ${db}/ICEberg/
        echo "ICEberg 就绪: ${db}/ICEberg/"
    else
        # ---- 方法1：官方下载 + BLAST 建库（online 模式）----
        wget -c https://db-mml.sjtu.edu.cn/ICEberg2/download/ICEberg.fasta \
            -O ${db}/ICEberg/ICEberg.fasta
        conda run --prefix ${envs}/assembly makeblastdb \
            -in ${db}/ICEberg/ICEberg.fasta -dbtype prot \
            -out ${db}/ICEberg/blast/ICEberg
    fi

    # ── integrall（整合子，30 MB .ffn + BLAST 索引）──
    # 注：脚本内无官方在线下载源，online/bank 两种模式均从 ${SIBLING_DB} 复制
    mkdir -p ${db}/integrall
    cp -r ${SIBLING_DB}/integrall/* \
        ${db}/integrall/
    echo "integrall 就绪: ${db}/integrall/"

    # ── transposase-db（转座酶 HMM，4.3 MB .hmm + hmmpress 索引）──
    mkdir -p ${db}/transposase-db
    if [ "${INSTALL_MODE}" = "bank" ]; then
        cp -r ${SIBLING_DB}/transposase-db/* \
            ${db}/transposase-db/
        echo "transposase-db 就绪: ${db}/transposase-db/"
    else
        # ---- 方法1：官方下载 + hmmpress（online 模式）----
        wget -c https://github.com/cjmateos/transposase-db/raw/main/transposase.hmm.gz \
            -O ${db}/transposase-db/transposase.hmm.gz
        gzip -dk ${db}/transposase-db/transposase.hmm.gz
        conda run --prefix ${envs}/assembly hmmpress ${db}/transposase-db/transposase.hmm
    fi
    ls -lh ${db}/transposase-db/

# --- §15.4 FeGenie（铁代谢基因预测）[✓ 已完成] ---
# 用途：预测铁获取（iron uptake）/ 储存 / 循环相关基因，宏基因组铁代谢功能分析
# 方法：conda 安装（bioconda fegenie 1.2，HMM 数据库随包安装）
# 大小：~50 MB（HMM 数据库内嵌于 envs/fegenie/share/fegenie-1.2/hmms/iron/）

    conda create --prefix ${envs}/fegenie -c conda-forge -c bioconda python=3.11 fegenie=1.2 -y
    conda run --prefix ${envs}/fegenie FeGenie.py -h

    # 验证 HMM 数据库
    ls -lh ${envs}/fegenie/share/fegenie-1.2/hmms/iron/

    echo "FeGenie 就绪: ${envs}/fegenie"
    echo "  10 个铁代谢功能类别 HMM："
    echo "    - Siderophore synthesis / transport（铁载体合成/转运）"
    echo "    - Heme transport / oxygenase（血红素转运/分解）"
    echo "    - Iron transport（铁直接转运）"
    echo "    - Iron oxidation / reduction（铁氧化/还原）"
    echo "    - Iron storage（铁储存，ferritin）"
    echo "    - Iron gene regulation（铁调控，Fur）"
    echo "    - Magnetosome formation（磁小体形成）"

# 测试验证：
    # bash scripts/31e_bac_fegenie.sh -s S02 -t 8 -w Project/Project_example -r ${PROJ_DIR}
# 输出：result/annotation/fegenie/S02/FeGenie-geneSummary.csv ✓（S02 检测到 1 个 iron_reduction 基因）

# --- §15.5 recombinase-kit（位点特异性重组酶）[✗ 待安装] ---
# 用途：注释酪氨酸重组酶 / 丝氨酸重组酶（整合子/转座子位点特异性重组）
# 原参考项目方式：Apptainer recombinase-kit-0.0.1.sif（DB 内嵌容器）
# 推荐替代方案：hmmscan + Pfam 子集（重组酶相关 Pfam HMM 已在 §15.2 就绪）

    # ---- 方法0：利用已有 Pfam HMM（推荐，零额外安装）----
    # 重组酶相关 Pfam 家族：PF00239（Resolvase），PF02022（Integrase），PF13495（Phage_int_SAM_5）
    # conda run --prefix ${envs}/assembly hmmscan --tblout ${WORKDIR}/result/annotation/recombinase/recombinase.tblout \
    #     --cpu 16 ${db}/pfam/Pfam-A.hmm ${WORKDIR}/result/assembly/cdhit/protein_nr.fa

    # ---- 方法1：Apptainer 方式（如有 recombinase-kit-0.0.1.sif）----
    # apptainer exec recombinase-kit-0.0.1.sif recombinase --help
    # # DB 内嵌于 SIF，无需额外配置

    echo "[INFO] recombinase-kit 尚未安装，可用 §15.2 Pfam-A HMM 通过 hmmscan 覆盖核心重组酶家族"
    echo "       Apptainer 容器方案：参见上方注释"

# --- §15.6 PlasmidFinder 2.1.6 [✓ 已完成] ---
# 用途：质粒识别（contig 层面），识别复制子类型和不相容群（Inc group）
# DB：conda 包内置（share/plasmidfinder-2.1.6/database/）— 无需单独下载
# 验证：exit 0，S02 测试通过（空结果为预期行为，测试样本深度不足）
# 对应脚本：scripts/42b_bac_plasmidfinder.sh

    # ---- 方法0：conda 安装（已完成）----
    # conda create --prefix ${envs}/plasmidfinder python=3.10 -y
    # conda install --prefix ${envs}/plasmidfinder -c conda-forge -c bioconda \
    #     plasmidfinder=2.1.6 blast -y
    # conda run --prefix ${envs}/plasmidfinder plasmidfinder.py --help

    echo "[INFO] PlasmidFinder 2.1.6 已安装于 envs/plasmidfinder"
    echo "       DB 路径: ${envs}/plasmidfinder/share/plasmidfinder-2.1.6/database/"

# ==============================================================================
# §15 状态：Swiss-Prot [✓] | Pfam [✓] | MGE 4库 [✓] | FeGenie [✓] | recombinase [✗] | PlasmidFinder [✓]
# ==============================================================================

# --- §16.1 shellcheck 0.11.0（本地伪CI静态检查层）[✓ 已完成] ---
# 用途：新增/修改的 .sh 脚本静态语法检查（git pre-commit hook 增量检查，
#       + scripts/tests/level1/run_shellcheck_all.sh 全量自查）
# 验证：envs/shellcheck/bin/shellcheck --version → 0.11.0
# 详见：docs/PROJECT_MAP.md 测试/CI 一节，或 scripts/tests/run_ci_checks.sh --help

    # mamba create -y --prefix ${envs}/shellcheck -c conda-forge "shellcheck>=0.9"
    # bash scripts/install_git_hooks.sh   # 一次性安装 pre-commit hook（符号链接）

    echo "[INFO] shellcheck 0.11.0 已安装于 envs/shellcheck"
    echo "       pre-commit hook 安装: bash scripts/install_git_hooks.sh"
    echo "       全量扫描: bash scripts/tests/level1/run_shellcheck_all.sh"
    echo "       三层CI统一入口: bash scripts/tests/run_ci_checks.sh --level all"

# ==============================================================================
# §16 状态：shellcheck [✓] | pre-commit hook [✓] | Test_CI_fixture [✓] | run_ci_checks.sh [✓]
# ==============================================================================

# --- §17.1 sylph 快速物种分类器（minhash sketch，GTDB-R220）[✓ 已完成] ---
# 用途：与 MetaPhlAn4/Kraken2 并列的第三个细菌分类工具，速度更快（官方数据
#       >50x 于同类工具），对 GTDB-R220 全库分类内存仅需 ~15GB，作为快速
#       预筛选选项，不替代现有两个工具。
# 参考：Shaw & Yu, Nature Biotechnology 2024; https://github.com/bluenote-1577/sylph

    mkdir -p ${db}/sylph
    conda create --prefix ${envs}/sylph -y
    conda install --prefix ${envs}/sylph -y sylph sylph-tax -c bioconda -c conda-forge
    conda run --prefix ${envs}/sylph sylph --version

    # 数据库下载（GTDB-R220，113,104 个物种代表基因组，-c200 灵敏版，13.1GB）
    if [ "${INSTALL_MODE}" = "online" ]; then
        # Google Cloud 镜像（官方维护，实测比主站更快）：
        wget -c https://storage.googleapis.com/sylph-stuff/gtdb-r220-c200-dbv1.syldb \
            -O ${db}/sylph/gtdb-r220-c200-dbv1.syldb

        # taxonomy metadata（sylph-tax 用于把 genome ID 转成物种名，含 GTDB_r220/r214/
        # FungiRefSeq 等全部支持的分类体系，体积小，直接用官方下载子命令即可）：
        conda run --prefix ${envs}/sylph sylph-tax download --download-to ${db}/sylph
    fi
    # 主站备用（较慢，按需解注释）：
    # wget -c http://faust.compbio.cs.cmu.edu/sylph-stuff/gtdb-r220-c200-dbv1.syldb \
    #     -O ${db}/sylph/gtdb-r220-c200-dbv1.syldb

    echo "[INFO] sylph + sylph-tax 已安装于 envs/sylph"
    echo "       数据库路径: ${db}/sylph/gtdb-r220-c200-dbv1.syldb"
    echo "       taxonomy metadata: ${db}/sylph/gtdb_r220_metadata.tsv.gz"

# ==============================================================================
# §17 状态：sylph [✓] | sylph-tax [✓] | GTDB-R220 sketch DB [✓] | taxonomy metadata [✓]
# ==============================================================================

# ==============================================================================
# §18 MetaX 数据库（15e_bac_metax.sh 依赖）
# ==============================================================================
# MetaX 跨域统一 profiler（细菌/古菌/真核/病毒/宿主一次输出），作为单域分类器的验证层。
# 版本锁定 metax 0.9.22 + 预构建 RefSeq DB（metax 2.0.1 改用 metax_db.tsv.gz/.mxi，
# 与预构建 DB 不兼容）。峰值内存 ~55G。
#
#     mkdir -p ${db}/metax
#     conda create --prefix ${envs}/metax -y python=3.9
#     conda install --prefix ${envs}/metax -y -c bioconda -c conda-forge metax=0.9.22 macmd
#
#     cd ${db}/metax
#     aria2c -x16 -s16 -k4M --file-allocation=none -c \
#         https://research.bifo.helmholtz-hzi.de/downloads/metax/metax_db.tar.xz
#     tar -xJf metax_db.tar.xz          # 勿用 pixz -d（会删除源文件）
#     # 预期产物：${db}/metax/metax_bavfph/metax_db.json
#
# ==============================================================================
# §18 状态：metax 0.9.22 [✓] | macmd [✓] | RefSeq 预构建 DB [✓]
# ==============================================================================

# ==============================================================================
# §19 GUNC 数据库（38b_bac_gunc.sh 依赖）
# ==============================================================================
# GUNC 二次质检：检测嵌合/跨谱系 bin（CheckM2 + GUNC 标准配对）。
#
#     mkdir -p ${db}/gunc
#     conda create --prefix ${envs}/gunc -y
#     conda install --prefix ${envs}/gunc -y -c bioconda -c conda-forge gunc=1.0.3
#
#     aria2c -x16 -s16 -k4M --file-allocation=none -c \
#         https://swifter.embl.de/~fullam/gunc/gunc_db_progenomes2.1.dmnd.gz -d ${db}/gunc
#     gunzip -k ${db}/gunc/gunc_db_progenomes2.1.dmnd.gz
#     # 预期 md5：bc93a855e0760aad5c4e5f2d0e26da46
#
# ==============================================================================
# §19 状态：gunc 1.0.3 [✓] | progenomes2.1 DB [✓]
# ==============================================================================
