/* V1.53.2 轮5.3 · 书籍详情页：本地 EPUB 信息块上移压缩（命中断言 + 体积护栏）
   ① 原页面底部的「本地 EPUB · 可直接阅读」整卡删除
   ② 改为统计行下方一条两行紧凑条：徽标+大小+DRM+图文 / 进度+位置+划线，
      右侧「打开阅读器」主钮 + 全书检索、删除两个图标钮
   ③ 描述性文字（删除口径、副本与缓存说明）收进「?」图标，点开底部弹层看
   用：node tools/reader/bs58patch.js */
const fs = require('fs');
const F = 'prototype/index-bookshelf.html';
let src = fs.readFileSync(F, 'utf8');
const origLen = src.length;
let hits = 0;
function rep(name, find, replace) {
  const n = src.split(find).length - 1;
  if (n !== 1) { console.error('MISS[' + name + '] 命中 ' + n + ' 次（期望 1）'); process.exit(1); }
  src = src.split(find).join(replace); hits++;
}

/* 1 · 详情页底部整卡 → 插到统计行与 tabs 之间的紧凑条 */
rep('strip',
  "  root.insertAdjacentHTML('beforeend',`<div id=\"brDcard\" class=\"mt-3 card\">\n" +
  "    <div class=\"flex items-center justify-between\"><div class=\"row-title text-xs font-extrabold\">本地 EPUB · 可直接阅读</div><span class=\"text-[9px] rounded-full px-1.5 py-0.5 bg-slate-100 dark:bg-slate-800 text-slate-400\">${b.epub?b.epub.fmt:'EPUB'}</span></div>\n" +
  "    <div class=\"mt-1.5 text-[10px] text-slate-400 leading-5 break-all\">${b.epub?brEsc(b.epub.path)+' · '+b.epub.size:'—'} · 无 DRM · 图文混排</div>\n" +
  "    <div class=\"mt-1.5 text-[10px] text-slate-400\">阅读位置 ${brPos[b.id]?brCfi(b.id,Math.min(brPos[b.id].ci,Math.max(0,brLeaves(b.id).length-1)),brPos[b.id].pg):'未开始'} · 划线 ${brHlCount(b.id)} 处 · 进度 ${brStPct(b.id)}%</div>\n" +
  "    <div class=\"mt-2.5 flex gap-2\"><button class=\"flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold\" onclick=\"brOpen('${b.id}')\">打开阅读器</button>\n" +
  "    <button class=\"py-2.5 px-3 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold\" onclick=\"navTo('p-readerSearch');brV.b='${b.id}'\">全书检索</button>\n" +
  "    <button class=\"py-2.5 px-3 rounded-xl border border-rose-200 dark:border-rose-500/30 text-rose-500 text-xs font-bold\" onclick=\"brDelOpen('${b.id}')\">删除…</button></div>\n" +
  "    <div class=\"mt-1.5 text-[9px] text-slate-400\">删除可选「仅清除阅读数据 · 保留源文件」或连源文件一并移除</div></div>`)}catch(e){}};",

  "  const tabs=document.getElementById('btToc');const host=tabs&&tabs.parentElement;\n" +
  "  if(!host||document.getElementById('brDstrip'))return;\n" +
  "  const fmt=(b.epub&&b.epub.fmt)||'EPUB', size=(b.epub&&b.epub.size)||'—';\n" +
  "  const pos=brPos[b.id]?brCfi(b.id,Math.min(brPos[b.id].ci,Math.max(0,brLeaves(b.id).length-1)),brPos[b.id].pg):'未开始';\n" +
  "  host.insertAdjacentHTML('beforebegin',\n" +
  "    `<div id=\"brDstrip\" class=\"mt-2.5 rounded-2xl border border-slate-200/70 dark:border-slate-700 px-3 py-2\">\n" +
  "      <div class=\"flex items-center gap-2\">\n" +
  "        <span class=\"shrink-0 text-[8.5px] rounded-md px-1.5 py-0.5 bg-slate-100 dark:bg-slate-800 text-slate-500 font-bold\">${fmt}</span>\n" +
  "        <span class=\"flex-1 min-w-0 truncate text-[10.5px] text-slate-500 dark:text-slate-400\">${size} · 无 DRM · 图文混排</span>\n" +
  "        <button class=\"shrink-0 w-5 h-5 rounded-full border border-slate-300 dark:border-slate-600 text-[10px] font-black text-slate-500 leading-none\" title=\"本地文件与缓存说明\" onclick=\"brLocalInfoOpen('${b.id}')\">?</button>\n" +
  "      </div>\n" +
  "      <div class=\"mt-1.5 flex items-center gap-1.5\">\n" +
  "        <span class=\"flex-1 min-w-0 truncate text-[10px] text-slate-400\">进度 ${brStPct(b.id)}% · 位置 ${pos} · 划线 ${brHlCount(b.id)} 处</span>\n" +
  "        <button class=\"shrink-0 py-1.5 px-3 rounded-xl grad text-white text-[10.5px] font-bold\" onclick=\"brOpen('${b.id}')\">打开阅读器</button>\n" +
  "        <button class=\"shrink-0 w-7 h-7 rounded-xl border border-slate-200 dark:border-slate-700 flex items-center justify-center\" title=\"全书检索\" onclick=\"navTo('p-readerSearch');brV.b='${b.id}'\"><svg width=\"13\" height=\"13\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"><circle cx=\"11\" cy=\"11\" r=\"7\"/><path d=\"m20 20-3.2-3.2\"/></svg></button>\n" +
  "        <button class=\"shrink-0 w-7 h-7 rounded-xl border border-rose-200 dark:border-rose-500/30 text-rose-500 flex items-center justify-center\" title=\"删除本地书\" onclick=\"brDelOpen('${b.id}')\"><svg width=\"13\" height=\"13\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"><path d=\"M5 7h14M9 7V5h6v2m-8 0 1 13h8l1-13\"/></svg></button>\n" +
  "      </div>\n" +
  "    </div>`)}catch(e){}};");

