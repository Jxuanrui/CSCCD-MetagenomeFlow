---
tool: "eggNOG-mapper 2.1.13"
dimension: "mycobiome"
category: "annotation"
author: ""
date: "2026-06-14"
tags: [fungi, eggnog, cog, ko, go, ec, cazy]
scenario: [mycobiome, fungal-proteins, functional-annotation]
---

# 真菌 eggNOG 综合功能注释建议

## Scenario

> 关键参数速查：`81_fun_eggnog.sh` 聚合收集 `result/fungi/prodigal/*/*.faa`，依赖 step 80；Tool = eggNOG-mapper 2.1.13；输入合并真菌蛋白集；输出 `result/fungi/eggnog/eggnog.emapper.annotations`，含 COG/KO/GO/EC/CAZy。

这一步和细菌 `21_bac_eggnog.sh` 使用同一类 eggNOG-mapper 工作流，但分析对象换成真菌 Prodigal 蛋白集合。它适合作为 mycobiome 功能注释的基础层，把真菌基因统一映射到 COG、KO、GO、EC 和 CAZy 等多套功能体系。

真菌 eggNOG 注释要特别注意 ortholog group 的分类范围。脚本当前不显式固定 `--tax_scope`，可以让 eggNOG 自动选择；如果手工直跑，建议使用 `--tax_scope eukaryota` 或保持 auto，避免把真菌蛋白强行放进不合适的细菌 OG 背景。

## Recommendation

推荐直接使用项目包装脚本，它会自动查找并合并所有真菌样本的 `.faa` 文件。

```bash
# Run eggNOG-mapper on all fungal protein predictions.
bash scripts/81_fun_eggnog.sh \
  -t 16 \
  -w /path/to/project \
  -r ${PROJ_DIR}
```

如果需要手工直跑 eggNOG-mapper，建议显式声明蛋白输入、DIAMOND 模式和真菌相关 tax scope。

```bash
emapper.py \
  -m diamond \
  --itype proteins \
  -i result/fungi/eggnog/combined_fungi.faa \
  --data_dir db/eggnog \
  --cpu 16 \
  --tax_scope eukaryota \
  -o eggnog \
  --output_dir result/fungi/eggnog \
  --override
```

主结果文件是 `eggnog.emapper.annotations`。下游可从中提取 KO 做通路汇总，提取 COG 做功能类别比较，提取 GO/EC/CAZy 做补充解释。

## Rationale

- **为什么做聚合注释**：`81_fun_eggnog.sh` 自动合并 `result/fungi/prodigal/*/*.faa`，避免对每个样本重复运行同一套数据库搜索。
- **为什么依赖 step 80**：eggNOG-mapper 这里使用蛋白输入，只有 `80_fun_prodigal.sh` 生成 `.faa` 后才能进入功能注释。
- **为什么和细菌脚本可比**：工具和输出字段与 `21_bac_eggnog.sh` 类似，便于在 bacteria 与 mycobiome 之间比较 KO、COG 和 EC 层面的功能差异。
- **为什么强调 eukaryota/auto scope**：真菌属于真核生物，合适的 ortholog 背景能提高 OG 转移解释的生物学一致性。
- **为什么 eggNOG 作为基础层**：它一次性提供 COG、KO、GO、EC 和 CAZy 等字段，比 KEGG-only 更适合搭建宽覆盖功能 profile。
- **为什么仍需和 KEGG 交叉验证 KO**：eggNOG 的 KO 来自 orthology 转移，KEGG DIAMOND best-hit 能提供独立证据，二者一致时 KO 解释更稳。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/81_fun_eggnog.sh`
- `scripts/21_bac_eggnog.sh`
- `docs/experience/eggnog-functional-annotation.md`
