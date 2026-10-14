# 病毒丰度定量已知偏差披露（2026-10-14，用户批准写入）

Project01 冻结基线的 vOTU 丰度定量（59 salmon → 60 聚合）使用了"病毒 CDS + vOTU contig"
混合索引（gentrome）：同一条落在基因区的 read 会被 Salmon 的 EM 算法分摊给基因和
contig 两条 target，随后 60 号在基因级聚合时丢掉基因行，被分走的 reads 一并丢失。

**偏差后果**（Project_demo 2026-10-13 V2 整改时实测，三条对照 contig）：
- vOTU 的 contig 级 reads 损失 35%–77% 不等，且损失比例随基因密度变化——
  vOTU 之间不可直接比较；
- contig 行 TPM 之和不守恒（<10⁶），样本内组成系统性偏低。

**处置口径**（用户 2026-10-13 approve #2）：Project01 基线**不重跑**（遵守冻结），
已发布的病毒丰度结论带此同源偏差；论文方法部分须写明本偏差。修正后的定量流程
（索引只含 vOTU contigs、contig 级 TPM、ΣTPM=10⁶ 守恒）见 Project_demo
（提交 7b2e9ab / d08d034 / 2c63754），质量审核审核档案 .claude/reviews/。

技术细节：Project_demo/result/virus/salmon/Sample1/quant.sf 三对照 contig 前后
对照 420.99→1614.48 / 2597.61→3995.86 / 1511.06→2553.89（NumReads）。
