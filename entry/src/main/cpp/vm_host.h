// 虚拟机后端抽象：桩实现与 qemu 实现共用同一套签名。
#ifndef DSHGO_VM_HOST_H
#define DSHGO_VM_HOST_H

#include <string>

namespace dshvm {

// 后端是否可用（qemu 库能否加载）
bool backend_available();

// 后端标识：stub / qemu-tci / qemu-jit
std::string backend_kind();

// 启动虚拟机；成功返回空串，失败返回错误说明
std::string backend_start(const std::string &kernelPath,
                          const std::string &rootfsPath,
                          int hostPort);

// 停止虚拟机
std::string backend_stop();

// 当前状态：idle / starting / running / stopping / error:...
std::string backend_status();

}  // namespace dshvm

#endif  // DSHGO_VM_HOST_H
