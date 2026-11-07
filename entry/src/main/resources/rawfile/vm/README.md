# 本机引擎资源（不随仓库分发）

这里需要放两个大文件，构建时会被打进 HAP：

| 文件 | 说明 |
|---|---|
| `kernel_aarch64` | Linux arm64 内核（来自 harmoninux/linux-config） |
| `rootfs_aarch64.qcow2` | 根文件系统，需预装 Node 24 + @deepseek-ai/dsh |

拉取方式：

```bash
./scripts/fetch-vm-assets.sh
```

两个文件都不在时，App 仍可正常构建与安装，「本机模式」会明确提示缺资源。
详见 `docs/LOCAL-ENGINE.md`。
