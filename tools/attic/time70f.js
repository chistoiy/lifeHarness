/* 轮7-2：时间分布改满高底轨+月分桶 · 年档加热力图 · 文案与演示数据说明 */
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const R = [];
function rep(name, a, b) {
  const n = s.split(a).length - 1;
  if (n !== 1) { console.error('MISS/DUP ' + name + ' count=' + n); process.exit(1); }
  s = s.split(a).join(b); R.push(name);
}
const L = a => a.join('\n');

/* ① tsStack 重写：满高底轨 + 段按分钟堆叠 · 支持日/月分桶 */
rep('stack', L([
  "function tsStack(byDay,from,to){const days=[];for(let d=from;d<=to;d++)days.push(d);",
  " const cats=Object.keys(tsAgg(from,to).byCat);",
  " return `<div class=\"flex items-end gap-[2px] h-28\">`+days.map(d=>{const v=(byDay[d]||0);const pct=Math.min(100,v/1440*100);",
  "  const parts=dayBlocks(d).reduce((m,b)=>{const mins=Math.max(0,Math.min(1439,bend(b))-b.s);if(mins)m[b.cat]=(m[b.cat]||0)+mins;return m},{});",
  "  return `<div class=\"flex-1 h-full flex flex-col justify-end items-center gap-0.5\" title=\"9月${d}日 · ${tsHM(v)}\">",
  "   <div class=\"w-full rounded-t relative overflow-hidden bg-slate-100 dark:bg-slate-800\" style=\"height:${Math.max(4,pct)}%\">",
  "    ${cats.filter(c=>parts[c]).map((c,i,a)=>`<div style=\"position:absolute;left:0;right:0;bottom:${a.slice(0,i).reduce((t,x)=>t+(parts[x]||0),0)/Math.max(1,v)*100}%;height:${parts[c]/Math.max(1,v)*100}%;background:${tsColor(c)}\"></div>`).join('')}",
  "   </div><span class=\"text-[7px] text-slate-400\">${d===TODAY?'今':d%5===0?d:''}</span></div>`}).join('')+`</div>`}",
]), L([
  "function tsDayParts(d){return dayBlocks(d).reduce((m,b)=>{const mins=Math.max(0,Math.min(1439,bend(b))-b.s);if(mins)m[b.cat]=(m[b.cat]||0)+mins;return m},{})}",
  "function tsBuckets(mode,from,to){",
  " if(mode!=='y'){const a=[];for(let d=from;d<=to;d++)a.push({label:d===TODAY?'今':(d%5===0||to-from<10?String(d):''),tip:'9月'+d+'日',parts:tsDayParts(d)});return a}",
  " const A=tsAgg(1,30);const months=Array.from({length:12},()=>({}));",
  " Object.keys(A.byCat).forEach(c=>{months[8][c]=A.byCat[c]});",
  " return months.map((p,i)=>({label:(i+1)%3===0?(i+1)+'月':'',tip:(i+1)+'月',parts:p}))}",
  "function tsBarCol(b,cap){const v=Object.values(b.parts).reduce((t,x)=>t+x,0);",
  " const cats=Object.keys(b.parts).sort((x,y)=>b.parts[x]-b.parts[y]);",
  " let acc=0;",
  " return `<div class=\"flex-1 h-full flex flex-col items-center gap-0.5 justify-end\" title=\"${b.tip} · ${tsHM(v)}\">",
  "  <div class=\"w-full rounded-md relative overflow-hidden bg-slate-100 dark:bg-slate-800/80\" style=\"height:100%\">",
  "   ${cats.map(c=>{const h=v?b.parts[c]/cap*100:0;const el=`<div style=\"position:absolute;left:0;right:0;bottom:${acc.toFixed(2)}%;height:${h.toFixed(2)}%;background:${tsColor(c)}\"></div>`;acc+=h;return el}).join('')}",
  "  </div><span class=\"text-[7px] text-slate-400 h-3 leading-3\">${b.label}</span></div>`}",
  "function tsStack(mode,from,to){const bs=tsBuckets(mode,from,to);",
  " const cap=Math.max(1,Math.max(...bs.map(b=>Object.values(b.parts).reduce((t,x)=>t+x,0))),mode==='y'?600:240);",
  " return `<div class=\"flex items-stretch gap-[3px] h-28\">`+bs.map(b=>tsBarCol(b,cap)).join('')+`</div>",
  "  <div class=\"flex justify-between text-[8px] text-slate-400 mt-1\"><span>0</span><span>柱高=满格 ${tsHM(Math.round(cap))}（含未记录）</span></div>`}",
  "function tsHeat(from,to){const A=tsAgg(1,30);const mx=Math.max(1,...Object.values(A.byDay));",
  " let cells='';for(let d=1;d<=30;d++){const v=A.byDay[d]||0;const f=v/mx;",
  "  cells+=`<div class=\"rounded-[3px]\" style=\"aspect-ratio:1;background:rgba(99,102,241,${v?(0.12+f*0.78).toFixed(2):'0.07'})\" title=\"9月${d}日 · ${tsHM(v)}\"></div>`}",
  " for(let k=0;k<(7-(30%7))%7;k++)cells+='<div></div>';",
  " return `<div class=\"grid grid-cols-7 gap-1\">${cells}</div>",
  "  <div class=\"flex items-center justify-end gap-1 text-[8px] text-slate-400 mt-1.5\"><span>少</span>${[0.12,0.3,0.5,0.7,0.9].map(a=>`<i class=\"w-2.5 h-2.5 rounded-[3px]\" style=\"background:rgba(99,102,241,${a})\"></i>`).join('')}<span>多</span></div>`}",
]));

