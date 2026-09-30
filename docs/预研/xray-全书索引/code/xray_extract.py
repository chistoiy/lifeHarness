# -*- coding: utf-8 -*-
"""
X-Ray 纯离线轻量抽取 demo（独立脚本，不属于项目代码）
抽取核：TOC词 + 中文姓氏/翻译名正则 + 地名/机构后缀 + 英文缩写 + 《》引用 + 词频候选术语
锚点：章序号 + 段序号（对齐现有 QuoteCf 章+段 体系）；键：文件 MD5（对齐 PRD）
输出：out/xray_<slug>.json + out/xray_<slug>.html
"""
import sys, os, re, json, zlib, hashlib, zipfile, posixpath, html as htmllib, time, unicodedata
from collections import Counter, defaultdict

SURNAME = set(
    "王李张刘陈杨黄赵吴周徐孙马朱胡郭何高林罗郑梁谢宋唐许韩冯邓曹彭曾肖田董袁潘于蒋蔡余杜叶程苏魏吕丁任沈姚卢姜崔钟谭陆汪范金石廖贾夏韦付方白邹孟熊秦邱江尹薛闫段雷侯龙史陶黎贺顾毛郝龚邵万钱严覃武戴莫孔向汤欧倪炎查乔庞樊兰殷施陶翼赫伏翟介屠池胥乔艾穆赖萧邝".replace("陶","")
    + "欧阳司马上官诸葛东方独孤南宫慕容皇甫尉迟公孙令狐淳于拓跋完颜文燕强沙岑哈"
)
# 复姓按整体匹配
COMPOUND_SURNAME = ["欧阳","司马","上官","诸葛","东方","独孤","南宫","慕容","皇甫","尉迟","公孙","令狐","淳于","拓跋","完颜"]
STOP_CHARS = set("的了是在和与及就都很更最其此这那有为而不之等着过得到从对上下里他她它们我你您请吗呢吧啊嗯没也才再又只会要能法去来去地得所一二三四五六七八九十百千万某该各每等等作做使让已被把对关于通过根据按照由于因为所以但是如果虽然然而而且然后以及并且或者要么"
                 "说问道看想笑答喊叫告诉走站坐拿放拿点头摇头起身手口头眼脸面前后内外多少这那每样")
CUTOFF = set("个中大型新旧小老男女好坏多少高低前后内外上面下时候问题东西事情人们自己"
             "什么这样那样怎么如何还是就是不是也许可能应该必须需要进行了着过")
STOP_WORDS = {"我们","他们","她们","它们","这个","那个","这些","那些","一个","什么","怎么","为什么","自己","可以","可能","需要","已经","因为","所以","但是","而且","然后","如果","虽然","由于","通过","进行","以及","或者","不是","没有","人们","时候","东西","问题","世界","人类","国家","社会","生活","工作","时间","现在","当时","一些","一切","这样","那样","以上","以下","以上","第一","第二","第三","成为","认为","作为","成为","无法","相当","完全","基本","直接","整个","全部","其中","其他","另外","例如","比如","甚至","只是","还有","之后","之前","以来","一起","一种","有着","显得","感到","发现","知道","相信","希望","开始","结束","继续","完成","形成","成为","出现","存在","认为","使用","利用","受到","得到","取得","达到","满足","控制","变化","发展","过程","方式","方法","能力","力量","作用","影响","结果","原因","条件","水平","程度","部分","整体","系统","结构","功能","状态","情况","情形","方面","方向","位置","空间","范围","数量","质量","标准","要求","需求","资源","环境","背景","基础","本质","意义","价值","目标","任务","计划","方案","措施","制度","体系","机制","模式","类型","种类","形式","内容","材料","数据","信息","知识","技术","工具","设备","设施","产品","商品","市场","经济","政治","文化","历史","科学","艺术","教育","军事","法律","权利","义务","责任","关系","联系","交流","合作","竞争","冲突","战争","和平","安全","风险","机会","挑战","优势","劣势","特点","特征","现象","规律","理论","观点","看法","想法","观念","意识","思想","精神","心理","情感","感觉","体验","经历","记忆","想象","创造","发明","发现","探索","研究","实验","观察","分析","比较","总结","概括","抽象","具体","简单","复杂","困难","容易","重要","主要","次要","基本","普遍","特殊","典型","常见","罕见","真实","虚假","正确","错误","准确","模糊","清晰","明确","肯定","否定","支持","反对","接受","拒绝","选择","决定","判断","评价","评估","测量","计算","统计"}

