# MaxMetagenome 文档系统索引

**更新日期**: 2026-08-19

---

## 核心文档（按使用频率排序）

### 1. 快速上手
- **Tutorial.md** — 完整使用教程，逐步审核制，面向首次使用者
  - 版本: v1.1 (2026-08 patch)
  - 包含单样本测试、批量运行、故障排查

### 2. 项目概览
- **README.md** — 项目主页，平台能力矩阵、快速启动、架构概览
  - 178 个脚本，138 条 Snakemake 规则
  - 三维度分析能力（细菌/病毒/真菌）

### 3. 流程地图
- **docs/PROJECT_MAP.md** — 完整脚本索引、依赖关系、技能触发规则
  - 从 CLAUDE.md §14 迁移而来
  - 包含 /mgx-* 技能族说明

### 4. 变更日志
- **docs/CHANGELOG_v1.1_patch.md** （新增，2026-08-19）
  - v1.1.0 → v1.1.1 所有优化与更改
  - 工程质量加固（pipefail + EXIT_CODE 冲突修复）
  - inStrain 菌株追踪集成（39b-d）
  - DAS_Tool R 环境 ABI 冲突修复
  - 回归测试建议 + 升级路径

### 5. AI 协作规范
- **CLAUDE.md** — Claude Code + Codex MCP 协作协议
  - CC = Plan/Review/Decide, Codex = Execute
  - 路由矩阵、4 阶段工作流、质量审核清单
  - No-touch 路径约束

---

## 专题文档

### 运维参考
- **docs/QUICK_START.md** — 5分钟快速上手（比 Tutorial.md 更精简）
- **docs/PERFORMANCE_TUNING.md** — 硬件配置推荐和参数调优策略
- **docs/TROUBLESHOOTING.md** — 常见问题诊断和解决方案
- **docs/visualization_workflow_specification.md** — 91-99 统计/可视化脚本的输入输出、依赖关系与执行顺序规范

### 工具参考（按需 WebSearch 动态生成）
- **docs/tools_ref/** — 缓存的工具官方文档摘要
  - 文件命名: `{tool_name}.md`
  - 生成规则: 用户询问未知工具参数 → WebSearch → 缓存

### 经验文档
- **docs/experience/** — 调试日志、已知问题、设计决策
  - `apptainer-codex-sandbox-conflict.md` — Apptainer SIF 容器无法在 Codex 沙箱中运行
  - 其他调试经验待补充

### 文献知识库
- **docs/literature/** — 三维度文献 PDF + 提取的知识
  - bacteria/ — 细菌维度文献
  - virome/ — 病毒维度文献
  - mycobiome/ — 真菌维度文献
  - cross_domain/ — 跨域分析文献

---

## 维护规则

### 版本号规范
- **主版本** (v1.0 → v2.0): 架构重构、破坏性变更
- **次版本** (v1.0 → v1.1): 新增核心功能模块（如 VEBA 真核 QC）
- **补丁版本** (v1.1.0 → v1.1.1): 错误修复、工程质量加固

### 文档同步原则
1. **Tutorial.md** — 每次脚本编号变化、流程链更新、新增关键步骤时必须更新
2. **README.md** — 脚本数、规则数、版本号、核心能力矩阵同步更新
3. **docs/PROJECT_MAP.md** — 新增脚本后 24 小时内同步分析流程索引表
4. **docs/CHANGELOG_*.md** — 每次发布 patch/minor 版本时创建对应清单

### 文档更新检查清单
当完成以下操作后，必须同步更新文档：
- [ ] 新增脚本 → Tutorial.md（流程链注释）+ PROJECT_MAP.md（分析表）+ README.md（脚本数）
- [ ] 新增 Snakemake 规则 → README.md（规则数）+ pipeline/Snakefile（DAG 注释）
- [ ] 修复已知 bug → CHANGELOG（问题根源+修复方案+影响范围）
- [ ] 新增技能卡 → PROJECT_MAP.md（技能触发规则）+ agents/registry.yaml
- [ ] 版本发布 → README.md（版本号+徽章）+ Tutorial.md（版本号+更新日期）

---

**本索引自动生成**: 2026-08-19  
**对应项目状态**: v1.1.2 patch, 178 scripts, 138 Snakemake rules
