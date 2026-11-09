# -*- coding: utf-8 -*-
"""三档量化评估：对人工标准答案集的召回率 + Top40 噪声率。"""
import json, os

BASE = os.path.dirname(os.path.abspath(__file__))

GT = {
    "sapiens": {
        "loc": {"欧洲","印度","中国","英国","美国","古罗马","西班牙","澳大利亚","美洲","非洲","波斯","希腊","德国","荷兰","中东","南非","东非","东亚","南美","大西洋","亚洲","新西兰","印度尼西亚"},
        "per": {"赫拉利","尤瓦尔","汉谟拉比","科尔特斯","哥伦布","达尔文","拿破仑","亚历山大","查理曼","马克思","伊壁鸠鲁","路德","加尔文","孔子和耶稣"},
        "term": {"智人","尼安德特人","农业革命","认知革命","科学革命","资本主义","人文主义","泛神论","一神论","狩猎采集","想像的秩序","货币","文字","帝国","宗教","部落","物种","演化","生物学","信贷","硬币","驯化","黑猩猩","小麦","种姓"},
    },
    "agatha85": {
        "per": {"波洛","马普尔","黑斯廷斯","贾普","莱蒙","奥利弗","萨特思韦特","汤米","杜芬妮","艾登","伯顿","里奇","巴特尔","杰拉德","阿伦德尔","英格尔索普","艾克罗伊德","卡罗琳","埃莉诺","布拉维"},
        "loc": {"伦敦","圣玛丽米德","高辛顿","达特穆尔","怀克里夫","纳赛尔","开罗","巴格达","叙利亚","印度","西班牙","埃及"},
        "org": {"苏格兰场","白狮子旅馆","圣玛丽米德村卫生所","蓝色列车","东方快车"},
        "term": {"不在场证明","遗嘱","毒药","氰化物","左轮手枪","侦探小说","出版"},
    },
}
NOISE = {  # top40 里判为噪声的显式黑名单（泛词/HTML残留/称谓本身/碎片）
    "common": {"先生","小姐","女士","太太","夫人","医生","护士","警司","爵士","伯爵","教授","博士","船长","上校","管家","牧师","法官","探长","队长","少爷","个人","大约","几乎","任何","确实","究竟","必须","今天","似乎","非常","事情","东西","时候","朋友","喜欢","明白","发生","意思","声音","离开","感到","知道","觉得","问题","有点","很多","一些","这样","那样","我们","他们","她们","自己","房间","女人","男人","黑人","白人","女人"}
}

def topn(book, ty, n=150):
    return [e["name"] for e in sorted([x for x in book["entities"] if x["type"] == ty],
            key=lambda x: -(x.get("score") or x["n"]))[:n]]

rows = []
for slug, label in [("sapiens", "人类简史"), ("agatha85", "阿加莎全集")]:
    tiers = {}
    for suf, name in [("", "B·频次"), ("_a", "A·n-gram增强"), ("_c", "C·分词POS"), ("_e", "E·净化增强")]:
        p = os.path.join(BASE, "out", f"xray_{slug}{suf}.json")
        if os.path.exists(p):
            tiers[name] = json.load(open(p, encoding="utf-8"))
    print("=" * 20, label, "=" * 20)
    for ty, gtset in GT[slug].items():
        line = f"  {ty}: GT={len(gtset)}"
        for name, book in tiers.items():
            t150 = set(topn(book, ty))
            t40 = topn(book, ty, 40)
            hit = len(gtset & t150)
            hit40 = len(gtset & set(t40))
            noise = sum(1 for x in t40 if x in NOISE["common"])
            line += f" | {name}: 召回T150 {hit}/{len(gtset)} 进T40 {hit40} 噪声T40 {noise}/40"
        print(line)
    for name, book in tiers.items():
        print(f"  [{name}] perTop12:", topn(book, "per", 12))
        print(f"  [{name}] termTop12:", topn(book, "term", 12))
