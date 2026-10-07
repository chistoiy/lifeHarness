import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/media_item.dart';

/// 影音游条目卡（LH-C14 · 原型 `index-media.html` `.mds-item` 扁平 V3 卡集）。
///
/// 视觉基线＝**与主框架同一扁平语言**（计划 §三 顶部反转横幅：微拟物已由产品否决，
/// Flutter 侧不实现卡带/BOX/双层光影/翻盖动效）。三类形态按原型：
/// 电影·剧集＝3:4 竖版封面 · 音乐＝封套＋探出的黑胶 · 游戏＝16:10 key-art。
/// 无封面时按 [MediaItem.paletteIdx] 取色板（与书籍侧 BS_COV 同构机制，§九.3）。

/// 色板（原型 MD_COV 8 组：渐变起/止；脊面与缩略用止色）。
const kMdsCov = <(Color, Color)>[
  (Color(0xFF6366F1), Color(0xFF312E81)), // indigo
  (Color(0xFF7C3AED), Color(0xFF2E1065)), // violet
  (Color(0xFF0EA5E9), Color(0xFF075985)), // sky
  (Color(0xFFDB2777), Color(0xFF831843)), // pink
  (Color(0xFF059669), Color(0xFF065F46)), // emerald
  (Color(0xFFF59E0B), Color(0xFF92400E)), // amber
  (Color(0xFF475569), Color(0xFF1E293B)), // slate
  (Color(0xFF14B8A6), Color(0xFF115E59)), // teal
];

/// 等宽数字字形（评分读数与「数字用等宽」口径同档＝LH-K33）。
const List<FontFeature> kMediaTabular = [FontFeature.tabularFigures()];

/// 分区徽标底色（原型 st-w/st-i/st-d/st-s 四档语义色）。
Color mdsStateColor(String tone) => switch (tone) {
  'i' => const Color(0xFF6366F1),
  'd' => const Color(0xFF10B981),
  's' => const Color(0xFF94A3B8),
  _ => const Color(0xFFF59E0B),
};

/// 四类线性图标（禁 emoji；Material outlined 族，与底栏图标同口径）。
IconData mdsKindIcon(String kind) => switch (kind) {
  MediaItem.kMovie => Icons.movie_outlined,
  MediaItem.kSeries => Icons.live_tv_outlined,
  MediaItem.kMusic => Icons.album_outlined,
  MediaItem.kGame => Icons.sports_esports_outlined,
  _ => Icons.bookmark_outline,
};

/// 进度条填充色（原型 `.pbar>i` 的 done/give 两档覆写）。
Color mdsProgressColor(BuildContext context, String tone) => switch (tone) {
  'done' => const Color(0xFF10B981),
  'give' => const Color(0xFF94A3B8),
  _ => Theme.of(context).colorScheme.primary,
};

/// 封面本体：本地文件优先，缺失回落色板渐变＋首字水印
/// （不拉第三方 API＝§九.3；读图失败铺底色板，条目仍可见）。
class MdsCoverArt extends StatelessWidget {
  const MdsCoverArt({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final (c1, c2) = kMdsCov[item.paletteIdx];
    final file = item.coverPath;
    final hasFile = file != null && file.isNotEmpty && File(file).existsSync();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
      ),
      child: hasFile
          ? Image.file(
              File(file),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _watermark(),
            )
          : Center(child: _watermark()),
    );
  }

  Widget _watermark() => Text(
    item.title.characters.first,
    style: const TextStyle(
      fontSize: 34,
      height: 1,
      fontWeight: FontWeight.w900,
      color: Colors.white24,
    ),
  );
}

/// 桌面视图条目卡（原型 `.mds-item`／`.vinyl`／`.gmcard` 三形态）。
class MediaItemCard extends StatelessWidget {
  const MediaItemCard({
    super.key,
    required this.item,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
  });

