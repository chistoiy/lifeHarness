/* ================= V2 · 档案 / 体征 / 症状 / 报告 / 提醒 / AI 小结 ================= */
const HP={
  list:[
    {id:1,name:'我',rel:'本人',sex:'男',birth:'1992-04-17',h:175,w:69.6,note:'',hist:[],all:[],lmeds:[],bp:[118,72],hr:62},
    {id:2,name:'王秀兰',rel:'妈妈',sex:'女',birth:'1962-08-03',h:158,w:61.2,note:'左耳听力下降 · 交流需提高音量',
      hist:['高血压 · 2019 确诊','骨质疏松 · 2023 体检发现'],all:['青霉素'],lmeds:['缬沙坦 80mg · 每日晨','钙片 · 每日晚'],bp:[138,86],hr:74},
    {id:3,name:'小满',rel:'女儿',sex:'女',birth:'2019-06-11',h:112,w:20.4,note:'',hist:['过敏性鼻炎'],all:['花生'],lmeds:[],bp:[96,62],hr:88}
  ],
  cur:1, vitals:[], syms:[], reports:[], reminds:[],
  vRange:30, vType:'bp', syPart:'全部', rpYear:'全部',
  syNames:['头痛','头晕','关节痛','乏力','失眠','恶心','皮疹','腹痛','胸闷','咳嗽'],
  parts:['头部','胸腹','腰背','四肢','关节','皮肤','全身'],
  aiRange:'近 30 天', aiMetrics:['血压','心率','体重','症状','报告'],
  vFilterOpen:null
};
const VT={
  bp:{n:'血压',u:'mmHg',ico:'care',ref:[90,139],slots:['晨起空腹','上午','午后','晚间','睡前','运动后'],
      fields:[['sys','收缩压',70,200,1],['dia','舒张压',40,130,1],['hr','心率',40,160,1]]},
  hr:{n:'心率',u:'次/分',ico:'trend',ref:[55,95],slots:['晨起静息','日间','晚间','运动后'],fields:[['val','静息心率',35,180,1]]},
  spo2:{n:'血氧',u:'%',ico:'wave',ref:[95,100],slots:['晨起','日间','晚间'],fields:[['val','血氧饱和度',80,100,1]]},
  glu:{n:'血糖',u:'mmol/L',ico:'water',ref:[3.9,6.1],slots:['空腹','餐后2h','随机','夜间'],fields:[['val','血糖',2.8,22,0.1]]},
  temp:{n:'体温',u:'℃',ico:'set',ref:[36,37.2],slots:['晨起','日间','晚间','复测'],fields:[['val','体温',35,42,0.1]]}
};
const VT_K=Object.keys(VT);
const HK_LIB=[['血红蛋白','g/L',115,150],['白细胞','×10⁹/L',3.5,9.5],['血小板','×10⁹/L',125,350],
  ['总胆固醇','mmol/L',0,5.2],['低密度脂蛋白','mmol/L',0,3.4],['甘油三酯','mmol/L',0,1.7],
  ['空腹血糖','mmol/L',3.9,6.1],['糖化血红蛋白','%',4,6],['尿酸','μmol/L',155,357],['肌酐','μmol/L',41,81]];
function hpP(){return HP.list.find(x=>x.id===HP.cur)||HP.list[0]}
function hpHash(s){let h=2166136261;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)}return (h>>>0)%10000}
function hpAgeOf(p){const y=+p.birth.slice(0,4),m=+p.birth.slice(5,7),d=+p.birth.slice(8,10);
  let a=2026-y; if(m>9||(m===9&&d>19))a--; return a}
function vtOf(pid,k){return HP.vitals.filter(v=>v.pid===pid&&(!k||v.k===k))}
function syOf(pid){return HP.syms.filter(s=>s.pid===pid)}
function rpOf(pid){return HP.reports.filter(r=>r.pid===pid)}
function vtFlag(k,v){const r=VT[k].ref;return v==null?'ok':(v<r[0]?'lo':(v>r[1]?'hi':'ok'))}
function vtPrimary(v){const f=VT[v.k].fields[0][0];return v[f]}
function hpFmt(v){const f=VT[v.k].fields[0][0];return v.k==='bp'?v.sys+'/'+v.dia:(+v[f]).toFixed(VT[v.k].fields[0][4]===0.1?1:0)}

/* ---------- 种子数据（确定性 · 可复现走查） ---------- */
function hpSeed(){
  HP.list.forEach(p=>{
    const base=p.id===2?1:[1,3].includes(p.id)?0:0;
    for(let i=0;i<HP.vRange+15;i++){
      const d=htDay(i),h=hpHash(p.id+'v'+d);
      if(h%2===0||p.id===2)HP.vitals.push({pid:p.id,k:'bp',d,t:['07:10','07:25','20:40','21:05'][h%4],
        sys:p.bp[0]+(h%9)-4,dia:p.bp[1]+(h%7)-3,hr:p.hr+(h%6)-3,slot:['晨起空腹','晚间'][h%2],note:''});
      if(h%5===0)HP.vitals.push({pid:p.id,k:'hr',d,t:'07:15',val:p.hr+(h%8)-4,slot:'晨起静息',note:''});
      if(h%7===1)HP.vitals.push({pid:p.id,k:'spo2',d,t:'21:10',val:96+(h%4),slot:'晚间',note:''});
      if(p.id===2&&h%3===2)HP.vitals.push({pid:p.id,k:'glu',d,t:['06:50','09:30','20:00'][h%3],val:+(p.bp[0]/24+(h%25)/10).toFixed(1),slot:['空腹','餐后2h','随机'][h%3],note:h%2?'面食偏多':''});
      if(h%11===3)HP.vitals.push({pid:p.id,k:'temp',d,t:'20:30',val:+(36.3+(h%9)/10).toFixed(1),slot:'晚间',note:''});
    }
    HP.vitals=HP.vitals.filter(v=>v.pid!==p.id||true);
  });
  const sy=[{p:2,i:0,n:'头痛',lv:4,part:'头部',min:90,tr:'熬夜后',ea:'休息后好转',desc:'右侧太阳穴跳痛',on:false,dg:false},
    {p:2,i:1,n:'关节痛',lv:6,part:'关节',min:240,tr:'阴天',ea:'热敷',desc:'双膝上下楼酸痛',on:true,dg:false},
    {p:1,i:2,n:'乏力',lv:2,part:'全身',min:180,tr:'睡眠不足',ea:'小睡',desc:'',on:false,dg:false},
    {p:2,i:4,n:'头晕',lv:5,part:'头部',min:15,tr:'起身过快',ea:'坐下休息',desc:'蹲起时眼前发黑',on:false,dg:true},
    {p:3,i:5,n:'皮疹',lv:1,part:'皮肤',min:1440,tr:'接触花生',ea:'涂药',desc:'前臂散在红疹',on:false,dg:true},
    {p:1,i:6,n:'失眠',lv:3,part:'全身',min:300,tr:'睡前用电脑',ea:'热水澡',desc:'',on:false,dg:false},
    {p:2,i:8,n:'胸闷',lv:5,part:'胸腹',min:20,tr:'爬楼后',ea:'静坐 10 分钟',desc:'伴气短 · 已测血氧 94%',on:false,dg:false},
    {p:1,i:10,n:'腹痛',lv:7,part:'胸腹',min:45,tr:'外卖后',ea:'',desc:'脐周绞痛 · 一次稀便',on:false,dg:false},
    {p:2,i:12,n:'咳嗽',lv:2,part:'胸腹',min:4320,tr:'受凉',ea:'糖浆',desc:'干咳无痰',on:true,dg:false},
    {p:3,i:14,n:'恶心',lv:3,part:'胸腹',min:30,tr:'晕车',ea:'开窗',desc:'',on:false,dg:false}];
  sy.forEach(x=>HP.syms.push({pid:x.p,d:htDay(x.i),t:'20:00',name:x.n,lv:x.lv,part:x.part,min:x.min,tr:x.tr,ea:x.ea,
    desc:x.desc,on:x.on,dg:x.dg,pics:x.n==='皮疹'?['IMG']:[]}));
  HP.reports=[
    {pid:2,d:'09-12',name:'血脂四项',hosp:'市一院',doc:'一周后复查血脂 · 控制饮食',fmt:'PDF',pics:[],
      ms:[['总胆固醇',6.4,'mmol/L',0,5.2],['低密度脂蛋白',4.1,'mmol/L',0,3.4],['甘油三酯',1.9,'mmol/L',0,1.7],['高密度脂蛋白',1.3,'mmol/L',1.0,2.0]]},
    {pid:2,d:'07-08',name:'血常规',hosp:'社区医院',doc:'轻度贫血 · 建议查铁蛋白',fmt:'图片 ×2',pics:['IMG','IMG'],
      ms:[['血红蛋白',108,'g/L',115,150],['白细胞',6.2,'×10⁹/L',3.5,9.5],['血小板',240,'×10⁹/L',125,350]]},
    {pid:1,d:'08-20',name:'年度体检 · 生化',hosp:'市二院',doc:'各项正常 · 保持运动',fmt:'图片 ×1',pics:['IMG'],
      ms:[['空腹血糖',5.3,'mmol/L',3.9,6.1],['尿酸',372,'μmol/L',155,357],['肌酐',78,'μmol/L',41,81]]},
    {pid:3,d:'06-15',name:'过敏原检测',hosp:'儿童医院',doc:'花生严格回避 · 春季提前用药',fmt:'图片 ×1',pics:['IMG'],
      ms:[['花生特异性 IgE',3.8,'kU/L',0,0.34],['尘螨 IgE',0.6,'kU/L',0,0.34]]}];
  HP.reminds=[
    {k:'服药',t:'按处方时刻（缬沙坦）',at:'09:15',rep:'每天',on:true},
    {k:'测量',t:'血压 · 晨起',at:'07:30',rep:'每天',on:true},
    {k:'测量',t:'血糖 · 空腹',at:'07:00',rep:'每天',on:false},
    {k:'复诊',t:'市一院 心内科',at:'09:00',rep:'单次',on:true,d:'10-19'}];
}

