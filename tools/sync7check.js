/* 缺口盘点批 #7 · 同步严格校验入口回归校验（CDP 无头 Chrome）
 * 断言：① 服务配置里有「允许严格校验（MD5）」开关且默认关；
 *      ② 未开启时差异对比点「严格 MD5」不放行（档不变·给出开启路径提示）；
 *      ③ 开启后可选且说明代价；④ 关闭时若正处严格档自动退回并提示；⑤ 零 JS 异常·截图。
 * 用法：node --experimental-websocket tools/sync7check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.S7_PORT || 9621);
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
const TIERS = `
  function on(i){var b=document.querySelectorAll('#s-diff .seg-btn')[i];return b&&b.classList.contains('on')}
  return {a:on(0),b:on(1),c:on(2)};`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); process.exit(1); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.s7-profile'),
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
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve('prototype/index-sync.html')).href });
  await wait(2200);
  const r0 = await ev(`return {ok:typeof tglVerify==='function'&&typeof pickTier==='function'};`);
  (!r0.ok ? bad : ok)('⓪ 同步专版脚本就绪', r0.ok ? 'tglVerify/pickTier 已可用' : '未就绪 · 断言不可信');
  if (!r0.ok) { try { chrome.kill(); } catch (e) { } process.exit(1); }

  /* ① 开关行存在且默认关 */
  const c1 = await ev(`
    openSvcEdit('edit');
    var el=document.getElementById('tglVerify');
    var row=el?el.closest('.row'):null;
    return {has:!!el, on:el?el.classList.contains('on'):null, svcVerify:svcVerify,
      label:row?row.querySelector('.r-t').firstChild.textContent.trim():'',
      sub:row?row.querySelector('.r-s').textContent.trim():''};`);
  (c1.has && !c1.on && c1.svcVerify === false && /允许严格校验/.test(c1.label) && /多一轮下载/.test(c1.sub)
    ? ok : bad)('① 服务配置出「允许严格校验（MD5）」开关·默认关·代价写在副标题', c1.label + ' · ' + c1.sub);
  await shot('s7_1_svc_edit.png');
  /* 开关行在弹层底部：把面板滚到底再拍一张，保证验收能看到 */
  await ev(`var p=document.querySelector('#s-svc-edit .sheet-panel');if(p)p.scrollTop=p.scrollHeight;return{ok:1};`);
  await wait(300); await shot('s7_1b_svc_edit_verify_row.png');

  /* ② 未开启时严格档不放行 */
  await ev(`closeSheet('s-svc-edit'); openSheet('s-diff'); return {ok:1};`);
  const t2a = await ev(TIERS);
  await ev(`document.querySelectorAll('#s-diff .seg-btn')[2].click(); return {ok:1};`);
  const t2 = await ev(TIERS);
  const toast2 = (await ev(`return {t:document.getElementById('toast').textContent};`)).t;
  (t2.c === false && t2.a === true && t2a.a === true && /服务配置/.test(toast2)
    ? ok : bad)('② 开关未开时点「严格 MD5」不放行（仍停在按字节数）', JSON.stringify(t2) + ' · ' + toast2);

  /* ③ 开启后可选 */
  await ev(`openSvcEdit('edit'); document.getElementById('tglVerify').click(); return {ok:1};`);
  const c3 = await ev(`return {on:document.getElementById('tglVerify').classList.contains('on'),
    v:svcVerify, t:document.getElementById('toast').textContent};`);
  await ev(`closeSheet('s-svc-edit'); openSheet('s-diff');
    document.querySelectorAll('#s-diff .seg-btn')[2].click(); return {ok:1};`);
  const t3 = await ev(TIERS);
  const toast3 = (await ev(`return {t:document.getElementById('toast').textContent};`)).t;
  (c3.on && c3.v === true && t3.c === true && /逐文件下载/.test(toast3)
    ? ok : bad)('③ 开启后严格档可选·提示写明逐文件下载的代价', c3.t + ' → ' + toast3);
  await shot('s7_2_tier_strict.png');

  /* ④ 关闭时自动退回 */
  await ev(`openSvcEdit('edit'); document.getElementById('tglVerify').click(); return {ok:1};`);
  const c4 = await ev(`return {v:svcVerify, t:document.getElementById('toast').textContent};`);
  await ev(`closeSheet('s-svc-edit'); return {ok:1};`);
  const t4 = await ev(TIERS);
  (c4.v === false && t4.c === false && t4.a === true && /退回/.test(c4.t)
    ? ok : bad)('④ 关闭开关时严格档自动退回「按字节数」并提示', JSON.stringify(t4) + ' · ' + c4.t);

  (errs.length === 0 ? ok : bad)('⑤ 运行期零 JS 异常', errs.slice(0, 3).join(' | '));
  log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  try { chrome.kill(); } catch (e) { }
  process.exit(fail ? 1 : 0);
})();
