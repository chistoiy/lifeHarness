part of 'diary_edit_page.dart';

// 日记改版批2（2026-10-19 · 工单 §4d ④⑤）：概览卡与底栏两段自 _DiaryEditPageState 移入同库扩展。
// 起因＝本批把编辑器与心情行改造完，主文件涨到 1228 行（红线 1200）——**先搬再接线**，
// 搬的两段是「底部固定区」（概览卡 + 模板/保存/保存态提示），与正文/富文本零耦合，
// 是最安全的一刀（同批前一次还债搬的是富文本群，见 `diary_edit_rich.dart`）。
// 纯机械搬迁＋本批新写的内容一起落这里：`_summaryCard`（弱底隔离＋插入/重新生成两枚）、
// `_tplRow`（等高 44 + 保存态降透明）。行为只在 `_saveNow`/`_saveStateOf` 两处新增（仍在主文件）。
extension _DiaryEditFoot on _DiaryEditPageState {
  /// 轮12-1：今日概览草稿卡=默认折叠，点标题行展开/收起。
  /// 批2（§4d ④）：标题去「联动 L2」；整卡改**弱品牌底**与手写区隔离；展开后给「插入到正文／重新生成」两枚。
  Widget _summaryCard(BuildContext context, tokens, scheme,
      List<Todo> todos, List<TimeBlock> blocks) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.accent.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('diary-sum-head'),
            borderRadius: BorderRadius.circular(16),
            // ignore: invalid_use_of_protected_member
            onTap: () => setState(() => _sumOpen = !_sumOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 14, color: tokens.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('今日概览草稿 · AI 自动生成',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: tokens.accent)),
                  ),
                  Icon(_sumOpen ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (_sumOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _summaryLines(todos, blocks).join('\n'),
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.7,
                        color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('diary-sum-insert'),
                          onPressed: () {
                            _insertAtCursor(_summaryText(todos, blocks));
                            _richFocus.requestFocus();
                          },
                          icon: const Icon(Icons.arrow_upward, size: 13),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            side: BorderSide(
                                color: tokens.accent.withValues(alpha: .3)),
                            foregroundColor: tokens.accent,
                          ),
                          label: const Text('插入到正文',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('diary-sum-regen'),
                          onPressed: () {
                            // 草稿内容本就由 provider 实时派生（待办/时间块），
                            // 「重新生成」＝重取一次源并提示，不做假造摘要。
                            // ignore: invalid_use_of_protected_member
                            setState(() {});
                            AppToast.show(context, '已重新生成概览草稿', ms: 1200);
                          },
                          icon: const Icon(Icons.refresh, size: 13),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            side: BorderSide(color: tokens.cardBorder),
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                          label: const Text('重新生成',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('diary-ai-reflect'),
                      onPressed: _genReflection,
                      child: Text('AI 生成反思草稿',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 底栏：模板（左·等高 h-11）+ 保存钮（右·等高）。批2 §4d ⑤。
  /// 模板钮改成**先预览**——点开弹层看简介与分节清单，再点「使用此模板」才真换（`_openTplSheet`）。
  Widget _tplRow(BuildContext context, tokens, scheme) {
    final dim = diarySaveDimmed(_saveStateOf);
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            key: const ValueKey('tpl-open-sheet'),
            onTap: _openTplSheet,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: tokens.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.cardBorder),
              ),
              child: Row(children: [
                Icon(Icons.description_outlined,
                    size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '模板：${_tpl.id == null ? '自由书写' : _tpl.name}',
                    key: const ValueKey('tpl-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface),
                  ),
                ),
                Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          key: const ValueKey('diary-save'),
          onTap: _saveNow,
          child: Opacity(
            opacity: dim ? .45 : 1,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  gradient: tokens.gradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: dim ? null : tokens.cardShadow),
              child: const Text('保存',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ),
          ),
        ),
      ],
    );
  }
}
