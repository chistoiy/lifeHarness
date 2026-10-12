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
    { q: 'shot=empty', hash: 'mm-list', dark: 0, name: '11-light-empty' }
  ];

  const diag = [];
  const wantPage = { list: 'mm-list', canvas: 'mm-canvas', bind: 'mm-canvas', nodemenu: 'mm-canvas', frommd: 'mm-list', frominbox: 'mm-list', empty: 'mm-list' };
  const wantSheet = { bind: 'sheetMm-bindNote', frommd: 'sheetMm-fromMd', frominbox: 'sheetMm-fromInbox' };
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
      title: (document.getElementById('pageTitle') || {}).textContent
    }));
    /* 断言：屏态/弹层态/色档必须与本张矩阵项一致，否则这张图不算数（防假绿） */
    const key = (s.q.match(/shot=([a-z]+)/) || [])[1];
    if (d.vw !== 390) bad.push(s.name + ' 视口非 390（' + d.vw + '）');
    if (d.page !== wantPage[key]) bad.push(s.name + ' 屏态错：期望 ' + wantPage[key] + ' 实得 ' + d.page);
    if (!!d.dark !== !!s.dark) bad.push(s.name + ' 色档错：期望 dark=' + !!s.dark + ' 实得 ' + d.dark);
    if (wantSheet[key] && d.sheets.indexOf(wantSheet[key]) < 0) bad.push(s.name + ' 弹层未开：' + (d.sheets || '无'));
    if (key === 'nodemenu' && !d.menu) bad.push(s.name + ' 节点操作单未开');
    if ((key === 'canvas' || key === 'bind' || key === 'nodemenu') && d.nodes < 10) bad.push(s.name + ' 画布节点数异常少：' + d.nodes);
    diag.push(s.name + '  vw=' + d.vw + ' page=' + d.page + ' dark=' + d.dark +
      ' nodes=' + d.nodes + ' sel=' + (d.sel || '-') + ' sheet=[' + d.sheets + '] menu=' + d.menu +
      ' scale=' + d.scale + ' title=' + d.title);
  }

  console.log('== 视口/状态回读 ==');
  diag.forEach(d => console.log('  ' + d));
  console.log(errs.length ? 'JS 报错 ' + errs.length + ' 条：\n  ' + errs.join('\n  ') : 'JS 报错 0 条');
  if (bad.length) { console.log('断言红灯 ' + bad.length + ' 条：'); bad.forEach(x => console.log('  x ' + x)); }
  else console.log('矩阵断言全绿（屏态/弹层态/色档/视口/节点数逐张对位）');
  console.log('截图目录：' + OUT);
  await b.close();
  if (errs.length || bad.length) process.exit(1);
})();