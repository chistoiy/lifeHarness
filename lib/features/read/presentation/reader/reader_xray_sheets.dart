/// V1.54 X-Ray 批A · 半屏弹层两件（原型 xrfrag/sheets.frag sheetXrScope / sheetXrFail
/// 的 1:1 落位）：解析范围（当前章/区间/全书＋DocStore 精算预估）与失败/中断
/// （从断点继续/重置/关闭）。从 reader_xray_panel.dart 拆出以守 1200 行体积预算。
library;

import 'package:flutter/cupertino.dart' show CupertinoPicker, FixedExtentScrollController;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/epub_doc.dart';
import '../../data/xray/xray_dao.dart';
import '../../domain/book.dart';
import '../../../../core/theme/app_theme.dart';
import '../read_providers.dart';
import '../read_sheets.dart' show readToast;

class _Ink {
  /// 强调色（F3-3：brand 收 `accent`）：随主题派生。
  static Color accent(BuildContext c) => c.tokens.accent;

  /// 次要小字（F3-1/F3-6）：走主题次文本令牌。
  static Color muted(BuildContext c) => c.tokens.text2;

  static const rose = Color(0xFFF43F5E);
}

// ---------- 屏1 · 解析范围半屏（xrfrag/sheets.frag sheetXrScope） ----------

Future<void> showXrScopeSheet(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
  required EpubDoc doc,
  required String md5,
  required int ci,
}) {
  final total = doc.chapters.length;
  return showModalBottomSheet<void>(
    context: context,
        shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sc) {
      var mode = 'cur';
      var from = ci.clamp(0, total - 1);
      var to = (ci + 3).clamp(0, total - 1);
      return StatefulBuilder(
        builder: (_, setSt) {
          int chars() {
            var n = 0;
            if (mode == 'cur') {
              n = doc.chapterCharCounts[ci];
            } else if (mode == 'all') {
              for (final c in doc.chapterCharCounts) {
                n += c;
              }
            } else {
              final a = from <= to ? from : to;
              final b = from <= to ? to : from;
              for (var i = a; i <= b; i++) {
                n += doc.chapterCharCounts[i];
              }
            }
            return n;
          }

          String fmt(int n) => n >= 10000
              ? '${(n / 10000).toStringAsFixed(1)} 万字'
              : '$n 字';

          String titleOf(int i) => i < doc.chapterTitles.length
              ? doc.chapterTitles[i]
              : '第${i + 1}章';

          Widget opt(String k, String label) {
            final on = mode == k;
            return GestureDetector(
              key: ValueKey('xr-scope-opt-$k'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setSt(() => mode = k),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: on ? _Ink.accent(context) : Theme.of(sc).dividerColor),
                  color: on ? _Ink.accent(context).withValues(alpha: .08) : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      on
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: on ? _Ink.accent(context) : _Ink.muted(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: on ? _Ink.accent(context) : null)),
                    ),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                key: const ValueKey('sheetXrScope'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('解析范围',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text('全书索引 · X-Ray',
                          style: TextStyle(fontSize: 9, color: _Ink.muted(context))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  opt('cur', '当前章 · ${titleOf(ci)}'),
                  opt('range', '章节区间'),
                  opt('all', '全书 · $total 章'),
                  if (mode == 'range')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Text('起',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _Ink.muted(context))),
                          Expanded(child: _chWheel(
                              keyTag: 'xrFrom',
                              count: total,
                              value: from,
                              onChanged: (v) => setSt(() => from = v))),
                          const SizedBox(width: 10),
                          Text('止',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _Ink.muted(context))),
                          Expanded(child: _chWheel(
                              keyTag: 'xrTo',
                              count: total,
                              value: to,
                              onChanged: (v) => setSt(() => to = v))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(sc).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text('预估文本量',
                            style: TextStyle(fontSize: 11, color: _Ink.muted(context))),
                        const Spacer(),
                        Text(fmt(chars()),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('前台轻抽取 · 解析期间书保持可读 · 断点可续',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9, color: _Ink.muted(context))),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.pop(sc),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(sc).dividerColor),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('取消',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          key: const ValueKey('xrScopeGo'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.pop(sc);
                            final (a, b) = mode == 'cur'
                                ? (ci, ci)
                                : mode == 'all'
                                    ? (0, total - 1)
                                    : (from <= to ? from : to,
                                        from <= to ? to : from);
                            ref
                                .read(xraySchedulerProvider)
                                .start(book: book, md5: md5, from: a, to: b);
                            readToast(sc, '解析已启动 · 前台运行不锁阅读');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _Ink.accent(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('开始解析',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 就地内嵌章轮盘（滚轮选择器规范：禁「点击→弹层→再操作」两段式）。
Widget _chWheel({
  required String keyTag,
  required int count,
  required int value,
  required ValueChanged<int> onChanged,
}) {
  return SizedBox(
    height: 120,
    child: CupertinoPicker(
      key: ValueKey(keyTag),
      scrollController:
          FixedExtentScrollController(initialItem: value.clamp(0, count - 1)),
      itemExtent: 28,
      onSelectedItemChanged: onChanged,
      children: [
        for (var i = 0; i < count; i++)
          Center(
            child: Text(
              '第${i + 1}章',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    ),
  );
}

// ---------- 屏7 · 失败/中断半屏（xrfrag/sheets.frag sheetXrFail） ----------

Future<void> showXrFailSheet(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
  required String md5,
  required XrayTaskRow task,
  String? error,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sc) {
      final sched = ref.read(xraySchedulerProvider);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            key: const ValueKey('sheetXrFail'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('解析中断',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  const Text('失败',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: _Ink.rose)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(sc).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '《${book.title}》解析到 ${task.processedCh}/${task.totalCh} 章时中断 · '
                  '断点与已产出实体已保存'
                  '${error == null ? '' : '\n原因：$error'}',
                  style: const TextStyle(fontSize: 11, height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                key: const ValueKey('xrFailRetry'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.pop(sc);
                  sched.resume(book, md5);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _Ink.accent(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '从断点继续 · 第${(task.processedCh + 1).clamp(1, 1 << 30)}章起',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const ValueKey('xrFailReset'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.pop(sc);
                  sched.reset(book.id, md5);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(sc).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('重置索引 · 清全书数据',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const ValueKey('xrFailClose'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(sc),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('关闭',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: _Ink.muted(context))),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
