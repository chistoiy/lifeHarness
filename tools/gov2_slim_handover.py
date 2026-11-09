# -*- coding: utf-8 -*-
"""治理二轮 T3：交接文档瘦身。
- 头部超长行(3~62)、旧§0(66~83)、旧§1(84~105)、旧§2(107~133)、旧§3(135~160)、§5变更日志(181~281)
  逐字迁出 -> docs/archive/交接文档-瘦身前存档-20261002.md
- §7 待排期池(318~405) 逐字迁出 -> docs/排期池.md（现行规划材料，独立成文件按需读）
- 主文件重写为短头部+指针；ADR/注意事项/附录逐字保留。
护栏：快照、行数/字符守恒断言，失败回滚。"""
import shutil, sys, os, re

ROOT = r"D:/dev_workplace/flutter_te/lifeHarness"
SRC = os.path.join(ROOT, "docs", "交接文档.md")
ARC = os.path.join(ROOT, "docs", "archive", "交接文档-瘦身前存档-20261002.md")
POOL = os.path.join(ROOT, "docs", "排期池.md")
SNAP = os.path.join(ROOT, "tmp", "交接文档.bak-20261002-gov2.md")

os.makedirs(os.path.dirname(SNAP), exist_ok=True)
shutil.copy2(SRC, SNAP)
orig = open(SRC, encoding="utf-8").read()
L = orig.split("\n")

def rng(a, b):  # 1-based 闭区间
    return L[a - 1:b]

def anchor(pred, frm=0):  # 返回 1-based 行号
    for i in range(frm, len(L)):
        if pred(L[i]):
            return i + 1
    return -1

i_h2 = anchor(lambda s: s.startswith("## 2. "))
i_h3 = anchor(lambda s: s.startswith("## 3. "))
i_h4 = anchor(lambda s: s.startswith("## 4. "))
i_h5 = anchor(lambda s: s.startswith("## 5. "))
i_h6 = anchor(lambda s: s.startswith("## 6. "))
i_h7 = anchor(lambda s: s.startswith("## 7. "))
i_ha = anchor(lambda s: s.startswith("## 附"))
assert -1 not in (i_h2, i_h3, i_h4, i_h5, i_h6, i_h7, i_ha), "章节锚点缺失"
assert L[i_h3 - 1].startswith("## 3. 下一步") and L[i_h7 - 1].startswith("## 7. 待排期池"), "章节语义变化"

sec_head = rng(3, 65)              # 头部超长行块（至 §0 前空行/---）
sec_0 = rng(66, i_h2 - 1)          # §0 快速上手 + §1 目录结构
sec_2 = rng(i_h2, i_h3 - 1)
sec_3 = rng(i_h3, i_h4 - 1)
sec_5 = rng(i_h5, i_h6 - 1)
sec_6 = rng(i_h6, i_h7 - 1)        # 保留
sec_7 = rng(i_h7, i_ha - 1)        # 迁出为排期池
sec_a = rng(i_ha, len(L) - 1)      # 附录保留

def demote(lines):
    return ["###" + s[2:] if s.startswith("## ") else s for s in lines]

moved = "\n\n".join([
    "# 交接文档 · 瘦身前存档（2026-10-02 治理二轮 · 逐字保留）",
    "> 来源：`docs/交接文档.md`（头部超长行 / 旧快速上手 / 旧目录结构 / 旧当前状态 / 旧下一步 / 旧变更日志全文）。仅供追溯，不再更新。",
    "## 一·头部与各节原文（## 已降为 ###）",
    "\n".join(demote(sec_head + sec_0 + sec_2 + sec_3)),
    "## 五·原变更日志全文",
    "\n".join(demote(sec_5)),
]) + "\n"
open(ARC, "w", encoding="utf-8", newline="").write(moved)

pool = ("# 待排期池（Backlog）\n\n"
        "> 2026-10-02 治理二轮自《交接文档》§7 逐字迁出，内容原样（## 已降为 ###）。排期决策前读；改状态只改本文件。\n\n"
        + "\n".join(demote(sec_7[1:])) + "\n")
open(POOL, "w", encoding="utf-8", newline="").write(pool)

