import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';

// 二期批6 · F6-7（外观二级页的返回语义）。
//
// 旧行为：外观面板里的二级页（字体/缩进/翻页/纸色/背景/简繁）按 Android 返回键
// 会把**整个面板**关掉——用户刚挑的纸色连同草稿一起没了；而且主↔子是同一帧硬换
// 内容，子页还接着主面板的滚动偏移打开（标题滚出视野）。
// 本文件钉三件：返回键退一级 / 主↔子有转场 / 子页不复用宿主滚动位。

const _filler =
    '这是一段用于外观面板实测的中文正文，长度足够在默认字号下占据两到三行。';

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

EpubDoc _doc() => EpubDoc(
  format: 'EPUB3',
  title: '外观书',
  author: '甲',
  toc: const [],
  chapters: [
    EpubChapter(
      href: 'c0',
      title: '第一章',
      paras: [
        const EpubPara(kind: EpubParaKind.heading, text: '第一章', headingLevel: 1),
        for (var i = 1; i <= 9; i++) _p('C0P$i。$_filler'),
      ],
    ),
  ],
  imageCount: 0,
  totalChars: 9 * _filler.length,
);

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
    await repo.addBook(
      Book(
        id: 's1',
        title: '外观书',
        local: true,
        epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  /// 开书 → 唤起 chrome → 点外观 → 面板出。
  Future<void> openAppearance(WidgetTester t) async {
    await useSurface(t, const Size(420, 780));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
          epubPreloadProvider.overrideWith((_) => EpubPreloadService(repo)),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 's1')),
      ),
    );
    await step(t, times: 4);
    await t.tapAt(Offset(210, 640));
    await step(t);
    await t.tap(find.byKey(const ValueKey('brBtnLook')));
    await step(t, ms: 320, times: 3);
    expect(find.byKey(const ValueKey('sheetBrAppearance')), findsOne);
  }

  testWidgets('返回键在二级页只退一级（不关整个面板），再按才关', (t) async {
    await openAppearance(t);
    await t.tap(find.byKey(const ValueKey('brApSubBtn-font')));
    await step(t, ms: 200, times: 2);
    expect(find.byKey(const ValueKey('brApSub-back')), findsOne,
        reason: '进了字体二级页');

    expect(await t.binding.handlePopRoute(), isTrue);
    await step(t, ms: 200, times: 2);
    expect(find.byKey(const ValueKey('brApSub-back')), findsNothing,
        reason: '返回键应当退回主面板');
    expect(
      find.byKey(const ValueKey('sheetBrAppearance')),
      findsOne,
      reason: '旧行为：返回键把整个外观面板关了（草稿一起丢）',
    );

    // 主面板再按返回＝关面板（canPop 恢复 true）。
    await t.binding.handlePopRoute();
    await step(t, ms: 320, times: 2);
    expect(find.byKey(const ValueKey('sheetBrAppearance')), findsNothing);
  });

  testWidgets('主↔子切换有 150ms 转场', (t) async {
    await openAppearance(t);
    final sw = t.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byKey(const ValueKey('sheetBrAppearance')),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(sw.duration, const Duration(milliseconds: 150),
        reason: '方案 §4.5：主↔子 120~180ms（旧实现同帧硬换＝闪一下）');
  });

  testWidgets('子页不复用宿主滚动位（自己一份控制器，起始在顶）', (t) async {
    await openAppearance(t);
    final mainCtl = t
        .widget<ListView>(
          find.descendant(
            of: find.byKey(const ValueKey('brApBody-main')),
            matching: find.byType(ListView),
          ),
        )
        .controller;
    await t.tap(find.byKey(const ValueKey('brApSubBtn-font')));
    await step(t, ms: 200, times: 2);
    final subCtl = t
        .widget<ListView>(
          find.descendant(
            of: find.byKey(const ValueKey('brApBody-font')),
            matching: find.byType(ListView),
          ),
        )
        .controller;
    expect(identical(mainCtl, subCtl), isFalse,
        reason: '主/子共用同一个控制器＝子页会接着主面板的偏移打开');
    expect(subCtl!.offset, 0, reason: '子页应当从头开始');
  });
}
