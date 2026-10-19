# busco: 轨道 1（有妥协）+ 轨道 2

## 妥协记录
- 主包 busco 保持 build 级钉版
- 15 个依赖包从 build 级放松为版本级（原 build string 含 _7100102 后缀，
  强制 AVX-512 microarch level 4；当前 conda-forge 已无同 build 的候选）
- _x86_64-microarch-level 虚拟包已移除（纯元数据标记）
- suitesparse 最后一个也放松后成功

## 对账标准
- busco 主包：version+build 精确一致 ✓
- 依赖包：version 一致，build 可能不同（从 AVX-512 专项构建变为通用构建）
- 如需 build 级完全一致，请使用轨道 2（conda-pack）
