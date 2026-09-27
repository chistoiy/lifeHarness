/* V1.52 第四轮：弹层瘦身 · 分类每行6个/3行内滚 · 滚轮压到3行小行高 · 去时长快捷 · 标签与管理并入一级分组行 */
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const R = [];
function rep(name, a, b, cnt) {
  const n = s.split(a).length - 1;
  if (n !== (cnt || 1)) { console.error('MISS/DUP ' + name + ' count=' + n); process.exit(1); }
  s = s.split(a).join(b);
  R.push(name);
}
const L = a => a.join('\n');

/* 1) 滚轮：行高 32→26 · 可视 3 行（78px） */
rep('css-wheel',
  '  .wheelbox{height:96px;overflow-y:auto;scroll-snap-type:y mandatory;scrollbar-width:none;-webkit-overflow-scrolling:touch;overscroll-behavior:contain}',
  '  .wheelbox{height:78px;overflow-y:auto;scroll-snap-type:y mandatory;scrollbar-width:none;-webkit-overflow-scrolling:touch;overscroll-behavior:contain}');
rep('css-witem',
  '  .witem{height:32px;line-height:32px;scroll-snap-align:center;text-align:center;font-size:12px;color:#94a3b8;font-weight:600;user-select:none;transition:color .15s}',
  '  .witem{height:26px;line-height:26px;scroll-snap-align:center;text-align:center;font-size:12px;color:#94a3b8;font-weight:600;user-select:none;transition:color .15s}');
rep('js-wih', "const WI_H=32;", "const WI_H=26;");
rep('js-spacer',
  "for(let k=0;k<rep*n;k++)h+=`<div class=\"witem\">${w.items[k%n]}</div>`;\n    h+='<div style=\"height:32px\"></div>';",
  "for(let k=0;k<rep*n;k++)h+=`<div class=\"witem\">${w.items[k%n]}</div>`;\n    h+='<div style=\"height:26px\"></div>';");
rep('js-spacer2', "let h='<div style=\"height:32px\"></div>';", "let h='<div style=\"height:26px\"></div>';");

/* 2) 时间卡内边距收紧 */
rep('card-pad',
  '          <span class="inline-block px-2 py-0.5 rounded-md bg-slate-900 text-white text-[9px] font-bold dark:bg-white dark:text-slate-900">上尾 · 起始</span>',
  '          <span class="inline-block px-1.5 py-0.5 rounded-md bg-slate-900 text-white text-[9px] font-bold dark:bg-white dark:text-slate-900">上尾 · 起始</span>');

/* 3) 删掉「时长」快捷钮行；标签/无分类 移到一级分组行右侧 */
rep('dur-row', L([
  '      <div class="mt-2 flex items-center gap-1.5 text-[10px] font-bold flex-wrap">时长',
  '        <button class="tag-chip justify-center" onclick="tpDur(0)">0分</button>',
  '        <button class="tag-chip justify-center" onclick="tpDur(15)">15分</button>',
  '        <button class="tag-chip justify-center" onclick="tpDur(30)">30分</button>',
  '        <button class="tag-chip justify-center" onclick="tpDur(60)">1时</button>',
  '        <button class="tag-chip justify-center" onclick="tpDur(120)">2时</button>',
  '        <span class="ml-auto flex gap-1"><button class="tag-chip" onclick="toast(\'标签选择面板（模拟）· 默认带分类默认标签\')">标签 ›</button><button class="tag-chip" onclick="closeSheet(\'sheetTimePick\');navTo(\'p-sub-cats\')">无分类 ›</button></span>',
  '      </div>',
  '      <div class="mt-3 text-xs font-bold text-slate-500">一级分组</div>',
  '      <div id="tpCats" class="mt-2 flex flex-wrap gap-2 text-[11px]"></div>',
  '      <div class="mt-3 pt-3 border-t-2 border-dashed border-slate-200 dark:border-slate-700 text-xs font-bold text-slate-500">子分组<span class="font-normal text-[10px] text-slate-400 ml-1">属于上方选中的一级分组 · 再点可取消</span></div>',
  '      <div id="tpSubs" class="mt-2 rounded-xl bg-slate-100 dark:bg-slate-800/60 p-2.5 flex flex-wrap gap-2 text-[11px] min-h-[38px]"></div>',
]), L([
  '      <div class="mt-2 flex items-center gap-1.5 text-xs font-bold text-slate-500">一级分组',
  '        <span class="ml-auto flex gap-1"><button class="tag-chip" onclick="toast(\'标签选择面板（模拟）· 默认带分类默认标签\')">标签 ›</button><button class="tag-chip" onclick="closeSheet(\'sheetTimePick\');navTo(\'p-sub-cats\')">管理 ›</button></span>',
  '      </div>',
  '      <div id="tpCats" class="tp-catgrid mt-1.5"></div>',
  '      <div class="mt-2 pt-2 border-t-2 border-dashed border-slate-200 dark:border-slate-700 text-xs font-bold text-slate-500">子分组<span class="font-normal text-[10px] text-slate-400 ml-1">属于上方选中的一级分组 · 再点可取消</span></div>',
  '      <div id="tpSubs" class="tp-catgrid tp-subgrid mt-1.5"></div>',
]));

/* 4) 分类网格样式：每行 6 个 · 行距 4px · 最多 3 行内滚 */
rep('catgrid-css',
  '  .witem{height:26px;',
  L([
  '  .tp-catgrid{display:grid;grid-template-columns:repeat(6,1fr);gap:4px;max-height:82px;overflow-y:auto;scrollbar-width:none}',
  '  .tp-catgrid::-webkit-scrollbar{display:none}',
  '  .tp-catgrid .tag-chip{padding:5px 2px;font-size:10px;justify-content:center;gap:3px;min-width:0}',
  '  .tp-catgrid .tag-chip i{width:7px!important;height:7px!important;flex:none}',
  '  .tp-catgrid > span{grid-column:1/-1;text-align:center;padding:4px 0}',
  '  .tp-subgrid{background:rgb(241 245 249 / .8);border-radius:12px;padding:6px}',
  '  .dark .tp-subgrid{background:rgb(30 41 59 / .6)}',
  '  .witem{height:26px;',
]));

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
