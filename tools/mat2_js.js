/* ================= 母婴呵护 · 专版 V2（对话 05fb2fde-1cf5-4d7c-a381-5cb3f45a9f7c） ================= */
const CARE_TODAY='09-19',CARE_NOW='15:30';
const CARERS=['妈妈','爸爸','奶奶','月嫂'];
let curCarer='妈妈',curBaby=0;
let BABIES=[
 {n:'团子',sex:'女',b:'2026-01-07',c:'from-sky-400 to-indigo-500',av:'🧸',logs:238,wk:[['46','本周喂养'],['35','尿布片'],['13.8h','日均睡眠']]},
 {n:'糯米',sex:'男',b:'2025-04-19',c:'from-amber-400 to-orange-500',av:'🐣',logs:96,wk:[['5','每日奶次'],['3','自主进食'],['12.9h','日均睡眠']]}];
function babyAgeStr(b){const t=new Date('2026-09-19'),d=new Date(b);let mo=(t.getFullYear()-d.getFullYear())*12+t.getMonth()-d.getMonth();let dd=t.getDate()-d.getDate();if(dd<0){mo--;const pm=new Date(t.getFullYear(),t.getMonth(),0).getDate();dd+=pm;}
 return mo>=12?Math.floor(mo/12)+' 岁 '+(mo%12)+' 个月':(mo?mo+' 个月 ':'')+dd+' 天';}
