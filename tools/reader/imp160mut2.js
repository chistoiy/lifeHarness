/* X-Ray 中心页批 · 变异自证（三刀）：深链段／书守卫弹层／明细同源守护
 * 用法：node tools/reader/imp160mut2.js（独占跑）
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const FLUTTER = 'D:/app_workplace/flutter/bin/flutter.bat';
const P = 'lib/features/read/presentation/xray_words_page.dart';
const T = 'test/xray_words_page_test.dart';
const cuts = [
  {
    name: '刀A 摘除 initialSeg 深链（默认段焊死词条）',
    old: `  late String _seg = switch (widget.initialSeg) {\r\n    'ai' => 'ai',\r\n    'idx' => 'idx',\r\n    _ => 'word',\r\n  };`,
    neu: `  late String _seg = 'word'; // MUTATED`,
  },
  {
    name: '刀B 不带书点开始不再弹书选择页',
    old: `      if (_book == null) {\r\n        await _ensureBookPicked();\r\n        return;\r\n      }`,
    neu: `      if (_book == null) {\r\n        return;\r\n      }`,
  },
  {
    name: '刀C 明细块改回中心页自写一份',
    old: `                xrRefineLogBlock(context, runner),`,
    neu: `                const Text('已出建议 删 0 · 改 0 · 补 0'), // MUTATED`,
  },
];
const results = [];
for (const c of cuts) {
  const orig = fs.readFileSync(P, 'utf8');
  const eol = orig.includes('\r\n') ? '\r\n' : '\n';
  const old = c.old.replace(/\r\n/g, eol), neu = c.neu.replace(/\r\n/g, eol);
  if (orig.split(old).length - 1 !== 1) {
    results.push([c.name, 'ANCHOR-FAIL（命中 ' + (orig.split(old).length - 1) + '）']);
    continue;
  }
  fs.writeFileSync(P, orig.replace(old, neu), 'utf8');
  try {
    const r = spawnSync('cmd.exe', ['/c', FLUTTER, 'test', T],
      { encoding: 'utf8', timeout: 600000, maxBuffer: 128 * 1024 * 1024, windowsHide: true });
    const out = (r.stdout || '') + (r.stderr || '');
    if (r.error || !/\+\d+/.test(out)) results.push([c.name, 'RUN-FAIL ' + (r.error || out.slice(0, 200))]);
    else {
      const red = (r.status || 0) !== 0 || /Some tests failed|\[E\]/.test(out);
      results.push([c.name, red ? 'RED（真被测点）' : 'GREEN——假绿！']);
    }
  } finally {
    fs.writeFileSync(P, orig, 'utf8');
    if (fs.readFileSync(P, 'utf8') !== orig) results.push([c.name + ' 还原', '不一致!!']);
  }
  console.log(results[results.length - 1].join('  →  '));
}
console.log('== imp160mut2 汇总 ==');
for (const r of results) console.log(r.join('  →  '));
process.exit(results.every(r => /RED（真被测点）/.test(r[1])) ? 0 : 1);
