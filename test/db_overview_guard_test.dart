/// B-4 机器闸（工单 §7-2 红线）：数据库概览人话词表必须覆盖全部 schema 实表。
///
/// 口径：「词表配机器闸」＝新增表未配人话名 → 红灯；词表里出现 schema 没有的
/// 表名（改名/删表后残留）同样红灯——过期词条会让概览静默少一格。
/// 另钉 X-Ray 三可再生表 label 含「可再生」（异常提示卡与模块行靠它做定性标注）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart'
    show kRegenerableExcluded;
import 'package:lifeharness/core/backup/db_overview.dart';
import 'package:lifeharness/core/database/schema.dart';

/// 从 DbSchema.createStatements 解析「实表名」集合
/// （与 test/backup_lh_bak_test.dart 的 schemaTableNames 同一定式——
/// 测试文件之间不互相 import，防止入口 main 串跑）。
Set<String> schemaTableNames() {
  final re = RegExp(
      r'CREATE TABLE (?:IF NOT EXISTS )?([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false);
  final names = <String>{};
  for (final sql in DbSchema.createStatements) {
    final m = re.firstMatch(sql);
    if (m != null) names.add(m.group(1)!);
  }
  return names;
}

void main() {
  group('dbTableLabels 全覆盖守护', () {
    test('schema 每张实表都必须有人话词条（新增表未配词=红灯）', () {
      final missing =
          schemaTableNames().difference(dbTableLabels.keys.toSet()).toList()..sort();
      expect(missing, isEmpty,
          reason: '以下表在 DbSchema 里但没有人话词条，数据库概览会退化显示表名：'
              '$missing ——请在 lib/core/backup/db_overview.dart 的 dbTableLabels 配齐');
    });

    test('词条不得残留 schema 已没有的表名（改名/删表=红灯）', () {
      final stale =
          dbTableLabels.keys.toSet().difference(schemaTableNames()).toList()..sort();
      expect(stale, isEmpty,
          reason: '以下词条对应的表已不在 DbSchema 中：$stale ——请删除或更名');
    });

    test('人话名不得是原始表名/含下划线（给用户看的必须人话）', () {
      final raw = dbTableLabels.entries
          .where((e) =>
              e.value.label.isEmpty ||
              e.value.label == e.key ||
              e.value.label.contains('_'))
          .map((e) => '${e.key}→${e.value.label}')
          .toList();
      expect(raw, isEmpty, reason: '以下 label 未人话化：$raw');
    });
  });

  group('可再生口径守护', () {
    test('备份恒排除三表 label 必须含「可再生」且归阅读模块', () {
      for (final t in kRegenerableExcluded) {
        final meta = dbTableLabels[t];
        expect(meta, isNotNull, reason: '$t 缺词条');
        expect(meta!.label, contains('可再生'),
            reason: '$t 属可再生派生表，label 必须含「可再生」定性');
        expect(meta.module, '阅读');
      }
    });

    test('X-Ray 四表（含用户词库）全部归阅读模块', () {
      for (final t in [
        DbSchema.tXrayMention,
        DbSchema.tXrayEntity,
        DbSchema.tXrayTask,
        DbSchema.tXrayUserdict,
      ]) {
        expect(dbTableLabels[t]?.module, '阅读', reason: '$t 归属模块应为阅读');
      }
    });
  });
}
