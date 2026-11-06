import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 无用项移除守护（2026-11-06 · 产品「无用的都移除掉」）。
///
/// 移除：影音游 `media.timerUI`（provider 零消费、全屏档对应的沉浸屏已下架）、
/// 购书费入账的设置项/同步挂点/备份导出登记/概览登记。
/// **保留**：`media.speedFold`（billedMinutes 折算仍在消费）、DB 物理层
/// `finance_txns` DDL/常量/列（老库兼容，不升版本、不 DROP 表）。
/// 变异刀靶点＝把任一已移除项写回，本文件必须报红。
String _read(String rel) => File(rel).readAsStringSync();

const _timerUiFiles = [
  'lib/features/media/presentation/media_set_page.dart',
  'lib/features/media/presentation/media_providers.dart',
  'prototype/index-media.html',
];

// 概览词条与备份单元属 DB 兼容层（表还在，必须覆盖），不在功能层清单内。
const _feeTxnFiles = [
  'lib/features/read/presentation/read_settings_page.dart',
  'lib/features/read/data/read_repo_book.dart',
];

void main() {
  test('media.timerUI 全链路零引用（实现与原型同源）', () {
    for (final rel in _timerUiFiles) {
      expect(_read(rel).contains('timerUI'), isFalse,
          reason: '$rel 仍引用已移除的计时形态设置（全屏档无消费方）');
    }
  });

  test('购书费入账功能层零引用', () {
    for (final rel in _feeTxnFiles) {
      final src = _read(rel);
      expect(
          src.contains('feeTxn') ||
              src.contains('finance_txns') ||
              src.contains('tFinance') ||
              src.contains('_syncFeeTxn'),
          isFalse,
          reason: '$rel 仍引用已移除的购书费入账口径');
    }
  });

  test('speedFold 仍是有效口径，不许被当成死键误删', () {
    expect(
        _read('lib/features/media/presentation/media_providers.dart')
            .contains('mediaSpeedFoldProvider'),
        isTrue,
        reason: '倍速折算 provider 仍被 mediaStatProvider 与 billedMinutes 消费');
    expect(
        _read('lib/features/media/presentation/media_set_page.dart')
            .contains("'media.speedFold'"),
        isTrue);
  });

  test('DB 兼容层保留：不升版本、不 DROP 表', () {
    final schema = _read('lib/core/database/schema.dart');
    expect(schema.contains('static const int version = 50;'), isTrue,
        reason: '本批刻意不动 DB 版本，避免不可逆迁移');
    expect(schema.contains('DROP TABLE IF EXISTS finance_txns'), isFalse,
        reason: '本批不 DROP 旧表，避免不可逆迁移');
    expect(_read('lib/core/database/schema/ledger.dart').contains('finance_txns'),
        isTrue,
        reason: '旧表 DDL 仅作老库兼容保留，代码侧已无功能引用');
  });
}
