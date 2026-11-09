import '../../../core/notifications/notification_service.dart';
import '../data/care_repository.dart';

/// V1.57 B 批 · 儿保体检节点提醒（care.rm.checkup 接真排程）。
///
/// 节点表按生长曲线既有月龄节点取（42 天产后复查 + 3/6/8/12/18 月龄），
/// 以当前宝宝出生日期推算；排最近一个未达节点当天 09:00 送达 · 受全局
/// 免打扰顺延；测试环境 ready=false 时排程静默降级，「排程调用」以返回
/// 文本为断言面，真实送达属真机验收项。
class CareCheckupNode {
  const CareCheckupNode(this.label, {this.months = 0, this.days = 0});

  final String label;
  final int months;
  final int days;
}

const kCareCheckupNodes = [
  CareCheckupNode('42 天体检', days: 42),
  CareCheckupNode('3 月龄体检', months: 3),
  CareCheckupNode('6 月龄体检', months: 6),
  CareCheckupNode('8 月龄体检', months: 8),
  CareCheckupNode('12 月龄体检', months: 12),
  CareCheckupNode('18 月龄体检', months: 18),
];

DateTime checkupDate(DateTime birth, CareCheckupNode n) =>
    DateTime(birth.year, birth.month + n.months, birth.day)
        .add(Duration(days: n.days));

/// 最近一个未达节点；全部已过（>18 月龄）返回 null。
(CareCheckupNode, DateTime)? nextCheckup(DateTime birth, DateTime now) {
  for (final n in kCareCheckupNodes) {
    final at = checkupDate(birth, n);
    if (at.isAfter(now)) return (n, at);
  }
  return null;
}

/// 体检提醒重排（开关关 / 无宝宝档案 / 节点全过 → 取消并不排）。
/// 返回已排文案（null＝未排），供用例断言「排程调用」。
Future<String?> syncCareCheckup(
  CareRepository repo, {
  DateTime? now,
  bool dnd = false,
}) async {
  final rm = await repo.reminderKvs();
  final on = (rm['care.rm.checkup'] ?? 'false') == 'true';
  Future<void> cancelAll() =>
      NotificationService.cancel(NotificationService.careCheckupId);
  if (!on) {
    await cancelAll();
    return null;
  }
  final id = await repo.curBabyId();
  final baby =
      (await repo.babies()).where((b) => b.id == id).firstOrNull;
  if (baby == null) {
    await cancelAll();
    return null;
  }
  final next = nextCheckup(baby.birth, now ?? DateTime.now());
  if (next == null) {
    await cancelAll();
    return null;
  }
  final at = next.$2;
  final when = DateTime(at.year, at.month, at.day, 9);
  final body = '「${baby.name}」${next.$1.label} · ${at.month}月${at.day}日';
  await NotificationService.scheduleOnce(
    id: NotificationService.careCheckupId,
    title: '儿保体检提醒',
    body: body,
    when: when,
    dnd: dnd,
  );
  return body;
}
