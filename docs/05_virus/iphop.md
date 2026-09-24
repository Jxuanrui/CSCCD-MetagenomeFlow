# iPHoP — 病毒-宿主关联预测

**版本**: 3+ | **环境**: `envs/iphop` | **脚本**: `scripts/68_vir_iphop.sh`

## 功能
iPHoP（Informational Protein Host Prediction）使用病毒信息蛋白（如 DNA 聚合酶、末端酶等保守蛋白）的序列特征，通过集成学习方法预测病毒-宿主关联关系。支持属（genus）到种（species）级别的宿主预测，覆盖细菌和古菌宿主。

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 vOTU 序列 | `result/virus/votu/contigs/virus.fasta` |
| 宿主预测表 | `result/virus/iphop/iphop_host_prediction.tsv` |

## 预测表格式

```
query               host_genus  host_species  score  confidence
vOTU_0001           Escherichia E. coli       0.97   High
vOTU_0002           Klebsiella  K. pneumoniae 0.85   Medium
```

| 列 | 说明 |
|----|------|
| query | 病毒序列 ID |
| host_genus | 宿主属名 |
| host_species | 宿主种名 |
| score | 预测置信分数（0–1） |
| confidence | High / Medium / Low |

## 关键参数

| 参数 | 默认 | 含义 |
|------|------|------|
| `--fa_file` | vOTU FASTA | 输入病毒序列 |
| `--db_dir` | `db/iphop` | iPHoP 宿主数据库 |
| `--out_dir` | 输出目录 | 预测结果目录 |
| `--num_threads` | CPUS | 线程数 |

## 数据库

iPHoP 使用预构建的宿主参考数据库（基于 RefSeq 基因组），需单独下载：

```bash
# 数据库下载（约 5 GB）
iphop download --db_dir db/iphop/
```

若数据库不存在，脚本 68 会优雅退出（创建空的 `host_prediction.tsv` 哨兵文件，不报错中止流程）。

## 与其他宿主预测工具对比

| 工具 | 方法 | 优势 |
|------|------|------|
| iPHoP | 信息蛋白 + 集成学习 | 精度高，通用性广 |
| 基于 CRISPR spacer | 序列比对 | 宿主分辨率高但灵敏度低 |
| 基于 tRNA 匹配 | 序列同源性 | 覆盖度低 |
| 基于片段映射（iPHoP 不依赖） | 读段比对 | 样本特异，无法泛化 |

## 注意事项
- iPHoP 输入建议使用 vOTU 代表序列（聚类的非冗余序列），而非所有原始病毒 contigs
- iPHoP 预测的是**最可能宿主**而非确凿证据；对于低置信度预测（score < 0.7），建议使用独立的 CRISPR 片段映射交叉验证
- iPHoP 数据库更新频率低，对罕见或新发宿主的预测能力有限
- 运行时间取决于 vOTU 数量；数千条 vOTU 约需 30-60 分钟

## 官方链接
- GitHub: https://github.com/RavelLab/iPHoP
- 论文: Roux et al. 2024, Nature Microbiology 9:1056–1068
