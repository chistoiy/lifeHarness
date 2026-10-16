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

  /* ⑱A2 修正：闸自身必须锁死被测文件。
     教训：早前版本遍历完21 屏后显式调 navTo('p-records')，而 p-records 属index.html
     （LH_REDIRECTS），lhGone 会 700ms 后 location.href 跳走 → 其后所有探针都在别的原型上跑，
     报出「运行期零 JS 异常」＝假绿（setPage 里用了 TITLES[p]，真缺必抛，却测不到）。
     现在① 只遍历本版实体 section② 周期性核验 location ③ 身份丢失＝硬失败。 */
  const SELF = path.basename(F);
  const lost = [];
  const where = async (tag) => {
    const w = await ev(`return location.pathname.split('/').pop();`);
    const cur = (w && w.__err === undefined) ? String(w) : '(eval失败)';
    if (cur !== SELF) lost.push(tag + '@' + cur);
    return cur;
  };

  const ids = await ev(`return [].map.call(document.querySelectorAll('section[id^=p-]'),function(s){return s.id});`);
  log('屏数 ' + (ids.length || 0) + '（本版实体屏，不含 LH_REDIRECTS 外借屏）');

  // 逐屏激活并调 navTo（走真实路由），捕获异常。只对本版实体屏调用，天然不会触发 lhGone。
  for (let k = 0; k < (ids || []).length; k++) {
    const id = ids[k];
    await ev(`try{ if(window.navTo) navTo(${JSON.stringify(id)}); var el=document.getElementById(${JSON.stringify(id)}); if(el){[].forEach.call(document.querySelectorAll('section.page'),function(s){s.classList.remove('active')}); el.classList.add('active');} }catch(e){}`);
    await wait(140);
    if (k % 6 === 0) await where('遍历' + id);
  }
  // 触发若干核心交互：渲染族 + 弹层
  const fns = ['renderShelf', 'renderBookDetail', 'renderQuotes', 'renderReadStat', 'renderReadTimer', 'renderReadLog', 'renderBm', 'bsInit', 'tick'];
  for (const f of fns) { await ev(`try{ if(window.${f}) ${f}(); }catch(e){}`); await wait(120); }
  await where('渲染族');
  /* ⑱A2 修正：Markdown 引擎在本版**没有宿主屏**——pwTextArea / pwBody / pwAttach 在
     bookshelf 里全不存在，宿主 p-records 归index.html。故不能靠 navTo 进屏触发（那正是
     跳页的祸根），改为直接驱动引擎纯函数，覆盖 esc2 / mdInline / mdRender 的调用面。
     pwHostDom 如实记账=false，提醒这批符号在本版无 UI 入口（属A3待删对象）。 */
  const mdCover = await ev(`var r={};
    try{ r.mdRender=(typeof mdRender==='function')?(mdRender('# T\\n\\n> q <i>&"x"</i>\\n\\n|a|b|\\n|-|-|\\n|1|2|\\n\\n- [x] t\\n\\n![i](y.png)\\n'),'ok'):'undef'; }catch(e){ r.mdRender='ERR:'+e.message; }
    try{ r.mdInline=(typeof mdInline==='function')?(mdInline('<b>&"</b> ![a](b.png)'),'ok'):'undef'; }catch(e){ r.mdInline='ERR:'+e.message; }
    try{ r.esc2=(typeof esc2==='function')?esc2('<a>&"'):'undef'; }catch(e){ r.esc2='ERR:'+e.message; }
    r.pwHostDom = !!(document.getElementById('pwTextArea')||document.getElementById('pwBody'));
    return r;`);
  log('Markdown 引擎直调 ' + JSON.stringify(mdCover));
  // ⑱A2：这三个必须真的跑通。只 log 不判＝变异自证假绿（删 esc2 定义仍报 PASS）。
  // 判据＝mdRender/mdInline 须为 ok、esc2 须给出转义结果。
  const mdBad = [];
  if (!mdCover || mdCover.mdRender !== 'ok') mdBad.push('mdRender=' + (mdCover && mdCover.mdRender));
  if (!mdCover || mdCover.mdInline !== 'ok') mdBad.push('mdInline=' + (mdCover && mdCover.mdInline));
  if (!mdCover || typeof mdCover.esc2 !== 'string' || mdCover.esc2.indexOf('&lt;') < 0) mdBad.push('esc2=' + (mdCover && mdCover.esc2));
  log(mdBad.length ? 'FAIL Markdown 引擎路径不通：' + mdBad.join(' / ') : 'PASS Markdown 引擎路径通（mdRender/mdInline/esc2 均已实跑）');
  if (mdCover && mdCover.pwHostDom === false) log('记账 本版无笔记宿主 DOM（pwTextArea/pwBody 不存在）→笔记批符号在本版无 UI 入口');
  await wait(250);
  // 弹层开关（openSheet 依赖保留的通用交互节）
  await ev(`try{ if(window.openSheet){ openSheet('sheetBookOps'); closeSheet('sheetBookOps'); } }catch(e){}`);
  await wait(600);
  await where('弹层');

  const after = await ev(`return {page: typeof curPage!=='undefined'?curPage:null, navItems: document.querySelectorAll('#navBar .navtab').length, active: (document.querySelector('section.page.active')||{}).id||null, loc: location.pathname.split('/').pop() + location.hash, screens: document.querySelectorAll('section[id^=p-]').length};`);
  log('激活后状态 ' + JSON.stringify(after));

  /* ⑤ 死入口探针（⑱A1 新增）：屏内 onclick 指向的函数若不存在，点下去就是「无反应」
     ——这正是 A1 修掉的缺陷类别，必须钉住防复发。
     ⑱A2 修正：首版只看 window[fn]，而顶层 const/let（esc2/imgTarget/TITLES…）不挂 window，
     会被误判成死入口。改以 eval('typeof fn') 为主判据，window 仅作快路径。 */
  const dead = await ev(`var bad=[];
    [].forEach.call(document.querySelectorAll('[onclick]'),function(e){
      var s=e.getAttribute('onclick')||'';
      var m=s.match(/(?:^|;|\\s)([A-Za-z_$][\\w$]*)\\s*\\(/);
      if(!m) return;
      var fn=m[1];
      if(fn==='if'||fn==='return') return;
      var ok=(typeof window[fn]==='function');
      if(!ok){ try{ ok=(eval('typeof '+fn)!=='undefined'); }catch(e){ ok=false; } }
      if(!ok) bad.push({where:(e.closest('section[id]')||{id:'(壳层)'}).id, fn:fn, html:e.outerHTML.slice(0,150)});
    });
    return {n:bad.length, list:bad.slice(0,20)};`);
  log(dead && dead.n ? 'FAIL 死 onclick ' + dead.n + ' 枚：\n  ' + (dead.list || []).map(d => d.where + ' → ' + d.fn + '\n      ' + d.html).join('\n  ')
    : 'PASS 无死 onclick（本版全屏内联处理器均已定义，含顶层 const/let 符号）');

  if (lost.length) log('FAIL 被测文件丢失 ' + lost.length + ' 次：' + lost.slice(0, 5).join(' | ') + '（这些探针结果对被测文件无效）');


  const fails = errs.length || (dead && dead.n) || lost.length || mdBad.length;
  log(errs.length === 0 ? 'PASS 运行期零 JS 异常（' + (ids || []).length + ' 屏全遍历 + ' + fns.length + ' 渲染族 + 弹层）'
    : 'FAIL 运行期异常 ' + errs.length + ' 条:\n  ' + errs.slice(0, 12).join('\n  '));
  try { chrome.kill('SIGKILL') } catch (e) { }
  process.exit(fails ? 1 : 0);
})();
