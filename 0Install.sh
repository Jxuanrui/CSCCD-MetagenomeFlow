#!/usr/bin/env bash
# ==============================================================================
# MaxMetagenome 软件和数据库安装脚本
# 版本: 0.1  日期: 2026/05/29
# 平台: Linux x86_64 ubuntu22.04
# 作者：Jxuanrui
# ------------------------------------------------------------------------------
# 安装进度（已完成节在此记录，下次从 ✗ 处继续）
#   [✓] §0   初始化（Miniforge3 + 通道 + activate.sh + Rscript）  2026/06/01  测试通过
#   [✓] §1.1 fastp 0.22.0                                         2026/06/01  测试通过
#   [✓] §1.2 kneaddata v0.12.4 + bowtie2                          2026/06/01  测试通过
#   [✓] §1.3 KneadData 数据库（human/mouse/rat，各 6 个 bt2）     2026/06/01  测试通过
#   [✓] §2.1 humann v3.9 + MetaPhlAn4 v4.2.4 + diamond 2.0.15    2026/06/01  测试通过（端到端输出 3 个 tsv）
#   [✓] §2.2 HUMAnN4 数据库（chocophlan 12773 + uniref 34G + mapping 20）  2026/06/01  测试通过
#   [✓] §2.3 MetaPhlAn4 数据库（mpa_vOct22_CHOCOPhlAnSGB_202212，已识别）  2026/06/01  测试通过
#   [✓] §2.4 LEfSe（biobakery channel）                           2026/06/01  测试通过
#   [✓] §2.5 Kraken2 2.1.3 + Bracken 3.1                         2026/06/01  测试通过
#   [✓] §2.6 Kraken2 数据库（pluspf_20240112，hash 77G，classify 正常）     2026/06/01  测试通过
#   [✓] §3.1 assembly（MEGAHIT 1.2.9 / SPAdes 3.15.5 / QUAST 5.0.2 / Prodigal 2.6.3 / CD-HIT 4.8.1 / salmon 1.2.0）  2026/06/01  测试通过（MEGAHIT 端到端）
#   [✓] §3.2 eggNOG-mapper 2.1.13（pip 安装，Python 3.9）         2026/06/01  测试通过
#   [✓] §3.3 eggNOG 数据库（5.0.2，39G+8.7G，--data_dir 参数指定，无软链接）  2026/06/01  测试通过（DB version 5.0.2 识别）
#   [✓] §4.1 MetaWRAP 1.3.2（--no-channel-priority 安装）          2026/06/01  测试通过
#   [✓] §4.2 CheckM 数据库（10 个文件，~/.checkm/DATA_CONFIG 配置）2026/06/01  测试通过
#   [✓] §4.3 dRep 3.6.2 + CheckM 1.2.5（pip 安装 + networkx）     2026/06/01  测试通过
#   [✓] §4.4 CoverM 0.7.0                                          2026/06/01  测试通过
#   [✓] §4.5 GTDB-Tk 2.5.2（tqdm=4.66.4 先固定）                  2026/06/01  测试通过
#   [✓] §4.6 GTDB-Tk 数据库（160 GB，13 个目录/文件）              2026/06/01  测试通过
#   [✓] §4.7 CheckM2（Python 3.8 + scikit-learn=0.23.2 + numpy<1.24）  2026/06/01  测试通过
#   [✓] §4.8 CheckM2 数据库（uniref100.KO.1.dmnd 2.9 GB）          2026/06/01  测试通过
#   [✓] §5.1 VIBRANT 1.2.1（envs/vibrant）+ CheckV（envs/checkv）  2026/06/01  测试通过（zlib冲突已拆分独立环境）
#   [✓] §5.2 AMRFinderPlus 3.10.1 + RGI 4.0.3 + CARD 数据库       2026/06/01  测试通过
#   [✓] §5.3 dbCAN3 + 数据库（3.5 GB）                             2026/06/01  测试通过
#   [✓] §5.4 StrainPhlAn4 4.2.4（复用 humann4 环境）               2026/06/03  测试通过（补装 samtools/mafft/fasttree）
#   [✓] §5.5 antiSMASH 7.1.0（--no-channel-priority 安装）         2026/06/01  测试通过
#   [✓] §5.6 FastSpar（SparCC）                                    2026/06/01  测试通过
#   [✓] §6.2 CRAN 包（vegan 2.7.5 / ggplot2 4.0.3 / dplyr 等 16 个）  2026/06/01  测试通过
#   [✓] §6.3 Bioconductor 包（phyloseq / DESeq2 / edgeR / microbiome / treeio / Maaslin2）  2026/06/01  测试通过
#   [✓] §6.4 ANCOMBC 2.12.0 + ggtree 4.0.4（conda bioconda 安装）  2026/06/01  测试通过
#   [✓] §7.1 assembly 环境扩充（centrifuger 1.0.5 / mmseqs2 13.45 / seqtk 1.4）  2026/06/02  测试通过
#   [✓] §7.3 genomad 1.12.0（独立环境，--no-channel-priority）                    2026/06/02  测试通过
#   [✓] §7.5 功能注释数据库（vfdb/bacmet/merops/sarg/phi/mvirdb/tcdb/ncyc/pcyc/amrfinder/genomad）  2026/06/02  测试通过
#   [✓] §7.4 centrifuger 数据库（166 GB，7 个文件）                              2026/06/02  测试通过
#   [✓] §7.5 KEGG 数据库（48 GB）                                                 2026/06/02  测试通过
# ------------------------------------------------------------------------------
# 待配置（Binning 流程新增工具，来自 Binning_Apptainer_pipline）:
#   [✓] §8.1 MetaBAT2 2.12.1 + MaxBin2 2.2.6（追加进 metawrap）+ SemiBin2 1.5.0  2026/06/02  测试通过
#   [✓] §8.2 DAS_Tool 1.1.7（独立环境）                                           2026/06/02  测试通过
#   [✓] §8.3 Bakta 1.12.0（独立环境 + 数据库 3.8 GB）                             2026/06/02  测试通过
#   [✓] §8.4 Defense-Finder 3.0.0（独立环境 + 数据库 320 MB）                     2026/06/02  测试通过
#   [✓] §8.5 MobileOG 数据库（19 GB，diamond 搜索）                               2026/06/02  测试通过
#   [✓] §8.6 CCyc 12G + MCyc 638M + SCyc 642M 数据库（各含1个子目录）            2026/06/02  测试通过
#   [✓] §8.7 VIBRANT 数据库（11G，KEGG 9995 + VOG 19182 + Pfam，hmmpress 完成）  2026/06/02  测试通过
#   [✓] §8.8 antiSMASH 数据库（从 Apptainer 项目解压，9.4 GB）                   2026/06/02  测试通过（10 个模块目录）
#   [✗] §9   MCP / RAG 服务   ← 最终步骤
# ==============================================================================


