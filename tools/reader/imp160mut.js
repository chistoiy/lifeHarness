/* V1.60 导入流程改造批 · 变异自证（四刀）
 * 每刀：改 lib → 跑目标用例（--plain-name）→ 必须红 → 还原。全部还原后才写结论。
 * 用法：node tools/reader/imp160mut.js   （约 4 分钟，独占跑，勿并行）
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const FLUTTER = 'D:/app_workplace/flutter/bin/flutter.bat';
const cuts = [
  {
    name: '刀1 向导塞回「分页预计算」',
    file: 'lib/features/read/presentation/import/local_import_page.dart',
    test: 'test/reader_wizard_page_test.dart',
    plain: '解析步任务恰好四项',
    mutate(s, eol) {
      const a = "    '封面与元数据抽取'," + eol + '  ];';
      if (s.split(a).length - 1 !== 1) throw new Error('锚1 不唯一/缺失');
      return s.replace(a, "    '封面与元数据抽取'," + eol + "    '分页预计算'," + eol + '  ];');
    },
  },
  {
    name: '刀2 守卫恢复拦截（预载中不放行）',
    file: 'lib/features/read/presentation/reader/epub_state_ui.dart',
    test: 'test/reader_preload_ui_test.dart',
    plain: '点封面直接进阅读器',
    mutate(s, eol) {
      const a = "    readToast(context, '整本分页仍在后台续算 · 已按首次加载口径打开');" + eol + '    return false;';
      if (s.split(a).length - 1 !== 1) throw new Error('锚2 不唯一/缺失');
      return s.replace(a, "    readToast(context, '正在预载整本书 · 完成后可进入');" + eol + '    return true;');
    },
  },
  {
    name: '刀3 摘除预载解析的并路挂接',
    file: 'lib/features/read/data/epub_cache.dart',
    test: 'test/reader_preload_test.dart',
    plain: '预载中开书并路',
    mutate(s, eol) {
      const a = '    _warmTasks[b.id] = gate.future;';
      if (s.split(a).length - 1 !== 1) throw new Error('锚3 不唯一/缺失');
      return s.replace(a, '    // MUTATED: 并路挂接摘除');
    },
  },
  {
    name: '刀4 分片写不再做指纹重置出清',
    file: 'lib/features/read/data/epub_cache.dart',
    test: 'test/reader_preload_test.dart',
    plain: '指纹变化＝整档重置',
    mutate(s, eol) {
      const a = '      if (await dir.exists()) await dir.delete(recursive: true);' + eol + '      await dir.create(recursive: true);';
      if (s.split(a).length - 1 !== 1) throw new Error('锚4 不唯一/缺失');
      return s.replace(a, '      await dir.create(recursive: true);');
    },
  },
];
const results = [];
for (const c of cuts) {
  const orig = fs.readFileSync(c.file, 'utf8');
  const eol = orig.includes('\r\n') ? '\r\n' : '\n';
  let mutated = null;
  try { mutated = c.mutate(orig, eol); } catch (e) { results.push([c.name, 'ANCHOR-FAIL ' + e.message]); continue; }
  fs.writeFileSync(c.file, mutated, 'utf8');
  let out = '';
  try {
    // 自证①：.bat 必须经 cmd /c 起，且 r.error/空输出不得当成“通过”（上一版工装就是这么假绿的）。
    const r = spawnSync('cmd.exe', ['/c', FLUTTER, 'test', c.test], { encoding: 'utf8', timeout: 600000, maxBuffer: 128 * 1024 * 1024, windowsHide: true });
    out = (r.stdout || '') + (r.stderr || '');
    if (r.error || !/\+\d+/.test(out)) { results.push([c.name, 'RUN-FAIL 工装没跑到用例: ' + (r.error ? r.error.message : out.slice(0, 200))]); }
    else {
      const rc = r.status || 0;
      const red = rc !== 0 || /Some tests failed|\[E\]/.test(out);
      results.push([c.name, red ? 'RED（真被测点）' : 'GREEN——假绿！该刀没被测试钉住']);
    }
  } catch (e) {
    results.push([c.name, 'RUN-FAIL ' + e.message]);
  } finally {
    fs.writeFileSync(c.file, orig, 'utf8');
    const back = fs.readFileSync(c.file, 'utf8');
    if (back !== orig) { results.push([c.name + ' 还原', '还原不一致!!']); }
  }
  console.log(results[results.length - 1].join('  →  '));
}
console.log('== 变异自证汇总 ==');
for (const r of results) console.log(r.join('  →  '));
const bad = results.some(r => !/RED（真被测点）/.test(r[1]));
process.exit(bad ? 1 : 0);
