# -*- coding: utf-8 -*-
"""治理二轮 T2：需求清单拆分——头部引用块(第3行) + 第十节 逐字迁出为《需求修订史》。
护栏：快照、命中断言、体积校验；按真实编码读写，LF 保持。失败即回滚。"""
import re, shutil, sys, os

ROOT = r"D:/dev_workplace/flutter_te/lifeHarness"
SRC = os.path.join(ROOT, "docs", "需求清单.md")
DST_DIR = os.path.join(ROOT, "docs", "archive")
DST = os.path.join(DST_DIR, "需求修订史-V1.19~V1.59.md")
SNAP = os.path.join(ROOT, "tmp", "需求清单.bak-20261002-gov2.md")

os.makedirs(DST_DIR, exist_ok=True)
os.makedirs(os.path.dirname(SNAP), exist_ok=True)
shutil.copy2(SRC, SNAP)

with open(SRC, "r", encoding="utf-8", newline="") as f:
    lines = f.read().split("\n")

orig_total = len(lines)
assert lines[2].startswith("> 本文件为经多轮确认"), "第3行不是引用块"
idx10 = next(i for i, l in enumerate(lines) if l.startswith("## 十、版本冻结说明"))
assert 500 < idx10 < 520, f"第十节起点异常: {idx10}"
tail = lines[idx10:]
head_quote = lines[2]

# --- 头部引用块拆条：每个 **V1.nn： 断段（逐字，仅断行） ---
body = head_quote.lstrip("> ")
entries = [p.strip() for p in re.split(r"(?=\*\*V1\.\d)", body) if p.strip()]

HDR_TITLE = "# LifeHarness 需求修订史（V1.18~V1.59）"
HDR_NOTE = ("> 由《需求清单》头部引用块与第十节逐字迁出（2026-10-02 治理二轮）。"
            "三源冲突优先序第一位＝本文件的修订记录。现行需求定义看 `docs/需求清单.md`。")
SEC1 = "## 一、头部修订摘录（迁自需求清单原第 3 行引用块）"
SEC2 = "## 二、逐版修订记录（原「十、版本冻结说明」全文迁出）"
hist = "\n\n".join([HDR_TITLE, HDR_NOTE, SEC1, "\n\n".join(entries), SEC2, "\n".join(tail)]) + "\n"
with open(DST, "w", encoding="utf-8", newline="") as f:
    f.write(hist)

# --- 新需求清单：标题 + 指针 + 现行一~九节 ---
ptr = "> 修订史（V1.18~V1.59 全部逐版记录 · 三源优先序第一位）：`docs/archive/需求修订史-V1.19~V1.59.md`。本文件只保留现行需求定义。"
new = [lines[0], "", ptr] + lines[3:idx10]
while len(new) > 1 and new[-1] == "" and new[-2] == "":
    new.pop()
with open(SRC, "w", encoding="utf-8", newline="") as f:
    f.write("\n".join(new))

# --- 校验 ---
with open(DST, "r", encoding="utf-8") as f:
    hist_txt = f.read()
with open(SRC, "r", encoding="utf-8") as f:
    src_txt = f.read()

def core_chars(s):
    return len(re.sub(r"[\s*|>#`\-—（）「」《》：；。、\'\"]", "", s))

framework = core_chars("\n\n".join([HDR_TITLE, HDR_NOTE, SEC1, SEC2]))
moved_chars = core_chars(hist_txt) - framework
orig_chars = core_chars(head_quote) + core_chars("\n".join(tail))
fail = []
if abs(moved_chars - orig_chars) > 20:
    fail.append(f"体积不守恒: 迁出 {moved_chars} vs 原文 {orig_chars}")
for kw in ["\n### V1.59 修订记录", "\n### V1.19 修订记录", "\n## 十、版本冻结说明", "**V1.30：阅读模块", "\n### 决策记录（确认门已关闭"]:
    if kw not in "\n" + hist_txt:
        fail.append(f"修订史缺标志: {kw.strip()[:20]}")
for kw in ["\n## 十、版本冻结说明", "\n### V1.59 修订记录", "\n### V1.53 修订记录"]:
    if kw in "\n" + src_txt:
        fail.append(f"需求清单仍含迁出内容: {kw.strip()[:20]}")
for kw in ["## 一、产品定位", "## 九、用户故事", "### 模块 8 · 记账", "#### V1.48.1 扩展"]:
    if kw not in src_txt:
        fail.append(f"需求清单丢了现行内容: {kw}")
n_v = len(re.findall(r"^### V1\.", hist_txt, re.M))
if n_v < 30:
    fail.append(f"修订史 ### V1.x 条目过少: {n_v}")

print(f"原行数={orig_total} 新需求清单行数={src_txt.count(chr(10))+1} 修订史行数={hist_txt.count(chr(10))+1} V条目={n_v}")
print(f"迁出核心字符={moved_chars} 原文核心字符={orig_chars}")
if fail:
    shutil.copy2(SNAP, SRC)
    print("FAIL 已回滚需求清单:\n" + "\n".join(fail))
    sys.exit(1)
print("PASS")
