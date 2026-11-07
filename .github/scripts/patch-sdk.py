#!/usr/bin/env python3
"""把 build-profile.json5 的 SDK 版本改成 CI 镜像对应的版本。

为什么需要：工程默认按 API 12 写（给真机用），而云端编译镜像带的是更新的
SDK（当前 api26r 对应 26.0.0）。hvigor 要求 compileSdkVersion 与镜像里的
SDK 匹配，否则直接报错。

只改两行值，不重排文件；--check 只检查不落盘。

用法:
  python3 patch-sdk.py build-profile.json5                 # 改成 26.0.0
  python3 patch-sdk.py build-profile.json5 --compile 24 --compatible 24
  python3 patch-sdk.py build-profile.json5 --check
"""

import re
import sys


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    path = argv[1]
    compile_ver = "26.0.0"
    compatible_ver = None
    check_only = "--check" in argv
    if "--compile" in argv:
        compile_ver = argv[argv.index("--compile") + 1]
    if "--compatible" in argv:
        compatible_ver = argv[argv.index("--compatible") + 1]
    if compatible_ver is None:
        compatible_ver = compile_ver

    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()

    def replace_value(source, key, value):
        pattern = re.compile(r'("%s"\s*:\s*)("[^"]*"|[0-9]+)' % re.escape(key))
        if not pattern.search(source):
            return source, False
        return pattern.sub(lambda m: m.group(1) + '"%s"' % value, source, count=1), True

    text, did_compile = replace_value(text, "compileSdkVersion", compile_ver)
    text, did_compatible = replace_value(text, "compatibleSdkVersion", compatible_ver)

    print("compileSdkVersion    -> %s %s" % (compile_ver, "ok" if did_compile else "(未找到)"))
    print("compatibleSdkVersion -> %s %s" % (compatible_ver, "ok" if did_compatible else "(未找到)"))

    if check_only:
        print("--check：不写文件")
        return 0

    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("已更新 %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
