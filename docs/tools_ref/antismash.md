# antiSMASH — 次级代谢产物/BGC 预测

**版本**: 7.x | **环境**: `envs/antismash` | **脚本**: `scripts/28_bac_antismash.sh`

## 功能
antiSMASH 识别宏基因组 contigs 中的次级代谢产物生物合成基因簇（BGCs），覆盖 PKS（聚酮合酶）/ NRPS（非核糖体肽合成酶）/ 萜类 / RiPPs 等主要 BGC 类型，输出 GenBank / JSON / HTML 可视化报告。

## 用法

```bash
bash scripts/28_bac_antismash.sh -s SAMPLE -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 contigs | `result/assembly/megahit/{sample}/{sample}.contigs.fa` |
| GenBank 输出 | `result/antismash/{sample}/{sample}.gbk` |
| JSON 输出 | `result/antismash/{sample}/{sample}.json` |
| 可视化报告 | `result/antismash/{sample}/index.html` |

## 主要 BGC 类型

| 类型 | 说明 | 示例产物 |
|------|------|---------|
| PKS I/II/III | 聚酮合酶 | 红霉素、四环素 |
| NRPS | 非核糖体肽合成酶 | 青霉素、环孢素 |
| Terpene | 萜类 | 类胡萝卜素 |
| RiPPs | 核糖体合成后修饰肽 | 乳链菌肽 |
| Saccharide | 糖类 BGC | 链霉素 |
| NRPS-PKS hybrid | 杂合 BGC | 雷帕霉素 |

## 注意事项
- antiSMASH 是 per-sample 步骤（按样本运行），使用 MEGAHIT contigs
- 宏基因组模式（`--minimal`）跳过 NCBI taxonomy 查询，加快运行
- BGC 的 HTLM 报告可用浏览器直接查看
- 数据库 `db/antismash/` 较大（~20 GB），首次运行需提前下载

## 官方链接
- Web: https://antismash.secondarymetabolites.org
- 论文: Blin et al. 2023, Nucleic Acids Research (antiSMASH 7)
