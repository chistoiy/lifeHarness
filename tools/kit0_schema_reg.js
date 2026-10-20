/* 批0-2：schema.dart 注册 kit 域（import / version 27→28 / createStatements /
 * 表名转发 / 语句转发 / kitTables / migrations）
 * 本文件是 CRLF，模式里的 \n 一律按实际行尾还原，避免整文件换行符漂移
 * 护栏：每处命中数必须为 1，任一处不符即整体零写入 */
const fs = require('fs');
const F = 'lib/core/database/schema.dart';
let raw = fs.readFileSync(F, 'utf8');
const NL = raw.includes('\r\n') ? '\r\n' : '\n';
const e = (a, b) => [a.replace(/\n/g, NL), b.replace(/\n/g, NL)];
const EDITS = [
  e("import 'schema/habit.dart' as h;", "import 'schema/habit.dart' as h;\nimport 'schema/kit.dart' as k;"),
  e('static const int version = 27;', 'static const int version = 28;'),
  e('    ...aiCallSchemaStatements,\n', '    ...aiCallSchemaStatements,\n    ...kitSchemaStatements,\n'),
  e('  static const String tAiCalls = a.tAiCalls;  // G5: ai.dart\n',
   '  static const String tAiCalls = a.tAiCalls;  // G5: ai.dart\n'
   + '  static const String tKitUsage = k.tKitUsage;  // G5: kit.dart\n'
   + '  static const String tKitLayout = k.tKitLayout;  // G5: kit.dart\n'
   + '  static const String tKitToolData = k.tKitToolData;  // G5: kit.dart\n'
   + '  static const String tKitPlugin = k.tKitPlugin;  // G5: kit.dart\n'),
  e('  static const List<String> careTables = e.careTables;  // G5: care.dart\n',
   '  static const List<String> careTables = e.careTables;  // G5: care.dart\n'
   + '  static const List<String> kitTables = k.kitTables;  // G5: kit.dart\n'),
  e('  static const List<String> careSchemaStatements = e.careSchemaStatements;  // G5: care.dart\n',
   '  static const List<String> careSchemaStatements = e.careSchemaStatements;  // G5: care.dart\n'
   + '  static const List<String> kitSchemaStatements = k.kitSchemaStatements;  // G5: kit.dart\n'),
  e('    ...h.mig,\n', '    ...h.mig,\n    ...k.mig,\n'),
];
const orig = raw;
for (const [oldS, newS] of EDITS) {
  const hits = raw.split(oldS).length - 1;
  if (hits !== 1) { console.error(`!! 命中 ${hits}（期望 1）：${JSON.stringify(oldS).slice(0, 70)}`); process.exit(1); }
  raw = raw.replace(oldS, newS);
}
if (raw === orig) { console.error('!! 内容未变化'); process.exit(2); }
fs.writeFileSync(F, raw);
console.log(`PASS schema.dart 已注册 kit 域（+${raw.length - orig.length} 字符 · 行尾 ${NL === '\r\n' ? 'CRLF' : 'LF'}）`);
