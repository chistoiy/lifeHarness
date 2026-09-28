// 一次性修复：AiCallStore._where 返回「不含 WHERE 关键字」的条件片段。
// 起因：db.query(where:) 自己加 WHERE，rawQuery 侧再拼一次 → 'WHERE WHERE' 语法错。
// 已执行过就不要再跑（命中数断言会直接报错）。
const fs = require('fs');
const p = 'lib/core/ai/ai_call_store.dart';
let s = fs.readFileSync(p, 'utf8');
const before = s.length;
function rep(a, b, n) {
  const c = s.split(a).length - 1;
  if (c !== n) throw new Error('命中 ' + c + ' != ' + n + ' :: ' + a.slice(0, 48));
  s = s.split(a).join(b);
}

rep(`    return (parts.isEmpty ? '' : 'WHERE \${parts.join(' AND ')}', args);`,
    `    return (parts.join(' AND '), args);`, 1);

rep('    final (where, args) = _where(f);', '    final (cond, args) = _where(f);', 4);
rep('        where: where.isEmpty ? null : where,', '        where: cond.isEmpty ? null : cond,', 1);
rep("'SELECT status, in_tok, out_tok FROM \$table \$where',",
    "'SELECT status, in_tok, out_tok FROM \$table \${_sqlWhere(cond)}',", 1);
rep("'SELECT module, COUNT(*) AS n FROM \$table \$where GROUP BY module ORDER BY module',",
    "'SELECT module, COUNT(*) AS n FROM \$table \${_sqlWhere(cond)} GROUP BY module ORDER BY module',", 1);
rep('    if (where.isEmpty) return clearAll();', '    if (cond.isEmpty) return clearAll();', 1);
rep('    return db.delete(table, where: where, whereArgs: args.isEmpty ? null : args);',
    '    return db.delete(table, where: cond, whereArgs: args.isEmpty ? null : args);', 1);

rep('  Future<List<AiCallRecord>> query(',
    `  /// rawQuery 侧的条件前缀（条件为空串时不拼 WHERE）。
  static String _sqlWhere(String cond) => cond.isEmpty ? '' : 'WHERE \$cond';

  Future<List<AiCallRecord>> query(`, 1);

if (Math.abs(s.length - before) > 800) throw new Error('体积异常 ' + before + '->' + s.length);
fs.writeFileSync(p, s, 'utf8');
console.log('OK', before, '->', s.length);
