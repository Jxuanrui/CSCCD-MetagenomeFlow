# MaxMetagenome v1.1.1 Patch 优化与更改清单

**更新日期**: 2026-08-19  
**适用版本**: v1.1.0 → v1.1.1  
**更新范围**: 工程质量加固 + inStrain 菌株追踪集成

---

## 一、工程质量加固（2026-08-18 发现并修复）

### 1.1 pipefail + EXIT_CODE 捕获冲突修复

**问题根源**:
- `set -euo pipefail` 全局启用后，任何管道命令失败会立即退出脚本
- 约30个脚本依赖手动 EXIT_CODE 捕获实现"优雅降级"（如零数据行时跳过而非报错）
- 管道失败时，`EXIT_CODE=$?` 根本执行不到，导致降级逻辑失效

**修复方案**:
```bash
# 修复前（会在管道失败时直接退出）
some_command | filter_pipeline
EXIT_CODE=$?

# 修复后（临时关闭 pipefail，确保捕获成功）
set +e
some_command | filter_pipeline
EXIT_CODE=$?
set -e
```

**影响脚本**（已全部修复）:
- `96_stat_functional.sh`: defense/prophage/virulence 三个统计分支
- `95b_stat_batch_evaluate.sh`: silhouette 评估管道
- `98d_fun_integration_tables.sh`: 真菌整合表管道
- 其他约27个带 EXIT_CODE 捕获的统计/整合脚本

**验证方式**:
```bash
# 零数据行场景应产出 SKIPPED sentinel，而非 exit 1
bash scripts/96_stat_functional.sh -w Project/Project01 -r ~/Course/Maxmetagenome
# 预期输出: result/statistics/bacteria/functional/defense/96_stat_functional.SKIPPED
```

### 1.2 DAS_Tool R 环境 ABI 冲突修复

**问题根源**:
- 项目全局 `R_LIBS_USER` 指向 R 4.5.3 编译的 Rlib
- DAS_Tool 环境 (`envs/dastool`) 自带 R 4.4.3
- R 4.4 → 4.5 跨越 ABI 边界，`data.table` 等包二进制不兼容
- DAS_Tool 内部 R 脚本加载 data.table 时崩溃（`Error in envRefInferField`）

**修复方案** (commit df1f1c5):
```bash
# 脚本 36_bac_dastool.sh 中，DAS_Tool 调用前临时清空 R_LIBS_USER
env -u R_LIBS_USER conda run --prefix "${REPO}/envs/dastool" --no-capture-output \
    DAS_Tool --threads "${CPUS}" -i "${INPUTS}" -l "${LABELS}" ...
```

**影响**: 所有调用 `36_bac_dastool.sh` 的流程（Snakemake / 手动执行）

---

## 二、inStrain 菌株追踪集成（2026-07-29 至 2026-08-05）

### 2.1 新增脚本

| 脚本编号 | 功能 | 输入 | 输出 |
|---------|------|------|------|
| `39b_bac_instrain_map.sh` | 比对到去冗余 MAG 集（per-sample）| dRep 去冗余 MAG + kneaddata reads | `{sample}.sorted.bam` |
| `39c_bac_instrain_profile.sh` | 菌株级微多样性分析（per-sample）| 39b BAM + combined_mags.fa + .stb | `{sample}_genome_info.tsv` |
| `39d_bac_instrain_compare.sh` | 跨样本 popANI 比较（aggregate）| 全样本 profile 目录 | `*_genomeWide_compare.tsv` |

### 2.2 核心设计决策

**combined_mags.fa 构建**:
- 跨样本共享，只构建一次（首次运行 39b 时）
- 自动从 `result/binning/drep/dereplicated_genomes/*.fa` 拼接
- 文件锁机制避免并行样本重复构建

**scaffold-to-bin 映射 (.stb)**:
- 跨样本共享，只构建一次（首次运行 39c 时）
- 用 `envs/drep/bin/parse_stb.py --reverse` 自动生成
- inStrain profile/compare 均依赖此文件

**零 MAG 情况处理**:
- 若 dRep 输出为空（0 MAG），39b/39c 创建空哨兵并 exit 0
- 39d（跨样本聚合）若样本数<2，优雅跳过并给出提示

### 2.3 Snakemake 集成

