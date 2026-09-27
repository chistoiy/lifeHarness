/* 批3.5 原型增量补丁 · prototype/index-bookshelf.html
 * 内容：整本预载封面态 / 单书清缓存弹层与三态 / 重新载入 / 原文件丢失引导重选（合并导入挂回）
 * 惯例：BS_OLD_* 包装器 + 模板追加位；每条替换断言命中恰好 1 次；写后校验体积。
 * 已执行 2026-09-28 · 勿重跑（锚点会命中 0 次）。 */
const fs = require('fs');
const P = 'prototype/index-bookshelf.html';
let H = fs.readFileSync(P, 'utf8');
const before = H.length;
let hits = 0;
function rep(name, find, sub) {
  const parts = H.split(find);
  const n = parts.length - 1;
  if (n !== 1) { console.error('ANCHOR ' + name + ' hits=' + n + ' (expect 1)'); process.exit(1); }
  H = parts.join(sub);
  hits++;
  console.log('ok  ' + name);
}

/* ---- 1) CSS ---- */
rep('css', '.br-local{position:absolute;right:3px;bottom:3px;z-index:5;display:inline-flex;align-items:center;gap:2px;font-size:8px;font-weight:800;color:#fff;background:rgba(15,23,42,.62);backdrop-filter:blur(3px);border-radius:99px;padding:1.5px 5px;line-height:1.4}',
String.raw`.br-local{position:absolute;right:3px;bottom:3px;z-index:5;display:inline-flex;align-items:center;gap:2px;font-size:8px;font-weight:800;color:#fff;background:rgba(15,23,42,.62);backdrop-filter:blur(3px);border-radius:99px;padding:1.5px 5px;line-height:1.4}
    .br-cached{background:rgba(217,119,6,.92)}
    .br-covovl{position:absolute;inset:0;z-index:6;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px}
    .br-covovl.pre{background:linear-gradient(180deg,rgba(15,23,42,.42),rgba(15,23,42,.74))}
    .br-covovl.cl{background:rgba(15,23,42,.5)}
    .br-prebar{width:70%;height:4px;border-radius:99px;background:rgba(255,255,255,.26);overflow:hidden}
    .br-prebar i{display:block;height:100%;border-radius:99px;background:#fff;transition:width .25s}
    .br-prepct{font-size:9px;font-weight:800;color:#fff;letter-spacing:.3px}
    .br-clchip{display:inline-flex;align-items:center;gap:3px;font-size:8.5px;font-weight:800;color:#fff;background:rgba(217,119,6,.94);border-radius:99px;padding:2px 6px}
    .br-dcache{border-left:3px solid #d97706}`);

