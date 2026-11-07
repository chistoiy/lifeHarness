# -*- coding: utf-8 -*-
"""三档对照面板：B档(demo频次) vs A档(n-gram+TF-IDF) vs C档(jieba分词+POS)。"""
import json, os

BASE = os.path.join(os.path.dirname(__file__), "out")
PAIRS = []
def slim(book):
    if book is None:
        return None
    b = dict(book)
    byt = {}
    for e in book["entities"]:
        byt.setdefault(e["type"], []).append(e)
    keep = []
    for t, lst in byt.items():
        lst.sort(key=lambda x: -(x.get("score") or x["n"]))
        for e in lst[:200]:
            keep.append({k: v for k, v in e.items() if k != "ctx"})
    b["entities"] = keep
    return b
for slug, label in [("sapiens", "人类简史"), ("agatha85", "阿加莎全集")]:
    b = json.load(open(os.path.join(BASE, f"xray_{slug}.json"), encoding="utf-8"))
    ap = json.load(open(os.path.join(BASE, f"xray_{slug}_a.json"), encoding="utf-8"))
    cp = os.path.join(BASE, f"xray_{slug}_c.json")
    c = json.load(open(cp, encoding="utf-8")) if os.path.exists(cp) else None
    # 每档每类只留前200，控制内联体积（内置浏览器对超大单行脚本会拒绝执行）
    PAIRS.append({"label": label, "b": slim(b), "a": slim(ap), "c": slim(c)})

html = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>X-Ray 三档抽取对照 · demo / n-gram增强 / 分词POS</title>
<style>
:root{--ink:#1d2733;--sub:#5b6b7b;--line:#dfe6ec;--bg:#f4f7f9;--card:#fff;--accent:#3c7f79;--miss:#a1543a;--chip:#e8f1ef}
*{box-sizing:border-box;margin:0;padding:0}
body{font:14px/1.55 "PingFang SC","Microsoft YaHei",system-ui,sans-serif;background:var(--bg);color:var(--ink);max-width:1280px;margin:0 auto;padding:14px}
h1{font-size:17px} .meta{color:var(--sub);font-size:12px;margin-top:2px}
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}
.tab{padding:5px 14px;border:1px solid var(--line);border-radius:16px;background:var(--card);cursor:pointer;font-size:13px;color:var(--sub)}
.tab.on{background:var(--accent);color:#fff;border-color:var(--accent)}
.grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px}
@media (max-width:980px){.grid{grid-template-columns:1fr}}
.col{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:9px 11px;max-height:72vh;overflow:auto}
.col h2{font-size:13px;margin-bottom:2px} .col .hint{color:var(--sub);font-size:11px;margin-bottom:6px}
.item{display:flex;align-items:baseline;gap:6px;padding:3px 6px;border-radius:6px;cursor:pointer;border-left:3px solid transparent}
.item:hover{background:var(--chip)}
.item.hl{outline:1.5px solid var(--accent)}
.item.miss{border-left-color:var(--miss)}
.rk{color:var(--sub);font-size:11px;width:22px;text-align:right}
.nm{font-weight:600;font-size:13px}
.st{margin-left:auto;color:var(--accent);font-size:11px;white-space:nowrap}
.summary{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:8px 12px;font-size:12px;margin-bottom:8px}
.legend{font-size:11px;color:var(--sub);margin:4px 0 8px}
</style></head><body>
<h1>X-Ray 三档抽取对照 · 同素材</h1>
<div class="meta">B档＝现demo（纯频次）｜ A档＝n-gram+边界熵+TF-IDF+称谓通道 ｜ C档＝jieba分词+POS分类（dart_jieba 为同源参考实现）。红边＝该词条在其他两档都不存在；点条目三列联动高亮。</div>
<div class="tabs" id="books"></div>
<div class="tabs" id="types"></div>
<div class="legend">每列按各自分数排序取 Top150；「独有」＝其他两档 Top150 中均无此词。</div>
<div class="summary" id="sum"></div>
<div class="grid" id="grid"></div>
<script>
const P=__DATA__;
let bi=0, ty="per";
const $=s=>document.querySelector(s);
const esc=s=>String(s).replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
const TY=[["per","人名"],["loc","地点"],["org","机构"],["term","术语"],["abbr","缩写"],["book","书名"]];
function pick(book){
  if(!book||!book.entities) return [];
  return book.entities.filter(e=>e.type===ty).sort((x,y)=>(y.score||y.n)-(x.score||x.n)).slice(0,150);
}
function render(){
  const p=P[bi];
  $("#books").innerHTML=P.map((x,i)=>`<div class="tab ${i===bi?'on':''}" onclick="setB(${i})">${x.label}</div>`).join("");
  $("#types").innerHTML=TY.map(([t,n])=>{
    const c=[p.b,p.a,p.c].filter(Boolean).map(x=>x.entities.filter(e=>e.type===t).length).join("/");
    return `<div class="tab ${t===ty?'on':''}" onclick="setT('${t}')">${n} ${c}</div>`;}).join("");
  const B=pick(p.b),A=pick(p.a),C=pick(p.c);
  const sets=[B,A,C].map(l=>new Set(l.map(e=>e.name)));
  const col=(title,hint,list,idx)=>`<div class="col"><h2>${title}</h2><div class="hint">${hint}</div>`+
    list.map((e,i)=>{
      const uniq=[0,1,2].filter(j=>j!==idx).every(j=>!sets[j].has(e.name));
      const extra=e.score?` ${Math.round(e.score)}分${e.toc?"·目":""}`:"";
      return `<div class="item ${uniq?"miss":""}" data-n="${esc(e.name)}" onclick="hl(this.dataset.n)">
      <span class="rk">${i+1}</span><span class="nm">${esc(e.name)}</span>
      <span class="st">${e.n}次${extra}</span></div>`;}).join("")+`</div>`;
  const inter=[...sets[0]].filter(x=>sets[1].has(x)&&sets[2].has(x)).length;
  const cc=p.c?p.c.stats.terms_sampled_mb.toFixed(1)+"M字采样":"未生成";
  $("#sum").innerHTML=`<b>${p.label}</b>｜${TY.find(t=>t[0]===ty)[1]}榜 B ${B.length} / A ${A.length} / C ${C.length}｜三档共有 <b>${inter}</b>｜C档=${cc}`;
  $("#grid").innerHTML=col("B 档 · 纯频次","demo 现状",B,0)+col("A 档 · n-gram增强","TF-IDF×√频次",A,1)+col("C 档 · 分词POS","jieba词性分类+TF-IDF",C,2);
}
function hl(n){document.querySelectorAll(".item").forEach(el=>el.classList.toggle("hl",el.dataset.n===n));}
function setB(i){bi=i;render();} function setT(t){ty=t;render();}
render();
</script></body></html>"""

out = os.path.join(BASE, "xray_compare3.html")
data_js = json.dumps(PAIRS, ensure_ascii=False).replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
open(out, "w", encoding="utf-8").write(html.replace("__DATA__", data_js))
print("compare3 ->", out, os.path.getsize(out), "bytes")
