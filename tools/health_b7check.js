/* health_b7check.js · 健康批7「今日仪表盘·今日健康卡」原型先行无头闸
 * 规格依据＝docs/健康管理模块开发计划-20260927.md §批7（环＋杯数＋运动分钟）＋需求清单 V1.63 增「当前血压位」
 *   ＋收口版迭代设计 §2.2 B8（共享面挂载·`index.html` 改动只经变更单）
 * 纪律沿用 gttrashcheck.js＝期望值**页面内现算**（达成度按 §五.1 喝水40＋睡眠35＋运动25 独立重算，不吃页面写的数）；
 *   截图默认关（HB7_SHOTS=1 才拍，落仓库外 tempWork）
 * 用法：node --experimental-websocket tools/health_b7check.js */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.HB7_PORT || 9626);
const SHOTS = process.env.HB7_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/health-b7-shots';
let chrome, pass = 0, fail = 0; const errs = [];
const log = m => { console.log(m) };
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
async function shot(name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64'));
}

/* 页面内公共探针：卡内文本、环读数、编排登记 */
const PRELUDE = String.raw`
window.__tx=function(id){if(id.charAt(0)==='#')id=id.slice(1);var e=document.getElementById(id);return e?(e.textContent||'').replace(/\s+/g,''):''};
window.__card=function(){return document.getElementById('dashHealth')};
window.__wrap=function(){var c=__card();return c?c.closest('.dash-card'):null};
window.__ring=function(){var e=document.getElementById('dashHealthRing');return e?(e.getAttribute('stroke-dasharray')||'').trim():''};
window.__ids=function(){return [].map.call(document.querySelectorAll('#p-dashboard .dash-card'),function(c){return c.dataset.id}).join(',')};`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.healthb7-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,1200', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 300));
  });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF });
  // index.html 头部挂着 Tailwind CDN，首次取可能几秒；定长 wait 会让断言跑在半份文档上。按 readyState＋工装就绪轮询。
  for (let i = 0; i < 40; i++) { const t = await ev('return typeof renderDashHealth'); if (t && t !== 'undefined') break; await wait(1000) }
  await wait(800);
  await ev(PRELUDE + 'return 1;');

  /* A1 卡在仪表盘内、位置＝快捷记录条之后、时间分布之前，且是可点入口（直达健康专版） */
  const a1 = await ev(`
    var p=document.getElementById('p-dashboard'),c=__card();
    if(!c) return {none:1};
    var kids=[].slice.call(p.children).indexOf(c.closest('.dash-card'));
    var inbox=[].slice.call(p.querySelectorAll('.dash-card')).filter(function(w){return /收集箱/.test(w.textContent)})[0];
    var chart=[].slice.call(p.querySelectorAll('.dash-card')).filter(function(w){return /本周时间分布/.test(w.textContent)})[0];
    return {inDash:!!c.closest('#p-dashboard'),afterInbox:p.children?[].slice.call(p.children).indexOf(c.closest('.dash-card'))>[].slice.call(p.children).indexOf(inbox):0,
      beforeChart:[].slice.call(p.children).indexOf(c.closest('.dash-card'))<[].slice.call(p.children).indexOf(chart),
      tap:(c.getAttribute('onclick')||''),kids:kids,nav:!!(window.LH_REDIRECTS&&window.LH_REDIRECTS['p-health'])};`);
  (a1.inDash && a1.afterInbox && a1.beforeChart && /navTo\('p-health'\)/.test(a1.tap) && a1.nav)
    ? ok('A1 卡位在快捷记录条与时间分布之间，点卡走 navTo(p-health)（入口直达专版，壳内不再造屏）') : bad('A1', JSON.stringify(a1));

  /* A2 编排登记：主页卡序＝七张，health 落在 inboxBar 之后 */
  const a2 = await ev(`return {ids:__ids(),wrap:!!__wrap(),wrapId:__wrap()?__wrap().dataset.id:''};`);
  (a2.wrap && a2.wrapId === 'health' && a2.ids === 'greeting,mood,events,inboxBar,health,chart,grid')
    ? ok('A2 自由编排把新卡登记进同一序列（可拖可 ↑↓，不是外挂死块）', a2.ids) : bad('A2', JSON.stringify(a2));

  /* A3 达成度＝§五.1 现算（喝水40＋睡眠35＋运动≥10 记满 25），与独立重算逐位相等 */
  const a3 = await ev(`
    var d=DASH_HEALTH,pc=function(a,b){return b<=0?0:Math.min(100,a/b*100)};
    var want=Math.round(pc(d.cups,d.waterGoal)*0.4+pc(d.sleepMin,d.sleepGoalMin)*0.35+(d.exMin>=10?100:0)*0.25);
    return {want:want,pct:__tx('#dashHealthPct'),ring:__ring(),cups:__tx('#dashHealthWater'),ex:__tx('#dashHealthEx')};`);
  (a3.pct === a3.want + '%' && a3.ring === a3.want + ' 100')
    ? ok('A3 环上百分比与 stroke-dasharray 同源同数（现算 ' + a3.want + '%，非写死）', '喝水 ' + a3.cups + ' · 运动 ' + a3.ex) : bad('A3', JSON.stringify(a3));

  /* A4 改数据即换数：把杯数灌满目标 → 分数必须跟着涨（证明分母吃当日目标） */
  const a4 = await ev(`
    var d=DASH_HEALTH,old=__tx('#dashHealthPct');d.cups=d.waterGoal;renderDashHealth();
    var pc=function(a,b){return b<=0?0:Math.min(100,a/b*100)};
    var want=Math.round(pc(d.cups,d.waterGoal)*0.4+pc(d.sleepMin,d.sleepGoalMin)*0.35+(d.exMin>=10?100:0)*0.25);
    var r={old:old,new:__tx('#dashHealthPct'),want:want,ring:__ring(),goal:__tx('#dashHealthGoal'),
      labelTx:(function(){var e=document.getElementById('dashHealthWater');return e?e.nextElementSibling.textContent:''})()};
    d.cups=2;renderDashHealth();return r;`);
  (a4.want > Number(a4.old.replace('%', '')) && a4.new === a4.want + '%' && a4.ring === a4.want + ' 100'
    && a4.labelTx.indexOf(a4.goal) >= 0)
    ? ok('A4 灌满一杯数即换分：' + a4.old + ' → ' + a4.new + '（分母随目标走，不是硬编码百分比）') : bad('A4', JSON.stringify(a4));

  /* A5 没记录的格子出「—」，不摆 0 假读数 */
  const a5 = await ev(`
    var d=DASH_HEALTH;d.cups=0;d.exMin=0;d.bp=null;renderDashHealth();
    var t=__card().textContent.replace(/\\s+/g,'');
    var r={water:__tx('#dashHealthWater'),ex:__tx('#dashHealthEx'),bp:__tx('#dashHealthBp'),zero:/0(?:杯|分钟)/.test(t)};
    d.cups=2;d.exMin=30;renderDashHealth();return r;`);
  (a5.water === '—' && a5.ex === '—' && a5.bp === '—' && !a5.zero)
    ? ok('A5 三格空记录一律「—」，卡内不出现「0 杯 / 0 分钟」假读数') : bad('A5', JSON.stringify(a5));

  /* A6 血压位（需求 V1.63）：测过就现读，读数格式两值 */
  const a6 = await ev(`
    var d=DASH_HEALTH;d.bp='120/80';renderDashHealth();
    var r={bp:__tx('#dashHealthBp'),label:(function(){var e=document.getElementById('dashHealthBp');return e?e.nextElementSibling.textContent:''})()};
    d.bp=null;renderDashHealth();return r;`);
  (a6.bp === '120/80' && /血压/.test(a6.label))
    ? ok('A6 当前血压位到位：读数＝最近一次测量，标签＝「血压」', a6.bp) : bad('A6', JSON.stringify(a6));

  /* A7 UI 纪律：卡内无线性图标以外的 emoji、无教学性文案、无「演示/模拟」字样 */
  const a7 = await ev(`
    var t=__card().textContent;
    var emo=(t.match(/[\\u{1F300}-\\u{1FAFF}\\u{2600}-\\u{27BF}]/gu)||[]).join('');
    return {emo:emo,demo:/演示|模拟|示例|点击可|你可以试试/.test(t),tx:t.replace(/\\s+/g,'|').slice(0,80)};`);
  (!a7.emo && !a7.demo)
    ? ok('A7 卡内零 emoji·零教学文案（只留功能标签与读数）', a7.tx) : bad('A7', JSON.stringify(a7));

  /* A8 其余主页卡不回归：问候卡与宫格照旧、卡片总数不变 */
  const a8 = await ev(`
    return {n:document.querySelectorAll('#p-dashboard .dash-card').length,
      hero:!!document.getElementById('dashRing'),grid:!!document.getElementById('appGrid'),
      mood:document.querySelectorAll('#p-dashboard .mood').length,
      footLast:(function(){var w=[].slice.call(document.getElementById('p-dashboard').children);return w[w.length-1].id})()};`);
  (a8.n === 7 && a8.hero && a8.grid && a8.mood === 7 && a8.footLast === 'dashFooter')
    ? ok('A8 主页其余六卡与心情排布照旧（新卡是第七张，页脚仍在尾）', '卡数 ' + a8.n) : bad('A8', JSON.stringify(a8));

  await shot('A-final-dash');
  const pe = errs.filter(e => !/lh-gov|init skip/.test(e));
  (pe.length === 0 ? ok : bad)('Z0 PAGE ERRORS', pe.length ? pe.join(' || ') : '0');

  finish();
})().catch(e => { bad('工装异常 ' + e.message); finish() });

function finish() { try { if (ws) ws.close() } catch (e) { } try { chrome && chrome.kill() } catch (e) { }
  log('---- health_b7check: ' + pass + '/' + (pass + fail) + ' 绿 ----');
  process.exit(fail ? 1 : 0);
}
