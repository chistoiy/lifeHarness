/* ============================================================
   健康管理专版（需求 V1.41 设计稿 · 事实源 prototype/index-health.html）
   覆盖：喝水 / 睡眠 / 运动（三模互算·计时） / 身体数据 / 用药 / 趋势与周报 / 目标 / 设置
   数据为确定性模拟常量（以 2026-09-19 为「今天」），无随机，逐屏走查可复现
   ============================================================ */
const HT = {
  waterN:5, waterGoal:8, cupMl:250, kgUnit:'kg', kmUnit:'km', stageLog:false,
  bodyRange:30, trRange:30, trMetric:'all', exRange:'w', exFilter:'全部',
  height:175, goalSleep:8, goalW:65, goalWaist:76, goalHip:93, goalNeck:36, bedLine:'23:30', weekExGoal:3,
  missed:30, dailyTime:'21:30', remTime:'08:00', showDash:true, fabQuick:true,
  exTypes:['跑步','骑行','游泳','力量','球类','瑜伽','步行','其他'],
  distTypes:['跑步','骑行','游泳','步行'],
  weights:[], sleeps:[], exs:[], drugs:[], logs:[], waterByDay:{}
};
function htDay(off){const b=new Date(2026,8,19);b.setDate(b.getDate()-off);return ('0'+(b.getMonth()+1)).slice(-2)+'-'+('0'+b.getDate()).slice(-2)}
function htWd(ds){return '周'+'日一二三四五六'[new Date(2026,+ds.slice(0,2)-1,+ds.slice(3,5)).getDay()]}
const HT_KCAL={'跑步':10.5,'骑行':7.5,'游泳':9,'力量':5,'球类':7,'瑜伽':3.4,'步行':4.2,'其他':5};
function htKcal(t,min,km){const r=HT_KCAL[t]||5;return Math.round((min||0)*r)}
/* 运动 MET 近似表 · 供种子与表单估算共用 */
(function seedHealth(){
  for(let i=44;i>=0;i--){
    const d=htDay(i), k=44-i;
    HT.weights.push({d:d, kg:+(69.6-0.021*k-((k*37)%9)/60).toFixed(2), f:+(19.4-0.012*k).toFixed(1),
      waist:+(80.5-0.03*k).toFixed(1), hip:+(95.2-0.01*k).toFixed(1), neck:(k%7===0)?+(37.2-0.005*k).toFixed(1):null});
    HT.waterByDay[d]=[6,8,7,5,8,8,4][k%7];
  }
  const qs=['优','良','中','差'];
  for(let i=6;i>=0;i--){
    const bh=[23,23,22,23,0,22,23][i], bm=[12,48,30,5,40,55,20][i], eh=[6,6,7,6,7,6,7][i], em=[24,10,45,30,55,12,40][i];
    let mins=(eh*60+em)-(bh*60+bm); if(mins<=0)mins+=1440;
    HT.sleeps.push({d:htDay(i), b:('0'+bh).slice(-2)+':'+('0'+bm).slice(-2), e:('0'+eh).slice(-2)+':'+('0'+em).slice(-2),
      h:+(mins/60).toFixed(1), q:qs[i%4], st:{deep:Math.round(mins*0.17), light:Math.round(mins*0.47), rem:Math.round(mins*0.2), awake:Math.round(mins*0.16)}});
  }
  HT.sleeps.sort((a,b)=>a.d.localeCompare(b.d));
  const ex=[{i:0,t:'跑步',km:5.1,min:33,note:'晨跑 · 江边',src:'计时'},{i:1,t:'力量',min:42,note:'腿日',src:'手动'},
    {i:2,t:'骑行',km:18.4,min:52,note:'通勤绕行',src:'手动'},{i:4,t:'跑步',km:6.2,min:41,note:'间歇 6 组',src:'计时'},
    {i:5,t:'瑜伽',min:25,note:'拉伸',src:'手动'},{i:7,t:'跑步',km:8.0,min:52,note:'长距离',src:'计时'},
    {i:8,t:'游泳',km:1.2,min:36,note:'自由泳 40×',src:'手动'},{i:11,t:'力量',min:48,note:'上肢推',src:'手动'},
    {i:13,t:'跑步',km:5.0,min:34,note:'配速稳',src:'计时'},{i:16,t:'步行',km:6.4,min:64,note:'city walk',src:'手动'},
    {i:19,t:'跑步',km:5.4,min:36,note:'',src:'手动'},{i:23,t:'骑行',km:22.0,min:63,note:'江边往返',src:'计时'}];
  HT.exs=ex.map(e=>{const km=e.km||null, mn=e.min, kcal=htKcal(e.t,mn,km);
    return {d:htDay(e.i), t:e.t, km:km, min:mn, pace:km?fmtPace(mn/km):null, kcal:kcal, note:e.note, src:e.src}});
  HT.drugs=[
    {n:'维生素 D3', spec:'400IU', unit:'片', dose:1, times:['09:15'], rem:true, dot:'amber', end:''},
    {n:'钙片', spec:'600mg', unit:'片', dose:2, times:['09:15','21:00'], rem:true, dot:'sky', end:''},
    {n:'阿托伐他汀', spec:'10mg', unit:'粒', dose:1, times:['08:00','20:00'], rem:true, dot:'rose', end:'2026-10-19'}];
  HT.drugs[0].done={};HT.drugs[1].done={};HT.drugs[2].done={};
  for(let i=0;i<14;i++){const d=htDay(i);
    HT.drugs.forEach(dg=>{const dn=dg.done[d]=[];dg.times.forEach((t,j)=>{if(!(htHash(d+t+j)%10===0&&i>1))dn.push(t)})});}
  HT.drugs[2].done['09-19']=['08:00'];
  HT.logs=[
    {k:'ex',t:'跑步 5.1 km · 33min',at:'07:12',d:'09-19'},
    {k:'drug',t:'钙片 · 09:15 已服用',at:'09:15',d:'09-19'},
    {k:'body',t:'体重 68.62 kg · BMI 22.4',at:'07:05',d:'09-19'},
    {k:'sleep',t:'睡眠 7.1h · 23:05 – 06:40',at:'06:45',d:'09-19'}];
})();
/* —— 线性图标 · 禁 emoji —— */
const HT_ICO={
  water:'<path d="M12 3.4c3.2 3.6 5.6 6.4 5.6 9.2a5.6 5.6 0 0 1-11.2 0c0-2.8 2.4-5.6 5.6-9.2z"/>',
  sleep:'<path d="M20 13.4A8.4 8.4 0 1 1 10.6 4a6.8 6.8 0 0 0 9.4 9.4z"/>',
  ex:'<circle cx="14.5" cy="4.6" r="1.8"/><path d="M13 8.4 9.6 10.2l1.6 3.4-1.4 5.6M13 8.4l3.4 1.4 1.2 3.2 3 .6M11.2 13.6 8 15.4l-1.4 4.8"/>',
  body:'<path d="M12 4.2c2.4 0 4.2 1.3 4.2 3.1S14.4 10.4 12 10.4 7.8 9.1 7.8 7.3 9.6 4.2 12 4.2z"/><path d="M6.6 20.2c0-4.2 2.4-6.8 5.4-6.8s5.4 2.6 5.4 6.8"/>',
  drug:'<rect x="3.2" y="8.6" width="17.6" height="6.8" rx="3.4"/><path d="M12 8.6v6.8"/>',
  trend:'<path d="M3.5 16.5 9 10.8l3.6 3.4L20.5 7"/><path d="M16.4 6.6h4.2v4.2"/>',
  goal:'<circle cx="12" cy="12" r="7.6"/><circle cx="12" cy="12" r="3"/><path d="M12 2.2v2.8M12 19v2.8M2.2 12H5M19 12h2.8"/>',
  set:'<circle cx="12" cy="12" r="2.8"/><path d="M12 3.2v2.2M12 18.6v2.2M4.8 7.6l1.9 1.1M17.3 15.3l1.9 1.1M4.8 16.4l1.9-1.1M17.3 8.7l1.9-1.1"/>',
  care:'<path d="M12 20.4S4.2 15.6 3 10C2.2 6.3 5.1 3.9 8 4.8c1.6.5 2.9 1.8 4 3.2 1.1-1.4 2.4-2.7 4-3.2 2.9-.9 5.8 1.5 5 5.2-1.2 5.6-9 10.4-9 10.4z"/>',
  report:'<rect x="4.5" y="3.5" width="15" height="17" rx="2.5"/><path d="M8 8.5h8M8 12h8M8 15.5h5"/>',
  bike:'<circle cx="6" cy="17" r="3.4"/><circle cx="18" cy="17" r="3.4"/><path d="M6 17l4.2-7h4L18 17M9.2 10h4.6M13.8 10l1.4-3.4h2.4"/>',
  dumbbell:'<path d="M4 9v6M7 7.5v9M17 7.5v9M20 9v6M7 12h10"/>',
  wave:'<path d="M3 9c2.4-2.4 4.2-2.4 6.6 0s4.2 2.4 6.6 0 2.6-1.6 4.2-1.2M3 15c2.4-2.4 4.2-2.4 6.6 0s4.2 2.4 6.6 0 2.6-1.6 4.2-1.2"/>',
  yoga:'<circle cx="12" cy="5" r="1.9"/><path d="M12 8v5M12 13l-4 3.6M12 13l4 3.6M6.6 10.4 12 13l5.4-2.6"/>'};
