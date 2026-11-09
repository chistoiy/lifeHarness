/* 缺口盘点批 #3（原型侧）· 记账设置三枚开关去「（演示）」并写明真行为 的回归校验
 * 断言：① 三行不再出现「演示」字样·超支/小结两行带真行为副标题；
 *      ② 两枚开关的提示条随开/关两态变化（关→说明不再提醒）；
 *      ③ 预算月起始日切 15 日的提示条改口径；④ 零 JS 异常·截图。
 * 用法：node --experimental-websocket tools/ledger3check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.L3_PORT || 9625);
const SHOTS = 'prototype/shots';
let pass = 0, fail = 0; const errs = [];
const ok = (n, i) => { pass++; console.log('PASS ' + n + (i ? '  →  ' + i : '')); };
const bad = (n, i) => { fail++; console.log('FAIL ' + n + '  →  ' + (i || '')); };
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
  console.log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}
/* 卡片首行＝标题，次行＝副标题（renderLset 里 row(t,ctrl,sub) 的三件套） */
const FIND = (t) => `[].slice.call(document.querySelectorAll('#lsetBody > div'))
  .filter(function(c){return c.innerText.trim().split('\\n')[0]===${JSON.stringify(t)}})[0]`;
const ROW = (t) => `
  var hit=${FIND(t)};
  if(!hit)return {miss:true};
  var ls=hit.innerText.trim().split('\\n'), tg=hit.querySelector('.toggle');
  return {sub:ls.length>1?ls[1]:'', on:tg?tg.classList.contains('on'):null,
    demo:hit.innerText.indexOf('演示')>=0};`;
const CLICK = (t) => `
  var hit=${FIND(t)}; hit.querySelector('.toggle').click();
  return {on:hit.querySelector('.toggle').classList.contains('on'),
    t:document.getElementById('toast').textContent};`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); process.exit(1); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.l3-profile'),
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
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve('prototype/index-ledger.html')).href });
  const t0 = Date.now(); let ready = false;
  while (Date.now() - t0 < 60000) {
    const r = await ev(`renderLset();return {ok:!!document.getElementById('lsetBody')&&document.getElementById('lsetBody').children.length>0};`);
    if (r.ok) { ready = true; break; }
    await wait(800);
  }
  if (!ready) { bad('⓪ 记账专版脚本就绪（Tailwind CDN 可能仍在加载）'); try { chrome.kill(); } catch (e) { } process.exit(1); }
  ok('⓪ 记账专版脚本就绪');
  await ev(`navTo('p-lset');renderLset();return{ok:1};`); await wait(400);

  /* ① 三行文案 */
  const r1 = await ev(ROW('预算超支提醒')), r2 = await ev(ROW('月度小结推送')), r3 = await ev(ROW('预算月起始日'));
  const whole = await ev(`
    var rows=[].slice.call(document.querySelectorAll('#lsetBody > div'));
    var demoRows=rows.filter(function(c){return c.innerText.indexOf('演示')>=0})
      .map(function(c){return c.innerText.trim().split('\\n')[0]});
    return {demoRows:demoRows};`);
  (!r1.miss && !r2.miss && !r3.miss && r1.on === true && /80% \/ 100%/.test(r1.sub) && /免打扰/.test(r1.sub) &&
    r2.on === false && /每月 1 日 09:00/.test(r2.sub) && /重排/.test(r3.sub) &&
    !r1.demo && !r2.demo && !r3.demo && JSON.stringify(whole.demoRows) === JSON.stringify(['重置演示数据'])
    ? ok : bad)('① 三行去「（演示）」·超支/小结带真行为副标题·残留仅重置演示数据行',
      '超支: ' + r1.sub + ' · 小结: ' + r2.sub + ' · 起始日: ' + r3.sub + ' · 仍含演示的行=' + JSON.stringify(whole.demoRows));
  await shot('l3_1_set_rows.png');

  /* ② 开关两态提示条（默认开 → 关 → 开） */
  const s1 = await ev(CLICK('预算超支提醒'));
  const s2 = await ev(CLICK('预算超支提醒'));
  (!s1.on && /已关闭/.test(s1.t) && s2.on && /已开启/.test(s2.t) && /80%/.test(s2.t)
    ? ok : bad)('② 超支提醒提示条随两态变化', s1.t + ' ⇄ ' + s2.t);
  const s3 = await ev(CLICK('月度小结推送'));
  const s4 = await ev(CLICK('月度小结推送'));
  (s3.on && /已开启 · 每月 1 日 09:00/.test(s3.t) && !s4.on && /已关闭/.test(s4.t)
    ? ok : bad)('②b 月度小结提示条随两态变化', s3.t + ' ⇄ ' + s4.t);

  /* ③ 预算月起始日切 15 日 */
  const s5 = await ev(`
    var hit=${FIND('预算月起始日')};
    hit.querySelectorAll('button')[1].click();
    return {t:document.getElementById('toast').textContent, ms:L.set.monthStart};`);
  (s5.ms === 15 && /每月 15 日起算/.test(s5.t) && !/演示/.test(s5.t)
    ? ok : bad)('③ 起始日切 15 日 · 提示条改口径', s5.t);

  (errs.length === 0 ? ok : bad)('④ 运行期零 JS 异常', errs.slice(0, 3).join(' | '));
  console.log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  try { chrome.kill(); } catch (e) { }
  process.exit(fail ? 1 : 0);
})();
