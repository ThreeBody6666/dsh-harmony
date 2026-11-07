# 本机引擎（真·本地）实施计划 —— 按 DSHM 的路子

> 结论：**不跑虚拟机，不连远程。HAP 里自带 libnode + dsh 核心树，进程内起
> `127.0.0.1:3080`，界面连本地。** 这条路 DSHM 已经跑通并上架，我们照着做，
> 只是界面用 dsh-go 的风格，不用 ArkWeb 装官方 Web UI。

## 一、DSHM 已验证的事实（从它源码与文档扒的）

| 事实 | 值 / 出处 |
|---|---|
| Node 运行时 | `libnode.so.137`（Node 24.2.0），**126 MB**，放 `entry/libs/arm64-v8a/` |
| 加载方式 | C++ NAPI 宿主 `hostruntime/src/main/cpp/dshhost.cc`，**候选名逐个 dlopen**：`libnode.so.137` → `libnode.so.127` → `libnode.so` |
| 核心树 | 打成一个 zip 放 `entry/src/main/resources/resfile/`，**约 84 MB**；首启解包到应用私有目录 |
| 启动参数 | `--jitless`（上架要求；代价是 `WebAssembly === undefined`） |
| execve | 沙箱内第三方 ELF 一律被拒 ⇒ 工具链（python/git/rg/busybox）**构建期自签名**，或走纯 JS 降级 |
| 成品包体 | signed HAP **306 MB** |
| 许可 | MIT（需署名） |

关键一句：**它没有用 proot，也没起虚拟机**。Node 就是被当成一个 `.so` 加载进应用进程的。

## 二、我们要做的四件事

### 1. 拿 libnode
两条路：
- **快**：从 DSHM 的已签 HAP 里取出 `libs/arm64-v8a/libnode.so.137`（MIT，署名即可）
- **慢但独立**：用 [hqzing/ohos-node](https://github.com/hqzing/ohos-node) 的 `build.sh`
  在 CI 里自己编（需要 OHOS NDK，命令行走廊有；node 全量编译 30–60 分钟）

阶段性建议：先走「快」的，把链路跑通；跑通后再换自编。

### 2. 打包核心树
`npm install @deepseek-ai/dsh`（或从 GitHub 拉源码构建），把 `node_modules` 裁掉
`*.d.ts / *.map / *.md / 测试目录`，压成 `core.zip` 放进 `resfile/`。
DSHM 的成品是 84 MB，我们照这个口径。

### 3. 写宿主（C++ NAPI）
我们工程里已有 `entry/src/main/cpp/`（今天的桩可作骨架），要补：
- `dlopen("libnode.so.137")`
- 解析并调用 Node 的嵌入入口（`node::Start` / `libnode` 导出的 `napi_*`）
- 把 argv 组装成：`node --jitless <core>/bin/dsh.js web --host 127.0.0.1 --port 3080 --no-open`
- 首启解包 `core.zip`（纯 JS tar/zip 解，避免依赖 spawn）
- 读取引擎启动后打印的 token，回调给 ArkTS

### 4. 界面
**已经写好了**：`pages/Index.ets` 那套 dsh-go 风格的三段式（连接 / 会话 / 聊天）
+ 平板双栏 + 协议客户端。只要把「连接页」换成「本机引擎自动就绪」，
登录地址固定 `http://127.0.0.1:3080`，其余不变。

## 三、为什么不在手机上做这些

- 手机侧 GitHub 下载被限速（实测 306 MB 的包 5 MB/10 分钟）
- 本机没有 NDK / SDK

**全部改到 CI 里跑**：GitHub Actions 拉 GitHub Release 是内网速度，
`harmonyos-ci` 镜像里带 NDK。所以：
`fetch 运行时` → `打包 core.zip` → `CMake 编宿主` → `出 HAP` 都在云端完成。

## 四、里程碑

| 阶段 | 验收 | 预计 |
|---|---|---|
| M1 | CI 能拉到 libnode + 打出 core.zip，HAP 体积到 250 MB+ | 1 轮 |
| M2 | 宿主 dlopen 成功，日志打出 node 版本 | 1–2 轮 |
| M3 | `127.0.0.1:3080` 返回 200，ArkTS 自动登录进会话列表 | 2–3 轮 |
| M4 | 能聊天、能跑 bash 工具（工具链自签名或纯 JS 降级） | 看沙箱 |
| M5 | 平板双栏 + dsh-go 视觉打磨 | 收尾 |

每一轮都是「改代码 → push → CI 出 HAP → 你侧载试」。我这边看不到真机，
所以每一步的验收得靠你装上去看一眼——但链路是通的，今天已经证明 CI 能出包。

## 五、风险

| 风险 | 说明 |
|---|---|
| libnode 版本 | DSHM 用 24.2.0；我们的 dsh 版本要对上，否则 ABI 不匹配 |
| `--jitless` 限制 | 没有 WebAssembly；dsh 核心树里若有用 wasm 的插件会挂 |
| 工具链 execve | 不签名就执行不了；要么构建期签名，要么纯 JS 降级 |
| 包体 | 250–320 MB，侧载没问题，上架会被卡 |
| 我无法本地验证 | 只能靠 CI + 你的真机反馈闭环 |