  final MediaItem item;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 卡体 key（测试与真机取证锚点：桌面视图数卡就数这个）。
  Key get cardKey => ValueKey('mds-card-${item.id}');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = item.progressPercent;
    return GestureDetector(
      key: cardKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selectionMode && selected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: .6),
            width: selectionMode && selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: switch (item.kind) {
                MediaItem.kMusic => _vinylFace(context),
                MediaItem.kGame => _gameFace(context),
                _ => _posterFace(context),
              },
            ),
            if (pct != null)
              SizedBox(
                height: 3,
                child: ColoredBox(
                  color: scheme.outlineVariant,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (pct / 100).clamp(0.0, 1.0),
                      child: ColoredBox(
                        color: mdsProgressColor(context, item.progressTone),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 卡底两行文案（标题＋年份·主创），三形态共用同一字号档。
  List<Widget> _textBlock(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = _subLine();
    return [
      Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w800,
          color: item.kind == MediaItem.kMovie || item.kind == MediaItem.kSeries
              ? Colors.white
              : scheme.onSurface,
        ),
      ),
      if (sub.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            color: item.kind == MediaItem.kMovie ||
                    item.kind == MediaItem.kSeries
                ? Colors.white.withValues(alpha: .9)
                : scheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  /// 影视＝3:4 竖版封面＋底部压暗带（原型 `.cover::after` 同向渐变）。
  Widget _posterFace(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MdsCoverArt(item: item),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .06),
                Colors.transparent,
                Colors.black.withValues(alpha: .52),
              ],
              stops: const [0, .42, 1],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        _kindChip(),
        _topRight(context),
        Positioned(
          left: 9,
          right: 9,
          bottom: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _textBlock(context),
          ),
        ),
      ],
    );
  }

  /// 音乐＝封套＋探出的黑胶（原型 `.vinyl`：封套居左 64%、唱片右探）。
  Widget _vinylFace(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (c1, c2) = kMdsCov[item.paletteIdx];
    return ColoredBox(
      color: scheme.surface,
      child: LayoutBuilder(
        builder: (context, c) {
          final side = (c.maxHeight * .58).clamp(0.0, c.maxWidth * .6);
          return Stack(
            children: [
              Positioned(
                left: c.maxWidth * .06,
                top: c.maxHeight * .1,
                width: side,
                height: side,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [c1, c2],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .18),
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: c.maxWidth * .04,
                top: c.maxHeight * .12,
                width: side,
                height: side,
                child: CustomPaint(painter: _VinylPainter(c1, c2)),
              ),
              Positioned(
                left: 9,
                right: 9,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _textBlock(context),
                ),
              ),
              _kindChip(),
              _topRight(context),
            ],
          );
        },
      ),
    );
  }

  /// 游戏＝16:10 key-art＋周目/发行角标（原型 `.gmcard`）。
  Widget _gameFace(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (c1, c2) = kMdsCov[item.paletteIdx];
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c1, c2],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Text(
                      item.title.characters.first,
                      style: const TextStyle(
                        fontSize: 30,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white24,
                      ),
                    ),
                  ),
                  if ((item.publisher ?? '').isNotEmpty)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: _miniTag(item.publisher!, dark: true),
                    ),
                  if (item.playthroughs > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _miniTag('周目 ${item.playthroughs}'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          ..._textBlock(context),
        ],
      ),
    );
  }

  Widget _kindChip() => Positioned(
    top: 7,
    left: 7,
    child: Container(
      key: ValueKey('mds-kind-${item.id}'),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: item.kind == MediaItem.kMovie || item.kind == MediaItem.kSeries
            ? Colors.white.withValues(alpha: .24)
            : const Color(0x470F172A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(mdsKindIcon(item.kind), size: 13, color: Colors.white),
    ),
  );

  /// 右上：管理态给选中圈，在册态给评分＋分区徽标（徽标只读——分区改由
  /// 长按管理条/详情动作面发起，枚举值不当循环钮用）。
  Widget _topRight(BuildContext context) {
    if (selectionMode) {
      return Positioned(
        top: 7,
        right: 7,
        child: Container(
          key: ValueKey('mds-sel-${item.id}'),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? Theme.of(context).colorScheme.primary : Colors.black26,
            border: Border.all(color: Colors.white.withValues(alpha: .9), width: 2),
          ),
          child: selected
              ? const Icon(Icons.check, size: 13, color: Colors.white)
              : null,
        ),
      );
    }
    final rate = item.myRating > 0 ? item.myRating : item.rating;
    return Positioned(
      top: 7,
      right: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (rate > 0)
            Container(
              key: ValueKey('mds-rate-${item.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .34),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                rate.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFeatures: kMediaTabular,
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          const SizedBox(height: 4),
          Container(
            key: ValueKey('mds-state-${item.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item.state,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: mdsStateColor(item.stateTone),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _subLine() => [
    if (item.releaseYear != null && item.releaseYear! > 0) '${item.releaseYear}',
    item.creator,
  ].where((s) => s.trim().isNotEmpty).join(' · ');

  Widget _miniTag(String text, {bool dark = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: dark
          ? Colors.black.withValues(alpha: .42)
          : Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w800,
        color: dark ? Colors.white : const Color(0xFF0F172A),
      ),
    ),
  );
}

/// 黑胶盘面（原型 `.disc`：纹路环＋中心标＋轴孔）。
class _VinylPainter extends CustomPainter {
  const _VinylPainter(this.c1, this.c2);

  final Color c1;
  final Color c2;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF0B1120));
    final groove = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6;
    for (var g = .22; g < .96; g += .07) {
      canvas.drawCircle(center, r * g, groove);
    }
    canvas.drawCircle(
      center,
      r * .3,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ).createShader(Rect.fromCircle(center: center, radius: r * .3)),
    );
    canvas.drawCircle(
      center,
      r * .06,
      Paint()..color = const Color(0xFF0B1120),
    );
  }

  @override
  bool shouldRepaint(covariant _VinylPainter old) =>
      old.c1 != c1 || old.c2 != c2;
}

/// 脊视图行（原型 `.mds-spine`：等宽标题＋右侧副注，色板止色铺底）。
/// 电影没有侧脊＝由架面按 kind 过滤后不出现（刀2 钉这条判定）。
class MediaSpineRow extends StatelessWidget {
  const MediaSpineRow({super.key, required this.item, this.onTap});

  final MediaItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (_, c2) = kMdsCov[item.paletteIdx];
    final sub = switch (item.kind) {
      MediaItem.kSeries => '${item.seasonsCount} 季',
      MediaItem.kMusic => item.creator,
      MediaItem.kGame => item.publisher ?? item.creator,
      _ => '',
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        key: ValueKey('mds-spine-${item.id}'),
        height: 38,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: c2, borderRadius: BorderRadius.circular(2)),
        child: Row(
          children: [
            Icon(mdsKindIcon(item.kind), size: 13, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .6,
                  color: Colors.white,
                ),
              ),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: .7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 列表视图行（原型 `.mds-list-row`：缩略＋标题＋分类型 meta＋分区徽标）。
class MediaListRow extends StatelessWidget {
  const MediaListRow({
    super.key,
    required this.item,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
  });

  final MediaItem item;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey('mds-row-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 40,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kMdsCov[item.paletteIdx].$1,
                      kMdsCov[item.paletteIdx].$2,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(
                  mdsKindIcon(item.kind),
                  size: 14,
                  color: Colors.white70,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.metaLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selectionMode)
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? scheme.primary : scheme.outlineVariant,
              )
            else
              Text(
                item.state,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: mdsStateColor(item.stateTone),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
