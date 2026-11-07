# 路线图与取舍

## 一、本机引擎：鸿蒙上最难的一块

Android 版靠 proot 在 App 私有目录里跑一个 Ubuntu + Node，从而「手机本机运行」。
HarmonyOS NEXT 上这条路基本封死：

- 没有 AOSP 兼容层，APK 装不上，`/system/bin/linker` 那套全不存在
- 应用沙箱不允许执行任意 ELF（`fork/exec` 只能拉起 HAP 内的原生库），proot 依赖的
  `ptrace + execve` 组合不可用
- 没有 `bash`、没有 `/bin/sh` 之外的工具链；DSH 的 bash 工具、文件工具都会残废

可选的替代方案（按可行性排序）：

| 方案 | 做法 | 代价 | 结论 |
|---|---|---|---|
| A. 远程引擎（已实现） | 手机只做客户端，引擎跑在电脑/NAS/服务器 | 依赖网络 | ✅ 首选 |
| B. 应用内 Linux 虚拟机 | qemu-system 编成 `.so`，VM 里跑 Node + bash（**HiSH 已证明手机可行**） | 包体 150–250MB、无 JIT 时慢、耗电 | ✅ **本机模式正解**，见 [LOCAL-ENGINE.md](LOCAL-ENGINE.md) |
| C. 直接嵌 Node（不跑 VM） | OpenHarmony 有 node 构建，作为原生库加载 | 没有 bash/进程，工具大面积残废 | ⚠️ 只能做纯对话 MVP |
| D. 云端引擎 | 共享一台云机跑 dsh web，手机直连 | 成本、账号隔离 | ⚠️ 适合进阶用户 |

路线：A 已经能用；接下来按 LOCAL-ENGINE.md 的 P0→P3 做 B。

## 二、功能对齐清单

对照 Android 版 `app/lib/ui/*`，按投入产出排优先级：

**P0（本工程已实现）**
- 登录 / cookie 持久化
- 会话列表、新建会话
- 聊天流：消息、思考、工具卡片、中断
- 发送 / 中断、断线重连

**P1（下一步，工作量小、体验缺口大）**
- [ ] 历史向上翻页（`session/page` 已封装，缺 UI 触发）
- [ ] 审批卡片（`approval/asked` + `approval/decided`，走 `$events/result` 回填）
- [ ] 提问卡片（`userQuestions`）
- [ ] 模型选择（`session/modelCatalog` / `session/selectModel`）
- [ ] 会话重命名 / 归档 / 搜索（`session/rename`、`workspace/archiveSession`、`session/search`）
- [ ] Markdown 渲染（标题、列表、行内代码、代码块 + 复製）
- [ ] 图片附件（`fileUploads/upload` 走 `/api/session/uploadFileBinary`）

**P2（中等）**
- [ ] 待办 / 计划面板（`todo/write`、`plan` projections 里已有数据）
- [ ] token 用量与上下文压力（`projections.values.tokenUsage` / `contextPressure`）
- [ ] 多工作区切换（`workspace/follow`、`workspace/list`）
- [ ] 语音输入（`speech/*` + 鸿蒙语音识别）
- [ ] 后台保活：长回复时切后台不中断（`ohos.permission.KEEP_BACKGROUND_RUNNING` + 长时任务）

**P3（大工程）**
- [ ] dsh-remote 隧道（`packages/dsh_remote`：Noise IK + WebRTC/relay），做到免公网、免端口映射
- [ ] 插件体系：Android 版是「原生插件协议 v1」，鸿蒙侧要另立一套（ArkUI 组件座位）
- [ ] 宠物 / 社区 / 分享链接等外围玩法

## 三、插件体系怎么落

Android 版的原生插件是「Dart 侧发现 + Kotlin 侧渲染」，鸿蒙没有这个耦合关系。
两个思路：

1. **快速方案**：把 dsh web 的官方 UI 放进 ArkUI 的 `Web` 组件，插件生态原样复用，
   代价是外壳变成网页（本工程当前的原生聊天页可以在「原生模式 / 网页模式」间切换）。
2. **原生方案**：定义鸿蒙侧的插件清单（`plugin.json`），宿主用 ArkUI 动态构建组件树，
   插件作者写 ArkTS。要重写一遍座位系统、流式协议与权限模型。

建议：先 1 保生态，再逐步把高频座位（首页胶囊、工具卡、面板）native 化。

## 四、已知技术债

- cookie 存在 `preferences` 明文里，应迁移到 `@ohos.security.asset`
- 聊天列表没有做增量刷新，长会话（>1000 条）会整表重建
- 没有做 Markdown，长回答里的代码块显示成纯文本
- 没有本地缓存，断网后进不了已读会话
