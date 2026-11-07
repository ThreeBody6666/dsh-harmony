# qemu 动态库（不随仓库分发）

把 `libqemu-system-aarch64-tci.so`（手机，无 JIT）或
`libqemu-system-aarch64.so`（有 JIT 的设备）放到这个目录。

CMakeLists.txt 检测到 `*.so` 就会编译 `qemu_backend/qemu_backend.cpp`
（真实现），否则编译 `vm_host_stub.cpp`（桩），保证工程始终可构建。

拉取：`./scripts/fetch-vm-assets.sh --qemu`
