# 云端编译（GitHub Actions + 鸿蒙命令行工具链）

本机没有 HarmonyOS SDK 也能编译：把工程推到 GitHub，Actions 会在
[harmonyos-ci](https://github.com/DaLongZhuaZi/harmonyos-ci) 的 Docker 镜像里
跑 `hvigorw assembleHap`，产出未签名 HAP 和完整日志。

---

## 一、一次性准备（约 3 分钟）

```bash
cd dsh-harmony
git init -b main
git add .
git commit -m "dsh-go harmony: 首个可编译版本"
git remote add origin https://github.com/<你的账号>/dsh-harmony.git
git push -u origin main
```

> 仓库要**公开**才能白嫖无限 Actions 分钟数；私有仓库每月 2000 分钟也够用。
> 推送时用个人访问令牌（PAT）当密码：`https://<user>:<token>@github.com/...`

第一次 push 后，Actions 会自动跑起来（`.github/workflows/build-hap.yml`）。

## 二、看结果

- 仓库页 → **Actions** → `云端编译 HAP` → 最近一次运行
- 绿了：**Artifacts** 里下载 `hap-unsigned`
- 红了：**Artifacts** 里还有 `build-log`（首轮 + 重试两轮日志），点进去就能看到真实报错

把报错贴给我，我照着改——这就是我们要的东西：**真实的 ArkTS/CMake 编译反馈**。

## 三、流水线做了什么

| 步骤 | 说明 |
|---|---|
| 安装依赖 | `ohpm install --all`（工程没有三方依赖，主要装工具链） |
| 剥离签名 | `.github/scripts/strip_signing.py` 去掉本机 `signingConfigs`，否则容器里找不到证书直接失败 |
| 首次构建 | 按仓库里的 SDK 版本（API 12）先试一次 |
| 失败重试 | 自动改写 `compileSdkVersion/compatibleSdkVersion` 为镜像对应版本（默认 `26.0.0`）再编一次 |
| 产物校验 | 确认 `*.hap` 存在且非空，否则直接标红 |
| 上传 | artifact `hap-unsigned`，保留 14 天 |

之所以「先按 12 试、失败再改写」，是因为镜像自带的是新 SDK，而工程默认是给
真机（API 12）写的；两种都试一遍，日志里能看清到底卡在哪。

## 四、常见失败与对策

| 报错关键词 | 原因 | 对策 |
|---|---|---|
| `compatibleSdkVersion is not supported` | 镜像 SDK 比工程写的旧 | 用 `workflow_dispatch` 手动跑，把 `sdk` 输入设成镜像对应版本 |
| `Cannot find module '@kit.NetworkKit'` | SDK 太老（< API 12） | 换 `api23`/`api24` 镜像 tag |
| `CMake Error` / 找不到 `libace_napi.z.so` | 镜像里没带 NDK | 告诉我，我改成「先不编原生桥」的降级版（本机模式暂时不可用，其余照编） |
| `ohpm install` 超时 | 镜像内 registry 慢 | 在 workflow 里加 `ohpm config set registry https://ohpm.openharmony.cn/ohpm/` |
| `Out of memory` | hvigor 内存不够 | 加 `NODE_OPTIONS=--max-old-space-size=4096` |

## 五、产物装不上手机？

`hap-unsigned` 是**未签名**包，真机装不了。要装得签名：

1. 电脑上用 DevEco Studio 打开工程 → `Project Structure → Signing Configs` → 自动签名
2. 或命令行：`java -jar hap-sign-tool.jar sign-app ...`（需要 p12 + cer + p7b）

CI 只负责证明「代码能编译」，签名这一步绕不开华为账号。

## 六、切换镜像

镜像 tag 与 SDK 对应关系（来自 harmonyos-ci 仓库）：

| tag | command-line-tools | 适用 SDK |
|---|---|---|
| `api26r` | 26.0.0.821 | HarmonyOS 26 正式版（默认） |
| `api26b2` | 26.0.0.621 | API 26 Beta2 |
| `api24` | 6.1.1.300 | API 24 |
| `api23` | 6.1.0.818 | API 23 |

改 `.github/workflows/build-hap.yml` 里的 `env.CI_IMAGE`，或手动触发时传 `image` 输入。
