/* 独立量具：每个分类网格「同一行排了几枚 / 共几枚 / 单枚宽度」
 * 用法：node --experimental-websocket tools/kits/gridproof.js */
const { spawn } = require('child_process');
const path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index-kits.html')).href;
const PORT = Number(process.env.GP_PORT || 9439);
const wait = ms => new Promise(r => setTimeout(r, ms));
const get = u => new Promise(res => { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) });
(async () => {
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/kits/.chrome-gridproof'), '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 40; i++) { data = await get(`http://127.0.0.1:${PORT}/json/version`); if (data) break; await wait(250); }
  const ws = new WebSocket(JSON.parse(data).webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const send = (m, p, s) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method: m, params: p, sessionId: s })); });
  ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { const q = pending.get(m.id); pending.delete(m.id); m.error ? q.rej(new Error(JSON.stringify(m.error))) : q.res(m.result); } };
  await new Promise(r => ws.onopen = r);
  const { targetId } = await send('Target.createTarget', { url: URLF + '#p-tools' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await wait(1800);
  const expr = `(async()=>{
    var out=[];
    document.querySelectorAll('#toolGrid .kgrid').forEach(function(g){
      var rects=[].slice.call(g.children).map(x=>x.getBoundingClientRect());
      if(!rects.length)return;
      var y=rects[0].top, row=rects.filter(r=>Math.abs(r.top-y)<2).length;
      var label=(g.previousElementSibling&&g.previousElementSibling.innerText||'?').split('\\n')[0];
      out.push(label+': '+row+'/'+rects.length+' 枚同行 · 单枚 '+Math.round(rects[0].width)+'px · 行宽 '+Math.round(g.getBoundingClientRect().width)+'px');
    });
    return out;
  })()`;
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, sessionId);
  if (r.exceptionDetails) console.log('EXC', JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description));
  else (r.result.value || []).forEach(l => console.log(l));
  ws.close(); chrome.kill(); process.exit(0);
})().catch(e => { console.log('FAIL ' + e.message); process.exit(1); });
