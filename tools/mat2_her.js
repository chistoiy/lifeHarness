const SYMPS=['😊 心情好','😌 平静','⚡ 精力旺','🌀 痛经','🍫 食欲旺','😢 情绪低落','🌡 涨奶','💆 头痛'];
const CYC_LENS=[29,28,30,27,29,28,26,37,29,28,30,28];
const CYC_M={/* 'p'经期 's'点滴 'o'排卵 'f'易孕（2026-10 为预测） */
 '2026-08':{p:[[12,5]],o:[26],f:[[23,7]]},
 '2026-09':{p:[[8,5]],o:[27],f:[[24,7]]},
 '2026-10':{p:[[3,5]],o:[17],f:[[14,5]],pred:1}};
let SYM_HIST=[
 {d:'09-19',ph:'卵泡期',syms:['😌 平静','⚡ 精力旺'],note:'喝了红枣姜茶',tag:['情绪']},
 {d:'09-15',ph:'卵泡期',syms:['🍫 食欲旺'],note:'',tag:['消化']},
 {d:'09-12',ph:'排卵期',syms:['🌡 涨奶','😢 情绪低落'],note:'',tag:['情绪']},
 {d:'09-08',ph:'月经期',flow:'中',syms:['🌀 痛经'],note:'痛经约1h，热敷缓解',tag:['不适']},
 {d:'08-30',ph:'黄体期',syms:['💆 头痛','😴 嗜睡'],note:'',tag:['不适']}];
function cyMark(y,m,d,kind){const mo=CYC_M[y+'-'+String(m).padStart(2,'0')];if(!mo)return false;
 if(kind==='p')return mo.p.some(([s,l])=>d>=s&&d<s+l);
 if(kind==='f')return mo.f.some(([s,l])=>d>=s&&d<s+l);
 if(kind==='o')return mo.o.includes(d);return false;}
function cycleCells(y,m,big){const first=new Date(y,m-1,1).getDay();const days=new Date(y,m,0).getDate();let c='';
 for(let i=0;i<first;i++)c+='<span></span>';
 const pad=big?'py-2.5':'py-1.5';
 for(let d=1;d<=days;d++){let cls='text-slate-500 dark:text-slate-400',tag='',ring='';
  if(cyMark(y,m,d,'p')){cls='bg-rose-100 dark:bg-rose-500/15 text-rose-500 font-extrabold';tag='经期'}
  else if(cyMark(y,m,d,'o')){cls='bg-violet-100 dark:bg-violet-500/15 text-violet-600 dark:text-violet-400 font-extrabold';tag='排卵'}
  else if(cyMark(y,m,d,'f')){cls='bg-teal-50 dark:bg-teal-500/10 text-teal-600 dark:text-teal-400 font-bold';tag='易孕'}
  if(y===2026&&m===9&&d===19)ring=' ring-2 ring-brand-500';
  if(y===2026&&m===9&&d>19&&!tag&&!(d>=8&&d<=12))cls='text-slate-300 dark:text-slate-600';
  const ds=y+'-'+String(m).padStart(2,'0')+'-'+String(d).padStart(2,'0');
  const lbl=big?'<span class="absolute bottom-0 inset-x-0 text-[8px] leading-none opacity-80">'+(tag||'')+'</span>':'';
  c+='<button class="relative '+pad+' rounded-xl text-[11px] '+cls+ring+'" onclick="openCycleDay(\''+ds+'\')">'+d+lbl+'</button>';}
 return c;}
function renderCycle(){$('#cycleCal').innerHTML=cycleCells(2026,9,false);}
let cyYM=[2026,9];
function renderCycleFull(){$('#cyFullLbl').textContent=cyYM[0]+' 年 '+cyYM[1]+' 月';
 $('#cycleCalFull').innerHTML=cycleCells(cyYM[0],cyYM[1],true);
 const fut=cyYM[0]*12+cyYM[1]>2026*12+10;$('#cyNextBtn').style.opacity=fut?'.3':'1';
 $('#cyPredTag').style.display=(cyYM[0]*12+cyYM[1]>=2026*12+10)?'':'none';}
function cyStep(k){const t=cyYM[0]*12+cyYM[1]-1+k;if(t<2026*12+7||t>2026*12+11)return;cyYM=[Math.floor(t/12),t%12+1];renderCycleFull();}
/* —— 她：日记录弹层 —— */
let cySel={date:'',state:'',flow:'',ov:''};
function oneChip(box,el){$$('#'+box+' .chip').forEach(b=>b.classList.remove('chip-on'));el.classList.add('chip-on');}
function getChip(box){const b=$('#'+box+' .chip-on');return b?(b.dataset.v||b.textContent.trim()):'';}
function cyPick(el,grp){if(el.classList.contains('chip-on')){el.classList.remove('chip-on');cySel[grp]='';}else{oneChip(grp==='state'?'cyStateChips':grp==='flow'?'cyFlowChips':'cyOvChips',el);cySel[grp]=el.dataset.v||el.textContent.trim();}}
function openCycleDay(ds){cySel={date:ds,state:'',flow:'',ov:''};$('#cyDayLbl').textContent=ds;$('#cyTemp').value='';$('#cyNote').value='';
 $$('#cyStateChips .chip,#cyFlowChips .chip,#cyOvChips .chip').forEach(b=>b.classList.remove('chip-on'));
 $('#cySymChips').innerHTML=SYMPS.map(s=>`<button class="chip whitespace-nowrap" onclick="this.classList.toggle('chip-on')">${s}</button>`).join('');
 openSheet('sheetCycleDay');}
