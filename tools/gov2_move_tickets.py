# -*- coding: utf-8 -*-
"""治理二轮 T4：工单生命周期流转。
活工单 git mv 入 docs/handoff/，闭环工单入 docs/archive/；
随后在「现行文档集」内把旧路径 docs/<base> 改写为新路径。
不触碰：并行会话文件（影音游计划/预研 legado/index-health）与全部未跟踪文件、archive 内部原文。"""
import subprocess, os, sys, shutil

ROOT = r"D:/dev_workplace/flutter_te/lifeHarness"
os.chdir(ROOT)

ALIVE = [
    "交棒话术-20261002-下一版实现批-F01-批C-R32精修.md",
    "真机逐屏验收清单-20260929.md",
    "真机逐屏验收清单-20261002-xray词库与精化.md",
    "交棒话术-20260929-R15-1整批撤销.md",
]

out = subprocess.run(["git", "-c", "core.quotepath=off", "ls-files", "docs"],
                     capture_output=True, text=True, encoding="utf-8").stdout
tracked = [l for l in out.splitlines() if l.strip()]
TICKET_PFX = ("docs/交棒话术-", "docs/真机逐屏验收清单-", "docs/拍板记录-")
tickets = [p for p in tracked if p.startswith(TICKET_PFX)]
assert len(tickets) == 26, f"工单数异常: {len(tickets)}"
os.makedirs("docs/handoff", exist_ok=True)

mapping = {}
for p in tickets:
    base = os.path.basename(p)
    dst = f"docs/handoff/{base}" if base in ALIVE else f"docs/archive/{base}"
    subprocess.run(["git", "mv", p, dst], check=True, stdout=subprocess.DEVNULL)
    mapping["docs/" + base] = dst
assert len(mapping) == 26 and sum(1 for v in mapping.values() if "/handoff/" in v) == 4

# 现行文档集：跟踪 md，排除 archive/、superpowers/、预研/、并行文件
out2 = subprocess.run(["git", "-c", "core.quotepath=off", "ls-files", "docs", "AGENTS.md"],
                      capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
skip = ("docs/archive/", "docs/superpowers/", "docs/预研/", "docs/影音游模块开发计划-20260922.md")
targets = [p for p in out2 if p.endswith(".md") and not p.startswith(skip)]

changed = 0
for p in targets:
    if not os.path.isfile(p):
        continue
    with open(p, encoding="utf-8", newline="") as f:
        s = f.read()
    s2 = s
    for old, new in mapping.items():
        s2 = s2.replace(old, new)
    if s2 != s:
        with open(p, "w", encoding="utf-8", newline="") as f:
            f.write(s2)
        changed += 1

# 校验：现行文档集不得再有「docs/<旧base>」形态的旧路径
# （旧键含 docs/ 前缀；新路径 docs/handoff/<base> 中 base 前是 handoff/ 而非 docs/，不会误报）
bad = []
for p in targets:
    if not os.path.isfile(p):
        continue
    s = open(p, encoding="utf-8", errors="replace").read()
    for old in mapping:
        if old in s:
            bad.append((p, old))
print("改写文件数:", changed)
if bad:
    print("残留旧路径:", bad[:10])
    sys.exit(1)
print("PASS", len(mapping), "份工单已流转")
