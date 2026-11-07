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
if(EXISTS ${NODE_INC}/node.h AND NODE_LIB)
  message(STATUS "dsh-go: node headers + libnode found, enabling in-process node")
  include_directories(${NODE_INC})
  list(GET NODE_LIB 0 NODE_LIB_FIRST)
  target_link_libraries(entry PUBLIC ${NODE_LIB_FIRST})
  target_compile_definitions(entry PRIVATE DSHGO_WITH_NODE=1)
else()
  message(STATUS "dsh-go: no node runtime yet, host falls back to stub")
endif()
