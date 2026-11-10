# Taxonomy Identity Schema(E-TAX foundation, Batch 1)

> 原则:GTDB 与 NCBI **同时是真实存在的 taxonomy systems**,不是"一个正确一个待修正"。
> 任何 taxon name 脱离 system 单独出现时,不得默认为同一 biological identifier。

## 1. 身份五元组

任何进入解释层的 taxonomy 断言必须可表达:

| 字段 | 说明 |
|---|---|
| `taxonomy_name` | 原始名称字符串(未经改写) |
| `taxonomy_system` | `GTDB-R214` / `NCBI-taxid` / `NCBI-name` / `PlusPF-NCBI` 等(系统+版本) |
| `taxonomy_rank` | d__/p__/…/s__(GTDB)或 species/genus(NCBI) |
| `taxonomy_source` | 产出工具+步骤(如 `GTDB-Tk(40)`、`MetaPhlAn4(11)`、`Kraken2+Bracken(14)`) |
| `source_entity` | 断言挂靠的实体(MAG id / contig / read-profile) |

## 2. 系统登记(当前项目实际产出)

| 来源 | system | rank 形态 | 备注 |
|---|---|---|---|
| 40 GTDB-Tk | GTDB R214 | `d__Bacteria;p__…;s__` | 98d GTDB_classification 列;98d 自 E-TAX 起附 `Taxonomy_System` 常量列 |
| 11/11b MetaPhlAn4 | NCBI 风格 clade 名, mpa vOct22 | `k__…\|s__` | 0-100 relab(见 QUANTIFICATION_CONTRACT Q4) |
| 14/14b Kraken2+Bracken | NCBI(PlusPF 库) | K/P/S 列 | reads 语义 |
| 15/15b Centrifuger | GTDB R226 + RefSeq | — | **与 40 的 GTDB 版本不同(R226 vs R214)** |
| 15c/15d sylph | GTDB R220 | 伪装 mpa 格式输出 GTDB 名(15c:9 已知) | **禁止按字符串直接与 11b join** |
| 15e MetaX | NCBI taxdump(2022-08) | 跨域 | 验证层 |
| 71/72 真菌 | NCBI / mpa vOct22 | — | — |

## 3. Crosswalk 规则(为 Batch 2 预置,本批不实现)

- 映射输出必须六列:`source_name / source_system / target_name / target_system / mapping_method / mapping_status`;
- `mapping_status ∈ {EXACT, SYNONYM, AMBIGUOUS, UNMAPPED}`;**1:N 一律 AMBIGUOUS,禁止 first-match**;
- 映射表可由库内已有数据生成(sylph gtdb_r220 metadata + 15e 的 NCBI taxdump),不新增数据库;
- join 语义上下文最小集:`name + system + rank`(§18)。

## 4. 代码落点(Batch 1 最小实现)

- 98d:`Taxonomy_System` 常量列(GTDB-Tk R214),与 GTDB_classification 成对出现——name 永不脱离 system;
- 本文档为 Batch 2 cross-validation(TAX-01/02)与 crosswalk 的契约源。
