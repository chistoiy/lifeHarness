/* 深色模式三档（外观屏）原型门回归 · 2026-10-07
 * 断言：① 三枚分段在册且默认为「跟随系统」 ② 点深色→整页 dark＋副注锁定 ③ 点浅色→摘 dark
 *      ④ 点回跟随系统→按系统态落位 ⑤ 强制深色主题（赛博朋克）下三档置灰不可点、整页仍深色
 *      ⑥ 切回普通主题后三档恢复 ⑦ 系统深浅切换在「跟随系统」档实时生效、锁定档不受影响
 * 用法：node --experimental-websocket tools/dark3check.js（截图：DARK3_SHOTS=1，落仓库外 tempWork）
 * 变异自证：摘掉 darkApply 的 classList.toggle → ②③ 红；renderDarkSeg 摘 disabled → ⑤ 红 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.DARK3_PORT || 9593);
const SHOTS = process.env.DARK3_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/dark3-shots';
const SHELL = 'file:///' + path.resolve('prototype/index.html').replace(/\\/g, '/') + '#p-sub-appearance';
let pass = 0, fail = 0; const errs = [];
let child = null;
const ok = (n, i) => { pass++; console.log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; console.log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 260) } }
}
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
async function open(u) { await cmd('Page.navigate', { url: u }); await wait(2800) }
// 系统深浅态模拟（CDP Emulation，无需真机）
async function emulate(mode) {
  await cmd('Emulation.setEmulatedMedia', { media: '', features: [{ name: 'prefers-color-scheme', value: mode }] });
  await wait(420);
}
const READ = `var q=function(i){return document.getElementById(i)};
  var seg=['system','light','dark'].map(function(m){var b=q('dm-'+m);
    return b?{m:m,on:b.classList.contains('seg-on'),dis:!!b.disabled,op:b.classList.contains('opacity-40')}:null});
  return {dark:document.documentElement.classList.contains('dark'),mode:DARK_MODE,forced:darkForced(),
    sub:(q('darkModeSub')||{}).textContent||'',seg:seg,segBox:!!q('darkModeSeg')};`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.dark3-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('chrome 起服'); return finish() }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');

  await open(SHELL);
  await emulate('light');
  await ev(`setPage('p-sub-appearance');return 1;`); await wait(400);

  // ① 三档在册＋默认跟随系统
  let s = await ev(READ);
  if (s.__err) { bad('读数可用', JSON.stringify(s)); return finish() }
  (s.segBox && s.seg.filter(x => x).length === 3) ? ok('① 三档分段在册（跟随系统／浅色／深色）') : bad('① 分段枚数', JSON.stringify(s));
  (s.mode === 'system' && s.seg[0] && s.seg[0].on && !s.seg[1].on && !s.seg[2].on)
    ? ok('① 默认档＝跟随系统且高亮唯一', 'mode=' + s.mode) : bad('① 默认档', JSON.stringify(s.seg));
  (/跟随系统/.test(s.sub)) ? ok('① 副注读得出当前档') : bad('① 副注', s.sub);
  await shot('d3-01-default-system');

  // ② 点「深色」
  await ev(`setDarkMode('dark');return 1;`); await wait(400);
  s = await ev(READ);
  (s.dark && s.mode === 'dark' && s.seg[2].on && !s.seg[0].on) ? ok('② 锁定深色＝整页 dark＋第三档高亮') : bad('② 深色档', JSON.stringify(s));
  (/已锁定深色/.test(s.sub)) ? ok('② 副注改口「已锁定深色」') : bad('② 副注', s.sub);
  await shot('d3-02-dark');

  // ③ 点「浅色」
  await ev(`setDarkMode('light');return 1;`); await wait(400);
  s = await ev(READ);
  (!s.dark && s.mode === 'light' && s.seg[1].on) ? ok('③ 锁定浅色＝摘掉 dark') : bad('③ 浅色档', JSON.stringify(s));
  (/已锁定浅色/.test(s.sub)) ? ok('③ 副注改口「已锁定浅色」') : bad('③ 副注', s.sub);
  await shot('d3-03-light');

  // ④ 回「跟随系统」：系统浅→整页浅
  await ev(`setDarkMode('system');return 1;`); await wait(400);
  s = await ev(READ);
  (!s.dark && s.mode === 'system' && s.seg[0].on) ? ok('④ 跟随系统·系统为浅→整页浅') : bad('④ 跟随系统(浅)', JSON.stringify(s));

  // ⑦ 系统切深→跟随档实时变深
  await emulate('dark');
  s = await ev(READ);
  (s.dark) ? ok('⑦ 系统改深→跟随档当场转深（无需重进）') : bad('⑦ 跟随系统未响应', JSON.stringify(s));
  await shot('d3-04-system-dark');
  // 锁定档不受系统影响
  await ev(`setDarkMode('light');return 1;`); await wait(300);
  s = await ev(READ);
  (!s.dark && s.mode === 'light') ? ok('⑦ 锁定浅色时系统切深不越权') : bad('⑦ 锁定档被系统改写', JSON.stringify(s));
  await ev(`setDarkMode('system');return 1;`); await wait(300);
  await emulate('light');

  // ⑤ 强制深色主题：三档置灰、整页仍深
  await ev(`setTheme('cyber');return 1;`); await wait(700);
  s = await ev(READ);
  (s.forced && s.dark && s.seg.every(x => x.dis && x.op && !x.on))
    ? ok('⑤ 赛博朋克强制深色＝三档置灰不可点＋整页深') : bad('⑤ 强制深色态', JSON.stringify(s));
  (/强制深色/.test(s.sub)) ? ok('⑤ 副注说明为何不可选') : bad('⑤ 副注', s.sub);
  await shot('d3-05-forced');
  // 点它没反应（disabled）
  s = await ev(`var before=DARK_MODE;document.getElementById('dm-light').click();return {mode:DARK_MODE,before:before};`);
  (s.mode === s.before) ? ok('⑤ 置灰档点不动（不静默改设置）') : bad('⑤ 置灰档仍可点', JSON.stringify(s));

  // ⑥ 切回普通主题→三档恢复
  await ev(`setTheme('minimal');return 1;`); await wait(700);
  s = await ev(READ);
  (!s.forced && s.seg.every(x => !x.dis && !x.op)) ? ok('⑥ 切回普通主题三档恢复可点') : bad('⑥ 恢复', JSON.stringify(s));
  (s.seg[0].on && !s.dark) ? ok('⑥ 恢复后仍停在「跟随系统」') : bad('⑥ 恢复后档位', JSON.stringify(s));
  await shot('d3-06-restored');

  errs.length ? bad('PAGE ERRORS', errs.slice(0, 3).join(' | ')) : ok('PAGE ERRORS 0');
  finish();
})().catch(e => { bad('异常', String(e)); finish() });

function finish() { try { ws && ws.close() } catch (e) { } try { child && child.kill() } catch (e) { }
  console.log('=== dark3check ' + pass + '/' + (pass + fail) + ' ==='); process.exit(fail ? 1 : 0) }
