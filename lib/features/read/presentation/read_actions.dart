import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/book.dart';
import 'read_providers.dart';
import 'read_sheets.dart';

/// 读书计时起停（工作台今日卡 / 详情页顶栏 / 书脊行共用一处语义 · §3.4）。
/// 在跑→结束并回显；未在跑→对目标书（或最近阅读的在读书）开始。
Future<void> readTimerTap(
    WidgetRef ref, BuildContext context, {Book? target}) async {
  final repo = ref.read(readRepositoryProvider);
  final running = await repo.runningSession();
  if (running != null) {
    final closed = await repo.endSession(running.bookId);
    ref.read(readTickProvider.notifier).state++;
    final books = await repo.allBooks();
    if (!context.mounted) return;
    final name = books
        .where((b) => b.id == running.bookId)
        .firstOrNull
        ?.title;
    readToast(
        context,
        closed == null
            ? '《$name》计时已取消'
            : '《$name》已结束计时 · ${bsFmt(closed.minutes)}');
    return;
  }
  var book = target;
  if (book == null) {
    final all = await repo.allBooks();
    final ing = ShelfSort.byLastRead(all
        .where((b) => b.state == Book.kStateReading && !b.isDeleted)
        .toList());
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
