/* —— 喂养分析（C10 · tab换肤 + 7×24时间规律 + 量堆叠 + 筛选） —— */
let bsT='milk',bsSel=[];
const BS7=['09-13','09-14','09-15','09-16','09-17','09-18','09-19'];
const BS_COLOR={milk:'#ec4899',sleep:'#8b5cf6',dia:'#f59e0b',all:'#ec4899'};
const BS_KINDS={milk:['nurse','bmilk','formula','water'],sleep:['sleep'],dia:['diaper'],all:null};
function bsDayLogs(d){const has=ALLLOGS[curBaby][d];
 if(has)return has;
 if(curBaby!==0||+d.slice(8)>=17)return [];
 const i=+d.slice(8)-13,L=[];
 [[7,30],[10,0],[13,30],[17,0],[21,0]].forEach(([hh,mm],j)=>L.push({k:'formula',s:String(hh).padStart(2,'0')+':'+String(mm).padStart(2,'0'),e:'',ml:[120,150,150,130,150][(j+i)%5],rec:'妈妈'}));
 L.push({k:'nurse',s:'14:40',e:'14:55',dur:15,seg:'左8′/右7′',rec:'妈妈'});
 [[8,10,'pee'],[12,40,'mix'],[19,20,'pee']].forEach(([hh,mm,t])=>L.push({k:'diaper',s:String(hh).padStart(2,'0')+':'+String(mm).padStart(2,'0'),e:'',dia:t,color:t==='pee'?'':'金黄',tex:t==='pee'?'':'糊状',vol:t==='pee'?'':'中',rec:'妈妈'}));
 L.push({k:'sleep',s:'13:00',e:'14:20',dur:80,rec:'妈妈'});
 return L;}
function bsInTab(r){const ks=BS_KINDS[bsT];
 if(ks&&!ks.includes(r.k))return false;
 return !bsSel.length||bsSel.includes(r.k);}
function bsTab(t){bsT=t;bsSel=[];$$('.bst').forEach(b=>{const on=b.dataset.t===t;b.classList.toggle('seg-on',on);b.classList.toggle('text-slate-500',!on)});
 const c=BS_COLOR[t];$('#bsClockTag').style.background=c;
 const fb=$('#bsFilterBtn');fb.classList.toggle('hidden',t!=='all');fb.style.borderColor=c;fb.style.color=c;
 renderStats();}
function bsToggleSel(k){const i=bsSel.indexOf(k);i<0?bsSel.push(k):bsSel.splice(i,1);renderStats();}
function bsRow(label,vals,unit,color){return `<div class="flex items-center gap-1 text-[9px]"><span class="w-9 shrink-0 text-slate-400 text-right pr-1">${label}</span>
 ${vals.map((v,i)=>`<span class="flex-1 text-center py-1 rounded-md ${i%2?'bg-slate-50 dark:bg-slate-800/40':''} font-bold ${v? 'text-slate-600 dark:text-slate-300':'text-slate-300 dark:text-slate-600'}">${v||0}${unit}</span>`).join('')}</div>`;}
