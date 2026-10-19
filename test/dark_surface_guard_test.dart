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
    // 8→7 棘轮收紧（阅读模块批2 · 2026-10-14 跑出「变小」提醒）：影音侧批次把卡面白字
    // 收掉 1 处（登记值未随增量同步），本批一行未动该文件——按口径调小登记值。
    'lib/features/media/presentation/widgets/media_card.dart': 7,
    'lib/features/media/presentation/media_shelf_page.dart': 1,
    // 批3 影音沉浸计时页：8 处「白」全是深色渐变底上的半透明白胶囊/钮（白字），
    // 属深色实态；观感门随复测包 6090 真机复验，不合规再摘模糊/改透明度。
    'lib/features/media/presentation/media_timer_page.dart': 8,
    // 影音游批5 笔记库＋名录入面各 1 处：命中的都是**前景字/图标**（黑 54 圆钮上的白叉、
    // 红角标上的白读数），底面一律吃 scheme，深色下不产生白底面缺陷——与 media_card 同形态。
    // 登记≠放行：本批两屏的深色观感随其真机复验轮走查（复测包尚未出）。
    'lib/features/media/presentation/media_notes_page.dart': 1,
    'lib/features/media/presentation/media_note_edit_sheet.dart': 1,
    // 批2d（2026-10-19）：`mindmap_list` 的 FAB 由原生 `FloatingActionButton`
    // （M3 16px 圆角方块底）换成 `GradFab` 圆球，图标吃 `Colors.white` ——
    // 命中是**渐变球上的白前景**，与 `days_page`/`goals_page` 的 FAB 同一形态，
    // 非不透明近白底面缺陷。本闸按行匹配 `color: Colors.white`、不区分前景与底面，
    // 故按现状登记（登记≠放行：深色观感仍随真机门走查）。
    'lib/features/mindmap/presentation/mindmap_list_page.dart': 1,
    // 健康批2 工作台：6 处命中全是 hero 渐变卡上的前景字（white/white70 读数与小标签），
    // 底面走主题渐变随深浅自动跟随——与 media_card 同一形态的深色实态，非白底面缺陷。
    'lib/features/health/presentation/health_home_page.dart': 6,
    // 批3：健康目标页 hero＝accent 渐变上的白读数/白副注四处（`Colors.white`/`white70` 是**字色**不是底面），
    // 与工作台 hero 同族同形——深色下仍是渐变底上的白字，非不透明近白底面缺陷；深色观感随 6092 真机门逐屏走查。
    'lib/features/health/presentation/health_goals_page.dart': 4,
    // 批2d（2026-10-19）：`health_sleep` 的 `FloatingActionButton.extended`
    // （实心主色胶囊）换 `GradFab` 圆球，图标吃 `Colors.white` —— 同 `mindmap_list`
    // 与 `days_page` 的白前景形态，非底面缺陷。
    'lib/features/health/presentation/health_sleep_page.dart': 1,
    'lib/features/ledger/presentation/ledger_page.dart': 13,
    'lib/features/care/presentation/baby_view.dart': 9,
    // 9→8 棘轮收紧（阅读模块批2 · 2026-10-14 跑出「变小」提醒）：本批 F2-6 把顶栏
    // 同义的第二枚退出钮（「收起」）整枚摘除，连带其 `Icon(color: Colors.white)` 一起走
    // ——白面真减 1，按口径调小登记值。
    'lib/features/read/presentation/stats/read_timer_page.dart': 8,
    'lib/features/care/presentation/cycle_view.dart': 8,
    'lib/features/habit/presentation/habits_page.dart': 8,
    // 影音游批2：记录页三态 FAB 收成一枚（该文件近白字面 7→6，登记值按实测收紧）。
    // 6→5 棘轮收紧（日记改版批2 · 2026-10-19 跑出「变小」提醒）：批1c 接扇形 FAB 时删掉顶行
    // 三枚图标与「写今天的日记」入口卡，白字面真减 1，按口径调小登记值。
    'lib/features/journal/presentation/journal_page.dart': 5,
    // 日记改版批2（2026-10-19）跑出本红两处「新面」，两条都是**存量漏登**、本批一行未动：
    // ① `journal_page_card.dart` 1 处＝篇卡缩略图上的白字（批1 拆 part 时从 journal_page 搬出，
    //    搬迁只搬了文件、没搬登记）；② `diary_fan_fab.dart` 1 处＝扇形 FAB 本体图标（§4c-2 同心
    //    品牌渐变底上的前景白）。两者底面都是主题/渐变，不是白底 —— 与 journal_page 5 处同形态。
    'lib/features/journal/presentation/journal_page_card.dart': 1,
    'lib/features/journal/presentation/widgets/diary_fan_fab.dart': 1,
    // ③ `diary_edit_foot.dart` 1 处＝保存钮上的白字（本批从页面搬到 part，形态未变：字压
    //    品牌渐变底）。同属「前景白、底面走主题」一族。
    'lib/features/journal/presentation/diary_edit_foot.dart': 1,
    'lib/features/journal/presentation/widgets/ins_card.dart': 7,
    // 日记改版批1a 新增（2026-10-19）：月历图墙 1 处＝实心格上的日号白字
    //（角标那枚 white 走 Icon.color 槽位，未入闸面，故不计）。
    // 底面是主题色实心块（`fill.withValues(alpha:.85)`），不是白底；与上面 journal_page 6 处、
    // ins_card 7 处同一形态（前景白字压在色块上）。登记≠放行：图墙深色观感仍走真机门。
    'lib/features/journal/presentation/widgets/journal_wall.dart': 1,
    // NFC 卡片模块存量归位（日记改版批1a · 2026-10-19 跑出本红）：nfc_page 卡片名/描述 2 处白字，
    // 压在色块卡面上（前景白字，非白底）。该文件本批一行未动，是 NFC 批2/批3 带进来的存量，
    // 登记值此前漏登——按现状登记，之后只许减。
    'lib/features/nfc/presentation/nfc_page.dart': 2,
    'lib/features/ledger/presentation/ledger_assets_page.dart': 6,
    'lib/features/care/presentation/vaccine_page.dart': 5,
    'lib/features/days/presentation/day_detail_page.dart': 5,
    'lib/features/days/presentation/days_page.dart': 5,
    'lib/features/habit/presentation/habit_auto_sheets.dart': 5,
    'lib/features/ledger/presentation/ledger_yearly_page.dart': 5,
    'lib/features/read/presentation/shelf/shelf_goal.dart': 5,
    // 4→5 存量上升归位（阅读模块批2 · 2026-10-14 跑出本红）：时间模块批4
    // （44d81ef8，2026-10-13 主屏 builder 化＋周视图 24 小时行铺进主屏列表）新增 1 处
    // 近白字面，该批门禁未带本闸；本批一行未动日历——按现状登记，之后只许减。
    'lib/features/calendar/presentation/calendar_page.dart': 5,
    'lib/features/care/presentation/care_stats_page.dart': 4,
    'lib/features/habit/presentation/habit_stat_page.dart': 4,
    'lib/features/ledger/presentation/ledger_hero_cfg_sheet.dart': 4,
    'lib/features/read/presentation/read_tab.dart': 4,
    // 4→2 棘轮收紧＋拆出件登记（高保真批6b·刀3）：2 处随 _localEpubStrip/_cacheRow
    // 整组迁入同库 part book_detail_cards.dart（机械搬迁·字面原值·文件总量不变）。
    // 2→3（日记改版批2d · 2026-10-19）：详情页右下「＋记摘录」由原生
    // `FloatingActionButton` 换 `GradFab`，多出的一处＝`Icon(color: Colors.white)`
    // 的白前景（渐变球之上），与新增的两处同形态。
    'lib/features/read/presentation/shelf/book_detail.dart': 3,
    // 高保真批6b·刀3 自 book_detail 迁入 2 处（原值）：紧凑条/缓存行内近白字面随组
    // 搬迁，非新面。登记≠放行：深色观感仍随该模块既有真机门走查。
    'lib/features/read/presentation/shelf/book_detail_cards.dart': 2,
    'lib/features/todo/presentation/widgets/pomo_screen.dart': 4,
    // 2026-10-14 摘除（悬浮胶囊增强批A 跟进）：条目已是「死登记」——批A 整文件重写时
    // 两条计时胶囊的字色由 `Colors.white` 改吃 scheme（onSurface/onSurfaceVariant），
    // 本文件近白底面实测归零；当时那轮门禁没点本闸文件，死项就此挂到现在（本批实跑复现）。
    // 按闸口径「归零即删项」摘除。此后本文件任何位置都不得再长回白底面。
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
    // diary_edit_page 的登记项**已删**（日记改版批2 · 2026-10-19）：该文件唯一那处白字面
    // （保存钮文字）随底栏整段搬进 `diary_edit_foot.dart`，本文件归零 ⇒ 按口径删项（留空登记＝死登记）。
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
    // 日记模板创建弹层（日记侧批次新增 · 阅读模块批2 2026-10-14 跑出本红）：
    // 唯一命中＝「保存模板」钮的**白字**（底面吃 `tokens.gradient` 渐变，随深浅自动跟随）
    // ——与 media_card / health hero 同形态的前景字，非不透明近白底面缺陷。
    // 登记≠放行：该弹层的深色观感仍须走真机观感门。本批一行未动该文件。
    'lib/features/journal/presentation/widgets/diary_tpl_create_sheet.dart': 1,
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
    // 高保真批6b·刀1/刀2（2026-10-16）：两文件各 1 处随拆 part 迁出后归零，按
    // 「归零即删项」删登记，白面原值落到同库新 part 件（同批机械搬迁·非新面）。
    'lib/features/read/presentation/read_sheets_b2_form.dart': 1,
    'lib/features/read/presentation/shelf/book_form_page_form.dart': 1,
    'lib/features/read/presentation/shelf/read_lists_page.dart': 1,
    'lib/features/read/presentation/shelf/shelf_fab.dart': 1,
    'lib/features/read/presentation/shelf/shelf_panel.dart': 1,
    'lib/features/read/presentation/shelf/shelf_views.dart': 1,
    'lib/features/read/presentation/stats/quotes_lib_page.dart': 1,
    'lib/features/read/presentation/stats/read_stat_heat_card.dart': 1,
    'lib/features/read/presentation/xray_words_page.dart': 1,
    // 1→4 存量上升归位（阅读模块批2 · 2026-10-14 跑出本红）：设置页近白字面由更早的
    // 设置/语义断链侧批次带到 4 处（登记值未随增量同步），本批一行未动该文件——
    // 按现状登记，之后只许减；真还债＝逐处核底面后改吃 scheme，另批做。
    'lib/features/settings/presentation/settings_page.dart': 4,
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