/* ---------- 档案条（各屏顶部复用） ---------- */
function hpBar(id){const el=document.getElementById(id);if(!el)return;
  el.innerHTML=HP.list.map(p=>`<button class="tag-chip shrink-0 ${p.id===HP.cur?'on':''}" onclick="hpSwitch(${p.id})">${p.name}<span class="opacity-60 ml-0.5">${p.rel}</span></button>`).join('')
    +`<button class="tag-chip shrink-0" onclick="hpMng()">管理 ›</button>`}
function hpSwitch(id){HP.cur=id;hpRenderAll();toast('已切换到「'+hpP().name+'」· 数据按档案隔离')}
function hpRenderAll(){hpRender();vtRender();syRender();rpRender();hpStrip()}

/* ---------- 档案屏 ---------- */
function hpRender(){
  hpBar('hpBar');const p=hpP();if(!p)return;
  hPut('hpName',p.name); hPut('hpMeta',p.rel+' · '+p.sex+' · '+p.birth);
  hPut('hpAge',hpAgeOf(p)); hPut('hpH',p.h); hPut('hpW',hKgShow(p.w)); hPut('hpBmi',bmiOf2(p.w,p.h).toFixed(1));
  const av=document.getElementById('hpAvatar'); if(av)av.innerHTML=hSvg('body','w-6 h-6');
  hPut('hpNote',p.note||'');
  const bs=document.getElementById('hpBaseSrc');
  if(bs)bs.textContent='手动设定 · 各指标页显示「较基线」';
  hPut('hpBp',p.bp[0]+'/'+p.bp[1]); hPut('hpHr',p.hr);
  const chips=(id,arr,empty)=>{const el=document.getElementById(id);if(!el)return;
    el.innerHTML=arr.length?arr.map(x=>`<span class="tag-chip !py-1">${x}</span>`).join(''):`<span class="text-[10px] text-slate-400">${empty}</span>`};
  chips('hpHist',p.hist,'未记录'); chips('hpAll',p.all,'未记录'); chips('hpLmeds',p.lmeds,'未记录');
  const c=document.getElementById('hpCount');
  if(c)c.innerHTML=[['体征',vtOf(p.id).length+' 条'],['症状',syOf(p.id).length+' 条'],['报告',rpOf(p.id).length+' 份'],['用药',HT.drugs.length+' 种']]
    .map(([n,v])=>`<div><b class="text-[13px] block" style="color:var(--accent)">${v}</b><span class="text-[9px] text-slate-400">${n}</span></div>`).join('');
}
function bmiOf2(kg,cm){return kg/Math.pow(cm/100,2)}
let _hp=null;
function hpAdd(){_hp=null;hpOpenSheet('新增档案',null)}
function hpEdit(){_hp=hpP().id;hpOpenSheet('编辑档案 '+hpP().name,hpP())}
function hpOpenSheet(title,p){
  openSheet('sheetHProfile'); hPut('hpfTitle',title);
  hPut('hpfName',p?p.name:''); hPut('hpfRel',p?p.rel:''); hPut('hpfNote',p?p.note:'');
  const sx=document.getElementById('hpfSex');
  if(sx)[...sx.children].forEach(b=>{const on=(p?p.sex:'女')===b.dataset.v;b.classList.toggle('seg-on',on);b.classList.toggle('text-slate-500',!on)});
  hWheel('hpfBY',hNums(1940,2025,1),p?(+p.birth.slice(0,4)-1940):(2025-1990));
  hWheel('hpfBM',hNums(1,12,1),p?(+p.birth.slice(5,7)-1):7);
  hWheel('hpfBD',hNums(1,31,1),p?(+p.birth.slice(8,10)-1):16);
  hWheel('hpfH',hNums(90,200,1),p?(p.h-90):(175-90));
  hWheel('hpfW',hNums(20,150,0.5),p?Math.round((p.w-20)/0.5):Math.round((69.6-20)/0.5));
}
function hpSave(){
  const n=(document.getElementById('hpfName').value||'').trim(); if(!n){toast('请填写姓名');return}
  const sex=(document.querySelector('#hpfSex .seg-on')||{}).dataset.v||'女';
  const birth=hNw('hpfBY')+'-'+('0'+hNw('hpfBM')).slice(-2)+'-'+('0'+hNw('hpfBD')).slice(-2);
  const o={name:n,rel:(document.getElementById('hpfRel').value||'').trim()||'家人',sex:sex,birth:birth,
    h:hNw('hpfH')||170,w:hNw('hpfW')||60,note:(document.getElementById('hpfNote').value||'').trim()};
  if(_hp){const p=HP.list.find(x=>x.id===_hp);Object.assign(p,o);toast('已更新「'+n+'」档案')}
  else{o.id=Math.max(...HP.list.map(x=>x.id))+1;o.hist=[];o.all=[];o.lmeds=[];o.bp=[120,78];o.hr=68;HP.list.push(o);HP.cur=o.id;toast('已新建「'+n+'」· 数据与本档案隔离')}
  closeSheet('sheetHProfile'); hpRenderAll();
}
function hpMng(){
  openSheet('sheetHProfileMng');
  const el=document.getElementById('hpmList');if(!el)return;
  el.innerHTML=HP.list.map(p=>`<div class="card !py-2.5 flex items-center gap-2">
    <div class="flex-1 min-w-0"><b class="text-[12.5px] block">${p.name}</b><span class="text-[9px] text-slate-400">${p.rel} · ${p.sex} · ${p.birth} · 体征 ${vtOf(p.id).length} 条</span></div>
    ${p.id===HP.cur?'<span class="vchip">当前</span>':`<button class="mini-btn !py-1" onclick="hpSwitch(${p.id});closeSheet('sheetHProfileMng')">切换</button>`}
    ${p.rel==='本人'?'':`<button class="text-[10px] text-rose-400 font-bold shrink-0" onclick="hpDel(${p.id})">删除</button>`}</div>`).join('');
}
function hpDel(id){const p=HP.list.find(x=>x.id===id);if(!confirmRow('删除「'+p.name+'」及其全部健康数据'))return;
  HP.list=HP.list.filter(x=>x.id!==id);HP.vitals=HP.vitals.filter(v=>v.pid!==id);
  HP.syms=HP.syms.filter(s=>s.pid!==id);HP.reports=HP.reports.filter(r=>r.pid!==id);
  if(HP.cur===id)HP.cur=HP.list[0].id;
  hpMng();hpRenderAll();toast('已删除档案 · 该档案记录一并移除')}
