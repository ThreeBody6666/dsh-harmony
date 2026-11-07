# 原生桥（NAPI）

这一层只做一件事：**在应用进程里把 Linux 虚拟机跑起来**，让 ArkTS 侧能
`start / stop / status` 它，并拿到 VM 里 `dsh web` 的地址。

## 为什么是「进程内 VM」而不是起子进程

华为官方 FAQ 写明「当前禁止三方应用在手机设备上 Fork 进程」，
所以不存在 `exec bash` / proot 这条路的可能。可行做法是把
`qemu-system-aarch64` 编成**动态库**，通过 `dlopen` 加载进应用进程，
由 qemu 自己在内部调度客户机进程——全程没有 `fork/exec`。

这条路线由 [HiSH](https://github.com/harmoninux/HiSH)（MIT）验证过，手机可用。

## 目录

```
cpp/
  CMakeLists.txt     构建脚本；检测 vendor/qemu/ 是否存在，决定编「真实现」还是「桩」
  napi_init.cpp      NAPI 绑定：vmStart / vmStop / vmStatus / nativeVersion
  vm_host.h          后端抽象（两个实现共用）
  vm_host_stub.cpp   默认实现：不依赖 qemu，只返回「未接入」
  qemu_backend/      放进 qemu 库后启用的真实现（见下）
```

## 接上真实现的三步

1. 跑 `scripts/fetch-vm-assets.sh`，或者手动把 HiSH 的产物放进 `entry/src/main/cpp/vendor/qemu/`：
   - `libqemu-system-aarch64-tci.so`（手机用 TCI 版；有 JIT 的设备用普通版）
   - `qemu-host.h`（后端要调用的入口声明，需按所选 qemu 分支的导出符号写一版）
2. 实现 `qemu_backend/qemu_backend.cpp` 里的三个函数：
   - `backend_available()`：dlopen 成功即 true
   - `backend_start(kernel, rootfs, hostPort, err)`：加载内核与 qcow2，配置 `-netdev user,hostfwd=tcp::3080-:3080`，起 VM 线程
   - `backend_stop()`：发 `quit` 让 qemu 退出并回收线程
3. 重新 Sync 构建，`vmStart` 就会走真实现。

> 具体调用签名取决于你用的 qemu 分支（harmoninux/qemu 把 `main` 改成了
> 可重入的入口）。把 `vendor/qemu/qemu-host.h` 放进去后，`CMakeLists.txt`
> 会自动编译 `qemu_backend/` 并把头文件路径加上。

## NAPI 接口

| 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `nativeVersion()` | — | string | 桥版本 + 后端类型（`stub` / `qemu-tci` / `qemu-jit`） |
| `vmStart(kernelPath, rootfsPath, hostPort)` | 三个 string/number | string | 成功返回空串，失败返回错误说明 |
| `vmStop()` | — | string | 同上 |
| `vmStatus()` | — | string | `idle` / `starting` / `running` / `stopping` / `error:...` |

ArkTS 侧见 `entry/src/main/ets/client/LocalEngine.ets`。
