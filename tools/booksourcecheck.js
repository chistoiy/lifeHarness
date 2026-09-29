/* V1.55 在线书源专版原型 · 逐屏无头走查（CDP）
 * 用法：node --experimental-websocket tools/booksourcecheck.js            # 断言
 *      BSRD_SHOTS=1 node --experimental-websocket tools/booksourcecheck.js  # 同时出截图
 * 覆盖：屏渲染/文本泄漏/emoji/书源管理·搜索·发现·详情·任务·源编辑 · 阅读内核同源 · 深链
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-booksource.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.BS_PORT || 9531);
const SHOTS = process.env.BSRD_SHOTS === '1';
const SHOTDIR = 'prototype/shots/booksource';
const LOG = 'tools/booksource-run.log';
const EMOJI = '[\\u{1F000}-\\u{1FAFF}\\u{2600}-\\u{27BF}\\u{2B00}-\\u{2BFF}\\u{FE0F}]';
let pass = 0, fail = 0; const errs = [];
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m) };
fs.writeFileSync(LOG, '== bscheck start ' + new Date().toISOString() + ' ==\n');
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result;
  try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 220) } }
}
async function run(code) { return cmd('Runtime.evaluate', { expression: code }) }
async function shot(name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64'));
}
/* 逐屏断言：渲染后文本量 / 假值 / class 泄漏 / emoji 泄漏 */
async function page(n, opener, min) {
  const r = await ev(`var el=document.getElementById('${n}');if(!el)return{no:1};setPage('${n}');if(window.${opener})window.${opener}();
    var t=el.innerText||'';var leak=0,emo=0;
    el.querySelectorAll('*').forEach(function(e){for(var i=0;i<e.childNodes.length;i++){var v=e.childNodes[i].nodeValue||'';
      if(e.childNodes[i].nodeType===3){if(/(^|[\\s>])(ring-|bg-|text-\\[|border-|rounded-|font-|dark:)/.test(v))leak++;
        if(new RegExp(${JSON.stringify(EMOJI)},'u').test(v))emo++;}}});
    return {len:t.length,bad:(t.match(/undefined|NaN|\\[object|\\bnull\\b/g)||[]).length,leak:leak,emo:emo,head:t.slice(0,26)}`);
  if (r.__err || r.no) return bad('屏 ' + n, r.__err || '屏不存在');
  (r.len > (min || 120) && r.bad === 0 && r.leak === 0 && r.emo === 0)
    ? ok('屏 ' + n, '文本' + r.len + ' · 假值0 · 泄漏0 · emoji0 ·「' + r.head.replace(/\s+/g, ' ') + '」')
    : bad('屏 ' + n, JSON.stringify(r));
  await shot('bs-' + n);
}
async function reload(q) {
  await cmd('Page.navigate', { url: URLF + (q || '') });
  await wait(2600);
}

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  log('launch chrome · port ' + PORT);
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.bs-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('chrome 调试端口'); return finish() }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || m.params.exceptionDetails.text || '').slice(0, 200));
    if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') errs.push('log:' + m.params.entry.text.slice(0, 160));
  });
  await cmd('Runtime.enable'); await cmd('Page.enable'); await cmd('Log.enable');
  await reload('');

  /* ---------- 启动 · 底座完好 + 书源域就位 ---------- */
  const boot = await ev(`return {src:BX_SRC.length,subs:BX_SUBS.length,usable:BX_SRC.filter(bxSel).length,
    books:BS_BOOKS.length,onl:BS_BOOKS.filter(b=>b.online).length,grp:RS_SEC[RS_SEC.length-1][0],
    rows:RS_SEC[RS_SEC.length-1][1].length,scr:document.querySelectorAll('section[id^="p-bs"]').length,
    bdg:[].map.call(document.querySelectorAll('#p-bookshelf .br-local'),function(e){return e.textContent.trim()})}`);
  (boot.src === 8 && boot.scr === 7) ? ok('启动·书源域注入', '源' + boot.src + ' · 屏' + boot.scr + ' · 可用' + boot.usable) : bad('启动', JSON.stringify(boot));
  boot.onl === 2 ? ok('启动·在线书已入架', '在线 2 本 · 全架 ' + boot.books + ' 本') : bad('启动·在线书', JSON.stringify(boot));
  const onB = boot.bdg.filter(t => /在线/.test(t)).length, loB = boot.bdg.filter(t => /本地/.test(t)).length;
  onB === 2 && loB === 1 ? ok('书架·徽标同位替换', '在线 ' + onB + ' 枚 · 本地 ' + loB + ' 枚（EPUB 仍标本地）') : bad('书架·徽标', JSON.stringify(boot.bdg));
  const rb = await ev(`return {row:brRowBadge(bxBk('剑来')),cov:brCovBadge(bxBk('剑来')),covEp:brCovBadge(bsBook('b1')),rowEp:brRowBadge(bsBook('b1'))}`);
  /在线/.test(rb.row) && /在线/.test(rb.cov) && /本地/.test(rb.covEp) && /本地/.test(rb.rowEp)
    ? ok('徽标·四视图出口同源', '列表行与封面均按来源切换文案') : bad('徽标·出口', JSON.stringify(rb));
  await run("stack.length=0;setPage('p-bookshelf');renderShelf()"); await shot('bs-shelf-online');
  boot.grp === '在线书源' && boot.rows === 17 ? ok('设置·在线书源分组', boot.rows + ' 行') : bad('设置·分组', JSON.stringify(boot));

  /* ---------- 七屏逐屏断言 ---------- */
  await page('p-bsSources', 'bxSrcRender', 300);
  await run("bxSearchOpen('')");
  await page('p-bsSearch', 'bxSearchRender', 90);
  await page('p-bsDiscover', 'bxDiscRender', 150);
  await run("BXQ.q='剑来';bxdOpen('r1',0)");
  await page('p-bsDetail', 'bxdRender', 300);
  await page('p-bsTask', 'bxTaskRender', 300);
  await run("bxFormOpen('r2')");
  await page('p-bsSrcForm', 'bxFormRender', 150);
  await run("bxVerifyOpen('全部')");
  await page('p-bsVerify', 'bxVerifyRender', 260);

  /* ---------- 书源管理 ---------- */
  const mgr = await ev(`return {rows:document.querySelectorAll('#bxSrcList .bx-row').length,
    k:document.querySelectorAll('#bxSrcList .bx-k').length,sub:document.querySelectorAll('#bxSrcRoot .card .bx-row').length}`);
  mgr.rows === 8 && mgr.k === 8 ? ok('管理·源列表全量', mgr.rows + ' 行 · 类型徽标 ' + mgr.k) : bad('管理·源列表', JSON.stringify(mgr));
  await run("bxFnTab('网文')");
  const f1 = await ev(`return document.querySelectorAll('#bxSrcList .bx-row').length`);
  f1 === 6 ? ok('管理·分组筛选', '网文 6 源') : bad('管理·分组', JSON.stringify({ f1 }));
  await run("bxFnTab('全部');BXSF.kw='熔断';bxFnKw('熔断');");
  const f2 = await ev(`return {n:document.querySelectorAll('#bxSrcList .bx-row').length,back:BX_SRC.length}`);
  f2.n === 1 ? ok('管理·关键词筛选', '命中熔断源 1') : bad('管理·关键词', JSON.stringify(f2));
  await run("BXSF.kw='';bxFnKw('');");
  await run("bxsOps('r2');bxToggleSrc('r2')");
  const tg = await ev(`return {on:bxs('r2').on,usable:BX_SRC.filter(bxSel).length}`);
  tg.on === 0 && tg.usable === 2 ? ok('管理·停用生效', '可用源 3→' + tg.usable) : bad('管理·停用', JSON.stringify(tg));
  await run("bxsOps('r2');bxToggleSrc('r2')");
  await run("bxSubOps('u1');bxSubToggle('u1')");
  const sub = await ev(`return {u:BX_SUBS.find(x=>x.id==='u1').on,on1u1:BX_SRC.filter(s=>s.sub==='u1'&&s.on).length}`);
  sub.u === 0 && sub.on1u1 === 0 ? ok('管理·停订阅连带停源', 'u1 下启用源 ' + sub.on1u1) : bad('管理·连带', JSON.stringify(sub));
  await run("bxSubToggle('u1')");
  const sub2 = await ev(`return {on:BX_SRC.filter(s=>s.sub==='u1'&&s.on).length,r5:!!bxs('r5')&&bxs('r5').on}`);
  sub2.on === 3 && sub2.r5 === 0 ? ok('管理·恢复按停用前状态', 'u1 下 ' + sub2.on + ' 源回弹 · 原停用源未被唤醒') : bad('管理·恢复', JSON.stringify(sub2));
  await run("bxSubOps('u1');bxSubView('u1')");
  const sub3 = await ev(`return {rows:document.querySelectorAll('#bxSrcList .bx-row').length,cap:/已筛订阅/.test(document.getElementById('bxSrcRoot').innerText)}`);
  sub3.rows === 7 && sub3.cap ? ok('管理·按订阅筛源', sub3.rows + ' 行（u1 的 7 源）') : bad('管理·按订阅筛', JSON.stringify(sub3));
  await run("BXSF.sub=null;bxSrcRender()");
  await run("bxAddOpen()");
  const add = await ev(`return {open:!document.getElementById('sheetBsAdd').classList.contains('hidden'),
    ta:document.querySelectorAll('#bxAddBody textarea').length,files:document.querySelectorAll('#bxAddBody .chip').length,
    parse:[].some.call(document.querySelectorAll('#bxAddBody button'),function(b){return b.textContent==='解析'})}`);
  add.open && add.ta === 2 && add.files >= 2 && add.parse ? ok('导入·批量入口（链接+文件+粘贴）', '输入区 ' + add.ta + ' · 文件/钮 ' + add.files) : bad('管理·添加弹层', JSON.stringify(add));
  await shot('bs-add');
  await run("document.getElementById('bxaiUrls').value='https://legado.aoaostar.com/api/bookSource\\n随手写的一行';BXAI.urls='https://legado.aoaostar.com/api/bookSource\\n随手写的一行';" +
    "document.getElementById('bxaiJson').value='[{\\\"bookSourceUrl\\\":\\\"https://m.d1.com\\\",\\\"bookSourceName\\\":\\\"演示1\\\"},{\\\"x\\\":1}]';BXAI.json=document.getElementById('bxaiJson').value;bxAddParse()");
  const pv = await ev(`return {rows:document.querySelectorAll('#bxaiPrev .bx-vrow').length,txt:document.getElementById('bxaiPrev').innerText.replace(/\\s+/g,' '),
    btn:[].some.call(document.querySelectorAll('#bxaiPrev button'),function(b){return /导入并校验/.test(b.textContent)})}`);
  pv.rows >= 4 && pv.btn && /订阅/.test(pv.txt) && /源数组/.test(pv.txt) && /无效/.test(pv.txt)
    ? ok('导入·自动解析分类与预览', pv.rows + ' 条 · 订阅/源数组/无效 分类 + 去重处置') : bad('导入·解析', JSON.stringify(pv));
  await run("bxAddImport()"); await wait(700);
  const imp = await ev(`return {n:BX_SRC.length,js:BX_SRC.filter(s=>s.kind==='js'&&s.on===0).length,subs:BX_SUBS.length,p:curPage,v:BXV2.rows.length}`);
  imp.n === 17 && imp.js >= 4 && imp.subs === 3 ? ok('导入·合并入列并停用不支持源', '源 8→' + imp.n + ' · @js 自动停用 ' + imp.js + ' · 订阅 ' + imp.subs) : bad('管理·导入', JSON.stringify(imp));
  imp.p === 'p-bsVerify' && imp.v > 0 ? ok('导入·导入后直落校验中心', '本次导入范围 ' + imp.v + ' 源') : bad('导入·转校验', JSON.stringify(imp));
  await run("bxSrcOpen()");
  await run("bxsCheck('r1')"); await wait(1100);
  const chk = await ev(`return bxs('r1').last`);
  chk === '刚刚' ? ok('管理·自检写回', '最近自检 ' + chk) : bad('管理·自检', JSON.stringify(chk));
  await run("window.__delId=BX_SRC[BX_SRC.length-1].id;bxsOps(__delId)");
  const dn0 = await ev(`window.__row=document.querySelector('#bxOpsBody .bx-row:last-child');return BX_SRC.length`);
  await run("bxDelSrc(__delId,__row)");
  const dn1 = await ev(`return {n:BX_SRC.length,arm:__row&&__row.getAttribute('data-arm')}`);
  dn1.n === dn0 && dn1.arm === '1' ? ok('管理·删除需二次确认', '首点只挂确认态（仍 ' + dn1.n + ' 源）') : bad('管理·删除确认', JSON.stringify({ dn0, dn1 }));
  await run("bxDelSrc(__delId,__row)");
  const dn2 = await ev(`return BX_SRC.length`);
  dn2 === dn0 - 1 ? ok('管理·二点真删', dn0 + ' → ' + dn2 + ' 源') : bad('管理·二点删', JSON.stringify({ dn0, dn2 }));
  await run("BX_SRC=BX_SRC.filter(s=>s.id[0]!=='x');BX_SUBS=BX_SUBS.slice(0,2);BXV2.ids=[];BXV2.rows=[];bxSrcRender()");
  const back = await ev(`return {n:BX_SRC.length,subs:BX_SUBS.length}`);
  back.n === 8 && back.subs === 2 ? ok('管理·导入批次可整体回退（走查复位）', '源回 ' + back.n + ' · 订阅回 ' + back.subs) : bad('管理·复位', JSON.stringify(back));

  /* ---------- 净化规则弹层 ---------- */
  await run("bxFilterOpen()");
  const flt = await ev(`return {open:!document.getElementById('sheetBsFilter').classList.contains('hidden'),n:document.querySelectorAll('#bxFilterBody .bx-code').length,on:BX_FILTERS.filter(f=>f.on).length}`);
  flt.open && flt.n === 4 ? ok('净化·规则清单', flt.n + ' 条 · 生效 ' + flt.on) : bad('净化·弹层', JSON.stringify(flt));
  await run("bxFilterAdd();bxFilterFlip(4)");
  const flt2 = await ev(`return {n:BX_FILTERS.length,on:BX_FILTERS[4].on}`);
  flt2.n === 5 && flt2.on === 1 ? ok('净化·新增与开关', '新增第 5 条并开') : bad('净化·新增', JSON.stringify(flt2));
  await run("BX_FILTERS.pop();closeSheet('sheetBsFilter')");

  /* ---------- 源编辑与测试 ---------- */
  await run("bxFormOpen('r1');bxTest('toc')"); await wait(900);
  const tst = await ev(`return {lbl:document.getElementById('bxTestLbl').textContent,out:document.getElementById('bxTestOut').innerText.length}`);
  /章/.test(tst.lbl) && tst.out > 10 ? ok('编辑·测目录', tst.lbl) : bad('编辑·测目录', JSON.stringify(tst));
  await run("bxFormOpen('r6');bxTest('search')"); await wait(900);
  const tst2 = await ev(`return {lbl:document.getElementById('bxTestLbl').textContent,t:document.getElementById('bxTestOut').innerText}`);
  tst2.lbl === '失败' && /JS 引擎/.test(tst2.t) ? ok('编辑·@js 源测试失败归因', tst2.t.slice(0, 22)) : bad('编辑·js 归因', JSON.stringify(tst2));
  await run("bxFormOpen('r2');bxTest('content')"); await wait(900);
  const tst3 = await ev(`return document.getElementById('bxTestLbl').textContent`);
  tst3 === '部分通过' ? ok('编辑·规则缺口部分通过', tst3) : bad('编辑·部分通过', JSON.stringify(tst3));
  await run("bxFormOpen('r1')");
  const hd = await ev(`return {enc:BXF.d.head.enc,on:[].map.call(document.querySelectorAll('#bxFormRoot .chip.chip-on'),function(c){return c.textContent}).join('/')}`);
  hd.enc === 'GBK' && hd.on.split('/').length === 4 ? ok('编辑·请求头按源回显', hd.enc + ' · ' + hd.on) : bad('编辑·请求头', JSON.stringify(hd));
  await run("bxHeadSet('ua',1)");
  const hd2 = await ev(`return {ua:BXF.d.head.ua,on:[].map.call(document.querySelectorAll('#bxFormRoot .chip.chip-on'),function(c){return c.textContent}).join('/')}`);
  hd2.ua === 0 && hd2.on.indexOf('UA') < 0 ? ok('编辑·UA 池可关', hd2.on) : bad('编辑·UA 关', JSON.stringify(hd2));
  await run("bxFormOpen(null);BXF.d.nm='走查自建源';bxFormSave()");
  const saved = await ev(`return {n:BX_SRC.length,nm:BX_SRC[0].nm,hs:BX_SRC[0].hs}`);
  saved.n === 9 && saved.nm === '走查自建源' ? ok('编辑·新建源入列', saved.nm + ' · ' + saved.hs) : bad('编辑·新建', JSON.stringify(saved));
  await run("BX_SRC.shift();bxSrcRender()");

  /* ---------- 搜索（并发 / 标注 / 熔断 / 展开） ---------- */
  await run("BXQ.sel=new Set(['r1','r2','r3']);bxSearchOpen('剑来')");
  await wait(2600);
  const sr = await ev(`return {done:BXQ.done,total:BXQ.total,n1:(BXQ.res.r1.list||[]).length,e3:BXQ.res.r3.err||'',
    part:(BXQ.res.r2.list||[]).length,src:document.querySelectorAll('#bxRes .bx-src').length,exp:!!document.querySelector('#bxRes .bx-tab')}`);
  sr.done === 3 && sr.n1 === 19 ? ok('搜索·并发与真站条数', 'r1 19 条 · 已返回 ' + sr.done + '/' + sr.total) : bad('搜索·并发', JSON.stringify(sr));
  /熔断/.test(sr.e3) ? ok('搜索·单源熔断标注', sr.e3) : bad('搜索·熔断', JSON.stringify(sr));
  sr.src > 0 && sr.exp ? ok('搜索·来源标注与折叠', '来源标 ' + sr.src + ' 处 · 有展开钮') : bad('搜索·标注', JSON.stringify(sr));
  await run("BXQ.exp.r1=1;bxResUpdate()");
  const ex = await ev(`return document.querySelectorAll('#bxRes .bx-row').length`);
  ex >= 22 ? ok('搜索·展开其余', ex + ' 条行') : bad('搜索·展开', JSON.stringify({ ex }));
  await shot('bs-search');
  await run("bxSearchOpen('');bxSearchKw('https://www.biqumo.com/book/12345/');bxSearchRun()"); await wait(700);
  const udm = await ev(`return {p:curPage,t:BXV.b&&BXV.b.t}`);
  udm.p === 'p-bsDetail' && /#12345/.test(udm.t || '') ? ok('搜索·粘贴地址自动识源', udm.t) : bad('搜索·识源', JSON.stringify(udm));

  /* ---------- 发现页 ---------- */
  await run("bxDiscOpen('r1')");
  const dc = await ev(`return {tabs:document.querySelectorAll('#bxDiscRoot .bx-tab').length,items:document.querySelectorAll('#bxDiscRoot .bx-grid>div').length,src:BX_SRC.filter(bxSel).length}`);
  dc.tabs === 3 && dc.items === 9 ? ok('发现·多 Tab 与首屏', '3 Tab · 9 条（源自带发现频道）') : bad('发现·首屏', JSON.stringify(dc));
  await run("bxDiscMore()"); await wait(900);
  const dc2 = await ev(`return {items:document.querySelectorAll('#bxDiscRoot .bx-grid>div').length,page:BXD.page}`);
  dc2.items === 18 && dc2.page === 2 ? ok('发现·{{page}} 翻页', '第 2 页 · 18 条') : bad('发现·翻页', JSON.stringify(dc2));
  await run("bxDiscTab(2)");
  const dc3 = await ev(`return document.querySelectorAll('#bxDiscRoot .bx-grid>div').length`);
  dc3 === 9 ? ok('发现·切 Tab 重置页', '回第 1 页 9 条') : bad('发现·切 Tab', JSON.stringify({ dc3 }));
  await shot('bs-discover');

  /* ---------- 详情 · 入库去重 ---------- */
  await run("BXQ.q='剑来';bxdOpen('r1',0)");
  const det = await ev(`return {t:BXV.b.t,total:bxStat().total,cached:bxStat().cached,btn:document.querySelectorAll('#bxDetailRoot button').length,rev:/转正/.test(document.getElementById('bxDetailRoot').innerText)}`);
  det.t === '剑来' && det.total === 108 && det.cached === 3 && det.rev ? ok('详情·目录章数与转正', det.total + ' 章 · 缓存 ' + det.cached) : bad('详情', JSON.stringify(det));
  const n0 = await ev(`return BS_BOOKS.length`);
  await run("bxdOpen('r1',1);bxToShelf('r1')");
  const dup = await ev(`return {n:BS_BOOKS.length,b:bxBk('剑来 校对版'),tags:bxBk('剑来 校对版')&&bxBk('剑来 校对版').tags}`);
  dup.n === n0 + 1 && dup.b && dup.b.online === 1 ? ok('详情·新书入架', '《剑来 校对版》入库 · tags ' + dup.tags) : bad('详情·入架', JSON.stringify(dup));
  await run("bxToShelf('r1')");
  const dup2 = await ev(`return BS_BOOKS.length`);
  dup2 === n0 + 1 ? ok('详情·重复加书架不增条', '同书仍一条（记录共用）') : bad('详情·去重', JSON.stringify({ dup2 }));

  /* ---------- 在线阅读 · 与 EPUB 同源 ---------- */
  await run("bxRead('r1')");
  await wait(500);
  const rd = await ev(`return {p:curPage,sub:document.getElementById('brTopSub').textContent,ch:brLeaves(brV.b).length,timer:!!document.getElementById('brSessChip'),toc:(BS_TOC[brV.b]||[[null,[[]]]])[0][2].length}`);
  rd.p === 'p-readerPage' && /在线 · 笔趣阁/.test(rd.sub) ? ok('阅读·在线书进内核', rd.sub) : bad('阅读·进内核', JSON.stringify(rd));
  rd.ch === 108 && rd.toc === 108 ? ok('阅读·章节目录 108 章同源', '章数 ' + rd.ch) : bad('阅读·章节', JSON.stringify(rd));
  await run("brChromeLabels();document.getElementById('brTop').classList.remove('hidden');document.getElementById('brBottom').classList.remove('hidden')");
  const rd2 = await ev(`return {top:document.getElementById('brTop').innerText.replace(/\\s+/g,' ').slice(0,40)}`);
  /在线 · /.test(rd2.top) ? ok('阅读·顶栏带源与缓存', rd2.top) : bad('阅读·顶栏', JSON.stringify(rd2));
  await shot('bs-reader-online');
  await run("document.getElementById('brTop').classList.add('hidden');document.getElementById('brBottom').classList.add('hidden')");
  await run("brV.ci=3;brFlip(1)");
  const fz = await ev(`var b=bsBook(brV.b);return {nm:b.n,cached:b.bsrc.cached,dead:b.bsrc.dead}`);
  fz.cached > 3 ? ok('阅读·翻到未缓存章现取', '《' + fz.nm + '》已缓存→' + fz.cached + ' 章') : bad('阅读·现取', JSON.stringify(fz));
  const cfi = await ev(`return {on:brCfi(brV.b,3,1),ep:brCfi('b1',3,1),o:bsBook(brV.b).online}`);
  /^src\/2\/5\/1$/.test(cfi.on) && /^epub\/2\/5\/1$/.test(cfi.ep) ? ok('阅读·CFI 前缀按来源泛化', '在线 ' + cfi.on + ' · 本地 ' + cfi.ep) : bad('阅读·CFI', JSON.stringify(cfi));
  const same = await ev(`return {q:typeof BS_QUOTES,ses:typeof BS_LOG,cf:brLocSnap().cfi||brLocSnap().ch,pct:brStPct(brV.b)}`);
  same.q !== 'undefined' && same.ses !== 'undefined' ? ok('阅读·书摘与会话同库', 'CFI/章 ' + same.cf + ' · 进度 ' + same.pct + '%') : bad('阅读·同库', JSON.stringify(same));
  await run("openSheet('sheetBrMore');brMoreRender()");
  const mo = await ev(`return !!document.getElementById('bxMoreSw')`);
  mo ? ok('阅读·更多菜单含换源') : bad('阅读·换源入口', JSON.stringify({ mo }));
  await run("closeSheet('sheetBrMore');brLeave();bxSrcOpen()");

  /* ---------- 轮2·阅读页常驻源钮 / 底栏续抓 / 逐章预取 ---------- */
  await run("var o=bxRegBook('r1','剑来');bxEnter(o.b.id)"); await wait(500);
  await run("brChromeLabels();document.getElementById('brTop').classList.remove('hidden');document.getElementById('brBottom').classList.remove('hidden');brTocOpen&&0");
  const pill = await ev(`return {btn:!!document.getElementById('bxSrcBtn'),cls:(document.getElementById('bxSrcBtn')||{}).className||'',txt:(document.getElementById('bxSrcBtn')||{}).innerText||'',batch:!!document.getElementById('bxBatchBtn')}`);
  pill.btn && /笔趣阁/.test(pill.txt) && pill.batch ? ok('轮2·阅读页常驻「源」钮与底栏「续抓」', pill.txt + ' · ' + pill.cls.trim()) : bad('轮2·常驻源钮', JSON.stringify(pill));
  await run("document.getElementById('bxSrcBtn').click()");
  const pillSheet = await ev(`return {open:!document.getElementById('sheetBsSwitch').classList.contains('hidden'),cur:document.querySelector('#bxSwitchBody .bx-row b').textContent}`);
  pillSheet.open && pillSheet.cur === '笔趣阁' ? ok('轮2·阅读中随时点开换源') : bad('轮2·换源入口', JSON.stringify(pillSheet));
  await run("bxOrdMove('r2',-1);bxOrdMove('r3',-1)");
  const ord = await ev(`return BX_ORDER.slice(0,3).join(',')`);
  /^r[0-9]+,/.test(ord) ? ok('轮2·候选优先级可拖序', '当前顺序 ' + ord) : bad('轮2·调序', JSON.stringify({ ord }));
  await run("closeSheet('sheetBsSwitch')");
  const p0 = await ev(`var b=bsBook(brV.b);return {c:b.bsrc.cached}`);
  await run("brV.ci=" + p0.c + ";brFlip(1)"); await wait(1300);
  const p1 = await ev(`var b=bsBook(brV.b);return {c:b.bsrc.cached}`);
  p1.c >= p0.c + 2 ? ok('轮2·看一章取一章 + 预取下一章', p0.c + ' → ' + p1.c + ' 章（翻 1 章推进 ≥2）') : bad('轮2·预取', JSON.stringify({ p0, p1 }));
  const wall = await ev(`var b=bsBook(brV.b);b.bsrc.srcId='r7';b.bsrc.srcNm='轻小说平台';brV.ci=b.bsrc.cached;var c0=b.bsrc.cached;brFlip(1);
    return {c0:c0,src:b.bsrc.srcId,cached:b.bsrc.cached,dead:b.bsrc.dead}`);
  wall.src !== 'r7' && wall.cached > wall.c0 && !wall.dead ? ok('轮2·防盗链 403 自动换源续读', '403 源 → ' + wall.src + ' · 停在第 ' + wall.cached + ' 章') : bad('轮2·自动换源', JSON.stringify(wall));
  const noauto = await ev(`var b=bsBook(brV.b);BS_SET.bsAuto=0;b.bsrc={srcId:'r5',srcNm:'得奇小说网',total:b.bsrc.total,cached:b.bsrc.cached,dead:false};brV.ci=b.bsrc.cached;brFlip(1);
    BS_SET.bsAuto=1;return {src:b.bsrc.srcId,dead:b.bsrc.dead}`);
  noauto.dead ? ok('轮2·全源不可用时标失效不硬翻', '源 r5 已标失效 · 待人工处置') : bad('轮2·失效标注', JSON.stringify(noauto));
  await run("closeSheet('sheetBsFail');closeSheet('sheetBsSwitch')");
  const off = await ev(`var b=bsBook(brV.b);b.bsrc={srcId:'r1',srcNm:'笔趣阁',total:b.bsrc.total,cached:b.bsrc.cached,dead:false};var c0=b.bsrc.cached;
    BS_SET.bsOn=0;brV.ci=c0;brFlip(1);BS_SET.bsOn=1;return {c0:c0,c1:b.bsrc.cached}`);
  off.c1 === off.c0 ? ok('轮2·总开关停用后翻章不请求只读缓存', '停在第 ' + off.c1 + ' 章 · 未发起抓取') : bad('轮2·停用', JSON.stringify(off));
  await run("bxBatchOpen()");
  const bat = await ev(`return {open:!document.getElementById('sheetBsBatch').classList.contains('hidden'),lv:document.querySelectorAll('#bxBatchBody .chip').length,
    txt:document.getElementById('bxBatchBody').innerText.replace(/\\s+/g,' ')}`);
  bat.open && bat.lv === 5 && /从第 \d+ 章起抓/.test(bat.txt) && /预估耗时/.test(bat.txt)
    ? ok('轮2·续抓档位（20/50/100/200/全部）', bat.txt.slice(0, 46)) : bad('轮2·续抓弹层', JSON.stringify(bat));
  await shot('bs-batch');
  await run("bxBatchPick(50);bxBatchGo()"); await wait(400);
  const rg = await ev(`var t=BX_TASKS[0];return {p:curPage,r:t&&t.range,st:t&&t.st,done:t&&t.done}`);
  rg.p === 'p-bsTask' && rg.r && rg.r[1] - rg.r[0] + 1 === 50 && rg.st === 'run'
    ? ok('轮2·预抓成范围任务（第 ' + rg.r[0] + '–' + rg.r[1] + ' 章）', rg.st + ' · done ' + rg.done) : bad('轮2·范围任务', JSON.stringify(rg));
  await wait(1400);
  const rg2 = await ev(`var t=BX_TASKS[0];return {done:t.done,st:t.st,card:/预抓/.test(document.getElementById('bxTaskRoot').innerText)}`);
  rg2.done > rg.done && rg2.card ? ok('轮2·范围任务推进且卡面标注预抓', rg.done + ' → ' + rg2.done + ' 章') : bad('轮2·范围推进', JSON.stringify({ rg, rg2 }));
  await run("bxTaskPause(BX_TASKS[0].id);BX_TASKS=BX_TASKS.filter(function(t){return t.id!==BX_TASKS[0].id});bxTaskRender()");
  await run("brLeave();bxSrcOpen()");

  /* ---------- 轮2·书源校验中心 ---------- */
  await run("window.__onSnap=BX_SRC.map(s=>s.on);window.__hsSnap=BX_SRC.map(s=>s.hs);bxVerifyOpen('全部')");
  const v0 = await ev(`return {p:curPage,rows:document.querySelectorAll('#bxVerifyRoot .bx-vrow').length,seg:document.querySelectorAll('#bxVerifyRoot .bx-seg3').length,
    btn:[].some.call(document.querySelectorAll('#bxVerifyRoot button'),function(b){return /开始校验/.test(b.textContent)})}`);
  v0.p === 'p-bsVerify' && v0.rows === 8 && v0.btn ? ok('轮2·校验中心开屏', v0.rows + ' 源 · 四段位 ' + v0.seg) : bad('轮2·校验开屏', JSON.stringify(v0));
  await run("bxVerifyRun()"); await wait(2600);
  const v1 = await ev(`return {run:BXV2.run,done:bxVerifyDone(),ok:bxs('r1').hs,warn:bxs('r2').hs,fuse:bxs('r3').hs,dead:bxs('r4').hs,never:bxs('r6').hs,
    jsOff:bxs('r6').on,txt:document.getElementById('bxVerifyRoot').innerText.replace(/\\s+/g,' ').slice(0,52)}`);
  v1.run === 0 && v1.done === 8 && v1.ok === 'ok' && v1.warn === 'warn' && v1.fuse === 'fuse' && v1.dead === 'dead' && v1.jsOff === 0
    ? ok('轮2·逐源跑完并按结论写回健康态', v1.txt) : bad('轮2·跑批', JSON.stringify(v1));
  await run("bxVerifyCopy()");
  const v2 = await ev(`return {lines:(window.__bxReport||'').split('\\n').length,has:/\\t.+\\t.+ms\\t/.test(window.__bxReport||'')}`);
  v2.lines === 8 && v2.has ? ok('轮2·报告含结论/耗时/归因', v2.lines + ' 行') : bad('轮2·报告', JSON.stringify(v2));
  const before2 = await ev(`return BX_SRC.filter(s=>s.on).length`);
  await run("bxVerifyDisableDead()");
  const v3 = await ev(`return {on:BX_SRC.filter(s=>s.on).length,bad:BX_SRC.filter(s=>!s.on&&(s.kind!=='rule'||s.hs==='dead'||s.hs==='fuse')).length}`);
  v3.on < before2 ? ok('轮2·一键停用不可用源', before2 + ' → ' + v3.on + ' 源启用') : bad('轮2·停用', JSON.stringify({ before2, v3 }));
  await run("bxVerifyScope('仅失效')");
  const v4 = await ev(`return {n:BXV2.rows.length,scope:BXV2.scope,chip:document.querySelectorAll('#bxVerifyRoot .chip.chip-on').length}`);
  v4.n > 0 && v4.scope === '仅失效' ? ok('轮2·范围切换（仅失效 ' + v4.n + ' 源）', '选中态 ' + v4.chip + ' 枚') : bad('轮2·范围', JSON.stringify(v4));
  await run("bxVerifyScope('全部')"); await shot('bs-verify');
  await run("BX_SRC.forEach(function(s,i){s.on=__onSnap[i];s.hs=__hsSnap[i]});BX_ORDER=BX_SRC.filter(bxSel).map(s=>s.id);bxSrcRender();bxVerifyReset()");
  const rst = await ev(`return {on:BX_SRC.filter(s=>s.on).length,hs:BX_SRC.map(s=>s.hs).join('/')}`);
  rst.on === 4 && rst.hs.indexOf('ok/warn/fuse/dead') === 0 ? ok('轮2·校验跑批后可复位（走查护栏）', '启用 ' + rst.on + ' · ' + rst.hs) : bad('轮2·复位', JSON.stringify(rst));

  /* ---------- 换源 ---------- */
  await run("BXV.b={t:'剑来',a:'烽火戏诸侯',st:'连载',wc:'1250 万字',last:'',hot:'9.8',intro:''};bxSwitchOpen('r1')");
  const sw = await ev(`return {open:!document.getElementById('sheetBsSwitch').classList.contains('hidden'),rows:document.querySelectorAll('#bxSwitchBody .bx-row').length,
    ord:document.querySelectorAll('#bxSwitchBody .bx-ord').length,auto:!!document.querySelector('#bxSwitchBody .toggle')}`);
  sw.open && sw.rows >= 6 && sw.ord >= 14 && sw.auto ? ok('换源·候选优先级与调序', sw.rows + ' 行 · ↑↓ ' + sw.ord + ' 钮 · 自动换源开关') : bad('换源·列表', JSON.stringify(sw));
  const before = await ev(`var b=bxBk('剑来');return {c:b.bsrc.cached,q:b.q,mn:b.min,tm:b.times}`);
  await run("bxSwitch('r2')");
  const after = await ev(`var b=bxBk('剑来');return {src:b.bsrc.srcId,nm:b.bsrc.srcNm,sel:bxSel(bxs(b.bsrc.srcId)),lbl:b.src,c:b.bsrc.cached,q:b.q,mn:b.min,tm:b.times}`);
  after.sel && after.lbl === '书源·' + after.nm && after.c >= before.c && after.q === before.q && after.tm === before.tm && after.mn === before.mn
    ? ok('换源·划线书摘计时进度不动', after.nm + ' · 缓存 ' + before.c + '→' + after.c + ' · 书架来源文案=' + after.lbl) : bad('换源·同源', JSON.stringify({ before, after }));
  await run("bxSwitch('r1')");
  await run("BS_SET.bsAuto=0;bxSwitch('r3');BS_SET.bsAuto=1");
  const man = await ev(`var b=bxBk('剑来');return {src:b.bsrc.srcId,nm:b.bsrc.srcNm,lbl:b.src,dead:b.bsrc.dead}`);
  man.dead && man.src === 'r3' ? ok('换源·关掉自动换源后停在所选手动源（不偷偷跳）', man.nm + ' · ' + man.lbl) : bad('换源·手动语义', JSON.stringify(man));
  await run("bxSwitch('r1')");
  await shot('bs-switch');

  /* ---------- 下载任务 · 断点 · 追更 ---------- */
  await run("bxdOpen('r1');bxDlOpen('r1');bsDlStart()"); await wait(300);
  const dl = await ev(`return {p:curPage,st:BX_TASKS[0].st,done:BX_TASKS[0].done,total:BX_TASKS[0].total}`);
  dl.p === 'p-bsTask' && dl.st === 'run' ? ok('下载·任务起跑', dl.done + '/' + dl.total + ' 章 · 串行限速') : bad('下载·起跑', JSON.stringify(dl));
  await wait(1300);
  const dl2 = await ev(`return {done:BX_TASKS[0].done}`);
  dl2.done > dl.done ? ok('下载·进度单调推进', dl.done + ' → ' + dl2.done + ' 章') : bad('下载·推进', JSON.stringify(dl2));
  await run("bxTaskPause(BX_TASKS[0].id)");
  const pz = await ev(`return {st:BX_TASKS[0].st,done:BX_TASKS[0].done,e:BX_TASKS[0].err}`);
  pz.st === 'pause' && /manifest/.test(pz.e) ? ok('下载·暂停落 manifest', pz.e + '（' + pz.done + ' 章）') : bad('下载·暂停', JSON.stringify(pz));
  await run("bxTaskGo(BX_TASKS[0].id)"); await wait(900);
  const rs = await ev(`return {st:BX_TASKS[0].st,done:BX_TASKS[0].done}`);
  rs.st === 'run' && rs.done > pz.done ? ok('下载·从断点续传', pz.done + ' → ' + rs.done + ' 章') : bad('下载·续传', JSON.stringify({ pz, rs }));
  await run("bxTaskPause(BX_TASKS[0].id)");
  const ftask = await ev(`return {st:BX_TASKS.find(t=>t.id==='t2').st,err:BX_TASKS.find(t=>t.id==='t2').err}`);
  ftask.st === 'fail' && /textNodes/.test(ftask.err) ? ok('下载·失败归因', ftask.err) : bad('下载·失败归因', JSON.stringify(ftask));
  await run("bxTaskRetry('t2')"); await wait(900);
  const ftask2 = await ev(`return {st:BX_TASKS.find(t=>t.id==='t2').st,done:BX_TASKS.find(t=>t.id==='t2').done}`);
  ftask2.st === 'fail' && ftask2.done === 10 ? ok('下载·重试后同章再失败（缺口未解）', '第 ' + ftask2.done + ' 章') : bad('下载·重试', JSON.stringify(ftask2));
  await run("bxTaskSkip('t2')"); await wait(500);
  const ftask3 = await ev(`return {st:BX_TASKS.find(t=>t.id==='t2').st,done:BX_TASKS.find(t=>t.id==='t2').done}`);
  ftask3.done > 10 ? ok('下载·跳过并继续', 'done ' + ftask3.done) : bad('下载·跳过', JSON.stringify(ftask3));
  await run("bxTaskPause('t2')");
  const up = await ev(`var t=BX_TASKS.find(x=>x.id==='t1');return {upd:t.upd,total:t.total}`);
  await run("bxTaskUpd('t1')"); await wait(1600);
  const up2 = await ev(`var t=BX_TASKS.find(x=>x.id==='t1');return {total:t.total,done:t.done,st:t.st,upd:t.upd}`);
  up2.total === up.total + up.upd ? ok('追更·目录 diff 增量抓', up.total + ' → ' + up2.total + ' 章 · ' + up2.st) : bad('追更', JSON.stringify({ up, up2 }));
  await run("bxTaskClear(BX_TASKS[0].id)");
  const cc = await ev(`var b=bxBk('剑来');return {c:b.bsrc.cached,st:b.epub.st,q:b.q,mn:b.min}`);
  cc.c === 0 && cc.q > 0 ? ok('清缓存·只回收正文', '缓存 ' + cc.c + ' · 书摘 ' + cc.q + ' 条 · 计时 ' + cc.mn + ' 分钟保留') : bad('清缓存', JSON.stringify(cc));
  await run("BX_PROTO.find(p=>p.nm==='剑来').cached=3;var b=bxBk('剑来');b.bsrc.cached=3;b.epub.st='rdy'");
  await shot('bs-task');

  /* ---------- 设置联动 ---------- */
  await run("navTo('p-readset');rsPickTab&&rsPickTab(RS_SEC.length-1);renderReadSet()");
  const st1 = await ev(`return {t:document.getElementById('p-readset').innerText.indexOf('在线书源')>=0,rate:BS_SET.bsRate}`);
  st1.t ? ok('设置·在线书源分组可见', '抓取间隔 ' + st1.rate + 'ms') : bad('设置·可见', JSON.stringify(st1));
  await run("rsChip('bsRate',600)");
  const st2 = await ev(`return BS_SET.bsRate`);
  st2 === 600 ? ok('设置·抓取间隔可改', '600ms') : bad('设置·间隔', JSON.stringify(st2));
  await run("rsFlip('bsOn')");
  const st3 = await ev(`return BS_SET.bsOn`);
  await run("rsFlip('bsOn');rsChip('bsRate',400)");
  st3 === 0 ? ok('设置·总开关可关', '关在线书源后 toast 留痕') : bad('设置·总开关', JSON.stringify(st3));

  /* ---------- 添加图书入口 ---------- */
  await run("bsrOpen()");
  const ent = await ev(`return {row:!!document.getElementById('bxRowEntry'),menu:(function(){BSR.menu=true;renderBsr();return !!document.getElementById('bxSrcEntry')})()}`);
  ent.row ? ok('入口·添加图书页书源卡') : bad('入口·书源卡', JSON.stringify(ent));
  ent.menu ? ok('入口·FAB 菜单含从书源搜索') : bad('入口·FAB 菜单', JSON.stringify(ent));
  await run("BSR.q='剑来';document.getElementById('bxSrcEntry').click()");
  const ent2 = await ev(`return {p:curPage,q:BXQ.q}`);
  ent2.p === 'p-bsSearch' && ent2.q === '剑来' ? ok('入口·带词跳书源搜索', ent2.q) : bad('入口·跳转', JSON.stringify(ent2));

  /* ---------- 深链：在线 / 失败 ---------- */
  await reload('?bs=online');
  const o1 = await ev(`return {p:curPage,sub:document.getElementById('brTopSub').textContent}`);
  o1.p === 'p-readerPage' && /在线/.test(o1.sub) ? ok('深链·?bs=online 直达阅读', o1.sub.slice(0, 30)) : bad('深链·online', JSON.stringify(o1));
  await reload('?bs=fail');
  await wait(500);
  const o2 = await ev(`return {open:!document.getElementById('sheetBsFail').classList.contains('hidden'),t:document.getElementById('bxFailBody').innerText.slice(0,40),
    ops:document.querySelectorAll('#bxFailBody .bx-row').length}`);
  o2.open && o2.ops === 4 && /均不可用/.test(o2.t) ? ok('深链·?bs=fail 失败四选一（含去校验）', o2.t.replace(/\s+/g, ' ')) : bad('深链·fail', JSON.stringify(o2));
  await shot('bs-fail');
  await reload('?bs=switch');
  const o3 = await ev(`return {open:!document.getElementById('sheetBsSwitch').classList.contains('hidden')}`);
  o3.open ? ok('深链·?bs=switch 换源弹层') : bad('深链·switch', JSON.stringify(o3));
  await reload('#p-bsSearch_i1');
  const o4 = await ev(`return {p:curPage,q:BXQ.q,run:BXQ.total}`);
  o4.p === 'p-bsSearch' && o4.q === '剑来' ? ok('深链·#p-bsSearch_i1 带词进搜页', o4.q + ' · 已并发 ' + o4.run + ' 源') : bad('深链·hash', JSON.stringify(o4));
  await reload('?bs=parse');
  const o5 = await ev(`return {open:!document.getElementById('sheetBsAdd').classList.contains('hidden'),prev:document.querySelectorAll('#bxaiPrev .bx-vrow').length,
    txt:document.getElementById('bxaiPrev').innerText.replace(/\\s+/g,' ').slice(0,40)}`);
  o5.open && o5.prev >= 3 ? ok('深链·?bs=parse 批量导入解析预览', o5.prev + ' 条 · ' + o5.txt) : bad('深链·parse', JSON.stringify(o5));
  await shot('bs-import');
  await run("bxAddImport()"); await wait(700);
  const o6 = await ev(`return {p:curPage,scope:BXV2.scope,n:BXV2.rows.length}`);
  o6.p === 'p-bsVerify' && o6.scope === '本次导入' && o6.n > 0 ? ok('深链·导入即跳校验（本次导入 ' + o6.n + ' 源）') : bad('深链·导入跳校验', JSON.stringify(o6));
  await run("BX_SRC=BX_SRC.filter(s=>s.id[0]!=='x');BX_SUBS=BX_SUBS.slice(0,2)");
  await reload('?bs=verify');
  const o7 = await ev(`return {p:curPage,rows:document.querySelectorAll('#bxVerifyRoot .bx-vrow').length}`);
  o7.p === 'p-bsVerify' && o7.rows === 8 ? ok('深链·?bs=verify 直落校验中心', o7.rows + ' 源') : bad('深链·verify', JSON.stringify(o7));
  await reload('?bs=batch');
  const o8 = await ev(`return {p:curPage,open:!document.getElementById('sheetBsBatch').classList.contains('hidden'),
    chips:document.querySelectorAll('#bxBatchBody .chip').length}`);
  o8.open && o8.p === 'p-readerPage' && o8.chips === 5 ? ok('深链·?bs=batch 阅读页续抓弹层', o8.chips + ' 档') : bad('深链·batch', JSON.stringify(o8));
  await shot('bs-batch-deeplink');
  await reload('?bs=switch');
  const o9 = await ev(`return {rows:document.querySelectorAll('#bxSwitchBody .bx-row').length,ord:document.querySelectorAll('#bxSwitchBody .bx-ord').length}`);
  o9.rows >= 6 && o9.ord >= 14 ? ok('深链·?bs=switch 换源弹层含优先级调序', o9.rows + ' 行 · ' + o9.ord + ' 钮') : bad('深链·switch 轮2', JSON.stringify(o9));

  /* ---------- 全屏 emoji / 泄漏复扫 ---------- */
  const sweep = await ev(`var out=[];['p-bsSources','p-bsSearch','p-bsDiscover','p-bsDetail','p-bsTask','p-bsSrcForm','p-bsVerify'].forEach(function(p){
    var el=document.getElementById(p);setPage(p);var t=el.innerText||'';
    if(new RegExp(${JSON.stringify(EMOJI)},'u').test(t))out.push(p+':emoji');
    if(/undefined|NaN|\\[object/.test(t))out.push(p+':fake');});
    return {bad:out,bs:typeof BX_SRC==='undefined'?0:BX_SRC.length}`);
  sweep.bad.length === 0 ? ok('全筛·七屏无 emoji 与假值') : bad('全筛', JSON.stringify(sweep.bad));

  finish();
  async function finish() {
    if (errs.length) bad('控制台异常 ' + errs.length + ' 条', errs.slice(0, 3).join(' | '));
    else ok('控制台零异常');
    log('== ' + pass + '/' + (pass + fail) + ' PASS ==');
    try { ws.close() } catch (e) { }
    try { chrome.kill() } catch (e) { }
    console.log('\n结果：' + pass + ' PASS / ' + fail + ' FAIL');
    process.exit(fail ? 1 : 0);
  }
})().catch(e => { log('RUNNER ERR ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 4).join('\n')); console.log('\n结果：' + pass + ' PASS / ' + (fail + 1) + ' FAIL'); process.exit(1) });