/* ② 调用点：分布卡传模式 · 年档加热力图卡 */
rep('calls', " if(tsSpan!=='d')h+=tsCard('dist','时间分布',tsStack(A.byDay,from,to),`<button class=\"tag-chip\" onclick=\"toast('全部/仅已记录 · 图例筛选（模拟）')\">全部</button>`);",
  " if(tsSpan==='y')h+=tsCard('heat','热力图',tsHeat(from,to));\n if(tsSpan!=='d')h+=tsCard('dist','时间分布',tsStack(tsSpan,from,to),`<button class=\"tag-chip\" onclick=\"toast('全部/仅已记录 · 图例筛选（模拟）')\">全部</button>`);");
rep('cmp-call', "  h+=tsCard('cmp',tsSpan==='y'?'单月时长对比':'单日时长对比',tsArea(tsSpan==='y'?Array.from({length:12},(_,i)=>i===8?total:0):vals,tsSpan==='y'?['1月','6月','12月']:days.map(d=>d+'日'),tsSpan==='y'?'月':'日'));}",
  "  h+=tsCard('cmp',tsSpan==='y'?'单月时长对比':'单日时长对比',tsArea(tsSpan==='y'?Array.from({length:12},(_,i)=>i===8?total:0):vals,tsSpan==='y'?['1月','6月','12月']:days.map(d=>d+'日'),tsSpan==='y'?'月':'日'));}");

/* ③ hero 文案：年档说明演示数据 */
rep('hero', "  <div class=\"mt-2 flex items-center gap-2 text-[10px] flex-wrap\">${tm?`<span class=\"bg-white/20 rounded-full px-2 py-1\">● 计时中 · ${tm.cat} ${tsHM(Math.max(0,nowMin()-tm.s))}</span>`:'<span class=\"bg-white/15 rounded-full px-2 py-1\">无计时中事件</span>'}",
  "  <div class=\"mt-2 flex items-center gap-2 text-[10px] flex-wrap\">${tm?`<span class=\"bg-white/20 rounded-full px-2 py-1\">● 计时中 · ${tm.cat} ${tsHM(Math.max(0,nowMin()-tm.s))}</span>`:'<span class=\"bg-white/15 rounded-full px-2 py-1\">无计时中事件</span>'}${tsSpan==='y'?'<span class=\"bg-white/15 rounded-full px-2 py-1\">原型演示数据仅覆盖 9 月</span>':''}",
);

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