const HT_EX_ICO={跑步:'ex',步行:'ex',骑行:'bike',游泳:'wave',力量:'dumbbell',瑜伽:'yoga',球类:'ex',其他:'ex'};
function hExIco(t){return hSvg(HT_EX_ICO[t]||'ex','w-4 h-4')}
function hSvg(k,cls){return `<svg class="${cls||'w-[17px] h-[17px]'}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" viewBox="0 0 24 24">${HT_ICO[k]}</svg>`}
/* 曲线图：把 viewBox 对齐到实际像素盒，避免默认 meet 缩放把图挤成中间一小块 */
function hChartBox(id,dW,dH){const s=document.getElementById(id);if(!s)return{W:dW,H:dH};
  const W=Math.max(200,s.clientWidth||dW), H=Math.max(48,s.clientHeight||dH);
  s.setAttribute('viewBox','0 0 '+W+' '+H); return {W:W,H:H,s:s}}
const HT_DOT={amber:'bg-amber-500/10 text-amber-500', sky:'bg-sky-500/10 text-sky-500', rose:'bg-rose-500/10 text-rose-500', mint:'bg-mint/15 text-emerald-600'};
function hIconFill(){
  const map={'hl-water':'water','hl-sleep':'sleep','hl-ex':'ex','hl-drug':'drug','hl-care':'care','hl-report':'report',
    'ha-water':'water','ha-sleep':'sleep','ha-ex':'ex','ha-body':'body','ha-drug':'drug'};
  for(const id in map){const el=document.getElementById(id);if(el)el.innerHTML=hSvg(map[id],'w-5 h-5')}
}
/* —— 通用交互助手 —— */
function hseg(el){const p=el.parentElement;if(!p)return;
  [...p.children].forEach(b=>{if(b.tagName==='BUTTON'){b.classList.remove('seg-on');b.classList.add('text-slate-500')}});
  el.classList.add('seg-on');el.classList.remove('text-slate-500')}
