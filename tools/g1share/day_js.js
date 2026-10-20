/* ================= 分享长图（G1 #2 · 四站共用） =================
 * 预览层＝真实分享物的形态；「复制文字版」出纯文本，「保存图片」在 Flutter 侧
 * 走 RepaintBoundary → PNG → 应用目录 share/<名>.png（口径同阅读书单长图）。 */
let scKind='stats';
const SC_REP={'once':'一次性倒数','solar-year':'每年（公历循环）',lunar:'每年（农历自动换算）',monthly:'每月循环'};
function scData(){
  if(scKind==='settle'){const it=D.items[curItem],pool=poolOf(it),inv=it.cost+it.extra;
    return {file:'决算-'+it.n,eyebrow:'LifeHarness · 物品决算',title:it.n+' 决算报告',
      line:it.st+' · '+it.buy+' 建档 · '+it.tl[it.tl.length-1].d+' 冻结',
      big:'¥ '+(pool/it.days).toFixed(2),unit:'/天',
      tiles:[['总投入',fmtY(inv)],['持有',it.days.toLocaleString()+' 天'],['净持有',fmtY(pool)]],
      secs:[{hd:'决算口径',rows:[['残值回收',fmtY(it.res)],['回收率',(inv?Math.round(it.res/inv*100):0)+'%'],['真实日均','¥'+(pool/it.days).toFixed(2)+'/天']]},
            {hd:'审计时间轴',rows:it.tl.map(e=>[e.a+' '+e.t,e.d])}]};}
  if(scKind==='day'){const d=D.days[curDay];
    return {file:'倒数日-'+d.t,eyebrow:'LifeHarness · 重要日子',title:d.t,
      line:d.l+' · '+(SC_REP[d.rep]||''),
      big:String(Math.abs(d.d)),unit:d.d>=0?'天后':'天前',
      tiles:[['类别',d.cat],['提醒',(d.rem||[]).map(v=>v===0?'当天':'前'+v+'天').join('/')||'无'],['准备',(d.prep||[]).length+' 项']],
      secs:[{hd:'准备事项',rows:(d.prep||[]).map(p=>[p.t,p.done?'已完成':'待办'])}]
        .concat(d.note?[{hd:'备注',rows:[[d.note,'']]}]:[])
        .concat((d.diary||[]).length?[{hd:'历年关联日记',rows:d.diary.map(s=>[s,''])}]:[])};}
  if(scKind==='review'){const i=Math.min(grIdx,D.reviews.length-1),rv=D.reviews[i],os=D.okr.filter(o=>o.per===rv.q);
    const kr=os.reduce((s,o)=>s+o.kr.length,0);
    return {file:'复盘-'+rv.q.replace(' ',''),eyebrow:'LifeHarness · 季度复盘',title:rv.q+' KPT 复盘',
      line:os.length+' 个目标 · '+kr+' 条 KR · 已归档',
      big:rv.p+'%',unit:'整体达成',
      tiles:[['目标',os.length+' 个'],['KR',kr+' 条'],['均达',Math.round(os.reduce((s,o)=>s+o.p,0)/(os.length||1))+'%']],
      secs:[{hd:'KR 达成对照',rows:os.reduce((a,o)=>a.concat(o.kr.map(k=>[k.k,k.v+'%'])),[])},
            {hd:'Keep · 做对了什么',rows:[[rv.k,'']]},
            {hd:'Problem · 卡在哪',rows:[[rv.r,'']]},
            {hd:'Try · 下季怎么改',rows:[[rv.y,'']]}]};}
  const bill=D.items.filter(x=>x.calc),total=bill.reduce((s,x)=>s+costOf(x),0);
  const poolAll=D.items.reduce((s,x)=>s+poolOf(x),0),cats={};
  bill.forEach(x=>{cats[x.cat]=(cats[x.cat]||0)+poolOf(x)});
  const top=[...bill].sort((a,b)=>costOf(b)-costOf(a)).slice(0,5);
  return {file:'物品价值统计',eyebrow:'LifeHarness · 物品价值',title:'今日持有成本',
    line:'计费中 '+bill.length+' 件 · 已归档决算 '+(D.items.length-bill.length)+' 件',
    big:'¥ '+total.toFixed(2),unit:'/天',
    tiles:[['本月花掉',fmtY(Math.round(total*30))],['成本池',fmtY(Math.round(poolAll))],['件均日均','¥'+(bill.length?(total/bill.length).toFixed(2):'0.00')]],
    secs:[{hd:'日均成本 Top 5',rows:top.map(x=>[x.n,'¥'+costOf(x).toFixed(2)+'/天'])},
          {hd:'分类占比 · 按成本池',rows:Object.entries(cats).sort((a,b)=>b[1]-a[1]).map(([k,v])=>[k,Math.round(v/poolAll*100)+'%'])}]};
}
function scOpen(k){scKind=k;scRender();openSheet('sheetShareCard')}
function scRender(){const m=scData(),el=$('#scImg');if(!el)return;
 el.innerHTML=`<div class="grad text-white p-5">
  <div class="text-[11px] opacity-85">${m.eyebrow}</div>
  <div class="text-lg font-black mt-1 leading-6">${m.title}</div>
  <div class="text-[10.5px] opacity-85 mt-1">${m.line}</div>
  <div class="mt-3 flex items-end gap-1.5"><span class="text-4xl font-black leading-none">${m.big}</span><span class="text-sm font-bold opacity-85 pb-0.5">${m.unit}</span></div>
  <div class="mt-4 grid grid-cols-3 gap-2 text-center">${m.tiles.map(t=>`<div class="rounded-2xl bg-white/15 py-2"><b class="text-[13px] block">${t[1]}</b><span class="text-[9px] opacity-85">${t[0]}</span></div>`).join('')}</div></div>
 <div class="p-5 bg-white dark:bg-slate-900">
  ${m.secs.filter(s=>s.rows.length).map(s=>`<div class="mb-4"><div class="text-[11px] font-black text-slate-500">${s.hd}</div>
   ${s.rows.map(r=>r[1]?`<div class="flex items-center gap-2 py-1.5 text-[12px] border-b border-slate-100 dark:border-slate-800"><span class="flex-1 min-w-0">${r[0]}</span><b class="shrink-0 text-mint">${r[1]}</b></div>`:`<div class="py-1.5 text-[12px] leading-5">${r[0]}</div>`).join('')}</div>`).join('')}
  <div class="pt-1 flex items-center gap-2 text-[9.5px] text-slate-400"><span class="flex-1 h-px bg-slate-200 dark:bg-slate-800"></span>数据仅存本机<span class="flex-1 h-px bg-slate-200 dark:bg-slate-800"></span></div></div>`;}
function scText(){const m=scData(),L=[m.title,m.big+' '+m.unit,m.line];
 m.secs.forEach(s=>{if(!s.rows.length)return;L.push('','〔'+s.hd+'〕');s.rows.forEach(r=>L.push(r[1]?r[0]+'：'+r[1]:r[0]))});
 return L.join('\n')}
function scCopy(){const t=scText();
 if(navigator.clipboard&&navigator.clipboard.writeText)navigator.clipboard.writeText(t).then(()=>toast('文字版已复制'),()=>toast('复制失败 · 可在预览里长按选择'));
 else toast('当前浏览器不支持剪贴板')}
function scSave(){toast('分享长图已保存：share/'+scData().file.replace(/[\\/:*?"<>|]/g,'')+'.png')}

/* ================= 全局搜索 ================= */
