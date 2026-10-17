# -*- coding: utf-8 -*-
"""E 档：A档实体集 + 四项补验（PMI结合度 / TextRank / 常用词与称谓后缀过滤 / 图节点净化）。
输出 xray_<slug>_e.json（schema 同 A），并打印术语榜前后对照。
"""
import sys, os, re, json, time, math
from collections import Counter, defaultdict

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import xray_extract as X

TITLES = ["先生", "小姐", "女士", "太太", "夫人", "医生", "护士", "警司", "探长", "爵士", "伯爵",
          "教授", "博士", "船长", "上校", "牧师", "法官", "管家", "少爷", "队长", "上尉", "中校", "少校"]
# 常用名词过滤表演示（生产=千级词表，来自词典词性或通用语料）
STOPNOUN = {"朋友", "事情", "声音", "意思", "东西", "时候", "问题", "房间", "女人", "男人", "孩子",
            "姑娘", "名字", "房子", "丈夫", "妻子", "父亲", "母亲", "电话", "眼睛", "头发", "脸",
            "手", "头", "心", "笑容", "样子", "地方", "时间", "大家", "人们", "身子", "口气",
            "神气", "动静", "世界", "人生", "社会", "生活", "工作", "家庭", "关系", "态度",
            "感觉", "想法", "办法", "办注", "好处", "坏处", "开始", "结束", "继续", "机会",
            "世纪", "年代", "时期", "现代", "当代", "远古", "今天", "明天", "昨天", "目前",
            "个人", "非常", "明白", "喜欢", "发生", "离开", "确实", "似乎", "必须", "改变",
            "先生", "小姐", "女士", "太太", "夫人", "医生", "护士", "警司", "探长", "爵士",
            "伯爵", "教授", "博士", "船长", "上校", "牧师", "法官", "管家", "少爷", "队长",
            "年轻人", "案子", "证明", "事实", "调查", "目光", "表情", "火车", "女儿", "女仆"}

def run(path, slug):
    t0 = time.time()
    a = json.load(open(os.path.join(BASE, "out", f"xray_{slug}_a.json"), encoding="utf-8"))
    meta, chapters, toc = X.load_epub(path)
    chars_total = sum(len(re.sub(r"\s", "", p)) for ch in chapters for p in ch["paras"])
    limit = 4_000_000 if chars_total > 8_000_000 else chars_total + 1

    # 重建 gram 计数（与 a_tier 同源 pass1），并留全文版供 PMI
    counts = Counter(); sampled = 0
    for ch in chapters:
        for text in ch["paras"]:
            if sampled >= limit:
                break
            segs = re.split(r"[^\u4e00-\u9fa5]+", text)
            sampled += sum(len(s) for s in segs)
            for seg in segs:
                L = len(seg)
                for n in (2, 3, 4, 5):
                    for i in range(L - n + 1):
                        g = seg[i:i+n]
                        if g[0] in X.STOP_CHARS or g[-1] in X.STOP_CHARS:
                            continue
                        counts[g] += 1
            sampled += 0
        if sampled >= limit:
            break
    total = max(1, sum(counts[g] for g in counts if len(g) == 2) // 2)

    def pmi_min(g):
        """所有切分位置的最低结合度；< 阈值视为松散拼接（碎片/合成短语）"""
        m = 99.0
        for k in range(1, len(g)):
            a_, b_ = g[:k], g[k:]
            ca, cb, cg = counts.get(a_, 0), counts.get(b_, 0), counts.get(g, 0)
            if ca and cb and cg:
                m = min(m, math.log2(cg * total / (ca * cb)))
        return m

    # ---- TextRank（共现图 PageRank，候选=频次top1200 gram）----
    cand = [g for g, _ in counts.most_common(1200)]
    cset = set(cand)
    rank = {g: 1.0 for g in cand}
    nbr = defaultdict(set)
    sampled = 0
    cap_tr = min(limit, 1_500_000)
    for ch in chapters:
        if sampled >= cap_tr:
            break
        for text in ch["paras"]:
            sampled += len(text)
            if sampled >= cap_tr:
                break
            for seg in re.split(r"[^\u4e00-\u9fa5]+", text):
                found = set()
                L = len(seg)
                for n in (2, 3, 4, 5):
                    for i in range(L - n + 1):
                        g = seg[i:i+n]
                        if g in cset:
                            found.add(g)
                fl = list(found)
                for i in range(len(fl)):
                    for j in range(i+1, len(fl)):
                        nbr[fl[i]].add(fl[j]); nbr[fl[j]].add(fl[i])
    for _ in range(20):
        newr = {g: 0.15 for g in cand}
        for g in cand:
            for h in nbr[g]:
                out = len(nbr[h]) or 1
                newr[g] += 0.85 * rank[h] / out
        rank = newr
    tr_max = max(rank.values()) or 1
    # ---- 组装 E 档 ----
    perset = {x["name"] for x in a["entities"] if x["type"] == "per"}
    ents = []
    for e in a["entities"]:
        n_, t_ = e["name"], e["type"]
        if t_ != "term":
            if t_ == "per" and n_ in STOPNOUN:
                continue
            ents.append(e); continue
        # 称谓后缀路由：X夫人且X是已知名人→归人名；裸称谓/头段为常用词→丢弃；其余降权留术语
        tail_title = next((tt for tt in TITLES if n_.endswith(tt) and len(n_) > len(tt)), None)
        if tail_title:
            head = n_[:-len(tail_title)]
            if head in perset:
                e2 = dict(e); e2["type"] = "per"; e2["score"] = e["n"]; e2["src"] = "title-route"
                ents.append(e2)
                continue
            if head in STOPNOUN or len(head) < 2:
                continue
            ents.append({"name": n_, "type": "term", "n": e["n"], "score": (e.get("score") or e["n"]) * 0.4,
                         "df": e.get("df"), "toc": e.get("toc", False), "src": "title-suffix"})
            continue
        if n_ in STOPNOUN:
            continue
        pm = pmi_min(n_)
        tr = rank.get(n_, 0) / tr_max
        score = (e.get("score") or e["n"])
        if len(n_) >= 3 and pm < 0.5:      # 松散拼接碎片
            continue
        e2 = dict(e)
        e2["score"] = round(score * (0.6 + 0.4 * tr) * (1.0 if pm >= 1.5 else 0.7), 1)
        e2["pmi"] = round(pm, 2); e2["tr"] = round(tr, 3)
        ents.append(e2)
    out = dict(a); out["entities"] = ents
    out["pipeline"] = "E档=A档+PMI结合度+TextRank+常用词/称谓后缀过滤"
    op = os.path.join(BASE, "out", f"xray_{slug}_e.json")
    json.dump(out, open(op, "w", encoding="utf-8"), ensure_ascii=False)
    terms = sorted([x for x in ents if x["type"] == "term"], key=lambda x: -x["score"])
    print(f"[{slug}] E档 ents={len(ents)} term={len(terms)} {time.time()-t0:.0f}s", flush=True)
    print("  termTop25:", [t["name"] for t in terms[:25]], flush=True)

for path, slug in [
    ("C:/Users/chist/Downloads/人类简史  从动物到上帝 = Sapiens A Br_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "sapiens"),
    ("C:/Users/chist/Downloads/阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "agatha85"),
]:
    run(path, slug)
