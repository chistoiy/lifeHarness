/* V1.64 笔记本地导入／导出为目录／系统打开（open-with）· 原型无头回归（2026-10-10）
 * 家＝prototype/index-bookshelf.html（记录·笔记 tab 与笔记树抽屉）· 规格＝docs/handoff/交棒话术-20261004-笔记本地导入导出与系统打开方式.md §2 N-1~N-4 · 拍板 A~G＝§4
 * 判什么：树顶「系统打开」行与计数同源·历史行三态角标与字段·点行跳笔记·转入清标·清空二次确认+空态虚线·演示进件计数随动·
 *         导入两取法就地切换·目录导入建「本地」角标节点+判重跳过汇总·文件导入当前目录挂标·
 *         导出置灰守卫+挂载节点「导出」角标+只读挂载拦截·零 emoji·PAGE ERRORS 0。
 * 用法：node --experimental-websocket tools/note64check.js（截图：NOTE64_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const PORT = Number(process.env.NOTE64_PORT || 9677);
const SHOTS = process.env.NOTE64_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/note64-shots';
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
async function shot(name) { if (!SHOTS) return; await wait(2300); /* 等弹层上滑动效落定＋toast 自行退场（2.2s），否则样张被半截面板与提示条糊住 */
  fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
function finish() { log('— 结果 ' + pass + ' PASS / ' + fail + ' FAIL · PAGE ERRORS ' + errs.length);
  if (errs.slice(0, 3).forEach) errs.slice(0, 3).forEach(e => log('  ERR ' + e));
  try { ws && ws.close() } catch (e) { } child && child.kill(); process.exit(fail || errs.length ? 1 : 0) }
