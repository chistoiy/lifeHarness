/* R14-14 专项校验（CDP 无头 Chrome）：今日问候卡与物品总览是否真联动
 * 断言：① 五个数字与页面内**独立重算**一致（不调用 renderHero，避免自证）；
 *      ② 勾今日待办 / 改象限 / 加物品 → 数字即时变化；
 *      ③ 撤销后回到初值（联动不是单向累加）；
 *      ④ 教学文案与问候 emoji 已摘；⑤ 壳宽不塌；⑥ 零 JS 异常；⑦ 截图。
 * 用法：node --experimental-websocket tools/hero144check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.H14_PORT || 9611);
const SHOTS = 'prototype/shots';
let pass = 0, fail = 0; const errs = [];
const log = (m) => console.log(m);
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')); };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')); };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function get(u) { return new Promise((res) => { try { require('http').get(u, (r) => { let d = ''; r.on('data', (c) => d += c); r.on('end', () => res(d)); }).on('error', () => res(null)); } catch (e) { res(null); } }); }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })); }); }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result;
  try { return JSON.parse(r.value); } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 200) }; }
}
async function shot(name) {
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  const b = m.result && m.result.data; if (!b) { bad('截图 ' + name); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, name), Buffer.from(b, 'base64'));
  log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}
/* 页面内独立重算（与实现同源谓词，但表达式独立书写） */
const RECOMPUTE = `
  var tt=D.todos.filter(function(t){return t.due.indexOf('今天')===0});
  var dn=tt.filter(function(t){return t.done}).length;
  var und=D.todos.filter(function(t){return !t.done});
  var imp=und.filter(function(t){return t.q===0||t.q===1}).length;
  var ip=und.length?Math.round(imp/und.length*100):0;
  var p=tt.length?Math.round(dn/tt.length*100):0;
  var live=D.items.filter(function(it){return it.calc});
  var cost=live.reduce(function(a,it){return a+((it.cost+it.extra-it.res)/it.days)},0);
  /* 今日安排：V1.52 起事件并入 blocks（D.events 迁移后为空），谓词＝day 缺省或等于 TODAY */
  var plansN=blocks.filter(function(b){return (b.day||TODAY)===TODAY}).length;
  return {todoN:tt.length, planN:plansN, insightPct:ip, ringPct:p, ringLine:dn+'/'+tt.length,
    cost:cost.toFixed(2), costN:live.length,
    use:D.items.filter(function(it){return it.st==='使用中'}).length,
    idle:D.items.filter(function(it){return it.st==='闲置'}).length,
    rec:D.items.filter(function(it){return it.st.indexOf('已回收')===0}).length,
    scrap:D.items.filter(function(it){return it.st==='已报废'}).length};`;

/* 读取屏上实际显示值 */
const READ = `
  function T(id){var e=document.getElementById(id);return e?e.textContent:'missing'}
  var ring=document.getElementById('dashRing');
  var ins=(T('dashInsight').match(/(\\d+)%/)||[])[1];
  return {todoN:T('dashTodoN'), planN:T('dashPlanN'), insight:ins,
    ring:ring?ring.getAttribute('stroke-dasharray'):'missing', ringPct:T('dashRingPct'),
    line:T('dashRingLine'), cost:T('dashCost'), costN:T('dashCostN'),
    itCost:T('itCost'), itUse:T('itUse'), itIdle:T('itIdle'), itRec:T('itRec'), itScrap:T('itScrap'),
    greet:T('dashGreet'), teach:document.getElementById('p-dashboard').innerText.indexOf('长按任意卡片可编排顺序')>=0,
    planRows:document.getElementById('dashEvents').children.length};`;

