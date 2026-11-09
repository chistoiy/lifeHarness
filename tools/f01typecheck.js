/* LH-F01 全局字体角色 · 原型校验与截图（CDP 无头 Chrome · 连接骨架照抄 xraycheck.js）
 * 断言：正文＝衬线链（思源宋体/Noto Serif SC）· 标题与底栏＝无衬线链 · 代码＝等宽 · 全部系统回落不随包字体。
 * 用法：node --experimental-websocket tools/f01typecheck.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.F01_PORT || 9613);
const SHOTS = 'prototype/shots';
let pass = 0, fail = 0;
const ok = (n, i) => { pass++; console.log('PASS ' + n + (i ? '  →  ' + i : '')); };
const bad = (n, i) => { fail++; console.log('FAIL ' + n + '  →  ' + (i || '')); };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function get(u) {
  return new Promise((res) => {
    try {
      require('http').get(u, (r) => { let d = ''; r.on('data', (c) => { d += c; }); r.on('end', () => res(d)); })
        .on('error', () => res(''));
    } catch (e) { res(''); }
  });
}
let ws, idc = 0; const pend = new Map();
function cmd(method, params) {
  return new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })); });
}
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())' });
  const r = m.result && m.result.result;
  try { return JSON.parse(r.value); } catch (e) { return { __err: (r && (r.value || r.description)) || 'ev fail' }; }
}
async function shot(name) {
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  const b = m.result && m.result.data;
  if (!b) { bad('截图 ' + name); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, name), Buffer.from(b, 'base64'));
  console.log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}
async function open(file) {
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve(file)).href });
  await wait(2600);
}
function finish(chrome) {
  console.log(`\n结果：${pass} 绿 / ${fail} 红`);
  try { chrome.kill(); } catch (e) {}
  try { ws.close(); } catch (e) {}
  process.exit(fail ? 1 : 0);
}

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return process.exit(1); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.f01-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) {
    const d = await get('http://127.0.0.1:' + PORT + '/json');
    if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) {} }
    await wait(300);
  }
  if (!data) { bad('CDP 起不来'); return process.exit(1); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
  });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Emulation.setDeviceMetricsOverride', { width: 430, height: 900, deviceScaleFactor: 2, mobile: true });

  // 1) 共享面：底栏/标题走无衬线链，三角色变量齐
  await open('prototype/index.html');
  let r = await ev(`var nav=document.querySelector('nav');
    var cs=getComputedStyle(document.documentElement);
    return{nav:nav?getComputedStyle(nav).fontFamily:'no-nav',
      ui:cs.getPropertyValue('--f-ui'),body:cs.getPropertyValue('--f-body'),code:cs.getPropertyValue('--f-code')}`);
  (/Noto Sans SC/.test(r.nav || '') && /Noto Serif SC/.test(r.body || '') && /ui-monospace/.test(r.code || ''))
    ? ok('共享面 LH-F01：底栏＝无衬线链 + 三角色变量在位', String(r.nav).slice(0, 44))
    : bad('共享面角色', JSON.stringify(r));
  await shot('f01_shared_dash.png');

  // 2) 阅读器：正文默认衬线、标题钉无衬线
  await open('prototype/index-bookshelf.html');
  r = await ev(`localStorage.removeItem('lh_reader_bs_v1');brOpen('b13');
    var h=document.querySelector('#brBody .brp-h');
    var b=[].slice.call(document.querySelectorAll('#brBody .brp')).filter(function(x){return !/brp-h/.test(x.className)})[0];
    return{font:brSt('b13').font,h:h?getComputedStyle(h).fontFamily:'',b:b?getComputedStyle(b).fontFamily:''}`);
  (/Noto Serif SC/.test(r.b || '') && /Noto Sans SC/.test(r.h || '') && r.font === 'serif')
    ? ok('阅读器 LH-F01：正文衬线 · 标题无衬线', 'body=' + String(r.b).slice(0, 22) + ' head=' + String(r.h).slice(0, 20))
    : bad('阅读器字体角色', JSON.stringify(r));
  await wait(400); await shot('f01_reader_serif.png');

  // 3) 字体目录九款全部有 CJK/系统等回落（不随包字体也要看得出差别）
  r = await ev(`var miss=[],n=0;for(var k in BR_FONTS){n++;var f=BR_FONTS[k][1];
    if(!/Noto|PingFang|Songti|SimSun|SimHei|KaiTi|FangSong|YaHei|monospace|system-ui/.test(f))miss.push(k)}
    return{miss:miss,n:n}`);
  (r.miss && r.miss.length === 0 && r.n === 9)
    ? ok('字体目录九款全带 CJK/系统回落链', 'n=' + r.n) : bad('字体回落链', JSON.stringify(r));

  finish(chrome);
})();
