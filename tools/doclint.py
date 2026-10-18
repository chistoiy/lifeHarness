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
# 依据＝docs/archive/治理方案-20261013-规则与上下文与记忆治理.md §6；回灌成句＝
# 「机器只认一份入口（AGENTS.md）；一条规则只在一处定义，其余写指针」。
# ---- 体量闸 ＋ 黄线（2026-10-14「文档体量治理」；口径＝AGENTS.md 同名条文）----
# ① 黄线＝上限 90%：只警告不红，但收尾须顺手动一次瘦身、或在本批变更日志写明不瘦的理由；
# ② 棘轮：每次瘦身后把上限下调到「瘦身后实测 ×1.15」，只降不升（本次＝2026-10-14 首次瘦身）。
# 例外＝AGENTS.md 是「规则型」件（红线＝Codex 注入余量的一半，非堆积）⇒ 不设黄线，
#        往它里面加内容一律「净零改写」（加一句删等量）。
y = []                              # 黄灯（只警告，不改 exit code）
def _gate(label, path, size, maxb, yellow=True):
    if size > maxb:
        g.append("%s：%s %d 字节超上限 %d（须归档瘦身；放宽须人审改常量并写理由）"
                 % (label, path, size, maxb))
    elif yellow and size > maxb * 0.9:
        y.append("%s：%s %d 字节已达上限 %d 的 %.0f%%（黄线 90%%）——收尾须顺手动一次瘦身，"
                 "或在本批变更日志写明不瘦的理由"
                 % (label, path, size, maxb, 100.0 * size / maxb))

# 十一) AGENTS.md 体量（超＝注入截断；放宽须人审改下列常量并在治理件写理由）
AGENTS_BYTES_MAX = 16384            # 16 KiB（Codex project_doc_max_bytes 默认 32 KiB，留一半余量）
_gate("守护十一", "AGENTS.md", os.path.getsize("AGENTS.md"), AGENTS_BYTES_MAX, yellow=False)
# 十二) 交接文档（2026-10-14 首次瘦身＝正文变更日志改滚动窗口只留近 7 天：203140→149674 字节；
#       2026-10-16 治理五轮T2 二次瘦身＝「附」段被当成第二面变更日志，164 条流水 137 KB 整段沉档：161031→21540 字节）
JIAOJIE_BYTES_MAX = 24289            # 23.7 KiB（棘轮＝瘦身后实测 21121 × 1.15 取整；上一档 25600·只降不升）
_gate("守护十二", "docs/交接文档.md", os.path.getsize("docs/交接文档.md"), JIAOJIE_BYTES_MAX)
# 十二B) 交接文档「唯一活体变更日志面」内容型闸（2026-10-16 治理五轮T2 新增·守护十二只卡总字节看不见病根）
#        病灶＝「附·本机未入库资产清单」标题之下被当成第二面变更日志，逐轮流水堆到 137 KB／全文 87%，
#        且与 §5 变更日志重复登记（10-12/10-13/10-15 三天双份）＋出窗条目赖着不走。
#        闸＝附段只许留指针：正文非空行 ≤6，且不得出现流水条目（日期开头的 "- " 列表行）。
_JJ_LINES = open("docs/交接文档.md", encoding="utf-8").read().split("\n")
_m = next((k for k, l in enumerate(_JJ_LINES) if l.startswith("## 附 ·")), None)
if _m is None:
    g.append("守护十二B：docs/交接文档.md 缺「## 附 ·」小节（小节被删/改名，本闸失效）")
else:
    _tail = [l for l in _JJ_LINES[_m + 1:] if l.strip() != ""]
    if len(_tail) > 6:
        g.append("守护十二B：交接文档「## 附 ·」段正文非空行 %d > 6——附段只许留指针，"
                 "逐轮流水/资产盘点原文沉 docs/archive/变更台账-*.md" % len(_tail))
    for _n, l in enumerate(_tail, 1):
        if re.match(r"^-\s*\d{4}-\d{2}-\d{2}", l):
            g.append("守护十二B：交接文档「## 附 ·」段出现流水条目（第 %d 行）——变更日志唯一活体面是 §5，"
                     "此处出现逐批流水＝第二面登记面复发，须沉 docs/archive/变更台账-*.md" % _n)
            break
