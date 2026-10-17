/* 批C 原型截图：面板明细（收起/展开）+ X-Ray 中心精化段（两处同构）。
 * 用法：node --experimental-websocket tools/reader/r3_3_shots.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.F01_PORT || 9617);
const SHOTS = 'prototype/shots';
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function get(u) {
  return new Promise((res) => {
    try { require('http').get(u, (r) => { let d = ''; r.on('data', (c) => { d += c; }); r.on('end', () => res(d)); }).on('error', () => res('')); } catch (e) { res(''); }
  });
}
let ws, idc = 0; const pend = new Map();
function cmd(m, p) { return new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method: m, params: p || {} })); }); }
async function ev(e) { const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + e + '})())' }); try { return JSON.parse(m.result.result.value); } catch (x) { return { __err: 'ev' }; } }
async function shot(n) {
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  const b = m.result && m.result.data; if (!b) { console.log('截图失败 ' + n); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, n), Buffer.from(b, 'base64'));
  console.log('截图 ' + n + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}

(async () => {
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.r33-shot-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get(`http://127.0.0.1:${PORT}/json`); if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) {} } await wait(300); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => { const m = JSON.parse(e2.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Emulation.setDeviceMetricsOverride', { width: 430, height: 900, deviceScaleFactor: 2, mobile: true });

  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href + '?xr=airun' });
  await wait(3200);
  await shot('r33_panel_collapsed.png');
  await ev(`xrAiLogToggle();return 1`); await wait(400);
  await shot('r33_panel_expanded.png');
  await ev(`xrAiLogToggle();navTo('p-xrwords');xrcTab('ai');return 1`); await wait(600);
  await shot('r33_center_ai.png');
  chrome.kill(); ws.close(); process.exit(0);
})();
