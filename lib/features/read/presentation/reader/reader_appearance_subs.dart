part of 'reader_appearance_sheet.dart';

/// R3-7 · 外观二级页（原型 sheetBrApSub）：**同一弹层内部页面栈**（宿主
/// `_ApSheetState._sub`），不嵌套第二个 showModalBottomSheet。
/// 头部＝⌄返回钮 + 居中标题 + 「当前选择 · X」副标题；底部「完成 · 返回外观」。
/// 子页内选择即时写草稿，副标题与主页入口卡回显随同一 state 重建同步。
/// 路线＝extension part（开发计划书 §2.2 私有巨型 State）；setState 一律走宿主
/// _set/_rebuild/_openSub/_closeSub 口，扩展体内不碰 protected 成员。
extension _ApSheetSubs on _ApSheetState {
  String get _subTitle => switch (_sub) {
    'font' => '字体样式',
    'ind' => '首行缩进',
    'turn' => '翻页方式',
    'theme' => '纸色主题',
    'bg' => '背景图片',
    _ => '简繁',
  };

  String get _subCur => switch (_sub) {
    'font' => _fontLbl,
    'ind' => _indLbl,
    'turn' => _turnLbl,
    'theme' => _themeLbl,
    'bg' => _bgLbl,
    _ => _s2tLbl,
  };

  List<Widget> _apSub(ColorScheme cs) => [
    Row(
      children: [
        IconButton(
          key: const ValueKey('brApSub-back'),
          onPressed: _closeSub,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            Icons.keyboard_arrow_down,
            semanticLabel: '返回',
            color: cs.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                _subTitle,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '当前选择 · $_subCur',
                key: const ValueKey('brApSubSub'),
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 40),
      ],
    ),
    const SizedBox(height: 6),
    Expanded(
      child: ListView(
        controller: widget.scrollCtl,
        children: [
          switch (_sub) {
            'font' => _fontSub(cs),
            'ind' => _rowsSub(
              const [
                ('auto', '跟随原书（默认）'),
                ('2', '两全角'),
                ('none', '无缩进'),
              ],
              _d.indMode,
              (v) => _set(_d.copyWith(indMode: v)),
              'brApIndent',
            ),
            'turn' => _rowsSub(
              const [('page', '翻页（左右翻）'), ('scroll', '滚动（上下连贯）')],
              _d.mode,
              (v) => _set(_d.copyWith(mode: v)),
              'brApTurn',
            ),
            'theme' => _themeSub(cs),
            'bg' => _bgSub(cs),
            _ => _rowsSub(
              const [('orig', '跟随原书'), ('s', '简体'), ('t', '繁体')],
              _d.s2t,
              (v) => _set(_d.copyWith(s2t: v)),
              'brApS2T',
            ),
          },
          const SizedBox(height: 8),
        ],
      ),
    ),
    FilledButton(
      key: const ValueKey('brApSubDone'),
      style: FilledButton.styleFrom(
        backgroundColor: context.tokens.accent,
      ),
      onPressed: _closeSub,
      child: const Text('完成 · 返回外观'),
    ),
  ];

