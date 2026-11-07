# -*- coding: utf-8 -*-
"""C 档验证：jieba 分词 + POS 分类（dart_jieba 的参考实现口径）。
输出与 B/A 档同 schema 的 xray_<slug>_c.json，并打印三档对照指标原料。
"""
import sys, os, re, json, time, math
from collections import Counter, defaultdict

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import xray_extract as X
import jieba.posseg as pseg
import logging
jieba_log = logging.getLogger("jieba"); jieba_log.setLevel(logging.ERROR)

TITLE_WORDS = {"先生", "小姐", "女士", "太太", "医生", "护士", "警司", "爵士", "伯爵", "夫人", "少爷",
               "牧师", "船长", "上校", "中校", "少校", "上尉", "法官", "探长", "队长", "管家", "教授", "博士"}
KEEP_FLAGS = {"nr", "nrt", "nrfg", "ns", "nt", "nz", "n", "vn", "eng", "an"}
TYPE_OF = {"nr": "per", "nrt": "per", "nrfg": "per", "ns": "loc", "nt": "org",
           "nz": "term", "n": "term", "vn": "term", "eng": "term", "an": "term"}
pat_book = re.compile(r"《([\u4e00-\u9fa5A-Za-z0-9·，,！？!?]{1,24})》")

# C 档停用词增强：英文虚词 + 中文高频普通名词（生产形态=打包停用词表文件）
STOP_EN = {"the","and","of","to","in","is","at","on","for","with","that","this","it","as","by","be",
           "or","from","are","was","were","not","have","has","had","will","can","you","all","but","if",
           "their","there","they","them","then","than","so","no","he","she","his","her","its","we","us",
           "what","when","where","which","who","how","why","very","just","also","more","most","other"}
GENERIC = {"事情","房间","女人","男人","声音","意思","丈夫","妻子","父亲","母亲","姑娘","女孩","孩子",
           "名字","房子","椅子","桌子","门","窗户","电话","大家","眼睛","头发","脸","手","头","心里",
           "笑容","样子","地方","时间","问题","东西","时候","先生们","人们","身子","神气","口气","动静"}

def stopworded(wl):
    if wl.isascii():
        return wl.lower() in STOP_EN
    return wl in GENERIC

def run_c(path, slug, sample_chars_limit):
    t0 = time.time()
    meta, chapters, toc = X.load_epub(path)
    N = len(chapters)
    chars = sum(len(re.sub(r"\s", "", p)) for ch in chapters for p in ch["paras"])
    scale = max(1, chars // 500000)
    MIN = {"per": min(20, 3 * scale), "loc": min(20, 3 * scale), "org": min(12, 2 * scale),
           "term": min(200, 15 * scale)}
    counts, df = Counter(), defaultdict(set)
    hits = defaultdict(lambda: {"n": 0, "chs": set(), "ctx": [], "first": None})
    bookc = Counter()
    processed = 0
    cut_secs = 0.0
    for ch in chapters:
        ci = ch["idx"]
        if processed >= sample_chars_limit:
            break
        for pi, text in enumerate(ch["paras"]):
            processed += len(text)
            for m in pat_book.finditer(text):
                bookc[m.group(1)] += 1
            t_c = time.time()
            toks = [(w, f) for w, f in pseg.cut(text) if w.strip()]
            cut_secs += time.time() - t_c
            seen_ch = set()
            prev = None
            for w, f in toks:
                wl = w.strip()
                if len(wl) < 2 or f not in KEEP_FLAGS or wl in X.STOP_WORDS or wl in TITLE_WORDS or stopworded(wl):
                    prev = None if f not in ("n", "vn", "nz") else wl
                    continue
                if any(c in X.STOP_CHARS for c in wl):
                    prev = None if f not in ("n", "vn", "nz") else wl
                    continue
                etype = TYPE_OF[f]
                # 人名防伪：须含「·」或首字为常见姓，否则降级为术语候选
                if etype == "per" and ("·" not in wl and wl[0] not in X.SURNAME):
                    etype = "term"
                key = (wl, etype)
                counts[key] += 1
                if ci not in seen_ch:
                    seen_ch.add(ci); df[key].add(ci)
                h = hits[key]
                h["n"] += 1
                h["chs"].add(ci)
                if len(h["ctx"]) < 4:
                    pos = text.find(wl)
                    s = max(0, pos - 30); e = min(len(text), pos + len(wl) + 40)
                    h["ctx"].append({"c": ci, "p": pi, "t": ("…" if s > 0 else "") + text[s:e] + ("…" if e < len(text) else "")})
                    if h["first"] is None:
                        h["first"] = {"c": ci, "p": pi}
                # 名词二元合并（线性+回归 → 线性回归 类多词术语）
                if prev and f in ("n", "vn", "nz", "eng"):
                    bg = prev + wl
                    bk = (bg, "term")
                    counts[bk] += 1
                    df[bk].add(ci)
                prev = wl if f in ("n", "vn", "nz") else None
    toc_text = "".join(toc)
    ents = []
    for (name, etype), c in counts.items():
        if c < MIN.get(etype, 3):
            continue
        h = hits.get((name, etype))
        idf = math.log(1 + N / (len(df[(name, etype)]) + 1))
        ents.append({"name": name, "type": etype, "n": c, "score": round(c ** 0.5 * idf, 1),
                     "df": len(df[(name, etype)]), "first": h["first"] if h else None,
                     "ctx": h["ctx"] if h else [], "toc": name in toc_text})
    for name, c in bookc.items():
        if c >= 1:
            ents.append({"name": name, "type": "book", "n": c, "score": c, "df": None, "first": None, "ctx": [], "toc": False})
    # 跨类型仲裁
    best = {}
    for e in ents:
        if e["type"] in ("abbr", "book"):
            continue
        if e["name"] not in best or e["n"] > best[e["name"]]["n"]:
            best[e["name"]] = e
    ents = [e for e in ents if e["type"] in ("abbr", "book") or best.get(e["name"]) is e]
    out = {"book_md5": "", "source_file": os.path.basename(path), "meta": meta,
           "stats": {"chapters": N, "chars": chars, "terms_sampled_mb": processed / 1e6},
           "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
           "pipeline": "C档：jieba分词+POS分类(n/nr/ns/nt/nz/vn)+名词二元合并+TF-IDF",
           "entities": ents}
    op = os.path.join(BASE, "out", f"xray_{slug}_c.json")
    json.dump(out, open(op, "w", encoding="utf-8"), ensure_ascii=False)
    byt = Counter(e["type"] for e in ents)
    print(f"[{slug}] C-tier: ents={len(ents)} {dict(byt)} chars_processed={processed/1e6:.1f}M "
          f"cut_cpu={cut_secs:.0f}s total={time.time()-t0:.0f}s -> {op}", flush=True)
    for t in ("per", "loc", "org"):
        print("  ", t, [(e["name"], e["n"]) for e in sorted([x for x in ents if x["type"] == t], key=lambda x: -x["n"])[:12]], flush=True)
    print("   term_by_score", [(e["name"], e["n"], e["score"]) for e in sorted([x for x in ents if x["type"] == "term"], key=lambda x: -x["score"])[:25]], flush=True)

for path, slug, lim in [
    ("C:/Users/chist/Downloads/人类简史  从动物到上帝 = Sapiens A Br_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "sapiens", 10**9),
    ("C:/Users/chist/Downloads/阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "agatha85", 5_000_000),
]:
    run_c(path, slug, lim)
