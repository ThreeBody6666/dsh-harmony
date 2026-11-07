cmake_minimum_required(VERSION 3.5.0)
project(dshgo_vm_bridge)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

# vendor/qemu/ 里放了 qemu 动态库时，编真实现；否则编桩实现。
# 这样工程在没有 qemu 库的情况下依然能构建、能跑、能给出明确提示。
set(QEMU_DIR ${NATIVERENDER_ROOT_PATH}/vendor/qemu)
file(GLOB QEMU_LIBS ${QEMU_DIR}/*.so)

if(QEMU_LIBS)
  message(STATUS "dsh-go: found qemu backend in ${QEMU_DIR}")
  include_directories(${QEMU_DIR})
  set(BACKEND_SRC ${NATIVERENDER_ROOT_PATH}/qemu_backend/qemu_backend.cpp)
  set(BACKEND_KIND "qemu")
else()
  message(STATUS "dsh-go: no qemu backend, building stub")
  set(BACKEND_SRC ${NATIVERENDER_ROOT_PATH}/vm_host_stub.cpp)
  set(BACKEND_KIND "stub")
endif()

add_library(entry SHARED
    napi_init.cpp
    ${BACKEND_SRC})

target_link_libraries(entry PUBLIC libace_napi.z.so libhilog_ndk.z.so)

if(QEMU_LIBS)
  # 真实现里用 dlopen 加载，避免把 .so 直接链进产物
  target_link_libraries(entry PUBLIC dl)
  target_compile_definitions(entry PRIVATE DSHGO_WITH_QEMU=1)
endif()
