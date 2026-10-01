/* V1.54.1 批2 原型补丁 · index-bookshelf.html 九处（词库管理页/开关/未命中二选一/入口行/深链）
 * 规矩：先快照 → 每个锚点全文唯一才落 → 体积校验 → 报告。已执行勿重复跑。
 */
const fs = require('fs'), path = require('path');
const F = path.resolve('prototype/index-bookshelf.html');
const SNAP = path.resolve('tools/attic/index-bookshelf.bak-20261002-xrwords.html');
let src = fs.readFileSync(F, 'utf8');
const size0 = src.length;
const hits = [];
/* 目标文件为 CRLF：锚点与插入块统一 \n→\r\n 归一后再比对/落盘 */
const crlf = (s) => s.replace(/\n/g, '\r\n');
function rep(anchor, replacement, tag) {
  anchor = crlf(anchor); replacement = crlf(replacement);
  const n = src.split(anchor).length - 1;
  if (n !== 1) { console.error('锚点非唯一(' + n + '): ' + tag); process.exit(1); }
  src = src.replace(anchor, replacement);
  hits.push(tag);
}

/* A1 · 管理页 DOM（插在 P-B5 书单列表前） */
rep('    <!-- ===== 书架生态 · P-B5 书单列表 ===== -->',
`    <!-- ===== 阅读器 · P-XR 词库管理（V1.54.1 批2 · GLOBAL 养成词库 CRUD + 启用开关） ===== -->
    <section id="p-xrwords" class="page px-5 safe-pb no-scrollbar">
      <div class="mt-3 card !py-3 flex items-center gap-2.5">
        <span class="w-9 h-9 rounded-xl bg-brand-50 dark:bg-brand-500/15 flex items-center justify-center text-brand-500"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="6"/><path d="m20 20-3.5-3.5"/></svg></span>
        <div class="flex-1 min-w-0"><div class="text-[13px] font-extrabold">X-Ray 词库管理</div><div class="text-[10px] text-slate-400 mt-0.5" id="xrwSum"></div></div>
        <button class="mini-btn !text-[10px]" onclick="navTo('p-bookshelf')">回书架</button>
      </div>
      <div class="mt-2 card !py-3 flex items-center gap-2.5">
        <div class="flex-1 min-w-0"><b class="text-[12.5px]">启用养成词库</b><div class="text-[10px] text-slate-400 mt-0.5">关＝纯预置视角：隐藏我的词条并恢复被屏蔽词 · 已整理状态不回滚，重开即恢复</div></div>
        <span class="toggle on" id="xrwToggle" onclick="xrWordsToggle()"><i></i></span>
      </div>
      <div class="mt-2 flex gap-1.5 flex-wrap" id="xrwTypeChips"></div>
      <div class="mt-3 flex gap-2"><input id="xrwAddInp" class="inp flex-1" placeholder="新增养入词…" onkeydown="if(event.key==='Enter')xrWordsAdd()"><button class="mini-btn self-stretch flex items-center px-4" onclick="xrWordsAdd()">添加</button></div>
      <div id="xrwList" class="mt-3"></div>
    </section>

    <!-- ===== 书架生态 · P-B5 书单列表 ===== -->`, 'A1 管理页DOM');

/* A2 · 未命中二选一弹层（插在 sheetXrMerge 前） */
rep('  <div id="sheetXrMerge" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet(\'sheetXrMerge\')">',
`  <div id="sheetXrMiss" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrMiss')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">未命中全书索引</b><span class="text-[9px] text-slate-400">选区 · X-Ray</span></div>
      <div class="mt-2.5 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] flex items-center gap-2"><span class="text-slate-400">选中文本</span><b class="ml-auto" id="xrMissWord">—</b></div>
      <div class="mt-2 text-[10px] text-slate-400">把它养进词库（加为词条并全书补扫），或拉黑（养词库生效期间不再显示）。</div>
      <div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet('sheetXrMiss')">取消</button><button class="flex-1 py-2.5 rounded-xl bg-rose-500 text-white text-xs font-bold" id="xrMissBan" onclick="xrMissBan()">改为屏蔽</button><button class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" id="xrMissAdd" onclick="xrMissAdd()">加为词条</button></div>
    </div>
  </div>
  <div id="sheetXrMerge" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrMerge')">`, 'A2 未命中弹层');

/* A3 · 面板头 r2 养词库开关 chip */
rep(`+'<span class="chip !text-[9px] !px-2.5'+(XR.org?' chip-on':'')+'" id="xrOrgBtn" onclick="xrToggleOrg()">整理词条</span></div>';`,
`+'<span class="chip !text-[9px] !px-2.5'+(XR.org?' chip-on':'')+'" id="xrOrgBtn" onclick="xrToggleOrg()">整理词条</span>'
      +'<span class="chip !text-[9px] !px-2.5'+(xrUserDictOn()?' chip-on':'')+'" id="xrUserDictBtn" onclick="xrUserDictFlip()">养词库 '+(xrUserDictOn()?'开':'关')+'</span></div>';`, 'A3 面板头开关');

