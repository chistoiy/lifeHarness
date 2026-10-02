/* 批C 诊断探针：?xr=airun 演示态为什么没生成逐批明细。
 * 打印 xrAiDemo 执行前后的关键事实 + 页面异常（连接骨架照抄 f01typecheck.js）。
 * 用法：node --experimental-websocket tools/reader/r3_3_probe.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.F01_PORT || 9615);
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function get(u) {
  return new Promise((res) => {
    try {
      require('http').get(u, (r) => { let d = ''; r.on('data', (c) => { d += c; }); r.on('end', () => res(d)); }).on('error', () => res(''));
    } catch (e) { res(''); }
  });
}
let ws, idc = 0; const pend = new Map(); const thrown = [];
function cmd(m, p) { return new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method: m, params: p || {} })); }); }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())' });
  const r = m.result && m.result.result;
  try { return JSON.parse(r.value); } catch (e) { return { __err: (r && (r.value || r.description)) || 'ev fail' }; }
}

(async () => {
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.r33-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get(`http://127.0.0.1:${PORT}/json`); if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) {} } await wait(300); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      thrown.push(((d.exception || {}).description || d.text || '').split('\n')[0]);
    }
  });
  await cmd('Runtime.enable'); await cmd('Page.enable');

  const f = 'prototype/index-bookshelf.html?xr=airun';
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href + '?xr=airun' });
  await wait(3200);
  console.log('深链后        ', await ev(`return{st:XRAI.st,b:XRAI.b,n:XRAI.n,log:XRAI.log.length}`));
  console.log('再调 demo     ', await ev(`xrAiDemo('run');return{st:XRAI.st,b:XRAI.b,n:XRAI.n,log:XRAI.log.length}`));
  console.log('手搓一行      ', await ev(`return{row:JSON.stringify(xrAiSimRow(2,8)),typeofRow:typeof xrAiSimRow}`));
  console.log('bar 里有无明细', await ev(`var b=document.getElementById('xrAiBar');return{hasSum:!!b.querySelector('#xrAiSum'),rows:b.querySelectorAll('[id^=xrAiRow-]').length,html:b.innerHTML.length}`));
  console.log('页面异常      ', thrown.slice(0, 4));
  chrome.kill(); ws.close(); process.exit(0);
})();
