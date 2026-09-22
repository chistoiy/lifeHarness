import 'dart:convert';
import 'dart:io';

import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/journal/data/diary_template_dao.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/diary_template.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/diary_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
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
          eventRepositoryProvider
              .overrideWithValue(EventRepository(EventDao(db), bus)),
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (wx != null) weatherServiceProvider.overrideWithValue(wx),
        ],
        child: MaterialApp(home: home),
      );

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
      expect(find.text('写今天的日记'), findsOneWidget);
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
      expect(find.textContaining('规划 V0.5'), findsWidgets);
      // 回日记段
      await tester.tap(find.byKey(const ValueKey('rec-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日记'));
      await tester.pumpAndSettle();
      expect(find.text('记录 · 日记'), findsOneWidget);
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

      // 行内顺序：切换钮在左、筛选钮在右
      final vx = tester.getRect(find.byKey(const ValueKey('diary-view'))).center.dx;
      final fx = tester
          .getRect(find.byKey(const ValueKey('diary-filter')))
          .center
          .dx;
      expect(fx, greaterThan(vx));

      await tester.tap(find.byKey(const ValueKey('diary-filter')));
      await tester.pumpAndSettle();
      expect(find.text('筛选'), findsOneWidget);
      expect(find.byKey(const ValueKey('df-opt-全部')), findsOneWidget);
      expect(find.byKey(const ValueKey('df-opt-☐ 待办')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('df-opt-☐ 待办')));
      await settle5(tester);
      // 仅含 ☐ 待办行的那篇可见
      expect(find.textContaining('买猫粮'), findsOneWidget);
      expect(find.textContaining('普通一天'), findsNothing);
      // 再开浮层：当前项✓ + 可回全部
      await tester.tap(find.byKey(const ValueKey('diary-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('df-opt-全部')));
      await settle5(tester);
      expect(find.textContaining('普通一天'), findsOneWidget);
    });

    testWidgets('INS 卡片流切换键：点 ❤️ 落库 liked', (tester) async {
      final e = await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '回望测试',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await tester.pumpWidget(scope(const JournalPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('diary-view')));
      await tester.pumpAndSettle();
      expect(find.text('CHIST · ${_two(DateTime.now().month)}-${_two(DateTime.now().day)}'),
          findsOneWidget);

      await tester.tap(find.byKey(ValueKey('ins-like-${e.id}')));
      await tester.pumpAndSettle();
      final after = await jrepo.byDay(DateTime.now());
      expect(after!.liked, isTrue);
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
      await tester.tap(find.byKey(const ValueKey('jm-1'))); // 😌 平静
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('diary-save')));
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
    });

    testWidgets('轮12-6/8 头部=仅居中日期（当年 MM-DD 周几 · 跨年显年月日）·无篇序/字数/搜索',
        (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(scope(const DiaryEditPage()));
      await settle5(tester);
      const wds = ['一', '二', '三', '四', '五', '六', '日'];
      expect(
          find.text(
              '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} 周${wds[now.weekday - 1]}'),
          findsOneWidget);
      expect(find.text('第 1 篇'), findsNothing);
      expect(find.textContaining(' 字'), findsNothing);
      expect(find.textContaining('已自动保存'), findsNothing);
      expect(find.text('写日记'), findsNothing);
      expect(find.byIcon(Icons.search), findsNothing);

      await tester.pumpWidget(scope(DiaryEditPage(key: UniqueKey(), day: DateTime(2025, 9, 19))));
      await settle5(tester);
      expect(find.text('2025-09-19 周五'), findsOneWidget); // 跨年历史篇补年份
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

      await tester.tap(find.text('插入正文 ↑'));
      await tester.pump();
      expect(richCtl(tester).controller.document.toPlainText(),
          contains('【今日概览 · 自动生成】'));
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
      expect(find.text('📋 模板：KPT 复盘 ▾'), findsOneWidget);
      expect(find.byKey(const ValueKey('diary-rich-editor')), findsNothing); // 结构化无富文本区

      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('sec-0')),
              matching: find.byType(TextField)),
          '坚持了晨跑');
      await tester.tap(find.byKey(const ValueKey('diary-save')));
      // 单帧即可：toast 1600ms 自动消失，pumpAndSettle 会推进过其生命周期。
      await tester.pump();
      expect(find.textContaining('KPT 复盘（3 节）'), findsOneWidget);
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

      await tester.tap(find.byKey(const ValueKey('diary-bold')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()),
          contains('"bold":true'));

      ctl.replaceText(3, 0, '', const TextSelection.collapsed(offset: 3));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('diary-task')));
      await tester.pump();
      expect(jsonEncode(ctl.document.toDelta().toJson()),
          contains('"list":"unchecked"'));
      await tester.tap(find.byKey(const ValueKey('diary-task')));
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
        tmp.deleteSync(recursive: true);
        docs.deleteSync(recursive: true);
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

      await tester.tap(find.byKey(const ValueKey('diary-album')));
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
      final e = await jrepo.byDay(DateTime.now());
      expect(e!.kind, 'rich');
      expect(e.content, contains('"image"'));
      expect(e.imagePaths, hasLength(1));
      expect(Note.richToPlain(e.content), contains('图片')); // 预览无路径
    });

    testWidgets('2a-1b 旧纯文本带图篇重开=图片转内嵌 embed；清空图后落库无图',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lhimg2a1b');
      addTearDown(() => tmp.deleteSync(recursive: true));
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
      final e = await jrepo.byDay(DateTime.now());
      expect(e!.imagePaths, isEmpty);
      expect(Note.richToPlain(e.content), contains('正文在前'));
    });

    testWidgets('2a-2 ＋拍照钮直取相机源·防抖自动存草稿带图', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lhimg2a2');
      final docs = Directory.systemTemp.createTempSync('lh_docs2a2');
      addTearDown(() {
        tmp.deleteSync(recursive: true);
        docs.deleteSync(recursive: true);
      });
      File(p.join(tmp.path, 'a.png')).writeAsBytesSync(base64Decode(_png1x1));
      ImagePickerPlatform.instance = _FakeImagePicker(p.join(tmp.path, 'a.png'));
      PathProviderPlatform.instance = _FakePathProvider(docs.path);
      await useSurface(tester);

      await tester.pumpWidget(scope(const DiaryEditPage()));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('diary-cam')));
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
    });

    /// 两条真 1×1 PNG + 一篇带图带待办的日记（INS/列表两用例共用装配）。
    Future<(JournalEntry, String, String)> seedImgEntry() async {
      final tmp = Directory.systemTemp.createTempSync('lhimg2a3');
      final a = p.join(tmp.path, 'a.png');
      final b = p.join(tmp.path, 'b.png');
      File(a).writeAsBytesSync(base64Decode(_png1x1));
      File(b).writeAsBytesSync(base64Decode(_png1x1));
      addTearDown(() => tmp.deleteSync(recursive: true));
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
      await tester.tap(find.byKey(const ValueKey('diary-view'))); // 切 INS
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
      expect(find.byKey(const ValueKey('diary-sel-bar')), findsNothing);
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
      await tester.tap(find.byKey(const ValueKey('diary-view')));
      await settle5(tester);

      await tester.longPress(find.text('CHIST · ${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}'));
      await settle5(tester);
      expect(find.byKey(const ValueKey('diary-sel-bar')), findsOneWidget);
      expect(find.byKey(ValueKey('insel-${e.id}')), findsOneWidget);

      // 取消勾选→空集自动退出多选
      await tester.tap(find.byKey(ValueKey('insel-${e.id}')),
          warnIfMissed: false);
      await settle5(tester);
      expect(find.byKey(const ValueKey('diary-sel-bar')), findsNothing);
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
      expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
      expect(find.byKey(const ValueKey('dr-trend')), findsOneWidget);
      expect(find.byKey(const ValueKey('dr-legend')), findsOneWidget);
      expect(find.textContaining('本月记录 3 篇'), findsOneWidget);
      // 词云：中文 2-gram 高频词（跑步=3 次 → 中号字）
      expect(find.text('跑步'), findsOneWidget);
      // 去年本月卡（弹层与背后列表各一份预览 → findsWidgets）
      expect(find.text('去年${now.month}月 · 共 1 篇'), findsOneWidget);
      expect(find.textContaining('一年前的今天'), findsWidgets);

      // 切到上月再回来：月标签联动、空月摘要兜底
      await tester.tap(find.byKey(const ValueKey('dr-prev')));
      await settle5(tester);
      final prev = DateTime(now.year, now.month - 1);
      expect(find.text('${prev.year}年${prev.month}月'), findsOneWidget);
      expect(find.textContaining('本月还没有记录'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dr-next')));
      await settle5(tester);
      expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
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
        return wxJson(WeatherDao.dayKey(DateTime.now()));
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
      final offline = WeatherService(WeatherDao(db), fetch: (u) async => null);
      expect(await offline.day(DateTime(2020, 1, 1), city), isNull);
      expect(await db.query('weather_daily'), hasLength(1)); // 换城市 replace 同日行
    });

    test('2e-0c searchCity：解析命中 · 空查询/无结果静默', () async {
      final svc = WeatherService(WeatherDao(db), fetch: (uri) async {
        if (uri.host != 'geocoding-api.open-meteo.com') return null;
        return {
          'results': [
            {'name': '杭州', 'latitude': 30.29, 'longitude': 120.16, 'admin1': '浙江', 'country': '中国'},
            {'name': '杭州湾', 'latitude': 30.1, 'longitude': 121.0},
          ]
        };
      });
      final hits = await svc.searchCity('杭州');
      expect(hits, hasLength(2));
      expect(hits.first.label, '杭州 · 浙江');
      expect(await svc.searchCity('  '), isEmpty);
      final bad = WeatherService(WeatherDao(db), fetch: (u) async => null);
      expect(await bad.searchCity('上海'), isEmpty);
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
        return wxJson(WeatherDao.dayKey(DateTime.now()));
      });
      await tester.pumpWidget(scope(DiaryEditPage(day: DateTime.now()), wx: svc));
      await settle5(tester);
      expect(find.byKey(const ValueKey('diary-wx-chip')), findsOneWidget);
      await waitFinder(tester, find.text('晴 20~30°')); // 自动抓链含 ffi 落库
      expect(calls, 1);
      final e = (await jrepo.listByDay(DateTime.now())).first;
      expect(e.weatherCode, 0);
      expect(e.tempMax, 30.4);
      final cache = await db.query('weather_daily');
      expect(cache, hasLength(1));
      expect(cache.first['city'], '杭州');
    });

    testWidgets('2e-2 点 chip 手动覆盖：落库 manual=1 · 重开不再自动抓 · 恢复自动',
        (tester) async {
      await setCity(WeatherCity.encode(city));
      var calls = 0;
      WeatherService svc() => WeatherService(WeatherDao(db), fetch: (uri) async {
            calls++;
            return wxJson(WeatherDao.dayKey(DateTime.now()));
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
    });

    testWidgets('2e-3b 有城市但无网：假 fetch 返回 null=静默，chip 空壳不写缓存',
        (tester) async {
      await setCity(WeatherCity.encode(city));
      await tester.pumpWidget(scope(
          DiaryEditPage(day: DateTime.now()),
          wx: WeatherService(WeatherDao(db), fetch: (u) async => null)));
      await settle5(tester);
      expect(find.text('天气'), findsOneWidget);
      expect(await db.query('weather_daily'), isEmpty);
    });
  });
}

String _two(int v) => v.toString().padLeft(2, '0');