function logsOf(date){return ALLLOGS[curBaby][date]||(ALLLOGS[curBaby][date]=[]);}
function bnow(){const d=new Date();return String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');}
function t2m(t){const p=t.split(':');return +p[0]*60+ +p[1];}
function hms(v){return v>=60?(Math.floor(v/60)+'h'+(v%60?v%60+'′':'')):v+'min';}
/* —— 事件注册表 —— */
const EVENTS={
 nurse:{n:'母乳亲喂',ic:'🤱',unit:'min',dur:1,timer:1,tint:'bg-rose-100 dark:bg-rose-500/15',def:15,quick:[5,10,15,20,30]},
 bmilk:{n:'瓶喂母乳',ic:'🍼',unit:'ml',amt:1,tint:'bg-pink-100 dark:bg-pink-500/15',def:120,quick:[60,90,120,150,180]},
 formula:{n:'配方奶',ic:'🥣',unit:'ml',amt:1,tint:'bg-amber-100 dark:bg-amber-500/15',def:150,quick:[90,120,150,180,210]},
 diaper:{n:'换尿布',ic:'🚼',sp:'dia',tint:'bg-orange-100 dark:bg-orange-500/15'},
 sleep:{n:'睡眠',ic:'😴',unit:'min',dur:1,timer:1,tint:'bg-indigo-100 dark:bg-indigo-500/15',def:60,quick:[30,60,90,120]},
 bath:{n:'洗澡',ic:'🛁',unit:'min',dur:1,timer:1,tint:'bg-sky-100 dark:bg-sky-500/15',def:15,quick:[10,15,20,30]},
 play:{n:'玩耍',ic:'🧸',unit:'min',dur:1,timer:1,tint:'bg-emerald-100 dark:bg-emerald-500/15',def:15,quick:[5,10,15,20,30]},
 supp:{n:'补剂',ic:'💊',sp:'supp',tint:'bg-violet-100 dark:bg-violet-500/15'},
 swim:{n:'游泳',ic:'🏊',unit:'min',dur:1,timer:1,tint:'bg-cyan-100 dark:bg-cyan-500/15',def:20,quick:[10,20,30]},
 water:{n:'喝水',ic:'💧',unit:'ml',amt:1,tint:'bg-teal-100 dark:bg-teal-500/15',def:30,quick:[10,20,30,50,80]},
 custom:{n:'自定义',ic:'✨',sp:'cus',tint:'bg-slate-100 dark:bg-slate-800'}};
let CUSTOM_EV={};try{CUSTOM_EV=JSON.parse(localStorage.getItem('lh_ev_custom')||'{}')}catch(e){}
function evDef(k){return EVENTS[k]||CUSTOM_EV[k]||{n:'记录',ic:'✨',unit:'min',dur:1};}
const EV_BASE=['nurse','bmilk','formula','diaper','sleep','bath','play','supp','swim','water','custom'];
let evOrder=(function(){let o=[];try{o=JSON.parse(localStorage.getItem('lh_ev_order')||'[]')}catch(e){}
 const saved=o.filter(k=>EVENTS[k]||CUSTOM_EV[k]);
 return saved.length?saved.filter((k,i,a)=>a.indexOf(k)===i).concat(EV_BASE.filter(k=>!saved.includes(k)),Object.keys(CUSTOM_EV).filter(k=>!saved.includes(k))):[...EV_BASE];})();
let evSortOn=false;
function saveEvOrder(){try{localStorage.setItem('lh_ev_order',JSON.stringify(evOrder));localStorage.setItem('lh_ev_custom',JSON.stringify(CUSTOM_EV))}catch(e){}}
function renderEvGrid(){const g=$('#evGrid');if(!g)return;
 g.innerHTML=evOrder.map((k,i)=>{const E=evDef(k);
  return `<div class="relative"><button class="card w-full !p-2 flex flex-col items-center gap-1 active:scale-95 transition" onclick="${evSortOn?'':'openEvent(\''+k+'\')'}">
   <span class="w-9 h-9 rounded-2xl ${E.tint||'bg-slate-100 dark:bg-slate-800'} flex items-center justify-center text-lg">${E.ic}</span><span class="truncate w-full">${E.n}</span></button>
   ${evSortOn?`<span class="absolute top-0.5 right-0.5 flex flex-col gap-0.5 text-[9px] font-bold text-brand-500"><button onclick="evMove(${i},-1)">▲</button><button onclick="evMove(${i},1)">▼</button></span>`:''}</div>`}).join('');
 $('#evSortBtn').className='text-[10px] font-bold '+(evSortOn?'text-brand-500':'text-slate-400');
 $('#evSortBtn').textContent=evSortOn?'✓ 完成':'⇅ 排序';}
function evSortToggle(){evSortOn=!evSortOn;if(!evSortOn){saveEvOrder();toast('事件顺序已保存（本机持久化）')}renderEvGrid();}
function evMove(i,dir){const j=i+dir;if(j<0||j>=evOrder.length){toast('已在边界');return}
 const t=evOrder[i];evOrder[i]=evOrder[j];evOrder[j]=t;renderEvGrid();}
/* —— 整屏互切（她 ⇄ 宝宝 ⇄ 汇总） —— */
function careSwap(to){if(stack.length&&stack[stack.length-1]===curPage)stack.pop();navTo(to);if(to==='p-babyStats')renderStats();}
/* —— 统一事件录入 / 二次编辑 —— */
const H24=Array.from({length:24},(_,i)=>String(i).padStart(2,'0'));
const M60=Array.from({length:60},(_,i)=>String(i).padStart(2,'0'));
const AMT_RANGE={min:[5,180,5],ml:[5,300,5],g:[1,500,1],'°C':[36,42,1],'次':[1,20,1]};
let elCur=null;
function elSetWheels(s,e){wReg('elSh',H24,t2m(s)/60|0,elUp);wReg('elSm',M60,t2m(s)%60,elUp);wReg('elEh',H24,t2m(e)/60|0,elUp);wReg('elEm',M60,t2m(e)%60,elUp);elUp();}
function elTimes(){return [WHEELS.elSh.items[WHEELS.elSh.i]+':'+WHEELS.elSm.items[WHEELS.elSm.i],WHEELS.elEh.items[WHEELS.elEh.i]+':'+WHEELS.elEm.items[WHEELS.elEm.i]];}
function elUp(){const [s,e]=elTimes();let d=t2m(e)-t2m(s);if(d<0)d+=1440;
 $('#elDur').innerHTML=(evDef(elCur.k).dur||elCur.k==='sleep')?`时长 <b class="text-brand-500">${hms(d)}</b>`:(d?`用时 ${d}min ·`:'')+` ${s} → ${e}`;elCur.dur=d;}
function elQuick(k){const E=evDef(k);
 if(E.dur){$('#elQuickAmt').innerHTML=(E.quick||[5,10,15,30,60]).map(v=>`<button class="chip" onclick="elDurSet(${v})">${v>=60?(v/60)+'h':v+'min'}</button>`).join('');return;}
 if(E.amt){const u=E.unit||elCur.unit||'ml';$('#elQuickAmt').innerHTML=(E.quick||[10,30,50,100,150,200]).map(v=>`<button class="chip" onclick="elAmtSet(${v})">${v}</button>`).join('');
  $('#elAmtLbl').textContent=k==='water'?'喝奶/水量（ml）':(E.n+'量（'+u+'）');}}
function elDurSet(v){const [s]=elTimes();const e2=t2m(s)+v;$('#elEh')&&0;WHEELS.elEh.i=Math.floor((e2%1440)/60)%24;WHEELS.elEm.i=(e2%1440)%60;renderW('elEh');renderW('elEm');elUp();}
function elAmtSet(v){const w=WHEELS.elAmtW;if(!w)return;let bi=0,bd=1e9;w.items.forEach((it,i)=>{const d=Math.abs(+it-v);if(d<bd){bd=d;bi=i}});w.i=bi;renderW('elAmtW');}
function elAmtBuild(u,val){const rg=AMT_RANGE[u]||AMT_RANGE.min;const items=[];for(let v=rg[0];v<=rg[1];v+=rg[2])items.push(String(v));
 wReg('elAmtW',items,items.indexOf(String(val))<0?0:items.indexOf(String(val)),()=>{});$('#elAmtUnit').textContent=u;}
function elPick(f,el){const box=el.parentElement;box.querySelectorAll('.chip').forEach(b=>b.classList.remove('chip-on'));el.classList.add('chip-on');elCur[f]=el.dataset.v;}
function elUnitPick(el){elPick('unit',el);elAmtBuild(elCur.unit||'min',10);}
function elDiaPick(v){elCur.dia=v;$$('#elDiaType .chip').forEach(b=>b.classList.toggle('chip-on',b.dataset.v===v));
 $('#elDiaPoo').classList.toggle('hidden',v==='pee');}
const POO_COLORS=[['黄绿','#84cc16'],['金黄','#f59e0b'],['棕色','#92400e'],['墨绿','#166534'],['茶色','#7c2d12'],['砖红','#b91c1c'],['灰白','#cbd5e1']];
function renderPooColors(){const box=$('#elPooColor');if(!box)return;
 box.innerHTML=POO_COLORS.map(([n,c])=>`<button class="flex flex-col items-center gap-1 text-[8px] font-bold ${n===(elCur.color||'金黄')?'text-brand-500':'text-slate-400'}" onclick="elCur.color='${n}';renderPooColors()">
  <span class="w-7 h-7 rounded-full border-2 ${n===(elCur.color||'金黄')?'border-brand-500 scale-110':'border-transparent'}" style="background:${c}"></span>${n}</button>`).join('');
 if(!elCur.color)elCur.color='金黄';}
function openEvent(k,ctx){
 const src=ctx?ALLLOGS[curBaby][ctx.date][ctx.i]:null;const key=src?src.k:k;const E=evDef(key);
 elCur={k:key,dia:src?src.dia:'pee',color:src?src.color:'金黄',tex:src?src.tex:'',vol:src?src.vol:'中',name:src?src.name:'',unit:src?src.unit:(E.unit||'min'),ctx:ctx};
 $('#elIco').textContent=src?icOf(src):E.ic;$('#elTitle').textContent=E.n+(src?' · 二次修改':'');
 $('#elNote').value=src&&src.note?src.note:'';
 const s=src?src.s:CARE_NOW;let e=src?src.e:CARE_NOW;
 if(!src&&E.dur)e=String((t2m(s)+(E.def||15))%1440/60|0).padStart(2,'0')+':'+String((t2m(s)+(E.def||15))%60).padStart(2,'0');
 elSetWheels(s,e);
 $('#elAmtWrap').classList.toggle('hidden',!(E.amt||E.sp==='cus'||(src&&(src.ml||src.amt))));
 if(E.amt||E.sp==='cus'){elAmtBuild(E.sp==='cus'?elCur.unit:'ml',src?(src.ml||src.amt):(E.def||30));elQuick(key);}
 $('#elDiaWrap').classList.toggle('hidden',!(E.sp==='dia'||(src&&src.k==='diaper')));
 if(E.sp==='dia'){elDiaPick(elCur.dia);renderPooColors();
  $$('#elPooTex .chip').forEach(b=>b.classList.toggle('chip-on',b.dataset.v===elCur.tex));
  $$('#elPooVol .chip').forEach(b=>b.classList.toggle('chip-on',b.dataset.v===elCur.vol));}
 $('#elSuppWrap').classList.toggle('hidden',!(E.sp==='supp'||(src&&src.k==='supp')));
 if(E.sp==='supp'){$$('#elSuppNames .chip').forEach(b=>b.classList.toggle('chip-on',b.dataset.v===elCur.name));$('#elSuppName').value=[ '维 D3 400IU','DHA','铁剂','益生菌'].includes(elCur.name)?'':(elCur.name||'');}
 $('#elCusWrap').classList.toggle('hidden',!(E.sp==='cus'||(src&&src.k&&src.k.startsWith('cus:'))));
 if(E.sp==='cus'){$('#elCusName').value=elCur.name||'';$$('#elCusUnit .chip').forEach(b=>b.classList.toggle('chip-on',b.dataset.v===elCur.unit));}
 $('#elTimerBtn').style.display=(E.timer&&!src)?'':'none';
 $('#elDelBtn').classList.toggle('hidden',!src);
 renderCarerRow('elCarers');if(src)$$('#elCarers .chip').forEach(b=>b.classList.toggle('chip-on',b.dataset.v===src.rec));
 openSheet('sheetEventLog');}
function elNow(){WHEELS.elEh.i=15;WHEELS.elEm.i=30;renderW('elEh');renderW('elEm');elUp();}
function elStartTimer(){closeSheet('sheetEventLog');startTimer(elCur.k);}
function saveEvent(){const [s,e]=elTimes();let dur=t2m(e)-t2m(s);if(dur<0)dur+=1440;
 const k=elCur.k,E=evDef(k),r=elCur.ctx?ALLLOGS[curBaby][elCur.ctx.date][elCur.ctx.i]:{k,s,e,rec:curCarer};
 r.s=s;r.e=e;r.rec=chipBox('elCarers');r.note=$('#elNote').value.trim();
 if(E.dur||k==='sleep')r.dur=dur;else r.dur=dur||undefined;
 if(E.amt){const w=WHEELS.elAmtW;r.ml=w?+w.items[w.i]:+$('#elSuppName')||E.def;}
 if(E.sp==='dia'){r.dia=elCur.dia;if(elCur.dia!=='pee'){r.color=elCur.color;r.tex=elCur.tex||'糊状';r.vol=elCur.vol||'中';}}
 if(E.sp==='supp'){r.name=$('#elSuppName').value.trim()||elCur.name||'维 D3 400IU';}
 if(E.sp==='cus'){r.name=$('#elCusName').value.trim()||'自定义';r.unit=elCur.unit;r.amt=WHEELS.elAmtW?+WHEELS.elAmtW.items[WHEELS.elAmtW.i]:0;
  if($('#elCusPin').classList.contains('on')&&!CUSTOM_EV['cus:'+r.name]){CUSTOM_EV['cus:'+r.name]={n:r.name,ic:'✨',unit:r.unit,tint:'bg-slate-100 dark:bg-slate-800'};evOrder.push('cus:'+r.name);saveEvOrder();renderEvGrid();toast('「'+r.name+'」已固定到速记区（长按排序可调整）');}}
 if(elCur.ctx){renderBabyToday();renderBabyDay();renderStats();closeSheet('sheetEventLog');toast('✔ 已更新记录（起止/量二次修改生效）');}
 else{pushLog(r);closeSheet('sheetEventLog');
  const warn=r.k==='diaper'&&r.color==='砖红'?' · 砖红色便建议拍照留档并咨询儿科':r.k==='diaper'&&r.color==='灰白'?' · 灰白便提示就医参考（演示文案）':'';
  toast('✔ '+evDef(k).n+'已入账 '+s+'~'+e+warn);}}
function delEvent(){if(!elCur.ctx)return;ALLLOGS[curBaby][elCur.ctx.date].splice(elCur.ctx.i,1);
 closeSheet('sheetEventLog');renderBabyToday();renderBabyDay();renderStats();toast('记录已删除');}
/* —— 记录文本/图标 —— */
function icOf(r){if(!r)return '✨';if(r.k==='diaper')return r.dia==='pee'?'💧':'💩';return (EVENTS[r.k]||CUSTOM_EV[r.k]||{ic:'✨'}).ic;}
function logTitle(r){const E=EVENTS[r.k]||CUSTOM_EV[r.k]||{n:r.name||'记录'};
 switch(r.k){
  case 'nurse':return '母乳亲喂 · '+hms(r.dur||0)+(r.seg?'（'+r.seg+'）':'');
  case 'bmilk':return '瓶喂母乳 '+r.ml+'ml';
  case 'formula':return '配方奶 '+r.ml+'ml'+(r.tmp?' · '+r.tmp+'°C':'');
  case 'water':return '喝水 '+r.ml+'ml';
  case 'sleep':return '睡眠 '+r.s+'~'+r.e+' · '+hms(r.dur||0);
  case 'diaper':return '尿布 · '+(r.dia==='pee'?'尿尿':r.dia==='mix'?'臭臭+尿尿':'臭臭')+(r.dia!=='pee'?' · '+r.color+'·'+r.tex+'·'+r.vol+'量':'');
  case 'supp':return '补剂 · '+r.name;
  case 'bath':return '洗澡 '+hms(r.dur||0);
  case 'swim':return '游泳 '+hms(r.dur||0);
  case 'play':return '玩耍 · '+(r.name||'')+' '+hms(r.dur||0);
  default:return (r.name||E.n)+' · '+(r.amt||r.dur||'')+(r.unit||'');}}
function pushLog(r){if(!r.at)r.at=r.s;logsOf(CARE_TODAY).unshift(r);
 BABIES[curBaby].logs++;renderBabyToday();renderBabyDay();renderStats();}
function recRow(r,i){return `<div class="flex items-center gap-2.5 bg-slate-50 dark:bg-slate-800/60 rounded-xl px-3 py-2 active:scale-[.99] transition" onclick="openRec(CARE_TODAY,${i})"><span class="text-[10px] font-mono text-slate-400 w-10 shrink-0">${r.s}</span><span class="text-base">${icOf(r)}</span><div class="flex-1 min-w-0"><b class="block truncate">${logTitle(r)}</b><div class="text-[9px] text-slate-400">记录人：${r.rec}</div></div><button class="text-[10px] text-rose-400 font-bold shrink-0" onclick="event.stopPropagation();ALLLOGS[${curBaby}]['${CARE_TODAY}'].splice(${i},1);renderBabyToday();renderBabyDay();renderStats();toast('记录已删除')">删除</button></div>`;}
function renderBabyToday(){const el=$('#babyToday');if(!el)return;const logs=logsOf(CARE_TODAY);
 el.innerHTML=logs.slice(0,5).map((r,i)=>recRow(r,i)).join('')||'<div class="text-center text-slate-400 py-4 text-[11px]">今天还没有记录，点上方事件速记</div>';
 const c=$('#babyCount');if(c)c.textContent=logs.length;}
function renderCarerRow(box){$('#'+box).innerHTML=CARERS.map(c=>`<button class="chip ${c===curCarer?'chip-on':''}" data-v="${c}" onclick="oneChip('${box}',this)">${c}</button>`).join('');}
function chipBox(box){const b=$('#'+box+' .chip-on');return b?b.dataset.v:curCarer;}
function openRec(date,i){const r=ALLLOGS[curBaby][date][i];if(r)openEvent(r.k,{date,i});}
/* —— 计时（悬浮条形态 · 复用宿主计时设施） —— */
let ftTimer=null,ftT0=0,ftKind='',ftSide='左',ftSwapMin=0,ftStart=CARE_NOW;
function startTimer(k){ftKind=k;ftSide='左';ftSwapMin=0;ftT0=Date.now();ftStart=bnow();ftTimer=setInterval(renderFeedBar,500);renderFeedBar();
 toast(evDef(k).ic+' '+evDef(k).n+'计时开始 · 界面可继续做别的');}
function ftSwap(min){ftSwapMin=min;ftSide=ftSide==='左'?'右':'左';renderFeedBar();toast('已换边 → '+ftSide+'侧继续计时，分段会记录');}
function renderFeedBar(){const s=Math.floor((Date.now()-ftT0)/1000);const mm=Math.floor(s/60),ss=String(s%60).padStart(2,'0');const bar=$('#feedTimer');if(!bar)return;bar.classList.remove('hidden');
 const E=evDef(ftKind);const isN=ftKind==='nurse';
 bar.innerHTML=`<span class="text-lg">${E.ic}</span><div class="flex-1 min-w-0"><b class="text-xs">${isN?ftSide+'侧':''}${E.n}计时 · ${mm}:${ss}</b><div class="text-[9px] text-slate-400">${isN?'换边继续计时，结束时自动生成分段记录':'结束自动入账，时长=起止差'}</div></div>
  ${isN?`<button class="mini-btn !text-[10px]" onclick="ftSwap(Math.round((Date.now()-ftT0)/60000))">🔄 换边</button>`:''}
  <button class="mini-btn !text-[10px] !bg-rose-100 !text-rose-500 dark:!bg-rose-500/15" onclick="endFeed()">■ 结束</button>`;}
function endFeed(){if(!ftTimer)return;const s=Math.floor((Date.now()-ftT0)/1000);const mins=Math.max(1,Math.round(s/60));
 const r={k:ftKind,s:ftStart,e:bnow(),dur:mins,rec:curCarer};
 if(ftKind==='nurse'){const l=ftSwapMin?Math.max(0,ftSide==='左'?ftSwapMin:mins-ftSwapMin):mins,rr=Math.max(0,mins-l);r.seg='左'+l+'′/右'+rr+'′';}
 clearInterval(ftTimer);ftTimer=null;ftKind='';$('#feedTimer').classList.add('hidden');
 pushLog(r);toast('✔ 计时已存 · '+ftStart+'~'+r.e+'（时长可二次修改）');}
/* —— 数据（示例） —— */
let ALLLOGS={0:{'09-19':[
   {k:'nurse',s:'14:20',e:'14:34',dur:14,seg:'左8′/右6′',rec:'妈妈'},
   {k:'diaper',s:'13:05',e:'13:05',dia:'pee',rec:'妈妈'},
   {k:'formula',s:'12:30',e:'12:45',dur:15,ml:150,tmp:42,rec:'爸爸'},
   {k:'sleep',s:'11:40',e:'13:30',dur:110,rec:'妈妈'},
   {k:'diaper',s:'09:40',e:'09:40',dia:'poop',color:'金黄',tex:'糊状',vol:'中',rec:'妈妈'},
   {k:'supp',s:'09:15',e:'09:15',name:'维 D3 400IU',rec:'妈妈'},
   {k:'play',s:'08:40',e:'08:48',dur:8,name:'俯卧时间',rec:'奶奶'},
   {k:'nurse',s:'07:50',e:'08:02',dur:12,rec:'妈妈'},
   {k:'water',s:'07:00',e:'07:00',ml:30,rec:'妈妈'}],
  '09-18':[
   {k:'formula',s:'19:40',e:'19:55',dur:15,ml:130,tmp:42,rec:'奶奶'},
   {k:'diaper',s:'17:20',e:'17:20',dia:'mix',color:'棕色',tex:'成形',vol:'多',rec:'爸爸'},
   {k:'nurse',s:'14:00',e:'14:15',dur:15,rec:'妈妈'},
   {k:'play',s:'10:30',e:'10:42',dur:12,name:'爬行练习',rec:'妈妈'},
   {k:'supp',s:'08:00',e:'08:00',name:'DHA',rec:'妈妈'},
   {k:'bath',s:'20:30',e:'20:55',dur:25,rec:'妈妈'}],
  '09-17':[
   {k:'bath',s:'20:10',e:'20:35',dur:25,rec:'妈妈'},
   {k:'diaper',s:'15:40',e:'15:40',dia:'pee',rec:'月嫂'},
   {k:'sleep',s:'12:20',e:'14:25',dur:125,rec:'妈妈'},
   {k:'swim',s:'10:00',e:'10:25',dur:25,rec:'爸爸'},
   {k:'supp',s:'09:00',e:'09:00',name:'维 D3 400IU',rec:'妈妈'},
   {k:'nurse',s:'07:30',e:'07:48',dur:18,seg:'左9′/右9′',rec:'妈妈'}]},
 1:{'09-19':[
   {k:'formula',s:'12:00',e:'12:20',dur:20,ml:180,tmp:42,rec:'爸爸'},
   {k:'play',s:'08:30',e:'08:45',dur:15,name:'积木抓握',rec:'妈妈'}]}};
/* —— 宝宝：主页 —— */
function renderBabyHero(){const b=BABIES[curBaby];$('#bhName').textContent=b.n;$('#bhAge').textContent=babyAgeStr(b.b);$('#bhAv').textContent=b.av;
 $('#bhSub').textContent=(b.sex==='女'?'女宝':'男宝')+' · 生日 '+b.b;
 $('#bhCarer').textContent=curCarer+' · 记录中';
 $('#bhStats').innerHTML=(b.wk||[]).map(([v,l])=>`<div class="rounded-2xl bg-white/15 py-2"><b class="text-base block">${v}</b><span class="text-[9px] opacity-80">${l}</span></div>`).join('');}
/* —— 全天时间线（C7） —— */
let bdDate=CARE_TODAY,bdFilter='全部';
function renderBabyDay(){const days=ALLLOGS[curBaby];const keys=Object.keys(days).sort();
 if(!days[bdDate]){bdDate=keys[keys.length-1];}
 $('#bdLbl').textContent=bdDate+(bdDate===CARE_TODAY?' · 今天':'');
 const list=days[bdDate]||[];$('#bdCnt').textContent='共 '+list.length+' 条记录';
 const ml=list.reduce((a,r)=>a+(r.ml||0),0),fc=list.filter(r=>['nurse','bmilk','formula'].includes(r.k)).length,dp=list.filter(r=>r.k==='diaper').length,sl=list.reduce((a,r)=>a+(r.k==='sleep'?r.dur||0:0),0);
 $('#bdSummary').innerHTML=`<div class="card !py-2"><b class="text-base">${fc}</b><div class="text-slate-400">喂养次</div></div>
  <div class="card !py-2"><b class="text-base">${ml}</b><div class="text-slate-400">奶量ml</div></div>
  <div class="card !py-2"><b class="text-base">${dp}</b><div class="text-slate-400">尿布</div></div>
  <div class="card !py-2"><b class="text-base">${sl?hms(sl):'0'}</b><div class="text-slate-400">睡眠</div></div>`;
 const kinds=['全部',...new Set(list.map(r=>evDef(r.k).n))];
 $('#bdFilters').innerHTML=kinds.map(k=>`<button class="chip whitespace-nowrap ${k===bdFilter?'chip-on':''}" onclick="bdFilter='${k}';renderBabyDay()">${k}</button>`).join('');
 const rows=list.map((r,i)=>[r,i]).filter(([r])=>bdFilter==='全部'||evDef(r.k).n===bdFilter);
 $('#bdList').innerHTML=rows.map(([r,i])=>`<div class="card !px-3.5 !py-2.5 flex items-center gap-3 active:scale-[.99] transition" onclick="openRec('${bdDate}',${i})">
   <span class="text-[11px] font-mono text-slate-400 w-10 shrink-0">${r.s}</span><span class="text-lg">${icOf(r)}</span>
   <div class="flex-1 min-w-0"><b class="text-xs">${logTitle(r)}</b><div class="text-[9px] text-slate-400">记录人：${r.rec}${r.note?' · '+r.note:''}</div></div><span class="text-slate-300">›</span></div>`).join('')||'<div class="text-center text-slate-400 py-6 text-[11px]">该类型没有记录</div>';
 $('#bdNextBtn').style.opacity=bdDate>=keys[keys.length-1]?'.3':'1';}
function bdStep(k){const days=Object.keys(ALLLOGS[curBaby]).sort();const i=days.indexOf(bdDate)+k;
 if(i<0||i>=days.length)return;bdDate=days[i];renderBabyDay();}
/* —— 宝宝档案（C6）与切换 —— */
function renderBabies(){$('#babyCardList').innerHTML=BABIES.map((b,i)=>`<div class="card flex items-center gap-3 ${i===curBaby?'ring-2 ring-brand-500':''}">
   <div class="w-11 h-11 rounded-full bg-gradient-to-br ${b.c} flex items-center justify-center text-xl">${b.av}</div>
   <div class="flex-1 min-w-0"><b class="text-sm">${b.n} <span class="text-[9px] px-1.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-400 font-normal">${b.sex}</span></b><div class="text-[10px] text-slate-400">${babyAgeStr(b.b)} · 生日 ${b.b} · 累计 ${b.logs} 条记录</div></div>
   ${i===curBaby?'<span class="text-[9px] px-2 py-1 rounded-full grad text-white font-bold">当前</span>':`<button class="mini-btn !text-[10px]" onclick="switchBaby(${i})">切换</button>`}
   <button class="text-[10px] text-slate-400 font-bold" onclick="toast('编辑档案（演示）')">编辑</button></div>`).join('');
 $('#carerChips').innerHTML=CARERS.map(c=>`<button class="chip ${c===curCarer?'chip-on':''}" onclick="curCarer='${c}';renderBabies();renderBabyHero();toast('默认记录人已切换：${c}')">${c}</button>`).join('')+'<button class="chip" onclick="toast(\'支持添加：外婆 / 保姆 等自定义身份（演示）\')">+ 添加</button>';}
function switchBaby(i){curBaby=i;bdDate=CARE_TODAY;renderBabyHero();renderBabyToday();renderBabyDay();renderBabies();renderBabySwitch();renderVax();renderWeekBaby();drawGrowth(gCur);renderStats();toast('已切换到「'+BABIES[i].n+'」· 记录与曲线独立成档');}
function renderBabySwitch(){$('#bswBabies').innerHTML=BABIES.map((b,i)=>`<button class="w-full flex items-center gap-3 rounded-xl px-3 py-2.5 text-left ${i===curBaby?'bg-brand-50 dark:bg-slate-800 ring-1 ring-brand-500':'bg-slate-50 dark:bg-slate-800/60'}" onclick="switchBaby(${i})">
   <span class="w-8 h-8 rounded-full bg-gradient-to-br ${b.c} flex items-center justify-center">${b.av}</span><div class="flex-1"><b class="text-xs">${b.n}</b><div class="text-[9px] text-slate-400">${babyAgeStr(b.b)}</div></div>${i===curBaby?'<span class="text-brand-500 text-xs">✓</span>':''}</button>`).join('');
 $('#bswCarers').innerHTML=CARERS.map(c=>`<button class="chip ${c===curCarer?'chip-on':''}" onclick="curCarer='${c}';renderBabySwitch();renderBabyHero();renderBabies()">${c}</button>`).join('');}
function saveBabyProfile(){const nm=$('#abName').value.trim();if(!nm){toast('先填宝宝昵称');return;}
 const sex=$('#abSex .chip-on').dataset.v,b=$('#abBirth').value||'2026-09-01',col=$('#abColors button.ring-2').dataset.v;
 BABIES.push({n:nm,sex:sex,b:b,c:col,av:'🍼',logs:0,wk:[['0','记录'],['—','—'],['—','—']]});ALLLOGS[BABIES.length-1]={'09-19':[]};
 closeSheet('sheetAddBaby');switchBaby(BABIES.length-1);toast('🍼 「'+nm+'」档案已创建 · 记录/曲线/疫苗独立管理');}
/* —— 生长曲线 —— */
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
 $$('#growthTabs .gc').forEach(b=>b.classList.toggle('on',b.dataset.k===k));$('#growthInfo').textContent=g.info;gPaint();renderGrowthFull();}
