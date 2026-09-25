/* ================= 运动记录 ================= */
let _he={};
function htExOpen(idx){
  const e=idx!=null?HT.exs[idx]:null; _he={idx:idx, type:e?e.t:HT.exTypes[0], mode:'km'};
  openSheet('sheetHEx');
  hPut('heTitle',e?('修改 '+e.d+' 的运动'):'记录运动');
  hRenderExTypes(); hDateRow('heDateRow',e?e.d:htDay(0));
  const set=(id,v)=>{const el=document.getElementById(id);if(el)el.value=v!=null?v:''};
  set('heKm',e&&e.km!=null?e.km:''); set('heMin',e?e.min:''); set('heKcal',e?e.kcal:''); set('heNote',e&&e.note?e.note:'');
  hExSrcRow(e?e.src:'手动');
  const mb=document.querySelector('#sheetHEx [data-m="km"]'); if(mb)hExMode('km',mb);
}
function hRenderExTypes(){const el=document.getElementById('heTypeRow');if(!el)return;
  el.innerHTML=HT.exTypes.map(t=>`<button class="tag-chip shrink-0 ${t===_he.type?'on':''}" data-t="${t}">${t}</button>`).join('');
  el.querySelectorAll('button').forEach(b=>b.onclick=()=>{_he.type=b.dataset.t;hRenderExTypes();hExCalc()})}
function hExSrcRow(cur){const el=document.getElementById('heSrcRow');if(!el)return;
  el.innerHTML=['手动','计时','设备导入'].map(s=>`<button class="tag-chip ${s===cur?'on':''}" data-s="${s}">${s}</button>`).join('');
  el.querySelectorAll('button').forEach(b=>b.onclick=()=>{[...el.children].forEach(x=>x.classList.remove('on'));b.classList.add('on')})}
function hExMode(m,el){if(!el)return;hseg(el);_he.mode=m;
  const km=document.getElementById('heKm'),mn=document.getElementById('heMin'),pc=document.getElementById('hePace');
  if(!km)return;
  km.readOnly=(m==='min'); mn.readOnly=(m==='pace'); pc.readOnly=(m==='km');
  pc.type='text'; hExCalc()}
