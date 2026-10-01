# tools/attic/xr_batchB_panel_patch.py — 批B 面板改造一次性脚本（命中断言由 python assert 承担）
import io

def patch(p, pairs):
    s = io.open(p, encoding='utf-8', newline='').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, a[:60], s.count(a))
        s = s.replace(a, b)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

# 1) providers: 两条接力旗
patch('lib/features/read/presentation/read_providers.dart', [
    ("""/// 书架长按「生成/管理全书索引」→ 阅读页落地自动开 X-Ray 段的一次性接力旗。
final readerXrOpenTabProvider = StateProvider<String?>((ref) => null);""",
     """/// 书架长按「生成/管理全书索引」→ 阅读页落地自动开 X-Ray 段的一次性接力旗。
final readerXrOpenTabProvider = StateProvider<String?>((ref) => null);

/// 选区迷你卡「查看全部位置」→ 面板直达该词条详情（批B F6）。
final readerXrFocusWordProvider = StateProvider<String?>((ref) => null);

/// 选区「X-Ray」未命中 → 面板自动开「加为词条」弹层并预填（批B F8①）。
final readerXrAddWordProvider = StateProvider<String?>((ref) => null);"""),
])

# 2) panel 主体改造
p = 'lib/features/read/presentation/reader/reader_xray_panel.dart'
patch(p, [
    ("import './reader_xray_sheets.dart';",
     "import './reader_xray_learn_sheets.dart';\nimport './reader_xray_sheets.dart';"),

    ("""  bool? _showCitesOverride; // 弹层内「显示全部引用」的本页覆盖（null＝跟随持久偏好）
  int _seenRev = -1;""",
     """  bool? _showCitesOverride; // 弹层内「显示全部引用」的本页覆盖（null＝跟随持久偏好）
  int _seenRev = -1;
  // 批B 整理模式（xrfrag：行前勾选 + 底部「合并/移除」条）。
  bool _org = false;
  final Set<int> _sel = {};
  bool _relayShown = false;"""),

    ("""    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: _head(sched, md5, task, live),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: _typeRow(_scoped(snap.entities, snap.anchors)),
        ),
        Expanded(
          key: const ValueKey('xrScroll'),
          child: _curId == null
              ? _list(snap, md5)
              : _detail(snap, md5, _curId!),
        ),
      ],
    );
  }""",
     """    // 接力：选区迷你卡「查看全部位置」直达详情；未命中词自动开加词弹层（各消费一次）。
    if (!_relayShown) {
      final focus = ref.read(readerXrFocusWordProvider);
      final addWord = ref.read(readerXrAddWordProvider);
      if (focus != null || addWord != null) {
        _relayShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (addWord != null) {
            ref.read(readerXrAddWordProvider.notifier).state = null;
            _openAdd(md5, prefill: addWord);
          }
          if (focus != null) {
            ref.read(readerXrFocusWordProvider.notifier).state = null;
            final hit =
                snap.entities.where((e) => e.name == focus).firstOrNull;
            if (hit != null) setState(() => _curId = hit.id);
          }
        });
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: _head(sched, md5, task, live),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: _typeRow(_scoped(snap.entities, snap.anchors)),
        ),
        if (sched.suggestion(widget.book.id) case final sug?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: _suggestionCard(sched, md5, sug),
          ),
        Expanded(
          key: const ValueKey('xrScroll'),
          child: _curId == null
              ? _list(snap, md5)
              : _detail(snap, md5, _curId!),
        ),
        if (_org && _curId == null) _orgBar(sched, md5, snap),
      ],
    );
  }

  Future<void> _openAdd(String? md5, {String prefill = ''}) => showXrAddSheet(
        context,
        ref,
        book: widget.book,
        md5: md5,
        prefill: prefill,
        ensureMd5: () =>
            ref.read(xraySchedulerProvider).ensureMd5(widget.book),
      );

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
  }"""),

    # 段二行尾追加 ＋加词/整理词条 chips
    ("""            for (final s in const [('page', '当前页'), ('chapter', '本章'), ('book', '全书')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  key: ValueKey('xr-scope-${s.$1}'),
                  onTap: () => setState(() {
                    _scope = s.$1;
                    _curId = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _scope == s.$1
                          ? Colors.white.withValues(alpha: .9)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      s.$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _scope == s.$1
                            ? const Color(0xFF0F172A)
                            : _XrStyle.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),""",
     """            for (final s in const [('page', '当前页'), ('chapter', '本章'), ('book', '全书')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  key: ValueKey('xr-scope-${s.$1}'),
                  onTap: () => setState(() {
                    _scope = s.$1;
                    _curId = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _scope == s.$1
                          ? Colors.white.withValues(alpha: .9)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      s.$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _scope == s.$1
                            ? const Color(0xFF0F172A)
                            : _XrStyle.muted,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            // 批B：段头部「＋加词 / 整理词条」（原型 xrHeadHtml r2 右组）。
            _chip('xrAddBtn', '＋加词', () => _openAdd(md5)),
            const SizedBox(width: 6),
            GestureDetector(
              key: const ValueKey('xrOrgBtn'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _org = !_org;
                if (!_org) _sel.clear();
                _curId = null;
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _org ? _XrStyle.accent : null,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: _org
                          ? _XrStyle.accent
                          : Theme.of(context).dividerColor),
                ),
                child: Text(
                  '整理词条',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: _org ? Colors.white : null),
                ),
              ),
            ),
          ],
        ),"""),
])
print('panel stage1 ok')
