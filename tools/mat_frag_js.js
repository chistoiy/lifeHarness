/* ================= 母婴呵护 · 专版（对话 05fb2fde-1cf5-4d7c-a381-5cb3f45a9f7c） ================= */
const CARE_TODAY='09-19';
const CARERS=['妈妈','爸爸','奶奶','月嫂'];
let curCarer='妈妈',curBaby=0;
let BABIES=[
 {n:'团子',sex:'女',b:'2026-01-07',c:'from-sky-400 to-indigo-500',av:'🧸',logs:238},
 {n:'糯米',sex:'男',b:'2025-04-19',c:'from-amber-400 to-orange-500',av:'🐣',logs:96}];
function babyAgeStr(b){const t=new Date('2026-09-19'),d=new Date(b);let mo=(t.getFullYear()-d.getFullYear())*12+t.getMonth()-d.getMonth();let dd=t.getDate()-d.getDate();if(dd<0){mo--;const pm=new Date(t.getFullYear(),t.getMonth(),0).getDate();dd+=pm;}
 return mo>=12?Math.floor(mo/12)+' 岁 '+(mo%12)+' 个月':(mo?mo+' 个月 ':'')+dd+' 天';}
function careLogs(){return ALLLOGS[curBaby][CARE_TODAY];}
let ALLLOGS={0:{'09-19':[
   {at:'14:20',ic:'🤱',kind:'feed',t:'母乳 · 共 14min（左8′/右6′）',min:14,rec:'妈妈',side:'左8′/右6′'},
   {at:'13:05',ic:'💧',kind:'diaper',t:'尿布 · 尿 · 重 240g',g:240,rec:'妈妈'},
   {at:'12:30',ic:'🥣',kind:'feed',t:'配方奶 150ml · 42°C',ml:150,rec:'爸爸'},
   {at:'11:40',ic:'😴',kind:'sleep',t:'睡眠结束 · 1h50min',min:110,rec:'妈妈'},
   {at:'09:15',ic:'💊',kind:'supp',t:'补剂 · 维 D3 400IU',rec:'妈妈'},
   {at:'08:40',ic:'🧸',kind:'play',t:'游戏 · 俯卧时间 8min',min:8,rec:'奶奶'},
   {at:'07:50',ic:'🤱',kind:'feed',t:'母乳 · 12min（左侧）',min:12,rec:'妈妈'},
   {at:'06:30',ic:'💧',kind:'diaper',t:'尿布 · 尿',rec:'妈妈'},
   {at:'02:10',ic:'🥣',kind:'feed',t:'夜奶 · 配方奶 120ml',ml:120,rec:'妈妈'}],
  '09-18':[
   {at:'21:30',ic:'😴',kind:'sleep',t:'入睡 · 夜觉',min:0,rec:'妈妈'},
   {at:'19:40',ic:'🥣',kind:'feed',t:'辅食+配方奶 130ml',ml:130,rec:'奶奶'},
   {at:'17:20',ic:'💩',kind:'diaper',t:'尿布 · 便 · 糊状（布里斯托 6 级）',rec:'爸爸'},
   {at:'14:00',ic:'🤱',kind:'feed',t:'母乳 · 15min',min:15,rec:'妈妈'},
   {at:'10:30',ic:'🧸',kind:'play',t:'游戏 · 爬行练习 12min',min:12,rec:'妈妈'},
   {at:'08:00',ic:'💊',kind:'supp',t:'补剂 · DHA',rec:'妈妈'}],
  '09-17':[
   {at:'20:10',ic:'🥣',kind:'feed',t:'配方奶 150ml',ml:150,rec:'妈妈'},
   {at:'15:40',ic:'💧',kind:'diaper',t:'尿布 · 尿 · 重 210g',g:210,rec:'月嫂'},
   {at:'12:20',ic:'😴',kind:'sleep',t:'午睡结束 · 2h05min',min:125,rec:'妈妈'},
   {at:'09:00',ic:'💊',kind:'supp',t:'补剂 · 维 D3 400IU',rec:'妈妈'},
   {at:'07:30',ic:'🤱',kind:'feed',t:'母乳 · 18min（左9′/右9′）',min:18,rec:'妈妈'}]},
 1:{'09-19':[
   {at:'12:00',ic:'🥣',kind:'feed',t:'配方奶 180ml · 42°C',ml:180,rec:'爸爸'},
   {at:'08:30',ic:'🧸',kind:'play',t:'游戏 · 积木抓握 15min',min:15,rec:'妈妈'}]}};
