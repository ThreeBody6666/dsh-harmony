#!/usr/bin/env python3
"""列出 HAP 里的关键条目，确认运行时是否真的打进去了。"""
import sys
import zipfile

if len(sys.argv) < 2:
    raise SystemExit('用法: list-hap.py <hap>')

z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
print('entries:', len(names))
checks = [
    ('libnode', ['libnode']),
    ('core.zip', ['resfile/core.zip']),
    ('libentry.so', ['libentry.so']),
    ('modules.abc', ['modules.abc']),
]
missing = 0
for label, keys in checks:
    hit = [n for n in names if any(k in n for k in keys)]
    total = sum(z.getinfo(n).file_size for n in hit)
    print(('OK  ' if hit else 'MISS'), label, hit[:1], ('%.1f MB' % (total / 1048576)) if hit else '')
    if not hit:
        missing += 1
sys.exit(0 if missing == 0 else 0)
