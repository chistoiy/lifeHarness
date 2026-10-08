import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_note.dart';
import '../domain/media_item.dart';
import '../domain/media_note.dart';
import 'media_note_edit_sheet.dart' show mediaNoteAtTx, mediaNoteTypeColor;
import 'media_providers.dart';

/// 名场面复习卡（原型 `m-review` · 词典 LH-S36 · 批5）。
///
/// 三条口径：
/// - **队列＝筛过的到期笔记**（工单 §1.2）：取数与笔记库共用 `mediaDueCountProvider` 那同一份
///   where，进屏读数与角标数必须一个口径，否则「角标写 3、点开只有 2 条」；
/// - **记住了＝推档并落库**（`markRemembered`：1→3→7 天，走完三档清排期）；
///   **跳过＝不落库**，只从本轮内存队列摘掉（下次进屏仍按排期出＝与原型同口径）；
/// - 翻面卡**卡角给不写字的小箭头**（拍板⑥），正面不出现出处与条目名——
///   背面信息漏在正面就等于没有翻面（批5 原型面自纠过同一条）。
Future<void> showMediaReviewSheet(BuildContext context, WidgetRef ref,
    {int? singleNoteId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(singleNoteId: singleNoteId),
    );

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({this.singleNoteId});

  /// 非空＝单条模式（从笔记行点开：无队列条数、无档位动作，只可翻面）。
  final int? singleNoteId;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  /// 本轮队列（内存态：跳过＝摘除，不写库）。
  List<MediaNote> _queue = const [];
  int _idx = 0;
  bool _flipped = false;
  bool _loading = true;
  bool _busy = false;

  Map<String, String> _titles = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(mediaRepositoryProvider);
    final f = ref.read(mediaNoteFilterProvider);
    final items = ref.read(mediaAllItemsProvider).valueOrNull ?? const <MediaItem>[];
    _titles = {for (final x in items) x.id: x.title};
    final list = widget.singleNoteId == null
        ? await repo.dueReviewNotes(
            noteType: f.type,
            kind: f.kind,
            itemId: f.itemId,
            tag: f.tag,
            query: f.query,
            starredOnly: f.starred,
          )
        : [
            if (await repo.noteById(widget.singleNoteId!) case final MediaNote n) n,
          ];
    if (!mounted) return;
    setState(() {
      _queue = list;
      _idx = 0;
      _loading = false;
    });
  }

  MediaNote? get _current =>
      _idx < _queue.length ? _queue[_idx] : null;

  bool get _single => widget.singleNoteId != null;

  /// 「记住了」：推档落库后取队列下一条（走完三档的行下次不再进队列）。
  Future<void> _remember() async {
    final n = _current;
    if (n == null || _busy) return;
    setState(() => _busy = true);
    await ref.read(mediaRepositoryProvider).markRemembered(n.id!);
    final tick = ref.read(mediaTickProvider.notifier);
    tick.state = tick.state + 1;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _flipped = false;
      _idx += 1; // 队列已推档＝本条本轮不再出（下次到期由档位排期决定）
    });
  }

  /// 「跳过这条」＝本轮不再出，**不落库**（工单 §1.2 钉死）。
  void _skip() => setState(() {
        _flipped = false;
        _idx += 1;
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = _current;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        key: const ValueKey('mdr-sheet'),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(_single ? '复习卡' : '名场面复习',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const Spacer(),
                // 位置槽（原型 `#mRevPos`）：队列模式给剩几条，单条模式写「单条」——
                // 「看完不蹭档位」这件事得在屏上看得出来，不能只靠没有按钮。
                // 口径偏离登记：原型是「当前 / 总数」，实现取「剩 N 条」（＝队列摘除语义更直白），
                // 留产品一句话定夺（批5 工单观察项）。
                if (!_loading && n != null)
                  Text(_single ? '单条' : '剩 ${_queue.length - _idx} 条',
                      key: const ValueKey('mdr-left'),
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            else if (n == null)
              const EmptyDashRow(
                key: ValueKey('mdr-empty'),
                text: '今天没有到期的复习',
              )
            else ...[
              _flipCard(context, n),
              // 三档 chips 显示当前档（走完＝「已掌握」，不再排队）；单条模式不显示档位。
              if (!_single) ...[
                const SizedBox(height: 12),
                _stageRow(n),
              ],
              if (!_single) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('mdr-remember'),
                        onPressed: _busy ? null : _remember,
                        child: const Text('记住了'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        key: const ValueKey('mdr-skip'),
                        onPressed: _busy ? null : _skip,
                        child: const Text('跳过这条'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 翻面卡（正面＝正文；背面＝出处＋批注；卡角两枚小箭头是不写字的翻面线索）。
  ///
  /// 色标＝左侧 3px 竖条走叠层，不写进 `Border(left: …)`：`BoxDecoration` 的圆角只容得下
  /// 四边同色的边框，单边色＋圆角在 paint 阶段直接断言炸卡（笔记库卡片同一条，批5 常驻例现形）。
  Widget _flipCard(BuildContext context, MediaNote n) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: const ValueKey('mdr-card'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _flipped = !_flipped),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: ClipRRect(
          key: ValueKey(_flipped ? 'back' : 'front'),
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 180),
                padding: const EdgeInsets.fromLTRB(17, 14, 14, 30),
                color: _flipped
                    ? scheme.surfaceContainerHighest
                    : scheme.surfaceContainerHighest.withValues(alpha: .55),
                child: _flipped ? _back(n, scheme) : _front(n, scheme),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: ColoredBox(
                  key: const ValueKey('mdr-accent'),
                  color: mediaNoteTypeColor(n.noteType),
                  child: const SizedBox(width: 3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _front(MediaNote n, ColorScheme scheme) => Column(
        key: const ValueKey('mdr-front'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n.body,
              style: const TextStyle(fontSize: 13.5, height: 1.6, fontWeight: FontWeight.w700)),
          if (n.imagePaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final p in n.imagePaths)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(p),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 60,
                              height: 60,
                              color: scheme.surfaceContainerHighest,
                              child: Icon(Icons.image_outlined,
                                  size: 16, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          _corner(scheme),
        ],
      );

  Widget _back(MediaNote n, ColorScheme scheme) => Column(
        key: const ValueKey('mdr-back'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${MediaItem.labelOf(n.kind)} · 《${_titles[n.itemId] ?? '已删条目'}》'
            '${n.atMin == null ? '' : ' · ${mediaNoteAtTx(n.atMin)}'}',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if ((n.thought ?? '').trim().isEmpty)
            Container(
              key: const ValueKey('mdr-no-thought'),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('未写批注',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            )
          else
            Text(n.thought!, style: const TextStyle(fontSize: 12, height: 1.6)),
          _corner(scheme),
        ],
      );

  /// 卡角小箭头（正面背面各一枚，不配文字＝拍板⑥的翻面线索）。
  Widget _corner(ColorScheme scheme) => Align(
        key: const ValueKey('mdr-corner'),
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Icon(Icons.swap_vert, size: 16, color: scheme.onSurfaceVariant),
        ),
      );

  /// 档位只读行：改档只能靠「记住了」逐档推进，点 chip 不许跳档，所以不画成可点的样子。
  Widget _stageRow(MediaNote n) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      key: const ValueKey('mdr-stages'),
      spacing: 8,
      runSpacing: 6,
      children: [
        for (var s = 0; s < MediaNote.reviewGapsDays.length; s++)
          Container(
            key: ValueKey('mdr-stage-${MediaNote.reviewGapsDays[s]}'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: n.reviewStage == s
                  ? scheme.primary.withValues(alpha: .16)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: n.reviewStage == s ? scheme.primary : scheme.outlineVariant),
            ),
            child: Text('${MediaNote.reviewGapsDays[s]} 天',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: n.reviewStage == s ? scheme.primary : scheme.onSurfaceVariant)),
          ),
        if (n.isMastered)
          Container(
            key: const ValueKey('mdr-stage-mastered'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.primary),
            ),
            child: const Text('已走完三档',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }
}
