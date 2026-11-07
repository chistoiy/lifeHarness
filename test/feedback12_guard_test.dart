import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-11-07 真机反馈十二整改 · 常驻守护（批2 立）。
///
/// 口径：工单 `docs/handoff/交棒话术-20261107-真机反馈九条整改.md` §1「新增常驻」。
/// 只钉**本批已落地**的六组形态；批3 的「免打扰设置非零操作」「复盘时间非四档常量」
/// 随批3 落地时再启用，提前钉会让当前门禁恒红（守护不是许愿池）。
///
/// 全部为源码级判据：改错形态即红，不依赖 pump（这些面多为 AppBar / 背景层 /
/// 路由参数，widget 用例覆盖不到「是否在安全区外」这类结构事实）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const pTags = 'lib/features/journal/presentation/tag_manage_page.dart';
  const pSettings = 'lib/features/settings/presentation/settings_page.dart';
  const pReader = 'lib/features/read/presentation/reader/reader_page.dart';
  const pBoot = 'lib/features/read/presentation/reader/reader_page_boot.dart';
  const pSheets =
      'lib/features/read/presentation/reader/reader_bottom_sheets.dart';
  const pDetail = 'lib/features/read/presentation/shelf/book_detail.dart';
  const pRoutes = 'lib/features/read/presentation/read_routes.dart';
  const pProtoTime = 'prototype/index-time.html';
  const pProtoSettings = 'prototype/index-settings.html';
  const pProtoBooks = 'prototype/index-bookshelf.html';

  group('真机反馈十二整改 · 批1/批2 形态守护', () {
    test('① 标签管理：顶栏三枚线性图标，内容区零文字按钮', () {
      final s = read(pTags);
      const keys = [
        "ValueKey('tg-fold-all')",
        "ValueKey('tg-sort')",
        "ValueKey('tg-add')",
      ];
      for (final k in keys) {
        expect(s.contains(k), isTrue, reason: '顶栏缺图标 $k');
        expect(s.split(k).length - 1, 1, reason: '$k 重复');
      }
      expect(s.contains('tg-add-top'), isFalse, reason: '内容区添加按钮回潮');
      expect(s.contains('class _TopBtn'), isFalse, reason: '文字按钮组件回潮');
      expect(s.contains('＋ 添加标签'), isFalse, reason: '内容区文字按钮回潮');
      // 两档排序语义仍在（0＝池序 / 1＝引用数降序）。
      expect(s.contains('_sortMode == 0 ? 1 : 0'), isTrue);
      expect(s.contains('copy.sort((a, b)'), isTrue);
      final proto = read(pProtoTime);
      for (final id in ['tagTopActions', 'tgFoldBtn', 'tgSortBtn', 'tgAddBtn']) {
        expect(proto.contains('id="$id"'), isTrue, reason: '原型顶栏缺 $id');
      }
    });

    test('② 外观：零重复主题入口、零主题色行、零顶栏昼夜钮', () {
      final s = read(pSettings);
      for (final banned in [
        '更多主题 ›',
        '全部主题 ›',
        '主题市场（GitHub',
        'theme-dot-',
        "Text('主题色'",
        'Icons.palette_outlined',
      ]) {
        expect(s.contains(banned), isFalse, reason: '重复/已撤入口回潮：$banned');
      }
      expect(s.contains('_ThemeGrid(registry: registry'), isTrue,
          reason: '7 套网格必须仍是唯一主题入口');
      expect(s.contains("key: const ValueKey('dark-mode-seg')"), isTrue,
          reason: '深浅色三档必须仍是唯一模式入口');
      final proto = read(pProtoSettings);
      expect(proto.contains('id="themeStyleRow"'), isTrue);
      expect(proto.contains('id="darkModeSeg"'), isTrue);
      // 隐藏的共享弹层标题「全部主题」是保留的死码债（并入专批清），
      // 这里只钉**按钮入口**：文案带 › 的两枚与 openSheet 调用都必须为零。
      expect(proto.contains('更多主题 ›'), isFalse);
      expect(proto.contains('全部主题 ›'), isFalse);
      expect(
          RegExp(r"<button[^>]*openSheet\('sheetThemeMarket'\)").hasMatch(proto),
          isFalse);
      expect(RegExp(r'id="themeDots"|<b>主题色</b>').hasMatch(proto), isFalse);
      expect(
          RegExp(r'onclick="toggleTheme\(\)"|function toggleTheme\(')
              .hasMatch(proto),
          isFalse);
    });

    test('③ 时间主屏：零「时间」标题行，日期/工具行置顶', () {
      final proto = read(pProtoTime);
      expect(proto.contains("const TITLES={'p-calendar':['','']"), isTrue);
      expect(proto.contains('id="hdM"') && proto.contains('id="calTools"'),
          isTrue);
      expect(proto.contains("const flat=p==='p-calendar'"), isTrue);
      // 实现侧 CalendarPage 本就无标题行；这里只钉它没有被「补回去」。
      final cal =
          read('lib/features/calendar/presentation/calendar_page.dart');
      expect(cal.contains("Text('时间'"), isFalse);
    });

    test('④ 阅读底纹：背景层在 SafeArea 之外，正文仍在其内', () {
      final s = read(pReader);
      final iBg = s.indexOf('child: BrBackdrop(');
      final iSafe = s.indexOf('child: SafeArea(', iBg);
      expect(iBg, greaterThan(-1), reason: '背景层消失');
      expect(iSafe, greaterThan(iBg), reason: '背景层被塞回安全区内＝状态栏无底纹');
      expect(s.contains('child: const SizedBox.expand(),'), isTrue,
          reason: '外层背景层必须自己铺满，不靠正文撑');
      final inner = s.substring(iSafe, s.indexOf('child: _stage(th)', iSafe));
      expect(inner.contains('BrBackdrop('), isFalse,
          reason: '背景层不能又画一遍在正文层');
      expect(
          s.indexOf('key: _stackKey') > iSafe &&
              s.indexOf('key: _stackKey') < s.indexOf('child: _stage(th)'),
          isTrue,
          reason: '正文与 chrome 必须留在安全区内的 Stack');
    });

    test('⑤ 目录行：点行进阅读器正文对应章节（不是只筛书摘）', () {
      final detail = read(pDetail);
      expect(detail.contains("'/read/reader/\${b.id}?chapter="), isTrue,
          reason: '目录行必须带章节参数进阅读器');
      expect(detail.contains('Uri.encodeComponent(s.title)'), isTrue);
      expect(detail.contains("ValueKey('toc-q-"), isTrue,
          reason: '本章书摘角标仍是筛选入口，别把能力弄丢');
      expect(detail.contains('Icons.chevron_right'), isTrue,
          reason: '目录行需要可点反馈');
      expect(read(pRoutes).contains('initialChapter:'), isTrue);
      expect(read(pReader).contains('final String? initialChapter;'), isTrue);
      final boot = read(pBoot);
      expect(boot.contains('widget.initialChapter'), isTrue);
      expect(boot.contains('_gotoChapter(ci)'), isTrue,
          reason: '装载完成后必须真跳章');
      final proto = read(pProtoBooks);
      expect(proto.contains('function tocJump(ch)'), isTrue);
      expect(proto.contains('brGotoCh(ci)'), isTrue,
          reason: '原型目录行必须进正文');
    });

    test('⑥ 进度：逻辑页与原书页双读数并存', () {
      final sheets = read(pSheets);
      for (final k in [
        'required this.logicLabel',
        'required this.paperLabel',
        "'brStLogic'",
        "'brStPaper'",
        'ValueKey(key)',
        '当前屏 · 逻辑页',
        '原书 · 纸书页',
      ]) {
        expect(sheets.contains(k), isTrue, reason: '进度弹层缺 $k');
      }
      final reader = read(pReader);
      expect(reader.contains('pag.estTotal'), isTrue);
      expect(reader.contains('pag.gPosEst(_pos.ci, _pos.pg)'), isTrue);
      expect(reader.contains('_book?.pages ?? 0'), isTrue,
          reason: '原书页必须由登记总页数折算');
      expect(reader.contains('未登记总页数'), isTrue);
      final proto = read(pProtoBooks);
      expect(proto.contains('id="brStLogic"'), isTrue);
      expect(proto.contains('id="brStPaper"'), isTrue);
    });
  });
}
