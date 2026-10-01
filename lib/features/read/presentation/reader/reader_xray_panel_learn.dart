part of 'reader_xray_panel.dart';

// V1.54 批B · 面板自学习 UI 群（建议卡 / 整理底栏 / 详情三件套）。
// 治理口径＝计划书 2.2「私有巨型 State 类走 extension part」：纯搬移零行为改动，
// 成员经 extension 直访 `_ReaderXrayPanelState` 私有一切（_org/_sel/_curId/setState）。

extension _XrPanelLearn on _ReaderXrayPanelState {
  /// 回流建议卡（§7：出场上下文 ≥30% 命中同一称谓形态 → 「采纳进全局表」）。
  Widget _suggestionCard(XrayScheduler sched, String md5, XraySuggestion sug) {
    return Container(
      key: ValueKey('xrSug-${sug.word}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: _XrStyle.accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _XrStyle.accent.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '「${sug.word}${sug.title}」写法占 ${sug.pct}% · 收进全局词库？',
              style: const TextStyle(fontSize: 10.5, height: 1.4),
            ),
          ),
          TextButton(
            key: const ValueKey('xrSugSkip'),
            onPressed: () => sched.dismissSuggestion(widget.book.id),
            child: const Text('忽略', style: TextStyle(fontSize: 10.5)),
          ),
          TextButton(
            key: const ValueKey('xrSugAdopt'),
            onPressed: () async {
              await sched.dao
                  .promoteWordToGlobal(md5, sug.word, patternHint: sug.title);
              sched.dismissSuggestion(widget.book.id);
              if (mounted) readToast(context, '已采纳进全局词库');
            },
            child: const Text('采纳',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _XrStyle.accent)),
          ),
        ],
      ),
    );
  }

  /// 整理底栏（xrBarHtml org 态）：已选计数 + 合并（≥2）+ 移除（≥1）+ 退出。
  Widget _orgBar(XrayScheduler sched, String md5, XrayPanelData snap) {
    final selected = snap.entities.where((e) => _sel.contains(e.id)).toList();
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('xrOrgBar'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Text('已选 ${selected.length} 条',
              style: const TextStyle(fontSize: 10, color: _XrStyle.muted)),
          const Spacer(),
          TextButton(
            key: const ValueKey('xrOrgExit'),
            // ignore: invalid_use_of_protected_member
            onPressed: () => setState(() {
              _org = false;
              _sel.clear();
            }),
            child: const Text('退出整理', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 6),
          _orgAction('xrOrgMerge', '合并', selected.length >= 2,
              const Color(0xFF6366F1), () async {
            if (selected.length < 2) return;
            final into = selected.first;
            await sched.dao.mergeInto(md5,
                intoId: into.id,
                fromIds: [for (final e in selected.skip(1)) e.id]);
            _sel.clear();
            sched.notifyDataChanged();
            if (mounted) {
              readToast(context, '已合并为「${into.name}」· 出场归属已迁移');
            }
          }),
          const SizedBox(width: 6),
          _orgAction('xrOrgDel', '移除', selected.isNotEmpty,
              const Color(0xFFF43F5E), () {
            if (selected.isEmpty) return;
            showXrDelSheet(context, ref,
                md5: md5,
                ids: [for (final e in selected) e.id],
                names: [for (final e in selected) e.name]);
          }),
        ],
      ),
    );
  }

  Widget _orgAction(
      String key, String label, bool enabled, Color bg, VoidCallback? onTap) {
    return GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : .4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
      ),
    );
  }

  /// 详情子页自学习区（批B）：疑似同一条目候选卡 · 合并进… · 不再显示该词 ·
  /// AI 释义二期预留位（形态＝xrDetailHtml 尾段，微信读书/Kindle 对照拍板）。
  List<Widget> _detailLearn(XrayPanelData snap, String md5, XrayEntityRow e) {
    final cand = snap.entities
        .where((v) =>
            v.id != e.id &&
            (v.name.contains(e.name) || e.name.contains(v.name)))
        .firstOrNull;
    final cs = Theme.of(context).colorScheme;
    return [
      if (cand != null)
        Container(
          key: ValueKey('xr-cand-${cand.id}'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('疑似同一条目：「${cand.name}」${cand.n} 次',
                    style: const TextStyle(fontSize: 11, height: 1.4)),
              ),
              TextButton(
                key: const ValueKey('xrCandMerge'),
                onPressed: () async {
                  await ref
                      .read(xrayDaoProvider)
                      .mergeInto(md5, intoId: e.id, fromIds: [cand.id]);
                  ref.read(xraySchedulerProvider).notifyDataChanged();
                  if (mounted) {
                    readToast(context,
                        '已并入「${e.name}」· 出场归属已迁移');
                  }
                },
                child: const Text('并入当前词条',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: _XrStyle.accent)),
              ),
            ],
          ),
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _detailBtn('xr-merge-into', '合并进…',
                cs.outlineVariant, cs.onSurface, () {
              showXrMergePickerSheet(
                context,
                ref,
                md5: md5,
                from: e,
                others:
                    snap.entities.where((v) => v.id != e.id).toList(),
                // ignore: invalid_use_of_protected_member
                onDone: (intoId) => setState(() => _curId = intoId),
              );
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _detailBtn('xr-ban', '不再显示该词',
                const Color(0xFFFECDD3), const Color(0xFFE11D48), () {
              showXrDelSheet(context, ref,
                  md5: md5, ids: [e.id], names: [e.name]);
            }),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        key: const ValueKey('xr-aihold'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: cs.outlineVariant,
              style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            const Text('AI 释义 · 二期',
                style: TextStyle(fontSize: 10, color: _XrStyle.muted)),
            const Spacer(),
            if ((e.aiDesc ?? '').isEmpty)
              const Text('暂未生成',
                  style:
                      TextStyle(fontSize: 9, color: Color(0xFFCBD5E1))),
          ],
        ),
      ),
    ];
  }

  Widget _detailBtn(
      String key, String label, Color border, Color fg, VoidCallback onTap) {
    return GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }

}
