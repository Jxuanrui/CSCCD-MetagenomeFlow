# MaxMetagenome Docker 使用指南

> 完整宏基因组分析平台容器化部署

---

## 概述

MaxMetagenome Docker 镜像提供开箱即用的宏基因组分析环境，包含：
- ✅ 43 个 Conda 独立工具环境
- ✅ 97 个分析脚本（细菌/病毒/真菌三维度）
- ✅ Snakemake 自动化流程
- ✅ 22 个 Claude Code 技能

**镜像体积**: ~20-25 GB (压缩后)  
**基础镜像**: Ubuntu 22.04  
**用户**: mgxuser (UID 1000, 非 root)

---

## 快速启动

### 1. 拉取镜像 (未来可用)

```bash
docker pull meta-servergenome:latest
```

### 2. 本地构建

```bash
cd /path/to/Maxmetagenome
docker build -t meta-servergenome:latest .
```

**预期构建时间**: 10-20 分钟 (取决于网络和硬件)

---

### 3. 启动容器

#### 交互式模式 (推荐用于首次测试)

```bash
docker run -it --rm \
  -v /host/path/to/db:/home/mgxuser/Maxmetagenome/db \
  -v /host/path/to/Project:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome:latest
```

**参数说明**:
- `-it`: 交互式终端
- `--rm`: 容器退出后自动删除
- `-v`: 挂载宿主机目录（**必须使用绝对路径**）

#### 后台运行分析

```bash
docker run -d --name mgx_analysis \
  -v /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db \
  -v /data/projects:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome:latest \
  snakemake -s pipeline/Snakefile --profile profiles/auto
```

**参数说明**:
- `-d`: 后台运行
- `--name`: 容器名称（便于后续管理）

**查看日志**:
```bash
docker logs -f mgx_analysis
```

**进入运行中容器**:
```bash
docker exec -it mgx_analysis /bin/bash
```

---

## 挂载说明

### 必需挂载

#### 1. 数据库目录 (`db/`)

**宿主机路径**: `/path/to/db`  
**容器内路径**: `/home/mgxuser/Maxmetagenome/db`  
**大小**: ~1.1 TB  
**内容**: MetaPhlAn, HUMAnN, Kraken2, CheckM 等数据库

```bash
-v /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db
```

**⚠️ 重要**: 数据库未挂载时容器无法运行分析

---

#### 2. 项目目录 (`Project/`)

**宿主机路径**: `/path/to/Project`  
**容器内路径**: `/home/mgxuser/Maxmetagenome/Project`  
**用途**: 存储原始数据、中间文件、最终结果

```bash
-v /data/projects:/home/mgxuser/Maxmetagenome/Project
```

**⚠️ 重要**: 不挂载时结果保存在容器内，容器删除后数据丢失

---

### 可选挂载

#### 3. 配置文件目录

如需自定义配置：

```bash
-v /path/to/custom/config.yaml:/home/mgxuser/Maxmetagenome/pipeline/config/config.yaml:ro
```

`:ro` 表示只读挂载

---

## 常见使用场景

### 场景 1: 运行完整分析流程

```bash
# 1. 准备数据
mkdir -p /data/projects/MyAnalysis/data
cp /path/to/*.fastq.gz /data/projects/MyAnalysis/data/

# 2. 编辑配置（宿主机或容器内）
# 编辑 /data/projects/MyAnalysis/config.yaml

# 3. 启动容器运行分析
docker run -d --name mgx_myanalysis \
  -v /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db \
  -v /data/projects:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome:latest \
  bash -c "cd /home/mgxuser/Maxmetagenome && \
           snakemake -s pipeline/Snakefile \
             --config workdir=/home/mgxuser/Maxmetagenome/Project/MyAnalysis \
                      samples='Sample1,Sample2,Sample3' \
                      cpus=16 \
             --profile profiles/auto"

# 4. 监控进度
docker logs -f mgx_myanalysis

# 5. 查看结果
ls /data/projects/MyAnalysis/result/
```

---

### 场景 2: 交互式探索

```bash
docker run -it --rm \
  -v /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db \
  -v /data/projects:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome:latest

# 容器内
snakemake --version
metaphlan --version
cd Project/MyAnalysis
head result/bacteria/metaphlan/Sample1_profile.tsv
```

---

### 场景 3: 仅运行特定脚本

```bash
docker run --rm \
  -v /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db \
  -v /data/projects:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome:latest \
  bash scripts/12_bac_metaphlan.sh -s Sample1 -t 16 -w /home/mgxuser/Maxmetagenome/Project/MyAnalysis -r /home/mgxuser/Maxmetagenome
```

---

## 资源限制

### CPU 限制

```bash
docker run --cpus="16" \
  -v /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db \
  -v /data/projects:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome:latest
```

