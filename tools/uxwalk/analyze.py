# -*- coding: utf-8 -*-
"""Analyze walk_all out/*.xml: coverage matrix + deterministic UX flags."""
import glob, re, os, collections, json

D = sys.argv[1] if len(sys.argv)>1 else "tmp/uxwalk"
EMOJI = re.compile(r"[\U0001F000-\U0001FAFF\u2600-\u26FF\u2700-\u27BF\u2B00-\u2BFF\uFE0F]")
MONO = set("✕✖✓✔☑☐❝❞✎✏›‹→←↑↓✦✱⚠✳✴❄☀")
TEACH = re.compile(r"(长按|双击|点击.{0,6}(即可|可以|可)|拖拽|滑动.{0,6}(即可|可)|说明：|提示：|操作方法|可拖|=调整|＝)")
DENS = 3.0  # 480dpi
MIN_TP = int(44 * DENS)  # 132px

rows = []
for p in sorted(glob.glob(D + "/*.xml")):
    rid = os.path.basename(p)[:-4]
    s = open(p, encoding="utf-8", errors="replace").read()
    nodes = re.findall(r"<node[^>]*>", s)
    texts, descs = [], []
    small_tp, unlabeled, emoji_hits, teach_hits, v1_hits = [], [], [], [], []
    for n in nodes:
        t = (re.search(r'text="([^"]*)"', n) or [None, ""])[1].strip() if re.search(r'text="([^"]*)"', n) else ""
        d = (re.search(r'content-desc="([^"]*)"', n) or [None, ""])[1].strip() if re.search(r'content-desc="([^"]*)"', n) else ""
        bm = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        b = list(map(int, bm.groups())) if bm else None
        clickable = 'clickable="true"' in n
        lab = d or t
        if d: descs.append(d)
        if t: texts.append(t)
        ce = [c for c in EMOJI.findall(lab) if c not in MONO and c != "\uFE0F"]
        if ce:
            emoji_hits.append((lab[:28], "".join(dict.fromkeys(ce))))
        if re.search(r"V1\.[0-9xX]", lab):
            v1_hits.append(lab[:30])
        if TEACH.search(t or d):
            teach_hits.append((t or d)[:36])
        if b and clickable:
            w, h = b[2] - b[0], b[3] - b[1]
            if (w < MIN_TP or h < MIN_TP) and w > 0 and h > 0:
                small_tp.append(f"{lab[:14] or '(no-label)'} {w}x{h}")
            if not lab:
                unlabeled.append(f"{w}x{h}@{b[0]},{b[1]}")
    title = (descs + texts + ["(untitled)"])[0][:24] if (descs or texts) else "(EMPTY)"
    rows.append({
        "id": rid, "nodes": len(nodes), "title": title,
        "emoji": len(emoji_hits), "emoji_samples": emoji_hits[:3],
        "teach": len(teach_hits), "teach_samples": teach_hits[:2],
        "v1": v1_hits[:2],
        "small_tp": len(small_tp), "small_samples": small_tp[:4],
        "unlabeled": len(unlabeled),
        "empty": len(nodes) < 8,
    })

import sys
A = D
with open(A + "/device-full-matrix.json", "w", encoding="utf-8") as f:
    json.dump(rows, f, ensure_ascii=False, indent=1)

out = []
out.append(f"{'id':16}{'nodes':>6}{'emoji':>6}{'teach':>6}{'smallTP':>8}{'unlab':>6}  title/flags")
for r in rows:
    flags = []
    if r["empty"]: flags.append("EMPTY-CAPTURE")
    if r["v1"]: flags.append("V1x:" + r["v1"][0][:12])
    if r["small_samples"]: flags.append("tp:" + ";".join(r["small_samples"][:2]))
    if r["teach_samples"]: flags.append("teach:" + r["teach_samples"][0][:16])
    out.append(f"{r['id']:16}{r['nodes']:>6}{r['emoji']:>6}{r['teach']:>6}{r['small_tp']:>8}{r['unlabeled']:>6}  {r['title']} | " + " | ".join(flags))
open(A + "/device-full-matrix.txt", "w", encoding="utf-8").write("\n".join(out))
print("screens:", len(rows), "empty:", sum(r['empty'] for r in rows),
      "emoji_total:", sum(r['emoji'] for r in rows), "smalltp_total:", sum(r['small_tp'] for r in rows))
