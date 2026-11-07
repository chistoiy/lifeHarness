// tools/r151_proto.js · R15-1/V1.56 原型门补丁：给记账专版补「导入记录 + 整批撤销」
// 口径（2026-09-30 产品拍板）：入口=完成页钮 + 批次列表两者都要 · 账户回收=默认不勾+勾选项 · 可撤销范围=仅最近一批
// 手法：命中断言式替换（每处必须恰好 1 次），改后打印体积差；不整文件重写。
const fs = require('fs');
const F = 'prototype/index-ledger.html';
let s = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const before = s.length;
const hits = [];
function rep(label, oldStr, newStr) {
  const n = s.split(oldStr).length - 1;
  if (n !== 1) { console.error('MISS[' + label + '] 命中 ' + n + ' 次（应为 1）'); process.exit(1); }
  s = s.replace(oldStr, newStr);
  hits.push(label);
}

/* ---------- 1. biHome「已导入的账单」死行 → 真实列表入口（带批次数） ---------- */
rep('biHome-导入记录行',
  `        <button class="mt-3 w-full card flex items-center py-3.5" onclick="toast('已导入的账单列表（模拟）')">
          <span class="flex-1 text-left text-sm font-bold">已导入的账单</span><span class="text-slate-300">›</span></button>`,
  `        <button class="mt-3 w-full card flex items-center py-3.5" onclick="biOpenBatches()">
          <span class="flex-1 text-left text-sm font-bold">导入记录</span><span class="text-xs text-slate-400" id="biBatCnt"></span><span class="text-slate-300 ml-1">›</span></button>`);

/* ---------- 2. 屏5 导入完成（撤销本批＝真动作） ---------- */
rep('屏5-biDone',
  `      <!-- 图3 类别关联半屏弹层 -->`,
  `      <!-- 屏5 导入完成（R15-1：「撤销本批」是可点动作，不是文案承诺） -->
      <div id="biDone" class="hidden">
        <div class="mt-8 flex flex-col items-center text-center">
          <svg class="w-14 h-14 text-emerald-500" fill="none" stroke="currentColor" stroke-width="1.8" viewBox="0 0 24 24" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="m8.4 12.4 2.6 2.6 4.6-5.2"/></svg>
          <div class="text-lg font-extrabold mt-3">导入完成</div>
          <div class="text-[11px] text-slate-400 leading-5 mt-2" id="biDoneSum"></div>
        </div>
        <button class="mt-7 w-full py-3.5 rounded-2xl border-2 border-rose-400 text-rose-500 text-[15px] font-bold" id="biDoneUndo" onclick="biAskUndo(biLatest(),'done')">撤销本批</button>
        <button class="mt-3 w-full py-3.5 rounded-2xl grad text-white text-[15px] font-bold shadow-md shadow-indigo-500/30" onclick="biBackHome()">完成</button>
        <button class="mt-4 w-full card flex items-center py-3.5" onclick="biOpenBatches()">
          <span class="flex-1 text-left text-sm font-bold">导入记录</span><span class="text-xs text-slate-400" id="biBatCnt2"></span><span class="text-slate-300 ml-1">›</span></button>
      </div>

      <!-- 图3 类别关联半屏弹层 -->`);

