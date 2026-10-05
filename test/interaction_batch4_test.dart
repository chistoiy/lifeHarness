import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart'
    show dayKey;
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

/// 交互整改批四 · T12（金额等宽数字）常驻用例。T14 的找回用例在
/// `test/reader_appearance_undo_test.dart`（同批两页以上同文件会撞 isolate 污染挂死）。
///
/// 三档：① 原语本体行为（作用域确实把 `tnum` 传到自带样式的文本上，
/// 且**不包就没有**——对照组防假绿）；② 记账线真页读数（L1 主页金额列）；
/// ③ 源码守护（记账线渲染金额的页面文件必须在作用域内，白名单失效即红）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  const tnum = FontFeature.tabularFigures();
  bool hasTnum(TextStyle? s) =>
      s?.fontFeatures?.any((f) => f == tnum) ?? false;
  bool tabularAt(WidgetTester t, Finder f) =>
      hasTnum(((t.renderObject<RenderParagraph>(f).text) as TextSpan).style);

  group('1 · LH-K33 TabularNums 作用域', () {
    Future<void> pump(WidgetTester t, {required bool scope}) =>
        t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: scope
                ? const TabularNums(
                    child: Text('¥1,234.00',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)))
                : const Text('¥1,234.00',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ));

    testWidgets('子树自带样式的文本也吃到 tnum（merge 沿袭，不必逐处写）', (t) async {
      await pump(t, scope: true);
      expect(tabularAt(t, find.text('¥1,234.00')), isTrue);
    });

    testWidgets('对照组：不包作用域就没有（本用例必须为红才说明上面那条不是假绿）',
        (t) async {
      await pump(t, scope: false);
      expect(tabularAt(t, find.text('¥1,234.00')), isFalse);
    });

    testWidgets('边界钉住：inherit:false 的样式不吃作用域', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TabularNums(
            child: Text('42',
                style: TextStyle(
                    fontSize: 13, inherit: false, color: Colors.black)),
          ),
        ),
      ));
      expect(tabularAt(t, find.text('42')), isFalse,
          reason: '不继承的样式＝调用方自理，本原语不承诺覆盖');
    });

    testWidgets('kTabularNumFeatures 就是 tnum（样式级接法与作用域同源）', (t) async {
      expect(kTabularNumFeatures, const [tnum]);
    });
  });

  group('2 · 记账线真页金额列', () {
    late Database db;
    late LedgerRepository repo;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = LedgerRepository(db);
    });
    tearDown(() => db.close());

    testWidgets('L1 主页：hero 大数字与预算文案都在等宽作用域内', (t) async {
      await useSurface(t);
      await repo.addTxn(LedgerTxn(
        kind: LedgerTxn.kExpense,
        bk: 1,
        amt: 120,
        catId: 101,
        accountId: 1,
        date: dayKey(DateTime.now()),
      ));
      final container = ProviderContainer(
        overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LedgerPage()),
      ));
      await settle5(t);
      final amt = find.text('¥120.00');
      expect(amt, findsWidgets);
      for (var i = 0; i < amt.evaluate().length; i++) {
        expect(tabularAt(t, amt.at(i)), isTrue,
            reason: '主页第 $i 枚「¥120.00」读数未等宽');
      }
    });
  });

  group('3 · 源码守护（记账线不许漏接等宽数字）', () {
    // 白名单＝**不该**由 Flutter 文本样式负责或结构上无法就地包的落点，逐条给理由。
    const excluded = <String, String>{
      'ledger_notify.dart': '系统通知正文（不是 Flutter 文本，主题/字形由系统渲染）',
      'widgets/ledger_kit.dart':
          '行组件本身不自带作用域，由承载页包（L1/搜索/账户详情均在 TabularNums 内渲染）',
      'ledger_pick_sheets.dart':
          '体积预算 1581 钉死（只许减不许增），批四 T9/T12 均登记随拆 part 批一起做',
    };
    final money = RegExp(r'\b(amtText|money)\s*\(');

    test('渲染金额的记账文件必须接入 TabularNums/kTabularNumFeatures', () {
      final dir = Directory('lib/features/ledger/presentation');
      final miss = <String>[], stale = <String>[];
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final rel = f.path.replaceAll(r'\', '/').split('presentation/').last;
        final src = f.readAsStringSync();
        final hit = money.hasMatch(src);
        if (!hit) {
          if (excluded.containsKey(rel)) {
            stale.add('$rel（已不再渲染金额，白名单该删：${excluded[rel]}）');
          }
          continue;
        }
        if (excluded.containsKey(rel)) continue;
        if (!src.contains('TabularNums(') &&
            !src.contains('kTabularNumFeatures')) {
          miss.add(rel);
        }
      }
      expect(miss, isEmpty,
          reason: '这些文件把金额写进 UI 却没进等宽作用域：$miss');
      expect(stale, isEmpty, reason: '白名单里的条目已失效：$stale');
    });
  });
}
