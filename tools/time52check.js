/* V1.52 时间模块原型回归 · 统一编辑弹层 / 今天计时 / 自动收口 / 补录守卫
 * 用法：node --experimental-websocket tools/time52check.js（截图：T52_SHOTS=1） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.T52_PORT || 9553);
const SHOTS = process.env.T52_SHOTS === '1';
const SHOTDIR = 'prototype/shots/time52';
const LOG = 'tools/time52-run.log';
let pass = 0, fail = 0; const errs = [];
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m) };
fs.writeFileSync(LOG, '== time52check start ' + new Date().toISOString() + ' ==\n');
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

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.t52-profile'), '--disable-extensions', '--no-default-browser-check',
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

  const boot = await ev(`setPage('p-calendar');return {p:curPage,view:calDay}`);
  (boot.p === 'p-calendar') ? ok('进入时间页') : bad('进入时间页', JSON.stringify(boot));

  /* T1 · 今天 FAB → 弹层默认起止=当前 */
  const t1 = await ev(`
    const n=nowMin();
    openTimePick(19);
    const s=tpMin('tpSh')*60+tpMin('tpSm'),e=tpEd();
    const r={open:!!document.querySelector('#sheetTimePick.sheet-open'),title:$('#tpTitle').textContent,s:s,e:e,n:n,
      foot:$('#tpFoot').textContent.replace(/\\s+/g,''),hint:$('#tpHintEl').textContent};
    closeSheet('sheetTimePick');return r`);
  (t1.open && t1.s === t1.n && t1.e === t1.n && /添加$/.test(t1.foot) && !/删除/.test(t1.foot))
    ? ok('T1 今天默认当前时刻') : bad('T1', JSON.stringify(t1));

  /* T2 · 确认添加 → 计时中块（轴视图带「■ 结束计时」） */
  const t2 = await ev(`
    openTimePick(19);
    tpAdd(0);
    const b=timingBlk();
    return {tm:!!b,note:b&&b.note,btns:[...document.querySelectorAll('#timeAxis button')].map(x=>x.textContent).join('|'),
      axis:$('#timeAxis').textContent.includes('计时中')}`);
  (t2.tm && /结束计时/.test(t2.btns) && t2.axis) ? ok('T2 添加即计时中·卡片带结束计时钮') : bad('T2', JSON.stringify(t2));
  await shot('t2-axis-timing');

  /* T3 · 块视图点已有计时块 → 编辑弹层（预填+结束计时+删除+保存） */
  const t3 = await ev(`
    switchCalView('block');
    const b=timingBlk();openBlockEdit(b);
    const r={title:$('#tpTitle').textContent,foot:$('#tpFoot').textContent.replace(/\\s+/g,''),
      s:tpMin('tpSh')*60+tpMin('tpSm'),bs:b.s,hint:$('#tpHintEl').textContent};
    return r`);
  (t3.title === '编辑事件 / 时间块' && /删除/.test(t3.foot) && /结束计时/.test(t3.foot) && /保存修改/.test(t3.foot) && t3.s === t3.bs)
    ? ok('T3 点已有块→统一编辑弹层预填') : bad('T3', JSON.stringify(t3));
  await shot('t3-edit-sheet');

  /* T4 · 弹层内「■ 结束计时」→ 收口 */
  const t4 = await ev(`const pre={edit:!!tpEdit,tm:tpEdit&&tpEdit.tm,tb:!!timingBlk()};tpEnd();const b=timingBlk();return {pre:pre,none:!b,open:!!document.querySelector('#sheetTimePick.sheet-open')}`);
  (t4.none && !t4.open && t4.pre.edit && t4.pre.tm===1) ? ok('T4 结束计时收口·弹层关闭') : bad('T4', JSON.stringify(t4));

  /* T5 · 非今天补录：无计时钮、落在那一天 */
  const t5 = await ev(`
    openTimePick(28,9,30);
    const r0={hint:$('#tpHintEl').textContent,foot:$('#tpFoot').textContent.replace(/\\s+/g,'')};
    tpSetWheel('tpSd',28-1);tpSetWheel('tpEd',28-1);tpSetWheel('tpSh',9);tpSetWheel('tpSm',30);tpSetWheel('tpEh',9);tpSetWheel('tpEm',45);
    tpAdd(0);
    const d28=dayBlocks(28);
    setDay(28);switchCalView('axis');
    const axisTxt=$('#timeAxis').textContent;
    return {r0:r0,n28:d28.length,blk:d28.map(b=>b.cat+' '+fmt(b.s)+'-'+fmt(b.e)),noTimer:!axisTxt.includes('结束计时'),hasEnt:d28.some(b=>b.s===570)};`);
  (t5.n28 === 2 && t5.hasEnt && t5.noTimer && !/结束计时/.test(t5.r0.foot))
    ? ok('T5 非今天补录·无计时钮·落日显示') : bad('T5', JSON.stringify(t5));
  await shot('t5-day28-axis');

  /* T6 · 计时中 + 再添加（起始≥a）→ a 自动收口 */
  const t6 = await ev(`
    setDay(19);
    const n=nowMin();openTimePick(19);tpAdd(0);
    const a=timingBlk();
    openTimePick(19);
    tpSetWheel('tpSh',Math.floor(n/60));tpSetWheel('tpSm',n%60);
    tpSetWheel('tpEh',Math.floor(n/60));tpSetWheel('tpEm',n%60);
    tpDur(10);tpAdd(0);
    const still=timingBlk();
    const aB=blocks.find(b=>b.day===19&&b.s===n&&b.tm!==1);
    return {aExisted:!!a,still:!!still,aEnd:aB?aB.e>=n:null,ab:!!aB};`);
  (!t6.still && t6.aExisted) ? ok('T6 后续事件自动关闭计时中事件') : bad('T6', JSON.stringify(t6));

  /* T7 · 补录跨越计时块起点 → 守卫拒绝；完全早于计时块 → 允许且不收口 */
  const t7 = await ev(`
    openTimePick(19);tpAdd(0);
    const tbS=timingBlk().s;
    const setW=(sh,sm,eh,em)=>{tpSetWheel('tpSd',19-1);tpSetWheel('tpEd',19-1);tpSetWheel('tpSh',sh);tpSetWheel('tpSm',sm);tpSetWheel('tpEh',eh);tpSetWheel('tpEm',em)};
    /* 7a 跨越：start=tbS-30 · end=tbS+30 → 应拒绝 */
    openTimePick(19);const before=blocks.length;
    setW(Math.floor((tbS-30)/60),(tbS-30)%60,Math.floor((tbS+30)/60),(tbS+30)%60);
    tpAdd(0);
    const cross={stillTim:!!timingBlk(),notAdded:blocks.length===before};
    /* 7b 完全早于：start=tbS-90 · end=tbS-60 → 应添加成功且计时块仍进行中 */
    openTimePick(19);const b2=blocks.length;
    setW(Math.floor((tbS-90)/60),(tbS-90)%60,Math.floor((tbS-60)/60),(tbS-60)%60);
    tpAdd(0);
    const early={added:blocks.length===b2+1,stillTim:!!timingBlk(),sameS:timingBlk()&&timingBlk().s===tbS};
    closeSheet('sheetTimePick');
    return {cross:cross,early:early,tbS:tbS}`);
  (t7.cross.stillTim && t7.cross.notAdded && t7.early.added && t7.early.stillTim && t7.early.sameS)
    ? ok('T7 跨越计时块起点的补录被拒·更早补录不收口') : bad('T7', JSON.stringify(t7));

  /* T8 · 日视图点事件卡 → 编辑弹层；改分类保存生效 */
  const t8 = await ev(`
    const b=timingBlk();if(b)tpEnd();
    switchCalView('day');
    const tgt=dayBlocks(19).find(x=>x.note==='晨间规划');
    openBlockEdit(tgt);
    const pre={title:$('#tpTitle').textContent,cat:tpSel.cat,note:$('#tpNote').value};
    tpCat('学习');tpSave();
    const after=blocks.find(x=>x===tgt);
    return {pre:pre,cat:after.cat,same:after.s===540};`);
  (t8.pre.title === '编辑事件 / 时间块' && t8.pre.cat === '工作' && t8.pre.note === '晨间规划' && t8.cat === '学习' && t8.same)
    ? ok('T8 日视图编辑改分类保存生效') : bad('T8', JSON.stringify(t8));

  /* T9 · 周视图点块 → 编辑弹层；空格子 → 添加弹层 */
  const t9 = await ev(`
    switchCalView('week');
    const cell=[...document.querySelectorAll('#calWeekGrid [onclick*="openBlockEdit"]')][0];
    const empty=[...document.querySelectorAll('#calWeekGrid [onclick*="openTimePick"]')][0];
    const r={hasBlock:!!cell,hasEmpty:!!empty};
    cell&&cell.click();
    r.titleEdit=$('#tpTitle').textContent;r.openEdit=!!document.querySelector('#sheetTimePick.sheet-open');
    closeSheet('sheetTimePick');
    empty&&empty.click();
    r.titleAdd=$('#tpTitle').textContent;
    closeSheet('sheetTimePick');return r`);
  (t9.hasBlock && t9.hasEmpty && t9.titleEdit === '编辑事件 / 时间块' && t9.titleAdd === '添加事件 / 时间块')
    ? ok('T9 周视图块编辑/空格添加') : bad('T9', JSON.stringify(t9));

  /* T10 · 分类速记=直接开一段计时块（并收口上一段）· 全站单一「计时中」状态 */
  const t10 = await ev(`
    switchCalView('block');
    const n=nowMin();openTimePick(19);tpAdd(0);
    const first=timingBlk();const had=!!first;
    railTap('餐饮');
    const now=timingBlk();
    return {had:had,one:!!now,cat:now&&now.cat,firstClosed:first?!!first.tm:false,
      total:blocks.filter(b=>b.tm).length};`);
  (t10.had && t10.one && t10.cat === '餐饮' && !t10.firstClosed && t10.total === 1)
    ? ok('T10 速记开计时块·上一段自动收口·全局单活') : bad('T10', JSON.stringify(t10));

  /* T10b · 非今天不允速记计时 */
  const t10b = await ev(`
    const cur=timingBlk();if(cur){tpEdit=cur;tpEnd()}
    setDay(21);railTap('娱乐');
    const r={none:!timingBlk(),added:blocks.filter(b=>b.cat==='娱乐'&&b.tm).length};
    setDay(19);return r`);
  (t10b.none && t10b.added === 0) ? ok('T10b 非今天速记计时被拒') : bad('T10b', JSON.stringify(t10b));

  /* T11 · 周视图：非整点起始块可见 + 格内显示名称与时长 */
  const t11 = await ev(`
    setDay(19);switchCalView('week');
    const before=blocks.length;
    const nb={day:19,s:965,e:972,cat:'工作',note:'周视图验证块'};blocks.push(nb);renderCal();
    const cells=[...document.querySelectorAll('#calWeekGrid [onclick*="openBlockEdit"]')];
    const found=cells.filter(c=>(c.getAttribute('title')||'').includes('周视图验证块'));
    const r={found:found.length,visible:found.some(c=>c.textContent.includes('周视图验证块')),dur:found.some(c=>/7分/.test(c.textContent)),total:cells.length};
    blocks=blocks.filter(x=>x!==nb);renderCal();
    return r`);
  (t11.found === 1 && t11.visible && t11.dur) ? ok('T11 周视图非整点块可见·格内显名称时长') : bad('T11', JSON.stringify(t11));

  /* T12 · 已结束块：对半拆分 */
  const t12 = await ev(`
    const nb={day:19,s:600,e:660,cat:'工作',note:'拆分块'};blocks.push(nb);renderCal();
    openBlockEdit(nb);
    const smVisible=!$('#tpSM').classList.contains('hidden');
    const btns=$('#tpSM').textContent;
    tpSplit();
    const parts=blocks.filter(x=>x.note==='拆分块').map(x=>[x.s,x.e]).sort((a,b)=>a[0]-b[0]);
    return {smVisible:smVisible,btns:btns.replace(/\\s+/g,'|'),n:parts.length,p:parts}`);
  (t12.smVisible && /对半拆分/.test(t12.btns) && /与上一个合并/.test(t12.btns) && /与下一个合并/.test(t12.btns)
    && t12.n === 2 && t12.p[0][0] === 600 && t12.p[0][1] === 630 && t12.p[1][0] === 630 && t12.p[1][1] === 660)
    ? ok('T12 三钮齐·对半拆分 60-660 → 60-630/630-660') : bad('T12', JSON.stringify(t12));

  /* T13 · 与下一个合并还原 */
  const t13 = await ev(`
    const a=blocks.filter(x=>x.note==='拆分块').sort((p,q)=>p.s-q.s)[0];
    openBlockEdit(a);tpMerge(1);
    const left=blocks.filter(x=>x.note==='拆分块');
    return {n:left.length,span:left[0]&&[left[0].s,left[0].e]}`);
  (t13.n === 1 && t13.span[0] === 600 && t13.span[1] === 660) ? ok('T13 与下一个合并还原整段') : bad('T13', JSON.stringify(t13));

  /* T14 · 计时中块不显示拆分/合并 */
  const t14 = await ev(`
    const nb=blocks.filter(x=>x.note==='拆分块')[0];blocks=blocks.filter(x=>x!==nb);
    openTimePick(19);tpAdd(0);
    const tb=timingBlk();openBlockEdit(tb);
    const hidden=$('#tpSM').classList.contains('hidden');
    const hasEnd=/结束计时/.test($('#tpFoot').textContent);
    tpEnd();closeSheet('sheetTimePick');
    return {hidden:hidden,hasEnd:hasEnd}`);
  (t14.hidden && t14.hasEnd) ? ok('T14 计时中无拆分合并·仅结束计时') : bad('T14', JSON.stringify(t14));

  /* T15 · 轴视图副行不再重复起止时间 */
  const t15 = await ev(`
    setDay(19);switchCalView('axis');
    const card=[...document.querySelectorAll('#timeAxis .card')].find(c=>c.textContent.includes('产品评审'));
    return {txt:card?card.textContent.replace(/\\s+/g,' '):''}`);
  (!/10:00 – 11:00/.test(t15.txt) && /60 分钟/.test(t15.txt)) ? ok('T15 轴视图副行去起止时间') : bad('T15', JSON.stringify(t15));

  /* T16 · 分钟滚轮 1 分粒度 · 默认精确到当前分钟 */
  const t16 = await ev(`
    const len=TP_MINS.length,twl=TW_MINS.length;
    openTimePick(19);
    const s=tpMin('tpSh')*60+tpMin('tpSm'),n=nowMin();
    tpSetWheel('tpSm',37);const m=tpMin('tpSm');
    closeSheet('sheetTimePick');
    return {len:len,twl:twl,diff:Math.abs(s-n),m37:m,cap:document.body.innerHTML.includes('1 分一档')&&!document.body.innerHTML.includes('5 分一档')};`);
  (t16.len === 60 && t16.twl === 12 && t16.diff <= 1 && t16.m37 === 37 && t16.cap)
    ? ok('T16 事件弹层 1 分粒度·待办侧保持 5 分档') : bad('T16', JSON.stringify(t16));

  /* T17 · 滚轮循环：59 再下一格回到 00 */
  const t17 = await ev(`
    openTimePick(19);
    wReg('tpSm',TP_MINS,59,tpUpd);
    const w=WHEELS.tpSm,pos=Math.floor(w._rep/2)*60+59,H=WI_H;
    w._bx.scrollTop=pos*H;commitW('tpSm');const at59=WHEELS.tpSm.i;
    w._bx.scrollTop=(pos+1)*H;commitW('tpSm');const down=WHEELS.tpSm.i;
    w._bx.scrollTop=(pos-1)*H;commitW('tpSm');const up=WHEELS.tpSm.i;
    closeSheet('sheetTimePick');
    return {at59:at59,down:down,up:up}`);
  (t17.at59 === 59 && t17.down === 0 && t17.up === 58) ? ok('T17 分钟滚轮循环滚动') : bad('T17', JSON.stringify(t17));

  /* T18 · 弹层瘦身：滚轮 3 行小档距 · 分类每行 6 个 · 时长快捷已删 · 标签/管理并入一级分组行 */
  const t18 = await ev(`
    setDay(19);openTimePick(19);
    const wb=document.querySelector('#tpSm .wheelbox'),it=document.querySelector('#tpSm .witem');
    const cats=document.querySelector('#tpCats');
    const cols=getComputedStyle(cats).gridTemplateColumns.split(' ').length;
    const panel=document.querySelector('#sheetTimePick .sheet-panel');
    const hdr=cats.previousElementSibling;
    const r={rows:wb.offsetHeight/it.offsetHeight,wbH:wb.offsetHeight,itemH:it.offsetHeight,cols:cols,
      catRows:new Set([...cats.children].map(c=>Math.round(c.offsetTop))).size,
      durGone:![...document.querySelectorAll('#sheetTimePick button')].some(b=>/^\\d+(分|时)$/.test(b.textContent.trim())),
      hasTag:/标签/.test(hdr.textContent),hasMng:/管理/.test(hdr.textContent),
      subsDisplay:getComputedStyle(document.querySelector('#tpSubs')).display,
      panelH:panel.offsetHeight,vh:window.innerHeight};
    closeSheet('sheetTimePick');return r`);
  (t18.rows === 3 && t18.cols === 6 && t18.subsDisplay === "flex" && t18.durGone && t18.hasTag && t18.hasMng && t18.panelH < t18.vh * 0.8)
    ? ok('T18 弹层瘦身·滚轮3行·分类6列·时长钮删除') : bad('T18', JSON.stringify(t18));

  /* T19 · 「管理」跳分类管理页 */
  const t19 = await ev(`
    openTimePick(19);
    const btn=[...document.querySelectorAll('#sheetTimePick button')].find(b=>b.textContent.includes('管理'));
    btn.click();
    return {page:curPage,sheetOpen:!!document.querySelector('#sheetTimePick.sheet-open'),hasAdd:!!document.querySelector('#catTree')};`);
  (t19.page === 'p-sub-cats' && !t19.sheetOpen && t19.hasAdd) ? ok('T19 管理钮直达分类管理页') : bad('T19', JSON.stringify(t19));

  /* T20 · 月历圆点随 blocks 实算 */
  const t20 = await ev(`
    const tb=timingBlk();if(tb){tpEdit=tb;tpEnd()}
    expandMonth();
    const none=dayStatus(5);
    const b7={day:7,s:600,e:630,cat:'工作',note:'点7'};const bd={day:6,s:600,e:630,cat:'工作',note:'点6',dn:1};
    blocks.push(b7,bd);renderCal();
    const btn7=[...document.querySelectorAll('#monthGrid button')].find(x=>x.textContent.trim().startsWith('7'));
    const btn6=[...document.querySelectorAll('#monthGrid button')].find(x=>x.textContent.trim().startsWith('6'));
    const r={none:none,s7:dayStatus(7),dot7:!!btn7.querySelector('span'),cls7:btn7.querySelector('span')?btn7.querySelector('span').className:'',
      s6:dayStatus(6),cls6:btn6.querySelector('span')?btn6.querySelector('span').className:''};
    blocks=blocks.filter(x=>x!==b7&&x!==bd);renderCal();return r`);
  (t20.none === null && t20.s7 === 'plan' && t20.dot7 && /bg-brand-400/.test(t20.cls7) && t20.s6 === 'done' && /bg-emerald-400/.test(t20.cls6))
    ? ok('T20 月历圆点实算·无块不显点/完成绿/计划蓝') : bad('T20', JSON.stringify(t20));

  /* T21 · 轴视图每段空隙可点 · 打开时刻与该段标注一致 */
  const t21 = await ev(`
    setDay(19);switchCalView('axis');
    const gaps=[...document.querySelectorAll('#timeAxis [onclick*="openTimePick"]')].filter(b=>b.textContent.includes('空闲'));
    const first=gaps[0];
    const shown=first.textContent.match(/空闲 (\\d\\d):(\\d\\d)/);
    first.click();
    const s=tpMin('tpSh')*60+tpMin('tpSm');
    closeSheet('sheetTimePick');
    return {n:gaps.length,shown:shown?+shown[1]*60+ +shown[2]:-1,s:s,label:first.querySelector('span').textContent.trim()};`);
  (t21.n >= 2 && t21.s === t21.shown) ? ok('T21 轴视图空隙可点且时刻一致（' + t21.n + ' 段）') : bad('T21', JSON.stringify(t21));

  /* T22 · 跨天事件（23:30 → 次日 00:30） */
  const t22 = await ev(`
    openTimePick(19);
    tpSetWheel('tpSd',19-1);tpSetWheel('tpSh',23);tpSetWheel('tpSm',30);
    tpSetWheel('tpEd',20-1);tpSetWheel('tpEh',0);tpSetWheel('tpEm',30);
    tpUpd();
    const rng=$('#tpRange').textContent;
    tpAdd(0);
    const b=blocks[blocks.length-1];
    return {rng:rng,day:b.day,s:b.s,e:b.e,dur:b.e-b.s}`);
  (t22.dur === 60 && t22.s === 1410 && t22.e === 1470 && t22.day === 19 && /跨天/.test(t22.rng) && /60 分钟/.test(t22.rng))
    ? ok('T22 跨天事件按结束日滚轮落库(60分钟)') : bad('T22', JSON.stringify(t22));

  /* T23 · 周视图月末仍固定 7 列 · 跨月列为惰性 */
  const t23 = await ev(`
    setDay(28);switchCalView('week');
    const html=$('#calWeekGrid').innerHTML;
    const heads=[...document.querySelectorAll('#calWeekGrid > div > span')].slice(0,8).map(x=>x.textContent.trim());
    const firstRowCells=(html.match(/wk-cell/g)||[]).length;
    const inert=(html.match(/bg-slate-50 dark:bg-slate-900\\/40/g)||[]).length;
    const r={cols:html.split('grid-template-columns:26px repeat(7,1fr)').length-1,cells:firstRowCells,inert:inert,
      title:$('#calWeekGrid').textContent.slice(0,20)};
    setDay(19);return r`);
  (t23.cols === 1 && t23.cells === 24 * 7 && t23.inert > 0) ? ok('T23 周视图固定7列·跨月惰性列') : bad('T23', JSON.stringify(t23));

  /* T24 · 删除可撤销 */
  const t24 = await ev(`
    const nb={day:19,s:1000,e:1030,cat:'工作',note:'撤销块'};blocks.push(nb);renderCal();
    openBlockEdit(nb);tpDel();
    const gone=!blocks.some(x=>x.note==='撤销块');
    undoAct();
    const back=blocks.filter(x=>x.note==='撤销块');
    return {gone:gone,restored:back.length===1,span:back[0]&&[back[0].s,back[0].e]}`);
  (t24.gone && t24.restored && t24.span[0] === 1000 && t24.span[1] === 1030) ? ok('T24 删除可撤销还原') : bad('T24', JSON.stringify(t24));

  /* T25 · 合并间隙阈值：>30 分钟不可合并 */
  const t25 = await ev(`
    const a={day:19,s:600,e:630,cat:'工作',note:'近邻A'};const b1={day:19,s:650,e:680,cat:'学习',note:'近邻B'};const b2={day:19,s:900,e:930,cat:'学习',note:'远邻C'};
    blocks.push(a,b1,b2);
    const near=nbOf(a,1)&&nbOf(a,1).note;
    blocks=blocks.filter(x=>x!==b1);
    const far=nbOf(a,1);
    blocks=blocks.filter(x=>x!==a&&x!==b2);renderCal();
    return {near:near,far:far?far.note:null}`);
  (t25.near === '近邻B' && t25.far === null) ? ok('T25 合并仅限 30 分钟内相邻段') : bad('T25', JSON.stringify(t25));

  /* T26 · 跨天块的次日尾巴在日/周视图可见 */
  const t26 = await ev(`
    const x={day:19,s:1400,e:1470,cat:'工作',note:'跨天块'};blocks.push(x);
    setDay(20);switchCalView('day');
    const dayTxt=$('#calDayHourView').textContent;switchCalView('axis');const axTxt=$('#timeAxis').textContent;switchCalView('day');
    switchCalView('week');setDay(19);
    const weekTxt=$('#calWeekGrid').textContent;
    const has=(document.querySelectorAll('#calWeekGrid [onclick*="openBlockEdit"]')).length;
    blocks=blocks.filter(b=>b!==x);setDay(19);renderCal();
    return {inDay:/跨天块/.test(dayTxt),tailLabel:/↩/.test(dayTxt)&&/续昨日/.test(axTxt),weekCells:has>0}`);
  (t26.inDay && t26.tailLabel) ? ok('T26 跨天块次日尾巴可见并标「续昨日」') : bad('T26', JSON.stringify(t26));

  /* T27 · 计时中时长走秒级文本刷新（不整页重绘） */
  const t27 = await ev(`
    const tb=timingBlk();if(tb){tpEdit=tb;tpEnd()}
    openTimePick(19);tpAdd(0);
    switchCalView('axis');
    const el=document.querySelector('#timeAxis .tmDur');
    const r={has:!!el,s:el?+el.dataset.s:null};
    const tb2=timingBlk();if(tb2){tpEdit=tb2;tpEnd()}
    return r`);
  (t27.has && t27.s !== null) ? ok('T27 计时时长走 .tmDur 秒级刷新') : bad('T27', JSON.stringify(t27));

  /* T28 · 时间账本四档实算（日/周/月/年 + 翻页 + 折叠 + 未记录 + 环比） */
  const t28 = await ev(`
    navTo('p-timeStats');
    const out={};
    tsSetMode('d');out.day={clock:!!document.querySelector('#tsBody svg path[fill]'),period:$('#tsPeriod').textContent,cards:[...document.querySelectorAll('#tsBody .card')].length};
    tsSetMode('w');out.week={area:document.querySelectorAll('#tsBody polyline').length,stack:document.querySelectorAll('#tsBody .flex.items-stretch > div').length,rank:document.querySelectorAll('#tsBody [onclick*="明细列表"]').length};
    tsSetMode('y');out.year={monthBars:document.querySelectorAll('#tsBody polyline').length,label:$('#tsPeriod').textContent,heat:document.querySelectorAll('#tsBody .grid > div').length};
    tsSetMode('m');const before=$('#tsPeriod').textContent;tsShift(1);const after=$('#tsPeriod').textContent;
    out.month={label:before,paged:after===before};
    const donutTxt=$('#tsBody').textContent;
    out.unrecorded=/未记录/.test(donutTxt);
    tsSetMode('w');
    const idx=[...document.querySelectorAll('#tsBody .card')].findIndex(c=>c.textContent.includes('分类时长汇总'));
    const openCls=document.querySelectorAll('#tsBody .card')[idx].querySelector('div:nth-child(2)').className;
    document.querySelectorAll('#tsBody .card')[idx].querySelector('.flex.items-center').click();
    const shutCls=document.querySelectorAll('#tsBody .card')[idx].querySelector('div:nth-child(2)').className;
    document.querySelectorAll('#tsBody .card')[idx].querySelector('.flex.items-center').click();
    const backCls=document.querySelectorAll('#tsBody .card')[idx].querySelector('div:nth-child(2)').className;
    out.fold=/hidden/.test(shutCls)&&!/hidden/.test(openCls)&&!/hidden/.test(backCls);
    const {from,to}=tsPeriod('w',tsAnchor);const A=tsAgg(from,to);
    out.total=Object.values(A.byCat).reduce((a,b)=>a+b,0);
    out.heroHas=out.total>0&&$('#tsBody').textContent.includes('已记录');
    setPage('p-calendar');
    out.dash=document.querySelector('#dashTimeDist').textContent.length>10;
    return out;`);
  (t28.day.clock && t28.week.stack >= 7 && t28.week.rank >= 1 && t28.year.monthBars >= 1 && t28.year.heat >= 30
    && t28.month.paged && t28.unrecorded && t28.fold && t28.heroHas && t28.dash)
    ? ok('T28 账本四档/翻页/折叠/未记录/环比/仪表盘联动') : bad('T28', JSON.stringify(t28));

  await ev(`
    setDay(19);switchCalView('axis');
    const nb={day:19,s:600,e:660,cat:'学习',note:'读书'};blocks.push(nb);
    const nb2={day:19,s:690,e:720,cat:'工作',note:'开会'};blocks.push(nb2);renderCal();
    openBlockEdit(nb);return 1`);
  await wait(300);await shot('r2-edit-split-merge');
  await ev(`closeSheet('sheetTimePick');switchCalView('week');return 1`);
  await wait(200);await shot('r2-week-view');
  /* 控制台异常 */
  errs.length ? bad('运行时异常', errs.slice(0, 3).join(' || ')) : ok('无未捕获异常');
  await shot('final');
  finish();

  function finish() { try { ws && ws.close() } catch (e) { } try { chrome.kill() } catch (e) { }
    log('== ' + pass + ' PASS / ' + fail + ' FAIL =='); process.exit(fail ? 1 : 0) }
})().catch(e => { log('CRASH ' + e.stack); process.exit(2) });
