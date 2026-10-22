# virsorter2：SIF 容器交付方案

## 现状
virsorter2 不是 conda 环境，而是一个 bash 包装脚本调用外部 SIF 容器：
- 脚本：envs/virsorter2/bin/virsorter（4 行 bash）
- 容器：~/Course/Virus_Apptainer_pipline/apptainer/virsorter2-kit-0.0.4.sif（1.7GB）
- 依赖：apptainer（宿主机需预装）

## 交付方案（轨道 2 专属）
1. 将 SIF 文件复制到交付包的 containers/ 目录
2. 修改包装脚本的 SIF 路径为相对路径（或用环境变量 VIRSORTER2_SIF）
3. 对方需要预装 apptainer（Linux 标准，apt install apptainer）
4. 不提供 pixi 锁文件（轨道 1 不适用）

## 改动需求
- scripts/53_vir_virsorter2.sh:57 直接调 conda run → 需改为直接调包装脚本
- 或：在目标机上建 envs/virsorter2/bin/virsorter 软链接指向容器