function hTg(el,msg){el.classList.toggle('on');toast(msg||'已切换（模拟持久化）')}
function hTgStage(el){el.classList.toggle('on');HT.stageLog=el.classList.contains('on');hRenderSleep();toast(HT.stageLog?'开启后记睡眠可逐段补录分期':'睡眠只记起止与质量')}
function hDateRow(id,cur){const el=document.getElementById(id);if(!el)return;
  el.dataset.v=cur;
  el.innerHTML=Array.from({length:8},(_,i)=>{const d=htDay(i);
    return `<button class="tag-chip shrink-0 ${d===cur?'on':''}" data-d="${d}" onclick="hDatePick('${id}','${d}')">${i===0?'今天':d}<span class="opacity-60 ml-0.5">${htWd(d).slice(1)}</span></button>`}).join('')}
function hDatePick(id,d){const el=document.getElementById(id);if(!el)return;el.dataset.v=d;
  [...el.children].forEach(b=>b.classList.toggle('on',b.dataset.d===d))}
function hNums(a,b,s){const r=[];for(let v=a;v<=b+1e-9;v+=s)r.push(+v.toFixed(2));return r}
function hHours(){return Array.from({length:24},(_,i)=>('0'+i).slice(-2))}
function hMins(){return Array.from({length:12},(_,i)=>('0'+(i*5)).slice(-2))}
function hTimes(){return hHours().flatMap(h=>[':00',':15',':30',':45'].map(m=>h+m))}
function fmtPace(mpk){if(!isFinite(mpk)||mpk<=0)return '—';const m=Math.floor(mpk),s=Math.round((mpk-m)*60);return m+'′'+('0'+s).slice(-2)+'″'}
function parsePace(tx){const m=String(tx||'').match(/(\d+)[^0-9]+(\d+)/);return m?(+m[1]+ +m[2]/60):null}
let _cfm=null;
function confirmRow(msg){if(_cfm===msg){_cfm=null;return true}_cfm=msg;toast('再点一次确认：'+msg);return false}
/* 就地内嵌滚轮（scroll-snap 真滑动） */
function hWheel(id,vals,idx){const el=typeof id==='string'?document.getElementById(id):id;if(!el||!vals)return;
  const rowH=28,sp=rowH*2; /* 首尾各留 2 格空隙，保证任意项都能滑到容器中心 */
  const H=el.clientHeight||Math.max(rowH,(parseFloat(getComputedStyle(el).height)||84)-2);
  const k=sp-(H-rowH)/2;   /* 选中第 i 项时 scrollTop = i*rowH + k */
  el.innerHTML=`<div style="height:${sp}px"></div>`+vals.map((v,i)=>`<div class="hw-i" data-i="${i}">${v}</div>`).join('')+`<div style="height:${sp}px"></div>`;
  el._vals=vals; el._i=Math.max(0,Math.min(vals.length-1,idx||0)); el._v=vals[el._i];
  el.onscroll=()=>{const i=Math.max(0,Math.min(vals.length-1,Math.round((el.scrollTop-k)/rowH)));
    if(el._i===i)return; el._i=i; el._v=vals[i];
    [...el.children].forEach(c=>{if(c.dataset.i!==undefined)c.classList.toggle('on',+c.dataset.i===i)});
    (HT._wb||function(){})();};
  el.scrollTop=el._i*rowH+k;
  const c=el.querySelector('[data-i="'+el._i+'"]'); if(c)c.classList.add('on')}
