const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '').split('\n');
let L = S.split('\n'), fails = 0;
function rep(t, a, b, all) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (!all && S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = all ? S.split(a).join(b) : S.slice(0, i) + b + S.slice(i + a.length);
  L = S.split('\n');
}
function before(t, sub, ins) {
  const i = L.findIndex(l => l.indexOf(sub) >= 0);
  if (i < 0) { console.log('BEFORE MISS', t); fails++; return }
  L = L.slice(0, i).concat(ins, L.slice(i)); S = L.join('\n');
}

/* 1) 日期速览弹层 + JS */
before('sheet', '  <!-- ===== 习惯专版 · 分类 / 单位管理器 ===== -->', R('hbH_sheet.txt').concat(['']));
before('js', '/* 分类 / 单位自定义（同一套管理器） */', R('hbH_js.txt').concat(['']));

/* 2) 日期标签 → 可点击打开日历 */
rep('label', `        <div class="flex-1 text-center text-[12px] font-extrabold" id="hbDayLabel">今天</div>`,
`        <button class="flex-1 text-center text-[12px] font-extrabold" id="hbDayLabel" onclick="hbDayOpen()">今天</button>`);

/* 3) 筛选框收窄 + 右侧计数提示 */
rep('selw', 'class="sel flex-1 !py-1.5 !text-[11px]"', 'class="sel !w-[102px] shrink-0 !py-1.5 !text-[11px]"', true);
rep('hint', `        <button id="hbViewBtn" class="w-9 h-9 rounded-xl bg-slate-100 dark:bg-slate-800 text-slate-500 flex items-center justify-center shrink-0" onclick="hbViewT()" title="切换视图"></button>`,
`        <button id="hbViewBtn" class="w-9 h-9 rounded-xl bg-slate-100 dark:bg-slate-800 text-slate-500 flex items-center justify-center shrink-0" onclick="hbViewT()" title="切换视图"></button>
        <span id="hbFilterHint" class="ml-auto text-[10px] text-slate-400 shrink-0"></span>`);
rep('hintfill', " el.className=hbView==='list'?'mt-3 space-y-3'",
 " const fh=document.getElementById('hbFilterHint');if(fh)fh.textContent='显示 '+list.length+' / '+book.length;\n el.className=hbView==='list'?'mt-3 space-y-3'");

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
