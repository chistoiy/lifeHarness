# -*- coding: utf-8 -*-
"""把 xray_*.json 装进一个单文件 HTML 面板（仿 X-Ray 主面板：标签页+实体列表+上下文）。"""
import json, os

BASE = os.path.join(os.path.dirname(__file__), "out")
BOOKS = []
for slug in ("sapiens", "agatha85"):
    p = os.path.join(BASE, f"xray_{slug}.json")
    if os.path.exists(p):
        BOOKS.append(json.load(open(p, encoding="utf-8")))

data_js = json.dumps(BOOKS, ensure_ascii=False)

html = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>X-Ray 全书索引 · 离线轻量抽取 Demo</title>
<style>
:root{--ink:#1d2733;--sub:#5b6b7b;--line:#dfe6ec;--bg:#f4f7f9;--card:#fff;--accent:#3c7f79;--chip:#e8f1ef}
*{box-sizing:border-box;margin:0;padding:0}
body{font:14px/1.6 "PingFang SC","Microsoft YaHei",system-ui,sans-serif;background:var(--bg);color:var(--ink);max-width:860px;margin:0 auto;padding:16px}
header{padding:12px 0 4px}
h1{font-size:18px;letter-spacing:.5px}
.meta{color:var(--sub);font-size:12px;margin-top:2px}
.tabs,.booktabs{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}
.tab{padding:5px 14px;border:1px solid var(--line);border-radius:16px;background:var(--card);cursor:pointer;font-size:13px;color:var(--sub)}
.tab.on{background:var(--accent);color:#fff;border-color:var(--accent)}
#search{width:100%;padding:8px 12px;border:1px solid var(--line);border-radius:8px;font-size:14px;background:var(--card);margin-bottom:10px}
.stat{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px;margin-bottom:10px;font-size:13px;color:var(--sub)}
.stat b{color:var(--ink)}
.ent{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 14px;margin-bottom:8px;cursor:pointer}
.ent:hover{border-color:var(--accent)}
.row{display:flex;align-items:baseline;gap:10px}
.name{font-size:15px;font-weight:600}
.n{margin-left:auto;color:var(--accent);font-weight:600;font-size:13px;white-space:nowrap}
.chips{display:flex;gap:6px;flex-wrap:wrap;margin-top:4px}
.chip{background:var(--chip);color:var(--accent);border-radius:4px;padding:1px 8px;font-size:12px}
.chip.warn{background:#f6ece2;color:#9a6b32}
.bar{height:3px;background:var(--line);border-radius:2px;margin-top:6px;overflow:hidden}
.bar i{display:block;height:100%;background:var(--accent)}
.detail{display:none;margin-top:8px;border-top:1px dashed var(--line);padding-top:8px}
.ent.open .detail{display:block}
.ctx{font-size:13px;color:var(--sub);padding:6px 8px;background:var(--bg);border-radius:6px;margin-top:6px}
.ctx b{color:var(--ink)}
.pipe{color:var(--sub);font-size:12px;margin:8px 0 2px}
footer{color:var(--sub);font-size:12px;margin:16px 0 8px}
</style></head>
<body>
<header>
<h1>X-Ray 全书索引 · 纯离线轻量抽取 Demo</h1>
<div class="meta">抽取核：TOC 词 + 姓氏/翻译名正则 + 地名/机构后缀 + 词频候选术语 + 《》引用 · 无任何模型/AI 参与 · 锚点为「章+段」（对齐现有书摘定位体系）</div>
</header>
<div class="booktabs" id="booktabs"></div>
<div id="stat" class="stat"></div>
<div class="tabs" id="tabs"></div>
<input id="search" placeholder="搜索实体 / 上下文（回车过滤）">
<div id="list"></div>
<footer id="foot"></footer>
<script>
const BOOKS = __DATA__;
const TYPES = [["all","全部"],["per","人名"],["loc","地点"],["org","机构"],["term","术语"],["abbr","缩写"],["book","书名"]];
let bi=0, tab="all", q="";
const $=s=>document.querySelector(s);
const esc=s=>s.replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
function chTitle(i){const c=BOOKS[bi].chapter_index.find(x=>x.i===i);return c?c.t:("spine#"+i);}
function render(){
  const b=BOOKS[bi], s=b.stats;
  $("#booktabs").innerHTML=BOOKS.map((x,i)=>`<div class="tab ${i===bi?'on':''}" onclick="setBook(${i})">${esc(x.meta.title||x.source_file.slice(0,20))}</div>`).join("");
  const byt={}; b.entities.forEach(e=>byt[e.type]=(byt[e.type]||0)+1);
  $("#stat").innerHTML=`<b>${esc(b.meta.title)}</b> ${esc(b.meta.author)} ｜ 章节 <b>${s.chapters}</b> ｜ 正文 <b>${(s.chars/10000).toFixed(1)}</b> 万字 ｜ 实体 <b>${b.entities.length}</b>（`+
    TYPES.slice(1).map(([k,n])=>`${n} ${byt[k]||0}`).join(" · ")+`) ｜ 术语抽取采样 <b>${s.terms_sampled_mb.toFixed(1)}</b> 百万字符<br>book_md5 ${b.book_md5}`;
  $("#tabs").innerHTML=TYPES.map(([k,n])=>{const c=k==="all"?b.entities.length:(byt[k]||0);return c?`<div class="tab ${k===tab?'on':''}" onclick="setTab('${k}')">${n} ${c}</div>`:"";}).join("");
  const maxN=Math.max(...b.entities.filter(e=>tab==="all"||e.type===tab).map(e=>e.n),1);
  const items=b.entities.filter(e=>(tab==="all"||e.type===tab)&&(!q||e.name.includes(q)||e.ctx.some(c=>c.t.includes(q)))).slice(0,300);
  $("#list").innerHTML=items.map((e,idx)=>`<div class="ent" onclick="this.classList.toggle('open')">
    <div class="row"><span class="name">${esc(e.name)}</span><span class="n">${e.n} 次</span></div>
    <div class="chips"><span class="chip">${TYPES.find(t=>t[0]===e.type)[1]}</span>
    ${e.first?`<span class="chip">首次 ${esc(chTitle(e.first.c).slice(0,18))} · 段${e.first.p}</span>`:`<span class="chip">词频统计</span>`}
    <span class="chip">跨 ${e.chs} 章</span>${e.toc?'<span class="chip warn">目录词</span>':""}</div>
    <div class="bar"><i style="width:${Math.max(2,Math.round(e.n/maxN*100))}%"></i></div>
    <div class="detail">${e.ctx.map(c=>`<div class="ctx"><b>${esc(chTitle(c.c).slice(0,20))} · 段${c.p}</b> ｜ ${esc(c.t)}</div>`).join("")||"<div class=ctx>（词频候选，无逐处上下文）</div>"}</div>
  </div>`).join("")||`<div class="stat">无匹配实体</div>`;
  $("#foot").textContent=`管线：${b.pipeline} ｜ 生成于 ${b.generated_at} ｜ 演示产物，未接入应用`;
}
function setBook(i){bi=i;render();} function setTab(t){tab=t;render();}
$("#search").addEventListener("input",e=>{q=e.target.value.trim();render();});
render();
</script></body></html>"""

out = os.path.join(BASE, "xray_viewer.html")
open(out, "w", encoding="utf-8").write(html.replace("__DATA__", data_js))
print("viewer ->", out, os.path.getsize(out), "bytes")
