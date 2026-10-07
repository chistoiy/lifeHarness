import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 共享层数字滚轮（LH-K39 · 健康模块批2 起为全仓唯一滚轮原语）。
/// 就地内嵌（红线：时间/数值输入禁「点击→弹层→再操作」两段式）。
/// 既有三处私有 CWheel（care/days/items）待后续收敛，禁再新增第四份。
///
/// 居中口径：导引线是 `LayoutBuilder` 算出的**选中带**
/// `top = (maxHeight - itemExtent)/2`、高 `itemExtent`，其几何中心即容器中心，
/// 与 CupertinoPicker 的选中项中心天然重合——容器改高也不偏（回归既定坑）。
/// 测试钩子：每项 `ValueKey('${keyPrefix}item$i')`、导引线 `ValueKey('wheel-guide-line')`。
class LHWheel extends StatefulWidget {
  const LHWheel({
    super.key,
    required this.labels,
    required this.initialIndex,
    required this.onSelect,
    this.height = 120,
    this.itemExtent = 34,
    this.keyPrefix,
  });

  final List<String> labels;
  final int initialIndex;
  final ValueChanged<int> onSelect;
  final double height;
  final double itemExtent;

  /// 非空时给第 i 项挂 Key('${keyPrefix}item$i')（测试定位用）。
  final String? keyPrefix;

  @override
  State<LHWheel> createState() => _LHWheelState();
}

class _LHWheelState extends State<LHWheel> {
  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
      initialItem: widget.initialIndex.clamp(0, widget.labels.length - 1));
  // 与控制器同源：`initialIndex` 越界时 CupertinoPicker 实际落在的是夹紧后的档，
  // `_last` 若不夹紧就会把「夹紧」当成用户改动上报（并且会让首帧噪音判据失效）。
  late int _last = widget.initialIndex.clamp(0, widget.labels.length - 1);
  // CupertinoPicker 首帧布局**通常**会自动回调一次，且回调发生在 build scope 内；
  // 直接透传会触发「setState during build」。但「首次回调」不等于「首帧回调」：
  // 实测时柱这类档（24 档、初始 index 7）首帧并不回调，于是用户的第一下真实改动会被
  // 当成首次噪音吞掉——读数纹丝不动，第二下才动。故只在**报的就是初始档**时才吞。
  bool _firstCallback = true;

  @override
  void didUpdateWidget(LHWheel old) {
    super.didUpdateWidget(old);
    final idx = widget.initialIndex.clamp(0, widget.labels.length - 1);
    if (idx != _last && _ctl.hasClients && _ctl.selectedItem != idx) {
      // **先认档再跳**：`jumpToItem` 会让 CupertinoPicker 回调一次这个档，
      // 若 `_last` 还是旧档，那次回调就被当成「用户滚到了这一档」上报给 onSelect——
      // 调用侧据此写库，写库又触发刷新，刷新再跳一次＝回写自循环
      // （健康批3 目标页 DB 作用域档位在 loading 帧被打回首档时实锤：pumpAndSettle 永动）。
      _last = idx;
      _ctl.jumpToItem(idx);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, constraints) {
        return Stack(
          children: [
            CupertinoPicker(
              scrollController: _ctl,
              itemExtent: widget.itemExtent,
              diameterRatio: 1.5,
              backgroundColor: Colors.transparent,
              onSelectedItemChanged: (i) {
                if (_firstCallback) {
                  _firstCallback = false;
                  // 报的就是初始档＝首帧噪音，吞掉（契约：未选中即未上报，见 lh_wheel_test）；
                  // 报了别的档＝真的改动，继续往下走，不能吞。
                  if (i == _last) {
                    _last = i;
                    return;
                  }
                }
                if (i == _last) return;
                _last = i;
                // 惯性滚动结束回调可能落在别的 widget 构建期，统一延一帧再上报。
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onSelect(i);
                });
              },
              children: [
                for (var i = 0; i < widget.labels.length; i++)
                  Center(
                    key: widget.keyPrefix == null
                        ? null
                        : ValueKey('${widget.keyPrefix}item$i'),
                    child: Text(
                      widget.labels[i],
                      style: TextStyle(
                        fontSize: i == _last ? 15 : 15 * .78,
                        fontWeight: i == _last ? FontWeight.w800 : FontWeight.w600,
                        color: i == _last ? scheme.primary : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
              ],
            ),
            Positioned(
              top: (constraints.maxHeight - widget.itemExtent) / 2,
              left: 12,
              right: 12,
              height: widget.itemExtent,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('wheel-guide-line'),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Container(
                    height: 1,
                    color: scheme.primary.withValues(alpha: .18),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// 数字滚轮标签（纯函数；「—」由调用侧置首＝未记录，index 0 读回 null 语义）。
String hourLabel(int h) => '$h 时';
String minuteLabel(int m) => '$m 分';
String cupsLabel(int c) => '$c 杯';
