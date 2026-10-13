# C++ / Haskell / Python measurement — 2026-09-05

本次在同一次运行中重新测量三个程序，语料参数保持原 benchmark 默认值。Python 使用 `/home/present/dev/tool/decode.py` 原文件，未做移植、优化或密钥替换。

- CPU：Intel Core i7-14700，28 个可用逻辑 CPU；Linux x86_64。
- Python：2.7.18；pyelliptic 1.5.9；zstandard 0.14.1。解释器为 `/usr/bin/python2.7`。
- 原脚本内置密钥与现有 `xlog/private.key` 一致；全部运行均逐字节通过输出校验。
- 每个程序、每个场景预热 1 次，正式测量 6 次，共 108 次计时。每轮循环移位，让三个程序均衡占据先后位置。
- 单文件 128 条 × 16 KiB，输出 2 MiB；目录 32 个文件，输出 64 MiB。
- 计时包含解释器/程序启动、依赖导入、读入、解码及写出；生成、删除旧输出和输出校验不计时。
- `/tmp` 为 tmpfs，使用预热缓存，不执行 fsync。

| 场景 | C++ 中位数 ms | Haskell 中位数 ms | Python 中位数 ms | Python / Haskell 耗时 |
| --- | ---: | ---: | ---: | ---: |
| 单文件 DEFLATE | 7.635 | 8.267 | 29.210 | 3.53× |
| 单文件加密 DEFLATE | 41.365 | 54.153 | 710.225 | 13.12× |
| 单文件 Zstd | 9.540 | 12.596 | 41.177 | 3.27× |
| 单文件加密 Zstd | 36.253 | 51.487 | 668.359 | 12.98× |
| 目录未加密混合格式 | 29.552 | 72.199 | 148.562 | 2.06× |
| 目录加密混合格式 | 106.996 | 209.019 | 21078.440 | 100.85× |

本次 Haskell 在单文件加密场景约为 Python 的 13 倍速度；加密目录约为 101 倍。**目录比较保留了默认执行策略：Python 脚本串行遍历，C++ 和 Haskell 使用线程池。** 这不能理解为同等并行度下或语言本身的差距。原脚本的实现细节、依赖版本和启动成本也不同。

单文件未加密场景较短，容易受环境噪声影响；例如 Python Zstd 范围为 29.968–49.649 ms，Haskell 为 7.697–15.658 ms。加密目录较稳定：Python 为 21034.121–21288.188 ms，Haskell 为 193.789–227.620 ms。相对于先前两方运行的数字变化体现了重新测量时的环境波动，应在本表内比较同次运行的三个版本。

## 重现

```bash
cabal bench migration-bench --benchmark-options='--baseline /home/present/.local/state/xlog/backups/20260905-2Wnx8rPo/xlog.cpp --candidate /home/present/.local/bin/xlog --python-script /home/present/dev/tool/decode.py --rounds 6'
```

可通过 `--python PATH` 指定解释器。未指定 `--python-script` 时仍运行原有 C++ / Haskell 两方 benchmark，不需要 Python 环境。benchmark 驱动保持 Haskell 实现；Python 文件作为外部被测程序，未复制到仓库。

被测文件 SHA-256：

```text
C++       35684ed569a8d065444740951f0950e421c1780ff14dd932f0dad5ddfc101c34
Haskell   103d36f0ab886b20c6112f7cb18e340a70ab6188a749aef63560f49f4d7b89a2
decode.py 89f78bf8ae8cae504a0a0be24c7f31c3eb76a5cb96a6635d7deb4ae1250eb329
python2.7 e85a01e774ad72b4da7e5ea37365e13910e337ebcda5e0979e450a33895430af
```

原始数据：[samples-python-20260905.csv](samples-python-20260905.csv)。本机完整报告位于 `bench/results/python-comparison/report.md`。该结果针对合成日志和本机环境，不保证适用于所有生产日志。
