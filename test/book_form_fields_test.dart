import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book_dict.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/shelf/book_form_page.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';

import 'helpers.dart';

/// 阅读模块批1 · F1-3 录入/编辑表单字段可填（doc 冻结方案 §2.1 F1-3 · §6.4）。
///
/// 口径：出版日期/购入日期＝**点开滚轮弹层**（原型 bfTap+bfDateOpen），
/// 不是文本输入框；确定写值、清空置空、回显到行。
/// 滚轮项键＝`${keyPrefix}item$i`（LH-K39），年池 1900~2100 且初始档在池中部
/// （当前年 2026 → index≈126），故弹层存在性以 `LHWheel` 计数断言，不依赖 item0。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  Widget page() => ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: BookFormPage()),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
  }

  /// 起手＝加高视口让懒构建 ListView 的深部行（来源/分组/购入日期＝第 4~6 段）入树。
  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(page());
    await settle(tester);
    await useSurface(tester, const Size(800, 4000));
    await settle(tester);
  }

  testWidgets('F1-3a 出版日期＝点击开滚轮弹层，确定后回显到行', (tester) async {
    await boot(tester);
    // 出版日期行存在且为可点控件（键 bf-pubDate）
    expect(find.byKey(const ValueKey('bf-pubDate')), findsOneWidget);
    // 打开弹层
    await tester.tap(find.byKey(const ValueKey('bf-pubDate')));
    await settle(tester);
    // ym 形态＝年/月两柱（藏日柱）+ 确定/清空在场
    expect(find.byType(LHWheel), findsNWidgets(2));
    expect(find.byKey(const ValueKey('bf-date-ok')), findsOneWidget);
    expect(find.byKey(const ValueKey('bf-date-clear')), findsOneWidget);
    // 确定 → 弹层关闭，回显非空
    await tester.tap(find.byKey(const ValueKey('bf-date-ok')));
    await settle(tester);
    expect(find.byType(LHWheel), findsNothing);
    final echo = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('bf-pubDate')),
        matching: find.byType(Text)));
    expect(echo.data, isNotEmpty);
  });

  testWidgets('F1-3b 购入日期＝年月日三柱（含日柱）', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('bf-feeDate')));
    await settle(tester);
    // ymd 形态＝年/月/日三柱
    expect(find.byType(LHWheel), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('bf-date-clear')));
    await settle(tester);
    // 清空后弹层关闭
    expect(find.byType(LHWheel), findsNothing);
  });

  testWidgets('F1-3c 来源/分组＝选择器（词典芯片）可真填', (tester) async {
    await repo.dictAdd(DictEntry.kSource, '得到');
    await repo.dictAdd(DictEntry.kGroup, '读书会');
    await boot(tester);
    // 来源/分组下拉在场
    expect(find.byKey(const ValueKey('bf-src')), findsOneWidget);
    expect(find.byKey(const ValueKey('bf-grp')), findsOneWidget);
  });
}
