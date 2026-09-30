# -*- coding: utf-8 -*-
"""D 组图谱面板：实体共现网络 + 章节脉络思维导图 + 对白归属 + 别名合并 + 词典新增地名。"""
import json, os

BASE = os.path.join(os.path.dirname(__file__), "out")
REPORTS = []
for slug in ("sapiens", "agatha85"):
    p = os.path.join(BASE, f"d_report_{slug}.json")
    if os.path.exists(p):
        REPORTS.append(json.load(open(p, encoding="utf-8")))

html = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>X-Ray 脉络图谱 · 共现网络与章节导图</title>
<style>
:root{--ink:#1d2733;--sub:#5b6b7b;--line:#dfe6ec;--bg:#f4f7f9;--card:#fff;--accent:#3c7f79;--per:#3c7f79;--loc:#a1543a;--org:#2e6b46;--term:#5b7b9a}
*{box-sizing:border-box;margin:0;padding:0}
body{font:14px/1.55 "PingFang SC","Microsoft YaHei",system-ui,sans-serif;background:var(--bg);color:var(--ink);max-width:1100px;margin:0 auto;padding:14px}
h1{font-size:17px}.meta{color:var(--sub);font-size:12px}
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}
.tab{padding:5px 14px;border:1px solid var(--line);border-radius:16px;background:var(--card);cursor:pointer;font-size:13px;color:var(--sub)}
.tab.on{background:var(--accent);color:#fff;border-color:var(--accent)}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin-bottom:10px}
canvas{width:100%;border-radius:10px;background:#fbfdfd;border:1px solid var(--line);display:block}
.legend{display:flex;gap:12px;font-size:12px;color:var(--sub);margin:6px 0}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:4px;vertical-align:-1px}
.row{display:flex;gap:8px;align-items:baseline;padding:6px 4px;border-bottom:1px dashed var(--line);font-size:13px}
.row b{min-width:90px}
.q{color:var(--sub);font-size:12px}
.grp{display:inline-flex;gap:6px;flex-wrap:wrap;margin:4px 0}
.chip{border-radius:4px;padding:2px 8px;font-size:12px;background:#e8f1ef;color:var(--accent)}
.chip.main{background:var(--accent);color:#fff}
.tt{position:fixed;pointer-events:none;background:#233;color:#fff;font-size:12px;padding:4px 8px;border-radius:6px;display:none;z-index:9}
.segrow{display:flex;gap:10px;padding:5px 0;border-bottom:1px dashed var(--line);font-size:13px;align-items:baseline}
.segrow .t{width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
</style></head><body>
<h1>X-Ray 脉络图谱 · 读者视角的「书地图」</h1>
<div class="meta">数据全部来自离线轻抽取（A档实体集 + D组通道）。网络图＝同段共现；导图＝章节段与热点实体；对白/别名/词典地名验证 D1/D2/D4。</div>
<div class="tabs" id="books"></div>
<div class="tabs" id="views"></div>
<div id="body"></div>
<div class="tt" id="tt"></div>
<script>
const R=__DATA__;
const COL={per:"#3c7f79",loc:"#a1543a",org:"#2e6b46",term:"#5b7b9a"};
const TYNAME={per:"人名",loc:"地点",org:"机构",term:"术语"};
let bi=0, vw="net";
const $=s=>document.querySelector(s);
const esc=s=>String(s).replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
function render(){
 $("#books").innerHTML=R.map((x,i)=>`<div class="tab ${i===bi?'on':''}" onclick="setB(${i})">${esc(x.meta.title||x.slug)}</div>`).join("");
 $("#views").innerHTML=[["net","共现网络"],["mind","章节脉络导图"],["dlg","对白归属"],["ali","别名合并"],["gaz","词典新增地名"]]
  .map(([k,n])=>`<div class="tab ${k===vw?'on':''}" onclick="setV('${k}')">${n}</div>`).join("");
 vw==="net"?net():vw==="mind"?mind():vw==="dlg"?dlg():vw==="ali"?ali():gaz();
}
function tip(e,t){const x=$("#tt");x.style.display="block";x.style.left=e.clientX+12+"px";x.style.top=e.clientY+8+"px";x.textContent=t;}
function net(){
 const d=R[bi];
 if(!window.__ff) window.__ff={per:1,loc:1,org:1,term:1,minn:10};
 const ff=window.__ff;
 $("#body").innerHTML=`<div class="legend">节点大小＝提及次数；连线＝同段共现。悬停查看。`+
  ["per","loc","org","term"].map(t=>`<label><input type="checkbox" ${ff[t]?"checked":""} onchange="tog('${t}')"><i class="dot" style="background:${COL[t]}"></i>${TYNAME[t]}</label>`).join("")+
  `<label>提及≥<input type="number" value="${ff.minn}" style="width:52px" onchange="setMin(this.value)"></label></div><canvas id="cv" width="1060" height="640"></canvas>`;
 const cv=$("#cv"),g=cv.getContext("2d"),W=cv.width,H=cv.height;
 const nodes=d.nodes.filter(n=>ff[n.type]&&n.n>=ff.minn).slice(0,90).map(n=>({name:n.name,type:n.type,n:n.n,x:W/2+(Math.random()-.5)*500,y:H/2+(Math.random()-.5)*350,vx:0,vy:0}));
 const idx={};nodes.forEach((n,i)=>idx[n.name]=i);
 const es=d.edges.filter(e=>idx[e.s]!=null&&idx[e.t]!=null).slice(0,300);
 for(let it=0;it<260;it++){
  for(let i=0;i<nodes.length;i++)for(let j=i+1;j<nodes.length;j++){
   const a=nodes[i],b=nodes[j];let dx=a.x-b.x,dy=a.y-b.y,d2=dx*dx+dy*dy+40;d2=Math.max(d2,600);
   const f=2600/d2;a.vx+=dx*f/Math.sqrt(d2);a.vy+=dy*f/Math.sqrt(d2);b.vx-=dx*f/Math.sqrt(d2);b.vy-=dy*f/Math.sqrt(d2);
  }
  for(const e of es){const a=nodes[idx[e.s]],b=nodes[idx[e.t]];const dx=b.x-a.x,dy=b.y-a.y,d=Math.sqrt(dx*dx+dy*dy)+1;
   const f=(d-130)*0.004;a.vx+=dx*f;a.vy+=dy*f;b.vx-=dx*f;b.vy-=dy*f;}
  for(const n of nodes){n.vx+=(W/2-n.x)*0.002;n.vy+=(H/2-n.y)*0.002;n.x+=Math.max(-6,Math.min(6,n.vx*=0.85));n.y+=Math.max(-6,Math.min(6,n.vy*=0.85));}
 }
 const maxN=Math.max(...nodes.map(n=>n.n));
 g.strokeStyle="rgba(90,110,120,.18)";
 for(const e of es){const a=nodes[idx[e.s]],b=nodes[idx[e.t]];g.lineWidth=Math.min(3,e.w/60+.4);g.beginPath();g.moveTo(a.x,a.y);g.lineTo(b.x,b.y);g.stroke();}
 for(const n of nodes){const r=6+22*Math.sqrt(n.n/maxN);n.r=r;
  g.fillStyle=COL[n.type]||COL.term;g.globalAlpha=.85;g.beginPath();g.arc(n.x,n.y,r,0,7);g.fill();g.globalAlpha=1;
  if(r>11){g.fillStyle="#1d2733";g.font=(r>18?"13px":"11px")+" sans-serif";g.textAlign="center";g.fillText(n.name,n.x,n.y+4);}}
 cv.onmousemove=ev=>{const rc=cv.getBoundingClientRect(),sx=cv.width/rc.width;
  const x=(ev.clientX-rc.left)*sx,y=(ev.clientY-rc.top)*(cv.height/rc.height);
  const h=nodes.find(n=>Math.hypot(n.x-x,n.y-y)<(n.r||8)+2);
  h?tip(ev,`${h.name}｜${TYNAME[h.type]}｜${h.n}次`):$("#tt").style.display="none";};
}
function mind(){
 const d=R[bi],segs=d.segments.slice(0,60);
 $("#body").innerHTML=`<div class="meta">中心＝本书；每行＝章节段（按 TOC 标题回落），右侧热点＝该段高频实体（类型着色）。这就是读者版的「全书脉络」。共 ${d.segments.length} 段，显示前60。</div>`+
  segs.map(s=>`<div class="segrow"><span class="t" title="${esc(s.title)}">${esc(s.title)}</span><span class="grp">`+
   s.hot.map(h=>`<span class="chip" style="background:${COL[h.t]}22;color:${COL[h.t]}">${esc(h.n)} ${h.w||""}</span>`).join("")+`</span></div>`).join("");
}
function dlg(){
 const d=R[bi];
 $("#body").innerHTML=`<div class="card">D1 对白归属：引号段 + 说话动词邻接判定。共归属 ${d.dialog.length} 个角色（示例展示前20，展开看代表台词）。</div>`+
  d.dialog.slice(0,20).map((x,i)=>`<div class="row"><b>${esc(x.name)}</b><span class="chip">${x.lines} 句</span><span class="q">`+
   (i<8?esc((x.eg[0]||"").slice(0,60)):"") + (x.lines>x.eg.length?` 等`:"") + `</span></div>`).join("");
}
function ali(){
 const d=R[bi];
 $("#body").innerHTML=`<div class="card">D2 别名合并候选（规则：名字包含 + 高频同类）。实装时展示为「合并建议」由用户确认，AI 层处理疑难对。组数=${d.aliases.length}</div>`+
  d.aliases.map(a=>`<div class="grp"><span class="chip main">${esc(a.main)}</span>`+a.members.slice(1).map(m=>`<span class="chip">${esc(m)}</span>`).join("")+`</div>`).join("");
}
function gaz(){
 const d=R[bi];
 $("#body").innerHTML=`<div class="card">D4 地名词典（约200词通用现行地名表演示）在 A 档 loc 榜之外新增命中。演示词表未含历史地名/小说虚构地名，实际产品词表扩充后上限更高。</div>`+
  d.gaz_new_locs.map(x=>`<div class="row"><b>${esc(x[0])}</b><span class="chip">${x[1]} 次</span></div>`).join("");
}
function setB(i){bi=i;render();}function setV(v){vw=v;render();}
function tog(t){window.__ff[t]=window.__ff[t]?0:1;if(vw==="net")net();}
function setMin(v){window.__ff.minn=Math.max(1,parseInt(v||"1",10));if(vw==="net")net();}
render();
</script></body></html>"""

out = os.path.join(BASE, "xray_graph.html")
data = json.dumps(REPORTS, ensure_ascii=False).replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
open(out, "w", encoding="utf-8").write(html.replace("__DATA__", data))
print("graph ->", out, os.path.getsize(out), "bytes")
