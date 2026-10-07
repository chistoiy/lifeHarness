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
EXEMPT_LINE = ("已删除", "找回", "git log", "瘦身前存档", "提案路径")
EXEMPT_REF = {"prototype/x.html", "docs/xxx.md"}  # 泛指示例
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
# 6) 施工类活工单必须带「⚙ 执行面板」（2026-10-06 单批20分钟流水线口径，计划书 §7.5；存量豁免名单只许减）
PANEL_EXEMPT = {  # 口径生效（20261006）前立案的存量活施工工单；其下一批开工须先补面板并出名单
    "docs/handoff/交棒话术-20261002-下一版实现批-F01-批C-R32精修.md": "立单早于口径",
    "docs/handoff/交棒话术-20261002-划线精确化批.md": "立单早于口径",
    "docs/handoff/交棒话术-20261004-笔记本地导入导出与系统打开方式.md": "立单早于口径",
    "docs/handoff/交棒话术-20261004-备份管理与图片预览批.md": "立单早于口径",
    "docs/handoff/交棒话术-20261004-真机反馈轮5三条.md": "立单早于口径",
    "docs/handoff/交棒话术-20260929-R15-1整批撤销.md": "立单早于口径",
    "docs/handoff/交棒话术-20261005-UX审计真机批-贴底行吞点击与工装转正.md": "立单早于口径",
}
for _l in idx.split("\n"):
    _m = re.search(r"docs/handoff/([^\s|`*（(]+\.md)", _l)
    if not _m or "活" not in _l:
        continue
    _name = _m.group(1)
    if not re.match(r"^(交棒话术-|.*开场白-)", _name):
        continue
    _p = "docs/handoff/" + _name
    if _p in PANEL_EXEMPT:
        continue
    if not os.path.exists(_p):
        g.append(f"守护六：INDEX 活工单文件缺失: {_p}")
        continue
    if "⚙ 执行面板" not in open(_p, encoding="utf-8", errors="replace").read():
        g.append(f"守护六：活施工工单缺「执行面板」小节（标题匹配串＝gear符+空格+执行面板，见计划书 §7.5）: {_p}")
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
# ---- 注册表 size/hash 体检（排期池候选批 2026-10-06：两列自登记后无人读过＝装饰，从此读它）----
# 改过任何原型屏/弹层后须 `node tools/proto_registry.js --write` 重算再收口；漂移即红灯。
try:
    rr = subprocess.run(["node", os.path.join(ROOT, "tools", "proto_registry.js"), "--check"],
                        capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ROOT)
    tail = [x for x in (rr.stdout or "").strip().splitlines() if x.startswith(("file 条目合计", "REGISTRY"))]
    print(" / ".join(tail) if tail else (rr.stdout or "").strip()[:200])
    if rr.returncode != 0:
        print("注册表 size/hash 漂移（红灯）：跑 `node tools/proto_registry.js --write` 重算后复跑本闸")
        sys.exit(1)
except FileNotFoundError:
    print("WARN 未找到 node，注册表体检跳过（本机应有 node，出现此行请先查 PATH）")
# ---- T13 档③ 硬零闸：代码自造表情只许在白名单文件（须写理由），新增即红灯 ----
try:
    re3 = subprocess.run(["node", os.path.join(ROOT, "tools", "emoji_triage.js"), "--check"],
                         capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ROOT)
    tail3 = [x for x in (re3.stdout or "").strip().splitlines() if x.startswith(("档③ 违规", "  EMOJI3"))]
    print(" / ".join(tail3[:1]) if tail3 else (re3.stdout or "").strip()[:160])
    if re3.returncode != 0:
        print("T13 档③ 红灯：上列 EMOJI3 是「代码里有、原型里没有」的表情符号——换线性图标/删字符，"
              "确需保留才进 tools/emoji_triage.js 的 ALLOW3 并写理由（例外失效也会红）")
        sys.exit(1)
except FileNotFoundError:
    print("WARN 未找到 node，T13 档③ 闸跳过")
print("PASS 零死链 + 守护全绿（工单落位/INDEX覆盖/需求清单/交接长行/三件套预算/执行面板）")
