# 调研报告：小样本网络组间比较的根因与业界实践（2026-10-17）

## 一、根因（代码 + 文献双证）

**93 号 netCompare 调用链**（`scripts/93_stat_cooccurrence.sh:610-625`）：
- 每组建网：`measure="sparcc", sparsMethod="threshold"(0.3)`
- 比较：`netCompare(testRand=FALSE, gcd=FALSE, cores=THREADS)` — **未显式设 nPerm → NetCoMi 默认 1000**（[NetCoMi 论文](https://pmc.ncbi.nlm.nih.gov/articles/PMC8293835/) 实例即 1000 次；论文自认 "permutation tests may prove to be computer intensive"）
- **机制**：每次置换=重排组标签→两组各重建一次 SparCC 网络→重算全部中心性。SparCC 单网实测 ~15 分钟 → 1000×2 次 ≈ 数天。**观测到的 25h+ 卡顿与该量级吻合**；R 实际单核运行（cores 参数未生效为并行）。

**统计学根因**：3v3 下组标签置换只有 C(6,3)=20 种——无论 nPerm 设多少，分辨率天花板由 20 决定。1000 次置换绝大多数是重复计算。

**业界门槛**：网络组间比较**建议每组 25-30 样本**（[Matchado et al. 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8131268)，引用 426+；CD Genomics 实务口径）。本项目 3/组低于门槛一个数量级。

## 二、同类项目与集成机会

| 项目 | 与我们的关系 | 机会 |
|---|---|---|
| **microeco + meconetcomp** | **91 号已用 microeo**（microtable）；meconetcomp 为同作者网络比较包 | 原生集成：microeco 的 `cal_network()`（支持 SpiecEasi/FlashWeave）+ meconetcomp 比较，替代裸调 NetCoMi；[文档](https://search.r-project.org/CRAN/refmans/microeco/html/trans_network.html)、[教程](https://onlinelibrary.wiley.com/doi/10.1002/imt2.71) |
| **[FlashWeave](https://github.com/meringlab/FlashWeave.jl)**（Julia） | 大规模网络推断更快、带混杂校正 | 若未来样本量扩大，替换 SparCC 推断层 |
| **[SPIEC-EASI](https://github.com/zdk123/SpiecEasi)** | 稀疏逆协方差建网，小 n 更稳 | microeco cal_network 已内置支持 |
| **[Glasgow Snakemake 宏基因组流程](https://userweb.eng.gla.ac.uk/umer.ijaz/projects/Liu_Kai_2020.pdf)** | 含共现网络步骤的同类管线 | 排程参考 |
| **[OMA 网络 章节](https://microbiome.github.io/OMA/docs/devel/pages/network_comparison.html)** | 官方教程明确"多核加速置换" | 印证 cores 应生效（我们未生效需排查 BiocParallel 后端） |

## 三、防复发通用规则（提案，待质量审核合议）

1. **重统计工具参数预算制**：凡带 nPerm/bootstrap/n_repeats 参数的步骤，泳道启动前必须显式设上限并换算预期墙钟（SparCC 单网耗时 × 置换数）；不依赖默认值。
2. **小 n 数学守卫**：组标签置换数 C(n1+n2, n1) < 100 时，自动降 nPerm 至置换空间大小并告警（超界部分纯浪费）。
3. **墙钟熔断**：统计类单步泳道默认挂 timeout（如 4h），超时报告而非无限挂起。
4. validate_step 补 netcomi 侧不变式：nPerm 实际生效值与产出行数闭合。
