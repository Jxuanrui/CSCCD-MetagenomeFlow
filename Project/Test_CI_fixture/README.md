# Test_CI_fixture

用于测试/CI体系（层二抽样集成测试、层三Snakemake DAG连通性测试），与真实分析项目
`Project01` 物理隔离，**不要用于真实分析，不要手动改动其中数据**。

## 生成方式

- `data/T01-T04_{1,2}.fastq.gz`：从 `Project_example` 的4个真实样本（S01/S02 control，
  S04/S05 treat）各用 `seqtk sample -s100 <fastq> 10000` 截取1万条reads pair，
  直接命名为 `.fastq.gz`（不用symlink，规避真实项目里`.fq.gz`底层文件+`.fastq.gz`
  symlink的命名层，简化fixture结构）。用真实数据subsample而非随机序列，是因为
  MetaPhlAn4/Kraken2这类基于参考库比对的工具在全随机序列上会产出空结果甚至异常退出，
  无法验证"脚本调用链路是否正确"这个层二测试的真实目的。
- `samplesheet.csv`/`metadata.csv`：4样本、2v2分组（control/treat），一眼可辨认是测试数据。
- `result/`（后续步骤补充）：预置的"伪造但格式正确"中间产物，复用
  `scripts/utils/generate_test_100samples.R` 的"真实数据形状+Dirichlet-multinomial模拟"
  手法缩小到4样本规模，保证组间有真实差异信号（不能全零，否则PERMANOVA等算法可能除零报错）。

## 用途

- 层二（`scripts/tests/level2/`）：抽样代表性脚本的集成测试，验证脚本调用链路、
  输入输出格式、sentinel/status.tsv写入逻辑是否正确。
- 层三（`scripts/tests/level3/`）：`pipeline/config/config.test_ci.yaml` 指向本目录，
  用 `snakemake -n` dry-run验证Snakemake规则图的连通性。

## 重新生成

如需重新生成（例如更换subsample种子样本），参见本文件"生成方式"一节的命令，
从 `Project/Project_example/data/` 重新截取即可，无需保留历史版本。
