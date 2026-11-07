#!/usr/bin/env python3
"""为命令行工具链准备 hvigor 配置。

背景：DevEco 新建工程会带 `hvigor/hvigor-config.json5`（含 modelVersion 等），
命令行里 `hvigorw assembleHap` 找不到它会直接报
`Hvigor config file .../hvigor/hvigor-config.json5 does not exist`。

这里按传入的版本号生成配置文件，并同步根 oh-package.json5 的 modelVersion，
保证两者一致——否则 hvigor 会报版本不匹配。

用法:
  python3 ci-prepare.py 6.0.0
  python3 ci-prepare.py            # 不带参数时只打印当前值
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def make_hvigor_config(version):
    return """{
  "modelVersion": "%s",
  "dependencies": {},
  "execution": {
    // "analyze": "normal",
    // "daemon": true,
    // "incremental": true,
    // "parallel": true,
    // "typeCheck": false
  },
  "logging": {
    // "level": "info"
  },
  "debugging": {
    // "stacktrace": false
  },
  "nodeOptions": {
    // "maxOldSpaceSize": 8192
  }
}
""" % version


def patch_root_package(version):
    """把根 oh-package.json5 的 modelVersion 换成目标版本（不做 JSON5 重排）。"""
    path = os.path.join(ROOT, "oh-package.json5")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    import re

    new_text, count = re.subn(r'("modelVersion"\s*:\s*)"[^"]*"', r'\1"%s"' % version, text, count=1)
    if count == 0:
        new_text = text
    if new_text != text:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(new_text)
    return count > 0


def main(argv):
    if len(argv) < 2:
        cfg = os.path.join(ROOT, "hvigor", "hvigor-config.json5")
        print("hvigor-config 存在:", os.path.exists(cfg))
        if os.path.exists(cfg):
            print(open(cfg, encoding="utf-8").read())
        return 0

    version = argv[1]
    cfg_dir = os.path.join(ROOT, "hvigor")
    os.makedirs(cfg_dir, exist_ok=True)
    with open(os.path.join(cfg_dir, "hvigor-config.json5"), "w", encoding="utf-8") as handle:
        handle.write(make_hvigor_config(version))
    patched = patch_root_package(version)
    print("hvigor-config.json5 -> modelVersion %s" % version)
    print("oh-package.json5 modelVersion %s" % ("已同步" if patched else "(没有 modelVersion 字段)"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