function hWv(id){const el=typeof id==='string'?document.getElementById(id):id;return el?el._v:undefined}
function hNw(id){const el=typeof id==='string'?document.getElementById(id):id;return el?parseFloat(el._v):null}
function hOpt(id){const v=hWv(id);return (v==null||v==='—'||!isFinite(parseFloat(v)))?null:parseFloat(v)}
/* 滚轮面板：内联在当页底部 · 每次新建不共用 id（避免多面板互相抢引用） */
function hInline(anchor,title,vals,cur,onOk){
  const sec=(anchor&&anchor.closest('.page'))||document.querySelector('.page.active'); if(!sec)return;
  sec.querySelectorAll('.h-inline').forEach(x=>x.remove());
  const p=document.createElement('div'); p.className='h-inline card mt-3'; sec.appendChild(p);
  const ci=Math.max(0,vals.map(String).indexOf(String(cur)));
  p.innerHTML=`<div class="flex items-center justify-between"><span class="text-[11px] font-bold">${title}</span><button class="text-[11px] text-slate-400 font-bold" data-act="close">✕ 收起</button></div><div class="hw mt-2"></div>
    <div class="flex gap-2 mt-2"><button class="flex-1 mini-btn" data-act="no">取消</button><button class="flex-1 py-2 rounded-xl grad text-white text-xs font-bold" data-act="yes">确定</button></div>`;
  const wheel=p.querySelector('.hw');
  hWheel(wheel,vals,ci);
  p.scrollIntoView({behavior:'smooth',block:'center'});
  const hide=()=>p.remove();
  p.querySelector('[data-act=close]').onclick=hide;
  p.querySelector('[data-act=no]').onclick=hide;
  p.querySelector('[data-act=yes]').onclick=()=>{const v=hWv(wheel);hide();onOk(v)};
}
function hWheelPick(anchor,key,title,unit,vals){
  hInline(anchor,title,vals,HT[key],v=>{
    HT[key]=/^-?\d+(\.\d+)?$/.test(String(v))?parseFloat(v):v;
    renderHealth(); hEcho(key);
    toast(title+' → '+v+(unit?' '+unit:'')+' · 仅本机生效（模拟持久化）');
  });
}
/* 设置项行内回显（改完立刻在按钮上可见） */
function hEcho(key){
  const set=(id,v)=>{const e=document.getElementById(id);if(e)e.textContent=v};
  if(key==='cupMl')set('gbCup',HT.cupMl+' ml');
  if(key==='dailyTime')set('gbDaily',HT.dailyTime);
  if(key==='remTime')set('gbRem',HT.remTime);
  if(key==='missed')set('gbMissedTx','超 '+HT.missed+' 分钟');
}
/* —— 达标度口径：综合 = 喝水 40% + 睡眠 35% + 运动 25%（分母为当日目标） —— */
function htScore(d){
  const a=Math.min(1,(htWater(d)||0)/HT.waterGoal);
  const b=Math.min(1,htSleepH(d)/8);
  const c=htExMin(d)>=10?1:0;
  return Math.round(a*40+b*35+c*25);
}
function bmiOf(w){return w/Math.pow(HT.height/100,2)}
/* —— 超出 45 天窗口时给确定性兜底值（年视图/月聚合需要，不引随机以保证走查可复现） —— */
function htHash(s){let h=2166136261;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)}return (h>>>0)%1000}
function htWater(d){return HT.waterByDay[d]!=null?HT.waterByDay[d]:(HT.goalSleep-4+htHash(d+'w')%5)}
function htSleepH(d){const s=HT.sleeps.find(x=>x.d===d);return s?s.h:+(6.2+(htHash(d+'s')%25)/10).toFixed(1)}
function htExMin(d){const e=HT.exs.filter(x=>x.d===d);if(e.length)return e.reduce((a,b)=>a+b.min,0);
  return htHash(d+'e')<420?0:18+htHash(d+'e')%32}