let child = null;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.note64-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,' + Number(process.env.NOTE64_H || 900), '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
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
  /* 就绪轮询：大页 boot 不定时，boot 未完就开测＝N1~N3 假红（本页曾实踩） */
  let ready = false;
  for (let i = 0; i < 40 && !ready; i++) {
    const r = await ev(`var o={nav:typeof navTab,nt:typeof renderNt,of:(typeof OF==='object'?OF.length:-1)};return o;`);
    ready = !r.__err && r.nav === 'function' && r.nt === 'function' && r.of === 3;
    if (!ready) await wait(400)
  }
  if (!ready) { bad('页面 boot 就绪（navTab/renderNt/OF=3）', JSON.stringify(ready ? '' : await ev('return {nav:typeof navTab,of:typeof OF};'))); return finish() }
  await wait(400);

  /* N1 进笔记 tab 开树抽屉：树顶「系统打开」固定行·临时角标·计数＝OF.length 同源 */
  const n1 = await ev(`navTab('p-records');switchRecord('note');ntOpenDrawer();
    var t=$('#noteTree');var rows=[].slice.call(t.querySelectorAll('.nt-row'));
    var o=rows.filter(function(r){return /系统打开/.test(r.textContent)})[0];
    return {open:t&&!t.classList.contains('hidden'),has:!!o,cnt:o?o.textContent.replace(/[^0-9]/g,''):'',ofLen:OF.length,
      temp:o?/临时/.test(o.textContent):false};`);
  (n1.open && n1.has && n1.temp && n1.cnt === String(n1.ofLen) && n1.ofLen === 3)
    ? ok('N1 树顶「系统打开」行在位 · 临时角标 · 计数与列表同源', '计数 ' + n1.cnt) : bad('N1', JSON.stringify(n1));

  /* N2 历史弹层：三行·三态角标各异·原路径与打开时间在行内 */
  const n2 = await ev(`nohOpen();var s=$('#sheetNoteOpenHist');var rows=[].slice.call(s.querySelectorAll('#nohList > div'));
    var txt=s.innerText;
    var has=function(a){return txt.indexOf(a)>=0};
    return {open:s.classList.contains('sheet-open'),rows:rows.length,
      wr:has('已回写原文件'),app:has('仅应用内'),mv:has('已转正式目录'),
      pth:has('/Download/')&&has('/Documents/'),ts:has('10-08')||has('10-09')||has('10-06'),
      actBtn:s.querySelectorAll('#nohList button').length};`);
  (n2.open && n2.rows === 3 && n2.wr && n2.app && n2.mv && n2.pth && n2.ts && n2.actBtn === 2)
    ? ok('N2 历史三行·三态角标齐·路径与时间在场 · 已转入行不出动作钮', '钮 ' + n2.actBtn) : bad('N2', JSON.stringify(n2));
  await shot('n2-hist');

  /* N3 点行跳归属笔记：弹层收起·回笔记 tab·toast 报打开哪篇（专版无编辑屏，样张按屏内语义） */
  const n3 = await ev(`nohGo(1);return {closed:!$('#sheetNoteOpenHist').classList.contains('sheet-open'),tab:recTab,toast:$('#toast').textContent};`);
  (n3.closed && n3.tab === 'note' && /已打开笔记「灵感速记」/.test(n3.toast))
    ? ok('N3 点历史行收起弹层并跳笔记段', n3.toast.slice(0, 30)) : bad('N3', JSON.stringify(n3));

  /* N4 转入正式目录：状态改·清临时标记语义 toast */
  const n4 = await ev(`ntOpenDrawer();nohOpen();nohMove(0);var t=$('#nohList').innerText;
    return {moved:/已转正式目录/.test(t),toast:$('#toast').textContent,first:/已转/.test($('#nohList > div').innerText)};`);
  (n4.moved && /转入/.test(n4.toast) && /清除临时标记/.test(n4.toast) && n4.first)
    ? ok('N4 转入正式目录 · 行状态即变 · toast 报去向与清标', n4.toast.slice(0, 40)) : bad('N4', JSON.stringify(n4));

  /* N5 清空＝二次确认：第一下只换钮文案；第二下落定 · 空态虚线 · 树行计数随动归零 */
  const n5 = await ev(`var b0=$('#nohClr').textContent;nohClr();var b1=$('#nohClr').textContent;var after1=$('#nohList').children.length;
    nohClr();return {b0:b0,b1:b1,after1:after1,empty:document.querySelectorAll('#nohList > div').length,
      dash:/border-dashed/.test($('#nohList').innerHTML),of:OF.length,
      treeCnt:[].slice.call($('#noteTree').querySelectorAll('.nt-row')).filter(function(r){return /系统打开/.test(r.textContent)})[0].textContent.replace(/[^0-9]/g,''),
      toast:$('#toast').textContent};`);
  (n5.b0 === '清空' && n5.b1 === '确认清空？' && n5.after1 === 3 && n5.empty === 1 && n5.dash && n5.of === 0 && n5.treeCnt === '0' && /已清空/.test(n5.toast))
    ? ok('N5 清空必二次确认 · 空态虚线行 · 树计数随动 · 已转入不受牵连') : bad('N5', JSON.stringify(n5));
  await shot('n5-empty');

  /* N6 演示系统打开：列表插顶·树计数+1·toast 带回写口径 */
  const n6 = await ev(`nohSim();var r0=$('#nohList > div').innerText;
    return {rows:document.querySelectorAll('#nohList > div').length,of:OF.length,
      treeCnt:[].slice.call($('#noteTree').querySelectorAll('.nt-row')).filter(function(x){return /系统打开/.test(x.textContent)})[0].textContent.replace(/[^0-9]/g,''),
      head:/新建笔记1\.md/.test(r0),toast:$('#toast').textContent};`);
  (n6.rows === 1 && n6.of === 1 && n6.treeCnt === '1' && n6.head && /回写原文件/.test(n6.toast))
    ? ok('N6 演示进件插顶 · 计数随动 · toast 声明保存回写', n6.toast.slice(0, 44)) : bad('N6', JSON.stringify(n6));
  await shot('n6-sim');

  /* N7 导入入口与就地两取法：默认目录档·文案随档位换 */
  const n7 = await ev(`closeSheet('sheetNoteOpenHist');niOpen();var d0={seg:$('#niSegDir').textContent,go:$('#niGo').textContent,hint:$('#niHint').textContent};
    niKindChg('file');var d1={go:$('#niGo').textContent,hint:$('#niHint').textContent};
    niKindChg('dir');return {open:$('#sheetNoteImport').classList.contains('sheet-open'),d0:d0,d1:d1,
      tree:/导入本地/.test($('#noteTree').innerText)};`);
  (n7.open && n7.d0.seg === '目录' && n7.d0.go === '选择目录并导入' && /哈希判重/.test(n7.d0.hint) &&
    n7.d1.go === '选择文件并导入' && /多选/.test(n7.d1.hint) && n7.tree)
    ? ok('N7 导入面板就地两取法 · 主钮与说明随档换') : bad('N7', JSON.stringify(n7));
  await shot('n7-import');

  /* N8 目录导入＝还原子层级：根夹＋两个子夹各带「本地」角标 · 笔记按子夹归位 · toast 汇总（计数现算） */
  const n8a = await ev(`niKindChg('dir');niDo();return {prog:$('#niProg').textContent,vis:!$('#niProg').classList.contains('hidden')};`);
  (/扫描/.test(n8a.prog) && n8a.vis) ? ok('N8a 目录导入有可见进度行', n8a.prog) : bad('N8a', JSON.stringify(n8a));
  await wait(800);
  const n8 = await ev(`var rows=[].slice.call($('#noteTree').querySelectorAll('.nt-row'));
    var hit=function(re){return rows.filter(function(r){return re.test(r.textContent)})};
    var root=hit(/外来笔记夹/),meet=hit(/会议记录/),quote=hit(/摘录/);
    var byName=function(n){return D.notes.filter(function(x){return x.folder===n}).length};
    var cnt=D.notes.length;niDo();
    return {root:root.length,rootBadge:!!root[0]&&/本地/.test(root[0].textContent),
      meet:meet.length,meetBadge:!!meet[0]&&/本地/.test(meet[0].textContent),
      quote:quote.length,quoteBadge:!!quote[0]&&/本地/.test(quote[0].textContent),
      dist:byName('外来笔记夹')+byName('会议记录')+byName('摘录'),
      t1:$('#toast').textContent,added:cnt};`);
  await wait(800);
  const n8b = await ev(`var rows=[].slice.call($('#noteTree').querySelectorAll('.nt-row'));
    var c=function(re){return rows.filter(function(r){return re.test(r.textContent)}).length};
    return {t:$('#toast').textContent,root:c(/外来笔记夹/),meet:c(/会议记录/),quote:c(/摘录/),notes:D.notes.length};`);
  (n8.root === 1 && n8.rootBadge && n8.meet === 1 && n8.meetBadge && n8.quote === 1 && n8.quoteBadge &&
    n8.dist === 4 && /已导入 4 条 · 跳过重复 0 条/.test(n8.t1) && n8.added >= 8 &&
    /已导入 0 条 · 跳过重复 4 条/.test(n8b.t) && n8b.root === 1 && n8b.meet === 1 && n8b.quote === 1 && n8b.notes === n8.added)
    ? ok('N8 目录导入还原子层级（三节点各带本地标·归位 4 条） · 二次全判重不堆副本', n8.t1 + ' / ' + n8b.t) : bad('N8', JSON.stringify(n8) + JSON.stringify(n8b));
  await ev(`ntOpenDrawer();ntExpandAll();return {};`);
  await shot('n8-tree-hierarchy');

  /* N9 文件导入：落当前目录（未选→灵感兜底）· 该目录挂本地标 */
  await ev(`niKindChg('file');niDo();return {};`);
  await wait(800);
  const n9b = await ev(`var nd=ntNode('灵感');var row=[].slice.call($('#noteTree').querySelectorAll('.nt-row')).filter(function(r){return /灵感/.test(r.textContent)})[0];
    return {src:nd&&nd.src,toast:$('#toast').textContent,rowBadge:!!row&&/本地/.test(row.textContent)};`);
  (n9b.src === 'local' && n9b.rowBadge && /已导入 2 条/.test(n9b.toast))
    ? ok('N9 文件导入兜底「灵感」并给目录挂本地标', 'src=' + n9b.src) : bad('N9', JSON.stringify(n9b));

  /* N10 导出：未选目录时「当前目录」置灰且点不动；全部笔记档导出→树增「笔记导出」带「导出」角标 */
  const n10 = await ev(`nxOpen();var cur={cls:$('#nxScCur').className,txt:$('#nxScCur').textContent};nxScChg('cur');
    var stay=nxSc;nxScChg('all');var all={cls:$('#nxScAll').className,txt:$('#nxScAll').textContent};
    nxDo();return {open:$('#sheetNoteExport').classList.contains('sheet-open'),cur:cur,stay:stay,all:all,toast0:$('#toast').textContent};`);
  await wait(800);
  const n10b = await ev(`return {node:/笔记导出/.test($('#noteTree').innerText),badge:/导出/.test($('#noteTree').innerText),toast:$('#toast').textContent};`);
  (n10.open && /opacity-40/.test(n10.cur.cls) && /当前目录/.test(n10.cur.txt) && n10.stay === 'all' && n10b.node && /已导出/.test(n10b.toast))
    ? ok('N10 未选目录置灰拒点 · 导出后树增挂载节点并汇总', n10b.toast.slice(0, 40)) : bad('N10', JSON.stringify(n10) + JSON.stringify(n10b));

  /* N11 只读挂载守卫：点「笔记导出」不进当前目录·toast 声明不回写 */
  const n11 = await ev(`var before=noteFolder;ntPick('笔记导出',false);
    var nd=ntNode('笔记导出');return {same:noteFolder===before&&noteFolder!=='笔记导出',src:nd.src,toast:$('#toast').textContent};`);
  (n11.same && n11.src === 'export' && /只读挂载/.test(n11.toast))
    ? ok('N11 导出目录点击被只读挂载拦下', n11.toast.slice(0, 34)) : bad('N11', JSON.stringify(n11));
  await shot('n11-mount');

  /* N13 长按挂载节点＝出「移除挂载」确认弹层：后果三行齐·子夹数与保留条数现算·未确认前节点仍在 */
  const n13 = await ev(`var row=[].slice.call($('#noteTree').querySelectorAll('.nt-row')).filter(function(r){return /外来笔记夹/.test(r.textContent)})[0];
    var bound=/ntLong/.test(row.getAttribute('oncontextmenu')||'');
    var before=D.notes.length;ntLong('外来笔记夹');
    var s=$('#sheetNoteUnmount'),txt=s.innerText,has=function(a){return txt.indexOf(a)>=0};
    var still=[].slice.call($('#noteTree').querySelectorAll('.nt-row')).filter(function(r){return /外来笔记夹/.test(r.textContent)}).length;
    return {bound:bound,open:s.classList.contains('sheet-open'),still:still,
      title:has('移除挂载 · 外来笔记夹'),badge:$('#nuBadge').textContent,path:has('/Download/外来笔记夹'),
      kids:has('子夹 2 个'),keep:has('已导入的 4 条笔记保留在库'),disk:has('手机里的目录与文件不删除'),
      keptNotes:D.notes.length===before};`);
  (n13.bound && n13.open && n13.still === 1 && n13.title && n13.badge === '本地' && n13.kids && n13.keep && n13.disk && n13.path && n13.keptNotes)
    ? ok('N13 长按挂载＝移除确认弹层 · 后果三行现算 · 未确认不动手', n13.title) : bad('N13', JSON.stringify(n13));
  await shot('n13-unmount');

  /* N14 确认移除＝摘挂载节点（连子夹一起摘）· 库内笔记一条不少 · toast 三要素 */
  const n14 = await ev(`nuDo();var rows=[].slice.call($('#noteTree').querySelectorAll('.nt-row'));
    var c=function(re){return rows.filter(function(r){return re.test(r.textContent)}).length};
    var kept=0;['外来笔记夹','会议记录'].forEach(function(n){kept+=D.notes.filter(function(x){return x.folder===n}).length});
    return {root:c(/外来笔记夹/),meet:c(/会议记录/),kept:kept,toast:$('#toast').textContent};`);
  (n14.root === 0 && n14.meet === 0 && n14.kept === 3 && /已移除挂载「外来笔记夹」 · 4 条笔记保留在库 · 原文件不动/.test(n14.toast))
    ? ok('N14 确认移除只摘挂载 · 笔记保留 4 条（含子夹归属）', n14.toast.slice(0, 46)) : bad('N14', JSON.stringify(n14));

  /* N15 非挂载不给移除入口：手建夹长按维持原语义；「系统打开」固定行无长按绑定 */
  const n15 = await ev(`ntLong('方法论');var s=$('#sheetNoteUnmount');
    var o=[].slice.call($('#noteTree').querySelectorAll('.nt-row')).filter(function(r){return /系统打开/.test(r.textContent)})[0];
    return {closed:!s.classList.contains('sheet-open'),toast:$('#toast').textContent,
      sysBound:o?/ntLong/.test(o.getAttribute('oncontextmenu')||''):'no-row'};`);
  (n15.closed && /重命名/.test(n15.toast) && n15.sysBound === false)
    ? ok('N15 手建夹与「系统打开」不出移除入口', n15.toast.slice(0, 26)) : bad('N15', JSON.stringify(n15));

  /* N16 导出挂载节点同族可移除：长按进弹层（角标＝导出）→ 确认后树行消失 */
  const n16 = await ev(`ntLong('笔记导出');var s=$('#sheetNoteUnmount');var op=s.classList.contains('sheet-open');
    var bg=$('#nuBadge').textContent,ttl=$('#nuTitle').textContent;nuDo();
    var gone=[].slice.call($('#noteTree').querySelectorAll('.nt-row')).filter(function(r){return /笔记导出/.test(r.textContent)}).length;
    return {open:op,badge:bg,ttl:ttl,gone:gone,toast:$('#toast').textContent};`);
  (n16.open && n16.badge === '导出' && /笔记导出/.test(n16.ttl) && n16.gone === 0 && /已移除挂载「笔记导出」/.test(n16.toast))
    ? ok('N16 导出挂载节点可移除（只读挂载同族语义）', n16.toast.slice(0, 40)) : bad('N16', JSON.stringify(n16));

  /* N17 移除后重导＝挂载节点重建、笔记不重复（拍板 H 的可逆性自证） */
  const n17 = await ev(`niKindChg('dir');niDo();return {};`);
  await wait(800);
  const n17b = await ev(`var rows=[].slice.call($('#noteTree').querySelectorAll('.nt-row'));
    var c=function(re){return rows.filter(function(r){return re.test(r.textContent)}).length};
    return {root:c(/外来笔记夹/),meet:c(/会议记录/),toast:$('#toast').textContent};`);
  (n17b.root === 1 && n17b.meet === 1 && /已导入 0 条 · 跳过重复 4 条/.test(n17b.toast))
    ? ok('N17 移除后重导＝节点重建 · 笔记仍判重不复制', n17b.toast) : bad('N17', JSON.stringify(n17b));

  /* N12 新增面零 emoji（线性/纯文字口径·禁令同源） */
  const n12 = await ev(`closeSheet('sheetNoteExport');var t=[$('#sheetNoteImport').innerText,$('#sheetNoteExport').innerText,$('#sheetNoteOpenHist').innerText,$('#sheetNoteUnmount').innerText,$('#noteTree').innerText].join('|');
    var EM=[/\\u{1F000}-\\u{1FAFF}/u,/\\u{2600}-\\u{27BF}/u,/\\u{2B00}-\\u{2BFF}/u];
    return {emoji:EM.some(function(r){return r.test(t)}),len:t.length};`);
  !n12.emoji ? ok('N12 新增面零 emoji') : bad('N12', JSON.stringify(n12));

  finish();
})().catch(e => { bad('harness 异常 ' + String(e).slice(0, 120)); finish() });
