# Migration benchmark

用 Haskell 编写的端到端 benchmark，对比原 C++ 可执行文件和 Haskell 可执行文件。它不会改动被测程序、默认密钥或用户日志。

可选地加入原样运行的 Python 解码脚本；benchmark 驱动仍全部使用 Haskell。只有指定 `--python-script` 时才需要 Python 环境。

已完成的本机对比见 [RESULTS.md](RESULTS.md)，原始样本随结果保留，便于后续版本复测。

加入 `decode.py` 后的三方实测见 [PYTHON-RESULTS.md](PYTHON-RESULTS.md)。

```bash
cabal bench migration-bench --benchmark-options='--baseline /path/to/old-xlog --candidate /path/to/new-xlog'

# 本机迁移前的备份与当前安装版本
cabal bench migration-bench --benchmark-options='--baseline /home/present/.local/state/xlog/backups/20260905-2Wnx8rPo/xlog.cpp --candidate /home/present/.local/bin/xlog'

# 不指定 --candidate 时，Cabal 自动构建并使用本项目的 xlog-hs
cabal bench migration-bench --benchmark-options='--baseline /path/to/old-xlog'

# 加入本机 Python 2.7 版本；6 轮让三个程序均衡轮换执行位置
cabal bench migration-bench --benchmark-options='--baseline /home/present/.local/state/xlog/backups/20260905-2Wnx8rPo/xlog.cpp --candidate /home/present/.local/bin/xlog --python-script /home/present/dev/tool/decode.py --rounds 6'

# 查看选项
cabal bench migration-bench --benchmark-options='--help'
```

默认读取 XDG 配置目录的 `xlog/private.key`，也可通过 `--key-file` 指定。密钥必须与 C++ 程序内置密钥相同；不匹配时输出校验会失败，不会生成该场景的有效结果。密钥及派生秘密不写入报告。

`--python-script PATH` 指定第三个解码器，`--python PATH` 可覆盖解释器（默认在 PATH 中查找 `python2`）。实际命令为 `PYTHON -B SCRIPT INPUT`；不改脚本、不移植到 Python 3，也不注入其他解密库。脚本内置密钥须与语料密钥一致。`decode.py` 的目录模式串行处理文件，C++ 和 Haskell 保持默认并发；三方结果反映实际运行方式的差异。Python 解释器启动和依赖导入也计入耗时。

## 场景与方法

默认六个场景：未加密 DEFLATE、加密 DEFLATE、未加密 Zstd、加密 Zstd 的单文件解码，以及未加密/加密的 DEFLATE + Zstd 混合目录解码。

- 每个文件 128 条记录，每条解码后 16 KiB，即每个文件输出 2 MiB。
- 目录包含 32 个文件，输出共 64 MiB；两版保留自己的默认并行策略。
- 每个程序每个场景预热 1 次，再正式测量 5 次；测量顺序每轮循环移位。两方时交替先后；三方时建议 `--rounds 6` 均衡先后位置。
- 输入为确定性的日志形状合成数据，包含变化的请求 ID 和重复字段。同一种压缩格式的文件复用同一记录序列。
- 每条加密记录都需要被测程序执行 ECDH、16 轮 TEA 和解压。生成语料时的压缩、加密不计时。
- 用单调时钟测量进程启动、读取、解码和写出的总墙钟时间。每次运行前移除上一次的输出，两版都创建新文件。
- 每一次预热和测量都在计时结束后逐字节检查全部输出，避免把错误或空输出误认为速度提升。
- 每个子进程限时 300 秒；临时语料通过 `bracket` 清理。清除子进程的 `GHCRTS` 环境变量，避免继承隐藏的运行参数。

可调整 `--rounds`、`--warmups`、`--files`、`--records` 和 `--record-bytes`，均要求正整数。`--output` 指定一个不存在的报告目录，默认使用 `bench/results/时间戳/`。报告含中位数、最小/最大耗时、解码输出吞吐量，以及其他程序相对 Haskell 的耗时比值；大于 1 表示 Haskell 更快。

生成文件：

- `report.md`：测量环境、二进制信息和汇总表。
- `samples.csv`：各轮原始耗时、输入/输出字节数和吞吐量。

## 解读限制

这是实际二进制及其默认策略的迁移对比。C++ 的编译参数无法从已剥离符号的备份程序中确认；Haskell 版本还包含更严格的错误处理和原子输出替换，因此不能把差异全部归因于语言。

测试使用预热后的文件系统缓存，不执行 fsync、不清空系统缓存。在本机运行时 `/tmp` 为 tmpfs，所以不是磁盘冷读写吞吐量。若要测量指定磁盘的临时文件行为，可在启动前设置 `TMPDIR`。合成数据不能代表所有生产日志；耗时很短或 min/max 差异较大的场景，应结合原始样本判断噪声，不把小幅差异视为确定结论。
