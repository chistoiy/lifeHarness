// 深色观感棘轮闸（2026-10-07 深色批·工单 §3 第一步）。
//
// 为什么是棘轮而不是一次性清扫：不透明近白字面当背景/表面，**静态判不出对错**——
// 渐变 hero 卡上的白底描边、图上遮罩、导出图片的纸面都可能是有意的（真机门才定得了）。
// 产品的既定口径＝T13 那一套：不做专项大清扫，**哪屏动到哪屏顺手清**，但闸必须现在就立住，
// 免得深色模式上线后白底面继续往外长。
//
// 口径：只数「不透明近白字面出现在背景/表面槽位」（Colors.white 与 #FFFFFF/#F8FAFC/#FAFAFA/#FDFDFD，
// 排除 `withValues/withOpacity` 半透明叠层）。阅读器热链（`lib/features/read/presentation/reader/**`）
// 有自己的深色/外观体系（工单 §5），整体不在本闸面。
//
// 再生成基线：`DARK_GUARD_DUMP=1 flutter test test/dark_surface_guard_test.dart`
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _bgSlot = RegExp(
    r'(backgroundColor|contentColor|canvasColor|barColor|cardColor|color)\s*:\s*(const\s+)?'
    r'(Colors\.white|Color\(0xFF(?:FFFFFF|F8FAFC|FAFAFA|FDFDFD)\))');
final _translucent = RegExp(r'withValues|withOpacity|\.withAlpha');

/// 有意白（不算深色缺陷）：黑底看图件、导出图片纸面、封面占位。删项须同时改这里的理由。
const _exempt = <String, String>{
  'lib/shared/widgets/image_lightbox.dart': '黑底看图件：控件与文字本就该是白',
  'lib/shared/widgets/share_card.dart': '导出分享图＝纸面，与 App 深浅无关',
  'lib/features/read/presentation/widgets/bs_cover.dart': '封面占位按书籍封面纸面渲染',
};