function saveCycleDay(){const syms=[...$$('#cySymChips .chip-on')].map(b=>b.textContent.trim()),note=$('#cyNote').value.trim(),temp=$('#cyTemp').value;
 const key=cySel.date;if(cySel.state==='p1'){const parts=key.split('-');const mo=parts[0]+'-'+parts[1];CYC_M[mo]=CYC_M[mo]||{p:[],o:[],f:[]};
  CYC_M[mo].p=[[+parts[2],CYC_M[mo].p.length?CYC_M[mo].p[0][1]:5]];renderCycleFull();
  toast('✔ 已标记 '+key+' 为经期第 1 天 · 周期重新预测：旧预测已存档');}
 else if(cySel.state||cySel.flow||syms.length||note||temp){
  if(syms.length||note)SYM_HIST.unshift({d:key.slice(5),ph:'—',syms:syms,note:note,tag:syms.some(s=>s.includes('痛')||s.includes('头痛'))?['不适']:['情绪']});}
 renderSymHist();closeSheet('sheetCycleDay');
 if(cySel.state!=='p1')toast('✔ '+key+' 已保存 · 状态/体温/试纸将参与预测修正');}
function logPeriod(){openCycleDay('2026-09-19');}
function renderSym(){$('#symChips').innerHTML=SYMPS.map(s=>`<button class="chip whitespace-nowrap" onclick="this.classList.toggle('chip-on')">${s}</button>`).join('');}
function saveSym(){const syms=[...$$('#symChips .chip-on')].map(b=>b.textContent.trim()),note=$('#symNote').value.trim();
 if(!syms.length&&!note){toast('先选感受或写点什么');return;}
 SYM_HIST[0]={d:'09-19',ph:'卵泡期',syms:syms,note:note,tag:['情绪']};renderSymHist();$('#symNote').value='';
 $$('#symChips .chip').forEach(b=>b.classList.remove('chip-on'));
 toast('✔ 今日感受已存 · 周期趋势可生成 AI 解读（本地聚合，不上传原始记录）');}
let symFilter='全部';
function renderSymHist(){$('#symFilterChips').innerHTML=['全部','不适','情绪','消化'].map(f=>`<button class="chip whitespace-nowrap ${f===symFilter?'chip-on':''}" onclick="symFilter='${f}';renderSymHist()">${f}</button>`).join('');
 const list=SYM_HIST.filter(x=>symFilter==='全部'||(x.tag||[]).includes(symFilter));
 $('#symHistList').innerHTML=list.map(x=>`<div class="card"><div class="flex items-center justify-between"><b class="text-xs">${x.d}</b><span class="text-[9px] px-2 py-0.5 rounded-full bg-pink-100 text-pink-500 dark:bg-pink-500/15 font-bold">${x.ph}${x.flow?' · 经量'+x.flow:''}</span></div>
  <div class="mt-1.5 flex flex-wrap gap-1.5 text-[10px]">${(x.syms||[]).map(s=>`<span class="px-2 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400">${s}</span>`).join('')||'<span class="text-slate-300">未选感受</span>'}</div>
  ${x.note?`<div class="mt-1.5 text-[11px] text-slate-400">📝 ${x.note}</div>`:''}</div>`).join('')||'<div class="text-center text-slate-400 py-6 text-[11px]">该筛选下暂无记录</div>';}
function renderCycStats(){const mx=40;
 $('#cycBars').innerHTML=CYC_LENS.map((v,i)=>{const h=Math.round(v/mx*100),ab=Math.abs(v-28.4)>7;
  return `<div class="flex-1 flex flex-col items-center gap-1" title="第 ${12-i} 个周期：${v} 天"><span class="text-[7px] ${ab?'text-rose-500 font-bold':'text-slate-300'}">${v}</span><div class="w-full rounded-t ${ab?'bg-rose-400':'grad'}" style="height:${h}%"></div><span class="text-[7px] text-slate-300">${i+1}</span></div>`}).join('');
 $('#flowDist').innerHTML=[['少',3,'bg-rose-200'],['中',7,'bg-rose-400'],['多',4,'bg-rose-500']].map(([k,n,c])=>`<div class="flex items-center gap-2"><span class="w-6 text-slate-400">${k}</span><div class="flex-1 h-2 rounded-full bg-slate-100 dark:bg-slate-800 overflow-hidden"><span class="block h-full ${c} rounded-full" style="width:${n/14*100}%"></span></div><b>${n} 次</b></div>`).join('');
 $('#symTop').innerHTML=[['🌀 痛经',9,64],['😢 情绪低落',7,50],['🌡 涨奶',6,43],['🍫 食欲旺',5,36],['💆 头痛',3,21]].map(([s,n,p])=>`<div class="flex items-center gap-2 text-[11px]"><span class="w-20 text-slate-500 dark:text-slate-400">${s}</span><div class="flex-1 h-1.5 rounded-full bg-slate-100 dark:bg-slate-800 overflow-hidden"><span class="block h-full grad rounded-full" style="width:${p}%"></span></div><span class="text-slate-400">${n}次</span></div>`).join('');}
