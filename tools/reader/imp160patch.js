/* V1.60 导入流程改造批 · 原型补丁 · prototype/index-bookshelf.html
 * 规格 = docs/handoff/交棒话术-20261002-下一版实现批-F01-批C-R32精修.md §3G 拍板
 * 护栏：快照 tmp/snap-imp160/ · 每条锚点命中必须=1 · 体积区间校验 · 锚点跟随目标文件行尾(CRLF)
 * 用法：node tools/reader/imp160patch.js
 */
const fs = require('fs');
const P = 'prototype/index-bookshelf.html';
const SNAP = 'tmp/snap-imp160/index-bookshelf.before.html';

const src = fs.readFileSync(P, 'utf8');
if (!fs.existsSync(SNAP)) { console.error('ABORT: 快照不存在，先拍快照'); process.exit(1); }
const snap = fs.readFileSync(SNAP, 'utf8');
if (snap !== src) { console.error('ABORT: 当前文件与快照不一致（可能已被其他改动），先重新快照'); process.exit(1); }
const EOL = src.includes('\r\n') ? '\r\n' : '\n';

let s = src;
const edits = [];
function rep(name, oldStr, newStr) { edits.push({ name, oldStr, newStr }); }

/* 1 · BR_TASKS 五→四（摘掉分页预计算） */
rep('BR_TASKS四条', `'封面与元数据抽取','分页预计算'];`, `'封面与元数据抽取'];`);
/* 2 · 大文件 warn 文案 */
rep('大文件warn', `warn:'大文件：解析与分页预计算可能需要 1-2 分钟'`, `warn:'大文件：解析与目录构建可能需要 1-2 分钟'`);
/* 3 · 核对步底注 */
rep('核对步底注', `源文件保留原位 · 书架登记解析结果与分页缓存`, `源文件保留原位 · 加入书架后整本分页后台续算`);
/* 4 · 保存钮文案 */
rep('保存钮', `:'加入书架 · 预载后可读';`, `:'加入书架 · 开始阅读';`);
/* 5 · 附本地文件 toast */
rep('附文件toast', `'附本地文件 · 预载完成后点封面进入阅读'`, `'附本地文件 · 点封面即可进入 · 整本分页后台续算'`);
/* 6 · 批3.5 口径注释：预载中可进 */
rep('三态注释', `三态：就绪→点封面秒进；已清缓存且原文件可读`, `三态：就绪→点封面秒进；预载中→可直接进入（V1.60：开书后台续算全书分页）；已清缓存且原文件可读`);
/* 7 · 预载模拟注释 */
rep('预载注释', `/* 预载模拟：整本解析+分页计算（实算在 Flutter 侧后台 isolate，此处只演示进度与守卫） */`, `/* 预载模拟：整本解析+分页计算（实算在 Flutter 侧首次开书后台续算，此处只演示进度；V1.60 预载中可点进） */`);
/* 8 · 完成 toast 措辞 */
rep('完成toast', `toast('《'+x.n+'》已预载完成 · 点封面秒进')`, `toast('《'+x.n+'》整本预载完成 · 开书秒进')`);
/* 9 · 入口守卫注释 + shOpen 放行（两行连块，锚含 EOL） */
rep('守卫注释', `/* 入口守卫：预载中不可点进阅读；已清缓存点封面→按源文件状态分流 */`, `/* 入口守卫（V1.60）：预载中可点进·开书后台续算全书分页；已清缓存点封面→按源文件状态分流 */`);
rep('shOpen放行', `  if(b.epub.st==='pre'){toast('正在预载整本书 · 完成后可进入');return}` + EOL + `  if(b.epub.st==='cl'){brSrcTap(id);return}}`,
  `  if(b.epub.st==='pre')toast('整本分页仍在后台续算 · 已按首次加载口径打开');` + EOL + `  else if(b.epub.st==='cl'){brSrcTap(id);return}}`);
/* 10 · 长按入口放行 */
rep('长按放行', `if(b.epub.st==='pre')return toast('正在预载整本书 · 完成后可进入');`,
  `if(b.epub.st==='pre'){toast('整本分页仍在后台续算 · 已按首次加载口径打开');return brOpen(id)}`);