/// 基线＝登记时实测处数，只许减不许增（新增文件＝直接红）。
const _baseline = <String, int>{
    // 深色观感棘轮基线（2026-10-07 生成·只许减）：不透明近白字面用作背景/表面处数
    'lib/features/dashboard/presentation/dashboard_page.dart': 22,
    // 影音游批2 两枚新面：命中处全是 FAB 图标与卡面图上白字/白图标（渐变与封面之上的前景），
    // 底面一律吃 scheme/色板渐变，随主题与深色自动跟随——与 journal_page 那 7 处同一形态。
    // 登记≠放行：影音架的深色观感仍要走真机门＝复测包 6089 自验清单第 8 条。
    'lib/features/media/presentation/widgets/media_card.dart': 8,
    'lib/features/media/presentation/media_shelf_page.dart': 1,
    // 批3 影音沉浸计时页：8 处「白」全是深色渐变底上的半透明白胶囊/钮（白字），
    // 属深色实态；观感门随复测包 6090 真机复验，不合规再摘模糊/改透明度。
    'lib/features/media/presentation/media_timer_page.dart': 8,
    'lib/features/ledger/presentation/ledger_page.dart': 13,
    'lib/features/care/presentation/baby_view.dart': 9,
    'lib/features/read/presentation/stats/read_timer_page.dart': 9,
    'lib/features/care/presentation/cycle_view.dart': 8,
    'lib/features/habit/presentation/habits_page.dart': 8,
    // 影音游批2：记录页三态 FAB 收成一枚（该文件近白字面 7→6，登记值按实测收紧）。
    'lib/features/journal/presentation/journal_page.dart': 6,
    'lib/features/journal/presentation/widgets/ins_card.dart': 7,
    'lib/features/ledger/presentation/ledger_assets_page.dart': 6,
    'lib/features/care/presentation/vaccine_page.dart': 5,
    'lib/features/days/presentation/day_detail_page.dart': 5,
    'lib/features/days/presentation/days_page.dart': 5,
    'lib/features/habit/presentation/habit_auto_sheets.dart': 5,
    'lib/features/ledger/presentation/ledger_yearly_page.dart': 5,
    'lib/features/read/presentation/shelf/shelf_goal.dart': 5,
    'lib/features/calendar/presentation/calendar_page.dart': 4,
    'lib/features/care/presentation/care_stats_page.dart': 4,
    'lib/features/habit/presentation/habit_stat_page.dart': 4,
    'lib/features/ledger/presentation/ledger_hero_cfg_sheet.dart': 4,
    'lib/features/read/presentation/read_tab.dart': 4,
    'lib/features/read/presentation/shelf/book_detail.dart': 4,
    'lib/features/todo/presentation/widgets/pomo_screen.dart': 4,
    'lib/shared/linkage/timer_bar_overlay.dart': 6,
    'lib/features/calendar/presentation/time_stats_page.dart': 3,
    'lib/features/care/presentation/care_kit.dart': 3,
    'lib/features/days/presentation/days_kit.dart': 3,
    'lib/features/items/presentation/items_kit.dart': 3,
    'lib/features/items/presentation/items_page.dart': 3,
    'lib/features/ledger/presentation/ledger_import_page.dart': 3,
    'lib/features/read/presentation/import/local_import_page.dart': 3,
    'lib/features/settings/presentation/log_page.dart': 3,
    'lib/core/widgets/module_placeholder.dart': 2,
    'lib/features/calendar/presentation/category_page.dart': 2,
    'lib/features/calendar/presentation/widgets/time_pick_sheet.dart': 2,
    'lib/features/goals/presentation/goals_kit.dart': 2,
    'lib/features/habit/presentation/habit_aux_sheets.dart': 2,
    'lib/features/habit/presentation/habit_sheets.dart': 2,
    'lib/features/journal/presentation/diary_edit_page.dart': 2,
    'lib/features/ledger/presentation/ledger_recur_page.dart': 2,
    'lib/features/read/presentation/biblio/isbn_scan_page.dart': 2,
    'lib/features/read/presentation/shelf/shelf_long_press.dart': 2,
    'lib/features/read/presentation/shelf/shelf_spine_time.dart': 2,
    'lib/features/read/presentation/stats/read_log_page.dart': 2,
    'lib/features/settings/presentation/sync_page.dart': 2,
    'lib/features/todo/presentation/widgets/quadrant_board.dart': 2,
    'lib/features/todo/presentation/widgets/todo_add_sheet.dart': 2,
    'lib/features/todo/presentation/widgets/todo_list_view.dart': 2,
    'lib/core/theme/app_theme.dart': 1,
    'lib/core/widgets/wheel_date.dart': 1,
    'lib/features/calendar/presentation/widgets/grid_day_view.dart': 1,
    'lib/features/care/presentation/babies_page.dart': 1,
    'lib/features/care/presentation/baby_day_page.dart': 1,
    'lib/features/care/presentation/growth_page.dart': 1,
    'lib/features/care/presentation/milestone_page.dart': 1,
    'lib/features/days/presentation/day_edit_page.dart': 1,
    'lib/features/goals/presentation/goals_page.dart': 1,
    'lib/features/habit/presentation/habit_backfill_sheet.dart': 1,
    'lib/features/habit/presentation/habit_edit_sheet.dart': 1,
    'lib/features/habit/presentation/widgets/habit_tile.dart': 1,
    'lib/features/inbox/presentation/inbox_page.dart': 1,
    'lib/features/items/presentation/item_detail_page.dart': 1,
    'lib/features/journal/presentation/note_edit_focus.dart': 1,
    'lib/features/journal/presentation/note_tab.dart': 1,
    'lib/features/ledger/presentation/ledger_add_page.dart': 1,
    'lib/features/ledger/presentation/ledger_date_sheet.dart': 1,
    'lib/features/ledger/presentation/ledger_debt_page.dart': 1,
    'lib/features/ledger/presentation/ledger_export_page.dart': 1,
    'lib/features/ledger/presentation/ledger_pick_sheets.dart': 1,
    'lib/features/ledger/presentation/ledger_report_page.dart': 1,
    'lib/features/ledger/presentation/ledger_wish_page.dart': 1,
    'lib/features/read/presentation/biblio/biblio_search_page.dart': 1,
    'lib/features/read/presentation/read_sheets_b2.dart': 1,
    'lib/features/read/presentation/shelf/book_form_page.dart': 1,
    'lib/features/read/presentation/shelf/read_lists_page.dart': 1,
    'lib/features/read/presentation/shelf/shelf_fab.dart': 1,
    'lib/features/read/presentation/shelf/shelf_panel.dart': 1,
    'lib/features/read/presentation/shelf/shelf_views.dart': 1,
    'lib/features/read/presentation/stats/quotes_lib_page.dart': 1,
    'lib/features/read/presentation/stats/read_stat_heat_card.dart': 1,
    'lib/features/read/presentation/xray_words_page.dart': 1,
    'lib/features/settings/presentation/settings_page.dart': 1,
    'lib/features/settings/presentation/trash_page.dart': 1,
    'lib/features/settings/presentation/widgets/sync_verify_sheet.dart': 1,
    'lib/features/todo/presentation/todo_page.dart': 1,
    'lib/features/todo/presentation/widgets/todo_edit_sheet.dart': 1,
    'lib/shared/widgets/image_attach.dart': 1,
};

