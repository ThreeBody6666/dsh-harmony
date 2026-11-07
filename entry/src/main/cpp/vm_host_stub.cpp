// 桩实现：没有接入 qemu 时保证工程能编译、能运行、能给出明确反馈。
#include "vm_host.h"

namespace dshvm {

namespace {
std::string g_status = "idle";
}

bool backend_available() { return false; }

std::string backend_kind() { return "stub"; }

std::string backend_start(const std::string &kernelPath,
                          const std::string &rootfsPath,
                          int hostPort) {
  if (kernelPath.empty() || rootfsPath.empty()) {
    g_status = "error:empty-path";
    return "kernel 或 rootfs 路径为空";
  }
  if (hostPort <= 0 || hostPort > 65535) {
    g_status = "error:bad-port";
    return "端口非法";
  }
  g_status = "error:backend-missing";
  return "本机引擎后端未接入：请把 libqemu-system-aarch64-tci.so 放进 "
         "entry/src/main/cpp/vendor/qemu/ 后重新构建，见 cpp/README.md";
}

std::string backend_stop() {
  g_status = "idle";
  return "";
}

std::string backend_status() { return g_status; }

}  // namespace dshvm
