# 快速启动指南

> 5 分钟内完成首次分析运行

---

## 1. 环境激活

每次分析前必须激活项目环境：

```bash
cd /path/to/CSCCD-MetagenomeFlow
source scripts/activate.sh
```

**首次迁移到新服务器**需额外执行一次：

```bash
bash scripts/checkm_config.sh
```

---

## 2. 准备数据

将测序数据放入项目目录：

```bash
mkdir -p Project/MyAnalysis/data
cp /path/to/your/*.fastq.gz Project/MyAnalysis/data/
```

**文件命名规范**: `{样本名}_1.fastq.gz` 和 `{样本名}_2.fastq.gz` (双端测序)

---

## 3. 配置分析参数

编辑 `pipeline/config/config.yaml`，修改以下三个必填字段：

```yaml
# 样本列表（逗号分隔，无空格）
samples: "Sample1,Sample2,Sample3"

# 工作目录（绝对路径）
workdir: "${PROJ_DIR}/Project/MyAnalysis"

# CPU 核心数（根据服务器配置调整）
cpus: 16
```

**硬件配置推荐**:
- 16 核 / 64GB 内存: `cpus: 16`, profile `auto` 或 `local_16c`
- 48 核 / 192GB 内存: `cpus: 48`, profile `48c`
- 96 核 / 512GB 内存: `cpus: 96`, profile `96c`

---

## 4. 启动分析

单命令启动完整流程：

```bash
snakemake -s pipeline/Snakefile --profile profiles/auto
```

**推荐先预览**（dry-run 模式）：

```bash
snakemake -s pipeline/Snakefile --profile profiles/auto --dry-run
```

---

## 5. 监控进度

查看实时日志：

```bash
tail -f Project/MyAnalysis/logs/snakemake_*.log
```

**预期运行时间**:
- 10 样本 × 16 核: ~12-18 小时
- 10 样本 × 48 核: ~4-6 小时
- 10 样本 × 96 核: ~2-3 小时

---

## 6. 查看结果

分析完成后，结果按维度和类型组织：

```
Project/MyAnalysis/result/
├── bacteria/              # 细菌维度结果
│   ├── metaphlan/         # 物种丰度
│   ├── humann/            # 功能通路
│   └── ...
├── virome/                # 病毒维度结果
│   ├── virsorter2/        # 病毒鉴定
│   └── ...
├── fungi/                 # 真菌维度结果
│   ├── phf_profiler/      # 真菌分类
│   └── ...
└── stats/                 # 跨维度统计
    ├── lefse/             # 差异分析
    ├── core_diversity/    # 核心多样性
    └── ...
```

---

## 下一步

- 📖 详细分析流程: [docs/PROJECT_MAP.md](PROJECT_MAP.md)
- 🛠️ 参数调优: [docs/PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)
- ❓ 遇到问题: [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- 🤖 使用技能: `README.md` 中的 22 个 `/mgx-*` 技能
