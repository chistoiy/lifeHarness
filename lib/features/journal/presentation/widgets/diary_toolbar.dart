import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 日记编辑页工具栏（原型 `diaryToolbar`，§4d ②）：
/// 三组＋组间细竖线；主栏只留 Top5（加粗／待办／相册／拍照／语音），低频（无序列表／引用块）
/// 收进 ⋮；每枚**长按 400ms 出 Tooltip**、松手 1.6s 收起（触屏没有 hover，长按是唯一可行手势）。
///
/// 抽成独立件的理由：页面本体已 1156 行（红线 1200），而这块的本体是长按计时＋浮层定位，
/// 塞回页面会把「正文与保存」的阅读路径挤散。动作全部由宿主传入，本件不读 provider。
class DiaryToolbar extends StatefulWidget {
  const DiaryToolbar({
    super.key,
    required this.onBold,
    required this.onTask,
    required this.onUl,
    required this.onQuote,
    required this.onGallery,
    required this.onCamera,
    required this.onVoice,
    this.onMmCard,
  });

  final VoidCallback onBold;
  final VoidCallback onTask;
  final VoidCallback onUl;
  final VoidCallback onQuote;
  final VoidCallback onGallery;
  final VoidCallback onCamera;

  /// 语音＝V1.x 占位（原型同为 disabled 态，点它给「敬请期待」）。
  final VoidCallback onVoice;

  /// 插导图卡片（连接点②）：与列表/引用同属「低频」，收进 ⋮ 展开行，不占主栏 Top5。
  final VoidCallback? onMmCard;

  @override
  State<DiaryToolbar> createState() => _DiaryToolbarState();
}

class _DiaryToolbarState extends State<DiaryToolbar> {
  bool _moreOpen = false;

  /// 哪一枚的 tooltip 正亮着（null＝都不亮）。
  String? _tip;

  /// 长按计时：按住满 400ms 才亮；不到 400ms 松手＝普通点击，提示不闪。
  Timer? _hold;
  Timer? _hide;

  @override
  void dispose() {
    _hold?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  /// 长短按共用一枚钮：按下起 400ms 计时；**抬起时看是否已出提示**——
  /// 已出＝只出提示不执行动作（长按的语义就是「问这是什么」）。
  /// 用 Listener 而非 GestureDetector 的 onLongPress：后者到阈值会吃掉 onTap，
  /// 但我们要的是「恰好过 400ms 才亮」，指针计时更直接、也不与 `InkWell` 抢手势。
  Widget _btn(String key, Widget icon, String tip, VoidCallback onTap) {
    return Listener(
      key: ValueKey('diary-tb-$key'),
      onPointerDown: (_) {
        _hold?.cancel();
        _hold = Timer(const Duration(milliseconds: 400), () {
          if (mounted) _tipOn(key);
        });
      },
      onPointerUp: (_) {
        final fired = _tip == key;
        _hold?.cancel();
        if (fired) return;
        _hide?.cancel();
        if (_tip != null) setState(() => _tip = null);
        onTap();
      },
      onPointerCancel: (_) => _hold?.cancel(),
      child: SizedBox(
        width: 36,
        height: 32,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Center(child: icon),
            if (_tip == key) _bubble(tip, 'diary-tip-$key'),
          ],
        ),
      ),
    );
  }

  void _tipOn(String key) {
    _hold?.cancel();
    _hide?.cancel();
    setState(() => _tip = key);
    _hide = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _tip = null);
    });
  }

  Widget _bubble(String tip, String key) {
    // 反色气泡＝`inverseSurface` / `onInverseSurface`（浅档深底白字、深档白底深字）。
    // 原先写死 `#0F172A` / `#E2E8F0` / `Colors.white` 三枚字面量，四主题 × 明暗下
    // 不跟令牌走，还撞色值棘轮闸——反色语义本来就有现成令牌。
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 34,
      child: Container(
        key: ValueKey(key),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(tip,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: scheme.onInverseSurface)),
      ),
    );
  }

  Widget _sep() => Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        color: context.tokens.cardBorder,
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = Theme.of(context).colorScheme.onSurfaceVariant;
    final bold = Text('B',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: fg));
    final task = Text('☑', style: TextStyle(fontSize: 15, color: fg));
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.cardBorder)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                _btn('bold', bold, '加粗', widget.onBold),
                _btn('task', task, '待办勾选', widget.onTask),
                _sep(),
                _btn('album', Icon(Icons.image_outlined, size: 17, color: fg), '相册',
                    widget.onGallery),
                _btn('camera', Icon(Icons.photo_camera_outlined, size: 17, color: fg),
                    '拍照', widget.onCamera),
                _btn(
                    'voice',
                    Opacity(opacity: .45, child: Icon(Icons.mic_none, size: 17, color: fg)),
                    // 不写「· V1.x」：U5 禁词闸不许把版本占位露给用户；
                    // 未开放这件事由 45% 透明 + 点击提示表达。
                    '语音',
                    widget.onVoice),
                const Spacer(),
                _btn('more', Icon(Icons.more_vert, size: 17, color: fg), '更多排版',
                    () => setState(() => _moreOpen = !_moreOpen)),
              ],
            ),
          ),
          if (_moreOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                key: const ValueKey('diary-tb-more-row'),
                children: [
                  _btn('ul', Text('≡', style: TextStyle(fontSize: 16, color: fg)),
                      '无序列表', widget.onUl),
                  _btn('quote', Text('❝', style: TextStyle(fontSize: 15, color: fg)),
                      '引用块', widget.onQuote),
                  if (widget.onMmCard != null)
                    _btn('mm',
                        Icon(Icons.account_tree_outlined, size: 17, color: fg),
                        '导图卡片', widget.onMmCard!),
                  const SizedBox(width: 4),
                  Text('块级排版',
                      style: TextStyle(fontSize: 10, color: fg.withValues(alpha: .7))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