/* ---------- 3. S6 导入记录半屏 + S7 撤销二次确认半屏 ---------- */
rep('S6S7-两弹层',
  `  <!-- ===== S5 金额滚轮弹层（预算/余额调整共用） ===== -->`,
  `  <!-- ===== S6 导入记录（批次列表 · R15-1 · 仅最近一批给撤销） ===== -->
  <div id="sheetLedgerBatches" class="sheet hidden fixed md:absolute inset-0 z-50 bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetLedgerBatches')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8 max-h-[80vh] overflow-y-auto no-scrollbar">
      <div class="grabber"></div>
      <div class="font-extrabold text-sm">导入记录</div>
      <div class="mt-3 space-y-2" id="biBatList"></div>
      <button class="mt-3 w-full py-2.5 rounded-2xl bg-slate-100 dark:bg-slate-800 text-[12px] font-bold" onclick="closeSheet('sheetLedgerBatches')">关闭</button>
    </div>
  </div>

  <!-- ===== S7 撤销本批二次确认（R15-1 · 默认只删流水，账户回收为勾选项） ===== -->
  <div id="sheetLedgerUndo" style="z-index:70" class="sheet hidden fixed md:absolute inset-0 z-50 bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetLedgerUndo')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="grabber"></div>
      <div class="text-center mt-1"><div class="text-base font-extrabold">撤销本批导入</div>
        <div class="text-[12px] text-slate-400 mt-2 leading-5" id="buSum"></div></div>
      <label class="mt-5 flex items-center gap-2.5 px-1 text-[13px] cursor-pointer" id="buRow" onclick="biUndoTog()">
        <span class="toggle"></span>同时移除本批新建且已无引用的账户</label>
      <div class="text-[10px] text-slate-400 px-1 mt-1.5" id="buAcctNote"></div>
      <div class="mt-5 flex gap-2">
        <button class="flex-1 py-3 rounded-2xl bg-slate-100 dark:bg-slate-800 text-[13px] font-bold" onclick="closeSheet('sheetLedgerUndo')">取消</button>
        <button class="flex-[2] py-3 rounded-2xl bg-rose-500 text-white text-[13px] font-extrabold" onclick="biUndoGo()">确认撤销</button>
      </div>
    </div>
  </div>

  <!-- ===== S5 金额滚轮弹层（预算/余额调整共用） ===== -->`);

/* ---------- 4. 状态位 ---------- */
rep('状态位',
  `let biN=1,biSrc='微信',biRows=null,biSel=new Set(),biAccts=null,biCatK=null,biCatBatch=false,biCatTmp=null,biCatTmpSub='',biAcctIdx=null;`,
  `let biN=1,biSrc='微信',biRows=null,biSel=new Set(),biAccts=null,biCatK=null,biCatBatch=false,biCatTmp=null,biCatTmpSub='',biAcctIdx=null;
/* R15-1：批次记录（原型为内存态·不真持久化）· biFileName=本次文件名 · biUndo*=撤销弹层态 */
let BI_BATCH=[],biBatSeq=0,biFileName='',biUndoId=null,biUndoFrom='list',biUndoReclaim=false;`);

/* ---------- 5. 选文件时记下文件名 ---------- */
rep('biChooseFile-记名',
  ` $('#biFileName').textContent=(BI_SRC.find(x=>x.k===biSrc)||{}).n+ext[biSrc];`,
  ` biFileName=(BI_SRC.find(x=>x.k===biSrc)||{}).n+ext[biSrc];$('#biFileName').textContent=biFileName;`);

