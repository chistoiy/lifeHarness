/* 一次性探针：在真实视口无头 Chrome 里读尺子全屏舞台与网格状态
 * 用法：node --experimental-websocket tools/kits/rsprobe.js */
const { spawn } = require('child_process');
const path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index-kits.html')).href;
const PORT = Number(process.env.RS_PORT || 9433);
const wait = ms => new Promise(r => setTimeout(r, ms));
const get = u => new Promise(res => { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) });
(async () => {
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/kits/.chrome-rsprobe'), '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 40; i++) { data = await get(`http://127.0.0.1:${PORT}/json/version`); if (data) break; await wait(250); }
  const ws = new WebSocket(JSON.parse(data).webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const send = (m, p, s) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method: m, params: p, sessionId: s })); });
  ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { const q = pending.get(m.id); pending.delete(m.id); m.error ? q.rej(new Error(JSON.stringify(m.error))) : q.res(m.result); } };
  await new Promise(r => ws.onopen = r);
  const { targetId } = await send('Target.createTarget', { url: URLF + '#p-tools' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await wait(1600);
  const evl = async expr => { const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, sessionId);
    if (r.exceptionDetails) return 'EXC ' + JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description || r.exceptionDetails.text);
    return r.result.value; };
  const out = await evl(`(async()=>{const sleep=ms=>new Promise(r=>setTimeout(r,ms));
    openTool('ruler'); await sleep(300);    const g=rsGeom();
    return {geom:g, cursorLeft:document.getElementById('rsCursor').style.left, zeroLeft:document.getElementById('rsZero').style.left,
      majors:document.querySelectorAll('#rsScale b').length, ticks:document.querySelectorAll('#rsScale i').length,
      span:document.getElementById('rulerSpan').textContent, big:document.getElementById('rsBig').textContent,
      gridCls:(document.querySelector('#toolGrid .grid')||{}).className,unit:KITS.rulerUnit,dir:KITS.rulerDir,cal:KITS.cal,rsCur:KITS.rsCur,rsZero:KITS.rsZero,stageDisp:getComputedStyle(document.getElementById('rulerStage')).display,tapeW:document.getElementById('rsTape').getBoundingClientRect().width,
      tiles:document.querySelectorAll('#toolGrid .kit-tile').length};
  })()`);
  console.log(JSON.stringify(out, null, 1));
  ws.close(); chrome.kill(); process.exit(0);
})().catch(e => { console.log('FAIL ' + e.message); process.exit(1); });
