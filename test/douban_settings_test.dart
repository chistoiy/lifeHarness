import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/read/data/isbn_enrich.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_settings_page.dart';

/// 豆瓣防封批（2026-09-26）· 阅读设置「数据与存储」新增两行：
/// Cookie 只进 SharedPreferences（绝不进 settings 表＝书架备份导出不带），
/// 缓存行展示条数并可手动清除。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    DoubanGuard.reset();
    DoubanCookie.set(null);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(
          home: ReadSettingsPage(initialSec: 4), // 数据与存储
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 屏上偶发周期任务禁 pumpAndSettle：小步 pump（SnackBar 退场口径）。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pump();
  }

  testWidgets('Cookie 保存只进 prefs 且即时生效；清除双清', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('set-dbCookie-input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('set-dbCookie-input')),
      '  ck=abc; ll="118351"  ',
    );
    await tester.tap(find.byKey(const ValueKey('set-dbCookie-save')));
    await settle(tester);

    expect(prefs.getString('read.dbCookie'), 'ck=abc; ll="118351"');
    expect(DoubanCookie.value, 'ck=abc; ll="118351"', reason: '保存即注入抓取链');
    // settings 表零足迹 → buildBackupJson（捞 read.*）永远不会带出 Cookie。
    expect(await repo.kv('read.dbCookie'), isNull);
    expect(find.byKey(const ValueKey('set-dbCookie-on')), findsOneWidget);
    expect(find.byKey(const ValueKey('set-dbCookie-input')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('set-dbCookie-clear')));
    await settle(tester);
    expect(prefs.getString('read.dbCookie'), isNull);
    expect(DoubanCookie.value, isNull);
    expect(find.byKey(const ValueKey('set-dbCookie-input')), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('无缓存时清除按钮置灰', (tester) async {
    await boot(tester);
    final btn = find.byKey(const ValueKey('set-dbCache-clear'));
    expect(tester.widget<TextButton>(btn).onPressed, isNull);
    expect(find.text('无缓存'), findsOneWidget);
  });

  testWidgets('有条数显示并可一键清除', (tester) async {
    await repo.doubanCachePut(
      '9787108009821',
      const IsbnBookMeta(title: '万历十五年', author: '黄仁宇'),
    );
    await boot(tester);
    expect(find.text('清除 1 条'), findsOneWidget);

    await tester.tap(find.text('清除 1 条'));
    await settle(tester);
    expect(await repo.doubanCacheCount(), 0);
    expect(find.text('无缓存'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('书架备份导出不含 Cookie 键（settings 表 read.* 全量导出侧证）',
      (tester) async {
    await repo.setKv('read.isbnFill', '抓豆瓣数据');
    await boot(tester);
    final json = await repo.buildBackupJson();
    expect(json, contains('isbnFill'));
    expect(json, isNot(contains('dbCookie')));
    expect(json, isNot(contains('abc')));
  });
}
