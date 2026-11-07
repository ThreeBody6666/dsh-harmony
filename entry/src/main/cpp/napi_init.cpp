// NAPI 绑定：把 vm_host 的四个能力暴露给 ArkTS。
#include <napi/native_api.h>
#include <hilog/log.h>

#include <string>

#include "vm_host.h"

namespace {

constexpr const char *kTag = "DSHGoVM";

std::string ValueToString(napi_env env, napi_value value) {
  size_t len = 0;
  napi_get_value_string_utf8(env, value, nullptr, 0, &len);
  std::string out(len, '\0');
  napi_get_value_string_utf8(env, value, out.data(), len + 1, &len);
  return out;
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
  OH_LOG_Info(LOG_APP, "%{public}s vmStart -> %{public}s", kTag,
              error.empty() ? "ok" : error.c_str());
  return MakeString(env, error);
}

napi_value VmStop(napi_env env, napi_callback_info info) {
  std::string error = dshvm::backend_stop();
  OH_LOG_Info(LOG_APP, "%{public}s vmStop -> %{public}s", kTag,
              error.empty() ? "ok" : error.c_str());
  return MakeString(env, error);
}

napi_value VmStatus(napi_env env, napi_callback_info info) {
  return MakeString(env, dshvm::backend_status());
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"nativeVersion", nullptr, NativeVersion, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"vmStart", nullptr, VmStart, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"vmStop", nullptr, VmStop, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"vmStatus", nullptr, VmStatus, nullptr, nullptr, nullptr, napi_default,
       nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = {0},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterDsGoVmModule(void) {
  napi_module_register(&g_module);
}
