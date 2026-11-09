/* mm_shot.js · 思维导图专版 F2/F3：注入副本 + CDP 真 390 视口截图矩阵
 * 用法：NODE_PATH=<node-workspace>/node_modules node tools/mm_shot.js [输出目录]
 * 矩阵：浅色 ×（列表 / 画布 / 挂笔记弹层 / md转导图弹层）＋ 深色 ×（画布 / 弹层）
 * 色档必须 emulateMediaFeatures 钉 prefers-color-scheme（headless 缺省 dark）。
 */
const path = require('path'), fs = require('fs'), os = require('os');
const puppeteer = require('puppeteer-core');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const SRC = path.join(__dirname, '..', 'prototype', 'index-mindmap.html');
const OUT = process.argv[2] || path.join(os.homedir(), '.workbuddy', 'shots', 'mindmap');
const PROFILE = path.join(os.tmpdir(), 'mm-cdp-profile');

fs.mkdirSync(OUT, { recursive: true });

/* ---- F2 注入副本：按 URL 参数驱动到目标态 ----
 * 时序坑（2026-10-12 实锤两轮）：注入脚本裸跑会与原型的 DOMContentLoaded 抢时序——
 * 原型注册的 setPage('mm-list') 在前、注入在后执行 ⇒ 注入被覆盖（诊断里 page 恒
 * mm-list 而画布已渲染＝假象）。现已给原型补 hash 深链（mmBoot），工装改走 **hash 驱动**：
 * 注入只在 hashchange 之后动作，与壳内 REDIRECTS 落地的真实路径同源，不再抢时序。
 */
function inject(shot) {
  return `
(function(){
  var q=new URLSearchParams(location.search);
  if(q.get('dark'))document.documentElement.classList.add('dark');
  var s=q.get('shot')||'list';
  var go=function(){
    if(s==='list'||s==='empty'){ if(s==='empty'){MAPS.length=0;} mmBoot(); }
    if(s==='canvas'){ mmBoot(); }
    if(s==='bind'){ mmBoot(); mmSelect('n1'); openSheet('sheetMm-bindNote'); }
    if(s==='frommd'){ mmBoot(); openSheet('sheetMm-fromMd'); mmPickMd('m1'); }
    if(s==='frominbox'){ mmBoot(); mmPickInbox('i1'); mmPickInbox('i3'); openSheet('sheetMm-fromInbox'); }
    if(s==='nodemenu'){ mmBoot(); mmSelect('n2');
      var vp=document.getElementById('mmCanvas').getBoundingClientRect();
      openNodeMenuAt({id:'n2'}, vp.width/2, vp.height/2); }
    /* 2026-10-12 查漏补缺批新增态（补 ②卡片/图管理/二次确认/收集箱侧入口/编辑节点/多根） */
    if(s==='map'){ mmBoot(); mmMapMenu('g1'); }
    if(s==='confirm'){ mmBoot(); mmSelect('n1'); mmDelNode(); }
    if(s==='card'){ mmBoot(); openSheet('sheetMm-card'); }
    if(s==='inboxto'){ mmBoot(); openSheet('sheetMm-inboxTo'); }
    if(s==='nodeedit'){ mmBoot(); mmSelect('n1'); mmEditNode(); }
    if(s==='multroot'){ mmBoot(); mmSelect('r'); mmAddRoot();
      document.getElementById('mmNodeInput').value='第二棵树';
      document.getElementById('mmNodeNote').value='一图多根示例';
      mmSaveNode(); }
    /* 2026-10-12 全批次批新增态（批2 撤销/搜索/文件夹/导出/换行；批3 样式；批4 布局；批5 标签任务图片） */
    if(s==='more'){ mmBoot(); mmOpenMore(); }
    if(s==='search'){ mmBoot(); mmOpenSearch();
      document.getElementById('mmSearchInput').value='时间'; mmRenderSearch(); }
    if(s==='folders'){ mmBoot(); mmOpenFolders(); }
    if(s==='export'){ mmBoot(); mmOpenExport(); }
    if(s==='style'){ mmBoot(); mmOpenStyle();
      mmSetStyle('bg','soft'); mmSetStyle('line','accent'); mmSetStyle('text','accent'); }
    if(s==='layout'){ mmBoot(); mmOpenLayout(); }
    if(s==='radial'){ mmBoot(); mmApplyPreset('radial/both/portrait'); }
    if(s==='landscape'){ mmBoot(); mmApplyPreset('tree/both/landscape'); }
    if(s==='wrap'){ mmBoot();
      var wn=cur.nodes.filter(function(x){return x.id==='n2';})[0];
      wn.t='注意力残留\\n（记录切换成本）'; wn.tags=['方法','复盘']; wn.task=true; wn.img=true;
      renderCanvas(); mmFit(); }
  };
  window.addEventListener('hashchange',go);
  window.addEventListener('load',function(){ go(); });
})();`;
}

