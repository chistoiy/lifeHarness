/* V1.55 书源专版原型构建脚本
   用法：node tools/bs_proto/inject.js          （从 index-bookshelf.html 重新生成 index-booksource.html）
   依赖：仅 Node 内置 fs。与项目构建隔离，不进 lib/ 与 flutter 测试路径。
   护栏：① 每处插入做命中断言（锚点出现次数必须等于预期）；② 产物体积区间校验；
        ③ 每次从底座重建（幂等），不增量改写已有产物；④ 底座只读，绝不写回。 */
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
const BASE = path.join(root, 'prototype', 'index-bookshelf.html');
const OUT = path.join(root, 'prototype', 'index-booksource.html');
const DIR = __dirname;

const base = fs.readFileSync(BASE, 'utf8');
const baseSize = Buffer.byteLength(base);
/* 底座是 CRLF 行尾，片段统一折成 CRLF，产物不留混合行尾 */
const eol = s => s.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
const css = eol(fs.readFileSync(path.join(DIR, 'frag_css.txt'), 'utf8'));
const screens = eol(fs.readFileSync(path.join(DIR, 'frag_screens.txt'), 'utf8'));
const sheets = eol(fs.readFileSync(path.join(DIR, 'frag_sheets.txt'), 'utf8'));
const js = eol(fs.readFileSync(path.join(DIR, 'frag_js.txt'), 'utf8'));

function countAll(hay, needle) { return hay.split(needle).length - 1 }
function must(label, got, want) {
  if (got !== want) { console.error('FAIL 锚点断言：' + label + ' 命中 ' + got + ' 处，期望 ' + want); process.exit(1) }
  console.log('  ok ' + label + ' · 命中 ' + got + '/' + want);
}
function insertOnce(hay, anchor, add, label, where) {
  must(label, countAll(hay, anchor), 1);
  const i = hay.indexOf(anchor);
  if (where === 'before') return hay.slice(0, i) + add + hay.slice(i);
  const j = i + anchor.length;
  return hay.slice(0, j) + add + hay.slice(j);
}

let out = base;
const TITLE_OLD = '<title>LifeHarness · 书架专版高保真（阅读：书架/书籍/笔记/计时/统计）</title>';
const TITLE_NEW = '<title>LifeHarness · 在线书源专版高保真（V1.55 · 书源管理/搜索/发现/在线阅读/抓取任务）</title>';

console.log('构建 index-booksource.html（底座 index-bookshelf.html ' + (baseSize / 1024).toFixed(0) + 'KB）');
must('title 锚点', countAll(out, TITLE_OLD), 1);
out = out.replace(TITLE_OLD, TITLE_NEW);
must('title 就位', countAll(out, TITLE_NEW), 1);

out = insertOnce(out, '  </main>', '\n' + screens, '屏插入 </main> 前', 'before');
/* 徽标传参改造：base 的 brCovBadge()/brRowBadge() 无参 → 传入 b，供书源版覆写「在线」 */
must('封面徽标调用点', countAll(out, 'b.local?brCovBadge()'), 3);
out = out.split('b.local?brCovBadge()').join('b.local?brCovBadge(b)');
must('行内徽标调用点', countAll(out, 'b.local?brRowBadge()'), 1);
out = out.split('b.local?brRowBadge()').join('b.local?brRowBadge(b)');
out = insertOnce(out, '</div><!-- /phone -->', '\n' + sheets + '\n', '弹层插入 /phone 前', 'before');
out = insertOnce(out, '\n  /* ---- 组件类 ---- */', '\n' + css, '样式插入 style 内', 'before');

const tail = '</script>';
{
  const first = out.indexOf(tail), last = out.lastIndexOf(tail);
  if (first === last) { console.error('FAIL 找不到主脚本收尾锚点'); process.exit(1) }
  const jsTailAnchor = out.slice(Math.max(0, last - 40), last);
  if (jsTailAnchor.indexOf('renderPwBar') < 0) { console.error('FAIL 主脚本收尾锚点内容不符：' + JSON.stringify(jsTailAnchor)); process.exit(1) }
  console.log('  ok JS 插入主脚本尾 · 锚点 renderPwBar();</script>');
  out = out.slice(0, last) + '\n' + js + '\n' + out.slice(last);
}

const banners = '\n<!-- V1.55 在线书源专版：由 tools/bs_proto/inject.js 从 index-bookshelf.html 生成，勿手工编辑产物（改片段后重跑）。 -->\n';
out = insertOnce(out, '</head>', banners, '来源横幅', 'before');

const outSize = Buffer.byteLength(out);
const add = outSize - baseSize;
if (add < 20000 || add > 200000) {
  console.error('FAIL 体积校验：新增 ' + (add / 1024).toFixed(1) + 'KB，超出合理区间 [20KB, 200KB]');
  process.exit(1);
}
fs.writeFileSync(OUT, out, 'utf8');
console.log('  → 产物 ' + (outSize / 1024).toFixed(0) + 'KB（新增 ' + (add / 1024).toFixed(1) + 'KB）· ' + OUT);

/* 内联脚本语法自检：抽出最后一个 <script> 块交给 vm 解析 */
const m = out.lastIndexOf('<script>');
const close = out.indexOf('</script>', m);
const code = out.slice(m + 8, close);
try {
  new (require('vm').Script)(code);
  console.log('  ok 内联 JS 语法通过（' + (Buffer.byteLength(code) / 1024).toFixed(0) + 'KB）');
} catch (e) {
  console.error('FAIL 内联 JS 语法错误：' + e.message);
  const line = (e.stack.match(/<anonymous>:(\d+)/) || [])[1];
  if (line) {
    const arr = code.split('\n');
    for (let i = Math.max(0, line - 3); i < Math.min(arr.length, +line + 2); i++) console.error('  ' + (i + 1) + '| ' + arr[i].slice(0, 160));
  }
  process.exit(1);
}
