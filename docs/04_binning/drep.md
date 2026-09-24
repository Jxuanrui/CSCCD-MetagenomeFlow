# dRep — MAG 去冗余

**版本**: v3.6.2 | **环境**: `envs/drep` | **脚本**: `scripts/38_bac_drep.sh`

## 功能
对来自多样本的 MAGs 进行全基因组比较去冗余（ANI-based clustering），在一定相似度阈值内每个簇选出质量最高的代表性 MAG，建立非冗余 MAG 目录（dereplicated genomes）。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 MAGs | `result/binning/checkm2/checkm2_filtered/*.fa` |
| CheckM2 报告 | `result/binning/checkm2/quality_report.tsv` |
| 代表性 MAGs | `result/binning/drep/dereplicated_genomes/*.fa` |
| 完成标记 | `result/binning/drep/.done` |
| 聚类报告 | `result/binning/drep/data_tables/Wdb.csv` |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `-g` | 输入 FASTA 列表 | 待去冗余 MAGs |
| `--checkM_method` | `checkm2` | 使用 CheckM2 质量评分 |
| `--genomeInfo` | CheckM2 报告 | 提供 completeness/contamination |
| `-pa` | 0.9 | 初级聚类 ANI 阈值（MASH） |
| `-sa` | 0.97 | 次级聚类 ANI 阈值（ANI >= 97% 视为同株） |
| `-nc` | 0.3 | N50 覆盖度阈值 |
| `-comp` | 50 | 最低完整性过滤 |
| `-con` | 10 | 最高污染率过滤 |
| `-p` | CPUS | 线程数 |

## 示例命令

```bash
# 聚合去冗余
bash scripts/38_bac_drep.sh -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow

# 查看聚类结果
cat result/binning/drep/data_tables/Wdb.csv | head

# 统计代表性 MAGs 数量
ls result/binning/drep/dereplicated_genomes/*.fa | wc -l
```

## 聚类策略说明

dRep 两步聚类：
1. **初级聚类**（ANI ≥ 90%）：用 MASH 快速粗聚类，减少精确 ANI 计算量
2. **次级聚类**（ANI ≥ 97%）：精确 pairwise ANI，97% = 种内 SNP 差异阈值

每个次级簇选择 `score = completeness - 5×contamination + 0.5×log10(N50)` 最高的代表。

## 注意事项
- dRep 要求至少 2 个 MAGs；若所有样本分箱结果过滤后 < 2 个，脚本会跳过
- `dereplicated_genomes/` 是 WGS 脚本（41b/41c/41d）的输入，命名直接保留原始 bin 名
- ANI 97% 为默认种级阈值；若研究菌株多样性，可调至 99%

## 官方链接
- GitHub: https://github.com/MrOlm/drep
- 文档: https://drep.readthedocs.io
- 论文: Olm et al. 2017, ISME Journal 11:2864-2868
