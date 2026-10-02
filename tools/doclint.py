#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""doclint：现行文档集的引用路径体检（治理二轮工装）。
扫描对象 = 仓库根 AGENTS.md + git 跟踪的 docs/**.md（排除 docs/archive/、docs/superpowers/、docs/预研/）。
规则：文中出现的 docs/、prototype/、tools/ 相对路径（.md/.html/.js/.sh/.json/.dart/.py/.yaml/.xml）
必须真实存在；含通配符或行内有「已删除/找回/git log」豁免词的行跳过。任何红灯 exit 1。"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

out = subprocess.run(["git", "-c", "core.quotepath=off", "ls-files", "docs", "AGENTS.md"],
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
print("PASS 零死链")
