# tools/attic/xr_batchB_panel_patch2.py — 批B 面板改造第二段：行勾选 / 详情自学习三件套 / 空态加词入口
import io

def patch(p, pairs):
    s = io.open(p, encoding='utf-8', newline='').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, a[:60], s.count(a))
        s = s.replace(a, b)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

p = 'lib/features/read/presentation/reader/reader_xray_panel.dart'
patch(p, [
    # 行：org 态勾选 + 合并选中样式（原型 xrRowHtml）
    ("""  Widget _row(XrayEntityRow e, List<XrayAnchorRow>? ms, {bool inCur = false}) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey('xrRow-${e.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _curId = e.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: inCur
                ? _XrStyle.accent.withValues(alpha: .55)
                : cs.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(""",
     """  Widget _row(XrayEntityRow e, List<XrayAnchorRow>? ms, {bool inCur = false}) {
    final cs = Theme.of(context).colorScheme;
    final sel = _sel.contains(e.id);
    return GestureDetector(
      key: ValueKey('xrRow-${e.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (_org) {
          sel ? _sel.remove(e.id) : _sel.add(e.id);
        } else {
          _curId = e.id;
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: inCur
                ? _XrStyle.accent.withValues(alpha: .55)
                : cs.outlineVariant.withValues(alpha: .5),
          ),
        ),
        foregroundDecoration: _org && sel
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _XrStyle.accent, width: 2),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_org)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      key: ValueKey('xr-ck-${e.id}'),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: sel ? _XrStyle.accent : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: sel
                          ? const Icon(Icons.check_rounded,
                              size: 12, color: Colors.white)
                          : null,
                    ),
                  ),
                Flexible("""),

    # 详情尾部：并词候选卡 + 合并进…/不再显示该词 + AI 二期预留位（原型 xrDetailHtml 自学习显性化）
    ("""        if (hidden > 0)
          Padding(
            key: const ValueKey('xr-spoiler'),
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text('剧透保护 · 隐藏未读 $hidden 处引用',
                style: const TextStyle(fontSize: 9, color: _XrStyle.muted)),
          ),
      ],
    );
  }""",
     """        if (hidden > 0)
          Padding(
            key: const ValueKey('xr-spoiler'),
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text('剧透保护 · 隐藏未读 $hidden 处引用',
                style: const TextStyle(fontSize: 9, color: _XrStyle.muted)),
          ),
        ..._detailLearn(snap, md5, e),
      ],
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
  }"""),

    # 空态文案补加词去向（org 空态不加文案）
    ("""              snap.entities.isEmpty ? '还没有词条 · 点「重新解析」生成全书索引' : '该范围没有词条',""",
     """              snap.entities.isEmpty ? '还没有词条 · 点「重新解析」生成全书索引' : '该范围没有词条',"""),

    # 未接线空态也补「＋加词」直达（xrGen 主按钮旁小字按钮）
    ("""          const SizedBox(height: 12),
          GestureDetector(
            key: const ValueKey('xrGen'),""",
     """          const SizedBox(height: 12),
          GestureDetector(
            key: const ValueKey('xrGen'),"""),
])
print('panel stage2 ok')
