# -*- coding: utf-8 -*-
"""D 组增强验证：D1对白归属 D2别名合并 D3共现图 D4地名词典 D6交叉置信。
输出 out/d_report_<slug>.json（供图谱面板）+ 控制台量化。
"""
import sys, os, re, json, time
from collections import Counter, defaultdict

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import xray_extract as X

# ---- D4 gazetteer：通用现行地名（国家/地区/主要城市；历史名需另补，评估时注明）----
GAZ = """中国 英国 美国 法国 德国 俄罗斯 日本 印度 巴西 阿根廷 智利 秘鲁 墨西哥 加拿大 澳大利亚 新西兰
西班牙 葡萄牙 荷兰 比利时 瑞士 奥地利 意大利 希腊 土耳其 伊朗 伊拉克 叙利亚 埃及 利比亚 突尼斯 阿尔及利亚
摩洛哥 埃塞俄比亚 肯尼亚 坦桑尼亚 南非 尼日利亚 刚果 苏丹 以色列 约旦 黎巴嫩 沙特 也门 阿富汗 巴基斯坦
蒙古 韩国 朝鲜 越南 泰国 缅甸 柬埔寨 老挝 马来西亚 印度尼西亚 菲律宾 新加坡 波兰 捷克 匈牙利 罗马尼亚
保加利亚 塞尔维亚 克罗地亚 瑞典 挪威 丹麦 芬兰 冰岛 爱尔兰 乌克兰 白俄罗斯 立陶宛 拉脱维亚 爱沙尼亚
中亚 东亚 东南亚 南亚 西亚 中东 西欧 东欧 北欧 南欧 北美 南美 大洋洲 非洲 欧洲 亚洲 南极洲 大西洋
太平洋 印度洋 北冰洋 地中海 红海 黑海 里海 波罗的海 北海 加勒比海 波斯湾 孟加拉湾 几内亚湾
亚马逊河 尼罗河 密西西比河 黄河 长江 恒河 印度河 幼发拉底河 底格里斯河 多瑙河 莱茵河 伏尔加河
撒哈拉 戈壁 西伯利亚 东南亚群岛 马达加斯加 斯里兰卡 锡兰 夏威夷 关岛 百慕大 格陵兰
伦敦 巴黎 柏林 罗马 雅典 马德里 里斯本 维也纳 布达佩斯 华沙 莫斯科 圣彼得堡 伊斯坦布尔 开罗
卡萨布兰卡 内罗毕 达累斯萨拉姆 好望角 耶路撒冷 巴格达 德黑兰 新德里 孟买 北京 长安 洛阳 开封 杭州
南京 上海 广州 成都 东京 京都 首尔 曼谷 西贡 河内 马尼拉 雅加达 悉尼 墨尔本 惠灵顿 洛杉矶 纽约
波士顿 费城 华盛顿 芝加哥 休斯顿 墨西哥城 哈瓦那 利马 圣地亚哥 布宜诺斯艾利斯 里约热内卢 圣保罗
"""
GAZ_WORDS = set(GAZ.split())

VERBS = "说|问道|答道|回答|笑道|喊道|低声|嘟囔|咕哔|喃喃|声明|表示|补充|打断|解释|反问|抱怨|提醒|宣布|叹气"
QUOTE_PAT = re.compile(r"[“\"][^“”\"]{6,120}[”\"]")

def nearest_speaker(text, qpos, qlen, names):
    """引语后/前的最近窗口里找『名字+说』或『说：名字』式说话人。"""
    win_a = text[qpos+qlen: qpos+qlen+28]
    win_b = text[max(0, qpos-30): qpos]
    best = None; bestd = 999
    for m in re.finditer(r"([\u4e00-\u9fa5·]{2,8})(?:(?:先生|女士|小姐|太太|夫人|上校|医生|护士|警司|探长)?)(?:，|,)?(?:" + VERBS + r")", win_a):
        cand = m.group(1)
        cand = re.sub(r"(先生|女士|小姐|太太|夫人|上校|医生|护士|警司|探长)$", "", cand)
        if cand in names and m.start() < bestd:
            best = cand; bestd = m.start()
    if best is None:
        for m in re.finditer(r"([\u4e00-\u9fa5·]{2,8})(?:，|,)?(?:" + VERBS + r")(?:：|:)", win_b):
            cand = m.group(1)
            if cand in names and (win_b and m.start() >= 0):
                if len(win_b) - m.end() < bestd:
                    best = cand; bestd = len(win_b) - m.end()
    return best

