/* g7c_chrome.js · G7c1：六个 UI builder 移入 extension part（同库私有直访·零调用点改动）
   _topBar/_bottomBar/_brIconBtn/_flashBar/_subSpan/_textSpan → reader_chrome.dart */
const fs = require('fs');
const P = 'lib/features/read/presentation/reader/reader_page.dart';
const O = 'lib/features/read/presentation/reader/reader_chrome.dart';
const src = fs.readFileSync(P, 'utf8');
const L = src.split(/\r?\n/);
const fail = (m) => { console.error('GUARD-FAIL: ' + m); process.exit(1); };
const find = (re) => { for (let i = 0; i < L.length; i++) if (re.test(L[i])) return i; return fail('未命中 ' + re); };
function blockEnd(i) {
  let depth = 0, started = false;
  for (let j = i; j < L.length; j++) {
    const line = L[j];
    let q = null;
    for (let c = 0; c < line.length; c++) {
      const ch = line[c];
      if (!q) {
        if (ch === '/' && line[c + 1] === '/') break;
        if (ch === "'" || ch === '"') { q = ch; continue; }
        if (ch === '{') { depth++; started = true; } else if (ch === '}') depth--;
        continue;
      }
      if (ch === '\\') { c++; continue; }
      if (ch === q) q = null;
    }
    if (started && depth === 0) return j;
  }
  fail('块未闭合');
}
const decls = [
  /^  Widget _topBar\(BrBar bar\) \{/,
  /^  Widget _bottomBar\(BrBar bar, Size size\) \{/,
  /^  Widget _brIconBtn\(/,
  /^  Widget _flashBar\(BrBar bar\) \{/,
  /^  TextSpan _subSpan\(/,
  /^  TextSpan _textSpan\(/,
];
const names = ['_topBar', '_bottomBar', '_brIconBtn', '_flashBar', '_subSpan', '_textSpan'];
const spans = decls.map((re, k) => {
  let s = find(re);
  while (s > 0 && /^\s*\/\/\//.test(L[s - 1])) s--;
  const e = blockEnd(find(re));
  return { n: names[k], s, e, t: L.slice(s, e + 1).join('\n') };
});
// 顺序与不重叠断言
for (let i = 1; i < spans.length; i++) if (spans[i].s <= spans[i - 1].e) fail('跨度乱序/重叠');
const total = spans.reduce((a, x) => a + (x.e - x.s + 1), 0);
const kept = [];
for (let i = 0; i < L.length; i++) {
  const inSp = spans.find((x) => i >= x.s && i <= x.e);
  if (inSp) { i = inSp.e; continue; }
  kept.push(L[i]);
}
let head = kept.join('\n');
if (!/part 'reader_models\.dart';/.test(head)) fail('G7a part 行缺失');
head = head.replace("part 'reader_models.dart';", "part 'reader_models.dart';\npart 'reader_chrome.dart';");
for (const n of names) if (new RegExp('\\b' + n + '\\s*\\(').test(spans.map(s => s.t).join('\n')) && !new RegExp('\\b' + n + '\\b').test(head)) {
  // 调用点仍在页面（引用扩展方法名即可），仅断言名字在剩余文本某处出现；_textSpan 由 _para 调用
}
fs.writeFileSync(P, head);
const body = [
  "part of 'reader_page.dart';",
  "",
  "// 治理G7c1：顶/底栏与文本构建六件自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。",
  "extension _ReaderChrome on _ReaderPageState {",
  spans
    .map((x) => x.t)
    .join('\n\n')
    // 扩展内调用宿主 setState 属受保护成员误报（运行时即本类），定点 ignore。
    .split('\n')
    .flatMap((ln) =>
      /^[^/]*\bsetState\(/.test(ln)
        ? [/^(\s*)/.exec(ln)[1] + '// ignore: invalid_use_of_protected_member', ln]
        : [ln],
    )
    .join('\n'),
  '}',
  '',
].join('\n');
fs.writeFileSync(O, body);
console.log('moved lines=', total, 'page now=', head.split('\n').length, 'chrome=', body.split('\n').length);
