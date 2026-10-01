/* V1.54 X-Ray 全书索引 · 批2 原型校验 v2（CDP 无头 Chrome · ?xr= 深链逐屏）
 * 形态=阅读页上拉全屏面板「目录｜X-Ray」双段（微信读书图1 版式）+ X-Ray 段内 Kindle 图2/3 列表与详情。
 * 用法：node --experimental-websocket tools/xraycheck.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const F = 'prototype/index-bookshelf.html';
const PORT = Number(process.env.XR_PORT || 9611);
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
  try { return JSON.parse(r.value); } catch (e) { return { __err: (r && (r.value || r.description)) || JSON.stringify(m).slice(0, 200) }; }
}
async function shot(name) {
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  const b = m.result && m.result.data;
  if (!b) { bad('截图 ' + name); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, name), Buffer.from(b, 'base64'));
  log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}
async function go(q) {
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve(F)).href + (q ? '?' + q : '') });
  await wait(2600);
}

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish(); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.xray-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) { } } await wait(300); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') { const t = ((m.params.exceptionDetails.exception || {}).description || m.params.exceptionDetails.text || '').slice(0, 160);
      if (!/tailwind is not defined/.test(t)) errs.push(t); } });
  await cmd('Runtime.enable'); await cmd('Page.enable');

  /* 面板形态：上拉全屏 · X-Ray 段 · 目录段回归 */
  await go('xr=panel');
  let r = await ev(`var d=document.getElementById('brTocDrawer'),pane=document.getElementById('xrPane'),sc=document.getElementById('brDrScroll');
    return{drawer:!d.classList.contains('hidden'),pane:!pane.classList.contains('hidden'),tocHidden:sc.classList.contains('hidden'),
      segXr:document.getElementById('xrSegXr').className.indexOf('on')>=0,
      wideFull:document.getElementById('brDrWide').className.indexOf('w-full')>=0,
      scopeSegs:document.querySelectorAll('#xrHead .xr-seg').length,
      types:document.querySelectorAll('#xrTypes .xr-tab').length,
      rows:document.querySelectorAll('#xrList .xr-row').length,
      curGrp:!document.getElementById('xr-grpCurLbl')&&!document.getElementById('xr-grpBookLbl'),
      bar:!!document.querySelector('#xr-bar-e_kmn i.now')};`);
  /* ④（工单20261001轮2）：全书范围不置顶「在当前页」分组；当前页只走范围段切换 */
  (r.drawer && r.pane && r.tocHidden && r.segXr && r.wideFull && r.scopeSegs === 3 && r.types === 7 && r.rows >= 15 && r.curGrp && r.bar)
    ? ok('面板=上拉全屏双段 · X-Ray 段：范围段3+类型段7+词条行+④全书态无当前页分组+行内分布条', 'rows=' + r.rows) : bad('面板形态', JSON.stringify(r));
  await shot('xr-panel.png');
  r = await ev(`document.getElementById('xrSegToc').click();
    var out={tocBack:!document.getElementById('brDrScroll').classList.contains('hidden'),
      paneOff:document.getElementById('xrPane').classList.contains('hidden'),
      foldRow:!document.getElementById('xrTocFoldRow').classList.contains('hidden'),
      lbl:(document.querySelector('#xrSearchPill span')||{}).textContent};
    document.getElementById('xrSearchPill').click();
    out.searchMode=!document.getElementById('xrHdrSearchRow').classList.contains('hidden')&&document.getElementById('xrHdrRow').classList.contains('hidden');
    var q=document.getElementById('xrHdrQ');q.value='第三章';xrHdrSearch('第三章');
    out.hits=!document.getElementById('brDrHits').classList.contains('hidden');
    out.clr=!document.getElementById('xrHdrClr').classList.contains('hidden');
    xrHdrClear();out.cleared=document.getElementById('brTocList').classList.contains('hidden')===false&&q.value==='';
    xrSearchExit();out.back=!document.getElementById('xrHdrRow').classList.contains('hidden');
    document.getElementById('xrSegXr').click();
    out.xrAgain=!document.getElementById('xrPane').classList.contains('hidden');
    out.xrLbl=(document.querySelector('#xrSearchPill span')||{}).textContent;
    out.segFlex=document.getElementById('xrSegToc').className.indexOf('flex-1')>=0&&document.getElementById('xrSearchPill').className.indexOf('flex-1')>=0;
    return out;`);
  (r.tocBack && r.paneOff && r.foldRow && r.searchMode && r.hits && r.clr && r.cleared && r.back && r.xrAgain && r.xrLbl === '搜词条' && r.segFlex)
    ? ok('头部三等分 · 点搜索独占态（输入/清空/取消）· 目录段命中与回归 · 段感知标签') : bad('头部/搜索', JSON.stringify(r));
  r = await ev(`var n0=document.querySelectorAll('#xrList .xr-row').length;xrSetScope('chapter');
    var n1=document.querySelectorAll('#xrList .xr-row').length;
    xrSetScope('page');
    var n2=document.querySelectorAll('#xrList .xr-row').length;
    var noLbl2=!document.getElementById('xr-grpCurLbl')&&!document.getElementById('xr-grpBookLbl');
    xrSetScope('book');
    return{n0:n0,n1:n1,n2:n2,noLbl2:noLbl2,back:document.querySelectorAll('#xrList .xr-row').length===n0};`);
  (r.n1 < r.n0 && r.n1 >= 2 && r.n2 <= r.n1 && r.noLbl2 && r.back) ? ok('范围段：当前页/本章只过滤不加组（④）· 全书回位', r.n0 + '→' + r.n1 + '→' + r.n2) : bad('范围段', JSON.stringify(r));
  r = await ev(`xrPickType('per');var per=document.querySelectorAll('#xrList .xr-row').length;xrPickType('all');
    xrToggleLow();var lowOn=/收起低置信/.test(document.getElementById('xr-lowmore').textContent);xrToggleLow();
    xrToggleSort();var sl=document.getElementById('xrSortBtn').textContent;
    return{per:per,lowOn:lowOn,sl:/按出场/.test(sl)};`);
  (r.per >= 5 && r.per < 15 && r.lowOn && r.sl) ? ok('类型段筛选 · 低置信展开 · 排序切换') : bad('类型/折叠/排序', JSON.stringify(r));

  /* 词条详情（段内子页）：时间轴 · 剧透保护 · 简介 · 候选并词 · 自学习动作 */
  await go('xr=ent');
  r = await ev(`var det=document.getElementById('xrList').innerText;
    return{pane:!document.getElementById('xrPane').classList.contains('hidden'),
      back:!!document.getElementById('xr-back'),name:/卡尼曼/.test(document.getElementById('xrList').innerText.slice(0,80)),
      desc:/诺贝尔/.test((document.getElementById('xr-desc-e_kmn')||{}).innerText||''),
      lg:!!document.querySelector('#xr-bar-e_kmn.lg i.now'),
      ticks:document.querySelectorAll('[id^="xr-tick-e_kmn-"]').length,
      clips:document.querySelectorAll('[id^="xr-clip-e_kmn"]').length,
      spoiler:/隐藏未读 1 处/.test(det),cand:!!document.getElementById('xr-cand'),
      into:!!document.getElementById('xr-merge-into'),ban:!!document.getElementById('xr-ban'),ai:/AI 释义 · 二期占位/.test(det)};`);
  (r.pane && r.back && r.name && r.desc && r.lg && r.ticks === 4 && r.clips === 3 && r.spoiler && r.cand && r.into && r.ban && r.ai)
    ? ok('详情子页：大时间轴(4点+橙线) · 剧透保护默认 · 简介 · 候选并词 · 合并进/不再显示', JSON.stringify(r)) : bad('详情', JSON.stringify(r));
  await shot('xr-ent.png');
  r = await ev(`xrToggleCites();return{clips:document.querySelectorAll('[id^="xr-clip-e_kmn"]').length,off:!document.getElementById('xr-spoiler')};`);
  (r.clips === 4 && r.off) ? ok('「显示全部引用」开关 → 未读引用出现') : bad('剧透开关', JSON.stringify(r));
  r = await ev(`var n0=xrEnts().length;document.getElementById('xr-cand').querySelector('button').click();
    return{lost:n0-xrEnts().length,toast:/已合并/.test(document.getElementById('toast').innerText)};`);
  (r.lost === 1 && r.toast) ? ok('候选卡一键并词（aliases+出场迁移）') : bad('候选并词', JSON.stringify(r));
  await go('xr=merge');
  r = await ev(`return{sh:!document.getElementById('sheetXrMerge').classList.contains('hidden'),rows:document.querySelectorAll('[id^="xr-mg-"]').length};`);
  (r.sh && r.rows >= 15) ? ok('「合并进…」半屏：全词条可选（'+r.rows+' 行）') : bad('合并半屏', JSON.stringify(r));
  r = await ev(`var n0=xrEnts().length;document.getElementById('xr-mg-e_hce').click();
    return{lost:n0-xrEnts().length,toast:/已合并/.test(document.getElementById('toast').innerText)};`);
  (r.lost === 1 && r.toast) ? ok('半屏选择目标执行合并') : bad('半屏合并', JSON.stringify(r));

  /* 跳转：详情片段 → 关面板 → 阅读位高亮 */
  await go('xr=jump');
  await wait(500);
  r = await ev(`return{drawer:document.getElementById('brTocDrawer').classList.contains('hidden'),
    page:curPage,toast:/已跳转/.test(document.getElementById('toast').innerText)};`);
  (r.drawer && r.page === 'p-readerPage' && r.toast) ? ok('片段/圆点跳转：关面板→定位→提示') : bad('跳转', JSON.stringify(r));
  r = await ev(`xrJumpTo(3,0);return{flash:!!document.querySelector('.br-flash-xr')};`);
  r.flash ? ok('段内高亮闪烁环在位') : bad('高亮环', JSON.stringify(r));
  await shot('xr-jump.png');

  /* 整理模式（多选合并/移除） */
  await go('xr=org');
  r = await ev(`return{bar:/已选 2 条/.test(document.getElementById('xrBar').innerText),
    merge:!!document.querySelector('#xrBar [onclick="xrMerge()"]'),del:!!document.querySelector('#xrBar [onclick="xrDelOpen()"]'),
    selChk:document.querySelectorAll('#xrList .xr-ck.on').length};`);
  (r.bar && r.merge && r.del && r.selChk === 2) ? ok('整理词条：多选态 + 底部合并/移除条') : bad('整理模式', JSON.stringify(r));
  await shot('xr-org.png');
  await go('xr=del');
  r = await ev(`return{sh:!document.getElementById('sheetXrDel').classList.contains('hidden'),scope:document.querySelectorAll('#xrDelScope .xr-scope-opt').length};`);
  (r.sh && r.scope === 2) ? ok('移除确认含「全局黑名单」升级选项') : bad('移除确认', JSON.stringify(r));
  r = await ev(`xrDelPickScope('global');var n0=xrEnts().length;xrDoDel();
    return{lost:n0-xrEnts().length,toast:/全局黑名单/.test(document.getElementById('toast').innerText)};`);
  (r.lost === 1 && r.toast) ? ok('全局黑名单移除生效') : bad('全局移除', JSON.stringify(r));

  /* 加词（面板入口 + 输入框） */
  await go('xr=addword');
  r = await ev(`return{sh:!document.getElementById('sheetXrAdd').classList.contains('hidden'),
      input:!!document.getElementById('xrAddWordIn'),types:document.querySelectorAll('#xrAddTypes .xr-tab').length,
      scopes:document.querySelectorAll('#xrAddScope .chip').length};`);
  (r.sh && r.input && r.types === 6 && r.scopes === 2) ? ok('＋加词弹层：输入框 + 6 类型 + 两范围') : bad('加词弹层', JSON.stringify(r));
  r = await ev(`document.getElementById('xrAddWordIn').value='巧克力';xrDoAdd();
    var l=document.getElementById('xrList').innerText;
    return{add:xrEnts().length,dom:/巧克力/.test(l),usr:/我的词条/.test(l)};`);
  (r.dom && r.usr) ? ok('加词入列（详情态 · 我的词条徽）') : bad('加词入列', JSON.stringify(r));

  /* 屏2 书架四态角标 + 长按入口 */
  await go('xr=shelf');
  r = await ev(`var bs=[].map.call(document.querySelectorAll('.xr-badge'),function(x){return x.textContent});
    return{n:bs.length,t:bs.join('|'),page:curPage};`);
  (r.page === 'p-bookshelf' && r.n >= 4 && /解析中 57%/.test(r.t) && /已暂停/.test(r.t) && /失败/.test(r.t) && /已索引/.test(r.t))
    ? ok('屏2 书架角标四态', r.t) : bad('屏2 角标', JSON.stringify(r));
  await shot('xr-shelf.png');
  await go('xr=menu');
  r = await ev(`var b=document.getElementById('lpXrBtn');
    return{sheet:!document.getElementById('sheetLongPress').classList.contains('hidden'),txt:b?b.textContent:''};`);
  (r.sheet && /全书索引/.test(r.txt)) ? ok('屏2 长按菜单「生成/管理全书索引」', r.txt.trim().slice(0, 30)) : bad('屏2 长按入口', JSON.stringify(r));

  /* 屏1 解析范围 */
  await go('xr=scope');
  r = await ev(`var o=[].map.call(document.querySelectorAll('#xrScopeOpts .xr-scope-opt'),function(x){return x.textContent});
    return{sh:!document.getElementById('sheetXrScope').classList.contains('hidden'),n:o.length,est:document.getElementById('xrScopeEst').textContent};`);
  (r.sh && r.n === 3 && /万字/.test(r.est)) ? ok('屏1 范围三选 · 预估字数（全书）', r.est) : bad('屏1 范围', JSON.stringify(r));
  r = await ev(`xrScopePick('range');return{h:!document.getElementById('xrScopeRange').classList.contains('hidden'),est:document.getElementById('xrScopeEst').textContent};`);
  (r.h && /字/.test(r.est)) ? ok('屏1 区间态起止章选择 · 预估联动', r.est) : bad('屏1 区间', JSON.stringify(r));
  await shot('xr-scope.png');

  /* 屏5 阅读器菜单 + 迷你卡（命中/未命中） */
  await go('xr=more');
  r = await ev(`var row=[].slice.call(document.querySelectorAll('#sheetBrMore [onclick^="closeSheet"]')).find(function(x){return /全书索引/.test(x.innerText)});
    return{sh:!document.getElementById('sheetBrMore').classList.contains('hidden'),row:row?row.innerText.replace(/\\s+/g,' '):''};`);
  (r.sh && /全书索引（X-Ray）/.test(r.row) && /已索引 12\/18 章 · 随阅读推进/.test(r.row)) ? ok('屏5 阅读器菜单行（入口=上拉面板 X-Ray 段）', r.row) : bad('屏5 菜单行', JSON.stringify(r));
  await go('xr=peek');
  r = await ev(`var chips=[].map.call(document.querySelectorAll('#brSelActs .sdb span'),function(x){return x.textContent});
    return{chip:chips.indexOf('X-Ray')>=0,sh:!document.getElementById('sheetXrPeek').classList.contains('hidden'),
      body:document.getElementById('xrPeekBody').innerText.slice(0,60)};`);
  (r.chip && r.sh && /系统1/.test(r.body) && /查看全部位置/.test(r.body)) ? ok('屏5 工具条 X-Ray · 迷你卡「查看全部位置」', r.body.replace(/\n/g, ' ').slice(0, 36)) : bad('屏5 peek', JSON.stringify(r));
  await shot('xr-peek.png');
  r = await ev(`document.querySelector('#xrPeekBody [onclick^="xrPeekToPanel"]').click();
    return{pane:!document.getElementById('xrPane').classList.contains('hidden'),drawer:!document.getElementById('brTocDrawer').classList.contains('hidden'),
      detail:/系统1/.test(document.getElementById('xrList').innerText.slice(0,60))};`);
  (r.pane && r.drawer && r.detail) ? ok('迷你卡→查看全部位置：开面板 X-Ray 段并选中词条') : bad('迷你卡跳转', JSON.stringify(r));
  await go('xr=add');
  r = await ev(`return{sh:!document.getElementById('sheetXrAdd').classList.contains('hidden'),word:document.getElementById('xrAddWordIn').value};`);
  (r.sh && r.word === '巧克力') ? ok('屏5 未命中→加为词条（预填选区词）') : bad('屏5 加词', JSON.stringify(r));

  /* 屏6 备份 · 屏7 中断 */
  await go('xr=bak');
  r = await ev(`return{sh:!document.getElementById('sheetXrBak').classList.contains('hidden'),row:!!document.getElementById('xrSetRow')};`);
  (r.sh && r.row) ? ok('屏6 阅读设置-数据 X-Ray 备份行+弹层') : bad('屏6 备份', JSON.stringify(r));
  r = await ev(`xrBakGo('imp');return{toast:/MD5 校验/.test(document.getElementById('toast').innerText)};`);
  r.toast ? ok('屏6 导入含 MD5 校验反馈') : bad('屏6 MD5', JSON.stringify(r));
  await go('xr=fail');
  r = await ev(`return{sh:!document.getElementById('sheetXrFail').classList.contains('hidden'),
      body:document.getElementById('xrFailBody').innerText.slice(0,40),
      btns:[].map.call(document.querySelectorAll('#sheetXrFail button'),function(x){return x.textContent}).join('|')};`);
  (r.sh && /12\/18/.test(r.body) && /从断点继续/.test(r.btns) && /重置索引/.test(r.btns)) ? ok('屏7 中断弹层：断点续跑/重置/关闭') : bad('屏7 中断', JSON.stringify(r));
  r = await ev(`xrFailRetry();return{st:xrState().status,p:xrState().p};`);
  (r.st === 'run' && r.p === 66) ? ok('屏7 断点继续转解析中') : bad('屏7 继续', JSON.stringify(r));

  /* V1.54.1 批2 · 词库管理页 + 启用开关 + 未命中二选一 */
  await go('xr=panel');
  r = await ev(`return{def:(BS_SET.brSelOps||[]).indexOf('X-Ray')>=0,
      reg:!!BR_SEL_TOOLS['X-Ray']};`);
  (r.def && r.reg) ? ok('批2 选区工具条默认名单含 X-Ray（修②：默认字面量补齐，非深链强制）') : bad('批2 默认名单', JSON.stringify(r));
  await go('xr=dict');
  r = await ev(`return{page:curPage,sum:document.getElementById('xrwSum').textContent,
    tg:document.getElementById('xrwToggle').className.indexOf('on')>=0,
    chips:document.querySelectorAll('#xrwTypeChips .chip').length,
    rows:document.querySelectorAll('#xrwList .shelf-row').length};`);
  (r.page === 'p-xrwords' && /3 个养成词/.test(r.sum) && r.tg && r.chips === 7 && r.rows === 3)
    ? ok('批2 词库管理页：3 养入词 + 7 类型筛选 + 开关默认开', r.sum) : bad('批2 管理页', JSON.stringify(r));
  await shot('xr-words.png');
  r = await ev(`document.getElementById('xrwAddInp').value='沉没成本';xrWordsAdd();
    var first=document.querySelector('#xrwList .shelf-row b');
    return{n:document.querySelectorAll('#xrwList .shelf-row').length,w:first?first.textContent:'',
      sum:document.getElementById('xrwSum').textContent};`);
  (r.n === 4 && r.w === '沉没成本' && /4 个养成词/.test(r.sum)) ? ok('批2 词库添加即置顶') : bad('批2 添加', JSON.stringify(r));
  r = await ev(`xrUserDictFlip();return{on:xrUserDictOn(),sum:document.getElementById('xrwSum').textContent};`);
  (r.on === false && /纯预置视角/.test(r.sum)) ? ok('批2 启用开关：关＝纯预置视角') : bad('批2 开关', JSON.stringify(r));
  await go('xr=panel');
  r = await ev(`document.getElementById('xrUserDictBtn').click();
    var b2=document.getElementById('xrUserDictBtn');
    return{txt:b2.textContent,on:b2.className.indexOf('chip-on')>=0};`);
  (/养词库 关/.test(r.txt) && !r.on) ? ok('批2 面板头养词库开关点按') : bad('批2 面板头开关', JSON.stringify(r));
  await go('xr=miss');
  r = await ev(`return{sh:!document.getElementById('sheetXrMiss').classList.contains('hidden'),
    w:document.getElementById('xrMissWord').textContent,
    btns:[].map.call(document.querySelectorAll('#sheetXrMiss button'),function(x){return x.textContent}).join('|')};`);
  (r.sh && r.w === '麦田里的守望者' && /加为词条/.test(r.btns) && /改为屏蔽/.test(r.btns))
    ? ok('批2 选区未命中二选一弹层', r.btns) : bad('批2 未命中弹层', JSON.stringify(r));
  r = await ev(`xrMissBan();var out={toast:/已屏蔽/.test(document.getElementById('toast').innerText)};
    xrAddOpen('巧克力');out.prefill=document.getElementById('xrAddWordIn').value;
    return out;`);
  (r.toast && r.prefill === '巧克力') ? ok('批2 改为屏蔽反馈 + 二选一→加词预填') : bad('批2 屏蔽', JSON.stringify(r));
  await go('xr=more');
  r = await ev(`var row=[].slice.call(document.querySelectorAll('#sheetBrMore [onclick^="closeSheet"]')).find(function(x){return /词库管理/.test(x.innerText)});
    return{row:row?row.innerText.replace(/\\s+/g,' '):''};`);
  (/X-Ray 词库管理/.test(r.row) && /养词库 开/.test(r.row)) ? ok('批2 ⋯菜单词库管理行', r.row) : bad('批2 菜单行', JSON.stringify(r));
  await go('xr=bak');
  r = await ev(`rsPickTab(RS_SEC.length-1);renderReadSet();
    var row=[].slice.call(document.querySelectorAll('#rsGroups .mini-btn')).find(function(b){return false});
    var nav=[].slice.call(document.querySelectorAll('#rsGroups b')).find(function(x){return /X-Ray 词库管理/.test(x.textContent)});
    return{nav:nav?nav.textContent:''};`);
  (r.nav === 'X-Ray 词库管理') ? ok('批2 阅读设置「本地阅读器」入口行') : bad('批2 设置入口', JSON.stringify(r));

  /* 收尾：emoji 与异常 */
  const EM = '[\\u{1F300}-\\u{1FAFF}\\u{FE0F}]';
  r = await ev(`var re=new RegExp(${JSON.stringify(EM)},'gu');
    var out='';['xrPane','sheetXrScope','sheetXrAdd','sheetXrPeek','sheetXrBak','sheetXrFail','sheetXrDel','sheetXrMerge','sheetXrMiss','p-xrwords'].forEach(function(id){var el=document.getElementById(id);out+=(el?el.innerText:'')});
    var m=out.match(re)||[];return{emoji:m.join(''),fns:[typeof xrRender,typeof xrPickEnt,typeof xrSelTool,typeof xrScopeOpen,typeof xrLpGo,typeof brTocTab].join(',')};`);
  (!r.emoji && r.fns === 'function,function,function,function,function,function') ? ok('零 emoji · 关键函数在位') : bad('emoji/函数', JSON.stringify(r));
  if (errs.length) bad('运行期异常', errs.join(' | ')); else ok('全程零 JS 异常');
  return finish();
})().catch((e) => { bad('脚本自身', String(e).slice(0, 200)); finish(); });

function finish() { try { ws && ws.close(); } catch (e) { } log(''); log('结果：' + pass + ' 绿 / ' + fail + ' 红'); process.exit(fail ? 1 : 0); }
