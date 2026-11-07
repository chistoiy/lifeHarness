import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/data/xray/xray_lexicon.dart';

/// X-Ray 词表与三层词库守护（需求 V1.54 · 设计书 §5）
///
/// 词表是**数据资产**而非代码：这里钉的是「装载口径 + 是否真的打进包」，
/// 内容对不对由批1e 的 golden 用例（简史 地名 23/23·小说术语噪声 0/40）负责。
void main() {
  const dir = 'assets/xray/dicts/';

  Map<String, String> readAll() => {
        for (final n in XrayWordBank.assetNames)
          n: File('$dir$n').readAsStringSync(),
      };

  test('八张预置词表全部装载，关键表不空', () {
    final bank = XrayWordBank.parse(readAll());
    expect(bank.funcWords.length, greaterThan(100), reason: '虚词表是 n-gram 首尾过滤的地基');
    expect(bank.commonNouns.length, greaterThan(50));
    expect(bank.titles, contains('先生'));
    expect(bank.locSuffix, contains('省'));
    expect(bank.orgSuffix, contains('公司'));
    expect(bank.stopEn, contains('the'));
    expect(bank.gazetteer.length, greaterThan(100),
        reason: '地名是简史 GT（23/23）的主通道，表缩水=验收基线塌');
  });

  test('姓氏表按长度分流：单姓进集合、复姓进有序表', () {
    final bank = XrayWordBank.parse(readAll());
    expect(bank.singleSurnames, contains('王'));
    expect(bank.compoundSurnames, contains('欧阳'));
    expect(bank.singleSurnames.every((s) => s.length == 1), isTrue);
    expect(bank.compoundSurnames.every((s) => s.length > 1), isTrue);
    // 整体匹配必须长优先，否则「欧阳」会被拆成「欧」+「阳」
    final lens = bank.compoundSurnames.map((s) => s.length).toList();
    final sorted = [...lens]..sort((a, b) => b.compareTo(a));
    expect(lens, sorted, reason: '复姓表未按时长倒序，最长匹配会失效');
  });

  test('地名词典：首字分桶 + 桶内最长优先（替代 §12 明令禁止的大正则）', () {
    final bank = XrayWordBank.parse(readAll());
    final bucket = bank.gazetteerStartingWith('地');
    expect(bucket, contains('地中海'));
    for (var i = 1; i < bucket.length; i++) {
      expect(bucket[i - 1].length, greaterThanOrEqualTo(bucket[i].length));
    }
    expect(bank.gazetteerStartingWith('锘'), isEmpty, reason: '没锚点的首字要空返回而非抛错');
  });

  test('三层词库：GLOBAL 屏蔽生效、按书加词能把常用词救回、按书优先于全局', () {
    final bank = XrayWordBank.parse(readAll());
    final lex = XrayLexicon(
      bank,
      global: const XrayUserLayer(forbidden: {'埃及'}, added: {'时间'}),
      book: const XrayUserLayer(added: {'案子'}, forbidden: {'波洛'}),
    );
    expect(lex.blocked('埃及'), isTrue, reason: 'F8② 永久屏蔽是状态位，不是降分');
    expect(lex.blocked('波洛'), isTrue);
    expect(lex.looksCommonNoun('时间'), isFalse, reason: '用户显式加词要能盖过预置噪声表');
    expect(lex.userAdded('案子'), isTrue);
    // 同词两动作：按书层赢（本书说了算）
    final clash = XrayLexicon(
      bank,
      global: const XrayUserLayer(added: {'尼罗河'}),
      book: const XrayUserLayer(forbidden: {'尼罗河'}),
    );
    expect(clash.blocked('尼罗河'), isTrue);
  });

  test('守护：词表目录已登记进 pubspec（否则 APK 里没有这些文件）', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/xray/'),
        reason: '只放目录不登记=真机 rootBundle 读不到，测试却全绿（本机读磁盘文件）');
  });

  test('守护：词表源文件无重复行、无未登记注释混排', () {
    for (final n in XrayWordBank.assetNames) {
      final lines = File('$dir$n')
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      expect(lines.toSet().length, lines.length, reason: '$n 有重复词：parse 会静默去重掩盖数据问题');
      expect(lines.every((l) => !l.contains(RegExp(r'\s'))), isTrue,
          reason: '$n 某行含空格：一行一词是装载口径，多词行会被当成一个长词');
    }
  });
}