function hpBaseOpen(){const p=hpP();openSheet('sheetHBaseline');
  hWheel('hbsSys',hNums(80,180,1),p.bp[0]-80);hWheel('hbsDia',hNums(40,120,1),p.bp[1]-40);hWheel('hbsHr',hNums(40,120,1),p.hr-40);
  HP._hb=function(){hPut('hbsTip','当前基线 '+hNw('hbsSys')+'/'+hNw('hbsDia')+' mmHg · 心率 '+hNw('hbsHr')+' · 体征页按此对比')};
  ['hbsSys','hbsDia','hbsHr'].forEach(i=>{const e=document.getElementById(i);if(e)e.addEventListener('scroll',HP._hb)});HP._hb();}
function hbsAuto(){const p=hpP(),bp=vtOf(p.id,'bp'),hr=vtOf(p.id,'hr');
  if(bp.length<3){toast('血压记录不足 3 条 · 无法取中位数');return}
  const med=a=>{const s=a.slice().sort((x,y)=>x-y);return Math.round(s[Math.floor(s.length/2)])};
  hWheel('hbsSys',hNums(80,180,1),med(bp.map(x=>x.sys))-80);hWheel('hbsDia',hNums(40,120,1),med(bp.map(x=>x.dia))-40);
  hWheel('hbsHr',hNums(40,120,1),(hr.length?med(hr.map(x=>x.val)):p.hr)-40);if(HP._hb)HP._hb();
  toast('已按近 30 天中位数填入 · 可再手动调整')}
function hbsSave(){const p=hpP();p.bp=[hNw('hbsSys'),hNw('hbsDia')];p.hr=hNw('hbsHr');
  closeSheet('sheetHBaseline');hpRenderAll();toast('基线已更新 · 体征卡显示「较基线」')}
function hpHistOpen(){const p=hpP();_hh={hist:p.hist.slice(),allergy:p.all.slice(),lmeds:p.lmeds.slice()};
  openSheet('sheetHHistory');hhRender()}
let _hh={hist:[],allergy:[],lmeds:[]};
function hhRender(){const m={hist:'hhHist',allergy:'hhAll',lmeds:'hhLm'};
  Object.keys(m).forEach(k=>{const el=document.getElementById(m[k]);if(!el)return;
    el.innerHTML=_hh[k].length?_hh[k].map((x,i)=>`<button class="tag-chip on !py-1" onclick="_hh.${k}.splice(${i},1);hhRender()">${x} ✕</button>`).join('')
      :'<span class="text-[10px] text-slate-400">尚未填写</span>'})}
function hhAdd(k){const inp={hist:'hhHistIn',allergy:'hhAllIn',lmeds:'hhLmIn'}[k];const el=document.getElementById(inp);
  const v=(el.value||'').trim();if(!v){toast('请先填写内容');return}
  if(_hh[k].includes(v)){toast('该项已存在');return}_hh[k].push(v);el.value='';hhRender()}
function hhSave(){const p=hpP();p.hist=_hh.hist;p.all=_hh.allergy;p.lmeds=_hh.lmeds;
  closeSheet('sheetHHistory');hpRender();toast('已保存 · 随档案与本地备份导出')}

/* ---------- 体征屏 ---------- */
function vtRender(){
  hpBar('vtBar');hSyncSeg('p-vitals',HP.vRange);
  const p=hpP(),days=HP.vRange,all=vtOf(p.id);
  const tiles=VT_K.map(k=>{const vs=all.filter(v=>v.k===k).slice(-8);
    const last=vs[vs.length-1],ab=vs.filter(v=>vtFlag(k,vtPrimary(v))!=='ok').length;
    return `<div class="card !p-3" onclick="vtPick('${k}')">
      <div class="flex items-center justify-between"><span class="text-[10px] text-slate-400">${VT[k].n}</span>${vs.length?(ab?`<span class="mflag hi">${ab} 异常</span>`:'<span class="mflag ok">正常</span>'):'<span class="text-[9px] text-slate-400">未记录</span>'}</div>
      <div class="flex items-end gap-1 mt-1"><b class="text-lg leading-none">${last?hpFmt(last):'—'}</b><span class="text-[9px] text-slate-400 mb-0.5">${VT[k].u}</span></div>
      <div class="text-[9px] text-slate-400 mt-0.5">${last?vtDelta(k,last):'暂无记录'}</div>
      <div class="flex items-end gap-[2px] h-6 mt-1.5">${vs.map(v=>{const f=VT[k].fields[0][4]||1;const h=Math.max(12,Math.min(100,vtPrimary(v)/(VT[k].ref[1]*1.15)*100));
        return `<span class="flex-1 rounded-t ${vtFlag(k,vtPrimary(v))==='ok'?'bg-indigo-400':'bg-rose-400'}" style="height:${h}%"></span>`}).join('')||'<span class="text-[9px] text-slate-300">—</span>'}</div></div>`}).join('');
  const el=document.getElementById('vtTiles');if(el)el.innerHTML=tiles;
  vtCurve();vtAbn();vtList();
}
function vtDelta(k,v){const p=hpP(),prim=vtPrimary(v);
  if(k==='bp')return '较基线 '+(v.sys-p.bp[0]>=0?'+':'')+(v.sys-p.bp[0])+' / '+(v.dia-p.bp[1]>=0?'+':'')+(v.dia-p.bp[1]);
  if(k==='hr')return '较静息 '+(prim-p.hr>=0?'+':'')+(prim-p.hr);
  const r=VT[k].ref;return '参考 '+r[0]+' ~ '+r[1]+' '+VT[k].u}
