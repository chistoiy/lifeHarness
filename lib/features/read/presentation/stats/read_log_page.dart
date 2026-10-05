import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/book.dart';
import '../../domain/book_session.dart';
import '../read_providers.dart';
import '../read_sheets.dart' show readToast;
import '../widgets/bs_cover.dart' show BsIcons;

/// 阅读记录页（真机验收轮1e · 原型 p-readlog/renderReadLog）：
/// 单条时间线卡（日期周几/时间段·止页/分钟渐变条 · 点卡就地展开改日期时长页码/删除）
/// + 右上 ⊕ 补记一次 + 数据卡下方「全部 ▾」范围筛选（轮1g）。
/// 入口：详情页「时长」、档案页累计卡与轨迹行、操作弹层、阅读轨迹「改明细」。
class ReadLogPage extends ConsumerStatefulWidget {
  const ReadLogPage({super.key, required this.bookId});
  final String bookId;

  static const _wd = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  /// 已结束的会话按开始时间倒序（原型 renderReadLog 排序口径）。
  static List<BookSession> endedDesc(List<BookSession> all) =>
      (all.where((s) => s.endedAt != null).toList())
        ..sort((x, y) => y.startedAt.compareTo(x.startedAt));

  @override
  ConsumerState<ReadLogPage> createState() => _ReadLogPageState();
}

class _ReadLogPageState extends ConsumerState<ReadLogPage> {
  static const _scopes = ['全部', '本月', '近3月'];
  int _scope = 0;
  // 轮5：时长卡点按就地改累计（原型 rlMinOpen/rlMinSave）。
  bool _minEdit = false;
  final _minCtl = TextEditingController();

  @override
  void dispose() {
    _minCtl.dispose();
    super.dispose();
  }

  Future<void> _saveTotalMin(int total, List<BookSession> all) async {
    final v = (int.tryParse(_minCtl.text.trim()) ?? total).clamp(0, 1 << 31);
    final d = v - total;
    if (d != 0) {
      final repo = ref.read(readRepositoryProvider);
      if (all.isNotEmpty) {
        // 差量记到最近一次会话上（时间线总量＝设定值）。
        final last = all.first;
        await repo.editSession(
          last.id!,
          minutes: (last.minutes + d).clamp(0, 1 << 31),
        );
      } else if (v > 0) {
        await repo.addManualSession(
          bookId: widget.bookId,
          day: DateTime.now(),
          minutes: v,
        );
      }
      if (!mounted) return;
      ref.read(readTickProvider.notifier).state++;
      readToast(context, '累计时长已更新 · ${bsFmt(v)}');
    }
    setState(() => _minEdit = false);
  }