LOC_SUFFIX = ["省","自治区","市","县","镇","乡","村","岛","半岛","洲","大陆","平原","高原","盆地","山脉","山谷","河","江","湖","海","洋","沙漠","森林","草原","瀑布","峡谷","城堡","庄园","别墅","公馆","宫殿","庙","塔","桥","公园","广场","街","路","巷","大道","车站","机场","港口","码头","学校","医院","监狱","农场","工厂","矿山","王国","帝国","王朝","地区","地带","方向"]
ORG_SUFFIX = ["公司","集团","银行","大学","学院","中学","小学","研究院","研究所","实验室","委员会","理事会","董事会","协会","联盟","组织","机构","基金会","教会","警署","警察局","法院","政府","内阁","参谋部","司令部","总部","办事处","事务所","出版社","报社","杂志社","剧院","宾馆","酒店","俱乐部","球队","军团","部队","师团","旅团","营","连","排","班","车间","科室","部门","事业部","分公司","子公司","厂","场","站","库","局","署","厅"]

def is_cn(ch):
    return "\u4e00" <= ch <= "\u9fff"

def clean_txt(s):
    s = re.sub(r"<[^>]*>", " ", s)
    s = htmllib.unescape(s)
    s = re.sub(r"[\u200b\ufeff\uf000-\uf0ff]", "", s)  # 全角ASCII/零宽
    return s.strip()

def para_split(html_text):
    body = html_text
    body = re.sub(r"(?is)<!doctype[^>]*>", "", body)
    body = re.sub(r"(?s)<!--.*?-->", "", body)
    body = re.sub(r"(?is)<(script|style|pre|code)[^>]*>.*?</\1>", "", body)
    body = re.sub(r"(?i)<br\s*/?>", "\n", body)
    parts = re.split(r"(?i)</(p|h[1-6]|li|div|blockquote|tr)>", body)
    paras = []
    buf = []
    for piece in parts:
        if piece is None:
            continue
        if re.match(r"(?i)^</?(p|h[1-6]|li|div|blockquote|tr)\b", piece) or piece.startswith("</"):
            t = clean_txt("".join(buf))
            if t:
                paras.append(t)
            buf = []
        else:
            buf.append(piece)
    t = clean_txt("".join(buf))
    if t:
        paras.append(t)
    return [p for p in paras if len(re.sub(r"\s","",p)) >= 2]

def load_epub(path):
    z = zipfile.ZipFile(path)
    container = z.read("META-INF/container.xml").decode("utf-8","ignore")
    opf_path = re.search(r'full-path="([^"]+)"', container).group(1)
    opf = z.read(opf_path).decode("utf-8","ignore")
    base = posixpath.dirname(opf_path)
    manifest = {}
    for it in re.findall(r"<item\b[^>]*/?>", opf):
        i = re.search(r'id="([^"]+)"', it); h = re.search(r'href="([^"]+)"', it)
        mt = re.search(r'media-type="([^"]+)"', it)
        if i and h:
            manifest[i.group(1)] = (posixpath.normpath(posixpath.join(base, h.group(1))), mt.group(1) if mt else "")
    spine = [s for s in re.findall(r'<itemref[^>]*idref="([^"]+)"', opf)]
    title_m = re.search(r"<dc:title[^>]*>(.*?)</dc:title>", opf, re.S)
    creator_m = re.search(r"<dc:creator[^>]*>(.*?)</dc:creator>", opf, re.S)
    toc_map = {}
    toc_titles = []
    ncx = [p for p, mt in manifest.values() if mt == "application/x-dtbncx+xml" or p.endswith(".ncx")]
    if ncx:
        try:
            t = z.read(ncx[0]).decode("utf-8","ignore")
            for np_ in re.findall(r"(?s)<navPoint\b.*?</navPoint>", t):
                src = re.search(r'src="([^"#]+)', np_)
                lbl = re.search(r"(?s)<text>(.*?)</text>", np_)
                if src and lbl:
                    p = posixpath.normpath(posixpath.join(base, src.group(1)))
                    txt = clean_txt(lbl.group(1))
                    toc_map.setdefault(p, txt)
                    if txt:
                        toc_titles.append(txt)
        except Exception:
            pass
    meta = {
        "title": clean_txt(title_m.group(1)) if title_m else "",
        "author": clean_txt(creator_m.group(1)) if creator_m else "",
    }
    chapters = []  # (spine_idx, path, title, paras)
    for ci, sid in enumerate(spine):
        if sid not in manifest:
            continue
        p, mt = manifest[sid]
        if mt.startswith("image"):
            continue
        try:
            raw = z.read(p).decode("utf-8", "ignore")
        except KeyError:
            continue
        paras = para_split(raw)
        if not paras:
            continue
        chapters.append({"idx": ci, "path": p, "title": toc_map.get(p, ""), "paras": paras})
    z.close()
    return meta, chapters, toc_titles

