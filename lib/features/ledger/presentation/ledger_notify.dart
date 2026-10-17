import '../../../core/logging/app_log.dart';
import '../../../core/notifications/notification_service.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';

/// V1.57 B 批 · 记账两枚通知排程（拍板记录 §九）。
///
/// 口径：
/// · 预算超支提醒＝支出达本期预算 80% 与 100% **各一次**；已发档位按
///   `ledger.budFired.<账本>.<月份>` KV 去重，跨周期（换月）自然重置；
///   免打扰（23:00–07:00）开启时顺延送达。
/// · 月度小结＝每月 1 日 09:00 一次性排程；每次启动/开关变化重排并刷新内容
///   （送达时的「上月」＝排程时的当月口径，重启越频内容越新，属既定降级面）。
/// · 测试环境 NotificationService.ready=false → 排程静默降级；本文件的
///   「排程调用」以返回计划文本 + key 行日志为断言面，真实送达属真机验收项。

/// 本档期应发档位（80/100；total<=0 无预算不提醒；已发档剔除）。
List<int> budgetStagesToFire({
  required double exp,
  required double total,
  required Set<int> already,
}) {
  if (total <= 0) return [];
  final pct = exp / total * 100;
  return [80, 100].where((s) => pct >= s && !already.contains(s)).toList();
}

Set<int> parseFiredStages(String? raw) => {
      for (final p in (raw ?? '').split(','))
        if (int.tryParse(p.trim()) case final int v) v,
    };

/// 月度小结送达时点：下一个「1 日 09:00」（当月 1 日 09:00 未到用当月，否则次月）。
DateTime nextDigestAt(DateTime now) {
  final firstThisMonth = DateTime(now.year, now.month, 1, 9);
  if (now.isBefore(firstThisMonth)) return firstThisMonth;
  return DateTime(now.year, now.month + 1, 1, 9);
}

/// 记账保存后检查预算档位（新增/编辑流水均调用）。返回本次实际触发的档位。
Future<List<int>> checkBudgetAlert(
  LedgerRepository repo, {
  DateTime? now,
  bool dnd = false,
}) async {
  if (!await repo.budgetAlert()) return [];
  final t = now ?? DateTime.now();
  final bk = await repo.curBookId();
  final month = monthKey(t);
  final txns = (await repo.bookTxns(bk))
      .where((x) => x.date.startsWith(month))
      .toList();
  final exp = mStat(txns).exp;
  final total = (await repo.budgetOf(bk, month)).total;
  final key = 'ledger.budFired.$bk.$month';
  final already = parseFiredStages(await repo.kv(key));
  final fire = budgetStagesToFire(exp: exp, total: total, already: already);
  for (final s in fire) {
    final body = '本期预算已用 ${(exp / total * 100).toStringAsFixed(0)}% · '
        '${money(exp)} / ${money(total)}';
    await NotificationService.showBudgetAlert(
      id: s == 80 ? NotificationService.ledgerBud80Id
          : NotificationService.ledgerBud100Id,
      body: body,
      dnd: dnd,
    );
    AppLog.addKey('预算超支提醒触发：$s% 档 · $month · 支出 ${money(exp)}',
        src: '记账');
    already.add(s);
    await repo.setKv(key, (already.toList()..sort()).join(','));
  }
  return fire;
}

/// 月度小结重排：开关开＝按下一 1 日 09:00 排程并返回文案；关＝取消并返回 null。
Future<String?> syncMonthlyDigest(
  LedgerRepository repo, {
  DateTime? now,
  bool dnd = false,
}) async {
  if (!await repo.monthlyDigest()) {
    await NotificationService.cancel(NotificationService.ledgerDigestId);
    return null;
  }
  final t = now ?? DateTime.now();
  final when = nextDigestAt(t);
  // 送达时点所在月的上一月＝小结口径月。
  final sumMonth = monthKey(when.subtract(const Duration(days: 1)));
  final bk = await repo.curBookId();
  final txns = (await repo.bookTxns(bk))
      .where((x) => x.date.startsWith(sumMonth))
      .toList();
  final st = mStat(txns);
  final cats = catStat(txns);
  final topName = cats.isEmpty
      ? null
      : (await repo.cats())
          .where((c) => c.id == cats.first.$1)
          .map((c) => c.name)
          .firstOrNull;
  final body = '「$sumMonth」收支已收官 · 支出 ${money(st.exp)} · '
      '收入 ${money(st.inc)}'
      '${topName == null ? '' : ' · 大头「$topName」'}';
  await NotificationService.scheduleOnce(
    id: NotificationService.ledgerDigestId,
    title: '记账月度小结',
    body: body,
    when: when,
    dnd: dnd,
  );
  return body;
}