function htKg(d){const w=HT.weights.find(x=>x.d===d);if(w)return w.kg;
  return +(70.6-(+d.slice(0,2))*0.30-(+d.slice(3,5))*0.006).toFixed(1)}
function htDrugPct(d){const p=hMedPlan(d);if(p.t)return Math.round(p.o/p.t*100);
  return htHash(d+'d')<780?100:htHash(d+'d')%70}
function bmiTag(b){return b<18.5?['偏瘦','text-sky-500']:b<24?['正常','text-emerald-500']:b<28?['超重','text-amber-500']:['肥胖','text-rose-500']}
function hKgShow(kg){return HT.kgUnit==='斤'?(kg*2).toFixed(1):kg.toFixed(1)}
function hPut(id,v){const e=document.getElementById(id);if(e)e.textContent=v}
/* 分段控件与状态回写同步（防止高亮与实际区间不一致） */
function hSyncSeg(pageId, val){const box=document.querySelector(`#${pageId} button[data-v]`);
  if(!box)return;[...box.parentElement.children].forEach(b=>{const on=String(b.dataset.v)===String(val);
    b.classList.toggle('seg-on',on);b.classList.toggle('text-slate-500',!on)})}

/* 消耗估算：按类型的每分钟 kcal（距离类不再一律按 62/km 估） */
/* ================= 健康主页（工作台） ================= */
function htNav(p){navTo(p);({ 'p-body':hBodyChart,'p-exLog':hRenderExLog,'p-med':hRenderMeds,'p-sleepLog':hRenderSleep,'p-trends':hTrends,'p-goalsH':hRenderGoals,'p-hSet':hRenderSet }[p]||function(){})()}
function renderHealth(){
  const today=htDay(0);
  HT.waterByDay[today]=HT.waterN;
  hPut('htTodayTx',today+' '+htWd(today));
  const pct=Math.min(100,Math.round(HT.waterN/HT.waterGoal*100));
  const ring=document.getElementById('heroRing'); if(ring)ring.setAttribute('stroke-dasharray',(107*pct/100).toFixed(1)+' 107');
  hPut('heroRingN',HT.waterN); hPut('waterN',HT.waterN); hPut('wTargetTx','/'+HT.waterGoal+' 杯 · '+pct+'%');
  const an=document.getElementById('haWaterN'); if(an)an.textContent=HT.waterN+' / '+HT.waterGoal;
  const last=HT.sleeps[HT.sleeps.length-1];
  hPut('heroSleep',last?last.h.toFixed(1):'—');
  const exToday=HT.exs.filter(x=>x.d===today).reduce((a,b)=>a+b.min,0);
  hPut('heroEx',exToday);
  const cur=HT.weights[HT.weights.length-1].kg, prev=HT.weights[HT.weights.length-8].kg;
  hPut('heroW',hKgShow(cur));
  const dw=cur-prev, dws=(HT.kgUnit==='斤'?(dw*2).toFixed(1):dw.toFixed(1));
  hPut('heroTip','体重周变化 '+(dw>=0?'+':'')+dws+' '+HT.kgUnit+' · 距目标 '+(cur-HT.goalW).toFixed(1)+' kg · 详见身体数据');
  const row=document.getElementById('hEntryRow');
  if(row)row.innerHTML=[['p-body','body','身体数据'],['p-sleepLog','sleep','睡眠'],['p-exLog','ex','运动'],['p-med','drug','用药'],['p-trends','trend','趋势'],['p-goalsH','goal','目标'],['p-hSet','set','设置']]
    .map(([p,k,n])=>`<button class="flex flex-col items-center gap-1 active:scale-95 transition py-1" onclick="htNav('${p}')"><span class="w-9 h-9 rounded-2xl bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 flex items-center justify-center">${hSvg(k,'w-[18px] h-[18px]')}</span><span>${n}</span></button>`).join('');
  const wr=document.getElementById('waterRow');
  if(wr)wr.innerHTML=Array.from({length:HT.waterGoal},(_,i)=>`<button onclick="setWater(${i+1})" class="h-7 rounded-lg text-[10px] font-bold ${i<HT.waterN?'bg-sky-400 text-white':'bg-slate-200 dark:bg-slate-800 text-slate-400'}">${i<HT.waterN?(i+1):''}</button>`).join('');
  const bars=document.getElementById('slBars');
  if(bars)bars.innerHTML=HT.sleeps.map((s,i)=>`<div class="flex-1 h-full flex flex-col justify-end" title="${s.d} ${s.h}h"><span style="height:${Math.max(14,Math.min(100,s.h/10*100))}%" class="w-full rounded-t ${i===6?'bg-indigo-500':'bg-indigo-400/50'}"></span></div>`).join('');
  hPut('slN',last?last.h.toFixed(1):'—'); hPut('slT',HT.goalSleep+'h · '+HT.bedLine+' 前');
  const wr2=document.getElementById('exWeekTx');
  if(wr2){const wk=HT.exs.filter(x=>x.d>=htDay(6));
    wr2.textContent='本周 '+wk.length+' 次 / 目标 '+HT.weekExGoal+' 次 · '+wk.reduce((a,b)=>a+b.min,0)+' 分钟 · '+wk.reduce((a,b)=>a+(b.km||0),0).toFixed(1)+' km'}
  hPut('exToday',exToday?('今日已运动 '+exToday+' 分钟'):'今日未记录');
  const hh=document.getElementById('hHubHeat');
  if(hh)hh.innerHTML=Array.from({length:14},(_,i)=>{const d=htDay(13-i),sc=htScore(d);
    const bg=sc>=80?'bg-mint':sc>=55?'bg-mint/60':sc>=30?'bg-mint/25':'bg-slate-100 dark:bg-slate-800';
    return `<div class="h-7 rounded-lg ${bg} flex items-center justify-center text-[9px] font-bold ${sc>=55?'text-white':'text-slate-400'}" title="${d} · 达标 ${sc}%" onclick="HT.trRange=30;htNav('p-trends')">${sc}</div>`}).join('');
  const st=document.getElementById('hStream');
  if(st)st.innerHTML=HT.logs.map((r,i)=>`<div class="card flex items-center gap-3 !py-2.5 active:scale-[.99]" onclick="hLogEdit(${i})">
      <span class="w-8 h-8 rounded-xl bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-300 flex items-center justify-center shrink-0">${hSvg(r.k==='body'?'body':r.k==='ex'?'ex':r.k==='drug'?'drug':r.k==='sleep'?'sleep':'water','w-4 h-4')}</span>
      <div class="flex-1 min-w-0"><b class="text-[12.5px] block truncate">${r.t}</b><span class="text-[9px] text-slate-400">${r.d} ${r.at} · 本机记录 · 点条目可修改</span></div>
      <span class="text-slate-300">›</span></div>`).join('')||'<div class="card text-[11px] text-slate-400 text-center py-5">今天还没有记录 · 右下 ＋ 开始</div>';
  hBodyChart(); hRenderExLog(); hRenderMeds(); hRenderSleep(); hTrends(); hRenderGoals(); hRenderSet();
}
function hLog(r){const t=new Date();r.d=htDay(0);r.at=('0'+t.getHours()).slice(-2)+':'+('0'+t.getMinutes()).slice(-2);
  HT.logs.unshift(r); HT.logs=HT.logs.slice(0,8)}
