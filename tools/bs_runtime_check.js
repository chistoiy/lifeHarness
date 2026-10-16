/* ⑰批2 变异/运行期验证 · bookshelf 运行期零 JS 异常 ＋ 21 屏深链可达
 * 手法复制 tools/protostructcheck.js（Chrome CDP），但被测文件换成 index-bookshelf.html，
 * 且逐屏激活 21 个 section + 触发 init 链，捕获 Runtime.exceptionThrown。
 * 用法：node --experimental-websocket tools/bs_runtime_check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const F = process.argv[2] || 'prototype/index-bookshelf.html';
const PORT = Number(process.env.BS_PORT || 9593);
const PROFILE = process.env.BS_PROFILE || 'tools/.bs-rt-profile';
const errs = [];
const log = m => console.log(m);
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(m, p) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method: m, params: p || {} })) }) }
async function ev(expr) {
  const r = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const v = r.result && r.result.result; try { return JSON.parse(v.value) } catch (e) { return { __err: (v && v.value) || '' } }
}

(async () => {
  if (!fs.existsSync(CHROME)) { log('FAIL chrome 缺失'); process.exit(1) }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve(PROFILE), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 300));
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error')
      errs.push('[console.error] ' + m.params.args.map(a => a.value || a.description || '').join(' ').slice(0, 300));
  });
  await cmd('Runtime.enable'); await cmd('Page.enable'); await cmd('Log.enable');
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve(F)).href });
  await wait(3500);

  const ids = await ev(`return [].map.call(document.querySelectorAll('section[id^=p-]'),function(s){return s.id});`);
  log('屏数 ' + (ids.length || 0));

  // 逐屏激活并调 navTo（走真实路由），捕获异常
  for (const id of (ids || [])) {
    await ev(`try{ if(window.navTo) navTo(${JSON.stringify(id)}); var el=document.getElementById(${JSON.stringify(id)}); if(el){[].forEach.call(document.querySelectorAll('section.page'),function(s){s.classList.remove('active')}); el.classList.add('active');} }catch(e){}`);
    await wait(140);
  }
  // 触发若干核心交互：渲染族 + 弹层
  const fns = ['renderShelf', 'renderBookDetail', 'renderQuotes', 'renderReadStat', 'renderReadTimer', 'renderReadLog', 'renderBm', 'bsInit', 'tick'];
  for (const f of fns) { await ev(`try{ if(window.${f}) ${f}(); }catch(e){}`); await wait(120); }
  // 笔记 Markdown 全路径：真实入口是 pwSync()（PW_TA 进编辑态才非空），
  // 直接调 mdRender 覆盖不到——必须先进笔记屏再触发。这是 esc2/imgTarget/pwLnOn 的调用面。
  await ev(`try{ if(window.navTo) navTo('p-records'); }catch(e){}`);
  await wait(400);
  await ev(`try{ if(window.renderPwBar) renderPwBar(); }catch(e){}`);
  await wait(200);
  await ev(`try{ var ta=document.getElementById('pwTextArea')||document.querySelector('#p-records textarea');
      if(ta && window.PW_TA!==undefined){ window.PW_TA=ta; ta.value='# T\\n\\n> 引用 <b>&"x"</b>\\n\\n|a|b|\\n|-|-|\\n|1|2|\\n\\n- [x] 任务\\n\\n![i](x.png)\\n';
        if(window.pwSync) pwSync(); if(window.mdInline) mdInline('<b>&"</b>'); } }catch(e){}`);
  await wait(300);
  await ev(`try{ if(window.mdRender) mdRender('# T\\n\\n> q <i>&"x"</i>\\n\\n- [ ] t\\n\\n![i](y.png)\\n'); }catch(e){}`);
  await wait(250);
  // 弹层开关（openSheet 依赖保留的通用交互节）
  await ev(`try{ if(window.openSheet){ openSheet('sheetBookOps'); closeSheet('sheetBookOps'); } }catch(e){}`);
  await wait(600);

  const after = await ev(`return {page: typeof curPage!=='undefined'?curPage:null, navItems: document.querySelectorAll('#navBar .navtab').length, active: (document.querySelector('section.page.active')||{}).id||null};`);
  log('激活后状态 ' + JSON.stringify(after));
  log(errs.length === 0 ? 'PASS 运行期零 JS 异常（' + (ids || []).length + ' 屏全遍历 + ' + fns.length + ' 渲染族 + 弹层）'
    : 'FAIL 运行期异常 ' + errs.length + ' 条:\n  ' + errs.slice(0, 12).join('\n  '));
  try { chrome.kill('SIGKILL') } catch (e) { }
  process.exit(errs.length ? 1 : 0);
})();
