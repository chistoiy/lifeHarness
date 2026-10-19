import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';
import '../diary_edit_page.dart';
import '../journal_providers.dart';

/// M1批2c · 回顾底部弹层（原型 sheetDiaryReview）：
/// 月份切换 ‹ YYYY年M月 › + 心情趋势柱状（CustomPaint·高度=心情1~7）
/// + 词云（高频词字号分级·无图表依赖）+ 去年本月卡（点按打开该篇）。
/// UI/UX批（2026-10-12）：逐柱/逐词可点对齐原型、月份切换有界（限往前 12 个月禁未来）。
///
/// **设计评审治理批（原型 `b1fe7386` · 本文件 2026-10-19 跟进）**：此前实现只跟到 M1/UIUX 批，
/// 治理批改的原型 `.dr-*` 一套令牌**从未落到 Flutter 侧**——真机上「回顾还没改」就是这个原因。
/// 已按原型逐项对齐（数值见各常量注释）：
/// - 面板 24px 顶圆角 / 内边距 `24·20·32`；蒙层 `rgba(15,23,42,.4)`；
/// - 标题 18px·w500（原 16px·w900）；月份钮 32×32 圆角 10（原 IconButton 48）；
/// - 卡片**去边框**改 `0 1px 8px` 淡阴影（原来是 `Border.all` —— 这是最扎眼的一条）；
/// - 卡片小标题 15px·w400（原 12.5px·w800）；
/// - 趋势图高 56（原型 `h-14`，原 96 太高）；
/// - 心情图例＝**右下角三档精简**（原 7 枚表情全列，治理时明确要求删掉的）；
/// - 「那年今日」独立卡：小标题 + `1 年前 · MM-DD` 副行 + `.dr-quote` 引用块（淡底＋左侧竖线）。
Future<void> openDiaryReview(BuildContext context, {DateTime? month}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // 蒙层 rgba(15,23,42,.4)（原型 .dr-scrim）；不设则默认蒙层偏浅、与原型不一。
      barrierColor: _kScrimColor,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (bc, scrollCtrl) => _drPanel(
          ctx,
          _DiaryReview(month ?? DateTime.now(), scrollCtrl),
        ),
      ),
    );

/// 原型 `.dr-panel`：24px 顶圆角 + 内边距 `24·20·32` + 卡片底色。
Widget _drPanel(BuildContext context, Widget child) {
  final tokens = context.tokens;
  final dark = ThemeData.estimateBrightnessForColor(tokens.page) ==
      Brightness.dark;
  return Container(
    decoration: BoxDecoration(
      color: dark ? _kPanelDark : Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: child,
  );
}

/// UI/UX批（2026-10-12）· 日记篇目选择半屏：单篇直开、多篇列选。
/// 主屏月历色条（该日多篇）与回顾弹层词云（含词篇目）共用；空列表不弹。
Future<void> openDiaryPickSheet(
    BuildContext context, String title, List<JournalEntry> entries) async {
  if (entries.isEmpty) return;
  if (entries.length == 1) {
    final e = entries.first;
    context.push('/journal/edit', extra: DiaryEditArg(entryId: e.id));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    builder: (bc) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          for (final e in entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                  '${e.day.year}-${e.day.month.toString().padLeft(2, '0')}-'
                  '${e.day.day.toString().padLeft(2, '0')} '
                  '${e.day.hour.toString().padLeft(2, '0')}:${e.day.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              subtitle: Text(
                e.content.isEmpty ? '（只打了心情卡）' : e.previewText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: moodEmoji(e.mood) == null ? null : Text(moodEmoji(e.mood)!),
              onTap: () {
                Navigator.of(bc).pop();
                context.push('/journal/edit', extra: DiaryEditArg(entryId: e.id));
              },
            ),
        ],
      ),
    ),
  );
}

/// 回顾弹层的原型色值（`b1fe7386` 治理批 `.dr-*` 令牌）。
///
/// 收成一处而不是散在渲染代码里：`color_ratchet` 守护按「硬编码色值处数」记账，
/// 散写会让同一个色重复计数、且改原型色时要追着改好几处。
const _kScrimColor = Color(0x66151F31); // 原型 .dr-scrim{background:rgba(15,23,42,.4)}
const _kPanelDark = Color(0xFF0F172A); // 深档面板底（原型 dark:bg-slate-900）
const _kGrabLight = Color(0xFFDCDFE6); // 原型 .dr-grab 浅档
const _kGrabDark = Color(0x29FFFFFF); // 原型 html.dark .dr-grab = rgba(255,255,255,.16)
const _kShadowLight = Color(0x0F0F172A); // rgba(15,23,42,.05)
const _kShadowDark = Color(0x47000000); // rgba(0,0,0,.28)

