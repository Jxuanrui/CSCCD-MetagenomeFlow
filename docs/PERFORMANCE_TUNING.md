# 性能调优指南

> 硬件配置推荐和参数优化策略

---

## 1. 硬件配置推荐

### 1.1 入门级 (16 核 / 64GB 内存)

**适用场景**: 小批量样本 (≤5)，探索性分析

**配置文件**:
```yaml
# pipeline/config/config.yaml
samples: "Sample1,Sample2,Sample3"
workdir: "/path/to/project"
cpus: 12              # 保留 4 核给系统
memory_mb: 51200      # 50GB (保留 14GB 给系统)
```

**Snakemake 启动**:
```bash
snakemake -s pipeline/Snakefile --profile profiles/local_16c -j 2
```

**预期性能**:
- **3 样本**: ~8-12 小时
- **5 样本**: ~15-20 小时
- **并行度**: 2 任务同时运行
- **瓶颈**: 内存密集型任务 (HUMAnN, Megahit, CheckM)

**优化建议**:
1. 禁用内存消耗最大的步骤:
   ```yaml
   # 跳过真菌组装（节省 ~30GB/样本）
   skip_fungi_assembly: true
   ```

2. 减少 HUMAnN 数据库大小:
   ```bash
   # 使用 Uniref50 替代 Uniref90
   humann_config --update database_folders uniref /path/to/uniref50
   ```

---

### 1.2 标准级 (48 核 / 192GB 内存)

**适用场景**: 中等批量 (10-20 样本)，常规科研分析

**配置文件**:
```yaml
# pipeline/config/config.yaml
cpus: 40              # 保留 8 核给系统
memory_mb: 163840     # 160GB (保留 32GB 给系统)
```

**Snakemake 启动**:
```bash
snakemake -s pipeline/Snakefile --profile profiles/48c -j 3
```

**预期性能**:
- **10 样本**: ~4-6 小时
- **20 样本**: ~8-12 小时
- **并行度**: 3-4 任务同时运行
- **瓶颈**: CPU 密集型任务 (Diamond, Bowtie2, Megahit)

**优化建议**:
1. 启用中间文件缓存:
   ```yaml
   cache_intermediate: true
   cache_dir: "/fast_ssd/cache"  # 使用 SSD 加速
   ```

2. 调整单任务线程数:
   ```yaml
   # 高 CPU 任务分配更多线程
   metaphlan_threads: 16
   humann_threads: 16
   megahit_threads: 24
   ```

---

### 1.3 高性能级 (96 核 / 512GB 内存)

**适用场景**: 大批量 (50+ 样本)，生产环境

**配置文件**:
```yaml
# pipeline/config/config.yaml
cpus: 88              # 保留 8 核给系统
memory_mb: 458752     # 448GB (保留 64GB 给系统)
```

**Snakemake 启动**:
```bash
snakemake -s pipeline/Snakefile --profile profiles/96c -j 6
```

**预期性能**:
- **10 样本**: ~2-3 小时
- **50 样本**: ~8-12 小时
- **100 样本**: ~20-30 小时
- **并行度**: 6-8 任务同时运行
- **瓶颈**: 磁盘 I/O (数据库访问频繁)

**优化建议**:
1. **数据库放在高速存储**:
   ```bash
   # 将 1.1TB 数据库迁移到 NVMe SSD
   rsync -av --progress db/ /nvme/db/
   ln -s /nvme/db db
   ```

2. **启用 Snakemake 集群模式**:
   ```bash
   # 使用 SLURM 调度器
   snakemake -s pipeline/Snakefile --profile profiles/hpc_slurm \
     --cluster "sbatch -p high_mem -c {threads} --mem={resources.mem_mb}"
   ```

3. **预加载数据库到内存**:
   ```bash
   # 将常用数据库缓存到 /dev/shm (RAM disk)
   cp db/metaphlan/*.pkl /dev/shm/
   export METAPHLAN_DB_DIR=/dev/shm
   ```

---

## 2. 瓶颈识别与优化

### 2.1 CPU 密集型任务 (TOP 10)

