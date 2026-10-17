/* ================= 记账年度分享长图（G1 #2 · 预览＋复制文字版＋保存图片） ================= */
function yrData(){const y=String(yearSel),all=L.txns.filter(t=>t.d.slice(0,4)===y&&t.bk===curBook);
 const exp=sumExp(all),inc=sumInc(all),cnt=all.filter(t=>['expense','income'].includes(t.kind)).length;
 const actDays=new Set(all.filter(t=>t.kind==='expense').map(t=>t.d)).size;
 const big=all.filter(t=>t.kind==='expense').sort((a,b)=>b.amt-a.amt)[0];
 const cs={};for(const t of all){if(t.kind==='expense')cs[t.cat]=(cs[t.cat]||0)+t.amt;else if(t.kind==='refund')cs[t.cat]=(cs[t.cat]||0)-t.amt}
 const rank=Object.entries(cs).filter(([,v])=>v>0).sort((a,b)=>b[1]-a[1]).slice(0,5);
 const mb=Array.from({length:12},(_,i)=>({m:i+1,e:sumExp(all.filter(t=>+t.d.slice(5,7)===i+1))}));
 return {y:y,exp:exp,inc:inc,cnt:cnt,actDays:actDays,big:big,rank:rank,mb:mb}}
function yrShareRender(){const d=yrData(),mx=Math.max(1,...d.mb.map(b=>b.e)),net=d.inc-d.exp;
 $('#yshImg').innerHTML=`<div class="grad text-white p-5">
  <div class="text-[11px] opacity-85">LifeHarness · 本地账本</div>
  <div class="text-lg font-black mt-1 leading-6">${d.y} 年收支总结</div>
  <div class="text-[10.5px] opacity-85 mt-1">${d.cnt} 笔流水 · 记账 ${d.actDays} 天 · 日均 ${AMT(d.exp/365)}</div>
  <div class="mt-3 flex items-end gap-1.5"><span class="text-4xl font-black leading-none">${AMT(d.exp)}</span><span class="text-sm font-bold opacity-85 pb-0.5">全年支出</span></div>
  <div class="mt-4 grid grid-cols-3 gap-2 text-center">
   ${[['全年收入',AMT(d.inc)],['全年结余',AMT(net)],['最大单笔',d.big?AMT(d.big.amt):'—']].map(t=>`<div class="rounded-2xl bg-white/15 py-2"><b class="text-[12px] block">${t[1]}</b><span class="text-[9px] opacity-85">${t[0]}</span></div>`).join('')}</div></div>
 <div class="p-5 bg-white dark:bg-slate-900">
  <div class="text-[11px] font-black text-slate-500">月度支出</div>
  <div class="mt-2 flex items-end gap-1" style="height:74px">${d.mb.map(b=>`<div class="flex-1 flex flex-col justify-end items-center"><i class="w-full max-w-[10px] rounded-t-sm ${b.e>0?'bg-rose-400':'bg-slate-200 dark:bg-slate-700'}" style="height:${b.e>0?Math.max(3,Math.round(b.e/mx*62)):2}px"></i></div>`).join('')}</div>
  <div class="mt-1 flex gap-1 text-[8px] text-slate-400">${d.mb.map(b=>`<span class="flex-1 text-center">${b.m}</span>`).join('')}</div>
  <div class="text-[11px] font-black text-slate-500 mt-4">年度分类 Top ${d.rank.length}</div>
  ${d.rank.map(([id,v],i)=>{const c=lcat(id);return `<div class="flex items-center gap-2 py-1.5 text-[12px] border-b border-slate-100 dark:border-slate-800">
    <b class="w-4 text-slate-400">${i+1}</b><span class="fin-ico !w-6 !h-6 !rounded-lg" style="background:${c.c}1a;color:${c.c}">${svgIco(c.i,'w-3.5 h-3.5')}</span>
    <span class="flex-1 min-w-0">${c.n}</span><b class="shrink-0">${AMT(v)}</b></div>`}).join('')||'<div class="py-1.5 text-[12px] text-slate-400">本年暂无支出</div>'}
  ${d.big?`<div class="mt-3 rounded-2xl bg-slate-100 dark:bg-slate-800 p-3 text-[12px] flex items-center gap-2"><span class="flex-1 min-w-0">最大单笔 · ${d.big.d} ${d.big.n||lcatN(d.big.cat)}</span><b class="text-rose-400">${AMT(d.big.amt)}</b></div>`:''}
  <div class="mt-4 pt-1 flex items-center gap-2 text-[9.5px] text-slate-400"><span class="flex-1 h-px bg-slate-200 dark:bg-slate-800"></span>数据仅存本机<span class="flex-1 h-px bg-slate-200 dark:bg-slate-800"></span></div></div>`}
function yrShareOpen(){yrShareRender();openSheet('sheetYearShare')}
function yrShareText(){const d=yrData();
 return [d.y+' 年收支总结','全年支出 '+AMT(d.exp)+' · 收入 '+AMT(d.inc)+' · 结余 '+AMT(d.inc-d.exp),
  d.cnt+' 笔流水 · 记账 '+d.actDays+' 天',d.big?('最大单笔 '+d.big.d+' '+(d.big.n||lcatN(d.big.cat))+' '+AMT(d.big.amt)):'',
  '','〔年度分类 Top〕'].concat(d.rank.map(([id,v])=>lcatN(id)+'：'+AMT(v))).filter(s=>s!=='').join('\n')}
function yrShareCopy(){const t=yrShareText();
 if(navigator.clipboard&&navigator.clipboard.writeText)navigator.clipboard.writeText(t).then(()=>toast('文字版已复制'),()=>toast('复制失败 · 可在预览里长按选择'));
 else toast('当前浏览器不支持剪贴板')}
function yrShareSave(){toast('分享长图已保存：share/'+yearSel+'年记账总结.png')}
