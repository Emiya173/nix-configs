# xlog-hs

依据 `XlogDecoder-cpp`（本地参考提交 `9812626912585d3057b0afc548e9b47d5b42e981`）实现的 Mars xlog 解码器。提供 Haskell 库和命令行程序，支持原项目的全部 13 种记录类型。

## 构建与运行

需要 GHC ≥ 9.2（含 hsc2hs）、Cabal、C99 编译器、pkg-config，以及 zlib ≥ 1.2.11、libzstd ≥ 1.4.0、OpenSSL libcrypto ≥ 3.0 的开发文件。已在 Linux / GHC 9.12.2 下验证。

```bash
# Debian / Ubuntu 的系统依赖
sudo apt-get install pkg-config zlib1g-dev libzstd-dev libssl-dev

cabal build all
# 一次运行核心测试和 CLI 集成测试
cabal test --test-show-details=direct

# 默认输出 app.xlog.log
cabal run xlog-hs -- app.xlog

# 指定输出文件
cabal run xlog-hs -- app.xlog decoded.log

# 加密日志：密钥文件包含 64 个十六进制字符，允许首尾空白
cabal run xlog-hs -- --private-key-file server.key app.xlog

# 也可将密钥保存为 ~/.config/xlog/private.key，之后直接解码
# 设置 XDG_CONFIG_HOME 时，默认路径为 $XDG_CONFIG_HOME/xlog/private.key

# 非递归处理目录，默认按可用逻辑 CPU 数设置 worker
cabal run xlog-hs -- ./logs

# 手动覆盖文件并发数
cabal run xlog-hs -- --jobs 4 ./logs

# 从第一个字节开始严格校验，限制单文件解码输出为 64 MiB
cabal run xlog-hs -- --strict --max-output 67108864 app.xlog
```

不传路径时处理当前目录的 `*.xlog`。已有输出文件在解码成功后通过同目录临时文件及 rename 替换；失败时保留原输出。输入和输出指向同一路径（包括符号链接）会被拒绝。批处理中单个文件失败不会阻止其他文件，最终退出码为非零。诊断写入 stderr，日志输出保留原始字节。

每次启动时通过 GHC 的 `getNumProcessors` 检测可用逻辑 CPU 数，作为默认 worker 上限；`--jobs N` 可手动覆盖。实际 worker 数不会超过待处理文件数。CLI 同步将运行时 capability 数设为 `min(可用逻辑 CPU 数, 实际 worker 数)`（空目录保留 1），因此无需额外传入 `+RTS -N`；这个自动设置也会覆盖启动时的 `-N` 值。单文件内部仍按记录顺序解码。

CLI 优先使用 `--private-key-file`，否则读取 XDG 配置目录下的 `xlog/private.key`；默认文件不存在时仍可处理未加密记录。建议密钥文件权限为 `600`。这个默认值仅属于 CLI，库调用仍通过 `DecodeOptions` 显式传入密钥。

安装为 `~/.local/bin/xlog` 后，Yazi 26.9 的 opener 可逐个处理选中文件，避免第二个路径被当成输出路径：

```toml
[opener]
xlog = [{ run = 'for file in %s; do "$HOME/.local/bin/xlog" -- "$file" || exit; done', desc = "Decode xlog (Haskell)", for = "unix" }]

[open]
prepend_rules = [{ url = "*.xlog", use = "xlog" }]
```

库和主程序的 Haskell 依赖仅使用随 GHC 提供的 `base`、`bytestring`、`binary`、`directory` 和 `filepath`；CLI 测试另用 `process`，样本生成工具另用 `text`，也均随 GHC 提供。系统依赖已安装时可以使用 `cabal build --offline` 和 `cabal test --offline`。构建、测试和样本生成均不需要 Python。

## FP 设计

| 模块 | 职责 |
| --- | --- |
| `Xlog.Types` | 用 ADT 表达编码方式、错误、恢复诊断和解码配置 |
| `Xlog.Format` | 纯函数解析头部、校验长度及结束字节、重同步、拼接分块 |
| `Xlog.Crypto` | 纯 XOR、16 轮 TEA、私钥 smart constructor |
| `Xlog.Decode` | 通过 `Backend m` 显式注入能力的解码流程 |
| `Xlog.Native` | 压缩和 ECDH 的 IO/FFI 边界，管理 native 缓冲区生命周期 |
| `Xlog` | 面向使用者的库入口 |
| `app/Main.hs` | 参数解析、文件 IO、原子替换输出、有界 worker 池 |