| 任务 | 平均耗时 (16C) | 优化策略 |
|------|---------------|---------|
| **Megahit 组装** | 60-120 分钟/样本 | 增加 `megahit_threads` 到 24-32 |
| **Diamond blastp** | 30-60 分钟/样本 | 使用 `--sensitive` 替代 `--more-sensitive` |
| **Bowtie2 比对** | 20-40 分钟/样本 | 增加 `bowtie2_threads` 到 16 |
| **MetaPhlAn** | 15-30 分钟/样本 | 使用 `--index latest` (更小索引) |
| **Prodigal** | 10-20 分钟/样本 | 无需优化 (已高效) |
| **HMMER** | 10-15 分钟/样本 | 增加线程数 |
| **Kraken2** | 5-10 分钟/样本 | 使用标准数据库而非 Plus |
| **VirSorter2** | 30-60 分钟/样本 | 降低 `--min-score` 阈值 |
| **CheckM** | 40-80 分钟/批次 | 使用 CheckM2 (快 5-10 倍) |
| **eggNOG-mapper** | 20-40 分钟/样本 | 增加 `--cpu` 参数 |

---

### 2.2 内存密集型任务 (TOP 5)

| 任务 | 峰值内存 | 优化策略 |
|------|---------|---------|
| **CheckM** | ~40GB (固定) | 单独运行，避免并行 |
| **Megahit** | 32-64GB/样本 | 降低 `--min-count` 或使用 `--memory 0.8` |
| **HUMAnN** | 16-32GB/样本 | 使用 Uniref50 数据库 |
| **Kraken2** | 50GB (数据库加载) | 使用 MiniKraken (8GB) |
| **MetaPhlAn** | 4-8GB/样本 | 无需优化 |

**并行策略**:
```yaml
# 内存密集型任务限制并行度
local_rule_threads:
  checkm: 16        # CheckM 独占 40GB
  megahit: 24       # 单次运行，避免多样本并行
  humann: 16        # 最多 2 样本并行 (2×16GB=32GB)
```

---

### 2.3 磁盘 I/O 密集型任务

**特征**: CPU 和内存使用率低，但 `iotop` 显示高读写

**常见任务**:
- 数据库查询 (MetaPhlAn, Kraken2)
- 大文件写入 (Megahit 组装输出)
- 日志文件频繁写入

**优化策略**:

1. **使用 SSD 存储数据库**:
   ```bash
   # HDD → SSD 性能提升: ~3-5 倍
   mv db/metaphlan /ssd/db/metaphlan
   ln -s /ssd/db/metaphlan db/metaphlan
   ```

2. **减少日志写入频率**:
   ```yaml
   # config.yaml
   log_level: "WARNING"  # 从 "INFO" 降低到 "WARNING"
   ```

3. **启用文件系统缓存**:
   ```bash
   # 增加 Linux 文件缓存
   sudo sysctl -w vm.vfs_cache_pressure=50
   ```

---

## 3. 并行度调优

### 3.1 Snakemake `-j` 参数 vs. `cpus` 配置

**概念区分**:
- **`-j` (jobs)**: Snakemake 同时运行的规则数
- **`cpus`**: 单个规则可用的线程数

**最佳配置**:
```
总 CPU 核心数 = -j × cpus + 系统保留 (4-8 核)
```

**示例**:
```bash
# 48 核服务器
snakemake -j 3 --profile profiles/48c  # 3 任务 × 16 线程 = 48 核
# config.yaml: cpus: 16

# 96 核服务器
snakemake -j 6 --profile profiles/96c  # 6 任务 × 16 线程 = 96 核
# config.yaml: cpus: 16
```

**常见错误**:
```bash
# ❌ 错误: 过度订阅
snakemake -j 8 --profile profiles/48c  # 8 × 16 = 128 > 48 核

# ✅ 正确
snakemake -j 3 --profile profiles/48c  # 3 × 16 = 48 核
```

---

### 3.2 动态并行度调整

**场景**: 不同阶段任务特性不同

**策略**:
```yaml
# config.yaml - 按任务类型动态分配
rule_specific_threads:
  # I/O 密集型: 低线程，高并行
  fastp: 4           # -j 12 (48 核服务器)
  
  # CPU 密集型: 高线程，低并行
  megahit: 32        # -j 1 (独占模式)
  
  # 平衡型: 中等配置
  metaphlan: 16      # -j 3
```

**实施**:
```bash
# 阶段 1: 质控 (I/O 密集)
snakemake -j 12 --until fastp_qc

# 阶段 2: 组装 (CPU 密集)
snakemake -j 1 --until megahit

# 阶段 3: 注释 (平衡)
snakemake -j 3
```

---

## 4. 缓存策略

### 4.1 可安全删除的中间文件

**释放空间但保留结果**:

```bash
# 质控中间文件 (~50GB/样本)
rm -rf Project/*/temp/kneaddata/*_contam_*.fastq

# 组装中间文件 (~30GB/样本)
rm -rf Project/*/temp/megahit/intermediate_contigs

# 比对中间文件 (~20GB/样本)
rm -rf Project/*/temp/bowtie2/*.sam  # 保留 .bam 即可
```