let gCur='w',gMode=0;
const GVALS={w:['处于 P62 百分位','高于均值 +0.9 SD','Z 分数 +0.35'],h:['处于 P75 百分位','高于均值 +1.2 SD','Z 分数 +0.47'],head:['处于 P85 百分位','高于均值 +1.6 SD','Z 分数 +0.62']};
function gPaint(){const b=$('#gModeBtn');if(!b)return;b.textContent=['P','SD','Z'][gMode];}
function gCycle(){gMode=(gMode+1)%3;gPaint();toast('显示模式：'+['百分位（对照 WHO P3/P50/P97 带）','标准差 SD','Z 分数'][gMode]);$$('.gfmode').forEach(b=>{const on=+b.dataset.m===gMode;b.classList.toggle('seg-on',on);b.classList.toggle('text-slate-500',!on);});renderGrowthFull();}
const GFULL={w:{med:[3.3,4.5,5.6,6.4,7.0,7.5,7.9,8.3,8.6,8.9,9.2,9.4,9.6],own:[[4,6.5],[5,7.2],[6,7.8],[7,8.3],[8.4,8.9]],u:'kg',name:'体重'},
 h:{med:[49.9,54.7,58.4,61.4,63.9,65.9,67.6,69.2,70.6,71.9,73.1,74.3,75.4],own:[[4,62],[5,64],[6,66.5],[7,68.5],[8.4,71]],u:'cm',name:'身高'},
 head:{med:[34.2,36.3,38.1,39.5,40.8,41.9,42.8,43.7,44.4,45.0,45.5,46.0,46.4],own:[[4,41],[5,42],[6,42.9],[7,43.7],[8.4,44.5]],u:'cm',name:'头围'}};
