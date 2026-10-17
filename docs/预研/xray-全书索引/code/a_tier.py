# -*- coding: utf-8 -*-
"""A 档升级验证：在 demo(n-gram) 基础上加三项纯统计增强，输出 A/B 对照。
1) 边界熵过滤：真词的左右邻接字应当多样（分支熵高）；碎片如「兰教」左邻恒为「伊」→ 熵≈0 → 抑制
2) 包含抑制：短 gram 的出现 70%+ 落在更长 gram 内 → 丢短保长
3) 章节 TF-IDF 排序：全书均匀散布的泛词(朋友/大约) idf 低自动沉底
4) 称谓人名通道：「波洛先生/XX教授」→ 归人名
"""
import sys, os, re, json, time, math, hashlib, posixpath
from collections import Counter, defaultdict

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import xray_extract as X

MIN_LEFT_SAMPLE = 40   # 邻接采样上限，控内存

# 与C档同源的停用词表（A档验证用；英文虚词对n-gram通道无意义，只挂中文泛名词）
GENERIC = {"事情","房间","女人","男人","声音","意思","丈夫","妻子","父亲","母亲","姑娘","女孩","孩子",
           "名字","房子","椅子","桌子","门","窗户","电话","大家","眼睛","头发","脸","手","头","心里",
           "笑容","样子","地方","时间","问题","东西","时候","人们","身子","神气","口气","动静",
           "明白","朋友","喜欢"}


