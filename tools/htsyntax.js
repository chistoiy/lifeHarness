/* 语法与结构检查：prototype/index-health.html（健康管理专版）
   用法：node tools/htsyntax.js
   说明：所有区域类检查（emoji / 文本泄漏 / 标签平衡）只作用于健康专版三段，
        避免把宿主原型 index.html 的既有写法计入本模块结论。 */
const fs = require('fs');
const vm = require('vm');
const P = 'prototype/index-health.html';
const H = fs.readFileSync(P, 'utf8').replace(/\r\n/g, '\n');
const SCRIPTS = [...H.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const body = SCRIPTS[SCRIPTS.length - 1];
const HTML_ONLY = H.replace(/<script>[\s\S]*?<\/script>/g, '').replace(/<style>[\s\S]*?<\/style>/g, '');
let rc = 0;
const fail = m => { console.log('⚠ ' + m); rc = 1 };

/* 1) 内联脚本语法 */
try { new vm.Script(body, { filename: 'inline.js' }); console.log('SYNTAX OK  scripts=' + SCRIPTS.length + ' js=' + body.length); }
catch (e) {
  console.log('SYNTAX FAIL ' + e.message);
  const l = /inline\.js:(\d+)/.exec(e.stack || '');
  if (l) { const arr = body.split('\n'); for (let i = Math.max(0, +l[1] - 3); i < +l[1] + 2; i++) console.log((i + 1) + ': ' + (arr[i] || '').slice(0, 240)); }
  process.exit(1);
}

/* 2) 三段定位（任一找不到即 RANGE FAIL，绝不等于通过） */
const RANGES = [
  ['pages', '    <!-- ===== H1 健康主页', '    <!-- ===== P10 目标 OKR'],
  ['sheets', '  <!-- ===== H-弹层组', '  <!-- ===== 插件详情弹层'],
  ['js', '   健康管理专版（需求 V1.41', '/* ================= 全局搜索']
];
const SEG = {};
for (const [n, a, b] of RANGES) {
  const i = H.indexOf(a), j = H.indexOf(b, i + a.length);
  if (i < 0 || j < i) { console.log(n.toUpperCase() + ' RANGE FAIL'); fail(n + ' 区间未扫到'); continue }
  SEG[n] = H.slice(i, j);
  console.log('RANGE ' + n + ' ok  lines=' + SEG[n].split('\n').length);
}
const MARKUP = (SEG.pages || '') + '\n' + (SEG.sheets || '');

/* 3) onclick/oninput 引用的顶层函数必须已定义 */
const decl = new Set();
for (const m of H.matchAll(/function\s+([A-Za-z_$][\w$]*)/g)) decl.add(m[1]);
for (const m of H.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g)) decl.add(m[1]);
const calls = new Set();
for (const m of MARKUP.matchAll(/on(?:click|input|change|submit|keydown)="([^"]*)"/g))
  for (const c of m[1].matchAll(/(^|[^.\w$])([A-Za-z_$][\w$]*)\s*\(/g)) calls.add(c[2]);
const KW=new Set(['if','for','while','switch','return','typeof','event']);
const missing = [...calls].filter(c => !decl.has(c)&&!KW.has(c));
console.log(missing.length ? 'MISSING FNS: ' + missing.join(', ') : 'ONCLICK FNS OK (' + calls.size + ' referenced)');
if (missing.length) fail('存在未定义处理器');

/* 4) id 唯一 + getElementById 字面量目标存在 */
const ids = [...MARKUP.matchAll(/\sid="([^"]+)"/g)].map(m => m[1]);
const idSet = new Set(ids);
const dup = [...new Set(ids.filter((x, i) => ids.indexOf(x) !== i))];
if (dup.length) fail('DUP IDS: ' + dup.join(', ')); else console.log('IDS UNIQUE OK (' + ids.length + ' 个)');
const missId = new Set();
const jsSeg = SEG.js || '';
/* 运行期由 hInline 注入的滚轮面板元素，静态 HTML 里本就不存在 */
const DYN = new Set(['hInlineW', 'hInlineNo', 'hInlineYes']);
const chk = id => { if (!idSet.has(id) && !DYN.has(id)) missId.add(id) };
for (const m of jsSeg.matchAll(/getElementById\(\s*['"]([\w-]+)['"]/g)) chk(m[1]);
for (const m of jsSeg.matchAll(/\bhPut\(\s*['"]([\w-]+)['"]/g)) chk(m[1]);
for (const m of jsSeg.matchAll(/\bhWv\(\s*['"]([\w-]+)['"]/g)) chk(m[1]);
for (const m of jsSeg.matchAll(/querySelector(?:All)?\(\s*'#([\w-]+)/g)) chk(m[1]);
for (const m of jsSeg.matchAll(/hWheel\(\s*['"]([\w-]+)['"]/g)) chk(m[1]);
for (const m of jsSeg.matchAll(/hDateRow\(\s*['"]([\w-]+)['"]/g)) chk(m[1]);
for (const m of jsSeg.matchAll(/'(hl-[\w-]+|ha-[\w-]+)'/g)) chk(m[1]);
console.log(missId.size ? 'MISSING IDS(运行期动态生成的需人工确认): ' + [...missId].join(', ') : 'ID REFS OK');
if (missId.size) fail('有无目标元素的 id 引用');

/* 5) TITLES 覆盖所有 section */
const titles = (body.match(/const TITLES=\{[\s\S]*?\};/) || [''])[0];
const secs = [...HTML_ONLY.matchAll(/<section id="(p-[\w-]+)"/g)].map(m => m[1]);
const noTitle = secs.filter(s => !titles.includes("'" + s + "'"));
console.log(noTitle.length ? 'NO TITLE: ' + noTitle.join(', ') : 'TITLES OK (' + secs.length + ' sections)');
if (noTitle.length) fail('section 缺标题');

/* 6) 文本节点泄漏扫描：模板把 class 写到 > 之后会渲染成裸字符 */
const leak = [];
for (const m of MARKUP.matchAll(/>([^<>]*?)</g)) {
  const t = m[1].trim();
  if (t && /(^|\s)(ring-|ring-offset|bg-|text-(slate|white|rose|teal|emerald|amber|brand|indigo|sky|violet)|dark:|seg-on|tag-chip|rounded|flex-|inp |card |mini-btn)/.test(t)) leak.push(t.slice(0, 90));
}
console.log(leak.length ? 'TEXT-LEAK: ' + JSON.stringify(leak.slice(0, 12)) : 'TEXT LEAK OK');
if (leak.length) fail('有类名字符串泄漏为文本');

/* 7) 标签平衡 */
for (const [n, o, c] of [['div', /<div\b/g, /<\/div>/g], ['section', /<section\b/g, /<\/section>/g],
  ['button', /<button\b/g, /<\/button>/g], ['span', /<span\b/g, /<\/span>/g], ['svg', /<svg\b/g, /<\/svg>/g]]) {
  const a = (MARKUP.match(o) || []).length, z = (MARKUP.match(c) || []).length;
  console.log('TAG ' + n + ': ' + a + '/' + z + (a === z ? ' OK' : ' MISMATCH'));
  if (a !== z) fail(n + ' 标签不平衡');
}

/* 8) 禁 emoji（本模块三段内） */
for (const [n, seg] of Object.entries(SEG)) {
  const hits = [...new Set((seg.match(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/gu) || []))].filter(e => !'✓✕›⚡☆★↔⇄⠿⋯☑❝≠'.includes(e));
  console.log(n + ' emoji: ' + (hits.length ? hits.join(' ') : 'NONE'));
  if (hits.length) fail(n + ' 段出现 emoji');
}

/* 9) 弹层可达 + 屏内主入口齐全 */
const sheetIds = [...MARKUP.matchAll(/<div id="(sheet[\w-]+)" class="sheet/g)].map(m => m[1]);
const unopened = sheetIds.filter(s => !new RegExp("openSheet\\('" + s + "'\\)").test(H));
console.log('弹层 ' + sheetIds.length + ' 张: ' + sheetIds.join(' '));
if (unopened.length) fail('无入口弹层: ' + unopened.join(', '));
const hsecs = [...(SEG.pages || '').matchAll(/<section id="(p-[\w-]+)"/g)].map(m => m[1]);
console.log('屏 ' + hsecs.length + ' 张: ' + hsecs.join(' '));
for (const need of ['p-health', 'p-body', 'p-exLog', 'p-med', 'p-sleepLog', 'p-trends', 'p-goalsH', 'p-hSet'])
  if (!hsecs.includes(need)) fail('缺屏 ' + need);
/* 主页七宫格入口：每个屏都要在 hEntryRow 的元组里出现一次 */
for (const t of hsecs.filter(s => s !== 'p-health'))
  if (!H.includes("['" + t + "','")) fail('主页入口项缺失 ' + t);

console.log(rc ? '\nRESULT: FAIL' : '\nRESULT: PASS');
process.exit(rc);
