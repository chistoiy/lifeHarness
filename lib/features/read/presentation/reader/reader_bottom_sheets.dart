import 'package:flutter/material.dart';

/// V1.53.2 轮5.1 · 阅读器弹层（原型 sheetBrProg / sheetBrMore）。
///
/// 口径：轮3 的「底栏内嵌面板」全部升格为正常底部弹层（用户反馈「点击后为什么
/// 要在左侧出现，正常弹窗不行吗」）；底栏只留 目录/进度/外观 三图标，
/// 主题·亮度·字号并进外观弹层（见 reader_appearance_sheet.dart）。

/// 进度弹层数据快照（打开时取一次，弹层内不反向持有页面状态）。
class BrProgData {
  const BrProgData({
    required this.pct,
    required this.eta,
    required this.sessMin,
    required this.notes,
    required this.frac,
    required this.auto,
    required this.homeLbl,
  });

  final int pct;

  /// 读完预估文案（已读完／刚开始读／约 N 分钟后读完…）。
  final String eta;
  final int sessMin;
  final int notes;

  /// 0~1 全书进度（滑条初值）。
  final double frac;
  final bool auto;

  /// 非空＝显示「回到进书位置」（拖离进书位置后才有值 · 轮5.2①）。
  final String? homeLbl;
}