/* ---- 2) 弹层三枚：清理缓存 / 重新载入 / 源文件丢失 ---- */
rep('sheets', String.raw`        <button class="flex-[2] py-3 rounded-2xl bg-rose-500 text-white text-sm font-bold" onclick="brDelCommit()">确认删除</button>
      </div>
    </div>
  </div>`,
String.raw`        <button class="flex-[2] py-3 rounded-2xl bg-rose-500 text-white text-sm font-bold" onclick="brDelCommit()">确认删除</button>
      </div>
    </div>
  </div>

  <!-- ===== 批3.5 · 清理缓存（单书·保留记录） ===== -->
  <div id="sheetBrCache" class="sheet hidden fixed md:absolute inset-0 z-[70] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetBrCache')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <b class="text-[15px]">清理缓存 · 《<span id="brCacheName">—</span>》</b>
      <div class="mt-3 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-3 text-[11px] leading-5" id="brCacheInfo"></div>
      <div class="mt-3 space-y-1.5 text-[11px] leading-5 text-slate-500 dark:text-slate-400">
        <div class="flex items-start gap-1.5"><span class="text-emerald-500 font-black">保留</span><span>阅读记录 · 进度与位置 · 外观记忆 · 划线与书摘 · 计时</span></div>
        <div class="flex items-start gap-1.5"><span class="text-sky-500 font-black">不动</span><span>源文件（不删除、不移动原文件本体）</span></div>
        <div class="flex items-start gap-1.5"><span class="text-amber-600 font-black">释放</span><span>本地副本 · 封面衍生图 · 分页缓存</span></div>
      </div>
      <div class="mt-4 flex gap-2">
        <button class="flex-1 py-3 rounded-2xl border border-slate-200 dark:border-slate-700 text-sm font-bold" onclick="closeSheet('sheetBrCache')">取消</button>
        <button class="flex-[2] py-3 rounded-2xl bg-amber-500 text-white text-sm font-bold" onclick="brCacheCommit()">清理缓存 · 约释放 <span id="brCacheSize">—</span></button>
      </div>
    </div>
  </div>

  <!-- ===== 批3.5 · 重新载入（已清缓存·原文件可读） ===== -->
  <div id="sheetBrReload" class="sheet hidden fixed md:absolute inset-0 z-[70] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetBrReload')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <b class="text-[15px]">重新载入 · 《<span id="brReloadName">—</span>》</b>
      <div class="mt-3 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-3 text-[11px] leading-5" id="brReloadInfo"></div>
      <div class="mt-3 text-[10px] leading-5 text-slate-400">将重新拷贝本地副本并预载整本书，完成前封面显示预载进度。</div>
      <div class="mt-4 flex gap-2">
        <button class="flex-1 py-3 rounded-2xl border border-slate-200 dark:border-slate-700 text-sm font-bold" onclick="closeSheet('sheetBrReload')">稍后</button>
        <button class="flex-[2] py-3 rounded-2xl grad text-white text-sm font-bold" onclick="brReloadCommit()">重新拷贝并预载</button>
      </div>
    </div>
  </div>

  <!-- ===== 批3.5 · 源文件丢失 → 重新选择文件 ===== -->
  <div id="sheetBrLost" class="sheet hidden fixed md:absolute inset-0 z-[70] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetBrLost')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <b class="text-[15px] text-amber-600">源文件已不存在 · 《<span id="brLostName">—</span>》</b>
      <div class="mt-3 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-3 text-[11px] leading-5" id="brLostInfo"></div>
      <div class="mt-3 text-[10px] leading-5 text-slate-400">阅读记录已全部保留。重新选择该书的 EPUB 文件后，本地副本与预载会自动挂回原记录。</div>
      <div class="mt-4 flex gap-2">
        <button class="flex-1 py-3 rounded-2xl border border-slate-200 dark:border-slate-700 text-sm font-bold" onclick="closeSheet('sheetBrLost')">知道了</button>
        <button class="flex-[2] py-3 rounded-2xl grad text-white text-sm font-bold" onclick="brLostGoImp()">重新选择文件</button>
      </div>
    </div>
  </div>`);

/* ---- 3) 导入完成 = 后台预载起点（新书 / 合并挂回 / 删除守卫停表） ---- */
rep('commit-new', String.raw`fin:'',local:1,epub:{fmt:m.fmt,size:brImp.file.sz,path:'内部存储/'+(brImp.dir==='download'?'下载':'文档')+'/'+brImp.file.n},coverCss:m.cover||''});`,
String.raw`fin:'',local:1,epub:{fmt:m.fmt,size:brImp.file.sz,path:'内部存储/'+(brImp.dir==='download'?'下载':'文档')+'/'+brImp.file.n,name:brImp.file.n,st:'pre',pr:4,cache:brImp.file.sz,srcOk:1},coverCss:m.cover||''});
  brPreStart(id,4);`);

rep('commit-merge', String.raw`    if(tagOn&&!b.tags.includes('本地'))b.tags.push('本地');
    renderShelf();renderQuotes();toast('《'+b.n+'》已附本地文件 · 点封面直接进入阅读');`,
String.raw`    if(tagOn&&!b.tags.includes('本地'))b.tags.push('本地');
    b.epub.name=b.epub.name||brImp.file.n;b.epub.cache=b.epub.cache||brImp.file.sz;b.epub.srcOk=1;
    if(brImp.lostId===b.id){b.epub.st='pre';b.epub.pr=4;delete b.epub.lost;brPreStart(b.id,4);}
    renderShelf();renderQuotes();toast('《'+b.n+'》已'+(brImp.lostId===b.id?'重新挂回 · 正在预载':'附本地文件 · 预载完成后点封面进入阅读'));`);