核心状态通过递归参数显式传递；使用严格字段和 `ByteString.Builder` 累积输出，避免反复拼接复制。业务失败返回 `Either DecodeError`，不会在库中 `exit`，也不使用 `unsafePerformIO`。native 调用保留在 `IO` 中；测试可注入 `Backend Identity` 验证无副作用路径，不需要堆叠无实际用途的 monad transformer。

`PrivateKey` 和 `TeaKey` 隐藏构造器，只能通过校验函数构造；私钥范围必须是 `1 <= d < secp256k1 的阶`，`Show` 不泄漏其内容。源码没有参考项目的实际私钥。`test/fixtures/test-private-key.txt` 中的标量 **1 仅供测试**。

```haskell
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Xlog

main :: IO ()
main = do
  input <- BS.readFile "app.xlog"
  result <- decodeXlog defaultDecodeOptions input
  case result of
    Left err -> print err
    Right report -> do
      LBS.writeFile "decoded.log" (decodedBytes report)
      mapM_ print (diagnostics report)
```

加密记录需要先 `parsePrivateKey`，再设置 `defaultDecodeOptions { privateKey = Just key }`。配置也允许分别设置单记录输入长度、单记录输出长度和整文件输出长度上限；默认分别为 64 MiB、256 MiB、1 GiB。所有上限必须为正数。

## 格式对应

多字节头字段和 TEA word 均显式使用 little-endian；ECDH 私钥、共享秘密和公钥坐标使用 big-endian 字节表示。TEA 密钥取共享秘密前 16 字节，再按四个 LE Word32 解释。

| Magic | 头长度 | 载荷处理 |
| --- | ---: | --- |
| `01` | 5 | XOR |
| `02` | 5 | XOR → raw DEFLATE |
| `03` | 9 | XOR |
| `04` | 9 | XOR → raw DEFLATE |
| `05` | 9 | 拼接 LE Word16 长度前缀的分块 → XOR → raw DEFLATE |
| `06`, `08`, `0a`, `0b` | 73 | 原样输出（同步记录） |
| `07` | 73 | secp256k1 ECDH → 16 轮 TEA → raw DEFLATE |
| `09` | 73 | raw DEFLATE |
| `0c` | 73 | secp256k1 ECDH → 16 轮 TEA → Zstd |
| `0d` | 73 | Zstd |

5 字节头为 `magic:u8, length:u32le`；9 字节头为 `magic:u8, seq:u16le, beginHour:u8, endHour:u8, length:u32le`；73 字节头在 9 字节头之后附加 64 字节 `x || y` 公钥。每条记录以 `00` 结束，长度字段不包含头和结束字节。

XOR key 为 `0xcc XOR magic XOR (length & 0xff)`（`01/02`），或 `0xcc XOR magic XOR (seq & 0xff)`（`03/04/05`）。TEA 仅处理完整 8 字节块，末尾不足 8 字节原样保留。

## 兼容行为与边界

- 默认 `Recover` 寻找下一个结构合法的记录，并报告跳过的字节。`Strict` 遇到坏头、截断或错误结束标记立即失败。重同步仅依据结构，损坏数据有可能形成伪记录；严格模式适用于不能接受跳过数据的场景。
- 缺失序号是单独的 `SequenceGap`，不会混入解码正文。序号 0 不更新状态，1 视为重置，Word16 回绕被正确处理。解密或解压失败在两种模式下都会返回错误；`Recover` 不会静默丢弃此类失败。
- 空文件产生空输出；非空文件找不到合法记录时返回 `NoRecords`。允许合法的零长度记录。修正了原项目 `01/03` 分支向空 vector 下标写入的问题，以及 `05` 分块缺少边界检查的问题。
- raw DEFLATE 同时接受完整流和以 `Z_SYNC_FLUSH` 结束的记录，并检查错误码；Zstd 支持完整帧、拼接帧和 `ZSTD_e_flush` 流。为兼容未结束的 Zstd 流，输入已消费且已产出内容时可返回成功，因此不能保证检测所有尾部截断；`--strict` 针对 xlog 记录结构，不等于压缩帧完整性验证。
- ECDH 使用 OpenSSL 3 EVP。参考项目所附 micro-ecc 提交 `fe8ed90abc356347378eb25e2586e90df7be015a` 在本机对部分合法边界标量返回失败，因此未将它作为运行依赖。
- 当前每个 worker 读取整个输入文件，返回 lazy 输出字节串，但不是恒定内存的流式文件解码器。总内存随输入、实际输出及 worker 数增长。输出限制在 native 扩容时检查，Zstd 窗口也有限制；大文件或高压缩率文件可在库配置中调整上限。
- 已用独立生成的协议样本验证；参考项目未附真实日志样本，因此尚未完成生产日志的差分验证。未声明 Windows/macOS 已验证。

