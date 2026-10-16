/* NFC 卡片模块 · 原型无头回归（2026-10-15 · 规格＝docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md）
 * 判什么：入口行在位与顺序·落屏与标题·列表与两处计数同源·空态虚线行定式·新建层三态与**目标三区块**
 *         （快捷动作/计时分类/阅读书目·区块间互斥单选·无二级弹层）·名称必填当场校验·新建→自动续写卡·
 *         写卡状态机七态（等待/占用/占用本机/非NDEF/只读/容量/中断/成功回写）·删除三处随动·
 *         贴卡两制（nav 跳转 / 有状态 toggle）·**toggle 全链（开始→回执→● 计时中→再贴结束）**·
 *         目标已失效分支·贴卡去抖 3 秒静默·未绑定→绑定态（保存不写卡）·锁屏与选型两行灰字在位·零 emoji。
 * 用法：node --experimental-websocket tools/nfc_proto_check.js（截图：NFC_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index.html')).href;
const PORT = Number(process.env.NFC_PORT || 9613);
const SHOTS = process.env.NFC_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/nfc-shots';
let pass = 0, fail = 0; const errs = [];
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

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.nfc-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('chrome 起服'); return finish() }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 200)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF });
  // 等主脚本就绪，**不用固定 sleep**（2026-10-16 实锤：index.html 有 167KB 主脚本
  // ＋ Tailwind CDN，固定 2800ms 在本机会整片假红——`setPage is not defined`、
  // `NFC_CARDS is not defined`，而 PAGE ERRORS 是 0、语法检查也全过，
  // 典型的「脚本还没执行完就去断言」，读起来却像原型坏了）。
  // 判据＝主脚本已执行（setPage 已定义）**且** NFC 段已就位（NFC_CARDS 已定义）。
  let ready = false;
  for (let i = 0; i < 40; i++) {
    const r = await ev(`return {s: typeof setPage, n: typeof NFC_CARDS};`);
    if (r.s === 'function' && r.n !== 'undefined') { ready = true; break; }
    await wait(300);
  }
  if (!ready) { bad('原型脚本就绪（setPage/NFC_CARDS 已定义）'); return finish(); }

  /* N1 入口行在位·紧邻「桌面与快捷方式」下一行·张数与列表同源 */
  const n1 = await ev(`setPage('p-profile');var t=$('#p-profile').innerText,ec=$('#nfcEntryCnt').textContent;
    return {has:/NFC 卡片/.test(t),after:/桌面与快捷方式[\\s\\S]*NFC 卡片/.test(t),ec:ec,rows:document.querySelectorAll('#nfcList > div').length};`);
  (n1.has && n1.after && n1.ec === String(n1.rows))
    ? ok('N1 入口行在位（桌面与快捷方式下一行）·张数与列表同源', n1.ec + ' 张 / ' + n1.rows + ' 行') : bad('N1', JSON.stringify(n1));

  /* N2 落屏与标题（三张卡＝计时/阅读/导航 各一） */
  const n2 = await ev(`navTo('p-sub-nfc');var t=$('#nfcList').innerText;
    return {page:curPage,title:$('#pageTitle').textContent,rows:document.querySelectorAll('#nfcList > div').length,cnt:$('#nfcCount').textContent,
      hasCat:/计时 · 学习/.test(t),hasBook:/阅读 · 思考/.test(t),hasNav:/记一笔/.test(t)};`);
  (n2.page === 'p-sub-nfc' && n2.title === 'NFC 卡片' && n2.rows === 3 && n2.cnt === '3' && n2.hasCat && n2.hasBook && n2.hasNav)
    ? ok('N2 落屏 · 三行分别显示目标（计时·学习／阅读·思考，快与慢／记一笔）') : bad('N2', JSON.stringify(n2));
  await shot('nfc-01-list');

  /* N3 空态＝虚线补录行（LH-L04 定式）· 两处计数归零 */
  const n3 = await ev(`var keep=NFC_CARDS.slice();NFC_CARDS=[];renderNfcList();
    var r={empty:$('#nfcList').innerText.trim(),dash:/border-dashed/.test($('#nfcList').innerHTML),cnt:$('#nfcCount').textContent,ec:$('#nfcEntryCnt').textContent};
    NFC_CARDS=keep;renderNfcList();return r;`);
  (n3.empty === '还没有卡片 · 点这里新建' && n3.dash && n3.cnt === '0' && n3.ec === '0')
    ? ok('N3 空态＝虚线行定式·两处计数归零', n3.empty) : bad('N3', JSON.stringify(n3));
  await shot('nfc-02-empty');

  /* N4 新建层：三区块结构（nav 7 / timer_cat 6 / read_book 3）·默认恰 1 枚选中·新建态不露「写入/删除」·名称留空拒收不落库 */
  const n4 = await ev(`nfcNew();var n0=NFC_CARDS.length;
    var g=function(k){return document.querySelectorAll('#nfcTargetBox [data-grp="'+k+'"] .chip').length};
    var r={title:$('#nfcEditTitle').textContent,grpNav:g('nav'),grpCat:g('timer_cat'),grpBook:g('read_book'),
      on:document.querySelectorAll('#nfcTargetBox .chip-on').length,
      opsHidden:$('#nfcEditOps').classList.contains('hidden'),hintHidden:$('#nfcBindHint').classList.contains('hidden')};
    $('#nfcName').value='';nfcSaveEdit();
    r.errShown=!$('#nfcNameErr').classList.contains('hidden');r.stayed=!$('#sheetNfcEdit').classList.contains('hidden');
    r.grew=NFC_CARDS.length-n0;return r;`);
  (n4.title === '新建卡片' && n4.grpNav === 7 && n4.grpCat === 6 && n4.grpBook === 3 && n4.on === 1 &&
    n4.opsHidden && n4.hintHidden && n4.errShown && n4.stayed && n4.grew === 0)
    ? ok('N4 目标三区块（7/6/3）·默认 1 枚选中·名称留空当场拒收且不落库') : bad('N4', JSON.stringify(n4));
  await shot('nfc-03-new');

  /* N5 三区块互斥单选（C28）：选计时分类 → 快捷动作区归零；再选阅读书目 → 计时区归零 */
  const n5 = await ev(`var on=function(k){return document.querySelectorAll('#nfcTargetBox [data-grp="'+k+'"] .chip-on').length};
    nfcPickTarget('timer_cat','c1');var a={nav:on('nav'),cat:on('timer_cat'),book:on('read_book'),total:document.querySelectorAll('#nfcTargetBox .chip-on').length};
    nfcPickTarget('read_book','b1');var b={nav:on('nav'),cat:on('timer_cat'),book:on('read_book')};
    return {a:a,b:b,target:nfcTarget.kind+'/'+nfcTarget.ref};`);
  (n5.a.nav === 0 && n5.a.cat === 1 && n5.a.book === 0 && n5.a.total === 1 &&
    n5.b.nav === 0 && n5.b.cat === 0 && n5.b.book === 1 && n5.target === 'read_book/b1')
    ? ok('N5 三区块互斥单选（选区唯一·无二级弹层）') : bad('N5', JSON.stringify(n5));

  /* N6 新建→自动续写卡（C16）·写卡层状态机七态·成功回写「已写入」 */
  const n6 = await ev(`$('#nfcName').value='书房阅读卡';nfcSaveEdit();
    var n=NFC_CARDS.length,newest=NFC_CARDS[n-1];
    var r={n:n,id:newest.id,kind:newest.kind,ref:newest.ref,wrote0:newest.wrote,
      s1:{editOpen:$('#sheetNfcEdit').classList.contains('sheet-open'),writeOpen:$('#sheetNfcWrite').classList.contains('sheet-open'),state:nfcWriteState,ring:!$('#nfcRing').classList.contains('hidden')}};
    nfcWriteSim('occupied');r.s2={occ:!$('#nfcOccupy').classList.contains('hidden'),txt:$('#nfcWriteState').textContent,sub:$('#nfcOccupyText').textContent};
    nfcWriteSim('occupiedOwn');r.s3={occ:!$('#nfcOccupy').classList.contains('hidden'),btnHidden:$('#nfcOccupy').querySelector('.bg-rose-500').classList.contains('hidden')};
    nfcWriteSim('nonndef');r.s4={err:!$('#nfcErr').classList.contains('hidden'),retry:$('#nfcWriteRetry').textContent,retryHidden:$('#nfcWriteRetry').classList.contains('hidden')};
    nfcWriteSim('readonly');r.s5={retry:$('#nfcWriteRetry').textContent};
    nfcWriteSim('capacity');r.s6=$('#nfcWriteState').textContent;
    nfcWriteSim('broken');r.s7=$('#nfcWriteState').textContent;
    nfcWriteSim('ok');r.s8={ok:!$('#nfcOk').classList.contains('hidden'),ring:$('#nfcRing').classList.contains('hidden'),
      wrote:NFC_CARDS.filter(function(c){return c.id===newest.id;})[0].wrote};
    return r;`);
  (n6.n === 4 && n6.kind === 'read_book' && n6.ref === 'b1' && n6.wrote0 === false &&
    n6.s1.writeOpen && !n6.s1.editOpen && n6.s1.state === 'waiting' && n6.s1.ring &&
    n6.s2.occ && /已有内容/.test(n6.s2.txt) && /原内容会消失/.test(n6.s2.sub) && n6.s3.occ && n6.s3.btnHidden &&
    n6.s4.err && n6.s4.retry === '重试' && !n6.s4.retryHidden && n6.s5.retry === '换卡' &&
    n6.s6 === '卡片容量不足' && n6.s7 === '写入中断' && n6.s8.ok && n6.s8.ring && n6.s8.wrote === true)
    ? ok('N6 新建→自动续写卡·状态机七态齐（占用/占用本机/非NDEF/只读/容量/中断/成功回写）') : bad('N6', JSON.stringify(n6));
  await shot('nfc-04-write-done');

  /* N7 有状态卡 toggle 全链（C19/C20/C22/C23）：贴学习卡＝开始＋回执＋「● 计时中」；再贴＝结束＋回执＋标记消失 */
  const n7 = await ev(`nfcWriteClose();closeSheet('sheetNfcEdit');
    var a=nfcTriggerSim('K7F3M2QX9TBA');var r1={r:a,toast:$('#toast').textContent,row:$('#nfcList').innerText};
    var uses1=NFC_CARDS.filter(function(c){return c.id==='K7F3M2QX9TBA';})[0].uses;
    nfcLastRun={id:null,ts:0};                       /* 模拟超过 3 秒再贴一次 */
    var b=nfcTriggerSim('K7F3M2QX9TBA');var r2={r:b,toast:$('#toast').textContent,row:$('#nfcList').innerText};
    var uses2=NFC_CARDS.filter(function(c){return c.id==='K7F3M2QX9TBA';})[0].uses;
    return {a:r1,b:r2,uses1:uses1,uses2:uses2,runTimer:nfcRunning.timerCat};`);
  (n7.a.r === 'toggle:timer:start' && /开始「学习」计时/.test(n7.a.toast) && /● 计时中/.test(n7.a.row) &&
    n7.b.r === 'toggle:timer:end' && /已结束「学习」/.test(n7.b.toast) && !/● 计时中/.test(n7.b.row) &&
    n7.uses1 === 37 && n7.uses2 === 38 && n7.runTimer === null)
    ? ok('N7 时间卡 toggle 全链：开始→回执→「● 计时中」→再贴结束→标记消失（两次各 +1 计数）') : bad('N7', JSON.stringify(n7));

  /* N8 阅读卡 toggle（C21）：贴＝开始阅读会话＋回执；再贴＝结束本次阅读（非「标记读完」） */
  const n8 = await ev(`var a=nfcTriggerSim('P4N8R2WD6HCZ');var t1=$('#toast').textContent,c1=/● 计时中/.test($('#nfcList').innerText);
    nfcLastRun={id:null,ts:0};
    var b=nfcTriggerSim('P4N8R2WD6HCZ');var t2=$('#toast').textContent,c2=/● 计时中/.test($('#nfcList').innerText);
    return {a:a,t1:t1,c1:c1,b:b,t2:t2,c2:c2,runBook:nfcRunning.book};`);
  (n8.a === 'toggle:read:start' && /开始阅读《思考，快与慢》/.test(n8.t1) && n8.c1 &&
    n8.b === 'toggle:read:end' && /《思考，快与慢》已结束 · 23 分钟/.test(n8.t2) && !n8.c2 && n8.runBook === null)
    ? ok('N8 阅读卡 toggle：开始阅读→回执→再贴＝结束本次阅读（不写「已读完」）') : bad('N8', JSON.stringify(n8));

  /* N9 导航卡：仍走路由跳转、不产生「计时中」标记（两制不串味） */
  const n9 = await ev(`var r=nfcTriggerSim('M9T4XB3JQ7LV');return {r:r,row:/● 计时中/.test($('#nfcList').innerText)};`);
  (n9.r === 'run:ledger' && n9.row === false)
    ? ok('N9 导航卡＝run:ledger·不产生「计时中」标记') : bad('N9', JSON.stringify(n9));

  /* N10 贴卡去抖：同卡 3 秒内第二次静默忽略且不计次（C6/B16） */
  const n10 = await ev(`nfcLastRun={id:null,ts:0};
    var h0=nfcDebounceHits,u0=NFC_CARDS.filter(function(c){return c.id==='K7F3M2QX9TBA';})[0].uses;
    var a=nfcTriggerSim('K7F3M2QX9TBA'),b=nfcTriggerSim('K7F3M2QX9TBA');
    var u1=NFC_CARDS.filter(function(c){return c.id==='K7F3M2QX9TBA';})[0].uses;
    return {a:a,b:b,h0:h0,h1:nfcDebounceHits,u0:u0,u1:u1};`);
  (n10.a === 'toggle:timer:start' && n10.b === 'ignored' && n10.h1 === n10.h0 + 1 && n10.u1 === n10.u0 + 1)
    ? ok('N10 去抖 3 秒：同卡第二次静默忽略且不计次') : bad('N10', JSON.stringify(n10));

  /* N11 目标已失效（C24）：分类/书/动作任一查不到 → 行标「已失效」+ 贴卡 toast，不执行 */
  const n11 = await ev(`NFC_CARDS.push({id:'DEAD00000001',name:'旧卡',kind:'timer_cat',ref:'cX',uses:1,wrote:true,last:'上月'});
    renderNfcList();var marked=/已失效/.test($('#nfcList').innerText);var r=nfcTriggerSim('DEAD00000001');
    return {marked:marked,r:r,toast:$('#toast').textContent};`);
  (n11.marked && n11.r === 'dead' && /已经不在了/.test(n11.toast))
    ? ok('N11 目标已失效：行标「已失效」+ 贴卡 toast「已经不在了」', n11.toast.slice(0, 18)) : bad('N11', JSON.stringify(n11));

  /* N12 未绑定卡片 → 落屏 + 绑定态（预填卡号·三区块可选）·绑定保存即落库并标「已写入」（不重写标签·C3） */
  const n12 = await ev(`nfcLastRun={id:null,ts:0};var r=nfcTriggerSim('ZZ9UNKNOWNID');
    var o={r:r,page:curPage,open:$('#sheetNfcEdit').classList.contains('sheet-open'),title:$('#nfcEditTitle').textContent,
      hintShown:!$('#nfcBindHint').classList.contains('hidden'),hint:$('#nfcBindHint').textContent,opsHidden:$('#nfcEditOps').classList.contains('hidden')};
    nfcPickTarget('timer_cat','c4');$('#nfcName').value='卫生间洗漱卡';nfcSaveEdit();
    var b=NFC_CARDS.filter(function(c){return c.id==='ZZ9UNKNOWNID';})[0];
    o.kind=b?b.kind+'/'+b.ref:null;o.wrote=b?b.wrote:null;o.closed=$('#sheetNfcEdit').classList.contains('hidden');return o;`);
  (n12.r === 'unbound' && n12.page === 'p-sub-nfc' && n12.open && n12.title === '绑定这张卡' && n12.hintShown &&
    /ZZ9UNKNOWNID/.test(n12.hint) && n12.opsHidden && n12.kind === 'timer_cat/c4' && n12.wrote === true && n12.closed)
    ? ok('N12 未绑定卡→绑定态（预填卡号·可选计时分类）·绑定后标「已写入」不写标签') : bad('N12', JSON.stringify(n12));

  /* N13 删除：走独立确认层 → 行数/屏内计数/入口计数三处随动 */
  const n13 = await ev(`var n0=NFC_CARDS.length;nfcEdit('DEAD00000001');nfcAskDel();
    var open=$('#sheetNfcDel').classList.contains('sheet-open'),sum=$('#nfcDelSum').textContent;nfcDelGo();
    var n1=NFC_CARDS.length;
    return {n0:n0,n1:n1,open:open,sum:sum,cnt:$('#nfcCount').textContent,ec:$('#nfcEntryCnt').textContent,rows:document.querySelectorAll('#nfcList > div').length};`);
  (n13.open && /旧卡/.test(n13.sum) && n13.n1 === n13.n0 - 1 && n13.cnt === String(n13.n1) && n13.ec === String(n13.n1) && n13.rows === n13.n1)
    ? ok('N13 删除走独立确认层·行数与两处计数三处随动', n13.cnt + ' 张 / ' + n13.rows + ' 行') : bad('N13', JSON.stringify(n13));

  /* N14 贴卡行为两开关默认态（C5/B17）＋锁屏与选型两行灰字在位（C26/C27）＋零 emoji */
  const n14 = await ev(`var t=$('#p-sub-nfc').innerText;
    var EM=[/\\u{1F000}-\\u{1FAFF}/u,/\\u{2600}-\\u{27BF}/u,/\\u{2B00}-\\u{2BFF}/u];
    return {confirm:nfcPrefs.confirm,prompt:nfcPrefs.prompt,
      confirmOff:!document.querySelector('[data-nfc="confirm"]').classList.contains('on'),
      promptOn:document.querySelector('[data-nfc="prompt"]').classList.contains('on'),
      lock:/锁屏状态下安卓不派发 NFC 事件/.test(t),pick:/NTAG213\\/215\\/216/.test(t),
      emoji:EM.some(function(r){return r.test($('#nfcEntry').innerText+t+$('#sheetNfcEdit').innerText+$('#sheetNfcWrite').innerText+$('#sheetNfcDel').innerText)})};`);
  (n14.confirm === false && n14.prompt === true && n14.confirmOff && n14.promptOn && n14.lock && n14.pick && n14.emoji === false)
    ? ok('N14 两开关默认态（先确认＝关·未识别提示＝开）·锁屏与选型两行在位·零 emoji') : bad('N14', JSON.stringify(n14));

  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail = 1 }
  else log('PAGE ERRORS 0');
  try { if (ws) ws.close() } catch (e) { }
  process.exit(fail ? 1 : 0) }