/* 11 · 详情本地卡文案 */
rep('详情卡文案', `整本预载中 · 解析与分页计算 · 完成前不可进入阅读`, `整本预载中 · 分页后台续算 · 点封面可直接进入阅读`);
/* 12 · 重新载入弹层文案 */
rep('重载弹层', `将重新拷贝本地副本并预载整本书，完成前封面显示预载进度。`, `将重新拷贝本地副本并预载整本书，封面显示预载进度 · 期间点封面可直接进入阅读。`);
/* 13 · 行视图徽标补预载中态（复用 data-brpct 同步，同套视觉） */
rep('行徽标预载', `brRowBadge=function(b){return BR35_OLD_ROWBADGE(b)+(b&&b.epub&&b.epub.st==='cl'?'<span class="text-[8px] font-black px-1.5 py-0.5 rounded-full bg-amber-500 text-white align-middle ml-1">已清缓存</span>':'')};`,
  `brRowBadge=function(b){return BR35_OLD_ROWBADGE(b)+(b&&b.epub&&b.epub.st==='cl'?'<span class="text-[8px] font-black px-1.5 py-0.5 rounded-full bg-amber-500 text-white align-middle ml-1">已清缓存</span>':b&&b.epub&&b.epub.st==='pre'?'<span class="text-[8px] font-black px-1.5 py-0.5 rounded-full bg-indigo-500 text-white align-middle ml-1" data-brpct="'+b.id+'">预载中 '+(b.epub.pr||0)+'%</span>':'')};`);
/* 14 · br35 深链注释与 toast 口径 */
rep('br35注释行', `?br35=pre     b1 整本预载中（封面进度条实时跑 · 点封面被守卫）`, `?br35=pre     b1 整本预载中（封面进度条实时跑 · 点封面可直接进入阅读）`);
rep('br35toast', `toast(k==='cl'?'演示：已清缓存 · 点封面重新载入':'演示：导入后后台整本预载 · 完成前封面不可点')`,
  `toast(k==='cl'?'演示：已清缓存 · 点封面重新载入':'演示：导入后后台整本预载 · 点封面可直接进入阅读')`);
/* 15 · 新深链 ?imp= 系，插在 br53 深链之前 */
rep('imp深链', `/* V1.53 轮3 深链：?br53=prog|bright|font|sel → 阅读主屏对应面板/选区态 */`,
  [`/* V1.60 导入流程改造深链：?imp=1授权|2选文件|3解析(仅四项)|4核对 ｜ pre 书架预载中书卡 ｜ enter 预载中点进阅读 */`
  , `(function impBoot(){try{`
  , `  const k=(location.search.match(/imp=(\\w+)/)||[])[1];if(!k)return;`
  , `  if(/^[1-4]$/.test(k)){const st=+k;brImp.file=BR_FILES.download[0];brImpGo(st);`
  , `    if(st===3)brImpParse();if(st===4)brImpMeta();`
  , `    navTo('p-localImport');toast('演示：导入向导第 '+st+' 步 · 解析步只有四项')}`
  , `  else if(k==='pre'){const b=bsBook('b1');if(!b||!b.local)return;`
  , `    b.epub.name='思考快与慢.epub';b.epub.cache='8.4 MB';b.epub.srcOk=1;b.epub.st='pre';b.epub.pr=4;brPreStart('b1',4);`
  , `    setPage('p-bookshelf');renderShelf();toast('演示：预载中书卡 · 点封面直接进入阅读')}`
  , `  else if(k==='enter'){const b=bsBook('b1');if(!b||!b.local)return;`
  , `    b.epub.name='思考快与慢.epub';b.epub.cache='8.4 MB';b.epub.srcOk=1;b.epub.st='pre';b.epub.pr=42;brPreStop('b1');shOpen('b1');`
  , `    toast('演示：预载中点进 · 全书分页后台续算')}`
  , `}catch(e){console.warn('imp',e)}})();`
  , ``
  , `/* V1.53 轮3 深链：?br53=prog|bright|font|sel → 阅读主屏对应面板/选区态 */`].join(EOL));

/* ---- 命中断言：每条锚必须恰好命中 1 次 ---- */
let bad = 0;
for (const e of edits) {
  const c = s.split(e.oldStr).length - 1;
  if (c !== 1) { console.error('ANCHOR ' + e.name + ' 命中 ' + c + ' 次（需要恰好 1）—— 中止，不落盘'); bad++; }
}
if (bad) process.exit(2);

for (const e of edits) s = s.replace(e.oldStr, e.newStr);

/* ---- 体积校验：本次只应小幅增减 ---- */
const delta = s.length - src.length;
if (delta < 200 || delta > 4000) { console.error('SIZE GUARD: 体积变化 ' + delta + ' 超出 [200,4000]，中止'); process.exit(3); }
/* 反向断言：新文本里不应再出现「分页预计算」与「完成前不可进入」 */
if (s.includes('分页预计算')) { console.error('GUARD: 分页预计算 仍残留'); process.exit(4); }
if (s.includes('完成前不可进入')) { console.error('GUARD: 完成前不可进入 仍残留'); process.exit(4); }
if (s.includes('完成后可进入')) { console.error('GUARD: 完成后可进入 仍残留'); process.exit(4); }

fs.writeFileSync(P, s, 'utf8');
console.log('OK: ' + edits.length + ' 处编辑已落盘；体积 ' + src.length + ' → ' + s.length + '（Δ' + delta + '）；行尾=' + (EOL === '\r\n' ? 'CRLF' : 'LF'));