class _DiaryReview extends ConsumerStatefulWidget {
  const _DiaryReview(this.month, this.scrollCtrl);

  final DateTime month;
  final ScrollController scrollCtrl;

  @override
  ConsumerState<_DiaryReview> createState() => _DiaryReviewState();
}

class _DiaryReviewState extends ConsumerState<_DiaryReview> {
  static const _palette = [
    Color(0xFF6366F1), Color(0xFF2DD4BF), Color(0xFFF59E0B),
    Color(0xFFFB7185), Color(0xFF8B5CF6), Color(0xFF0EA5E9), Color(0xFFF43F5E),
  ];

  late DateTime _m = widget.month;

  /// UI/UX批：月份偏移有界（对齐原型 drMonth：当月 0、最早往前 11 个月）。
  int _off = 0;

  Future<List<JournalEntry>> _load() =>
      ref.read(journalRepositoryProvider).month(_m);

  void _shift(int delta) => setState(() {
        final next = _off + delta;
        if (next > 0 || next < -11) return; // 禁未来 · 限往前 12 个月
        _off = next;
        _m = DateTime(widget.month.year, widget.month.month + _off);
      });

  /// UI/流畅批：同月内重复 build 不重建 future（切月才重查）。
  Future<List<JournalEntry>>? _lastYearFut;
  String? _lastYearKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<JournalEntry>>(
      key: ValueKey('${_m.year}-${_m.month}'),
      future: _load(),
      builder: (bc, snap) {
        final entries = snap.data ?? const <JournalEntry>[];
        // UI/流畅批：逐日首篇 map 建一次（趋势柱绘制与点按命中共用，
        // 词云词表也算一次——原 build 每帧 _topWords 两遍）。
        final byDay = <int, JournalEntry>{};
        for (final e in entries) {
          byDay.putIfAbsent(e.day.day, () => e); // 同日多篇取首篇（列表新→旧）
        }
        final words = _topWords(entries);
        return ListView(
          controller: widget.scrollCtrl,
          // 原型 `.dr-panel{padding:24px 20px 32px}`。
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            // 原型 `.dr-grab{width:40px!important;height:4px;background:#DCDFE6}`。
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: _grabberColor(tokens),
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
            // 原型 `.dr-grab{margin:0 auto 14px}`。
            const SizedBox(height: 14),
            // 标题 + 月份切换（原型：.dr-title 18px/w500 + .dr-navbtn 32×32 + .dr-month 13px/w600 宽72）
            Row(
              key: const ValueKey('dr-head'),
              children: [
                Expanded(
                  child: Text('回顾',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -.18,
                          color: tokens.ink)),
                ),
                _navBtn(
                    key: const ValueKey('dr-prev'),
                    icon: Icons.chevron_left,
                    enabled: _off > -11,
                    onTap: () => _shift(-1),
                    tokens: tokens),
                SizedBox(
                  width: 72,
                  child: Text('${_m.year}-${_m.month.toString().padLeft(2, '0')}',
                      key: const ValueKey('dr-month-label'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: tokens.text2)),
                ),
                _navBtn(
                    key: const ValueKey('dr-next'),
                    icon: Icons.chevron_right,
                    enabled: _off < 0,
                    onTap: () => _shift(1),
                    tokens: tokens),
              ],
            ),
            const SizedBox(height: 16),
            _card(bc, tokens, scheme, '心情趋势', [
              // UI/UX批：逐柱可点对齐原型——命中按 x 折算日号，有记录日直开该篇
              //（同日多篇取首篇，与绘制口径一致），无记录淡条不可点。
              LayoutBuilder(
                builder: (lc, cons) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final days = DateTime(_m.year, _m.month + 1, 0).day;
                    final day = (d.localPosition.dx / cons.maxWidth * days).floor() + 1;
                    final e = byDay[day];
                    if (e == null) return;
                    Navigator.of(bc).pop();
                    context.push('/journal/edit',
                        extra: DiaryEditArg(entryId: e.id));
                  },
                  child: SizedBox(
                    key: const ValueKey('dr-trend'),
                    // 原型 `h-14`＝56px（原实现 96 太高，治理件要求压扁）。
                    height: 56,
                    child: CustomPaint(
                        size: const Size(double.infinity, 56),
                        painter: _TrendPainter(month: _m, byDay: byDay)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 原型：图例靠右下角（`justify-end`），且**只三档**（低落/一般/愉悦）——
              // 治理件明确删掉了原来那一排 7 枚连续表情。
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  key: const ValueKey('dr-legend'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, name) in const [
                      (0, '低落'),
                      (3, '一般'),
                      (6, '愉悦'),
                    ]) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: _palette[i], shape: BoxShape.circle)),
                      const SizedBox(width: 3),
                      Text(name,
                          style: TextStyle(
                              fontSize: 11,
                              color: tokens.text2.withValues(alpha: .8))),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(_summary(entries),
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: tokens.text2.withValues(alpha: .85))),
            ]),
            const SizedBox(height: 16),
            // 原型文案＝「词云 · 本月高频」
            _card(bc, tokens, scheme, '词云 · 本月高频', [
              Wrap(
                key: const ValueKey('dr-cloud'),
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // UI/UX批：逐词可点对齐原型——点开本月含词篇目（单篇直开/多篇列选）。
                  for (final (w, freq) in words)
                    GestureDetector(
                      onTap: () {
                        final hits = entries
                            .where((e) => e.plainBody.contains(w))
                            .toList();
                        if (hits.isEmpty) return;
                        Navigator.of(bc).pop();
                        openDiaryPickSheet(context, '含「$w」的日记', hits);
                      },
                      child: Text(w,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: _fs(freq),
                              height: 1.3,
                              color: Color.lerp(scheme.onSurface,
                                  tokens.accent, _fs(freq) / 24))),
                    ),
                ],
                // 空月份兜底
              ),
              if (words.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('本月文字还太少 · 多写几篇再回来看',
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
                ),
            ]),
            const SizedBox(height: 12),
            _lastYearCard(bc, tokens, scheme),
          ],
        );
      },
    );
  }

  /// 原型 `.dr-grab` 拖拽条色：浅档 `#DCDFE6`，深档 `rgba(255,255,255,.16)`。
  static Color _grabberColor(ThemeTokens t) {
    final dark =
        ThemeData.estimateBrightnessForColor(t.page) == Brightness.dark;
    return dark ? _kGrabDark : _kGrabLight;
  }

  /// 原型 `.dr-card` / 那年今日卡的极淡浮起阴影。
  /// **注意浅档必须几乎无感**（`rgba(15,23,42,.05)`）——治理件要的是「靠阴影轻轻浮起」，
  /// 加重就变成卡片描边效果，与原型不同。
  static List<BoxShadow> _cardShadow(bool dark) => dark
      ? const [
          BoxShadow(color: _kShadowDark, blurRadius: 10, offset: Offset(0, 2)),
        ]
      : const [
          BoxShadow(color: _kShadowLight, blurRadius: 8, offset: Offset(0, 1)),
        ];

  /// 原型 `.dr-navbtn`：32×32、圆角 10、无默认水波纹外扩（原 IconButton 是 48×48 且带 padding，
  /// 把月份挤得很散）。禁用时降到 `.25` 透明度，与原型 `disabled` 观感一致。
  Widget _navBtn({
    required Key key,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required ThemeTokens tokens,
  }) {
    return Opacity(
      opacity: enabled ? 1 : .25,
      child: InkResponse(
        key: key,
        onTap: enabled ? onTap : null,
        radius: 18,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
          ),
          // 原型 `.dr-navbtn` 字号 18、色 `rgba(100,116,139,.75)`。
          child: Icon(icon,
              size: 18, color: tokens.text2.withValues(alpha: .75)),
        ),
      ),
    );
  }

  Widget _card(
      BuildContext bc, ThemeTokens tokens, ColorScheme scheme, String title,
      List<Widget> body) {
    final dark =
        ThemeData.estimateBrightnessForColor(tokens.page) == Brightness.dark;
    return Container(
      // 原型 `.dr-card{padding:14px;border-radius:16px;border:none;
      //   box-shadow:0 1px 8px <淡>}` —— **无边框**，靠极淡阴影浮起。
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _cardShadow(dark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 原型 `.dr-sub`：15px / w400（次级说明色），不是加粗小标题。
          Text(title,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w400, color: tokens.text2)),
          const SizedBox(height: 8),
          ...body,
        ],
      ),
    );
  }

  /// 去年本月卡：repo.range 取去年同月条目，点最新一篇进编辑。
  Widget _lastYearCard(
      BuildContext bc, ThemeTokens tokens, ColorScheme scheme) {
    final key = '${_m.year - 1}-${_m.month}';
    if (key != _lastYearKey) {
      _lastYearKey = key;
      _lastYearFut =
          ref.read(journalRepositoryProvider).month(DateTime(_m.year - 1, _m.month, 1));
    }
    return FutureBuilder<List<JournalEntry>>(
      future: _lastYearFut,
      builder: (bc2, snap) {
        final old = snap.data ?? const <JournalEntry>[];
        if (old.isEmpty) return const SizedBox.shrink();
        final latest = old.last; // range 升序 → 末条=最新
        final dark =
            ThemeData.estimateBrightnessForColor(tokens.page) == Brightness.dark;
        final mmdd = '${latest.day.month.toString().padLeft(2, '0')}-'
            '${latest.day.day.toString().padLeft(2, '0')}';
        // 原型「那年今日」独立卡：`.dr-sub` 小标题 + `.dr-note` 副行 + `.dr-quote` 引用块。
        return GestureDetector(
          key: const ValueKey('dr-yoy'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Navigator.of(bc2).pop();
            bc.push('/journal/edit', extra: DiaryEditArg(entryId: latest.id));
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: _cardShadow(dark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('那年今日',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: tokens.text2)),
                const SizedBox(height: 4),
                Text('1 年前 · $mmdd',
                    style: TextStyle(
                        fontSize: 12,
                        color: tokens.text2.withValues(alpha: .75))),
                const SizedBox(height: 6),
                // 原型 `.dr-quote`：`--accent-06` 淡底 + 左侧 **2px `--accent-28`** 竖线，
                // 圆角 `0 10px 10px 0`、内边距 `8px 10px 8px 12px`。
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: dark ? .10 : .06),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    border: Border(
                      left: BorderSide(
                          width: 2,
                          color: tokens.accent.withValues(alpha: .28)),
                    ),
                  ),
                  child: Text(
                    latest.previewText.replaceAll('\n', ' ').clamp40(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, height: 1.65, color: tokens.ink),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _summary(List<JournalEntry> entries) {
    final counts = <int, int>{};
    var chars = 0;
    for (final e in entries) {
      if (e.mood != null) counts[e.mood!] = (counts[e.mood!] ?? 0) + 1;
      chars += e.plainBody.replaceAll(RegExp(r'\s'), '').length;
    }
    if (entries.isEmpty) return '本月还没有记录 · 从写今天的日记开始';
    final top = counts.entries.isEmpty
        ? null
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return '本月记录 ${entries.length} 篇 · 共 $chars 字'
        '${top == null ? '' : ' · 心情以 ${moodEmoji(top)} ${moodLabel(top)} 居多'}';
  }

  /// 高频词：ASCII 词 + 中文 2-gram（去停用字），按频次取前 12。
  static List<(String, int)> _topWords(List<JournalEntry> entries) {
    const stop = {
      '的', '了', '是', '在', '我', '有', '和', '就', '不', '人', '都', '一',
      '上', '也', '很', '到', '说', '要', '去', '会', '着', '没', '看', '好',
      '自己', '这', '那', '他', '她', '它', '们', '个', '吗', '呢', '吧', '把',
    };
    final freq = <String, int>{};
    final re = RegExp(r"[a-zA-Z]{2,}|[\u4e00-\u9fff]+");
    for (final e in entries) {
      for (final m in re.allMatches(e.plainBody)) {
        final t = m.group(0)!;
        if (t.codeUnitAt(0) < 0x4e00) {
          final w = t.toLowerCase();
          freq[w] = (freq[w] ?? 0) + 1;
        } else if (t.length == 1 && !stop.contains(t)) {
          freq[t] = (freq[t] ?? 0) + 1;
        } else {
          for (var i = 0; i + 2 <= t.length; i++) {
            final g = t.substring(i, i + 2);
            if (!stop.contains(g[0]) || !stop.contains(g[1])) {
              freq[g] = (freq[g] ?? 0) + 1;
            }
          }
        }
      }
    }
    final list = freq.entries.where((x) => x.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final x in list.take(12)) (x.key, x.value)];
  }

  static double _fs(int freq) =>
      freq >= 8 ? 22 : freq >= 5 ? 17 : freq >= 3 ? 14 : 11.5;
}

/// 心情趋势柱：当月每天一根，高度=心情 1~7（无记录=12% 淡条）。
/// UI/流畅批：逐日 map 由 build 侧建一次传入（绘制与点按命中共用）。
class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.month, required this.byDay});

  final DateTime month;
  final Map<int, JournalEntry> byDay;

  static const _palette = [
    Color(0xFF6366F1), Color(0xFF2DD4BF), Color(0xFFF59E0B),
    Color(0xFFFB7185), Color(0xFF8B5CF6), Color(0xFF0EA5E9), Color(0xFFF43F5E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final slot = size.width / days;
    final w = (slot * 0.62).clamp(2.0, 14.0);
    for (var d = 1; d <= days; d++) {
      final e = byDay[d];
      final mood = e?.mood;
      final h = mood == null
          ? size.height * 0.12
          : size.height * (0.3 + mood / kJournalMoods.length * 0.7);
      final paint = Paint()
        ..color = mood == null
            ? const Color(0x1F000000)
            : _palette[(mood - 1) % _palette.length];
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH((d - 1) * slot + (slot - w) / 2, size.height - h, w, h),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.month != month || !identical(old.byDay, byDay);
}

extension on String {
  String clamp40() => length <= 40 ? this : '${substring(0, 40)}…';
}
