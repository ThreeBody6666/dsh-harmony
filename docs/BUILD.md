# 构建与安装（HarmonyOS NEXT）

本工程面向 **API 12 / HarmonyOS 5.0.0**（stage 模型，ArkTS + ArkUI），没有任何三方 ohpm 依赖。

> 说明：本工程是在手机上的 Ubuntu(proot) 里写的，那里**没有** HarmonyOS SDK，
> 所以代码只做过静态自检（`node tools/verify.mjs`），真正的编译要在装了
> DevEco Studio 的电脑上完成。

---

## 一、环境

| 工具 | 版本 | 说明 |
|---|---|---|
| DevEco Studio | 5.0 及以上 | 自带 hvigor、ohpm、SDK Manager |
| HarmonyOS SDK | API 12（5.0.0） | SDK Manager 里装 `HarmonyOS 5.0.0(12)` |
| 设备 | HarmonyOS NEXT 真机 | 模拟器也能跑，但连不到你电脑的引擎时意义不大 |

首次打开工程后 DevEco 会提示同步（Sync Now），让它下载 hvigor 依赖即可。

## 二、签名

真机安装必须签名，两种方式：

1. **自动签名**（推荐）：`File → Project Structure → Signing Configs`，勾选
   `Automatically generate signature`，登录华为开发者账号，DevEco 会生成调试证书。
2. **手动签名**：准备好 `*.p12`、`*.cer`、`*.p7b`，在同一个面板里填进去，然后
   把 `build-profile.json5` 里 `products[0].signingConfig` 改成对应名字。

> `build-profile.json5` 里的 `signingConfigs` 目前是空数组，就是留给签名面板写入的。

## 三、构建

DevEco 里直接 `Build → Build Hap(s)/APP(s) → Build Hap(s)`。

命令行（在工程根目录）：

```bash
# 需要先把 DevEco 的 hvigor 与 SDK 路径配好，或直接用 DevEco 自带的终端
./hvigorw clean --no-daemon
./hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`

## 四、装到手机

```bash
hdc list targets
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.dshgo.app
```

手机上需要开启「开发者选项 → USB 调试」。

## 四·五、原生桥与本机模式

工程带一个 NAPI 原生模块（`entry/src/main/cpp`），`entry/build-profile.json5` 里已经配好：

```json5
"externalNativeOptions": { "path": "./src/main/cpp/CMakeLists.txt" },
"nativeLib": { "abiFilters": ["arm64-v8a"] }
```

- **没放 qemu 库时**：CMake 编 `vm_host_stub.cpp`，产物仍是 `libentry.so`，App 正常安装；
  点「在手机本机启动引擎」会提示「后端未接入」。
- **放了 qemu 库时**：`./scripts/fetch-vm-assets.sh --qemu`，CMake 自动改编
  `qemu_backend/qemu_backend.cpp`，走真实现。
- 需要 NDK（DevEco 自带），目标架构 arm64-v8a。

## 五、连不上引擎时按这个顺序查

| 现象 | 原因 | 处理 |
|---|---|---|
| 登录报 `auth/no-cookie` | token 过期（每次 `dsh web` 重启都会变） | 用最新打印的 token |
| 登录报 `auth/denied` / 403 | 引擎护栏拒绝了 authority | 启动时加 `--trusted-host <手机访问用的IP>:<端口>` |
| 请求超时 | 手机与电脑不在同一网段，或电脑防火墙拦了 | 先用手机浏览器打开 `http://<IP>:3080/?token=…` 试 |
| `WebSocket 在 ready 之前断开` | 引擎没起、或 cookie 失效 | 重新登录；确认 `dsh web` 还活着 |
| `session/follow: gateway/arguments-invalid` | 参数少包了 `request` | 见 `docs/PROTOCOL.md` 第 4 节 |

## 六、把引擎跑到电脑上（给手机连）

```bash
# 电脑上
dsh web --host 0.0.0.0 --port 3080 --trusted-host 192.168.1.10:3080
```

- `--host 0.0.0.0` 让局域网可访问（引擎本身拒绝通配地址，这里给了具体网卡地址，
  如果你的环境只接受具体 IP，就写电脑的局域网 IP）
- `--trusted-host` 写**手机访问时用的那个 authority**（IP:端口）
- 终端打印的 token 填进 App

想在公网用，建议加一层 TLS：引擎支持 `--tls-cert/--tls-key`，或前面挂 nginx，
并用 `--public-url` 声明外部地址（同时把外部域名加进 `--trusted-host`）。

## 七、常见编译问题

| 报错 | 处理 |
|---|---|
| `Cannot find module '@kit.NetworkKit'` | SDK 版本低于 API 12；改用 `import http from '@ohos.net.http'` 并把 SDK 升到 12 |
| `Property 'xxx' does not exist on type 'Object'` | ArkTS 严格模式不接受 `Object` 上的动态取键；用 `Record<string, Object>` 或补 interface |
| 页面白屏且日志 `loadContent failed` | `resources/base/profile/main_pages.json` 与 `pages/Index.ets` 路径不一致 |
| 图标报错 | `AppScope` 与 `entry` 各有一份 `app_icon.png`，缺一不可 |
