// 工单 §3H 一次性测量/复验探针（页底切字 A ＋ 大小字混排 B）——**不是常态回归**，
// 只在 env LH_ZTJ 指向真《資治通鑑》样包时执行（同 reader_span_baseline_test 口径）。
// 读数走 `flutter test test/reader_ztj_clip_probe_test.dart` 直接 grep 'ZTJ-'
// （勿经 tools/ftest.sh，它的过滤会吞探针 print）。
// 修后复验口径：ZTJ-A4 溢出页＝0（插图页除外）；ZTJ-EXCEPTION 必须为空；
// ZTJ-B 混字号段逐行行高全等；ZTJ-LH 行距滑杆必须改变段高。
// 字体口径注记：flutter_test 用 Ahem 等宽占位字族，CJK 的 advance 两边都＝1em，
// 行数与页划分可比，绝对像素另说。
@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/reader_cfg.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

const _defaultPath =
    'D:/dev_workplace/flutter_te/tempWork/新建文件夹/'
    '資治通鑑 ([宋] 司馬光 編集  [元] 胡三省 注) (z-library.sk, 1lib.sk, z-lib.sk).epub';

/// 真机 ea028260 口径：1200x2670 @480dpi＝逻辑 400x890，顶部安全区＝134px＝44.67 逻辑。
const _devW = 400.0, _devH = 890.0, _devTopPx = 134.0, _devDpr = 3.0;

