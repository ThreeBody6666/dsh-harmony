#!/usr/bin/env bash
# 为本机引擎准备运行时物料（在 CI 里跑，不要在手机上跑——GitHub 会限速）。
#
# 产出：
#   entry/libs/arm64-v8a/libnode.so.*           Node 运行时（共享库形式）
#   entry/src/main/resources/resfile/core.zip   dsh 核心树（node_modules 裁枝后打包）
#
# 用法：
#   ./scripts/prepare-local-runtime.sh            # 全量
#   ./scripts/prepare-local-runtime.sh --node     # 只取 libnode
#   ./scripts/prepare-local-runtime.sh --core     # 只打核心树
#
# 说明：libnode 默认从 DSHM（MIT）的已签 HAP 里取，属于「先跑通链路」的做法；
# 想完全独立可以改用 hqzing/ohos-node 的 build.sh 自行编译，替换本函数即可。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS_DIR="$ROOT/entry/libs/arm64-v8a"
RESFILE_DIR="$ROOT/entry/src/main/resources/resfile"
WORK="$(mktemp -d)"

# 与 dsh 版本对齐：核心树用哪个版本，就钉这个版本
DSH_VERSION="${DSH_VERSION:-0.2.2-rc.1}"
# 取 libnode 的来源（DSHM v1.1.0 的已签 HAP，MIT）
DSHM_HAP_URL="${DSHM_HAP_URL:-https://github.com/sol5766/dshm/releases/download/v1.1.0/DSHM-1.1.0-core0.2.1-alpha.1%2Bdshm.6-arm64-signed.hap}"

want_node=1
want_core=1
if [ "$#" -gt 0 ]; then
  want_node=0; want_core=0
  for arg in "$@"; do
    case "$arg" in
      --node) want_node=1 ;;
      --core) want_core=1 ;;
      *) echo "未知参数：$arg" >&2; exit 1 ;;
    esac
  done
fi

mkdir -p "$LIBS_DIR" "$RESFILE_DIR"

# ---------------------------------------------------------------- libnode
prepare_node() {
  if ls "$LIBS_DIR"/libnode.so* >/dev/null 2>&1; then
    echo "== libnode 已存在，跳过"
    return 0
  fi
  echo "== 下载 DSHM HAP 取 libnode（约 300MB，CI 内网速度快）"
  python3 - "$DSHM_HAP_URL" "$WORK/dshm.hap" <<'PY'
import sys, urllib.request
url, out = sys.argv[1], sys.argv[2]
req = urllib.request.Request(url, headers={'User-Agent': 'dsh-harmony-ci'})
with urllib.request.urlopen(req, timeout=600) as r, open(out, 'wb') as f:
    while True:
        chunk = r.read(1 << 20)
        if not chunk:
            break
        f.write(chunk)
print('downloaded')
PY
  echo "== 解出 libs/arm64-v8a/libnode.so*"
  python3 - "$WORK/dshm.hap" "$LIBS_DIR" <<'PY'
import sys, zipfile, os, io
hap, outdir = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(hap)
picked = [n for n in z.namelist() if 'libs/arm64-v8a/libnode.so' in n]
if not picked:
    raise SystemExit('HAP 里没有 libnode：' + ', '.join(n for n in z.namelist() if 'libnode' in n) or '无')
for name in picked:
    data = z.read(name)
    dest = os.path.join(outdir, os.path.basename(name))
    open(dest, 'wb').write(data)
    print('  ', dest, len(data), 'bytes')
PY
  ls -lh "$LIBS_DIR"
}

# ---------------------------------------------------------------- core tree
prepare_core() {
  if [ -f "$RESFILE_DIR/core.zip" ]; then
    echo "== core.zip 已存在，跳过"
    return 0
  fi
  echo "== 安装 dsh 核心树 @$DSH_VERSION"
  mkdir -p "$WORK/core"
  cd "$WORK/core"
  npm init -y >/dev/null 2>&1
  npm install --omit=dev --no-audit --no-fund "@deepseek-ai/dsh@$DSH_VERSION"
  # 裁枝：类型声明、sourcemap、文档、测试目录都不进包
  find node_modules -name '*.d.ts' -delete
  find node_modules -name '*.map' -delete
  find node_modules -name '*.md' -delete
  find node_modules -type d \( -name test -o -name tests -o -name '__tests__' \) -prune -exec rm -rf {} + 2>/dev/null || true
  echo "== 打包 core.zip"
  python3 - "$WORK/core" "$RESFILE_DIR/core.zip" <<'PY'
import sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
count = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for base, dirs, files in os.walk(src):
        for name in files:
            full = os.path.join(base, name)
            rel = os.path.relpath(full, src)
            z.write(full, rel)
            count += 1
print('files:', count)
PY
  ls -lh "$RESFILE_DIR"
}

[ "$want_node" = 1 ] && prepare_node
[ "$want_core" = 1 ] && prepare_core

echo "== 完成"
du -sh "$LIBS_DIR" "$RESFILE_DIR" 2>/dev/null || true
