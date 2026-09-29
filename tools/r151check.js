/* R15-1/V1.56 专项校验（CDP 无头 Chrome）：记账专版「导入记录 + 整批撤销」是否真的可用
 * 断言：① 向导跑完出第 5 屏完成态，摘要数字与页面内独立计数一致；
 *      ② 完成页「撤销本批」→ 二次确认半屏，写明删除条数，账户回收勾选默认关；
 *      ③ 确认后：该批流水整批消失·其它批不受影响·本批新建账户按档位回收·toast 如实回报；
 *      ④ 批次列表只渲染真实批次，且**仅最近一批**有撤销钮（拍板口径）；
 *      ⑤ 撤掉最新批后，次新批成为最新 → 撤销钮随之下移（不是写死第一行）；
 *      ⑥ 「已导入的账单列表（模拟）」死 toast 与「支持整批撤销」空文案均已归零；
 *      ⑦ 零 JS 异常 + 宽度不塌 + 三张取证截图。
 * 用法：node --experimental-websocket tools/r151check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.R151_PORT || 9618);
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
  try { return JSON.parse(r.value); } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 200) }; }
}
async function shot(name) {
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  const b = m.result && m.result.data; if (!b) { bad('截图 ' + name); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, name), Buffer.from(b, 'base64'));
  log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}

/* 走一遍向导（直调既有函数，与真人点按同一条主路） */
const RUN_WIZARD = (plat) => `
  billGo();biPickSrc('${plat}');biStart();biChooseFile();biAcctNext();
  var total=biRows.length, drop=biRows.slice(-3).map(function(r){return r.k});
  drop.forEach(function(k){biSel.delete(k);});           // 末 3 条不勾 → skip=3
  var before=L.txns.length, acctsBefore=L.accounts.length;
  biCommit();
  return {biN:biN, total:total, skip:drop.length, written:total-drop.length,
    added:L.txns.length-before, acctsAdded:L.accounts.length-acctsBefore,
    doneVisible:!document.getElementById('biDone').classList.contains('hidden'),
    sum:document.getElementById('biDoneSum').innerText,
    batch:BI_BATCH[BI_BATCH.length-1], title:document.getElementById('pageTitle').textContent};`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish(); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.r151-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) { } } await wait(300); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 160)); });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: require('url').pathToFileURL(path.resolve('prototype/index-ledger.html')).href });
  await wait(2800);

  /* ① 向导完成 → 第 5 屏 + 摘要数字与独立计数一致 */
  const w1 = await ev(RUN_WIZARD('微信'));
  const d1 = [];
  if (w1.biN !== 5) d1.push('biN 期望 5 实得 ' + w1.biN);
  if (!w1.doneVisible) d1.push('屏5 biDone 未显示');
  if (String(w1.written) !== String(w1.added)) d1.push('写入数 ' + w1.written + ' ≠ 实际新增流水 ' + w1.added);
  if (!new RegExp(w1.written + ' 条').test(w1.sum)) d1.push('完成屏摘要未写写入条数：' + w1.sum);
  if (!/未勾选 3 条不导入/.test(w1.sum)) d1.push('完成屏摘要未写未勾选数：' + w1.sum);
  if (w1.title !== '导入完成') d1.push('顶栏标题期望「导入完成」实得「' + w1.title + '」');
  (d1.length === 0 ? ok : bad)('① 向导第 5 屏完成态·摘要＝独立计数', d1.length ? d1.join(' | ') : w1.sum.replace(/\n/g, ' / '));
  await wait(450); await shot('r151_1_done.png');

  /* ② 完成页「撤销本批」→ 二次确认半屏·默认不勾回收 */
  const c2 = await ev(`biAskUndo(biLatest(),'done');
    var sh=document.getElementById('sheetLedgerUndo');
    return {open:sh.classList.contains('sheet-open'), sum:document.getElementById('buSum').innerText,
      reclaimOn:document.querySelector('#sheetLedgerUndo .toggle').classList.contains('on'),
      rowHidden:document.getElementById('buRow').classList.contains('hidden'),
      note:document.getElementById('buAcctNote').textContent};`);
  const d2 = [];
  if (!c2.open) d2.push('确认弹层未打开');
  if (!new RegExp('将删除.*' + w1.written + ' 条流水').test(c2.sum)) d2.push('确认弹层未写明删除条数：' + c2.sum);
  if (c2.reclaimOn) d2.push('账户回收勾选项默认应为关（拍板口径）');
  if (w1.acctsAdded > 0 && c2.rowHidden) d2.push('本批新建了 ' + w1.acctsAdded + ' 个账户却隐藏了回收行');
  (d2.length === 0 ? ok : bad)('② 二次确认写明删除条数·回收默认关', d2.length ? d2.join(' | ') : c2.sum.replace(/\n/g, ' / ') + ' · ' + c2.note);
  await wait(450); await shot('r151_2_confirm.png');

  /* ③ 勾选回收并确认 → 流水整批消失·账户按档回收·批次出列 */
  const firstId = w1.batch.id, firstAccts = w1.batch.made.map((m) => m.id);
  const c3 = await ev(`biUndoTog();
    var AC=${JSON.stringify(firstAccts)};
    var beforeTx=L.txns.length, beforeAc=L.accounts.length;
    biUndoGo();
    return {toast:document.getElementById('toast').textContent,
      left:BI_BATCH.length, stillTx:L.txns.filter(function(t){return t.bat===${firstId}}).length,
      txDelta:L.txns.length-beforeTx, acctGone:AC.filter(function(id){return !L.accounts.some(function(a){return a.id===id})}).length,
      acctDelta:L.accounts.length-beforeAc, biN:biN, undoSheet:document.getElementById('sheetLedgerUndo').classList.contains('sheet-open')};`);
  const d3 = [];
  if (c3.left !== 0) d3.push('批次未出列，BI_BATCH 仍 ' + c3.left + ' 条');
  if (c3.stillTx !== 0) d3.push('撤销后该批仍有 ' + c3.stillTx + ' 条流水');
  if (c3.txDelta !== -w1.written) d3.push('流水减少 ' + c3.txDelta + ' ≠ -' + w1.written);
  if (c3.acctDelta !== -w1.acctsAdded) d3.push('账户减少 ' + c3.acctDelta + ' ≠ -' + w1.acctsAdded);
  if (!/已撤销批次/.test(c3.toast)) d3.push('撤销后无如实回报：' + c3.toast);
  if (c3.biN !== 1) d3.push('从完成页撤销后应回导入首页，实得 biN=' + c3.biN);
  if (c3.undoSheet) d3.push('确认弹层未关闭');
  (d3.length === 0 ? ok : bad)('③ 整批撤销·流水与账户同步回收', d3.length ? d3.join(' | ') : c3.toast);

  /* ④ 连导两批 → 列表两行·仅最近一批有撤销钮 */
  await ev(RUN_WIZARD('微信'));
  await ev(RUN_WIZARD('支付宝'));
  const secondId = (await ev(`return {id:BI_BATCH[BI_BATCH.length-1].id};`)).id;
  await ev(`biBackHome();biOpenBatches();return{ok:1};`);
  const l4 = await ev(`var rows=document.getElementById('biBatList').children;
    return {n:rows.length, btns:[].map.call(rows,function(r){return r.querySelector('button')?r.querySelector('button').textContent:''}),
      txt:rows.length?rows[0].innerText.replace(/\\n/g,' | '):'',
      sheet:document.getElementById('sheetLedgerBatches').classList.contains('sheet-open'),
      cnt:document.getElementById('biBatCnt').textContent, batches:BI_BATCH.length};`);
  const d4 = [];
  if (!l4.sheet) d4.push('导入记录半屏未打开');
  if (l4.n !== 2) d4.push('列表期望 2 行（批1 已撤只剩批2？请核）实得 ' + l4.n);
  if (l4.btns.filter((x) => x === '撤销').length !== 1) d4.push('撤销钮应只有一枚（仅最近一批），实得 ' + JSON.stringify(l4.btns));
  if (l4.btns[0] !== '撤销') d4.push('撤销钮应挂在最新一行（列表倒序首行），实得「' + l4.btns[0] + '」');
  if (l4.cnt !== l4.batches + ' 批') d4.push('首页批次计数「' + l4.cnt + '」≠ ' + l4.batches + ' 批');
  (d4.length === 0 ? ok : bad)('④ 批次列表两行·仅最近一批可撤', d4.length ? d4.join(' | ') : l4.txt);
  await wait(450); await shot('r151_3_batches.png');

  /* ⑤ 撤掉最新批 → 次新批成为最新·撤销钮下移（先补一批再撤最新） */
  await ev(`closeSheet('sheetLedgerBatches');return{ok:1};`);
  await ev(RUN_WIZARD('通用'));
  const thirdId = (await ev(`return {id:BI_BATCH[BI_BATCH.length-1].id};`)).id;
  const l5 = await ev(`biOpenBatches();
    var rows=document.getElementById('biBatList').children;
    return {n:rows.length,btns:[].map.call(rows,function(r){return r.querySelector('button')?r.querySelector('button').textContent:''})};`);
  const c5 = await ev(`biAskUndo(${thirdId},'list');biUndoGo();
    var rows=document.getElementById('biBatList').children;
    return {batches:BI_BATCH.length,n:rows.length,
      btns:[].map.call(rows,function(r){return r.querySelector('button')?r.querySelector('button').textContent:''}),
      otherTx:L.txns.filter(function(t){return t.bat===${secondId}}).length};`);
  const d5 = [];
  if (l5.btns.filter((x) => x === '撤销').length !== 1) d5.push('三批时撤销钮应只 1 枚，实得 ' + JSON.stringify(l5.btns));
  if (c5.batches !== 2) d5.push('撤销后应剩 2 批，实得 ' + c5.batches);
  if (c5.btns.filter((x) => x === '撤销').length !== 1) d5.push('撤销后仍应恰好 1 枚撤销钮，实得 ' + JSON.stringify(c5.btns));
  if (c5.otherTx <= 0) d5.push('撤最新批不应影响其它批次流水（批 ' + secondId + ' 剩 ' + c5.otherTx + ' 条）');
  (d5.length === 0 ? ok : bad)('⑤ 撤销钮始终挂在最近一批·其它批不受牵连', d5.length ? d5.join(' | ') : '剩 ' + c5.batches + ' 批 · 批' + secondId + ' 流水 ' + c5.otherTx + ' 条在');

  /* ⑥ 死 toast 与空承诺文案归零 */
  const src = fs.readFileSync('prototype/index-ledger.html', 'utf8');
  const d6 = [];
  if (/已导入的账单列表（模拟）/.test(src)) d6.push('「已导入的账单列表（模拟）」死 toast 仍在');
  if (/支持整批撤销/.test(src)) d6.push('「支持整批撤销」空文案仍在（应为可点动作）');
  if (!/function biUndoGo\(/.test(src)) d6.push('撤销实现缺失');
  if (/👋|🖐/.test(src.slice(src.indexOf('function renderBiBatches'), src.indexOf('function renderBiBatches') + 4000))) d6.push('新增区域出现教学 emoji');
  (d6.length === 0 ? ok : bad)('⑥ 空承诺文案归零', d6.length ? d6.join(' | ') : '承诺已变成可点动作');

  /* ⑦ 宽度不塌 + 零异常 */
  const w7 = await ev(`return {w:Math.round(document.getElementById('p-billImport').getBoundingClientRect().width)};`);
  (w7.w > 350 ? ok : bad)('⑦ 导入屏激活宽度不塌', 'w=' + w7.w);
  (errs.length === 0 ? ok : bad)('⑧ 运行期零 JS 异常', errs.join(' | '));
  finish(chrome);
})();

function finish(chrome) {
  log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  try { if (chrome) chrome.kill(); } catch (e) { }
  process.exit(fail ? 1 : 0);
}
