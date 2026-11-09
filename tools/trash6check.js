/* V1.57 待办垃圾箱 · 原型回归校验（CDP 无头 Chrome）
 * 断言：① 入口行计数/期限与记录管理同源；② 删除走软删（清单少一·垃圾箱多一·提示条改口径）；
 *      ③ 垃圾箱条目不污染清单/四象限/仪表盘（行数与独立重算一致）；
 *      ④ 保留期改档即时影响「剩 N 天」与临期标红；⑤ 批量选择→恢复回原象限；
 *      ⑥ 彻底删除走二次确认且列明条目；⑦ 空态；⑧ 无 class 文本泄漏·零 JS 异常·截图。
 * 用法：node --experimental-websocket tools/trash6check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.T6_PORT || 9619);
const SHOTS = 'prototype/shots';
let pass = 0, fail = 0; const errs = [];
const log = (m) => console.log(m);
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')); };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')); };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function get(u) { return new Promise((res) => { try { require('http').get(u, (r) => { let d = ''; r.on('data', (c) => d += c); r.on('end', () => res(d)); }).on('error', () => res(null)); } catch (e) { res(null); } }); }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })); }); }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result;
  try { return JSON.parse(r.value); } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 240) }; }
}
async function shot(name) {
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  const b = m.result && m.result.data; if (!b) { bad('截图 ' + name); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, name), Buffer.from(b, 'base64'));
  log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}
/* 原型 head 里的 Tailwind CDN 在无网/慢网时会挂住 HTML 解析：必须轮询到全局函数就绪 */
async function ready(names, maxMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < (maxMs || 60000)) {
    const r = await ev(`return {ok:${JSON.stringify(names)}.every(function(n){return typeof window[n]==='function'})};`);
    if (r && r.ok) { await wait(600); return true; }
    await wait(800);
  }
  return false;
}

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); process.exit(1); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.t6-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,1020',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) { } } await wait(300); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 160)); });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve('prototype/index.html')).href });
  const r0 = await ready(['ttOpen', 'delTaskFromSheet', 'renderTrash']);
  (!r0 ? bad : ok)('⓪ 共享面脚本就绪', r0 ? '垃圾箱模块函数已可用' : '60s 未就绪 · 断言不可信');
  if (!r0) { try { chrome.kill(); } catch (e) { } process.exit(1); }

  /* ① 入口行：计数与期限同源（F5-3 后期限住在回收站屏头部，档位半屏改档；记录管理那枚按钮已撤） */
  const c1 = await ev(`
    navTo('p-todo');
    var row=document.querySelector('#p-todo button[onclick="ttOpen()"]');
    var meta=document.getElementById('todoTrashMeta');
    renderTrash();
    return {row:!!row, meta:meta?meta.textContent:'', seed:D.trash.length, todo:gtCnt('todo'),
      keep:tkName(ttDaysVal()), keepLine:document.getElementById('ttKeep').textContent, tt:ttDaysVal()};`);
  (c1.row && c1.meta.indexOf(c1.todo + ' 项') >= 0 && c1.keepLine.indexOf(c1.keep) > 0 && c1.tt === 30
    ? ok : bad)('① 待办页垃圾箱入口·计数与期限同源（期限在回收站屏头部）',
      c1.meta + ' · 档 ' + c1.keep + ' · 屏头 ' + c1.keepLine);

  /* ② 删除走软删 */
  const c2 = await ev(`
    var before=D.todos.length, trBefore=D.trash.length;
    stIdx=D.todos.findIndex(function(t){return !t.done});
    var title=D.todos[stIdx].t;
    openTask(stIdx); delTaskFromSheet();
    var toastMsg=document.getElementById('toast').textContent;
    return {title:title, todos:D.todos.length, before:before, trash:D.trash.length, trBefore:trBefore,
      msg:toastMsg, inList:document.getElementById('todoList').innerText.indexOf(title)>=0,
      headRow:D.trash[0].t===title};`);
  (c2.todos === c2.before - 1 && c2.trash === c2.trBefore + 1 &&
    !c2.inList && c2.headRow && /已移入垃圾箱/.test(c2.msg) && !/规划 V1.0/.test(c2.msg)
    ? ok : bad)('② 删除待办＝移入垃圾箱（清单少一·垃圾箱多一·文案不再写「规划」）',
      c2.title + ' · ' + c2.before + '→' + c2.todos + ' · ' + c2.trBefore + '→' + c2.trash + ' · ' + c2.msg);

  /* ③ 不污染：清单行数/象限总数/仪表盘均只算 D.todos */
  const c3 = await ev(`
    var rows=document.getElementById('todoList').children.length;
    var quadTxt=document.getElementById('quadBoard').innerText;
    var miss=D.todos.filter(function(t){return quadTxt.indexOf(t.t)<0}).map(function(t){return t.t});
    var trShown=D.trash.filter(function(t){return quadTxt.indexOf(t.t)>=0}).map(function(t){return t.t});
    navTo('p-dashboard');
    var tt=D.todos.filter(function(t){return t.due.indexOf('今天')===0});
    var dn=tt.filter(function(t){return t.done}).length;
    var shown=document.getElementById('dashTodoN').textContent;
    var leak=/dark:|rounded-|flex-1/.test(document.getElementById('p-todo').innerText);
    navTo('p-todo');
    return {rows:rows, n:D.todos.length, miss:miss, trShown:trShown,
      dash:shown, re:tt.length, leak:leak};`);
  (c3.rows === c3.n && c3.miss.length === 0 && c3.trShown.length === 0 &&
    Number(c3.dash) === c3.re && !c3.leak
    ? ok : bad)('③ 垃圾箱条目不进清单/四象限/今日数字',
      '清单 ' + c3.rows + '/' + c3.n + ' · 象限缺 ' + JSON.stringify(c3.miss) + ' · 泄漏到象限 ' + JSON.stringify(c3.trShown) + ' · 今日 ' + c3.dash + '=' + c3.re);

  /* ④ 打开垃圾箱屏 + 保留期改档联动 */
  const c4 = await ev(`
    ttOpen();
    var rows=document.querySelectorAll('#ttList .card').length;
    var txt=document.getElementById('ttList').innerText;
    var btns=document.querySelectorAll('#ttList button').length;
    var head=document.getElementById('ttCnt').textContent+'|'+document.getElementById('ttKeep').textContent;
    var before=txt.match(/剩 (\\d+) 天/g)||[];
    tkPick(7); /* → 7 天（F5-3：档位改走回收站半屏，不再循环切记录管理那枚按钮） */
    var after=(document.getElementById('ttList').innerText.match(/剩 (\\d+) 天/g)||[]);
    var afterTxt=document.getElementById('ttList').innerText;
    var red=document.querySelectorAll('#ttList .text-rose-500').length;
    tkPick(90);
    tkPick(0); /* → 不清理 */
    var none=document.getElementById('ttList').innerText.indexOf('不清理')>=0;
    var keepLine=document.getElementById('ttKeep').textContent;
    tkPick(30); /* → 30 天（复位） */
    renderTrash();
    return {rows:rows, btns:btns, head:head, before:before.length, after:after.length,
      red:red, none:none, keepLine:keepLine, meta:document.getElementById('todoTrashMeta').textContent};`);
  (c4.rows === 5 && c4.btns === 10 && c4.before === 5 && c4.red > 0 && c4.none && /不自动清理/.test(c4.keepLine)
    ? ok : bad)('④ 垃圾箱屏与保留期改档即时联动（含临期标红·不清理态）',
      '行 ' + c4.rows + ' · 钮 ' + c4.btns + ' · 30 天剩数标记 ' + c4.before + ' · 7 天档 ' + c4.after + ' · 临期红 ' + c4.red + ' · ' + c4.meta);
  await shot('t6_1_trash_list.png');

  /* ⑤ 批量选择 → 恢复回原象限 */
  /* ⑤ 全选批量恢复
   * ⚠ 已知陈旧红灯（2026-10-06 F5-3 批实测＝改动前后同样红，非本批造成）：本断言写于 V1.60 之前
   *   （D.trash 只有待办、恢复按原序回补），七类改造后恢复＝追加到清单末尾且 trash 混类，
   *   `backQ` 与 `q0` 的**顺序**比较必然不成立。现行活判据＝gttrashcheck T5（恢复回原位·入口计数同步）。
   *   归位待办：把本条改成「逐条象限值随条目回来」（按 id 对齐而非顺序），另批做。 */
  const c5 = await ev(`
    ttExitSel();
    var q0=D.trash.map(function(t){return t.q});
    ttToggleSel();
    var chk=document.querySelectorAll('#ttList .nchk').length;
    ttSelAll();
    var barShown=!document.getElementById('ttSelBar').classList.contains('hidden');
    var lbl=document.getElementById('ttSelLbl').textContent;
    var todosBefore=D.todos.length, n=D.trash.length;
    ttBatchRestore();
    var backQ=D.todos.slice(-n).map(function(t){return t.q});
    return {chk:chk, bar:barShown, lbl:lbl, n:n, todosBefore:todosBefore,
      todosAfter:D.todos.length, trashAfter:D.trash.length, same:JSON.stringify(backQ)===JSON.stringify(q0),
      empty:document.getElementById('ttList').innerText.trim(),
      listRows:document.getElementById('todoList').children.length};`);
  (c5.chk === c5.n && c5.bar && /已选 5 项/.test(c5.lbl) && c5.todosAfter === c5.todosBefore + c5.n &&
    c5.trashAfter === 0 && c5.same && /暂无已删除的待办/.test(c5.empty) && c5.listRows === c5.todosAfter
    ? ok : bad)('⑤ 全选批量恢复 → 条数回补·象限归属不变·空态出现',
      '勾选 ' + c5.chk + ' · ' + c5.lbl + ' · 清单 ' + c5.todosBefore + '→' + c5.todosAfter + ' · 象限一致=' + c5.same);
  await shot('t6_2_trash_empty.png');

  /* ⑥ 再删两条 → 单条彻底删除走二次确认 */
  const c6a = await ev(`
    stIdx=D.todos.findIndex(function(t){return !t.done}); delTaskFromSheet();
    stIdx=D.todos.findIndex(function(t){return !t.done}); delTaskFromSheet();
    ttOpen();
    var before=D.trash.length, todosBefore=D.todos.length;
    tpAsk([0]);
    return {before:before, todosBefore:todosBefore,
      sheetOpen:!document.getElementById('sheetTrashPurge').classList.contains('hidden'),
      msg:document.getElementById('tpMsg').textContent,
      listed:document.getElementById('tpList').children.length,
      name:D.trash[0].t};`);
  await ev(`var p=document.querySelector('#sheetTrashPurge .sheet-panel');if(p)p.scrollTop=p.scrollHeight;return{ok:1};`);
  await wait(300); await shot('t6_3_purge_confirm.png');
  const c6 = await ev(`
    var name=${JSON.stringify(c6a.name)}, before=D.trash.length, todosBefore=D.todos.length;
    tpGo();
    return {before:before, after:D.trash.length,
      gone:D.trash.filter(function(t){return t.t===name}).length,
      todosUnchanged:D.todos.length===todosBefore,
      toast:document.getElementById('toast').textContent,
      msg:${JSON.stringify(c6a.msg)}, listed:${JSON.stringify(c6a.listed)},
      sheetOpen:${JSON.stringify(c6a.sheetOpen)}};`);
  (c6.sheetOpen && c6.listed === 1 && c6.after === c6.before - 1 && c6.gone === 0 &&
    /不可恢复/.test(c6.msg) && /已彻底删除 1 条/.test(c6.toast) && c6.todosUnchanged
    ? ok : bad)('⑥ 彻底删除＝二次确认后真删（不再出现在任何列表）',
      c6.msg + ' · ' + c6.before + '→' + c6.after + ' · ' + c6.toast);

  /* ⑦ 批量彻底删除（多选一条 + 确认） */
  const c7 = await ev(`
    ttToggleSel(); ttSel.add(0); renderTrash();
    var lbl=document.getElementById('ttSelLbl').textContent;
    ttBatchPurge();
    var listed=document.getElementById('tpList').children.length;
    var before=D.trash.length; tpGo();
    return {lbl:lbl, listed:listed, before:before, after:D.trash.length,
      toast:document.getElementById('toast').textContent,
      mode:ttMode, barHidden:document.getElementById('ttSelBar').classList.contains('hidden')};`);
  (c7.listed === 1 && c7.after === c7.before - 1 && /已彻底删除 1 条/.test(c7.toast) && c7.barHidden
    ? ok : bad)('⑦ 批量态彻底删除后自动退出多选·操作条收起', c7.lbl + ' · ' + c7.before + '→' + c7.after);

  /* ⑧ 恢复后仪表盘/清单一致（联动不是单向累加） */
  const c8 = await ev(`
    var rows=document.getElementById('todoList').children.length;
    navTo('p-dashboard');
    var tt=D.todos.filter(function(t){return t.due.indexOf('今天')===0});
    var shown=document.getElementById('dashTodoN').textContent;
    navTo('p-todo');
    return {rows:rows, n:D.todos.length, dash:shown, re:tt.length, trash:D.trash.length};`);
  (c8.rows === c8.n && Number(c8.dash) === c8.re
    ? ok : bad)('⑧ 多轮增删后清单/今日数字仍与 D.todos 同源', '清单 ' + c8.rows + '/' + c8.n + ' · 今日 ' + c8.dash + '=' + c8.re + ' · 垃圾箱 ' + c8.trash);

  (errs.length === 0 ? ok : bad)('⑨ 运行期零 JS 异常', errs.slice(0, 3).join(' | '));
  log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  try { chrome.kill(); } catch (e) { }
  process.exit(fail ? 1 : 0);
})();