const GBANDS=[[.74,.82,.90,.96,1,1.05,1.11,1.20],[.80,.87,.93,.98,1,1.03,1.08,1.15]];
function gFull(k){gCur=k;$$('.gfw').forEach(b=>{const on=b.dataset.k===k;b.classList.toggle('seg-on',on);b.classList.toggle('text-slate-500',!on);});drawGrowth(k);}
function gSetMode(m){gMode=m;$$('.gfmode').forEach(b=>{const on=+b.dataset.m===m;b.classList.toggle('seg-on',on);b.classList.toggle('text-slate-500',!on);});gPaint();renderGrowthFull();toast('显示模式：'+['百分位 P（WHO 参考带）','标准差 SD','Z 分数'][m]);}
function renderGrowthFull(){const el=$('#growthSvgFull');if(!el)return;const g=GFULL[gCur],isF=BABIES[curBaby].sex==='女';const bd=GBANDS[isF?1:0];const col=GROWTH[gCur].col;
 const xs=34,xe=330,yb=178,hgt=150;const X=m=>xs+(m/12)*(xe-xs);
 const lo=Math.min.apply(null,g.med)*bd[0]*0.92,hi=Math.max.apply(null,g.med)*bd[7]*1.06;
 const Y=v=>yb-((v-lo)/(hi-lo))*hgt;
 const pathAt=f=>g.med.map((v,i)=>(i?'L':'M')+X(i).toFixed(1)+','+Y(v*f).toFixed(1)).join(' ');
 const band=(fa,fb,op)=>`<path d="${pathAt(fb)} ${g.med.map((v,i)=>'L'+X(12-i).toFixed(1)+','+Y(g.med[12-i]*fa).toFixed(1)).join(' ')} Z" fill="${col}" opacity="${op}"/>`;
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
 pushLog({k:'measure',name:'测量',s:bnow(),e:bnow(),amt:w,unit:'kg',detail:w+'kg / '+hh+'cm / '+hd+'cm',rec:curCarer});
 MEASURE_HIST.unshift({d:'2026-'+CARE_TODAY,w:w,h:hh,c:hd,p:'P62',rec:curCarer});
 closeSheet('sheetBabyMeasure');drawGrowth('w');renderMeasureHist();
 toast('✔ 已描点生长曲线 · 下次体检提醒已更新（测量量可二次修改）');}
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
function vaxRow(x,i){const dd=vxDays(x.due);
 return `<div class="flex items-center gap-2.5 ${x.st==='done'?'opacity-55':''} bg-slate-50 dark:bg-slate-800/60 rounded-xl px-3 py-2.5"><span>${x.st==='done'?'✅':x.st==='late'?'⚠️':'💉'}</span>
  <div class="flex-1 min-w-0"><b>${x.n} ${x.dose} <span class="text-[8px] px-1.5 py-0.5 rounded-full ${x.kind==='免规'?'bg-sky-100 text-sky-600 dark:bg-sky-500/15':'bg-amber-100 text-amber-600 dark:bg-amber-500/15'}">${x.kind}</span></b>
  <div class="text-[9px] text-slate-400">${x.st==='done'?'已完成 · 凭证已归档':x.st==='late'?'已过计划日期 '+(-dd)+' 天 · 尽快补种':'计划 '+x.due+' · '+(dd>0?'还有 '+dd+' 天':'即将到期')+' · 提前 '+x.lead+' 天提醒'}</div></div>
  ${x.st!=='done'?`<button class="mini-btn !text-[10px]" onclick="vaxDone(${i})">完成</button>`:`<button class="text-[10px] text-slate-400 font-bold" onclick="toast('查看接种凭证照片（本地图档）')">凭证</button>`}</div>`;}
