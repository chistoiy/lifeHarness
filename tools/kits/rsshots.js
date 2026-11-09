/* 验收轮2 取证截图：尺子全屏舞台（含游标/零点）+ 紧凑工具网格
 * 用法：node --experimental-websocket tools/kits/rsshots.js */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index-kits.html')).href;
const PORT = Number(process.env.RS_PORT || 9435);
const DIR = 'prototype/shots/kits';
const wait = ms => new Promise(r => setTimeout(r, ms));
const get = u => new Promise(res => { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) });
(async () => {
  fs.mkdirSync(DIR, { recursive: true });
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/kits/.chrome-rsshots'), '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 40; i++) { data = await get(`http://127.0.0.1:${PORT}/json/version`); if (data) break; await wait(250); }
  const ws = new WebSocket(JSON.parse(data).webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const send = (m, p, s) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method: m, params: p, sessionId: s })); });
  ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { const q = pending.get(m.id); pending.delete(m.id); m.error ? q.rej(new Error(JSON.stringify(m.error))) : q.res(m.result); } };
  await new Promise(r => ws.onopen = r);
  const { targetId } = await send('Target.createTarget', { url: URLF + (process.env.RS_HASH||'#p-tools'), background: false });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await send('Emulation.setDeviceMetricsOverride', { width: 400, height: 840, deviceScaleFactor: 2, mobile: true }, sessionId);
  await wait(2600);
  const evl = async expr => { const r = await send('Runtime.evaluate', { expression: '(async()=>{const sleep=ms=>new Promise(r=>setTimeout(r,ms));' + expr + '})()', returnByValue: true, awaitPromise: true }, sessionId);
    if (r.exceptionDetails) return 'EXC ' + JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description || r.exceptionDetails.text); return r.result.value; };
  const shot = async name => { const { data: b64 } = await send('Page.captureScreenshot', { format: 'png' }, sessionId); fs.writeFileSync(path.join(DIR, name), Buffer.from(b64, 'base64')); return name; };
  console.log(await evl(`setPage('p-tools');await sleep(400);return document.title`));
  console.log('shot', await shot('r2-tools-compact.png'));
  console.log(await evl(`openTool('ruler');await sleep(500);var g=rsGeom();rsSetFromX(g.left+g.ppmm*143,'cur');rsSetFromX(g.left+g.ppmm*20,'zero');await sleep(150);return document.getElementById('rulerSpan').textContent+' | '+document.getElementById('rsBig').textContent`));
  console.log('shot', await shot('r2-ruler-stage.png'));
  console.log(await evl(`rulerFsClose();setPage('p-kitsPlg');await sleep(300);return [...document.querySelectorAll('#p-kitsPlg .row-title')].map(x=>x.textContent).join(',')`));
  console.log('shot', await shot('r2-plg.png'));
  console.log(await evl(`setPage('p-profile');await sleep(300);return {rows:[...document.querySelectorAll('#p-profile button')].map(b=>b.innerText.split('\\n')[0]).filter(Boolean).join('|'),hasPlg:/插件中心/.test(document.getElementById('p-profile').innerText)}`));
  console.log('shot', await shot('r2-profile.png'));
  console.log(await evl(`setPage('p-tools');KITS.pset={scan:true,wifi:false,bakPlg:true,bakFoot:true};kitSave();renderKitPset();openSheet('sheetKitSet');await sleep(250);return {rows:document.querySelectorAll('#kitSetRows [data-pset]').length,cls:[...document.querySelectorAll('#kitSetRows [data-pset]')].map(x=>x.dataset.pset+':'+x.className).join(' | '),pset:JSON.stringify(kitPset()),raw:(document.getElementById('kitSetRows').innerHTML||'').slice(0,220)}`));
  console.log('shot', await shot('r3-kitset-sheet.png'));
  console.log(await evl(`closeSheet('sheetKitSet');setPage('p-kitsPlg');await sleep(250);return document.querySelectorAll('#kitPsetRows [data-pset]').length+' 行（插件中心·拓展设置）'`));
  console.log('shot', await shot('r3-plgset-rows.png'));
  console.log(await evl(`return {navPool:NAV_MODS.map(m=>m[1]).join(','),nav:document.getElementById('navBar').innerText.replace(/\\s+/g,'/')}`));
  ws.close(); chrome.kill(); console.log('done'); process.exit(0);
})().catch(e => { console.log('FAIL ' + e.message); process.exit(1); });
