# -*- coding: utf-8 -*-
"""一次性生成器（跑完即删）：把预研脚本里**实测验证过**的词表机械导出成 APK 资产。

为什么不让手抄：X-Ray 词表的每一条都在预研 GT 里担着数（简史 地名 23/23、小说术语噪声 7/40→0/40），
手抄错一字就会让批1e 的 golden 用例莫名其妙地红，还查不出来。这里只做「读常量 → 去重 → 一行一词写盘」。

来源映射（设计书 §5 的 7 张表）：
  xray_extract.py  STOP_CHARS/CUTOFF/STOP_WORDS -> func_words.txt      停用虚词（n-gram 首尾过滤）
                   STOPNOUN(e)+GENERIC(c)        -> common_nouns.txt    常用名词（含裸称谓/亲属/日常）
                   TITLES(e)                     -> titles.txt          称谓词表
                   SURNAME+COMPOUND_SURNAME      -> surnames.txt        姓氏表（1 字单姓 / >1 字复姓）
                   LOC_SUFFIX / ORG_SUFFIX       -> loc_suffix/org_suffix.txt
                   STOP_EN(c)                    -> stop_en.txt         英文虚词
                   GAZ(d)                        -> gazetteer.txt       地名词典（一期种子）
"""
import ast
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.abspath(os.path.join(HERE, "..", ".."))  # 仓库根（脚本住在 tools/xray/）
SRC = os.path.join(BASE, "docs", "预研", "xray-全书索引", "code")
OUT = os.path.join(BASE, "assets", "xray", "dicts")
os.makedirs(OUT, exist_ok=True)

# ---- 1) xray_extract.py 可安全 import（有 __main__ 门）----
sys.dont_write_bytecode = True  # 别在预研目录里落 __pycache__（那是别人的归档目录）
sys.path.insert(0, SRC)
import xray_extract as X  # noqa: E402


def literals_from_py(path, names):
    """ast 静态取顶层赋值里的字符串集合（脚本本体没有 __main__ 门，不能 import）。"""
    tree = ast.parse(io.open(path, encoding="utf-8").read())
    found = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for tgt in node.targets:
            if isinstance(tgt, ast.Name) and tgt.id in names:
                found[tgt.id] = collect(node.value)
    missing = [n for n in names if n not in found]
    if missing:
        raise SystemExit("ANCHOR-MISS %s in %s" % (missing, os.path.basename(path)))
    return found


def collect(node, mode="auto"):
    """mode: 'chars' → 字符串按**单字**展开；'words' → 按空白切词；'one' → 整串当一个词。

    三种都必须显式处理，否则会把 `set("的了是…")` 这种「字符集字面量」误当成一个词，
    也会把 GAZ 那串多行空格分隔的地名误当成一个字表——两者都会静默毁掉词表语义。
    """
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        if mode == "chars":
            return set(node.value)
        if mode == "one":
            return {node.value}
        return set(node.value.split())  # auto：多行/空格分隔串按词切
    if isinstance(node, (ast.Set, ast.List, ast.Tuple)):
        out = set()
        for el in node.elts:
            out |= collect(el, "one")  # 集合字面量的元素本身就是词
        return out
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return collect(node.left, mode) | collect(node.right, mode)
    if isinstance(node, ast.Call):
        fname = getattr(node.func, "id", None)
        if fname == "set" and node.args:
            return collect(node.args[0], "chars")  # set("字面串") = 单字集
        attr = getattr(node.func, "attr", None)
        if attr == "replace" and len(node.args) == 2:  # "...".replace(a, b)
            base = collect(node.func.value, "chars")
            a, b = node.args[0].value, node.args[1].value
            if b == "":
                return {w for w in base if w != a}
            return {w.replace(a, b) for w in base}
        raise SystemExit("unsupported Call: %s" % ast.dump(node)[:80])
    raise SystemExit("unsupported node: %s" % type(node).__name__)


e = literals_from_py(os.path.join(SRC, "e_tier.py"), {"TITLES", "STOPNOUN"})
c = literals_from_py(os.path.join(SRC, "c_tier.py"), {"STOP_EN", "GENERIC"})
d = literals_from_py(os.path.join(SRC, "d_tier.py"), {"GAZ"})

tables = {
    "func_words.txt": sorted(set(X.STOP_CHARS) | set(X.CUTOFF) | set(X.STOP_WORDS)),
    "common_nouns.txt": sorted(e["STOPNOUN"] | c["GENERIC"]),
    "titles.txt": sorted(e["TITLES"]),
    # 复姓整体匹配，单姓按字；同表两形态由 loader 按长度分流（设计书 §4 通道 1）
    "surnames.txt": sorted(set(X.SURNAME) | set(X.COMPOUND_SURNAME)),
    "loc_suffix.txt": sorted(set(X.LOC_SUFFIX)),
    "org_suffix.txt": sorted(set(X.ORG_SUFFIX)),
    "stop_en.txt": sorted(c["STOP_EN"]),
    # 地名词典：预研 D4 实测口径（简史 地名 23/23 就是这张种子表跑出来的）
    "gazetteer.txt": sorted(d["GAZ"], key=lambda w: (-len(w), w)),
}

notes = {
    "_default": "# 一期种子表：由 tools/xray/gen_asset_dicts.py 从 docs/预研/xray-全书索引/code 的**实测常量**机械导出。\n"
    "# 规模按预研验证过的量（非设计书 §5 的生产目标规模）；扩充是**纯数据动作**——只加行，不改代码与表结构。\n",
    "gazetteer.txt": "# 地名词典·一期种子＝预研 D4 实测表（d_tier.py 的 GAZ，简史 地名 23/23 就是它跑出来的）。\n"
    "# 设计书 §5 生产目标 3~5 万条（行政区划表优先；若换 GeoNames 需在关于页 CC-BY 署名——待产品拍板）。\n",
    "surnames.txt": "# 单字=单姓；多字=复姓（整体匹配）。含预研同源的百家姓裁剪表 + 常见复姓。\n",
    "titles.txt": "# 称谓词表：人名通道 / 组合名路由 / 别名合并 三用（设计书 §4）。\n",
    "common_nouns.txt": "# 常用名词表——**含裸称谓/亲属/日常名词**：小说术语噪声 7/40→0/40 的那一刀靠它（设计书 §4 后处理）。\n",
    "func_words.txt": "# 停用虚词（虚字 + 虚词合并一表）：n-gram 首尾过滤用（设计书 §4 通道 2）。\n",
}

summary = []
for name, words in tables.items():
    words = [w for w in words if w and w.strip()]
    assert len(words) > 0, name
    assert len(set(words)) == len(words), "dup in " + name
    with io.open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(notes["_default"])
        f.write(notes.get(name, ""))
        f.write("\n".join(words) + "\n")
    summary.append("%s=%d" % (name.replace(".txt", ""), len(words)))

sys.stdout.write("OK " + " ".join(summary) + "\n")