## 测试与资料

所有测试和样本生成逻辑都使用 Haskell：

| 入口 | 职责 |
| --- | --- |
| `test/Main.hs` | 33 组核心测试：全部 magic、ECDH/TEA、flush 流、扩容、截断前缀、坏分块、无效密钥、输出上限、恢复与序号、确定性随机输入 |
| `test/cli/Main.hs` | 27 组 CLI 测试：文件、目录自动并发、空目录、失败退出码、诊断、输出保护和默认密钥读取 |
| `test/support/Test/Support.hs` | 两个测试套件共用的断言、异常报告和退出码处理 |
| `tools/fixtures/` | 独立的 Haskell 样本编码器及压缩 FFI，生成 61 个 fixture 文件 |

`cabal test` 自动构建被测 CLI，通过 `build-tool-depends` 提供可执行文件路径，无需预先安装程序或手动运行脚本。每个 CLI 用例使用独立临时目录，通过 `bracket` 清理资源，子进程有 30 秒超时。

`test/fixtures/` 保留固定 golden 样本；测试不会自动重写它们。生成器不依赖 `xlog-hs` 库，独立实现记录编码、XOR、TEA 加密和公开测试点运算。压缩通过 Haskell FFI 调用系统 zlib/Zstd，`.hsc` 使用 hsc2hs 从系统头文件取得结构布局。它的私钥固定为公开测试标量 1，点运算仅用于测试数据生成。

```bash
# 独立生成到指定目录
cabal run generate-fixtures -- /tmp/xlog-fixtures

# 只校验现有样本，不写入文件
cabal run generate-fixtures -- --check test/fixtures
```

迁移时已验证 Haskell 生成结果与原有 61 个文件逐字节一致。不同系统压缩库版本可能产生不同的压缩字节，因此 `--check` 是显式的重现检查，不作为默认测试的前置条件；默认测试始终读取固定样本校验解码结果。

## 性能对比

新增 Haskell benchmark，对比迁移前 C++ 程序和 Haskell 程序，覆盖单文件、目录自动并行、未加密及旧密钥加密的 DEFLATE/Zstd 场景：

```bash
cabal bench migration-bench --benchmark-options='--baseline /path/to/old-xlog --candidate /path/to/new-xlog'

# 可选加入 Python 解码器；默认使用 python2，可通过 --python 指定解释器
cabal bench migration-bench --benchmark-options='--baseline /path/to/old-xlog --python-script /path/to/decode.py --rounds 6'
```

每个场景默认预热一次、测量五次，交替执行顺序；每次均校验输出。报告包含中位数、吞吐量和 CSV 原始数据。方法、可调参数及限制见 [bench/README.md](bench/README.md)，本次实测见 [bench/RESULTS.md](bench/RESULTS.md)。benchmark 另使用随 GHC 提供的 `time`，不增加 Haskell 外部包依赖。

Python 2.7 原脚本的三方对比见 [bench/PYTHON-RESULTS.md](bench/PYTHON-RESULTS.md)：三方测量使用六轮循环移位，保持原程序和默认并行策略，并校验每次输出。

实现时核对了 [zlib 手册](https://www.zlib.net/manual.html)、[Zstd 流式 API](https://github.com/facebook/zstd/blob/dev/lib/zstd.h) 和 [OpenSSL EVP ECDH](https://docs.openssl.org/3.0/man3/EVP_PKEY_derive/)；格式和 TEA 参数以本地参考项目为准。MIT 许可证保留原项目版权声明；系统库沿用各自许可证。
