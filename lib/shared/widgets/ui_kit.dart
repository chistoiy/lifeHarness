import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/logging/app_log.dart';
import '../../core/theme/app_theme.dart';

/// LH UI 原语库（《docs/UI组件规范.md》§七）。
/// 新代码一律优先复用本文件组件；存量重复调用点按两档流程「路过替换」。
/// 微调某类外观时只改本文件/theme 一处，全 app 生效。

/// T7（交互整改批二）：把技术异常转成人话一句话——面向用户，细节留日志页。
///
/// 口径：只翻译「用户能自己处置」的类别（网络/超时/证书/磁盘/权限/取消），
/// 认不出的**原样返回**（不编造解释），由调用方在末尾统一附「详情见日志」。
String humanizeError(Object e) {
  final t = e.toString();
  final low = t.toLowerCase();
  bool has(List<String> keys) {
    for (final k in keys) {
      if (low.contains(k)) return true;
    }
    return false;
  }

  if (e is TimeoutException ||
      has(['timeout', 'timed out', 'deadline exceeded'])) {
    return '请求超时，稍后重试';
  }
  if (e is SocketException ||
      has([
        'socketexception',
        'failed host lookup',
        'connection refused',
        'network is unreachable',
      ])) {
    return '网络连接不上，检查网络或代理后重试';
  }
  if (has(['certificate', 'handshake'])) {
    return '服务器证书校验失败，稍后重试或更换服务地址';
  }
  final status =
      RegExp(r'(?:status(?:Code)?|statusCode)\s*[:=]?\s*(4\d\d|5\d\d)')
          .firstMatch(t)
          ?.group(1);
  if (status != null) {
    final code = int.parse(status);
    if (code == 401 || code == 403) return '服务拒绝访问（$status），检查账号或密钥';
    if (code == 404) return '服务上找不到该路径（404），检查目录或地址';
    if (code >= 500) return '服务端出错（$status），稍后重试';
    return '服务返回异常（$status）';
  }
  if (has(['enospc', 'no space left'])) {
    return '本机存储空间不足，清理后重试';
  }
  if (has(['permission denied', 'eacces'])) {
    return '没有该位置的读写权限';
  }
  if (has(['cancelled'])) return '已取消';
  return t;
}

/// LH-K00 按压反馈原语（T5 · 交互整改批二）：全 app 统一的「按下即微缩」帧反馈。
///
/// 只观察指针、不参与手势竞技场（`Listener`），故与子树里的
/// GestureDetector/InkWell/滚动父级零冲突：按下缩放、抬起/取消复原。
/// 口径＝scale（不用 splash）：本原语要能安全套进横滑列表与卡片，
/// Material splash 需要 Material 祖先且会在滚动面留残影（阅读器毛玻璃教训同族）。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = .96,
  });

  final Widget child;
  final bool enabled;

  /// 按下缩放比例（0.9~1）；越接近 1 越含蓄。
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: widget.enabled ? (_) => _set(true) : null,
        onPointerUp: widget.enabled ? (_) => _set(false) : null,
        onPointerCancel: widget.enabled ? (_) => _set(false) : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// LH-K32 表单就地错误行（T9 · 交互整改批三）：校验失败写在字段旁，不借道提示条。
///
/// 口径：文案沿用原 toast 的短句（只换呈现位置，不加解释）；样式＝弹层内提示行既有
/// 定式（10.5 / w700 / 玫红，见 LH-S03 `_hint`）。`message == null` 时不占位。
/// 输入框类字段优先走框架 `InputDecoration.errorText`；滚轮/选择器这类
/// 「点开后回填」的控件没有失焦语义，用本原语在控件下方补一行。
class FieldError extends StatelessWidget {
  const FieldError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m == null || m.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3, left: 4),
      child: Text(m,
          style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF43F5E))),
    );
  }
}

/// LH-K33 等宽数字作用域（T12 · 交互整改批四）：子树里的数字按等宽字形排，防列抖动。
///
/// 口径：**不换字族**（主题字族、LH-F01 三档角色照旧），只给文本挂 `tnum` 字形特性——
/// 只影响数字的宽度，不动观感，故属纯行为修复、不走原型门。
/// 用法＝在含数字列的页面/卡片外**包一层**，不必逐处改样式：
/// `TextStyle.merge` 对 `fontFeatures` 走「子级没写就沿袭上级」的继承链（已在
/// flutter/painting/text_style.dart 的 merge→copyWith 里核过），
/// 因此页内 `Text(style: TextStyle(fontSize: 13 …))` 这类自带样式也会吃到等宽。
/// 已自写 `fontFeatures` 的存量点（阅读器 chrome/计时 9 处）不受本层影响。
/// 边界：字族本身没有 `tnum` 特性时该特性为空操作——观感不变、列宽仍可能微抖，
/// 这是系统回落字体链（〇A「不随包字体文件」）的已知代价。
class TabularNums extends StatelessWidget {
  const TabularNums({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: const TextStyle(fontFeatures: kTabularNumFeatures),
        child: child,
      );
}

/// [TabularNums] 的字形特性串（单独露出：调用方自带整套 `TextStyle` 时直接引用）。
const List<FontFeature> kTabularNumFeatures = [FontFeature.tabularFigures()];

/// LH-T01 胶囊提示：全局统一深色胶囊 SnackBar（样式基线在 app_theme snackBarTheme）。
class AppToast {
  AppToast._();

