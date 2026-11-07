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
import 'package:lifeharness/features/read/presentation/biblio/douban_login_page.dart'
    show doubanCookieHeader;
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_settings_page.dart';

/// 豆瓣防封批（2026-09-26）· 阅读设置「数据与存储」新增两行；
/// V1.45 改口（2026-09-27）：Cookie 从手动粘贴改为应用内登录获取——
/// 未配置显「登录豆瓣」，已配置显「已配置」+清除+重新登录。
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

  test('doubanCookieHeader：必须含 dbcl2 才成头，按 name=value; … 拼接', () {
    expect(
      doubanCookieHeader({'dbcl2': '"a b"', 'll': '118351'}),
      'dbcl2="a b"; ll=118351',
    );
    // 只有匿名跟踪 cookie（未登录）→ 判未登录，不存半吊子。
    expect(doubanCookieHeader({'ck': 'x', 'll': '118351'}), isNull);
    expect(doubanCookieHeader({}), isNull);
  });

  testWidgets('未配置显「登录豆瓣」钮，无输入框（粘贴口径已废）', (tester) async {
    await boot(tester);
    expect(find.text('登录豆瓣'), findsOneWidget);
    expect(find.byKey(const ValueKey('set-dbCookie-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('set-dbCookie-input')), findsNothing);
    expect(find.byKey(const ValueKey('set-dbCookie-on')), findsNothing);
  });

  testWidgets('已配置：徽标+重新登录；清除（F2-11 过二次确认）→prefs 与内存态双清、回到未配置',
      (tester) async {
    // 登录页「完成」后的落点即 prefs＋DoubanCookie，这里直接预置等价状态。
    await prefs.setString('read.dbCookie', 'ck=abc; ll="118351"');
    DoubanCookie.set('ck=abc; ll="118351"');
    await boot(tester);
    expect(find.byKey(const ValueKey('set-dbCookie-on')), findsOneWidget);
    expect(find.text('登录豆瓣'), findsNothing);
    expect(find.byKey(const ValueKey('set-dbCookie-relogin')), findsOneWidget);
    // settings 表零足迹 → buildBackupJson（捞 read.*）永远不会带出 Cookie。
    expect(await repo.kv('read.dbCookie'), isNull);

    // F2-11（LH-S31）：清除登录态＝破坏性动作，先过统一二次确认（点「清除」才真清）。
    await tester.tap(find.byKey(const ValueKey('set-dbCookie-clear')));
    await settle(tester);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget,
        reason: '清 Cookie 必须先弹二次确认');
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await settle(tester);
    expect(prefs.getString('read.dbCookie'), isNull);
    expect(DoubanCookie.value, isNull);
    expect(find.text('登录豆瓣'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('无缓存时清除按钮置灰', (tester) async {
    await boot(tester);
    final btn = find.byKey(const ValueKey('set-dbCache-clear'));
    expect(tester.widget<TextButton>(btn).onPressed, isNull);
    expect(find.text('无缓存'), findsOneWidget);
  });

  testWidgets('有条数显示并可一键清除（F2-11 过二次确认 · F2-14 状态小标）', (tester) async {
    await repo.doubanCachePut(
      '9787108009821',
      const IsbnBookMeta(title: '万历十五年', author: '黄仁宇'),
    );
    await boot(tester);
    expect(find.text('清除 1 条'), findsOneWidget);

    // F2-14（LH-K36）：按钮旁常驻状态小标（禁用第三态＝不把状态只压按钮文案）。
    expect(find.byKey(const ValueKey('set-dbCache-state')), findsOneWidget);
    expect(find.text('本机 1 条'), findsOneWidget);

    // F2-11（LH-S31）：清缓存＝破坏性动作，先过统一二次确认。
    await tester.tap(find.text('清除 1 条'));
    await settle(tester);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget,
        reason: '清缓存必须先弹二次确认');
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await settle(tester);
    expect(await repo.doubanCacheCount(), 0);
    expect(find.text('无缓存'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('书架备份导出不含 Cookie 键（prefs 有值也不被 settings 捞走）',
      (tester) async {
    await prefs.setString('read.dbCookie', 'ck=abc');
    await repo.setKv('read.isbnFill', '抓豆瓣数据');
    await boot(tester);
    final json = await repo.buildBackupJson();
    expect(json, contains('isbnFill'));
    expect(json, isNot(contains('dbCookie')));
    expect(json, isNot(contains('abc')));
  });
}