/* A4 · 选区未命中改走二选一 */
rep(`    if(hit)xrPeekOpen(hit.name)
    else xrAddOpen(w)`,
`    if(hit)xrPeekOpen(hit.name)
    else xrMissOpen(w)`, 'A4 选区未命中路由');

/* A5 · ⋯菜单词库管理行（插在 X-Ray 行后） */
rep(`        <div class="flex items-center justify-between py-1 cursor-pointer" onclick="closeSheet('sheetBrMore');xrEntry()"><span>全书索引（X-Ray）</span><b class="text-[10px] text-slate-400" id="brMoreXr">已索引 12/18 章 · 随阅读推进</b></div>`,
`        <div class="flex items-center justify-between py-1 cursor-pointer" onclick="closeSheet('sheetBrMore');xrEntry()"><span>全书索引（X-Ray）</span><b class="text-[10px] text-slate-400" id="brMoreXr">已索引 12/18 章 · 随阅读推进</b></div>
        <div class="flex items-center justify-between py-1 cursor-pointer" onclick="closeSheet('sheetBrMore');xrWordsOpen()"><span>X-Ray 词库管理</span><b class="text-[10px] text-slate-400" id="brMoreXrw">养词库 开</b></div>`, 'A5 菜单行');

/* A6 · 阅读设置「本地阅读器」入口行 */
rep(`['epub','导入本地 EPUB','nav',"navTo('p-localImport');brImpGo(1)",'添加图书流程内同样有入口 · Android 13+ SAF 单次读取'],`,
`['epub','导入本地 EPUB','nav',"navTo('p-localImport');brImpGo(1)",'添加图书流程内同样有入口 · Android 13+ SAF 单次读取'],['xrwords','X-Ray 词库管理','nav',"navTo('p-xrwords');renderXrWords()",'GLOBAL 养成词库 · 增删改查 · 启用开关（关＝纯预置视角） · 导入导出随批3'],`, 'A6 设置入口');