function hLogEdit(i){const r=HT.logs[i];if(!r)return;
  ({body:()=>hRecOpen(), sleep:()=>hSleepOpen(), ex:()=>htExOpen(), drug:()=>hMedOpenSheet(),
    water:()=>toast('喝水按杯计数 · 用主页杯格或 ＋1 杯调整')})[r.k]&&({body:hRecOpen,sleep:hSleepOpen,ex:htExOpen,drug:hMedOpenSheet})[r.k]()}
function water(n){HT.waterN=Math.max(0,Math.min(HT.waterGoal,HT.waterN+n));
  HT.waterByDay[htDay(0)]=HT.waterN;
  if(n>0)hLog({k:'water',t:'喝水 +1 杯（累计 '+HT.waterN+' 杯）'});
  renderHealth(); if(HT.waterN===HT.waterGoal)toast('今日 '+HT.waterGoal+' 杯达成 · 将写入日记与周报')}
function setWater(n){HT.waterN=n;HT.waterByDay[htDay(0)]=n;hLog({k:'water',t:'喝水调整为 '+n+' 杯'});renderHealth()}
/* ================= 身体数据 ================= */
/* 区间序列：实测记录优先，超出实测范围按 htKg 趋势补全（原型演示用，界面上有注记） */
function htSeries(n){const out=[];
  for(let i=n-1;i>=0;i--){const d=htDay(i), w=HT.weights.find(x=>x.d===d);
    out.push(w||{d:d, kg:htKg(d), f:null, waist:null, hip:null, neck:null, synth:true})}
  return out}
