---
tool: "GTDB-Tk v2"
dimension: "bacteria"
category: "taxonomy"
author: ""
date: "2026-06-13"
tags: [gtdbtk, gtdb-r214, mag, taxonomy, pplacer]
scenario: [gut-microbiome, mag-catalog, phylogenetic-placement]
---

# GTDB-Tk MAG 系统发育分类建议

## Scenario

> 适用于 dRep 去冗余后，需要把代表 MAG 放入 GTDB R214 参考树，获得系统发育一致的细菌和古菌分类结果。

GTDB-Tk 的重点不是按最佳 BLAST hit 给名字，而是基于 marker genes、参考树和相对进化距离对 MAG 做 phylogenetic placement。对 MAG catalog 来说，这比传统 NCBI taxonomy 更适合处理未培养谱系、命名重排和不同研究之间的可比性。

GTDB 与 NCBI 分类会出现大量不一致，尤其是 Firmicutes 相关谱系在 GTDB 中被拆分为 Firmicutes_A、Firmicutes_B、Firmicutes_C 等 clade。发表或交付报告时，建议同时保留 GTDB taxonomy 与 NCBI taxonomy，并在方法中明确 GTDB release，例如 GTDB R214。

**关键参数速查**：Tool = `GTDB-Tk v2` with GTDB R214；Depends on = dRep dereplicated MAGs；Key params = `gtdbtk classify_wf`, `--genome_dir`, `--out_dir`, `--cpus 16`, `--skip_ani_screen` optional for speed, GTDB R214 database at `db/gtdbtk/`；Input = dRep dereplicated MAGs；Output = `gtdbtk.bac120.summary.tsv` + `gtdbtk.ar53.summary.tsv`；Threshold/resource = requires ~320GB GTDB database and memory-intensive pplacer placement。

## Recommendation

```bash
# Run GTDB-Tk classification on dereplicated MAGs.
bash scripts/40_bac_gtdbtk.sh \
  -t 16 \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow
```

如需直接运行，建议显式设置数据库路径，保证使用同一个 GTDB release：

```bash
# Direct GTDB-Tk v2 classify workflow with GTDB R214.
export GTDBTK_DATA_PATH=/path/to/CSCCD-MetagenomeFlow/db/gtdbtk
gtdbtk classify_wf \
  --genome_dir /path/to/project/result/binning/drep/dereplicated_genomes \
  --out_dir /path/to/project/result/binning/gtdbtk \
  -x fa \
  --cpus 16 \
  --skip_ani_screen \
  --force
```

主结果查看 `classify/gtdbtk.bac120.summary.tsv` 和 `classify/gtdbtk.ar53.summary.tsv`。如果样本里几乎全是细菌，古菌表为空是正常现象；如果 pplacer 阶段失败，应优先检查 GTDB 数据库完整性、内存和临时目录空间，而不是先修改 MAG 输入。

## Rationale

- **为什么使用 GTDB R214**：分类结果强依赖参考数据库版本，明确 release 才能让不同批次 MAG catalog 可比较。
- **为什么输入必须是 dRep 代表 MAG**：对所有近重复 bin 分类会浪费计算并制造重复谱系，去冗余后分类更适合构建最终 MAG catalog。
- **为什么用 `classify_wf`**：该工作流整合 marker gene 识别、比对、ANI screening 和树上放置，是 GTDB-Tk 对用户基因组分类的标准入口。
- **为什么 `--skip_ani_screen` 可以作为加速选项**：在大量 MAG 或已有 dereplicated catalog 中跳过 ANI 预筛可节省时间，但需要接受可能少用一层快速近邻判断。
- **为什么必须关注 pplacer 内存**：GTDB 参考树和 marker alignment 很大，pplacer placement 是 GTDB-Tk 中最容易受内存限制影响的步骤。
- **为什么 GTDB 会不同于 NCBI**：GTDB 以系统发育一致性重构命名体系，许多传统门、纲、科会被拆分或重命名。
- **为什么报告中要同时给 GTDB 和 NCBI**：GTDB 提供系统发育一致性，NCBI 仍便于读者检索历史文献和公共数据库记录。
- **为什么 Firmicutes_A/B/C 要单独说明**：这些名称常让读者误以为是错误标签，实际是 GTDB 对传统 Firmicutes 谱系拆分后的标准命名。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/40_bac_gtdbtk.sh`
- `agents/skills/40_bac_gtdbtk.yaml`