function vtPick(k){HP.vType=k;vtRender();vtCurve()}
function vtCurve(){
  const k=HP.vType||'bp',box=hChartBox('vtSvg',300,90),p=hpP();
  const vs=vtOf(p.id,k).slice(-HP.vRange);
  if(!box.s)return;
  if(vs.length<2){box.s.innerHTML='<text x="8" y="45" font-size="9" fill="#94a3b8">该指标记录不足 2 条 · 暂无曲线</text>';
    hPut('vtCurTx',VT[k].n+' · 数据不足');hPut('vtStat','');document.getElementById('vtStat').innerHTML='';return}
  const W=box.W,H=box.H,ref=VT[k].ref;
  const vals=vs.map(vtPrimary),mn=Math.min(...vals,ref[0])-1,mx=Math.max(...vals,ref[1])+1;
  const X=i=>8+i*((W-16)/Math.max(1,vs.length-1)),Y=v=>(H-12)-((v-mn)/Math.max(.0001,mx-mn))*(H-28);
  box.s.innerHTML=`<rect x="4" y="${Y(ref[1]).toFixed(1)}" width="${W-8}" height="${Math.max(0,Y(ref[0])-Y(ref[1])).toFixed(1)}" fill="rgba(16,185,129,.10)"/>`+
    `<polyline points="${vals.map((v,i)=>X(i).toFixed(1)+','+Y(v).toFixed(1)).join(' ')}" fill="none" stroke="var(--accent)" stroke-width="2" stroke-linecap="round"/>`+
    vals.map((v,i)=>`<circle cx="${X(i).toFixed(1)}" cy="${Y(v).toFixed(1)}" r="2" fill="${vtFlag(k,v)==='ok'?'var(--accent)':'#f43f5e'}"/>`).join('');
  hPut('vtCurTx',VT[k].n+' · '+VT[k].u+' · 近 '+HP.vRange+' 天');
  hPut('vtAxisLo',mn.toFixed(1));hPut('vtAxisHi',mx.toFixed(1));hPut('vtRangeTx','参考 '+ref[0]+' ~ '+ref[1]+' '+VT[k].u);
  const ab=vals.filter(v=>vtFlag(k,v)!=='ok').length,avg=vals.reduce((a,b)=>a+b,0)/vals.length;
  document.getElementById('vtStat').innerHTML=[['均值',avg.toFixed(1)+VT[k].u],['异常',ab+' 次'],['记录',vs.length+' 条']]
    .map(([n,v])=>`<div class="rounded-xl bg-slate-100 dark:bg-slate-800 py-2"><b class="text-[13px] block">${v}</b><span class="text-[9px] text-slate-400">${n}</span></div>`).join('');
}
function vtRange(n){HP.vRange=n;vtRender()}
function vtAbn(){const p=hpP(),el=document.getElementById('vtAbn');if(!el)return;
  const ab=vtOf(p.id).filter(v=>vtFlag(v.k,vtPrimary(v))!=='ok').slice(0,8);
  hPut('vtAbnN',ab.length?ab.length+' 条待关注':'近 '+HP.vRange+' 天无异常');
  el.innerHTML=ab.length?ab.map(v=>`<div class="flex items-center gap-2">
    <span class="mflag ${vtFlag(v.k,vtPrimary(v))==='lo'?'lo':'hi'}">${vtFlag(v.k,vtPrimary(v))==='lo'?'偏低':'偏高'}</span>
    <span class="text-[11px] flex-1 truncate">${VT[v.k].n} ${hpFmt(v)} ${VT[v.k].u} · ${v.d} ${v.t}</span>
    <button class="text-[10px] font-bold shrink-0" style="color:var(--accent)" onclick="vtOpenTo('${v.k}')">补记录 ›</button></div>`).join('')
    :'<div class="text-[11px] text-slate-400 py-2 text-center">全部落在参考范围内</div>'}
function vtOpenTo(k){HP.vType=k;vtOpen()}
function vtList(){const p=hpP(),el=document.getElementById('vtList');if(!el)return;
  const vs=vtOf(p.id).slice().sort((a,b)=>(a.d+a.t)<(b.d+b.t)?1:-1).slice(0,20);
  el.innerHTML=vs.length?vs.map((v,i)=>{const gi=HP.vitals.indexOf(v),fl=vtFlag(v.k,vtPrimary(v));
    return `<div class="px-4 py-2.5 flex items-center gap-2 active:bg-slate-50 dark:active:bg-slate-800/60" onclick="vtEdit(${gi})">
      <span class="mflag ${fl==='ok'?'ok':(fl==='lo'?'lo':'hi')}">${fl==='ok'?'正常':(fl==='lo'?'低':'高')}</span>
      <div class="flex-1 min-w-0"><b class="text-[12.5px] block truncate">${VT[v.k].n} ${hpFmt(v)} ${VT[v.k].u}</b>
        <span class="text-[9px] text-slate-400">${v.d} ${htWd(v.d)} ${v.t} · ${v.slot||'—'}${v.note?' · '+v.note:''}</span></div>
      <button class="text-[10px] text-rose-400 font-bold shrink-0" onclick="event.stopPropagation();vtDel(${gi})">删除</button></div>`}).join('')
    :'<div class="text-center text-slate-400 text-[11px] py-6">该档案暂无体征记录</div>'}
let _vt=null;
function vtOpen(idx){const p=hpP();_vt=idx!=null?idx:null;
  const v=_vt!=null?HP.vitals[_vt]:null;
  openSheet('sheetHVital');hPut('vtTitle',v?('修改 '+v.d+' 的'+VT[v.k].n):'记录体征');
  hDateRow('vtDateRow',v?v.d:htDay(0));
  HP.vType=v?v.k:(HP.vType||'bp');
  vtTypeRow(v?v.t:'07:30');vtFields(v);vtSlots(v);
}
function vtTypeRow(cur){const el=document.getElementById('vtTypeRow');if(!el)return;
  el.innerHTML=VT_K.map(k=>`<button class="tag-chip shrink-0 ${k===HP.vType?'on':''}" onclick="vtSetType('${k}')">${VT[k].n}</button>`).join('');
  const h=document.getElementById('vtHH'),m=document.getElementById('vtMM');
  const hh=+String(cur).slice(0,2),mm=Math.round(+String(cur).slice(3,5)/5);
  hWheel('vtHH',hHours(),hh);hWheel('vtMM',hMins(),mm);
}
function vtSetType(k){HP.vType=k;vtFields();vtSlots();vtTypeRow(hWv('vtHH')+':'+hWv('vtMM'))}
function vtFields(v){const el=document.getElementById('vtFields');if(!el)return;const K=VT[HP.vType];
  el.style.gridTemplateColumns='repeat('+K.fields.length+',1fr)';
  el.innerHTML=K.fields.map(([f,label,lo,hi,st])=>{const vals=hNums(lo,hi,st||1);
    const cur=v&&v[f]!=null?v[f]:Math.round((lo+hi)/2/(st||1))*(st||1);
    return `<div><div class="hw !h-[68px]" id="vf_${f}"></div><span class="text-slate-400">${label}</span></div>`}).join('');
  K.fields.forEach(([f,label,lo,hi,st])=>{const vals=hNums(lo,hi,st||1);
    const cur=v&&v[f]!=null?v[f]:+(((lo+hi)/2).toFixed(1));
    let i=0;vals.forEach((x,j)=>{if(Math.abs(x-cur)<Math.abs(vals[i]-cur))i=j});
    hWheel('vf_'+f,vals,i)});
  ['vf_'+VT[HP.vType].fields[0][0]].forEach(id=>{const e=document.getElementById(id);if(e)e.addEventListener('scroll',vtPreview)});
  vtPreview();
}
function vtSlots(v){const K=VT[HP.vType];const el=document.getElementById('vtSlotRow');if(!el)return;
  hPut('vtSlotTx',HP.vType==='glu'?'血糖时段 · 饮食情况见备注':'测量时段');
  const cur=v?v.slot:K.slots[0];
  el.innerHTML=K.slots.map(s=>`<button class="tag-chip !py-1 ${s===cur?'on':''}" onclick="vtSlot('${s}',this)">${s}</button>`).join('');
  if(v&&v.note)document.getElementById('vtNote').value=v.note}
function vtSlot(s,el){[...el.parentElement.children].forEach(b=>b.classList.remove('on'));el.classList.add('on')}
function vtPreview(){const el=document.getElementById('vtPreview');if(!el||el.offsetParent===null)return;
  const K=VT[HP.vType],p=hpP(),f=K.fields[0][0],v=hNw('vf_'+f);
  if(v==null){el.textContent='—';return}
  const fl=vtFlag(HP.vType,v),txt=fl==='ok'?'<span class="mflag ok">落在参考范围</span>':(fl==='lo'?'<span class="mflag lo">低于参考值</span>':'<span class="mflag hi">高于参考值</span>');
  el.innerHTML=K.n+' <b>'+ (HP.vType==='bp'?(hNw('vf_sys')+'/'+hNw('vf_dia')):v) + ' '+K.u+'</b> · 参考 '+K.ref[0]+' ~ '+K.ref[1]+' '+txt+
    (HP.vType==='bp'?' · 较基线 '+((hNw('vf_sys')||0)-p.bp[0]>=0?'+':'')+((hNw('vf_sys')||0)-p.bp[0]):'')}