**新增规则** (`pipeline/rules/bacteria_binning.smk`):
```python
rule instrain_map:      # 39b, per-sample
    input: drep_dereplicated_genomes, kneaddata_reads
    output: "{sample}.sorted.bam"

rule instrain_profile:  # 39c, per-sample
    input: instrain_map_bam, combined_mags_fa, stb
    output: "{sample}_genome_info.tsv"

rule instrain_compare:  # 39d, aggregate
    input: expand(..., sample=SAMPLES)
    output: "*_genomeWide_compare.tsv"
```

**依赖链更新**:
```
38 dRep → 39 coverm_quant → 39b instrain_map → 39c instrain_profile → 39d instrain_compare → 40 gtdbtk
```

### 2.4 Agents 技能卡集成

**新增 YAML** (`agents/skills/`):
- `39b_bac_instrain_map.yaml`
- `39c_bac_instrain_profile.yaml`
- `39d_bac_instrain_compare.yaml`

**registry.yaml 更新**:
- 总脚本数: 94 → 97
- inStrain 3 条依赖链记录完整

### 2.5 实测验证

**Project01 真实数据**（213 个去冗余 MAG，10 样本）:
- combined_mags.fa: 530 MB, 32,537 scaffolds
- 39b map: 每样本耗时 ~6-12 分钟
- 39c profile: 每样本耗时 ~8-15 分钟
- 39d compare: 10 样本 45 对组合，耗时 ~25 分钟

**输出示例** (`39d_bac_instrain_compare.sh` 产出):
- `comparisonsTable.tsv`: 45 行（10 样本对组合）
- `genomeWide_compare.tsv`: popANI 矩阵（genome × sample_pair）
- `strain_comparison_summary.tsv`: 每个 MAG 的最小 popANI + same_strain 判定

---

## 三、文档同步更新

### 3.1 Tutorial.md 更新

**新增章节**:
- §步骤 02b: R1/R2 严格重新配对（修复 kneaddata 输出顺序错位）
- §步骤 36b: Post-binning Reassembly（metaWRAP 精细重组装）
- §步骤 39b-d: inStrain 菌株追踪（map → profile → compare）

**更新内容**:
- 版本号: v1.1 → v1.1.1 (2026-08-19)
- 流程链注释: 在步骤 39（coverm_quant）后追加 "39b-d inStrain"
- 执行进度表: 追加 39b/39c/39d 行，状态标记"✅ 已集成 Snakemake"

### 3.2 README.md 更新

**版本信息**:
- 追加 v1.1.1 patch 说明（错误处理加固）
- 分析能力统计更新:
  - 脚本数: 144 → 168
  - --force 支持率: 136/144 (94.4%) → 137/146 (93.8%)
  - 明确标注 inStrain 菌株追踪模块

**平台参数表更新**:
- 分析脚本: 168 (01–98f + utilities)
- Snakemake 规则: 138（包含 39b-d 三条新规则）

### 3.3 PROJECT_MAP.md 更新

**细菌维度分析表**（39 行后追加）:
```markdown
| 39b | bac_instrain_map     | inStrain 比对（per-sample BAM）         | ✅ | agents/skills/39b_bac_instrain_map.yaml     |
| 39c | bac_instrain_profile | inStrain 菌株级微多样性分析（per-sample）| ✅ | agents/skills/39c_bac_instrain_profile.yaml |
| 39d | bac_instrain_compare | inStrain 跨样本 popANI 比较（aggregate） | ✅ | agents/skills/39d_bac_instrain_compare.yaml |
```

---

## 四、已知限制与待办事项

### 4.1 已知限制

**inStrain compare 规模限制**:
- 当前实现: 全样本两两比较（N 样本 → N(N-1)/2 对）
- 大规模项目（N>50）计算时间随 N² 增长
- 暂无亚采样/分组比较策略

**popANI 生物学意义**:
- popANI ≥ 0.99999 判定"同一菌株"基于 inStrain 默认阈值
- 不同研究场景可能需要调整此阈值（目前硬编码在 39d 脚本中）

### 4.2 待办事项（后续版本）

**CI 集成测试覆盖**:
- 当前 Test_CI_fixture 无 binning 产出（无 dastool/checkm2/drep）
- 计划: 用 T01+T02 两样本建最小前置链，测试 39b/39c/39d

**inStrain 高级功能**:
- 基因级 SNP 功能注释（`-g GENE_FILE` + `parse_annotations`）
- 当前只做菌株级 popANI 追踪，未接入基因级分析

