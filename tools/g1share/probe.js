/* 探针：确认 CDP 里当前页 URL 与关键符号是否存在（排查工装而非改动） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.G1S_PORT || 9618);
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function get(u) { return new Promise((res) => { try { require('http').get(u, (r) => { let d = ''; r.on('data', (c) => d += c); r.on('end', () => res(d)); }).on('error', () => res(null)); } catch (e) { res(null); } }); }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })); }); }
async function raw(expr) {
  const m = await cmd('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
  return JSON.stringify(m).slice(0, 700);
}
(async () => {
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.g1s-probe'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) { } } await wait(300); }
  console.log('targets:', data.map((t) => t.type + '|' + t.url + '|' + (t.title || '')).join('  ;;  '));
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => { const m = JSON.parse(e2.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve('prototype/index-day_aim__goods.html')).href });
  await wait(3000);
  console.log(await raw('location.href + " | typeof scData=" + (typeof scData) + " | sheet=" + !!document.getElementById("sheetShareCard") + " | title=" + document.title'));
  console.log(await raw('(function(){var b=document.querySelector("#p-itemStats button"); return b?b.outerHTML:"no button"})()'));
  chrome.kill(); process.exit(0);
})();