  Widget _minBtn(String key, String label, Color color, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: cs.surfaceContainerHighest.withValues(alpha: .5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }

  /// 按会话开始时间做自然月窗口筛选（0 全部 · 1 本月 · 2 近3月含本月）。
  bool _inScope(int ms) {
    if (_scope == 0) return true;
    final d = DateTime.fromMillisecondsSinceEpoch(ms), now = DateTime.now();
    final off = (now.year - d.year) * 12 + (now.month - d.month);
    return _scope == 1 ? off == 0 : off >= 0 && off <= 2;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final b = (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
        .where((x) => x.id == widget.bookId && !x.isDeleted)
        .firstOrNull;
    final all = ReadLogPage.endedDesc(
      ref.watch(sessionsOfProvider(widget.bookId)).valueOrNull ??
          const <BookSession>[],
    );
    // 轮1g「全部 ▾」范围筛选：仅作用于时间线分组与已读天数；累计时长/进度/开始日期保持全书口径（原型一致）。
    final sessions = all.where((s) => _inScope(s.startedAt)).toList();
    final total = all.fold<int>(0, (t, s) => t + s.minutes);
    final dayKeys = {
      for (final s in sessions)
        DateTime.fromMillisecondsSinceEpoch(s.startedAt).toIso8601String().substring(0, 10),
    };
    final startMs = b?.startedAt ??
        (all.isEmpty
            ? null
            : all.map((s) => s.startedAt).reduce((a, x) => a < x ? a : x));
    final maxMin = all.fold<int>(
      1,
      (m, s) => s.minutes > m ? s.minutes : m,
    );
    // 按月分组（键 yyyy-M · 组内倒序 · 月间倒序）。
    final groups = <String, List<BookSession>>{};
    for (final s in sessions) {
      final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      groups.putIfAbsent('${d.year}-${d.month}', () => []).add(s);
    }
    final months = groups.keys.toList();
    months.sort((x, y) {
      final xy = x.split('-').map(int.parse).toList();
      final yy = y.split('-').map(int.parse).toList();
      return (yy[0] * 12 + yy[1]).compareTo(xy[0] * 12 + xy[1]);
    });
    return Scaffold(
      appBar: AppBar(
        // 轮5：标题居中
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('阅读记录'),
            if (b != null)
              Text(
                '《${b.title}》',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('rl-add'),
            tooltip: '补记一次',
            icon: const Icon(BsIcons.add, size: 18),
            onPressed: () async {
              // 原型 bsSessAdd：from=当前进度页，to=min(总页数, from+10)。
              final fp = (b?.readPages ?? 0) > 0 ? b!.readPages : null;
              await ref.read(readRepositoryProvider).addManualSession(
                bookId: widget.bookId,
                day: DateTime.now(),
                minutes: 20,
                fromPage: fp,
                toPage: fp == null
                    ? null
                    : (b!.pages > 0 ? fp + 10 > b.pages ? b.pages : fp + 10 : fp + 10),
              );
              if (!context.mounted) return;
              ref.read(readTickProvider.notifier).state++;
              readToast(context, '已补记一次 · 可直接改日期与时长');
            },
          ),
        ],
      ),
      body: b == null
          ? Center(
              child: Text(
                '这本书已不在书架',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // 书基本信息（书名 + 作者 · 出版社 · 出版时间）。
                Container(
                  key: const ValueKey('rl-info'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: _cardDeco(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          b.author,
                          if ((b.publisher ?? '').isNotEmpty) b.publisher,
                          if ((b.pubDate ?? '').isNotEmpty) b.pubDate,
                        ].where((x) => (x ?? '').isNotEmpty).join(' · '),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 四数据卡 2×2。
                Row(
                  children: [
                    Expanded(
                      child: _stat(
                        context,
                        'rl-prog',
                        '阅读进度',
                        b.pages > 0
                            ? '${b.readPages}'
                            : '${b.percent}',
                        unit: b.pages > 0 ? ' / ${b.pages} 页 · ${b.percent}%' : '%',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _minEdit
                          ? Container(
                              key: const ValueKey('rl-min'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: _cardDeco(context),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '阅读时长（分钟）',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 30,
                                          child: TextField(
                                            key: const ValueKey('rl-min-all'),
                                            controller: _minCtl,
                                            keyboardType: TextInputType.number,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w900,
                                            ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 6,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      _minBtn(
                                        'rl-min-save',
                                        '保存',
                                        tokens.accent,
                                        () => _saveTotalMin(total, all),
                                      ),
                                      const SizedBox(width: 8),
                                      _minBtn(
                                        'rl-min-cancel',
                                        '取消',
                                        cs.onSurfaceVariant,
                                        () => setState(() => _minEdit = false),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : GestureDetector(
                              key: const ValueKey('rl-min'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                _minCtl.text = '$total';
                                setState(() => _minEdit = true);
                              },
                              child: _stat(
                                context,
                                null,
                                '阅读时长',
                                bsFmt(total),
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _stat(context, 'rl-days', '已读天数', '${dayKeys.length}', unit: '天'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _stat(
                        context,
                        'rl-start',
                        '开始日期',
                        startMs == null
                            ? '—'
                            : () {
                                final d = DateTime.fromMillisecondsSinceEpoch(startMs);
                                return '${d.year}.${d.month.toString().padLeft(2, '0')}.'
                                    '${d.day.toString().padLeft(2, '0')}';
                              }(),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      const Spacer(),
                      PopupMenuButton<int>(
                        key: const ValueKey('rl-filter'),
                        tooltip: '筛选范围',
                        itemBuilder: (context) => [
                          for (var i = 0; i < _scopes.length; i++)
                            PopupMenuItem(
                              value: i,
                              child: Text(
                                _scopes[i],
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                        ],
                        onSelected: (i) => setState(() => _scope = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: .6),
                            ),
                          ),
                          child: Text(
                            '${_scopes[_scope]} ▾',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (sessions.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    decoration: _cardDeco(context),
                    child: Center(
                      child: Text(
                        all.isEmpty
                            ? '还没有计时记录 · 点右上 ＋ 补记一次'
                            : '当前范围没有记录 · 点右上 ＋ 补记一次',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                for (final m in months) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 2),
                    child: Row(
                      key: ValueKey('rl-m-$m'),
                      children: [
                        Text(
                          '${m.split('-')[0]}年${int.parse(m.split('-')[1])}月',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            bsFmt(
                              groups[m]!.fold<int>(0, (t, s) => t + s.minutes),
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final s in groups[m]!)
                    _LogCard(
                      s: s,
                      maxMin: maxMin,
                      wd: ReadLogPage._wd,
                      seq: all.indexOf(s) + 1,
                      totalMin: total,
                    ),
                ],
              ],
            ),
    );
  }

  BoxDecoration _cardDeco(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    );
  }

  Widget _stat(
    BuildContext context,
    String? key,
    String label,
    String value, {
    String unit = '',
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: key == null ? null : ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: unit,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条记录卡：日期列 + 绿点 + 时间段·止页/分钟渐变条；点卡就地展开编辑器（原型 rlToggle）。
class _LogCard extends ConsumerStatefulWidget {
  const _LogCard({
    required this.s,
    required this.maxMin,
    required this.wd,
    required this.seq,
    required this.totalMin,
  });
  final BookSession s;
  final int maxMin;
  final List<String> wd;
  final int seq; // 第 N 次（按时间正序）
  final int totalMin; // 全书累计分钟（保存回显用）

  @override
  ConsumerState<_LogCard> createState() => _LogCardState();
}

class _LogCardState extends ConsumerState<_LogCard> {
  bool _open = false;
  bool _dateOpen = false;
  final TextEditingController _min = TextEditingController();
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();

  @override
  void dispose() {
    _min.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  /// 展开时以当前库值回填三输入（轮3：编辑器带字段名＋保存/取消钮）。
  void _syncCtl() {
    final s = widget.s;
    _min.text = '${s.minutes}';
    _from.text = s.fromPage == null ? '' : '${s.fromPage}';
    _to.text = s.toPage == null ? '' : '${s.toPage}';
  }

  Future<void> _saveRow() async {
    final s = widget.s;
    final minutes = int.tryParse(_min.text.trim()) ?? s.minutes;
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    await ref.read(readRepositoryProvider).editSession(
      s.id!,
      startedAtMs: s.startedAt,
      minutes: minutes,
      fromPage: from,
      toPage: to,
    );
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    readToast(
      context,
      '第 ${widget.seq} 次已更新 · 累计 '
      '${bsFmt(widget.totalMin - s.minutes + minutes)}',
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 会话位置摘要（轮5.2②：起止章节/页/百分比由阅读器退出时自动记录；
  /// 手工补记与旧数据只有 toPage → 保持原展示）。
  static String _sessPos(BookSession s) {
    final ch = (s.toChapter ?? s.fromChapter ?? '').trim();
    final pg = s.fromPage != null && s.toPage != null
        ? 'P${s.fromPage}→${s.toPage}'
        : 'P${s.toPage ?? '—'}';
    final pc = s.fromPct != null && s.toPct != null
        ? '${s.fromPct!.round()}%→${s.toPct!.round()}%'
        : null;
    return [
      if (ch.isNotEmpty) ch,
      pg,
      ?pc,
    ].join(' · ');
  }

  Future<void> _apply({int? minutes, int? fromPage, int? toPage, int? startedAtMs}) async {
    await ref.read(readRepositoryProvider).editSession(
      widget.s.id!,
      startedAtMs: startedAtMs ?? widget.s.startedAt,
      minutes: minutes ?? widget.s.minutes,
      fromPage: fromPage,
      toPage: toPage,
    );
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final s = widget.s;
    final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    final frac = (s.minutes / widget.maxMin).clamp(.18, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        key: ValueKey('rl-sess-${s.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Text(
                  '${d.day}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                Text(
                  ReadLogPage._wd[d.weekday - 1],
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _open = !_open;
                if (_open) _syncCtl();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: _cardDeco(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_hhmm(d)} - ${_hhmm(DateTime.fromMillisecondsSinceEpoch(s.endedAt ?? s.startedAt))}'
                          ' · ${_sessPos(s)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _open ? '收起' : '修改',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: tokens.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, box) => Container(
                        height: 28,
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: box.maxWidth * frac,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      tokens.accent.withValues(alpha: .72),
                                      tokens.accent,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Center(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${s.minutes}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const TextSpan(
                                          text: '分钟',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_open)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              key: ValueKey('rl-date-${s.id}'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setState(() => _dateOpen = !_dateOpen),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _dateOpen
                                        ? tokens.accent
                                        : cs.outlineVariant.withValues(
                                            alpha: .4,
                                          ),
                                  ),
                                ),
                                child: Text(
                                  '日期 ${d.year}-${d.month.toString().padLeft(2, '0')}-'
                                  '${d.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            if (_dateOpen)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SizedBox(
                                  height: 92,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _WheelCol(
                                          keyName: 'rl-dw-${s.id}-y',
                                          items: [
                                            for (var y = 2015; y <= 2100; y++)
                                              '$y 年',
                                          ],
                                          initialIndex: d.year - 2015,
                                          onChanged: (i) => _applyDate(
                                            y: 2015 + i,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _WheelCol(
                                          keyName: 'rl-dw-${s.id}-m',
                                          items: [
                                            for (var m = 1; m <= 12; m++)
                                              '$m 月',
                                          ],
                                          initialIndex: d.month - 1,
                                          onChanged: (i) =>
                                              _applyDate(m: i + 1),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _WheelCol(
                                          keyName: 'rl-dw-${s.id}-d',
                                          items: [
                                            for (var dd = 1; dd <= 31; dd++)
                                              '$dd 日',
                                          ],
                                          initialIndex: d.day - 1,
                                          onChanged: (i) =>
                                              _applyDate(day: i + 1),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            // 轮3：三输入带字段名（时长/起页/止页），改完点「保存」落库。
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '时长',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 56,
                                  child: _num('rl-min-${s.id}', _min, ''),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '分钟',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '起页',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: _num('rl-from-${s.id}', _from, '')),
                                const SizedBox(width: 10),
                                Text(
                                  '止页',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: _num('rl-to-${s.id}', _to, '')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _editBtn(
                                    'rl-del-${s.id}',
                                    '删除这次',
                                    cs.error,
                                  () async {
                                    await ref
                                        .read(readRepositoryProvider)
                                        .deleteSession(s.id!);
                                    if (!context.mounted) return;
                                    ref.read(readTickProvider.notifier).state++;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _editBtn(
                                    'rl-cancel-${s.id}',
                                    '取消',
                                    cs.onSurfaceVariant,
                                    () => setState(() {
                                      _open = false;
                                      _dateOpen = false;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _editBtn(
                                    'rl-save-${s.id}',
                                    '保存',
                                    tokens.accent,
                                    _saveRow,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 就地滚轮改日期：保持原时刻，只换年月日（铁律 · 禁日历二段弹层）。
  Future<void> _applyDate({int? y, int? m, int? day}) async {
    final d = DateTime.fromMillisecondsSinceEpoch(widget.s.startedAt);
    final ny = y ?? d.year;
    final nm = m ?? d.month;
    final maxDay = DateTime(ny, nm + 1, 0).day;
    final nd = (day ?? d.day).clamp(1, maxDay);
    await _apply(
      startedAtMs: DateTime(ny, nm, nd, d.hour, d.minute).millisecondsSinceEpoch,
    );
  }

  Widget _num(String key, TextEditingController ctl, String hint) {
    return TextField(
      key: ValueKey(key),
      controller: ctl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 11.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11),
      ),
    );
  }

  /// 编辑区三钮（删除这次 / 取消 / 保存）。
  Widget _editBtn(
    String key,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: cs.surfaceContainerHighest.withValues(alpha: .5),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
        ),
      ),
    );
  }

  BoxDecoration _cardDeco(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    );
  }
}

/// 就地滚轮列（与摘录表单 _ColWheel 同规格 · 跨文件独立一份）。
class _WheelCol extends StatefulWidget {
  const _WheelCol({
    required this.keyName,
    required this.items,
    required this.initialIndex,
    required this.onChanged,
  });
  final String keyName;
  final List<String> items;
  final int initialIndex;
  final ValueChanged<int> onChanged;

  @override
  State<_WheelCol> createState() => _WheelColState();
}

class _WheelColState extends State<_WheelCol> {
  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
    initialItem: widget.initialIndex.clamp(0, widget.items.length - 1),
  );

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      key: ValueKey<String>(widget.keyName),
      controller: _ctl,
      itemExtent: 30,
      squeeze: 1.05,
      diameterRatio: 2.4,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: widget.onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: widget.items.length,
        builder: (context, i) => Center(
          child: Text(
            widget.items[i],
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