function hBodyChart(){
  const box=hChartBox('bdSvg',300,120); const svg=box.s; if(!svg)return;
  hSyncSeg('p-body', HT.bodyRange);
  const all=HT.weights, w=htSeries(HT.bodyRange);
  const kgv=w.map(x=>x.kg);
  const mn=Math.min(...kgv, HT.goalW)-.4, mx=Math.max(...kgv, HT.goalW)+.4, W=box.W, H=box.H;
  const X=i=>8+i*((W-16)/Math.max(1,w.length-1)), Y=v=>H-18-(v-mn)/(mx-mn)*(H-34);
  const gy=Y(HT.goalW);
  svg.innerHTML=`<line x1="4" y1="${gy.toFixed(1)}" x2="${W-4}" y2="${gy.toFixed(1)}" stroke="#f43f5e" stroke-width="1" stroke-dasharray="3 3" opacity=".8"/>`+
   `<text x="${W-58}" y="${(gy-3).toFixed(1)}" font-size="7" fill="#f43f5e">目标 ${HT.goalW}kg</text>`+
   `<polyline points="${w.map((x,i)=>X(i).toFixed(1)+','+Y(x.kg).toFixed(1)).join(' ')}" fill="none" stroke="var(--accent)" stroke-width="2" stroke-linecap="round"/>`+
   w.map((x,i)=>(i%Math.ceil(w.length/8)===0||i===w.length-1)?`<circle cx="${X(i).toFixed(1)}" cy="${Y(x.kg).toFixed(1)}" r="2.4" fill="var(--accent)" title="${x.d} ${x.kg}kg"/>`:'').join('')+
   `<text x="4" y="10" font-size="8" fill="#94a3b8">${mx.toFixed(1)}</text><text x="4" y="${H-4}" font-size="8" fill="#94a3b8">${mn.toFixed(1)}</text>`+
   `<text x="${(X(w.length-1)-26).toFixed(1)}" y="${(Y(w[w.length-1].kg)-7).toFixed(1)}" font-size="9" font-weight="700" fill="var(--accent)">${w[w.length-1].kg.toFixed(1)}</text>`+
   `<text x="4" y="${H-4}" font-size="7" fill="#94a3b8"> </text>`;
  const cur=all[all.length-1], first=w[0], b=bmiOf(cur.kg), tg=bmiTag(b);
  hPut('bdW',hKgShow(cur.kg)); hPut('bdH',HT.height); hPut('bdB',b.toFixed(1));
  const bm=document.getElementById('bdBm'); if(bm){bm.textContent='BMI '+tg[0]; bm.className='text-[9px] block '+tg[1]}
  hPut('bdF',cur.f!=null?cur.f.toFixed(1):'—');
  const wk=cur.kg-all[all.length-8].kg, dd=cur.kg-first.kg;
  hPut('boWk',(wk>=0?'+':'')+ (HT.kgUnit==='斤'?(wk*2).toFixed(1):wk.toFixed(1))+' '+HT.kgUnit);
  hPut('boRg',(dd>=0?'+':'')+(HT.kgUnit==='斤'?(dd*2).toFixed(1):dd.toFixed(1))+' '+HT.kgUnit);
  hPut('boG',(cur.kg-HT.goalW).toFixed(1)+' kg');
  const list=document.getElementById('bodyList');
  if(list){list.innerHTML=all.slice(-10).reverse().map(r=>{const i=all.indexOf(r), bb=bmiOf(r.kg), t=bmiTag(bb);
      return `<div class="px-4 py-2.5 flex items-center gap-2.5 active:bg-slate-50 dark:active:bg-slate-800/60" onclick="hRecOpen(${i})">
        <span class="w-11 text-[11px] font-mono text-slate-400 shrink-0">${r.d}</span>
        <b class="text-[13px] w-16 shrink-0">${r.kg.toFixed(2)}<span class="text-[9px] text-slate-400">kg</span></b>
        <span class="text-[10px] px-1.5 py-0.5 rounded-md shrink-0 ${t[1]} bg-slate-100 dark:bg-slate-800">BMI ${bb.toFixed(1)}</span>
        <span class="flex-1 text-[10px] text-slate-400 truncate">${[r.f!=null?'体脂'+r.f+'%':null,r.waist?'腰'+r.waist:null,r.hip?'臀'+r.hip:null,r.neck?'颈'+r.neck:null].filter(Boolean).join(' · ')}</span>
        <button class="text-[10px] text-rose-400 font-bold shrink-0" onclick="event.stopPropagation();hBodyDel(${i})">删除</button></div>`}).join('');
    hPut('boCount','共 '+all.length+' 条实测'+(HT.bodyRange>all.length?' · 超出区间按趋势补全':''))}
}
function hBodyDel(i){const r=HT.weights[i];if(!confirmRow('删除 '+r.d+' 的测量记录'))return;
  HT.weights.splice(i,1); hLog({k:'body',t:'删除 '+r.d+' 测量记录'}); renderHealth(); toast('已删除 · 曲线与 BMI 已重算')}
