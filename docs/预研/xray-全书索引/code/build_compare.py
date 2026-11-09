# -*- coding: utf-8 -*-
"""A/B 对照面板：同一素材的 B 档(demo纯频次) 与 A 档(TF-IDF+增强) 并排比对。"""
import json, os

BASE = os.path.join(os.path.dirname(__file__), "out")
PAIRS = []
for slug, label in [("sapiens", "人类简史"), ("agatha85", "阿加莎全集")]:
    b = json.load(open(os.path.join(BASE, f"xray_{slug}.json"), encoding="utf-8"))
    a = json.load(open(os.path.join(BASE, f"xray_{slug}_a.json"), encoding="utf-8"))
    PAIRS.append({"label": label, "b": b, "a": a})

html = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>X-Ray 抽取档位对照 · B档(demo) vs A档(TF-IDF增强)</title>
<style>
:root{--ink:#1d2733;--sub:#5b6b7b;--line:#dfe6ec;--bg:#f4f7f9;--card:#fff;--accent:#3c7f79;--new:#2e6b46;--gone:#a1543a;--chip:#e8f1ef}
*{box-sizing:border-box;margin:0;padding:0}
body{font:14px/1.55 "PingFang SC","Microsoft YaHei",system-ui,sans-serif;background:var(--bg);color:var(--ink);max-width:1080px;margin:0 auto;padding:16px}
h1{font-size:18px} .meta{color:var(--sub);font-size:12px;margin-top:2px}
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}
.tab{padding:5px 14px;border:1px solid var(--line);border-radius:16px;background:var(--card);cursor:pointer;font-size:13px;color:var(--sub)}
.tab.on{background:var(--accent);color:#fff;border-color:var(--accent)}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
@media (max-width:760px){.grid{grid-template-columns:1fr}}
.col{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 12px}
.col h2{font-size:14px;margin-bottom:2px}
.col .hint{color:var(--sub);font-size:12px;margin-bottom:8px}
.item{display:flex;align-items:baseline;gap:8px;padding:4px 8px;border-radius:6px;cursor:pointer}
.item:hover{background:var(--chip)}
.item.hl{outline:1.5px solid var(--accent)}
.item.onlyA{border-left:3px solid var(--new)}
.item.onlyB{border-left:3px solid var(--gone)}
.rk{color:var(--sub);font-size:12px;width:26px;text-align:right}
.nm{font-weight:600}
.st{margin-left:auto;color:var(--accent);font-size:12px;white-space:nowrap}
.bar{height:3px;background:var(--line);border-radius:2px;flex:1 1 60px;min-width:40px;max-width:90px}
.bar i{display:block;height:100%;background:var(--accent)}
.legend{display:flex;gap:14px;font-size:12px;color:var(--sub);margin:6px 0 10px}
.dot{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}
.summary{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 14px;font-size:13px;margin-bottom:10px}
</style></head><body>
<h1>X-Ray 抽取档位对照 · 同素材 A/B 并排</h1>
<div class="meta">左列 B 档＝现 demo（纯词频排序）；右列 A 档＝TF-IDF＋边界熵＋包含抑制＋称谓人名通道。绿边＝A 档独有（新增/上浮），红边＝B 档独有（被 A 档挤出）。点任一条，另一列同名条目高亮定位。</div>
<div class="tabs" id="books"></div>
<div class="tabs" id="types"></div>
<div class="legend"><span><i class="dot" style="background:var(--new)"></i>A 独有</span><span><i class="dot" style="background:var(--gone)"></i>B 独有</span><span>Top150 · B按频次 / A按置信分</span></div>
<div class="summary" id="sum"></div>
<div class="grid" id="grid"></div>
<script>
const P = __DATA__;
let bi=0, ty="term";
const $=s=>document.querySelector(s);
const esc=s=>s.replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
const TY=[["term","术语"],["per","人名"],["loc","地点"],["org","机构"],["abbr","缩写"],["book","书名"]];
function lst(book){return book.entities.filter(e=>e.type===ty).sort((x,y)=>y.n-x.n).slice(0,150);}
function lstA(){return P[bi].a.entities.filter(e=>e.type===ty)
  .sort((x,y)=>(y.score||y.n)-(x.score||x.n)).slice(0,150);}
function col(title,hint,list,side){
  const max=Math.max(...list.map(e=>e.n),1);
  const other=new Set((side==="B"?lstA():lst(P[bi].b)).map(e=>e.name));
  return `<div class="col"><h2>${title}</h2><div class="hint">${hint}</div>`+list.map((e,i)=>{
    const only=side==="A"?`onlyA`:"";const cls=other.has(e.name)?"":(side==="A"?"onlyA":"onlyB");
    const extra=e.score?`分${Math.round(e.score)}${e.df?`·df${e.df}`:""}${e.toc?"·目":""}`:"";
    return `<div class="item ${cls}" data-n="${esc(e.name)}" onclick="hl('${esc(e.name).replace(/'/g,"")}')">
      <span class="rk">${i+1}</span><span class="nm">${esc(e.name)}</span>
      <span class="bar"><i style="width:${Math.max(3,Math.round(e.n/max*100))}%"></i></span>
      <span class="st">${e.n}次${extra?` · ${extra}`:""}</span></div>`;}).join("")+`</div>`;
}
function render(){
  $("#books").innerHTML=P.map((x,i)=>`<div class="tab ${i===bi?'on':''}" onclick="setB(${i})">${x.label}</div>`).join("");
  const cnt={}; ["b","a"].forEach(k=>TY.forEach(([t])=>{cnt[k+t]=P[bi][k].entities.filter(e=>e.type===t).length;}));
  $("#types").innerHTML=TY.map(([t,n])=>`<div class="tab ${t===ty?'on':''}" onclick="setT('${t}')">${n} B${cnt["b"+t]||0}/A${cnt["a"+t]||0}</div>`).join("");
  const B=lst(P[bi].b),A=lstA();const sb=new Set(B.map(x=>x.name)),sa=new Set(A.map(x=>x.name));
  const addN=[...sa].filter(x=>!sb.has(x)).length, delN=[...sb].filter(x=>!sa.has(x)).length;
  $("#sum").innerHTML=`<b>${P[bi].label}</b> · ${ty==="term"?"术语":TY.find(t=>t[0]===ty)[1]}榜：B档 ${B.length} 条 / A档 ${A.length} 条 ｜ A 独有 <b style="color:var(--new)">${addN}</b> · B 独有 <b style="color:var(--gone)">${delN}</b> ｜ 重合 ${sa.size-addN}`;
  $("#grid").innerHTML=col("B 档 · 现 demo（按频次）","纯计数，泛词与碎片易霸榜",B,"B")
    +col("A 档 · 增强（按置信分）","TF-IDF×√频次；人名含称谓通道(·=hon)",A,"A");
}
function hl(n){document.querySelectorAll(".item").forEach(el=>el.classList.toggle("hl",el.dataset.n===n));}
function setB(i){bi=i;render();} function setT(t){ty=t;render();}
render();
</script></body></html>"""

out = os.path.join(BASE, "xray_compare.html")
open(out, "w", encoding="utf-8").write(html.replace("__DATA__", json.dumps(PAIRS, ensure_ascii=False)))
print("compare ->", out, os.path.getsize(out), "bytes")