let babyLogs=ALLLOGS[0][CARE_TODAY];
/* —— 他/她 tab —— */
function careTab(k){[['her','careHer','ctHer'],['baby','careBaby','ctBaby']].forEach(([id,w,b])=>{$('#'+w).classList.toggle('hidden',id!==k);const btn=$('#'+b);btn.className=(id===k?'seg-on ':'flex-1 rounded-lg py-1.5 text-slate-500')+' flex-1 rounded-lg py-1.5';if(id===k)btn.classList.add('font-bold');});}
/* —— 她：周期数据 —— */
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
function saveCycleDay(){const syms=$$('#cySymChips .chip-on').map(b=>b.textContent.trim()),note=$('#cyNote').value.trim(),temp=$('#cyTemp').value;
 const key=cySel.date;if(cySel.state==='p1'){const parts=key.split('-');const mo=parts[0]+'-'+parts[1];CYC_M[mo]=CYC_M[mo]||{p:[],o:[],f:[]};
  CYC_M[mo].p=[[+parts[2],CYC_M[mo].p.length?CYC_M[mo].p[0][1]:5]];renderCycleFull();
  toast('✔ 已标记 '+key+' 为经期第 1 天 · 周期重新预测：旧预测已存档');}
 else if(cySel.state||cySel.flow||syms.length||note||temp){
  if(syms.length||note)SYM_HIST.unshift({d:key.slice(5),ph:'—',syms:syms,note:note,tag:syms.some(s=>s.includes('痛')||s.includes('头痛'))?['不适']:['情绪']});}
 renderSymHist();closeSheet('sheetCycleDay');
 if(cySel.state!=='p1')toast('✔ '+key+' 已保存 · 状态/体温/试纸将参与预测修正');}
