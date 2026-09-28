/* g7a_extract.js · G7 第一刀 v2：reader_page 零状态件外提（part 同库·私有名不变）
   搬移 _Pos/_LocalHl（原样类块）与 _kTerm/_kSoft/_kTail/_kBrDict/_sentenceAt/
   _firstRenderParagraph（顶层件·去 static）。守护：命中断言+行数核对。 */
const fs = require('fs');
const P = 'lib/features/read/presentation/reader/reader_page.dart';
const O = 'lib/features/read/presentation/reader/reader_models.dart';
const src = fs.readFileSync(P, 'utf8');
const eol = src.includes('\r\n') ? '\r\n' : '\n';
const L = src.split(/\r?\n/);
const fail = (m) => { console.error('GUARD-FAIL: ' + m); process.exit(1); };
function findLine(re) { for (let i = 0; i < L.length; i++) if (re.test(L[i])) return i; return fail('未命中 ' + re); }
function blockEnd(i) {
  if (L[i].trim().endsWith(';')) return i; // 单行成员
  let depth = 0, started = false;
  for (; i < L.length; i++) {
    for (const c of L[i]) { if (c === '{') { depth++; started = true; } else if (c === '}') depth--; }
    if (started && depth === 0) return i;
  }
  fail('块未闭合');
}
const topCuts = [], clsCuts = [];
function cut(re, sink) {
  let s = findLine(re);
  while (s > 0 && /^\s*\/\/\//.test(L[s - 1])) s--; // 吸走紧邻 /// 文档注释
  const e = blockEnd(findLine(re));
  sink.push([s, e, L.slice(s, e + 1).join(eol)]);
}
cut(/^class _Pos \{/, clsCuts);
cut(/^class _LocalHl \{/, clsCuts);
cut(/^  static const _kTerm = /, topCuts);
cut(/^  static const _kSoft = /, topCuts);
cut(/^  static const _kTail = /, topCuts);
cut(/^  static const _kBrDict = \{/, topCuts);
cut(/^  static \(\{int a, int b\}\) _sentenceAt/, topCuts);
cut(/^  static RenderParagraph\? _firstRenderParagraph/, topCuts);
if (clsCuts.length !== 2 || topCuts.length !== 6) fail('cut 分类不齐');

const toTop = (t) => t
  .replace(/^  static const /gm, 'const ')
  .replace(/^  static (?=[\w(])/gm, '');

const all = [...clsCuts.map(c => c[2]), ...topCuts.map(c => toTop(c[2]))];
let total = 0;
for (const [s, e] of [...clsCuts, ...topCuts].sort((a, b) => b[0] - a[0])) { L.splice(s, e - s + 1); total += e - s + 1; }
let head = L.join(eol);
head = head.replace(/(import '\.\/reader_toc_drawer\.dart';)/, "$1" + eol + eol + "part 'reader_models.dart';");
fs.writeFileSync(P, head);
fs.writeFileSync(O, "part of 'reader_page.dart';" + eol + eol +
  '// 治理G7a：零状态件自 reader_page.dart 纯搬移（同库私有名不变·行为零改动）。' + eol +
  eol + eol + all.join(eol + eol) + eol);
console.log('extracted lines=', total, 'page now=', head.split(eol).length);
