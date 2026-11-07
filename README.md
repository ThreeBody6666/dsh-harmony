# DSH Go · 鸿蒙端（HarmonyOS NEXT）

把 [dsh-go](https://github.com/ccch1mneyyy/dsh-Go)（DeepSeek​Harness 手机客户端）带到纯血鸿蒙。
这是一个 **ArkTS + ArkUI 的原生工程**，不是把 Flutter 塞进鸿蒙壳里。

> 状态：**首版可编译工程 + 远程引擎模式跑通**。已用真实引擎逐条验证过协议；
> 鸿蒙侧代码因本机没有 DevEco / HarmonyOS SDK，尚未做真机编译，见「验证情况」。

---

## 为什么不是「把现有 App 移植过去」

dsh-go 的 Android 版是三件套：Flutter UI + Kotlin 原生层 + **proot 里跑的 Ubuntu/Node 本机引擎**。

| 组成 | 鸿蒙 NEXT 上能不能直接搬 |
|---|---|
| Flutter UI | 不能。Flutter 官方不支持 HarmonyOS，只有社区 `flutter_ohos` 分支，且需要重做平台通道 |
| Kotlin 原生层（解压运行时、起进程、前台服务） | 不能。鸿蒙是 ArkTS/ArkUI，进程模型与 Android 完全不同 |
| proot + Ubuntu + Node（本机引擎） | 不能。鸿蒙**禁止三方应用在手机设备上 fork 进程**，proot 那套依赖 `fork/exec`；HNP 包又只在 PC 生效 |

所以鸿蒙端分两层：

1. **远程引擎模式**（本工程已实现）：手机只做客户端，连一台跑着 `dsh web` 的机器。
2. **本机引擎模式**（方案已定，待实施）：不做 proot，改成**在应用进程内跑一台 Linux 虚拟机**——
   把 qemu-system 编译成 `.so`（HiSH 证明手机能跑），内核 + rootfs 打进 HAP，VM 里跑 Node 引擎。
   完整方案、体积、性能与风险见 **[docs/LOCAL-ENGINE.md](docs/LOCAL-ENGINE.md)**。

两套模式共用同一份协议客户端，只在「引擎从哪来」这层分叉，所以本工程的聊天代码可以原样复用。

---

## 现在能做什么

- 用「引擎地址 + 启动 token」登录（token → cookie，与官方客户端同一套握手）
- 会话列表（含标题、cwd、运行状态，按更新时间排序）
- 新建会话
- 聊天：`session/follow` 实时流，消息 / 思考过程 / 工具卡片（可展开看参数与输出）/ 中断提示
- 发送消息（`session/prompt`）、中断当前回合（`session/cancel`）
- 流式增量（`assistant-stream` 的 text-delta / reasoning-delta）与 durable 事件去重
- 断线自动重连，重连后重新 snapshot 补齐

- **本机模式（脚手架已就位）**：连接页有「在手机本机启动引擎」，走
  rawfile 释放 → NAPI 起 VM → 轮询 token → 复用同一套聊天代码；qemu 后端需按
  [LOCAL-ENGINE.md](docs/LOCAL-ENGINE.md) 接入

暂未实现：插件、宠物/语音/手机操控、审批与提问卡片、图片附件、代码高亮渲染。

---

## 目录

```
dsh-harmony/
  AppScope/app.json5                应用级配置（bundleName / 版本 / 图标）
  build-profile.json5               构建产品与 SDK 版本
  hvigorfile.ts / oh-package.json5  根工程脚本与依赖
  entry/
    build-profile.json5             HAP 模块构建配置
    src/main/module.json5           模块声明、页面、权限（INTERNET）
    src/main/ets/
      entryability/EntryAbility.ets 应用入口
      pages/Index.ets               主页面（连接 / 会话 / 聊天 三分支）
      ui/ChatRows.ets               聊天行组件（气泡 / 思考 / 工具卡）
      ui/Theme.ets                  设计令牌
      ui/Storage.ets                preferences 持久化
      client/DshClient.ets          门面：登录、会话、prompt、follow 循环
      client/Transcript.ets         事件 → 可渲染条目
      net/Connection.ets            HTTP 载体 + 登录换 cookie
      net/Mux.ets                   WebSocket 多路流
      model/Types.ets               协议与领域模型
    src/main/cpp/                    原生桥（NAPI + qemu 后端 + 桩实现）
    src/main/resources/             资源（图标、字符串、颜色、页面表）
    src/main/resources/rawfile/vm/  内核与 rootfs（不入库，脚本拉取）
  scripts/fetch-vm-assets.sh        拉取 VM 物料
  docs/
    BUILD.md                        本地构建、签名、真机安装
    CLOUD-BUILD.md                  云端编译（GitHub Actions）
    PROTOCOL.md                     与引擎的协议（含实测记录）
    LOCAL-ENGINE.md                 本机引擎（手机本地跑）的完整方案
    ROADMAP.md                      后续能力与取舍
    API-NOTES.md                    鸿蒙 API 逐条核对结果
  tools/verify.mjs                  无 SDK 也能跑的静态自检
```

---

## 快速开始

手机/电脑上先起一个允许局域网访问的引擎：

```bash
dsh web --host 0.0.0.0 --port 3080 --trusted-host 192.168.1.10:3080
```

终端会打印 `dsh web: http://127.0.0.1:3080/?token=…`，把 **IP** 和 **token** 填进 App 的连接页即可。

> `--trusted-host` 是引擎的浏览器护栏：它只接受 loopback，或显式信任的 authority。
> 不带这个参数，手机用局域网 IP 访问会被 403。源码里 `docs/BUILD.md` 有说明。

---

## 云端编译（不需要本地 SDK）

工程带了 GitHub Actions 流水线：推到 GitHub 就自动在鸿蒙命令行工具链镜像里编译。

- 用法与排错：[docs/CLOUD-BUILD.md](docs/CLOUD-BUILD.md)
- 流水线：[.github/workflows/build-hap.yml](.github/workflows/build-hap.yml)
- 镜像：[harmonyos-ci](https://github.com/DaLongZhuaZi/harmonyos-ci)（MIT，公开可拉）

## 验证情况

| 项目 | 状态 | 说明 |
|---|---|---|
| 引擎协议（登录、session/list、create、prompt、page、follow、流式增量） | ✅ 已实测 | 在本机起独立 `dsh web`，用 Node 复刻同一套帧格式跑通，见 `docs/PROTOCOL.md` |
| 事件折叠逻辑（消息/思考/工具/去重） | ✅ 已实测 | 用真实 snapshot（349 条记录）+ 脚本化流式事件验证 |
| 工程结构自检 | ✅ 通过 | `node tools/verify.mjs`：JSON5、import 解析、资源引用、页面登记、括号配平 |
| ArkTS 编译 | ✅ 云端通过 | GitHub Actions 实测编出 HAP（含 libentry.so 与 modules.abc），见 CLOUD-BUILD.md |
| 真机运行 | ❌ 未验证 | 需要签名证书 |
| 原生桥（桩） | ✅ 可构建 | 无 qemu 库时编桩，App 正常安装、按钮给出明确提示 |
| 原生桥（qemu 真实现） | ⚠️ 待接线 | 入口符号需对着 qemu 分支确认一次，见 LOCAL-ENGINE.md |

编译步骤见 `docs/BUILD.md`。
