#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""doclint：现行文档集的引用路径体检（治理二轮工装）。
扫描对象 = 仓库根 AGENTS.md + git 跟踪的 docs/**.md（排除 docs/archive/、docs/superpowers/、docs/预研/）。
规则：文中出现的 docs/、prototype/、tools/ 相对路径（.md/.html/.js/.sh/.json/.dart/.py/.yaml/.xml）
必须真实存在；含通配符或行内有「已删除/找回/git log」豁免词的行跳过。任何红灯 exit 1。"""
import os, re, subprocess, sys

if hasattr(sys.stdout, "reconfigure"):      # GBK 控制台吃中文（2026-10-08 实踩）：统一按 UTF-8 出
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

out = subprocess.run(["git", "-c", "core.quotepath=off", "ls-files", "docs", "AGENTS.md", "README.md"],
                     capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
skip = ("docs/archive/", "docs/superpowers/", "docs/预研/")
targets = [p for p in out if p.endswith(".md") and not p.startswith(skip)]

pat = re.compile(r"(?<![A-Za-z0-9_/.-])(?:docs|prototype|tools)/[^\s`\"'()（）,，、；;|>]*\.(?:md|html|json|yaml|xml|js|sh|dart|py)")
EXEMPT_LINE = ("已删除", "找回", "git log", "瘦身前存档", "提案路径", "反例")
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
# 8) 文档里禁「花括号路径展开」（2026-10-11 实踩：`docs/{STATUS.md,INDEX.md}` 被本闸当字面量路径
#    判成死链，红得莫名其妙；写文档的人省了八个字，闸多绕一圈。代码签名里的 `{a, b}` 不带斜杠前缀
#    也不带扩展名，两条同时要求＝零误报。）
BRACE_PATH = re.compile(r"[\w/.-]*/\{([A-Za-z0-9_.-]+(?:,[A-Za-z0-9_.-]+)+)\}")
for p in targets:
    try:
        lines = open(p, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        continue
    for n, line in enumerate(lines, 1):
        if any(e in line for e in EXEMPT_LINE):
            continue  # 反例行（如守护八自己条文里举的坏例子）不判
        for m in BRACE_PATH.finditer(line):
            inner = m.group(1)
            if "." not in inner or "*" in m.group(0):
                continue  # 无扩展名＝多半是代码形参；带通配符＝死链检查本来就跳过
            g.append("守护八：路径别用花括号展开（本闸会当字面量判死链），逐条写全：%s:%d -> %s"
                     % (p, n, m.group(0)))
# 9) STATUS 必登记「未出编号」（2026-10-11 实伤：dart 攒两天没出装机包，产品没法真机验；
#    出装机包不是发布闸不需请示，所以「有没有欠着一枚包」必须每轮摆在台面上）。
stxt = open("docs/STATUS.md", encoding="utf-8").read()
m = re.search(r"^- 未出编号＝(.*)$", stxt, re.M)
if not m:
    g.append("守护九：docs/STATUS.md 缺「- 未出编号＝」行（收尾必报项；确实没有也要写「无」）")
else:
    declared = m.group(1)
    pending = set(re.findall(r"攒[^。\n]{0,24}?(\d{4})[^。\n]{0,12}?(?:未构建|未出)", stxt))
    for num in sorted(pending):
        if num not in declared:
            g.append("守护九：正文出现「攒 %s（未构建/未出）」但未写进「未出编号」行" % num)
    # 9B) 出包攒批口径（2026-10-11 产品拍板改口：复测包**不再每批自动构建**，
    #     只在产品说「这轮要装机/出包」时出一枚，覆盖攒下的所有批次。
    #     本闸强制两件事：① 台面行必须写明当前口径；② 说了「收口即出 NNNN」就必须真已出。
    if "攒批" not in declared and "待产品令" not in declared and "产品令装机" not in declared:
        g.append("守护九B：「- 未出编号＝」行未写明出包口径（须含「攒批」或「产品令装机」字样）"
                 "——口径＝复测包只在产品令装机时一枚打包，不每批自动构建")
    claimed = set(re.findall(r"(?:收口即出|即时出|收口出)\s*(\d{4})", stxt))
    pkg_line = re.search(r"^- 复测包＝(.*)$", stxt, re.M)
    built = pkg_line.group(1) if pkg_line else ""
    for num in sorted(claimed):
        if ("%s 已出" % num) not in built and ("**%s 已出**" % num) not in built:
            g.append("守护九B：正文声称「收口即出 %s」，但「- 复测包＝」行没有「%s 已出」＝说没做等于没做" % (num, num))
# 7) STATUS 体量硬闸（2026-10-08 治理批立·细则＝tools/status_set.py 头注释）
#    行数预算（守护五）拦不住「一行滚到 8 千字符」，这里补单行/全文/字段级数三道闸；
#    收尾改 STATUS 一律走 `python tools/status_set.py --rotate` + `--set 本批 --text-file`，禁手改表头行。
st = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "status_set.py"), "--check"],
                    capture_output=True, text=True, encoding="utf-8", errors="replace")
for _l in (st.stdout or "").splitlines():
    if _l.strip() and st.returncode != 0:
        g.append("守护七：" + _l.strip())
if st.returncode != 0 and not (st.stdout or "").strip():
    g.append("守护七：status_set.py --check 异常退出 rc=%s（stderr=%s）"
             % (st.returncode, (st.stderr or "").strip()[:160]))
