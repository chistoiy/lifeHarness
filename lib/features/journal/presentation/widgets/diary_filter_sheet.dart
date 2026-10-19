import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/diary_filter_kit.dart';
import '../../domain/journal_entry.dart';

/// 日记筛选弹层（批2c 重做 · 批2d 补时间段）。
///
/// 原实现是一列 `ListTile`（每项 48px 独占一行），标签还硬编码只取前 4 条；
/// 原型早已改成「标记／标签两段 32px 胶囊横排 + 标签超一行折叠」，
/// 本文件把这一面补上，弹层高度从「6 项吃掉 288px」收到两组各一行。
///
/// 批2d（2026-10-19）再补第三段「时间段」——**此前根本没实现**，
/// 筛选只有标记与标签两维，原型里 8 档预设 + 自定义起止的能力在实现侧整段缺失。
/// 三条口径来自产品令，别顺手改：
/// ① **不超一行时不出「展开全部」按钮、也不裁剪**（按钮本身不占位、不多占一行）；
/// ② 展开状态在切筛选项后**保持**（用户展开过就该一直展开）——故选中只改本地态
///    与 settings，不弹关弹层；
/// ③ 选中即生效（列表在弹层后面实时跟着变），底部给实时计数与重置。
///
/// 时间段与标记/标签是**正交的三维**：`diaryInRange` 先过，再 `diaryHit` 判后两维
/// （顺序照原型 `dwHit`：时间段是硬的前提，不满足连标签都不用看）。
Future<void> showDiaryFilterSheet(
  BuildContext context, {
  required String cur,
  required String range,
  required String from,
  required String to,
  required List<String> tags,
  required List<JournalEntry> entries,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _DiaryFilterSheet(
      cur: cur,
      range: range,
      from: from,
      to: to,
      tags: tags,
      entries: entries,
    ),
  );
}

class _DiaryFilterSheet extends ConsumerStatefulWidget {
  const _DiaryFilterSheet({
    required this.cur,
    required this.range,
    required this.from,
    required this.to,
    required this.tags,
    required this.entries,
  });

  final String cur;
  final String range;
  final String from;
  final String to;
  final List<String> tags;
  final List<JournalEntry> entries;

  @override
  ConsumerState<_DiaryFilterSheet> createState() => _DiaryFilterSheetState();
}

class _DiaryFilterSheetState extends ConsumerState<_DiaryFilterSheet> {
  late String _cur = widget.cur;
  late String _range = widget.range;
  late String _from = widget.from;
  late String _to = widget.to;

  /// 标签段是否展开。默认折叠一行；切筛选项**不重置**（口径②）。
  bool _tagOpen = false;

  /// 当前三项条件下的篇数——底部计数与小注共用一个值，避免两处各算一遍再错开。
  int _count() => widget.entries
      .where((e) =>
          diaryInRange(e, range: _range, from: _from, to: _to) &&
          diaryHit(e, _cur))
      .length;

  /// 选中即生效：写 settings（冷启动恢复）+ 本地态（弹层不关，好看实时计数）。
  void _pick(String key) {
    setState(() => _cur = key);
    ref.read(settingsControllerProvider.notifier).setJournalFilter(key);
  }

  Future<void> _pickRange(String k) async {
    setState(() => _range = k);
    await ref.read(settingsControllerProvider.notifier).setJournalRange(k);
  }