/* 2 · 「?」说明弹层（路径 / 删除口径 / 副本与缓存 + 清理入口） */
rep('info-sheet',
  '  <!-- AI 解读 -->',
  '  <!-- 轮5.3 · 本地文件与缓存说明（详情页「?」入口） -->\n' +
  '  <div id="sheetBrLocalInfo" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet(\'sheetBrLocalInfo\')">\n' +
  '    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">\n' +
  '      <div class="flex items-center justify-between"><b class="text-[15px]">本地文件与缓存</b><span class="text-[9px] text-slate-400" id="brLiFmt">EPUB</span></div>\n' +
  '      <div class="mt-3 space-y-2.5 text-[11.5px] leading-5">\n' +
  '        <div><div class="text-[9.5px] text-slate-400 mb-0.5">文件路径</div><div class="break-all rounded-xl bg-slate-50 dark:bg-slate-800/60 px-2.5 py-2 text-[10.5px]" id="brLiPath">—</div></div>\n' +
  '        <div class="flex items-center justify-between"><span class="text-slate-400">体积 / 加密 / 版式</span><b id="brLiMeta">—</b></div>\n' +
  '        <div class="flex items-center justify-between"><span class="text-slate-400">阅读位置 / 划线 / 进度</span><b id="brLiPos">—</b></div>\n' +
  '        <div class="pt-1 border-t border-slate-100 dark:border-slate-800 text-[10.5px] text-slate-500 leading-5">删除时分两种口径：仅清除阅读数据（保留源文件），或连源文件一并移除；书籍记录、书摘与计时始终保留。</div>\n' +
  '        <div id="brLiCache" class="text-[10.5px] text-slate-500 leading-5"></div>\n' +
  '      </div>\n' +
  '      <div class="mt-4 flex gap-2">\n' +
  '        <button class="flex-1 py-3 rounded-2xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet(\'sheetBrLocalInfo\')">知道了</button>\n' +
  '        <button id="brLiClean" class="flex-1 py-3 rounded-2xl border border-amber-300 dark:border-amber-500/40 text-amber-600 text-xs font-bold" onclick="closeSheet(\'sheetBrLocalInfo\');brCacheOpen(CURBK)">清理缓存</button>\n' +
  '      </div>\n' +
  '    </div>\n' +
  '  </div>\n\n' +
  '  <!-- AI 解读 -->');

/* 3 · 弹层数据填充 */
rep('info-js',
  '/* 设置页联动：brBright 与阅读器常亮同步 */',
  'function brLocalInfoOpen(id){const b=bsBook(id||CURBK);if(!b)return;\n' +
  "  const e=b.epub||{};const set=(k,v)=>{const el=document.getElementById(k);if(el)el.textContent=v};\n" +
  "  set('brLiFmt',e.fmt||'EPUB');set('brLiPath',e.path||'—');\n" +
  "  set('brLiMeta',(e.size||'—')+' · 无 DRM · 图文混排');\n" +
  "  set('brLiPos',(brPos[b.id]?brCfi(b.id,Math.min(brPos[b.id].ci,Math.max(0,brLeaves(b.id).length-1)),brPos[b.id].pg):'未开始')+' · 划线 '+brHlCount(b.id)+' 处 · 进度 '+brStPct(b.id)+'%');\n" +
  "  const cache=document.getElementById('brLiCache'),clean=document.getElementById('brLiCache')&&document.getElementById('brLiClean');\n" +
  "  if(cache)cache.innerHTML='本地副本 + 分页缓存约 <b>'+(e.cache||e.size||'—')+'</b> · 源文件在原始位置保留';\n" +
  "  if(clean)clean.classList.toggle('hidden',!(e.cache||e.size));\n" +
  "  openSheet('sheetBrLocalInfo')}\n" +
  '/* 设置页联动：brBright 与阅读器常亮同步 */');

fs.writeFileSync(F, src);
console.log('hits=' + hits + ' size ' + origLen + ' → ' + src.length);
if (src.length < origLen * 0.9) { console.error('体积异常缩小，疑似覆盖'); process.exit(1); }
