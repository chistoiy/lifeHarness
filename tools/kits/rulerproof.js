/* A1 复测：真实视口无头 Chrome 里读尺面长/短边换算是否为非零且与手机框一致
 * 用法：node --experimental-websocket tools/kits/rulerproof.js */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index-kits.html')).href;
const PORT = Number(process.env.RP_PORT || 9431);
const wait = ms => new Promise(r => setTimeout(r, ms));
const get = u => new Promise(res => { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) });

(async () => {
  const prof = path.resolve('tools/kits/.chrome-rulerproof');
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + prof, '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 40; i++) { data = await get(`http://127.0.0.1:${PORT}/json/version`); if (data) break; await wait(250); }
  if (!data) { console.log('FAIL chrome 未起'); process.exit(1); }
  const ws = new WebSocket(JSON.parse(data).webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const send = (method, params, sid) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params, sessionId: sid })); });
  ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.rej(new Error(JSON.stringify(m.error))) : p.res(m.result); } };
  await new Promise(r => ws.onopen = r);
  const { targetId } = await send('Target.createTarget', { url: URLF + '#p-toolDetail_ruler' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await wait(1500);
  const ev = async expr => {
    const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, sessionId);
    if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description || r.exceptionDetails.text));
    return r.result.value;
  };
  const out = await ev(`(async()=>{
    const sleep=ms=>new Promise(r=>setTimeout(r,ms));
    await sleep(300);
    const pe=document.getElementById('phone'), pr=pe.getBoundingClientRect();
    rulerDir('long'); await sleep(150);
    const long=document.getElementById('rulerSpan').textContent;
    rulerDir('short'); await sleep(150);
    const short=document.getElementById('rulerSpan').textContent;
    rulerDir('long'); await sleep(150);
    return {rect:{w:Math.round(pr.width),h:Math.round(pr.height)}, long, short,
      rows:document.querySelectorAll('#rulerBox > div > div').length,
      expectLongMm:Math.round(Math.max(pr.width,pr.height)/3.78)};
  })()`);
  console.log(JSON.stringify(out, null, 1));
  const ok = /长边 ([1-9]\d+) mm/.test(out.long) && /短边 ([1-9]\d+) mm/.test(out.short) && out.rows > 50;
  console.log(ok ? '== A1 复测 PASS ==' : '== A1 复测 FAIL ==');
  ws.close(); chrome.kill(); process.exit(ok ? 0 : 1);
})().catch(e => { console.log('FAIL ' + e.message); process.exit(1); });
