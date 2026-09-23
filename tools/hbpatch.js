const fs = require('fs');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n');
const L0 = S.length;
let fails = 0;

function span(t, a, b, ins, keepEnd) {
  const i = S.indexOf(a), j = S.indexOf(b, i);
  if (i < 0 || j < 0) { console.log('SPAN MISS', t, i, j); fails++; return }
  S = S.slice(0, i) + ins + (keepEnd ? S.slice(j) : '') + S.slice(j + (keepEnd ? 0 : 0));
  if (!keepEnd) { /* replaced through b */ }
}
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
}
// region replace [startMarker, endMarker) keeping endMarker
function reg(t, a, b, ins) {
  const i = S.indexOf(a), j = S.indexOf(b, i);
  if (i < 0 || j < 0) { console.log('REG MISS', t, i, j); fails++; return }
  S = S.slice(0, i) + ins + S.slice(j);
}

reg('pages', '    <!-- ===== P12 习惯打卡 ===== -->', '    <!-- ===== P12a 二级：数据与同步 ===== -->', R('hb_pages.txt') + '\n');
reg('sheets', '  <!-- ===== 新建习惯 ===== -->', '  <!-- ===== 主题市场 ===== -->', R('hb_sheets.txt') + '\n');
reg('js', '/* ================= 习惯打卡（正向/负向） ================= */', '/* ================= 插件中心（大模块插件化） ================= */', R('hb_js.txt') + '\n');

// 顶栏：页内动作容器 + 搜索按钮 id
rep('hdr', `    <button onclick="openSheet('sheetSearch')" class="w-9 h-9 rounded-full flex items-center justify-center active:bg-slate-200 dark:active:bg-slate-800">`,
  `    <div id="hdrActs" class="hidden items-center gap-1.5"></div>
    <button id="btnHdrSearch" onclick="openSheet('sheetSearch')" class="w-9 h-9 rounded-full flex items-center justify-center active:bg-slate-200 dark:active:bg-slate-800">`);

// setPage 钩子
rep('setPage', `  $('#btnTodoViewToggle').classList.toggle('flex',p==='p-todo');`,
  `  $('#btnTodoViewToggle').classList.toggle('flex',p==='p-todo');
  if(typeof renderHdrActs==='function')renderHdrActs(p);`);

// CSS
rep('css', '  .hb-dot{', '  .hb-cell{height:20px;border-radius:6px;cursor:pointer}\n  .hb-cell.bf-on{outline:2px solid var(--accent);outline-offset:1px}\n  .hb-dot{');

const keep = S.length / L0;
if (keep < 0.9 || keep > 1.25) { console.log('SIZE GUARD ABORT', L0, '->', S.length); process.exit(1) }
if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('OK', L0, '->', S.length, 'ratio', keep.toFixed(3));