def add_hit(hits, name, etype, ci, pi, text, cap=4):
    if len(name) < 2 or len(name) > 24:
        return
    h = hits[(name, etype)]
    h["n"] += 1
    h["chs"].add(ci)
    if len(h["ctx"]) < cap:
        pos = text.find(name)
        s = max(0, pos-30); e = min(len(text), pos+len(name)+40)
        snip = ("…" if s>0 else "") + text[s:e] + ("…" if e<len(text) else "")
        h["ctx"].append({"c": ci, "p": pi, "t": snip})
        if "first" not in h:
            h["first"] = {"c": ci, "p": pi}

def extract(meta, chapters, toc_titles, corpus_chars, term_sample_limit):
    hits = defaultdict(lambda: {"n":0,"chs":set(),"ctx":[]})
    scale = max(1, corpus_chars // 500000)
    MIN = {"per": min(20, 3*scale), "loc": min(20, 3*scale), "org": min(12, 2*scale),
           "abbr": min(10, 3*scale), "term": min(200, 15*scale), "book": 1}
    # --- 人名 ---
    pat_tr = re.compile("[\u4e00-\u9fa5]{1,7}·[\u4e00-\u9fa5]{1,7}(?:·[\u4e00-\u9fa5]{1,7})*")
    pat_abbr = re.compile(r"\b[A-Z][A-Z0-9]{1,7}\b")
    pat_book = re.compile(r"《([\u4e00-\u9fa5A-Za-z0-9·，,！？!?]{1,24})》")
    pat_sur = re.compile("(?:^|[^\u4e00-\u9fa5])([" + "".join(sorted(SURNAME)) + "])([\u4e00-\u9fa5]{1,2})(?![\u4e00-\u9fa5])")
    pat_loc = re.compile(r"[\u4e00-\u9fa5]{1,6}(?:" + "|".join(sorted(LOC_SUFFIX, key=len, reverse=True)) + r")")
    pat_say = re.compile("([" + "".join(sorted(SURNAME)) + r"])([\u4e00-\u9fa5]{1,2})(?=说|道|问|答|笑道|喊道|低声|心想|认为|指出|回答|看着|回答|说道)")
    pat_org = re.compile(r"[\u4e00-\u9fa5]{2,8}(?:" + "|".join(sorted([s for s in ORG_SUFFIX if s not in ("局","署","厅","营","连","排","班","厂","场","站","库","部门","科室")], key=len, reverse=True)) + r")")

    bad_word = lambda w: any(c in STOP_CHARS for c in w)
    term_counts = Counter()
    term_pool = []
    sampled = 0
    for ch in chapters:
        ci = ch["idx"]
        for pi, text in enumerate(ch["paras"]):
            for m in pat_tr.finditer(text):
                full = m.group(0)
                if len(full) >= 3 and not bad_word(full):
                    add_hit(hits, full, "per", ci, pi, text)
                for part in full.split("·"):
                    if len(part) >= 2 and not bad_word(part):
                        add_hit(hits, part, "per", ci, pi, text)
            for m in pat_say.finditer(text):
                name = m.group(1) + m.group(2)
                if name in STOP_WORDS or bad_word(name) or name[1:] in CUTOFF:
                    continue
                add_hit(hits, name, "per", ci, pi, text)
            for m in pat_sur.finditer(text):
                name = m.group(1) + m.group(2)
                if len(name) < 2 or name in STOP_WORDS or bad_word(name):
                    continue
                if name[1:] in CUTOFF:
                    continue
                add_hit(hits, name, "per", ci, pi, text)
            for m in pat_loc.findall(text):
                if m in STOP_WORDS or bad_word(m):
                    continue
                add_hit(hits, m, "loc", ci, pi, text)
            for m in pat_org.findall(text):
                if bad_word(m):
                    continue
                add_hit(hits, m, "org", ci, pi, text)
            for m in pat_abbr.findall(text):
                add_hit(hits, m, "abbr", ci, pi, text)
            for m in pat_book.findall(text):
                add_hit(hits, m, "book", ci, pi, text)
            # 候选术语 n-gram（可采样限量）
            if sampled < term_sample_limit:
                segs = re.split(r"[^\u4e00-\u9fa5]+", text)
                sampled += sum(len(s) for s in segs)
                for seg in segs:
                    L = len(seg)
                    for n in (2,3,4,5):
                        for i in range(L-n+1):
                            g = seg[i:i+n]
                            if g[0] in STOP_CHARS or g[-1] in STOP_CHARS:
                                continue
                            term_counts[g] += 1

    # 术语筛选：频次 + 剔除包含关系 + 目录词加权
    toc_text = "".join(toc_titles)
    cands = [(g,c) for g,c in term_counts.items() if c >= MIN["term"] and g not in STOP_WORDS and not any(ch in g for ch in STOP_CHARS) ]
    cands.sort(key=lambda x: (-len(x[0]), -x[1]))
    kept = set()
    for g,c in cands:
        if any(g in k for k in kept):
            continue
        if any(k in g for k in kept) and c < max(term_counts.get(k,0) for k in kept if k in g)*0.5:
            continue
        kept.add(g)
    for g in kept:
        add_hit(hits, g, "term", -1, -1, "", cap=0)
        h = hits[(g, "term")]
        h["n"] = term_counts[g]
        if g in toc_text:
            h["toc"] = True
    return hits, MIN

def main():
    jobs = [
        ("C:/Users/chist/Downloads/人类简史  从动物到上帝 = Sapiens A Br_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "sapiens"),
        ("C:/Users/chist/Downloads/阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ (z-library.sk, 1lib.sk, z-lib.sk).epub", "agatha85"),
    ]
    outdir = os.path.join(os.path.dirname(__file__), "out")
    for path, slug in jobs:
        t0 = time.time()
        md5 = hashlib.md5(open(path,"rb").read()).hexdigest()
        meta, chapters, toc_titles = load_epub(path)
        corpus_chars = sum(len(re.sub(r"\s","",p)) for ch in chapters for p in ch["paras"])
        print(f"[{slug}] loaded: chapters={len(chapters)} chars={corpus_chars} md5={md5}", flush=True)
        limit = 4_000_000 if corpus_chars > 8_000_000 else corpus_chars + 1  # 大书采样防超时
        hits, MIN = extract(meta, chapters, toc_titles, corpus_chars, limit)
        # 组装
        ents = []
        for (name, etype), h in hits.items():
            if etype == "term":
                pass
            elif h["n"] < MIN[{"per":"per","loc":"loc","org":"org","abbr":"abbr","book":"book"}[etype]]:
                continue
            if etype == "book":
                pass
            ents.append({"name":name,"type":etype,"n":h["n"],"chs":len(h["chs"]),"first":h.get("first"),"ctx":h["ctx"],"toc":h.get("toc",False)})
        order = {"per":0,"loc":1,"org":2,"term":3,"abbr":4,"book":5}
        # 跨类型仲裁：同名多类命中，保留提及数最高的一类
        best = {}
        for e in ents:
            if e["type"] in ("abbr","book"):
                continue
            k = e["name"]
            if k not in best or e["n"] > best[k]["n"]:
                best[k] = e
        ents = [e for e in ents if e["type"] in ("abbr","book") or best.get(e["name"]) is e]
        ents.sort(key=lambda e:(order[e["type"]], -e["n"]))
        data = {
            "book_md5": md5,
            "source_file": os.path.basename(path),
            "meta": meta,
            "stats": {"chapters": len(chapters), "chars": corpus_chars, "terms_sampled_mb": min(corpus_chars, limit)/1e6},
            "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "pipeline": "离线轻量抽取demo v0：TOC词+姓氏人名/翻译名+地名/机构后缀+英文缩写+《》引用+词频候选术语",
            "entities": ents,
            "chapter_index": [{"i":c["idx"],"t":c["title"] or posixpath.basename(c["path"])} for c in chapters],
        }
        jp = os.path.join(outdir, f"xray_{slug}.json")
        json.dump(data, open(jp,"w",encoding="utf-8"), ensure_ascii=False)
        print(f"[{slug}] entities={len(ents)} types=" + str(Counter(e['type'] for e in ents)) + f" {time.time()-t0:.1f}s -> {jp}", flush=True)

if __name__ == "__main__":
    main()