function vtSave(){const d=(document.getElementById('vtDateRow')||{}).dataset.v||htDay(0);
  const t=('0'+(hWv('vtHH')||'07')).slice(-2)+':'+('0'+(hWv('vtMM')||'30')).slice(-2);
  const K=VT[HP.vType],rec={pid:HP.cur,k:HP.vType,d:d,t:t,slot:(document.querySelector('#vtSlotRow .on')||{}).textContent||K.slots[0],
    note:(document.getElementById('vtNote').value||'').trim()};
  K.fields.forEach(([f])=>{rec[f]=hNw('vf_'+f)});
  if(_vt!=null)HP.vitals[_vt]=rec; else HP.vitals.push(rec);
  closeSheet('sheetHVital');hpRenderAll();
  const fl=vtFlag(rec.k,vtPrimary(rec));
  toast('已记录 '+K.n+' '+hpFmt(rec)+' '+K.u+(fl!=='ok'?' · 超出参考范围':''))}
function vtEdit(i){vtOpen(i)}
function vtDel(i){if(!confirmRow('删除该条体征记录'))return;HP.vitals.splice(i,1);hpRenderAll();toast('已删除 · 统计重算')}

/* ---------- 症状屏 ---------- */
function syRender(){hpBar('syBar');const p=hpP();let ss=syOf(p.id);
  const live=ss.filter(s=>s.on);
  hPut('syLiveN',live.length?live.length+' 项':'无');
  const lc=document.getElementById('syLive');
  if(lc)lc.innerHTML=live.length?live.map(s=>`<div class="flex items-center gap-2"><span class="mflag hi">发作中</span>
    <span class="text-[11px] flex-1 truncate">${s.name} · ${s.part} · ${s.lv} 分</span>
    <button class="text-[10px] font-bold shrink-0" style="color:var(--accent)" onclick="syEnd(${HP.syms.indexOf(s)})">标记结束</button></div>`).join('')
    :'<div class="text-[11px] text-slate-400 py-1 text-center">当前无发作中症状</div>';
  const hist=Array(11).fill(0);ss.forEach(s=>hist[Math.max(0,Math.min(10,s.lv))]++);
  const mxh=Math.max(1,...hist);
  const hb=document.getElementById('syHist');if(hb)hb.innerHTML=hist.map((n,i)=>`<span class="flex-1 rounded-t" title="${i} 分 · ${n} 次" style="height:${Math.max(6,n/mxh*100)}%;background:${syColor(i)}"></span>`).join('');
  const ha=document.getElementById('syHistAx');if(ha)ha.innerHTML=hist.map((n,i)=>`<span class="flex-1 text-center">${i}</span>`).join('');
  const pr=document.getElementById('syPartRow');
  if(pr)pr.innerHTML=['全部'].concat(HP.parts).map(x=>`<button class="tag-chip shrink-0 ${x===HP.syPart?'on':''}" onclick="syFilter('${x}')">${x}</button>`).join('');
  if(HP.syPart!=='全部')ss=ss.filter(s=>s.part===HP.syPart);
  syCloud(ss);
  const el=document.getElementById('syList');
  if(el)el.innerHTML=ss.length?ss.slice().sort((a,b)=>a.d<b.d?1:-1).map(s=>{const i=HP.syms.indexOf(s);
    return `<div class="px-4 py-2.5 flex items-center gap-2.5 active:bg-slate-50 dark:active:bg-slate-800/60" onclick="syEdit(${i})">
      <span class="w-8 h-8 rounded-xl flex items-center justify-center shrink-0" style="background:${syColor(s.lv)}22;color:${syColor(s.lv)}"><b class="text-[11px]">${s.lv}</b></span>
      <div class="flex-1 min-w-0"><b class="text-[12.5px] block truncate">${s.name}${s.on?' · 发作中':''}${s.dg?' <span class="vchip">用药相关</span>':''}</b>
        <span class="text-[9px] text-slate-400">${s.d} ${s.t} · ${s.part} · 持续 ${syDur(s.min)}${s.pics&&s.pics.length?' · 照片 '+s.pics.length:''}${s.desc?' · '+s.desc:''}</span></div>
      <button class="text-[10px] text-rose-400 font-bold shrink-0" onclick="event.stopPropagation();syDel(${i})">删除</button></div>`}).join('')
    :'<div class="text-center text-slate-400 text-[11px] py-6">该档案暂无症状记录</div>';
}
function syDur(m){return m>=1440?Math.round(m/1440)+' 天':(m>=60?(Math.round(m/60*10)/10)+' 小时':m+' 分钟')}
function syColor(l){return ['#10b981','#84cc16','#eab308','#f59e0b','#f97316','#ef4444'][Math.min(5,Math.floor(l/2))]}
function syFilter(x){HP.syPart=x;syRender()}
function syEnd(i){HP.syms[i].on=false;HP.syms[i].min=(HP.syms[i].min||0)+15;syRender();toast('已标记结束 · 持续时长 +15 分钟')}
function syCloud(ss){const el=document.getElementById('syCloud');if(!el)return;
  const c={};ss.forEach(s=>{[s.name].concat((s.desc||'').split(/[ ·,，。]/)).concat((s.tr||'').split(/[ ·,，]/)).forEach(w=>{if(w&&w.length>1)c[w]=(c[w]||0)+1})});
  const ks=Object.keys(c).sort((a,b)=>c[b]-c[a]).slice(0,18),mx=Math.max(1,c[ks[0]]||1);
  hPut('syWcN',ks.length?ks.length+' 个高频词':'暂无文本');
  el.innerHTML=ks.map(k=>`<span style="font-size:${(10+c[k]/mx*8).toFixed(1)}px;opacity:${(.45+c[k]/mx*.55).toFixed(2)}">${k}</span>`).join('')}
let _sy=null,_sySel=null;
function syOpen(idx){const p=hpP();_sy=idx!=null?idx:null;const s=_sy!=null?HP.syms[_sy]:null;
  openSheet('sheetHSymptom');hPut('syTitle',s?('修改 '+s.d+' 的症状'):'记录症状');
  _sySel=s?{name:s.name,lv:s.lv,parts:[s.part],pics:(s.pics||[]).slice(),pain:s.lv}:_sySel||{name:HP.syNames[0],lv:0,parts:[],pics:[],pain:0};
  hDateRow('syDateRow',s?s.d:htDay(0));
  hWheel('syHH',hHours(),s?+s.t.slice(0,2):20);hWheel('syMM',hMins(),s?Math.round(+s.t.slice(3,5)/5):0);
  hWheel('syDur',hNums(5,1440,5),s?Math.round((s.min-5)/5):1);
  syNames();syPainRow();syPartPick();syPics();
  document.getElementById('syTrig').value=s?s.tr||'':'';document.getElementById('syEase').value=s?s.ea||'':'';
  document.getElementById('syDesc').value=s?s.desc||'':'';
  document.getElementById('syOnTg').classList.toggle('on',s?!!s.on:false);
  document.getElementById('syDrugTg').classList.toggle('on',s?!!s.dg:false);
}
function syNames(){const el=document.getElementById('syNameRow');if(!el)return;
  el.innerHTML=HP.syNames.map(n=>`<button class="tag-chip !py-1 ${n===_sySel.name?'on':''}" onclick="_sySel.name='${n}';syNames()">${n}</button>`).join('')}
function syAddName(){const el=document.getElementById('syNameIn'),v=(el.value||'').trim();if(!v){toast('请先填写症状名');return}
  if(!HP.syNames.includes(v))HP.syNames.push(v);_sySel.name=v;el.value='';syNames();toast('已加入常用症状')}
function syPainRow(){const el=document.getElementById('syPain');if(!el)return;
  el.innerHTML=Array.from({length:11},(_,i)=>`<b class="${i===_sySel.pain?'on':''}" style="${i===_sySel.pain?('background:'+syColor(i)):''}" onclick="sySetPain(${i})">${i}</b>`).join('');
  hPut('syPainTx',_sySel.pain+' 分 · '+(_sySel.pain<4?'轻度':_sySel.pain<7?'中度':'重度'))}
function sySetPain(i){_sySel.pain=i;syPainRow()}
function syPartPick(){const el=document.getElementById('syPartPick');if(!el)return;
  el.innerHTML=HP.parts.map(x=>`<button class="tag-chip !py-1 ${_sySel.parts.includes(x)?'on':''}" onclick="syTogPart('${x}')">${x}</button>`).join('')}
