/* 缺口盘点批 #8 · 时间账本分类明细下钻 回归校验（CDP 无头 Chrome）
 * 断言：① 分类行已是真入口（旧「明细列表（模拟）」文案摘除）；
 *      ② 半屏段数/合计＝汇总行显示值＝tsAgg 独立重算（三处同源）；
 *      ③ 切档（周→月）后仍同源；④ 新增跨零点块 → 明细即时跟随且撤销回初值；
 *      ⑤ 无块分类出空态；⑥ 无 class 文本泄漏·零 JS 异常·截图。
 * 用法：node --experimental-websocket tools/ts8check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.TS8_PORT || 9623);
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
/* 页面内独立重算（不调用 tsCatSegs，避免自证） */
const RECALC = (cat) => `
  var P=tsPeriod(tsSpan,tsAnchor),sum=0,n=0;
  blocks.forEach(function(b){if(b.cat!==${JSON.stringify(cat)})return;
    var d0=b.day||TODAY,e=bend(b);var parts=[[d0,Math.min(e,1439)]];if(e>1439)parts.push([d0+1,e-1440]);
    parts.forEach(function(p){var mins=Math.max(0,p[1]-b.s);if(!mins||p[0]<P.from||p[0]>P.to)return;sum+=mins;n++})});
  return {sum:sum,n:n,label:P.label};`;
