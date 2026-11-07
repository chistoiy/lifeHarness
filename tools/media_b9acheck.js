/* media_b9acheck.js · 影音游批9a 原型先行的无头回归（m-import 重建：五档×13 家矩阵 · 粘贴三 id 识别 · 五步向导 · 歌单四源两弹层）
 * 口径依据＝docs/handoff/交棒话术-20261009-影音游批9导入矩阵与导出尾项.md §1＋计划 §六 导入与去重规范
 * 标记类：[data-mit] · [data-mi-ch] · [data-mi-fmt] · [data-mi-c8] · #miClipHit[data-miclip] · #miSteam ·
 *   [data-mistep] · .mi-row[data-mij] · [data-misum] · #miRes[data-mires] · #miUndoRow · [data-mipl-src] · [data-mipl-mode] · #miplRes[data-miplres]
 * 期望值一律页内独立算子现算（按 MI_SMP 对账 MDEMO/MPLISTS 重算三计数，不复用渲染函数）。
 * 用法：node --experimental-websocket tools/media_b9acheck.js            （截图：MB9A_SHOTS=1，落仓库外 tempWork）
 *       node --experimental-websocket tools/media_b9acheck.js --mut 1|2|3 （变异刀：①对账行摘「重复跳过」②撤销不接结果态③粘贴识别摘 tt 前缀） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-media.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.MB9A_PORT || 9638);
const SHOTS = process.env.MB9A_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/media-b9a-shots';
const MUT = process.argv.indexOf('--mut');
const mut = MUT >= 0 ? Number(process.argv[MUT + 1]) : 0;
const ORIG = fs.readFileSync(FILE, 'utf8');
let chrome, pass = 0, fail = 0; const errs = [];
const log = m => { console.log(m) };
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
async function shot(name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTDIR, { recursive: true });
  await wait(420);
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64'));
}
/* 独立算子：与页内渲染同数据不同代码——三计数由 MI_SMP 对账 MDEMO 现算 */
const RAW = `function miqNorm(s){return String(s).toLowerCase().replace(/[\\s《》·:：'"‘’“”\\-—、,.!？?]/g,'')}
  function miqCnt(ch){var rows=(MI_SMP[ch]||[]);var a=0,u=0,d=0;rows.forEach(function(r){var h=MDEMO.find(function(x){return miqNorm(x.title)===miqNorm(r.t)});
    if(!h)a++;else if(h.year===r.y)d++;else u++});return {a:a,u:u,d:d,n:rows.length}}
  function miqPlCnt(src){var p=MIPL_SMP[src];var a=0,d=0,n=0;p.forEach(function(x){if(MPLISTS.some(function(m){return m.name===x.t}))d++;else{a++;n+=x.n}});return {a:a,d:d,tracks:n}}`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish(); }
  if (mut) {
    const inject = (n, a, b) => {
      if (ORIG.split(a).length - 1 !== 1) { bad('MUT' + n + ' 就地锚点命中数<>1（刀没处下＝红灯）'); return finish(); }
      fs.writeFileSync(FILE, ORIG.replace(a, b), 'utf8');
    };
    if (mut === 1) inject(1, "· 重复跳过 '+s.d", "· 跳过 '+s.d");
    if (mut === 2) inject(2, 'MI.undone=true;miRender()}', 'miRender()}');
    if (mut === 3) inject(3, 'match(/tt\\d{7,8}/)', 'match(/\\d{7,8}/)');
    log('MUT=' + mut + ' 已就地注入（跑完按 ORIG 逐字节复原）');
  }
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.media9a-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260));
  });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF });
  /* 内联脚本排在 Tailwind CDN 之后：轮询到本批全局在场再用，勿改固定 sleep（批7 实锤坑） */
  for (let i = 0; i < 30; i++) {
    const r = await ev(`return (typeof mRenderImport==='function')&&(typeof miOpen==='function')&&(typeof miUndo==='function')&&(typeof miClipCheck==='function')&&(typeof miplRender==='function')&&(typeof MI_SMP!=='undefined')`);
    if (r === true) break;
    await wait(700);
  }

  /* A1 矩阵＝取法五档组头齐（4 组渠道行＋剪贴板粘贴框）· 13 家按档落位（授权3/配对2/API5/文件3） */
  const a1 = await ev(`navTo('m-import');
    var tiers=[].map.call(document.querySelectorAll('#mImportBody .mi-tier'),function(t){return t.getAttribute('data-mit')}).join(',');
    var byT=function(t){return [].slice.call(document.querySelectorAll('#mImportBody [data-mi-ch]')).filter(function(r){return MI_CH.find(function(c){return c.n===r.getAttribute('data-mi-ch')}).t===t}).length};
    return {tiers:tiers,n:document.querySelectorAll('#mImportBody [data-mi-ch]').length,auth:byT('auth'),pair:byT('pair'),api:byT('api'),file:byT('file'),c8:document.querySelectorAll('[data-mi-c8]').length};`);
  (a1.tiers === 'auth,pair,api,file,clip' && a1.n === 13 && a1.auth === 3 && a1.pair === 2 && a1.api === 5 && a1.file === 3 && a1.c8 === 8)
    ? ok('A1 五档组头齐·13 家按档 3/2/5/3·剪贴板八家模板') : bad('A1', JSON.stringify(a1));
  await shot('mb9a-01-matrix');

  /* A2 每行＝渠道名+取法徽标≥1+格式说明一句非空（13/13） */
  const a2 = await ev(`var rows=[].slice.call(document.querySelectorAll('#mImportBody [data-mi-ch]'));
    var noFmt=rows.filter(function(r){var f=r.querySelector('[data-mi-fmt]');return !f||f.textContent.trim().length<4}).length;
    var noBdg=rows.filter(function(r){return r.querySelectorAll('.mi-bdg').length<1}).length;
    return {rows:rows.length,noFmt:noFmt,noBdg:noBdg};`);
  (a2.rows === 13 && a2.noFmt === 0 && a2.noBdg === 0) ? ok('A2 十三行徽标+格式句全在场') : bad('A2', JSON.stringify(a2));

  /* A3 点渠道行＝开向导·步条五枚·落给料步·文件档出选文件钮（豆瓣） */
  const a3 = await ev(RAW + `miOpen('豆瓣');
    var dots=[].map.call(document.querySelectorAll('[data-mistep]'),function(d){return d.getAttribute('data-mistep')}).join(',');
    var on=document.querySelector('.mi-dot.on').getAttribute('data-mistep');
    return {open:!document.getElementById('sheet-m-import').classList.contains('hidden'),dots:dots,on:on,
      file:!!document.getElementById('miFileIn'),btns:!!document.querySelector('#miBody button')};`);
  (a3.open && a3.dots === '1,2,3,4,5' && a3.on === '2' && a3.file && a3.btns) ? ok('A3 点行开向导·五步点条·给料=选文件') : bad('A3', JSON.stringify(a3));

  /* A4 给料形态随取法分派：授权=拉取钮 / API=输入框 / 配对=检测钮 */
  const a4 = await ev(`miOpen('Steam');var auth=!!document.querySelector('#miBody .mds-chip.on');
    miOpen('IMDb');var api=!!document.getElementById('miGivenIn');
    miOpen('网易云音乐');var pairTxt=document.getElementById('miBody').textContent.indexOf('配对')>=0;
    return {auth:auth,api:api,pair:pairTxt};`);
  (a4.auth && a4.api && a4.pair) ? ok('A4 给料按授权/API/配对三形态分派') : bad('A4', JSON.stringify(a4));

  /* A5 解析预览＝逐行带外部 id·对账行三计数与独立算子现算全等（变异刀①靶） */
  const a5 = await ev(RAW + `miOpen('豆瓣');miFetch();
    var want=miqCnt('豆瓣');
    var sum=document.getElementById('miSum').getAttribute('data-misum');
    var txt=document.getElementById('miSum').textContent;
    var extN=[].slice.call(document.querySelectorAll('#miRows .mi-row')).filter(function(r){return /d:|tt|app|tm:|tv:|mb:|ig:|sp:|ne:|bl:|rym:|dgs:/.test(r.textContent)}).length;
    var rowN=document.querySelectorAll('#miRows .mi-row').length;
    return {sum:sum,want:want.a+','+want.u+','+want.d,txt:txt,a:want.a,d:want.d,extN:extN,rowN:rowN,n:want.n};`);
  (a5.sum === a5.want && a5.rowN === a5.n && a5.extN === a5.n && txt_has(a5, '重复跳过'))
    ? ok('A5 预览 ' + a5.rowN + ' 行全带外部 id·对账＝新建' + a5.want.split(',')[0] + '/更新' + a5.want.split(',')[1] + '/跳过' + a5.want.split(',')[2]) : bad('A5', JSON.stringify(a5));
  if (mut === 1) log('MUT1 期望＝本条独红');
  function txt_has(o, s) { return o.txt.indexOf(s + ' ' + o.d) >= 0 }

  /* A6 判定三态齐现：豆瓣样例行对上 MDEMO 的 skip / 年份差 upd / 未见 add */
  const a6 = await ev(`var js=[].map.call(document.querySelectorAll('#miRows .mi-row'),function(r){return r.getAttribute('data-mij')});
    var uniq={};js.forEach(function(j){uniq[j]=(uniq[j]||0)+1});
    var upd=document.querySelector('#miRows .mi-row[data-mij="upd"]').textContent;
    return {uniq:uniq,upd:upd};`);
  (a6.uniq.add >= 1 && a6.uniq.upd >= 1 && a6.uniq.dup >= 1 && /将更新/.test(a6.upd)) ? ok('A6 三态判定齐（add/upd/dup 各≥1·更新行标将更新）') : bad('A6', JSON.stringify(a6));

  /* A7 确认导入＝真写库：MDEMO 增数=新建数·年份更新落值·结果三计数=预览 */
  const a7 = await ev(RAW + `var n0=MDEMO.length;var want=miqCnt('豆瓣');
    miGo(1);miApply();
    var d0=MDEMO.find(function(x){return x.title==='奥本海默'});
    var resTxt=document.getElementById('miRes').textContent;
    return {n0:n0,dn:MDEMO.length-n0,a:want.a,u:want.u,d:want.d,year:d0&&d0.year,res:resTxt};`);
  (a7.dn === a7.a && a7.year === 2024 && a7.res.indexOf('新增 ' + a7.a) >= 0 && a7.res.indexOf('更新 ' + a7.u) >= 0 && a7.res.indexOf('跳过 ' + a7.d) >= 0)
    ? ok('A7 落库＝新增' + a7.a + '·奥本海默年份改 2024·结果三计数对账') : bad('A7', JSON.stringify(a7));
  await shot('mb9a-02-result');

  /* A8 撤销本批＝真动作：行数与年份逐字回原（与 A7 前基线比对）·结果态翻「已撤销」（变异刀②靶） */
  const a8 = await ev(`document.getElementById('miUndoRow').click();
    var res=document.getElementById('miRes').textContent;
    return {undone:MI.undone,len:MDEMO.length,year:MDEMO.filter(function(x){return x.title==='奥本海默'})[0].year,res:res};`);
  (a8.undone === true && a8.len === a7.n0 && a8.year === 2023 && /已撤销/.test(a8.res))
    ? ok('A8 撤销＝行数回基线 ' + a8.len + '·年份回 2023·结果态翻面') : bad('A8', JSON.stringify(a8));
  if (mut === 2) log('MUT2 期望＝本条独红');
  await ev(`miClose();return 1`);

  /* A9 粘贴识别三 id＋裸数字不误判（变异刀③靶） */
  const a9 = await ev(`var out=[];
    function chk(v){miClipCheck(v);var h=document.querySelector('[data-miclip]');return h?h.getAttribute('data-miclip'):''}
    out.push(chk('tt0111166'));
    out.push(chk('https://movie.douban.com/subject/26264956/'));
    out.push(chk('https://store.steampowered.com/app/2358720/'));
    out.push(chk('26264956'));
    miClipCheck('');
    return {out:out.join(',')};`);
  (a9.out === 'IMDb,豆瓣,Steam,') ? ok('A9 三 id 各归其源·裸数字不误识别') : bad('A9', JSON.stringify(a9));
  if (mut === 3) log('MUT3 期望＝本条独红');

  /* A10 命中两动作：去录入开录入弹层；去导入开向导且给料=只读原文 */
  const a10 = await ev(`miClipCheck('tt0111166');miClipEnter();
    var addOpen=!document.getElementById('m-sheet-add').classList.contains('hidden');closeSheet('m-sheet-add');
    miClipImport();
    var ta=document.getElementById('miGivenIn');
    var clip=ta&&ta.hasAttribute('readonly')&&ta.value.indexOf('tt0111166')>=0;
    miClose();miClipCheck('');
    return {addOpen:addOpen,clip:clip};`);
  (a10.addOpen && a10.clip) ? ok('A10 去录入/去导入两动作真接线·粘贴给料带原文') : bad('A10', JSON.stringify(a10));

  /* A11 Steam 库扫描＝占位灰钮（pointer-events:none·无 onclick） */
  const a11 = await ev(`var b=document.getElementById('miSteam');
    return {pe:getComputedStyle(b).pointerEvents,oc:b.getAttribute('onclick'),txt:b.textContent};`);
  (a11.pe === 'none' && !a11.oc) ? ok('A11 扫描 Steam 库灰态点不动零说明') : bad('A11', JSON.stringify(a11));

  /* A12 歌单弹层＝四源 chips＋文件/粘贴两法·默认网易云+文件 */
  const a12 = await ev(`mImportPlaylist();
    var srcs=[].map.call(document.querySelectorAll('[data-mipl-src]'),function(s){return s.getAttribute('data-mipl-src')}).join(',');
    var modes=[].map.call(document.querySelectorAll('[data-mipl-mode]'),function(s){return s.getAttribute('data-mipl-mode')}).join(',');
    var fileBtn=!!document.getElementById('miplFileIn');
    return {open:!document.getElementById('sheet-m-playlist').classList.contains('hidden'),srcs:srcs,modes:modes,file:fileBtn};`);
  (a12.open && a12.srcs === '网易云,Spotify,QQ音乐,Apple Music' && a12.modes === 'file,clip' && a12.file)
    ? ok('A12 歌单面＝四源×两法·文件档出选件钮') : bad('A12', JSON.stringify(a12));

  /* A13 歌单解析＝复用五步③行式（.mi-row[data-mij]＋data-misum 同算子）·通勤循环标已存在 */
  const a13 = await ev(RAW + `miplParse();
    var want=miqPlCnt('网易云');
    var sum=document.getElementById('miplSum').getAttribute('data-misum');
    var rows=[].slice.call(document.querySelectorAll('#miplRows .mi-row'));
    var dupRow=rows.filter(function(r){return r.getAttribute('data-mij')==='dup'})[0];
    return {rows:rows.length,sum:sum,want:want.a+',0,'+want.d,dup:dupRow?dupRow.textContent:''};`);
  (a13.sum === a13.want && /通勤循环/.test(a13.dup) && /已存在/.test(a13.dup))
    ? ok('A13 歌单预览复用同对账行·已存在单标跳过') : bad('A13', JSON.stringify(a13));

  /* A14 歌单确认＝MPLISTS 真增单·结果读数现算·完成后架面音乐轨同步·演示数据复原零残留 */
  const a14 = await ev(RAW + `var n0=MPLISTS.length;
    miplApply();
    var added=MPLISTS[MPLISTS.length-1];
    var res=document.getElementById('miplRes').textContent;
    miplClose();
    var track=document.getElementById('mShelfBody')?document.querySelector('.mds-pl'):null;
    var i=MPLISTS.findIndex(function(p){return p.name==='夜航西飞'});if(i>=0)MPLISTS.splice(i,1);
    return {len:MPLISTS.length-n0,added:added.name+'/'+added.n+'/'+added.src,res:res,track:!!track};`);
  (a14.len === 0 && a14.added === '夜航西飞/28/网易云' && /新增 1 单 · 28 首/.test(a14.res))
    ? ok('A14 歌单落 MPLISTS＝夜航西飞 28 首·结果现算·复原无残留') : bad('A14', JSON.stringify(a14));
  await shot('mb9a-03-playlist');

  /* A15 本批 JS 段与三面 DOM 段：零「演示」零 emoji 零随机 零占位自注 */
  const a15 = await ev(`var fns=[mRenderImport,miOpen,miClose,miGo,miFetch,miRender,miApply,miUndo,miClipCheck,miClipEnter,miClipImport,miRowsHTML,miNew,miCompute,miCount,miJudge,miDup,miNorm,miOf,miplOpen,miplClose,miplPick,miplMode,miplRows,miplParse,miplApply,miplRender,mImportPlaylist];
    var src=fns.map(String).join('')+JSON.stringify(MI_CH)+JSON.stringify(MI_SMP)+JSON.stringify(MIPL_SMP)+JSON.stringify(MI_TIER);
    var dom=document.getElementById('m-import').outerHTML+document.getElementById('sheet-m-import').outerHTML+document.getElementById('sheet-m-playlist').outerHTML;
    var re=[/[\\u{1F300}-\\u{1FAFF}]/u,/[\\u{2600}-\\u{27BF}]/u,/[\\u{2B00}-\\u{2B5F}]/u,/\\u{FE0F}/u];
    return {demo:(src.match(/演示/g)||[]).length,rand:(src.match(/Math\\.random/g)||[]).length,ph:/待实现|待批|占位/.test(src),
      emoji:re.filter(function(r){return r.test(dom)||r.test(src)}).length};`);
  (a15.demo === 0 && a15.rand === 0 && !a15.ph && a15.emoji === 0) ? ok('A15 批9a 全段：零演示/零随机/零占位自注/零 emoji') : bad('A15', JSON.stringify(a15));

  /* A16 同态重渲染逐字节等（矩阵与向导预览皆确定性） */
  const a16 = await ev(`navTo('m-import');mRenderImport();var a=document.getElementById('mImportBody').innerHTML;mRenderImport();
    miOpen('豆瓣');miFetch();var p=document.getElementById('miBody').innerHTML;miFetch();
    var q=p===document.getElementById('miBody').innerHTML;miClose();
    return {m:a===document.getElementById('mImportBody').innerHTML,w:q};`);
  (a16.m && a16.w) ? ok('A16 矩阵与预览同态重渲染逐字节等') : bad('A16', JSON.stringify(a16));

  log('PAGE ERRORS ' + errs.length + (errs.length ? ' :: ' + errs.join(' || ') : ''));
  finish();
})().catch(e => { bad('runner', String((e && e.message) || e)); if (errs.length) log('PAGE ERRORS ' + errs.length + ' :: ' + errs.join(' || ')); finish(); });

function finish() {
  try { ws && ws.close() } catch (e) { }
  try { chrome && chrome.kill() } catch (e) { }
  if (mut) {
    fs.writeFileSync(FILE, ORIG, 'utf8');
    const a = require('crypto').createHash('md5').update(fs.readFileSync(FILE)).digest('hex');
    const b = require('crypto').createHash('md5').update(Buffer.from(ORIG, 'utf8')).digest('hex');
    log('MUT 复原 md5 ' + a + (a === b ? ' == 基线全等' : ' != 基线 ' + b + '（红灯）'));
  }
  log('RESULT ' + pass + '/' + (pass + fail) + ' 绿 · fail=' + fail + ' · PAGE ERRORS ' + errs.length);
  process.exit(fail || errs.length ? 1 : 0);
}
