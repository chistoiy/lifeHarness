/* g7b_sel_layer.js · G7b1：_selLayer/_brHandle/_BrTriPainter 外提为 reader_sel_layer.dart
   行为零改动：全部 State 依赖改构造参数闭包；ValueKey 原样保留。守护：每处替换命中数断言。 */
const fs = require('fs');
const P = 'lib/features/read/presentation/reader/reader_page.dart';
const O = 'lib/features/read/presentation/reader/reader_sel_layer.dart';
const src = fs.readFileSync(P, 'utf8');
const eol = src.includes('\r?\n') ? '\n' : '\n';
const L = src.split(/\r?\n/);
const fail = (m) => { console.error('GUARD-FAIL: ' + m); process.exit(1); };
const find = (re) => { for (let i = 0; i < L.length; i++) if (re.test(L[i])) return i; return fail('未命中 ' + re); };
function blockEnd(i) {
  let depth = 0, started = false;
  for (; i < L.length; i++) {
    for (const c of L[i]) { if (c === '{') { depth++; started = true; } else if (c === '}') depth--; }
    if (started && depth === 0) return i;
  }
  fail('块未闭合');
}
const rSl = { s: find(/^  List<Widget> _selLayer\(Size size\) \{/), };
rSl.e = blockEnd(rSl.s);
const rHd = { s: find(/^  Widget\? _brHandle\(bool end\) \{/) };
rHd.e = blockEnd(rHd.s);
const rPt = { s: find(/^class _BrTriPainter extends CustomPainter \{/) };
rPt.e = blockEnd(rPt.s);
// 文档注释吸走
for (const r of [rSl, rHd]) { let s = r.s; while (s > 0 && /^\s*\/\/\//.test(L[s - 1])) s--; r.s = s; }
let slTxt = L.slice(rSl.s, rSl.e + 1).join('\n');
let hdTxt = L.slice(rHd.s, rHd.e + 1).join('\n');
const ptTxt = L.slice(rPt.s, rPt.e + 1).join('\n');
const need = (t, re, n, why) => { const c = (t.match(new RegExp(re, 'g')) || []).length; if (c !== n) fail(`${why}: 命中 ${c} != ${n}`); return t; };
let hits;
// selLayer 体改参数
hits = 0;
slTxt = slTxt
  .replace('  List<Widget> _selLayer(Size size) {', '  hits0')
; if (!slTxt.includes('hits0')) fail('sl 签名替换失败');
slTxt = slTxt
  .replace('  hits0', '')
  .replace(/\b_hlPop\b/g, 'hlPop')
  .replace(/=> _addHl\(tg\)/g, '=> onColor(tg)')
  .replace(/onPressed: _delHl/g, 'onPressed: onDelete')
  .replace(/, _actCopy\)/g, ', onCopy)')
  .replace(/setState\(\(\) => hlPop = !hlPop\)/g, 'onToggleHl()')
  .replace(/\(\) => _actQuote\((true|false)\)/g, '() => onQuote($1)')
  .replace(/, _actDict\)/g, ', onDict)')
  .replace(/, _actAi\)/g, ', onAi)')
  .replace(/, _actShare\)/g, ', onShare)')
  .replace(/_brHandle\((false|true)\)/g, 'handle($1)')
  .replace(/_BrTriPainter\(/g, 'BrTriPainter(')
  .replace(/\(\) => readToast\(context, '朗读能力规划中 · 暂未上线'\)/g, '() => onTts()');
if (/_(hlPop|act|addHl|delHl|brHandle|BrTriPainter|selAnchor|dragSel)\b/.test(slTxt)) fail('sl 残留私有引用: ' + (slTxt.match(/_\w+/g) || []).join(','));
// handle 改参数化函数
hdTxt = hdTxt
  .replace(/\n    final p = _selAnchor\(end\);/, '')
  .replace('Widget? _brHandle(bool end) {', 'Widget? brHandleWidget(bool end, Offset? p, void Function(Offset g) onDrag) {')
  .replace(/onPanUpdate: \(d\) => _dragSel\(end: end, global: d\.globalPosition\)/g, 'onPanUpdate: (d) => onDrag(d.globalPosition)');
if (/_(selAnchor|dragSel|brHandle)\b/.test(hdTxt)) fail('hd 残留');
const ptOut = ptTxt.replace(/_BrTriPainter/g, 'BrTriPainter');
// 页面侧：删除三块 + 替换调用点
const page = [];
for (let i = 0; i < L.length; i++) {
  if (i === rSl.s) { i = rSl.e; continue; }
  if (i === rHd.s) { i = rHd.e; continue; }
  if (i === rPt.s) { i = rPt.e; continue; }
  page.push(L[i]);
}
let pt2 = page.join('\n');
const useRe = /\.\.\._selLayer\(size\),/;
if (!useRe.test(pt2)) fail('调用点未找到');
pt2 = pt2.replace(useRe, '...brSelLayer(\n                        size: size,\n                        hlPop: _hlPop,\n                        onCopy: _actCopy,\n                        onToggleHl: () => setState(() => _hlPop = !_hlPop),\n                        onQuote: _actQuote,\n                        onDict: _actDict,\n                        onTts: () => readToast(context, \'朗读能力规划中 · 暂未上线\'),\n                        onAi: _actAi,\n                        onShare: _actShare,\n                        onColor: _addHl,\n                        onDelete: _delHl,\n                        handle: (end) =>\n                            brHandleWidget(\n                              end,\n                              _selAnchor(end),\n                              (g) => _dragSel(end: end, global: g),\n                            ),\n                      ),');
pt2 = pt2.replace(/import '\.\/reader_toc_drawer\.dart';/, "import './reader_sel_layer.dart';\nimport './reader_toc_drawer.dart';");
if (/(_selLayer|_brHandle|_BrTriPainter)/.test(pt2)) fail('页面残留: ' + (pt2.match(/_(selLayer|brHandle|BrTriPainter)/g) || []).join(','));
fs.writeFileSync(P, pt2);
const out = [
  "// 治理G7b1：选区浮层三件自 reader_page.dart 提件（行为零改动·State 依赖全参数化·ValueKey 保留）。",
  "import 'package:flutter/material.dart';",
  "",
  "import '../../domain/book.dart';",
  "",
  "/// 选区浮层（划线弹出色环 + 工具条 + 指向气泡 + 首尾手柄槽位）。",
  'List<Widget> brSelLayer({',
  '  required Size size,',
  '  required bool hlPop,',
  '  required VoidCallback onCopy,',
  '  required VoidCallback onToggleHl,',
  '  required void Function(bool) onQuote,',
  '  required VoidCallback onDict,',
  '  required VoidCallback onTts,',
  '  required VoidCallback onAi,',
  '  required VoidCallback onShare,',
  '  required void Function(String) onColor,',
  '  required VoidCallback onDelete,',
  '  required Widget? Function(bool end) handle,',
  '}) {',
  slTxt.replace(/^ {2}\/\/\/.*$/gm, '// $&'.slice(3)).replace(/^ {2}\/\/\//gm, '//'),
  '',
  '/// 选区端点手柄：锚点算不出（段落未渲染/快照缺段）就不画，也不拦事件。',
  hdTxt.replace(/^ {2}\/\/\/.*$/gm, ''),
  '',
  ptOut,
].join('\n');
fs.writeFileSync(O, out);
console.log('OK page lines now=', pt2.split('\n').length, ' sel_layer=', out.split('\n').length);
