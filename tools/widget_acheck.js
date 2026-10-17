/* 小组件模块 批A · 原型无头回归（2026-10-17 · 规格＝docs/handoff/小组件模块-批A按实例绑定与打卡试点.md §2）
 * 判什么：打卡四格试点样张在位（命名「功能-形态」·四件套模板·未打卡/已打卡双态·深浅双档）·
 *         计数型 ±N 三格（只改显示态）· 失效三态三文案＋点击重绑去向 · 「先选后落」四步流程 ·
 *         桌面示意落一枚打卡 widget · 设置屏小部件卡回灌（打卡-单习惯行＋添加小组件口径）·
 *         运行期零 JS 异常 · 零 emoji。
 * 用法：node --experimental-websocket tools/widget_acheck.js（截图：WA_SHOTS=1，落仓库外 tempWork）
 * 门禁：node tools/widget_acheck.js（违例 exit 1）；变异自证＝改坏一件必须红（放 tmp/，跑完 md5 复原）。 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const DESK = url.pathToFileURL(path.resolve('prototype/index-desktop.html')).href;
const SET = url.pathToFileURL(path.resolve('prototype/index-settings.html')).href;
const PORT = Number(process.env.WA_PORT || 9621);
const SHOTS = process.env.WA_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/wa-shots';
let pass = 0, fail = 0; const errs = []; let child = null;
const log = m => console.log(m);
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(m, p) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method: m, params: p || {} })) }) }
async function ev(x) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + x + '})())' });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 240) } }
}
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
/* 等主脚本就绪：判据＝壳函数已定义（禁固定 sleep——index.html 167KB 主脚本＋Tailwind CDN 实锤过假红）
   注：本机 CDP 实测 IIFE 必须带显式 return（单表达式完成值回 undefined），与 nfc_proto_check 同纪律 */
