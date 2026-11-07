// qemu 后端：把 libqemu-system-aarch64*.so 当共享库加载进进程，跑一台 Linux VM。
//
// 这个文件只在 entry/src/main/cpp/vendor/qemu/ 里存在 .so 时才会被编译
// （见 CMakeLists.txt）。没有库时走 vm_host_stub.cpp，工程照样能构建。
//
// ⚠️ 接入前请确认你要用的 qemu 分支导出了什么入口。harmoninux/qemu 把原本的
//    main() 改成了可重入入口，名称以该仓库为准；这里用「按候选符号依次查找」
//    的方式，避免写死。

#include <dlfcn.h>
#include <pthread.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "vm_host.h"

namespace dshvm {

namespace {

// 候选入口签名：int fn(int argc, char **argv)
using QemuEntry = int (*)(int, char **);

const char *kLibCandidates[] = {
    "libqemu-system-aarch64-tci.so",
    "libqemu-system-aarch64.so",
};

// 不同分支导出名不同，按顺序尝试。
const char *kEntryCandidates[] = {
    "qemu_main",
    "qemu_main_android",
    "qemu_host_main",
};

pthread_t g_thread;
bool g_threadAlive = false;
void *g_lib = nullptr;
std::string g_status = "idle";
std::vector<std::string> g_argvStore;
std::vector<char *> g_argv;
std::string g_kernel;
std::string g_rootfs;
int g_port = 3080;

void *RunQemu(void *arg) {
  QemuEntry entry = reinterpret_cast<QemuEntry>(arg);
  std::vector<char *> argv = g_argv;
  argv.push_back(nullptr);
  entry(static_cast<int>(argv.size()) - 1, argv.data());
  g_status = "idle";
  g_threadAlive = false;
  return nullptr;
}

void *TryOpen(std::string &err) {
  for (const char *name : kLibCandidates) {
    void *handle = dlopen(name, RTLD_NOW | RTLD_GLOBAL);
    if (handle != nullptr) {
      return handle;
    }
    err = dlerror() == nullptr ? "dlopen 失败" : dlerror();
  }
  return nullptr;
}

}  // namespace

bool backend_available() {
  std::string err;
  void *handle = TryOpen(err);
  if (handle == nullptr) {
    return false;
  }
  dlclose(handle);
  return true;
}

std::string backend_kind() {
#if defined(DSHGO_QEMU_TCI)
  return "qemu-tci";
#else
  return "qemu";
#endif
}

std::string backend_start(const std::string &kernelPath,
                          const std::string &rootfsPath,
                          int hostPort) {
  if (g_threadAlive) {
    return "VM 已经在运行";
  }
  std::string err;
  g_lib = TryOpen(err);
  if (g_lib == nullptr) {
    g_status = "error:dlopen";
    return "加载 qemu 库失败：" + err;
  }

  QemuEntry entry = nullptr;
  for (const char *symbol : kEntryCandidates) {
    entry = reinterpret_cast<QemuEntry>(dlsym(g_lib, symbol));
    if (entry != nullptr) {
      break;
    }
  }
  if (entry == nullptr) {
    dlclose(g_lib);
    g_lib = nullptr;
    g_status = "error:no-entry";
    return "qemu 库里没找到入口符号（qemu_main / qemu_host_main），"
           "请按你用的分支修改 qemu_backend.cpp 的 kEntryCandidates";
  }

  g_kernel = kernelPath;
  g_rootfs = rootfsPath;
  g_port = hostPort;

  // 典型参数：机器类型、内核、根盘、串口/nographic、端口转发
  g_argvStore.clear();
  g_argvStore.push_back("qemu-system-aarch64");
  g_argvStore.push_back("-M");
  g_argvStore.push_back("virt");
  g_argvStore.push_back("-cpu");
  g_argvStore.push_back("cortex-a72");
  g_argvStore.push_back("-smp");
  g_argvStore.push_back("4");
  g_argvStore.push_back("-m");
  g_argvStore.push_back("2048");
  g_argvStore.push_back("-kernel");
  g_argvStore.push_back(kernelPath);
  g_argvStore.push_back("-drive");
  g_argvStore.push_back("file=" + rootfsPath + ",format=qcow2,if=virtio");
  g_argvStore.push_back("-append");
  g_argvStore.push_back("root=/dev/vda rw console=ttyAMA0 quiet");
  g_argvStore.push_back("-nographic");
  g_argvStore.push_back("-netdev");
  g_argvStore.push_back("user,id=net0,hostfwd=tcp::" + std::to_string(hostPort) + "-:3080");
  g_argvStore.push_back("-device");
  g_argvStore.push_back("virtio-net-pci,netdev=net0");

  g_argv.clear();
  for (std::string &item : g_argvStore) {
    g_argv.push_back(const_cast<char *>(item.c_str()));
  }

  g_status = "starting";
  if (pthread_create(&g_thread, nullptr, RunQemu, reinterpret_cast<void *>(entry)) != 0) {
    g_status = "error:pthread";
    return "创建 VM 线程失败";
  }
  g_threadAlive = true;
  g_status = "running";
  return "";
}

std::string backend_stop() {
  if (!g_threadAlive) {
    g_status = "idle";
    return "";
  }
  // 最稳的做法是让 qemu 自己退出：这里先取消线程，真实现应改为向 VM 的
  // monitor 发 quit（例如通过 unix socket），再 join。
  pthread_cancel(g_thread);
  pthread_join(g_thread, nullptr);
  g_threadAlive = false;
  if (g_lib != nullptr) {
    dlclose(g_lib);
    g_lib = nullptr;
  }
  g_status = "idle";
  return "";
}

std::string backend_status() { return g_status; }

}  // namespace dshvm