function hExCalc(){
  const kmEl=document.getElementById('heKm'); if(!kmEl)return;
  const g=el=>parseFloat(el.value);
  let km=g(kmEl), mn=g(document.getElementById('heMin')), pc=parsePace(document.getElementById('hePace').value);
  const m=_he.mode||'km';
  if(m==='km'&&km>0&&mn>0)pc=mn/km;
  if(m==='min'&&mn>0&&pc!=null)km=mn/pc;
  if(m==='pace'&&km>0&&pc!=null)mn=km*pc;
  /* 派生项即使只读也要回显（否则残留上一模式的值） */
  const set=(el,v)=>{if(el&&v!=null&&v!=='')el.value=v};
  set(document.getElementById('hePace'), pc!=null?fmtPace(pc):null);
  set(document.getElementById('heKm'), km!=null?+km.toFixed(2):null);
  set(document.getElementById('heMin'), mn!=null?Math.round(mn):null);
  const out=document.getElementById('heCalc');
  if(!HT.distTypes.includes(_he.type)){out.textContent='该类型不计距离 · 只需填时长';return}
  out.textContent=(km>0&&mn>0&&pc!=null)?('三值闭合 · 均配速 '+fmtPace(pc)+' /km · 估算消耗 '+htKcal(_he.type,mn,km)+' kcal'):'还需填一项';
}
function htExSave(again){
  const kmEl=document.getElementById('heKm'); if(!kmEl)return;
  const km=_he.type&&HT.distTypes.includes(_he.type)?parseFloat(kmEl.value)||null:null;
  const mn=parseFloat(document.getElementById('heMin').value)||null;
  if(!mn){toast('至少填一个时长');return}
  const pc=km&&mn?mn/km:parsePace(document.getElementById('hePace').value);
  const kc=parseFloat(document.getElementById('heKcal').value)||htKcal(_he.type,mn,km);
  const d=(document.getElementById('heDateRow').dataset.v)||htDay(0);
  const srcEl=document.querySelector('#heSrcRow .on');
  const rec={d:d,t:_he.type,km:km,min:mn,pace:(km&&pc!=null)?fmtPace(pc):null,kcal:kc,
    note:document.getElementById('heNote').value.trim(),src:srcEl?srcEl.dataset.s:'手动'};
  if(_he.idx!=null)HT.exs[_he.idx]=rec; else HT.exs.push(rec);
  HT.exs.sort((a,b)=>b.d.localeCompare(a.d));
  hLog({k:'ex',t:rec.t+(rec.km?' '+rec.km+' km':'')+' · '+rec.min+'min'});
  renderHealth();
  toast('已存 · 时间账本「运动」入账 + L11 趋势重算（联动 L7 周目标）');
  if(again){_he.keepDate=d; _he.idx=null; htExOpen(); hDateRow('heDateRow',d); return}
  closeSheet('sheetHEx');
}
function hRenderExLog(){
  const fr=document.getElementById('exFilterRow');
  if(fr){const types=['全部'].concat(HT.exTypes);
    fr.innerHTML=types.map(t=>`<button class="tag-chip shrink-0 ${t===HT.exFilter?'on':''}" data-t="${t}">${t}</button>`).join('');
    fr.querySelectorAll('button').forEach(b=>b.onclick=()=>{HT.exFilter=b.dataset.t;hRenderExLog()})}
  const today=htDay(0);
  const inR=e=>HT.exRange==='w'?e.d>=htDay(6):e.d>=htDay(29);
  const list=HT.exs.filter(e=>inR(e)&&(HT.exFilter==='全部'||e.t===HT.exFilter));
  hPut('elN',list.length); hPut('elMin',list.reduce((a,b)=>a+b.min,0));
  hPut('elKm',list.reduce((a,b)=>a+(b.km||0),0).toFixed(1)); hPut('elPc',list.reduce((a,b)=>a+(b.kcal||0),0));
  const box=document.getElementById('exList');
  if(box)box.innerHTML=list.length?list.map(e=>{const i=HT.exs.indexOf(e);
    return `<div class="px-4 py-2.5 flex items-center gap-2.5 active:bg-slate-50 dark:active:bg-slate-800/60" onclick="htExOpen(${i})">
      <span class="w-8 h-8 rounded-xl bg-amber-500/10 text-amber-500 flex items-center justify-center shrink-0">${hExIco(e.t)}</span>
      <div class="flex-1 min-w-0"><b class="text-[12.5px] block truncate">${e.t}${e.km?' · '+e.km+' km':''} · ${e.min}min</b>
        <span class="text-[9px] text-slate-400">${e.d} ${htWd(e.d)} · ${e.kcal?e.kcal+' kcal · ':''}来源 ${e.src}${e.note?' · '+e.note:''}</span></div>
      ${e.pace?`<b class="text-[11px] shrink-0" style="color:var(--accent)">${e.pace}</b>`:''}
      <button class="text-[10px] text-rose-400 font-bold shrink-0" onclick="event.stopPropagation();hExDel(${i})">删除</button></div>`}).join('')
    :'<div class="text-center text-slate-400 text-[11px] py-6">该区间暂无运动记录 · 点「＋ 记一笔」或开始计时</div>';
  const pbox=hChartBox('paceSvg',300,70);
  if(pbox.s){const ds=HT.exs.filter(e=>e.km).slice(0,12).reverse();
    if(ds.length<2)pbox.s.innerHTML='<text x="8" y="40" font-size="9" fill="#94a3b8">距离类记录不足 2 次 · 暂无配速曲线</text>';
    else{const W=pbox.W,H=pbox.H,vs=ds.map(e=>e.min/e.km), mn=Math.min(...vs)-.4, mx=Math.max(...vs)+.4;
      const pts=vs.map((v,i)=>[10+i*((W-20)/Math.max(1,vs.length-1)), (H-12)-(v-mn)/(mx-mn)*(H-26)]);
      pbox.s.innerHTML=`<polyline points="${pts.map(p=>p[0].toFixed(1)+','+p[1].toFixed(1)).join(' ')}" fill="none" stroke="var(--accent)" stroke-width="2" stroke-linecap="round"/>`+
        pts.map((p,i)=>`<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="2.4" fill="var(--accent)" title="${ds[i].d} ${ds[i].pace}"/>`).join('')+
        `<text x="4" y="10" font-size="8" fill="#94a3b8">最快 ${fmtPace(Math.min(...vs))}</text><text x="${(W-88).toFixed(0)}" y="${H-3}" font-size="8" fill="#94a3b8">最慢 ${fmtPace(Math.max(...vs))}</text>`}}
  hPut('heroEx',HT.exs.filter(e=>e.d===today).reduce((a,b)=>a+b.min,0));
  const out=document.getElementById('spOut');
  if(out){const km=parseFloat((document.getElementById('spKm')||{}).value), mn=parseFloat((document.getElementById('spMin')||{}).value);
    out.textContent=km>0&&mn>0?('均配速 '+fmtPace(mn/km)+' /km · 约 '+htKcal(_he.type||'跑步',mn,km)+' kcal'):''}
}
function hExDel(i){const e=HT.exs[i];if(!confirmRow('删除 '+e.d+' 的'+e.t+'记录'))return;
  HT.exs.splice(i,1); renderHealth(); toast('已删除 · 账本与统计重算')}
