/* R14-7/8 原型改批专项校验（CDP 无头 Chrome·深链逐屏）
 * 断言：① 设置区与外观页 emoji 归零；② 入口行图标确有 <svg>；③ 教学文案已摘；
 *      ④ 页宽不塌（防误删闭合标签）；⑤ 运行期零 JS 异常；⑥ 逐屏截图入 shots。
 * 用法：node --experimental-websocket tools/r1478check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const F = 'prototype/index.html';
const PORT = Number(process.env.R78_PORT || 9597);
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
  const b = m.result && m.result.data;
  if (!b) { bad('截图 ' + name); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, name), Buffer.from(b, 'base64'));
  log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}
/* emoji 判据：只取真正的图形 emoji（1F300-1FAFF + 变体选择符）。
   ✓ ● › 这类文本符号不算（历史口径）；用户数据自带图标（提醒通知里的习惯条目
   「🏃 晨间跑步 / 📚 阅读 / 🧋 奶茶控制」）属数据而非 UI 装饰，列入白名单。 */
const EMOJI_SRC = '[\\u{1F300}-\\u{1FAFF}\\u{FE0F}]';
const WHITELIST = { 'p-sub-notify': ['🏃', '📚', '🧋'] };

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish(); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.r78-profile'),
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
  await cmd('Page.navigate', { url: require('url').pathToFileURL(path.resolve(F)).href });
  await wait(2800);

  /* ① 设置屏 + 外观二级页：emoji 归零、入口图标确有 svg、标题无 emoji 前缀
     （坑记：JSON.stringify(RegExp) 得到的是 {}，落到页面会退化成
     「[object Object] 字符类」正则从而每屏都误报命中——必须传 source 字符串就地构造） */
  const r1 = await ev(`var re=new RegExp(${JSON.stringify(EMOJI_SRC)},'gu');
    var wl=${JSON.stringify(WHITELIST)};
    var out=[];
    ['p-profile','p-sub-appearance','p-sub-data','p-sub-notify','p-sub-ai','p-sub-recmg','p-sub-cats'].forEach(function(id){
      var el=document.getElementById(id); if(!el){out.push(id+':missing');return}
      var txt=(el.innerText||'');
      var m=txt.match(re)||[];
      var allow=wl[id]||[];
      var rest=m.filter(function(c){return allow.indexOf(c)<0});
      var svgs=el.querySelectorAll('.set-ic svg').length;
      // 不变式：入口图标块要么有 <svg>，要么是「Aa」这类纯文字标记，不能空块
      var bare=[].slice.call(el.querySelectorAll('.set-ic')).filter(function(c){
        return !c.querySelector('svg') && !(c.textContent||'').trim();
      }).length;
      out.push(id+':emoji='+rest.length+'('+rest.join('')+')'
        +(allow.length?'·白名单='+allow.length+'个用户数据图标':'')
        +'·setIcSvg='+svgs+'·空块='+bare);
    });
    return {out:out};`);
  const bad1 = (r1.out || []).filter((x) => /emoji=[1-9]|空块=[1-9]|missing/.test(x));
  (bad1.length === 0)
    ? ok('① 设置族 7 屏 emoji 归零·入口图标为 SVG 或纯文字', r1.out.join(' | '))
    : bad('① 设置族 emoji', r1.out.join(' | '));

  /* ② 教学文案已摘：块视图顶部只留刻度读数，右列标题为「分类」 */
  const r2 = await ev(`var gl=document.getElementById('granLabel');
    var blk=document.getElementById('calBlockView');
    var t=blk?blk.innerText:'';
    return {gran:gl?gl.textContent:'missing',
      teaching:/点右列分类=直接标记|点已有块可改起止|选中=标记 · 未选=记到此刻/.test(t),
      hasScale:/1 格 = \\d+ 分 · 全天 0-24/.test(t),
      railTitle:/分类/.test(t),
      drag:/长按拖拽 = 调整顺序/.test((document.getElementById('p-profile')||{innerText:''}).innerText)};`);
  (!r2.teaching && !r2.drag && r2.hasScale && r2.gran !== 'missing')
    ? ok('② 教学文案已摘·刻度读数与 granLabel 接线保留', 'gran=' + r2.gran)
    : bad('② 教学文案', JSON.stringify(r2));

  /* ③ 逐屏激活宽度不塌（防标签配平被改坏） */
  const r3 = await ev(`var out=[];
    ['p-profile','p-sub-appearance','p-calendar','p-sub-ai','p-sub-data'].forEach(function(p){
      var el=document.getElementById(p); if(!el){out.push(p+':missing');return}
      document.querySelectorAll('.page').forEach(function(s){s.classList.remove('active')});
      el.classList.add('active');
      out.push(p+':'+Math.round(el.getBoundingClientRect().width));
    });return {out:out};`);
  const thin = (r3.out || []).filter((x) => !/missing/.test(x) && parseInt(x.split(':')[1], 10) < 350);
  (thin.length === 0 && !/missing/.test(r3.out.join(' ')))
    ? ok('③ 五屏激活宽度均 >350px（壳层未塌）', r3.out.join(' '))
    : bad('③ 页面宽度', r3.out.join(' '));

  /* ④ 分类速记列仍渲染（去教学文案没伤到功能） */
  const r4 = await ev(`document.querySelectorAll('.page').forEach(function(s){s.classList.remove('active')});
    document.getElementById('p-calendar').classList.add('active');
    var el=document.getElementById('catRail2');
    return {exists:!!el, children:el?el.children.length:-1, firstTxt:el&&el.children[0]?el.children[0].innerText.slice(0,10):''};`);
  (r4.exists && r4.children > 0)
    ? ok('④ 块视图右列分类仍在', 'n=' + r4.children)
    : bad('④ 右列分类', JSON.stringify(r4));

  /* ⑤ 逐屏截图（深浅各一）供产品逐屏确认 */
  const nav = async (id, dark) => {
    await ev(`document.documentElement.classList.toggle('dark',${dark});
      document.querySelectorAll('.page').forEach(function(s){s.classList.remove('active')});
      document.getElementById('${id}').classList.add('active');
      window.scrollTo(0,0);return{ok:1};`);
    await wait(220);
    await shot('r1478_' + id + (dark ? '_dark' : '') + '.png');
  };
  await nav('p-profile', false);
  await nav('p-profile', true);
  await nav('p-sub-appearance', false);
  // 块视图在日历屏内，需切到块视图 tab
  await ev(`document.documentElement.classList.toggle('dark',false);
    document.querySelectorAll('.page').forEach(function(s){s.classList.remove('active')});
    document.getElementById('p-calendar').classList.add('active');
    if(typeof switchCalView==='function')switchCalView('block');return{ok:1};`);
  await wait(300);
  await shot('r1478_p-calendar_block.png');

  /* ⑥ 零 JS 异常 */
  (errs.length === 0 ? ok : bad)('⑤ 运行期零 JS 异常', errs.join(' | '));

  finish(chrome);
})();

function finish(chrome) {
  log('== ' + pass + ' PASS / ' + fail + ' FAIL ==');
  try { if (chrome) chrome.kill(); } catch (e) { }
  process.exit(fail ? 1 : 0);
}