function renderVax(){const el=$('#vaxList');if(!el)return;
 el.innerHTML=VAX.filter(x=>x.st!=='done').slice(0,3).map(x=>`<div class="flex items-center gap-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 px-2.5 py-1.5"><span>${x.st==='late'?'⚠️':'💉'}</span><div class="flex-1 min-w-0"><b class="block truncate text-[10px]">${x.n} ${x.dose}</b><span class="text-[8px] text-slate-400">${x.due.slice(5)} · ${vxDays(x.due)>0?'D-'+vxDays(x.due):'已到期'}</span></div></div>`).join('');
 const pl=VAX.filter(x=>x.st!=='done').length,nx=VAX.filter(x=>x.st==='plan').sort((a,b)=>a.due.localeCompare(b.due))[0];
 const s=$('#vxSummary');if(s)s.textContent='待接种 '+pl+' 剂 · 下一剂 '+(nx?nx.due.slice(5)+' '+nx.n:'—')+'（提前 7 天提醒，联动重要日子倒数）';
 const f=$('#vaxFull');if(f)f.innerHTML=VAX.map((x,i)=>[x,i]).filter(([x])=>vaxView==='all'||(vaxView==='plan'?x.st!=='done':x.st==='done')).map(([x,i])=>vaxRow(x,i)).join('')||'<div class="text-center text-slate-400 py-6 text-[11px]">暂无该状态疫苗</div>';}
