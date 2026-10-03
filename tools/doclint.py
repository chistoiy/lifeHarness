#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""doclint：现行文档集的引用路径体检（治理二轮工装）。
扫描对象 = 仓库根 AGENTS.md + git 跟踪的 docs/**.md（排除 docs/archive/、docs/superpowers/、docs/预研/）。
规则：文中出现的 docs/、prototype/、tools/ 相对路径（.md/.html/.js/.sh/.json/.dart/.py/.yaml/.xml）
必须真实存在；含通配符或行内有「已删除/找回/git log」豁免词的行跳过。任何红灯 exit 1。"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

out = subprocess.run(["git", "-c", "core.quotepath=off", "ls-files", "docs", "AGENTS.md", "README.md"],
                     capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
skip = ("docs/archive/", "docs/superpowers/", "docs/预研/")
targets = [p for p in out if p.endswith(".md") and not p.startswith(skip)]

pat = re.compile(r"(?<![A-Za-z0-9_/.-])(?:docs|prototype|tools)/[^\s`\"'()（）,，、；;|>]*\.(?:md|html|json|yaml|xml|js|sh|dart|py)")
EXEMPT_LINE = ("已删除", "找回", "git log", "瘦身前存档")
EXEMPT_REF = {"prototype/x.html"}  # 泛指示例
# 文件级豁免（原因注释）：
FILE_EXEMPT = {
    "docs/影音游模块开发计划-20260922.md": "并行会话 M 中，禁改写；其工具链引用按延后裁定处理",
    "docs/架构与原型治理评估-20260928.md": "已收口评估记录，attic/历史脚本路径属史实记载非现行指针",
}
red = []
checked = 0
for p in targets:
    if p in FILE_EXEMPT:
        continue
    with open(p, encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f, 1):
            for m in pat.finditer(line):
                ref = m.group(0)
                checked += 1
                if "*" in ref or any(e in line for e in EXEMPT_LINE) or ref in EXEMPT_REF:
                    continue
                if ref.startswith("docs/archive/") or ref.startswith("docs/handoff/"):
                    pass  # 同样要求存在
                if not os.path.exists(ref):
                    red.append((p, n, ref))
print(f"扫描 {len(targets)} 份现行文档，{checked} 处路径引用")
if red:
    print(f"红灯 {len(red)} 处:")
    for p, n, ref in red:
        print(f"  {p}:{n} -> {ref}")
    sys.exit(1)

# ---- 漂移守护（防「又来很多轮后重新腐化」）----
g = []
# 1) 工单不得落 docs 顶层
ticket_pat = re.compile(r"^(交棒话术-|真机逐屏验收清单-|拍板记录-|.*开场白-)")
for p in out:
    if p.startswith("docs/") and p.count("/") == 1 and p.endswith(".md") and ticket_pat.match(p[5:]):
        g.append(f"工单落错层（应建在 docs/handoff/）: {p}")
# 2) INDEX 覆盖率：docs 顶层 + handoff 的跟踪 md 文件名必须出现在 INDEX.md
idx = open("docs/INDEX.md", encoding="utf-8").read()
for p in out:
    if not p.endswith(".md"):
        continue
    base = os.path.basename(p)
    if p == "docs/INDEX.md" or p == "docs/STATUS.md":
        continue
    if (p.startswith("docs/") and p.count("/") == 1) or p.startswith("docs/handoff/"):
        if base not in idx:
            g.append(f"INDEX 未登记: {p}")
# 3) 需求清单不得复活第十节/修订长行
req = open("docs/需求清单.md", encoding="utf-8").read().split("\n")
if any(l.startswith("## 十") for l in req):
    g.append("需求清单复活了「## 十、…」节（修订记录应写 docs/archive/需求修订史-*.md）")
for n, l in enumerate(req, 1):
    if len(l) > 1000:
        g.append(f"需求清单超长行（>1000 字符，疑修订长文回填）: 行{n} len={len(l)}")
# 4) 交接文档主文超长行
for n, l in enumerate(open("docs/交接文档.md", encoding="utf-8").read().split("\n"), 1):
    if len(l) > 800:
        g.append(f"交接文档超长行（>800）: 行{n} len={len(l)}")
# 5) 三件套行数预算
budgets = {"AGENTS.md": 90, "docs/STATUS.md": 60, "docs/INDEX.md": 130}
for p, lim in budgets.items():
    nl = sum(1 for _ in open(p, encoding="utf-8"))
    if nl > lim:
        g.append(f"{p} 行数 {nl} 超预算 {lim}")
if g:
    print(f"守护红灯 {len(g)} 处:")
    for x in g:
        print("  " + x)
    sys.exit(1)
# ---- 原型屏归属闸（治理批 §4-3；模式由 prototype/_modules.json.gateMode 决定，动刀批收口切 strict）----
pr = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "protogate.py")],
                    capture_output=True, text=True, encoding="utf-8", errors="replace")
print(pr.stdout.strip())
if pr.returncode != 0:
    print("protogate 红灯（strict），按上列明细处置后重跑")
    sys.exit(1)
print("PASS 零死链 + 守护全绿（工单落位/INDEX覆盖/需求清单/交接长行/三件套预算）")
