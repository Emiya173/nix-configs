# Migration measurement — 2026-09-05

本次比较的是迁移前备份的 C++ 程序与当前已安装的 Haskell 程序。没有为跑分修改二进制，也没有使用有利于某一版的额外运行参数。

- CPU：Intel Core i7-14700，28 个可用逻辑 CPU。
- 平台：Linux x86_64；临时语料位于 `/tmp`，文件系统为 tmpfs。
- 每个程序每个场景预热 1 次，测量 5 次，执行顺序按轮交替。
- 单文件输出 2 MiB（128 条 × 16 KiB）；目录含 32 个文件，输出总计 64 MiB。
- 每次都逐字节验证输出，全部通过；耗时包括启动、读取、解码及写出。
- 读取已预热，不执行 fsync。这不是磁盘冷读写测试。

| 场景 | C++ 中位数 ms | Haskell 中位数 ms | Haskell / C++ 耗时 |
| --- | ---: | ---: | ---: |
| 单文件 DEFLATE | 12.589 | 14.730 | 1.17× |
| 单文件加密 DEFLATE | 38.195 | 53.497 | 1.40× |
| 单文件 Zstd | 10.815 | 13.977 | 1.29× |
| 单文件加密 Zstd | 37.761 | 48.701 | 1.29× |
| 目录未加密混合格式 | 33.000 | 69.903 | 2.12× |
| 目录加密混合格式 | 119.204 | 223.437 | 1.87× |

本次 Haskell 的目录输出吞吐量分别为约 915.55 MiB/s 和 286.43 MiB/s。两版目录模式均使用各自默认并行策略；Haskell 自动按可用 CPU 数调整 worker 和 capability。

小文件结果有明显噪声：例如单文件未加密 DEFLATE 的 C++ 范围是 6.495–15.616 ms，Haskell 是 7.987–18.035 ms。不能据此认为小幅差异适用于所有数据。目录场景的差异更明显，但具体原因需要后续 profiling，当前数据不足以把开销归因到 TEA、GC、内存复制或 IO 中的某一项。

## 可重复执行

```bash
cabal bench migration-bench --benchmark-options='--baseline /home/present/.local/state/xlog/backups/20260905-2Wnx8rPo/xlog.cpp --candidate /home/present/.local/bin/xlog'
```

被测二进制 SHA-256：

```text
C++     35684ed569a8d065444740951f0950e421c1780ff14dd932f0dad5ddfc101c34
Haskell 103d36f0ab886b20c6112f7cb18e340a70ab6188a749aef63560f49f4d7b89a2
```

原始数据：[samples-20260905.csv](samples-20260905.csv)。本机完整运行报告在 `bench/results/migration-defaults/report.md`。这是合成日志、已安装版本及当前运行环境的结果，不是语言本身的性能排名。
