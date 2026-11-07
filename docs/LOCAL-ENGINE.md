# 本机引擎方案（手机本地跑 DSH，不连电脑）

> 目标：在**鸿蒙手机内部**跑完整的 DSH 引擎（Node + shell），不依赖任何外部机器。
> 结论先说：**能做成**，但不是 dsh-go 安卓版那套 proot，而是「应用内跑一台 Linux 虚拟机」。

---

## 一、先排除三条走不通的路

| 方案 | 为什么不行 | 依据 |
|---|---|---|
| proot + Ubuntu（安卓版做法） | 鸿蒙应用沙箱**禁止三方应用在手机设备上 Fork 进程**（2026-10-27 更新的官方 FAQ），proot 依赖 `fork/exec` | [华为 FAQ：是否允许三方应用在手机设备上Fork进程](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-ability-29) —「当前禁止三方应用在手机设备上Fork进程。」 |
| HNP 包（Termony / harmonix 在 PC 上的做法） | HNP 只在 PC/2in1 生效，**手机和平板不支持安装 hnp 包** | [知乎：鸿蒙PC、Pad和手机都能运行Linux了](https://zhuanlan.zhihu.com/p/1947748753579673022) —「遗憾的是，鸿蒙手机和Pad不支持安装 hnp 包」 |
| qemu-user（用户态模拟，harmonix） | 同样要 exec 目标 ELF，且受鸿蒙权限管控，很多能力做不到 | 同上文对 Harmonix 与 HiSH 的对比 |

> 反过来说：**只要不 fork/exec，而是把「跑 Linux」这件事放在应用自己的进程里，就能绕开沙箱限制。**

---

## 二、可行路径：把 qemu-system 编译成 .so，在应用内直接启动 Linux 虚拟机

[HiSH](https://github.com/harmoninux/HiSH)（683★，MIT）已经把这条路走通了，并且**明确支持手机**：

- 把 qemu-system-aarch64 **编译成动态库** `libqemu-system-aarch64-tci.so`（手机没有 JIT，用 TCG 解释器 TCI 版本）
- Linux 内核镜像 `kernel_aarch64` 和根文件系统 `rootfs_aarch64.qcow2` 作为 rawfile 打进 HAP
- 在应用进程内调用这个 .so 启动 VM，把串口重定向到 unix socket，前端用 hterm 呈现终端
- 已支持：完整 arm64 Linux 内核、**网络与端口转发**、共享文件夹、导入 Ubuntu 24.04 / Debian 12 镜像

**关键在于：整条链路没有一次 fork/exec。** qemu 是应用进程里 loaded 的共享库，客户机里的进程是 qemu 自己调度出来的，跟鸿蒙的进程沙箱无关。

### 我们要的架构

```
┌─────────────────────────── HAP（我们的应用）───────────────────────────┐
│  ArkTS UI（本工程已实现：连接/会话/聊天）                                │
│        │ HTTP + WebSocket                                           │
│        │ 127.0.0.1:3080  ←── 端口转发 ──┐                              │
│  NAPI 桥（LibVmHost）                  │                              │
│        │                               │                              │
│  libqemu-system-aarch64-tci.so ────► Linux VM（arm64）                 │
│  rawfile: kernel_aarch64               ├─ bash / coreutils            │
│  rawfile: rootfs.qcow2（预装 Node）     ├─ node 24 + @deepseek-ai/dsh   │
│                                        └─ /root/.dsh（用户数据）         │
└───────────────────────────────────────────────────────────────────────┘
```

也就是说：**UI 层一行都不用改**——它以为自己在连一台 `dsh web`，实际上连的是手机里的虚拟机。

---

## 三、需要哪些东西

| 组件 | 来源 | 体积（估算） |
|---|---|---|
| `libqemu-system-aarch64-tci.so` | 用 [harmoninux/qemu](https://github.com/harmoninux/qemu) 的 `deps` 构建（`make aarch64-tci`） | 30–50 MB |
| `kernel_aarch64` | [linux-config releases](https://github.com/harmoninux/linux-config/releases)（arm64_virt 配置） | 约 30 MB |
| `rootfs.qcow2` | 基于 Ubuntu 24.04 base，预装 Node 24 + dsh npm 包 | 80–150 MB |
| 启动器（C++ NAPI） | 自己写，照着 HiSH 的 `napi_*` 层裁剪 | 很小 |

整体 HAP 会到 **150–250 MB**（dsh-go 安卓版的运行时也不小，量级相当）。

### 现成物料（可以直接拿来验证 P0）

| 东西 | 地址 |
|---|---|
| 预编译 qemu 动态库 | HiSH 的 `libs.zip`：`https://github.com/harmoninux/qemu/releases/download/hish-20260110/libs.zip` |
| 内核 | `https://github.com/harmoninux/linux-config/releases/download/kernel-20260228/kernel_aarch64` |
| 根文件系统（qcow2） | `https://github.com/harmoninux/linux-config/releases/download/rootfs-20260117/rootfs_aarch64.qcow2` |
| Ubuntu 24.04 镜像 | `https://github.com/harmoninux/linux-config/releases/download/rootfs-20251213/ubuntu-base-24.04.zip` |
| 构建脚本参考 | HiSH 仓库 `deps/Makefile`（`make aarch64-tci`） |

用这些能在不编译任何东西的情况下先跑通 P0（VM 起得来、能进 shell）。

### 首启流程

1. 从 rawfile 释放 `kernel` / `rootfs` 到 `filesDir/vm/`（只在首次或版本升级时做，用版本号标记）
2. 通过 NAPI 调 `vm_start(kernelPath, rootfsPath, hostPort=3080)` → qemu 起 VM
3. VM 内 systemd/init 脚本启动 `dsh web --host 127.0.0.1 --port 3080 --no-open`，把 token 写到一个共享目录文件
4. ArkTS 侧轮询共享目录里的 `token` 文件（或由 NAPI 回调推送），拿到 token 后走现有登录流程
5. 停止时 `vm_stop()`；后台/前台切换时暂停与恢复

**端口转发**这一步 HiSH 已实现，我们照搬：qemu 的 user-mode 网络把客户机 3080 映射到应用进程的 127.0.0.1:3080。

---

## 四、性能，得说实话

| 场景 | 预期 |
|---|---|
| 有 JIT（侧载安装 + 开发者模式） | 接近原生 ARM 性能，Node 启引擎约 2–5 秒 |
| 无 JIT（应用市场版本，TCI 解释器） | 慢很多，Node 启动 15–40 秒，npm 装依赖会很难受，日常聊天可以接受 |
| 功耗与发热 | VM 常驻会明显增加耗电；建议「用时启动、闲时挂起」，并做前台服务保活 |

优化方向：
- **预烘焙镜像**：rootfs 里预先装好 Node 与 dsh，首次启动不联网、不 npm install，只解压
- **快照**：VM 启动后保存快照，二次启动直接恢复（qemu 支持 `savevm`）
- **懒加载**：只在用户进「本机模式」时启动 VM，远程模式不付这个代价
- **TCI→JIT 自适应**：检测是否允许 JIT，选择对应 .so

---

## 四·五、已经落地的脚手架（本次交付）

工程里已经写好 P0/P1 的骨架，**不需要 qemu 库也能构建、能安装、能跑**：

| 文件 | 作用 |
|---|---|
| `entry/src/main/cpp/CMakeLists.txt` | 检测 `vendor/qemu/*.so`：有 → 编真实现，无 → 编桩实现 |
| `entry/src/main/cpp/napi_init.cpp` | NAPI 绑定：`nativeVersion` / `vmStart` / `vmStop` / `vmStatus` |
| `entry/src/main/cpp/vm_host_stub.cpp` | 桩：返回明确错误，帮你知道「后端还没接」 |
| `entry/src/main/cpp/qemu_backend/qemu_backend.cpp` | 真实现：dlopen qemu、拼 `-kernel/-drive/-netdev hostfwd` 参数、起线程 |
| `entry/src/main/ets/client/LocalEngine.ets` | 释放 rawfile → 起 VM → 轮询 token → 交给登录流程 |
| `entry/src/main/ets/pages/Index.ets` | 连接页多了「在手机本机启动引擎」按钮 |
| `scripts/fetch-vm-assets.sh` | 一条命令拉内核 / rootfs / qemu 动态库 |

跑通顺序（真机上）：

1. `./scripts/fetch-vm-assets.sh`
2. DevEco 构建安装（CMake 自动识别真实现）
3. 点「在手机本机启动引擎」→ 看日志 `LocalEngine` / `DSHGoVM`
4. 若停在 `error:no-entry`，改 `qemu_backend.cpp` 里的 `kEntryCandidates`（不同 qemu 分支导出名不同）

诚实的边界：**qemu 的具体入口符号和参数集需要对着你选的 qemu 分支确认一次**，
这一步没有 SDK 我验证不了，但接口边界、生命周期、参数拼装都已经写死在这里了。

## 五、实施计划（分四步，每步都能验收）

**P0｜VM 能起来（1 周量级）**
- 拿到预编译的 `libqemu-system-aarch64-tci.so` + kernel + alpine rootfs
- 写最小 NAPI 桥：`start(kernel, rootfs)` / `stop()` / `onSerial(cb)`
- 验收：手机上能进 Alpine shell（不是我们的 UI，先证明能跑）

**P1｜网络通（3–5 天）**
- 打开 qemu 的 user-mode 网络与 hostfwd，验证 VM 内 `curl 127.0.0.1:3080` 从应用侧可达
- 验收：VM 里起一个 `python3 -m http.server`，ArkTS 侧能 GET 到

**P2｜引擎跑起来（1–2 周）**
- 烘 rootfs：装 Node 24（arm64）+ dsh，配好入口脚本与 token 落盘
- 验收：App 的「本机模式」能登录、能聊天、能执行 bash 工具

**P3｜打磨（持续）**
- 首启解压进度、VM 生命周期、快照加速、电量策略、崩溃恢复、日志面板

---

## 六、风险清单

| 风险 | 影响 | 应对 |
|---|---|---|
| 手机无 JIT，性能差 | 体验差 | 预烘焙 + 快照；侧载版走 JIT |
| HAP 体积大 | 分发受限 | 首启下载 rootfs（增量包），而不是内置 |
| 上架政策（应用市场对 VM/JIT 敏感） | 无法上架 | 走侧载分发，或只保留「远程模式」上架 |
| qemu 在部分机型/系统版本上不稳定 | 崩溃 | 跟 HiSH 的已知问题清单，先做设备白名单 |
| 许可 | 合规 | HiSH 是 MIT，但按其要求需在「关于」页注明基于 HiSH 及其仓库地址；qemu 是 GPLv2，动态库形式分发需评估合规 |
| 电池/发热 | 用户抱怨 | 缺省不常驻，进设置可调 |

---

## 七、和远程模式的关系

不是二选一：

- **远程模式**（本工程已实现）：轻、稳、零体积代价，适合「电脑就在旁边」
- **本机模式**（本文件方案）：重、慢、但离线可用，是 dsh-go 的立身之本

UI 层共用同一套协议客户端，只在「引擎从哪来」这一层分叉——本工程现在的
`ConnectView` 里加一个「本机」入口即可复用全部聊天代码。

---

## 八、参考

- [HiSH — 在鸿蒙上运行 Linux Shell，支持手机/平板/PC](https://github.com/harmoninux/HiSH)（MIT，683★，方案来源）
- [qemu-ohos — 面向鸿蒙裁剪的 qemu](https://github.com/harmoninux/qemu)
- [linux-config — 内核与 rootfs 镜像](https://github.com/harmoninux/linux-config)
- [知乎：鸿蒙PC、Pad和手机都能运行Linux了](https://zhuanlan.zhihu.com/p/1947748753579673022)（原理与 hnp 限制）
- [华为 FAQ：是否允许三方应用在手机设备上 Fork 进程](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-ability-29)
- [Termony — 鸿蒙版 Termux（PC 路线，HNP）](https://github.com/TermonyHQ/Termony)
- [hqzing/ohos-node — OpenHarmony 原生 Node 构建](https://github.com/hqzing/ohos-node)（备选：不跑 VM 直接嵌 Node）