const _needle = '彼驕';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['LH_ZTJ'] ?? _defaultPath;
  final has = File(path).existsSync();

  EpubDoc? cached;
  EpubDoc parse() => cached ??= EpubDoc.parse(File(path).readAsBytesSync());

  // 装箱用的舞台高＝视口高减顶部安全区（与阅读主屏同一算法，见 brStageHeight）。
  ReaderLayout layout() => ReaderLayout.of(
    ReaderCfg.defaults,
    width: _devW,
    height: _devH - _devTopPx / _devDpr,
  );

  group('§3H-A 修后复验 · 全书装箱对账', () {
    test('每一页的绘制合计不得超可用高（插图页除外）', () {
      if (!has) {
        // ignore: avoid_print
        print('ZTJ-SKIP 样包不在 $path');
        return;
      }
      final doc = parse();
      final l = layout();
      // ignore: avoid_print
      print('ZTJ-BOX contentH=${l.contentH.toStringAsFixed(1)} '
          'contentW=${l.contentW.toStringAsFixed(1)} '
          '正文测量宽=${paraMeasureW(l, EpubParaKind.text).toStringAsFixed(1)} '
          '引文测量宽=${paraMeasureW(l, EpubParaKind.quote).toStringAsFixed(1)}');
      var pages = 0, over = 0, worst = 0.0, splitParas = 0, extraPieces = 0;
      var imgPages = 0;
      var tallest = 0.0, tallestDesc = '';
      for (var ci = 0; ci < doc.chapters.length; ci++) {
        final paras = doc.chapters[ci].paras;
        final tab = EpubPager.layoutChapter(paras, l);
        final seen = <int, int>{};
        for (final pg in tab) {
          pages++;
          var h = 0.0;
          var hasImage = false;
          for (final b in pg) {
            if (paras[b.pi].kind == EpubParaKind.image) hasImage = true;
            final x = EpubPager.pieceHeight(paras[b.pi], l, b.from, b.to);
            h += x;
            if (x > tallest) {
              tallest = x;
              tallestDesc = '章$ci 段${b.pi} 块[${b.from},${b.to}) 字=${b.to - b.from}';
            }
            seen[b.pi] = (seen[b.pi] ?? 0) + 1;
          }
          if (hasImage) {
            imgPages++;
            continue;
          }
          if (h > l.contentH + 0.01) {
            over++;
            if (h - l.contentH > worst) worst = h - l.contentH;
          }
        }
        for (final e in seen.entries) {
          if (e.value > 1) {
            splitParas++;
            extraPieces += e.value - 1;
          }
        }
      }
      // ignore: avoid_print
      print('ZTJ-A4 总页=$pages 溢出=$over 页 最差溢出=${worst.toStringAsFixed(1)}px '
          '（插图页 $imgPages 页不参与判定）');
      // ignore: avoid_print
      print('ZTJ-A5 被拆续的段=$splitParas 追加块=$extraPieces '
          '最高块=${tallest.toStringAsFixed(0)}px @$tallestDesc');
      expect(over, 0, reason: '修完仍溢出＝测量与绘制没同源');
    });

    testWidgets('章#8 那一页不再裁字（同页复验）', (t) async {
      if (!has) return;
      final doc = parse();
      final l = layout();
      var ci = -1;
      for (var i = 0; i < doc.chapters.length && ci < 0; i++) {
        if (doc.chapters[i].paras.any((p) => p.text.contains(_needle))) ci = i;
      }
      expect(ci, greaterThanOrEqualTo(0));
      final paras = doc.chapters[ci].paras;
      final pages = EpubPager.layoutChapter(paras, l);
      var pg = 0, pi = 0, from = 0, to = 0;
      for (var i = 0; i < pages.length; i++) {
        for (final b in pages[i]) {
          if (paras[b.pi].text.substring(b.from, b.to).contains(_needle)) {
            pg = i;
            pi = b.pi;
            from = b.from;
            to = b.to;
          }
        }
      }
      // ignore: avoid_print
      print('ZTJ-CH 章#$ci（共${pages.length}页）needle 在第${pg + 1}页 '
          '段$pi 块[$from,$to) 段长=${paras[pi].text.length}');

      AppLog.reset();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db =
          await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      addTearDown(db.close);
      final repo = ReadRepository(db);
      const id = 'ztj-probe';
      await repo.addBook(
        Book(
          id: id,
          title: '資治通鑑',
          local: true,
          epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await repo.setKv('reader.pos.$id', jsonEncode({'ci': ci, 'pg': pg}));

      await useSurface(t, const Size(_devW, _devH));
      t.view.devicePixelRatio = _devDpr;
      t.view.padding = FakeViewPadding(top: _devTopPx);
      addTearDown(() {
        t.view.devicePixelRatio = 3.0;
        t.view.padding = FakeViewPadding();
      });

      await t.pumpWidget(
        ProviderScope(
          overrides: [
            readRepositoryProvider.overrideWithValue(repo),
            sharedPreferencesProvider.overrideWithValue(prefs),
            epubDocLoaderProvider.overrideWithValue((_) async => doc),
          ],
          child: MaterialApp(home: ReaderPage(bookId: id)),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 220));
      }
      final ex = t.takeException();
      // ignore: avoid_print
      print('ZTJ-EXCEPTION ${ex == null ? "无" : ex.toString().split("\n").first}');
      expect(ex, isNull, reason: '仍有 RenderFlex 溢出＝页底还在裁字');

      // 页容器矩形（公开 API：RenderFlex.children 是 protected，dynamic 取会在
      // 运行期 NoSuchMethodError，只能在调试期看溢出条）。
      final pageRect = t.getRect(find.byKey(ValueKey('page-$ci-$pg')));
      final inner = Rect.fromLTRB(
        pageRect.left + 22,
        pageRect.top + 22 + kBrChromeTopPad,
        pageRect.right - 22,
        pageRect.bottom - 22 - kBrChromeBottomPad,
      );
      final blocks = EpubPager.layoutChapter(paras, l)[pg];
      var tops = <double>[], bottoms = <double>[];
      for (final b in blocks) {
        final r = t.getRect(find.byKey(
            ValueKey('brp-$ci-${b.pi}${b.from == 0 ? '' : '-${b.from}'}')));
        tops.add(r.top);
        bottoms.add(r.bottom);
      }
      // ignore: avoid_print
      print('ZTJ-DRAW 内框=[${inner.top.toStringAsFixed(1)},'
          '${inner.bottom.toStringAsFixed(1)}] 块=${blocks.length} '
          '首块顶=${tops.isEmpty ? "-" : tops.first.toStringAsFixed(1)} '
          '末块底=${bottoms.isEmpty ? "-" : bottoms.last.toStringAsFixed(1)} '
          '装箱用=${l.contentH.toStringAsFixed(1)}');
      expect(tops, isNotEmpty);
      expect(tops.first, greaterThanOrEqualTo(inner.top - 0.6),
          reason: '首块被顶出容器＝仍在裁字');
      expect(bottoms.last, lessThanOrEqualTo(inner.bottom + 0.6),
          reason: '末块下沿越过容器＝页底裁字');
      await settle5(t);
    });
  });

  group('§3H-B 行距拉平复验', () {
    test('混字号段落的逐行行高全等（原书 line-height 不再各算各的）', () {
      if (!has) return;
      final doc = parse();
      final l = layout();
      var checked = 0, uneven = 0, shown = 0;
      for (var ci = 0; ci < 24 && checked < 300; ci++) {
        for (final p in doc.chapters[ci].paras) {
          if (p.kind != EpubParaKind.text) continue;
          final sizes = <double>{
            for (final r in p.runs)
              (l.base.fontSize ?? 19) * (r.style.fontRatio ?? 1),
          };
          if (sizes.length < 2) continue;
          checked++;
          final tp = TextPainter(
            text: paraSpan(p, l.base, orig: true, indMode: 'auto'),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: paraMeasureW(l, p.kind));
          final ms = tp.computeLineMetrics();
          tp.dispose();
          final hs = {
            for (final m in ms) m.height.toStringAsFixed(2)
          };
          if (hs.length > 1) {
            uneven++;
            if (shown < 2) {
              shown++;
              // ignore: avoid_print
              print('ZTJ-B-SAMPLE 章$ci 行高=${[for (final m in ms) m.height.toStringAsFixed(1)]}');
              // ignore: avoid_print
              print('ZTJ-B-STYLES 段=${(() { final st = paraStyle(p, l.base, orig: true); return '${st.fontSize}x${st.height?.toStringAsFixed(3)}'; })()} '
                  '区间=${[for (final sg in paraRunStyles(p, l.base, orig: true)) '${sg.style.fontSize}x${sg.style.height?.toStringAsFixed(3)}'].toSet()}');
            }
          }
        }
      }
      // ignore: avoid_print
      print('ZTJ-B 混字号段抽样=$checked 行高不齐=$uneven');
      expect(uneven, 0, reason: '行距拉平没生效');
    });

    test('外观行距滑杆改变段高（这本书此前完全失效）', () {
      if (!has) return;
      final doc = parse();
      const loose = ReaderLayout(
          width: _devW, height: 400, lh: 2.0, orig: true, font: 'serif');
      const tight = ReaderLayout(
          width: _devW, height: 400, lh: 1.2, orig: true, font: 'serif');
      var changed = 0, total = 0;
      // 卷一首章是封面章（零段），抽样改取全书前 200 段，别拿空样本自证通过。
      final sample = <EpubPara>[
        for (final c in doc.chapters)
          ...c.paras.take(math.min(20, c.paras.length)),
      ].take(200).toList();
      for (final p in sample) {
        if (p.kind == EpubParaKind.image || p.text.isEmpty) continue;
        total++;
        if ((EpubPager.paraHeight(p, loose) - EpubPager.paraHeight(p, tight))
            .abs() >
            0.01) {
          changed++;
        }
      }
      // ignore: avoid_print
      print('ZTJ-LH 卷一抽样段=$total 行距滑杆改变段高=$changed');
      expect(changed, total, reason: '行距滑杆对这本书无效＝原书声明又盖回来了');
    });
  });
}
