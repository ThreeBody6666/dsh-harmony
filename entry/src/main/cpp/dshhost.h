// 本机引擎宿主接口（供 NAPI 绑定调用）。
#ifndef DSHGO_DSHHOST_H
#define DSHGO_DSHHOST_H

#include <string>

namespace dshgo {

// libnode / stub
std::string host_kind();

// 在进程内加载核心树并起 dsh web；成功返回空串
std::string host_start(const std::string &coreDir, const std::string &dataDir, int port);

std::string host_stop();

std::string host_status();

}  // namespace dshgo

#endif  // DSHGO_DSHHOST_H