/// 阅读进度弹层：统计三格 + 全书滑条 + 明细/自动翻页 +（离开过才现）回到进书位置。
///
/// 滑条拖离进书位置后「回到进书位置」即时出现（原型 brProgHomeSync），
/// 因此弹层自带滑条值与返回态，读页面用 [homeProbe] 反问。
Future<void> showBrProgressSheet(
  BuildContext context, {
  required BrProgData d,
  required ValueChanged<double> onSeek,
  required VoidCallback onDetail,
  required VoidCallback onAuto,
  required String? Function() homeProbe,
  required VoidCallback onHome,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => _ProgSheet(
    d: d,
    onSeek: onSeek,
    onDetail: onDetail,
    onAuto: onAuto,
    homeProbe: homeProbe,
    onHome: onHome,
  ),
);

class _ProgSheet extends StatefulWidget {
  const _ProgSheet({
    required this.d,
    required this.onSeek,
    required this.onDetail,
    required this.onAuto,
    required this.homeProbe,
    required this.onHome,
  });
  final BrProgData d;
  final ValueChanged<double> onSeek;
  final VoidCallback onDetail;
  final VoidCallback onAuto;
  final String? Function() homeProbe;
  final VoidCallback onHome;

  @override
  State<_ProgSheet> createState() => _ProgSheetState();
}

class _ProgSheetState extends State<_ProgSheet> {
  late double _frac = widget.d.frac;
  late String? _home = widget.d.homeLbl;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          key: const ValueKey('sheetBrProg'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '阅读进度',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stat(context, 'brStPct', '${d.pct}', '%', d.eta),
                _stat(context, 'brStMin', '${d.sessMin}', '分钟', '本次时长'),
                _stat(context, 'brStNote', '${d.notes}', '条', '本书笔记'),
              ],
            ),
            Slider(
              key: const ValueKey('brProg'),
              value: (_frac * 1000).clamp(0, 1000).toDouble(),
              min: 0,
              max: 1000,
              onChanged: (v) {
                setState(() {
                  _frac = v / 1000;
                  _home = widget.homeProbe();
                });
                widget.onSeek(v / 1000);
              },
            ),
            Center(
              child: Text(
                '拖动到全书任意位置 · 目标章节即时实算',
                style: TextStyle(
                  fontSize: 9.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brPpDetail'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onDetail();
                    },
                    child: const Text('阅读明细'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('brPpAuto'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onAuto();
                    },
                    child: Text(d.auto ? '暂停自动翻页' : '开启自动翻页'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_home != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('brProgHome'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .5),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onHome();
                      },
                      child: Text(_home!),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brPpClose'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


Widget _stat(
  BuildContext context,
  String key,
  String big,
  String unit,
  String sub,
) {
  final cs = Theme.of(context).colorScheme;
  return Expanded(
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              big,
              key: ValueKey(key),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              unit,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
        ),
      ],
    ),
  );
}

/// 本书操作弹层（原型 sheetBrMore）：八宫格 + 阅读模式 + 三个跳转行 + 常亮。
Future<void> showBrMoreSheet(
  BuildContext context, {
  required int quotes,
  required String mode,
  required bool bright,
  required VoidCallback onToc,
  required VoidCallback onSearch,
  required VoidCallback onQuotes,
  required VoidCallback onLog,
  required VoidCallback onStat,
  required VoidCallback onDetail,
  required VoidCallback onAppearance,
  required VoidCallback onDelete,
  required VoidCallback onReadSet,
  required ValueChanged<String> onMode,
  required ValueChanged<bool> onBright,
  String? xrStatus,
  VoidCallback? onXray,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (sc) {
    void go(void Function() f) {
      Navigator.of(sc).pop();
      f();
    }

    final td = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          key: const ValueKey('sheetBrMore'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '本书操作',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.25,
              children: [
                _tile(sc, 'brMtToc', '目录', Icons.menu_rounded, () => go(onToc)),
                _tile(
                  sc,
                  'brMtSearch',
                  '检索',
                  Icons.search_rounded,
                  () => go(onSearch),
                ),
                _tile(
                  sc,
                  'brMtQuotes',
                  '书摘',
                  Icons.note_alt_outlined,
                  () => go(onQuotes),
                ),
                _tile(
                  sc,
                  'brMtLog',
                  '记录',
                  Icons.history_rounded,
                  () => go(onLog),
                ),
                _tile(
                  sc,
                  'brMtStat',
                  '统计',
                  Icons.bar_chart_rounded,
                  () => go(onStat),
                ),
                _tile(
                  sc,
                  'brMtDetail',
                  '详情',
                  Icons.description_outlined,
                  () => go(onDetail),
                ),
                _tile(
                  sc,
                  'brMtLook',
                  '外观',
                  Icons.palette_outlined,
                  () => go(onAppearance),
                ),
                _tile(
                  sc,
                  'brMtDel',
                  '删除',
                  Icons.delete_outline_rounded,
                  () => go(onDelete),
                ),
              ],
            ),
            // V1.54 批A · 屏5（more.frag）：全书索引行＋任务态状态字。
            if (onXray != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                key: const ValueKey('brMoreXr'),
                behavior: HitTestBehavior.opaque,
                onTap: () => go(onXray),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('全书索引（X-Ray）',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                      Text(
                        xrStatus ?? '',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('阅读模式', style: TextStyle(fontSize: 12.5)),
                const Spacer(),
                for (final (k, l) in const [('page', '翻页'), ('scroll', '滚动')])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _seg(
                      keyTag: 'brMode-$k',
                      label: l,
                      on: mode == k,
                      cs: td.colorScheme,
                      onTap: () {
                        Navigator.of(sc).pop();
                        onMode(k);
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _row(
              sc,
              'brMnQuotes',
              '本书书摘与划线',
              trailing: Text(
                '$quotes 条',
                style: TextStyle(
                  fontSize: 10.5,
                  color: td.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => go(onQuotes),
            ),
            _row(
              sc,
              'brMnDetail',
              '书籍详情与资料页',
              trailing: const Text('›', style: TextStyle(color: Colors.grey)),
              onTap: () => go(onDetail),
            ),
            _row(
              sc,
              'brMnSet',
              '阅读器设置',
              trailing: const Text('›', style: TextStyle(color: Colors.grey)),
              onTap: () => go(onReadSet),
            ),
            _row(
              sc,
              'brMnBright',
              '屏幕常亮',
              trailing: Switch(
                key: const ValueKey('brMoreBright'),
                value: bright,
                onChanged: (v) {
                  Navigator.of(sc).pop();
                  onBright(v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  },
);

Widget _tile(
  BuildContext sc,
  String key,
  String label,
  IconData icon,
  VoidCallback onTap,
) {
  final cs = Theme.of(sc).colorScheme;
  return GestureDetector(
    key: ValueKey(key),
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: cs.onSurface),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

Widget _seg({
  required String keyTag,
  required String label,
  required bool on,
  required VoidCallback onTap,
  required ColorScheme cs,
}) => GestureDetector(
  key: ValueKey(keyTag),
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: on ? cs.primary.withValues(alpha: .12) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: on ? cs.primary : cs.outlineVariant,
        width: on ? 1.6 : 1,
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: on ? cs.primary : cs.onSurfaceVariant,
      ),
    ),
  ),
);

Widget _row(
  BuildContext sc,
  String key,
  String label, {
  required Widget trailing,
  VoidCallback? onTap,
}) {
  return InkWell(
    key: ValueKey(key),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12.5)),
          ),
          trailing,
        ],
      ),
    ),
  );
}
