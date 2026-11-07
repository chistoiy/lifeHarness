/* mm_check.js · 思维导图专版 F1 结构断言（2026-10-12 原型批）
 * 口径与既有 protostructcheck/protojscheck 同族：
 *   ① 零 emoji（排版箭头 → 不算）；② 屏级 id 唯一；③ onclick 引用的函数都有定义；
 *   ④ 每个内联 <script> 过 new vm.Script 语法门；⑤ 屏/弹层 id 命名与注册表前缀约定。
 * 用法：node tools/mm_check.js [文件路径]
 */
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = path.dirname(__dirname);
const F = process.argv[2] || path.join(ROOT, 'prototype', 'index-mindmap.html');
const html = fs.readFileSync(F, 'utf8');

const red = [], warn = [];
const REL = path.relative(ROOT, F).replace(/\\/g, '/');

/* ① 零 emoji ＋ 零排版箭头（本项目口径：两者皆红，见 MEMORY「原型·三道校」） */
const EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{2190}-\u{21FF}\u{2B05}-\u{2B07}]/u;
const emo = [];
html.split('\n').forEach((l, i) => {
  const m = l.match(EMOJI);
  if (m) emo.push('  ' + REL + ':' + (i + 1) + ' -> ' + JSON.stringify(m[0]));
});
if (emo.length) red.push('零 emoji/箭头 红灯：\n' + emo.join('\n'));

/* ② 屏级 id 唯一（section 全收；div 仅 sheetMm-/drawer 收） */
const idRe = /<(section|div)\b[^>]*\bid="([^"]+)"/gi;
const seen = new Map();
let m;
while ((m = idRe.exec(html))) {
  const tag = m[1].toLowerCase(), id = m[2];
  if (tag === 'div' && !/^(sheetMm|drawer)/.test(id)) continue;
  seen.set(id, (seen.get(id) || 0) + 1);
}
for (const [id, n] of seen) if (n > 1) red.push('id 重复 ' + n + ' 次：' + id);

/* ②b 命名约定：屏 mm- 前缀、弹层 sheetMm- 前缀 */
for (const id of seen.keys()) {
  if (/^(sheetMm|drawer)/.test(id)) continue;
  if (!id.startsWith('mm-')) red.push('屏 id 未用 mm- 前缀：' + id);
}
for (const id of seen.keys()) {
  if (id.startsWith('sheet') && !id.startsWith('sheetMm-')) red.push('弹层 id 未用 sheetMm- 前缀：' + id);
}

/* ②c 引用的屏必须存在（setPage/navTab/openSheet/closeSheet 的字面量参数） */
const refIds = new Set();
for (const r of [/(?:setPage|navTo|navTab)\('([^']+)'\)/g, /(?:openSheet|closeSheet)\('([^']+)'\)/g]) {
  let x; while ((x = r.exec(html))) refIds.add(x[1]);
}
for (const id of refIds) {
  if (!seen.has(id)) red.push('引用的 id 未在文件里定义：' + id);
}

/* ③ onclick 函数定义校验：整段提取 onclick="..." 再抓调用名，排除 JS 关键字 */
const KW = new Set(['if', 'for', 'while', 'switch', 'return', 'catch', 'function', 'typeof', 'new', 'do', 'else', 'event', 'this']);
const called = new Set();
const onRe = /onclick="([^"]*)"/g;
let o;
while ((o = onRe.exec(html))) {
  const body = o[1];
  const cRe = /([A-Za-z_$][\w$]*)\s*\(/g;
  let c;
  while ((c = cRe.exec(body))) {
    const name = c[1];
    if (KW.has(name)) continue;
    called.add(name);
  }
}
const defined = new Set();
const dRe = /function\s+([A-Za-z_$][\w$]*)\s*\(/g;
let d;
while ((d = dRe.exec(html))) defined.add(d[1]);
for (const r of [/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\(/g, /window\.([A-Za-z_$][\w$]*)\s*=/g]) {
  let v; while ((v = r.exec(html))) defined.add(v[1]);
}
for (const name of called) {
  if (!defined.has(name)) red.push('onclick 引用未定义函数：' + name);
}

/* ④ 内联 script 过语法门 */
const scripts = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
let si = 0;
for (const s of scripts) {
  si++;
  const body = s[1];
  if (!body.trim()) continue;
  try { new vm.Script(body); }
  catch (e) { red.push('内联 script #' + si + ' 语法错：' + e.message); }
}

/* ⑤ 禁教学性说明文案 / 禁 emoji 图标位（原型里的图标须为 inline svg） */
if (/<(img|span)[^>]*class="[^"]*\b(emo|emoji)\b/i.test(html)) red.push('发现 emoji 图标位（须线性 SVG）');
const iconFont = /font-awesome|fa-[a-z-]+\s|iconfont/i.test(html);
if (iconFont) red.push('发现图标字体引用（本项目禁 emoji 图标，须 inline SVG）');

/* ⑥ 禁 InteractiveViewer 大图冲突面的提示：画布须自带手势仲裁标注 */
if (!/手势/.test(html)) warn.push('未见手势口径注释（2d 裁定要求画布自仲裁）');

console.log('== mm_check · ' + REL + ' ==');
console.log('屏级 id ' + seen.size + ' 个 · onclick 调用 ' + called.size + ' 种 · 内联 script ' + scripts.length + ' 段');
if (warn.length) { console.log('软提示 ' + warn.length + ' 条：'); warn.forEach(w => console.log('  ! ' + w)); }
if (red.length) {
  console.log('红灯 ' + red.length + ' 处：');
  red.forEach(r => console.log('  x ' + r));
  process.exit(1);
}
console.log('PASS 结构全绿（零 emoji/箭头 / id 唯一 / 引用齐全 / onclick 有定义 / 语法门）');