function syTogPart(x){const i=_sySel.parts.indexOf(x);i<0?_sySel.parts.push(x):_sySel.parts.splice(i,1);syPartPick()}
function syPics(){const el=document.getElementById('syPics');if(!el)return;
  el.innerHTML=Array.from({length:4},(_,i)=>_sySel.pics[i]?`<div class="ph !border-solid on" style="background:var(--card-bd)" onclick="syRmPic(${i})">IMG<span class="text-[8px] block">移除</span></div>`
    :`<div class="ph" onclick="syAddPic(${i})">＋</div>`).join('')}
function syAddPic(i){_sySel.pics[i]='IMG';syPics();toast('已插入照片 '+(_sySel.pics.filter(Boolean).length)+' 张 · 仅存本机')}
function syRmPic(i){_sySel.pics.splice(i,1);syPics()}
function sySave(){const d=(document.getElementById('syDateRow')||{}).dataset.v||htDay(0);
  const t=('0'+(hWv('syHH')||'20')).slice(-2)+':'+('0'+(hWv('syMM')||'00')).slice(-2);
  const rec={pid:HP.cur,d:d,t:t,name:_sySel.name,lv:_sySel.pain,part:(_sySel.parts[0]||'全身'),min:hNw('syDur')||30,
    tr:(document.getElementById('syTrig').value||'').trim(),ea:(document.getElementById('syEase').value||'').trim(),
    desc:(document.getElementById('syDesc').value||'').trim(),on:document.getElementById('syOnTg').classList.contains('on'),
    dg:document.getElementById('syDrugTg').classList.contains('on'),pics:_sySel.pics.filter(Boolean)};
  if(_sy!=null)HP.syms[_sy]=rec;else HP.syms.push(rec);
  closeSheet('sheetHSymptom');hpRenderAll();
  toast('已记录 '+rec.name+' '+rec.lv+' 分'+(rec.dg?' · 已标为用药相关':''))}
function syEdit(i){syOpen(i)}
function syDel(i){if(!confirmRow('删除该条症状记录'))return;HP.syms.splice(i,1);hpRenderAll();toast('已删除')}

/* ---------- 报告屏 ---------- */
function rpRender(){hpBar('rpBar');const p=hpP();let rs=rpOf(p.id);
  const abn=rs.reduce((a,r)=>a+r.ms.filter(m=>m[1]<m[3]||m[1]>m[4]).length,0);
  const st=document.getElementById('rpStat');
  if(st)st.innerHTML=[['报告',rs.length+' 份'],['异常项',abn+' 条'],['图片/PDF',rs.reduce((a,r)=>a+(r.pics.length||(r.fmt==='PDF'?1:0)),0)+' 个']]
    .map(([n,v])=>`<div class="rounded-xl bg-slate-100 dark:bg-slate-800 py-2"><b class="text-[13px] block" style="color:var(--accent)">${v}</b><span class="text-[9px] text-slate-400">${n}</span></div>`).join('');
  const mo=['全部'].concat([...new Set(rs.map(r=>r.d.slice(0,2)))]);
  const yr=document.getElementById('rpYearRow');
  if(yr)yr.innerHTML=mo.map(x=>`<button class="tag-chip shrink-0 ${x===HP.rpYear?'on':''}" onclick="rpYear('${x}')">${x==='全部'?'全部':(+x)+' 月'}</button>`).join('');
  if(HP.rpYear!=='全部')rs=rs.filter(r=>r.d.slice(0,2)===HP.rpYear);
  const g=document.getElementById('rpGroups');
  if(g)g.innerHTML=rs.length?rs.map(r=>{const i=HP.reports.indexOf(r);
    return `<div class="card !p-0 overflow-hidden">
      <div class="px-4 py-3 flex items-center gap-2" onclick="rpToggle(${i})">
        <div class="flex-1 min-w-0"><b class="text-[13px] block truncate">${r.name}</b>
          <span class="text-[9px] text-slate-400">${r.d} · ${r.hosp} · ${r.fmt} · ${r.ms.length} 项</span></div>
        ${r.ms.filter(m=>m[1]<m[3]||m[1]>m[4]).length?`<span class="mflag hi">${r.ms.filter(m=>m[1]<m[3]||m[1]>m[4]).length} 项异常</span>`:'<span class="mflag ok">全部正常</span>'}
        <span class="text-slate-300" id="rpArw${i}">›</span></div>
      <div class="hidden px-4 pb-3" id="rpBody${i}">
        <div class="flex gap-1.5 mb-2">${r.pics.length?r.pics.map((x,j)=>`<div class="ph w-14 !h-14" style="background:var(--card-bd)">IMG</div>`).join(''):(r.fmt==='PDF'?'<div class="ph w-14 !h-14" style="background:var(--card-bd)">PDF</div>':'')}</div>
        <div>${r.ms.map(m=>{const fl=m[1]<m[3]?'lo':(m[1]>m[4]?'hi':'ok');
          return `<div class="mrow"><span class="text-[11px] truncate">${m[0]}</span><b class="text-[11px]">${m[1]} <span class="text-[9px] font-normal text-slate-400">${m[2]}</span></b><span class="text-[9px] text-slate-400">${m[3]} ~ ${m[4]}</span><span class="mflag ${fl}">${fl==='ok'?'正常':(fl==='lo'?'偏低':'偏高')}</span></div>`}).join('')}</div>
        <div class="text-[10px] text-slate-400 mt-2 leading-4">医生建议：${r.doc||'—'}</div>
        <div class="flex gap-2 mt-2"><button class="flex-1 mini-btn" onclick="hmkOpen(${i})">＋ 检验项</button><button class="flex-1 mini-btn" onclick="rpNote(${i})">关联笔记 ›</button><button class="flex-1 mini-btn" onclick="rpDel(${i})">删除报告</button></div>
      </div></div>`}).join('')
    :'<div class="card text-center text-slate-400 text-[11px] py-6">该档案暂无报告 · 点下方上传</div>';
}
function vtFlag2(){return 'ok'}
function rpYear(x){HP.rpYear=x;rpRender()}
function rpToggle(i){const b=document.getElementById('rpBody'+i),a=document.getElementById('rpArw'+i);
  if(!b)return;b.classList.toggle('hidden');if(a)a.textContent=b.classList.contains('hidden')?'›':'⌄'}
function rpNote(i){const r=HP.reports[i];toast('已新建笔记「就诊心得 · '+r.name+'」并回填报告链接（模拟）')}
function rpDel(i){if(!confirmRow('删除 '+HP.reports[i].name+' 报告'))return;HP.reports.splice(i,1);rpRender();toast('已删除 · 图片随报告移除')}
let _rp=null,_rpDraft=null;
function rpaOpen(idx){_rp=idx!=null?idx:null;const r=_rp!=null?HP.reports[_rp]:null;
  _rpDraft=r?{pics:r.pics.slice(),fmt:r.fmt}:_rpDraft||{pics:[],fmt:'图片 ×0'};
  openSheet('sheetHReportAdd');hPut('rpaTitle',r?('修改 '+r.d+' 的报告'):'上传检查报告');
  hDateRow('rpaDateRow',r?r.d:htDay(0));
  const src=document.getElementById('rpaSrc');
  if(src)src.innerHTML=[['拍照','cam'],['相册','img'],['PDF','doc']].map(([n,k])=>`<button class="card !p-3 flex flex-col items-center gap-1" onclick="rpaAdd('${k}')"><span class="w-8 h-8 rounded-xl flex items-center justify-center" style="background:color-mix(in srgb,var(--accent) 12%,transparent);color:var(--accent)">${hSvg('report','w-4 h-4')}</span><span>${n}</span></button>`).join('');
  document.getElementById('rpaHosp').value=r?r.hosp:'';document.getElementById('rpaName').value=r?r.name:'';
  document.getElementById('rpaDoc').value=r?r.doc:'';rpaPics();rpaPrev()}
