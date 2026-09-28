/* V1.53「AI 使用记录」原型回归（p-aiUsage 全屏页 · 筛选 · 行内详情 · 查删 · 记录设置 · 入口卡）
 * 用法：node --experimental-websocket tools/aiusagecheck.js（截图：AIU_SHOTS=1） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.AIU_PORT || 9561);
const SHOTS = process.env.AIU_SHOTS === '1';
const SHOTDIR = 'prototype/shots/aiusage';
const LOG = 'tools/aiu-run.log';
let pass = 0, fail = 0; const errs = [];
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m) };
fs.writeFileSync(LOG, '== aiusagecheck start ' + new Date().toISOString() + ' ==\n');
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
/* 列表当前渲染出的行 id 数组（裸表达式，直接嵌进 ev 的对象字面量里） */
const ROWS = "[].map.call($$('#auBox .ailine'),function(l){return +l.dataset.i})";
/* 断言前复位筛选态：任一用例中途抛错也不会把状态漏给后续用例 */
const RESET = "auSetSt('all','auSAll');auSetRange(9999,'auDA');auPickMod('all');$('#auKw').value='';";

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.aiu-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* T1 入口卡与页注册 */
  const t1 = await ev(`setPage('p-sub-ai');
    return {title:(TITLES['p-aiUsage']||[])[0],k1:$('#auK1').textContent,k2:$('#auK2').textContent,
      k3:$('#auK3').textContent,k4:$('#auK4').textContent,
      jump:!!document.querySelector('[onclick*="p-aiUsage"]')};`);
  (t1.title === 'AI 使用记录' && +t1.k1 === 5 && +t1.k4 === 13 && t1.jump)
    ? ok('T1 AI 增强页入口卡（今日 5 次 · 累计 13 条 · 有跳转钮）', JSON.stringify(t1))
    : bad('T1', JSON.stringify(t1));

  /* T2 进页 + 默认今日范围 */
  const t2 = await ev(`navTo('p-aiUsage');auRender();
    return {p:curPage,rows:${ROWS},sum:$('#auSum').textContent,cnt:$('#auSum').textContent};`);
  (t2.p === 'p-aiUsage' && JSON.stringify(t2.rows) === '[1,2,3,4,5]' && /今日 5 次/.test(t2.sum))
    ? ok('T2 默认「今日」只列当天 5 条 + 摘要条') : bad('T2', JSON.stringify(t2));

  await shot('aiu-list-today');
  /* T3 全部范围 13 条 */  const t3 = await ev(`auSetRange(9999,'auDA');return {rows:${ROWS},cnt:$('#auSum').textContent};`);
  (t3.rows.length === 13) ? ok('T3 切「全部」= 13 条') : bad('T3', JSON.stringify(t3));

  /* T4 模块胶囊：点开才横向出选项（带计数）· 选完自动收起并生效 */
  const t4 = await ev(`${RESET}
    auPopToggle('mod');
    var chips=[].map.call($$('#auPop .auf'),function(b){return b.textContent.trim()});
    var openH=!!document.querySelector('#aup-mod.on');
    auPopPick('mod','阅读');
    var rows=[].map.call(document.querySelectorAll('#auBox .ailine .am'),function(e){return e.textContent});
    var r={chips:chips,openH:openH,closed:document.getElementById('auPop').className==='hidden',
      n:rows.length,allRead:rows.every(function(t){return /^阅读 ·/.test(t)}),
      pill:$('#aup-mod').textContent.replace(/\\s+/g,'')};
    auPickMod('all');return r;`);
  (t4.openH && t4.closed && t4.n === 4 && t4.allRead && t4.chips.join('|').indexOf('阅读 4') > 0 && t4.pill.indexOf('模块·阅读4') >= 0)
    ? ok('T4 模块胶囊横向出选项（带计数）· 选「阅读」=4 条并收起', JSON.stringify(t4.pill)) : bad('T4', JSON.stringify(t4));

  /* T5 状态筛选 */
  const t5 = await ev(`${RESET}auSetSt('fail','auSF');var r={rows:${ROWS},cnt:$('#auSum').textContent};auSetSt('all','auSAll');return r;`);
  (JSON.stringify(t5.rows) === '[5,10]') ? ok('T5 状态=失败 命中 2 条（含 429 与断连）') : bad('T5', JSON.stringify(t5));

  /* T6 关键词跨正文搜索 */
  const t6 = await ev(`${RESET}$('#auKw').value='报销';auRender();var r=${ROWS};$('#auKw').value='';auRender();return {rows:r};`);
  (JSON.stringify(t6.rows) === '[2]') ? ok('T6 关键词「报销」命中输入正文里的 1 条') : bad('T6', JSON.stringify(t6));

  /* T7 时间范围 7 天 */
  const t7 = await ev(`${RESET}auSetRange(7,'auD7');var r=${ROWS};auSetRange(9999,'auDA');return {rows:r};`);
  (t7.rows.length === 10) ? ok('T7 「7 天」= 10 条（排除 d≥7 的三条）') : bad('T7', JSON.stringify(t7));

  /* T8 点行展开详情：三段正文 + 四个操作 */
  const t8 = await ev(`auToggle(1);
    var l=document.querySelector('#auBox .ailine[data-i="1"]');
    return {open:l.classList.contains('open'),pre:l.querySelectorAll('.ab pre').length,
      heads:[].map.call(l.querySelectorAll('.ab h5'),function(h){return h.textContent}).join('/'),
      ops:l.querySelectorAll('.ops .mini-btn').length,cut:!!l.querySelector('.cut')};`);
  (t8.open && t8.pre === 3 && t8.ops === 4 && /System/.test(t8.heads) && /User/.test(t8.heads) && /输出/.test(t8.heads) && t8.cut)
    ? ok('T8 展开=System/User/输出 三段 + 四钮 + 截断标注', JSON.stringify(t8)) : bad('T8', JSON.stringify(t8));

  await shot('aiu-row-expanded');
  /* T9 失败行展开显示原因（无输出段） */
  const t9 = await ev(`auToggle(5);
    var l=document.querySelector('#auBox .ailine[data-i="5"]');
    return {heads:[].map.call(l.querySelectorAll('.ab h5'),function(h){return h.textContent}).join('/'),
      err:!!l.querySelector('pre.err')};`);
  (t9.err && /原因/.test(t9.heads) && !/输出/.test(t9.heads))
    ? ok('T9 失败行展开=原因段（不显示空输出）') : bad('T9', JSON.stringify(t9));
  await ev(`auToggle(1);auToggle(5);return 1;`);

  /* T10 复制输入（打桩剪贴板；桩不生效时退化为按 toast 判定代码路径） */
  await ev(`window.__cp='';try{Object.defineProperty(navigator,'clipboard',{value:{writeText:function(t){window.__cp=t;return Promise.resolve()}},configurable:true})}catch(e){}
    auCopy(1,'usr');return 1;`);
  await wait(150);
  const t10 = await ev(`return {len:(window.__cp||'').length,head:(window.__cp||'').slice(0,8),toast:$('#toast').textContent};`);
  ((t10.len > 100 && t10.head.indexOf('你是图书') === 0) || /已复制/.test(t10.toast))
    ? ok('T10 复制输入=System+User 全文', JSON.stringify(t10)) : bad('T10', JSON.stringify(t10));

  /* T11 删除本条 */
  const t11 = await ev(`auDel(4);return {rows:${ROWS},has4:${ROWS}.indexOf(4)>=0,n:AI_CALLS.length};`);
  (!t11.has4 && t11.n === 12) ? ok('T11 删除本条即刻从列表消失') : bad('T11', JSON.stringify(t11));

  /* T12 删除筛选结果=两段式确认 */
  const t12 = await ev(`${RESET}auSetSt('ok','auSOk');
    var btn=[].filter.call(document.querySelectorAll('.mini-btn'),function(x){return /删除筛选结果/.test(x.textContent)})[0];
    btn.click();var first=btn.textContent;var n1=AI_CALLS.length;
    btn.click();var second=btn.textContent;var n2=AI_CALLS.length;
    auSetSt('all','auSAll');auRender();return {first:first,second:second,dropped:n1-n2,left:n2};`);
  (/再点一次确认/.test(t12.first) && t12.dropped === 8 && t12.left === 4)
    ? ok('T12 「删除筛选结果」两段式确认（首次只武装·再点才删 8 条）', JSON.stringify(t12)) : bad('T12', JSON.stringify(t12));

  /* T13 空态（关键词无命中） */
  const t13 = await ev(`$('#auKw').value='zzz不存在';auRender();
    var r={html:$('#auBox').textContent.slice(0,24),cnt:$('#auSum').textContent};
    $('#auKw').value='';auRender();return r;`);
  (/暂无 AI 调用记录/.test(t13.html)) ? ok('T13 清空后列表空态文案') : bad('T13', JSON.stringify(t13));

  /* T14 记录设置弹层：保留 7 天 + 正文开关 + 清空全部 */
  const t14 = await ev(`AI_CALLS=[{i:91,d:0,t:'09-28 09:00:00',m:'阅读',id:'read.toc',n:'目录 AI 补全',st:'ok',it:10,ot:20,ms:300,cut:0,sys:'S',usr:'U',out:'O',err:''},
    {i:92,d:9,t:'09-19 09:00:00',m:'待办',id:'todo.quadrant',n:'AI 判象限',st:'ok',it:1,ot:2,ms:3,cut:0,sys:'S2',usr:'U2',out:'O2',err:''}];
    auSetRange(9999,'auDA');auRender();openSheet('sheetAiUsageCfg');
    var sheetOpen=!!document.querySelector('#sheetAiUsageCfg.sheet-open');
    auKeep(7);var afterKeep=AI_CALLS.length;
    auToggleBody(document.getElementById('auCfgBody'));var bodyOff=auBodyOn;
    auClearBody();var noBody=AI_CALLS.every(function(r){return !r.sys&&!r.usr&&!r.out;});
    auToggleBody(document.getElementById('auCfgBody'));
    auRender();auToggle(91);
    var hint=/未存正文/.test(document.querySelector('#auBox .ailine[data-i="91"]').textContent);
    return {sheetOpen:sheetOpen,afterKeep:afterKeep,bodyOff:bodyOff,noBody:noBody,hint:hint};`);
  (t14.sheetOpen && t14.afterKeep === 1 && t14.bodyOff === false && t14.noBody && t14.hint)
    ? ok('T14 设置弹层：保留 7 天丢超期 · 停记正文 · 清除正文后展开给占位', JSON.stringify(t14)) : bad('T14', JSON.stringify(t14));
  await shot('aiu-settings-sheet');
  await ev(`closeSheet('sheetAiUsageCfg');return 1;`);

  /* T15 清空全部（两段式） */
  const t15 = await ev(`openSheet('sheetAiUsageCfg');
    var btn=[].filter.call(document.querySelectorAll('#sheetAiUsageCfg button'),function(x){return /清空全部/.test(x.textContent)})[0];
    btn.click();var first=btn.textContent;var n1=AI_CALLS.length;
    btn.click();return {first:first,n1:n1,n2:AI_CALLS.length};`);
  (/再点一次确认/.test(t15.first) && t15.n1 === 1 && t15.n2 === 0)
    ? ok('T15 「清空全部记录」两段式确认') : bad('T15', JSON.stringify(t15));

  /* T16 无 JS 异常 + 无脏文本泄漏 */
  const t16 = await ev(`setPage('p-sub-ai');return {body:document.body.innerText};`);
  const leak = ['undefined', 'NaN', '[object Object]', 'null 次'].filter(k => (t16.body || '').includes(k));
  (errs.length === 0 && leak.length === 0)
    ? ok('T16 零 JS 异常 · 无 undefined/NaN/[object Object] 泄漏') : bad('T16', 'errs=' + errs.join(' | ') + ' leak=' + leak.join(','));

  /* T17~T19 第二轮改版：无底栏 / 筛选合一行 / 统计与删除上移（重新播种几条再量版式） */
  await ev(`AI_CALLS=[
    {i:201,d:0,t:'09-28 10:02:11',m:'阅读',id:'read.toc',n:'目录 AI 补全',st:'ok',it:173,ot:4216,ms:13443,cut:0,sys:'S',usr:'U',out:'O',err:''},
    {i:202,d:0,t:'09-28 09:41:02',m:'待办',id:'todo.quadrant',n:'AI 判象限',st:'fail',it:88,ot:0,ms:2100,cut:0,sys:'S',usr:'U',out:'',err:'rateLimited: 429'},
    {i:203,d:1,t:'09-27 20:11:44',m:'日记',id:'journal.reflect',n:'当日复盘草稿',st:'ok',it:612,ot:988,ms:6800,cut:0,sys:'S',usr:'U',out:'O',err:''}];
    ${RESET}navTo('p-aiUsage');auToggle(201);auRender();return 1;`);
  const t17 = await ev(`return {p:curPage,navHidden:$('#tabNav').classList.contains('hidden'),
      mainH:(document.querySelector('main')||{style:{}}).style.height};`);
  (t17.p === 'p-aiUsage' && t17.navHidden && /calc/.test(t17.mainH))
    ? ok('T17 本页隐藏底栏且 main 通底（与日志页同款）', JSON.stringify(t17)) : bad('T17', JSON.stringify(t17));

  const t18 = await ev(`
    var ids=['aup-d','aup-st','aup-mod'].map(function(i){return document.getElementById(i).getBoundingClientRect().top});
    var bar=document.getElementById('auBar');
    return {tops:ids.map(function(t){return Math.round(t)}),bar:!!bar,h:Math.round(bar.getBoundingClientRect().height),
      popHidden:document.getElementById('auPop').className==='hidden'};`);
  (t18.bar && (Math.max.apply(null, t18.tops) - Math.min.apply(null, t18.tops)) < 6 && t18.h < 40 && t18.popHidden)
    ? ok('T18 三组条件收成一行三胶囊（同基线 · 行高<40px · 选项条默认收起）', JSON.stringify(t18)) : bad('T18', JSON.stringify(t18));

  const t20 = await ev(`auPopToggle('d');
    var o=$$('#auPop .auf').length, act=!!document.querySelector('#auPop .auf.on'), h=Math.round(document.getElementById('auPop').getBoundingClientRect().height);
    auPopToggle('d');
    return {o:o,act:act,h:h,closed:document.getElementById('auPop').className==='hidden'};`);
  (t20.o === 4 && t20.act && t20.h > 20 && t20.closed)
    ? ok('T20 点「时间」胶囊横向弹出 4 个选项（当前项高亮）· 再点收起', JSON.stringify(t20)) : bad('T20', JSON.stringify(t20));
  await ev(`auPopToggle('mod');return 1;`);
  await shot('aiu-pill-open');
  await ev(`auPopToggle('mod');return 1;`);

  const t19 = await ev(`
    var sum=$('#auSum').getBoundingClientRect(), box=$('#auBox').getBoundingClientRect();
    var del=[].filter.call(document.querySelectorAll('.mini-btn'),function(x){return /删除筛选结果/.test(x.textContent)})[0].getBoundingClientRect();
    return {sumBottom:Math.round(sum.bottom),delTop:Math.round(del.top),boxTop:Math.round(box.top),
      noCnt:!document.getElementById('auCnt'),kw:!!document.getElementById('auKw')};`);
  (t19.sumBottom < t19.boxTop && t19.delTop < t19.boxTop && t19.noCnt && t19.kw)
    ? ok('T19 统计与「删除筛选结果」上移到列表上方（底部行已移除）', JSON.stringify(t19)) : bad('T19', JSON.stringify(t19));
  await shot('aiu-compact');

  await shot('aiu-final');
  finish();
  try { chrome.kill('SIGKILL') } catch (e) { }
})();

function finish() {
  log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  process.exit(fail ? 1 : 0);
}
