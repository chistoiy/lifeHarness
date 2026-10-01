# tools/attic/xr_batchB_test_patch.py — 批B 测试扩展：假通道补扫分支 + 自学习用例组
import io

CRLF_MARK = chr(13) + chr(10)

p = 'test/xray_panel_test.dart'
s = io.open(p, encoding='utf-8', newline='').read()


def rep(a, b, cnt=1):
    global s
    a = a.replace(chr(10), CRLF_MARK) if CRLF_MARK in s and a not in s else a
    b = b.replace(chr(10), CRLF_MARK) if a in s and CRLF_MARK in s and b not in s else b
    assert s.count(a) == cnt, (a[:40], s.count(a))
    s = s.replace(a, b)


# 1) 假通道加 scan 分支
rep("""  final XrayJobSpec _spec;
  final XrayWorkerEvents _ev;
  final XrayEngine engine;
  final Map<int, List<String>> _stored = {};
  List<XrayEntity>? _keep;

  @override
  void feedCollect(int ci, List<String> paras) {
    _stored[ci] = paras;
    engine.runChapter(XrayChapter(idx: ci, paras: paras));
    scheduleMicrotask(() => _ev.onChapterDone(ci));
  }""",
    """  final XrayJobSpec _spec;
  final XrayWorkerEvents _ev;
  final XrayEngine engine;
  final Map<int, List<String>> _stored = {};
  List<XrayEntity>? _keep;
  XrayWordScan? _scan;

  @override
  void feedCollect(int ci, List<String> paras) {
    _stored[ci] = paras;
    if (_spec.word != null) {
      _scan ??= XrayWordScan(
          word: _spec.word!, type: _spec.wordType ?? 'term', bank: _bank());
      _scan!.addChapter(ci, paras);
    } else {
      engine.runChapter(XrayChapter(idx: ci, paras: paras));
    }
    scheduleMicrotask(() => _ev.onChapterDone(ci));
  }""")

rep("""  @override
  void finishCollect() {
    _keep = engine.finish(tocTitles: _spec.tocTitles);""",
    """  @override
  void finishCollect() {
    if (_scan != null) {
      final payload = _scan!.payload();
      scheduleMicrotask(() => _ev.onResult([payload]));
      return;
    }
    _keep = engine.finish(tocTitles: _spec.tocTitles);""")

