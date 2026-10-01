/* 批2 修③ · 选区 X-Ray 优先级重排（用户拍板 2026-10-02）：
 * 命中＝直达 X-Ray 面板定位该实体（迭代掉迷你卡中转）；
 * 未命中＝面板带入搜索+空态「加为词条」入口——不前置「屏蔽/添加」二选一。
 * 撤 sheetXrPeek / sheetXrMiss 两弹层与 xrMiss* 函数。规矩同前：快照+锚点唯一断言。 */
const fs = require('fs'), path = require('path');
const F = path.resolve('prototype/index-bookshelf.html');
fs.copyFileSync(F, path.resolve('tools/attic/index-bookshelf.bak-20261002-xrwords-fix3.html'));
let src = fs.readFileSync(F, 'utf8');
const size0 = src.length;
const crlf = (s) => s.replace(/\n/g, '\r\n');
const hits = [];
function rep(anchor, replacement, tag) {
  anchor = crlf(anchor); replacement = crlf(replacement);
  const n = src.split(anchor).length - 1;
  if (n !== 1) { console.error('锚点非唯一(' + n + '): ' + tag); process.exit(1); }
  src = src.replace(anchor, replacement);
  hits.push(tag);
}

/* P1 · xrSelTool 路由重排 */
rep(`    if(hit)xrPeekOpen(hit.name)
    else xrMissOpen(w)
  };`,
`    if(hit){brTocOpen('xr');xrPickEnt(hit.id);return}
    brTocOpen('xr');XR.kw=w;XR.cur=null;XR.mode='list';xrRender()
    /* 选区未命中＝面板带入搜索+空态加词入口（批2修③ 口径：屏蔽不前置，仍留在词条详情与管理页） */
  };`, 'P1 路由');

/* P2 · 空态：kw 命中时给「没有找到 + 加为词条」，并新增搜索横幅 */
rep(`    if(!hi.length&&!lo.length)h+='<div class="text-[10px] text-slate-400 py-6 text-center">该范围没有词条</div>';`,
`    if(!hi.length&&!lo.length){
      if(XR.kw.trim())h+='<div class="text-[10px] text-slate-400 py-3 text-center">没有找到「'+XR.kw.trim()+'」</div>'
        +'<div class="flex justify-center pb-2"><button class="grad text-white !text-[10px] font-bold px-3 py-1.5 rounded-lg" id="xrKwAdd" onclick="xrAddKw()">＋ 加为词条</button></div>';
      else h+='<div class="text-[10px] text-slate-400 py-6 text-center">该范围没有词条</div>';
    }`, 'P2 空态');

rep(`    h+='<div class="text-[9px] text-slate-400 text-center pb-2">'+XR_ENTS.length+' 个词条 · 出场锚点全量 · 上下文截断（每实体前 N 条）</div>';
    return h`,
`    h+='<div class="text-[9px] text-slate-400 text-center pb-2">'+XR_ENTS.length+' 个词条 · 出场锚点全量 · 上下文截断（每实体前 N 条）</div>';
    return (XR.kw.trim()?'<div class="flex items-center gap-2 px-1 pt-1 pb-1"><span class="text-[10px] text-slate-400">搜索「'+XR.kw.trim()+'」</span><span class="flex-1"></span><button class="chip !text-[9px] !px-2.5" id="xrKwClr" onclick="xrKwClear()">清除</button></div>':'')+h`, 'P2 搜索横幅');

/* P3 · xrPeekOpen/xrPeekToPanel 撤除 → xrKwClear/xrAddKw */
rep(`  window.xrPeekOpen=function(word){
    var x=XR_ENTS.find(function(v){return v.name===word});
    if(!x){xrAddOpen(word);return}
    var h='<div class="flex items-center gap-2 flex-wrap"><b class="text-[15px]">'+x.name+'</b><span class="xr-tbadge '+(x.usr?'user':x.type)+'">'+(x.usr?'我的词条':XR_TL[x.type])+'</span>'+(x.toc?'<span class="xr-tbadge toc">目录词</span>':'')+'</div>';
    h+='<div class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5">'+x.n+' 次提及 · 跨 '+x.chs+' 章 · 置信 '+x.score.toFixed(2)+(x.dlg!=null?' · 台词 '+x.dlg+' 段':'')+'</div>';
    if(x.q)h+='<div class="mt-2 text-[10px] text-slate-500 dark:text-slate-400">'+x.q+'</div>';
    h+='<div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet(\\'sheetXrPeek\\')">关闭</button><button class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="xrPeekToPanel(\\''+x.name+'\\')">查看全部位置</button></div>';
    document.getElementById('xrPeekBody').innerHTML=h;
    openSheet('sheetXrPeek')
  };
  window.xrPeekToPanel=function(name){closeSheet('sheetXrPeek');var x=XR_ENTS.find(function(v){return v.name===name});if(x)xrPickEnt(x.id);else brTocOpen('xr')};`,
`  window.xrKwClear=function(){XR.kw='';XR.mode='list';xrRender()};
  window.xrAddKw=function(){xrAddOpen(XR.kw.trim())};`, 'P3 peek撤除');