/* 半屏读数 */
const READ = `
  var st=document.getElementById('tscStat').innerText.replace(/\\s+/g,' ');
  var segs=document.querySelectorAll('#tscList > div').length;
  return {open:!document.getElementById('sheetTsCat').classList.contains('hidden'),
    title:document.getElementById('tscTitle').textContent, period:document.getElementById('tscPeriod').textContent,
    stat:st, segs:segs, empty:document.getElementById('tscList').innerText.indexOf('该时段没有此分类')>=0,
    leak:/dark:|rounded-|flex-1|min-w-0/.test(document.getElementById('sheetTsCat').innerText)};`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); process.exit(1); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.ts8-profile'),
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
  /* Tailwind CDN 同步脚本会挂住 HTML 解析：轮询到模块函数就绪再断言 */
  const t0 = Date.now(); let r0 = { ok: false };
  while (Date.now() - t0 < 60000) {
    r0 = await ev(`return {ok:typeof tsOpenCat==='function'&&typeof tsCatSegs==='function'};`);
    if (r0.ok) break;
    await wait(800);
  }
  if (!r0.ok) { bad('⓪ 脚本就绪（Tailwind CDN 可能仍在加载）'); try { chrome.kill(); } catch (e) { } process.exit(1); }
  ok('⓪ 共享面脚本就绪');
  await wait(600);

  /* ① 分类行改真入口 */
  const c1 = await ev(`
    tsSpan='w';tsAnchor=TODAY;navTo('p-timeStats');renderTimeStats();
    var html=document.getElementById('tsBody').innerHTML;
    var cats=Object.keys(tsAgg(tsPeriod('w',TODAY).from,tsPeriod('w',TODAY).to).byCat);
    var wired=cats.every(function(c){return html.indexOf("tsOpenCat('"+c+"')")>=0});
    return {wired:wired, cats:cats, old:html.indexOf('明细列表（模拟）')>=0};`);
  (c1.wired && !c1.old ? ok : bad)('① 分类时长汇总每行都是真下钻入口', c1.cats.join('、') + ' · 旧模拟文案=' + c1.old);
  const CAT = (await ev(`
    var P=tsPeriod('w',TODAY),A=tsAgg(P.from,P.to);
    var e=Object.entries(A.byCat).sort(function(a,b){return b[1]-a[1]})[0];
    return {c:e[0],n:A.cnt[e[0]],sum:e[1]};`));

  /* ② 半屏三处同源 */
  await ev(`tsOpenCat(${JSON.stringify(CAT.c)});return{ok:1};`);
  const r2 = await ev(READ), rc2 = await ev(RECALC(CAT.c));
  const row2 = await ev(`
    var el=document.querySelector('#tsBody div[onclick*="tsOpenCat"]');
    var rows=[].slice.call(document.querySelectorAll('#tsBody div[onclick*="tsOpenCat"]'));
    var hit=rows.filter(function(d){return d.innerText.indexOf(${JSON.stringify(CAT.c)})===0})[0]||rows[0];
    return {txt:hit.innerText.replace(/\\s+/g,' ')};`);
  const wantN = rc2.n + ' 段', wantSum = await ev(`return {t:tsHM(${rc2.sum})};`);
  (r2.open && r2.title === CAT.c && r2.segs === rc2.n &&
    /^本周 · 9\.\d\d-9\.\d\d$/.test(r2.period) &&
    r2.stat.indexOf(wantN) >= 0 && r2.stat.indexOf(wantSum.t) >= 0 &&
    row2.txt.indexOf(CAT.c) > 0 && row2.txt.indexOf(CAT.n + ' 次') > 0 && row2.txt.indexOf(wantSum.t) > 0 && !r2.leak
    ? ok : bad)('② 明细段数/合计＝汇总行显示＝独立重算（三处同源·周档标签含月前缀）',
      CAT.c + ' · 明细 ' + r2.segs + ' 段 ' + wantSum.t + ' · ' + r2.period);
  await shot('ts8_1_cat_drill.png');

  /* ③ 切档后仍同源 */
  await ev(`tsSpan='m';renderTimeStats();tsOpenCat(${JSON.stringify(CAT.c)});return{ok:1};`);
  const r3 = await ev(READ), rc3 = await ev(RECALC(CAT.c));
  const sum3 = await ev(`return {t:tsHM(${rc3.sum})};`);
  (r3.segs === rc3.n && r3.stat.indexOf(rc3.n + ' 段') >= 0 && r3.stat.indexOf(sum3.t) >= 0 &&
    /本月/.test(r3.period) && rc3.n >= rc2.n
    ? ok : bad)('③ 切到本月档 · 明细与本周口径各自同源',
      '周 ' + rc2.n + ' 段 → 月 ' + rc3.n + ' 段 · ' + sum3.t + ' · ' + r3.period);
  await shot('ts8_2_cat_month.png');

  /* ④ 新增跨零点块 → 即时跟随 · 撤销回初值 */
  const c4 = await ev(`
    blocks.push({day:20,s:1350,e:1500,cat:${JSON.stringify(CAT.c)},note:'校验用跨零点'});
    renderTimeStats();tsOpenCat(${JSON.stringify(CAT.c)});return{ok:1};`);
  const r4 = await ev(READ), rc4 = await ev(RECALC(CAT.c));
  const sum4 = await ev(`return {t:tsHM(${rc4.sum})};`);
  const cross = await ev(`return {has:document.getElementById('tscList').innerText.indexOf('跨零点')>=0};`);
  (r4.segs === rc4.n && rc4.n === rc3.n + 1 && r4.stat.indexOf(sum4.t) >= 0 && cross.has
    ? ok : bad)('④ 新增跨零点块 → 明细 +1 段且标注跨零点',
      rc3.n + ' → ' + rc4.n + ' 段 · ' + sum3.t + ' → ' + sum4.t);
  await ev(`blocks.pop();renderTimeStats();tsOpenCat(${JSON.stringify(CAT.c)});return{ok:1};`);
  const r5 = await ev(READ), rc5 = await ev(RECALC(CAT.c));
  (r5.segs === rc5.n && rc5.n === rc3.n ? ok : bad)('④b 撤销后回到初值（联动非单向累加）', rc5.n + ' 段');

  /* ⑤ 空态：造一个当期无块的分类 */
  const c6 = await ev(`
    tsSpan='d';tsAnchor=1;renderTimeStats();tsOpenCat(${JSON.stringify(CAT.c)});
    return {n:tsCatSegs().length};`);
  const r6 = await ev(READ);
  (r6.empty && r6.segs === 1 ? ok : bad)('⑤ 该时段无块时给空态而非空白', '9 月 1 日 · ' + CAT.c + ' · ' + r6.stat);
  await shot('ts8_3_cat_empty.png');

  (errs.length === 0 ? ok : bad)('⑥ 运行期零 JS 异常', errs.slice(0, 3).join(' | '));
  log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  try { chrome.kill(); } catch (e) { }
  process.exit(fail ? 1 : 0);
})();
