# 故障排查指南

> 常见问题诊断和解决方案

---

## 1. 环境问题

### 1.1 Conda 环境未激活

**症状**:
```
bash: snakemake: command not found
bash: metaphlan: command not found
```

**诊断**:
```bash
echo $CONDA_PREFIX
# 如果输出为空或不包含 "CSCCD-MetagenomeFlow/miniforge3"，则环境未激活
```

**解决**:
```bash
cd /path/to/CSCCD-MetagenomeFlow
source scripts/activate.sh
```

**预防**: 在 `~/.bashrc` 中添加自动激活（可选）

---

### 1.2 CheckM 数据库未配置

**症状**:
```
[CheckM - ERROR] Invalid path to marker gene file
```

**诊断**:
```bash
grep "dataRoot" ~/.checkm/config
# 应输出正确的数据库路径
```

**解决**:
```bash
bash scripts/checkm_config.sh
```

**预防**: 迁移到新服务器后首次运行必须执行该脚本

---

## 2. 依赖冲突

### 2.1 多个脚本共享输出文件

**症状**:
```
MissingOutputException: Output file XYZ.txt expected but not produced
WorkflowError: Rule X and Rule Y both produce output file XYZ.txt
```

**诊断**:
```bash
snakemake -s pipeline/Snakefile --dry-run --quiet 2>&1 | grep "Conflicting"
```

**解决**:
- 检查 `pipeline/rules/*.smk` 中是否有重复 `output:` 声明
- 修改其中一个规则的输出路径或文件名

**预防**: 新增规则时用唯一前缀命名输出文件

---

### 2.2 --force 参数误用

**症状**:
- 单样本修改触发全流程重跑
- 已完成任务被意外覆盖

**诊断**:
```bash
snakemake -s pipeline/Snakefile --dry-run | grep "forced"
# 检查有多少任务被标记为 "forced"
```

**解决**:
- **精确重跑单个规则**: `snakemake -R rule_name`
- **重跑失败任务**: `snakemake --rerun-incomplete`
- **仅在确认需要覆盖时使用 --force**

**预防**: 阅读 `pipeline/README.md` 中的 "Advanced Usage" 章节

---

## 3. 资源不足

### 3.1 内存溢出 (OOM)

**症状**:
```
Killed
slurmstepd: error: Detected X oom-kill event(s)
MemoryError: Unable to allocate array
```

**诊断**:
```bash
dmesg | grep -i "out of memory"
free -h  # 检查当前可用内存
```

**解决**:
1. **降低并行度**: 编辑 `config.yaml`，减小 `cpus` 值
2. **切换到低内存 profile**: `--profile profiles/local_16c` (而非 `96c`)
3. **分批处理样本**: 将大批次拆分为多个小批次

**内存需求参考**:
- MetaPhlAn: ~4GB/样本
- HUMAnN: ~16GB/样本
- Megahit 组装: ~32-64GB/样本
- CheckM: ~40GB (固定开销)

**预防**: 根据样本数和硬件配置选择合适的 profile

---

### 3.2 磁盘空间不足

**症状**:
```
OSError: [Errno 28] No space left on device
```

**诊断**:
```bash
df -h | grep -E "/$|/data|/tmp"
du -sh Project/*/temp  # 检查临时文件占用
```

**解决**:
1. **清理临时文件**:
   ```bash
   # 删除中间文件（保留最终结果）
   rm -rf Project/MyAnalysis/temp/*/intermediate_*
   ```

2. **清理旧日志**:
   ```bash
   find Project/*/logs -name "*.log" -mtime +30 -delete
   ```

3. **移动数据库到大容量盘**:
   ```bash
   mv db /data/large_disk/
   ln -s /data/large_disk/db db
   ```

**空间需求参考**:
- 原始数据 (fastq.gz): ~10-50GB/样本
- 临时文件: ~100-200GB/样本
- 最终结果: ~5-10GB/样本
- 数据库: ~1.1TB (固定)

**预防**: 分析前确保至少有 `样本数 × 200GB` 可用空间

---

### 3.3 CPU 线程数过高

**症状**:
- 系统响应缓慢
- 任务调度延迟
- `top` 显示 load average > CPU 核心数 × 2

**诊断**:
```bash
nproc  # 查看可用 CPU 核心数
pstree -p | grep megahit | wc -l  # 统计活跃任务数
```

**解决**:
编辑 `config.yaml`，降低 `cpus`:
```yaml
cpus: 16  # 从 48 降到 16
```

**线程分配策略**:
- **16 核服务器**: 单任务 8-12 线程，并行 2 任务
- **48 核服务器**: 单任务 16 线程，并行 3 任务
- **96 核服务器**: 单任务 16-24 线程，并行 4-6 任务