  /// 通用三/两选行（原型 brApRows：整行卡 + 右侧「当前选择」标记）。
  Widget _rowsSub(
    List<(String, String)> opts,
    String cur,
    ValueChanged<String> onPick,
    String keyBase,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
    children: [
      for (final (v, l) in opts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            key: ValueKey('$keyBase-$v'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onPick(v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cur == v ? cs.primary : cs.outlineVariant,
                  width: cur == v ? 1.8 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (cur == v)
                    Text(
                      '当前选择',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
    );
  }

  // ---------- 字体样式（分类 chips + 三列网格各自预览字形） ----------

  Widget _fontSub(ColorScheme cs) {
    final cats = ['全部', ...kBrFonts.keys.map(brFontCat).toSet()];
    final shown = kBrFonts.entries
        .where((e) => _fontCat == '全部' || brFontCat(e.key) == _fontCat)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '字体（系统字体 · 可扩展下载，控制包体积）',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey('brApFontCats'),
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in cats)
              _segPill(
                keyTag: 'brApFontCat-$c',
                label:
                    '$c(${c == '全部' ? kBrFonts.length : kBrFonts.keys.where((k) => brFontCat(k) == c).length})',
                on: _fontCat == c,
                onTap: () => _rebuild(() => _fontCat = c),
              ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (_, box) {
            const gap = 8.0;
            final w = (box.maxWidth - gap * 2) / 3;
            return Wrap(
              key: const ValueKey('brApFonts'),
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final e in shown)
                  GestureDetector(
                    key: ValueKey('brApFont-${e.key}'),
                    onTap: () => _set(_d.copyWith(font: e.key)),
                    child: Container(
                      width: w,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _d.font == e.key
                              ? cs.primary
                              : cs.outlineVariant,
                          width: _d.font == e.key ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '資治通鑑',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                              fontFamily: ReaderCfg(font: e.key).fontFamily,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            child: Text(
                              e.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ---------- 纸色主题（主题卡 + 背景色预设 + 自定义取色整组） ----------

  Widget _themeSub(ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '主题',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Row(
        key: const ValueKey('brApThemes'),
        children: [
          for (final e in kBrThemes.entries)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _themeCard(e.key, e.value.$1, e.value.$2, e.value.$3),
              ),
            ),
          Expanded(
            child: _themeCard('custom', '自定义', _d.bgColor, _d.textColor),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        '背景色',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Wrap(
        key: const ValueKey('brApBgs'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final hex in kBrBgs)
            GestureDetector(
              key: ValueKey('brApBg-$hex'),
              onTap: () => _set(_d.copyWith(theme: 'custom', bg: hex, bgImg: '')),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: ReaderCfg(bg: hex).bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        _d.theme == 'custom' &&
                            _d.bg == hex &&
                            _d.bgImg.isEmpty
                        ? cs.primary
                        : cs.outlineVariant,
                    width:
                        _d.theme == 'custom' && _d.bg == hex && _d.bgImg.isEmpty
                        ? 2
                        : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        '自定义颜色',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Container(
            key: const ValueKey('brApSwBg'),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _d.bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            key: const ValueKey('brApSwFg'),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _d.bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              'A',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: _d.textColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [_hueSlider(cs), const SizedBox(height: 6), _liteSlider(cs)],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        key: const ValueKey('brApPickTgt'),
        children: [
          for (final (k, l) in const [('bg', '改底色'), ('fg', '改字色')])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _segPill(
                keyTag: 'brApTgt-$k',
                label: l,
                on: _pickTgt == k,
                onTap: () => _rebuild(() => _pickTgt = k),
              ),
            ),
          const Spacer(),
          Text(
            _pickTgt == 'bg' ? '底色 ${_d.bg}' : '字色 ${_d.fg}',
            key: const ValueKey('brApHex'),
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ],
  );

  Widget _themeCard(String key, String name, Color bg, Color fg) {
    final on = _d.theme == key;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey('brApTheme-$key'),
      onTap: () => _rebuild(() {
        _d = key == 'custom'
            ? _d.copyWith(theme: 'custom')
            : _d.copyWith(
                theme: key,
                bg:
                    '#${(kBrThemes[key]!.$2.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
                fg:
                    '#${(kBrThemes[key]!.$3.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
              );
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: fg,
              ),
            ),
            Text(
              'Aa 阅读示例',
              style: TextStyle(fontSize: 7.5, color: fg.withValues(alpha: .7)),
            ),
          ],
        ),
      ),
    );
  }
  /// 色相滑杆（自绘彩虹轨道 · 禁系统取色器）。
  Widget _hueSlider(ColorScheme cs) => Container(
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      gradient: const LinearGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ),
    ),
    child: Slider(
      key: const ValueKey('brApHue'),
      min: 0,
      max: 360,
      divisions: 360,
      value: _hue.toDouble().clamp(0, 360),
      activeColor: Colors.white,
      inactiveColor: Colors.transparent,
      onChanged: (v) {
        _rebuild(() => _hue = v.round());
        _pickColor();
      },
    ),
  );

  /// 明度滑杆（黑→白轨道）。
  Widget _liteSlider(ColorScheme cs) => Container(
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      gradient: const LinearGradient(
        colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
      ),
    ),
    child: Slider(
      key: const ValueKey('brApLite'),
      min: 0,
      max: 100,
      divisions: 100,
      value: _lite.toDouble().clamp(0, 100),
      activeColor: Colors.transparent,
      inactiveColor: Colors.transparent,
      onChanged: (v) {
        _rebuild(() => _lite = v.round());
        _pickColor();
      },
    ),
  );

  // ---------- 背景图片（纹理 + 相册选图 + 淡化整组） ----------

  Widget _bgSub(ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '图片背景',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Wrap(
        key: const ValueKey('brApTex'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in kBrTex.entries)
            Builder(
              builder: (_) {
                // 「无」只有在既无纹理也无图片时才算选中（原型同式）。
                final on =
                    _d.bgTex == e.key &&
                    (e.key.isNotEmpty ||
                        (_d.bgImg.isEmpty && _pickedImg == null));
                return GestureDetector(
                  key: ValueKey(
                    'brApTex-${e.key.isEmpty ? 'none' : e.key}',
                  ),
                  onTap: () => _set(_d.copyWith(bgTex: e.key)),
                  child: SizedBox(
                    width: 56,
                    height: 44,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BrBackdrop(
                          cfg: ReaderCfg(
                            bg: _d.bg,
                            fg: _d.fg,
                            theme: 'custom',
                            bgTex: e.key,
                          ),
                          base: _d.bgColor,
                          thumb: true,
                          child: const SizedBox.expand(),
                        ),
                        Center(
                          child: Text(
                            e.value,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _d.textColor,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: on ? cs.primary : cs.outlineVariant,
                              width: on ? 2 : 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (_pickedImg != null || _d.bgImg.isNotEmpty)
            GestureDetector(
              key: const ValueKey('brApTex-img'),
              onTap: () => _rebuild(() {
                _pickedImg = null;
                _d = _d.copyWith(bgImg: '');
              }),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 44,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(_pickedImg ?? _d.bgImg),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: cs.surfaceContainerHighest,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.primary, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const Positioned(
                        bottom: 2,
                        right: 0,
                        left: 0,
                        child: Text(
                          '清除',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            backgroundColor: Color(0x99000000),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const ValueKey('brApPickImg'),
          onPressed: _pickImage,
          icon: const Icon(Icons.image_outlined, size: 16),
          label: const Text(
            '从相册选择图片',
            style: TextStyle(fontSize: 11.5),
          ),
        ),
      ),
      if (_pickErr.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _pickErr,
            style: TextStyle(fontSize: 10.5, color: cs.error),
          ),
        ),
      _slider(
        label: '淡化',
        valueLabel: '${_d.dim}',
        min: 0,
        max: 90,
        divisions: 18,
        value: _d.dim.toDouble(),
        keyTag: 'Dim',
        onChanged: (v) => _set(_d.copyWith(dim: v.round())),
      ),
      Text(
        '越淡越好读；点「无」回到纯色背景',
        style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
      ),
    ],
  );
}