rep('commit-clear', String.raw`function brDelCommit(){const b=bsBook(brDelId);if(!b)return closeSheet('sheetBrDel');
  b.local=0;delete b.epub;`,
String.raw`function brDelCommit(){const b=bsBook(brDelId);if(!b)return closeSheet('sheetBrDel');
  if(b.epub&&b.epub.st==='pre')brPreStop(b.id);
  b.local=0;delete b.epub;`);

/* ---- 4) 重选模式：文件名匹配优先挂回丢失记录 + 导入页提示 ---- */
/* 原文该处为反引号模板：find/sub 用普通字符串转义书写（\` \\${ 为字面反引号/美元括号） */
rep('meta-dup',
"  const dup=BS_BOOKS.find(b=>brNorm(b.n)===brNorm(m.t)||b.n===f.merge);\n" +
"  brImp.mergeTo=dup?dup.id:null;\n" +
"  document.getElementById('brDup').classList.toggle('hidden',!dup);\n" +
"  if(dup){document.getElementById('brDup').innerHTML=\`已存在《${dup.n}》（${dup.src} · ${dup.st}${dup.st==='在读'?' '+dup.p+'%':''}）。推荐把本地文件<b>挂到该记录</b>：书摘、计时、进度共用一条，点封面即可阅读。\`}\n" +
"  document.getElementById('brSaveBtn').textContent=dup?'合并到已有记录 · 附本地文件':'加入书架 · 开始阅读';",
"  const lost=br35LostBook(f.n);\n" +
"  const dup=lost||BS_BOOKS.find(b=>brNorm(b.n)===brNorm(m.t)||b.n===f.merge);\n" +
"  brImp.mergeTo=dup?dup.id:null;brImp.lostId=lost?lost.id:null;\n" +
"  document.getElementById('brDup').classList.toggle('hidden',!dup);\n" +
"  if(dup){document.getElementById('brDup').innerHTML=lost?\`原文件丢失的《${lost.n}》仍在书架保留全部记录。本次将把选中的文件<b>挂回原记录</b>：书摘、计时、进度共用一条。\`:\`已存在《${dup.n}》（${dup.src} · ${dup.st}${dup.st==='在读'?' '+dup.p+'%':''}）。推荐把本地文件<b>挂到该记录</b>：书摘、计时、进度共用一条，点封面即可阅读。\`}\n" +
"  const at=document.getElementById('brAttachHint');if(at)at.classList.add('hidden');\n" +
"  document.getElementById('brSaveBtn').textContent=dup?(lost?'挂回原记录 · 重新预载':'合并到已有记录 · 附本地文件'):'加入书架 · 预载后可读';");

rep('files-hint', String.raw`function brImpFiles(){const box=document.getElementById('brFiles');`,
String.raw`function brImpFiles(){const box=document.getElementById('brFiles');
  const at=document.getElementById('brAttachHint');
  if(at){const lb=br35LostBook();at.classList.toggle('hidden',!lb);if(lb)at.innerHTML='正在为《'+brEsc(lb.n)+'》重新选择文件 · 选中原文件即挂回原记录';}`);

/* ---- 5) 长按注入按钮改为带状态守卫的入口（唯一锚点=onclick 片段） ---- */
rep('lp-run', String.raw`onclick="closeSheet(\'sheetLongPress\');brOpen(\''+id+'\')"`,
String.raw`onclick="brLpRead(\''+id+'\')"`);

