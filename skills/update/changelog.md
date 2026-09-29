# Skills 变更日志

## 2026-06-09 — v2 大规模扩展
- **新增 SciAgent-Skills**: 199 个生命科学技能（92% BixBench），覆盖基因组学/结构生物学/科学计算/科学写作等 12 个类别
- **新增 GPTomics/bioSkills**: 89 个直接相关的生信技能（7 宏基因组 + 32 微生物组 + 20 可视化 + 6 通路分析 + 8 系统发育 + 40 工作流模板）
- **新增 awesome-skills**: 1,976 个聚合技能（来自 15 个上游来源，含 K-Dense-AI 137 技能 + bioSkills + SciAgent 的并集）
- **registry 架构升级**: 新增 plugin_packages 和 categories 层级，支持大技能包管理
- **总覆盖**: 7 大类别全部填满，analysis 和 methodology 缺口已补

## 2026-06-09 — v1 初始化
- 初始化 Skills 管理系统
- 创建 skills/ 目录结构和发现引擎框架
- 采纳首批 9 个种子技能（nature-skills 包）
