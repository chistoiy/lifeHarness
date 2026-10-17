// 批三实现批·第一步：67 万 span 分页耗时基线（预研《原书样式保真CSS画像》§5.3 红线
// 「性能这条不许口头承诺：实现批必须先量 67 万 span 下的分页耗时基线，超预算先立性能专项再谈上屏」）。
//
// 本文件＝**一次性测量工装**，不是常态回归：默认 skip，只在环境变量 LH_ZTJ 指向真《資治通鑑》
// epub 时执行。读数走 `flutter test test/reader_span_baseline_test.dart` 直接 grep 'ZTJ-'
// （ftest.sh 的过滤会吞探针 print，勿经它跑）。
//
// 同一本书、同一 ReaderLayout 三档对照，唯一变量＝TextSpan 有没有 children：
//   A 现状平文本      —— 走生产 EpubPager.paraHeight 原函数（grab 已把内联压平）
//   B 全 span 进 runs —— 按画像实测密度（≈3.3 字/段span·672k runs）把每段拆 children，
//                        样式按通鉴真值轮转（色/注小字 .75em/下划线装饰），确定性 RNG 固定种子
//   C 语义白名单裁剪  —— 仅 ~15% 段带 children（note/comment/reign/gray 系），装饰线走绘制通道不进 runs
// 判定线（工单 §3 实现批开场钉死）：B 全程分页绝对耗时 + B/A 放大比 → 未超＝进样式翻译器批；
// 超＝先立性能专项。字体口径注记：flutter_test 引擎用 Ahem 等宽占位字族，绝对秒与真机（Noto Serif
// SC 回退）有差，但**放大比**是结构成本，跨字族可比——判定优先看比值，绝对值另配真机复测。
@TestOn('windows')
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';

const _defaultPath =
    'D:/dev_workplace/flutter_te/tempWork/新建文件夹/'
    '資治通鑑 ([宋] 司馬光 編集  [元] 胡三省 注) (z-library.sk, 1lib.sk, z-lib.sk).epub';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['LH_ZTJ'] ?? '';
  final has = path.isNotEmpty && File(path).existsSync();

  test('67万span分页耗时基线（三档对照）', () {
    if (!has) {
      // ignore: avoid_print
      print('ZTJ-SKIP 样包未点名：设 env LH_ZTJ 指向样包才跑（默认样包路径参考 $_defaultPath）；'
          '默认不拖全量门禁');
      return;
    }
    final t0 = Stopwatch()..start();
    final doc = EpubDoc.parse(File(path).readAsBytesSync());
    final l = ReaderLayout(width: 393, height: 851);
    final totalParas = doc.chapters.fold<int>(0, (s, c) => s + c.paras.length);
    final totalChars = doc.chapters.fold<int>(
        0, (s, c) => s + c.charCount); // charCount 含标题等，口径够用
    final rng = math.Random(42);

    double plain(EpubPara p) => EpubPager.paraHeight(p, l);

    // B 档：整段拆 children；样式轮转≈通鉴真值（色 navy 1/5 · 注小字 .75em 1/8 · 波浪线 1/6）
    double rich(EpubPara p, {required double keep}) {
      final txt = paraDisplayText(p, indMode: l.indMode, s2t: l.s2t);
      if (txt.isEmpty || rng.nextDouble() > keep) return plain(p);
      final children = <InlineSpan>[];
      var i = 0;
      var k = 0;
      while (i < txt.length) {
        final n = 2 + k % 3; // 3.3 字/span ≈ 2~4 取整均值
        final piece = txt.substring(i, math.min(i + n, txt.length));
        final mod = k % 40;
        children.add(TextSpan(
          text: piece,
          style: mod < 8
              ? l.base.copyWith(color: const Color(0xFF000080))
              : mod < 13
                  ? l.base.copyWith(
                      fontSize: (l.base.fontSize ?? 19) * .75,
                      color: const Color(0xFF006400))
                  : mod < 20
                      ? l.base.copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: const Color(0xFF000000))
                      : null,
        ));
        i += n;
        k++;
      }
      final tp = TextPainter(
        text: TextSpan(style: l.base, children: children),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: l.contentW);
      return tp.height + 7.0; // 同 paraHeight 正文 gap 口径
    }

    double runMode(double Function(EpubPara) h) {
      for (final c in doc.chapters) {
        for (final p in c.paras) {
          h(p);
        }
      }
      return 0;
    }

    final sa = Stopwatch()..start();
    runMode(plain);
    final msA = sa.elapsedMilliseconds;

    final sc = Stopwatch()..start();
    runMode((p) => rich(p, keep: 0.15));
    final msC = sc.elapsedMilliseconds;

    final sb = Stopwatch()..start();
    var worstCh = 0, worstMs = 0, ci = 0;
    for (final c in doc.chapters) {
      final cs = Stopwatch()..start();
      for (final p in c.paras) {
        rich(p, keep: 1.0);
      }
      if (cs.elapsedMilliseconds > worstMs) {
        worstMs = cs.elapsedMilliseconds;
        worstCh = ci;
      }
      ci++;
    }
    final msB = sb.elapsedMilliseconds;

    // ignore: avoid_print
    print('ZTJ-BOOK 章=${doc.chapters.length} 段=$totalParas 字=$totalChars '
        '解析=${t0.elapsedMilliseconds}ms');
    // ignore: avoid_print
    print('ZTJ-A 现状平文本 全程=${msA}ms');
    // ignore: avoid_print
    print('ZTJ-C 白名单裁剪(15%) 全程=${msC}ms 放大=${(msC / math.max(1, msA)).toStringAsFixed(2)}x');
    // ignore: avoid_print
    print('ZTJ-B 全span(≈${(totalChars / 3.3).round() ~/ 10000}万 runs) 全程=${msB}ms '
        '放大=${(msB / math.max(1, msA)).toStringAsFixed(2)}x 最差章#$worstCh=${worstMs}ms');
    // ignore: avoid_print
    print('ZTJ-SPAN 按画像3.3字/span 估算=${(totalChars / 3.3).round()}，画像全书实测 672,124');
  }, skip: false, timeout: const Timeout(Duration(minutes: 25)));
}