function sportCalc(){
  const km=parseFloat((document.getElementById('spKm')||{}).value), mn=parseFloat((document.getElementById('spMin')||{}).value);
  const out=document.getElementById('spOut'); if(!out)return;
  if(!(km>0)||!(mn>0)){out.textContent='请填距离与时长';return}
  hPut('heroEx',mn); hLog({k:'ex',t:'跑步 '+km+' km · '+mn+'min'});
  renderHealth(); toast('已存 · 均配速 '+fmtPace(mn/km)+' /km · 入时间账本「运动」');
}
let _ext0=null;
function exTimerToggle(){
  const btn=document.getElementById('exTimerBtn');
  if(!_ext0){_ext0=Date.now(); if(btn)btn.textContent='结束并记录'; toast('计时开始 · 复用日程进行中/悬浮计时条基础设施（L1）'); return}
  const mins=Math.max(1,Math.round((Date.now()-_ext0)/60000)); _ext0=null;
  if(btn)btn.textContent='开始计时';
  htExOpen(); const mn=document.getElementById('heMin'); if(mn)mn.value=mins;
  const s=document.querySelector('#heSrcRow [data-s="计时"]'); if(s){[...s.parentElement.children].forEach(x=>x.classList.remove('on'));s.classList.add('on')}
  hExCalc(); toast('计时结束 '+mins+' 分钟 · 已回填表单，确认后入账');
}
/* ================= 睡眠 ================= */
function hRenderSleep(){
  const last=HT.sleeps[HT.sleeps.length-1]; if(!last)return;
  hPut('slLastDate',last.d+' · '+last.b+' 入睡 · 质量 '+last.q);
  const bar=document.getElementById('slStageBar');
  if(bar)bar.innerHTML=HT.stageLog?[['深睡','bg-indigo-800',last.st.deep],['浅睡','bg-brand-500',last.st.light],['REM','bg-indigo-300',last.st.rem],['清醒','bg-slate-300 text-slate-600',last.st.awake]]
      .map(([n,c,v])=>`<span style="width:${(v/(last.st.deep+last.st.light+last.st.rem+last.st.awake)*100).toFixed(0)}%" class="${c}">${n}</span>`).join('')
      :'<span class="w-full bg-slate-100 dark:bg-slate-800 text-slate-400 flex items-center justify-center">未记录分期 · 设置中可开启逐段补录</span>';
  const meta=document.getElementById('slMeta');
  if(meta)meta.innerHTML=`<span>${last.b} 入睡</span><span>${last.e} 醒来</span><span>共 ${last.h}h · 达标 ${last.h>=HT.goalSleep?'是':'否'}</span>`;
  hPut('slStageTip',HT.stageLog?'四段之和 = 总时长':'未开启');
  const b2=document.getElementById('slBars2');
  if(b2)b2.innerHTML=HT.sleeps.map(s=>`<div class="flex-1 h-full flex flex-col items-center justify-end gap-1" title="${s.d} ${s.h}h"><span class="text-[8px] text-slate-400">${s.h}</span><span style="height:${Math.min(78,s.h/10*78)}%" class="w-full rounded-t ${s.h>=HT.goalSleep?'bg-emerald-400':s.h>=6.5?'bg-indigo-400':'bg-amber-400'}"></span></div>`).join('');
  const wd=document.getElementById('slWdRow');
  if(wd)wd.innerHTML=HT.sleeps.map(s=>`<span class="flex-1 text-center">${htWd(s.d).slice(1)}</span>`).join('');
  hPut('slT2',HT.goalSleep+'h');
  const isOndt=s=>s.b>='18:00'&&s.b<=HT.bedLine;
  const ondt=HT.sleeps.filter(isOndt).length;
  let best=0,run=0;HT.sleeps.forEach(s=>{if(s.h>=HT.goalSleep){run++;best=Math.max(best,run)}else run=0});
  hPut('snOndt',ondt); hPut('snAvg',(HT.sleeps.reduce((a,b)=>a+b.h,0)/HT.sleeps.length).toFixed(1)); hPut('snBest',best+' 天');
  const list=document.getElementById('slList');
  if(list)list.innerHTML=HT.sleeps.slice().reverse().map(s=>{const i=HT.sleeps.indexOf(s);
    return `<div class="px-4 py-2.5 flex items-center gap-2.5 active:bg-slate-50 dark:active:bg-slate-800/60" onclick="hSleepOpen(${i})">
      <span class="w-11 text-[11px] font-mono text-slate-400 shrink-0">${s.d}</span>
      <b class="text-[13px] w-12 shrink-0">${s.h.toFixed(1)}h</b>
      <span class="text-[10px] text-slate-400 flex-1">${s.b} → ${s.e}${s.b>s.e?' · 跨天':''}</span>
      <span class="text-[10px] px-1.5 py-0.5 rounded-md shrink-0 bg-slate-100 dark:bg-slate-800 ${s.q==='优'?'text-emerald-500':s.q==='良'?'text-brand-500':'text-amber-500'}">${s.q}</span>
      <span class="text-slate-300">›</span></div>`}).join('');
  hPut('slT',HT.goalSleep+'h · '+HT.bedLine+' 前'); hPut('slOndt',ondt);
  hPut('heroSleep',last.h.toFixed(1));
}
let _hs={};
function hSleepOpen(idx){
  const s=idx!=null?HT.sleeps[idx]:HT.sleeps[HT.sleeps.length-1]; _hs={idx:idx};
  openSheet('sheetHSleep');
  hPut('hsTitle',idx!=null?('修改 '+s.d+' 的睡眠'):'记录睡眠');
  hDateRow('hsDateRow',s?s.d:htDay(0));
  const bh=s?+s.b.slice(0,2):23, bm=s?+s.b.slice(3,5):10, eh=s?+s.e.slice(0,2):6, em=s?+s.e.slice(3,5):30;
  hWheel('hsBH',hHours(),bh); hWheel('hsBM',hMins(),Math.round(bm/5));
  hWheel('hsEH',hHours(),eh); hWheel('hsEM',hMins(),Math.round(em/5));
  const q=document.getElementById('hsQList');
  if(q){q.innerHTML=['优','良','中','差'].map(x=>`<button class="tag-chip ${x===(s?s.q:'良')?'on':''}" data-q="${x}">${x}</button>`).join('');
    q.querySelectorAll('button').forEach(b=>b.onclick=()=>{[...q.children].forEach(x=>x.classList.remove('on'));b.classList.add('on')})}
  const tg=document.getElementById('hsStageTg'); if(tg)tg.classList.toggle('on',!!HT.stageLog);
  const stip=document.getElementById('hsStageTip'); if(stip)stip.textContent=HT.stageLog?'已开启':'未开启';
  const wrap=document.getElementById('hsStageWrap'); if(wrap)wrap.classList.toggle('hidden',!HT.stageLog);
  const st=(s&&s.st)||{deep:70,light:200,rem:90,awake:30};
  hWheel('hsDeep',hNums(0,300,5),Math.round(st.deep/5)); hWheel('hsLight',hNums(0,480,5),Math.round(st.light/5));
  hWheel('hsRem',hNums(0,240,5),Math.round(st.rem/5)); hWheel('hsAwake',hNums(0,120,5),Math.round(st.awake/5));
  HT._wb=hSleepDur; hSleepDur();
}
function hSleepDur(){
  const el=document.getElementById('hsDur'); if(!el||el.offsetParent===null)return;
  const bh=hWv('hsBH'), bm=hWv('hsBM'), eh=hWv('hsEH'), em=hWv('hsEM');
  if(bh==null)return;
  let mins=((+eh)*60+(+em))-((+bh)*60+(+bm)); if(mins<=0)mins+=1440;
  const wrap=document.getElementById('hsStageWrap');
  let tx=(mins/60).toFixed(1)+' 小时'+(bh>eh?' · 跨天':'')+' · 按时入睡 '+(('0'+bh).slice(-2)+':'+('0'+bm).slice(-2)<=HT.bedLine?'是':'否');
  if(wrap&&!wrap.classList.contains('hidden')){
    const st=(hNw('hsDeep')||0)+(hNw('hsLight')||0)+(hNw('hsRem')||0)+(hNw('hsAwake')||0);
    tx+=st?(' · 分期合计 '+st+'min'+(Math.abs(st-mins)>20?'（与总时长差 '+Math.abs(st-mins)+'min，请核对）':'（与总时长一致）')):'';
  }
  el.textContent=tx;
}
function hStageToggle(el){el.classList.toggle('on');
  const wrap=document.getElementById('hsStageWrap'); if(wrap)wrap.classList.toggle('hidden',!el.classList.contains('on'));
  const stip=document.getElementById('hsStageTip'); if(stip)stip.textContent=el.classList.contains('on')?'已开启':'未开启';
  HT.stageLog=el.classList.contains('on'); hSleepDur(); hRenderSleep();}
