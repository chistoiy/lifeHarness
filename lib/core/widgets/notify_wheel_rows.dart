import 'package:flutter/material.dart';

import '../../shared/widgets/lh_wheel.dart';
import '../theme/app_theme.dart';
import 'wheel_time.dart';

/// 反馈批3 · 提醒通知页就地滚轮编辑行（原型 `p-sub-notify` 的
/// `#nfDiaryBox` / `#nfDndBox`）。
///
/// 红线：在卡片内点开就地展开，**不做「点击→弹层→再操作」两段式**；
/// 滚轮滑动只改本行草稿，按「确定」才经 `onApply` 落库并重排提醒。
/// 两行共用同一副行壳与同一套键名，页面侧只负责接线。

String twoDigits(int v) => v.toString().padLeft(2, '0');

/// 免打扰窗口文案（与 `NotificationService.inDndWindow` 同判据：起＝止＝空窗口）。
/// 起止只存整点，健康页的 `mdDndTx` 亦按整点采样反推文案，故这里不引入分钟。
String dndWindowLabel(int start, int end) => start == end
    ? '未设置免打扰时段'
    : '${twoDigits(start)}:00 – ${twoDigits(end)}:00';

/// 行壳：标签 + 当前值按钮；展开后在卡片内嵌双列滚轮与「确定」。
class _WheelField extends StatefulWidget {
  const _WheelField({
    required this.label,
    required this.value,
    required this.keyName,
    required this.wheel,
    required this.onConfirm,
  });

  final String label;
  final String value;
  final String keyName;
  final Widget Function() wheel;
  final VoidCallback onConfirm;

  @override
  State<_WheelField> createState() => _WheelFieldState();
}

class _WheelFieldState extends State<_WheelField> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            InkWell(
              key: ValueKey('${widget.keyName}-value'),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(widget.value,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.accent)),
              ),
            ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 4),
          Container(
            key: ValueKey('${widget.keyName}-box'),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              border: Border.all(color: tokens.cardBorder),
            ),
            child: Row(
              children: [
                Expanded(child: SizedBox(height: 96, child: widget.wheel())),
                const SizedBox(width: 8),
                TextButton(
                  key: ValueKey('${widget.keyName}-confirm'),
                  onPressed: () {
                    widget.onConfirm();
                    setState(() => _open = false);
                  },
                  child: const Text('确定', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 晚间复盘提醒时间：时/分双列，24×60 任一时刻可任选（默认 21:30）。
/// 原四档常量 21:00/21:30/22:00/22:30 已撤。
class DiaryTimeWheelRow extends StatefulWidget {
  const DiaryTimeWheelRow({
    super.key,
    required this.value,
    required this.onApply,
  });

  final String value;
  final ValueChanged<String> onApply;

  @override
  State<DiaryTimeWheelRow> createState() => _DiaryTimeWheelRowState();
}

class _DiaryTimeWheelRowState extends State<DiaryTimeWheelRow> {
  late int _h;
  late int _m;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DiaryTimeWheelRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _sync();
  }

  void _sync() {
    final p = widget.value.split(':');
    _h = (int.tryParse(p.first) ?? 21).clamp(0, 23);
    _m = (int.tryParse(p.length > 1 ? p[1] : '0') ?? 30).clamp(0, 59);
  }

  @override
  Widget build(BuildContext context) => _WheelField(
        label: '晚间复盘提醒时间',
        value: widget.value,
        keyName: 'nf-diary',
        // 滚轮回调只写草稿、不 setState：`InlineWheelTime` 的回调来自滚动通知，
        // 在 build scope 里 setState 会炸；选中态由它自己的 ValueNotifier 换样式。
        wheel: () => InlineWheelTime(
          key: const ValueKey('nf-diary-wheel'),
          initial: TimeOfDay(hour: _h, minute: _m),
          onChanged: (h, m) {
            _h = h;
            _m = m;
          },
        ),
        onConfirm: () =>
            widget.onApply('${twoDigits(_h)}:${twoDigits(_m)}'),
      );
}

/// 免打扰时段：起/止两列整点滚轮，跨午夜与同日窗口都按半开区间判定。
class DndWindowWheelRow extends StatefulWidget {
  const DndWindowWheelRow({
    super.key,
    required this.startHour,
    required this.endHour,
    required this.onApply,
  });

  final int startHour;
  final int endHour;
  final void Function(int start, int end) onApply;

  @override
  State<DndWindowWheelRow> createState() => _DndWindowWheelRowState();
}

class _DndWindowWheelRowState extends State<DndWindowWheelRow> {
  static final List<String> _hours =
      List<String>.generate(24, (i) => twoDigits(i));
  late int _s;
  late int _e;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DndWindowWheelRow old) {
    super.didUpdateWidget(old);
    if (old.startHour != widget.startHour || old.endHour != widget.endHour) {
      _sync();
    }
  }

  void _sync() {
    _s = widget.startHour.clamp(0, 23);
    _e = widget.endHour.clamp(0, 23);
  }

  @override
  Widget build(BuildContext context) => _WheelField(
        label: '免打扰时段',
        value: dndWindowLabel(widget.startHour, widget.endHour),
        keyName: 'nf-dnd',
        wheel: () => Row(
          children: [
            Expanded(
              child: LHWheel(
                keyPrefix: 'nf-dnd-s',
                labels: _hours,
                initialIndex: _s,
                height: 96,
                itemExtent: 30,
                onSelect: (i) => setState(() => _s = i),
              ),
            ),
            const Text('–',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Expanded(
              child: LHWheel(
                keyPrefix: 'nf-dnd-e',
                labels: _hours,
                initialIndex: _e,
                height: 96,
                itemExtent: 30,
                onSelect: (i) => setState(() => _e = i),
              ),
            ),
          ],
        ),
        onConfirm: () => widget.onApply(_s, _e),
      );
}