function rpaAdd(k){_rpDraft.pics.push(k==='PDF'?'PDF':'IMG');_rpDraft.fmt=k==='PDF'?'PDF':('图片 ×'+_rpDraft.pics.length);rpaPics();rpaPrev();
  toast(k==='PDF'?'已导入 PDF · 原文件仅存本机':'已插入 1 张 · 仅存本机')}
function rpaPics(){const el=document.getElementById('rpaPics');if(!el)return;
  el.innerHTML=_rpDraft.pics.map((x,i)=>`<div class="ph !border-solid" style="background:var(--card-bd)" onclick="rpaRm(${i})">${x}<span class="text-[8px] block">移除</span></div>`).join('')
    +(el.children.length<6?'<div class="ph" onclick="rpaAdd(\'img\')">＋</div>':'')}
function rpaRm(i){_rpDraft.pics.splice(i,1);_rpDraft.fmt=_rpDraft.pics.length?'图片 ×'+_rpDraft.pics.length:'未附';rpaPics();rpaPrev()}
function rpaPrev(){const el=document.getElementById('rpaPreview');if(!el)return;
  el.textContent='附件 '+_rpDraft.pics.length+' 个 · 检验项需建档后逐条录入（参考范围决定偏高/偏低标记）'}
function rpaNote(){toast('已新建笔记并回填报告链接 · 保存后可在笔记内看到（模拟）')}
function rpaSave(){const d=(document.getElementById('rpaDateRow')||{}).dataset.v||htDay(0);
  const nm=(document.getElementById('rpaName').value||'').trim();if(!nm){toast('请填写报告名称');return}
  const rec={pid:HP.cur,d:d,name:nm,hosp:(document.getElementById('rpaHosp').value||'').trim()||'—',
    doc:(document.getElementById('rpaDoc').value||'').trim(),fmt:_rpDraft.fmt,pics:_rpDraft.pics.slice(),ms:_rp!=null?HP.reports[_rp].ms:[]};
  if(_rp!=null)HP.reports[_rp]=rec;else HP.reports.push(rec);
  closeSheet('sheetHReportAdd');rpRender();
  toast('已归档 '+nm+(rec.ms.length?' · '+rec.ms.length+' 项':' · 待录入检验项'))}
function hmkOpen(ri){_rp=ri;openSheet('sheetHMetric');
  const r=HP.reports[ri];hPut('hmkSub',r.name+' · '+r.d+' · 已录 '+r.ms.length+' 项');
  const lib=document.getElementById('hmkLib');
  if(lib)lib.innerHTML=HK_LIB.map((m,i)=>`<button class="tag-chip !py-1" onclick="hmkLib(${i})">${m[0]}</button>`).join('');
  document.getElementById('hmkNameIn').value='';
  HT._wb=hmkTip; hmkWheels(0,400,1);hmkTip();hmkList()}
/* 数值滚轮按量程自适应：跨度小就 0.1 步进，避免上千格滚不动 */
function hmkWheels(lo,hi,step){const span=Math.max(4,(hi-lo));
  const a=Math.max(0,+(lo-span*.45).toFixed(1)),b=+(hi+span*.45).toFixed(1),st=(b-a)>80?1:0.1;
  const vals=hNums(a,b,st);
  hWheel('hmkVal',vals,Math.round(vals.length/2));
  hWheel('hmkLo',hNums(0,Math.max(20,Math.round(hi*1.6)),1),Math.round(lo));
  hWheel('hmkHi',hNums(0,Math.max(20,Math.round(hi*1.6)),1),Math.round(hi))}
function hmkLib(i){const m=HK_LIB[i],el=document.getElementById('hmkNameIn');if(el)el.value=m[0];
  hmkWheels(m[2],m[3]);
  const a=Math.max(0,+(m[2]-1).toFixed(1)),b=+(m[3]+1).toFixed(1),vals=hNums(a,b,0.1),def=(m[2]+m[3])/2;
  let k=0;vals.forEach((x,j)=>{if(Math.abs(x-def)<Math.abs(vals[k]-def))k=j});
  hWheel('hmkVal',vals,k);hmkTip()}
function hmkName(){return ((document.getElementById('hmkNameIn')||{}).value||'').trim()}
function hmkTip(){const el=document.getElementById('hmkTip');if(!el||el.offsetParent===null)return;
  const v=hNw('hmkVal'),lo=hNw('hmkLo'),hi=hNw('hmkHi'),nm=hmkName();
  if(!nm||v==null||lo==null||hi==null){el.textContent='选项目 · 填数值与参考范围后自动标记偏高偏低';return}
  const fl=v<lo?'lo':(v>hi?'hi':'ok');
  el.innerHTML=nm+' <b>'+v+' '+((HK_LIB.find(m=>m[0]===nm)||[,''])[1]||'')+'</b> · 参考 '+lo+' ~ '+hi+' '+
    (fl==='ok'?'<span class="mflag ok">正常</span>':(fl==='lo'?'<span class="mflag lo">偏低</span>':'<span class="mflag hi">偏高</span>'))}
function hmkAdd(){const r=HP.reports[_rp];if(!r)return;
  const nm=hmkName();if(!nm){toast('请先选或填写项目名称');return}
  const u=(HK_LIB.find(m=>m[0]===nm)||[,''])[1]||'';
  r.ms.push([nm,hNw('hmkVal'),u,hNw('hmkLo'),hNw('hmkHi')]);
  hmkList();hmkTip();rpRender();toast('已加入 '+nm+' · 报告标记重算')}
function hmkList(){const el=document.getElementById('hmkList');if(!el)return;const r=HP.reports[_rp];if(!r)return;
  el.innerHTML=r.ms.length?r.ms.map((m,i)=>{const fl=m[1]<m[3]?'lo':(m[1]>m[4]?'hi':'ok');
    return `<div class="mrow"><span class="text-[11px] truncate">${m[0]}</span><b class="text-[11px]">${m[1]} <span class="text-[9px] font-normal text-slate-400">${m[2]}</span></b><span class="text-[9px] text-slate-400">${m[3]} ~ ${m[4]}</span><button class="mflag ${fl}" onclick="HP.reports[${_rp}].ms.splice(${i},1);hmkList();rpRender()">删</button></div>`}).join('')
    :'<div class="text-[10px] text-slate-400 text-center py-2">尚未录入检验项</div>'}

/* ---------- 提醒 ---------- */
function hrmOpen(){openSheet('sheetHRemind');hrmList()}
function hrmList(){const el=document.getElementById('hrmList');if(!el)return;
  el.innerHTML=HP.reminds.map((r,i)=>`<div class="card !py-2.5 flex items-center gap-2">
    <span class="vchip shrink-0">${r.k}</span>
    <div class="flex-1 min-w-0"><b class="text-[12.5px] block truncate">${r.t}</b><span class="text-[9px] text-slate-400">${r.at} · ${r.rep}${r.d?' · '+r.d:''}</span></div>
    <button class="mini-btn !py-1" onclick="hrmTime(${i})">改时刻</button>
    <span class="toggle ${r.on?'on':''}" onclick="HP.reminds[${i}].on=!HP.reminds[${i}].on;hrmList();toast(HP.reminds[${i}].on?'已排程到通知中心':'已撤销排程')"></span></div>`).join('')}
function hrmTime(i){const r=HP.reminds[i];hInline(document.getElementById('hrmList'),'提醒时刻 · '+r.t,hTimes(),r.at,v=>{r.at=v;hrmList()})}
function hrmAdd(){HP.reminds.push({k:'测量',t:'新测量提醒',at:'08:00',rep:'每天',on:false});hrmList();toast('已新增 · 打开开关即排程')}
function hrmSave(){const n=HP.reminds.filter(r=>r.on).length;closeSheet('sheetHRemind');
  toast(n?('已排程 '+n+' 条提醒到通知中心'):'当前无启用提醒')}

