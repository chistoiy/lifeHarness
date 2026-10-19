import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/diary_template_dao.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/domain/diary_template.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/diary_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/journal_routes.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:lifeharness/shared/weather/weather.dart';
import 'package:lifeharness/shared/weather/weather_dao.dart';
import 'package:lifeharness/shared/weather/weather_service.dart';
import 'package:lifeharness/shared/weather/weather_visual.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 1×1 有效 PNG（批2a 插图链测试真实可解码字节·与 note_test 同款）。
const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource(
          {required ImageSource source,
          ImagePickerOptions options = const ImagePickerOptions()}) async =>
      XFile(path);
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// 修复批 #5 变异验证用：首击 save 挂在门闸上，制造真实并发窗口
/// （无门闸时两击间微任务已排空，第二击走既有篇更新路径，防重入测不到）。
class _GatedJournalRepo extends JournalRepository {
  _GatedJournalRepo(super.dao);
  final Completer<void> gate = Completer<void>();
  var calls = 0;
  @override
  Future<JournalEntry> save(JournalEntry e) async {
    calls++;
    if (calls == 1) await gate.future;
    return super.save(e);
  }
}

/// 回顾弹层月份标签。原型 `.dr-month` 是 `YYYY-MM`（如 `2026-10`），
/// 不是中文 `YYYY年M月` —— 2026-10-19 治理批对齐时改的，别改回中文，否则与原型不符。
String _ml(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late JournalRepository jrepo;
  late TodoRepository trepo;
  late EventBus bus;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    jrepo = JournalRepository(JournalDao(db));
    trepo = TodoRepository(TodoDao(db), bus);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  ProviderScope scope(Widget home, {WeatherService? wx}) => ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWithValue(jrepo),
          todoRepositoryProvider.overrideWithValue(trepo),
          diaryTemplateDaoProvider.overrideWithValue(DiaryTemplateDao(db)),
          sharedPreferencesProvider.overrideWithValue(prefs),
          readRepositoryProvider
              .overrideWithValue(ReadRepository(db)), // 阅读 tab 真实化后需库
          // UIUX批（2026-10-12）：搜索半屏纳入日记，笔记源也接测试库
          //（原 noteDaoProvider 默认读 AppDatabase.instance，测试内未开库）。
          noteDaoProvider.overrideWithValue(NoteDao(db)),
          if (wx != null) weatherServiceProvider.overrideWithValue(wx),
        ],
        // **必须关动画**：日记页 FAB 有「呼吸环」无限循环动画（原型 `#fabHalo`
        // 4s 一来回），`pumpAndSettle` 会一直等不到静止而超时。`disableAnimations`
        // 就是原型 `prefers-reduced-motion` 的 Flutter 对应物，组件里已有停环分支。
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: home,
          ),
        ),
      );

  /// §4c-2 之后：顶行的档位/设置/筛选三枚图标**已整行移除**，三者只剩
  /// 「FAB 长按扇形」一条路。测试统一走这里，别再去点顶行。
  Future<void> openDiaryFan(WidgetTester tester) async {
    await tester.longPress(find.byKey(const ValueKey('diary-fan-fab')));
    await tester.pumpAndSettle();
  }

  /// 长按展开扇形后点其中一枚（`label` ∈ {筛选, 设置}）。
  Future<void> tapFan(WidgetTester tester, String label) async {
    await openDiaryFan(tester);
    await tester.tap(find.byKey(ValueKey('diary-fan-$label')));
    await tester.pumpAndSettle();
  }

  /// 经扇形切到指定视图档（替代原 `diary-view` 一键切换）。
  Future<void> switchLayout(WidgetTester tester, String k) async {
    await tapFan(tester, '设置');
    await tester.tap(find.byKey(ValueKey('dset-$k')));
    await tester.pumpAndSettle();
  }

  group('JournalRepository（M0 业务③）', () {
    test('V1.28 一天多篇：save 无 id=新增一篇；带 id=更新该篇', () async {
      final a = await jrepo.save(JournalEntry(
          day: DateTime(2026, 9, 20),
          content: '初稿',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      expect(a.id, isNotNull);
      final b = await jrepo.save(JournalEntry(
          day: DateTime(2026, 9, 20),
          content: '改稿',
          mood: 2,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      expect(b.id, isNot(a.id)); // 新篇而非覆盖
      final all = await jrepo.list();
      expect(all, hasLength(2));
      final day = await jrepo.listByDay(DateTime(2026, 9, 20));
      expect(day.first.content, '改稿'); // 新→旧
      // 带 id 更新指定篇
      final a2 = await jrepo.save(a.copyWith(
          id: a.id, content: '初稿·改', mood: 5, updatedAt: DateTime.now()));
      expect(a2.id, a.id);
      expect(await jrepo.list(), hasLength(2));
      final re = await jrepo.open(a.id!);
      expect(re!.content, '初稿·改');
      expect(re.mood, 5);
    });

    test('V1.28 结构化篇：分节落 journal_sections + content 快照 + 重写', () async {
      final saved = await jrepo.save(JournalEntry(
          day: DateTime(2026, 9, 20),
          templateId: 1,
          sections: const [
            DiarySection(title: '感恩 ①', body: '阳光'),
            DiarySection(title: '感恩 ②', body:'☐ 买牛奶'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      final open = await jrepo.open(saved.id!);
      expect(open!.sections.map((s) => s.title), ['感恩 ①', '感恩 ②']);
      expect(open.content, contains('## 感恩 ①\n阳光'));
      // 快照里的 ☐ 行仍可被 L3 解析
      expect(open.todoLines(), contains('买牛奶'));
      // 更新：分节重写不残留
      final upd = await jrepo.save(saved.copyWith(
          sections: const [DiarySection(title: '感恩 ①', body: '晚风')],
          updatedAt: DateTime.now()));
      expect(upd.id, saved.id);
      final again = await jrepo.open(saved.id!);
      expect(again!.sections, hasLength(1));
      expect(again.sections.first.body, '晚风');
    });

    test('V1.28 模板 DAO：内置种子 2 套 + 自定义增删', () async {
      final dao = DiaryTemplateDao(db);
      final list = await dao.list();
      expect(list, hasLength(2));
      expect(list.every((t) => t.builtin), isTrue);
      expect(list.first.sections, hasLength(3));
      final id = await dao.create(const DiaryTemplate(name: '每日三省', sections: [
        TemplateSection(title: '早晨问自己'),
        TemplateSection(title: '晚间问自己'),
      ]));
      final all = await dao.list();
      expect(all, hasLength(3));
      final custom = all.firstWhere((t) => t.id == id);
      expect(custom.builtin, isFalse);
      expect(custom.sections, hasLength(2));
      await dao.remove(id);
      expect(await dao.list(), hasLength(2));
    });

    test('setMoodOfDay（V1.28）：已有正文篇则新增仅心情篇；再点更新空白篇不叠加（L4）', () async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '正文保留',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await jrepo.setMoodOfDay(DateTime.now(), 3);
      var entries = await jrepo.listByDay(DateTime.now());
      expect(entries, hasLength(2));
      expect(entries.first.mood, 3); // 最新=仅心情篇
      expect(entries.first.content, '');
      expect(entries.last.content, '正文保留'); // 原篇不动
      await jrepo.setMoodOfDay(DateTime.now(), 4); // 复用空白篇
      entries = await jrepo.listByDay(DateTime.now());
      expect(entries, hasLength(2));
      expect(entries.first.mood, 4);

      await jrepo.setMoodOfDay(DateTime(2020, 1, 1), 5);
      final n = await jrepo.byDay(DateTime(2020, 1, 1));
      expect(n!.mood, 5);
      expect(n.content, '');
    });

    test('streak 连续记录天数（今天+昨天+前天=3，中断即止）', () async {
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        final d = now.subtract(Duration(days: i));
        await jrepo.save(JournalEntry(
            day: d, content: 'x', createdAt: now, updatedAt: now));
      }
      // 跳过 3 天前 → 4 天前再写一条不应计入。
      await jrepo.save(JournalEntry(
          day: now.subtract(const Duration(days: 4)),
          content: 'x',
          createdAt: now,
          updatedAt: now));
      expect(await jrepo.streak(), 3);
    });

    test('☐ 待办行与 #标签 解析', () async {
      final e = JournalEntry(
          day: DateTime.now(),
          content: '上午开会\n- ☐ 回复邮件\n☐ 约牙医\n\n#复盘 #运动',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());
      expect(e.todoLines(), ['回复邮件', '约牙医']);
      expect(e.hashTags(), containsAll(['复盘', '运动']));
      final saved = await jrepo.save(e);
      expect(saved.tags, containsAll(['复盘', '运动']));
    });

    test('previewText：结构化快照渲染为「标题：首行」串联·自由书写原样', () {
      final e = JournalEntry(
          day: DateTime.now(),
          content: '## Keep · 做对了什么\n坚持了晨跑\n\n## Problem · 哪里不顺\n熬夜半小时',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());
      expect(e.previewText,
          'Keep · 做对了什么：坚持了晨跑 · Problem · 哪里不顺：熬夜半小时');
      final plain = JournalEntry(
          day: DateTime.now(),
          content: '普通正文',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());
      expect(plain.previewText, '普通正文');
    });

    test('v5 迁移：旧表（无回望列）升级后默认值可读', () async {
      await databaseFactoryFfiNoIsolate.deleteDatabase('jtest_migration_v5.db');
      final db2 = await databaseFactoryFfiNoIsolate
          .openDatabase('jtest_migration_v5.db');
      await db2.execute('''
        CREATE TABLE journal_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entry_date INTEGER NOT NULL,
          mood INTEGER,
          content TEXT NOT NULL,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db2.insert('journal_entries', {
        'entry_date': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'content': '老数据',
        'created_at': 1,
        'updated_at': 1,
      });
      for (final sql in DbSchema.migrations[4]!) {
        await db2.execute(sql);
      }
      final e = JournalEntry.fromRow((await db2.query('journal_entries')).first);
      expect(e.starred, isFalse);
      expect(e.liked, isFalse);
      expect(e.viewCount, 0);

      // V1.28 v6：模板/分节表 + template_id 列 + 内置种子
      for (final sql in DbSchema.migrations[5]!) {
        await db2.execute(sql);
      }
      final tpls = await db2.query('diary_templates');
      expect(tpls, hasLength(2));
      final secs = await db2.query('template_sections');
      expect(secs, hasLength(6));
      final cols =
          await db2.rawQuery('PRAGMA table_info(journal_entries)');
      expect(cols.map((c) => c['name']), contains('template_id'));
      await db2.close();
    });
  });

  group('记录页（原型 p-records · V1.29轮5 记录·X 标题+⇄菜单）', () {
    testWidgets('标题随段变化 · ⇄ 菜单切段 · 心情月历卡 + 写今天入口 + 真实条目卡', (tester) async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          mood: 2,
          content: '今天跑了 5 公里\n#运动',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(const JournalPage()));
      await tester.pumpAndSettle();

      expect(find.text('记录 · 日记'), findsOneWidget);
      expect(find.text('📔 日记'), findsNothing); // 段切换行已移除
      expect(find.byKey(const ValueKey('rec-switch')), findsOneWidget);
      // §4b-4（产品令）：「写今天的日记」入口卡已整行移除（FAB 覆盖同一入口）
      expect(find.text('写今天的日记'), findsNothing);
      expect(find.textContaining('已记录 1 篇'), findsOneWidget);
      expect(find.textContaining('连续记录 1 天'), findsOneWidget);
      expect(find.textContaining('今天跑了 5 公里'), findsOneWidget);

      // ⇄ 菜单：当前项带✓，切「阅读」→ 标题与占位联动。
      await tester.tap(find.byKey(const ValueKey('rec-switch')));
      await tester.pumpAndSettle();
      expect(find.text('影音游'), findsOneWidget);
      await tester.tap(find.text('阅读'));
      await tester.pumpAndSettle();
      expect(find.text('记录 · 阅读'), findsOneWidget);
      // M1批3 后阅读 tab=书架工作台（不再是占位）
      expect(find.text('最近摘录'), findsOneWidget);
      // 回日记段
      await tester.tap(find.byKey(const ValueKey('rec-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日记'));
      await tester.pumpAndSettle();
      expect(find.text('记录 · 日记'), findsOneWidget);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('轮9g 筛选钮=切换钮右侧·底部浮层 全部/☐待办/标签 生效',
        (tester) async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '买猫粮\n☐ 预约疫苗',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await jrepo.save(JournalEntry(
          day: DateTime.now().subtract(const Duration(days: 1)),
          content: '普通一天',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(const JournalPage()));
      await tester.pumpAndSettle();

      // §4c-2：顶行三枚图标已整行移除，筛选只剩 FAB 长按扇形一条路——
      // 这里改为「断言顶行确实没了 + 扇形里能开到筛选」。
      expect(find.byKey(const ValueKey('diary-view')), findsNothing);
      expect(find.byKey(const ValueKey('diary-set')), findsNothing);
      expect(find.byKey(const ValueKey('diary-filter')), findsNothing);

      await tapFan(tester, '筛选');
      expect(find.text('筛选'), findsOneWidget);
      // 批2c：横排胶囊取代了原 48px 竖排 ListTile，键从 `df-opt-<文案>` 改为按筛选值取
      expect(find.byKey(const ValueKey('df-mark-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('df-mark-todo')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('df-mark-todo')));
      await settle5(tester);
      // 仅含 ☐ 待办行的那篇可见
      expect(find.textContaining('买猫粮'), findsOneWidget);
      expect(find.textContaining('普通一天'), findsNothing);
      // 批2c：选中**不关弹层**（要看实时计数），故直接再点「全部」回全量
      expect(find.byKey(const ValueKey('df-count')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('df-mark-all')));
      await settle5(tester);
      expect(find.textContaining('普通一天'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('df-done')));
      await tester.pumpAndSettle();
    });

    testWidgets('INS 卡片流切换键：点 ❤️ 落库 liked', (tester) async {
      final e = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '回望测试',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(const JournalPage()));
      await tester.pumpAndSettle();

      await switchLayout(tester, 'ins');
      await tester.pumpAndSettle();
      // 演示残留批：INS 卡头改读昵称 helper（未设置回落「本地用户」，原硬编 CHIST）。
      expect(find.text('本地用户 · ${_two(DateTime.now().month)}-${_two(DateTime.now().day)}'),
          findsOneWidget);

      await tester.tap(find.byKey(ValueKey('ins-like-${e.id}')));
      await tester.pumpAndSettle();
      final after = await jrepo.byDay(DateTime.now());
      expect(after!.liked, isTrue);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });
  });

  group('日记编辑页（原型 p-diaryEdit · 轮12 富文本+简化头部）', () {
    QuillEditor richCtl(WidgetTester tester) => tester.widget<QuillEditor>(
        find.byKey(const ValueKey('diary-rich-editor')));

    testWidgets('输入正文+选心情+☐ 行 → 富文本落库并同步待办（L3）', (tester) async {
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();

      richCtl(tester).controller.replaceText(0, 0, '晨会定了排期\n☐ 整理评审纪要',
          const TextSelection.collapsed(offset: 15));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mood-main-2'))); // 😌 平静
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('diary-save')));
      await tester.pumpAndSettle();
      // 批2 §4d ⑤：保存钮不再点完就退（要先让用户看见「保存中…→已保存」）⇒ 补一次返回
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final e = await jrepo.byDay(DateTime.now());
      expect(e, isNotNull);
      expect(e!.mood, 2);
      expect(e.kind, 'rich'); // 批2b：自由书写=Delta JSON
      expect(Note.richToPlain(e.content), contains('整理评审纪要'));

      final todos = await trepo.list();
      expect(todos.map((t) => t.title), contains('整理评审纪要'));
      expect(todos.first.quadrant, Quadrant.q2);
      expect(todos.first.tag, '日记');
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('轮12-6/8 头部=日期+天气 chip（批2 起星期全称 · 跨年补年份）·无篇序/字数/搜索',
        (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await settle5(tester);
      // 批2 §6-2：星期由简称「周五」改全称「星期五」（产品令）
      const wds = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
      expect(
          find.text(
              '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${wds[now.weekday - 1]}'),
          findsOneWidget);
      expect(find.text('第 1 篇'), findsNothing);
      expect(find.textContaining(' 字'), findsNothing);
      // 批2 §4d ⑤：底部常驻保存态提示（clean＝「草稿已自动保存」，不再是"无任何状态字样"）
      expect(find.byKey(const ValueKey('diary-save-hint')), findsOneWidget);
      expect(find.text('草稿已自动保存'), findsOneWidget);
      expect(find.text('写日记'), findsNothing);
      expect(find.byIcon(Icons.search), findsNothing);

      await tester.pumpWidget(scope(DiaryEditPage(key: UniqueKey(), day: DateTime(2025, 9, 19))));
      await settle5(tester);
      expect(find.text('2025-09-19 星期五'), findsOneWidget); // 跨年历史篇补年份
    });

    testWidgets('V1.28 打开既有篇=回填+浏览计数；新建篇=空白富文本', (tester) async {
      final e1 = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '已有正文',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(DiaryEditPage(key: UniqueKey(), entryId: e1.id)));
      await tester.pumpAndSettle();
      expect(richCtl(tester).controller.document.toPlainText(), contains('已有正文')); // 回填
      final re = await jrepo.open(e1.id!);
      expect(re!.viewCount, 1); // 打开累计浏览

      await tester.pumpWidget(scope(DiaryEditPage(key: UniqueKey(), day: DateTime(2030, 1, 1))));
      await settle5(tester);
      expect(richCtl(tester).controller.document.toPlainText().trim(), isEmpty); // 新篇空白
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('轮12-1 今日概览草稿默认折叠·点标题行展开·插入正文进富文本', (tester) async {
      await trepo.add(Todo(title: '已完成任务', quadrant: Quadrant.q1, done: true));
      await trepo.add(Todo(title: '未完成任务', quadrant: Quadrant.q3));
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('今日完成 1 · 未完成 1'), findsNothing); // 默认折叠
      await tester.tap(find.byKey(const ValueKey('diary-sum-head')));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日完成 1 · 未完成 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('diary-sum-insert')));
      await tester.pump();
      expect(richCtl(tester).controller.document.toPlainText(),
          contains('【今日概览 · 自动生成】'));
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('V1.28 模板弹层：应用 KPT → 3 分节卡（仍纯文本）· 保存 toast 含节数',
        (tester) async {
      // 加高视口：文档态 ListView 懒构建，保证模板行/分节卡/保存钮全部在树内。
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tpl-open-sheet')));
      await tester.pumpAndSettle();
      expect(find.text('📋 日记模板'), findsOneWidget);
      expect(find.byKey(const ValueKey('tpl-row-2')), findsOneWidget); // KPT 种子
      expect(find.byKey(const ValueKey('tpl-row-free')), findsOneWidget);
      expect(find.byKey(const ValueKey('tpl-del-1')), findsNothing); // 内置不可删
      await tester.tap(find.byKey(const ValueKey('tpl-row-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sec-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('sec-2')), findsOneWidget);
      expect(find.textContaining('3 节 · 各节独立保存'), findsOneWidget);
      expect(find.text('模板：KPT 复盘'), findsOneWidget);
      expect(find.byKey(const ValueKey('diary-rich-editor')), findsNothing); // 结构化无富文本区

      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('sec-0')),
              matching: find.byType(TextField)),
          '坚持了晨跑');
      await tester.tap(find.byKey(const ValueKey('diary-save')));
      // 批2 §4d ⑤：保存留在页内，只给一句「手记已保存」（节数 toast 随退出路径走）
      await tester.pumpAndSettle();
      expect(find.text('手记已保存'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final day = await jrepo.listByDay(DateTime.now());
      expect(day.first.sections, hasLength(3));
      expect(day.first.sections.first.body, '坚持了晨跑');
      expect(day.first.content, contains('## Keep · 做对了什么\n坚持了晨跑'));
      expect(day.first.kind, ''); // 结构化篇回落纯文本
    });

    testWidgets('轮12-9 快捷栏=B/≡/☑/拍照/相册/语音/❝ 直接施加富文本格式',
        (tester) async {
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await settle5(tester);
      final ctl = richCtl(tester).controller;
      ctl.replaceText(0, 0, '加粗我', const TextSelection.collapsed(offset: 3));
      ctl.replaceText(
          0, 0, '', const TextSelection(baseOffset: 0, extentOffset: 3));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('diary-tb-bold')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()),
          contains('"bold":true'));

      ctl.replaceText(3, 0, '', const TextSelection.collapsed(offset: 3));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('diary-tb-task')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()),
          contains('"list":"unchecked"'));
      await tester.tap(find.byKey(const ValueKey('diary-tb-task')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()),
          contains('"list":"checked"'));
      // 无 MD 语法残留
      expect(ctl.document.toPlainText(), isNot(contains('**')));
      expect(ctl.document.toPlainText(), isNot(contains('- ')));
    });
  });

  group('M1批2a · 日记图片附件全链（编辑/列表/INS/全屏）', () {
    test('域协议：图片行剥离/追加可逆 · 预览去路径 · imagePaths 提取 · kind 落库',
        () async {
      const body = '晨跑五公里\n☐ 买鞋';
      final withImgs =
          JournalEntry.appendImageLines(body, ['/a/x.png', '/a/y.png']);
      expect(withImgs, '晨跑五公里\n☐ 买鞋\n\n![图片](/a/x.png)\n![图片](/a/y.png)');
      expect(JournalEntry.bodyWithoutImages(withImgs), body);
      final e = JournalEntry(
          day: DateTime(2026, 9, 22),
          content: withImgs,
          createdAt: DateTime(2026, 9, 22),
          updatedAt: DateTime(2026, 9, 22));
      expect(e.imagePaths, ['/a/x.png', '/a/y.png']);
      expect(e.previewText, isNot(contains('/a/'))); // 展示不露本地路径
      expect(e.todoLines(), contains('买鞋')); // 剥离图片不伤 ☐ 解析
      // 仓储更新链路带 kind（批2b 富文本落库前置）
      final a = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: 'x',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await jrepo.save(a.copyWith(id: a.id, kind: 'rich'));
      expect((await jrepo.open(a.id!))!.kind, 'rich');
    });

    testWidgets('2a-1 相册插图→内嵌 Delta image→落库 kind=rich（轮12 直取来源）',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lhimg2a');
      final docs = Directory.systemTemp.createTempSync('lh_docs2a');
      addTearDown(() {
        // R5b：Image.file 解码句柄释放有 Windows 竞态，temp 目录删除失败容忍（OS 回收）。
        try { tmp.deleteSync(recursive: true); } catch (_) {}
        try { docs.deleteSync(recursive: true); } catch (_) {}
      });
      File(p.join(tmp.path, 'a.png')).writeAsBytesSync(base64Decode(_png1x1));
      ImagePickerPlatform.instance = _FakeImagePicker(p.join(tmp.path, 'a.png'));
      PathProviderPlatform.instance = _FakePathProvider(docs.path);
      await useSurface(tester);

      await tester.pumpWidget(scope(const DiaryEditPage()));
      await settle5(tester);
      final ctl = tester
          .widget<QuillEditor>(
              find.byKey(const ValueKey('diary-rich-editor')))
          .controller;
      ctl.replaceText(0, 0, '正文在前', const TextSelection.collapsed(offset: 4));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('diary-tb-album')));
      await tester.pump();
      // 轮12-2：快捷栏钮直取来源，不再弹 相册/拍照 选择层
      expect(find.byKey(const ValueKey('img-gallery')), findsNothing);
      for (var i = 0;
          i < 10 &&
              !jsonEncode(ctl.document.toDelta().toJson())
                  .contains('"image"');
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
      expect(find.textContaining('![图片]'), findsNothing); // 无 MD 语法露出

      await tester.tap(find.byKey(const ValueKey('diary-save')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute(); // 批2：保存在页内，退出另走返回
      await tester.pumpAndSettle();
      final e = await jrepo.byDay(DateTime.now());
      expect(e!.kind, 'rich');
      expect(e.content, contains('"image"'));
      expect(e.imagePaths, hasLength(1));
      expect(Note.richToPlain(e.content), contains('图片')); // 预览无路径
    });

    testWidgets('2a-1b 旧纯文本带图篇重开=图片转内嵌 embed；清空图后落库无图',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lhimg2a1b');
      addTearDown(() {
        try { tmp.deleteSync(recursive: true); } catch (_) {}
      });
      final img = p.join(tmp.path, 'a.png');
      File(img).writeAsBytesSync(base64Decode(_png1x1));
      final seeded = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: JournalEntry.appendImageLines('正文在前', [img]),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await useSurface(tester);

      await tester.pumpWidget(
          scope(DiaryEditPage(key: UniqueKey(), entryId: seeded.id)));
      await settle5(tester);
      final ctl = tester
          .widget<QuillEditor>(
              find.byKey(const ValueKey('diary-rich-editor')))
          .controller;
      // 迁移：正文段 + image embed（路径原样保留）
      final hasImg = ctl.document.toDelta().toJson().any((op) =>
          op['insert'] is Map && (op['insert'] as Map)['image'] == img);
      expect(hasImg, isTrue);
      expect(find.textContaining('![图片]'), findsNothing);

      // 键盘删除（选区清空 embed）→ 保存后不再带图
      ctl.replaceText(4, ctl.document.length - 5, '',
          const TextSelection.collapsed(offset: 4));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('diary-save')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute(); // 批2：保存在页内，退出另走返回
      await tester.pumpAndSettle();
      final e = await jrepo.byDay(DateTime.now());
      expect(e!.imagePaths, isEmpty);
      expect(Note.richToPlain(e.content), contains('正文在前'));
    });

    testWidgets('2a-2 ＋拍照钮直取相机源·防抖自动存草稿带图', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lhimg2a2');
      final docs = Directory.systemTemp.createTempSync('lh_docs2a2');
      addTearDown(() {
        // R5b：Image.file 解码句柄释放有 Windows 竞态，temp 目录删除失败容忍（OS 回收）。
        try { tmp.deleteSync(recursive: true); } catch (_) {}
        try { docs.deleteSync(recursive: true); } catch (_) {}
      });
      File(p.join(tmp.path, 'a.png')).writeAsBytesSync(base64Decode(_png1x1));
      ImagePickerPlatform.instance = _FakeImagePicker(p.join(tmp.path, 'a.png'));
      PathProviderPlatform.instance = _FakePathProvider(docs.path);
      await useSurface(tester);

      await tester.pumpWidget(scope(const DiaryEditPage()));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('diary-tb-camera')));
      await tester.pump();
      expect(find.byKey(const ValueKey('img-gallery')), findsNothing); // 跳过弹层
      final ctl = tester
          .widget<QuillEditor>(
              find.byKey(const ValueKey('diary-rich-editor')))
          .controller;
      for (var i = 0;
          i < 10 &&
              !jsonEncode(ctl.document.toDelta().toJson())
                  .contains('"image"');
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
      // 自动存草稿链：图片随防抖落库（不点保存）
      await tester.pump(const Duration(milliseconds: 1200));
      final e = await jrepo.byDay(DateTime.now());
      expect(e!.imagePaths, hasLength(1));
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    /// 两条真 1×1 PNG + 一篇带图带待办的日记（INS/列表两用例共用装配）。
    Future<(JournalEntry, String, String)> seedImgEntry() async {
      final tmp = Directory.systemTemp.createTempSync('lhimg2a3');
      final a = p.join(tmp.path, 'a.png');
      final b = p.join(tmp.path, 'b.png');
      File(a).writeAsBytesSync(base64Decode(_png1x1));
      File(b).writeAsBytesSync(base64Decode(_png1x1));
      addTearDown(() {
        try { tmp.deleteSync(recursive: true); } catch (_) {}
      });
      final e = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '看图\n☐ 买水\n\n![图片]($a)\n![图片]($b)',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      return (e, a, b);
    }

    testWidgets('2a-3 INS 卡网格点图看大图 + 关联小图标展开 + ⛶ 全屏浏览',
        (tester) async {
      final (e, a, _) = await seedImgEntry();
      await useSurface(tester);
      await tester.pumpWidget(scope(const JournalPage()));
      await settle5(tester);
      await switchLayout(tester, 'ins'); // 切 INS
      await settle5(tester);

      expect(find.byKey(ValueKey('ins-img-${e.id}-0')), findsOneWidget);
      expect(find.byKey(ValueKey('ins-img-${e.id}-1')), findsOneWidget);
      expect(find.textContaining(a), findsNothing); // 卡面不露路径

      // 点缩略图 → 全屏黑底大图（再点任意处关）
      await tester.tap(find.byKey(ValueKey('ins-img-${e.id}-0')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('note-img-light')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-img-light')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('note-img-light')), findsNothing);

      // 轮12-11：关联信息=小图标（全屏钮左侧）·点击展开/收起
      expect(find.textContaining('本页关联'), findsNothing);
      await tester.tap(find.byKey(ValueKey('ins-ref-${e.id}')));
      await settle5(tester);
      expect(find.textContaining('本页关联 · ☑ 1 个待办同步'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('ins-ref-${e.id}')));
      await settle5(tester);
      expect(find.textContaining('本页关联'), findsNothing);

      await tester.tap(find.byKey(ValueKey('ins-full-${e.id}')));
      await settle5(tester);
      expect(find.byKey(ValueKey('diary-full-${e.id}')), findsOneWidget);
      expect(find.text('看图\n☐ 买水'), findsOneWidget); // 全屏正文（弹层那份·剥离图片行）
      await tester.tap(find.byKey(ValueKey('diary-full-${e.id}')),
          warnIfMissed: false);
      await settle5(tester);
      expect(find.byKey(ValueKey('diary-full-${e.id}')), findsNothing);
    });

    testWidgets('2a-4 列表行缩略点大图 + 关联小图标展开 + 预览去路径', (tester) async {
      final (e, a, b) = await seedImgEntry();
      await useSurface(tester);
      await tester.pumpWidget(scope(const JournalPage()));
      await settle5(tester);

      expect(find.byKey(ValueKey('jimg-${e.id}-0')), findsOneWidget);
      expect(find.byKey(ValueKey('jimg-${e.id}-1')), findsOneWidget);
      expect(find.textContaining(a), findsNothing);
      expect(find.textContaining(b), findsNothing);
      expect(find.textContaining('看图'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('jimg-${e.id}-0')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('note-img-light')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-img-light')));
      await settle5(tester);

      // 轮12-11：列表行右下角小图标（保存时间左侧）·点击展开明细
      expect(find.textContaining('本页关联'), findsNothing);
      await tester.tap(find.byKey(ValueKey('jref-${e.id}')));
      await settle5(tester);
      expect(find.textContaining('本页关联 · ☑ 1 个待办同步'), findsOneWidget);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });
  });

  group('V1.29轮13 · 日记删除 + 长按批量选中', () {
    testWidgets('13-1 编辑页删除钮=确认弹层→落库删除→返回；新篇不显示钮',
        (tester) async {
      final e = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '要删掉的一篇',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await useSurface(tester);

      // 新建篇（未落库）无删除钮
      await tester.pumpWidget(scope(DiaryEditPage(key: UniqueKey())));
      await settle5(tester);
      expect(find.byKey(const ValueKey('diary-del')), findsNothing);

      await tester.pumpWidget(
          scope(DiaryEditPage(key: UniqueKey(), entryId: e.id)));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('diary-del')));
      await settle5(tester);
      expect(find.text('删除这篇日记？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('diary-del-ok')));
      await tester.pumpAndSettle();
      expect(await jrepo.open(e.id!), isNull);
      expect(await jrepo.list(), isEmpty);
      // 语义断链批（2026-10-12）：软删进回收站（原硬删不可恢复）；恢复回原位。
      expect((await jrepo.trashed()).map((x) => x.id), contains(e.id!));
      await jrepo.restoreJournal(e.id!);
      expect((await jrepo.list()).map((x) => x.id), contains(e.id!));
    });

    testWidgets('13-2 列表长按→已选底栏→多选→批量删除确认落库', (tester) async {
      final e1 = await jrepo.save(JournalEntry(
          day: DateTime.now().subtract(const Duration(days: 1)),
          content: '旧的一天',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      final e2 = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '今天的一篇',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await useSurface(tester);
      await tester.pumpWidget(scope(const JournalPage()));
      await settle5(tester);

      expect(find.byKey(const ValueKey('diary-sel-bar')), findsNothing);
      await tester.longPress(find.textContaining('旧的一天'));
      await settle5(tester);
      expect(find.byKey(const ValueKey('diary-sel-bar')), findsOneWidget);
      expect(find.text('已选 1 篇'), findsOneWidget);
      expect(find.byKey(ValueKey('jsel-${e1.id}')), findsOneWidget);

      await tester.tap(find.textContaining('今天的一篇'));
      await settle5(tester);
      expect(find.text('已选 2 篇'), findsOneWidget);
      expect(find.byKey(ValueKey('jsel-${e2.id}')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('diary-del-batch')));
      await settle5(tester);
      expect(find.text('删除选中的 2 篇日记？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('diary-del-batch-ok')));
      await tester.pumpAndSettle();
      expect(await jrepo.open(e1.id!), isNull);
      expect(await jrepo.open(e2.id!), isNull);
      // 语义断链批：批量删除同样进回收站（两篇都在册）。
      expect((await jrepo.trashed()).map((x) => x.id),
          containsAll([e1.id!, e2.id!]));
      expect(find.byKey(const ValueKey('diary-sel-bar')), findsNothing);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('13-3 INS 卡长按进多选·点卡切换勾选·✕退出', (tester) async {
      final e = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: 'INS 长按测试',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await useSurface(tester);
      await tester.pumpWidget(scope(const JournalPage()));
      await settle5(tester);
      await switchLayout(tester, 'ins');
      await settle5(tester);

      await tester.longPress(find.text('本地用户 · ${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}'));
      await settle5(tester);
      expect(find.byKey(const ValueKey('diary-sel-bar')), findsOneWidget);
      expect(find.byKey(ValueKey('insel-${e.id}')), findsOneWidget);

      // 取消勾选→空集自动退出多选
      await tester.tap(find.byKey(ValueKey('insel-${e.id}')),
          warnIfMissed: false);
      await settle5(tester);
      expect(find.byKey(const ValueKey('diary-sel-bar')), findsNothing);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });
  });

  group('M1批2c · 回顾弹层（心情趋势+词云+去年本月）', () {
    testWidgets('2c-1 📊 回顾钮开底部弹层：月标签/趋势/图例/摘要/词云/去年本月 + 切月',
        (tester) async {
      final now = DateTime.now();
      // 本月 3 篇（带心情 + 高频词「跑步」重复）
      for (var i = 0; i < 3; i++) {
        await jrepo.save(JournalEntry(
            day: DateTime(now.year, now.month, 1 + i),
            mood: i + 1,
            content: '今天跑步了\n跑步让我开心\n明天继续跑步',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()));
      }
      // 去年同月 1 篇
      await jrepo.save(JournalEntry(
          day: DateTime(now.year - 1, now.month, 5),
          content: '一年前的今天去爬山了',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await useSurface(tester);
      await tester.pumpWidget(scope(const JournalPage()));
      await settle5(tester);

      await tester.tap(find.text('📊 回顾'));
      await settle5(tester);
      expect(find.text('回顾'), findsOneWidget);
      expect(find.text(_ml(now)), findsOneWidget);
      expect(find.byKey(const ValueKey('dr-trend')), findsOneWidget);
      expect(find.byKey(const ValueKey('dr-legend')), findsOneWidget);
      expect(find.textContaining('本月记录 3 篇'), findsOneWidget);
      // 词云：中文 2-gram 高频词（跑步=3 次 → 中号字）
      expect(find.text('跑步'), findsOneWidget);
      // 去年本月卡（弹层与背后列表各一份预览 → findsWidgets）
      expect(find.text('那年今日'), findsOneWidget);
      expect(find.text('1 年前 · ${now.month.toString().padLeft(2, '0')}-05'), findsOneWidget);
      expect(find.textContaining('一年前的今天'), findsWidgets);

      // 切到上月再回来：月标签联动、空月摘要兜底
      await tester.tap(find.byKey(const ValueKey('dr-prev')));
      await settle5(tester);
      final prev = DateTime(now.year, now.month - 1);
      expect(find.text(_ml(prev)), findsOneWidget);
      expect(find.textContaining('本月还没有记录'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dr-next')));
      await settle5(tester);
      expect(find.text(_ml(now)), findsOneWidget);
    });

    testWidgets('2c-2 治理批口径：卡片去边框 / 图例只三档 / 词云标题 / 趋势高 56',
        (tester) async {
      final now = DateTime.now();
      await jrepo.save(JournalEntry(
          day: DateTime(now.year, now.month, 3),
          mood: 4,
          content: '骑车去湖边',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await useSurface(tester);
      await tester.pumpWidget(scope(const JournalPage()));
      await settle5(tester);
      await tester.tap(find.text('📊 回顾'));
      await settle5(tester);

      // ① 原型文案「词云 · 本月高频」（原实现写的是「高频词云」）
      expect(find.text('词云 · 本月高频'), findsOneWidget);
      expect(find.text('高频词云'), findsNothing);

      // ② 心情图例只三档（原型治理件明确删掉那一排 7 枚连续表情）
      final legend = find.byKey(const ValueKey('dr-legend'));
      expect(legend, findsOneWidget);
      expect(
          find.descendant(of: legend, matching: find.byType(Text)),
          findsNWidgets(3),
          reason: '图例应只低落/一般/愉悦三档，多出来说明又退回 7 枚全列');

      // ③ 趋势图高 56（原型 h-14）；原实现 96 太高
      expect(tester.getSize(find.byKey(const ValueKey('dr-trend'))).height, 56);

      // ④ 卡片去边框：原实现 `Border.all(cardBorder)` 是治理件点名要删的。
      //    直接扫渲染层 DecoratedBox 的 BoxDecoration 里有没有 border。
      final cards = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .map((c) => c.decoration as BoxDecoration)
          .where((d) => d.borderRadius == BorderRadius.circular(16));
      expect(cards, isNotEmpty, reason: '没找到卡片，断言失效');
      for (final d in cards) {
        expect(d.border, isNull, reason: '治理批要求卡片无边框（改极淡阴影浮起）');
      }

      // ⑤ 月份标签是 YYYY-MM 而不是中文年月
      expect(find.text(_ml(now)), findsOneWidget);
      expect(find.text('${now.year}年${now.month}月'), findsNothing);
      await drainLogTimer(tester);
    });
  });

  group('M1批2e · 天气快照（当天自动抓+缓存 · 手动覆盖 · 无网静默）', () {
    const city = WeatherCity(name: '杭州', lat: 30.29, lon: 120.16);

    Map<String, dynamic> wxJson(String day, {int code = 0}) => {
          'daily': {
            'time': [day],
            'weather_code': [code],
            'temperature_2m_max': [30.4],
            'temperature_2m_min': [20.2],
          },
        };

    Future<void> setCity(String? v) async {
      SharedPreferences.setMockInitialValues(
          v == null ? {} : {'lh.weather_city': v});
      prefs = await SharedPreferences.getInstance();
    }

    // sqflite ffi 走真实事件循环：等某 finder 出现（60ms 步进·runAsync 放行）
    Future<void> waitFinder(WidgetTester tester, Finder f,
        {int times = 15}) async {
      for (var i = 0; i < times; i++) {
        if (f.evaluate().isNotEmpty) return;
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
    }

    test('2e-0 域：WeatherCity 编码往返 · weatherText 口径 · 七选项代表码', () {
      expect(WeatherCity.decode(WeatherCity.encode(city))?.lat, 30.29);
      expect(WeatherCity.decode(''), isNull);
      expect(WeatherCity.decode('a|b|c'), isNull);
      expect(weatherText(0, tmax: 30.4, tmin: 20.2), '晴 20~30°');
      expect(weatherText(61, tmax: 18.2, compact: true), '小雨 18°');
      expect(weatherText(2), '多云');
      expect(kWeatherOptions.map(weatherLabel).join(),
          '晴多云阴小雨小雪雾雷阵雨');
    });

    test('2e-0b WeatherService：只抓当天 · 缓存日一次 · 换城市重抓 · 无网 null', () async {
      var calls = 0;
      final svc = WeatherService(WeatherDao(db), fetch: (uri) async {
        calls++;
        return (json: wxJson(WeatherDao.dayKey(DateTime.now())), err: null);
      });
      final today = DateTime.now();
      final w = await svc.day(today, city);
      expect(w?.code, 0);
      expect(w?.tmax, 30.4);
      expect(calls, 1);
      await svc.day(today, city); // 命中缓存
      expect(calls, 1);
      await svc.day(today, const WeatherCity(name: '北京', lat: 40, lon: 116));
      expect(calls, 2); // 城市变更失效重抓
      expect(await svc.day(today.subtract(const Duration(days: 1)), city), isNull);
      expect(calls, 2); // 历史不查（只存当时）
      final offline = WeatherService(WeatherDao(db),
          fetch: (u) async => (json: null, err: 'socket'));
      expect(await offline.day(DateTime(2020, 1, 1), city), isNull);
      expect(await db.query('weather_daily'), hasLength(1)); // 换城市 replace 同日行
    });

    test('2e-0c searchCity：解析命中 · 空查询静默 · 取数失败带 err（≠无匹配）', () async {
      final svc = WeatherService(WeatherDao(db), fetch: (uri) async {
        if (uri.host != 'geocoding-api.open-meteo.com') {
          return (json: null, err: null);
        }
        return (
          json: {
            'results': [
              {'name': '杭州', 'latitude': 30.29, 'longitude': 120.16, 'admin1': '浙江', 'country': '中国'},
              {'name': '杭州湾', 'latitude': 30.1, 'longitude': 121.0},
            ]
          },
          err: null
        );
      });
      final r = await svc.searchCity('杭州');
      expect(r.err, isNull);
      expect(r.hits, hasLength(2));
      expect(r.hits.first.label, '杭州 · 浙江');
      expect((await svc.searchCity('  ')).hits, isEmpty);
      final bad =
          WeatherService(WeatherDao(db), fetch: (u) async => (json: null, err: 'socket'));
      final failed = await bad.searchCity('上海');
      expect(failed.hits, isEmpty);
      expect(failed.err, 'socket'); // 无网不是「查无此城」
    });

    test('2e-0d repo：save 落天气字段 · attachWeather 直写不打乱 updated_at', () async {
      final u0 = DateTime(2026, 9, 22, 8);
      final e = await jrepo.save(JournalEntry(
          day: DateTime(2026, 9, 20),
          content: '正文',
          weatherCode: 61,
          tempMax: 18.5,
          tempMin: 12.1,
          createdAt: u0,
          updatedAt: u0));
      var re = await jrepo.open(e.id!);
      expect(re!.weatherCode, 61);
      expect(re.tempMax, 18.5);
      expect(re.weatherManual, isFalse);
      final before = re.updatedAt; // save 会把 updated_at 刷成 now，以落库值起算
      await jrepo.attachWeather(e.id!, code: 0, tmax: 30.4, manual: true);
      re = await jrepo.open(e.id!);
      expect(re!.weatherCode, 0);
      expect(re.weatherManual, isTrue);
      expect(re.updatedAt, before); // 快照直写不碰更新时间
    });

    test('2e-0e v11 迁移：journal 加天气四列 + weather_daily 建表 · 旧行默认读', () async {
      const name = 'jtest_migration_v11.db';
      await databaseFactoryFfiNoIsolate.deleteDatabase(name);
      final db2 = await databaseFactoryFfiNoIsolate.openDatabase(name);
      await db2.execute('''
        CREATE TABLE journal_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entry_date INTEGER NOT NULL,
          mood INTEGER,
          content TEXT NOT NULL,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          starred INTEGER NOT NULL DEFAULT 0,
          liked INTEGER NOT NULL DEFAULT 0,
          view_count INTEGER NOT NULL DEFAULT 0,
          template_id INTEGER,
          kind TEXT NOT NULL DEFAULT ''
        )
      ''');
      await db2.insert('journal_entries',
          {'entry_date': 1, 'content': '老数据', 'created_at': 1, 'updated_at': 1});
      for (final sql in DbSchema.migrations[10]!) {
        await db2.execute(sql);
      }
      final cols = await db2.rawQuery('PRAGMA table_info(journal_entries)');
      expect(
          cols.map((c) => c['name']),
          containsAll(
              ['weather_code', 'temp_max', 'temp_min', 'weather_manual']));
      final e = JournalEntry.fromRow((await db2.query('journal_entries')).first);
      expect(e.weatherCode, isNull);
      expect(e.weatherManual, isFalse);
      expect(await db2.query('weather_daily'), isEmpty); // 新表已建
      await db2.close();
    });

    testWidgets('2e-1 当天开新篇=自动抓一次：chip 显「晴 20~30°」+条目落库+缓存行',
        (tester) async {
      await setCity(WeatherCity.encode(city));
      var calls = 0;
      final svc = WeatherService(WeatherDao(db), fetch: (uri) async {
        calls++;
        return (json: wxJson(WeatherDao.dayKey(DateTime.now())), err: null);
      });
      await tester.pumpWidget(scope(DiaryEditPage(day: DateTime.now()), wx: svc));
      await settle5(tester);
      expect(find.byKey(const ValueKey('diary-wx-chip')), findsOneWidget);
      await waitFinder(tester, find.text('晴 20~30°')); // 自动抓链落定
      expect(calls, 1);
      // 修复批 #6（拍板「打开不落库」）：自动抓只进页内态，不再落空篇幽灵行
      expect(await jrepo.listByDay(DateTime.now()), isEmpty);
      final cache = await db.query('weather_daily');
      expect(cache, hasLength(1));
      expect(cache.first['city'], '杭州');
      // 打字 → 防抖自动存：快照随首次落库一并写入
      final ctl = tester.widget<QuillEditor>(
              find.byKey(const ValueKey('diary-rich-editor')))
          .controller;
      ctl.replaceText(0, 0, '今天不错',
          const TextSelection.collapsed(offset: 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000)); // 推过 900ms 防抖
      await tester.pump();
      final day = await jrepo.listByDay(DateTime.now());
      expect(day, hasLength(1));
      expect(day.first.weatherCode, 0);
      expect(day.first.tempMax, 30.4);
      expect(Note.richToPlain(day.first.content), contains('今天不错'));
      await drainLogTimer(tester); // 自动存落库 → AppLog 节流 Timer 需排空
    });

    testWidgets('2e-2 点 chip 手动覆盖：落库 manual=1 · 重开不再自动抓 · 恢复自动',
        (tester) async {
      await setCity(WeatherCity.encode(city));
      var calls = 0;
      WeatherService svc() => WeatherService(WeatherDao(db), fetch: (uri) async {
            calls++;
            return (json: wxJson(WeatherDao.dayKey(DateTime.now())), err: null);
          });
      await tester.pumpWidget(scope(DiaryEditPage(day: DateTime.now()), wx: svc()));
      await settle5(tester);
      await waitFinder(tester, find.text('晴 20~30°')); // 先让自动抓落定
      await tester.tap(find.byKey(const ValueKey('diary-wx-chip')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('wx-grid')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wx-opt-3'))); // 阴
      await settle5(tester);
      expect(find.text('阴 20~30° ·手动'), findsOneWidget);
      var e = (await jrepo.listByDay(DateTime.now())).first;
      expect(e.weatherCode, 3);
      expect(e.weatherManual, isTrue);
      expect(calls, 1); // 手动后未被自动覆盖
      // 恢复自动：弹层出现恢复钮 → 重抓落回
      await tester.tap(find.byKey(const ValueKey('diary-wx-chip')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('wx-restore')));
      await settle5(tester);
      await waitFinder(tester, find.text('晴 20~30°'));
      e = (await jrepo.listByDay(DateTime.now())).first;
      expect(e.weatherCode, 0);
      expect(e.weatherManual, isFalse);
      expect(calls, 1); // 恢复自动命中当日缓存=不再触网
    });

    testWidgets('2e-3 城市未设置：不触网不抓，chip 留空壳不阻塞', (tester) async {
      await setCity(null);
      await tester.pumpWidget(scope(DiaryEditPage(day: DateTime.now())));
      await settle5(tester);
      expect(find.text('天气'), findsOneWidget); // 空壳入口仍在
      expect(find.byKey(const ValueKey('diary-rich-editor')), findsOneWidget);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('2e-3b 有城市但无网：假 fetch 返回 null=静默，chip 空壳不写缓存',
        (tester) async {
      await setCity(WeatherCity.encode(city));
      await tester.pumpWidget(scope(
          DiaryEditPage(day: DateTime.now()),
          wx: WeatherService(WeatherDao(db),
              fetch: (u) async => (json: null, err: 'socket'))));
      await settle5(tester);
      expect(find.text('天气'), findsOneWidget);
      expect(await db.query('weather_daily'), isEmpty);
    });
  });

  group('M1 修复批 · 日记编辑能力六刀（评估件 20261012 高危 #1~#6）', () {
    QuillEditor richCtlOf(WidgetTester tester) => tester.widget<QuillEditor>(
        find.byKey(const ValueKey('diary-rich-editor')));

    Finder secField(int i) => find.descendant(
        of: find.byKey(ValueKey('sec-$i')), matching: find.byType(TextField));

    Future<void> openTpl(WidgetTester tester, String rowKey) async {
      await tester.tap(find.byKey(const ValueKey('tpl-open-sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(rowKey)));
      await tester.pumpAndSettle();
    }

    testWidgets('#1 P0 重开结构化模板篇：回填模板名与分节标题/正文，不越界',
        (tester) async {
      await useSurface(tester);
      final saved = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          templateId: 2,
          kind: '',
          content: '',
          sections: const [
            DiarySection(title: 'Keep · 做对了什么', body: '晨跑了三公里'),
            DiarySection(title: 'Problem · 哪里不顺', body: '睡晚了'),
            DiarySection(title: 'Try · 下一步怎么改', body: '十一点前放下手机'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(
          scope(DiaryEditPage(key: UniqueKey(), entryId: saved.id)));
      await tester.pumpAndSettle(); // 修复前：此处 RangeError（空 sections 下标越界）
      expect(find.textContaining('KPT 复盘 · 3 节'), findsOneWidget); // 真名回填
      expect(find.text('Keep · 做对了什么'), findsOneWidget);
      expect(find.text('Try · 下一步怎么改'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(secField(0))
              .controller!
              .text,
          '晨跑了三公里');
      await drainLogTimer(tester);

      // 回落：模板已删（id 查无）→ 用既有篇存储分节回填，同样不炸
      final orphan = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          templateId: 999,
          kind: '',
          content: '',
          sections: const [
            DiarySection(title: '自留节甲', body: '甲内容'),
            DiarySection(title: '自留节乙', body: '乙内容'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(
          scope(DiaryEditPage(key: UniqueKey(), entryId: orphan.id)));
      await tester.pumpAndSettle();
      expect(find.textContaining('模板 · 2 节'), findsOneWidget);
      expect(find.text('自留节甲'), findsOneWidget);
      expect(find.text('自留节乙'), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('#2 结构化分节输入=防抖自动存（不等手动保存）', (tester) async {
      await useSurface(tester);
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();
      await openTpl(tester, 'tpl-row-2'); // KPT
      await tester.enterText(secField(0), '自动存进首节');
      await tester.pump(const Duration(milliseconds: 1000)); // 推过 900ms 防抖
      await tester.pump();
      final day = await jrepo.listByDay(DateTime.now());
      expect(day, hasLength(1));
      expect(day.first.sections.first.body, '自动存进首节');
      await drainLogTimer(tester);
    });

    testWidgets('#3 打字后立即返回=PopScope flush 尾稿不丢（<900ms 窗口）',
        (tester) async {
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();
      richCtlOf(tester).controller.replaceText(
          0, 0, '临走前打的几行字', const TextSelection.collapsed(offset: 8));
      await tester.pump(); // 置脏＋排防抖（尚未到期）
      // 系统返回（home 路由无 AppBar 返回钮，pageBack 不可用）→
      // maybePop → PopScope 拦截 → flush 尾稿 → 强退
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final day = await jrepo.listByDay(DateTime.now());
      expect(day, hasLength(1));
      expect(Note.richToPlain(day.first.content), contains('临走前打的几行字'));
      await drainLogTimer(tester);
    });

    testWidgets('#4 切模板不弃稿：按节顺序搬/溢出并末节/自由合并/富文进首节',
        (tester) async {
      await useSurface(tester);
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await tester.pumpAndSettle();

      // 自由书写写字 → KPT：富文本纯文进首节
      richCtlOf(tester).controller.replaceText(
          0, 0, '自由的一段', const TextSelection.collapsed(offset: 5));
      await tester.pump();
      await openTpl(tester, 'tpl-row-2');
      expect(tester.widget<TextField>(secField(0)).controller!.text,
          '自由的一段');

      // 再写两节 → 感恩三件事：按节顺序搬，原首节内容进新首节
      await tester.enterText(secField(0), '甲节内容');
      await tester.pump();
      await tester.enterText(secField(1), '乙节内容');
      await tester.pump();
      await openTpl(tester, 'tpl-row-1'); // 感恩三件事（3 节）
      expect(tester.widget<TextField>(secField(0)).controller!.text, '甲节内容');
      expect(tester.widget<TextField>(secField(1)).controller!.text, '乙节内容');
      expect(tester.widget<TextField>(secField(2)).controller!.text, isEmpty);

      // 3 节 → 2 节模板不存在，改走 →自由书写：合并为一段替换富文本（不重复叠加）
      await tester.enterText(secField(2), '丙节内容');
      await tester.pump();
      await openTpl(tester, 'tpl-row-free');
      final plain = richCtlOf(tester).controller.document.toPlainText();
      expect(plain, contains('甲节内容'));
      expect(plain, contains('乙节内容'));
      expect(plain, contains('丙节内容'));
      expect('甲节内容'.allMatches(plain), hasLength(1)); // 往返不叠加
    });

    testWidgets('#5 保存钮连点两下=只落一篇（防重入·门闸制造并发窗口）',
        (tester) async {
      final gated = _GatedJournalRepo(JournalDao(db));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWithValue(gated),
          todoRepositoryProvider.overrideWithValue(trepo),
          diaryTemplateDaoProvider.overrideWithValue(DiaryTemplateDao(db)),
          sharedPreferencesProvider.overrideWithValue(prefs),
          readRepositoryProvider.overrideWithValue(ReadRepository(db)),
        ],
        child: MaterialApp(home: DiaryEditPage(key: UniqueKey())),
      ));
      await tester.pumpAndSettle();
      richCtlOf(tester).controller.replaceText(
          0, 0, '只此一篇', const TextSelection.collapsed(offset: 4));
      await tester.pump();
      // 第一击：挂起在门闸前（_persist 未归，_existing 仍无 id）
      await tester.tap(find.byKey(const ValueKey('diary-save')),
          warnIfMissed: false);
      await tester.pump(); // 推进到 save 门闸挂起点
      expect(gated.calls, 1);
      // 第二击：无护栏＝并发第二插（两篇）；有护栏＝被 _saving 拦下
      await tester.tap(find.byKey(const ValueKey('diary-save')),
          warnIfMissed: false);
      await tester.pump();
      gated.gate.complete(); // 放行第一击
      await tester.pumpAndSettle();
      expect(await jrepo.list(), hasLength(1));
      await drainLogTimer(tester);
    });

    testWidgets('#6 打开抓天气不落库＋无稿退出零残留（幽灵篇不再生成）',
        (tester) async {
      const city = WeatherCity(name: '杭州', lat: 30.29, lon: 120.16);
      SharedPreferences.setMockInitialValues(
          {'lh.weather_city': WeatherCity.encode(city)});
      prefs = await SharedPreferences.getInstance(); // scope() 读外层变量，同 2e 组 setCity 手法
      final wx = WeatherService(WeatherDao(db),
          fetch: (uri) async => (
                json: {
                  'daily': {
                    'time': [WeatherDao.dayKey(DateTime.now())],
                    'weather_code': [0],
                    'temperature_2m_max': [30.4],
                    'temperature_2m_min': [20.2],
                  },
                },
                err: null
              ));
      await tester.pumpWidget(scope(DiaryEditPage(key: UniqueKey()), wx: wx));
      await settle5(tester);
      // 打开即抓但零落库
      expect(await jrepo.list(), isEmpty);
      // 无稿退出（系统返回）：不 flush 不残留
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await jrepo.list(), isEmpty);
    });
  });

  group('UIUX/流畅批 · 日记交互与列表（2026-10-12 评估件 §四）', () {
    /// 路由化 pump：context.push('/journal/edit') 需 GoRouter（scope 的裸 MaterialApp 推不了栈）。
    Future<void> pumpRouted(WidgetTester tester) async {
      final router =
          GoRouter(routes: [...journalShellRoutes(), ...journalPageRoutes()]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWithValue(jrepo),
          todoRepositoryProvider.overrideWithValue(trepo),
          diaryTemplateDaoProvider.overrideWithValue(DiaryTemplateDao(db)),
          sharedPreferencesProvider.overrideWithValue(prefs),
          readRepositoryProvider.overrideWithValue(ReadRepository(db)),
          noteDaoProvider.overrideWithValue(NoteDao(db)),
        ],
        // 同 `scope()`：关动画，否则呼吸环的无限循环让 `settle5` 永远等不到静止。
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ));
      router.go('/journal');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('U1 月历色条=「点色条看当天」：有篇日直开既有篇', (tester) async {
      final now = DateTime.now();
      final e = await jrepo.save(JournalEntry(
          day: DateTime(now.year, now.month, 5),
          mood: 5,
          content: '公园野餐真开心',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await pumpRouted(tester);

      await tester.tap(find.byKey(const ValueKey('moodbar-5')));
      await settle5(tester);
      expect(find.byType(DiaryEditPage), findsOneWidget);
      // 既有篇回填（原行为=一律新建该日 N+1 篇，与脚注「点色条看当天」相悳）；
      // 富文本正文不在 Text 树，断言走 Quill 文档（同「打开既有篇=回填」用例手法）。
      expect(_richOf(tester).controller.document.toPlainText(),
          contains('公园野餐真开心'));
      expect(e.id, isNotNull);
      await drainLogTimer(tester); // 打开既有篇落浏览计数 → AppLog Timer
    });

    testWidgets('U2 色条无篇日仍可点：整格 36px 热区（原无心情日 ~4px 点不中）',
        (tester) async {
      await pumpRouted(tester);
      final bar = find.byKey(const ValueKey('moodbar-10'));
      expect(tester.getRect(bar).height, 36, reason: '热区=整格高度');
      await tester.tap(bar);
      await settle5(tester);
      expect(find.byType(DiaryEditPage), findsOneWidget); // 新建入口保留
      await drainLogTimer(tester);
    });

    testWidgets('U3 回顾弹层月份切换有界：禁未来（连点›停当月）', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(scope(const JournalPage()));
      await settle5(tester);
      await tester.tap(find.text('📊 回顾'));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('dr-next')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('dr-next')));
      await settle5(tester);
      expect(find.text(_ml(now)), findsOneWidget,
          reason: '当月=上界，再点不得越界');
      // disabled 钮仍有 RenderBox（hitTestable 不为空），断言 onTap 已置空。
      // 2026-10-19 治理对齐：月份钮从 `IconButton`（48×48）换成原型 `.dr-navbtn`
      // 的 `InkResponse`（32×32 圆角 10），这里同步断言载体。
      expect(
          tester.widget<InkResponse>(find.byKey(const ValueKey('dr-next'))).onTap,
          isNull,
          reason: '上界处禁用›（对齐原型 drMonth off≤0）');
      await drainLogTimer(tester);
    });

    testWidgets('U4 趋势柱逐柱可点：命中日号开该篇（原整块 CustomPaint 不可点）',
        (tester) async {
      final now = DateTime.now();
      await jrepo.save(JournalEntry(
          day: DateTime(now.year, now.month, 15),
          mood: 4,
          content: '山顶的日出真美',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await pumpRouted(tester);
      await tester.tap(find.text('📊 回顾'));
      await settle5(tester);

      final rect = tester.getRect(find.byKey(const ValueKey('dr-trend')));
      final days = DateTime(now.year, now.month + 1, 0).day;
      // 15 日槽位中心：(15-1+0.5)/days
      final dx = rect.left + rect.width * 14.5 / days;
      await tester.tapAt(Offset(dx, rect.center.dy));
      await settle5(tester);
      expect(find.byType(DiaryEditPage), findsOneWidget);
      expect(_richOf(tester).controller.document.toPlainText(),
          contains('山顶的日出真美'));
      await drainLogTimer(tester);
    });

    testWidgets('U5 搜索半屏纳入日记：日记/笔记双源命中，点日记行开编辑页',
        (tester) async {
      final now = DateTime.now();
      final e = await jrepo.save(JournalEntry(
          day: DateTime(now.year, now.month, 8),
          content: '公园野餐真开心',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await NoteDao(db).insert(Note(
          title: '损失厌恶笔记',
          content: '锚定效应与框架效应',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await pumpRouted(tester);

      await tester.tap(find.byKey(const ValueKey('rec-search')));
      await settle5(tester);
      final input = find.byKey(const ValueKey('note-search-input'));
      expect(input, findsOneWidget);
      await tester.enterText(input, '野餐');
      await settle5(tester);
      // 命中判定限定在搜索结果列表内——半屏背后仍压着完整日记列表（批5① 同坑同解）。
      final results = find.byKey(const ValueKey('note-search-list'));
      expect(results, findsOneWidget);
      expect(
          find.descendant(
              of: results,
              matching: find.byKey(ValueKey('diary-search-hit-${e.id}'))),
          findsOneWidget);
      // 点日记行 → 收屏开编辑页
      await tester.tap(
          find.descendant(
              of: results,
              matching: find.byKey(ValueKey('diary-search-hit-${e.id}'))),
          warnIfMissed: false);
      await settle5(tester);
      expect(find.byType(DiaryEditPage), findsOneWidget);
      expect(_richOf(tester).controller.document.toPlainText(),
          contains('公园野餐真开心'));
      await drainLogTimer(tester);
    });
  });

  group('语义断链批 · 回收站/L3 回勾/标签减法/持久化（2026-10-12 评估件 §三）', () {
    test('S1 回收站第八类：彻底删除连带清分节；到期清理按档跑', () async {
      final e = await jrepo.save(JournalEntry(
          day: DateTime(2026, 9, 20),
          content: '带分节的回收站篇',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await jrepo.remove(e.id!);
      expect(await jrepo.list(), isEmpty);
      expect((await jrepo.trashed()).map((x) => x.id), contains(e.id!));
      // 彻底删除＝真删（返回连带分节行数；本篇无分节＝0）
      expect(await jrepo.purgeJournal(e.id!), 0);
      expect((await jrepo.trashed()).map((x) => x.id), isNot(contains(e.id!)));
      // 到期清理：keepDays=30，刚删的行未到期不被清
      expect(await jrepo.purgeExpired(30), 0);
    });

    test('S2 L3 反向回勾：纯文本篇 ☐→☑（完成待办后同名行置勾）', () async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '☐ 买菜\n其他正文',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      expect(await jrepo.tickTodoLine('买菜'), isTrue);
      expect((await jrepo.list()).first.plainBody, contains('☑ 买菜'));
      // 未命中静默：非同名待办不写任何篇
      expect(await jrepo.tickTodoLine('不存在的待办'), isFalse);
    });

    test('S3 L3 回勾·结构化篇：分节 body 置勾且快照同步重渲', () async {
      final e = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          templateId: 1,
          sections: const [
            DiarySection(title: '感恩 ①', body: '☐ 谢天'),
            DiarySection(title: '感恩 ②', body: '谢地'),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      expect(await jrepo.tickTodoLine('谢天'), isTrue);
      final re = await jrepo.open(e.id!);
      expect(re!.sections[0].body, '☑ 谢天');
      expect(re.sections[1].body, '谢地');
      expect(re.content, contains('☑ 谢天')); // 渲染快照同步
    });

    test('S4 标签减法：正文删掉 #词后 tags 同步剔除（不再残留死标签）', () async {
      final e = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '#晨跑 #复盘 今天跑了一圈',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      expect(e.tags, containsAll(['晨跑', '复盘']));
      // 改稿删掉 #晨跑 → tags 只剩 复盘
      final e2 = await jrepo.save(e.copyWith(content: '今天跑了 #复盘 记录'));
      expect(e2.tags, ['复盘']);
    });

    test('S5 INS 布局/筛选持久化：settings 往返（冷启动恢复上次态）', () async {
      final container = ProviderContainer(overrides: [
        settingsRepositoryProvider
            .overrideWithValue(SettingsRepository(prefs)),
      ]);
      addTearDown(container.dispose);
      await container
          .read(settingsControllerProvider.notifier)
          .setJournalIns(true);
      await container
          .read(settingsControllerProvider.notifier)
          .setJournalFilter('todo');
      // 新仓库实例读同一 prefs＝冷启动等价
      final loaded = SettingsRepository(prefs).load();
      expect(loaded.journalIns, isTrue);
      expect(loaded.journalFilter, 'todo');
      expect(loaded.journalDefaultTpl, '纯文本'); // 默认值不受影响
    });

    // 6109 预发布实锤：迁移语句与基础 DDL 都加了 deleted_at，唯独
    // `DbSchema.version` 漏改（仍 43）⇒ 真机升级 onUpgrade 不触发 ⇒ 表无该列，
    // 日记读写全断（保存失败/列表空）。本组钉两层：键值一致性 + 真升级触发。
    test('S6 version 常量 = migrations 最高键 + 1（漏改 version＝升级静默失效）', () {
      final maxKey = DbSchema.migrations.keys
          .reduce((a, b) => a > b ? a : b); // migrations 空表时 reduce 抛＝更该红
      expect(DbSchema.version, maxKey + 1,
          reason: 'migrations 已定义到 $maxKey → ${maxKey + 1}，'
              '但 version=${DbSchema.version} 没跟上——真机 user_version 已到 '
              '${maxKey + 1} 以上时该迁移永不执行');
    });

    test('S7 真升级路径：v43 库（无 deleted_at）经 openDatabase(version:) 升 v44 '
        '→ 列出现＋老行保留＋带列写读走通', () async {
      const name = 'jtest_upgrade_v43to44.db';
      await databaseFactoryFfiNoIsolate.deleteDatabase(name);
      // 1) 手工搭出 v43 时代库（基础 DDL 含天气四列、无 deleted_at）并钉 user_version=43
      final old = await databaseFactoryFfiNoIsolate.openDatabase(name);
      await old.execute('''
        CREATE TABLE journal_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entry_date INTEGER NOT NULL,
          mood INTEGER,
          content TEXT NOT NULL,
          tags TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          starred INTEGER NOT NULL DEFAULT 0,
          liked INTEGER NOT NULL DEFAULT 0,
          view_count INTEGER NOT NULL DEFAULT 0,
          template_id INTEGER,
          kind TEXT NOT NULL DEFAULT '',
          weather_code INTEGER,
          temp_max REAL,
          temp_min REAL,
          weather_manual INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await old.insert('journal_entries',
          {'entry_date': 1, 'content': '升级前的老篇', 'created_at': 1, 'updated_at': 1});
      await old.execute('PRAGMA user_version = 43');
      await old.close();
      // 2) 按生产 openDatabase 口径重开（version 触发 onUpgrade 逐级迁移）
      final upgraded = await databaseFactoryFfiNoIsolate.openDatabase(name,
          options: OpenDatabaseOptions(
            version: DbSchema.version,
            onUpgrade: (d, from, to) async {
              for (var v = from; v < to; v++) {
                for (final sql in DbSchema.migrations[v] ?? const <String>[]) {
                  await d.execute(sql);
                }
              }
            },
          ));
      // 3) 列出现 + 老行保留
      final cols = await upgraded.rawQuery('PRAGMA table_info(journal_entries)');
      expect(cols.map((c) => c['name']), contains('deleted_at'));
      final oldRows = await upgraded.query('journal_entries');
      expect(oldRows, hasLength(1));
      expect(oldRows.first['content'], '升级前的老篇');
      // 4) 带列写读走通（6109 上炸的就是这两类 SQL）
      await upgraded.insert('journal_entries', {
        'entry_date': 2,
        'content': '升级后新篇',
        'created_at': 2,
        'updated_at': 2,
        'deleted_at': null,
      });
      final active = await upgraded
          .query('journal_entries', where: 'deleted_at IS NULL');
      expect(active.map((r) => r['content']), contains('升级后新篇'));
      await upgraded.close();
    });
  });
}

String _two(int v) => v.toString().padLeft(2, '0');

/// UIUX批守护组用：编辑页富文本控件（原为「输入正文+选心情」用例内局部函数，
/// 跨用例复用提为文件级；正文断言走 Quill 文档，find.textContaining 找不到）。
QuillEditor _richOf(WidgetTester tester) => tester.widget<QuillEditor>(
    find.byKey(const ValueKey('diary-rich-editor')));
