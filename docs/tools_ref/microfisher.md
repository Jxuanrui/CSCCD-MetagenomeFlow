# MicroFisher — 多超变区真菌分类

**环境**: `envs/microfisher` | **脚本**: `scripts/77_fun_microfisher.sh`

## 功能
MicroFisher 使用 Centrifuge 结合 HMD（Human Microbiome Database）ITS/18S/28S 多项超变区参考库进行高通量真菌分类鉴定。通过合并 ITS1、ITS2、18S 和 28S 多个标记的多重序列比对，提升真菌分类分辨率和覆盖率。

## 用法

```bash
bash scripts/77_fun_microfisher.sh -s SAMPLE -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
```

| 参数 | 必需 | 默认 | 含义 |
|------|------|------|------|
| `-s` | 是 | — | 样本 ID |
| `-t` | 否 | 8 | 线程数 |
| `-w` | 是 | — | 工作目录 |
| `-r` | 是 | — | 项目根目录 |

## 输入 / 输出

| 项目 | 路径 |
|------|------|
| 输入 cleaned reads | `temp/{sample}/02_kneaddata/{sample}_kneaddata_clean.fastq.gz` |
| 分类表格 | `result/fungi/microfisher/{sample}_taxonomy.tsv` |
| 丰度矩阵（可选） | `result/fungi/microfisher/{sample}_abundance.tsv` |

## 工作流程

1. Centrifuge 对 ITS1/ITS2/18S/28S 多库同时进行比对
2. 提取匹配标记 reads 和最佳匹配物种
3. 汇总多标记分类结果

## 与 MetaPhlAn4 真菌模式的对比

| 工具 | 标记 | 覆盖 | 精度 |
|------|------|------|------|
| MetaPhlAn4（72） | 物种特异性 markers | 全面（含原核+真核） | 高（菌株级） |
| **MicroFisher**（77） | ITS1/ITS2/18S/28S | 真菌高分辨率 | 物种/属级 |

## 注意事项
- 多标记流程降低单一标记的 PCR/NGS 偏差
- 依赖 `db/microfisher/` 参考数据库（ITSDB + HMD）
- 适合缺乏近缘参考基因组的真菌新物种鉴定

## 官方链接
- GitHub: https://github.com/microfisher-db/MicroFisher
