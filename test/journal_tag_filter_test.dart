import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/diary_filter_kit.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 日记改版收尾批（2026-10-19）·筛选**标签多选 AND**。
///
/// 原型口径（`index-journal.html` `dwHit` / `diaryTagToggle`）：
/// - 标签是**数组**，选中多枚＝`every` 全部命中（AND），不是「任一命中」；
/// - 标签与标记（全部/收藏/点亮/待办）**正交叠加**——原型批2b-2 修过一次
///   「先判 `全部` 就 return true」把标签短路掉的偏；
/// - 标签多选落**新键**（`journalTags`），旧的单值标签筛选（`journalFilter` 存标签名）
///   做只读兼容，打开弹层后自然迁移到新键。
///
/// 本文件先钉纯逻辑（判据、收敛、计数文案），再钉 settings 往返与弹层行为。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  JournalEntry entry({
    required String content,
    List<String> tags = const [],
    bool starred = false,
    bool liked = false,
    int day = 19,
  }) =>
      JournalEntry(
        day: DateTime(2026, 10, day),
        content: content,
        tags: tags,
        starred: starred,
        liked: liked,
        createdAt: DateTime(2026, 10, day, 9),
        updatedAt: DateTime(2026, 10, day, 9),
      );

  group('标签多选判据（AND）', () {
    final both = entry(content: '正文', tags: const ['复盘', '阅读']);
    final onlyReview = entry(content: '正文', tags: const ['复盘']);

    test('T1 选两枚＝两枚都命中；只命中一枚即不通过', () {
      expect(diaryHit(both, 'all', tags: const ['复盘', '阅读']), isTrue);
      expect(diaryHit(onlyReview, 'all', tags: const ['复盘', '阅读']), isFalse);
      expect(diaryHit(onlyReview, 'all', tags: const ['复盘']), isTrue);
    });

    test('T2 空集合＝不设限（等价未筛标签）；单枚等价旧单选', () {
      expect(diaryHit(onlyReview, 'all', tags: const []), isTrue);
      expect(diaryHit(onlyReview, 'all', tags: const ['阅读']), isFalse);
    });

    test('T3 历史带 `#` 的标签键也要认（剥前缀再比）', () {
      expect(diaryHit(both, 'all', tags: const ['#复盘']), isTrue);
      expect(diaryHit(both, 'all', tags: const ['#复盘', '#阅读']), isTrue);
      expect(diaryHit(onlyReview, 'all', tags: const ['#阅读']), isFalse);
    });

    test('T4 标签与标记正交：两条都过才命中', () {
      final todoReview =
          entry(content: '正文\n☐ 买牛奶', tags: const ['复盘']);
      expect(diaryHit(todoReview, 'todo', tags: const ['复盘']), isTrue);
      // 标记命中、标签不命中
      expect(diaryHit(todoReview, 'todo', tags: const ['阅读']), isFalse);
      // 标签命中、标记不命中
      expect(diaryHit(todoReview, 'starred', tags: const ['复盘']), isFalse);
      // 标记全部 + 标签命中（原型曾把这条短路成「显示全部」）
      expect(diaryHit(todoReview, 'all', tags: const ['复盘']), isTrue);
    });
  });

  group('筛选键收敛与旧单值兼容', () {
    test('T5 dfMarkOf：固定键直取，标签名/脏值回落 all', () {
      expect(dfMarkOf('all'), 'all');
      expect(dfMarkOf('todo'), 'todo');
      expect(dfMarkOf('starred'), 'starred');
      expect(dfMarkOf('liked'), 'liked');
      expect(dfMarkOf('复盘'), 'all');
      expect(dfMarkOf(''), 'all');
    });

    test('T6 dfTagsOf：新键优先；新键空时旧单值标签升为唯一选中', () {
      expect(dfTagsOf('todo', const ['复盘', '阅读']), ['复盘', '阅读']);
      expect(dfTagsOf('复盘', const []), ['复盘']);
      expect(dfTagsOf('#复盘', const []), ['复盘']);
      expect(dfTagsOf('todo', const []), isEmpty);
      expect(dfTagsOf('all', const []), isEmpty);
      expect(dfTagsOf('', const []), isEmpty);
    });

    test('T7 计数文案：标记 + 多标签 + 时间段三段并列', () {
      expect(dfCountLabel(n: 2, tags: const ['复盘', '阅读']),
          '当前筛选：#复盘 #阅读，共 2 篇');
      expect(
        dfCountLabel(
            n: 1, mark: 'todo', tags: const ['复盘'], range: '7d'),
        '当前筛选：待办 · #复盘 · 近 7 天，共 1 篇',
      );
      // 旧单值标签键仍能说出人话（不因新键引入而退化成「全部」）
      expect(dfCountLabel(n: 1, mark: '复盘'), '当前筛选：#复盘，共 1 篇');
    });
  });

  group('settings 落盘（新键 journalTags）', () {
    test('T8 toMap/fromMap 往返：保序、去重、逗号不拆', () {
      const s = UserSettings(
        themeId: 'minimal',
        mode: ThemeModeOption.system,
        navIds: ['today', 'journal', 'settings'],
        journalFilter: 'todo',
        journalTags: ['复盘,复盘', '阅读'],
      );
      final back = UserSettings.fromMap(s.toMap());
      expect(back.journalFilter, 'todo');
      // 标签名里的逗号必须原样保留——逗号分隔会把它静默拆成两枚
      expect(back.journalTags, ['复盘,复盘', '阅读']);
    });

    test('T9 脏值收敛：空串丢弃、重复去重、超上限截断', () {
      final raw = List.generate(
              UserSettings.kJournalTagMax + 5, (i) => '标签$i')
          .join('\u0001');
      final many = UserSettings.decodeJournalTags('$raw\u0001\u0001$raw');
      expect(many.length, UserSettings.kJournalTagMax);
      expect(many.first, '标签0');
      expect(UserSettings.decodeJournalTags(''), isEmpty);
      expect(UserSettings.decodeJournalTags(null), isEmpty);
      expect(UserSettings.decodeJournalTags('a\u0001a'), ['a']);
    });

    test('T10 控制器：toggle 增删、reset 四维全清并落盘', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(c.dispose);
      final ctl = c.read(settingsControllerProvider.notifier);

      await ctl.toggleJournalTag('复盘');
      await ctl.toggleJournalTag('阅读');
      expect(c.read(settingsControllerProvider).journalTags, ['复盘', '阅读']);

      await ctl.toggleJournalTag('复盘');
      expect(c.read(settingsControllerProvider).journalTags, ['阅读']);

      await ctl.setJournalFilter('todo');
      await ctl.resetJournalFilter();
      final s = c.read(settingsControllerProvider);
      expect(s.journalTags, isEmpty);
      expect(s.journalFilter, 'all');
      expect(s.journalRange, 'all');

      // 落盘可解（不是只改内存态）
      final loaded = SettingsRepository(prefs).load();
      expect(loaded.journalTags, isEmpty);
      expect(loaded.journalFilter, 'all');
    });

    test('T11 setJournalFilter 收窄为标记键：标签名回落 all', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      addTearDown(c.dispose);
      final ctl = c.read(settingsControllerProvider.notifier);

      await ctl.setJournalFilter('复盘');
      expect(c.read(settingsControllerProvider).journalFilter, 'all');
      await ctl.setJournalFilter('starred');
      expect(c.read(settingsControllerProvider).journalFilter, 'starred');
    });
  });

  // ---------------------------------------------------------------------
  // 弹层行为（多选 AND 在真 widget 树里也成立）
  // ---------------------------------------------------------------------
  late Database db;
  late JournalRepository jrepo;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    jrepo = JournalRepository(JournalDao(db));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // A：复盘+阅读+待办 · B：仅复盘 · C：仅阅读
    await jrepo.save(entry(content: 'A\n☐ 买牛奶', tags: const ['复盘', '阅读'], day: 19));
    await jrepo.save(entry(content: 'B', tags: const ['复盘'], day: 18));
    await jrepo.save(entry(content: 'C', tags: const ['阅读'], day: 17));
  });

  tearDown(() async => db.close());

  Widget scope(Widget home) => ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWithValue(jrepo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: MediaQuery(
            // FAB 呼吸环是无限动画，`pumpAndSettle` 会等不到静止
            data: const MediaQueryData(disableAnimations: true),
            child: home,
          ),
        ),
      );

  Future<void> openFilterSheet(WidgetTester tester) async {
    await tester.pumpWidget(scope(const JournalPage()));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('diary-fan-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diary-fan-筛选')));
    await tester.pumpAndSettle();
  }

  String countText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('df-count'))).data!;

  group('弹层多选（AND）', () {
    testWidgets('T12 连点两枚标签＝AND 收窄；取消一枚即放宽', (tester) async {
      await openFilterSheet(tester);
      expect(countText(tester), '共 3 篇日记');

      await tester.tap(find.byKey(const ValueKey('df-tag-复盘')));
      await tester.pumpAndSettle();
      expect(countText(tester), '当前筛选：#复盘，共 2 篇');

      await tester.tap(find.byKey(const ValueKey('df-tag-阅读')));
      await tester.pumpAndSettle();
      // AND：只有同时带两枚标签的 A
      expect(countText(tester), '当前筛选：#复盘 #阅读，共 1 篇');

      // 再点一次＝取消该枚（不是「替换成另一枚」）
      await tester.tap(find.byKey(const ValueKey('df-tag-阅读')));
      await tester.pumpAndSettle();
      expect(countText(tester), '当前筛选：#复盘，共 2 篇');
      // 弹层不关（口径：选中即生效 + 实时计数）
      expect(find.byKey(const ValueKey('df-sheet')), findsOneWidget);
    });

    testWidgets('T13 标记与标签叠加：待办 + 阅读只出 A', (tester) async {
      await openFilterSheet(tester);
      await tester.tap(find.byKey(const ValueKey('df-tag-阅读')));
      await tester.pumpAndSettle();
      expect(countText(tester), '当前筛选：#阅读，共 2 篇');

      await tester.tap(find.byKey(const ValueKey('df-mark-todo')));
      await tester.pumpAndSettle();
      expect(countText(tester), '当前筛选：待办 · #阅读，共 1 篇');
    });

    testWidgets('T14 重置：标签与标记一起清，计数回满', (tester) async {
      await openFilterSheet(tester);
      await tester.tap(find.byKey(const ValueKey('df-tag-复盘')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('df-mark-todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('df-reset')));
      await tester.pumpAndSettle();

      expect(countText(tester), '共 3 篇日记');
      final c = ProviderScope.containerOf(tester.element(find.byType(JournalPage)));
      expect(c.read(settingsControllerProvider).journalTags, isEmpty);
      expect(c.read(settingsControllerProvider).journalFilter, 'all');
    });

    testWidgets('T15 旧单值兼容：journalFilter 存标签名仍能筛出该标签', (tester) async {
      // 模拟旧版本落盘的筛选态：标签名在单值键里，新键不存在。
      // 直接写 mock 存储（此时 settings controller 还没首次读取，读到即生效）。
      await prefs.setString('lh.journal_filter', '复盘');
      await openFilterSheet(tester);
      expect(countText(tester), '当前筛选：#复盘，共 2 篇');
      // 兼容值在弹层里呈选中态：再点一次即取消（若是未选中态，点一次会变成选中）
      await tester.tap(find.byKey(const ValueKey('df-tag-复盘')));
      await tester.pumpAndSettle();
      expect(countText(tester), '共 3 篇日记');
    });
  });
}
