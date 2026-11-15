cmake_minimum_required(VERSION 3.5.0)
project(dshgo_host)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
include_directories(${NATIVERENDER_ROOT_PATH} ${NATIVERENDER_ROOT_PATH}/include)

# ---------------------------------------------------------------- 本机引擎
# 需要三样东西同时在位才编「真实现」：
#   vendor/node/include/node.h         Node 头文件（CI 里下）
#   entry/libs/arm64-v8a/libnode.so*   Node 运行时（CI 里从 DSHM 取）
#   resfile/core.zip                   dsh 核心树（CI 里打包）
set(NODE_INC ${NATIVERENDER_ROOT_PATH}/vendor/node/include)
file(GLOB NODE_LIB ${NATIVERENDER_ROOT_PATH}/../../../libs/arm64-v8a/libnode.so*)

set(HOST_SOURCES napi_init.cpp dshhost.cpp)

# ---------------------------------------------------------------- VM 后端（可选）
set(QEMU_DIR ${NATIVERENDER_ROOT_PATH}/vendor/qemu)
file(GLOB QEMU_LIBS ${QEMU_DIR}/*.so)
if(QEMU_LIBS)
  message(STATUS "dsh-go: qemu backend found")
  include_directories(${QEMU_DIR})
  list(APPEND HOST_SOURCES qemu_backend/qemu_backend.cpp)
else()
  message(STATUS "dsh-go: qemu backend absent, using stub")
  list(APPEND HOST_SOURCES vm_host_stub.cpp)
endif()

add_library(entry SHARED ${HOST_SOURCES})
target_link_libraries(entry PUBLIC libace_napi.z.so libhilog_ndk.z.so)

if(QEMU_LIBS)
  target_link_libraries(entry PUBLIC dl)
endif()

# ---------------------------------------------------------------- 进程内 node
# 不再链接 libnode、也不需要 node.h：
# 运行时在本 .so 同目录 dlopen libnode.so.137/127 并 dlsym node::Start。
# 这样构建期不依赖 Node 头文件（Node 26 的 v8.h 需要 C++20 <source_location>，
# OHOS libc++ 没有），也不会因为「头文件没配好」悄悄降级成桩实现。
target_link_libraries(entry PUBLIC dl)
