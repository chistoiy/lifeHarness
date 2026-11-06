import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/data/xray/xray_engine.dart';
import 'package:lifeharness/features/read/data/xray/xray_lexicon.dart';

// 二期批7 · X-Ray 效率（F7-1）。独立文件·纯函数面（不起 widget，秒级）。
//
// 这一批改的是「白烧」：n-gram 采样闸门没卡住上限（旧写法只在段前判一次，
// 一放行就整段照加，长章把采样冲过上限数倍）。F7-6 的懒构建与记忆化在
// `xray_panel_test` 的列表用例里有行数观测，这里不重复起 widget。

/// 造一段纯汉字长文（避开虚词字，保证 n-gram 候选真的会被计数）。
String _longHan(int n) {
  const pool = '山水风月云雾霜雪花草木林泉石径桥亭台楼阁琴书剑诗酒茶';
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    b.write(pool[i % pool.length]);
  }
  return b.toString();
}

void main() {
  const dir = 'assets/xray/dicts/';
  final bank = XrayWordBank.parse({
    for (final n in XrayWordBank.assetNames) n: File('$dir$n').readAsStringSync(),
  });

  XrayEngine engine({required int cap}) => XrayEngine(
        bank: bank,
        totalChars: 500000,
        maxNgramSampleChars: cap,
      );

  group('F7-1 · n-gram 采样闸门卡在上限内', () {
    test('单章远超上限：采样字符数必须 ≤ maxNgramSampleChars', () {
      const cap = 500;
      final eng = engine(cap: cap);
      // 一章 5000 字＝上限的 10 倍。
      eng.runChapter(XrayChapter(idx: 0, paras: [_longHan(5000)]));
      expect(
        eng.debugSampledChars,
        lessThanOrEqualTo(cap),
        reason: '闸门必须卡在段内——旧写法只在段前判一次，一放行就整段照加，'
            '长章会把采样冲过上限数倍（大书多算数倍 n-gram＝纯白烧 CPU）',
      );
      expect(eng.debugSampledChars, greaterThan(0), reason: '该算的还是要算');
    });

    test('多章累加同样不许越线', () {
      const cap = 800;
      final eng = engine(cap: cap);
      for (var i = 0; i < 8; i++) {
        eng.runChapter(XrayChapter(idx: i, paras: [_longHan(900)]));
      }
      expect(eng.debugSampledChars, lessThanOrEqualTo(cap),
          reason: '章与章之间是累加的，闸门跨章同样要生效');
    });

    test('额度足够时不截断（不许把正常书算少）', () {
      final text = _longHan(300);
      final eng = engine(cap: 100000);
      eng.runChapter(XrayChapter(idx: 0, paras: [text]));
      expect(eng.debugSampledChars, text.length,
          reason: '额度够就必须全算，不能因为改闸门把正常书算少');
    });

    test('到线即停：后续章节不再累加', () {
      const cap = 400;
      final eng = engine(cap: cap);
      eng.runChapter(XrayChapter(idx: 0, paras: [_longHan(2000)]));
      final after = eng.debugSampledChars;
      eng.runChapter(XrayChapter(idx: 1, paras: [_longHan(2000)]));
      expect(eng.debugSampledChars, after, reason: '到线即停，不许再累加');
      expect(after, lessThanOrEqualTo(cap));
    });
  });
}
