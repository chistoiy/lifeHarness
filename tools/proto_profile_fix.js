/* 我的页两处保真缺口（2026-09-29 产品走查反馈）：
   ① 「编辑」只弹 toast，资料无法操作；
   ② 三张统计卡（完成任务/连续记录天/在册书籍）是写死数字，与演示数据无联动。
   做法：D 内加 profile（昵称/签名 + 历史基数），统计卡改为「历史基数 + 当前演示数据聚合」，
   进页与数据变更后重算；「编辑」开半屏弹层改昵称/签名，保存后同步头像字、副标题、
   今天页问候语与待办「已完成」chip。
   用法：node tools/proto_profile_fix.js [--dry] */
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const before = s.length;
const dry = process.argv.includes('--dry');
let hits = 0;
const misses = [];
function sub(one, many, tag) {
  const n = s.split(one).length - 1;
  if (n !== 1) { misses.push((tag || one.slice(0, 30)) + ' ×' + n); return; }
  s = s.split(one).join(many);
  hits++;
}

/* ── 1) D 内加 profile（放在 const D = { 之后） */
sub(
  'const D = {\n  todoChips:',
  'const D = {\n' +
    '  // 我的页资料与统计基数（2026-09-29）：统计卡 = 基数 + 当前演示数据聚合，\n' +
    '  // 基数代表历史累计（演示数据只含近期样本），故初始仍显示 128/55/17。\n' +
    "  profile:{name:'CHIST',bio:'数据在手心里',doneBase:127,streakBase:52,booksBase:13},\n" +
    '  todoChips:',
  'profile',
);

/* ── 2) 头像/昵称/副标题/编辑钮 */
sub(
  '<div class="w-16 h-16 rounded-full grad flex items-center justify-center text-white text-2xl font-extrabold shadow-lg shadow-indigo-500/30">C</div>\n' +
    '        <div><div class="font-extrabold text-lg">CHIST</div><div class="text-xs text-slate-400">本地模式 · 无账号 · 已记录 55 天</div></div>\n' +
    '        <button class="ml-auto text-xs text-brand-500 font-bold" onclick="toast(\'编辑资料（模拟）\')">编辑</button>',
  '<div id="pfAv" class="w-16 h-16 rounded-full grad flex items-center justify-center text-white text-2xl font-extrabold shadow-lg shadow-indigo-500/30">C</div>\n' +
    '        <div><div id="pfName" class="font-extrabold text-lg">CHIST</div><div id="pfSub" class="text-xs text-slate-400">本地模式 · 无账号 · 已记录 55 天</div></div>\n' +
    '        <button id="pfEditBtn" class="ml-auto text-xs text-brand-500 font-bold" onclick="openProfileEdit()">编辑</button>',
  'header',
);

/* ── 3) 三张统计卡挂 id */
sub(
  '<div class="card !py-2.5"><b class="text-base text-brand-500">128</b>完成任务</div>\n' +
    '        <div class="card !py-2.5"><b class="text-base text-mint">55</b>连续记录天</div>\n' +
    '        <div class="card !py-2.5"><b class="text-base text-sun">17</b>在册书籍</div>',
  '<div class="card !py-2.5"><b id="pfDone" class="text-base text-brand-500">128</b>完成任务</div>\n' +
    '        <div class="card !py-2.5"><b id="pfStreak" class="text-base text-mint">55</b>连续记录天</div>\n' +
    '        <div class="card !py-2.5"><b id="pfBooks" class="text-base text-sun">17</b>在册书籍</div>',
  'stats',
);

/* ── 4) 今天页问候语挂 id（与昵称联动） */
sub(
  '<div class="text-sm opacity-80">早上好，CHIST ☀️</div>',
  '<div id="dashGreet" class="text-sm opacity-80">早上好，CHIST ☀️</div>',
  'greet',
);

/* ── 5) 待办「已完成」chip 改实时数 */
sub(
  "function renderChips(){ $('#smartChips').innerHTML=D.todoChips.map((c,i)=>`<button",
  "function renderChips(){ D.todoChips=D.todoChips.map(c=>c.replace(/已完成 \\d+/,'已完成 '+statDone())); $('#smartChips').innerHTML=D.todoChips.map((c,i)=>`<button",
  'chips',
);

