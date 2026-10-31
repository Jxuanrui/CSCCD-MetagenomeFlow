# SIF 容器化评估报告（review 16th Review P2-2，2026-10-30）

## 目的
评估三个环境痛点工具的 SIF 容器化可行性——这三个工具恰好是 P3 条件触发项的根因。

## 候选评估

### 1. gapseq（优先级最高）
- **痛点**：缺 R cobrar 包，10/10 MAG 产出 draft 但无 SBML；GEM 链单路依赖 CarveMe
- **容器来源**：`docker://ghcr.io/jotech/gapseq:latest`（官方，candidate_research）
- **许可证**：MIT（source code），镜像许可未核证
- **数据库**：gapseq 自带内置数据库，属软件层——不入 db/ 冻结区
- **挂载**：需挂载 MAG 输入+输出目录
- **试点可行性**：高（官方有 Docker 支持）

### 2. FunOMIC 分类器（中等优先）
- **痛点**：官方分类器二进制缺失，回退 DIAMOND 分支 6.7-9.9h/样本
- **容器来源**：官方未提供镜像（需自建，candidate_research）
- **许可证**：FunOMIC 工具许可未核证
- **数据库**：341 万蛋白库已在本仓 db/funomic/
- **试点可行性**：中（需自行打包分类器+数据库组合）

### 3. CheckAMG（优先级第三）
- **痛点**：torch_scatter PyTorch 生态安装壁垒，5 种策略全败
- **容器来源**：无官方镜像（candidate_research）
- **许可证**：未核证
- **数据库**：模型权重内嵌，属软件层
- **试点可行性**：低-中（需打包 PyTorch+torch_scatter+checkamg 全链）

## 推荐试点

**gapseq**：已有官方 Docker 镜像、MIT 许可、GEM 链是已交付能力中唯一有已知缺陷（10/10 无 SBML）的环节。SIF 化后可：
- 绕过 R 包安装问题
- 产出 SBML 模型使 43 号 GEM 链从单路（CarveMe）变为双路（CarveMe+gapseq）
- 直接提升 GEM 交付从 9/10 到潜在 10/10

**试点条件**：
1. 核实官方镜像 digest 与许可证
2. 在隔离目录试运行（不触 envs/）
3. 输出对比现有 CarveMe SBML（结构一致性检查）
4. 用户逐个批准后方可实施

## 冻结边界声明

SIF 评估属"软件层入容器"；**数据库序列不入容器**（db/ 冻结约束 §10.5-2）。
任何 SIF 实施须逐个用户批准，不因本评估自动解冻。

## 维护成本

| 工具 | 镜像大小（估） | 更新频率 | 维护负担 |
|---|---|---|---|
| gapseq | ~2-5 GB | 低（工具稳定） | 低 |
| FunOMIC | ~5-10 GB（含库） | 中 | 中 |
| CheckAMG | ~3-8 GB（含 PyTorch） | 高（依赖链复杂） | 高 |
