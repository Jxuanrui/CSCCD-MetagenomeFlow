# scripts/tests/deprecated_examples/

这3个测试脚本依赖 `Project/Test_100samples`（100样本模拟数据集），该目录已在
2026-07 被删除，脚本目前**全部失效，不能直接运行**。

移到本目录而非直接删除，是因为脚本内暴露的产物命名模式（如真菌/细菌维度文件名的
差异、跨队列批次评估的目录结构约定）仍有参考价值，作为"反例"保留。

替代方案：见 `scripts/tests/level1/`、`scripts/tests/level2/`、
`scripts/tests/level3/` 与 `scripts/tests/run_ci_checks.sh`（2026-07-28
新建的三层测试金字塔，基于 `Project/Test_CI_fixture` 专用小型测试数据集）。

| 脚本 | 依赖的已删除资源 | 原用途 |
|---|---|---|
| `test_97_crosscohort.sh` | `Project/Project_example`（复制生成mock队列，非Test_100samples本身，但用途已被layer2/3覆盖） | 跨队列验证框架测试 |
| `test_four_modules.sh` | `Project/Test_100samples/metadata.csv` | 4个新模块（LEfSe/Core/FDI/Pathway）批量测试 |
| `test_four_modules_fixed.sh` | `Project/Test_100samples/` | 同上，修复版 |