/* ---- 6) 批3.5 主体：预载状态机 + 封面态 + 入口守卫 + 三态弹层 + 详情缓存行 + 深链 ---- */
rep('block', String.raw`/* ================= 阅读器（书架专版）结束 ================= */`,
String.raw`/* ================= 批3.5 · 导入预载 + 大书内存模型 + 单书清缓存 ================= */
/* 数据口径：b.epub={fmt,size,path,name, st:'pre'|'rdy'|'cl', pr:0-100, cache:'约释放 MB', srcOk:1|0, lostAt}
   三态：就绪→点封面秒进；已清缓存且原文件可读→提示后重新拷贝+预载；原文件丢失→引导重选文件走合并导入挂回原记录。
   清理只回收本地副本/封面衍生/分页缓存；记录·书摘划线·计时·进度全保留；原文件绝不删除。 */
const BR35_OLD_COVBADGE=brCovBadge;
brCovBadge=function(b){return BR35_OLD_COVBADGE(b)+(b&&b.epub&&b.epub.st==='cl'?'<span class="br-local br-cached"><svg width="7" height="7" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M12 15V4"/><path d="m7 10 5-5 5 5"/><path d="M5 19h14"/></svg>已清缓存</span>':'')};
const BR35_OLD_ROWBADGE=brRowBadge;
brRowBadge=function(b){return BR35_OLD_ROWBADGE(b)+(b&&b.epub&&b.epub.st==='cl'?'<span class="text-[8px] font-black px-1.5 py-0.5 rounded-full bg-amber-500 text-white align-middle ml-1">已清缓存</span>':'')};
function brCovOvl(b){const e=b&&b.epub;if(!b||!b.local||!e)return '';
  if(e.st==='pre')return '<div class="br-covovl pre"><div class="br-prebar"><i data-brpre="'+b.id+'" style="width:'+Math.round((e.pr||0)*0.9)+'%"></i></div><span class="br-prepct" data-brpct="'+b.id+'">预载中 '+(e.pr||0)+'%</span></div>';
  if(e.st==='cl')return '<div class="br-covovl cl"><span class="br-clchip"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 16V6"/><path d="m8 10 4-4 4 4"/><path d="M5 19h14"/></svg>已清缓存 · 点按重新载入</span></div>';
  return ''}
/* 封面墙 / 横向轨道：在封面节点内注入预载与已清缓存覆盖层（其余视图不展示本地态） */
const BR35_OLD_SHWALL=shWall, BR35_OLD_SHRAIL=shWallRail;
shWall=function(list,cols){return '<div class="bk-grid '+(cols===4||cols===5?'c'+cols:'')+'">'+list.map(b=>'<div class="relative" onclick="'+(shBatch?'shSelTap(\''+b.id+'\')':'shOpen(\''+b.id+'\')')+'" oncontextmenu="event.preventDefault();shLongMenu(\''+b.id+'\');return false">'+
  '<div class="bk-cov cov '+bsCovCls(b)+' w-full" style="'+bsCovStyle(b)+'">'+bsProgressBadge(b)+(b.local?brCovBadge(b):'')+brCovOvl(b)+'<div class="au">'+b.a+'</div>'+(shBatch?'<span class="bsel '+(shSel.has(b.id)?'on':'')+'">'+(shSel.has(b.id)?'<svg class="w-[11px] h-[11px] inline" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="m5 13 4.5 4.5L19 7"/></svg>':'')+'</span>':'')+'</div>'+
  '<div class="nm">'+b.n+'</div>'+BR35_SHBAR(b)+'</div>').join('')+'</div>'};
const BR35_SHBAR=b=>{const w=b.st==='想读'?0:b.p,cls=b.st==='已读'?'full':b.st==='想读'?'zero':b.st==='弃读'?'give':'';
  const lab=b.st==='已读'?'读完':b.st==='想读'?'未开始':b.st==='弃读'?b.p+'%':b.p+'%';
  return '<div class="bk-pbar has-pct"><i class="'+cls+'" style="width:'+w+'%;'+(b.st==='弃读'?'background:#94a3b8':'')+'"></i><span class="bk-pct" style="color:'+(w>=62?'#fff':'var(--text2,#64748b)')+'">'+lab+'</span></div>'};
shWallRail=function(list){return '<div class="bk-rail no-scrollbar">'+list.map(b=>'<div class="relative" onclick="'+(shBatch?'shSelTap(\''+b.id+'\')':'shOpen(\''+b.id+'\')')+'" oncontextmenu="event.preventDefault();shLongMenu(\''+b.id+'\');return false">'+
  '<div class="bk-cov cov '+bsCovCls(b)+' w-full !h-[159px]" style="'+bsCovStyle(b)+'">'+bsProgressBadge(b)+(b.local?brCovBadge(b):'')+brCovOvl(b)+'<div class="au">'+b.a+'</div>'+(shBatch?'<span class="bsel '+(shSel.has(b.id)?'on':'')+'"></span>':'')+'</div>'+
  '<div class="text-[10px] font-extrabold leading-tight mt-1.5 truncate">'+b.n+'</div>'+shRailBar(b)+'</div>').join('')+'</div>'};
/* 预载模拟：整本解析+分页计算（实算在 Flutter 侧后台 isolate，此处只演示进度与守卫） */
const brPre={timers:{},
 stop(id){const t=brPre.timers[id];if(t){clearInterval(t);delete brPre.timers[id]}},
 start(id,from){brPre.stop(id);const b=bsBook(id);if(!b||!b.epub)return;b.epub.pr=Math.max(2,from||2);b.epub.st='pre';brPre.sync(id);
  brPre.timers[id]=setInterval(()=>{const x=bsBook(id);if(!x||!x.epub||x.epub.st!=='pre'){brPre.stop(id);return}
    x.epub.pr=Math.min(100,x.epub.pr+9);brPre.sync(id);
    if(x.epub.pr>=100){brPre.stop(id);x.epub.st='rdy';
      if(curPage==='p-bookshelf'||curPage==='p-readhub'){renderShelf();try{renderRecHub()}catch(e){}try{renderBookDetail()}catch(e){}}
      toast('《'+x.n+'》已预载完成 · 点封面秒进')}},420)},
 sync(id){const b=bsBook(id);if(!b||!b.epub)return;const pct=Math.round((b.epub.pr||0)*0.9);
  document.querySelectorAll('[data-brpre="'+id+'"]').forEach(el=>{el.style.width=pct+'%'});
  document.querySelectorAll('[data-brpct="'+id+'"]').forEach(el=>{el.textContent='预载中 '+(b.epub.pr||0)+'%'})}};
function brPreStart(id,from){brPre.start(id,from)}
function brPreStop(id){brPre.stop(id)}
/* 入口守卫：预载中不可点进阅读；已清缓存点封面→按源文件状态分流 */
const BR35_OLD_SHOPEN=shOpen;
shOpen=function(id){const b=bsBook(id);if(b&&b.local&&b.epub){
  if(b.epub.st==='pre'){toast('正在预载整本书 · 完成后可进入');return}
  if(b.epub.st==='cl'){brSrcTap(id);return}}
  BR35_OLD_SHOPEN(id)};
function brLpRead(id){const b=bsBook(id);closeSheet('sheetLongPress');if(!b||!b.epub)return;
  if(b.epub.st==='pre')return toast('正在预载整本书 · 完成后可进入');
  if(b.epub.st==='cl')return brSrcTap(id);
  brOpen(id)}
function brSrcTap(id){const b=bsBook(id);if(!b||!b.epub)return;
  if(b.epub.srcOk)brReloadOpen(id);else brLostOpen(id)}
/* 清理缓存（保留记录 · 原文件不删） */
let brCacheId='';
function brCacheOpen(id){const b=bsBook(id);if(!b||!b.epub)return;brCacheId=id;
  document.getElementById('brCacheName').textContent=b.n;
  document.getElementById('brCacheSize').textContent=b.epub.cache||b.epub.size||'—';
  document.getElementById('brCacheInfo').innerHTML='当前本地副本与分页缓存约 <b>'+(b.epub.cache||b.epub.size||'—')+'</b><div class="mt-0.5 text-slate-400 break-all">'+brEsc(b.epub.path)+' · 源文件保留原位</div>';
  openSheet('sheetBrCache')}
function brCacheCommit(){const b=bsBook(brCacheId);if(!b||!b.epub)return closeSheet('sheetBrCache');
  brPreStop(b.id);b.epub.st='cl';b.epub.pr=0;
  if(b.epub.lostAt)b.epub.srcOk=0;
  closeSheet('sheetBrCache');renderShelf();try{renderRecHub()}catch(e){}try{renderBookDetail()}catch(e){}brPersist();
  toast('已释放约 '+(b.epub.cache||'—')+' · 记录与书摘保留 · 源文件未删除')}
/* 重新载入：原文件可读 → 提示后重新拷贝 + 预载 */
let brReloadId='';
function brReloadOpen(id){const b=bsBook(id);if(!b||!b.epub)return;brReloadId=id;
  document.getElementById('brReloadName').textContent=b.n;
  document.getElementById('brReloadInfo').innerHTML='源文件仍可读：<div class="mt-0.5 break-all text-slate-400">'+brEsc(b.epub.path)+'</div><div class="mt-1">重新拷贝约 '+(b.epub.cache||b.epub.size||'—')+' 本地副本并预载分页 · 书摘与进度不动</div>';
  openSheet('sheetBrReload')}
function brReloadCommit(){const b=bsBook(brReloadId);if(!b||!b.epub)return closeSheet('sheetBrReload');
  closeSheet('sheetBrReload');b.epub.pr=4;renderShelf();brPreStart(b.id,4);
  toast('正在重新拷贝并预载《'+b.n+'》')}
/* 原文件丢失：引导重选文件 → 合并导入挂回原记录 */
let brLostId='';
function brLostOpen(id){const b=bsBook(id);if(!b||!b.epub)return;brLostId=id;
  document.getElementById('brLostName').textContent=b.n;
  document.getElementById('brLostInfo').innerHTML='原位置：<div class="mt-0.5 break-all text-slate-400">'+brEsc(b.epub.path)+(b.epub.lostAt?' · 于 '+b.epub.lostAt+' 探测失效':'')+'</div>';
  openSheet('sheetBrLost')}
function brLostGoImp(){closeSheet('sheetBrLost');navTo('p-localImport');brImpGo(2)}
function brNormFn(s){return String(s||'').replace(/[《》\s，,。.·．:：;；、()（）\-—_]/g,'').toLowerCase()}
function br35LostBook(fileName){
  const lost=BS_BOOKS.filter(b=>b.local&&b.epub&&b.epub.st==='cl'&&!b.epub.srcOk);
  if(fileName)return lost.find(b=>brNormFn(b.epub.name||(b.epub.path||'').split('/').pop())===brNormFn(fileName))||null;
  return lost[0]||null}
/* 详情本地卡：打开钮改走守卫入口 + 追加「本地副本与缓存」行（四态） */
const BR35_OLD_RBD=renderBookDetail;
renderBookDetail=function(){BR35_OLD_RBD();try{
  const ob=document.querySelector('#brDcard button[onclick^="brOpen("]');if(ob)ob.setAttribute('onclick',ob.getAttribute('onclick').replace('brOpen(','shOpen('));
  const b=bsBook(CURBK);if(!b||!b.local||!b.epub)return;
  const card=document.getElementById('brDcard');if(!card||document.getElementById('brDcache'))return;
  card.insertAdjacentHTML('beforeend',brDcacheRow(b))}catch(e){}};
function brDcacheRow(b){const e=b.epub;let inner='';
  if(e.st==='pre')inner='<div class="text-[10px] text-slate-400">整本预载中 · 解析与分页计算 · 完成前不可进入阅读</div><div class="br-prebar mt-1.5" style="width:100%;background:rgba(148,163,184,.35)"><i data-brpre="'+b.id+'" style="width:'+Math.round((e.pr||0)*0.9)+'%;background:#6366f1"></i></div>';
  else if(e.st==='cl'&&e.srcOk)inner='<div class="text-[10px] text-slate-400">本地副本已清理 · 重新载入约 '+(e.cache||e.size||'—')+' · 源文件仍可读 · 记录与书摘完整保留</div><button class="mt-1.5 py-2 px-3 rounded-xl grad text-white text-[11px] font-bold" onclick="brReloadOpen(\''+b.id+'\')">重新载入本地副本</button>';
  else if(e.st==='cl')inner='<div class="text-[10px] text-rose-500">本地副本已清理 · 原文件已不存在 · 记录与书摘完整保留</div><button class="mt-1.5 py-2 px-3 rounded-xl bg-amber-500 text-white text-[11px] font-bold" onclick="brLostOpen(\''+b.id+'\')">重新选择文件</button>';
  else inner='<div class="text-[10px] text-slate-400">本地副本 + 分页缓存约 <b>'+(e.cache||e.size||'—')+'</b> · 源文件在原始位置保留</div><button class="mt-1.5 py-2 px-3 rounded-xl border border-amber-300 dark:border-amber-500/40 text-amber-600 text-[11px] font-bold" onclick="brCacheOpen(\''+b.id+'\')">清理缓存 · 约释放 '+(e.cache||e.size||'—')+'</button>';
  return '<div id="brDcache" class="mt-2.5 rounded-xl border border-slate-100 dark:border-slate-800 br-dcache bg-slate-50/60 dark:bg-slate-800/40 p-2.5">'+inner+'</div>'}
/* 导入页：描述改口径 + 「重选挂回」提示条 */
(()=>{const dl=document.querySelector('#p-localImport .desc');if(dl)dl.textContent='EPUB · 导入后后台预载整本 · 源文件保留原位';
  const st=document.querySelector('#p-localImport #brSteps');if(st)st.insertAdjacentHTML('afterend','<div id="brAttachHint" class="hidden mt-2 rounded-xl bg-amber-50 dark:bg-amber-500/10 border border-amber-200 dark:border-amber-500/30 px-3 py-2 text-[10px] font-bold text-amber-700 dark:text-amber-400"></div>');})();
/* 演示种子与深链：
   ?br35=pre     b1 整本预载中（封面进度条实时跑 · 点封面被守卫）
   ?br35=frozen  b1 预载 64% 静态（截图用）
   ?br35=cl      b1 已清缓存·源文件可读（封面蒙层 + 点封面 → 重新载入弹层）
   ?br35=lost    b9 已清缓存·原文件丢失（点封面 → 引导重选 → 导入页选「万历十五年.epub」挂回）
   ?br35=detail  b1 详情页本地卡（已清可读态 + 缓存行） */
function br35Seed(){
  const b1=bsBook('b1');
  if(b1&&b1.local&&b1.epub&&!b1.epub.st){b1.epub.st='cl';b1.epub.pr=0;b1.epub.cache='8.4 MB';b1.epub.srcOk=1;b1.epub.name='思考快与慢.epub'}
  const b9=bsBook('b9');
  if(b9&&!b9.local){b9.local=1;b9.epub={fmt:'EPUB3',size:'6.8 MB',path:'内部存储/下载/万历十五年.epub',name:'万历十五年.epub',st:'cl',pr:0,cache:'6.8 MB',srcOk:0,lostAt:'09-26 18:42'};if(!b9.tags.includes('本地'))b9.tags.push('本地')}
  if(!BR_FILES.download.some(f=>f.n==='万历十五年.epub'))BR_FILES.download.push({n:'万历十五年.epub',sz:'6.8 MB',meta:{t:'万历十五年',a:'黄仁宇',press:'中华书局',pub:'2006-08',fmt:'EPUB2',cover:'linear-gradient(150deg,#78716c,#d6d3d1)',pages:276,intro:'1580 年在位万历皇帝的平庸年代里，张居正、海瑞、戚继光、李贽的困境与抉择。'}});
}
(function br35Boot(){
  try{
    if(!/br35=/.test(location.search))return;
    const k=(location.search.match(/br35=([a-z]+)/)||[])[1];
    if(k==='detail'){br35Seed();setPage('p-bookshelf');renderShelf();BR35_OLD_SHOPEN('b1');toast('演示：本地卡 · 已清缓存 · 源文件可读');return}
    if(k==='lost'){br35Seed();setPage('p-bookshelf');renderShelf();shOpen('b9');toast('演示：点封面 → 原文件丢失引导');return}
    const b=bsBook('b1');if(!b||!b.local)return;
    if(k==='pre'||k==='frozen'||k==='cl'){
      if(k==='cl'){br35Seed()}
      else{b.epub.name='思考快与慢.epub';b.epub.cache='8.4 MB';b.epub.srcOk=1;b.epub.st='pre';
        if(k==='pre'){b.epub.pr=4;brPreStart('b1',4)}else b.epub.pr=64}
      setPage('p-bookshelf');renderShelf();
      toast(k==='cl'?'演示：已清缓存 · 点封面重新载入':'演示：导入后后台整本预载 · 完成前封面不可点')}}
  catch(e){}
})();
/* ================= 阅读器（书架专版）结束 ================= */`);

/* ---- 写盘 + 体积校验 ---- */
if (H.length <= before) { console.error('SIZE SHRANK: ' + before + ' -> ' + H.length); process.exit(1); }
fs.writeFileSync(P, H, 'utf8');
console.log('DONE replacements=' + hits + '  size ' + before + ' -> ' + H.length);