  // T4（交互整改批一）：撤销条存续窗口内普通提示不顶掉它——普通 show 挂起排队
  // （只留最新一条），窗口结束自动补挂；撤销条一律显式 `persist: false`
  //（框架默认 persist = action != null，真机反馈「不点撤销就一直挂着」即此）。
  static bool _undoOpen = false;
  static int _undoToken = 0; // 新撤销条顶掉旧条时，旧条退场回调不再关窗
  static (ScaffoldMessengerState, String, int)? _deferred;

  static void show(BuildContext context, String msg, {int ms = 1600}) {
    final messenger = ScaffoldMessenger.of(context);
    if (_undoOpen) {
      _deferred = (messenger, msg, ms); // 排他：不打扰撤销窗口，退场后补挂
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: Duration(milliseconds: ms)));
  }

  /// T7：失败条统一出口——异常转人话（[humanizeError]）＋时长下限 3.2s
  /// （普通提示 1.6s 读不完错误句），技术细节按「双通道」口径落日志页。
  /// [logDetail] 传 null 时按 `'$prefix：$e'` 记一条 [logLevel]；
  /// 调用方**自己已留痕**时传 `log: false`，避免同一失败刷两行。
  static void showError(
    BuildContext context,
    Object e, {
    String prefix = '操作失败',
    String? logDetail,
    LhLevel logLevel = LhLevel.warn,
    bool log = true,
  }) {
    show(context, '$prefix：${humanizeError(e)} · 详情见日志', ms: 3200);
    if (log) AppLog.add(logDetail ?? '$prefix：$e', level: logLevel);
  }

  /// 带「撤销」的提示条（排他基建入口；context 须在弹层 pop 前取好 messenger，
  /// 跨弹层场景改用 [showUndoWith] 直接传 messenger）。
  static void showUndo(
    BuildContext context,
    String msg, {
    String label = '撤销',
    int ms = 4000,
    required void Function() onUndo,
  }) =>
      showUndoWith(ScaffoldMessenger.of(context), msg,
          label: label, ms: ms, onUndo: onUndo);

  static void showUndoWith(
    ScaffoldMessengerState messenger,
    String msg, {
    String label = '撤销',
    int ms = 4000,
    required void Function() onUndo,
  }) {
    final token = ++_undoToken;
    _undoOpen = true;
    void closeWindow() {
      if (token != _undoToken) return; // 已被更新撤销条接管
      _undoOpen = false;
      final d = _deferred;
      _deferred = null;
      if (d != null) {
        d.$1
          ..hideCurrentSnackBar()
          ..showSnackBar(
              SnackBar(content: Text(d.$2), duration: Duration(milliseconds: d.$3)));
      }
    }

    messenger.hideCurrentSnackBar();
    // 关窗时机＝条真正退场（到期/被顶掉/点了撤销）：用 controller.closed 跟随
    // 框架动画时钟，不另起裸 Timer（FakeAsync 下裸定时器会炸测试不变量）。
    final controller = messenger.showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(milliseconds: ms),
      persist: false,
      action: SnackBarAction(
        label: label,
        onPressed: () {
          closeWindow();
          onUndo();
        },
      ),
    ));
    unawaited(controller.closed
        .catchError((Object _) => SnackBarClosedReason.hide)
        .whenComplete(closeWindow));
  }
}

