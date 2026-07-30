# MaxMetagenome Docker Image
# 完整宏基因组分析平台容器化

FROM ubuntu:22.04 AS base

# 避免交互式配置提示
ENV DEBIAN_FRONTEND=noninteractive

# 系统依赖
RUN apt-get update && apt-get install -y \
    bash \
    wget \
    curl \
    git \
    build-essential \
    bzip2 \
    ca-certificates \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

# 创建非 root 用户 (与典型 HPC 环境一致)
RUN useradd -m -u 1000 -s /bin/bash mgxuser

WORKDIR /home/mgxuser/Maxmetagenome

# ============================================================
# 阶段 2: 复制平台文件并清理
# ============================================================

FROM base AS builder

# 复制脚本和配置文件
COPY --chown=mgxuser:mgxuser scripts/ ./scripts/
COPY --chown=mgxuser:mgxuser pipeline/ ./pipeline/
COPY --chown=mgxuser:mgxuser agents/ ./agents/
COPY --chown=mgxuser:mgxuser docs/ ./docs/
COPY --chown=mgxuser:mgxuser .claude/skills/ ./.claude/skills/
COPY --chown=mgxuser:mgxuser README.md ./

# 复制 Conda 环境 (最大体积部分)
COPY --chown=mgxuser:mgxuser miniforge3/ ./miniforge3/
COPY --chown=mgxuser:mgxuser envs/ ./envs/

# 清理 Conda 缓存和不必要文件
RUN rm -rf miniforge3/pkgs/* \
    && find miniforge3/ -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
    && find miniforge3/ -name "*.pyc" -delete \
    && find miniforge3/ -name "*.pyo" -delete \
    && find envs/ -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
    && find envs/ -name "*.pyc" -delete \
    && find envs/ -name "*.pyo" -delete \
    && find envs/ -name "pkgs" -type d -exec rm -rf {} + 2>/dev/null || true

# ============================================================
# 阶段 3: 运行时环境
# ============================================================

FROM base AS runtime

# 从 builder 复制清理后的文件
COPY --from=builder --chown=mgxuser:mgxuser /home/mgxuser/Maxmetagenome /home/mgxuser/Maxmetagenome

# 复制 entrypoint 脚本
COPY --chown=mgxuser:mgxuser docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 切换到非 root 用户
USER mgxuser

# 环境变量
ENV PATH="/home/mgxuser/Maxmetagenome/miniforge3/bin:${PATH}" \
    PROJ_DIR="/home/mgxuser/Maxmetagenome" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# 挂载点声明 (数据库和项目目录)
VOLUME ["/home/mgxuser/Maxmetagenome/db", "/home/mgxuser/Maxmetagenome/Project"]

# 工作目录
WORKDIR /home/mgxuser/Maxmetagenome

# 入口脚本
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 默认命令 (交互式 shell)
CMD ["/bin/bash"]

# 元数据
LABEL maintainer="MaxMetagenome Team" \
      description="Complete metagenomics analysis platform with bacteria/virome/fungi dimensions" \
      version="1.1.0"