# 十三) 需求清单（行数 + 字节双闸；字节闸＝2026-10-14 新增——防「行数没超但巨行把体积顶满」，
#       该件实测平均 263 字节/行、最长 983 字符，纯行数闸根本看不见体积）
REQ_LINES_MAX = 600                 # 当前 562 行
REQ_BYTES_MAX = 174080              # 170 KiB（棘轮＝2026-10-14 实测 148423 × 1.15 取整）
_REQ = "docs/需求清单.md"
_rl = sum(1 for _ in open(_REQ, encoding="utf-8"))
_gate("守护十三", _REQ, os.path.getsize(_REQ), REQ_BYTES_MAX)
if _rl > REQ_LINES_MAX:
    g.append("守护十三：%s %d 行超上限 %d（修订记录应进 archive/需求修订史-*.md）"
             % (_REQ, _rl, REQ_LINES_MAX))
# 十四) 入仓文档禁出现 .workbuddy/ 路径（入仓文档指向不入仓路径＝换机即死链）
#      豁免：行级 EXEMPT_LINE；`shots` 为仓库外截图留底目录（非知识指针）
#      （原 治理方案件 文件级豁免已随该件 2026-10-13 收尾归档进 docs/archive/ 而移除——archive 被 skip 自动豁免）
FILE_EXEMPT_14 = {}
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
_gate("守护十六", _bp, _bb, BACKLOG_BYTES_MAX)
if _bl > BACKLOG_LINES_MAX:
    g.append("守护十六：%s %d 行超上限 %d（本件只该装「一件一行」的候选索引；"
             "历史流水进 docs/archive/、条详情进 docs/handoff/）" % (_bp, _bl, BACKLOG_LINES_MAX))
# 十七) 开发计划书体量上限（2026-10-14 新增：本件此前**无任何闸**——「不会被提醒的件才是真隐患」，
#       它 60 KB 且每轮收口都在长（测试口径/流水线细则先写这里），自 2026-09-25 起无人拦。）
PLAN_BYTES_MAX = 71680              # 70 KiB（棘轮＝2026-10-14 实测 60202 × 1.15 取整）
_gate("守护十七", "docs/开发计划书.md", os.path.getsize("docs/开发计划书.md"), PLAN_BYTES_MAX)
# ---- 守护二十/二十一/二十二：治理文档「内容型瘦身闸」（治理五轮 T1·2026-10-16 立）----
# 起因：本仓文档瘦身规则**只卡字节/行数上限，不卡「该沉什么」**——每轮收尾照抄读数，
# 闸红了就单向放宽上限，永远回不到默认面。2026-10-16 实测病灶：
#   · INDEX 84,698 B 里 69%（30,799 字符）挂在 43 条**已归档件**的行尾流水上（最长一行 11,930 字符），活件仅 18 条；
#   · STATUS 13,931 B 已越黄线 12,902，单行滚存（下一站 1,192 字符）；
#   · 排期池速览表与详情段**重复登记同一实测读数**。
# 本组三闸改「量型判红」为「内容型判红」——不看总字节，看该沉的内容是否还钉在现行件里。
# 工单＝docs/handoff/交棒话术-20261016-治理文档瘦身规则优化.md §2 规则一。

# 守护二十：INDEX 归档件行 ≤ ARCHIVE_ROW_MAX 字符（归档件只需「在哪、能查」，不需要「做了什么」）
ARCHIVE_ROW_MAX = 220
for _l in [x for x in idx.splitlines() if x.strip().startswith("| docs/archive/")]:
    if len(_l) > ARCHIVE_ROW_MAX:
        g.append("守护二十：INDEX 归档件行 %d 字符 > %d「%s…」——历史叙事沉该件自身 docs/archive/ 正文，INDEX 只留路径＋一句能查（工单 §2 规则三）"
                 % (len(_l), ARCHIVE_ROW_MAX, _l.strip()[:40]))

# 守护二十一：STATUS 单行滚存 ≤ STATUS_ROW_MAX 字符（严于 status_set.py 的 1200，专治下一站/复测包这类超长行）
STATUS_ROW_MAX = 700                # 单行滚存上限（严于 status_set.py 的 MAX_LINE_CHARS=1200·专治下一站/复测包类超长行）
_st_body = open("docs/STATUS.md", encoding="utf-8").read()
for _i, _l in enumerate(_st_body.splitlines(), 1):
    if len(_l) > STATUS_ROW_MAX:
        g.append("守护二十一：STATUS L%d %d 字符 > %d——单行只许写「现状一行结论＋指针」，历史读数沉交接文档变更日志（工单 §2 规则三）"
                 % (_i, len(_l), STATUS_ROW_MAX))

# 守护二十二：排期池速览表行 ≤ BACKLOG_ROW_MAX 字符（速览只留结论＋指针，细节在详情段）
BACKLOG_ROW_MAX = 160
_bl_view = [x for x in open(_bp, encoding="utf-8").read().splitlines()
            if x.strip().startswith("|") and x.count("|") >= 5]
