// 本机引擎宿主：运行时 dlopen libnode，在同一进程内起 dsh web（127.0.0.1）。
//
// 为什么是同进程 dlopen，而不是链接 libnode 或 fork/exec：
//   1. 鸿蒙禁止三方应用 fork/创建进程（childProcessManager 仅平板/PC-2in1 可用）；
//   2. 构建期链接 libnode 需要 node.h → Node 26 的 v8.h 依赖 C++20 <source_location>，
//      OHOS 的 libc++ 没有，直接编不过；
//   3. 链接还会把「没配好」变成静默降级（我们踩过：编成了 stub 却毫无提示）。
//   所以这里只做一件事：dladdr 找到自己所在目录 → dlopen libnode.so.<N> (RTLD_GLOBAL)
//   → dlsym 取 mangled 的 node::Start。不引用任何 node:: / v8:: 类型。
//
// 必须带 --jitless：本应用不申请 ALLOW_WRITABLE_CODE_MEMORY，V8 申请可写可执行内存会被拦。
#include <dlfcn.h>
#include <unistd.h>

#include <cstdio>

#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "dshhost.h"

namespace dshgo {

namespace {

constexpr int kLogDomain = 0x3200;
constexpr const char *kLogTag = "DSHGO-HOST";

// soname 随 NODE_MODULE_VERSION 走：137 = Node 26.x，127 = Node 24.x
const char *kLibnodeCandidates[] = {"libnode.so.137", "libnode.so.127"};

typedef int (*NodeStartFn)(int argc, char **argv);

std::mutex g_mutex;
std::string g_status = "idle";
void *g_libnode = nullptr;
NodeStartFn g_nodeStart = nullptr;

std::string libs_dir() {
  Dl_info info;
  if (::dladdr(reinterpret_cast<void *>(&libs_dir), &info) != 0 && info.dli_fname != nullptr) {
    std::string self(info.dli_fname);
    const size_t slash = self.find_last_of('/');
    if (slash != std::string::npos) {
      return self.substr(0, slash + 1);
    }
  }
  return std::string();
}

bool ensure_libnode() {
  std::lock_guard<std::mutex> guard(g_mutex);
  if (g_nodeStart != nullptr) {
    return true;
  }
  const std::string dir = libs_dir();
  for (const char *name : kLibnodeCandidates) {
    const std::string path = dir + name;
    void *handle = ::dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (handle == nullptr) {
      handle = ::dlopen(name, RTLD_NOW | RTLD_GLOBAL);
    }
    if (handle != nullptr) {
      g_libnode = handle;
      g_nodeStart = reinterpret_cast<NodeStartFn>(::dlsym(handle, "_ZN4node5StartEiPPc"));
      if (g_nodeStart != nullptr) {
        return true;
      }
    }
  }
  return false;
}

}  // namespace

std::string host_kind() {
  return ensure_libnode() ? "libnode" : "stub";
}

std::string host_start(const std::string &hookPath, const std::string &coreDir,
                       const std::string &dataDir, int port) {
  if (!ensure_libnode()) {
    g_status = "error:no-libnode";
    return "加载 libnode 失败：libs 目录下没有 libnode.so.137/127";
  }
  if (coreDir.empty()) {
    g_status = "error:no-core";
    return "核心树目录为空";
  }
  const std::string entry = coreDir + "/node_modules/@deepseek-ai/dsh/lib/bin.js";
  if (access(entry.c_str(), R_OK) != 0) {
    g_status = "error:no-entry";
    return "找不到核心入口：" + entry;
  }
  if (g_status == "running") {
    return "";
  }

  // 等价于：
  //   NODE_OPTIONS="--import <hook>" node --jitless <core>/bin.js web --host 127.0.0.1 --port <port> --no-open
  static std::vector<std::string> store;
  store.clear();
  store.push_back("dsh");
  store.push_back("--jitless");  // 见文件头：不申请可写可执行内存
  store.push_back(entry);
  store.push_back("web");
  store.push_back("--host");
  store.push_back("127.0.0.1");
  store.push_back("--port");
  store.push_back(std::to_string(port));
  store.push_back("--no-open");

  setenv("DSH_HOME", (dataDir + "/dshhome").c_str(), 1);
  setenv("HOME", dataDir.c_str(), 1);
  setenv("NODE_PATH", (coreDir + "/node_modules").c_str(), 1);
  setenv("TMPDIR", (dataDir + "/tmp").c_str(), 1);
  if (!hookPath.empty()) {
    setenv("NODE_OPTIONS", ("--import " + hookPath).c_str(), 1);
  }

  static std::vector<char *> argv;
  argv.clear();
  for (std::string &item : store) {
    argv.push_back(const_cast<char *>(item.c_str()));
  }
  argv.push_back(nullptr);

  g_status = "running";
  // 把 Node 的 stdout/stderr 抓进文件：应用进程的 stdout 在设备上看不见，
  // 而 node::Start 失败时原因全打在 stdout/stderr 上（DSHM 同款做法）。
  const std::string nodeLog = dataDir + "/node-output.log";
  // node::Start 会阻塞并自己跑事件循环，必须离开 NAPI 调用线程
  std::thread loop([nodeLog]() {
    if (FILE *f = ::freopen(nodeLog.c_str(), "w", stdout)) {
      ::setvbuf(f, nullptr, _IOLBF, 0);
      ::dup2(::fileno(f), 2);
    }
    const int argc = static_cast<int>(store.size());
    const int rc = g_nodeStart(argc, argv.data());
    g_status = rc == 0 ? "exited" : ("error:exit-" + std::to_string(rc));
  });
  loop.detach();
  return "";
}

std::string host_stop() {
  // 进程内 node 无法从外部安全停止（node::Start 阻塞）。如实返回，不假装成功。
  g_status = "idle";
  return "进程内 Node 不支持从外部停止：重启应用即可";
}

std::string host_status() {
  return g_status;
}

}  // namespace dshgo
