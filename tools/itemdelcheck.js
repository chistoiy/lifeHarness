/* V1.61「物品档案删除」原型回归（专版 index-day_aim__goods.html · 详情四钮 · 后果清单 · 取消不删 · 删除出列）
 * 用法：node --experimental-websocket tools/itemdelcheck.js（截图：ID_SHOTS=1，落仓库外）
 * 口径：本文件只断专版侧；回收站第七类（分段/副信息/彻底删除后果/恢复文案）断在 tools/gttrashcheck.js。
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-day_aim__goods.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.ID_PORT || 9611);
const SHOTS = process.env.ID_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/itemdel-shots';
const WIN = process.env.ID_WIN || '430,900';   // 弹层通栏要看得全，视口给高一点
let pass = 0, fail = 0; const errs = [];
const log = m => console.log(m);
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { require('http').get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 260) } }
}
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.itemdel-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=' + WIN, '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('chrome 起来'); return finish() }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* G1 详情页动作行＝四钮，第四钮是删除（玫红描边 + 线性 SVG，不跟前三钮的 emoji） */
  const g1 = await ev(`itemOpen(0);
    var b=document.getElementById('itemDelBtn');
    return {p:curPage,btns:$$('#p-itemDetail .life-btn').length,has:!!b,txt:b?b.textContent.trim():'',
      svg:b?b.querySelectorAll('svg').length:-1,cls:b?b.className:'',
      emoji:b?/[\\u{1F300}-\\u{1FAFF}\\u{2600}-\\u{27BF}]/u.test(b.textContent):true};`);
  (g1.p === 'p-itemDetail' && g1.btns === 4 && g1.has && g1.txt === '删除' && g1.svg === 1
    && /border-rose/.test(g1.cls) && g1.emoji === false)
    ? ok('G1 详情四钮齐 · 第四钮＝线性 SVG 删除（玫红描边一档）') : bad('G1', JSON.stringify(g1));
  await shot('id-01-four-btns');

  /* G2 后果清单三行读数与该档案真实数据一致（时间轴条数 / 按次用量 / 带金额的事件＝关联流水） */
  const g2 = await ev(`openItemDelSheet();
    var it=D.items[curItem],tl=(it.tl||[]).length,us=it.used||0,tx=(it.tl||[]).filter(function(e){return /^¥/.test(String(e.a))}).length;
    return {open:!document.getElementById('sheetItemDel').classList.contains('hidden'),
      name:document.getElementById('idName').textContent,
      txt:document.getElementById('idConseq').textContent,tl:tl,us:us,tx:tx};`);
  (g2.open && g2.name && new RegExp('成本时间轴 ' + g2.tl + ' 条 · 按次用量 ' + g2.us + ' 次').test(g2.txt)
    && new RegExp('关联记账流水 ' + g2.tx + ' 条').test(g2.txt) && /保留在记账/.test(g2.txt) && /30 天/.test(g2.txt))
    ? ok('G2 后果三行读数与档案同源 · 明说流水保留与保留期', g2.name) : bad('G2', JSON.stringify(g2));
  await wait(700);   // 弹层有进场动画，立刻截图会拍到半程
  await shot('id-02-consequences');

  /* G3 取消＝什么都不删（档案仍在、列表计数不变） */
  const g3 = await ev(`var n=D.items.length,t0=D.items[curItem].n;
    document.querySelector('#sheetItemDel [onclick="closeSheet(\\'sheetItemDel\\')"]').click();
    return {closed:document.getElementById('sheetItemDel').classList.contains('hidden'),
      same:D.items.length===n,still:D.items.some(function(i){return i.n===t0}),cnt:document.getElementById('itemHeroCnt').textContent};`);
  (g3.closed && g3.same && g3.still) ? ok('G3 点取消不删任何东西（弹层关 · 档案在册）') : bad('G3', JSON.stringify(g3));

  /* G4 确认删除＝出列 + 回列表 + 提示说清去哪找回 */
  const g4 = await ev(`var n=D.items.length;
    itemOpen(0);openItemDelSheet();itemDelGo();
    return {back:curPage,left:D.items.length,was:n,toast:document.getElementById('toast').textContent};`);
  (g4.back === 'p-items' && g4.left === g4.was - 1 && /已移入回收站/.test(g4.toast) && /我的/.test(g4.toast))
    ? ok('G4 删除后回列表 · 档案出列 · 提示条指路回收站') : bad('G4', JSON.stringify(g4));
  await shot('id-03-after-delete');

  /* G5 任意状态可删：已报废档案的详情页同样给第四钮（拍板③） */
  const g5 = await ev(`var i=D.items.findIndex(function(x){return x.st==='已报废'});
    if(i<0)return {none:true,st:D.items.map(function(x){return x.st}).join(',')};
    itemOpen(i);var b=document.getElementById('itemDelBtn');
    return {i:i,st:D.items[i].st,has:!!b,txt:b?b.textContent.trim():''};`);
  (g5.none || (g5.has && g5.txt === '删除'))
    ? ok('G5 已报废/已回收档案同样给删除钮（任意状态可删）', g5.st || '') : bad('G5', JSON.stringify(g5));

  /* G6 删除＝整条档案从列表出列（演示数据里查不到该名字） */
  const g6 = await ev(`itemOpen(0);var nm=D.items[curItem].n;
    openItemDelSheet();itemDelGo();
    return {nm:nm,still:D.items.some(function(x){return x.n===nm}),left:D.items.length};`);
  g6.still === false ? ok('G6 删除＝整条档案从列表出列', g6.nm) : bad('G6', JSON.stringify(g6));

  /* G7 结构闸：新弹层遮罩点外关自己；两份文件里「六类」旧口径不留存 */
  const g7 = await ev(`var s=document.getElementById('sheetItemDel');
    return {mask:s?s.getAttribute('onclick'):'',hasClose:/closeSheet\\('sheetItemDel'\\)/.test(s?s.getAttribute('onclick'):''),
      six:/六类/.test(document.body.innerHTML)};`);
  const src = fs.readFileSync(FILE, 'utf8');
  (g7.hasClose && src.includes('sheetItemDel') && !/六类/.test(src))
    ? ok('G7 弹层遮罩可关 · 专版无「六类」旧口径残留') : bad('G7', JSON.stringify(g7));

  /* G8 几何闸：四钮在 430 宽下不横向溢出、钮内文字不被截断 */
  const g8 = await ev(`itemOpen(0);
    var g=document.querySelector('#p-itemDetail .grid-cols-4');
    var bs=[].slice.call(g.querySelectorAll('.life-btn'));
    return {ovf:g.scrollWidth-g.clientWidth,
      clipped:bs.filter(function(b){return b.scrollWidth>b.clientWidth+1}).map(function(b){return b.textContent.trim()}),
      widths:bs.map(function(b){return Math.round(b.getBoundingClientRect().width)}),
      delVisible:(document.getElementById('itemDelBtn').getBoundingClientRect().width>0)};`);
  (g8.ovf <= 0 && g8.clipped.length === 0 && g8.delVisible)
    ? ok('G8 四钮行无溢出·无截字（430 宽实测）', '宽度 ' + g8.widths.join('/')) : bad('G8', JSON.stringify(g8));
  await shot('id-04-geometry');

  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail++ }
  else log('PAGE ERRORS 0');
  try { spawn('taskkill', ['/pid', 'chrome', '/f'], { stdio: 'ignore' }) } catch (e) { }
  process.exit(fail ? 1 : 0) }