/* ---------- 6. biCommit：登记批次 · 流水挂 bat · 跳完成屏 ---------- */
rep('biCommit',
  `function biCommit(){const nw=biAccts.filter(a=>a.pick==='__new');
 nw.forEach(a=>{if(!L.accounts.some(x=>x.n===a.src))L.accounts.push({id:'imp_'+a.src,type:a.src.includes('储蓄卡')?'debit':'ewallet',n:a.src,i:'card',c:'#8b5cf6',base:0});});
 let cnt=0;for(const r of biRows){if(!biSel.has(r.k))continue;const a=biAccts.find(x=>x.src===r.pay);const acc=a&&a.pick!=='__new'?(L.accounts.find(x=>x.n===a.pick)||{id:a.pick}).id||'imp_'+a.src:'imp_'+r.pay;
  ledgerAdd({kind:r.kind==='income'?'income':'expense',cat:r.cat,sub:'',n:r.m,amt:r.amt,a:acc,d:r.d,tags:[],src:'bill',note:biSrc+' · '+r.t});cnt++;}
 toast('✔ 已写入 '+cnt+' 条流水 · 支持整批撤销');biN=1;biRows=null;biSel=new Set();biAccts=null;renderBi();}`,
  `function biCommit(){const nw=biAccts.filter(a=>a.pick==='__new');const made=[];
 nw.forEach(a=>{if(!L.accounts.some(x=>x.n===a.src)){L.accounts.push({id:'imp_'+a.src,type:a.src.includes('储蓄卡')?'debit':'ewallet',n:a.src,i:'card',c:'#8b5cf6',base:0});made.push({id:'imp_'+a.src,n:a.src});}});
 const biBat={id:++biBatSeq,plat:biSrc,file:biFileName||'账单文件',ts:biNow(),n:0,skip:0,made};
 for(const r of biRows){const a=biAccts.find(x=>x.src===r.pay);const acc=a&&a.pick!=='__new'?(L.accounts.find(x=>x.n===a.pick)||{id:a.pick}).id||'imp_'+a.src:'imp_'+r.pay;
  if(!biSel.has(r.k)){biBat.skip++;continue;}
  ledgerAdd({kind:r.kind==='income'?'income':'expense',cat:r.cat,sub:'',n:r.m,amt:r.amt,a:acc,d:r.d,tags:[],src:'bill',note:biSrc+' · '+r.t,bat:biBat.id});biBat.n++;}
 BI_BATCH.push(biBat);biRows=null;biSel=new Set();biAccts=null;biN=5;renderBi();}`);

/* ---------- 7. renderBi 支持第 5 屏 ---------- */
rep('renderBi-显隐',
  ` [1,2,3,4].forEach(n=>$('#bi'+['Home','File','Acct','Detail'][n-1]).classList.toggle('hidden',n!==biN));`,
  ` [1,2,3,4].forEach(n=>$('#bi'+['Home','File','Acct','Detail'][n-1]).classList.toggle('hidden',n!==biN));
 $('#biDone').classList.toggle('hidden',biN!==5);biBatCnt();`);
rep('renderBi-屏5文案',
  ` if(biN===4){pt.textContent='共'+(biRows?biRows.length:0)+'笔明细';if(ps)ps.textContent='';}}`,
  ` if(biN===4){pt.textContent='共'+(biRows?biRows.length:0)+'笔明细';if(ps)ps.textContent='';}
 if(biN===5){const b=BI_BATCH[BI_BATCH.length-1];pt.textContent='导入完成';if(ps)ps.textContent='本批可整批撤销';
  $('#biDoneSum').innerHTML=b?b.plat+' · '+b.file+'<br>写入 '+b.n+' 条'+(b.skip?' · 未勾选 '+b.skip+' 条不导入':'')+(b.made.length?'<br>新建账户 '+b.made.length+' 个（'+b.made.map(x=>x.n).join('、')+'）':''):'';}}`);