function hSleepSave(){
  const d=(document.getElementById('hsDateRow').dataset.v)||htDay(0);
  const bh=String(hWv('hsBH')), bm=String(hWv('hsBM')), eh=String(hWv('hsEH')), em=String(hWv('hsEM'));
  let mins=((+eh)*60+(+em))-((+bh)*60+(+bm)); if(mins<=0)mins+=1440;  const q=(document.querySelector('#hsQList .on')||{}).dataset;
  const on=document.getElementById('hsStageTg').classList.contains('on');
  const rec={d:d, b:bh+':'+bm, e:eh+':'+em, h:+(mins/60).toFixed(1), q:q.q||'良',
    st:on?{deep:hNw('hsDeep'),light:hNw('hsLight'),rem:hNw('hsRem'),awake:hNw('hsAwake')}:null};
  if(_hs.idx!=null)HT.sleeps[_hs.idx]=rec; else {HT.sleeps.push(rec);HT.sleeps.sort((a,b)=>a.d.localeCompare(b.d))}
  HT.logs.unshift({k:'sleep',t:'睡眠 '+rec.h+'h · '+rec.b+' – '+rec.e,d:d,at:'刚刚'});
  closeSheet('sheetHSleep'); renderHealth();
  toast('已记录 '+d+' 睡眠 '+rec.h+'h · 达标 '+(rec.h>=HT.goalSleep?'是':'否')+' · 入仪表盘与周报');
}
/* ================= 用药 ================= */
function hMedPlan(d){let t=0,o=0;(HT.drugs||[]).forEach(dg=>{const dn=(dg.done||{})[d]||[];
  dg.times.forEach(x=>{t++;if(dn.includes(x))o++})});return {t:t,o:o}}
function hRenderMeds(){
  const today=htDay(0), plan=hMedPlan(today);
  hPut('medTotal',plan.t); hPut('medDone',plan.o);
  hRenderMedChips();
  const box=document.getElementById('medCards'); if(!box)return;
  box.innerHTML=HT.drugs.length?HT.drugs.map((dg,gi)=>{const dn=(dg.done||{})[today]||[];
    return `<div class="card !p-0 overflow-hidden">
      <div class="px-4 pt-3 pb-2 flex items-center gap-2.5">
        <span class="w-8 h-8 rounded-xl ${HT_DOT[dg.dot]||HT_DOT.rose} flex items-center justify-center shrink-0">${hSvg('drug','w-4 h-4')}</span>
        <div class="flex-1 min-w-0"><b class="text-[13px] block truncate">${dg.n}</b>
          <span class="text-[9px] text-slate-400">${dg.spec} · 每次 ${dg.dose} ${dg.unit}${dg.end?' · 疗程至 '+dg.end:''}</span></div>
        <button class="text-[10px] font-bold text-slate-400 shrink-0" onclick="hDrugDel(${gi})">删除</button></div>
      <div class="px-4 pb-3 space-y-1.5">
        ${dg.times.map(t=>{const ok=dn.includes(t);
          return `<div class="flex items-center gap-2 rounded-xl px-3 py-2 ${ok?'bg-emerald-50 dark:bg-emerald-500/10':'bg-slate-50 dark:bg-slate-800/60'}">
            <span class="text-[11px] font-mono shrink-0 ${ok?'text-emerald-600 dark:text-emerald-400':'text-slate-500'}">${t}</span>
            <span class="flex-1 text-[10px] ${ok?'text-emerald-600 dark:text-emerald-400':'text-slate-400'}">${ok?'已服用 · 可撤销':'待服用'}</span>
            <button class="mini-btn !py-1" onclick="hMedTap(${gi},'${t}')">${ok?'撤销':'打卡'}</button></div>`}).join('')}
        <div class="flex items-center justify-between pt-1">
          <span class="text-[9px] text-slate-400">按时刻提醒</span>
          <span class="toggle ${dg.rem?'on':''}" onclick="hDrugRem(${gi},this)"></span></div>
        <div class="pt-1"><div class="text-[9px] text-slate-400 mb-1">近 7 天打卡</div>
          <div class="flex gap-1">${Array.from({length:7},(_,i)=>{const d=htDay(6-i), p=hMedPlan(d);
            const full=p.t&&p.o>=p.t, part=p.o>0&&!full;
            return `<span class="flex-1 h-5 rounded-md ${full?'bg-emerald-500':part?'bg-amber-300':'bg-slate-100 dark:bg-slate-800'}" title="${d} ${p.o}/${p.t}"></span>`}).join('')}</div></div>
      </div></div>`}).join('')
    :'<div class="card text-[11px] text-slate-400 text-center py-6">还没有药品档案 · 点下方「＋ 新增药品」</div>';
}
function hRenderMedChips(){
  const el=document.getElementById('medChips'); if(!el)return; const today=htDay(0); const items=[];
  HT.drugs.forEach((dg,gi)=>dg.times.forEach(t=>items.push({gi:gi,t:t,ok:((dg.done||{})[today]||[]).includes(t),n:dg.n})));
  el.innerHTML=items.length?items.slice(0,5).map(x=>`<button class="tag-chip !py-1 max-w-full truncate ${x.ok?'on':''}" onclick="hMedTap(${x.gi},'${x.t}')">${x.t} ${x.n} · ${x.ok?'已服':'待服'}</button>`).join('')
    +(items.length>5?`<button class="text-[10px] text-slate-400 self-center shrink-0" onclick="htNav('p-med')">+${items.length-5} 全部</button>`:'')
    :'<span class="text-[10px] text-slate-400">暂无用药计划 · 去「用药」建档</span>';
}
function hMedRate7(){let t=0,o=0;for(let i=0;i<7;i++){const p=hMedPlan(htDay(i));t+=p.t;o+=p.o}return t?Math.round(o/t*100):0}
function hMedTap(gi,t){
  const dg=HT.drugs[gi], today=htDay(0); dg.done=dg.done||{}; const dn=dg.done[today]=dg.done[today]||[];
  const i=dn.indexOf(t);
  if(i>=0){dn.splice(i,1);toast(t+' · '+dg.n+' 已撤销打卡')}
  else{dn.push(t);hLog({k:'drug',t:dg.n+' · '+t+' 已服用'});toast(t+' · '+dg.n+' 打卡成功')}
  renderHealth();
  if(document.getElementById('hdlList')&&!document.getElementById('sheetHDrugLog').classList.contains('hidden'))hRenderDrugLog();
}
function hDrugRem(gi,el){el.classList.toggle('on');HT.drugs[gi].rem=el.classList.contains('on');renderHealth();
  toast(HT.drugs[gi].rem?'已排程到提醒中心 · 文案「该吃药了 · '+HT.drugs[gi].n+'」':'该药提醒已关闭')}