**按需手动清理**（仓库不内置自动清理脚本）:
```bash
find Project/*/temp -name "*intermediate*" -delete
find Project/*/temp -name "*.sam" -delete  # 保留 .bam
find Project/*/logs -name "*.log" -mtime +30 -delete
```

---

### 4.2 不可删除的关键文件

**删除后需完全重跑**:
- `result/kneaddata/*.kneaddata.fastq.gz` (质控后数据)
- `result/assembly/*.contigs.fa` (组装结果)
- `result/metaphlan/*.tsv` (物种丰度表)
- `result/humann/*_genefamilies.tsv` (基因家族)

**空间占用**: ~5-10GB/样本

---

## 5. 数据库优化

### 5.1 本地 vs. 网络存储

**性能对比** (MetaPhlAn 查询延迟):
| 存储类型 | 延迟 | 吞吐量 | 推荐场景 |
|---------|------|--------|---------|
| NVMe SSD | 0.1ms | 3GB/s | 生产环境 (最佳) |
| SATA SSD | 0.5ms | 500MB/s | 标准分析 (推荐) |
| HDD (本地) | 10ms | 150MB/s | 低频分析 |
| NFS (千兆网) | 50ms | 100MB/s | ❌ 不推荐 |

**迁移建议**:
```bash
# 优先级 1: 高频访问数据库 → SSD
db/metaphlan/       # ~50GB, 每样本访问
db/humann/uniref/   # ~10GB, 每样本访问

# 优先级 2: 中频数据库 → HDD 可接受
db/kraken2/         # ~50GB, 偶尔使用
db/checkm/          # ~275MB, 每批次访问一次

# 优先级 3: 大型静态数据库 → 网络存储可接受
db/gtdb/            # ~400GB, 很少更新
```

---

### 5.2 数据库版本选择

**权衡**: 准确性 vs. 速度 vs. 空间

| 数据库 | 标准版 | 精简版 | 性能差异 |
|-------|-------|-------|---------|
| **HUMAnN Uniref** | Uniref90 (20GB) | Uniref50 (5GB) | 精简版快 3 倍 |
| **Kraken2** | Standard (50GB) | MiniKraken (8GB) | 精简版快 2 倍 |
| **GTDB** | Full (400GB) | Representative (80GB) | 精简版快 5 倍 |

**推荐配置**:
```yaml
# 科研发表: 使用标准版 (追求准确性)
humann_protein_database: "uniref90"

# 探索分析: 使用精简版 (追求速度)
humann_protein_database: "uniref50"
```

---

## 6. 实战案例

### 案例 1: 48 核服务器分析 20 样本

**初始配置** (耗时 18 小时):
```yaml
cpus: 48
snakemake -j 1  # 单任务串行
```

**优化后** (耗时 6 小时):
```yaml
cpus: 16
snakemake -j 3  # 3 任务并行
cache_intermediate: true
skip_fungi_assembly: true  # 跳过真菌组装
```

**优化效果**: 3 倍加速

---

### 案例 2: 16 核服务器 OOM 问题

**问题**: HUMAnN 运行时内存溢出

**诊断**:
```bash
dmesg | grep oom
# Out of memory: Killed process 12345 (humann)
```

**解决方案**:
1. 降低并行度: `-j 2` → `-j 1`
2. 使用 Uniref50 数据库 (减少 15GB 内存)
3. 增加 swap 空间:
   ```bash
   sudo fallocate -l 32G /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

---

## 7. 性能监控

### 7.1 实时监控命令

```bash
# CPU 使用率
htop

# 内存使用
watch -n 5 free -h

# 磁盘 I/O
iotop -o

# Snakemake 进度
tail -f Project/*/logs/snakemake_*.log | grep "of [0-9]* steps"
```

---

### 7.2 性能基准测试

**标准测试集**: Project01 (10 样本)

**运行基准**:
```bash
time snakemake -s pipeline/Snakefile --profile profiles/auto
```

**记录指标**:
- 总耗时
- 峰值内存
- 磁盘占用
- 每样本平均耗时

**性能目标** (Project01 10 样本):
- 16 核: < 18 小时
- 48 核: < 6 小时
- 96 核: < 3 小时

---

## 更多帮助

- 📖 故障排查: [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- 📖 快速启动: [docs/QUICK_START.md](QUICK_START.md)
- 🤖 自动调优: 使用 `/mgx-tune` 技能获取配置建议
