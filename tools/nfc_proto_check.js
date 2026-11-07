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
    navTo('p-sub-nfc');var row=document.querySelector('#nfcList > div');var bts=row?row.querySelectorAll('button'):[];
    var ocs=Array.prototype.map.call(bts,function(b){return b.getAttribute('onclick')||''}).join('|');
    return {has:/NFC 卡片/.test(t),after:/桌面与快捷方式[\\s\\S]*NFC 卡片/.test(t),ec:ec,rows:document.querySelectorAll('#nfcList > div').length,
      twoNodes:/nfcEditTarget/.test(ocs)&&/nfcEditCard/.test(ocs),chain:row?!!row.querySelector('svg'):false,
      setBtn:Array.prototype.some.call(document.querySelectorAll('button'),function(b){return (b.getAttribute('onclick')||'').indexOf("openSheet('sheetNfcSet')")>=0})};`);
  (n1.has && n1.after && n1.ec === String(n1.rows) && n1.twoNodes && n1.chain && n1.setBtn)
    ? ok('N1 入口行在位（桌面与快捷方式下一行）·张数与列表同源·列表行＝左目标/右卡片双节点·右上角设置入口在位', n1.ec + ' 张 / ' + n1.rows + ' 行') : bad('N1', JSON.stringify(n1));


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

  /* N4 新建层：三区块结构（nav 7 / 一级分组 11 / 书目收起态 0）·默认恰 1 枚选中·
     分类两级联动（选一级「工作」→ 子分组出现）·书目展开后 3 本·新建态不露「写入/删除」·名称留空拒收不落库 */
  const n4 = await ev(`nfcNew();var n0=NFC_CARDS.length;
    var g=function(k){return document.querySelectorAll('#nfcTargetBox [data-grp="'+k+'"] .chip').length};
    var g1=function(l){return document.querySelectorAll('#nfcTargetBox [data-lvl="'+l+'"] .chip').length};
    var r={title:$('#nfcEditTitle').textContent,tab:nfcTab,
      tabs:document.querySelectorAll('#nfcTargetBox > div:first-child .chip').length,
      grpNav:g('nav'),grpCat:g('timer_cat'),grpBook:g('read_book'),
      on:document.querySelectorAll('#nfcTargetBox [data-grp] .chip-on').length,
      opsHidden:$('#nfcEditOps').classList.contains('hidden'),hintHidden:$('#nfcBindHint').classList.contains('hidden')};
    r.tabLabels=Array.prototype.map.call(document.querySelectorAll('#nfcTargetBox > div:first-child .chip'),function(b){return b.textContent.trim()}).join('/');
    nfcTabTo('habit');r.habitSubs=g1('1');r.habitTgt=nfcTarget.ref+'/'+nfcTarget.sub;r.habitEmoji=/[\\u{1F000}-\\u{1FAFF}\\u{2600}-\\u{27BF}]/u.test(document.querySelector('#nfcTargetBox [data-grp="habit"]').innerText);
    nfcTabTo('care');r.babyLvl1=g1('1');r.careLvl2=g1('2');r.careTgt=nfcTarget.ref+'/'+nfcTarget.sub;
    nfcTabTo('nav');r.backSub=nfcTarget.sub;
    nfcTabTo('timer_cat');r.tab2=nfcTab;r.lvl1=g1('1');r.lvl2=g1('2');
    r.on2=document.querySelectorAll('#nfcTargetBox [data-grp] .chip-on').length;
    nfcTabTo('read_book');r.tab3=nfcTab;r.bookClosed=document.querySelectorAll('#nfcBookList button').length;
    nfcToggleBooks();r.bookOpen=document.querySelectorAll('#nfcBookList button').length;nfcToggleBooks();
    $('#nfcName').value='';nfcSaveEdit();
    r.errShown=!$('#nfcNameErr').classList.contains('hidden');r.stayed=!$('#sheetNfcEdit').classList.contains('hidden');
    r.grew=NFC_CARDS.length-n0;return r;`);
  (n4.title === '新建卡片' && n4.tab === 'nav' && n4.tabs === 5 && n4.tabLabels === '快捷动作/打卡/呵护宝宝/计时分类/阅读书目' && n4.grpNav === 6 && n4.grpCat === 0 && n4.grpBook === 0 &&
    n4.on === 1 && n4.habitSubs === 5 && /^habit\/.+/.test(n4.habitTgt) && n4.habitEmoji === false &&
    n4.babyLvl1 === 2 && n4.careLvl2 === 3 && /^care\/baby\d\/(milk|sleep|dia)$/.test(n4.careTgt) && n4.backSub === null &&
    n4.tab2 === 'timer_cat' && n4.lvl1 === 11 && n4.lvl2 === 2 && n4.on2 === 1 &&
    n4.tab3 === 'read_book' && n4.bookClosed === 0 && n4.bookOpen === 3 &&
    n4.opsHidden && n4.hintHidden && n4.errShown && n4.stayed && n4.grew === 0)
    ? ok('N4 五大类横向 tab（5 段·一次只显示一区）·快捷动作 6 枚·打卡大类 5 条习惯（零 emoji）·呵护宝宝大类 2×3·分类 11/2·书目 0→3·名称留空当场拒收且不落库') : bad('N4', JSON.stringify(n4));

  await shot('nfc-03-new');

  /* N5 tab 互斥（一屏一区·选区唯一）＋ 分类两级联动（父子双高亮·再点取消·无次级提示）＋ 书目搜索：
     切「计时分类」→ 快捷动作归零、默认选中一级「工作」；选子类「开会」→ 父子双高亮；再点＝回退父级；
     切「阅读书目」→ 分类归零、目标落到默认书；展开 3 本、搜索「快」过滤到 1 本；选书 → 下拉自动收起 */
  const n5 = await ev(`nfcNew();
    var on=function(k){return document.querySelectorAll('#nfcTargetBox [data-grp="'+k+'"] .chip-on').length};
    var hitxt=function(){return Array.prototype.map.call(document.querySelectorAll('#nfcTargetBox [data-lvl] .chip-on'),function(e){return e.textContent.trim()}).join('+')};
    nfcTabTo('timer_cat');
    var a={tab:nfcTab,nav:on('nav'),cat:on('timer_cat'),total:document.querySelectorAll('#nfcTargetBox [data-grp] .chip-on').length,
      target:nfcTarget.kind+'/'+nfcTarget.ref};
    nfcPickCat2('工作','开会');var a2=nfcTarget.ref,hi2=hitxt(),n2=on('timer_cat');
    nfcPickCat2('工作','开会');var a3=nfcTarget.ref,hi3=hitxt();
    nfcPickCat1('学习');var noSub=document.querySelector('#nfcTargetBox [data-grp="timer_cat"]').innerText.indexOf('该分类无次级')>=0;
    nfcTabTo('read_book');
    var b0={nav:on('nav'),cat:on('timer_cat'),target:nfcTarget.kind+'/'+nfcTarget.ref};
    nfcToggleBooks();var listLen=document.querySelectorAll('#nfcBookList button').length;
    nfcBookFilter('快');var filtered=document.querySelectorAll('#nfcBookList button').length;nfcBookFilter('');
    nfcPickBook('b1');
    var b={tab:nfcTab,nav:on('nav'),cat:on('timer_cat'),target:nfcTarget.kind+'/'+nfcTarget.ref,listGone:document.getElementById('nfcBookList')===null};
    return {a:a,a2:a2,hi2:hi2,n2:n2,a3:a3,hi3:hi3,noSub:noSub,b0:b0,listLen:listLen,filtered:filtered,b:b};`);
  (n5.a.tab === 'timer_cat' && n5.a.nav === 0 && n5.a.cat === 1 && n5.a.total === 1 && n5.a.target === 'timer_cat/工作' &&
    n5.a2 === '开会' && n5.n2 === 2 && n5.hi2 === '工作+开会' &&
    n5.a3 === '工作' && n5.hi3 === '工作' && n5.noSub &&
    n5.b0.nav === 0 && n5.b0.cat === 0 && n5.b0.target === 'read_book/b1' &&
    n5.listLen === 3 && n5.filtered === 1 &&
    n5.b.tab === 'read_book' && n5.b.target === 'read_book/b1' && n5.b.listGone)
    ? ok('N5 三区块 tab 互斥（一屏一区·选区唯一）＋分类两级联动（父子双高亮·再点取消·无次级提示）＋书目搜索过滤') : bad('N5', JSON.stringify(n5));

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

  /* N14 贴卡行为两开关默认态（C5/B17·已收进右上角设置层）＋锁屏与选型两行灰字在位（C26/C27）＋零 emoji */
  const n14 = await ev(`var t=$('#p-sub-nfc').innerText;
    var EM=[/\\u{1F000}-\\u{1FAFF}/u,/\\u{2600}-\\u{27BF}/u,/\\u{2B00}-\\u{2BFF}/u];
    return {confirm:nfcPrefs.confirm,prompt:nfcPrefs.prompt,
      confirmOff:!document.querySelector('[data-nfc="confirm"]').classList.contains('on'),
      promptOn:document.querySelector('[data-nfc="prompt"]').classList.contains('on'),
      inSetSheet:!!document.querySelector('#sheetNfcSet [data-nfc="confirm"]')&&!!document.querySelector('#sheetNfcSet [data-nfc="prompt"]'),
      outOfScreen:!document.querySelector('#p-sub-nfc [data-nfc="confirm"]'),
      lock:/锁屏状态下安卓不派发 NFC 事件/.test(t),pick:/NTAG213\\/215\\/216/.test(t),
      emoji:EM.some(function(r){return r.test($('#nfcEntry').innerText+t+$('#sheetNfcEdit').innerText+$('#sheetNfcWrite').innerText+$('#sheetNfcDel').innerText+$('#sheetNfcSet').innerText)})};`);
  (n14.confirm === false && n14.prompt === true && n14.confirmOff && n14.promptOn && n14.inSetSheet && n14.outOfScreen && n14.lock && n14.pick && n14.emoji === false)
    ? ok('N14 两开关默认态（先确认＝关·未识别提示＝开·已从屏内收进右上角设置层）·锁屏与选型两行在位·零 emoji') : bad('N14', JSON.stringify(n14));


  /* N15 双节点列表与两形态弹层（产品令 2026-10-17）：左＝绑定目标（点＝只改目标）·右＝卡片（点＝只改卡片信息） */
  const n15 = await ev(`navTo('p-sub-nfc');var id=NFC_CARDS[0].id;
    nfcEditCard(id);
    var r={card:{mode:nfcEditMode,title:$('#nfcEditTitle').textContent,cardOn:!$('#nfcCardBlock').classList.contains('hidden'),
      tgtOff:$('#nfcTargetBlock').classList.contains('hidden'),ops:!$('#nfcEditOps').classList.contains('hidden'),
      name:$('#nfcName').value,desc:$('#nfcDesc').value,sum:$('#nfcTargetSum').textContent,colors:document.querySelectorAll('#nfcColorRow button').length}};
    closeSheet('sheetNfcEdit');
    nfcEditTarget(id);
    r.tgt={mode:nfcEditMode,title:$('#nfcEditTitle').textContent,cardOff:$('#nfcCardBlock').classList.contains('hidden'),
      tgtOn:!$('#nfcTargetBlock').classList.contains('hidden'),opsOff:$('#nfcEditOps').classList.contains('hidden')};
    closeSheet('sheetNfcEdit');
    nfcEdit(id);
    r.full={mode:nfcEditMode,cardOn:!$('#nfcCardBlock').classList.contains('hidden'),tgtOn:!$('#nfcTargetBlock').classList.contains('hidden')};
    closeSheet('sheetNfcEdit');
    /* 只改目标：卡片信息不动 */
    nfcEditTarget(id);nfcTabTo('habit');nfcPickHabit(0);nfcSaveEdit();
    var c=nfcById(id);r.saved={kind:c.kind,ref:c.ref,sub:c.sub,name:c.name,desc:c.desc,color:c.color,label:nfcTargetLabel(c)};
    /* 只改卡片信息：目标不动 */
    nfcEditCard(id);$('#nfcName').value='改名后的卡';$('#nfcDesc').value='新描述';nfcPickColor(3);nfcSaveEdit();
    var c2=nfcById(id);r.saved2={name:c2.name,desc:c2.desc,color:c2.color,ref:c2.ref,sub:c2.sub};
    return r;`);
  (n15.card.mode === 'card' && n15.card.cardOn && n15.card.tgtOff && n15.card.ops && n15.card.colors === 6 &&
    n15.card.name === '书桌学习卡' && n15.card.desc === '坐下就计时' && n15.card.sum === '计时 · 学习' &&
    n15.tgt.mode === 'target' && n15.tgt.cardOff && n15.tgt.tgtOn && n15.tgt.opsOff &&
    n15.full.mode === 'full' && n15.full.cardOn && n15.full.tgtOn &&
    n15.saved.kind === 'nav' && n15.saved.ref === 'habit' && /晨间跑步/.test(n15.saved.sub) && n15.saved.name === '书桌学习卡' &&
    n15.saved.desc === '坐下就计时' && n15.saved.color === 0 && /打卡 · 晨间跑步/.test(n15.saved.label) &&
    n15.saved2.name === '改名后的卡' && n15.saved2.desc === '新描述' && n15.saved2.color === 3 &&
    n15.saved2.ref === 'habit' && n15.saved2.sub === n15.saved.sub)
    ? ok('N15 双节点两形态弹层：右节点＝卡片信息（名称/描述/6 色/目标摘要）·左节点＝绑定目标（仅目标区）·新建＝全量；只改目标不动卡片、只改卡片不动目标') : bad('N15', JSON.stringify(n15));

  /* N16 贴卡回执双态口径回灌（批3e/3f·2026-10-17 产品令）：前台 toast／后台自绘悬浮横幅
     · 左→右＋右→左两格示意（方向逐次交替）· 2.6s 滑出 · 通知栏零条目 */
  const n16 = await ev(`var t=$('#p-sub-nfc').innerText, s=$('#sheetNfcSet').innerText;
    var card=document.evaluate("//div[contains(@class,'card')][contains(.,'贴卡回执长什么样')]",document,null,9,null).singleNodeValue;
    var cells=card?card.querySelectorAll('.grid > div'):[];
    return {card:!!card,
      title:/贴卡回执长什么样/.test(t),
      l2r:!!cells[0]&&/第一次 · 左→右/.test(cells[0].innerText)&&/开始「学习」计时/.test(cells[0].innerText),
      r2l:!!cells[1]&&/第二次 · 右→左/.test(cells[1].innerText)&&/已结束「学习」计时/.test(cells[1].innerText),
      alt:/方向交替/.test(t),
      noNotif:/不会在通知栏留条目/.test(t),
      setRow:/回执方式/.test(s)&&/不在通知栏留条目/.test(s),
      src:/原生自绘悬浮横幅/.test(document.documentElement.innerHTML)};`);
  (n16.card && n16.title && n16.l2r && n16.r2l && n16.alt && n16.noNotif && n16.setRow && n16.src)
    ? ok('N16 回执双态回灌：前台 toast／后台自绘横幅·左→右＋右→左两格示意·方向交替·通知栏零条目·设置层有回执方式行') : bad('N16', JSON.stringify(n16));
  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail = 1 }
  else log('PAGE ERRORS 0');
  try { if (ws) ws.close() } catch (e) { }
  process.exit(fail ? 1 : 0) }
