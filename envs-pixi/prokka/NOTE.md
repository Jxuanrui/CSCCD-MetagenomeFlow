# prokka: 仅轨道 2（conda-pack 保底）

pixi 无法解析 samtools==0.1.19 的依赖链（需要 openssl 1.1.x + 特定 python 版本，
均已从上游通道移除）。本环境通过 conda-pack 打包交付（轨道 2），
不提供 pixi 锁文件（轨道 1）。

原因链：samtools 0.1.19 → openssl >=1.1.0,<=1.1.1 → 已从 conda-forge 移除
