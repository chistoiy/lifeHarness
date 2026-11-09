import 'dart:convert';

import '../../../core/logging/app_log.dart';

/// 条目「一页总结」（影音游批4b · 三行感想，存 `media_items.final_note` 的 JSON 三键）。
///
/// 零迁移：列早就存在（`MediaItem.fromMap`/`toMap` 已透传），本类只钉「JSON 三键」
/// 这一种编码——键名固定 a/b/c，三行文案按 kind 换词属 UI 侧（A3）的事：
/// - [decode] 容错：非 JSON 旧裸文本／顶层非对象／缺键一律读成空，**不抛**
///   （一条脏行不许炸掉详情页；回落留痕走 AppLog，守 catch_log_guard）；
/// - 空不落列：[isEmpty] 时由保存侧写 NULL 而不是 `"{}"` 占位
///   （与 `external_ids` 列「空即 null」同一纪律）。
class MediaSummary {
  const MediaSummary({this.a = '', this.b = '', this.c = ''});

  final String a;
  final String b;
  final String c;

  bool get isEmpty => a.isEmpty && b.isEmpty && c.isEmpty;

  /// final_note 原始值 → 三键。脏值（裸文本/坏 JSON/非对象）按空处理并记一条 warn。
  static MediaSummary decode(String? raw) {
    if (raw == null || raw.isEmpty) return const MediaSummary();
    try {
      final d = jsonDecode(raw);
      if (d is! Map) {
        // 顶层非对象（数字/裸字符串/数组）＝不是本编码写的，按「无总结」处理并留痕。
        AppLog.add('media summary decode：final_note 非对象，按空处理',
            level: LhLevel.warn);
        return const MediaSummary();
      }
      return MediaSummary(
        a: '${d['a'] ?? ''}',
        b: '${d['b'] ?? ''}',
        c: '${d['c'] ?? ''}',
      );
    } catch (e) {
      AppLog.add('media summary decode：final_note 非 JSON，按空处理: $e',
          level: LhLevel.warn);
      return const MediaSummary();
    }
  }

  /// 三键 → final_note 原文。全空由调用侧落 NULL（本方法不产 `{}` 语义空串）。
  String encode() => jsonEncode({'a': a, 'b': b, 'c': c});
}
