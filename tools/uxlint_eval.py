# -*- coding: utf-8 -*-
"""uxlint 棘轮评估：统计在活 8 份原型的四规则命中数，与基线比较，升即红。
用法：python uxlint_eval.py <report.json> <baseline.json> [--write]"""
import json, sys, collections

report_p, base_p = sys.argv[1], sys.argv[2]
write = ("--write" in sys.argv) or ("--baseline" in sys.argv)
ACTIVE = {"index.html", "index-ledger.html", "index-bookshelf.html", "index-maternity_bady.html",
          "index_habitcheck.html", "index-health.html", "index-day_aim__goods.html", "index-sync.html"}
RULES = {"emoji-in-ui", "lone-emoji-as-icon", "icon-emoji-stamp",          # emoji 族合并
         "placeholder-as-label", "select-without-label", "outline-none-no-focus-visible"}
GROUP = {"emoji": {"emoji-in-ui", "lone-emoji-as-icon", "icon-emoji-stamp"},
         "placeholder-as-label": {"placeholder-as-label"},
         "select-without-label": {"select-without-label"},
         "outline-none": {"outline-none-no-focus-visible"}}

r = json.load(open(report_p, encoding="utf-8"))
cur = {g: 0 for g in GROUP}
for x in r["findings"]:
    fn = x["file"].replace("\\", "/").split("/")[-1]
    if fn not in ACTIVE:
        continue
    for g, rules in GROUP.items():
        if x["rule_id"] in rules:
            cur[g] += 1

if write:
    json.dump(cur, open(base_p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("baseline written:", cur)
    sys.exit(0)

try:
    base = json.load(open(base_p, encoding="utf-8"))
except Exception:
    print("RED: 无基线文件，先跑 tools/uxlint.sh --baseline")
    sys.exit(2)

red = False
for g, n in sorted(cur.items()):
    b = base.get(g, 0)
    mark = "OK " if n <= b else "RED"
    if n > b:
        red = True
    print(f"{mark} {g}: {n} (基线 {b})")
print("PASS 零升档" if not red else "FAIL 有规则命中上升（棘轮只降不升）")
sys.exit(1 if red else 0)