function hMedOpenSheet(){openSheet('sheetHDrugLog');hRenderDrugLog()}
function hRenderDrugLog(){
  const today=htDay(0), box=document.getElementById('hdlList'); if(!box)return;
  const p=hMedPlan(today);
  hPut('hdlSub',today+' · '+HT.drugs.length+' 种药 · 计划 '+p.t+' 次 · 已服 '+p.o+' 次');
  box.innerHTML=HT.drugs.map((dg,gi)=>{const dn=(dg.done||{})[today]||[];
    return `<div class="card !py-2.5 flex items-center gap-2 flex-wrap">
      <div class="flex-1 min-w-[100px]"><b class="text-[12.5px] block">${dg.n}</b><span class="text-[9px] text-slate-400">${dg.times.join(' / ')} · 每次 ${dg.dose}${dg.unit}</span></div>
      ${dg.times.map(t=>{const ok=dn.includes(t);return `<button class="tag-chip !py-1 ${ok?'on':''}" onclick="hMedTap(${gi},'${t}')">${t} ${ok?'已服':'待服'}</button>`}).join('')}</div>`}).join('')
    ||'<div class="text-[11px] text-slate-400 text-center py-4">暂无药品</div>';
}
let hdTimes=[];
function hDrugOpen(){
  hdTimes=['08:00']; openSheet('sheetHDrug'); hRenderDrugTimes();
  hWheel('hdAddTime',hTimes(),32); hWheel('hdDose',hNums(0.5,6,0.5),1);
}
function hRenderDrugTimes(){const el=document.getElementById('hdTimeRow');if(!el)return;
  el.innerHTML=hdTimes.length?hdTimes.map((t,i)=>`<button class="tag-chip on" onclick="hdTimes.splice(${i},1);hRenderDrugTimes()">${t} ✕</button>`).join('')
    :'<span class="text-[10px] text-slate-400">尚未选择时刻</span>'}
function hdAddT(){const v=hWv('hdAddTime'); if(!v)return; if(hdTimes.includes(v)){toast('该时刻已存在');return}
  hdTimes.push(v); hdTimes.sort(); hRenderDrugTimes(); toast('已加入 '+v)}
function hDrugSave(){
  const n=(document.getElementById('hdName').value||'').trim(); if(!n){toast('请填写药品名称');return}
  const spec=(document.getElementById('hdSpec').value||'').trim()||'—';
  const rem=document.getElementById('hdRem').classList.contains('on');
  const end=document.getElementById('hdEnd').value||'';
  HT.drugs.push({n:n, spec:spec, unit:'片', dose:hNw('hdDose')||1, times:hdTimes.length?hdTimes.slice():['08:00'],
    rem:rem, dot:'rose', end:end, done:{}});
  document.getElementById('hdName').value=''; document.getElementById('hdSpec').value='';
  closeSheet('sheetHDrug'); renderHealth();
  toast('已建档 '+(rem?'· 提醒已排程到通知中心':'· 未开启提醒'));
}
function hDrugDel(gi){const dg=HT.drugs[gi];if(!confirmRow('删除「'+dg.n+'」档案'))return;
  HT.drugs.splice(gi,1); renderHealth(); toast('已删除档案 · 历史打卡保留在流水')}