function vaxTab(k){vaxView=k;[['plan','vaxT0'],['done','vaxT1'],['all','vaxT2']].forEach(([v,id])=>{const b=$('#'+id);b.className=(v===k?'seg-on ':'flex-1 rounded-lg py-1.5 text-slate-500')+' flex-1 rounded-lg py-1.5';});renderVax();}
function vaxDone(i){VAX[i].st='done';renderVax();toast('✔ 已记录接种 · 下一针提醒已自动写入「重要日子」（联动 L10）');}
function getChip(box){const b=$('#'+box+' .chip-on');return b?(b.dataset.v||b.textContent.trim()):'';}
function oneChip(box,el){$$('#'+box+' .chip').forEach(b=>b.classList.remove('chip-on'));el.classList.add('chip-on');}
function addVax(){const nm=$('#vaName').value.trim();if(!nm){toast('先填疫苗名称');return;}
 VAX.unshift({n:nm,dose:$('#vaDose').value.trim()||'第1剂',due:$('#vaDate').value||'2026-10-20',st:'plan',kind:getChip('vaKind')||'免规',lead:+getChip('vaLead')||7});
 $('#vaName').value='';$('#vaDose').value='';closeSheet('sheetVaxAdd');renderVax();
 toast('💉 已加入计划 · 倒数提醒与提前 '+VAX[0].lead+' 天提醒已生成（联动 L10）');}
