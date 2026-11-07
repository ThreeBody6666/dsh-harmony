#!/usr/bin/env bash
# 拉取本机引擎需要的三样外部物料（默认取 HiSH 发布的预编译产物，MIT）。
#
# 用法：
#   ./scripts/fetch-vm-assets.sh            # 内核 + rootfs + qemu 动态库
#   ./scripts/fetch-vm-assets.sh --kernel   # 只拉内核
#   ./scripts/fetch-vm-assets.sh --rootfs   # 只拉 rootfs
#   ./scripts/fetch-vm-assets.sh --qemu     # 只拉 qemu 动态库
#
# 产物位置：
#   entry/src/main/resources/rawfile/vm/   内核与 rootfs（会打进 HAP）
#   entry/src/main/cpp/vendor/qemu/        qemu 动态库（只参与编译，不进 HAP 资源）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$ROOT/entry/src/main/resources/rawfile/vm"
QEMU_DIR="$ROOT/entry/src/main/cpp/vendor/qemu"
BASE_LINUX_CONFIG="https://github.com/harmoninux/linux-config/releases/download"
BASE_QEMU="https://github.com/harmoninux/qemu/releases/download/hish-20260110"

KERNEL_URL="$BASE_LINUX_CONFIG/kernel-20260228/kernel_aarch64"
ROOTFS_URL="$BASE_LINUX_CONFIG/rootfs-20260117/rootfs_aarch64.qcow2"
QEMU_URL="$BASE_QEMU/libs.zip"

mkdir -p "$VM_DIR" "$QEMU_DIR"

download() {
  local url="$1" out="$2"
  if [ -f "$out" ]; then
    echo "  已有，跳过：$(basename "$out")"
    return 0
  fi
  echo "  下载 $(basename "$out") …"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$out.part" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 -O "$out.part" "$url"
  else
    echo "需要 curl 或 wget" >&2
    exit 1
  fi
  mv "$out.part" "$out"
}

want_all=1
want_kernel=1; want_rootfs=1; want_qemu=1
if [ "$#" -gt 0 ]; then
  want_all=0; want_kernel=0; want_rootfs=0; want_qemu=0
  for arg in "$@"; do
    case "$arg" in
      --kernel) want_kernel=1 ;;
      --rootfs) want_rootfs=1 ;;
      --qemu)   want_qemu=1 ;;
      *) echo "未知参数：$arg" >&2; exit 1 ;;
    esac
  done
fi

echo "== 内核/镜像 → $VM_DIR"
[ "$want_kernel" = 1 ] && download "$KERNEL_URL" "$VM_DIR/kernel_aarch64"
[ "$want_rootfs" = 1 ] && download "$ROOTFS_URL" "$VM_DIR/rootfs_aarch64.qcow2"

echo "== qemu 动态库 → $QEMU_DIR"
if [ "$want_qemu" = 1 ]; then
  if [ ! -f "$QEMU_DIR/libs.zip" ]; then
    download "$QEMU_URL" "$QEMU_DIR/libs.zip"
  fi
  if [ -f "$QEMU_DIR/libs.zip" ]; then
    echo "  解压 libs.zip（需要 unzip）"
    (cd "$QEMU_DIR" && unzip -oq libs.zip && rm -f libs.zip)
  fi
fi

echo
echo "完成。检查一下："
ls -lh "$VM_DIR" 2>/dev/null || true
ls -lh "$QEMU_DIR" 2>/dev/null || true
cat <<'TIP'

下一步：
  1. 重新用 DevEco 构建（CMake 检测到 vendor/qemu/*.so 会自动编真实现，
     否则编桩实现，App 仍可安装，只是「本机模式」会提示后端未接入）
  2. 真机上装好后进 App，点「在手机本机启动引擎」
  3. 若报 error:no-entry，说明 qemu 分支的入口符号名不同，
     改 entry/src/main/cpp/qemu_backend/qemu_backend.cpp 的 kEntryCandidates
TIP
