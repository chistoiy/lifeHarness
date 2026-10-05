/* V1.60「全局回收站」原型回归（p-sub-trash 七类分段 · 书连带清防幽灵 · 三入口改道 · 计数同源）
 * V1.61 追加：物品成为第七类（T1b 分段行副信息 · T7c 彻底删除后果 · T11 恢复文案）
 * 用法：node --experimental-websocket tools/gttrashcheck.js（截图：GT_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.GT_PORT || 9573);
const SHOTS = process.env.GT_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/r4c-shots';
let pass = 0, fail = 0; const errs = [];
const log = m => { console.log(m) };
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 260) } }
}
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
const ROWSORPH = "[].slice.call($$('#ttList .card')).filter(function(c){return /不可单独恢复/.test(c.textContent)})";
const ROWS = "[].map.call($$('#ttList .card'),function(c){return c.querySelector('.font-semibold').textContent})";

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.gt-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* T1 进屏：七类分段 chips + 全部 10 行 + 计数同源 */
  const t1 = await ev(`gtOpen('all');
    return {p:curPage,chips:$$('#gtSegRow button').length,rows:${ROWS},cnt:$('#ttCnt').textContent};`);
  (t1.p === 'p-sub-trash' && t1.chips === 8 && t1.rows.length === 10 && /^10 项$/.test(t1.cnt))
    ? ok('T1 回收站屏：8 段 chips（含物品） · 全部 10 行 · 计数 10 项') : bad('T1', JSON.stringify(t1));
  await shot('gt-01-all');

  /* T1b V1.61 物品分段：单行 · 副信息带分类/成本池/持有天数与「关联流水保留」（截图后再回全部段） */
  const t1b = await ev(`gtSeg='item';ttExitSel();
    return {rows:$$('#ttList .card').length,txt:$('#ttList').textContent,cnt:$('#ttCnt').textContent,
      seg:[].map.call($$('#gtSegRow button'),function(b){return b.textContent.trim()}).join('|')};`);
  await wait(400);   // 等一帧重绘，否则样张拍到过滤前的旧帧
  await shot('gt-01b-item-seg');
  await ev(`gtSeg='all';ttExitSel();return 1;`);
  (t1b.rows === 1 && t1b.cnt === '1 项' && /成本池 ¥1,499/.test(t1b.txt) && /持有 1210 天/.test(t1b.txt)
    && /关联流水 1 条保留/.test(t1b.txt) && /物品 1/.test(t1b.seg))
    ? ok('T1b 物品行副信息＝分类·成本池·持有·流水保留（分段计数同源）') : bad('T1b', JSON.stringify(t1b));

  /* T2 书行连带文案（进屏即可见，不用先点开删除） */
  const t2 = await ev(`return {txt:${ROWS}.join('|'),book:($('#ttList').textContent.includes('含在库划线·笔记 23 条 · 阅读 186 分钟 · 进度 41%'))};`);
  t2.book ? ok('T2 书行连带计数文案（在库划线·计时·进度）') : bad('T2', JSON.stringify(t2));

  /* T2b 孤行两态：父书还在回收站也判孤（V1.60 实现口径回灌） */
  const t2b = await ev(`gtSeg='quote';ttExitSel();
    var r={orph:${ROWSORPH}.length,txt:$('#ttList').textContent};gtSeg='all';ttExitSel();return r;`);
  (t2b.orph === 1 && /· 书还在回收站/.test(t2b.txt) && /不可单独恢复/.test(t2b.txt))
    ? ok('T2b 父书在回收站＝同判孤，副信息说明原因') : bad('T2b', JSON.stringify(t2b));
  await shot('gt-01b-quote-parent-in-trash');

  /* T3 剩余天数临期标红（习惯 08-26 → 剩 7；待办 08-22 → 剩 3） */
  const t3 = await ev(`return [].map.call($$('#ttList .text-rose-500'),function(e){return e.textContent}).filter(function(t){return /剩|待清理/.test(t)});`);
  (JSON.stringify(t3.sort()) === JSON.stringify(['剩 3 天', '剩 7 天'])) ? ok('T3 临期剩余天数标红') : bad('T3', JSON.stringify(t3));

  /* T4 分段过滤 */
  const t4 = await ev(`gtSeg='note';ttExitSel();var n=$$('#ttList .card').length;gtSeg='list';ttExitSel();
    return {note:n,list:$$('#ttList .card').length,cnt:$('#ttCnt').textContent};`);
  (t4.note === 1 && t4.list === 1 && t4.cnt === '1 项') ? ok('T4 分段过滤：笔记 1 · 书单 1 · 计数随段切换') : bad('T4', JSON.stringify(t4));

  /* T5 恢复待办：回清单且入口计数同步 */
  const t5 = await ev(`gtSeg='all';ttExitSel();var b=D.todos.length,ti=D.trash.findIndex(function(t){return (t.k||'todo')==='todo'});
    ttRestore([ti]);return {d:D.todos.length-b,trash:D.trash.length,meta:$('#todoTrashMeta').textContent};`);
  (t5.d === 1 && t5.trash === 9 && /待办 3 项/.test(t5.meta)) ? ok('T5 恢复回原位 · 待办页入口计数同步') : bad('T5', JSON.stringify(t5));

  /* T6 彻底删除书籍：确认弹层带连带清单 */
  const t6 = await ev(`var bi=D.trash.findIndex(function(t){return t.k==='book'});tpAsk([bi]);
    return {sheet:!$('#sheetTrashPurge').classList.contains('hidden'),txt:$('#tpList').textContent};`);
  (/连带清 在库划线·笔记 23 条 · 计时 · 进度/.test(t6.txt) && t6.sheet) ? ok('T6 删除书籍确认弹层列在库连带数量') : bad('T6', JSON.stringify(t6));
  await shot('gt-02-purge-book-sheet');

  /* T7 执行后防幽灵：所属书没了的划线＝不可单独恢复 */
  const t7 = await ev(`tpGo();gtSeg='quote';ttExitSel();
    return {orphan:D.trash.filter(function(t){return t.k==='quote'&&t.orphan}).length,row:($('#ttList').textContent.includes('不可单独恢复')),txt:$('#ttList').textContent};`);
  (t7.orphan === 1 && t7.row && /所属书已彻底删除/.test(t7.txt)) ? ok('T7 父书彻底删除后孤行置灰并说明成因') : bad('T7', JSON.stringify(t7));
  await shot('gt-03-quote-orphan');

  /* T7c 习惯/书单/物品在彻底删除弹层里也要看清后果（V1.60 口径回灌 · V1.61 物品追加） */
  const t7c = await ev(`gtSeg='all';ttExitSel();
    var hi=D.trash.findIndex(function(t){return t.k==='habit'}),li=D.trash.findIndex(function(t){return t.k==='list'});
    tpAsk([hi,li]);var s=$('#tpList').textContent;closeSheet('sheetTrashPurge');
    return {habit:/只清定义 · 历史流水保留/.test(s),list:/连成员行一起清 · 书本身保留/.test(s)};`);
  (t7c.habit && t7c.list) ? ok('T7c 习惯只清定义留流水 · 书单连带成员行') : bad('T7c', JSON.stringify(t7c));

  /* T7d V1.61 物品彻底删除：列连带清除的子记录，并明说记账流水保留 */
  const t7d = await ev(`gtSeg='all';ttExitSel();
    var ii=D.trash.findIndex(function(t){return t.k==='item'});
    tpAsk([ii]);var s=$('#tpList').textContent;closeSheet('sheetTrashPurge');
    return {hit:ii>=0,purge:/连带清 成本时间轴 2 条 · 按次用量 0 次 · 关联流水保留/.test(s)};`);
  (t7d.hit && t7d.purge) ? ok('T7d 物品彻底删除后果＝时间轴+用量连带清 · 流水保留') : bad('T7d', JSON.stringify(t7d));

  /* T8 三入口改道：我的页回收站行（与日志管理同级）· 待办页卡 · 笔记抽屉行 */
  const t8 = await ev(`renderNt();setPage('p-sub-recmg');
    return {mine:(setPage('p-profile'),!!document.querySelector('#p-profile [onclick="gtOpen(\\'all\\')"]')),
      pfCnt:$('#pfTrashCnt').textContent,
      todo:!!document.querySelector('#p-todo [onclick="ttOpen()"]')||!!document.querySelector('[onclick="ttOpen()"]'),
      noteRow:!!document.querySelector('.nt-row[onclick*="gtOpen"]')};`);
  (t8.mine && +t8.pfCnt.split(' ')[0] === 8 && t8.todo && t8.noteRow)
    ? ok('T8 三入口全部改道回收站（我的页 8 项计数同源）') : bad('T8', JSON.stringify(t8));
  await shot('gt-04-profile-entry');

  /* T9 保留期改档联动全页读数 */
  const t9 = await ev(`$('#recTrashOpt').textContent='7 天';renderTrash();
    return {keep:$('#ttKeep').textContent,red:[].map.call($$('#ttList .text-rose-500'),function(e){return e.textContent}).join(',')};`);
  (/删除 7 天/.test(t9.keep)) ? ok('T9 保留期档位改档即时联动（期限文案随动）', t9.keep) : bad('T9', JSON.stringify(t9));

  /* T10 旧屏下架：p-sub-todoTrash 不再存在 */
  const t10 = await ev(`return {gone:!document.getElementById('p-sub-todoTrash'),bar:!!document.getElementById('ttSelBar')};`);
  (t10.gone && t10.bar) ? ok('T10 待办旧专屏已下架 · 批量操作条保留为通用') : bad('T10', JSON.stringify(t10));

  /* T11 V1.61 恢复物品：出回收站且提示说清回哪、计费怎么接 */
  const t11 = await ev(`gtSeg='all';ttExitSel();
    var ii=D.trash.findIndex(function(t){return t.k==='item'}),b=D.trash.length;
    ttRestore([ii]);return {n:b-D.trash.length,txt:$('#toast').textContent,left:D.trash.length};`);
  (t11.n === 1 && t11.left === 7 && /已回到物品列表 · 每日计费按删除前状态继续/.test(t11.txt))
    ? ok('T11 恢复物品＝回到物品列表并按删除前状态续计费') : bad('T11', JSON.stringify(t11));
  await shot('gt-05-item-restore');

  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail++ }
  else log('PAGE ERRORS 0');
  try { const ps = spawn('taskkill', ['/pid', 'chrome', '/f'], { stdio: 'ignore' }) } catch (e) { }
  process.exit(fail ? 1 : 0) }