/// LH-K03 胶囊筛选 chip：选中=accent 实底白字，未选=卡底描边。
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? icon;

  /// 置灰不可点（协议锁定态——编辑已建服务时禁改协议，见 R2 项⑤b）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tap = enabled ? onTap : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tap,
      // T5：原语级按压反馈（此前完全无反馈）。
      child: Pressable(
        enabled: enabled,
        child: Opacity(
          opacity: enabled ? 1 : .45,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? tokens.accent : tokens.card,
              borderRadius: BorderRadius.circular(999),
              border: selected ? null : Border.all(color: tokens.cardBorder),
            ),
            child: Text(
              icon == null ? label : '$icon $label',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// LH-K09 横滑选择器（原型 .hpick/.hopt/.hon，V1.50 批3.6 V5）：
/// 横向可滑 + 松手吸附居中，替代上下滚轮 CWheel——左右滑或点选切换，选中项居中
/// accent 高亮。首尾留半格外边距使首末项可真正居中。每项 key=`hopt-<label>` 供测试点选。
class HPick extends StatefulWidget {
  const HPick({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.itemWidth = 76,
    this.height = 40,
  });

  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  final double itemWidth;
  final double height;

  @override
  State<HPick> createState() => _HPickState();
}

class _HPickState extends State<HPick> {
  final ScrollController _ctl = ScrollController();
  late int _cur = widget.index;
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(widget.index, animate: false));
  }

  @override
  void didUpdateWidget(HPick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && widget.index != _cur) {
      _cur = widget.index;
      _center(widget.index, animate: true);
    }
  }

  double _offsetFor(int i) => i * widget.itemWidth;

  void _center(int i, {required bool animate}) {
    if (!_ctl.hasClients || _viewport == 0) return;
    final target =
        (_offsetFor(i) - (_viewport - widget.itemWidth) / 2).clamp(0.0, _ctl.position.maxScrollExtent);
    if (animate) {
      _ctl.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _ctl.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _cur) return;
    setState(() => _cur = i);
    _center(i, animate: true);
    widget.onChanged(i);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(builder: (context, box) {
      _viewport = box.maxWidth;
      final pad = ((_viewport - widget.itemWidth) / 2).clamp(0.0, double.infinity);
      return SizedBox(
        height: widget.height,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            if (_ctl.hasClients) {
              // R3-9：索引与回中必须共用同一居中约定（target＝i*w-pad 的反算＝
              // (offset+pad)/w），否则 end 回调的 animateTo 会把自己喂回去——
              // 真机 16:36:45 自激 855 层栈溢出（日志页 HPick）。
              final pad = (_viewport - widget.itemWidth) / 2;
              final i = ((_ctl.offset + pad) / widget.itemWidth)
                  .round()
                  .clamp(0, widget.items.length - 1);
              if (i != _cur) {
                setState(() => _cur = i);
                widget.onChanged(i);
              }
              // 帧后回调 + 只有「未居中」才回中：收敛后 offset==target，不再产生新 end。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_ctl.hasClients) return;
                final target = (_offsetFor(i) - pad)
                    .clamp(0.0, _ctl.position.maxScrollExtent);
                if ((_ctl.offset - target).abs() > 0.5) {
                  _ctl.animateTo(target,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut);
                }
              });
            }
            return false;
          },
          child: ListView.builder(
            controller: _ctl,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemCount: widget.items.length,
            itemBuilder: (context, i) {
              final on = i == _cur;
              return GestureDetector(
                key: ValueKey('hopt-${widget.items[i]}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _select(i),
                // T5：点选项给按压帧反馈（Listener 不进竞技场，惯性滚动不受影响）。
                child: Pressable(
                  child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: widget.itemWidth,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? tokens.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: on
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .10),
                                blurRadius: 4,
                                offset: const Offset(0, 1))
                          ]
                        : null,
                  ),
                  child: Text(
                    widget.items[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: on
                          ? tokens.accent
                          : Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: .72),
                    ),
                  ),
                ),
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

/// LH-K05 色点图例：`(标签, 颜色)` 横排。
class DotLegend extends StatelessWidget {
  const DotLegend({super.key, required this.items, this.trailing});

  final List<(String, Color)> items;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (label, color) in items)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                const SizedBox(width: 3),
                Text(label, style: TextStyle(fontSize: 9, color: muted)),
              ],
            ),
          ),
        if (trailing != null)
          Text(trailing!, style: TextStyle(fontSize: 9, color: muted)),
      ],
    );
  }
}

/// LH-K06 心情表情行：点选放大 1.25，未选 45% 透明（数据无关，回调下标）。
class MoodRow extends StatelessWidget {
  const MoodRow({
    super.key,
    required this.emojis,
    this.selected,
    required this.onPick,
    this.keyPrefix = 'mood',
  });

  final List<String> emojis;
  final int? selected;
  final ValueChanged<int> onPick;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < emojis.length; i++)
          GestureDetector(
            key: ValueKey('$keyPrefix-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onPick(i),
            child: Pressable(
              // T6：视觉仍 24dp 表情，热区外扩到 44dp 方形（Material 触控下限）。
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AnimatedScale(
                    scale: selected == i ? 1.25 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Opacity(
                      opacity: selected == null || selected == i ? 1 : .45,
                      child:
                          Text(emojis[i], style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// LH-C04 分节卡：描边卡 + 节标题 + 内容（日记模板分节/其他分节表单共用）。
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// LH-L04 空态补录行：描边占位行，点击=补录/添加入口。
class EmptyDashRow extends StatelessWidget {
  const EmptyDashRow({super.key, required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(
          child: Text(text,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}