int _countIn(String path) {
  final src = File(path).readAsStringSync();
  var n = 0;
  for (final ln in src.split('\n')) {
    if (_bgSlot.hasMatch(ln) && !_translucent.hasMatch(ln)) n++;
  }
  return n;
}

List<String> get _dartFiles {
  final out = <String>[];
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) {
      out.add(e.path.replaceAll('\\', '/'));
    }
  }
  return out..sort();
}

void main() {
  test('深色观感棘轮：不透明近白底面只许减不许增（新增文件即红）', () {
    final found = <String, int>{};
    for (final f in _dartFiles) {
      if (f.contains('/read/presentation/reader/')) continue; // 阅读器自有体系
      if (_exempt.containsKey(f)) continue;
      final n = _countIn(f);
      if (n > 0) found[f] = n;
    }
    if (Platform.environment['DARK_GUARD_DUMP'] == '1') {
      for (final e in found.entries) {
      // ignore: avoid_print
        print("    '${e.key}': ${e.value},");
      }
      // ignore: avoid_print
      print('=== 共 ${found.length} 文件 / ${found.values.fold(0, (a, b) => a + b)} 处 ===');
      return;
    }
    final fresh = <String>[];
    final grown = <String>[];
    final shrunk = <String>[];
    for (final e in found.entries) {
      final b = _baseline[e.key];
      if (b == null) {
        fresh.add('${e.key}（新面 ${e.value} 处）');
      } else if (e.value > b) {
        grown.add('${e.key} $b→${e.value}');
      } else if (e.value < b) {
        shrunk.add('${e.key} $b→${e.value}');
      }
    }
    final stale = <String>[];
    for (final f in _baseline.keys) {
      if (!found.containsKey(f)) {
        stale.add('$f（登记 ${_baseline[f]} 处，现已归零→删项）');
      }
    }
    for (final s in shrunk) {
      // ignore: avoid_print
      print('[dark_surface_guard 提醒] 白底面变少了，请跑 DARK_GUARD_DUMP=1 收紧登记：$s');
    }
    expect(fresh, isEmpty, reason: '深色模式已上线，新增不透明近白底面必须先过真机观感门：\n$fresh');
    expect(grown, isEmpty, reason: '登记面只许减不许增：\n$grown');
    expect(stale, isEmpty, reason: '已归零的文件要删登记项（留着＝死登记）：\n$stale');
  });

  test('豁免项必须仍在册且仍真有白底面（防「白名单空挂」）', () {
    for (final e in _exempt.entries) {
      expect(File(e.key).existsSync(), isTrue, reason: '${e.key} 已不存在，白名单要删');
      expect(_countIn(e.key), greaterThan(0),
          reason: '${e.key} 已无白底面，豁免失效应出名单（理由＝${e.value}）');
      expect(e.value.length, greaterThan(8), reason: '豁免必须写理由，不许空挂');
    }
  });
}