def run(path, slug):
    t0 = time.time()
    meta, chapters, toc = X.load_epub(path)
    # 载入 E 档实体（如缺失则回退 A 档）
    ep = os.path.join(BASE, "out", f"xray_{slug}_e.json")
    apath = os.path.join(BASE, "out", f"xray_{slug}_a.json")
    aents = json.load(open(ep if os.path.exists(ep) else apath, encoding="utf-8"))["entities"]
    centers = {e["name"]: e for e in aents if e["type"] in ("per", "loc", "org", "term")}
    names = set(centers)
    # D4 gazetteer：单一长正则（按长度倒序，贪婪取最长）扫正文
    gaz_pat = re.compile("|".join(sorted(GAZ_WORDS, key=len, reverse=True)))
    gaz_hits = Counter()
    per_ch = defaultdict(Counter)   # 章节段 -> 实体计数（共现与脉络用）
    paras_ctx = []                  # (ci, text)
    for ch in chapters:
        ci = ch["idx"]
        for text in ch["paras"]:
            paras_ctx.append((ci, text))
            for m in gaz_pat.finditer(text):
                gaz_hits[m.group(0)] += 1
    # D1 对白归属
    dlg = defaultdict(list)
    for ci, text in paras_ctx:
        for m in QUOTE_PAT.finditer(text):
            sp = nearest_speaker(text, m.start(), m.end()-m.start(), names)
            if sp:
                if len(dlg[sp]) < 300:
                    dlg[sp].append({"c": ci, "q": m.group(0)[:80]})
    # D3 共现（top60 实体，同段共现）
    top = sorted(centers.values(), key=lambda e: -e["n"])[:120]
    cooc_names = [e["name"] for e in top[:60]]
    topnames = set(cooc_names)
    cooc = Counter()
    for ci, text in paras_ctx:
        present = [w for w in cooc_names if w in text]
        present = present[:8]
        for i in range(len(present)):
            for j in range(i+1, len(present)):
                a, b = present[i], present[j]
                cooc[(a, b)] += 1
        for w in present:
            per_ch[ci][w] += 1
    edges = [{"s": a, "t": b, "w": w} for (a, b), w in cooc.most_common(400)]
    # D2 别名合并（规则）：包含 + 称谓
    alias_groups = []
    used = set()
    for e in sorted(top, key=lambda x: -x["n"]):
        if e["name"] in used or e["type"] != "per":
            continue
        grp = [e["name"]]
        for f in top:
            if f is e or f["name"] in used or f["type"] != "per":
                continue
            if e["name"] in f["name"] or f["name"] in e["name"]:
                grp.append(f["name"]); used.add(f["name"])
        if len(grp) > 1:
            used.add(e["name"])
            alias_groups.append({"main": e["name"], "members": grp})
    # D6 交叉置信：A∩C
    try:
        cents = json.load(open(os.path.join(BASE, "out", f"xray_{slug}_c.json"), encoding="utf-8"))["entities"]
        cnames = {x["name"] for x in cents if x["type"] in ("per", "loc", "org", "term")}
        both = sum(1 for e in aents if e["type"] in ("per", "loc", "org", "term") and e["name"] in cnames)
        aonly = sum(1 for e in aents if e["type"] in ("per", "loc", "org", "term") and e["name"] not in cnames)
    except FileNotFoundError:
        both = aonly = -1
    # gazetteer 对 loc 榜的增量
    new_locs = [(g, c) for g, c in gaz_hits.most_common() if c >= max(3, min(20, 3*max(1, sum(len(t) for _, t in paras_ctx)//500000))) and g not in {e['name'] for e in aents if e['type']=='loc'}]
    # 章节脉络 segments：按 toc 命中的章分段聚合 top3 实体
    segs = []
    for ch in chapters:
        tt = ch["title"]
        tops = [{"n": w, "t": centers[w]["type"] if w in centers else "term"} for w, _ in per_ch[ch["idx"]].most_common(4)]
        segs.append({"i": ch["idx"], "title": tt or os.path.basename(ch["path"]), "hot": tops})
    rep = {
        "slug": slug, "meta": meta,
        "nodes": [{"name": e["name"], "type": e["type"], "n": e["n"]} for e in top],
        "edges": edges,
        "dialog": [{"name": k, "lines": len(v), "eg": [x["q"] for x in v[:3]]} for k, v in sorted(dlg.items(), key=lambda kv: -len(kv[1]))[:40]],
        "aliases": alias_groups[:40],
        "gaz_new_locs": new_locs[:40],
        "d6": {"both": both, "aonly": aonly},
        "segments": segs[:120],
        "secs": round(time.time()-t0, 1),
    }
    json.dump(rep, open(os.path.join(BASE, "out", f"d_report_{slug}.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print(f"[{slug}] nodes={len(top)} edges={len(edges)} speakers={len(dlg)} aliasGroups={len(alias_groups)} "
          f"gazNewLoc={len(new_locs)} D6 both/aonly={both}/{aonly} {rep['secs']}s", flush=True)
    print("  top speakers:", [(d["name"], d["lines"]) for d in rep["dialog"][:10]], flush=True)
    print("  alias sample:", [g["main"] + "<-" + ",".join(g["members"][1:3]) for g in rep["aliases"][:6]], flush=True)
    print("  gaz new locs:", new_locs[:15], flush=True)

for path, slug in [
    ("C:/Users/chist/Downloads/人类简史  从动物到上帝 = Sapiens A Br_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "sapiens"),
    ("C:/Users/chist/Downloads/阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "agatha85"),
]:
    run(path, slug)