**98d MAG 整合表关联**:
- inStrain compare 结果尚未自动接入 `98d_bac_integration_tables.sh`
- 若需要，作为独立任务在后续版本实现

---

## 五、回归测试建议

### 5.1 核心流程验证

**完整 binning 链**（涵盖所有修复点）:
```bash
# 单样本测试（Sample2，真实数据）
bash scripts/32_bac_coverm_depth.sh -s Sample2 -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome
bash scripts/33_bac_metabat2.sh -s Sample2 -w Project/Project01 -r ~/Course/Maxmetagenome
bash scripts/34_bac_maxbin2.sh -s Sample2 -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome
bash scripts/35_bac_semibin2.sh -s Sample2 -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome
bash scripts/36_bac_dastool.sh -s Sample2 -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome --force
# 预期: DAS_Tool 成功整合，产出 N 个 bins（N>0），无 R ABI 报错

# 跨样本聚合测试（涵盖 inStrain 全链条）
bash scripts/37_bac_checkm2.sh -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome
bash scripts/38_bac_drep.sh -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome
bash scripts/39b_bac_instrain_map.sh -s Sample2 -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome
bash scripts/39c_bac_instrain_profile.sh -s Sample2 -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome
bash scripts/39d_bac_instrain_compare.sh -t 16 -w Project/Project01 -r ~/Course/Maxmetagenome
# 预期: 39d 产出 strain_comparison_summary.tsv，行数 = dRep 去冗余 MAG 数
```

### 5.2 零数据行优雅降级验证

```bash
# 制造零数据场景（临时删除 defense 表）
mv Project/Project01/result/statistics/bacteria/functional/defense/merged_defense_counts.tsv{,.bak}
bash scripts/96_stat_functional.sh -w Project/Project01 -r ~/Course/Maxmetagenome
# 预期: 产出 96_stat_functional.SKIPPED sentinel，exit 0

# 恢复数据
mv Project/Project01/result/statistics/bacteria/functional/defense/merged_defense_counts.tsv{.bak,}
```

### 5.3 Snakemake 干运行验证

```bash
cd Project/Project01
snakemake -s ../../pipeline/Snakefile \
  --configfile ../../pipeline/config/config.yaml \
  --profile ../../pipeline/profiles/local_48c \
  -n
# 预期: DAG 包含 instrain_map/instrain_profile/instrain_compare 三条规则
# grep "instrain" 应有 3 × N_samples + 1 条任务（N per-sample map/profile + 1 aggregate compare）
```

---

## 六、升级路径

### 6.1 从 v1.1.0 升级到 v1.1.1

**必须操作**:
```bash
cd ~/Course/Maxmetagenome
git pull origin master  # 获取最新脚本
source scripts/activate.sh  # 重新激活环境（确保 envs/instrain 可用）
```

**可选操作**（若已有 v1.1.0 运行结果）:
- 若 36_bac_dastool.sh 曾报错 "envRefInferField" → 用 `--force` 重跑该样本
- 若 96_stat_functional.sh 等统计脚本在零数据行时异常退出 → 重跑即可（现已优雅降级）
- 若想启用 inStrain 菌株追踪 → 从 39b 开始跑（前提: 38 dRep 已完成）

**不需要操作**:
- 已完成的 fastp/kneaddata/metaphlan4/humann3/megahit/binning 结果**无需重跑**
- 数据格式向后兼容，无 schema 破坏性变更

### 6.2 新项目从零开始

遵循 Tutorial.md 完整流程即可，所有修复已自动生效。

---

## 七、贡献者与审核

**主要修复**:
- pipefail + EXIT_CODE 冲突: Claude Code + 人工审核（2026-08-18）
- DAS_Tool R ABI 冲突: Claude Code 调试 + 验证（commit df1f1c5）
- inStrain 集成: Claude Code 实现 + Project01 真实数据验证（2026-07-29 至 2026-08-05）

**文档同步**:
- Tutorial.md / README.md / PROJECT_MAP.md 全面更新（2026-08-19）

**回归测试**:
- Project01 全 10 样本 Snakemake 主流程验证（2026-08-19 启动，预计 16-20 小时完成）

---

**本清单自动生成**: 2026-08-19  
**对应 Git 提交**: df1f1c5（DAS_Tool fix）及后续 inStrain 集成系列提交
