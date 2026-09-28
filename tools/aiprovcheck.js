/* V1.53.1「AI 服务商可增删改」原型回归（服务商列表 · 添加/编辑弹层 · 校验 · http 明文确认 · 实测连接）
 * 用法：node --experimental-websocket tools/aiprovcheck.js（截图：AIP_SHOTS=1） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index.html')).href;
const PORT = Number(process.env.AIP_PORT || 9571);
const SHOTS = process.env.AIP_SHOTS === '1';
const SHOTDIR = 'prototype/shots/aiprov';
const LOG = 'tools/aip-run.log';
let pass = 0, fail = 0; const errs = [];
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m) };
fs.writeFileSync(LOG, '== aiprovcheck start ' + new Date().toISOString() + ' ==\n');
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 260) } }
}
async function awe(expr) { /* 异步表达式：把 Promise 结果写进 window.__r 再轮询取回 */
  await ev(`window.__r='__pending';(async function(){${expr}})();return 1;`);
  for (let i = 0; i < 60; i++) { const v = await ev(`return window.__r;`); if (v !== '__pending') return v; await wait(120) }
  return '__timeout';
}
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true }); const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
const ROWS = "[].map.call(document.querySelectorAll('#aiProvList > div'),function(d){return d.textContent.replace(/\\s+/g,' ')})";

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.aip-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* P1/P2 列表运行时渲染 + 预置徽标 + 当前标记 */
  const p1 = await ev(`setPage('p-sub-ai');var r=${ROWS};
    return {n:r.length,cur:r.filter(function(t){return /● 当前/.test(t)}).length,
      builtin:r.filter(function(t){return /预置/.test(t)}).length,
      ollama:r.filter(function(t){return /http 明文/.test(t)}).length,
      relay:r.filter(function(t){return /\\/v1\\/api/.test(t)}).length};`);
  (p1.n === 4 && p1.cur === 1 && p1.builtin === 3 && p1.ollama === 1 && p1.relay === 1)
    ? ok('P1 服务商列表运行时渲染（4 行 · 1 当前 · 3 预置徽 · Ollama 标 http 明文 · 中转站自定义后缀）', JSON.stringify(p1)) : bad('P1', JSON.stringify(p1));

  /* P2 「+ 添加服务商」开真弹层（原先是假 toast） */
  const p2 = await ev(`aiProvEdit(null);
    return {open:!!document.querySelector('#sheetAiProv.sheet-open'),title:$('#apTitle').textContent,
      delHidden:document.getElementById('apDelBtn').classList.contains('hidden'),
      url:$('#apUrl').value,model:$('#apModel').value,proto:$$('#apProto .auf.on').length};`);
  (p2.open && p2.title === '添加服务商' && p2.delHidden && p2.url === '' && p2.proto === 1)
    ? ok('P2 点「+ 添加服务商」打开表单（协议单选默认 OpenAI · 新增态无删除钮）') : bad('P2', JSON.stringify(p2));
  await shot('aip-form');

  /* P3 表单校验：空名/非法 URL/空模型 一律拒收 */
  const p3 = await ev(`var before=AI_PROVS.length;
    $('#apName').value='';$('#apUrl').value='https://x.com/v1';$('#apModel').value='m';aiProvSave();var t1=$('#toast').textContent;
    $('#apName').value='测试';$('#apUrl').value='x.com/v1';aiProvSave();var t2=$('#toast').textContent;
    $('#apUrl').value='https://x.com/v1';$('#apModel').value='';aiProvSave();var t3=$('#toast').textContent;
    return {added:AI_PROVS.length-before,t1:t1,t2:t2,t3:t3};`);
  (p3.added === 0 && /名称/.test(p3.t1) && /http/.test(p3.t2) && /模型/.test(p3.t3))
    ? ok('P3 三项校验都拒收且不落列表', JSON.stringify(p3)) : bad('P3', JSON.stringify(p3));

  /* P4 http 明文必须二次确认 */
  const p4 = await ev(`var before=AI_PROVS.length;
    $('#apName').value='家里 Ollama';$('#apUrl').value='http://192.168.31.9:11434/v1';$('#apModel').value='qwen2.5:7b';
    apHintCheck();var rowShown=!document.getElementById('apHttpRow').classList.contains('hidden');
    aiProvSave();var denied=$('#toast').textContent;var n1=AI_PROVS.length;
    document.getElementById('apHttpOk').classList.add('on');aiProvSave();
    return {rowShown:rowShown,denied:denied,addedAfterConfirm:AI_PROVS.length-before,stillNew:AI_PROVS.length-n1,
      cur:aiCurProv().n,url:aiCurProv().u};`);
  (p4.rowShown && /http 明文/.test(p4.denied) && p4.addedAfterConfirm === 1 && p4.cur === '家里 Ollama')
    ? ok('P4 http 明文未确认被拒 · 确认后保存并自动设为当前', JSON.stringify(p4)) : bad('P4', JSON.stringify(p4));

  /* P5 编辑既有项：预填 + 改模型生效 + 条数不变（deepseek 此时已非当前项 → 允许删） */
  const p5 = await ev(`var n0=AI_PROVS.length;aiProvEdit('deepseek');
    var pre={u:$('#apUrl').value,m:$('#apModel').value,k:/留空则不改/.test($('#apKey').placeholder),del:!document.getElementById('apDelBtn').classList.contains('hidden')};
    $('#apModel').value='deepseek-reasoner';aiProvSave();
    var p=aiProvById('deepseek');
    return {same:AI_PROVS.length===n0,pre:pre,model:p.m};`);
  (p5.same && p5.pre.u.indexOf('api.deepseek.com') > 0 && p5.pre.k && p5.pre.del && p5.model === 'deepseek-reasoner')
    ? ok('P5 编辑预填（Key 留空=不改 · 非当前项才给删钮）· 改模型即刻生效', JSON.stringify(p5)) : bad('P5', JSON.stringify(p5));

  /* P6 切换当前：原当前项露出「选用」，新当前项显 ● 当前 且无删除钮 */
  const p6 = await ev(`aiProvUse('relay');var r=${ROWS};
    return {curRelay:/● 当前/.test(r.filter(function(t){return /自建中转站/.test(t)})[0]),
      dsUse:/选用/.test(r.filter(function(t){return /DeepSeek/.test(t)})[0]),
      curNoDel:!(/删/.test(r.filter(function(t){return /自建中转站/.test(t)})[0])),
      sum:$('#apCur').textContent.replace(/\\s+/g,'')};`);
  (p6.curRelay && p6.dsUse && p6.curNoDel && /自建中转站/.test(p6.sum))
    ? ok('P6 「选用」切换当前端点 · Key 配置卡摘要同步', JSON.stringify(p6)) : bad('P6', JSON.stringify(p6));

  /* P7 删除非当前项=两段式确认 */
  const p7 = await ev(`var btns=[].filter.call(document.querySelectorAll('#aiProvList .mini-btn'),function(b){return b.textContent.trim()==='删'});
    var b=btns[0],n0=AI_PROVS.length;b.click();var first=b.textContent;var n1=AI_PROVS.length;b.click();
    return {hasBtn:btns.length>=1,first:first,dropped:n0-AI_PROVS.length,left:AI_PROVS.length};`);
  (/再点一次确认/.test(p7.first) && p7.dropped === 1 && p7.left === 4)
    ? ok('P7 删除服务商两段式（首点只武装 · 再点才删）', JSON.stringify(p7)) : bad('P7', JSON.stringify(p7));

  /* P8 实测连接：不可达端点给「未送达」+ 局域网/CORS 说明（不发真请求也能验通路） */
  const p8 = await awe(`$('#apUrl').value='http://127.0.0.1:9/v1';$('#apModel').value='x';
    await aiProvPing();window.__r=$('#apRes').textContent.replace(/\\s+/g,' ').slice(0,60);`);
  (/未送达|超时|HTTP/.test(String(p8))) ? ok('P8 测试连接走真实 fetch 并回读状态/失败原因', JSON.stringify(p8)) : bad('P8', JSON.stringify(p8));

  /* P9 与 AI 使用记录页共存：入口卡与全屏页仍在（本轮改动没打破 V1.53） */
  const p9 = await ev(`return {prov:!!document.getElementById('aiProvList'),usage:!!document.getElementById('p-aiUsage'),
    cfg:!!document.getElementById('sheetAiUsageCfg'),kpi:document.getElementById('auK1').textContent};`);
  (p9.prov && p9.usage && p9.cfg) ? ok('P9 AI 使用记录页与设置弹层未被本轮改动破坏') : bad('P9', JSON.stringify(p9));

  /* P10 零异常 + 无脏文本 */
  const p10 = await ev(`return {body:document.body.innerText};`);
  const leak = ['undefined', 'NaN', '[object Object]'].filter(k => (p10.body || '').includes(k));
  (errs.length === 0 && leak.length === 0)
    ? ok('P10 零 JS 异常 · 无 undefined/NaN/[object Object] 泄漏', errs.join('|')) : bad('P10', errs.join('|') + ' leak=' + leak);

  /* P11 正常导航路径下的整页截图（navTo 走栈，与真人点开一致） */
  await ev(`navTo('p-sub-ai');return 1;`); await wait(500);
  await shot('aip-page-full');
  const p11 = await ev(`var el=document.getElementById('p-sub-ai');
    return {w:Math.round(el.getBoundingClientRect().width),rows:document.querySelectorAll('#aiProvList > div').length,
      inMain:!!el.closest('main')};`);
  (p11.w > 380 && p11.rows === 4 && p11.inMain)
    ? ok('P11 正常导航下 AI 增强页版式完好（宽 ' + p11.w + 'px · 服务商 4 行）', JSON.stringify(p11)) : bad('P11', JSON.stringify(p11));

  await shot('aip-final');
  finish();
  try { chrome.kill('SIGKILL') } catch (e) { }
})();

function finish() { log('== ' + pass + ' PASS / ' + fail + ' FAIL =='); process.exit(fail ? 1 : 0); }
