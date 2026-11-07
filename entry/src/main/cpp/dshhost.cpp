// 本机引擎宿主：把 libnode 当共享库加载，起 dsh web 在 127.0.0.1。
//
// 与 DSHM（MIT）同构：Node 不是被 exec 起来的，而是 dlopen 链接进本进程，
// 这样避开了「沙箱禁止 fork/exec」的限制。
#include <dlfcn.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "dshhost.h"

#if defined(DSHGO_WITH_NODE)
#include <node.h>
#include <v8.h>
#endif

namespace dshgo {

namespace {
std::string g_status = "idle";
}

std::string host_kind() {
#if defined(DSHGO_WITH_NODE)
  return "libnode";
#else
  return "stub";
#endif
}

std::string host_start(const std::string &coreDir, const std::string &dataDir, int port) {
#if defined(DSHGO_WITH_NODE)
  if (coreDir.empty()) {
    g_status = "error:no-core";
    return "核心树目录为空";
  }
  const std::string entry = coreDir + "/node_modules/@deepseek-ai/dsh/lib/bin.js";
  if (access(entry.c_str(), R_OK) != 0) {
    g_status = "error:no-entry";
    return "找不到核心入口：" + entry;
  }

  // 进程内起 node：等价于 node <entry> web --host 127.0.0.1 --port <port> --no-open
  static std::vector<std::string> store;
  store.clear();
  store.push_back("dsh");
  store.push_back(entry);
  store.push_back("web");
  store.push_back("--host");
  store.push_back("127.0.0.1");
  store.push_back("--port");
  store.push_back(std::to_string(port));
  store.push_back("--no-open");

  setenv("DSH_HOME", dataDir.c_str(), 1);
  setenv("HOME", dataDir.c_str(), 1);
  setenv("NODE_PATH", (coreDir + "/node_modules").c_str(), 1);

  std::vector<char *> argv;
  for (std::string &item : store) {
    argv.push_back(const_cast<char *>(item.c_str()));
  }
  argv.push_back(nullptr);

  g_status = "running";
  int rc = node::Start(static_cast<int>(argv.size()) - 1, argv.data());
  g_status = "stopped";
  return rc == 0 ? "" : ("node 退出码 " + std::to_string(rc));
#else
  (void) coreDir;
  (void) dataDir;
  (void) port;
  g_status = "error:no-node";
  return "本机引擎后端未编入：缺少 libnode 与 node 头文件，见 docs/LOCAL-VIA-NODE.md";
#endif
}

std::string host_stop() {
  g_status = "idle";
  return "";
}

std::string host_status() {
  return g_status;
}

}  // namespace dshgo
