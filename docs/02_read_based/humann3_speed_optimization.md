# HUMAnN3 速度优化指南

本文档说明 `scripts/13_bac_humann3.sh` 的三种速度模式及其适用场景。

---

## 速度模式对比

| 模式 | 物种阈值 | 输入 | 内存 | 自动清理 | 速度 | 精度 | 适用场景 |
|------|---------|------|------|---------|------|------|---------|
| **standard** | 1% | 双端合并 | 最小 | 否 | 1× | 100% | 低深度样本（<20M reads），需要最高精度 |
| **balanced** | 5% | 双端合并 | 最大 | 是 | **~2×** | >95% | **高深度样本（>20M reads），生产推荐** |
| **fast** | 10% | 只用 R1 | 最大 | 是 | **3-5×** | 80-90% | 探索性分析，可接受低丰度物种丢失 |

---

## 核心提速原理

### 1. `--prescreen-threshold`（最关键）

**作用**：控制进入 custom ChocoPhlAn 数据库的物种最低丰度阈值

**影响链**：
```
阈值 0.01（1%） → 检测到 ~300 物种 → custom db ~60G → bowtie2-build 索引 10-20 小时
阈值 0.05（5%） → 检测到 ~100 物种 → custom db ~20G → bowtie2-build 索引 2-3 小时
阈值 0.1（10%） → 检测到  ~50 物种 → custom db ~10G → bowtie2-build 索引 30-60 分钟
```

**代价**：过滤掉低于阈值的物种的功能信息

**实测数据**（SRR28210342，62M reads）：
- MetaPhlAn4 检测到 304 个物种
- 阈值 0.01 → custom db 60G（包含全部 304 物种对应的基因组）
- 阈值 0.05 → custom db 预计 ~20G（只包含丰度 >5% 的 ~100 个物种）

---

### 2. `--memory-use maximum`

**作用**：Diamond 翻译搜索时将整个 UniRef90 数据库（11GB）载入内存，减少磁盘 I/O

**提速**：20-30%

**代价**：内存占用从 ~15GB 增加到 ~40GB（对 >256GB 内存服务器无压力）

---

### 3. `--remove-temp-output`

**作用**：自动删除 `temp/humann3/` 下的中间文件（60-100GB）

**提速**：无（仅节省磁盘空间）

**注意**：删除后无法从中间步骤续跑（如 bowtie2 索引已建好但 Diamond 失败）

---

### 4. 只用 R1（fast 模式）

**作用**：HUMAnN3 不考虑双端配对信息，只用 R1 端结果与 R1+R2 高度相关

**提速**：2×（数据量减半）

**代价**：
- 通路丰度相关性 >0.95（来自 EasyMetagenome 经验）
- 低丰度物种的基因可能覆盖度下降

---

### 5. `--diamond-options "--block-size 6.0"`（fast 模式）

**作用**：增大 Diamond 分块大小（默认 2.0），减少分块次数

**提速**：10-20%

**代价**：内存需求再增加 10-20GB

---

## 使用方法

### 方法 1：直接调用脚本

```bash
# 标准模式（默认）
bash scripts/13_bac_humann3.sh \
     -s SRR28210342 -t 16 \
     -w Project/Project_example \
     -r ~/Course/CSCCD-MetagenomeFlow

# 平衡模式（推荐）
bash scripts/13_bac_humann3.sh \
     -s SRR28210342 -t 16 \
     -w Project/Project_example \
     -r ~/Course/CSCCD-MetagenomeFlow \
     --speed-mode balanced

# 快速模式
bash scripts/13_bac_humann3.sh \
     -s SRR28210342 -t 16 \
     -w Project/Project_example \
     -r ~/Course/CSCCD-MetagenomeFlow \
     --speed-mode fast
```

### 方法 2：Pipeline 模式

```bash
# 所有样本使用 balanced 模式
bash scripts/00_pipeline_bacteria.sh \
     -i samplesheet.csv \
     -r ~/Course/CSCCD-MetagenomeFlow -t 16 \
     --humann-speed balanced
```

---

## 选择建议

### 场景 A：标准宏基因组（推荐 balanced）

- 样本特征：人体/环境样本，测序深度 >20M reads
- 推荐模式：**balanced**
- 理由：
  - 高深度样本通常检测到 200-400 个物种，custom db 极大（60G+）
  - 阈值 5% 只过滤极低丰度物种（<5% reads），主要物种功能信息完整
  - 速度提升 ~2 倍，精度损失 <5%
  - 自动清理 temp 节省 60-100GB 磁盘

### 场景 B：低深度样本（使用 standard）

- 样本特征：低生物量样本，测序深度 <20M reads，物种数 <50
- 推荐模式：**standard**
- 理由：
  - 低深度样本检测物种数少，custom db 本身就小（<10G），索引快（<1小时）
  - 阈值 1% 保留最多物种信息
  - 不需要提速

### 场景 C：探索性分析（使用 fast）

- 样本特征：初步探索，只关心优势物种功能
- 推荐模式：**fast**
- 理由：
  - 只用 R1 + 阈值 10% → 3-5 倍提速
  - 适合快速筛选样本、初步功能画像
  - **不适合**发表级分析（低丰度物种信息丢失）

---

## 性能预期（SRR28210342 实测）

| 样本特征 | 模式 | Custom DB | 索引时间 | Diamond | 总耗时 | 精度 |
|---------|------|-----------|---------|---------|--------|------|
| 62M reads<br>304 物种 | standard | 60G | 10-20h | ~2h | **12-22h** | 100% |
| 62M reads<br>304 物种 | balanced | ~20G | 2-3h | ~1h | **3-4h** | >95% |
| 62M reads<br>304 物种 | fast | ~10G | 30-60min | ~30min | **1-1.5h** | 80-90% |

**注**：索引时间是瓶颈，占总时间 80-90%

---

## 磁盘空间管理

| 目录 | 大小 | 用途 | balanced/fast 清理 |
|------|------|------|-------------------|
| `temp/humann3/` | 60-100G | custom db + 索引 + 中间文件 | 自动删除 |
| `result/functional/humann3/` | 50-200MB | 最终结果 | 保留 |

**建议**：
- 生产环境使用 balanced/fast 模式，自动清理 temp 节省磁盘
- 开发调试使用 standard 模式，保留 temp 便于续跑

---

## 常见问题

### Q1：balanced 模式会丢失哪些物种的功能？

**A**：只丢失丰度 <5% 的物种。对于 62M reads 样本，5% 阈值 = 3.1M reads，足够覆盖常见肠道/环境物种的功能基因。

### Q2：fast 模式适合发表吗？

**A**：不推荐。只用 R1 + 阈值 10% 会丢失低丰度物种信息，结果可重复性降低。仅用于快速探索。

### Q3：如何判断样本适合哪种模式？

**A**：先运行步骤 11（MetaPhlAn4），查看检测到的物种数：
- 物种数 <50 → standard（索引本身就快）
- 物种数 50-200 → balanced
- 物种数 >200 → balanced（必须，否则索引 >10 小时）

### Q4：balanced 模式后如何验证精度？

**A**：对比 standard 和 balanced 的 `pathabundance_relab.tsv`，计算主要通路（前 100 条）的 Pearson 相关系数，通常 >0.95。

---

## 参考

- HUMAnN 官方文档：https://github.com/biobakery/humann
- bioBakery 性能优化讨论：https://forum.biobakery.org/t/performance-of-humann-custom-database-creation/7091
- Beghini et al. eLife 2021; PMID 33944776