function renderStats(){const el=$('#bsClock');if(!el)return;const c=BS_COLOR[bsT];
 const days=BS7.map(bsDayLogs);
 let html='<div class="grid" style="grid-template-columns:repeat(7,1fr) 24px">';
 for(let h=0;h<24;h++){
  days.forEach((L,di)=>{const rs=L.filter(r=>bsInTab(r)&&+r.s.slice(0,2)===h);
   const icons=[...new Set(rs.map(icOf))];
   html+=`<span class="h-[15px] flex items-center justify-center gap-[1px] text-[9px] ${di%2?'':'bg-pink-50/50 dark:bg-slate-800/30'}" title="${BS7[di]} ${h}时 · ${rs.length}条">${icons.slice(0,3).join('')}${rs.length>icons.length&&rs.length>2?'<i class="text-[7px] not-italic font-bold" style="color:'+c+'">+</i>':''}</span>`});
  html+=`<span class="text-[7px] text-slate-300 pl-0.5 leading-[15px]">${h%2===0?h:''}</span>`}
 html+='</div><div class="grid mt-1" style="grid-template-columns:repeat(7,1fr) 24px">';
 days.forEach((L,di)=>html+=`<span class="text-center text-[8px] font-bold ${di===6?'':'text-slate-400'}" ${di===6?'style="color:'+c+'"':''}>${BS7[di].slice(5).replace('-','.')}${di===6?' 今天':''}</span>`);
 html+='<span></span></div>';
 el.innerHTML=html;
 const lg=bsT==='all'?EV_BASE.filter(k=>k!=='custom'):BS_KINDS[bsT];
 $('#bsLegend').innerHTML=lg.map(k=>`<span class="flex items-center gap-1">${evDef(k).ic} ${evDef(k).n}</span>`).join('')+(bsT==='dia'?'<span class="flex items-center gap-1"><i class="dot" style="background:#f59e0b"></i>嘘嘘</span><span class="flex items-center gap-1"><i class="dot bg-emerald-500"></i>臭臭</span><span class="flex items-center gap-1"><i class="dot bg-blue-500"></i>嘘嘘+臭臭</span>':'');
 const fb=$('#bsFilterChips');
 if(fb)fb.innerHTML=EV_BASE.filter(k=>k!=='custom').map(k=>`<button class="chip !py-2 ${bsSel.includes(k)?'chip-on':''}" onclick="bsToggleSel('${k}')">${evDef(k).ic} ${evDef(k).n}</button>`).join('');
 const cards=$('#bsCards');if(!cards)return;
 let out='';
 if(bsT==='milk'||bsT==='all'){
  const qin=days.map(L=>L.filter(r=>r.k==='nurse')),qb=days.map(L=>L.filter(r=>r.k==='bmilk'||r.k==='formula'));
  const avgB=Math.round(qb.reduce((a,L)=>a+L.reduce((x,r)=>x+(r.ml||0),0),0)/7);
  out+=`<div class="card !p-3.5"><span class="text-[10px] font-extrabold text-white px-2.5 py-1 rounded-full" style="background:#ec4899">喂奶量</span><span class="text-[9px] text-slate-400 ml-2">统计周期：每日00:00-24:00 · 近7天</span>
   <div class="mt-3 text-[10px] font-extrabold" style="color:#ec4899">▎亲喂母乳</div>
   <div class="mt-1.5 space-y-1">${bsRow('次数',qin.map(a=>a.length),'次','#ec4899')}${bsRow('左侧',qin.map(a=>a.reduce((x,r)=>x+(r.seg&&r.seg.startsWith('左')?+r.seg.match(/左(\d+)/)[1]:Math.round((r.dur||0)/2)),0)),'分钟')}
   ${bsRow('右侧',qin.map(a=>a.reduce((x,r)=>x+(r.seg&&r.seg.includes('右')?+r.seg.match(/右(\d+)/)[1]:Math.round((r.dur||0)/2)),0)),'分钟')}</div>
   <div class="mt-3 text-[10px] font-extrabold" style="color:#ec4899">▎瓶喂（配方奶 + 瓶喂母乳）</div>
   <div class="mt-1.5 space-y-1">${bsRow('次数',qb.map(a=>a.length),'次')}${bsRow('总量',qb.map(a=>a.reduce((x,r)=>x+(r.ml||0),0)),'ml')}</div>
   <div class="relative mt-2 flex items-end justify-between gap-1 h-40 pt-4">
    <span class="absolute left-1/2 -translate-x-1/2 top-0 text-[9px] px-2 py-0.5 rounded-full border bg-white dark:bg-slate-900" style="color:#ec4899;border-color:#ec4899">近7天平均每天 ${avgB}ml</span>
    ${qb.map((a,di)=>`<div class="flex-1 flex flex-col-reverse items-center gap-[3px] h-full justify-start">${a.map(r=>`<span class="w-full max-w-[26px] text-[7px] text-center text-white rounded-md py-[3px] truncate" style="background:${r.k==='formula'?'#f97316':'#ec4899'}" title="${BS7[di]} ${r.s} ${r.ml}ml">${r.ml}</span>`).join('')}<span class="text-[8px] font-bold mt-0.5 ${di===6?'':'text-slate-400'}" ${di===6?'style="color:#ec4899"':''}>${a.reduce((x,r)=>x+(r.ml||0),0)||''}</span></div>`).join('')}
   </div>
   <div class="flex justify-between mt-1">${BS7.map((d,i)=>`<span class="text-[8px] font-bold ${i===6?'':'text-slate-400'}" ${i===6?'style="color:#ec4899"':''}>${d.slice(5).replace('-','.')}</span>`).join('')}</div></div>`;}
 if(bsT==='sleep'||bsT==='all'){
  const sl=days.map(L=>L.filter(r=>r.k==='sleep'));const avgS=Math.round(sl.reduce((a,L)=>a+L.reduce((x,r)=>x+(r.dur||0),0),0)/7*10/60)/10;
  out+=`<div class="card !p-3.5"><span class="text-[10px] font-extrabold text-white px-2.5 py-1 rounded-full" style="background:#8b5cf6">睡眠量</span>
   <div class="mt-2 space-y-1">${bsRow('总次数',sl.map(a=>a.length),'次')}${bsRow('总时长',sl.map(a=>{const m=a.reduce((x,r)=>x+(r.dur||0),0);return m?Math.floor(m/60)+'h'+(m%60?m%60+'′':''):'0'}),'')}</div>
   <div class="relative mt-2 flex items-end gap-1 h-24 pt-4">
    <span class="absolute left-1/2 -translate-x-1/2 top-0 text-[9px] px-2 py-0.5 rounded-full border bg-white dark:bg-slate-900" style="color:#8b5cf6;border-color:#8b5cf6">近7天平均每天 ${Math.floor(avgS)}小时${Math.round(avgS%1*60)}分钟</span>
    ${sl.map((a,di)=>{const m=a.reduce((x,r)=>x+(r.dur||0),0);return `<div class="flex-1 flex flex-col items-center justify-end h-full"><span class="w-full max-w-[22px] rounded-t-md" style="background:#a78bfa;height:${Math.min(100,m/14/60*100)}%"></span><span class="text-[7px] mt-0.5 ${di===6?'font-bold text-violet-500':'text-slate-400'}">${BS7[di].slice(5).replace('-','.')}</span></div>`}).join('')}</div></div>`;}
 if(bsT==='dia'||bsT==='all'){
  const dp=days.map(L=>L.filter(r=>r.k==='diaper'));const avgD=(dp.reduce((a,L)=>a+L.length,0)/7).toFixed(1);
  out+=`<div class="card !p-3.5"><span class="text-[10px] font-extrabold text-white px-2.5 py-1 rounded-full" style="background:#f59e0b">换尿布次数</span>
   <div class="mt-1.5 space-y-1">${bsRow('总次数',dp.map(a=>a.length),'次')}</div>
   <div class="relative mt-2 flex items-end gap-1.5 min-h-32 pt-5">
    <span class="absolute left-1/2 -translate-x-1/2 top-0 text-[9px] px-2 py-0.5 rounded-full border bg-white dark:bg-slate-900" style="color:#f59e0b;border-color:#f59e0b">近7天平均每天 ${avgD}次</span>
    ${dp.map((a,di)=>`<div class="flex-1 flex flex-col-reverse items-center gap-[3px]">${a.map(r=>`<i class="w-3 h-3 rounded-full" style="background:${r.dia==='pee'?'#f59e0b':r.dia==='mix'?'#3b82f6':'#10b981'}"></i>`).join('')}<span class="text-[7px] mt-0.5 ${di===6?'font-bold text-amber-500':'text-slate-400'}">${BS7[di].slice(5).replace('-','.')}</span></div>`).join('')}</div>
   <div class="text-[9px] text-slate-400 mt-1.5"><i class="dot" style="background:#f59e0b"></i>嘘嘘　<i class="dot bg-emerald-500"></i>臭臭　<i class="dot bg-blue-500"></i>嘘嘘+臭臭</div></div>`;}
 const INS={milk:'近7天瓶喂均值稳定，亲喂左侧时长略多于右侧，可交替起始侧平衡泌乳。6月龄前一般无需额外喂水，观察尿量即可。',
  sleep:'昼夜睡眠总量在月龄参考区间内；入睡时间波动 ±40 分钟，建议固定睡前程序（洗澡→抚触→暗光）。',
  dia:'大便颜色与饮食相关，金黄色糊状为母乳便典型表现。若出现砖红色、灰白色或带血丝，请拍照留档并咨询儿科（不构成医疗建议）。',
  all:'喂养-排尿-睡眠链路节奏正常；数据将自动汇入周报（联动 L4），可在「分析与建议」持续追踪。'};
 out+=`<div class="card !p-3.5"><div class="text-[11px] font-extrabold">分析与建议</div>
  <div class="mt-1.5 text-[11px] text-slate-500 dark:text-slate-400 leading-5">${INS[bsT]}</div>
  <div class="text-[9px] text-slate-300 dark:text-slate-600 mt-1.5">规则引擎本地生成 · 不构成医疗建议 · AI 深度解读为 Opt-in（原始记录不出本机）</div></div>`;
 cards.innerHTML=out;}