/* A7 · 管理面 JS（插在 xrAddPick 前） */
rep(`  var xrAddPick={word:'',type:'term',scope:'book'};`,
`  /* V1.54.1 批2 · GLOBAL 养成词库管理 + 启用开关 + 选区未命中二选一 */
  window.xrUserDictOn=function(){return BS_SET.xrUserDict!==false};
  window.xrUserDictFlip=function(){BS_SET.xrUserDict=!xrUserDictOn();xrRender();
    toast(xrUserDictOn()?'养词库已开启 · 我的词条与屏蔽恢复生效':'已切纯预置视角 · 已整理状态不回滚，重开即恢复')};
  var XR_WORDS=[
    {w:'认知负担',type:'term',act:'add',src:'《模型思维》',ts:Date.now()-86400000*2},
    {w:'普通国家',type:'term',act:'add',src:'人类简史',ts:Date.now()-86400000*5},
    {w:'麦田里的守望者',type:'book',act:'forbid',src:'雾都小书',ts:Date.now()-86400000*9}];
  var XR_BLOCKED={};
  var xrwType='all',xrwQ='';
  window.xrWordsOpen=function(){TITLES['p-xrwords']=['X-Ray 词库管理','GLOBAL 养成词库 · 随批3 可导入导出'];navTo('p-xrwords');renderXrWords()};
  window.xrwSetType=function(t){xrwType=t;renderXrWords()};
  window.xrwSetQ=function(v){xrwQ=(v||'').trim().toLowerCase();renderXrWords()};
  window.xrWordsToggle=function(){xrUserDictFlip();renderXrWords();
    var b=document.getElementById('brMoreXrw');if(b)b.textContent='养词库 '+(xrUserDictOn()?'开':'关')};
  function xrwTypeBadge(t){return (XR_TYPES.find(function(x){return x[0]===t})||['','词'])[1]}
  window.renderXrWords=function(){
    var tg=document.getElementById('xrwToggle');if(!tg)return;
    var on=xrUserDictOn();
    tg.className='toggle'+(on?' on':'');
    var mb=document.getElementById('brMoreXrw');if(mb)mb.textContent='养词库 '+(on?'开':'关');
    document.getElementById('xrwTypeChips').innerHTML=[['all','全部']].concat(XR_TYPES).map(function(t){
      var n=t[0]==='all'?XR_WORDS.length:XR_WORDS.filter(function(r){return r.type===t[0]}).length;
      return '<button class="chip !text-[10px]'+(xrwType===t[0]?' chip-on':'')+'" id="xrw-tp-'+t[0]+'" onclick="xrwSetType(\\''+t[0]+'\\')">'+t[1]+' · '+n+'</button>'}).join('');
    document.getElementById('xrwSum').textContent=XR_WORDS.length+' 个养成词 · '+(on?'养词库生效中':'纯预置视角（开关已关）');
    document.getElementById('xrwList').innerHTML=XR_WORDS.filter(function(r){return (xrwType==='all'||r.type===xrwType)&&(!xrwQ||r.w.toLowerCase().indexOf(xrwQ)>=0)}).map(function(r){
      return '<div class="shelf-row !px-3" data-w="'+r.w+'"><div class="flex-1 min-w-0"><b class="text-[13px] block truncate">'+r.w+'</b>'
        +'<span class="text-[10px] text-slate-400">'+xrwTypeBadge(r.type)+' · '+(r.act==='add'?'加词':'屏蔽')+' · 来源 '+r.src+' · '+new Date(r.ts).toISOString().slice(5,10)+'</span></div>'
        +'<button class="mini-btn !text-[10px]" onclick="xrwRename(\\''+r.w+'\\')">改名</button>'
        +'<button class="mini-btn !text-[10px]" onclick="xrwFlip(\\''+r.w+'\\')">'+(r.act==='add'?'改屏蔽':'改加词')+'</button>'
        +'<button class="mini-btn !text-[10px] !bg-peach/15 !text-rose-500" onclick="xrwDel(\\''+r.w+'\\')">删除</button></div>'
    }).join('')||'<div class="card text-[11px] text-slate-400 text-center py-6">该类型还没有养成词，先在上方添加</div>';
  };
  window.xrWordsAdd=function(){var i=document.getElementById('xrwAddInp');var w=(i&&i.value||'').trim();if(!w){toast('先输入词');return}
    if(XR_WORDS.some(function(r){return r.w===w})){toast('该词已在词库');return}
    XR_WORDS.unshift({w:w,type:xrGuessType(w),act:'add',src:'手动养入',ts:Date.now()});
    if(i)i.value='';xrwType='all';xrwQ='';renderXrWords();toast('已养入「'+w+'」· 重解析与补扫时生效')};
  window.xrwRename=function(w){var nn=prompt('改成：',w);if(nn==null)return;nn=nn.trim();if(!nn||nn===w)return;
    XR_WORDS.forEach(function(r){if(r.w===w)r.w=nn});renderXrWords();toast('已改名「'+nn+'」')};
  window.xrwFlip=function(w){XR_WORDS.forEach(function(r){if(r.w===w)r.act=r.act==='add'?'forbid':'add'});
    renderXrWords();toast('已更新动作')};
  window.xrwDel=function(w){XR_WORDS=XR_WORDS.filter(function(r){return r.w!==w});delete XR_BLOCKED[w];
    renderXrWords();toast('已删除「'+w+'」')};
  var xrMissW='';
  window.xrMissOpen=function(w){xrMissW=w||'';
    document.getElementById('xrMissWord').textContent=xrMissW;openSheet('sheetXrMiss')};
  window.xrMissAdd=function(){closeSheet('sheetXrMiss');xrAddOpen(xrMissW)};
  window.xrMissBan=function(){XR_BLOCKED[xrMissW]=1;closeSheet('sheetXrMiss');
    try{xrRender()}catch(e){}
    toast('已屏蔽「'+xrMissW+'」· 关养词库开关可恢复')};
  var xrAddPick={word:'',type:'term',scope:'book'};`, 'A7 管理面JS');

/* A8 · 列表过滤：关开关隐 usr、屏蔽词隐（开开关时） */
rep(`    var pool=xrByType(xrScoped(),XR.type);
    if(XR.kw.trim())pool=pool.filter(function(x){return x.name.indexOf(XR.kw.trim())>=0});`,
`    var pool=xrByType(xrScoped(),XR.type);
    if(XR.kw.trim())pool=pool.filter(function(x){return x.name.indexOf(XR.kw.trim())>=0});
    var ud=xrUserDictOn();
    pool=pool.filter(function(x){return (ud||!x.usr)&&!XR_BLOCKED[x.name]});`, 'A8 列表过滤');

/* A9 · 深链 dict / miss（插在 fail 前） */
rep(`    if(m==='fail'){xrSeed();brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');openSheet('sheetXrFail');return}`,
`    if(m==='dict'){navTo('p-xrwords');renderXrWords();return}
    if(m==='miss'){brOpen('b1');brShowChrome();xrMissOpen('麦田里的守望者');return}
    if(m==='fail'){xrSeed();brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');openSheet('sheetXrFail');return}`, 'A9 深链');

fs.writeFileSync(SNAP, fs.readFileSync(F, 'utf8'));
fs.writeFileSync(F, src);
const size1 = src.length;
if (size1 <= size0) { console.error('体积未增长，异常'); process.exit(1); }
console.log('OK 九处落齐: ' + hits.join(', '));
console.log('体积 ' + size0 + ' -> ' + size1 + ' (+' + (size1 - size0) + ')，快照 ' + SNAP);
