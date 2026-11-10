---
tool: "run_dbcan 4.x"
dimension: "mycobiome"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [fungi, dbcan, cazyme, cazy, hmmer, diamond, ecami]
scenario: [mycobiome, fungal-proteins, carbohydrate-active-enzyme]
---

# 真菌 dbCAN CAZyme 注释建议

## Scenario

> 关键参数速查：`83_fun_dbcan.sh` 依赖 step 80，聚合合并真菌 FAA；Tool = run_dbcan 4.x；方法 = HMMER + DIAMOND + eCAMI；输入 `combined_fungi.faa`；输出 `result/fungi/dbcan/overview.txt`，建议以 ≥2/3 方法一致作为高可信 CAZyme 注释。

真菌是肠道环境中重要的 carbohydrate-active enzyme 生产者，尤其在膳食多糖利用、宿主黏液糖链互作和真菌生态位解释中有价值。dbCAN 是细菌和真菌 CAZyme 注释都常用的标准工具，因此适合作为 mycobiome CAZyme 主结果来源。

`overview.txt` 是最适合下游统计的主表。它把 HMMER、DIAMOND 和 eCAMI 的证据整合到同一个结果中，比单独使用某一路输出更适合做 family-level 的 GH、GT、PL、CE、AA 和 CBM 汇总。

## Recommendation

推荐直接运行项目脚本，在所有真菌 Prodigal 蛋白上做一次聚合 CAZyme 注释。

```bash
# Run run_dbcan on merged fungal proteins.
bash scripts/83_fun_dbcan.sh \
  -t 16 \
  -w /path/to/project \
  -r ${PROJ_DIR}
```

如果手工直跑，建议启用全部工具证据通道，并把 `overview.txt` 作为主结果。

```bash
run_dbcan \
  result/fungi/dbcan/combined_fungi.faa \
  protein \
  --tools all \
  --db_dir db/dbcan3 \
  --out_dir result/fungi/dbcan
```

报告时优先展示 CAZy family 层级，而不是逐条蛋白铺开。真菌 CAZyme 结果尤其适合和物种组成、膳食纤维相关表型或细菌 CAZyme profile 做联动解释。

## Rationale

- **为什么用 dbCAN**：dbCAN 是 CAZyme 注释的标准工具，细菌和真菌蛋白都可用，便于跨维度比较。
- **为什么需要三方法证据**：HMMER、DIAMOND 和 eCAMI 分别代表 profile、序列相似性和 signature 证据，三路一致性更适合降低假阳性。
- **为什么推荐 ≥2/3 一致**：至少两种方法支持的 CAZyme 调用更保守，适合作为下游统计和论文报告主表。
- **为什么输入用合并 FAA**：脚本自动合并 `result/fungi/prodigal/*/*.faa`，能统一注释全项目真菌蛋白集合。
- **为什么输出看 `overview.txt`**：该文件是整合后的主结果，比单工具输出更适合直接汇总 CAZy family。
- **为什么真菌 CAZyme 值得单独做**：真菌分泌酶和多糖降解能力常影响肠道底物利用生态位，不能只用细菌 CAZyme 结果替代。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/83_fun_dbcan.sh`
- `docs/experience/dbcan-cazyme-annotation.md`
