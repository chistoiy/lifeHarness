/* G1 #2 分享长图包 · 原型回归校验（CDP 无头 Chrome）
 * 断言：① 六处假 toast 站点全部改接预览弹层（旧文案消失）；
 *      ② 预览数字＝页面内独立重算（不调用 scData/yrData 取数，避免自证）；
 *      ③ 改数据后预览即时跟随、撤销回初值（联动不是单向累加）；
 *      ④ 复制文字版有内容、保存图片给真实落盘回执（不再「模拟」）；
 *      ⑤ 预览 DOM 无 class 文本泄漏；⑥ 零 JS 异常；⑦ 逐屏截图。
 * 用法：node tools/g1sharecheck.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.G1S_PORT || 9617);
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
const fileUrl = (p) => url.pathToFileURL(path.resolve(p)).href;
/* 工装注意：原型 <head> 里有 <script src="https://cdn.tailwindcss.com">，
 * 本机无外网时该同步脚本会挂住 HTML 解析（后半文档与内联 JS 都不在），
 * 表现为「所有断言 undefined」。因此每页必须轮询到全局函数就绪再断言。 */
async function ready(names, maxMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < (maxMs || 60000)) {
    const r = await ev(`return {ok:${JSON.stringify(names)}.every(function(n){return typeof window[n]==='function'})};`);
    if (r && r.ok) { await wait(600); return true; }
    await wait(800);
  }
  return false;
}
/* 预览弹层通用检查：容器有内容 + 无 class 文本泄漏 */
const SHEET_CHECK = (sheetId, boxId) => `
  var s=document.getElementById('${sheetId}');
  var box=document.getElementById('${boxId}');
  var leak=/(dark:|rounded-|text-\\[|flex-1|bg-white)/.test(box?box.innerText:'');
  return {open:s&&!s.classList.contains('hidden'), has:!!box&&box.innerHTML.length>200,
    len:box?box.innerText.length:0, leak:leak, txt:(box?box.innerText:'').slice(0,60).replace(/\\s+/g,' ')};`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); process.exit(1); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.g1s-profile'),
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

  /* ================= 一、日子/物品/目标专版 ================= */
  await cmd('Page.navigate', { url: fileUrl('prototype/index-day_aim__goods.html') });
  const r1 = await ready(['scOpen', 'navTo', 'itemSettleOpen']);
  (!r1 ? bad : ok)('⓪a 专版脚本就绪（Tailwind CDN 挂起防护）', r1 ? 'day_aim 全局函数已可用' : '60s 未就绪 · 断言不可信');
  if (!r1) { log('== 工装未就绪，终止 =='); try { chrome.kill(); } catch (e) { } process.exit(1); }

  /* ① 四站按钮改接 + 旧假 toast 文案消失 */
  const a1 = await ev(`
    var st=document.querySelector('#p-itemStats button[onclick^="scOpen"]');
    var body=document.getElementById('settleBody'), dd=document.getElementById('dayDetailBody'), gr=document.getElementById('grBody');
    var old=['统计卡已生成分享长图','决算长图已生成','倒数日分享卡已生成'].filter(function(t){return document.documentElement.innerHTML.indexOf(t)>=0});
    return {stats:!!st, hasSheets:!!document.getElementById('sheetShareCard'), old:old};`);
  (a1.stats && a1.hasSheets && a1.old.length === 0 ? ok : bad)('① 统计/决算/倒数日按钮已接弹层·旧假 toast 文案已摘',
    JSON.stringify(a1));

  /* ② 统计卡预览＝独立重算（谓词按页面口径独立书写：按次均摊件用「每次成本×近30天频次/30」） */
  const c2 = await ev(`
    var bill=D.items.filter(function(x){return x.calc});
    var total=bill.reduce(function(s,x){var pool=x.cost+x.extra-x.res;
      return s+(x.mode==='times'?(pool/x.plan)*((x.used30||0)/30):pool/x.days)},0);
    renderItemStats(); navTo('p-itemStats'); scOpen('stats');
    return {re:total.toFixed(2), big:document.getElementById('scImg').innerText.indexOf(total.toFixed(2))>=0,
      hero:document.getElementById('stTotal').innerText.replace(/\\s+/g,' ').trim()};`);
  const s2 = await ev(SHEET_CHECK('sheetShareCard', 'scImg'));
  (c2.big && !s2.leak && s2.open ? ok : bad)('② 统计卡预览大数字＝独立重算·弹层已开',
    '重算 ' + c2.re + ' · 屏上 ' + c2.hero + ' · 预览含数=' + c2.big + (s2.leak ? ' · 有 class 泄漏' : ''));

  /* ③ 联动：给计费中物品加 1000 成本 → 预览数字跟随；撤销回初值 */
  const c3 = await ev(`
    var i=D.items.findIndex(function(x){return x.calc&&x.mode!=='times'}); D.items[i].cost+=1000; scOpen('stats');
    var bill=D.items.filter(function(x){return x.calc});
    var total=bill.reduce(function(s,x){var pool=x.cost+x.extra-x.res;
      return s+(x.mode==='times'?(pool/x.plan)*((x.used30||0)/30):pool/x.days)},0);
    var mid=total.toFixed(2), midShown=document.getElementById('scImg').innerText.indexOf(mid)>=0;
    D.items[i].cost-=1000; scOpen('stats');
    return {mid:mid, midShown:midShown, back:document.getElementById('scImg').innerText.indexOf(${JSON.stringify(c2.re)})>=0, idx:i};`);
  (c3.midShown && c3.back && c3.mid !== c2.re ? ok : bad)('③ 改物品成本 → 预览即时联动·撤销回初值',
    c2.re + ' → ' + c3.mid + ' → ' + c2.re);

  /* ④ 决算卡：与决算屏同源（净持有/真实日均） */
  const c4 = await ev(`
    var i=D.items.findIndex(function(x){return !x.calc}); curItem=i; itemSettleOpen(i); navTo('p-itemSettle');
    scOpen('settle');
    var it=D.items[i], pool=it.cost+it.extra-it.res;
    var t=(pool/it.days).toFixed(2);
    return {idx:i, name:it.n, day:t, pool:pool,
      inPrev:document.getElementById('scImg').innerText.indexOf(t)>=0,
      onPage:document.getElementById('settleBody').innerText.indexOf(t)>=0,
      named:document.getElementById('scImg').innerText.indexOf(it.n)>=0};`);
  (c4.inPrev && c4.onPage && c4.named ? ok : bad)('④ 决算卡预览＝决算屏真实日均·含物品名', c4.name + ' ¥' + c4.day + '/天');

  /* ⑤ 倒数日卡：大数字＝详情页天数 */
  const c5 = await ev(`
    var i=D.days.findIndex(function(d){return d.d>0}); curDay=i; dayOpen(i);
    scOpen('day');
    var d=D.days[i];
    var txt=document.getElementById('scImg').innerText;
    return {idx:i, t:d.t, n:String(d.d), prev:txt.indexOf(d.t)>=0&&txt.indexOf(String(d.d))>=0,
      page:document.getElementById('dayDetailBody').innerText.indexOf(String(d.d))>=0};`);
  (c5.prev && c5.page ? ok : bad)('⑤ 倒数日卡＝日子名＋剩余天数同源', c5.t + ' · ' + c5.n + ' 天');

  /* ⑥ 复盘卡：归档态出分享钮，数字＝KR 达成 */
  const c6 = await ev(`
    grIdx=0; renderGoalReview();
    var btn=document.getElementById('grBody').innerText.indexOf('分享复盘卡')>=0;
    scOpen('review');
    var rv=D.reviews[0], txt=document.getElementById('scImg').innerText;
    return {btn:btn, p:rv.p, shown:txt.indexOf(rv.p+'%')>=0, kr:txt.indexOf('KR 达成对照')>=0,
      tryTxt:txt.indexOf(rv.y.slice(0,6))>=0};`);
  (c6.btn && c6.shown && c6.kr && c6.tryTxt ? ok : bad)('⑥ 归档复盘出分享钮·预览含达成率与 KPT',
    '达成 ' + c6.p + '% · KR 段 ' + c6.kr);

  /* ⑦ 文字版与落盘回执 */
  const c7 = await ev(`
    scKind='stats';
    var t=scText();
    scSave();
    var toastMsg=document.getElementById('toast').textContent;
    return {len:t.length, head:t.slice(0,24).replace(/\\s+/g,' '), hasNum:/\\d/.test(t), msg:toastMsg};`);
  (c7.len > 40 && c7.hasNum && /分享长图已保存：share\//.test(c7.msg) && !/模拟/.test(c7.msg)
    ? ok : bad)('⑦ 复制文字版有内容·保存图片给落盘路径回执', c7.head + ' … · ' + c7.msg);
  /* 逐卡截图（每卡先 scOpen 重渲染，等 toast 自行退场再拍） */
  for (const [k, nm] of [['stats', 'g1_1_day_stats.png'], ['settle', 'g1_2_day_settle.png'],
    ['day', 'g1_3_day_countdown.png'], ['review', 'g1_4_day_review.png']]) {
    await ev(`scOpen('${k}');return{ok:1};`);
    await wait(2600); await shot(nm);
  }

  /* ================= 二、记账专版（年度分享图） ================= */
  await cmd('Page.navigate', { url: fileUrl('prototype/index-ledger.html') });
  const r2 = await ready(['yrShareOpen', 'navTo', 'renderYearly']);
  (!r2 ? bad : ok)('⓪b 记账专版脚本就绪', r2 ? 'ok' : '60s 未就绪 · 断言不可信');
  if (!r2) { log('== 工装未就绪，终止 =='); try { chrome.kill(); } catch (e) { } process.exit(1); }
  const c8 = await ev(`
    navTo('p-yearly');
    var y=String(yearSel),all=L.txns.filter(function(t){return t.d.slice(0,4)===y&&t.bk===curBook});
    var exp=all.reduce(function(s,t){return s+(t.kind==='expense'?t.amt:t.kind==='refund'?-t.amt:0)},0);
    var inc=all.reduce(function(s,t){return s+(t.kind==='income'?t.amt:0)},0);
    var btn=document.getElementById('yrBody').innerHTML.indexOf("yrShareOpen()")>=0;
    var old=document.documentElement.innerHTML.indexOf('已生成年度分享图（模拟）');
    yrShareOpen();
    var txt=document.getElementById('yshImg').innerText, money=AMT(exp);
    return {btn:btn, old:old>=0, money:money, big:txt.indexOf(money)>=0,
      bars:document.querySelectorAll('#yshImg i').length, rank:txt.indexOf('年度分类')>=0,
      inc:txt.indexOf(AMT(inc))>=0, leak:/(dark:|rounded-|max-w)/.test(txt)};`);
  const s8 = await ev(SHEET_CHECK('sheetYearShare', 'yshImg'));
  (c8.btn && !c8.old && c8.big && c8.inc && c8.rank && c8.bars >= 12 && !c8.leak && s8.open
    ? ok : bad)('⑧ 记账年度分享图：按钮接弹层·支出/收入/12 月柱/分类 Top 全同源',
      c8.money + ' · 柱 ' + c8.bars + ' · 旧文案残留=' + c8.old + (s8.leak || c8.leak ? ' · 有泄漏' : ''));
  const c9 = await ev(`
    var t=yrShareText(); yrShareSave();
    return {len:t.length, head:t.slice(0,20).replace(/\\s+/g,' '), msg:document.getElementById('toast').textContent};`);
  (c9.len > 40 && /分享长图已保存：share\//.test(c9.msg) && !/模拟/.test(c9.msg)
    ? ok : bad)('⑨ 年度文字版与落盘回执', c9.head + ' … · ' + c9.msg);
  await wait(2600); await shot('g1_5_ledger_year.png');

  /* ================= 三、习惯专版（保存图片改真落盘） ================= */
  await cmd('Page.navigate', { url: fileUrl('prototype/index_habitcheck.html') });
  const r3 = await ready(['hbShareSave', 'hbShareOpen']);
  (!r3 ? bad : ok)('⓪c 习惯专版脚本就绪', r3 ? 'ok' : '60s 未就绪 · 断言不可信');
  if (!r3) { log('== 工装未就绪，终止 =='); try { chrome.kill(); } catch (e) { } process.exit(1); }
  const c10 = await ev(`
    var s=document.getElementById('sheetHabitShare');
    var b=s?s.querySelector('button[onclick="hbShareSave()"]'):null;
    var old=s&&s.innerHTML.indexOf('已保存到相册（模拟）')>=0;
    hbShareOpen(); hbShareSave();
    return {btn:!!b, old:old, msg:document.getElementById('toast').textContent,
      img:document.getElementById('hshImg').innerHTML.length>200};`);
  (c10.btn && !c10.old && /分享长图已保存：share\//.test(c10.msg) && c10.img
    ? ok : bad)('⑩ 习惯长图保存图片＝落盘回执（相册模拟已摘）', c10.msg);
  await wait(2600); await shot('g1_6_habit_share.png');

  (errs.length === 0 ? ok : bad)('⑪ 三页运行期零 JS 异常', errs.slice(0, 3).join(' | '));
  log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  try { chrome.kill(); } catch (e) { }
  process.exit(fail ? 1 : 0);
})();
