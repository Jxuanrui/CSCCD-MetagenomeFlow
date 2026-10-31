# MEROPS — 真菌蛋白酶注释

**环境**: `envs/assembly` | **脚本**: `scripts/86_fun_merops.sh`

## 功能
使用 DIAMOND blastp 将真菌蛋白序列比对到 MEROPS 数据库进行蛋白酶及抑制因子注释。MEROPS 是国际权威的肽酶数据库（http://merops.sanger.ac.uk），涵盖六大蛋白酶催化类型和抑制因子家族，与真菌侵袭性机制密切相关。

## 用法

```bash
bash scripts/86_fun_merops.sh -s SAMPLE -t 16 -w /path/to/workdir -r ~/Course/CSCCD-MetagenomeFlow
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
| 输入蛋白序列 | `result/fungi/prodigal/{sample}/{sample}.faa` |
| DIAMOND 输出 | `result/fungi/merops/{sample}_merops.tsv` |

## 输出内容（BLAST m6 格式）

```
qseqid   sseqid   pident   length   evalue   bitscore   merops_family   merops_type
```

其中 `merops_type` 包含以下分类：
| 类型 | 含义 | 真菌意义 |
|------|------|---------|
| A 型 | 天冬氨酸蛋白酶 | 念珠菌天冬氨酸蛋白酶（SAPs）家族 |
| C 型 | 半胱氨酸蛋白酶 | 溶酶体相关 |
| M 型 | 金属蛋白酶 | 侵袭性生长相关 |
| S 型 | 丝氨酸蛋白酶 | 宿主免疫逃逸 |
| T 型 | 苏氨酸蛋白酶 | 蛋白酶体 |
| I 型 | 抑制因子 | 宿主-病原互作 |

## 注意事项
- 依赖 Prodigal（80）的蛋白序列输出
- 真菌蛋白酶在侵袭性真菌感染中发挥关键作用，如白色念珠菌天冬氨酸蛋白酶（SAPs）
- 可作为毒力因子注释的补充（84_fun_vfdb.sh）

## 官方链接
- MEROPS: https://www.ebi.ac.uk/merops/
- 论文: Rawlings et al. 2018, Nucleic Acids Research