for _l in _bl_view:
    if len(_l) > BACKLOG_ROW_MAX:
        g.append("守护二十二：排期池速览行 %d 字符 > %d——速览只留一行结论＋指针，细节在详情段（工单 §2 规则三）"
                 % (len(_l), BACKLOG_ROW_MAX))

# ---- 守护十九：收口必归档（治理四轮 T1·2026-10-16 立）----
# 起因：2026-10-02 治理二轮做过一次同款流转（26 份→4 活 22 闭环，tools/gov2_move_tickets.py），
# 但**没有任何闸管「收口了要归档」**——两周内 docs/handoff/ 又从 4 份积回 50 份，其中 17 份
# 末次提交主题就写着「收口/闭环/验收通过」却仍占着交接层，无人发现（不会被提醒的件才是真隐患）。
# 本闸＝工单生命周期的「双向核」：交接层实施工单 ⇔ 活单名单，两边必须严格相等。
#   · 交接层出现名单外的实施工单 → 红（要么它真已收口该归档，要么该登进名单当活单）
#   · 名单里的文件不在交接层     → 红（已归档却忘从名单摘，或活单被误删）
# 名单与 tmp/gov4_move_tickets.py 的 ACTIVE 同源，改一处必两处同改。
TICKET_PFX19 = ("交棒话术-", "真机逐屏验收清单-", "拍板记录-", "悬浮胶囊增强批-")
ACTIVE_TICKETS19 = {
    "交棒话术-20261015-备份导出余量时间维度与子集部分恢复.md",
    "交棒话术-20261011-笔记模块结构与手感优化.md",
    "交棒话术-20261011-底栏双指收起态.md",
    "交棒话术-20261008-健康批7仪表盘今日健康卡.md",
    "交棒话术-20261009-影音游批9导入矩阵与导出尾项.md",
    "交棒话术-20261004-笔记本地导入导出与系统打开方式.md",
    "交棒话术-20261005-UX审计真机批-贴底行吞点击与工装转正.md",
    "悬浮胶囊增强批-20261014.md",
    "交棒话术-20261016-治理文档瘦身规则优化.md",
    "拍板记录-20261018-记一笔弹窗记账与零输入口径改判.md",
}
_ho = "docs/handoff"
_on_disk = {f for f in os.listdir(_ho)
            if f.endswith(".md") and f.startswith(TICKET_PFX19)} if os.path.isdir(_ho) else set()
_unlisted = sorted(_on_disk - ACTIVE_TICKETS19)
_missing = sorted(ACTIVE_TICKETS19 - _on_disk)
print("守护十九 工单生命周期：交接层实施工单 %d 份 / 活单名单 %d 份" % (len(_on_disk), len(ACTIVE_TICKETS19)))
for _u in _unlisted:
    g.append("守护十九：交接层有未登记的实施工单 %s——已收口请 git mv 入 docs/archive/ 并改指引用；"
              "仍活跃请把文件名加进 doclint 守护十九 ACTIVE_TICKETS19" % _u)
for _m in _missing:
    g.append("守护十九：活单名单里的 %s 不在 docs/handoff/——已归档请从名单摘掉；否则红" % _m)
for x in y:
    print("体量黄灯（达上限 90%）: " + x)
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
# ---- 守护十八：读侧索引卡一致性（治理 §4-6「doclint 校索引与 HTML 一致」2026-10-16 补做）----
# 卡是 pslice.js --list 的唯一读数来源；过期卡＝读侧工具给错读数且无人知情。漂移即红灯。
try:
    rc = subprocess.run(["node", os.path.join(ROOT, "tools", "proto_cards_check.js"), "--check"],
                        capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ROOT)
    tailc = [x for x in (rc.stdout or "").strip().splitlines() if x.startswith(("索引卡体检", "CARDS"))]
    print(" / ".join(tailc) if tailc else (rc.stdout or "").strip()[:200])
    if rc.returncode != 0:
        print("守护十八 红灯（索引卡缺/过期/孤儿）：跑 `node tools/proto_cards_check.js --write` 重生成后复跑本闸")
        sys.exit(1)
except FileNotFoundError:
    print("WARN 未找到 node，索引卡体检跳过（本机应有 node，出现此行请先查 PATH）")
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
print("PASS 零死链 + 守护全绿（工单落位/INDEX覆盖/需求清单/交接长行/三件套预算/执行面板/体量上限＋黄线/禁指工具目录/必需小节/排期池体量/计划书体量）")
