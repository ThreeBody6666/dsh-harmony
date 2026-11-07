// NAPI 绑定：把 vm_host 的四个能力暴露给 ArkTS。
#include <napi/native_api.h>
#include <hilog/log.h>

#include <string>
#include <vector>

#include "vm_host.h"
#include "dshhost.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "DSHGoVM"

namespace {

// 取字符串参数：napi_get_value_string_utf8 需要可写的 char 缓冲，
// 不能直接传 std::string::data()（C++11/14 下返回 const char*）。
std::string ValueToString(napi_env env, napi_value value) {
  size_t len = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok || len == 0) {
    return std::string();
  }
  std::vector<char> buffer(len + 1, '\0');
  size_t written = 0;
  if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &written) != napi_ok) {
    return std::string();
  }
  return std::string(buffer.data(), written);
}

napi_value MakeString(napi_env env, const std::string &text) {
  napi_value result = nullptr;
  napi_create_string_utf8(env, text.c_str(), text.size(), &result);
  return result;
}

napi_value NativeVersion(napi_env env, napi_callback_info info) {
  return MakeString(env, "dsh-go-vm-bridge/0.1 (" + dshvm::backend_kind() + ")");
}

napi_value VmStart(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

  std::string kernel;
  std::string rootfs;
  int32_t port = 3080;
  if (argc >= 1 && argv[0] != nullptr) {
    kernel = ValueToString(env, argv[0]);
  }
  if (argc >= 2 && argv[1] != nullptr) {
    rootfs = ValueToString(env, argv[1]);
  }
  if (argc >= 3 && argv[2] != nullptr) {
    napi_get_value_int32(env, argv[2], &port);
  }

  std::string error = dshvm::backend_start(kernel, rootfs, port);
  OH_LOG_INFO(LOG_APP, "vmStart -> %{public}s", error.empty() ? "ok" : error.c_str());
  return MakeString(env, error);
}

napi_value VmStop(napi_env env, napi_callback_info info) {
  std::string error = dshvm::backend_stop();
  OH_LOG_INFO(LOG_APP, "vmStop -> %{public}s", error.empty() ? "ok" : error.c_str());
  return MakeString(env, error);
}

napi_value VmStatus(napi_env env, napi_callback_info info) {
  return MakeString(env, dshvm::backend_status());
}

// ---- 本机引擎（进程内 node） ----
napi_value HostKind(napi_env env, napi_callback_info info) {
  return MakeString(env, dshgo::host_kind());
}

napi_value HostStart(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  std::string coreDir;
  std::string dataDir;
  int32_t port = 3080;
  if (argc >= 1 && argv[0] != nullptr) {
    coreDir = ValueToString(env, argv[0]);
  }
  if (argc >= 2 && argv[1] != nullptr) {
    dataDir = ValueToString(env, argv[1]);
  }
  if (argc >= 3 && argv[2] != nullptr) {
    napi_get_value_int32(env, argv[2], &port);
  }
  std::string error = dshgo::host_start(coreDir, dataDir, port);
  OH_LOG_INFO(LOG_APP, "hostStart -> %{public}s", error.empty() ? "ok" : error.c_str());
  return MakeString(env, error);
}

napi_value HostStop(napi_env env, napi_callback_info info) {
  return MakeString(env, dshgo::host_stop());
}

napi_value HostStatus(napi_env env, napi_callback_info info) {
  return MakeString(env, dshgo::host_status());
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"nativeVersion", nullptr, NativeVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"vmStart", nullptr, VmStart, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"vmStop", nullptr, VmStop, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"vmStatus", nullptr, VmStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"hostKind", nullptr, HostKind, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"hostStart", nullptr, HostStart, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"hostStop", nullptr, HostStop, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"hostStatus", nullptr, HostStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

// C++ 里用定位初始化，避免依赖 C++20 的指定初始化器
napi_module g_module = {
    1,        // nm_version
    0,        // nm_flags
    nullptr,  // nm_filename
    Init,     // nm_register_func
    "entry",  // nm_modname
    nullptr,  // nm_priv
    {0},      // reserved
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterDsGoVmModule(void) {
  napi_module_register(&g_module);
}
