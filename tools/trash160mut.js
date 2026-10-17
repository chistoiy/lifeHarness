/* V1.60 全局回收站批 · 变异自证（五刀）
 * 每刀：把一个已交付口径改坏 → 跑对应用例必须变红 → 立刻复原。
 * 用法：node tools/trash160mut.js            （全跑）
 *      node tools/trash160mut.js 2 3        （只跑编号）
 * 口径来源＝docs/handoff/交棒话术-20261004-真机反馈轮4批.md §5 批C⑦＋需求清单 §四「全局回收站」。
 */
const { spawnSync } = require('child_process');
const fs = require('fs');

const FLUTTER = 'D:/app_workplace/flutter/bin/flutter.bat';

// 每刀：[编号, 说明, 文件, 原串, 变异串, 应红的用例文件]
const MUTS = [
  ['1', 'KrSource.read 摘掉软删谓词（删过的书还计进 KR）',
    'lib/features/goals/data/goals_repository.dart',
    "AND ended_at < ? AND deleted_at IS NULL\",",
    "AND ended_at < ?\",",
    'test/goals_repo_test.dart'],
  ['2', '孤行判定只看「父书没了」（父书还在回收站也放行＝幽灵摘录）',
    'lib/shared/trash/trash_repository.dart',
    'final orphan = parent == null || parent.isDeleted;',
    'final orphan = parent == null;',
    'test/trash_data_test.dart'],
  ['3', 'purgeBook 连垃圾箱里的划线一起删（孤行口径失效，需求「置灰说明连带」没得展示）',
    'lib/features/read/data/read_repo_book.dart',
    "where: 'book_id = ? AND deleted_at IS NULL',",
    "where: 'book_id = ?',",
    'test/trash_data_test.dart'],
  ['4', '孤行照旧给恢复钮（屏层红线失守）',
    'lib/features/settings/presentation/trash_page.dart',
    'if (t.orphan)',
    'if (!t.orphan)',
    'test/trash_page_test.dart'],
  ['5', '分段计数与屏内不同源（三入口计数说谎）',
    'lib/shared/trash/trash_providers.dart',
    'return (total: items.length, byKind: byKind);',
    'return (total: items.length + 1, byKind: byKind);',
    'test/trash_page_test.dart'],
];

function runTest(file) {
  // .bat 必须经 cmd /c 起（spawnSync 直跑 .bat 得到 status=null 的假结果）
  const r = spawnSync('cmd.exe', ['/c', FLUTTER, 'test', file, '--reporter', 'compact'],
    { encoding: 'buffer' });
  const out = (r.stdout || Buffer.alloc(0)).toString('utf8') +
    (r.stderr || Buffer.alloc(0)).toString('utf8');
  const line = (out.match(/(\d+(?::\d+)? \+\d+ ?~?\d* ?-?\d*: (?:All tests passed!|Some tests failed.))/g) || []).pop();
  return { rc: r.status, plain: line || out.slice(-200), out };
}

function main() {
  const only = process.argv.slice(2);
  let red = 0, green = 0, broken = 0;
  for (const [id, desc, file, from, to, test] of MUTS) {
    if (only.length && !only.includes(id)) continue;
    const src = fs.readFileSync(file, 'utf8');
    const hits = src.split(from).length - 1;
    if (hits !== 1) {
      console.log(`M${id} SKIP 锚点命中 ${hits} 次（应为 1）：${file}`);
      broken++;
      continue;
    }
    fs.writeFileSync(file, src.replace(from, to), 'utf8');
    const r = runTest(test);
    fs.writeFileSync(file, src, 'utf8'); // 复原
    const wentRed = r.rc !== 0;
    if (wentRed) { red++; console.log(`M${id} 红 ✓ ${desc}\n     ${r.plain}`); }
    else { green++; console.log(`M${id} 没红 ✗ ${desc}\n     ${r.plain}`); }
    if (!fs.readFileSync(file, 'utf8').includes(from)) {
      console.log(`M${id} 复原失败：${file}`); broken++;
    }
  }
  console.log(`\nRESULT 变异 ${red} 红 / ${green} 没红 / ${broken} 工装异常` +
    (green || broken ? ' FAIL' : ' PASS'));
  process.exit(green || broken ? 1 : 0);
}
main();
