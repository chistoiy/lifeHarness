import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// NFC 卡片批1 · 隐私守护（F1-1b · 冻结档 C11：卡号不入日志正文，
/// **UID 指纹与 `tag_key` 原文永不进任何日志（含 debug 级）**）。
///
/// 为什么用「扫源码」而不是「跑起来抓日志」：本项目没有日志总线可 hook，
/// 而这条守护的真实风险是**将来有人顺手加一行 `debugPrint(card.tagKey)`**——
/// 那种改动测试跑起来照样全绿，只有扫源码才抓得到。
///
/// 与 `catch_log_guard_test` 同款手法（扫 `lib/**` 里的日志调用形态）。
void main() {
  // 本仓内可能承载 NFC 卡片数据的文件集合＝`lib/features/nfc/**` 全量。
  // linkage 出口也会拿到卡片行，扫 `lib/shared/linkage/nfc_mounts.dart`。
  const watched = <String>[
    'lib/features/nfc',
    'lib/shared/linkage/nfc_mounts.dart',
  ];

  List<File> dartFilesUnder(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return const <File>[];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  /// 行内去掉注释后再判（注释里的示意代码不算真日志调用，但注释里若写了
  /// 「指纹进日志」的自述说明会被误伤，故这里只保留非注释部分）。
  String codeOnly(String src) => src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('*'))
      .join('\n');

  test('NFC 相关代码里不出现任何日志调用（防止将来顺手加 debugPrint）', () {
    final offenders = <String>[];
    for (final root in watched) {
      for (final f in dartFilesUnder(root)) {
        final src = codeOnly(f.readAsStringSync());
        for (final line in src.split('\n')) {
          final t = line.trim();
          // 日志形态：debugPrint / print / developer.log / AppLog.* / LhLog.*
          final isLog = t.contains('debugPrint(') ||
              t.startsWith('print(') ||
              t.contains('developer.log(') ||
              t.contains('AppLog.') ||
              t.contains('LhLog.');
          if (isLog) {
            offenders.add('${f.path}: ${t.length > 90 ? '${t.substring(0, 90)}…' : t}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'NFC 模块内出现日志调用——卡号/指纹是敏感数据，'
            '要排障请只用 [maskedTagKey] 的脱敏形态');
  });

  test('NFC 相关代码里不出现 tagKey/tag_key 原文的直接插值', () {
    final offenders = <String>[];
    final re = RegExp(r"""\$\{[^}]*\b(tagKey|tag_key)\b[^}]*\}""");
    for (final root in watched) {
      for (final f in dartFilesUnder(root)) {
        final src = f.readAsStringSync();
        for (final line in src.split('\n')) {
          if (re.hasMatch(line)) {
            offenders.add('${f.path}: ${line.trim().length > 90 ? '${line.trim().substring(0, 90)}…' : line.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'tag_key 原文被插进字符串（极可能进日志）——'
            '要排障请用 [maskedTagKey]（只留后 4 位）');
  });

  test('卡片 id 不进日志正文（C11：只记「已触发卡片」不带 id）', () {
    // 本批不做触发放（批2），但「触发日志」这条口径现在就钉住：
    // 一旦批2 写了日志调用，本断言会因 id 出现在插值里而红。
    final offenders = <String>[];
    final re = RegExp(r"""(log|print)[^;]*\$\{[^}]*\bcardId\b""",
        caseSensitive: false);
    for (final root in watched) {
      for (final f in dartFilesUnder(root)) {
        final src = f.readAsStringSync();
        for (final line in src.split('\n')) {
          if (re.hasMatch(line)) offenders.add('${f.path}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'cardId 进了日志');
  });

  test('脱敏函数本体在仓（没有它，将来排障就会退化为打原文）', () {
    final f = File('lib/features/nfc/domain/nfc_card.dart');
    expect(f.existsSync(), isTrue);
    final src = jsonEncode(f.readAsStringSync());
    expect(src.contains('maskedTagKey'), isTrue);
  });
}