function tgMedAll(el){el.classList.toggle('on');const on=el.classList.contains('on');
  HT.drugs.forEach(d=>d.rem=on); renderHealth(); toast(on?'全部药品提醒已排程':'全部用药提醒已关闭')}
/* ================= 健康趋势 ================= */
const HT_METRICS={
  all:{n:'综合达标',col:'bg-mint',u:'%'}, water:{n:'喝水',col:'bg-sky-400',u:'杯'},
  sleep:{n:'睡眠',col:'bg-indigo-400',u:'h'}, ex:{n:'运动',col:'bg-amber-400',u:'分钟'},
  body:{n:'体重',col:'bg-emerald-400',u:'kg'}, drug:{n:'用药',col:'bg-rose-400',u:'%'}};
function htVal(d,k){
  if(k==='all')return htScore(d);
  if(k==='water')return htWater(d);
  if(k==='sleep')return htSleepH(d);
  if(k==='ex')return htExMin(d);
  if(k==='body')return htKg(d);
  if(k==='drug')return htDrugPct(d);
  return 0;
}
function htGoal(k){return {all:80, water:HT.waterGoal, sleep:HT.goalSleep, ex:30, body:HT.goalW, drug:100}[k]}
function hTrends(){
  const row=document.getElementById('trMetricRow'); if(!row)return;
  const M=HT_METRICS[HT.trMetric], year=HT.trRange===12;
  hSyncSeg('p-trends', HT.trRange);
  row.innerHTML=Object.keys(HT_METRICS).map(k=>`<button class="tag-chip shrink-0 ${k===HT.trMetric?'on':''}" data-k="${k}">${HT_METRICS[k].n}</button>`).join('');
  row.querySelectorAll('button').forEach(b=>b.onclick=()=>{HT.trMetric=b.dataset.k;hTrends()});
  const heat=document.getElementById('trHeat');
  heat.style.gridTemplateColumns=year?'repeat(6,1fr)':'repeat(7,1fr)';
  const cells=year?Array.from({length:12},(_,i)=>({lab:(i+1)+'月',v:hMonthAvg(i+1,HT.trMetric)}))
    :Array.from({length:HT.trRange},(_,i)=>{const k=HT.trRange-1-i,d=htDay(k);return {lab:d.slice(3),d:d,v:htVal(d,HT.trMetric)}});
  const mx=Math.max(...cells.map(c=>c.v),htGoal(HT.trMetric),1), mn=Math.min(...cells.map(c=>c.v),0);
  heat.innerHTML=cells.map((c,i)=>{const r=(c.v-mn)/Math.max(.0001,mx-mn), lv=r>=.72?3:r>=.45?2:r>=.18?1:0;
    const bg=lv===0?'bg-slate-100 dark:bg-slate-800':M.col+(lv===1?'/25':lv===2?'/60':'');
    return `<div class="h-8 rounded-lg ${bg} flex items-center justify-center text-[9px] font-bold ${lv>=2?'text-white':'text-slate-400'}" data-i="${i}" onclick="hTrendDay(this,${i})">${c.lab}</div>`}).join('');
  hPut('trLegend',(year?'按月 · ':'')+'色阶 '+mn.toFixed(0)+' ~ '+mx.toFixed(1)+M.u);
  hPut('trHeatTx','达标热力 · '+M.n+' · '+(year?'近 12 个月':'近 '+HT.trRange+' 天'));
  const dd=document.getElementById('trDayDetail'); if(dd){delete dd.dataset.filled;dd.innerHTML='未选日期'}
  const vs=cells.map(c=>c.v), avg=vs.reduce((a,b)=>a+b,0)/vs.length;
  const goal=htGoal(HT.trMetric);
  const put=(id,v)=>{const e=document.getElementById(id);if(e)e.textContent=v};
  if(HT.trMetric==='body'){
    put('tv1',vs[vs.length-1].toFixed(1));put('tl1','期末 kg');put('tv2',avg.toFixed(1));put('tl2','区间均值');
    put('tv3',(vs[vs.length-1]-vs[0]).toFixed(1));put('tl3','区间变化');put('tv4',(vs[vs.length-1]-HT.goalW).toFixed(1));put('tl4','距目标');
  }else if(HT.trMetric==='all'||HT.trMetric==='drug'){
    put('tv1',Math.round(avg)+'%');put('tl1','平均达标');put('tv2',vs.filter(v=>v>=goal).length);put('tl2','达标天');
    put('tv3',Math.round(Math.max(...vs))+'%');put('tl3','峰值');put('tv4',vs.filter(v=>v<40).length);put('tl4','待改善天');
  }else{
    put('tv1',vs.reduce((a,b)=>a+b,0).toFixed(0));put('tl1','合计'+M.u);put('tv2',avg.toFixed(1));put('tl2','日均'+M.u);
    put('tv3',vs.filter(v=>v>=goal).length);put('tl3','达标天');put('tv4',Math.max(...vs).toFixed(1));put('tl4','单日峰值');
  }
  const box=hChartBox('trSvg',300,90);
  const pad=(mx-mn)*0.28||1, lo=Math.max(0,mn-pad), hi=mx+pad;
  const W=box.W, H=box.H;
  const X=i=>8+i*((W-16)/Math.max(1,vs.length-1)), Y=v=>(H-12)-((v-lo)/Math.max(.0001,hi-lo))*(H-28);
  box.s.innerHTML=`<line x1="4" y1="${Y(goal).toFixed(1)}" x2="${W-4}" y2="${Y(goal).toFixed(1)}" stroke="#f43f5e" stroke-width="1" stroke-dasharray="3 3"/>`+
    `<text x="${W-8}" y="${(Y(goal)-4).toFixed(1)}" font-size="7" text-anchor="end" fill="#f43f5e">目标 ${goal}${M.u}</text>`+
    `<polyline points="${vs.map((v,i)=>X(i).toFixed(1)+','+Y(v).toFixed(1)).join(' ')}" fill="none" stroke="var(--accent)" stroke-width="2" stroke-linecap="round"/>`+
    vs.map((v,i)=>`<circle cx="${X(i).toFixed(1)}" cy="${Y(v).toFixed(1)}" r="2" fill="var(--accent)"/>`).join('');
  hPut('trCurTx',M.n+'趋势 · '+(year?'按月':HT.trRange+' 天'));
  const pAvg=HT.trMetric==='body'?(HT.weights[Math.max(0,HT.weights.length-1-HT.trRange*2)]||{kg:avg}).kg:avg*(1-((HT.trRange*3)%7)/100);
  const cmp=(avg-pAvg)/pAvg*100;
  hPut('trCompare','环比上期 '+(cmp>=0?'+':'')+cmp.toFixed(1)+'%'+(year?' · 同比去年同期 '+(cmp*0.6).toFixed(1)+'%':'')+' · 日均 '+avg.toFixed(1)+M.u);
  hReport();
}
function hMonthAvg(m,k){let s=0,last=[31,28,31,30,31,30,31,31,30,31,30,31][m-1];
  for(let j=1;j<=last;j++){const d=('0'+m).slice(-2)+'-'+('0'+j).slice(-2);s+=htVal(d,k)}
  return +(s/last).toFixed(k==='body'?2:1)}