function renderWeekBaby(){const el=$('#weekBars');if(!el)return;const d=curBaby===0?[[6,13.8],[7,14.1],[5,13.2],[7,14.6],[6,13.5],[8,14.0],[7,13.6]]:[[5,12.8],[6,13.0],[5,13.4],[6,12.6],[5,13.1],[6,13.5],[5,13.2]];
 el.innerHTML=d.map(([c,h],i)=>`<div class="flex-1 flex items-end gap-[2px] h-full" title="${i===6?'今天':'前'+(6-i)+'天'}：喂养${c}次 · 睡眠${h}h"><span class="w-1/2 rounded-t bg-brand-500/80" style="height:${c*11}%"></span><span class="w-1/2 rounded-t bg-mint/70" style="height:${(h-11.5)*22}%"></span></div>`).join('');}
/* —— 照护多维汇总 —— */
let bsR='d',bsK='all';
function bsLogs(){return bsR==='d'?logsOf(CARE_TODAY):Object.values(ALLLOGS[curBaby]).flat();}
function renderStats(){const el=$('#bsTot');if(!el)return;
 const F=bsR==='d'?1:bsR==='w'?2.4:10.5;const ls=bsLogs();
 const cnt=Math.round(ls.length*F);
 const ml=Math.round(ls.filter(r=>r.ml).reduce((a,r)=>a+r.ml,0)*F);
 const dur=ls.reduce((a,r)=>a+(r.dur||0),0);
 const care=Math.round(ls.filter(r=>['bath','play','swim','diaper'].includes(r.k)).reduce((a,r)=>a+(r.dur||3),0)*F);
 const night=ls.filter(r=>t2m(r.s)<300||t2m(r.s)>=1300).length;
 el.innerHTML=`<div class="card !py-2"><b class="text-base">${cnt}</b><div class="text-slate-400">记录条</div></div>
  <div class="card !py-2"><b class="text-base text-brand-500">${ml}</b><div class="text-slate-400">奶量ml</div></div>
  <div class="card !py-2"><b class="text-base text-mint">${Math.round(dur/6)}h</b><div class="text-slate-400">睡眠h</div></div>
  <div class="card !py-2"><b class="text-base text-sun">${Math.round(care/6)/10}h</b><div class="text-slate-400">照护h${bsR!=='d'?'·估':''}</div></div>`;
 const g={};ls.forEach(r=>{const k=r.k;g[k]=g[k]||{c:0,ml:0,dur:0};g[k].c++;g[k].ml+=r.ml||0;g[k].dur+=r.dur||0;});
 const keys=Object.keys(g).sort((a,b)=>g[b].c-g[a].c).filter(k=>bsK==='all'||k===bsK);
 $('#bsKindHint').textContent=bsK==='all'?'全部事件':evDef(bsK).n;
 $('#bsKindChips').innerHTML=['all',...new Set(ls.map(r=>r.k))].map(k=>`<button class="chip whitespace-nowrap ${k===bsK?'chip-on':''}" onclick="bsK='${k}';renderStats()">${k==='all'?'全部':evDef(k).n}</button>`).join('');
 const mx=Math.max(...Object.values(g).map(x=>x.c),1);
 $('#bsEvents').innerHTML=keys.map(k=>{const E=evDef(k),x=g[k];
  const val=x.ml?x.ml+'ml':x.dur?hms(x.dur):x.c+'次';
  return `<div class="flex items-center gap-2.5 text-[11px]"><span class="w-5 text-center">${E.ic}</span><span class="w-16 shrink-0 text-slate-500 dark:text-slate-400">${E.n}</span>
   <div class="flex-1 h-2 rounded-full bg-slate-100 dark:bg-slate-800 overflow-hidden"><span class="block h-full grad rounded-full" style="width:${x.c/mx*100}%"></span></div>
   <b class="w-10 text-right">${x.c}次</b><span class="w-14 text-right text-slate-400">${val}</span></div>`}).join('')||'<div class="text-center text-slate-400 py-3 text-[11px]">暂无数据</div>';
 const kinds=[...new Set(ls.map(r=>r.k))].slice(0,7);
 let clock='<div class="text-[8px] text-slate-400 grid" style="grid-template-columns:44px repeat(24,1fr)">';
 for(let h=0;h<24;h++)clock+=`<span class="${h%6?'invisible':''} text-center">${h}</span>`;
 kinds.forEach(k=>{clock+=`<span class="text-[8px] text-slate-500 self-center truncate">${evDef(k).ic}${evDef(k).n.slice(0,2)}</span>`;
  for(let h=0;h<24;h++){const n=ls.filter(r=>r.k===k&&+r.s.slice(0,2)===h).length;
   clock+=`<span class="w-2 h-2 m-auto rounded-full" style="background:${n?'var(--accent)':'#e2e8f0'};opacity:${n?Math.min(1,.25+n*.3):.5}"></span>`}});
 clock+='</div>';$('#bsClock').innerHTML=clock;
 const T=curBaby===0?[[6,13.8,760],[7,14.1,820],[5,13.2,690],[7,14.6,880],[6,13.5,740],[8,14.0,910],[7,13.6,860]]:[[5,12.8,900],[6,13.0,940],[5,13.4,880],[6,12.6,920],[5,13.1,900],[6,13.5,950],[5,13.2,910]];
 $('#bsTrend').innerHTML=T.map(([c,h,m],i)=>`<div class="flex-1 flex items-end gap-[2px] h-full" title="${i===6?'今天':'前'+(6-i)+'天'}：喂养${c}次 · 睡眠${h}h · 奶量${m}ml"><span class="w-1/3 rounded-t bg-brand-500/80" style="height:${c*11}%"></span><span class="w-1/3 rounded-t bg-mint/70" style="height:${(h-11.5)*22}%"></span><span class="w-1/3 rounded-t bg-sun/70" style="height:${m/10}%"></span></div>`).join('');
 $('#bsInsight').innerHTML=`<div class="row-title">解读与建议</div>
  <div class="mt-1.5 space-y-1 text-[11px] text-slate-400 leading-5">
   <div>· 奶量较${bsR==='d'?'昨日':bsR==='w'?'上周':'上月'} <b class="text-teal-600">+6%</b> · 生长曲线跟随 P62 通道</div>
   <div>· 睡眠夜觉 ${bsR==='d'?'11h/段':bsR==='w'?'13.4h/天':'13.2h/天'} · 夜奶 ${bsR==='d'?'—':'2 次'}，可关注戒夜奶窗口</div>
   <div>· 尿布：便 ${ls.filter(r=>r.k==='diaper'&&r.dia!=='pee').length} 次均正常色 · 无异常预警</div></div>
  <button class="mt-3 w-full py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold text-slate-500" onclick="toast('🤖 AI 育儿周报：Opt-in · 仅上传聚合统计（原始记录不出本机），联动 AI 安全规范（V1.x）')">🤖 生成育儿周报解读</button>`;}
function bsRange(r){bsR=r;[['d','bsT0'],['w','bsT1'],['m','bsT2']].forEach(([v,id])=>{const b=$('#'+id);b.className=(v===r?'seg-on ':'flex-1 rounded-lg py-1.5 text-slate-500')+' flex-1 rounded-lg py-1.5';});renderStats();}
/* —— 汇总 init 时渲染一次即可，切换时再渲染 —— */
function renderCare(){renderCycle();renderSym();renderSymHist();renderCycStats();renderBabyHero();renderEvGrid();renderBabyToday();renderBabies();renderBabySwitch();drawGrowth('w');renderMeasureHist();renderVax();renderWeekBaby();renderBabyDay();renderStats();}