/* ---------- 8. 批次列表 / 撤销 引擎（挂在 billStep 之后） ---------- */
const engine = [
  'function billStep(d){renderBi();}',
  '/* ===== R15-1 导入记录与整批撤销（可撤范围＝最近一批；账户回收默认不勾） ===== */',
  "function biNow(){const d=new Date(),p=n=>String(n).padStart(2,'0');return p(d.getMonth()+1)+'-'+p(d.getDate())+' '+p(d.getHours())+':'+p(d.getMinutes());}",
  'function biLatest(){const b=BI_BATCH[BI_BATCH.length-1];return b?b.id:null;}',
  'function biBatCnt(){const t=BI_BATCH.length?BI_BATCH.length+\' 批\':\'\';',
  "  const e1=$('#biBatCnt'),e2=$('#biBatCnt2');if(e1)e1.textContent=t;if(e2)e2.textContent=t;}",
  "function biOpenBatches(){renderBiBatches();openSheet('sheetLedgerBatches');}",
  'function renderBiBatches(){const el=$(\'#biBatList\');if(!el)return;',
  ' if(!BI_BATCH.length){el.innerHTML=\'<div class="text-center text-xs text-slate-400 py-6">暂无导入记录</div>\';return;}',
  ' const last=biLatest();',
  ' el.innerHTML=BI_BATCH.slice().reverse().map(b=>{const st=BI_SRC.find(x=>x.k===b.plat)||{badge:\'账\',bg:\'#64748B1a\',c:\'#64748B\'};',
  '  const btn=b.id===last?\'<button class="px-3.5 py-2 rounded-full border border-rose-400 text-rose-500 text-[12px] font-bold shrink-0" onclick="biAskUndo(\'+b.id+\',\\\'list\\\')">撤销</button>\':\'\';',
  '  return \'<div class="card !p-3 flex items-center gap-3"><span class="w-9 h-9 rounded-lg flex items-center justify-center text-[14px] font-black shrink-0" style="background:\'+st.bg+\';color:\'+st.c+\'">\'+st.badge+\'</span>\'+',
  '   \'<div class="flex-1 min-w-0"><div class="text-[13px] font-bold truncate">\'+b.file+\'</div><div class="text-[10px] text-slate-400 truncate mt-0.5">\'+b.plat+\' · \'+b.ts+\' · 写入 \'+b.n+\' 条\'+(b.made.length?\' · 新建账户 \'+b.made.length+\' 个\':\'\')+\'</div></div>\'+btn+\'</div>\';}).join(\'\');}',
  "function biAskUndo(id,from){const b=BI_BATCH.find(x=>x.id===id);if(!b)return;",
  " biUndoId=id;biUndoFrom=from||'list';biUndoReclaim=false;",
  " $('#buSum').innerHTML='将删除 <b>'+b.n+'</b> 条流水 · '+b.plat+' · '+b.file+'<br>报表、分类占比与资产页同步重算';",
  " $('#buAcctNote').textContent=b.made.length?('本批新建账户：'+b.made.map(x=>x.n).join('、')):'本批未新建账户';",
  " $('#buRow').classList.toggle('hidden',!b.made.length);",
  " $('#sheetLedgerUndo').querySelector('.toggle').classList.remove('on');",
  " openSheet('sheetLedgerUndo');}",
  "function biUndoTog(){biUndoReclaim=!biUndoReclaim;",
  " $('#sheetLedgerUndo').querySelector('.toggle').classList.toggle('on',biUndoReclaim);}",
  'function biUndoGo(){const b=BI_BATCH.find(x=>x.id===biUndoId);if(!b)return;',
  ' let n=0;L.txns=L.txns.filter(t=>{if(t.bat===b.id){n++;return false;}return true;});',
  ' let rc=0;',
  ' if(biUndoReclaim)b.made.forEach(m=>{',
  '  const used=L.txns.some(t=>t.a===m.id||t.to===m.id);',
  '  const a=L.accounts.find(x=>x.id===m.id);',
  '  if(!used&&a&&a.base===0){L.accounts=L.accounts.filter(x=>x.id!==m.id);rc++;}});',
  ' BI_BATCH=BI_BATCH.filter(x=>x.id!==b.id);',
  " closeSheet('sheetLedgerUndo');finTouch();",
  " if(biUndoFrom==='done'){biBackHome();}else{renderBiBatches();biBatCnt();}",
  " toast('已撤销批次 '+b.id+' · 删除 '+n+' 条流水'+(rc?' · 移除 '+rc+' 个账户':''));}"
].join('\n');
rep('撤销引擎', 'function billStep(d){renderBi();}', engine);

fs.writeFileSync(F, s);
console.log('命中 ' + hits.length + ' 处：' + hits.join(' / '));
console.log('体积 ' + before + ' → ' + s.length + '（+' + (s.length - before) + '）');