# ==============================================================================
# 0. 初始化  ——  每次安装前必须先运行本节  [✓ 2026/06/01]
# ==============================================================================

# --- 0.1 项目路径 ---

    # 自动获取脚本所在目录作为项目根目录
    PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    soft=${PROJ_DIR}/miniforge3   # Miniforge3 安装目录
    envs=${PROJ_DIR}/envs         # 各工具 conda 独立环境目录
    db=${PROJ_DIR}/db             # 数据库目录
    tools=${PROJ_DIR}/tools       # 辅助脚本目录

    mkdir -p ${envs} ${db} ${tools}
    echo "项目根目录: ${PROJ_DIR}"


# --- 0.2 Miniforge3 安装（安装在项目目录内，不修改 ~/.bashrc） ---

    # 若已存在则跳过，否则从镜像下载安装
    if [ -f "${soft}/bin/conda" ]; then
        echo "Miniforge3 已存在: ${soft}"
    else
        wget http://mirror.example-server.invalid:63332/static/Miniforge3-25.3.1-0-Linux-x86_64.sh \
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
# 1. 数据预处理工具  [✓ 2026/06/01]
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

    # ----
    # 方法0：从百度云链接进行下载配置
    # ----
    cp /data/mydirectory/db/kneaddata/human/* ${db}/kneaddata/human/
    cp /data/mydirectory/db/kneaddata/mouse/* ${db}/kneaddata/mouse/
    cp /data/mydirectory/db/kneaddata/rat/*   ${db}/kneaddata/rat/

    # ----
    # 方法1：NMDC 国内镜像下载（国内服务器推荐，速度较快）
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

    # ----
    # 方法2：官方地址下载
    # ----
    # 人类基因组 hg37（Huttenhower Lab）
    # kneaddata_database --download human_genome bowtie2 ${db}/kneaddata/human

    # 人类基因组 hg39/T2T（更新版本，3.6 GB）
    # wget -c https://huttenhower.sph.harvard.edu/kneadData_databases/Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz \
    #     -O ${db}/kneaddata/human/Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz
    # tar xvzf ${db}/kneaddata/human/Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz \
    #     -C ${db}/kneaddata/human/ && rm -f ${db}/kneaddata/human/*.tar.gz

    # 小鼠基因组 C57BL/6NJ（官方，2.83 GB）
    # wget -c http://huttenhower.sph.harvard.edu/kneadData_databases/mouse_C57BL_6NJ_Bowtie2_v0.1.tar.gz \
    #     -O ${db}/kneaddata/mouse/mouse_C57BL_6NJ_Bowtie2_v0.1.tar.gz
    # tar xvzf ${db}/kneaddata/mouse/mouse_C57BL_6NJ_Bowtie2_v0.1.tar.gz \
    #     -C ${db}/kneaddata/mouse/ && rm -f ${db}/kneaddata/mouse/*.tar.gz

    # 大鼠基因组 Rnor_6.0（bowtie2 index，S3）
    # wget -c https://genome-idx.s3.amazonaws.com/bt/Rnor_6.0.zip \
    #     -O ${db}/kneaddata/rat/Rnor_6.0.zip
    # unzip ${db}/kneaddata/rat/Rnor_6.0.zip -d ${db}/kneaddata/rat/ \
    #     && rm -f ${db}/kneaddata/rat/Rnor_6.0.zip

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
    conda run --prefix ${envs}/humann4 pip install humann
    conda run --prefix ${envs}/humann4 pip install metaphlan

    # 安装 StrainPhlAn4 运行时必须依赖（2026-06-03 补充，mamba 求解更稳定）
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

    # ----
    # 方法0：从本服务器复制（最快）
    # ----
    cp -r /data/mydirectory/db/humann3/chocophlan/*    ${db}/humann4/chocophlan/
    cp -r /data/mydirectory/db/humann3/uniref/*        ${db}/humann4/uniref/
    cp -r /data/mydirectory/db/humann3/utility_mapping/* ${db}/humann4/utility_mapping/

    # ----
    # 方法1：官方下载（humann v3.9 兼容版本）
    # ----
    # chocophlan 全库（42 GB）
    # wget -c http://huttenhower.sph.harvard.edu/humann_data/chocophlan/chocophlan.v201901_v31.tar.gz \
    #     -O ${db}/humann4/chocophlan.tar.gz
    # tar xvzf ${db}/humann4/chocophlan.tar.gz -C ${db}/humann4/chocophlan/ \
    #     && rm -f ${db}/humann4/chocophlan.tar.gz
    # uniref90 diamond 索引（893 MB）
    # wget -c http://huttenhower.sph.harvard.edu/humann_data/uniprot/uniref_annotated/uniref90_annotated_v201901b.tar.gz \
    #     -O ${db}/humann4/uniref90.tar.gz
    # tar xvzf ${db}/humann4/uniref90.tar.gz -C ${db}/humann4/uniref/ \
    #     && rm -f ${db}/humann4/uniref90.tar.gz
    # utility_mapping（2.7 GB）
    # wget -c http://huttenhower.sph.harvard.edu/humann_data/full_mapping_v201901b.tar.gz \
    #     -O ${db}/humann4/mapping.tar.gz
    # tar xvzf ${db}/humann4/mapping.tar.gz -C ${db}/humann4/utility_mapping/ \
    #     && rm -f ${db}/humann4/mapping.tar.gz

    # ----
    # 方法2：NMDC 国内镜像
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

    # ----
    # 方法0：从本服务器复制（最快）
    # ----
    cp /data/mydirectory/db/metaphlan4/* ${db}/metaphlan4/

    # ----
    # 方法1：NMDC 国内镜像（202403 最新版，推荐）
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar \
    #     -O ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
    # tar xvf ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar -C ${db}/metaphlan4/ \
    #     && rm -f ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
    # wget -c ftp://download.nmdc.cn/tools/meta/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar.gz \
    #     -O ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar.gz
    # tar xvzf ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar.gz -C ${db}/metaphlan4/ \
    #     && rm -f ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar.gz

    # ----
    # 方法2：官方下载
    # ----
    # wget -c http://cmprod1.cibio.unitn.it/biobakery4/metaphlan_databases/mpa_vOct22_CHOCOPhlAnSGB_202403.tar \
    #     -O ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
    # tar xvf ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar -C ${db}/metaphlan4/ \
    #     && rm -f ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
    # wget -c http://cmprod1.cibio.unitn.it/biobakery4/metaphlan_databases/bowtie2_indexes/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar \
    #     -O ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar
    # tar xvf ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar -C ${db}/metaphlan4/ \
    #     && rm -f ${db}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar

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

    # ----
    # 方法0：从本服务器复制（最快）
    # ----
    cp /data/mydirectory/db/kraken2/pluspf/* ${db}/kraken2/pluspf/

    # ----
    # 方法1：官方 S3 下载
    # ----
    # v=20251015
    # PlusPF-16（压缩 11.2 GB，解压 14.9 GB，适合内存 ≤ 32 GB）
    # wget -c https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_16_GB_${v}.tar.gz \
    #     -O ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz
    # tar xvzf ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz -C ${db}/kraken2/pluspf16g/ \
    #     && rm -f ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz
    # PlusPF 完整版（压缩 77.5 GB，解压 100.6 GB，适合内存 ≥ 128 GB）
    # wget -c https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_${v}.tar.gz \
    #     -O ${db}/kraken2/k2_pluspf_${v}.tar.gz
    # tar xvzf ${db}/kraken2/k2_pluspf_${v}.tar.gz -C ${db}/kraken2/pluspf/ \
    #     && rm -f ${db}/kraken2/k2_pluspf_${v}.tar.gz

    # ----
    # 方法2：NMDC 国内镜像
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/kraken2/k2_pluspf_16_GB_${v}.tar.gz \
    #     -O ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz
    # tar xvzf ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz -C ${db}/kraken2/pluspf16g/ \
    #     && rm -f ${db}/kraken2/k2_pluspf_16_GB_${v}.tar.gz

    echo "Kraken2 数据库就绪: ${db}/kraken2/"
    ls ${db}/kraken2/pluspf/ | head -5


# ==============================================================================
# 3. 组装分析工具  [✓ 2026/06/01]
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
    conda run --prefix ${envs}/eggnog pip install eggnog-mapper
    conda run --prefix ${envs}/eggnog emapper.py --data_dir ${db}/eggnog --version 2>&1 | grep "Installed eggNOG DB"


# --- 3.3 eggNOG 数据库  [✓ 5.0.2 / eggnog.db 39G / eggnog_proteins.dmnd 8.7G / --data_dir 参数指定] ---

    mkdir -p ${db}/eggnog

    # ----
    # 方法0：从本服务器复制（最快，约 59 GB）
    # ----
    cp /data/mydirectory/db/eggnog/eggnog.db                    ${db}/eggnog/
    cp /data/mydirectory/db/eggnog/eggnog_proteins.dmnd          ${db}/eggnog/
    cp /data/mydirectory/db/eggnog/eggnog.taxa.db                ${db}/eggnog/
    cp /data/mydirectory/db/eggnog/eggnog.taxa.db.traverse.pkl   ${db}/eggnog/

    # ----
    # 方法1：NMDC 国内镜像
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/eggnog/eggnog.tar.gz \
    #     -O ${db}/eggnog/eggnog.tar.gz
    # tar xvzf ${db}/eggnog/eggnog.tar.gz -C ${db}/eggnog/ \
    #     && rm -f ${db}/eggnog/eggnog.tar.gz

    # ----
    # 方法2：官方脚本下载（eggnog.db 6.3G + eggnog_proteins.dmnd 4.9G，解压后约 48 GB）
    # ----
    # conda run --prefix ${envs}/eggnog \
    #     download_eggnog_data.py -y -f --data_dir ${db}/eggnog

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
# 4. Binning 工具  [✓ 2026/06/01]
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

    # ----
    # 方法0：从本服务器复制（1.7 GB）
    # ----
    cp -r /data/mydirectory/db/checkm/* ${db}/checkm/

    # ----
    # 方法1：官方下载（275 MB 压缩，解压 1.4 GB）
    # ----
    # wget -c https://data.ace.uq.edu.au/public/CheckM_databases/checkm_data_2015_01_16.tar.gz \
    #     -O ${db}/checkm/checkm_data_2015_01_16.tar.gz
    # tar xvf ${db}/checkm/checkm_data_2015_01_16.tar.gz -C ${db}/checkm/ \
    #     && rm -f ${db}/checkm/checkm_data_2015_01_16.tar.gz

    # ----
    # 方法2：NMDC 镜像
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
    conda run --prefix ${envs}/drep pip install drep checkm-genome networkx
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

    # ----
    # 方法0：从本服务器复制（160 GB）
    # ----
    cp -r /data/mydirectory/db/gtdbtk-2.3.2/* ${db}/gtdbtk/

    # ----
    # 方法1：官方下载
    # ----
    # wget -c https://data.gtdb.ecogenomic.org/releases/latest/auxillary_files/gtdbtk_package/full_package/gtdbtk_data.tar.gz \
    #     -O ${db}/gtdbtk/gtdbtk_data.tar.gz
    # tar xvzf ${db}/gtdbtk/gtdbtk_data.tar.gz -C ${db}/gtdbtk/ --strip 1 \
    #     && rm -f ${db}/gtdbtk/gtdbtk_data.tar.gz

    # ----
    # 方法2：NMDC 镜像
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
        checkm2 tensorflow-cpu wrapt requests
    conda run --prefix ${envs}/checkm2 checkm2 -h 2>&1 | grep -v "tensorflow\|cuda\|CPU\|Warning\|AVX" | head -5


# --- 4.8 CheckM2 数据库  [✓ uniref100.KO.1.dmnd 2.9 GB] ---

    mkdir -p ${db}/checkm2

    # ----
    # 方法0：从本服务器复制（2.9 GB）
    # ----
    cp -r /data/mydirectory/db/checkm2/* ${db}/checkm2/

    # ----
    # 方法1：官方下载
    # ----
    # conda run --prefix ${envs}/checkm2 \
    #     checkm2 database --download --path ${db}/checkm2

    # ----
    # 方法2：NMDC 镜像
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/checkm2/uniref100.KO.1.dmnd.tar.gz \
    #     -O ${db}/checkm2/uniref100.KO.1.dmnd.tar.gz
    # tar xvzf ${db}/checkm2/uniref100.KO.1.dmnd.tar.gz -C ${db}/checkm2/ \
    #     && rm -f ${db}/checkm2/uniref100.KO.1.dmnd.tar.gz

    # CheckM2 数据库路径已写入 scripts/activate.sh，source 后自动生效
    echo "CheckM2 数据库就绪: ${db}/checkm2/"
    ls ${db}/checkm2/CheckM2_database/

# ==============================================================================
# 5. 深度挖掘工具  [✓ 2026/06/01]
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
    # 方法0：本服务器无现成数据库，请使用方法1或方法2
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
    # 方法0：本服务器无现成数据库，请使用方法1或方法2
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
    # ----
    # 方法0：从本服务器复制（48 MB）
    # ----
    cp /data/mydirectory/db/card/* ${db}/card/
    # 方法1：官方下载
    # wget -c https://card.mcmaster.ca/latest/data \
    #     -O ${db}/card/card-data.tar.gz
    # tar xvf ${db}/card/card-data.tar.gz -C ${db}/card/ \
    #     && rm -f ${db}/card/card-data.tar.gz
    # 方法2：NMDC 镜像
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
    # ----
    # 方法0：从本服务器复制（3.5 GB）
    # ----
    cp /data/mydirectory/db/dbcan3/* ${db}/dbcan3/
    # 方法1：官方下载
    # wget -c https://bcb.unl.edu/dbCAN2/download/CAZyDB.07262023.fa \
    #     -O ${db}/dbcan3/CAZyDB.07262023.fa
    # wget -c https://bcb.unl.edu/dbCAN2/download/dbCAN-HMMdb-V12.txt \
    #     -O ${db}/dbcan3/dbCAN-HMMdb-V12.txt
    # 方法2：NMDC 镜像
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
    # 方法0：本服务器无现成数据库，请使用方法1或方法2
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


# --- 6.4 activate.sh 中加入 Rlib 路径 ---

    # 将 Rlib 路径写入 activate.sh，每次 source 后 R 自动找到项目包
    echo "export R_LIBS_USER=\"${PROJ_DIR}/Rlib\"" \
        >> ${PROJ_DIR}/scripts/activate.sh


# --- 6.5 版本验证 ---

    ${PROJ_DIR}/miniforge3/bin/Rscript -e "
    lib <- '${PROJ_DIR}/Rlib'
    .libPaths(c(lib, .libPaths()))
    pkgs <- c('vegan','ggplot2','phyloseq','DESeq2','ANCOMBC','ggtree','Maaslin2')
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

    # ----
    # 方法0：从 Apptainer 项目复制（最快）
    # ----
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/centrifuger/* ${db}/centrifuger/

    # ----
    # 方法1：官方下载
    # ----
    # wget -c https://genome-idx.s3.amazonaws.com/centrifuger/cfr_gtdb_r226+refseq_hvfc.tar.gz \
    #     -O ${db}/centrifuger/cfr_gtdb_r226+refseq_hvfc.tar.gz
    # tar xvzf ${db}/centrifuger/cfr_gtdb_r226+refseq_hvfc.tar.gz -C ${db}/centrifuger/ \
    #     && rm -f ${db}/centrifuger/*.tar.gz
    echo "Centrifuger 数据库就绪: ${db}/centrifuger/"


# --- 7.5 功能注释数据库（从 Apptainer 项目复制）---

    # VFDB 毒力因子（2.0 GB）
    mkdir -p ${db}/vfdb
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/vfdb/* ${db}/vfdb/
    echo "VFDB 就绪: ${db}/vfdb/"

    # BacMet 重金属抗性基因（867 MB）
    mkdir -p ${db}/bacmet
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/bacmet-db/* ${db}/bacmet/
    echo "BacMet 就绪: ${db}/bacmet/"

    # MEROPS 蛋白酶（3.7 GB）
    mkdir -p ${db}/merops
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/merops/* ${db}/merops/
    echo "MEROPS 就绪: ${db}/merops/"

    # KEGG diamond 索引（48 GB）
    mkdir -p ${db}/kegg
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/kegg/* ${db}/kegg/
    echo "KEGG 就绪: ${db}/kegg/"

    # NCBI AMRFinder 数据库（488 MB，amr 环境已有工具）
    mkdir -p ${db}/amrfinder
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/amrfinder-db/* ${db}/amrfinder/
    echo "AMRFinder 数据库就绪: ${db}/amrfinder/"

    # SARG+ 污水抗性基因库（264 MB）
    mkdir -p ${db}/sarg
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/sarg+-db/* ${db}/sarg/
    echo "SARG+ 就绪: ${db}/sarg/"

    # PHI 植物-微生物互作（946 MB）
    mkdir -p ${db}/phi
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/phi/* ${db}/phi/
    echo "PHI 就绪: ${db}/phi/"

    # mVIRdb 微生物病毒数据库（1.2 GB）
    mkdir -p ${db}/mvirdb
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/mvirdb/* ${db}/mvirdb/
    echo "mVIRdb 就绪: ${db}/mvirdb/"

    # TCDB 转运载体数据库（982 MB）
    mkdir -p ${db}/tcdb
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/tcdb/* ${db}/tcdb/
    echo "TCDB 就绪: ${db}/tcdb/"

    # NCyc 氮循环（214 MB）
    mkdir -p ${db}/ncyc
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/ncyc-db/* ${db}/ncyc/
    echo "NCyc 就绪: ${db}/ncyc/"

    # PCyc 磷循环（846 MB）
    mkdir -p ${db}/pcyc
    cp -r /home/labuser/Course/Metagenomics_Apptainer_pipline/db/pcyc-db/* ${db}/pcyc/
    echo "PCyc 就绪: ${db}/pcyc/"


# --- 7.6 genomad 数据库（2.6 GB）---

    mkdir -p ${db}/genomad

    # ----
    # 方法0：从压缩包解压（Apptainer 项目有 tar.gz）
    # ----
    tar xvzf /home/labuser/Course/Metagenomics_Apptainer_pipline/db/genomad.tar.gz \
        -C ${db}/genomad/ 2>/dev/null \
        || echo "genomad.tar.gz 解压失败，请使用方法1"

    # ----
    # 方法1：官方下载
    # ----
    # conda run --prefix ${envs}/genomad genomad download-database ${db}/genomad
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
    tar xvzf /home/labuser/Course/Binning_Apptainer_pipline/db/bakta.tar.gz \
        -C ${db}/bakta/ 2>/dev/null && echo "Bakta 数据库就绪: ${db}/bakta/" \
        || echo "bakta.tar.gz 解压失败"


# --- 8.4 Defense-Finder 防御系统检测（独立环境）---

    # 注：defense-finder 与 amr 环境有依赖冲突，需独立环境
    conda create --prefix ${envs}/defense-finder -y
    conda install --prefix ${envs}/defense-finder -y defense-finder -c bioconda -c conda-forge
    conda run --prefix ${envs}/defense-finder conda list | grep "^defense-finder"

    # Defense-Finder 数据库
    mkdir -p ${db}/defense-finder
    tar xvzf /home/labuser/Course/Binning_Apptainer_pipline/db/defense-finder-db.tar.gz \
        -C ${db}/defense-finder/ 2>/dev/null && echo "Defense-Finder 数据库就绪" \
        || echo "defense-finder-db.tar.gz 解压失败"


# --- 8.5 MobileOG-db 可移动遗传元素数据库 ---

    # MobileOG 无 conda 包，通过 pip 安装；数据库直接解压使用
    conda run --prefix ${envs}/amr pip install mobileog -q 2>/dev/null \
        || echo "mobileog pip 安装失败，可通过 diamond 直接搜索数据库"

    # MobileOG 数据库（从 Binning 项目解压，约 5.8 GB）
    mkdir -p ${db}/mobileog
    tar xvzf /home/labuser/Course/Binning_Apptainer_pipline/db/mobileOG-db.tar.gz \
        -C ${db}/mobileog/ 2>/dev/null && echo "MobileOG 数据库就绪: ${db}/mobileog/" \
        || echo "mobileOG-db.tar.gz 解压失败"


# --- 8.6 代谢通路数据库（CCyc / MCyc / SCyc）---

    # 从 Binning 项目解压（碳循环/甲烷循环/硫循环）
    mkdir -p ${db}/ccyc ${db}/mcyc ${db}/scyc

    tar xvzf /home/labuser/Course/Binning_Apptainer_pipline/db/ccyc-db.tar.gz \
        -C ${db}/ccyc/ 2>/dev/null && echo "CCyc 就绪: ${db}/ccyc/" \
        || echo "ccyc-db.tar.gz 解压失败"

    tar xvzf /home/labuser/Course/Binning_Apptainer_pipline/db/mcyc-db.tar.gz \
        -C ${db}/mcyc/ 2>/dev/null && echo "MCyc 就绪: ${db}/mcyc/" \
        || echo "mcyc-db.tar.gz 解压失败"

    tar xvzf /home/labuser/Course/Binning_Apptainer_pipline/db/scyc-db.tar.gz \
        -C ${db}/scyc/ 2>/dev/null && echo "SCyc 就绪: ${db}/scyc/" \
        || echo "scyc-db.tar.gz 解压失败"


# --- 8.7 VIBRANT 数据库  [✓ 11G / KEGG 9995 + VOG 19182 + Pfam / hmmpress 完成] ---

    # 注：官方 download-db.sh 依赖 KEGG FTP（日本），速度极慢（~16 KB/s）
    # 推荐方法0：使用本服务器已有 kofam_profiles 直接构建（约 30 分钟）
    mkdir -p ${db}/vibrant

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
    KOFAM_DIR=/home/labuser/Course/ViOTUcluster/db/DRAM/kofam_profiles/profiles
    cd ${db}/vibrant/databases
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

    # ----
    # 方法0：从 Apptainer 项目解压（推荐）
    # ----
    # 注：解压后数据库实际路径为 ${db}/antismash/antismash-db/
    # 使用时：antismash --databases ${db}/antismash/antismash-db
    tar xzf /home/labuser/Course/Metagenomics_Apptainer_pipline/db/antismash-db.tar.gz \
        -C ${db}/antismash/ \
        && echo "antiSMASH 数据库就绪: ${db}/antismash/antismash-db/ ($(ls ${db}/antismash/antismash-db/ | wc -l) 个模块)"

    # ----
    # 方法1：官方自动下载（约 10 GB）
    # ----
    # conda run --prefix ${envs}/antismash \
    #     download-antismash-databases --database-dir ${db}/antismash

    # ----
    # 方法2：NMDC 镜像
    # ----
    # wget -c ftp://download.nmdc.cn/tools/meta/antismash/antismash_db.tar.gz \
    #     -O ${db}/antismash/antismash_db.tar.gz
    # tar xvzf ${db}/antismash/antismash_db.tar.gz -C ${db}/antismash/ \
    #     && rm -f ${db}/antismash/antismash_db.tar.gz


# ==============================================================================
# ← 下次从此处开始：§9 MCP / RAG 服务
# ==============================================================================
