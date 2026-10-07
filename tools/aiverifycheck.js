/* aiverifycheck.js · 批①硬闸：壳原型「AI API 验证」屏（p-sub-aiVerify）无头逐链断言
 * 口径＝实现真页 lib/features/settings/presentation/ai_page_verify.dart 的形态：
 *   服务商 chips 预选 → 端点/Key/模型/提示词 → 真实发送验证 → 结果三态（通过 · 凭据错误 · 网络失败）
 * 用法：node --experimental-websocket tools/aiverifycheck.js（截图：AV_SHOTS=1）
 * 变异自证：摘 aiVfJudge 的 Key 判定 → V9 红；摘 avBusy 早退 → V12 红。
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index.html')).href;
const PORT = Number(process.env.AV_PORT || 9583);
const SHOTS = process.env.AV_SHOTS === '1';
const SHOTDIR = 'prototype/shots/aiverify';
const LOG = 'tools/av-run.log';
let pass = 0, fail = 0; const errs = [];
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m) };
fs.writeFileSync(LOG, '== aiverifycheck start ' + new Date().toISOString() + ' ==\n');
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
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true }); const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
/* 点发送并等结果落定（620ms 计时器 + 余量） */
async function settle(ms) { await wait(ms || 900); return ev(`return {busy:aiVfBusy(),res:$('#avRes').textContent,color:$('#avRes').style.color,btn:$('#avSend').textContent,lat:$('#avLat').textContent};`) }

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.av-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('CDP 就绪'); try { chrome.kill('SIGKILL') } catch (e) { } return finish() }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* V1 屏在册（未登记 section 会被 lhGone 兜走，必须真存在） */
  const v1 = await ev(`return {has:!!document.getElementById('p-sub-aiVerify'),
    inReg:(typeof LH_LANDING!=='undefined')};`);
  v1.has ? ok('V1 新屏 p-sub-aiVerify 在原型里') : bad('V1', JSON.stringify(v1));

  /* V2 入口：AI 增强页「验证状态」行的重新验证钮 → 真进屏 */
  const v2 = await ev(`setPage('p-sub-ai');var b=[].slice.call(document.querySelectorAll('#p-sub-ai button')).filter(function(x){return /重新验证/.test(x.textContent)})[0];
    var has=!!b;if(b)b.click();
    return {has:has,cur:curPage,title:$('#pageTitle').textContent,active:!!document.querySelector('#p-sub-aiVerify.active'),
      back:!$('#btnBack').classList.contains('hidden')};`);
  (v2.has && v2.cur === 'p-sub-aiVerify' && v2.title === 'AI API 验证' && v2.active && v2.back)
    ? ok('V2 入口钮进屏＋顶栏标题＋返回钮在位') : bad('V2', JSON.stringify(v2));

  /* V3 预填＝当前服务商（对齐实现 _prefill），结果区先给空态 */
  const v3 = await ev(`aiVfFill();var c=aiCurProv();
    return {url:$('#avUrl').value,m:$('#avModel').value,pr:$('#avPrompt').value,cu:c.u,
      idle:/^结果将显示在此/.test($('#avRes').textContent),gray:$('#avRes').style.color==='rgb(148, 163, 184)'||$('#avRes').style.color==='#94a3b8',
      keyHas:$('#avKey').value.length>0,eye:$('#avEye').innerHTML.length>0};`);
  (v3.url && v3.m && v3.url.indexOf(v3.cu) === 0 && v3.pr === '请只回复四个字：连接成功' && v3.idle && v3.gray && v3.keyHas && v3.eye)
    ? ok('V3 进屏即预填当前端点·模型·提示词，结果区空态灰字', JSON.stringify({ url: v3.url, m: v3.m })) : bad('V3', JSON.stringify(v3));

  /* V4 服务商 chips：枚数＝在册服务商，当前那枚有选中态 */
  const v4 = await ev(`var cs=$$('#avChips button');
    var on=[].filter.call(cs,function(b){return b.getAttribute('style')&&/background/.test(b.getAttribute('style'))});
    return {n:cs.length,on:on.length,seed:aiProvs().length};`);
  (v4.n === v4.seed && v4.n >= 3 && v4.on === 1)
    ? ok('V4 chips 与服务商同集且仅一枚选中态', JSON.stringify(v4)) : bad('V4', JSON.stringify(v4));

  /* V5 点 chip 就地改端点与模型（不做两段式弹层） */
  const v5 = await ev(`var b=[].filter.call($$('#avChips button'),function(x){return /Anthropic/.test(x.textContent)})[0];
    b.click();return {url:$('#avUrl').value,model:$('#avModel').value,proto:aiVfProto($('#avUrl').value)};`);
  (v5.url.indexOf('anthropic') > 0 && v5.proto === 'anthropic')
    ? ok('V5 选 Anthropic 后端点/模型/协议当场跟') : bad('V5', JSON.stringify(v5));

  /* V6 请求中态：协议走 /messages，按钮变文案并置忙 */
  await ev(`$('#avKey').value='sk-test';$('#avModel').value='claude-3-5-haiku-latest';aiVfSend();return 1;`);
  const v6 = await ev(`return {busy:aiVfBusy(),btn:$('#avSend').textContent,res:$('#avRes').textContent,
    dim:$('#avSend').classList.contains('opacity-40')};`);
  (v6.busy && v6.btn === '请求中…' && /⏳ POST .*\/messages · model=claude-3-5-haiku-latest/.test(v6.res) && v6.dim)
    ? ok('V6 发送即进「请求中」且按协议拼路径', JSON.stringify({ res: v6.res.slice(0, 60) })) : bad('V6', JSON.stringify(v6));

  /* V7 防重入：忙中真点按钮不重起请求（计时器不被重启＝到点必落定；无闸则读数被推后仍显 ⏳） */
  await settle(); /* 先把 V6 那发等落定，避免与本轮计时器串台 */
  await ev(`aiVfPick('deepseek');$('#avKey').value='sk-demo-deepseek';$('#avModel').value='deepseek-flash';aiVfSend();return 1;`);
  await wait(500);
  const v7a = await ev(`return {busy:aiVfBusy(),res:$('#avRes').textContent.slice(0,1)};`);
  await ev(`document.getElementById('avSend').click();document.getElementById('avSend').click();return 1;`);
  await wait(350);
  const v7b = await ev(`return {busy:aiVfBusy(),res:$('#avRes').textContent.slice(0,1)};`);
  (v7a.busy && v7a.res === '⏳' && !v7b.busy && v7b.res !== '⏳')
    ? ok('V7 忙中再点不重起请求，到点即落定') : bad('V7', JSON.stringify({ a: v7a, b: v7b }));

  /* V8 通过态：绿字＋延迟读数＋主页状态行联动 */
  await ev(`aiVfPick('deepseek');$('#avKey').value='sk-demo-deepseek';$('#avModel').value='deepseek-flash';aiVfSend();return 1;`);
  const v8 = await settle();
  const v8b = await ev(`return {st:$('#apVerifyState').textContent};`);
  (v8.res.indexOf('✓ 812ms · 200 OK') === 0 && /模型回复/.test(v8.res) && /usage: 12 \+ 4 tokens/.test(v8.res)
    && /#10b981|rgb\(16, 185, 129\)/.test(v8.color) && v8.lat.indexOf('812') >= 0 && /✓ 刚刚通过/.test(v8b.st) && !v8.busy)
    ? ok('V8 通过态＝绿＋延迟＋主页验证状态联动', JSON.stringify({ lat: v8.lat, st: v8b.st })) : bad('V8', JSON.stringify(v8) + JSON.stringify(v8b));
  await shot('av-ok');

  /* V9 凭据错误：Key 清空 → 401 玫红 */
  await ev(`$('#avKey').value='';aiVfSend();return 1;`);
  const v9 = await settle();
  (/✕ 401 未授权/.test(v9.res) && /#f43f5e|rgb\(244, 63, 94\)/.test(v9.color) && v9.lat === '未通过')
    ? ok('V9 无 Key＝401 凭据错误（不静默）') : bad('V9', JSON.stringify(v9));

  /* V10 模型名错：Key 有、模型空 → 404 */
  await ev(`$('#avKey').value='sk-demo-deepseek';$('#avModel').value='';aiVfSend();return 1;`);
  const v10 = await settle();
  (/✕ 404 模型不存在/.test(v10.res)) ? ok('V10 模型名缺失＝404 归因') : bad('V10', JSON.stringify(v10));

  /* V11 网络失败：非法 Base URL → 不发请求，直说连不上 */
  await ev(`$('#avModel').value='deepseek-flash';$('#avUrl').value='api.deepseek.com/v1';aiVfSend();return 1;`);
  const v11 = await settle();
  (/✕ 网络失败/.test(v11.res) && /无法连接/.test(v11.res)) ? ok('V11 地址不合法＝网络失败归因') : bad('V11', JSON.stringify(v11));

  /* V12 眼睛钮：明文/掩码可切（与 Key 配置同款交互） */
  const v12 = await ev(`var t0=$('#avKey').type;apPeek('avKey','avEye');var t1=$('#avKey').type;apPeek('avKey','avEye');
    return {t0:t0,t1:t1,back:$('#avKey').type};`);
  (v12.t0 === 'password' && v12.t1 === 'text' && v12.back === 'password')
    ? ok('V12 Key 明文可切且切回掩码') : bad('V12', JSON.stringify(v12));

  /* V13 返回栈：回 AI 增强页，入口状态行仍在 */
  const v13 = await ev(`$('#btnBack').click();
    return {cur:curPage,state:!!document.getElementById('apVerifyState')};`);
  (v13.cur === 'p-sub-ai' && v13.state) ? ok('V13 返回落回 AI 增强页且状态行保留', JSON.stringify(v13)) : bad('V13', JSON.stringify(v13));

  /* V14 屏面无 emoji 图标（结果区的 ✓✕⏳ 是状态符号，且属运行期文本，先复位再扫源码面） */
  const v14 = await ev(`$('#avRes').textContent=AV_IDLE;
    var h=document.getElementById('p-sub-aiVerify').innerHTML;
    var emo=h.match(/[\\u{1F300}-\\u{1FAFF}]/gu)||[];
    return {n:emo.length,g:emo.join('')};`);
  (v14.n === 0) ? ok('V14 屏面无 emoji 图标') : bad('V14', JSON.stringify(v14));

  /* V15 运行期零异常 */
  (!errs.length) ? ok('V15 控制台无未捕获异常') : bad('V15', errs.slice(0, 3).join(' | '));

  await shot('av-final');
  finish();
  try { chrome.kill('SIGKILL') } catch (e) { }
})();

function finish() { log('== ' + pass + ' PASS / ' + fail + ' FAIL =='); process.exit(fail ? 1 : 0) }