  /// 选一端日期。**只改本地态不落盘**——落盘发生在点「应用」时
  /// （原型 `dfCustomSet` 也只重渲染，`dfCustomApply` 才切档）。
  Future<void> _pickDate(bool isFrom) async {
    final cur = DateTime.tryParse(isFrom ? _from : _to);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: cur ?? now,
      firstDate: DateTime(now.year - 30, 1, 1),
      // 不能选未来：日记是「已经发生过的事」，允许选明天会让「近 7 天」筛出空集。
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: isFrom ? '选择起始日期' : '选择结束日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = dfIsoDate(picked);
      } else {
        _to = dfIsoDate(picked);
      }
    });
  }

  void _applyCustom() {
    if (!dfRangeValid(from: _from, to: _to)) return;
    setState(() => _range = kDiaryRangeCustom);
    ref.read(settingsControllerProvider.notifier).setJournalCustom(_from, _to);
  }

  /// 重置＝**三维全清**（标记回全部、时间段回全部、起止清空）。
  /// 只清标记不清时间段的话，用户点「重置」后仍看着被时间筛过的列表，会以为重置坏了。
  void _reset() {
    setState(() {
      _cur = 'all';
      _range = 'all';
      _from = '';
      _to = '';
    });
    ref.read(settingsControllerProvider.notifier).resetJournalFilter();
  }

  /// 量一段文字在胶囊字号下的宽——只用于折行估算，故与渲染同字体同字号。
  double _textW(String s, {required bool bold}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: kDfChipFontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final tags = widget.tags;
    final count = _count();

    return Container(
      key: const ValueKey('df-sheet'),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text('筛选',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                GestureDetector(
                  key: const ValueKey('df-close'),
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close,
                      size: 18, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _groupTitle('标记', scheme),
                    Wrap(
                      spacing: kDfChipGap,
                      runSpacing: kDfChipGap,
                      children: [
                        for (final k in kDfMarkKeys)
                          _chip(
                            key: 'df-mark-$k',
                            label: dfMarkLabel(k),
                            icon: _markIcon(k),
                            on: _cur == k,
                            onTap: () => _pick(k),
                          ),
                      ],
                    ),
                    _groupTitle('标签', scheme),
                    if (tags.isEmpty)
                      Text(
                        '还没有标签 · 正文里写 #标签，保存时会自动归入筛选',
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: scheme.onSurfaceVariant),
                      )
                    else
                      _tagSection(tags, scheme),
                    _groupTitle('时间段', scheme),
                    _rangeSection(scheme),
                    const SizedBox(height: 10),
                    _customRow(scheme),
                    const SizedBox(height: 6),
                    Text(
                      _rangeNote(count),
                      key: const ValueKey('df-range-note'),
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: scheme.onSurfaceVariant.withValues(alpha: .9)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: scheme.onSurfaceVariant.withValues(alpha: .12)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    dfCountLabel(
                      n: count,
                      mark: _cur,
                      range: _range,
                      from: _from,
                      to: _to,
                    ),
                    key: const ValueKey('df-count'),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
                _resetBtn(scheme),
                const SizedBox(width: 8),
                _doneBtn(tokens, scheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTitle(String text, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1,
            color: scheme.onSurfaceVariant.withValues(alpha: .85),
          ),
        ),
      );

  IconData _markIcon(String k) => switch (k) {
        'starred' => Icons.favorite_border,
        'liked' => Icons.star_border,
        'todo' => Icons.check_box_outlined,
        _ => Icons.circle_outlined,
      };

  /// 标签段：一行以内直接铺开；超一行折叠成一行 + 末尾「展开全部 (N)」。
  ///
  /// 折叠**不靠「先裁再量」**（原型三次实错的坑，见 `diary_filter_kit` 文件头）：
  /// 先按容器宽度算行数，再决定挂不挂裁剪与按钮。
  Widget _tagSection(List<String> tags, ColorScheme scheme) {
    return LayoutBuilder(
      builder: (c, cons) {
        final widths = [
          for (final t in tags)
            dfChipWidth(_textW(t, bold: _cur == t)),
        ];
        final over = dfTagsOverflow(widths, cons.maxWidth);
        final chips = [
          for (final t in tags)
            _chip(
              key: 'df-tag-$t',
              label: t,
              icon: Icons.sell_outlined,
              on: _cur == t,
              onTap: () => _pick(_cur == t ? 'all' : t),
            ),
        ];
        // 口径①：一行以内——原样铺开，按钮不出现（也就不会多占一行）。
        if (!over) {
          return Wrap(spacing: kDfChipGap, runSpacing: kDfChipGap, children: chips);
        }
        // 展开态：全量折行铺开，按钮跟在末尾（随流换行，不另起一行）。
        if (_tagOpen) {
          return Wrap(
            spacing: kDfChipGap,
            runSpacing: kDfChipGap,
            children: [...chips, _moreBtn(tags.length, scheme)],
          );
        }
        // 折叠态：只露一整行（定高 32 + 裁掉溢出），按钮固定在行尾。
        return Row(
          children: [
            Expanded(
              child: ClipRect(
                // 常驻键：断言「折叠态只剩一行」靠它量高度（32），
                // 展开/不超一行时它整棵都不在树里——「不裁剪」也就有了可测判据。
                key: const ValueKey('df-tag-clip'),
                child: SizedBox(
                  height: kDfChipH,
                  child: Wrap(
                    spacing: kDfChipGap,
                    runSpacing: kDfChipGap,
                    children: chips,
                  ),
                ),
              ),
            ),
            const SizedBox(width: kDfChipGap),
            _moreBtn(tags.length, scheme),
          ],
        );
      },
    );
  }

  /// 时间段段（原型 `#dfRange`）：8 档预设胶囊**单行横滑** ＋ 行尾「自定义」。
  ///
  /// 口径来自原型的设计注释原文（`index-journal.html:1164`）：「② 时间段改为**紧凑单行**
  /// ＋自定义起止日期」——但原型自己的实现是 `flex flex-wrap`，400px 框架下实测折成
  /// **2 排**（4+4，76px），注释与实现又是一处自相矛盾。按**注释/产品口径**落成单行：
  /// 9 枚胶囊在 360dp 内容宽里绝不可能并排装下，单行的唯一实现是横滑（原型面板本来
  /// 就挂 `no-scrollbar`，即「横滑不带滚动条」是这套的口径）。
  ///
  /// 代价是右半截档位看不见 ⇒ 右缘加一道渐隐（`ShaderMask` 只做蒙版、不写死色值），
  /// 提示「后面还有，可以继续滑」。**不要改回 `Wrap`**：一旦改回就是 2~3 排，
  /// 正是真机 6195 上被产品点名的「时间选择做成多行」。
  ///
  /// 「自定义」胶囊的常驻条件是**选过起止**（`_from`/`_to` 任一非空），不是
  /// 「当前在 custom 档」——原型 `renderDiaryRange` 每次重建 innerHTML 只铺 8 档，
  /// 一旦切回预设档那枚胶囊就再也不出现，用户上次选的区间成了点不到的死数据。
  Widget _rangeSection(ColorScheme scheme) {
    final hasCustom =
        _range == kDiaryRangeCustom || _from.isNotEmpty || _to.isNotEmpty;
    final pills = <Widget>[
      // 顺序即 [kDiaryRanges] 字面序：`全部` 在最前（默认最常用），其余跨度递增。
      for (final r in kDiaryRanges)
        _pill(
          key: 'df-range-${r.k}',
          label: r.n,
          on: _range == r.k,
          onTap: () => _pickRange(r.k),
        ),
      if (hasCustom)
        _pill(
          key: 'df-range-custom',
          label: '自定义',
          on: _range == kDiaryRangeCustom,
          onTap: () => _pickRange(kDiaryRangeCustom),
        ),
    ];
    return SizedBox(
      height: kDfPillH,
      child: ShaderMask(
        // dstIn 只看蒙版 alpha：左 88% 全保留，最右 12% 淡到透明。
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, .88, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          key: const ValueKey('df-range-scroll'),
          scrollDirection: Axis.horizontal,
          // 胶囊自带内边距，行内只留间距；纵向不需要滚动。
          child: Row(
            children: [
              for (var i = 0; i < pills.length; i++) ...[
                if (i > 0) const SizedBox(width: kDfChipGap),
                pills[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 段尾小注（原型 `#dfRangeNote`）：说清「这一档现在意味着什么」。
  ///
  /// 文案用的 N 与底部计数**同源**（都是 [count]）。原型这里用的是 `dwShown()`
  /// 全条件计数，文案却写「该时间段内共 N 篇」——照抄会让「选了 7 天 + 待办」
  /// 时小注说 3 篇、看着像时间段只筛出 3 篇。同源至少不会自相矛盾。
  String _rangeNote(int count) {
    if (_range == kDiaryRangeCustom) {
      return (_from.isNotEmpty || _to.isNotEmpty)
          ? '自定义区间内共 $count 篇'
          : '选好起止日期后点「应用」';
    }
    return _range == 'all' ? '默认显示全部日记' : '该时间段内共 $count 篇';
  }

  /// 时间段胶囊（原型 `.df-pill`）：**纯文字无图标**，高 34 / 内边距 14 / 全圆角。
  ///
  /// ⚠ **不许加 `alignment:`**：`Container(alignment:)` 会包一层 `Align`，而
  /// `Align` 在**有限**宽度约束下会撑满父级——它外面是 `Wrap`（`maxWidth` 有限），
  /// 于是每枚胶囊都被撑成整行宽（360dp），8 枚就摊成 8 行、弹层被顶到 670dp。
  /// 真机 6195 上「时间段变成一列」就是这个原因，不是设计口径。
  /// 复现/守护＝`diary_filter_rows_test.dart`（断言 400dp 下 ≤2 行且单枚宽 <200）。
  /// 文字要居中不必靠 `alignment`：Container 只剩一个 Text 子级，内容盒＝文字宽，
  /// 居中与左对齐渲染结果相同。
  Widget _pill({
    required String key,
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        height: kDfPillH,
        padding: const EdgeInsets.symmetric(horizontal: kDfPillPadX),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kDfPillH / 2),
          color: on ? tokens.accent.withValues(alpha: .06) : Colors.transparent,
          border: Border.all(
            color: on
                ? tokens.accent
                : scheme.onSurfaceVariant.withValues(alpha: .45),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
            color: on ? tokens.accent : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 自定义起止行（原型 `#dfCustom`）：起 — 止 [应用]。
  ///
  /// **常驻显示**（原型 `renderDfCustom()` 无条件渲染这一行），只有处于 `custom` 档
  /// 才整体高亮成实线主色描边（`.df-custom-on`）——用户不必先点「自定义」胶囊
  /// 才能选日期，那是两步操作换一步。日期用系统日期选择器（原型是原生 `type=date`）。
  Widget _customRow(ColorScheme scheme) {
    final tokens = context.tokens;
    final on = _range == kDiaryRangeCustom;
    return Row(
      children: [
        Expanded(child: _dateField(true, on, scheme, tokens)),
        const SizedBox(width: 8),
        Text('—',
            style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: .9))),
        const SizedBox(width: 8),
        Expanded(child: _dateField(false, on, scheme, tokens)),
        const SizedBox(width: 8),
        _applyBtn(dfRangeValid(from: _from, to: _to), tokens, scheme),
      ],
    );
  }

  /// 一端日期输入的外壳：未选时显示占位名（「起始日期」/「结束日期」）。
  Widget _dateField(
      bool isFrom, bool on, ColorScheme scheme, ThemeTokens tokens) {
    final v = isFrom ? _from : _to;
    return GestureDetector(
      key: ValueKey(isFrom ? 'df-from' : 'df-to'),
      onTap: () => _pickDate(isFrom),
      child: Container(
        height: kDfPillH,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: on ? tokens.accent.withValues(alpha: .06) : Colors.transparent,
          border: Border.all(
            color: on
                ? tokens.accent
                : scheme.onSurfaceVariant.withValues(alpha: .35),
          ),
        ),
        child: Text(
          v.isEmpty ? (isFrom ? '起始日期' : '结束日期') : v,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 12,
            color: v.isEmpty
                ? scheme.onSurfaceVariant.withValues(alpha: .7)
                : (on ? tokens.accent : scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  /// 「应用」：非法区间（两端全空 / `from > to`）时置灰且不响应点击。
  ///
  /// 置灰而不是隐藏：按钮消失会让行内布局每次选日期都跳一下，
  /// 而且用户不知道「还差什么才能生效」。
  Widget _applyBtn(bool ok, ThemeTokens tokens, ColorScheme scheme) {
    return GestureDetector(
      key: const ValueKey('df-apply'),
      onTap: ok ? _applyCustom : null,
      child: Container(
        height: kDfPillH,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: ok ? tokens.accent.withValues(alpha: .10) : Colors.transparent,
          border: Border.all(
            color: ok
                ? tokens.accent
                : scheme.onSurfaceVariant.withValues(alpha: .25),
          ),
        ),
        child: Text(
          '应用',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ok
                ? tokens.accent
                : scheme.onSurfaceVariant.withValues(alpha: .45),
          ),
        ),
      ),
    );
  }

  /// 一枚胶囊：高 32 / 圆角 16 / 14px 线性图标 + 文字；选中＝主色描边 + 6% 淡底 + 加粗。
  ///
  /// 底色走 `--accent` 派生淡档（`tokens.accent` 按 alpha 叠），**不写死色值**——
  /// 四主题 × 明暗共 8 组合下都得跟主题走（色值棘轮也吃这一条）。
  Widget _chip({
    required String key,
    required String label,
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final fg = on ? tokens.accent : scheme.onSurfaceVariant;
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        height: kDfChipH,
        padding: const EdgeInsets.symmetric(horizontal: kDfChipPadX),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kDfChipH / 2),
          color: on ? tokens.accent.withValues(alpha: .06) : Colors.transparent,
          border: Border.all(
            color: on
                ? tokens.accent
                : scheme.onSurfaceVariant.withValues(alpha: .35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: kDfChipIcon, color: fg.withValues(alpha: on ? 1 : .7)),
            const SizedBox(width: kDfChipIconGap),
            Text(
              label,
              style: TextStyle(
                fontSize: kDfChipFontSize,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「展开全部 (N)」／「收起」：虚线描边在原型的表达是「非实心按钮」，
  /// Flutter 没有现成的 dashed border，改用低透明实线 + 更小字号，观感同档。
  Widget _moreBtn(int total, ColorScheme scheme) => GestureDetector(
        key: const ValueKey('df-more'),
        onTap: () => setState(() => _tagOpen = !_tagOpen),
        child: Container(
          height: kDfChipH,
          padding: const EdgeInsets.symmetric(horizontal: kDfChipPadX),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kDfChipH / 2),
            border: Border.all(
                color: scheme.onSurfaceVariant.withValues(alpha: .45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dfMoreLabel(open: _tagOpen, total: total),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 5),
              Icon(_tagOpen ? Icons.expand_less : Icons.expand_more,
                  size: 12, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      );

  Widget _resetBtn(ColorScheme scheme) => GestureDetector(
        key: const ValueKey('df-reset'),
        onTap: _reset,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: scheme.onSurfaceVariant.withValues(alpha: .3)),
          ),
          child: Text('重置',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
        ),
      );

  Widget _doneBtn(ThemeTokens tokens, ColorScheme scheme) => GestureDetector(
        key: const ValueKey('df-done'),
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: tokens.accent,
          ),
          // 文字取 `onPrimary`（主色之上的前景），不写死白色——
          // 写死不跟主题与深浅走，且会撞深色观感棘轮闸。
          child: Text('完成',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary)),
        ),
      );
}
