import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/book.dart';
import 'read_providers.dart';
import 'read_sheets.dart';

/// 读书计时起停（工作台今日卡 / 胶囊态顶栏 / 书脊行共用一处语义 · §3.4）。
/// 在跑→结束并回显（read.autoAsk 开启时结束即弹记进度）；
/// 未在跑→对目标书（或最近阅读的在读书）开始。
Future<void> readTimerTap(
  WidgetRef ref,
  BuildContext context, {
  Book? target,
}) async {
  final repo = ref.read(readRepositoryProvider);
  final running = await repo.runningSession();
  if (running != null) {
    final closed = await repo.endSession(running.bookId);
    ref.read(readTickProvider.notifier).state++;
    final books = await repo.allBooks();
    if (!context.mounted) return;
    final book = books.where((b) => b.id == running.bookId).firstOrNull;
    final name = book?.title;
    readToast(
      context,
      closed == null
          ? '《$name》计时已取消'
          : '《$name》已结束计时 · ${bsFmt(closed.minutes)}',
    );
    if (closed != null &&
        book != null &&
        await ref.read(autoAskProvider.future)) {
      if (context.mounted) showProgressSheet(context, ref, book);
    }
    return;
  }
  var book = target;
  if (book == null) {
    final all = await repo.allBooks();
    final ing = ShelfSort.byLastRead(
      all.where((b) => b.state == Book.kStateReading && !b.isDeleted).toList(),
    );
    book = ing.isEmpty ? null : ing.first;
  }
  if (book == null) {
    if (context.mounted) readToast(context, '书架上暂时没有在读的书');
    return;
  }
  await repo.startSession(book.id);
  ref.read(readTickProvider.notifier).state++;
  if (context.mounted) readToast(context, '已为《${book.title}》开始计时');
}

/// 详情页顶栏计时钮入口（§3.3 计时形态可切换）：
/// 全屏＝跳沉浸计时页（页内起停）；顶部胶囊＝原地起停 + 顶部长胶囊。
Future<void> readTimerEntry(WidgetRef ref, BuildContext context, Book b) async {
  final ui = await ref.read(timerUIProvider.future);
  if (!context.mounted) return;
  if (ui == '全屏') {
    final running = await ref.read(readRepositoryProvider).runningSession();
    if (!context.mounted) return;
    if (running != null && running.bookId == b.id) {
      // 已在计时：再点直接结束（与胶囊一致的回停语义）
      await readTimerTap(ref, context, target: b);
      return;
    }
    context.push('/read/timer/${b.id}');
    return;
  }
  await readTimerTap(ref, context, target: b);
}
