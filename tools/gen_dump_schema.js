/* gen_dump_schema.js · 从 schema.dart 提取全部 static const 名，生成 tools/dump_schema.dart */
const fs = require('fs');
const src = fs.readFileSync('lib/core/database/schema.dart', 'utf8');
const names = [...new Set([...src.matchAll(/static const [\w<>, ]+? (\w+) =/g)].map(m => m[1]))].sort();
if (names.length < 80) { console.error('GUARD-FAIL names=' + names.length); process.exit(1); }
const body = names.map(n => "      '" + n + "': DbSchema." + n + ',').join('\n');
fs.writeFileSync('tools/dump_schema.dart', `// dump_schema.dart · 治理G5等价性快照（由 tools/gen_dump_schema.js 生成·勿手改）
// 用法：dart tools/dump_schema.dart > tools/schema-dump-<tag>.json
import 'dart:convert';
import 'dart:io';
import 'package:lifeharness/core/database/schema.dart';

String norm(String s) => s.replaceAll(RegExp(r'\\s+'), ' ').trim();

void main() {
  stdout.write(const JsonEncoder.withIndent(' ').convert({
    'version': DbSchema.version,
    'fileName': DbSchema.fileName,
    'consts': <String, dynamic>{
${body}
    },
    'create': DbSchema.createStatements.map(norm).toList(),
    'migrations': <String, dynamic>{
      for (final e in DbSchema.migrations.entries)
        '\${e.key}': e.value.map(norm).toList(),
    },
  }));
}
`);
console.log('dump tool regenerated, consts=' + names.length);
