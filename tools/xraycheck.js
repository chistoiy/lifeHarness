/* V1.54 X-Ray 全书索引 · 批2 原型校验（CDP 无头 Chrome · ?xr= 深链逐屏）
 * 覆盖 设计书§9 七屏：范围弹层/书架入口+角标/面板(标签·搜索·折叠·整理)/实体详情+跳转/
 * 阅读器菜单+选区工具条(X-Ray·加为词条)/设置-数据备份/失败中断。
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

  /* 屏2 书架四态角标 */
  await go('xr=shelf');
  let r = await ev(`var bs=[].map.call(document.querySelectorAll('.xr-badge'),function(x){return x.textContent});
    return{n:bs.length,t:bs.join('|'),page:curPage};`);
  (r.page === 'p-bookshelf' && r.n >= 4 && /解析中 57%/.test(r.t) && /已暂停/.test(r.t) && /失败/.test(r.t) && /已索引/.test(r.t))
    ? ok('屏2 书架角标四态', r.t) : bad('屏2 角标', JSON.stringify(r));
  await shot('xr-shelf.png');

  /* 屏2 长按菜单入口 */
  await go('xr=menu');
  r = await ev(`var b=document.getElementById('lpXrBtn');
    return{sheet:!document.getElementById('sheetLongPress').classList.contains('hidden'),txt:b?b.textContent:''};`);
  (r.sheet && /全书索引/.test(r.txt)) ? ok('屏2 长按菜单「生成/管理全书索引」', r.txt.trim().slice(0, 30)) : bad('屏2 长按入口', JSON.stringify(r));
  await shot('xr-menu.png');

  /* 屏1 解析范围弹层 */
  await go('xr=scope');
  r = await ev(`var o=[].map.call(document.querySelectorAll('#xrScopeOpts .xr-scope-opt'),function(x){return x.textContent});
    return{sh:!document.getElementById('sheetXrScope').classList.contains('hidden'),n:o.length,est:document.getElementById('xrScopeEst').textContent,rangeHidden:document.getElementById('xrScopeRange').classList.contains('hidden')};`);
  (r.sh && r.n === 3 && /万字/.test(r.est) && r.rangeHidden) ? ok('屏1 范围三选 · 预估字数（全书）', r.est) : bad('屏1 范围', JSON.stringify(r));
  r = await ev(`xrScopePick('range');var h=!document.getElementById('xrScopeRange').classList.contains('hidden');return{h:h,est:document.getElementById('xrScopeEst').textContent};`);
  (r.h && r.est && /字/.test(r.est)) ? ok('屏1 区间态出现起止章选择 · 预估联动', r.est) : bad('屏1 区间', JSON.stringify(r));
  await shot('xr-scope.png');

  /* 屏3 面板：标签/排序/低分折叠/搜索 */
  await go('xr=panel');
  r = await ev(`return{page:curPage,tabs:[].map.call(document.querySelectorAll('#xrTabs .xr-tab'),function(x){return x.textContent}),
    rows:document.querySelectorAll('#xrList .xr-ent').length,low:!!document.getElementById('xr-lowtoggle'),
    head:(document.getElementById('xrHead').innerText||'').slice(0,20)};`);
  (r.page === 'p-xray' && r.tabs.length === 6 && r.rows > 5 && r.low && /已解析 12\/18/.test(r.head))
    ? ok('屏3 面板六标签 · 词条列表 · 低分折叠 · 已解析x/y章', r.tabs.join('|')) : bad('屏3 面板', JSON.stringify(r));
  r = await ev(`var before=document.querySelectorAll('#xrList .xr-ent').length;
    document.getElementById('xr-lowtoggle').click();
    var after=document.querySelectorAll('#xrList .xr-ent').length;
    var anyLow=[].slice.call(document.querySelectorAll('#xr-lowzone .xr-ent')).some(function(x){return /0\\.[0-6]/.test(x.innerText)});
    return{before:before,after:after,anyLow:after>before&&anyLow};`);
  r.anyLow ? ok('屏3 低分折叠展开（0.7 以下入折叠区）', r.before + '→' + r.after) : bad('屏3 折叠展开', JSON.stringify(r));
  await shot('xr-panel.png');
  r = await ev(`document.getElementById('xrQ').value='特沃';document.getElementById('xrQ').dispatchEvent(new Event('input'));
    var per=document.querySelector('#xr-tab-per');per&&per.click();
    var rows=[].map.call(document.querySelectorAll('#xrList .xr-ent b'),function(x){return x.textContent});
    return{rows:rows};`);
  (r.rows.length === 1 && /特沃斯基/.test(r.rows[0])) ? ok('屏3 类内搜索（人名·特沃→1条）', r.rows.join('|')) : bad('屏3 搜索', JSON.stringify(r));

  /* 屏3 整理：合并与移除 */
  await go('xr=org');
  r = await ev(`var bar=!document.getElementById('xrBar').classList.contains('hidden');
    var cnt=(document.getElementById('xrBar').innerText.match(/已选 (\\d+) 条/)||[])[1];
    return{bar:bar,cnt:cnt,merge:!!document.querySelector('#xrBar [onclick="xrMerge()"]'),del:!!document.querySelector('#xrBar [onclick="xrDelOpen()"]')};`);
  (r.bar && r.cnt === '2' && r.merge && r.del) ? ok('屏3 整理模式 · 多选合并/移除条', '已选 ' + r.cnt) : bad('屏3 整理', JSON.stringify(r));
  await shot('xr-org.png');
  r = await ev(`var n0=xrEnts().length;xrMerge();
    var kn=xrEnts().find(function(v){return v.id==='e_kmn'});
    return{lost:n0-xrEnts().length,alias:kn&&kn.aliases?kn.aliases.length:0,toast:/已合并/.test(document.getElementById('toast').innerText)};`);
  (r.lost === 1 && r.alias === 1 && r.toast) ? ok('屏3 合并执行 · aliases 归一出场迁移', JSON.stringify(r)) : bad('屏3 合并', JSON.stringify(r));
  r = await ev(`xrSel('e_s1');xrDelOpen();
    return{sh:!document.getElementById('sheetXrDel').classList.contains('hidden'),scope:document.querySelectorAll('#xrDelScope .xr-scope-opt').length};`);
  (r.sh && r.scope === 2) ? ok('屏7 移除确认含「全局黑名单」升级选项', '') : bad('移除确认', JSON.stringify(r));
  await shot('xr-del.png');
  r = await ev(`xrDelPickScope('global');var n0=xrEnts().length;xrDoDel();
    return{lost:n0-xrEnts().length,toast:/全局黑名单/.test(document.getElementById('toast').innerText)};`);
  (r.lost === 1 && r.toast) ? ok('屏7 全局黑名单移除生效') : bad('全局移除', JSON.stringify(r));

  /* 屏4 实体详情 + 跳转 */
  await go('xr=ent');
  r = await ev(`var bd=document.getElementById('xrEntBody').innerText;
    return{sh:!document.getElementById('sheetXrEnt').classList.contains('hidden'),
      hasName:/卡尼曼/.test(bd),spark:document.querySelectorAll('#xr-spark-e_kmn i').length,
      ments:document.querySelectorAll('[id^="xr-ment-e_kmn"]').length,ai:/AI 释义 · 二期占位/.test(bd),dlg:/台词 34/.test(bd)};`);
  (r.sh && r.hasName && r.spark === 18 && r.ments === 4 && r.ai && r.dlg)
    ? ok('屏4 实体详情：频次分布18柱 · 出场4条 · 台词 · AI预留位', JSON.stringify(r)) : bad('屏4 详情', JSON.stringify(r));
  await shot('xr-ent.png');
  await go('xr=jump');
  await wait(400);
  r = await ev(`return{page:curPage,toast:/已跳转/.test(document.getElementById('toast').innerText),
    flash:!!document.querySelector('.br-flash-xr')};`);
  (r.page === 'p-readerPage' && r.toast) ? ok('屏4 出场点击→跳阅读位置（跳转文案）', JSON.stringify(r)) : bad('屏4 跳转', JSON.stringify(r));
  r = await ev(`xrJumpTo(3,0);return{flash:!!document.querySelector('.br-flash-xr')};`);
  r.flash ? ok('屏4 段内高亮闪烁环在位') : bad('屏4 高亮环', JSON.stringify(r));
  await shot('xr-jump.png');

  /* 屏5 阅读器菜单 + 选区工具条 */
  await go('xr=more');
  r = await ev(`var row=[].slice.call(document.querySelectorAll('#sheetBrMore [onclick^="closeSheet"]')).find(function(x){return /全书索引/.test(x.innerText)});
    return{sh:!document.getElementById('sheetBrMore').classList.contains('hidden'),row:row?row.innerText.replace(/\\s+/g,' '):''};`);
  (r.sh && /全书索引（X-Ray）/.test(r.row) && /已解析 12\/18 章/.test(r.row)) ? ok('屏5 阅读器菜单「全书索引（X-Ray）」行', r.row) : bad('屏5 菜单行', JSON.stringify(r));
  await shot('xr-more.png');
  await go('xr=peek');
  r = await ev(`var chips=[].map.call(document.querySelectorAll('#brSelActs .sdb span'),function(x){return x.textContent});
    return{chip:chips.indexOf('X-Ray')>=0,sh:!document.getElementById('sheetXrPeek').classList.contains('hidden'),
      body:document.getElementById('xrPeekBody').innerText.slice(0,60)};`);
  (r.chip && r.sh && /系统1/.test(r.body) && /面板中查看/.test(r.body)) ? ok('屏5 工具条 X-Ray 动作 · 命中浮摘要', r.body.replace(/\n/g, ' ').slice(0, 40)) : bad('屏5 peek', JSON.stringify(r));
  await shot('xr-peek.png');
  await go('xr=add');
  r = await ev(`return{sh:!document.getElementById('sheetXrAdd').classList.contains('hidden'),
      word:document.getElementById('xrAddWord').textContent,types:document.querySelectorAll('#xrAddTypes .xr-tab').length,
      scopes:document.querySelectorAll('#xrAddScope .chip').length};`);
  (r.sh && r.word === '巧克力' && r.types === 6 && r.scopes === 2) ? ok('屏5 未命中→加为词条（6 类型+两范围）', r.word) : bad('屏5 加词', JSON.stringify(r));
  await shot('xr-add.png');
  r = await ev(`var n0=xrEnts().length;xrDoAdd();
    if(curPage!=='p-xray')navTo('p-xray');xrRender();
    var l=document.getElementById('xrList').innerText;
    var tt=(document.getElementById('toast')||{}).innerText||'';
    return{add:xrEnts().length-n0,dom:/巧克力/.test(l)&&/我的词条/.test(l),
      toast:/已加词/.test(tt),tt:tt.slice(0,30)};`);
  (r.add === 1 && r.dom) ? ok('屏5 加词入列（我的词条徽）', 'toast=' + r.tt || '(空)') : bad('加词入列', JSON.stringify(r));

  /* 屏6 设置-数据 · 备份 */
  await go('xr=bak');
  r = await ev(`return{page:curPage,sh:!document.getElementById('sheetXrBak').classList.contains('hidden'),
      row:!!document.getElementById('xrSetRow'),exp:document.getElementById('xrBakExport').innerText,imp:document.getElementById('xrBakImport').innerText};`);
  (r.sh && r.row && /\.xraybak/.test(r.exp) && /从备份导入/.test(r.imp)) ? ok('屏6 阅读设置-数据 X-Ray 备份行+弹层', '') : bad('屏6 备份', JSON.stringify(r));
  await shot('xr-bak.png');
  r = await ev(`xrBakGo('imp');return{toast:/MD5 校验/.test(document.getElementById('toast').innerText)};`);
  r.toast ? ok('屏6 导入含 MD5 校验反馈') : bad('屏6 MD5', JSON.stringify(r));

  /* 屏7 失败/中断 */
  await go('xr=fail');
  r = await ev(`return{sh:!document.getElementById('sheetXrFail').classList.contains('hidden'),
      body:document.getElementById('xrFailBody').innerText.slice(0,40),
      btns:[].map.call(document.querySelectorAll('#sheetXrFail button'),function(x){return x.textContent}).join('|')};`);
  (r.sh && /12\/18/.test(r.body) && /从断点继续/.test(r.btns) && /重置索引/.test(r.btns) && /关闭/.test(r.btns))
    ? ok('屏7 中断弹层：断点续跑/重置/关闭', r.btns) : bad('屏7 中断', JSON.stringify(r));
  await shot('xr-fail.png');
  r = await ev(`xrFailRetry();return{st:xrState().status,p:xrState().p};`);
  (r.st === 'run' && r.p === 66) ? ok('屏7 断点继续转解析中') : bad('屏7 继续', JSON.stringify(r));

  /* 收尾：emoji 与异常 */
  const EM = '[\\u{1F300}-\\u{1FAFF}\\u{FE0F}]';
  r = await ev(`var re=new RegExp(${JSON.stringify(EM)},'gu');
    var out='';['p-xray','sheetXrScope','sheetXrEnt','sheetXrAdd','sheetXrPeek','sheetXrBak','sheetXrFail','sheetXrDel'].forEach(function(id){var el=document.getElementById(id);out+=(el?el.innerText:'')});
    var m=out.match(re)||[];return{emoji:m.join(''),fns:[typeof xrRender,typeof xrEntOpen,typeof xrSelTool,typeof xrScopeOpen,typeof xrLpGo].join(',')};`);
  (!r.emoji && r.fns === 'function,function,function,function,function') ? ok('七屏零 emoji · 关键函数在位') : bad('emoji/函数', JSON.stringify(r));
  if (errs.length) bad('运行期异常', errs.join(' | ')); else ok('全程零 JS 异常');
  return finish();
})().catch((e) => { bad('脚本自身', String(e).slice(0, 200)); finish(); });

function finish() { try { ws && ws.close(); } catch (e) { } log(''); log('结果：' + pass + ' 绿 / ' + fail + ' 红'); process.exit(fail ? 1 : 0); }