/* ── 6) 新增：统计聚合 + 资料编辑弹层逻辑（挂在 navTo 之前） */
sub(
  'function navTo(p){ if(p!==curPage){ stack.push(curPage); setPage(p);} }',
  '/* ===== 我的 · 资料与统计联动 =====\n' +
    '/* 统计卡＝历史基数 + 当前演示数据聚合：勾完一条待办/新增一本书/多记一天日记都会即时反映 */\n' +
    'const statDone=()=>D.profile.doneBase+D.todos.filter(t=>t.done).length;\n' +
    'const statStreak=()=>D.profile.streakBase+new Set(D.diary.map(d=>d.d)).size;\n' +
    'const statBooks=()=>D.profile.booksBase+D.books.length;\n' +
    'function renderProfile(){\n' +
    "  const p=D.profile,av=$('#pfAv');if(!av)return;\n" +
    "  av.textContent=(p.name||'·').trim().charAt(0).toUpperCase();\n" +
    "  $('#pfName').textContent=p.name; $('#pfSub').textContent='本地模式 · 无账号 · 已记录 '+statStreak()+' 天';\n" +
    "  $('#pfDone').textContent=statDone(); $('#pfStreak').textContent=statStreak(); $('#pfBooks').textContent=statBooks();\n" +
    "  const g=$('#dashGreet'); if(g){ if(!g.dataset.hi)g.dataset.hi=g.textContent.split('，')[0]+'，'; g.textContent=g.dataset.hi+p.name+' ☀️'; }\n" +
    "  if(curPage==='p-profile')$('#pageSub').textContent='本地模式 · '+p.bio;\n" +
    '}\n' +
    "function openProfileEdit(){ const p=D.profile; $('#pfNameIn').value=p.name; $('#pfBioIn').value=p.bio; $('#pfNameErr').classList.add('hidden'); openSheet('sheetProfile'); }\n" +
    "function saveProfileEdit(){\n" +
    "  const v=$('#pfNameIn').value.trim();\n" +
    '  if(!v){ $("#pfNameErr").textContent="昵称不能为空"; $("#pfNameErr").classList.remove("hidden"); return; }\n' +
    "  D.profile.name=v; D.profile.bio=$('#pfBioIn').value.trim()||'数据在手心里';\n" +
    "  closeSheet('sheetProfile'); renderProfile(); renderChips(); toast('资料已更新（模拟持久化）');\n" +
    '}\n' +
    'function navTo(p){ if(p!==curPage){ stack.push(curPage); setPage(p);} }',
  'js',
);

/* ── 7) setPage 内挂渲染（进页即重算·顶栏副标题随签名） */
sub(
  "  if(p==='p-timeStats')renderTimeStats();",
  "  if(p==='p-timeStats')renderTimeStats();\n  if(p==='p-profile')renderProfile();",
  'setPage',
);

/* ── 8) 弹层：昵称 + 签名 + 保存（放在城市选择弹层之后） */
sub(
  '  <!-- ===== V1.28 新建/编辑模板（分节结构） ===== -->',
  '  <!-- ===== 我的 · 编辑资料（昵称/签名 · 2026-09-29 保真补口） ===== -->\n' +
    "  <div id=\"sheetProfile\" class=\"sheet hidden fixed md:absolute inset-0 z-50 bg-black/40 items-end\" onclick=\"if(event.target===this)closeSheet('sheetProfile')\">\n" +
    '    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">\n' +
    '      <div class="grabber"></div>\n' +
    '      <div class="font-extrabold">编辑资料</div>\n' +
    '      <div class="mt-3 text-xs font-bold text-slate-400">昵称</div>\n' +
    '      <input id="pfNameIn" maxlength="12" class="mt-1.5 w-full rounded-xl bg-slate-100 dark:bg-slate-800 px-4 py-3 text-sm outline-none" placeholder="显示在「我的」与今天页问候语">\n' +
    '      <div id="pfNameErr" class="hidden text-[11px] text-rose-500 mt-1 font-bold"></div>\n' +
    '      <div class="mt-3 text-xs font-bold text-slate-400">一句话签名</div>\n' +
    '      <input id="pfBioIn" maxlength="20" class="mt-1.5 w-full rounded-xl bg-slate-100 dark:bg-slate-800 px-4 py-3 text-sm outline-none" placeholder="出现在顶栏副标题">\n' +
    '      <div class="mt-4 flex gap-2"><button class="flex-1 py-2.5 rounded-xl bg-slate-100 dark:bg-slate-800 text-sm font-bold" onclick="closeSheet(\'sheetProfile\')">取消</button>\n' +
    '        <button class="flex-1 py-2.5 rounded-xl grad text-white text-sm font-bold" onclick="saveProfileEdit()">保存</button></div>\n' +
    '    </div>\n' +
    '  </div>\n' +
    '  <!-- ===== V1.28 新建/编辑模板（分节结构） ===== -->',
  'sheet',
);

/* ── 9) 勾待办时同步「已完成」chip（与我的页统计同源） */
sub(
  'function tkToggle(i){ const t=D.todos[i]; t.done=!t.done; renderTodos(); renderQuad(); renderTimeline();',
  'function tkToggle(i){ const t=D.todos[i]; t.done=!t.done; renderTodos(); renderQuad(); renderTimeline(); renderChips();',
  'tkToggle',
);

console.log('命中 =', hits, '| 异常 =', misses.length ? misses.join(' || ') : '无');
console.log('体积：', before, '→', s.length, '（Δ', s.length - before, '）');
if (misses.length) { console.error('有异常命中，拒绝写出'); process.exit(1); }
if (dry) { console.error('--dry 未写盘'); process.exit(1); }
fs.writeFileSync(P, s);
console.log('已写', P);
