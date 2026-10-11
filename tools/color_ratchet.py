#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""色值棘轮（doclint 守护十 · 2026-10-11 手感批）：拦「新增硬编码 Color(0x」。

--check ＝ 按 git 跟踪的 lib/**.dart 逐文件数代码行 `Color(0x` 出现数，
           对基线 tools/color_ratchet_baseline.json：超数或新文件冒出＝红灯 exit 1。
--write  ＝ 把当前计数钉成新基线（真需新增色值＝人审后跑它，并在收口行写一句理由）。
口径＝行内先剥 `//` 后段（注释不计）；`/* */` 段不专门剥——check 与 write 同函数，
自证一致（基线由本脚本生成，任何解析盲区两侧同享，不产生假红）。只拦新增不溯存量。
"""
import json
import os
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
BASE = os.path.join("tools", "color_ratchet_baseline.json")
NEEDLE = "Color(0x"


def counts():
    files = subprocess.run(
        ["git", "-c", "core.quotepath=off", "ls-files", "lib"],
        capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
    c = {}
    for p in files:
        if not p.endswith(".dart"):
            continue
        n = 0
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                for line in f:
                    n += line.split("//", 1)[0].count(NEEDLE)
        except OSError:
            continue
        if n:
            c[p] = n
    return c


cur = counts()
if "--write" in sys.argv:
    with open(BASE, "w", encoding="utf-8") as f:
        json.dump(cur, f, ensure_ascii=False, indent=1, sort_keys=True)
    print("color_ratchet WRITE 基线文件数=%d 出现总数=%d" % (len(cur), sum(cur.values())))
    sys.exit(0)

if not os.path.exists(BASE):
    print("color_ratchet 红灯：基线缺失（先跑 --write 生成并人审）")
    sys.exit(1)
base = json.load(open(BASE, encoding="utf-8"))
red = []
for p in sorted(cur):
    b = base.get(p, 0)
    if cur[p] > b:
        red.append("%s: Color(0x 出现 %d 处 > 基线 %d（确需新增色值＝人审后跑 --write 钉基线并写理由）"
                   % (p, cur[p], b))
if red:
    print("color_ratchet 红灯 %d 处:" % len(red))
    for x in red:
        print("  " + x)
    sys.exit(1)
print("color_ratchet OK 文件数=%d 出现总数=%d（=基线）" % (len(cur), sum(cur.values())))
