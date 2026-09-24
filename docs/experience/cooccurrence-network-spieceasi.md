---
tool: "SpiecEasi + NetCoMi (R)"
dimension: "statistics"
category: "network"
author: ""
date: "2026-06-13"
tags: [spieceasi, netcomi, cooccurrence, network, cross-domain]
scenario: [bacteria-virus-fungi, relative-abundance, network-inference]
---

# SpiecEasi + NetCoMi 共现网络分析建议

## Scenario

> 适用于已经得到细菌、病毒和真菌相对丰度表后，需要推断单域或跨域 microbial co-occurrence network，并总结 hub taxa、模块化和跨域边。

微生物共现网络不能简单等同于 Pearson correlation 图。宏基因组丰度表是 compositional data，闭合效应会制造伪相关；SpiecEasi 通过稀疏逆协方差或 neighborhood selection 更适合从组成型数据中推断条件依赖关系，再用 NetCoMi 和 igraph 汇总网络指标。

跨域网络尤其需要保守解释。bacteria-virus、bacteria-fungi 边可能反映生态互作、共同生态位、宿主状态或组合数据效应，不能直接写成因果关系。实际报告中应把 hub taxa、betweenness centrality、modularity 和跨域 edge type 分开呈现，并结合已知生物学进行解释。

**关键参数速查**：Tool = `SpiecEasi + NetCoMi (R)`；Depends on = merged taxonomy/vOTU/fungi relative abundance tables and metadata；Key params = `SpiecEasi(method="mb")` SPIEC-EASI Meinshausen-Bühlmann, `lambda.min.ratio=0.1`, `nlambda=20`, `rep.num=50` stability, NetCoMi for network metrics hub scores and modularity；Input = merged taxonomy/vOTU/fungi tables；Output = network edges + hub taxa summary；Threshold = minimum 30 samples recommended。

## Recommendation

```bash
# Run co-occurrence network analysis for all supported domains.
bash scripts/93_stat_cooccurrence.sh \
  -w /path/to/project \
  -r /path/to/CSCCD-MetagenomeFlow \
  -t 16 \
  -m /path/to/project/metadata.csv \
  -g group \
  -n all
```

R 中的核心推断建议使用 MB method 和 stability selection：

```r
# SPIEC-EASI Meinshausen-Buehlmann network inference.
se <- SpiecEasi::spiec.easi(
  otu_table,
  method = "mb",
  lambda.min.ratio = 0.1,
  nlambda = 20,
  pulsar.params = list(rep.num = 50)
)
```

结果输出应至少包含 edge table、node table、hub taxa summary 和 modularity。若样本量低于 30，应把网络作为探索性结果；若做 cross-domain network，建议同时输出 edge domain labels，区分 bacteria-bacteria、bacteria-virus、bacteria-fungi 和 fungi-fungi 等边类型。

## Rationale

- **为什么优先 SpiecEasi 而不是 Pearson**：Pearson 直接在相对丰度上算相关，容易受闭合效应影响；SpiecEasi 更适合 compositional microbiome data。
- **为什么 MB method 适合大网络**：Meinshausen-Bühlmann neighborhood selection 通常比 glasso 更快，面对数百个 taxa 的矩阵更实用。
- **为什么设置 `lambda.min.ratio=0.1`**：较保守的 lambda 搜索范围能避免网络过密，让稳定边更容易解释。
- **为什么 `nlambda=20` 足够实用**：该设置在搜索精度和运行时间之间折中，适合批量比较多个域或多个分组。
- **为什么需要 `rep.num=50`**：stability selection 通过重复抽样评估边稳定性，能减少单次拟合造成的偶然连接。
- **为什么建议至少 30 个样本**：网络参数多而样本少时边集合极不稳定，低样本量结果只能作为探索性图示。
- **为什么用 NetCoMi 汇总指标**：NetCoMi 提供 microbiome network 的构建、比较和指标框架，比手写 igraph 流程更容易标准化。
- **为什么关注 betweenness hub taxa**：高中介中心性的 taxa 可能连接多个模块，是生态网络中更值得优先解释的 keystone candidates。
- **为什么跨域边要谨慎解释**：细菌、病毒和真菌表的测量误差、稀疏度和 compositional effects 不同，边并不等同于直接互作或感染关系。

## Verified

- pending — 基于工具文档与脚本分析推导，待实际运行验证

## References（可选）

- `scripts/93_stat_cooccurrence.sh`
- `agents/skills/93_stat_cooccurrence.yaml`