function cmp(exp, got, tag, out) {
  const chk = [['todoN', String(exp.todoN)], ['planN', String(exp.planN)], ['insight', String(exp.insightPct)],
    ['ringPct', exp.ringPct + '%'], ['cost', exp.cost], ['costN', String(exp.costN)],
    ['itCost', exp.cost], ['itUse', String(exp.use)], ['itIdle', String(exp.idle)],
    ['itRec', String(exp.rec)], ['itScrap', String(exp.scrap)]];
  chk.forEach(([k, want]) => { if (['itCost', 'itUse', 'itIdle', 'itRec', 'itScrap'].includes(k) && String(got[k]) === 'missing') return; /* 治理批拍板：物品总览随代表屏下架迁物品专版，壳侧只考核问候卡 */ if (String(got[k]) !== want) out.push(tag + '.' + k + ' 期望 ' + want + ' 实得 ' + got[k]); });
  // 「3/5<br>已完成」的 textContent 没有分隔符，只比对分子/分母前缀
  if (String(got.line).indexOf(exp.ringLine) !== 0) out.push(tag + '.line 期望以 ' + exp.ringLine + ' 开头 实得 ' + got.line);
  if (got.ring !== exp.ringPct + ' 100') out.push(tag + '.ring 期望 ' + exp.ringPct + ' 100 实得 ' + got.ring);
  // 「N 场安排」与今日安排列表必须同源同数
  if (Number(got.planRows) !== exp.planN) out.push(tag + '.planRows 列表 ' + got.planRows + ' 行 ≠ 数字 ' + exp.planN);
}

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish(); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.h14-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) { } } await wait(300); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 160)); });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: require('url').pathToFileURL(path.resolve('prototype/index.html')).href });
  await wait(2800);
  await ev(`document.querySelectorAll('.page').forEach(function(s){s.classList.remove('active')});
    document.getElementById('p-dashboard').classList.add('active');return{ok:1};`);
  await wait(200);

  /* ① 初值＝独立重算 */
  const exp0 = await ev(RECOMPUTE); const got0 = await ev(READ);
  const d1 = []; cmp(exp0, got0, '初值', d1);
  (d1.length === 0 ? ok : bad)('① 问候卡与物品总览逐项＝独立重算', d1.length ? d1.join(' | ') : JSON.stringify(exp0));
  const chipOf = `var t=document.getElementById('smartChips').innerText;
    return {c:(t.match(/今天 (\\d+)/)||[])[1], done:(t.match(/已完成 (\\d+)/)||[])[1]};`;
  const chip0 = await ev(chipOf);

  /* ② 教学文案与 emoji 已摘 */
  const d2 = [];
  if (got0.teach) d2.push('「长按任意卡片可编排顺序」仍在');
  if (/[\u{1F300}-\u{1FAFF}\u{FE0F}]/u.test(got0.greet)) d2.push('问候语仍带 emoji：' + got0.greet);
  (d2.length === 0 ? ok : bad)('② 教学文案已删·问候语无 emoji', d2.length ? d2.join(' | ') : 'greet=' + got0.greet);

  /* ②b 心情提示：未选时不占位（教学句已摘），选中后才出状态提示 */
  const mt0 = await ev(`var e=document.getElementById('moodTip');
    return {txt:e.innerText.trim(), hidden:e.classList.contains('hidden')};`);
  const mt1 = await ev(`document.querySelectorAll('.mood')[2].click();
    var e=document.getElementById('moodTip');
    return {txt:e.innerText.trim().slice(0,24), hidden:e.classList.contains('hidden')};`);
  (!mt0.txt && mt0.hidden && !mt1.hidden && /已记录/.test(mt1.txt)
    ? ok : bad)('②b 心情提示改为选中后状态提示', JSON.stringify(mt0) + ' → ' + JSON.stringify(mt1));

  /* ③ 联动：勾掉一条今日未完成待办 → 完成环与 chip 同步 */
  const act3 = await ev(`var i=D.todos.findIndex(function(t){return t.due.indexOf('今天')===0&&!t.done});
    D.todos[i].done=true; renderTodos(); renderChips();
    return {idx:i,title:D.todos[i].t};`);
  const exp3 = await ev(RECOMPUTE); const got3 = await ev(READ);
  const chip3 = await ev(chipOf);
  const d4 = []; cmp(exp3, got3, '勾待办后', d4);
  if (chip3.c !== String(exp3.todoN)) d4.push('chip 今天 期望 ' + exp3.todoN + ' 实得 ' + chip3.c);
  if (Number(chip3.done) !== Number(chip0.done) + 1) d4.push('chip 已完成 期望 ' + (Number(chip0.done) + 1) + ' 实得 ' + chip3.done);
  (d4.length === 0 && got3.line !== got0.line
    ? ok : bad)('③ 勾选今日待办 → 完成环/环百分比/chip 即时联动',
      d4.length ? d4.join(' | ') : act3.title + ' → ' + got3.line + ' · ' + got3.ringPct + ' · chip 今天 ' + chip3.c);

  /* ④ 撤销回初值 */
  await ev(`D.todos[${act3.idx}].done=false; renderTodos(); renderChips(); return{ok:1};`);
  const got4 = await ev(READ);
  (JSON.stringify(got4) === JSON.stringify(got0) ? ok : bad)('④ 取消勾选后回到初值',
    JSON.stringify(got4) === JSON.stringify(got0) ? got0.line : '差异：' + got4.line + '/' + got4.ringPct);

  /* ⑤ 象限拖拽等价改 q → 洞察行百分比变化 */
  const act5 = await ev(`var i=D.todos.findIndex(function(t){return !t.done&&t.q>=2});
    var oldQ=D.todos[i].q; D.todos[i].q=1; renderTodos();
    return {idx:i,oldQ:oldQ};`);
  const exp5 = await ev(RECOMPUTE); const got5 = await ev(READ);
  const d5 = []; cmp(exp5, got5, '改象限后', d5);
  (d5.length === 0 && Number(got5.insight) > exp0.insightPct
    ? ok : bad)('⑤ 待办移入重要象限 → 精力占比上升', d5.length ? d5.join(' | ') : exp0.insightPct + '% → ' + got5.insight + '%');
  await ev(`D.todos[${act5.idx}].q=${act5.oldQ}; renderTodos(); renderQuad(); return{ok:1};`);
  const got5b = await ev(READ);
  (JSON.stringify(got5b) === JSON.stringify(got0) ? ok : bad)('⑤b 象限复原后回到初值',
    JSON.stringify(got5b) === JSON.stringify(got0) ? got0.insight : '差异：' + got5b.insight);

  /* ⑥ 物品新增计费项 → 两处成本同步 */
  const act6 = await ev(`D.items.push({n:'校验用显示器',ic:'',days:100,cost:1000,extra:0,res:0,st:'使用中',calc:1});
    renderHero(); return{ok:1};`);
  const exp6 = await ev(RECOMPUTE); const got6 = await ev(READ);
  const d6 = []; cmp(exp6, got6, '加物品后', d6);
  (d6.length === 0 && got6.cost !== got0.cost
    ? ok : bad)('⑥ 新增计费物品 → 问候卡成本同步变化（物品页总览已迁物品专版）',
      d6.length ? d6.join(' | ') : got0.cost + ' → ' + got6.cost + ' · ' + got6.costN + ' 件');
  await ev(`D.items.pop(); renderHero(); renderTodos(); return{ok:1};`);
  const got7 = await ev(READ);
  (got7.cost === got0.cost && got7.costN === got0.costN ? ok : bad)('⑦ 撤销物品后成本回落', got0.cost + ' vs ' + got7.cost);

  /* ⑦b 新增今日安排块 → 「N 场安排」与列表同源增长（走 renderCal 主路） */
  await ev(`blocks.push({day:TODAY,s:1430,e:1439,cat:'校验',note:'校验用安排'}); renderCal(); return{ok:1};`);
  const expB = await ev(RECOMPUTE); const gotB = await ev(READ);
  const dB = []; cmp(expB, gotB, '加安排后', dB);
  (dB.length === 0 && Number(gotB.planN) === Number(got0.planN) + 1
    ? ok : bad)('⑦b 新增今日安排 → 场安排与列表同步 +1',
      dB.length ? dB.join(' | ') : got0.planN + ' → ' + gotB.planN + ' · 列表 ' + gotB.planRows + ' 行');
  await ev(`blocks.pop(); renderCal(); return{ok:1};`);
  const gotB2 = await ev(READ);
  (JSON.stringify(gotB2) === JSON.stringify(got0) ? ok : bad)('⑦c 撤销安排后回到初值',
    JSON.stringify(gotB2) === JSON.stringify(got0) ? got0.planN + ' 场' : '差异：' + gotB2.planN);

  /* ⑧ 壳宽不塌 + 截图 */
  const w = await ev(`return {w:Math.round(document.getElementById('p-dashboard').getBoundingClientRect().width)};`);
  (w.w > 350 ? ok : bad)('⑧ 仪表盘激活宽度', 'w=' + w.w);
  await shot('r1414_p-dashboard.png');
  await ev(`document.querySelectorAll('.page').forEach(function(s){s.classList.remove('active')});
    document.getElementById('p-items').classList.add('active');return{ok:1};`);
  await wait(200); await shot('r1414_p-items.png');

  (errs.length === 0 ? ok : bad)('⑨ 运行期零 JS 异常', errs.join(' | '));
  finish(chrome);
})();

function finish(chrome) {
  log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  try { if (chrome) chrome.kill(); } catch (e) { }
  process.exit(fail ? 1 : 0);
}