let _hw={};
function hRecOpen(idx){
  const all=HT.weights, r=idx!=null?all[idx]:all[all.length-1];
  _hw={idx:idx};
  openSheet('sheetHWeight');
  hPut('hwTitle',idx!=null?('修改 '+r.d+' 的记录'):'记录身体数据');
  hDateRow('hwDateRow',r.d);
  const kgI=Math.floor(r.kg), kgD=Math.round((r.kg-kgI)*10);
  hWheel('hwKgI',hNums(35,120,1),kgI-35);
  hWheel('hwKgD',hNums(0,9,1),kgD);
  hWheel('hwH',hNums(140,200,1),HT.height-140);
  /* 选填项：滚轮首位「—」= 不写入，新建记录默认停在「—」 */
  const opt=(id,vals,v)=>{let i=0;if(v!=null)vals.forEach((x,j)=>{if(Math.abs(x-v)<Math.abs(vals[i]-v))i=j});
    hWheel(id,['—'].concat(vals),v==null?0:i+1)};
  opt('hwF',hNums(8,40,0.5),r.f); opt('hwW',hNums(50,120,0.5),r.waist);
  opt('hwHp',hNums(60,130,0.5),r.hip); opt('hwNk',hNums(28,48,0.5),r.neck);
  hPut('hwKgU',HT.kgUnit);
  HT._wb=hBodyPreview; hBodyPreview();
}
function hBodyPreview(){
  const el=document.getElementById('hwPreview'); if(!el||el.offsetParent===null)return;
  const kg=(hNw('hwKgI')||69)+(hNw('hwKgD')||0)/10, b=bmiOf(kg), t=bmiTag(b), prev=HT.weights[HT.weights.length-8].kg;
  _hw.kg=kg;
  el.innerHTML=`<span class="text-slate-400">预览 </span><b style="color:var(--accent)">${kg.toFixed(1)} ${HT.kgUnit}</b> · BMI <b>${b.toFixed(1)}</b> <b class="${t[1]}">${t[0]}</b> · 距目标 <b>${(kg-HT.goalW).toFixed(1)}</b> kg · 周变化 <b>${(kg-prev>=0?'+':'')+(kg-prev).toFixed(1)}</b> kg`;
}
function hBodySave(){
  const d=(document.getElementById('hwDateRow')||{}).dataset.v||htDay(0), kg=+((hNw('hwKgI')||69)+(hNw('hwKgD')||0)/10).toFixed(2);
  HT.height=hNw('hwH')||HT.height;
  const rec=HT.weights.find(x=>x.d===d)||{d:d};
  rec.kg=kg;
  const f=hOpt('hwF'), w=hOpt('hwW'), hp=hOpt('hwHp'), nk=hOpt('hwNk');
  if(f!=null)rec.f=f; if(w!=null)rec.waist=w; if(hp!=null)rec.hip=hp; if(nk!=null)rec.neck=nk;
  if(!HT.weights.includes(rec)){HT.weights.push(rec);HT.weights.sort((a,b)=>a.d.localeCompare(b.d))}
  const ex=[f!=null?'体脂 '+f+'%':null,w!=null?'腰围 '+w:null,hp!=null?'臀围 '+hp:null,nk!=null?'颈围 '+nk:null].filter(Boolean).join(' · ');
  HT.logs.unshift({k:'body',t:'体重 '+kg.toFixed(2)+' kg · BMI '+bmiOf(kg).toFixed(1)+(ex?' · '+ex:''),d:d,at:'刚刚'});
  closeSheet('sheetHWeight'); renderHealth();
  toast('已记录 '+d+' · '+kg.toFixed(1)+' kg · BMI '+bmiOf(kg).toFixed(1)+'（'+bmiTag(bmiOf(kg))[0]+'）· 联动 L11 健康趋势');
}