async function ready(fn) { let last = null; for (let i = 0; i < 80; i++) { last = await ev('return (typeof ' + fn + '==="function")'); if (last === true) return true; await wait(250) } console.log('READY-DBG last=' + JSON.stringify(last)); return false }
async function toastText() { return (await ev("var t=document.getElementById('toast');return t&&!t.classList.contains('hidden')?t.textContent:''")) || '' }

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.wa-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('chrome 起服'); return finish() }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 200)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');

  /* ============ 专版 index-desktop.html ============ */
  await cmd('Page.navigate', { url: DESK });
  if (!await ready('setPage')) { bad('专版主脚本就绪（setPage）'); return finish() }
  ok('专版主脚本就绪');
  /* 页内切换条（2026-10-17 产品反馈「找不到屏」后补·scr-sw）：四枚 chip 可点直达四屏 */
  const r0 = await ev("var b=document.getElementById('scrSw');var bs=b?b.querySelectorAll('button'):[];"
    + "var labels=[];for(var i=0;i<bs.length;i++)labels.push(bs[i].textContent);"
    + "return {n:bs.length,labels:labels,def:document.querySelector('.page.active').id};");
  (r0 && r0.n === 4 && r0.def === 'dt-desk') ? ok('页内切换条四枚 chip 在位（默认落 dt-desk）', (r0.labels || []).join('/')) : bad('切换条缺失或默认屏错', JSON.stringify(r0));
  const r0b = await ev("var b=document.getElementById('scrSw');"
    + "var t=Array.prototype.filter.call(b.querySelectorAll('button'),function(x){return x.getAttribute('data-scr')==='dt-widget'})[0];"
    + "t.click();return document.querySelector('.page.active').id;");
  r0b === 'dt-widget' ? ok('点「小组件规格」chip → 直达 dt-widget（无需深链/控制台）', r0b) : bad('chip 点击切换失效', String(r0b));
  const r0c = await ev("var b=document.getElementById('scrSw');"
    + "var on=Array.prototype.filter.call(b.querySelectorAll('button'),function(x){return x.classList.contains('on')});"
    + "return on.length===1?on[0].getAttribute('data-scr'):'multi:'+on.length;");
  r0c === 'dt-widget' ? ok('chip 高亮与当前屏同步') : bad('chip 高亮不同步', String(r0c));
  await shot('scr-switch');

  /* 2026-10-18 既有 widget 整改（产品反馈）：4×1 两区→三区提密度；待办勾圈示意层可点 */
  const rq = await ev("navTo('dt-desk');var w=Array.prototype.filter.call(document.querySelectorAll('#dt-desk .wg'),function(x){return x.textContent.indexOf('记一笔')>=0})[0];"
    + "var t=w?w.textContent:'';return {has:w?1:0,spend:t.indexOf('今日支出')>=0,left:t.indexOf('本月结余')>=0,noName:t.indexOf('LifeHarness · 快捷记录')<0};");
  (rq && rq.has && rq.spend && rq.left && rq.noName) ? ok('4×1 三区（记一笔｜今日支出｜本月结余·条内不显名）') : bad('4×1 三区改版缺项', JSON.stringify(rq));
  const rt = await ev("navTo('dt-widget');var rows=Array.prototype.slice.call(document.querySelectorAll('#dt-widget .wg-todo'));"
    + "var chk=rows[1].querySelector('.wg-chk');chk.click();"
    + "var done=rows[1].classList.contains('done'),on=chk.classList.contains('on');"
    + "chk.click();var back=!rows[1].classList.contains('done');"
    + "return {n:rows.length,done:done,on:on,back:back};");
  (rt && rt.n === 6 && rt.done && rt.on && rt.back) ? ok('待办勾圈可点（切换完成态·可逆·示意层·深浅各三行）') : bad('待办勾圈点击无效', JSON.stringify(rt));

  /* 2026-10-18 拍板·A 路：4×1「记一笔」＝弹窗记账（dt-desk 可点演示＋dt-widget 规格卡） */
  const rd1 = await ev("navTo('dt-desk');var d=document.getElementById('qpDlg');"
    + "var btn=Array.prototype.filter.call(document.querySelectorAll('#dt-desk .wg-btn'),function(x){return x.textContent.indexOf('记一笔')>=0})[0];"
    + "var hid0=d.classList.contains('hidden');btn.click();var open=!d.classList.contains('hidden');"
    + "var okBtn=d.querySelector('.qp-ok');okBtn.click();var closed=d.classList.contains('hidden');"
    + "var t1=document.getElementById('toast').textContent;"
    + "btn.click();d.querySelector('.qp-no').click();var closed2=d.classList.contains('hidden');"
    + "return {hid0:hid0,open:open,closed:closed,toast:t1,closed2:closed2};");
  (rd1 && rd1.hid0 && rd1.open && rd1.closed && rd1.closed2 && rd1.toast.indexOf('已入账') >= 0 && rd1.toast.indexOf('Dart 写库') >= 0)
    ? ok('记一笔弹窗：默认隐→点开→保存（已入账·交 Dart 写库）→关；取消→关', rd1.toast)
    : bad('弹窗交互缺项', JSON.stringify(rd1));
  const rd2 = await ev("navTo('dt-widget');var t=document.getElementById('dt-widget').textContent;"
    + "return {card:t.indexOf('记一笔 · 弹窗记账')>=0,ruling:t.indexOf('2026-10-18 拍板')>=0,"
    + "dlg:document.querySelectorAll('#dt-widget .qp-dlg').length};");
  (rd2 && rd2.card && rd2.ruling && rd2.dlg === 2) ? ok('dt-widget 弹窗规格卡（深浅双档＋拍板口径＋禁做清单改释）') : bad('弹窗规格卡缺项', JSON.stringify(rd2));
  await shot('dt-desk-quickpopup');
  const r1 = await ev("navTo('dt-widget');var s=document.getElementById('dt-widget');return {on:s.classList.contains('active'),"
    + "name:(s.textContent.match(/打卡-单习惯/g)||[]).length,"
    + "wgName:(s.querySelectorAll('.wg-name').length),"
    + "dot:(s.querySelectorAll('.wg-dot').length),dotOn:s.querySelectorAll('.wg-dot.on').length,"
    + "btn:(s.textContent.match(/打卡/g)||[]).length,"
    + "cnt:(s.querySelectorAll('.wg-cnt').length),cntBtn:(s.querySelectorAll('.wg-cnt-btn').length),"
    + "ph:(s.querySelectorAll('.wg-ph').length),"
    + "flow:(s.querySelectorAll('.flow-step').length),"
    + "wstrip:(s.querySelectorAll('.wstrip span.on').length),"
    + "pair:(s.querySelectorAll('.pair').length)}");
  r1 && r1.on ? ok('dt-widget 屏可达') : bad('dt-widget 屏可达', JSON.stringify(r1));
  (r1 && r1.name >= 2) ? ok('「打卡-单习惯」命名（功能-形态口径）', r1.name + ' 处') : bad('「打卡-单习惯」命名缺失', JSON.stringify(r1));
  (r1 && r1.wgName >= 6) ? ok('四件套之标题（LifeHarness · 打卡）', r1.wgName + ' 处') : bad('标题缺', JSON.stringify(r1));
  (r1 && r1.dot >= 4 && r1.dotOn >= 2) ? ok('四件套之状态点（未打卡空心＋已打卡实心双态）', 'dot=' + r1.dot + ' on=' + r1.dotOn) : bad('状态点双态缺', JSON.stringify(r1));
  (r1 && r1.cnt === 2 && r1.cntBtn === 4) ? ok('计数型 ±N 三格（−5／数值／＋5 × 深浅）', 'cnt=' + r1.cnt + ' btn=' + r1.cntBtn) : bad('计数型 ±N 缺', JSON.stringify(r1));
  (r1 && r1.ph === 3) ? ok('失效三态三格占位', 'ph=' + r1.ph) : bad('失效三态缺', JSON.stringify(r1));
  (r1 && r1.flow === 4) ? ok('「先选后落」四步流程', 'flow=' + r1.flow) : bad('四步流程缺', JSON.stringify(r1));
  (r1 && r1.wstrip === 1) ? ok('五段目标区（打卡段选中态）') : bad('五段选中态缺', JSON.stringify(r1));
  const r1b = await ev("var s=document.getElementById('dt-widget');var t=s.textContent;"
    + "return {wait:t.indexOf('等待数据')>=0,nobind:t.indexOf('未选择内容，点此设置')>=0,dead:t.indexOf('内容已失效，点此重新选择')>=0,"
    + "s1:t.indexOf('设置页入口')>=0,s2:t.indexOf('五段选目标')>=0,s3:t.indexOf('系统确认')>=0,s4:t.indexOf('无感回写')>=0}");
  (r1b && r1b.wait && r1b.nobind && r1b.dead) ? ok('失效三态文案（产品勾定三句）') : bad('失效三态文案缺', JSON.stringify(r1b));
  (r1b && r1b.s1 && r1b.s2 && r1b.s3 && r1b.s4) ? ok('四步流程文案齐') : bad('四步流程文案缺', JSON.stringify(r1b));

  /* 点击冒烟：打卡按钮 → 乐观回显 toast；失效态 → 重绑 toast */
  const clickR = await ev("var s=document.getElementById('dt-widget');"
    + "var b=Array.prototype.find.call(s.querySelectorAll('.wg-btn'),function(x){return x.textContent==='打卡'});"
    + "if(b)b.click();return !!b");
  clickR ? ok('打卡主按钮可点') : bad('打卡主按钮缺失');
  await wait(150);
  const t1 = await toastText();
  t1.indexOf('乐观回显') >= 0 && t1.indexOf('不起 App') >= 0 ? ok('打卡点击 toast＝本地回显→后台 isolate→快照收敛', t1) : bad('打卡点击 toast 不符', t1);
  const clickR2 = await ev("var s=document.getElementById('dt-widget');"
    + "var p=Array.prototype.find.call(s.querySelectorAll('.wg-ph'),function(x){return x.textContent.indexOf('未选择内容')>=0});"
    + "if(p)p.closest('.wg').click();return !!p");
  clickR2 ? ok('失效态可点') : bad('失效态不可点');
  await wait(150);
  const t2 = await toastText();
  t2.indexOf('重绑') >= 0 || t2.indexOf('引导选目标') >= 0 ? ok('失效态点击去向＝起 App 引导重绑', t2) : bad('失效态点击去向不符', t2);
  await shot('dt-widget-checkin');

  /* 桌面示意：dt-desk 落一枚打卡 widget */
  const r2 = await ev("navTo('dt-desk');var s=document.getElementById('dt-desk');var w=Array.prototype.filter.call(s.querySelectorAll('.wg'),function(x){return x.textContent.indexOf('早起')>=0});"
    + "return {n:w.length,t:s.textContent.indexOf('打卡-单习惯')>=0}");
  (r2 && r2.n === 1) ? ok('桌面示意落一枚打卡-单习惯 widget') : bad('桌面示意打卡 widget 缺', JSON.stringify(r2));
  (r2 && r2.t) ? ok('桌面屏说明提及批 A 打卡 widget') : bad('桌面屏说明未提及', JSON.stringify(r2));
  await shot('dt-desk-checkin');

  /* ============ 设置专版 index-settings.html · p-sub-desktop 小部件卡 ============ */
  await cmd('Page.navigate', { url: SET });
  if (!await ready('setPage')) { bad('设置专版主脚本就绪（setPage）'); return finish() }
  const r3 = await ev("setPage('p-sub-desktop');var s=document.getElementById('p-sub-desktop');var t=s.textContent;"
    + "return {on:s.classList.contains('active'),row:t.indexOf('打卡-单习惯（2×2）')>=0,add:t.indexOf('添加小组件')>=0,"
    + "flow:t.indexOf('先选后落')>=0,iso:t.indexOf('后台提交')>=0}");
  (r3 && r3.on && r3.row && r3.add && r3.flow && r3.iso) ? ok('设置屏小部件卡回灌（打卡-单习惯行＋先选后落＋isolate 口径）') : bad('设置屏回灌缺项', JSON.stringify(r3));
  await shot('p-sub-desktop-widgets');

  /* 运行期零异常 ＋ 零 emoji（新样张段） */
  errs.length === 0 ? ok('运行期零 JS 异常') : bad('运行期 JS 异常', errs[0]);
  const em = await ev("var a=document.querySelectorAll('.wg,.flow-step,.wg-ph');var s='';for(var i=0;i<a.length;i++)s+=a[i].textContent;"
    + "return /[\\u{1F300}-\\u{1FAFF}\\u{1F000}-\\u{1F0FF}]/u.test(s)");
  em === false ? ok('新样张零 emoji') : bad('新样张检出 emoji');

  finish();
})().catch(e => { bad('脚本异常', String(e).slice(0, 200)); finish() });

function finish() {
  try { if (child) child.kill() } catch (e) { }
  console.log('—— widget_acheck：' + pass + ' 绿 / ' + fail + ' 红');
  process.exit(fail ? 1 : 0);
}