(async () => {
  const tmp = path.join(os.tmpdir(), 'mm-inject.html');
  fs.writeFileSync(tmp, fs.readFileSync(SRC, 'utf8').replace('</body>', '<script>' + inject() + '</script>\n</body>'));

  const b = await puppeteer.launch({
    executablePath: CHROME, headless: 'new',
    userDataDir: PROFILE,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--hide-scrollbars']
  });
  const p = await b.newPage();
  await p.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });

  const errs = [];
  p.on('pageerror', e => errs.push('pageerror: ' + e.message));
  p.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });

  const shots = [
    { q: 'shot=list', hash: 'mm-list', dark: 0, name: '01-light-list' },
    { q: 'shot=canvas', hash: 'mm-canvas', dark: 0, name: '02-light-canvas' },
    { q: 'shot=bind', hash: 'mm-canvas', dark: 0, name: '03-light-bind-sheet' },
    { q: 'shot=frommd', hash: 'mm-list', dark: 0, name: '04-light-frommd' },
    { q: 'shot=frominbox', hash: 'mm-list', dark: 0, name: '05-light-frominbox' },
    { q: 'shot=nodemenu', hash: 'mm-canvas', dark: 0, name: '06-light-nodemenu' },
    { q: 'shot=list', hash: 'mm-list', dark: 1, name: '07-dark-list' },
    { q: 'shot=canvas', hash: 'mm-canvas', dark: 1, name: '08-dark-canvas' },
    { q: 'shot=bind', hash: 'mm-canvas', dark: 1, name: '09-dark-bind-sheet' },
    { q: 'shot=frommd', hash: 'mm-list', dark: 1, name: '10-dark-frommd' },
    { q: 'shot=empty', hash: 'mm-list', dark: 0, name: '11-light-empty' },
    { q: 'shot=map', hash: 'mm-list', dark: 0, name: '13-light-map-sheet' },
    { q: 'shot=confirm', hash: 'mm-canvas', dark: 0, name: '14-light-confirm-sheet' },
    { q: 'shot=card', hash: 'mm-list', dark: 0, name: '15-light-card-sheet' },
    { q: 'shot=inboxto', hash: 'mm-list', dark: 0, name: '16-light-inboxto-sheet' },
    { q: 'shot=nodeedit', hash: 'mm-canvas', dark: 0, name: '17-light-node-edit' },
    { q: 'shot=multroot', hash: 'mm-canvas', dark: 0, name: '18-light-multiroot' },
    { q: 'shot=map', hash: 'mm-list', dark: 1, name: '19-dark-map-sheet' },
    /* 全批次新增态 */
    { q: 'shot=more', hash: 'mm-list', dark: 0, name: '20-light-more-sheet' },
    { q: 'shot=search', hash: 'mm-list', dark: 0, name: '21-light-search' },
    { q: 'shot=folders', hash: 'mm-list', dark: 0, name: '22-light-folders' },
    { q: 'shot=export', hash: 'mm-list', dark: 0, name: '23-light-export' },
    { q: 'shot=style', hash: 'mm-canvas', dark: 0, name: '24-light-style' },
    { q: 'shot=layout', hash: 'mm-canvas', dark: 0, name: '25-light-layout' },
    { q: 'shot=radial', hash: 'mm-canvas', dark: 0, name: '26-light-radial' },
    { q: 'shot=landscape', hash: 'mm-canvas', dark: 0, name: '27-light-landscape' },
    { q: 'shot=wrap', hash: 'mm-canvas', dark: 0, name: '28-light-wrap-node' },
    { q: 'shot=style', hash: 'mm-canvas', dark: 1, name: '29-dark-style' },
    { q: 'shot=layout', hash: 'mm-canvas', dark: 1, name: '30-dark-layout' },
    { q: 'shot=radial', hash: 'mm-canvas', dark: 1, name: '31-dark-radial' }
  ];

  const diag = [];
  const wantPage = { list: 'mm-list', canvas: 'mm-canvas', bind: 'mm-canvas', nodemenu: 'mm-canvas', frommd: 'mm-list', frominbox: 'mm-list', empty: 'mm-list',
    map: 'mm-list', confirm: 'mm-canvas', card: 'mm-list', inboxto: 'mm-list', nodeedit: 'mm-canvas', multroot: 'mm-canvas',
    more: 'mm-list', search: 'mm-list', folders: 'mm-list', export: 'mm-list',
    style: 'mm-canvas', layout: 'mm-canvas', radial: 'mm-canvas', landscape: 'mm-canvas', wrap: 'mm-canvas' };
  const wantSheet = { bind: 'sheetMm-bindNote', frommd: 'sheetMm-fromMd', frominbox: 'sheetMm-fromInbox',
    map: 'sheetMm-map', confirm: 'sheetMm-confirm', card: 'sheetMm-card', inboxto: 'sheetMm-inboxTo', nodeedit: 'sheetMm-node',
    more: 'sheetMm-more', search: 'sheetMm-search', folders: 'sheetMm-folders', export: 'sheetMm-export',
    style: 'sheetMm-style', layout: 'sheetMm-layout' };
  const bad = [];
  for (const s of shots) {
    await p.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: s.dark ? 'dark' : 'light' }]);
    const url = 'file:///' + tmp.replace(/\\/g, '/') + '?' + s.q + (s.dark ? '&dark=1' : '') + '#' + s.hash;
    await p.goto(url, { waitUntil: 'load' });
    await new Promise(r => setTimeout(r, 700));
    await p.screenshot({ path: path.join(OUT, s.name + '.png') });
    /* 诊断回读：视口宽 / 当前屏 / 选中节点 / 弹层开合 / 节点数 */
    const d = await p.evaluate(() => ({
      vw: document.documentElement.clientWidth,
      phone: (document.getElementById('phone') || {}).clientWidth,
      page: (document.querySelector('.page.active') || {}).id,
      dark: document.documentElement.classList.contains('dark'),
      nodes: document.querySelectorAll('.mm-node').length,
      sel: (document.querySelector('.mm-node.sel .mm-txt') || {}).textContent,
      sheets: Array.from(document.querySelectorAll('.sheet.open')).map(x => x.id).join(','),
      menu: (document.getElementById('mmNodeMenu') || {}).classList ? document.getElementById('mmNodeMenu').classList.contains('open') : null,
      scale: (document.getElementById('mmScaleTag') || {}).textContent,
      title: (document.getElementById('pageTitle') || {}).textContent,
      roots: (function(){ try{ var cs={}; Object.keys(TREE).forEach(function(p){(TREE[p]||[]).forEach(function(k){cs[k]=1;});});
        return cur.nodes.filter(function(n){return !cs[n.id];}).length; }catch(e){ return -1; } })(),
      confirmBody: (document.getElementById('mmConfirmBody') || {}).textContent || '',
      view: (typeof VIEW !== 'undefined') ? (VIEW.struct + '/' + VIEW.dir + '/' + VIEW.ratio) : '',
      wrap: document.querySelectorAll('.mm-node.wrap').length,
      tags: document.querySelectorAll('.mm-node .mm-tag').length,
      tasks: document.querySelectorAll('.mm-node .mm-task').length,
      thumbs: document.querySelectorAll('.mm-node .mm-thumb').length,
      folders: document.querySelectorAll('#mmRows .folder-hd').length,
      searchRows: document.querySelectorAll('#mmSearchList .row').length,
      moreRows: document.querySelectorAll('#mmMoreList .op').length,
      layCards: document.querySelectorAll('#mmLayGrid .lay-card').length,
      exportSpec: (document.getElementById('mmExportSpec') || {}).textContent || ''
    }));
    /* 断言：屏态/弹层态/色档必须与本张矩阵项一致，否则这张图不算数（防假绿） */
    const key = (s.q.match(/shot=([a-z]+)/) || [])[1];
    if (d.vw !== 390) bad.push(s.name + ' 视口非 390（' + d.vw + '）');
    if (d.page !== wantPage[key]) bad.push(s.name + ' 屏态错：期望 ' + wantPage[key] + ' 实得 ' + d.page);
    if (!!d.dark !== !!s.dark) bad.push(s.name + ' 色档错：期望 dark=' + !!s.dark + ' 实得 ' + d.dark);
    if (wantSheet[key] && d.sheets.indexOf(wantSheet[key]) < 0) bad.push(s.name + ' 弹层未开：' + (d.sheets || '无'));
    if (key === 'nodemenu' && !d.menu) bad.push(s.name + ' 节点操作单未开');
    if ((key === 'canvas' || key === 'bind' || key === 'nodemenu' || key === 'confirm' || key === 'nodeedit' || key === 'multroot') && d.nodes < 10) bad.push(s.name + ' 画布节点数异常少：' + d.nodes);
    if (key === 'multroot' && d.roots < 2) bad.push(s.name + ' 多根未生效：根数 ' + d.roots + '（期望 ≥2）');
    if (key === 'confirm' && !/子节点/.test(d.confirmBody)) bad.push(s.name + ' 删除确认未列明连带子级：' + d.confirmBody);
    /* 全批次新增态对位断言 */
    if (key === 'radial' && d.view.indexOf('radial') !== 0) bad.push(s.name + ' 放射布局未生效：' + d.view);
    if (key === 'landscape' && d.view !== 'tree/both/landscape') bad.push(s.name + ' 双向/横向布局未生效：' + d.view);
    if (key === 'layout' && d.layCards < 4) bad.push(s.name + ' 布局预设卡不足 4 个：' + d.layCards);
    if (key === 'wrap' && (d.wrap < 1 || d.tags < 2 || d.tasks < 1 || d.thumbs < 1)) bad.push(s.name + ' 批5/换行元素缺失 wrap=' + d.wrap + ' tags=' + d.tags + ' task=' + d.tasks + ' img=' + d.thumbs);
    if (key === 'search' && d.searchRows < 1) bad.push(s.name + ' 搜索结果为空（应有匹配行）');
    if (key === 'more' && d.moreRows < 3) bad.push(s.name + ' 更多菜单条目不足：' + d.moreRows);
    if (key === 'list' && d.folders < 2) bad.push(s.name + ' 列表未按文件夹分组：' + d.folders);
    if (key === 'export' && !/单文件/.test(d.exportSpec)) bad.push(s.name + ' 导出规格未渲染');
    diag.push(s.name + '  vw=' + d.vw + ' page=' + d.page + ' dark=' + d.dark +
      ' nodes=' + d.nodes + ' roots=' + d.roots + ' sel=' + (d.sel || '-') + ' sheet=[' + d.sheets + '] menu=' + d.menu +
      ' view=' + d.view + ' scale=' + d.scale + ' title=' + d.title);
  }

  /* ---- 交互断言：自由拖拽定位（2d 裁定 2026-10-12 改口）必须真能拖动 ----
     只截静态图证明不了「拖得动」，故真发 pointer 事件拖一枚节点，
     验 dx/dy 已写、屏幕 left/top 变了、连线跟着变。 */
  await p.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }]);
  await p.goto('file:///' + tmp.replace(/\\/g, '/') + '?shot=canvas#mm-canvas', { waitUntil: 'load' });
  await new Promise(r => setTimeout(r, 700));
  const drag = await p.evaluate(async () => {
    const el = document.querySelector('.mm-node[data-id="n2"]');
    if (!el) return { err: '找不到 n2 节点' };
    const before = { left: el.style.left, top: el.style.top, dx: (cur.nodes.find(n => n.id === 'n2') || {}).dx || 0 };
    const edgeBefore = document.querySelectorAll('#mmEdges path').length
      + ':' + (document.querySelector('#mmEdges path') || {}).getAttribute('d');
    const r = el.getBoundingClientRect();
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const opts = (x, y) => ({ pointerId: 1, isPrimary: true, button: 0, buttons: 1, clientX: x, clientY: y, bubbles: true, cancelable: true });
    el.dispatchEvent(new PointerEvent('pointerdown', opts(cx, cy)));
    await new Promise(r2 => setTimeout(r2, 30));
    el.dispatchEvent(new PointerEvent('pointermove', opts(cx + 60, cy + 90)));
    await new Promise(r2 => setTimeout(r2, 30));
    el.dispatchEvent(new PointerEvent('pointerup', opts(cx + 60, cy + 90)));
    await new Promise(r2 => setTimeout(r2, 120));
    const el2 = document.querySelector('.mm-node[data-id="n2"]');
    const after = { left: el2 ? el2.style.left : '', top: el2 ? el2.style.top : '', dx: (cur.nodes.find(n => n.id === 'n2') || {}).dx || 0 };
    const edgeAfter = (document.querySelector('#mmEdges path') || {}).getAttribute('d');
    return { before, after, edgeBefore, edgeAfter };
  });
  if (drag.err) bad.push('拖拽探针：' + drag.err);
  else {
    if (!drag.after.dx) bad.push('拖拽未写 dx（节点拖不动）');
    if (drag.after.left === drag.before.left && drag.after.top === drag.before.top) bad.push('拖拽后屏幕坐标未变');
    if (drag.edgeAfter === drag.edgeBefore) bad.push('拖拽后连线未跟随变形');
    console.log('== 拖拽探针 ==\n  前 ' + JSON.stringify(drag.before) + '\n  后 ' + JSON.stringify(drag.after) +
      '\n  连线 ' + (drag.edgeBefore === drag.edgeAfter ? '未变（红）' : '已跟随变形'));
  }
  await p.screenshot({ path: path.join(OUT, '12-light-dragged.png') });

  /* ---- 交互断言：点空白取消选中 / 双击已挂笔记进笔记（2026-10-12 查漏补缺批新增） ---- */
  await p.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }]);
  await p.goto('file:///' + tmp.replace(/\\/g, '/') + '?shot=canvas#mm-canvas', { waitUntil: 'load' });
  await new Promise(r => setTimeout(r, 700));
  const inter = await p.evaluate(async () => {
    const out = {};
    mmSelect('n1');
    out.selAfterSelect = !!cur.sel;
    const cv = document.getElementById('mmCanvas'), r = cv.getBoundingClientRect();
    const o = (x, y) => ({ pointerId: 9, isPrimary: true, button: 0, buttons: 1, clientX: x, clientY: y, bubbles: true, cancelable: true });
    const bx = r.left + 8, by = r.bottom - 8;
    cv.dispatchEvent(new PointerEvent('pointerdown', o(bx, by)));
    cv.dispatchEvent(new PointerEvent('pointermove', o(bx + 1, by + 1)));
    cv.dispatchEvent(new PointerEvent('pointerup', o(bx + 1, by + 1)));
    await new Promise(r2 => setTimeout(r2, 60));
    out.selAfterBlank = !!cur.sel;
    out.toolbarHidden = document.getElementById('mmToolbar').classList.contains('hide');
    const el = document.querySelector('.mm-node[data-id="n1"]');
    if (el) el.dispatchEvent(new MouseEvent('dblclick', { bubbles: true, cancelable: true }));
    await new Promise(r2 => setTimeout(r2, 60));
    const t = document.getElementById('toast');
    out.dblToast = (t && t.style.display !== 'none') ? t.textContent : '';
    return out;
  });
  if (inter.selAfterBlank) bad.push('点空白未取消选中');
  if (!inter.toolbarHidden) bad.push('取消选中后工具条未收起');
  if (!/进入笔记/.test(inter.dblToast)) bad.push('双击已挂笔记节点未触发进笔记（toast=' + inter.dblToast + '）');
  console.log('== 交互探针 ==\n  选中后点空白取消=' + (!inter.selAfterBlank) + ' 工具条收起=' + inter.toolbarHidden +
    ' 双击进笔记=' + (/进入笔记/.test(inter.dblToast)) + '（' + inter.dblToast + '）');

  /* ---- 交互断言：批2 撤销/重做 ＋ 复制粘贴；批5 任务勾选 ---- */
  await p.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'light' }]);
  await p.goto('file:///' + tmp.replace(/\\/g, '/') + '?shot=canvas#mm-canvas', { waitUntil: 'load' });
  await new Promise(r => setTimeout(r, 700));
  const ops = await p.evaluate(async () => {
    const out = {};
    const before = cur.nodes.length;
    out.before = before;
    mmSelect('r'); mmAddRoot();
    document.getElementById('mmNodeInput').value = '第二棵树';
    mmSaveNode();
    out.afterAdd = cur.nodes.length;
    out.undoEnabled = !document.getElementById('btnUndo').disabled;
    mmUndo();
    out.afterUndo = cur.nodes.length;
    out.redoEnabled = !document.getElementById('btnRedo').disabled;
    mmRedo();
    out.afterRedo = cur.nodes.length;
    const n0 = cur.nodes.length;
    mmSelect('n2'); mmCopyNode();
    mmSelect('n3'); mmPasteNode();
    out.pasted = cur.nodes.length - n0;
    const nd = cur.nodes.filter(x => x.id === 'n1')[0];
    nd.task = true; nd.taskDone = false; renderCanvas();
    mmToggleTask(nd);
    out.taskDone = !!nd.taskDone;
    return out;
  });
  if (ops.afterAdd !== ops.before + 1) bad.push('撤销探针：加根后节点数未 +1（' + ops.before + ' 到 ' + ops.afterAdd + '）');
  if (!ops.undoEnabled) bad.push('撤销探针：加节点后撤销钮仍禁用');
  if (ops.afterUndo !== ops.before) bad.push('撤销探针：撤销后未回到原节点数（' + ops.afterUndo + '）');
  if (!ops.redoEnabled || ops.afterRedo !== ops.before + 1) bad.push('重做探针：重做未恢复（' + ops.afterRedo + '）');
  if (ops.pasted < 2) bad.push('粘贴探针：粘贴未新增子级（+' + ops.pasted + '）');
  if (!ops.taskDone) bad.push('批5 探针：任务勾选未生效');
  console.log('== 批2/批5 探针 ==\n  加根 +1=' + (ops.afterAdd === ops.before + 1) + ' 撤销回退=' + (ops.afterUndo === ops.before) +
    ' 重做恢复=' + (ops.afterRedo === ops.before + 1) + ' 粘贴 +' + ops.pasted + ' 任务勾选=' + ops.taskDone);

  console.log('== 视口/状态回读 ==');
  diag.forEach(d => console.log('  ' + d));
  console.log(errs.length ? 'JS 报错 ' + errs.length + ' 条：\n  ' + errs.join('\n  ') : 'JS 报错 0 条');
  if (bad.length) { console.log('断言红灯 ' + bad.length + ' 条：'); bad.forEach(x => console.log('  x ' + x)); }
  else console.log('矩阵断言全绿（屏态/弹层态/色档/视口/节点数逐张对位）');
  console.log('截图目录：' + OUT);
  await b.close();
  if (errs.length || bad.length) process.exit(1);
})();