function hTrendDay(el,i){
  const dd=document.getElementById('trDayDetail'); if(!dd)return;
  [...el.parentElement.children].forEach(c=>c.classList.remove('ring-2','ring-brand-500'));
  el.classList.add('ring-2','ring-brand-500');
  if(HT.trRange===12){const m=i+1, M=HT_METRICS[HT.trMetric], v=hMonthAvg(m,HT.trMetric);
    const tail=(M.u==='%')?('约 '+Math.round(v/100*30)+' 天/月达标'):('月合计约 '+(v*30).toFixed(0)+' '+M.u);
    dd.innerHTML=`<b>${m} 月</b> 月均 ${v} ${M.u} · ${tail} · <span class="text-slate-400">年视图按月聚合，日明细请切「月」</span>`;return}
  const d=htDay(HT.trRange-1-i);
  dd.innerHTML=`<b>${d} ${htWd(d)}</b> · 喝水 ${htWater(d)}/${HT.waterGoal} 杯 · 睡眠 ${htSleepH(d).toFixed(1)}h · 运动 ${htExMin(d)} 分钟 · 体重 ${htKg(d).toFixed(1)}kg · 用药 ${htDrugPct(d)}% · 综合 <b style="color:var(--accent)">${htScore(d)}%</b>`;
}
function hReport(){
  const tiles=document.getElementById('hrTiles'); if(!tiles)return;
  const wDays=Array.from({length:7},(_,i)=>htDay(6-i));
  const avg=a=>a.reduce((x,y)=>x+y,0)/a.length;
  const wa=avg(wDays.map(d=>HT.waterByDay[d]||0)), sl=avg(wDays.map(d=>htVal(d,'sleep'))), exn=wDays.filter(d=>htVal(d,'ex')>=10).length;
  const sc7=Math.round(wDays.filter(d=>htScore(d)>=80).length/7*100);
  tiles.innerHTML=[['日均喝水',wa.toFixed(1)+' 杯'],['日均睡眠',sl.toFixed(1)+' h'],['运动次数',exn+' 次'],
    ['全达标天',sc7+'%'],['期末体重',HT.weights[HT.weights.length-1].kg.toFixed(1)+' kg'],['用药依从',hMedRate7()+'%']]
    .map(([n,v])=>`<div class="bg-white/15 rounded-xl py-2"><b class="text-[14px] block">${v}</b><span class="text-[9px] opacity-80">${n}</span></div>`).join('');
  const dif=document.getElementById('hrDiff');
  dif.innerHTML=[['日均睡眠','+0.4 h','好'],['日均喝水','−0.6 杯','注意'],['运动次数','+1 次','好'],['平均配速','−8″ /km','好'],['体重','−0.3 kg','优']]
    .map(([n,v,k])=>`<div class="flex items-center gap-2 text-[11px]"><span class="flex-1 text-slate-500 dark:text-slate-400">${n}</span><b>${v}</b><span class="text-[9px] px-1.5 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800 ${k==='注意'?'text-amber-500':'text-emerald-500'}">${k}</span></div>`).join('');
  const bars=document.getElementById('hrBars');
  bars.innerHTML=wDays.map(d=>{const sc=htScore(d);
    return `<div class="flex items-center gap-2 text-[10px]"><span class="w-12 text-slate-400 font-mono">${d.slice(3)} ${htWd(d).slice(1)}</span><div class="flex-1 h-2 rounded-full bg-slate-100 dark:bg-slate-800 overflow-hidden"><span class="block h-full ${sc>=80?'bg-mint':sc>=55?'bg-mint/60':'bg-amber-300'}" style="width:${sc}%"></span></div><b class="w-9 text-right">${sc}%</b></div>`}).join('');
  hPut('hrVerdict','本周 '+sc7+'% 的天数完成全部目标 · 睡眠比上周改善 · 喝水有 '+wDays.filter(d=>(HT.waterByDay[d]||0)<6).length+' 天不足 6 杯');
  hPut('hrRange',wDays[0]+' ~ '+wDays[6]);
}
/* ================= 健康目标 ================= */
function hRenderGoals(){
  const today=htDay(0);
  const conds=[HT.waterN>=HT.waterGoal, htVal(today,'sleep')>=HT.goalSleep, HT.exs.some(x=>x.d===today&&x.min>=10), hMedPlan(today).t>0&&hMedPlan(today).o>=hMedPlan(today).t];
  const doneN=conds.filter(Boolean).length;
  hPut('goalRingTx',doneN+'/4');
  const ring=document.getElementById('goalRing'); if(ring)ring.setAttribute('stroke-dasharray',(107*doneN/4).toFixed(1)+' 107');
  hPut('goalSum','喝水 '+HT.waterN+'/'+HT.waterGoal+' · 睡眠 '+htVal(today,'sleep').toFixed(1)+'/'+HT.goalSleep+'h · 运动 '+(HT.exs.filter(x=>x.d===today).length)+' 次 · 用药 '+hMedPlan(today).o+'/'+hMedPlan(today).t);
  hPut('gbWater',HT.waterGoal+' 杯'); hPut('gbSleep',HT.goalSleep+' h'); hPut('gbBed',HT.bedLine);
  hPut('gbEx',HT.weekExGoal+' 次/周'); hPut('gbW',HT.goalW+' kg');
  const last=HT.weights[HT.weights.length-1];
  hPut('gWaist',(last.waist||'—')+' / '+(HT.goalWaist||'—')); hPut('gHip',(last.hip||'—')+' / '+(HT.goalHip||'—')); hPut('gNeck',(last.neck||'—')+' / '+(HT.goalNeck||'—'));
}
function hGoalPick(k){
  const map={water:['gbWater','每日喝水目标','water',HT.waterGoal,hNums(4,14,1),'杯'],
    sleep:['gbSleep','睡眠时长目标','goalSleep',HT.goalSleep,hNums(6,10,0.5),'小时'],
    bed:['gbBed','按时入睡线','bedLine',HT.bedLine,hTimes(),''],
    ex:['gbEx','每周运动次数','weekExGoal',HT.weekExGoal,hNums(1,7,1),'次'],
    w:['gbW','目标体重','goalW',HT.goalW,hNums(45,95,0.5),'kg'],
    waist:['gWaist','腰围目标','goalWaist',HT.goalWaist,hNums(55,110,1),'cm'],
    hip:['gHip','臀围目标','goalHip',HT.goalHip,hNums(70,120,1),'cm'],
    neck:['gNeck','颈围目标','goalNeck',HT.goalNeck,hNums(30,45,1),'cm']}[k];
  hInline(document.getElementById(map[0]),map[1]+'（'+map[5]+'）',map[4],map[3],v=>{HT[map[2]]=parseFloat(v)||v;
    if(k==='water')HT.waterN=Math.min(HT.waterN,HT.waterGoal);
    renderHealth(); toast(map[1]+' → '+v+(map[5]?' '+map[5]:'')+' · 历史数据不追改')});
}
function hGoalsReset(){HT.waterGoal=8;HT.goalSleep=8;HT.bedLine='23:30';HT.weekExGoal=3;HT.goalW=65;HT.goalWaist=76;HT.goalHip=93;HT.goalNeck=36;
  renderHealth(); toast('已恢复默认目标 · 喝水 8 杯 / 睡眠 8h / 23:30 前 / 运动 3 次·周 / 体重 65kg')}