function logPeriod(){openCycleDay('2026-09-19');}
function renderSym(){$('#symChips').innerHTML=SYMPS.map(s=>`<button class="chip whitespace-nowrap" onclick="this.classList.toggle('chip-on')">${s}</button>`).join('');}
function saveSym(){const syms=$$('#symChips .chip-on').map(b=>b.textContent.trim()),note=$('#symNote').value.trim();
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
/* —— 宝宝：主页 —— */
function renderBabyHero(){const b=BABIES[curBaby];$('#bhName').textContent='👶 '+b.n;$('#bhAge').textContent=babyAgeStr(b.b);
 $('#bhCarer').textContent='👨‍👩‍👧 '+curCarer+'记录中';
 $('#bhWeek').textContent=curBaby===0?'本周：喂养 46 次 · 尿布 35 片 · 睡眠 13.8h/天 · 体重 P62 ↑':'本周：三餐+奶 5 次 · 自主进食练习 3 次 · 语言爆发期';}
function bnow(){const d=new Date();return String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');}
function recRow(r,i){return `<div class="flex items-center gap-2.5 bg-slate-50 dark:bg-slate-800/60 rounded-xl px-3 py-2 active:scale-[.99] transition" onclick="openRec(CARE_TODAY,${i})"><span class="text-base">${r.ic}</span><div class="flex-1 min-w-0"><b>${r.t}</b><div class="text-[9px] text-slate-400">今天 ${r.at} · 记录人：${r.rec}</div></div><button class="text-[10px] text-rose-400 font-bold shrink-0" onclick="event.stopPropagation();ALLLOGS[${curBaby}]['${CARE_TODAY}'].splice(${i},1);babyLogs=careLogs();renderBabyToday();renderBabyDay();toast('记录已删除')">删除</button></div>`;}
function renderBabyToday(){const el=$('#babyToday');if(!el)return;const logs=careLogs();
 el.innerHTML=logs.slice(0,5).map((r,i)=>recRow(r,i)).join('')||'<div class="text-center text-slate-400 py-4 text-[11px]">今天还没有记录，点上方一键开始</div>';
 const c=$('#babyCount');if(c)c.textContent=logs.length;}
function renderCarerRow(box){$('#'+box).innerHTML=CARERS.map(c=>`<button class="chip ${c===curCarer?'chip-on':''}" data-v="${c}" onclick="oneChip('${box}',this)">${c}</button>`).join('');}
function chipBox(box){return $('#'+box+' .chip-on')?$('#'+box+' .chip-on').textContent.trim():curCarer;}
function pushLog(o){const logs=careLogs();logs.unshift(o);babyLogs=logs;renderBabyToday();renderBabyDay();
 BABIES[curBaby].logs++;}
function qTap(k){
 if(k==='milk'||k==='sleep'){if(ftTimer&&ftKind!==k){toast('请先结束当前计时');return;}if(ftTimer){if(k==='milk'){ftSwap(Math.round((Date.now()-ftT0)/60000));return}endFeed();return;}startFeed(k);return;}
 if(k==='bottle'){renderCarerRow('btCarers');$('#btMl').value='';const last=careLogs().find(r=>r.kind==='feed');
  $('#bottleHint').textContent=last?'距上次喂养（'+last.at+'）约 '+Math.max(5,Math.round((Date.now()/60000)%90))+' 分钟':'今天还没有喂养记录';
  openSheet('sheetBottle');return;}
 if(k==='supp'){renderCarerRow('spCarers');$('#spName').value='';openSheet('sheetSupp');return;}
 if(k==='poop'){ppType('poop');renderCarerRow('ppCarers');$('#ppGram').value='';openSheet('sheetPoop');return;}
 if(k==='play'){renderCarerRow('plCarers');openSheet('sheetPlay');return;}
 if(k==='measure'){openSheet('sheetBabyMeasure');return;}
 if(k==='pee'){pushLog({ic:'💧',t:'尿布 · 尿',at:bnow(),kind:'diaper',rec:curCarer});toast('✔ 已记录');}}
function saveBottle(){const ml=+$('#btMl').value||+getChip('btMlChips')||150,tmp=getChip('btTmpChips')||'42',brand=$('#btBrand').value.trim();
 pushLog({ic:'🥣',t:'配方奶 '+ml+'ml · '+tmp+'°C'+(brand?' · '+brand:''),at:bnow(),kind:'feed',ml:ml,rec:chipBox('btCarers')});
 closeSheet('sheetBottle');toast('✔ 已记录 · 奶量已入今日统计');}
function saveSupp(){const nm=$('#spName').value.trim()||getChip('spNameChips')||'补剂';
 pushLog({ic:'💊',t:'补剂 · '+nm,at:bnow(),kind:'supp',rec:chipBox('spCarers')});
 closeSheet('sheetSupp');toast('✔ 已记录'+($('#spRemind').classList.contains('on')?' · 每日服用提醒已排定':''));}
function savePlay(){const ty=getChip('plTypeChips')||'游戏',mn=getChip('plMinChips')||'10';
 pushLog({ic:'🧸',t:'游戏 · '+ty+' '+mn+'min',at:bnow(),kind:'play',min:+mn,rec:chipBox('plCarers')});
 closeSheet('sheetPlay');toast('✔ 已记录 · 时长将入「时间账本-育儿」（联动 L11）');}
/* 尿布 + 布里斯托 */
const BRISTOL=[['1','硬球状','偏秘'],['2','块状','偏秘'],['3','腊肠裂','正常'],['4','光滑腊肠','最佳'],['5','软块','偏稀'],['6','糊状','偏稀'],['7','水样','警惕']];
let ppKind='poop',ppBristol=3;
function ppType(k){ppKind=k;[['pee','ppT0'],['poop','ppT1'],['mix','ppT2']].forEach(([v,id])=>{const b=$('#'+id);b.className=(v===k?'seg-on ':'flex-1 rounded-lg py-1.5 text-slate-500')+' flex-1 rounded-lg py-1.5';});
 $('#ppBristolWrap').classList.toggle('hidden',k==='pee');renderBristol();}
function renderBristol(){$('#bristolRow').innerHTML=BRISTOL.map(([n,l],i)=>`<button class="py-1.5 rounded-xl text-[10px] font-bold ${i===ppBristol?'grad text-white':'bg-slate-100 dark:bg-slate-800 text-slate-400'}" onclick="ppBristol=${i};renderBristol()">${n}</button>`).join('');
 $('#bristolLbl').textContent=BRISTOL[ppBristol][0]+' 级 · '+BRISTOL[ppBristol][1]+'（'+BRISTOL[ppBristol][2]+'）';}
function savePoop(){const g=$('#ppGram').value;
 const lbl=ppKind==='pee'?'尿':ppKind==='poop'?'便':'便+尿';
 const desc=ppKind==='pee'?'':(ppKind==='poop'?' · '+BRISTOL[ppBristol][1]+'（布里斯托 '+(ppBristol+1)+' 级）':' · 含便 '+BRISTOL[ppBristol][1]);
 pushLog({ic:ppKind==='pee'?'💧':'💩',t:'尿布 · '+lbl+desc+(g?' · 重 '+g+'g':''),at:bnow(),kind:'diaper',g:+g||undefined,rec:chipBox('ppCarers')});
 closeSheet('sheetPoop');toast(ppBristol>=5&&ppKind!=='pee'?'✔ 已记录 · 连续偏稀将温柔提醒就医参考':'✔ 已记录'+(g?' · 称重已关联':''));}
/* 哺乳/睡眠计时（复用悬浮计时条形态） */
let ftTimer=null,ftT0=0,ftKind='',ftSide='左',ftSwapMin=0;
function startFeed(kind){ftKind=kind;ftSide='左';ftSwapMin=0;ftT0=Date.now();ftTimer=setInterval(renderFeedBar,500);renderFeedBar();
 toast(kind==='milk'?'🤱 哺乳计时开始（默认左侧）':'😴 睡眠计时开始 · 界面可继续做别的')}
function ftSwap(min){ftSwapMin=min;ftSide=ftSide==='左'?'右':'左';renderFeedBar();toast('已换边 → '+ftSide+'侧继续计时，分段会记录')}
function renderFeedBar(){const s=Math.floor((Date.now()-ftT0)/1000);const mm=Math.floor(s/60),ss=String(s%60).padStart(2,'0');const bar=$('#feedTimer');bar.classList.remove('hidden');
 bar.innerHTML=ftKind==='milk'?`<span class="text-lg">🤱</span><div class="flex-1 min-w-0"><b class="text-xs">${ftSide}侧哺乳 · 累计 ${mm}:${ss}</b><div class="text-[9px] text-slate-400">换边继续计时，结束时自动生成分段记录</div></div><button class="mini-btn !text-[10px]" onclick="ftSwap(Math.round((Date.now()-ftT0)/60000))">🔄 换边</button><button class="mini-btn !text-[10px] !bg-rose-100 !text-rose-500 dark:!bg-rose-500/15" onclick="endFeed()">■ 结束</button>`
 :`<span class="text-lg">😴</span><div class="flex-1 min-w-0"><b class="text-xs">入睡中 · ${mm}:${ss}</b><div class="text-[9px] text-slate-400">与上次喂养自动关联「吃-睡间隔」</div></div><button class="mini-btn !text-[10px] !bg-mint/15 !text-teal-600" onclick="endFeed()">⏰ 醒了</button>`;}
function endFeed(){if(!ftTimer)return;const s=Math.floor((Date.now()-ftT0)/1000);const mins=Math.max(1,Math.round(s/60));
 if(ftKind==='milk'){const l=ftSwapMin?(ftSide==='左'?ftSwapMin:mins-ftSwapMin):mins,r=mins-l;
  pushLog({ic:'🤱',t:`母乳 · 共 ${mins}min（左${l}′/右${r}′）`,at:bnow(),kind:'feed',min:mins,rec:curCarer});}
 else pushLog({ic:'😴',t:`睡眠 · ${mins>=60?(Math.floor(mins/60)+'h'+(mins%60)+(mins%60?'′':'')+'m'):mins+'min'}`,at:bnow(),kind:'sleep',min:mins,rec:curCarer});
 clearInterval(ftTimer);ftTimer=null;ftKind='';$('#feedTimer').classList.add('hidden');toast('✔ 计时已存 · 今日一览与时长统计已更新');}
/* —— 全天记录（C7） —— */
const BD_KINDS=[['全部',null],['喂养','feed'],['尿布','diaper'],['睡眠','sleep'],['补剂','supp'],['游戏','play'],['测量','measure']];
let bdDate=CARE_TODAY,bdFilter='全部';
function renderBabyDay(){const days=ALLLOGS[curBaby];const keys=Object.keys(days).sort();
 if(!days[bdDate]){const nx=keys[keys.length-1];toast('该日期暂无记录');bdDate=nx;}
 $('#bdLbl').textContent=bdDate+(bdDate===CARE_TODAY?' · 今天':'');
 const list=days[bdDate]||[];$('#bdCnt').textContent='共 '+list.length+' 条记录';
 const ml=list.reduce((a,r)=>a+(r.ml||0),0),sml=list.filter(r=>r.kind==='feed'&&r.min).length,dp=list.filter(r=>r.kind==='diaper').length,sl=list.reduce((a,r)=>a+(r.kind==='sleep'?r.min||0:0),0);
 $('#bdSummary').innerHTML=`<div class="card !py-2"><b class="text-base">${ml}${sml?'+'+sml+'次母乳':''}</b><div class="text-slate-400">奶量ml</div></div>
  <div class="card !py-2"><b class="text-base">${dp}</b><div class="text-slate-400">尿布</div></div>
  <div class="card !py-2"><b class="text-base">${sl>=60?Math.floor(sl/60)+'h'+sl%60+'′':sl+'min'}</b><div class="text-slate-400">睡眠</div></div>
  <div class="card !py-2"><b class="text-base">${list.length}</b><div class="text-slate-400">记录</div></div>`;
 $('#bdFilters').innerHTML=BD_KINDS.map(([k])=>`<button class="chip whitespace-nowrap ${k===bdFilter?'chip-on':''}" onclick="bdFilter='${k}';renderBabyDay()">${k}</button>`).join('');
 const f=BD_KINDS.find(x=>x[0]===bdFilter);
 const rows=list.map((r,i)=>[r,i]).filter(([r])=>!f[1]||r.kind===f[1]);
 $('#bdList').innerHTML=rows.map(([r,i])=>`<div class="card !px-3.5 !py-2.5 flex items-center gap-3 active:scale-[.99] transition" onclick="openRec('${bdDate}',${i})">
   <span class="text-[11px] font-mono text-slate-400 w-10 shrink-0">${r.at}</span><span class="text-lg">${r.ic}</span>
   <div class="flex-1 min-w-0"><b class="text-xs">${r.t}</b><div class="text-[9px] text-slate-400">记录人：${r.rec}</div></div><span class="text-slate-300">›</span></div>`).join('')||'<div class="text-center text-slate-400 py-6 text-[11px]">该类型今天没有记录</div>';
 const only=keys[keys.length-1];$('#bdNextBtn').style.opacity=bdDate>=only?'.3':'1';}
function bdStep(k){const days=Object.keys(ALLLOGS[curBaby]).sort();const i=days.indexOf(bdDate)+k;
 if(i<0||i>=days.length)return;bdDate=days[i];renderBabyDay();}
let rdCur=null;
function openRec(date,i){rdCur={date:date,i:i};const r=ALLLOGS[curBaby][date][i];if(!r)return;
 $('#rdIco').textContent=r.ic;$('#rdTitle').textContent=r.t;$('#rdMeta').textContent=date+' '+r.at+' · '+BABIES[curBaby].n+' · '+r.rec;
 $('#rdNote').value=r.note||'';renderCarerRow('rdCarers');
 $$('#rdCarers .chip').forEach(b=>b.classList.toggle('chip-on',b.dataset.v===r.rec));
 $('#rdLink').textContent=r.kind==='feed'&&r.ml?'奶量将汇入每日统计与周概览':r.kind==='diaper'&&r.g?'称重已与尿布记录关联':'修改将同步今日一览与时间线';
 openSheet('sheetRecDetail');}
function saveRec(){const r=ALLLOGS[curBaby][rdCur.date][rdCur.i];r.rec=chipBox('rdCarers');r.note=$('#rdNote').value.trim();
 closeSheet('sheetRecDetail');renderBabyToday();renderBabyDay();toast('✔ 记录已更新');}
function delRec(){ALLLOGS[curBaby][rdCur.date].splice(rdCur.i,1);babyLogs=careLogs();
 closeSheet('sheetRecDetail');renderBabyToday();renderBabyDay();toast('记录已删除');}
/* —— 宝宝档案（C6）与切换 —— */
function renderBabies(){$('#babyCardList').innerHTML=BABIES.map((b,i)=>`<div class="card flex items-center gap-3 ${i===curBaby?'ring-2 ring-brand-500':''}">
   <div class="w-11 h-11 rounded-full bg-gradient-to-br ${b.c} flex items-center justify-center text-xl">${b.av}</div>
   <div class="flex-1 min-w-0"><b class="text-sm">${b.n} <span class="text-[9px] px-1.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-400 font-normal">${b.sex}</span></b><div class="text-[10px] text-slate-400">${babyAgeStr(b.b)} · 生日 ${b.b} · 累计 ${b.logs} 条记录</div></div>
   ${i===curBaby?'<span class="text-[9px] px-2 py-1 rounded-full grad text-white font-bold">当前</span>':`<button class="mini-btn !text-[10px]" onclick="switchBaby(${i})">切换</button>`}
   <button class="text-[10px] text-slate-400 font-bold" onclick="toast('编辑档案（演示）')">编辑</button></div>`).join('');
 $('#carerChips').innerHTML=CARERS.map(c=>`<button class="chip ${c===curCarer?'chip-on':''}" onclick="curCarer='${c}';renderBabies();renderBabyHero();toast('默认记录人已切换：${c}')">${c}</button>`).join('')+'<button class="chip" onclick="toast(\'支持添加：外婆 / 保姆 等自定义身份（演示）\')">+ 添加</button>';}
function switchBaby(i){curBaby=i;bdDate=CARE_TODAY;babyLogs=careLogs();renderBabyHero();renderBabyToday();renderBabyDay();renderBabies();renderVax();renderWeekBaby();drawGrowth(gCur);renderBabySwitch();toast('已切换到「'+BABIES[i].n+'」· 记录与曲线独立成档');}
function renderBabySwitch(){$('#bswBabies').innerHTML=BABIES.map((b,i)=>`<button class="w-full flex items-center gap-3 rounded-xl px-3 py-2.5 text-left ${i===curBaby?'bg-brand-50 dark:bg-slate-800 ring-1 ring-brand-500':'bg-slate-50 dark:bg-slate-800/60'}" onclick="switchBaby(${i})">
   <span class="w-8 h-8 rounded-full bg-gradient-to-br ${b.c} flex items-center justify-center">${b.av}</span><div class="flex-1"><b class="text-xs">${b.n}</b><div class="text-[9px] text-slate-400">${babyAgeStr(b.b)}</div></div>${i===curBaby?'<span class="text-brand-500 text-xs">✓</span>':''}</button>`).join('');
 $('#bswCarers').innerHTML=CARERS.map(c=>`<button class="chip ${c===curCarer?'chip-on':''}" onclick="curCarer='${c}';renderBabySwitch();renderBabyHero();renderBabies()">${c}</button>`).join('');}
function saveBabyProfile(){const nm=$('#abName').value.trim();if(!nm){toast('先填宝宝昵称');return;}
 const sex=$('#abSex .chip-on').dataset.v,b=$('#abBirth').value||'2026-09-01',col=$('#abColors button.ring-2').dataset.v;
 BABIES.push({n:nm,sex:sex,b:b,c:col,av:'🍼',logs:0});ALLLOGS[BABIES.length-1]={'09-19':[]};
 closeSheet('sheetAddBaby');switchBaby(BABIES.length-1);toast('🍼 「'+nm+'」档案已创建 · 记录/曲线/疫苗独立管理');}
/* —— 生长曲线（预览 + 全屏） —— */
const GROWTH={w:{pts:[3.3,4.5,5.6,6.3,6.9,7.4,7.8,8.3,8.9],info:'体重 8.9kg · 近 P62 · 上月 +0.6kg · 曲线平滑正常',col:'#6366f1'},
 h:{pts:[49.9,54.7,58.4,61.4,63.9,65.9,67.6,69.2,71],info:'身高 71cm · 近 P75 · 遗传目标身高预测 172±5cm',col:'#2dd4bf'},
 head:{pts:[34.2,36.3,38.1,39.5,40.8,41.9,42.8,43.7,44.5],info:'头围 44.5cm · 近 P85 · 连续跟随自身曲线',col:'#f59e0b'}};
function drawGrowth(k){gCur=k;const g=GROWTH[k],el=$('#growthSvg');if(!el)return;const xs=16,xe=304;const vs=g.pts;const lo=Math.min(...vs)*.78,hi=Math.max(...vs)*1.1;
 const X=i=>xs+i*((xe-xs)/(vs.length-1)),Y=v=>126-((v-lo)/(hi-lo))*108;
 const line=f=>vs.map((v,i)=>(i?'L':'M')+X(i).toFixed(1)+','+Y(v*f).toFixed(1)).join(' ');
 el.innerHTML=`<path d="${line(1.13)}" fill="none" stroke="#94a3b8" stroke-width="1" stroke-dasharray="3 3" opacity=".5"/>
  <path d="${line(1)}" fill="none" stroke="#94a3b8" stroke-width="1" stroke-dasharray="3 3" opacity=".8"/>
  <path d="${line(.87)}" fill="none" stroke="#94a3b8" stroke-width="1" stroke-dasharray="3 3" opacity=".5"/>
  <path d="${vs.map((v,i)=>(i?'L':'M')+X(i).toFixed(1)+','+Y(v).toFixed(1)).join(' ')}" fill="none" stroke="${g.col}" stroke-width="2.5"/>
  ${vs.map((v,i)=>`<circle cx="${X(i).toFixed(1)}" cy="${Y(v).toFixed(1)}" r="3" fill="${g.col}"/>`).join('')}
  ${vs.map((v,i)=>`<text x="${X(i).toFixed(1)}" y="138" font-size="7" fill="#94a3b8" text-anchor="middle">${i}m</text>`).join('')}
  <text x="300" y="14" font-size="7" fill="#94a3b8" text-anchor="end">P97 · P50 · P3（虚线带）</text>`;
 $$('#growthTabs .gc')&&$$('#growthTabs .gc').forEach(b=>b.classList.toggle('on',b.dataset.k===k));$('#growthInfo').textContent=g.info;gPaint();renderGrowthFull();}
let gCur='w',gMode=0;
const GVALS={w:['处于 P62 百分位','高于均值 +0.9 SD','Z 分数 +0.35'],h:['处于 P75 百分位','高于均值 +1.2 SD','Z 分数 +0.47'],head:['处于 P85 百分位','高于均值 +1.6 SD','Z 分数 +0.62']};
function gPaint(){const b=$('#gModeBtn');if(!b)return;const names=['百分位 P','标准差 SD','Z 分数 Z'];b.textContent=names[gMode];const h=$('#gValHint');if(h)h.textContent=GVALS[gCur][gMode]+' · 点击切换';}
function gCycle(){gMode=(gMode+1)%3;gPaint();const names=['百分位（对照 WHO P3/P50/P97 带）','标准差（SD，偏离均值倍数）','Z 分数（=SD 的同义学术表达）'];toast('显示模式：'+names[gMode]);$$('.gfmode').forEach(b=>b.classList.toggle('on',+b.dataset.m===gMode));}
const GFULL={w:{med:[3.3,4.5,5.6,6.4,7.0,7.5,7.9,8.3,8.6,8.9,9.2,9.4,9.6],own:[[4,6.5],[5,7.2],[6,7.8],[7,8.3],[8.4,8.9]],u:'kg',name:'体重'},
 h:{med:[49.9,54.7,58.4,61.4,63.9,65.9,67.6,69.2,70.6,71.9,73.1,74.3,75.4],own:[[4,62],[5,64],[6,66.5],[7,68.5],[8.4,71]],u:'cm',name:'身高'},
 head:{med:[34.2,36.3,38.1,39.5,40.8,41.9,42.8,43.7,44.4,45.0,45.5,46.0,46.4],own:[[4,41],[5,42],[6,42.9],[7,43.7],[8.4,44.5]],u:'cm',name:'头围'}};
const GBANDS=[[.74,.82,.90,.96,1,1.05,1.11,1.20],[.80,.87,.93,.98,1,1.03,1.08,1.15]];/* 男/女 P3..P97 近似系数 */
function gFull(k){gCur=k;$$('.gfw').forEach(b=>{const on=b.dataset.k===k;b.classList.toggle('seg-on',on);b.classList.toggle('text-slate-500',!on);});drawGrowth(k);}
function gSetMode(m){gMode=m;$$('.gfmode').forEach(b=>{const on=+b.dataset.m===m;b.classList.toggle('seg-on',on);b.classList.toggle('text-slate-500',!on);});gPaint();renderGrowthFull();toast('显示模式：'+['百分位 P（WHO 参考带）','标准差 SD','Z 分数'][m]);}
function renderGrowthFull(){const el=$('#growthSvgFull');if(!el)return;const g=GFULL[gCur],isF=BABIES[curBaby].sex==='女';const bd=GBANDS[isF?1:0];
 const xs=34,xe=330,yb=178,hgt=150;const X=m=>xs+(m/12)*(xe-xs);
 const lo=Math.min.apply(null,g.med)*bd[0]*0.92,hi=Math.max.apply(null,g.med)*bd[7]*1.06;
 const Y=v=>yb-((v-lo)/(hi-lo))*hgt;
 const pathAt=f=>g.med.map((v,i)=>(i?'L':'M')+X(i).toFixed(1)+','+Y(v*f).toFixed(1)).join(' ');
 const band=(fa,fb,op)=>`<path d="${pathAt(fb)} ${g.med.map((v,i)=>'L'+X(11-i).toFixed(1)+','+Y(g.med[11-i]*fa).toFixed(1)).join(' ')} Z" fill="${g.col}" opacity="${op}"/>`;
 const own=g.own.map(([m,v])=>({m:m,x:X(m).toFixed(1),y:Y(v).toFixed(1)}));
 const ownLine=own.map((p,i)=>(i?'L':'M')+p.x+','+p.y).join(' ');
 const lbl=(GVALS[gCur][gMode].match(/P\d+|[+-]?[\d.]+ ?SD|Z 分数 [\d.+-]+/)||[''])[0];
 el.innerHTML=band(bd[0],bd[7],.07)+band(bd[2],bd[5],.10)+band(bd[3],bd[4],.15)+
  `<path d="${pathAt(1)}" fill="none" stroke="#94a3b8" stroke-width="1.4" stroke-dasharray="4 3"/>
  ${[bd[0],bd[2],bd[4],bd[6]].map((f,i)=>`<text x="4" y="${Y(g.med[11]*f).toFixed(1)}" font-size="7" fill="#94a3b8">${['P3','P25','P50','P97'][i]}</text>`).join('')}
  <path d="${ownLine}" fill="none" stroke="#4f46e5" stroke-width="2.5"/>
  ${own.map(p=>`<circle cx="${p.x}" cy="${p.y}" r="3.6" fill="#4f46e5" stroke="#fff" stroke-width="1.2"/>`).join('')}
  <text x="${own[own.length-1].x}" y="${+own[own.length-1].y-8}" font-size="8" fill="#4f46e5" font-weight="bold" text-anchor="middle">${lbl}</text>
  ${Array.from({length:13},(_,m)=>`<text x="${X(m).toFixed(1)}" y="196" font-size="7" fill="#94a3b8" text-anchor="middle">${m}</text>`).join('')}
  <text x="${xs}" y="14" font-size="8" fill="#64748b" font-weight="bold">${g.name} · ${BABIES[curBaby].n} · ${isF?'女宝':'男宝'} WHO 参考带</text>
  <text x="${xe}" y="212" font-size="7" fill="#94a3b8" text-anchor="end">月龄</text>`;
 $('#gfRead').innerHTML=`最新：<b>${g.own[g.own.length-1][1]}${g.u}</b> @ ${g.own[g.own.length-1][0]} 月龄 · ${GVALS[gCur][gMode]} · 近 3 次增速正常`;
 $('#gfWarn').innerHTML=`<div class="row-title">跨带预警</div><div class="mt-1.5 text-[11px] text-slate-400 leading-5">当前曲线平滑跟随自身百分位通道，<b class="text-teal-600">未触发预警</b>。规则：30 天内跨 2 条主百分位带（升或降）→ 温柔提醒并给出儿保就诊参考（不构成医疗建议）。</div>`;}
/* —— 测量 —— */
let MEASURE_HIST=[
 {d:'2026-09-19',w:8.9,h:71,c:44.5,p:'P62',rec:'妈妈'},
 {d:'2026-08-19',w:8.3,h:70,c:43.7,p:'P58',rec:'妈妈'},
 {d:'2026-07-19',w:7.8,h:68.5,c:43.0,p:'P55',rec:'爸爸'},
 {d:'2026-06-19',w:7.2,h:66.8,c:42.1,p:'P50',rec:'妈妈'},
 {d:'2026-05-19',w:6.5,h:64.9,c:41.0,p:'P46',rec:'妈妈'}];
function renderMeasureHist(){const el=$('#measureHist');if(!el)return;
 el.innerHTML=`<div class="grid grid-cols-6 text-[9px] text-slate-400 font-bold pb-1 border-b border-slate-100 dark:border-slate-800"><span>日期</span><span>体重</span><span>身高</span><span>头围</span><span>百分位</span><span>记录人</span></div>`+
 MEASURE_HIST.map(m=>`<div class="grid grid-cols-6 text-[10px] py-1.5 border-b border-slate-50 dark:border-slate-800/60 last:border-0"><span class="text-slate-400">${m.d.slice(5)}</span><b>${m.w}kg</b><span>${m.h}cm</span><span>${m.c}cm</span><span class="text-brand-500 font-bold">${m.p}</span><span class="text-slate-400">${m.rec}</span></div>`).join('');}
function saveMeasure(){const w=+$('#mW').value,hh=+$('#mH').value,hd=+$('#mC').value;
 if(!w||!hh||!hd){toast('请填写三项测量值');return;}
 pushLog({ic:'⚖️',t:`测量 · ${w}kg / ${hh}cm / ${hd}cm`,at:bnow(),kind:'measure',rec:curCarer});
 MEASURE_HIST.unshift({d:'2026-'+CARE_TODAY,w:w,h:hh,c:hd,p:'P62',rec:curCarer});
 closeSheet('sheetBabyMeasure');drawGrowth('w');renderMeasureHist();
 toast('✔ 已描点生长曲线 · 本月 +0.7kg 正常 · 下次体检提醒已更新');}
/* —— 疫苗 —— */
let VAX=[
 {n:'手足口病灭活疫苗',dose:'第1剂',due:'2026-10-12',st:'plan',kind:'自费',lead:7},
 {n:'流脑 A群多糖',dose:'第1剂',due:'2026-11-02',st:'plan',kind:'免规',lead:7},
 {n:'麻腮风减毒',dose:'第1剂',due:'2026-09-10',st:'late',kind:'免规',lead:7},
 {n:'乙脑减毒',dose:'第1剂',due:'2026-09-08',st:'done',kind:'免规'},
 {n:'百白破',dose:'第3剂',due:'2026-08-05',st:'done',kind:'免规'},
 {n:'乙肝',dose:'第3剂',due:'2026-07-15',st:'done',kind:'免规'}];
let vaxView='plan';
function vxDays(due){return Math.round((new Date(due)-new Date('2026-09-19'))/864e5);}
function vaxRow(x,i,full){const dd=vxDays(x.due);
 return `<div class="flex items-center gap-2.5 ${x.st==='done'?'opacity-55':''} bg-slate-50 dark:bg-slate-800/60 rounded-xl px-3 py-2.5"><span>${x.st==='done'?'✅':x.st==='late'?'⚠️':'💉'}</span>
  <div class="flex-1 min-w-0"><b>${x.n} ${x.dose} <span class="text-[8px] px-1.5 py-0.5 rounded-full ${x.kind==='免规'?'bg-sky-100 text-sky-600 dark:bg-sky-500/15':'bg-amber-100 text-amber-600 dark:bg-amber-500/15'}">${x.kind}</span></b>
  <div class="text-[9px] text-slate-400">${x.st==='done'?'已完成 · 凭证已归档':x.st==='late'?'已过计划日期 '+(-dd)+' 天 · 尽快补种':'计划 '+x.due+' · '+(dd>0?'还有 '+dd+' 天':'即将到期')+' · 提前 '+x.lead+' 天提醒'}</div></div>
  ${x.st!=='done'?`<button class="mini-btn !text-[10px]" onclick="vaxDone(${i})">完成</button>`:`<button class="text-[10px] text-slate-400 font-bold" onclick="toast('查看接种凭证照片（本地图档）')">凭证</button>`}</div>`;}
function renderVax(){const el=$('#vaxList');if(!el)return;
 el.innerHTML=VAX.filter(x=>x.st!=='done').slice(0,3).map((x,i)=>vaxRow(x,VAX.indexOf(x),false)).join('');
 const pl=VAX.filter(x=>x.st!=='done').length,nx=VAX.filter(x=>x.st==='plan').sort((a,b)=>a.due.localeCompare(b.due))[0];
 const s=$('#vxSummary');if(s)s.textContent='待接种 '+pl+' 剂 · 下一剂 '+(nx?nx.due.slice(5)+' '+nx.n:'—')+'（提前 7 天提醒，联动重要日子倒数）';
 const f=$('#vaxFull');if(f)f.innerHTML=VAX.map((x,i)=>[x,i]).filter(([x])=>vaxView==='all'||(vaxView==='plan'?x.st!=='done':x.st==='done')).map(([x,i])=>vaxRow(x,i,true)).join('')||'<div class="text-center text-slate-400 py-6 text-[11px]">暂无该状态疫苗</div>';}
function vaxTab(k){vaxView=k;[['plan','vaxT0'],['done','vaxT1'],['all','vaxT2']].forEach(([v,id])=>{const b=$('#'+id);b.className=(v===k?'seg-on ':'flex-1 rounded-lg py-1.5 text-slate-500')+' flex-1 rounded-lg py-1.5';});renderVax();}
function vaxDone(i){VAX[i].st='done';renderVax();toast('✔ 已记录接种 · 下一针提醒已自动写入「重要日子」（联动 L10）');}
function addVax(){const nm=$('#vaName').value.trim();if(!nm){toast('先填疫苗名称');return;}
 VAX.unshift({n:nm,dose:$('#vaDose').value.trim()||'第1剂',due:$('#vaDate').value||'2026-10-20',st:'plan',kind:getChip('vaKind')||$('#vaKind .chip-on').textContent.trim(),lead:+getChip('vaLead')||7});
 $('#vaName').value='';$('#vaDose').value='';closeSheet('sheetVaxAdd');renderVax();
 toast('💉 已加入计划 · 倒数提醒与提前 '+VAX[0].lead+' 天提醒已生成（联动 L10）');}
function renderWeekBaby(){const el=$('#weekBars');if(!el)return;const d=curBaby===0?[[6,13.8],[7,14.1],[5,13.2],[7,14.6],[6,13.5],[8,14.0],[7,13.6]]:[[5,12.8],[6,13.0],[5,13.4],[6,12.6],[5,13.1],[6,13.5],[5,13.2]];
 el.innerHTML=d.map(([c,h],i)=>`<div class="flex-1 flex items-end gap-[2px] h-full" title="${i===6?'今天':'前'+(6-i)+'天'}：喂养${c}次 · 睡眠${h}h"><span class="w-1/2 rounded-t bg-brand-500/80" style="height:${c*11}%"></span><span class="w-1/2 rounded-t bg-mint/70" style="height:${(h-11.5)*22}%"></span></div>`).join('');}
function renderCare(){renderCycle();renderSym();renderSymHist();renderCycStats();renderBabyHero();renderBabyToday();renderBabies();renderBabySwitch();drawGrowth('w');renderMeasureHist();renderVax();renderWeekBaby();renderBabyDay();}
/* —— 保留：小工具页运动换算（原母婴段后续内容） —— */
function sportCalc(){const km=+$('#spKm').value||0,mn=+$('#spMin').value||0;const el=$('#spOut');if(!km||!mn){el.textContent='请填写距离与时长';return}
 const p=mn/km,pm=Math.floor(p),sec=Math.round((p-pm)*60);el.textContent=`配速 ${pm}′${String(sec).padStart(2,'0')}″/km · ${km}km=${mn}min 三模互算 ✓`;}
function sportCalc0(){sportCalc()}
function sportSave(){sportCalc();const km=+$('#spKm').value||0,mn=+$('#spMin').value||0;if(!km||!mn)return;toast('🏃 已存：运动 '+km+'km / '+mn+'min → 写入时间账本「运动」（L11）· 可发起运动计时（复用悬浮计时条）')}