# 10) 色值棘轮（2026-10-11 手感批：新增硬编码 Color(0x 即红；条文＝docs/UI组件规范.md 〇B，
#     工单＝docs/archive/交棒话术-20261011-手感批-触觉四锚与色值棘轮与边缘右滑内收.md §2。
#     存量不溯；确需新增＝人审后 `python tools/color_ratchet.py --write` 钉基线并在收口行写理由。）
cr = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "color_ratchet.py"), "--check"],
                    capture_output=True, text=True, encoding="utf-8", errors="replace")
if cr.returncode != 0:
    g.append("守护十：" + ((cr.stdout or "") + (cr.stderr or "")).strip().replace("\n", " / ")[:300])
# ---- 治理三轮（2026-10-13）可移植规则系统五条守护 ----
# 依据＝docs/handoff/治理方案-20261013-规则与上下文与记忆治理.md §6；回灌成句＝
# 「机器只认一份入口（AGENTS.md）；一条规则只在一处定义，其余写指针」。
# 十一) AGENTS.md 体量（超＝注入截断；放宽须人审改下列常量并在治理件写理由）
AGENTS_BYTES_MAX = 16384            # 16 KiB（Codex project_doc_max_bytes 默认 32 KiB，留一半余量）
_ab = os.path.getsize("AGENTS.md")
if _ab > AGENTS_BYTES_MAX:
    g.append("守护十一：AGENTS.md %d 字节超上限 %d（注入会被截断；须净零改写或归档）"
             % (_ab, AGENTS_BYTES_MAX))
# 十二/十三) 热点文档体量上限（二轮治理瘦身目标曾反弹；超上限须归档瘦身，放宽须人审）
JIAOJIE_BYTES_MAX = 215040          # 210 KiB（当前约 196 KiB，留 append 变更日志余量）
_jb = os.path.getsize("docs/交接文档.md")
if _jb > JIAOJIE_BYTES_MAX:
    g.append("守护十二：docs/交接文档.md %d 字节超上限 %d（须归档瘦身）" % (_jb, JIAOJIE_BYTES_MAX))
REQ_LINES_MAX = 600                 # 当前 562 行
_rl = sum(1 for _ in open("docs/需求清单.md", encoding="utf-8"))
if _rl > REQ_LINES_MAX:
    g.append("守护十三：docs/需求清单.md %d 行超上限 %d（修订记录应进 archive/需求修订史-*.md）"
             % (_rl, REQ_LINES_MAX))
# 十四) 入仓文档禁出现 .workbuddy/ 路径（入仓文档指向不入仓路径＝换机即死链）
#      豁免：行级 EXEMPT_LINE；`shots` 为仓库外截图留底目录（非知识指针）；治理件记录迁移前状态
FILE_EXEMPT_14 = {
    "docs/handoff/治理方案-20261013-规则与上下文与记忆治理.md":
        "本件记录「迁移前状态」、全篇讨论 .workbuddy/；收口归档后进 archive（skip）自动豁免",
}
for _p in targets:
    if _p in FILE_EXEMPT_14:
        continue
    for _n, _line in enumerate(open(_p, encoding="utf-8", errors="replace"), 1):
        if ".workbuddy/" in _line and "shots" not in _line and not any(e in _line for e in EXEMPT_LINE):
            g.append("守护十四：入仓文档出现不入仓路径 .workbuddy/（换机读不到）: %s:%d" % (_p, _n))
# 十五) AGENTS.md 必需锚点小节齐全（防「折叠丢失」——小节被删/合并后静默失效）
REQUIRED_SECTIONS = ["开工先读", "工单生命周期", "环境事实", "验证门禁", "禁令",
                     "忽略清单", "会话口令", "会话收尾仪式", "下指令"]
_ag = open("AGENTS.md", encoding="utf-8").read()
for _s in REQUIRED_SECTIONS:
    if not re.search(r"^##\s*" + re.escape(_s), _ag, re.M):
        g.append("守护十五：AGENTS.md 缺必需小节「%s」（规则折叠丢失）" % _s)
# 十六) 排期池体量上限（2026-10-13 立：该件曾塞入 92K 历史流水表＝其 93.7%，
#       而当时无任何闸看它 ⇒ 自 2026-10-02 迁入后涨了三个多月无人拦。
#       口径＝本件只装「一件一行」的候选索引，详情指向依据文档（handoff）或历史件（archive）；
#       放宽须人审改下列常量并写理由。）
BACKLOG_BYTES_MAX = 20480           # 20 KiB（瘦身后实测约 6.2 KB，留 3 倍余量）
BACKLOG_LINES_MAX = 120
_bp = "docs/排期池.md"
_bb = os.path.getsize(_bp)
_bl = sum(1 for _ in open(_bp, encoding="utf-8"))
if _bb > BACKLOG_BYTES_MAX:
    g.append("守护十六：%s %d 字节超上限 %d（本件只该装「一件一行」的候选索引；"
             "历史流水进 docs/archive/、条详情进 docs/handoff/）" % (_bp, _bb, BACKLOG_BYTES_MAX))
if _bl > BACKLOG_LINES_MAX:
    g.append("守护十六：%s %d 行超上限 %d" % (_bp, _bl, BACKLOG_LINES_MAX))
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
print("PASS 零死链 + 守护全绿（工单落位/INDEX覆盖/需求清单/交接长行/三件套预算/执行面板/体量上限/禁指工具目录/必需小节/排期池体量）")
