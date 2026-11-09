import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-11-07 真机反馈十二整改 · 常驻守护（批2 立）。
///
/// 口径：工单 `docs/handoff/交棒话术-20261107-真机反馈九条整改.md` §1「新增常驻」。
/// 批1/批2 六组＋批3 三组（2026-11-08 批3 落地后启用）：「免打扰设置非零操作」
/// 「复盘时间非四档常量」「就地滚轮零两段式」。提前钉未落地的面会让门禁恒红
/// （守护不是许愿池）。
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
  const pNotify = 'lib/features/settings/presentation/notify_settings_page.dart';
  const pNotifyWheels = 'lib/core/widgets/notify_wheel_rows.dart';
  const pNotifySettings = 'lib/core/settings/user_settings.dart';
  const pNotifyService = 'lib/core/notifications/notification_service.dart';
  const pBootMain = 'lib/main.dart';
  const pHealthMed = 'lib/features/health/presentation/health_med_page.dart';

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

  group('真机反馈十二整改 · 批3 形态守护（反馈批3 落地后启用）', () {
    test('⑦ 复盘时间：非零操作、非四档常量、原型与实现同为就地滚轮', () {
      final s = read(pNotify);
      expect(s.contains('DiaryTimeWheelRow('), isTrue,
          reason: '实现侧必须换成就地时/分滚轮行');
      expect(s.contains('value: n.diaryTime'), isTrue);
      expect(s.contains("const ['21:00', '21:30', '22:00', '22:30']"), isFalse,
          reason: '四档常量回潮');
      expect(s.contains("_selectRow(context, '晚间复盘提醒时间'"), isFalse,
          reason: '复盘时间不许退回下拉');
      final w = read(pNotifyWheels);
      expect(w.contains('InlineWheelTime('), isTrue);
      expect(w.contains("ValueKey('nf-diary-wheel')"), isTrue);
      final proto = read(pProtoSettings);
      for (final id in ['nfDiaryVal', 'nfDiaryBox', 'nfDiaryH', 'nfDiaryM']) {
        expect(proto.contains('id="$id"'), isTrue, reason: '原型复盘滚轮缺 $id');
      }
      expect(proto.contains('NF_M=Array.from({length:60}'), isTrue,
          reason: '分钟列必须 60 档，不许退回四档常量');
      expect(proto.contains("nfApply('diary')"), isTrue);
    });

    test('⑧ 免打扰：设置真落库、窗口判据可配、两处 toast 占位清零', () {
      final s = read(pNotify);
      expect(s.contains('DndWindowWheelRow('), isTrue);
      expect(s.contains('startHour: n.dndStartHour'), isTrue);
      expect(s.contains("_toast(context, '免打扰时段编辑"), isFalse,
          reason: '实现侧 toast 死键回潮');
      expect(s.contains('void _toast('), isFalse,
          reason: '页面 toast 占位方法应整段撤掉');
      expect(s.contains('NotificationService.configureDndWindow('), isTrue,
          reason: '落库后必须立刻灌入判据');
      final proto = read(pProtoSettings);
      for (final id in [
        'nfDndVal',
        'nfDndSet',
        'nfDndBox',
        'nfDndSH',
        'nfDndEH'
      ]) {
        expect(proto.contains('id="$id"'), isTrue, reason: '原型免打扰滚轮缺 $id');
      }
      expect(proto.contains("toast('编辑时段（模拟）')"), isFalse,
          reason: '原型侧 toast 死键回潮');
      final m = read(pNotifySettings);
      for (final k in ['dndStartHour', 'dndEndHour', 'dndHourOf(']) {
        expect(m.contains(k), isTrue, reason: '设置模型缺 $k');
      }
      final svc = read(pNotifyService);
      expect(svc.contains('static void configureDndWindow('), isTrue);
      expect(svc.contains('static int dndStartHour = 23;'), isTrue);
      expect(svc.contains('t.hour >= 23 || t.hour < 7'), isFalse,
          reason: '判据不许再写死 23/7');
      expect(read(pBootMain).contains('NotificationService.configureDndWindow('),
          isTrue, reason: '启动装配必须灌入落库窗口');
      expect(read(pHealthMed).contains('mdDndTx(NotificationService.inDndWindow'),
          isTrue, reason: '健康页仍按函数指针反推文案，判据签名不可改');
    });

    test('⑨ 滚轮就地内嵌：实现侧零两段式弹层', () {
      final w = read(pNotifyWheels);
      for (final banned in [
        'showModalBottomSheet',
        'showDialog',
        'Navigator.of(context).push',
      ]) {
        expect(w.contains(banned), isFalse,
            reason: '就地滚轮不许「点击→弹层→再操作」：$banned');
      }
      expect(w.contains('LHWheel('), isTrue);
      expect(w.contains('dndWindowLabel('), isTrue);
      expect(w.contains('onConfirm:'), isTrue);
    });
  });
}
