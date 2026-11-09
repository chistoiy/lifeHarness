/* 批②b · S3 差异半屏（B-2）＋图片存储清理屏（B-3）＋两处共用全屏预览（U3）· 原型无头回归
 * 判什么：入口行与计数同源·四态分组与吸底合计·仅云端不做假热区·本机图片行可点·预览件位置/页滑/缩放/关闭·
 *         一致组折叠只读·勾选联动体积·冲突与残留标注·清理行人话主文案（裸哈希退到副行）·删除双门槛与三处随动·
 *         空态虚线行·两处共用同一查看件·零 emoji。
 * 用法：node --experimental-websocket tools/b2b3check.js（截图：B23_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index.html')).href;
const PORT = Number(process.env.B23_PORT || 9611);
const SHOTS = process.env.B23_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/b2b3-shots';
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
  await wait(420); // .sheet-panel 入场动画 0.25s：不等就拍会拍到半透明滑入中帧（首轮样张即此坑）
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.b2b3-profile'), '--disable-extensions', '--no-default-browser-check',
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
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* T1 差异入口行在位＋计数＝非一致条数；开弹层即画，四态分组齐、合计与勾选同源 */
  const t1 = await ev(`setPage('p-sub-data');
    var has=new RegExp('差异对比').test(document.getElementById('p-sub-data').innerText);
    var ec=$('#sdEntryCnt').textContent,want=SD_ROWS.filter(function(r){return r.st!=='same'}).length;
    openSheet('sheetSyncDiff');
    var t=$('#sdBody').innerText;
    var c=sdChecked(),bytes=c.reduce(function(a,r){return a+r.s},0);
    return {has:has,ec:ec,want:want,open:$('#sheetSyncDiff').classList.contains('sheet-open'),
      g:[/仅本地/.test(t),/仅云端/.test(t),/已修改/.test(t),/一致/.test(t)],
      sum:$('#sdSum').textContent,wantUp:c.filter(function(r){return r.st!=='remote'}).length,
      wantDn:c.filter(function(r){return r.st==='remote'}).length,wantMb:(bytes/1048576).toFixed(1)};`);
  (t1.has && t1.ec === t1.want + ' 项差异' && t1.open && t1.g.every(Boolean) &&
    new RegExp('上传 ' + t1.wantUp + ' · 下载 ' + t1.wantDn + ' · 共 ' + t1.wantMb + ' MB').test(t1.sum))
    ? ok('T1 差异入口行在位 · 计数＝非一致条数 · 四态分组齐 · 吸底合计与勾选同源', t1.sum) : bad('T1', JSON.stringify(t1));
  await shot('t1-diff');

  /* T2 热区诚实性：本机图片行＝缩略块可点；「仅云端」图片行＝虚线空框且无 ivOpen 热区；非图片行不带块 */
  const t2 = await ev(`var rows=[].slice.call(document.querySelectorAll('#sdBody > div'));
    function find(p){for(var i=0;i<rows.length;i++)if(rows[i].innerText.indexOf(p)>=0)return rows[i];return null}
    var loc=SD_ROWS.filter(function(r){return r.st==='local'&&isImg(r.p)})[0];
    var rem=SD_ROWS.filter(function(r){return r.st==='remote'&&isImg(r.p)})[0];
    var bak=SD_ROWS.filter(function(r){return !isImg(r.p)})[0];
    var L=find(loc.p),R=find(rem.p),B=find(bak.p);
    function tileBg(d){var t=d&&d.querySelector('.ins-img');if(!t)return '';return getComputedStyle(t).backgroundImage||''}
    return {locClicks:!!L&&/ivOpen/.test(L.innerHTML),locTile:!!L&&/ins-img/.test(L.innerHTML),
      locPaint:/linear-gradient/.test(tileBg(L)),
      remDashed:!!R&&/border-dashed/.test(R.innerHTML),remNoHot:!!R&&!/ivOpen/.test(R.innerHTML),
      bakNoTile:!!B&&!/ins-img/.test(B.innerHTML)};`);
  (t2.locClicks && t2.locTile && t2.locPaint && t2.remDashed && t2.remNoHot && t2.bakNoTile)
    ? ok('T2 本机图片行可点且缩略块真上底色（computed 有渐变）· 仅云端＝虚线空框不可点（不做假热区）· 非图片行不带块') : bad('T2', JSON.stringify(t2));

  /* T3 点行即开全屏预览：黑底·位置 1/N·底部给人话名与完整路径＋64 位哈希 */
  const t3 = await ev(`var im=SD_ROWS.filter(function(r){return isImg(r.p)&&sdLocal(r)});
    ivOpen('sd',0);
    return {open:!$('#imgView').classList.contains('hidden'),pos:$('#ivPos').textContent,wantN:im.length,
      name:$('#ivName').textContent,meta:$('#ivMeta').textContent,
      hash:new RegExp(im[0].p.slice(13,29)).test($('#ivMeta').textContent),
      grad:($('#ivImg').getAttribute('style')||'').indexOf('linear-gradient')>=0};`);
  (t3.open && t3.pos === '1 / ' + t3.wantN && /本机图片/.test(t3.name) && /\.jpg$|\.png$/.test(t3.meta) && t3.hash && t3.grad)
    ? ok('T3 预览打开：位置计数·人话名·底部含完整路径与哈希·图块有渐变底', t3.pos + ' · ' + t3.meta.slice(0, 40)) : bad('T3', JSON.stringify(t3));
  await shot('t3-viewer');

  /* T4 页滑与缩放：滑张后回到原尺寸·末张禁用「下一张」·点图 1×⇄2× 互切·点空白关闭 */
  const t4 = await ev(`var n=ivList.length;
    ivNav(1);var p1=$('#ivPos').textContent;
    ivZoom(1);var z1=$('#ivImg').style.transform;
    for(var k=0;k<30&&!$('#ivNext').disabled;k++)ivNav(1);
    var last=$('#ivPos').textContent,nd=$('#ivNext').disabled,zAfterNav=$('#ivImg').style.transform;
    $('#ivImg').click();var zUp=$('#ivImg').style.transform;
    $('#ivImg').click();var zDown=$('#ivImg').style.transform;
    document.querySelector('#imgView > div:nth-child(2)').click();
    return {p1:p1,want2:'2 / '+n,z1:z1,zAfterNav:zAfterNav,last:last,wantLast:n+' / '+n,nd:nd,zUp:zUp,zDown:zDown,closed:$('#imgView').classList.contains('hidden')};`);
  (t4.p1 === t4.want2 && /scale\(2\)/.test(t4.z1) && /scale\(1\)/.test(t4.zAfterNav) && t4.last === t4.wantLast &&
    t4.nd === true && /scale\(2\)/.test(t4.zUp) && /scale\(1\)/.test(t4.zDown) && t4.closed)
    ? ok('T4 页滑逐张到末张禁用「下一张」· 换张回到 1×·点图 1×⇄2×·点空白关闭', t4.p1 + ' → ' + t4.last) : bad('T4', JSON.stringify(t4));

  /* T5 一致组：默认折叠＝0 行，展开后行数＝一致条数且无勾选框（只读） */
  const t5 = await ev(`var before=document.querySelectorAll('#sdBody > div').length;
    sdSameOpen=true;sdRender();
    var after=document.querySelectorAll('#sdBody > div').length;
    var sameRows=[].slice.call(document.querySelectorAll('#sdBody > div')).filter(function(d){return /一致$/.test(d.innerText.trim())});
    return {d:after-before,n:sameRows.length,want:sdGroup('same').length,
      noChk:sameRows.every(function(d){return !/type="checkbox"/.test(d.outerHTML)})};`);
  (t5.d === t5.want && t5.n === t5.want && t5.noChk)
    ? ok('T5 一致组默认折叠 · 展开补齐 N 行 · 只读无勾选框', '+' + t5.d + ' 行') : bad('T5', JSON.stringify(t5));

  /* T6 取消一条勾选 → 合计条数与体积同时随动（期望值由页面现值算出，不写死） */
  const t6 = await ev(`sdSameOpen=false;sdRender();
    var c=sdChecked(),b0=c.reduce(function(a,r){return a+r.s},0);
    var want0='上传 '+c.filter(function(r){return r.st!=='remote'}).length+' · 下载 '+c.filter(function(r){return r.st==='remote'}).length+' · 共 '+(b0/1048576).toFixed(1)+' MB';
    var before=$('#sdSum').textContent;
    sdToggle(c[0].p,false);
    var c2=sdChecked(),b1=c2.reduce(function(a,r){return a+r.s},0);
    var want2='上传 '+c2.filter(function(r){return r.st!=='remote'}).length+' · 下载 '+c2.filter(function(r){return r.st==='remote'}).length+' · 共 '+(b1/1048576).toFixed(1)+' MB';
    return {before:before,want0:want0,after:$('#sdSum').textContent,want2:want2,less:b1<b0,one:c[0].st!=='remote'};`);
  (t6.before === t6.want0 && t6.after === t6.want2 && t6.less)
    ? ok('T6 取消勾选后条数与体积同时随动（合计由逐行现算）', t6.before + ' → ' + t6.after) : bad('T6', JSON.stringify(t6));

  /* T7 冲突行标注「本机 X / 云端 Y · 本机为准」；残留角标只在该行；仅云端每行带「下载」 */
  const t7 = await ev(`var rows=[].slice.call(document.querySelectorAll('#sdBody > div'));
    function row(p){for(var i=0;i<rows.length;i++)if(rows[i].innerText.indexOf(p)>=0)return rows[i];return null}
    var mod=SD_ROWS.filter(function(r){return r.st==='mod'})[0],mr=row(mod.p);
    var st=SD_ROWS.filter(function(r){return r.stale})[0],sr=row(st.p);
    var mt=mr?mr.innerText.replace(/\\n/g,' '):'';
    var sst=sr?sr.innerText.replace(/\\n/g,' '):'';
    return {conflict:/两端内容不同/.test(mt)&&/冲突本机为准/.test(mt),
      both:mt.indexOf('本机 ')>=0&&mt.indexOf(' / 云端 ')>=0,
      staleOnlyOnStale:mt.indexOf('残留')<0&&sst.indexOf('残留')>=0,
      remoteAllDl:sdGroup('remote').every(function(r){var x=row(r.p);return !!x&&x.innerText.indexOf('下载')>=0})};`);
  (t7.conflict && t7.both && t7.staleOnlyOnStale && t7.remoteAllDl)
    ? ok('T7 冲突行给人话比对（本机／云端·本机为准）· 残留角标只在该行 · 仅云端每行带「下载」') : bad('T7', JSON.stringify(t7));
  await shot('t7-marks');

  /* T8 清理屏：我的页入口行与计数·屏头「未引用 N / 共 M · 体积」与逐行同源·主行人话（不含 64 位裸哈希） */
  const t8 = await ev(`setPage('p-profile');
    var entry=/图片存储清理/.test(document.getElementById('p-profile').innerText);
    var pf=$('#pfMcCnt').textContent,want=MC_FILES.length+' 个';
    navTo('p-sub-mediaclean');
    var b=new RegExp('未引用 '+MC_FILES.length+' / 共 '+MC_TOTAL+' · ').test($('#mcSum').textContent);
    var rows=[].slice.call(document.querySelectorAll('#mcList > div'));
    var main=rows.map(function(d){return d.children[2].innerText.split('\\n')[0]});
    var sub=rows.map(function(d){return d.children[2].innerText.split('\\n')[1]||''});
    var bytes=MC_FILES.reduce(function(a,f){return a+f.s},0);
    return {entry:entry,pf:pf,want:want,title:$('#pageTitle').textContent,rows:rows.length,wantRows:MC_FILES.length,head:b,
      human:main.every(function(t){return /笔记插图|书籍封面/.test(t)&&!/[0-9a-f]{20,}/.test(t)}),
      time:main.every(function(t){return /\\d\\d-\\d\\d \\d\\d:\\d\\d/.test(t)}),
      subHasSize:sub.every(function(t){return /KB|MB/.test(t)&&/编号 [0-9a-f]{8}/.test(t)}),
      mb:(bytes/1048576).toFixed(1),sumText:$('#mcSum').textContent,
      paint:/linear-gradient/.test(getComputedStyle(document.querySelector('#mcList .ins-img')).backgroundImage)};`);
  (t8.entry && t8.pf === t8.want && t8.title === '图片存储清理' && t8.head && t8.rows === t8.wantRows && t8.paint &&
    t8.human && t8.time && t8.subHasSize && t8.sumText.indexOf(t8.mb + ' MB') >= 0)
    ? ok('T8 清理屏入口与计数同源 · 屏头由逐行现算 · 主行＝目录人话＋落盘时间，裸哈希退到副行「编号 8 位」', t8.sumText) : bad('T8', JSON.stringify(t8));
  await shot('t8-mediaclean');

  /* T9 勾选→清理确认→删除三处随动，全删后空态虚线行（期望值由当时行数与体积现算） */
  const t9 = await ev(`var n0=MC_FILES.length;
    mcToggle(MC_FILES[0].h,true);mcToggle(MC_FILES[1].h,true);
    var lbl=$('#mcDelBtn').textContent;mcAskDel();
    var asked=$('#sheetMcDel').classList.contains('sheet-open'),sum=$('#mcDelSum').textContent;
    var del=MC_FILES.filter(function(f){return mcOn.has(f.h)}).reduce(function(a,f){return a+f.s},0);
    mcDelGo();var rowsAfter=MC_FILES.length,domRows=document.querySelectorAll('#mcList > div').length;
    for(var i=0;i<MC_FILES.length;i++)mcToggle(MC_FILES[i].h,true);
    var allLbl=$('#mcDelBtn').textContent;mcAskDel();mcDelGo();
    return {lbl:lbl,asked:asked,sum:sum,wantMb:(del/1048576).toFixed(1),
      rowsAfter:rowsAfter,wantAfter:n0-2,domRows:domRows,allLbl:allLbl,
      empty:$('#mcList').innerText.trim(),dash:/border-dashed/.test($('#mcList').innerHTML),
      sumText:$('#mcSum').textContent,dis:$('#mcDelBtn').disabled,pf:$('#pfMcCnt').textContent};`);
  (t9.lbl === '清理选中（2）' && t9.asked && /将删除 2 个文件 · /.test(t9.sum) && /，不可恢复/.test(t9.sum) &&
    t9.sum.indexOf(t9.wantMb + ' MB') >= 0 && t9.rowsAfter === t9.wantAfter && t9.domRows === t9.wantAfter &&
    /清理选中（4）/.test(t9.allLbl) && t9.empty === '无未引用图片' && t9.dash &&
    t9.sumText === '无未引用图片' && t9.dis === true && t9.pf === '0 个')
    ? ok('T9 清理双门槛（勾选→确认列出 N·体积·不可恢复）· 删后行数/屏头/入口随动 · 空态虚线行·钮禁用') : bad('T9', JSON.stringify(t9));
  await shot('t9-after-clean');

  /* T10 两处共用同一查看件（全页只有一个预览容器·笔记旧件未被我改写）·新增两块零 emoji */
  const t10 = await ev(`var EM=[/\\u{1F000}-\\u{1FAFF}/u,/\\u{2600}-\\u{27BF}/u,/\\u{2B00}-\\u{2BFF}/u];
    var sd=$('#sheetSyncDiff').innerText,mc=document.getElementById('p-sub-mediaclean').innerText;
    return {viewers:document.querySelectorAll('#imgView').length,
      sdEmoji:EM.some(function(r){return r.test(sd)}),mcEmoji:EM.some(function(r){return r.test(mc)}),
      oldLight:!!document.getElementById('imgLight')};`);
  (t10.viewers === 1 && !t10.sdEmoji && !t10.mcEmoji && t10.oldLight)
    ? ok('T10 全屏预览＝单一共享件（两处共用）· 新屏与新半屏零 emoji') : bad('T10', JSON.stringify(t10));

  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail = 1 }
  else log('PAGE ERRORS 0');
  try { if (ws) ws.close() } catch (e) { }
  process.exit(fail ? 1 : 0) }