def run_a(path, slug):
    t0 = time.time()
    md5 = hashlib.md5(open(path, "rb").read()).hexdigest()
    meta, chapters, toc = X.load_epub(path)
    N = len(chapters)
    chars = sum(len(re.sub(r"\s", "", p)) for ch in chapters for p in ch["paras"])
    scale = max(1, chars // 500000)
    MIN_TERM = min(200, 15 * scale)
    limit = 4_000_000 if chars > 8_000_000 else chars + 1

    # ---- pass1: 全局计数 ----
    counts = Counter()
    sampled = 0
    for ch in chapters:
        for text in ch["paras"]:
            if sampled < limit:
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
    cand = {g for g, c in counts.items() if c >= MIN_TERM and g not in X.STOP_WORDS and g not in GENERIC}
    df = defaultdict(set)
    # 只保留极大候选：若存在更长候选包含它且计数比>=0.7，候选阶段先不删（下面按包含抑制处理）

    # ---- pass2: 对候选收集左右邻接 + 章节df ----
    left = defaultdict(set); right = defaultdict(set)
    sampled = 0
    for ch in chapters:
        ci = ch["idx"]
        if sampled >= limit:
            break
        for text in ch["paras"]:
            segs = re.split(r"[^\u4e00-\u9fa5]+", text)
            sampled += sum(len(s) for s in segs)
            for seg in segs:
                L = len(seg)
                for n in (2, 3, 4, 5):
                    for i in range(L - n + 1):
                        g = seg[i:i+n]
                        if g not in cand:
                            continue
                        df[g].add(ci)
                        if seg[i-1:i]:
                            lset = left[g]
                            if len(lset) < MIN_LEFT_SAMPLE: lset.add(seg[i-1])
                        if i+n < L:
                            rset = right[g]
                            if len(rset) < MIN_LEFT_SAMPLE: rset.add(seg[i+n])
    # 内嵌/碎片抑制：从最长候选向下，若 h ⊃ g 且 counts[h] >= 0.7*counts[g] → 抑制 g（自长保短代价 O(Σh|sub|)）
    suppressed = set()
    for h in sorted(cand, key=len, reverse=True):
        Lh = len(h)
        for n in range(2, Lh):
            for i in range(Lh - n + 1):
                g = h[i:i+n]
                if g in cand and g not in suppressed and counts[h] >= 0.7 * counts[g]:
                    suppressed.add(g)

    def entropy(s):
        if not s: return 0.0
        k = len(s)
        return math.log2(k) if k > 1 else 0.0

    def score(g):
        c = counts[g]
        idf = math.log(1 + N / (len(df[g]) + 1))
        return c ** 0.5 * idf

    terms = []
    for g in cand:
        if g in suppressed:
            continue
        le, re_ = entropy(left[g]), entropy(right[g])
        if le < 1.0 and re_ < 1.0:
            continue   # 两侧邻接都固定 → 碎片
        terms.append({"name": g, "n": counts[g], "df": len(df[g]),
                      "idf": round(idf := math.log(1 + N / (len(df[g]) + 1)), 3),
                      "score": round(score(g), 1), "lvar": le, "rvar": re_,
                      "toc": g in "".join(toc)})
    terms.sort(key=lambda t: -t["score"])

    # ---- 称谓通道人名（复用B档已有per/loc/org通道）----
    hits, MINb = None, None
    # 只重跑一遍完整 extract 取 B 档实体
    hits, MINb = X.extract(meta, chapters, toc, chars, limit)
    bents = []
    for (name, etype), h in hits.items():
        if etype != "term" and h["n"] >= MINb[etype]:
            bents.append({"name": name, "type": etype, "n": h["n"], "score": h["n"]})
    # 跨类型仲裁（同B档逻辑）
    best = {}
    for e in bents:
        if e["type"] in ("abbr", "book"): continue
        k = e["name"]
        if k not in best or e["n"] > best[k]["n"]: best[k] = e
    bents = [e for e in bents if e["type"] in ("abbr", "book") or best.get(e["name"]) is e]

    # 称谓人名
    pat_hon = re.compile(r"([\u4e00-\u9fa5·]{2,6}?)(?=先生|女士|小姐|太太|教授|博士|医生|警司|探长|队长|法官|上校|中校|少校|上尉|船长|管家|伯爵|夫人|少爷|牧师|船长)")
    hon = Counter()
    for ch in chapters:
        for text in ch["paras"]:
            for m in pat_hon.findall(text):
                if len(m) >= 2 and not any(c in X.STOP_CHARS for c in m) and m not in GENERIC:
                    hon[m] += 1
    honorific = [{"name": k, "n": v, "type": "per"} for k, v in hon.most_common(60) if v >= min(20, 3 * scale)]

    result = {
        "slug": slug, "md5": md5,
        "a_terms_top": terms[:40],
        "a_terms_100": [t["name"] for t in terms[:100]],
        "b_terms_top": [e["name"] for e in sorted([x for x in bents if x["type"] == "term"], key=lambda x: -x["n"])[:40]],
        "b_per_top": [e["name"] for e in sorted([x for x in bents if x["type"] == "per"], key=lambda x: -x["n"])[:20]],
        "honorific_per_top": [(h["name"], h["n"]) for h in honorific[:30]],
        "counts": {"cand": len(cand), "kept_terms": len(terms)},
        "secs": round(time.time() - t0, 1),
    }
    print(json.dumps(result, ensure_ascii=False, indent=1))
    # 落盘A档完整术语表
    json.dump(terms, open(os.path.join(BASE, "out", f"a_terms_{slug}.json"), "w", encoding="utf-8"), ensure_ascii=False)

    # ---- A 档完整实体集（与B档同 schema，便于面板对照）----
    a_ents = []
    for t in terms[:400]:
        a_ents.append({"name": t["name"], "type": "term", "n": t["n"], "score": t["score"],
                       "df": t["df"], "toc": t["toc"], "src": "tfidf"})
    honnames = {h["name"] for h in honorific}
    for e in bents:
        if e["type"] == "term":
            continue
        if e["type"] == "per" and e["name"] in honnames:
            continue
        a_ents.append(e)
    for h in honorific:
        a_ents.append({"name": h["name"], "type": "per", "n": h["n"], "score": h["n"] * 1.0, "src": "hon"})
    a_ents = [e for e in a_ents if e["type"] != "term" or e["n"] > 0]
    a_out = {
        "book_md5": md5, "source_file": os.path.basename(path), "meta": meta,
        "stats": {"chapters": N, "chars": chars, "terms_sampled_mb": min(chars, limit) / 1e6},
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "pipeline": "A档：n-gram + 边界熵 + 包含抑制 + 章节TF-IDF + 称谓人名通道",
        "entities": a_ents,
    }
    json.dump(a_out, open(os.path.join(BASE, "out", f"xray_{slug}_a.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print(f"[{slug}] A-tier entities saved: {len(a_ents)}", flush=True)

for path, slug in [
    ("C:/Users/chist/Downloads/人类简史  从动物到上帝 = Sapiens A Br_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "sapiens"),
    ("C:/Users/chist/Downloads/阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "agatha85"),
]:
    print("=" * 30, slug, "=" * 30)
    run_a(path, slug)