new = "\n".join([
    "# LifeHarness 交接文档",
    "",
    "> 用途：过程/知识文档——快速上手路径、目录结构、关键决策、变更日志登记规则、注意事项、未入库资产盘点。",
    "> **当前状态看 `docs/STATUS.md`（唯一状态源）**；文档路由看 `docs/INDEX.md`；禁令与环境事实看 `AGENTS.md`。",
    "> 历史时点全文在 `docs/archive/交接文档-瘦身前存档-20261002.md`；每批交付细节在对应工单（docs/handoff→archive）。",
    "",
    "## 0. 快速上手（接手人先读这里）",
    "",
    "1. 开工三件套：`docs/STATUS.md` → `docs/INDEX.md`（按任务路由，只读命中行指向的文件）→ 本批活工单（`docs/handoff/`）。",
    "2. 需求：`docs/需求清单.md`（现行定义）；逐版修订与「三源优先序第一位」＝`docs/archive/需求修订史-V1.19~V1.59.md`。不臆测范围。",
    "3. 视觉/交互：`prototype/index.html`（共享面事实源）与各专版原型（INDEX §3 清单）；按屏深链定位，勿整读大文件。",
    "4. 流程铁律（发版 §7.1 / 测试调度 §7.2 / 工程红线 §五）见 `docs/开发计划书.md`；禁令以 `AGENTS.md` 为准。",
    "5. 旧版逐条铁律全文（预发布铁律、确认门、护栏、两档提速、所有权、体积预算等 14 条）已存档于瘦身档 §一，其现行有效口径均已收录于计划书与 AGENTS。",
    "",
    "## 1. 目录结构",
    "",
    "```",
    "lifeHarness/",
    "├── android/  lib/  test/  pubspec.yaml      # Flutter 工程（包名 lifeharness·仅 Android·minSdk 26）",
    "├── assets/themes/                            # 7 套主题设计令牌 json（构建期载入）",
    "├── prototype/                                # index.html 共享面 + index-*.html 各模块专版",
    "├── tools/                                    # 校验与工装脚本（ftest.sh 门禁包装；attic/ 为本机快照区·不入库）",
    "└── docs/",
    "    ├── STATUS.md / INDEX.md（+仓库根 AGENTS.md）  # 开工三件套",
    "    ├── 需求清单 / UI组件规范 / 开发计划书 / 本文件 / 排期池 / 高保真原型设计准则",
    "    ├── handoff/ 活工单 · archive/ 闭环归档 · 预研/ 结论 · 发版说明/ · superpowers/ 规格与计划",
    "    └── lib/features/ 按模块分目录（代码即事实，结构不在此复述）",
    "```",
    "",
    "## 2. 当前状态 / 下一步",
    "",
    "见 `docs/STATUS.md`（状态）与 `docs/INDEX.md` §2（活工单=下一步规格）。本文不再内嵌状态表。",
    "",
    "\n".join(demote([l for l in rng(i_h4, i_h5 - 1)])).replace("### 4. ", "## 4. ", 1),
    "",
    "## 5. 变更日志（Change Log）",
    "",
    "> 治理二轮起：每批收口在此追加 **≤3 行**（结论+提交+发版），逐轮细节写进工单；181~281 行的旧日志全文已迁 `docs/archive/交接文档-瘦身前存档-20261002.md` §五。",
    "",
    "- 2026-10-02 治理二轮（零代码改动）：开工三件套入库；需求清单拆分出修订史；本文瘦身存档；工单流转 handoff/archive；截图与 tools/attic 出仓；体积债务登记。计划与规格见 docs/superpowers/{plans,specs}/2026-10-02-context-governance*。",
    "",
    "\n".join(demote(sec_6)).replace("### 6. ", "## 6. ", 1),
    "",
    "## 7. 待排期池（Backlog）",
    "",
    "已独立成文件 **`docs/排期池.md`**（逐字迁出，内容未改）；排期决策前读。",
    "",
    "\n".join(demote(sec_a)).replace("### 附 · ", "## 附 · ", 1),
]) + "\n"
open(SRC, "w", encoding="utf-8", newline="").write(new)

# --- 校验 ---
main = open(SRC, encoding="utf-8").read()
def core(s):
    return len(re.sub(r"[\s*|>#`\-—「」《》：；。、\'\"()（）]", "", s))
fail = []
arc_txt = open(ARC, encoding="utf-8").read()
moved_core = core(arc_txt) + core(pool)
kept_core = core(main)
orig_core = core(orig)
if moved_core + kept_core < orig_core - 200:  # 新头部/指针有增量，允许存档侧≥原文
    fail.append(f"内容疑似丢失: 存+留 {moved_core} vs 原 {orig_core}")
nl = main.count("\n") + 1
if not (100 <= nl <= 220):
    fail.append(f"主文件行数异常: {nl}")
for kw in ["STATUS.md", "排期池", "瘦身前存档"]:
    if kw not in main:
        fail.append(f"主文件缺指针: {kw}")
for kw in ["3c10", "V1.58 下架发版链", "下一站", "## 4. 关键决策", "## 6. 注意事项", "## 附"]:
    hay = main if kw.startswith("## ") else (main + arc_txt)
    if kw not in hay:
        fail.append(f"关键内容丢失: {kw}")
print(f"主文件行数={nl} 原行数={len(L)} 存档行数={moved.count(chr(10))+1} 排期池行数={pool.count(chr(10))+1}")
print(f"核心字符 原={orig_core} 留={kept_core} 存={moved_core}")
if fail:
    shutil.copy2(SNAP, SRC)
    print("FAIL 已回滚:\n" + "\n".join(fail)); sys.exit(1)
print("PASS")