**预防**: 不要将 `cpus` 设置为超过物理核心数的值

---

## 4. 数据格式问题

### 4.1 FASTQ 文件命名不规范

**症状**:
```
KeyError: 'Sample1' not found in samples list
Input file Sample1_1.fq.gz not found
```

**诊断**:
```bash
ls Project/MyAnalysis/data/*.fastq.gz
# 检查文件名是否为 {样本名}_1.fastq.gz 和 {样本名}_2.fastq.gz
```

**解决**:
批量重命名：
```bash
cd Project/MyAnalysis/data
for f in *.fq.gz; do
  mv "$f" "${f%.fq.gz}.fastq.gz"
done
```

**标准命名格式**:
- ✅ `Sample1_1.fastq.gz` 和 `Sample1_2.fastq.gz`
- ❌ `Sample1_R1.fastq.gz` (错误后缀)
- ❌ `Sample1.1.fq.gz` (错误扩展名)

**预防**: 数据准备时统一命名格式

---

### 4.2 Metadata 文件缺失必需列

**症状**:
```
KeyError: 'Group' not found in metadata
ValueError: Sample ID mismatch between fastq and metadata
```

**诊断**:
```bash
head -1 Project/MyAnalysis/metadata.tsv
# 检查是否包含 "SampleID" 和 "Group" 列
```

**解决**:
编辑 `metadata.tsv`，确保包含必需列：
```tsv
SampleID	Group	Age	Sex
Sample1	Control	25	M
Sample2	Treatment	30	F
```

**必需列**:
- `SampleID`: 与 fastq 文件名匹配
- `Group`: 分组信息（用于统计分析）

**可选列**: `Age`, `Sex`, `BMI`, `Disease`, 等

**预防**: 使用模板文件 `Project/Project_example/metadata.tsv`

---

## 5. 权限问题

### 5.1 数据库只读

**症状**:
```
PermissionError: [Errno 13] Permission denied: 'db/metaphlan/mpa_vJan21_CHOCOPhlAnSGB_202103.pkl'
```

**诊断**:
```bash
ls -ld db/
ls -l db/metaphlan/*.pkl
```

**解决**:
```bash
chmod -R u+w db/
```

**预防**: 数据库目录应由当前用户拥有且可写

---

### 5.2 临时目录不可写

**症状**:
```
OSError: [Errno 30] Read-only file system: '/tmp/snakemake.XXXX'
```

**诊断**:
```bash
touch /tmp/test_write && rm /tmp/test_write
# 如果失败，则 /tmp 不可写
```

**解决**:
指定可写的临时目录：
```bash
export TMPDIR=$HOME/tmp
mkdir -p $TMPDIR
snakemake -s pipeline/Snakefile --profile profiles/auto
```

**预防**: 在 HPC 环境中始终指定用户临时目录

---

## 6. 特定工具错误

### 6.1 VirSorter2 "setuid bit" 错误

**症状**:
```
ERROR : Installation issue: starter-suid doesn't have setuid bit set
```

**原因**: VirSorter2 依赖 Apptainer/Singularity 容器，与 执行沙箱冲突

**解决**: 见 `docs/experience/apptainer-sandbox-noprivs-conflict.md`

**预防**: VirSorter2 任务必须通过 宿主 Bash执行，不能通过 Codex

---

### 6.2 CheckM "Marker gene placement" 卡住

**症状**: CheckM 任务长时间无输出（>2 小时）

**诊断**:
```bash
ps aux | grep checkm
# 检查 CPU 使用率，如果接近 0% 则可能卡住
```

**解决**:
1. 杀死卡住的进程: `pkill -9 checkm`
2. 清理不完整输出: `rm -rf Project/MyAnalysis/temp/checkm/incomplete_run`
3. 重新运行: `snakemake --rerun-incomplete`

**预防**: CheckM 对某些低质量组装可能卡住，考虑跳过该步骤或使用 CheckM2

---

## 7. 快速诊断流程

遇到错误时，按以下顺序排查：

1. **检查环境**: `echo $CONDA_PREFIX`
2. **检查日志**: `tail -50 Project/*/logs/snakemake_*.log`
3. **检查资源**: `free -h && df -h`
4. **检查进程**: `ps aux | grep -E "snakemake|metaphlan|megahit"`
5. **重现错误**: `snakemake --dry-run`

---

## 更多帮助

- 📖 性能调优: [docs/PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)
- 📖 项目架构: [docs/PROJECT_MAP.md](PROJECT_MAP.md)
- 🤖 自动诊断: 使用 `/mgx-tune` 技能获取配置建议