### 内存限制

```bash
docker run --memory="64g" --memory-swap="128g" \
  -v /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db \
  -v /data/projects:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome:latest
```

**推荐配置**:
- 小批量 (≤5 样本): `--cpus=8 --memory=32g`
- 中等批量 (10-20 样本): `--cpus=16 --memory=64g`
- 大批量 (50+ 样本): `--cpus=32 --memory=128g`

---

## 故障排查

### 问题 1: 数据库未挂载

**症状**:
```
⚠️ WARNING: db/ 目录为空或未挂载
```

**解决**:
检查挂载路径是否正确（必须是绝对路径）：
```bash
docker run -v /absolute/path/to/db:/home/mgxuser/Maxmetagenome/db ...
```

---

### 问题 2: 权限错误

**症状**:
```
Permission denied: /home/mgxuser/Maxmetagenome/Project/...
```

**原因**: 宿主机目录权限与容器用户 (UID 1000) 不匹配

**解决**:
```bash
# 宿主机上修改权限
sudo chown -R 1000:1000 /data/projects
```

或使用 `--user` 参数匹配宿主机用户：
```bash
docker run --user $(id -u):$(id -g) ...
```

---

### 问题 3: 内存不足

**症状**:
```
Killed
OOMKilled
```

**解决**:
1. 增加 Docker 内存限制: `--memory=128g`
2. 或降低并行度: 编辑 `config.yaml`，减小 `cpus` 值

---

### 问题 4: 磁盘空间不足

**症状**:
```
No space left on device
```

**检查容器占用**:
```bash
docker system df
```

**清理未使用镜像/容器**:
```bash
docker system prune -a
```

---

## Docker Compose (推荐生产环境)

创建 `docker-compose.yml`：

```yaml
version: '3.8'

services:
  meta-servergenome:
    image: meta-servergenome:latest
    container_name: mgx_production
    volumes:
      - /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db
      - /data/projects:/home/mgxuser/Maxmetagenome/Project
    environment:
      - PROJ_DIR=/home/mgxuser/Maxmetagenome
    cpus: 32
    mem_limit: 128g
    restart: unless-stopped
    command: snakemake -s pipeline/Snakefile --profile profiles/auto
```

**启动**:
```bash
docker-compose up -d
```

**查看日志**:
```bash
docker-compose logs -f
```

**停止**:
```bash
docker-compose down
```

---

## 与 Singularity 互转 (HPC 环境)

### Docker → Singularity

```bash
# 1. 构建 Docker 镜像
docker build -t meta-servergenome:latest .

# 2. 转换为 Singularity SIF
singularity build meta-servergenome.sif docker-daemon://meta-servergenome:latest

# 3. 运行 Singularity 容器
singularity exec \
  --bind /data/db:/home/mgxuser/Maxmetagenome/db \
  --bind /data/projects:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome.sif \
  snakemake -s pipeline/Snakefile --profile profiles/auto
```

---

## 系统要求

### 宿主机
- **Docker**: >= 20.10
- **磁盘空间**: 
  - 镜像: ~25 GB
  - 数据库: ~1.1 TB
  - 分析项目: 每样本 ~200 GB
- **内存**: >= 16 GB (推荐 64 GB)
- **CPU**: >= 8 核 (推荐 32+ 核)

### 网络
- 首次构建需下载 ~5 GB 依赖（如使用预构建镜像则不需要）

---

## 高级配置

### 使用 GPU (如有 GPU 加速工具)

```bash
docker run --gpus all \
  -v /data/meta-servergenome/db:/home/mgxuser/Maxmetagenome/db \
  -v /data/projects:/home/mgxuser/Maxmetagenome/Project \
  meta-servergenome:latest
```

### 自定义网络

```bash
docker network create mgx-network
docker run --network mgx-network ...
```

---

## 镜像管理

### 查看镜像信息

```bash
docker images meta-servergenome
docker inspect meta-servergenome:latest
```

### 导出镜像

```bash
docker save meta-servergenome:latest | gzip > meta-servergenome_latest.tar.gz
```

### 导入镜像

```bash
docker load < meta-servergenome_latest.tar.gz
```

### 推送到私有仓库

```bash
docker tag meta-servergenome:latest registry.example.com/meta-servergenome:latest
docker push registry.example.com/meta-servergenome:latest
```

---

## 更多帮助

- 📖 平台文档: `docs/PROJECT_MAP.md`
- 📖 快速启动: `docs/QUICK_START.md`
- 📖 故障排查: `docs/TROUBLESHOOTING.md`
- 📖 性能调优: `docs/PERFORMANCE_TUNING.md`
- 🐛 问题反馈: GitHub Issues

---

## License

MaxMetagenome Platform is distributed under the MIT License.
