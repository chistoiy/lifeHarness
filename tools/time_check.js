/* time_check.js · 时间模块专版 F1 结构断言（2026-10-12 抽离批）
 * 口径与 mm_check/protostructcheck 同族：
 *   ① 零 emoji/箭头；② 屏/弹层 id 唯一且命名合规；③ 引用的屏存在（setPage/navTo/navTab/openSheet/closeSheet 字面量）；
 *   ④ onclick 引用的函数都有定义；⑤ 每个内联 <script> 过 new vm.Script；⑥ 静态 div/section 配平；⑦ 行尾标签 >0。
 * 用法：node tools/time_check.js [文件路径]
 */
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = path.dirname(__dirname);
const F = process.argv[2] || path.join(ROOT, 'prototype', 'index-time.html');
const html = fs.readFileSync(F, 'utf8');
const REL = path.relative(ROOT, F).replace(/\\/g, '/');
const red = [];

/* ① 零 emoji ＋ 零排版箭头 */
const EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{2190}-\u{21FF}\u{2B05}-\u{2B07}]/u;
const emo = [];
html.split('\n').forEach((l, i) => { const m = l.match(EMOJI); if (m) emo.push('  ' + REL + ':' + (i + 1) + ' -> ' + JSON.stringify(m[0])); });
if (emo.length) red.push('零 emoji/箭头 红灯：\n' + emo.join('\n'));

/* ② 屏/弹层 id 唯一 */
const idRe = /<(section|div)\b[^>]*\bid="([^"]+)"/gi;
const seen = new Map(); let m;
while ((m = idRe.exec(html))) {
  const tag = m[1].toLowerCase(), id = m[2];
  if (tag === 'div' && !/^(sheet|drawer)/.test(id)) continue;
  seen.set(id, (seen.get(id) || 0) + 1);
}
for (const [id, n] of seen) if (n > 1) red.push('id 重复 ' + n + ' 次：' + id);

/* ②b 命名：屏 p-*（或已知壳内别名）、弹层 sheet* */
for (const id of seen.keys()) {
  if (/^(sheet|drawer)/.test(id)) continue;
  if (!/^p-/.test(id)) red.push('屏 id 未用 p- 前缀：' + id);
}

/* ②c 引用的屏必须存在（EXT＝全局壳层弹层，家不在本专版，仅允许被引用） */
const EXT = new Set(['sheetSearch']);
const refIds = new Set();
for (const r of [/(?:setPage|navTo|navTab)\('([^']+)'\)/g, /(?:openSheet|closeSheet)\('([^']+)'\)/g]) {
  let x; while ((x = r.exec(html))) refIds.add(x[1]);
}
for (const id of refIds) if (!seen.has(id) && !EXT.has(id)) red.push('引用的 id 未在文件里定义：' + id);

/* ④ onclick 函数定义校验（排除成员调用 name. 与 Math. 这类方法） */
const KW = new Set(['if', 'for', 'while', 'switch', 'return', 'catch', 'function', 'typeof', 'new', 'do', 'else', 'event', 'this']);
const called = new Set(); const onRe = /onclick="([^"]*)"/g; let o;
while ((o = onRe.exec(html))) { const cRe = /(?<![\w$.])([A-Za-z_$][\w$]*)\s*\(/g; let c; while ((c = cRe.exec(o[1]))) { if (!KW.has(c[1])) called.add(c[1]); } }
const defined = new Set(); const dRe = /function\s+([A-Za-z_$][\w$]*)\s*\(/g; let d;
while ((d = dRe.exec(html))) defined.add(d[1]);
for (const r of [/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g, /window\.([A-Za-z_$][\w$]*)\s*=/g]) { let v; while ((v = r.exec(html))) defined.add(v[1]); }
for (const name of called) if (!defined.has(name)) red.push('onclick 引用未定义函数：' + name);

/* ⑤ 内联 script 语法门 */
const scripts = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
let si = 0;
for (const s of scripts) { si++; const body = s[1]; if (!body.trim()) continue; try { new vm.Script(body); } catch (e) { red.push('内联 script #' + si + ' 语法错：' + e.message); } }

/* ⑥ 静态配平（专版按 0 基线） */
const divDiff = (html.match(/<div[\s>]/g) || []).length - (html.match(/<\/div>/g) || []).length;
const secDiff = (html.match(/<section[\s>]/g) || []).length - (html.match(/<\/section>/g) || []).length;
if (divDiff !== 0) red.push('静态 div 不配平：' + divDiff);
if (secDiff !== 0) red.push('静态 section 不配平：' + secDiff);

/* ⑦ 图标位须 inline svg，禁图标字体 */
if (/font-awesome|iconfont/i.test(html)) red.push('发现图标字体引用（须 inline SVG）');
if (/<img[^>]*class="[^"]*\b(emo|emoji)\b/i.test(html)) red.push('发现 emoji 图标位');

console.log('== time_check · ' + REL + ' ==');
console.log('屏/弹层 id ' + seen.size + ' 个 · onclick 调用 ' + called.size + ' 种 · 内联 script ' + scripts.length + ' 段 · div差 ' + divDiff + ' section差 ' + secDiff);
if (red.length) { console.log('红灯 ' + red.length + ' 处：'); red.forEach(r => console.log('  x ' + r)); process.exit(1); }
console.log('PASS 结构全绿（零 emoji/箭头 / id 唯一 / 引用齐全 / onclick 有定义 / 语法门 / 配平）');