/* ================= 健康设置 ================= */
function hRenderSet(){
  hPut('gbCup',HT.cupMl+' ml'); hPut('kgUnitTx',HT.kgUnit); hPut('kmUnitTx',HT.kmUnit);
  const tg=document.getElementById('tgStage'); if(tg)tg.classList.toggle('on',!!HT.stageLog);
  const td=document.getElementById('tgDash'); if(td)td.classList.toggle('on',HT.showDash!==false);
  const tf=document.getElementById('tgFab'); if(tf)tf.classList.toggle('on',HT.fabQuick!==false);
}
function hToggleKg(){HT.kgUnit=HT.kgUnit==='kg'?'斤':'kg';renderHealth();toast('体重单位 → '+HT.kgUnit+' · 1 kg = 2 斤')}
function hToggleKm(){HT.kmUnit=HT.kmUnit==='km'?'mile':'km';renderHealth();toast('距离单位 → '+HT.kmUnit)}
function hExport(anchor){hInline(anchor||document.querySelector('#p-hSet .mini-btn'),'导出健康流水 · 范围',['本机全部','近 30 天','近 90 天','按月份'],
  '本机全部',v=>toast('已生成 health_*.csv（'+v+'）· 落点见「数据与同步」'))}
/* ================= 用药打卡弹层收尾 ================= */
function hDrugLogSave(){const today=htDay(0),p=hMedPlan(today);
  const note=(document.getElementById('hdlNote').value||'').trim();
  hLog({k:'drug',t:'用药打卡 '+p.o+'/'+p.t+' 次'+(note?' · '+note:'')});
  closeSheet('sheetHDrugLog'); renderHealth();
  toast('已记录 · 今日 '+p.o+'/'+p.t+' 次'+(p.o<p.t?' · 剩余 '+(p.t-p.o)+' 次到点仍会提醒':' · 全部完成'));
}
/* ================= 启动接线（FAB 覆盖 + 图标注入 + 设置回显） ================= */
function hBoot(){
  hIconFill(); hEcho('cupMl'); hEcho('dailyTime'); hEcho('remTime'); hEcho('missed');
  FAB_CFG['p-health']={ico:'＋',act:()=>openSheet('sheetHAdd')};
  ['p-body','p-exLog','p-med','p-sleepLog'].forEach(p=>FAB_CFG[p]={ico:'＋',act:()=>openSheet('sheetHAdd')});
}
