import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 诚实性批守护（2026-11-05 · 产品裁定「三处原型定稿占位先明示不做」）。
///
/// 钉死四件事：不再向用户声称「已同步/已导出」、不再呈现可拨的假开关、
/// 购书费不再写那张账本侧零消费的旧表（旧表本身保留留档）。
/// 变异刀靶点＝把任一处文案/开关/写库改回原样，本文件必须在对应用例报红。
String _read(String rel) => File(rel).readAsStringSync();

void main() {
  group('诚实性批守护', () {
    test('G6 续费提醒不再声称「已同步」（原型／挂载／交易详情三处同源）', () {
      const lie = '续费提醒日程已同步';
      for (final rel in [
        'prototype/index-ledger.html',
        'lib/shared/linkage/ledger_mounts.dart',
        'lib/features/ledger/presentation/ledger_tx_detail_page.dart',
      ]) {
        expect(_read(rel).contains(lie), isFalse,
            reason: '$rel 仍在向用户声称已同步续费提醒日程（该能力从未落 events 表）');
      }
      expect(
        _read('lib/shared/linkage/ledger_mounts.dart').contains('续费提醒日程未开启'),
        isTrue,
        reason: '挂载 toast 必须明示未开启，不许静默删字了事',
      );
    });

    test('G5 自动同步引擎未上线＝零假开关', () {
      final sheet = _read(
          'lib/features/settings/presentation/widgets/sync_throttle_sheet.dart');
      expect(sheet.contains('_setWifi'), isFalse,
          reason: '不该再有写入 sync_wifiOnly 的可拨开关回调');
      expect(sheet.contains('onChanged: null'), isTrue,
          reason: 'wifi-switch 必须固定禁用，不许留可拨态');
      expect(sheet.contains('自动同步 · 未上线'), isTrue);
      expect(_read('prototype/index-sync.html').contains('仅 Wi-Fi 自动同步'), isFalse,
          reason: '原型侧同步回改，不许两侧口径分叉');
    });

    test('G8 习惯数据导出不再谎报「已导出 …（模拟）」', () {
      final page =
          _read('lib/features/habit/presentation/habit_detail_page.dart');
      final proto = _read('prototype/index_habitcheck.html');
      expect(page.contains(r'已导出 ${h.name}.json'), isFalse,
          reason: '纯提示不得再伪造导出成功');
      expect(page.contains('习惯数据导出 · 未上线'), isTrue);
      expect(proto.contains("toast('已导出 '+h.n+'.json（打卡序列 + 触发记录 · 模拟）')"),
          isFalse,
          reason: '原型侧同一句谎报文案须同步下架');
    });

    test('G3 购书费不出账；旧表仅作老库兼容，功能层零引用', () {
      final repo = _read('lib/features/read/data/read_repo_book.dart');
      expect(repo.contains('DbSchema.tFinance'), isFalse);
      expect(repo.contains('_syncFeeTxn'), isFalse,
          reason: '同步挂点已随设置项移除');
      expect(repo.contains('老库兼容保留'), isTrue,
          reason: '保留 DB 兼容层的原因必须写在代码里，防止后人误 DROP');
      // 只查功能层；概览词条与备份单元属 DB 兼容层（表还在，必须覆盖）。
      for (final rel in [
        'lib/features/read/presentation/read_settings_page.dart',
      ]) {
        final src = _read(rel);
        expect(src.contains('feeTxn') ||
            src.contains('finance_txns') ||
            src.contains('tFinance'), isFalse,
            reason: '$rel 仍引用已移除的购书费入账口径');
      }
      expect(_read('lib/core/database/schema/ledger.dart').contains('finance_txns'),
          isTrue,
          reason: 'DB 兼容层保留（不升版本、不 DROP 表）');
    });
  });
}
