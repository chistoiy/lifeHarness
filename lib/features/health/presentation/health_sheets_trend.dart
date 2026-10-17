part of 'health_sheets.dart';
// ==================== 健康周报弹层（批6a · 原型 `sheetHealthReport`） ====================

/// 弹层只画不算：六枚 tile、同比上周五行、七日条、结论句全部来自 `trWeekReport`（域层单源）。
///
/// **命名让路**：`showHealthReportSheet` 已被批3.5b 的「检查报告」弹层占用（`health_sheets_report.dart`），
/// 本枚是**周报**，叫 `showHealthWeekReportSheet`，两张弹层不同事、别互相顶名。
///
/// 三条口径写在最近处：
/// · **同比上周必须现算**——原型 `hrDiff` 那五行（`+0.4 h`／`−0.6 杯`…）是写死的演示常量，
///   实现取上一段同七天对差；上周无记录出「—」，不出现 `NaN`（工单 §2）；
/// · **长图分享不铺假入口**——原型那颗按钮只是 `toast(…模拟)`，本期只有「复制文本」真写剪贴板，
///   长图另立工单走截图合成（登记偏离）；
/// · 全部本机计算、无网络上传（需求 176 行），脚注把这句写实。
Future<void> showHealthWeekReportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _HealthReportSheet(),
  );
}

class _HealthReportSheet extends ConsumerWidget {
  const _HealthReportSheet();

  static const Key kTiles = ValueKey('hr-tiles');
  static const Key kDiffs = ValueKey('hr-diffs');
  static const Key kBars = ValueKey('hr-bars');
  static const Key kCopy = ValueKey('hr-copy');
  static const Key kVerdict = ValueKey('hr-verdict');
  static const Key kRange = ValueKey('hr-range');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final days = ref.watch(healthTrendProvider(7)).valueOrNull ?? const <TrDay>[];
    final goals = ref.watch(healthTrGoalsProvider);
    final now = ref.watch(healthClockProvider)();
    if (days.isEmpty) {
      return _sheetShell(context, title: '健康周报', children: [
        const EmptyDashRow(text: '本周还没有健康记录 · 记一笔后再来看摘要'),
      ]);
    }
    final split = trSplitDays(days, 7);
    final rep = trWeekReport(
        thisWeek: split.cur, lastWeek: split.prev, goals: goals, now: now);

    return _sheetShell(context, title: '健康周报', children: [
      Row(
        children: [
          const Spacer(),
          Text(rep.rangeTx,
              key: kRange, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
      const SizedBox(height: 8),
      _reportCard(context, rep),
      const Padding(
        padding: EdgeInsets.fromLTRB(0, 12, 0, 4),
        child: Text('同比上周', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      ),
      Column(key: kDiffs, children: [for (final d in rep.diffs) _diffRow(context, d)]),
      const Padding(
        padding: EdgeInsets.fromLTRB(0, 12, 0, 4),
        child: Text('指标构成（本周）', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      ),
      Column(key: kBars, children: [for (final b in rep.bars) _barRow(context, b)]),
      const SizedBox(height: 8),
      const Text('全部本机计算 · 无网络上传',
          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: kCopy,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: rep.copyText));
            if (context.mounted) AppToast.show(context, '周报文本已复制');
          },
          child: const Text('复制文本'),
        ),
      ),
    ]);
  }

  /// 渐变摘要卡（原型 `hrCard`）：周号＋标题＋六枚 tile＋结论句。
  Widget _reportCard(BuildContext context, TrWeekReport rep) {
    final a = context.tokens.accent;
    final onGrad = Theme.of(context).colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, Color.lerp(a, Colors.black, .35)!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LifeHarness · ${rep.weekTx}',
              style: TextStyle(
                  fontSize: 11, color: onGrad.withValues(alpha: .8))),
          const SizedBox(height: 2),
          Text('本周健康摘要',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: onGrad)),
          const SizedBox(height: 10),
          GridView.count(
            key: kTiles,
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.9,
            children: [
              for (final t in rep.tiles)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: onGrad.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900, color: onGrad)),
                      Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 9, color: onGrad.withValues(alpha: .8))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(rep.verdictTx,
              key: kVerdict,
              style: TextStyle(fontSize: 10, color: onGrad.withValues(alpha: .85))),
        ],
      ),
    );
  }

  Widget _diffRow(BuildContext context, TrDiff d) {
    final scheme = Theme.of(context).colorScheme;
    final good = d.tag == '好';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(d.name,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))),
          Text(d.delta, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(d.tag,
                key: ValueKey('hr-diff-tag-${d.name}'),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: good
                        ? const Color(0xFF10B981)
                        : (d.tag == '注意' ? const Color(0xFFF59E0B) : scheme.onSurfaceVariant))),
          ),
        ],
      ),
    );
  }

  Widget _barRow(BuildContext context, TrBar b) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(b.label,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              return Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (b.score / 100).clamp(0.0, 1.0),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: b.score >= TrGoals.scoreGoalPct
                            ? const Color(0xFF34D399)
                            : (b.score >= 55 ? const Color(0xFF34D399).withValues(alpha: .6) : const Color(0xFFFCD34D)),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 32,
            child: Text('${b.score.toStringAsFixed(0)}%',
                key: ValueKey('hr-bar-${b.label}'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
