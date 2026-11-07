/* B-1 备份文件管理屏 · 原型无头回归（2026-10-06 · 交棒话术-20261004-备份管理与图片预览批 §2 B-1）
 * 判什么：入口行·列表与合计同源·三档来源角标·行内恢复/删除·删除二次确认（物理删不进回收站·
 *         auto 档回滚资产警示）·删后三处计数随动·选择态与批量删·空态虚线行·次通道常驻。
 * 用法：node --experimental-websocket tools/b1check.js（截图：B1_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index.html')).href;
const PORT = Number(process.env.B1_PORT || 9601);
const SHOTS = process.env.B1_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/b1-shots';
let pass = 0, fail = 0; const errs = [];
const log = m => console.log(m);
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(m, p) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method: m, params: p || {} })) }) }
async function ev(x) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + x + '})())' });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 240) } }
}
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.b1-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('chrome 起服'); return finish() }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 200)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* B1 入口行 + 落屏 + 合计与逐行同源 */
  const b1 = await ev(`setPage('p-sub-data');
    var entry=/备份文件/.test(document.getElementById('p-sub-data').innerText),ec=$('#bkEntryCnt').textContent;
    navTo('p-sub-backup');
    return {entry:entry,ec:ec,page:curPage,title:$('#pageTitle').textContent,rows:document.querySelectorAll('#bkList > div').length,
      cnt:$('#bkCnt').textContent,sum:$('#bkSum').textContent,each:[].map.call($$('#bkList .text-\\\\[13px\\\\]'),function(e){return e.textContent})};`);
  const sumOk = b1.each && b1.each.length === 4 && /合计 59\.3 MB/.test(b1.sum);
  (b1.entry && b1.ec === '4' && b1.page === 'p-sub-backup' && b1.title === '备份文件' && b1.rows === 4 && b1.cnt === '4 包' && sumOk)
    ? ok('B1 入口行在位 · 落屏四行 · 合计与逐行求和同源', b1.cnt + b1.sum) : bad('B1', JSON.stringify(b1));
  await shot('b1-01-list');

  /* B2 三档来源角标（命名＋色区分），且无 emoji */
  const b2 = await ev(`var t=$('#bkList').innerText;
    var cs=[].map.call($$('#bkList b'),function(e){return e.getAttribute('style')||''});
    var EM=[/\\u{1F000}-\\u{1FAFF}/u,/\\u{2600}-\\u{27BF}/u,/\\u{2B00}-\\u{2BFF}/u];
    return {local:/本地导出/.test(t),cloud:/云端下载/.test(t),auto:/恢复前自动/.test(t),
      uniq:new Set(cs).size,emoji:EM.some(function(r){return r.test(t)})};`);
  (b2.local && b2.cloud && b2.auto && b2.uniq >= 3 && !b2.emoji)
    ? ok('B2 三档来源角标齐（本地导出／云端下载／恢复前自动）· 色值互异 · 零 emoji') : bad('B2', JSON.stringify(b2));

  /* B3 行内恢复＝送进既有校验链（口令→二次确认→整库替换，当前库先存 safety 快照） */
  const b3 = await ev(`bkRestore(1);return {t:$('#toast').textContent};`);
  (/口令/.test(b3.t) && /整库替换/.test(b3.t) && /safety/.test(b3.t))
    ? ok('B3 恢复走既有校验链口径（口令·二次确认·整库替换·先存 safety 快照）', b3.t.slice(0, 46)) : bad('B3', JSON.stringify(b3));

  /* B4 删除二次确认：物理删不进回收站；auto 档另出回滚资产警示，非 auto 档不出 */
  const b4 = await ev(`bkAskDel(0);var a={sum:$('#bkDelSum').innerText,warnHidden:$('#bkDelWarn').classList.contains('hidden'),open:$('#sheetBkDel').classList.contains('sheet-open')};
    closeSheet('sheetBkDel');bkAskDel(2);
    var b={sum:$('#bkDelSum').innerText,warnHidden:$('#bkDelWarn').classList.contains('hidden'),warn:$('#bkDelWarn').textContent};
    return {a:a,b:b};`);
  (b4.a.open && /物理删除 · 不进回收站 · 不可恢复/.test(b4.a.sum) && b4.a.warnHidden &&
    !b4.b.warnHidden && /回滚资产/.test(b4.b.warn))
    ? ok('B4 删除必二次确认（物理删·不进回收站）· auto 档加回滚资产警示、普通档不加') : bad('B4', JSON.stringify(b4));
  await shot('b4-del-confirm');

  /* B5 确认删除后：行数·合计·入口计数三处随动，toast 报释放量（期望值由页面现值算出，不写死） */
  const b5 = await ev(`var n0=BK_FILES.length,b0=BK_FILES.reduce((t,x)=>t+x.b,0),gone=BK_FILES[bkPend[0]].b;
    bkDelGo();return {rows:document.querySelectorAll('#bkList > div').length,cnt:$('#bkCnt').textContent,
    sum:$('#bkSum').textContent,ec:$('#bkEntryCnt').textContent,toast:$('#toast').textContent,
    wantRows:n0-1,wantSum:' · 合计 '+((b0-gone)/1048576).toFixed(1)+' MB',wantRel:((gone)/1048576).toFixed(1)};`);
  (b5.rows === b5.wantRows && b5.cnt === b5.wantRows + ' 包' && b5.sum === b5.wantSum && b5.ec === String(b5.wantRows)
    && new RegExp('已彻底删除 1 个备份文件 · ' + b5.wantRel + ' MB').test(b5.toast))
    ? ok('B5 删除后行数／屏头合计／入口计数三处随动 · toast 报释放 MB', b5.cnt + b5.sum + ' · 入口 ' + b5.ec) : bad('B5', JSON.stringify(b5));

  /* B6 选择态：出勾选圈·收行内钮·头部「删除 N 项」·全选批量删到空态虚线行（N 由当时行数算） */
  const b6 = await ev(`var n0=BK_FILES.length;bkToggleSel();var m1={pick:$('#bkPickBtn').textContent,rings:document.querySelectorAll('#bkList .rounded-full.border-2').length,rowBtns:document.querySelectorAll('#bkList button').length};
    bkSelAll();var n=bkSel.size;var delBtn=$('#bkDelBtn').textContent;bkAskDelBatch();var asked=!$('#sheetBkDel').classList.contains('hidden');bkDelGo();
    return {n0:n0,m1:m1,n:n,delBtn:delBtn,asked:asked,empty:$('#bkList').innerText.trim(),dash:/border-dashed/.test($('#bkList').innerHTML),
      cnt:$('#bkCnt').textContent,ec:$('#bkEntryCnt').textContent,mode:bkMode};`);
  (b6.m1.pick === '取消' && b6.m1.rings === b6.n0 && b6.m1.rowBtns === 0 && b6.n === b6.n0 && b6.delBtn === '删除 ' + b6.n0 + ' 项' && b6.asked &&
    b6.empty === '暂无备份文件' && b6.dash && b6.cnt === '0 包' && b6.ec === '0' && b6.mode === false)
    ? ok('B6 选择态→全选→批量删到空态（虚线行定式）· 计数随动 · 自动退出选择态') : bad('B6', JSON.stringify(b6));
  await shot('b6-empty');

  /* B7 次通道「从其他位置选择」空态下仍在位（主通道断了不能连带把次通道也藏掉） */
  const b7 = await ev(`return {btn:/从其他位置选择/.test($('#p-sub-backup').innerText)};`);
  b7.btn ? ok('B7 次通道按钮常驻（空态不藏）') : bad('B7', JSON.stringify(b7));

  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail = 1 }
  else log('PAGE ERRORS 0');
  try { if (ws) ws.close() } catch (e) { }
  process.exit(fail ? 1 : 0) }