/* P4 · sheetXrPeek DOM 撤除 */
rep(`  <div id="sheetXrPeek" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrPeek')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">X-Ray</b><span class="text-[9px] text-slate-400">选区命中</span></div>
      <div id="xrPeekBody" class="mt-2"></div>
    </div>
  </div>
`, '', 'P4 peek DOM');

/* P5 · xrMiss* 函数撤除 */
rep(`  var xrMissW='';
  window.xrMissOpen=function(w){xrMissW=w||'';
    document.getElementById('xrMissWord').textContent=xrMissW;openSheet('sheetXrMiss')};
  window.xrMissAdd=function(){closeSheet('sheetXrMiss');xrAddOpen(xrMissW)};
  window.xrMissBan=function(){XR_BLOCKED[xrMissW]=1;closeSheet('sheetXrMiss');
    try{xrRender()}catch(e){}
    toast('已屏蔽「'+xrMissW+'」· 关养词库开关可恢复')};
`, '', 'P5 miss函数');

/* P6 · sheetXrMiss DOM 撤除 */
rep(`  <div id="sheetXrMiss" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetXrMiss')">
    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">
      <div class="flex items-center justify-between"><b class="text-[15px]">未命中全书索引</b><span class="text-[9px] text-slate-400">选区 · X-Ray</span></div>
      <div class="mt-2.5 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] flex items-center gap-2"><span class="text-slate-400">选中文本</span><b class="ml-auto" id="xrMissWord">—</b></div>
      <div class="mt-2 text-[10px] text-slate-400">把它养进词库（加为词条并全书补扫），或拉黑（养词库生效期间不再显示）。</div>
      <div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet('sheetXrMiss')">取消</button><button class="flex-1 py-2.5 rounded-xl bg-rose-500 text-white text-xs font-bold" id="xrMissBan" onclick="xrMissBan()">改为屏蔽</button><button class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" id="xrMissAdd" onclick="xrMissAdd()">加为词条</button></div>
    </div>
  </div>
`, '', 'P6 miss DOM');

/* P7 · 深链分支改形 */
rep(`      if(!els.length){xrPeekOpen('系统1');return}`,
`      if(!els.length){brTocOpen('xr');xrPickEnt('e_s1');return}`, 'P7a boot兜底');
rep(`        if(m==='peek')xrSelTool();else xrAddOpen('巧克力');
        var pk=document.getElementById('sheetXrPeek');
        if(m==='peek'&&pk.classList.contains('hidden'))xrPeekOpen('系统1');`,
`        if(m==='peek')xrSelTool();else xrAddOpen('巧克力');`, 'P7b boot兜底');
rep(`        if(m==='peek')xrPeekOpen('系统1');else xrAddOpen('巧克力')`,
`        if(m==='peek'){brTocOpen('xr');xrPickEnt('e_s1')}else xrAddOpen('巧克力')`, 'P7c boot兜底');
rep(`    if(m==='miss'){brOpen('b1');brShowChrome();xrMissOpen('麦田里的守望者');return}`,
`    if(m==='miss'){brOpen('b1');brShowChrome();xrBootCh();brTocOpen('xr');XR.kw='麦田里的守望者';XR.cur=null;XR.mode='list';xrRender();return}`, 'P7d miss深链');

fs.writeFileSync(F, src);
const size1 = src.length;
console.log('OK 七组落齐: ' + hits.join(', '));
console.log('体积 ' + size0 + ' -> ' + size1 + ' (' + (size1 - size0) + ')');