# 2) 文末追加批B用例组（放 main 收尾 `}` 前）
tail_anchor = """      await t.pump(const Duration(milliseconds: 400));
    });
  });
}
"""
assert s.endswith(tail_anchor), repr(s[-120:])
group = """      await t.pump(const Duration(milliseconds: 400));
    });
  });

  group('批B-L · 自学习（假通道）', () {
    test('加词补扫：出场回填 + 称谓形态建议产出', () async {
      final b = await addBook('l1');
      await dao.setBookMd5('l1', 'M');
      final s = makeScheduler();
      await s.dao.registerUserWord(md5: 'M', word: '李德', type: 'per');
      await s.scanWord(book: b, md5: 'M', word: '李德', type: 'per');
      // 假通道纯微任务：轮询到词条计数回填为止。
      var ent = await dao.entityByName('M', '李德');
      for (var i = 0; i < 2000 && (ent == null || ent.n == 0); i++) {
        await Future<void>.microtask(() {});
        ent = await dao.entityByName('M', '李德');
      }
      expect(ent, isNotNull);
      expect(ent!.userAdded, isTrue, reason: '加词行必须标 my-vocab 来源');
      expect(ent.n, greaterThanOrEqualTo(4));
      final anchors = await dao.anchorsOf('M', ent.id);
      expect(anchors.length, ent.n, reason: '补扫锚点全量');
      // 语料里「李德说/李德道/李德问」后跟的是动词不是称谓 → 不产建议；
      // 称谓形态在下一例专门验。
      expect(s.suggestion('l1'), isNull);
      s.dispose();
    });

    test('称谓形态 ≥30% → 建议卡 + 采纳落 GLOBAL', () async {
      final b = await addBook('l2');
      await dao.setBookMd5('l2', 'M');
      final s2 = XrayScheduler(
        dao: dao,
        loadDoc: (_) async => EpubDoc(
          format: 'EPUB2',
          title: '称谓书',
          author: '甲',
          toc: const [],
          chapters: [
            EpubChapter(href: 'c1', title: '第一章', paras: [
              _p('李德先生说。'),
              _p('李德先生道。'),
              _p('李德先生问。'),
              _p('有人喊了李德。'),
            ]),
          ],
          imageCount: 0,
          totalChars: 40,
        ),
        md5Hook: (_) async => 'M',
        workerFactory: (spec, ev) async => _FakeWorker(spec, ev),
      );
      await s2.dao.registerUserWord(md5: 'M', word: '李德', type: 'per');
      await s2.scanWord(book: b, md5: 'M', word: '李德', type: 'per');
      for (var i = 0; i < 2000 && s2.suggestion('l2') == null; i++) {
        await Future<void>.microtask(() {});
      }
      final sug2 = s2.suggestion('l2');
      expect(sug2, isNotNull, reason: '75% 出场后跟「先生」必须挂出建议');
      expect(sug2!.title, '先生');
      await s2.dao.promoteWordToGlobal('M', '李德', patternHint: '先生');
      final layer = await s2.dao.userLayer('M');
      expect(layer.added, contains('李德'));
      s2.dismissSuggestion('l2');
      expect(s2.suggestion('l2'), isNull);
      s2.dispose();
    });

    test('合并写时物化：mention 迁移 + aliases + n/chs 重算 + 死行标记', () async {
      final b = await addBook('l3');
      await dao.setBookMd5('l3', 'M');
      final s = makeScheduler();
      // 造两条词条：李德（章0/1 各一条锚点）与 李德先生（章1 两条）。
      await s.dao.writeRunResult(md5: 'M', rows: [
        XrayWriteEntity(
            name: '李德',
            type: 'per',
            n: 2,
            chs: 2,
            score: 3.0,
            channels: 1,
            tocFlag: false,
            aliases: const [],
            anchors: const [XrayMention(0, 3), XrayMention(1, 1)]),
        XrayWriteEntity(
            name: '李德先生',
            type: 'per',
            n: 2,
            chs: 1,
            score: 2.0,
            channels: 1,
            tocFlag: false,
            aliases: const [],
            anchors: const [XrayMention(1, 5, '李德先生道'), XrayMention(1, 9)]),
      ]);
      final a = (await dao.entityByName('M', '李德'))!;
      final c = (await dao.entityByName('M', '李德先生'))!;
      await dao.mergeInto('M', intoId: a.id, fromIds: [c.id]);
      final into = (await dao.entityByName('M', '李德'))!;
      expect(into.aliases, contains('李德先生'));
      expect(into.n, 4, reason: '写时物化：n 当场重算，不靠读侧再并');
      final anchors = await dao.anchorsOf('M', into.id);
      expect(anchors, hasLength(4));
      expect((await dao.anchorsOf('M', c.id)), isEmpty,
          reason: '出场已整体迁到规范词条');
      final dead = await dao.entityById('M', c.id);
      expect(dead, isNull, reason: 'merged_into 行不再出现在读侧');
      s.dispose();
    });

    test('移除=状态位：读侧消失且重解析不洗白；全局升级入黑名单', () async {
      final b = await addBook('l4');
      await dao.setBookMd5('l4', 'M');
      final s = makeScheduler();
      await s.start(book: b, md5: 'M', from: 0, to: 1);
      await waitTask(s, 'M');
      final lide = (await dao.entityByName('M', '李德'))!;
      await dao.markDeleted('M', [lide.id], toGlobal: true);
      expect(await dao.entityByName('M', '李德'), isNull);
      final layer = await dao.userLayer('M');
      expect(layer.forbidden, contains('李德'));
      // 重跑解析（洗白攻击面）：被屏蔽的词不得回到读侧。
      await s.start(book: b, md5: 'M', from: 0, to: 1);
      await waitTask(s, 'M');
      expect((await dao.allEntities('M')).where((e) => e.name == '李德'),
          isEmpty);
      s.dispose();
    });
  });

  group('批B-W · 面板自学习面（widget）', () {
    Future<XrayScheduler> openReaderB(
      WidgetTester t,
      String id,
    ) async {
      final sched = makeScheduler();
      await useSurface(t, const Size(420, 1600));
      await addBook(id);
      await dao.setBookMd5(id, 'M');
      await t.pumpWidget(ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
          xraySchedulerProvider.overrideWith((_) => sched),
        ],
        child: MaterialApp(home: ReaderPage(bookId: id)),
      ));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      await t.tapAt(const Offset(210, 645));
      await t.pump(const Duration(milliseconds: 200));
      return sched;
    }

    Future<void> toXrTabB(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('brBtnToc')));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('xrSegXr')));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('＋加词 → 弹层登记 → 整理模式勾选→移除弹层', (t) async {
      final sched = await openReaderB(t, 'w1');
      final b = await repo.bookById('w1');
      await sched.start(book: b!, md5: 'M', from: 0, to: 1);
      await waitTask(sched, 'M');
      await toXrTabB(t);
      // 加词弹层
      await t.tap(find.byKey(const ValueKey('xrAddBtn')));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const ValueKey('sheetXrAdd')), findsOne);
      await t.enterText(find.byKey(const ValueKey('xrAddWordIn')), '巧克力');
      await t.pump(const Duration(milliseconds: 100));
      await t.ensureVisible(find.byKey(const ValueKey('xrAddGo')));
      await t.tap(find.byKey(const ValueKey('xrAddGo')));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final ent = await dao.entityByName('M', '巧克力');
      expect(ent, isNotNull, reason: '加词行必须登记（默认语料无出场也建行）');
      expect(ent!.userAdded, isTrue);
      // 整理模式：勾选榜首 → 底栏出现 → 移除弹层确认 → 该行从列表消失。
      await t.tap(find.byKey(const ValueKey('xrOrgBtn')));
      await t.pump(const Duration(milliseconds: 100));
      final rows = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xrRow-'));
      expect(rows, findsWidgets);
      final firstKey =
          (rows.evaluate.first.widget as GestureDetector).key as ValueKey<String>;
      await t.tap(rows.first);
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('xrOrgBar')), findsOne);
      await t.tap(find.byKey(const ValueKey('xrOrgDel')));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const ValueKey('sheetXrDel')), findsOne);
      await t.ensureVisible(find.byKey(const ValueKey('xrDelGo')));
      await t.tap(find.byKey(const ValueKey('xrDelGo')));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(firstKey), findsNothing,
          reason: '移除＝读侧立刻消失（状态位口径）');
    });

    testWidgets('详情自学习三件套在位（候选卡随数据出现）', (t) async {
      final sched = await openReaderB(t, 'w2');
      final b = await repo.bookById('w2');
      await sched.start(book: b!, md5: 'M', from: 0, to: 1);
      await waitTask(sched, 'M');
      // 造一条与「李德」互含的词条触发候选卡。
      await dao.writeRunResult(md5: 'M', rows: [
        XrayWriteEntity(
            name: '李德先生',
            type: 'per',
            n: 1,
            chs: 1,
            score: 0.5,
            channels: 1,
            tocFlag: false,
            aliases: const [],
            anchors: const [XrayMention(1, 0, '李德先生道')]),
      ]);
      sched.notifyDataChanged();
      await toXrTabB(t);
      final rows = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xrRow-'));
      expect(rows, findsWidgets);
      await t.tap(rows.first); // 榜首（李德）进详情
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('xr-merge-into')), findsOne);
      expect(find.byKey(const ValueKey('xr-ban')), findsOne);
      expect(find.byKey(const ValueKey('xr-aihold')), findsOne);
      final cand = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xr-cand-'));
      expect(cand, findsOne, reason: '「李德先生」互含必出候选卡');
    });
  });
}
"""
s = s[: -len(tail_anchor)] + group
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('test patch ok')