/* ---------- AI 健康小结 ---------- */
function aisOpen(){openSheet('sheetHAiSummary');
  const rr=document.getElementById('aisRangeRow');
  if(rr)rr.innerHTML=['近 7 天','近 30 天','近 90 天'].map(x=>`<button class="tag-chip !py-1 ${x===HP.aiRange?'on':''}" onclick="aisRange('${x}',this)">${x}</button>`).join('');
  const mr=document.getElementById('aisMetricRow');
  if(mr)mr.innerHTML=['血压','心率','血氧','血糖','体温','体重','睡眠','运动','症状','报告','用药'].map(x=>`<button class="tag-chip !py-1 ${HP.aiMetrics.includes(x)?'on':''}" onclick="aisTog('${x}',this)">${x}</button>`).join('');
  document.getElementById('aisPayload').classList.add('hidden');
  document.getElementById('aisOut').classList.add('hidden');document.getElementById('aisActs').classList.add('hidden')}
function aisRange(x,el){HP.aiRange=x;[...el.parentElement.children].forEach(b=>b.classList.remove('on'));el.classList.add('on')}
function aisTog(x,el){const i=HP.aiMetrics.indexOf(x);i<0?HP.aiMetrics.push(x):HP.aiMetrics.splice(i,1);el.classList.toggle('on')}
function aisData(){const p=hpP(),n=+HP.aiRange.replace(/\D/g,''),ds=[];
  for(let i=0;i<n;i++)ds.push(htDay(i));
  const vt=vtOf(p.id).filter(v=>ds.includes(v.d)),ss=syOf(p.id).filter(s=>ds.includes(s.d)),rs=rpOf(p.id).filter(r=>ds.includes(r.d));
  return {p,n,ds,vt,ss,rs}}
function aisPayload(){const d=aisData(),L=[];
  L.push('对象：'+d.p.rel+' · '+d.p.sex+' · '+hpAgeOf(d.p)+' 岁 · BMI '+bmiOf2(d.p.w,d.p.h).toFixed(1));
  L.push('病史：'+(d.p.hist.join(' / ')||'无')+' · 过敏：'+(d.p.all.join(' / ')||'无')+' · 长期用药：'+(d.p.lmeds.join(' / ')||'无'));
  L.push('区间：'+HP.aiRange+'（'+d.ds[d.ds.length-1]+' ~ '+d.ds[0]+'）');
  if(HP.aiMetrics.includes('血压')){const b=d.vt.filter(v=>v.k==='bp');
    if(b.length)L.push('血压 '+b.length+' 次 · 均值 '+Math.round(b.reduce((a,x)=>a+x.sys,0)/b.length)+'/'+Math.round(b.reduce((a,x)=>a+x.dia,0)/b.length)+' · 基线 '+d.p.bp[0]+'/'+d.p.bp[1]+' · 超范围 '+b.filter(v=>vtFlag('bp',v.sys)!=='ok').length+' 次')}
  ['心率','血氧','血糖','体温'].forEach(k=>{if(!HP.aiMetrics.includes(k))return;const key=k==='心率'?'hr':(k==='血氧'?'spo2':(k==='血糖'?'glu':'temp'));
    const a=d.vt.filter(v=>v.k===key);if(a.length)L.push(VT[key].n+' '+a.length+' 次 · 均值 '+(a.reduce((s,x)=>s+vtPrimary(x),0)/a.length).toFixed(1)+' '+VT[key].u+' · 异常 '+a.filter(v=>vtFlag(key,vtPrimary(v))!=='ok').length+' 次')});
  if(HP.aiMetrics.includes('体重'))L.push('体重 最新 '+HT.weights[HT.weights.length-1].kg+' kg · 目标 '+HT.goalW+' kg');
  if(HP.aiMetrics.includes('睡眠'))L.push('睡眠 '+HT.sleeps.length+' 晚 · 均值 '+(HT.sleeps.reduce((a,s)=>a+s.h,0)/HT.sleeps.length).toFixed(1)+' h · 目标 '+HT.goalSleep+' h');
  if(HP.aiMetrics.includes('运动'))L.push('运动 '+HT.exs.length+' 次 · 合计 '+HT.exs.reduce((a,e)=>a+e.min,0)+' 分钟');
  if(HP.aiMetrics.includes('症状'))L.push('症状 '+d.ss.length+' 条'+(d.ss.length?' · 最高 '+Math.max(...d.ss.map(s=>s.lv))+' 分 · 部位：'+[...new Set(d.ss.map(s=>s.part))].join('/'):''));
  if(HP.aiMetrics.includes('报告'))L.push('报告 '+d.rs.length+' 份'+(d.rs.length?' · 异常项 '+d.rs.reduce((a,r)=>a+r.ms.filter(m=>m[1]<m[3]||m[1]>m[4]).length,0)+' 条':''));
  if(HP.aiMetrics.includes('用药'))L.push('用药 '+HT.drugs.length+' 种 · 今日依从 '+Math.round(HT.drugs.reduce((a,g)=>a+((g.done||{})[htDay(0)]||[]).length,0))+'/'+HT.drugs.reduce((a,g)=>a+g.times.length,0)+' 次');
  return L}
function aisPreview(){const el=document.getElementById('aisPayload');el.classList.remove('hidden');
  el.innerHTML='<b class="block mb-1">将发送给 AI 的内容（本机生成 · 可逐行核对）</b>'+aisPayload().map(x=>'· '+x).join('<br>')
    +'<br><span class="text-slate-400">只发聚合数值与文字描述 · 不含姓名 · 不含报告图片 · 不含任何凭据</span>'}
function aisRun(btn){const el=document.getElementById('aisOut'),acts=document.getElementById('aisActs');
  const d=aisData(),bp=d.vt.filter(v=>v.k==='bp'),ab=bp.filter(v=>vtFlag('bp',v.sys)!=='ok').length;
  const syTop=(d.ss.sort((a,b)=>b.lv-a.lv)[0]||{}).name;
  el.classList.remove('hidden');acts.classList.remove('hidden');
  el.innerHTML='<div class="flex items-center justify-between"><span class="vchip">AI 生成 · 仅文本整理</span><span class="text-[9px] text-slate-400">'+HP.aiRange+'</span></div>'+
    '<div class="text-[11px] leading-5 mt-2">· 区间内共 '+d.vt.length+' 条体征、'+d.ss.length+' 条症状、'+d.rs.length+' 份报告。<br>'+
    (ab?'· 血压有 '+ab+' 次高于基线参考区间，最高 '+Math.max(...bp.map(v=>v.sys))+' mmHg。<br>':'· 血压全部落在参考区间内。<br>')+
    (syTop?'· 疼痛最重的一次为「'+syTop+'」。<br>':'')+
    '· 以上为数据归纳，<b>不构成诊断或用药建议</b>，异常项请以医生意见为准。</div>';
  btn.textContent='已生成';toast('小结已生成 · 可复制或存入笔记')}
function aisCopy(){toast('小结文本已复制到剪贴板（模拟）')}
function aisToNote(){toast('已新建笔记「健康小结 · '+HP.aiRange+'」并带 AI 生成标识（模拟）')}

/* ---------- 工作台体征条 ---------- */
function hpStrip(){const el=document.getElementById('hpStrip');if(!el)return;const p=hpP();
  const one=k=>{const a=vtOf(p.id,k);return a[a.length-1]};
  el.innerHTML=VT_K.map(k=>{const v=one(k);const fl=v?vtFlag(k,vtPrimary(v)):'ok';
    return `<button class="flex-1 min-w-0 text-center" onclick="htNav('p-vitals');HP.vType='${k}';vtRender()">
      <div class="text-[9px] text-slate-400">${VT[k].n}</div>
      <b class="text-[12.5px] block truncate" style="color:${fl==='ok'?'var(--accent)':'#f43f5e'}">${v?hpFmt(v):'—'}</b></div>`}).join('')}

/* ---------- 启动 ---------- */
function hpBoot(){hpSeed();hpRenderAll();
  const nav=document.getElementById('p-health');
  if(nav)nav.addEventListener('click',()=>{},false)}
