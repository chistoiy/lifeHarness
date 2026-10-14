import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// U5（UX 审计真机批 2026-10-05 · 词表已获产品 OK）用户可见文案**禁词闸**。
///
/// 口径：`lib/**` 的**代码行**（注释行不裁——工单语言写注释合法）不许出现开发者黑话
/// 与版本占位串，这些串会直接进 UI/提示条/角标，真机语义树已抓实过：
///  · `联动Lx`：模块联动编号（「准备事项（勾选即转待办 · 联动 L3）」「（联动 L10）」）；
///  · `V1x`：版本占位（宫格磁贴角标 `V1.0`/`V1.x`、`规划 V1.x` toast、
///    呵护 `_VChip('V1.x')`、外观页「主题市场…V1.x 上线」）；
///  · `（模拟）`：把「这版还是假的」写给用户（「添加图片附件（模拟）」「搜索分类（模拟）」）；
///  · `正交|热加载|配置文件`：设计令牌那套自述（「设计令牌热加载」「与深色模式正交」）。
/// 教学句式族（「长按/点击…即可」）与 emoji 面**不在本闸**，走交互整改 T13 专项批，
/// 不在这里重复立案。
///
/// 存量按**棘轮**登记（登记值＝登记时该文件命中数，只许减不许增；减到 0 请删项归还默认面）。
/// 清污本身＝独立文案批：同一串字在原型侧也有，UI 变更要先过原型门，本批不动产品文案。
///
/// 重生成登记面：`U5_GUARD_DUMP=1 flutter test test/u5_copy_banned_guard_test.dart`
///
/// 同文件第二条闸＝`DropdownButton` 禁新增（既定口径：数值→就地滚轮、枚举→半屏选择页，
/// 见 `docs/UI组件规范.md`；2026-10-05 实测存量 29 处，整改另批）。
void main() {
  const libDir = 'lib';

  /// 只留「代码原文」：按字符串状态扫描，剥掉行尾 `//` 与 `/*`（字符串里的 `//`
  /// 不算，如 URL）。不这么做的话 `import x; // V1.53 批` 这类版本注释会被当成
  /// 用户可见文案命中——正是「守护被注释喂词」的坑。
  String codePart(String line) {
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (quote != null) {
        if (c == r'\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        quote = c;
      } else if (c == '/' && i + 1 < line.length && line[i + 1] == '/') {
        return line.substring(0, i);
      } else if (c == '/' && i + 1 < line.length && line[i + 1] == '*') {
        return line.substring(0, i);
      }
    }
    return line;
  }

  final families = <String, RegExp>{
    '联动Lx': RegExp(r'联动\s?L\d'),
    'V1x': RegExp(r'V1\.[0-9x]'),
    '模拟': RegExp(r'（模拟）|设置模拟'),
    '黑话': RegExp(r'正交|热加载|配置文件'),
    'DropdownButton': RegExp(r'\bDropdownButton\b'),
    // 顶栏标题居中（本批 2026-10-05 产品拍板＝全仓 67 处一次性摘净，**硬零面**）：
    // 原型只有一枚 `topHead`＝左标题（`#pageTitle` text-xl ＋ `#pageSub` 11px 小字，
    // 返回钮在左、动作钮在右），`app_theme.dart` 的 AppBarTheme 也早写着
    // `centerTitle: false`——63 个文件里逐页盖 `centerTitle: true` 属实现漂移。
    // 漂移的真实代价不是「不统一」而是**伪居中**：title 是两行 Column（标题＋副标题），
    // 居中的是那个块，块宽由副标题决定，标题文字实测落在 x=101.5（390dp 屏），
    // 离屏中心 195 偏左 93.5dp，还随副标题字数浮动；顶栏带动作钮时槽位不让。
    // 想留居中例外＝先改原型过门，再在这里登记例外面（当前为空）。
    '顶栏居中': RegExp(r'centerTitle:\s*true'),
  };

  /// 豁免面：整行命中但按拍板保留的（一行一条理由，别攒批糊）。
  final exempt = <String, RegExp>{
    // 'features/x/y.dart': RegExp(r'u5-ok: 理由'),
  };

  // 2026-10-05 上线时在 **HEAD 干净树**实测登记的存量面（U5_GUARD_DUMP 出数）。
  final baseline = <String, Map<String, int>>{
    '联动Lx': {
      'features/calendar/presentation/calendar_page.dart': 1,
      'features/care/presentation/care_remind_page.dart': 1,
      'features/care/presentation/care_stats_page.dart': 1,
      'features/care/presentation/vaccine_page.dart': 3,
      'features/days/presentation/day_detail_page.dart': 4,
      'features/days/presentation/day_edit_page.dart': 2,
      'features/days/presentation/day_remind_page.dart': 1,
      'features/days/presentation/days_page.dart': 2,
      'features/goals/presentation/goal_review_page.dart': 1,
      'features/goals/presentation/goals_page.dart': 1,
      'features/inbox/presentation/inbox_page.dart': 2,
      'features/items/data/items_repository.dart': 3,
      'features/items/presentation/item_detail_page.dart': 4,
      'features/items/presentation/item_edit_page.dart': 3,
      'features/journal/presentation/diary_edit_page.dart': 1,
      'features/read/presentation/biblio/book_info_page.dart': 1,
      'features/read/presentation/read_sheets_b3.dart': 1,
      'features/read/presentation/read_sheets_b4.dart': 1,
      'features/read/presentation/reader/reader_sel_ops.dart': 1,
      'features/read/presentation/stats/quotes_lib_page.dart': 4,
      'features/read/presentation/stats/read_stat_page.dart': 1,
      'features/todo/presentation/widgets/quadrant_board.dart': 1,
      'features/todo/presentation/widgets/todo_edit_sheet.dart': 3,
      'features/todo/presentation/widgets/todo_list_view.dart': 1,
    },
    'V1x': {
      'features/care/presentation/babies_page.dart': 1,
      'features/care/presentation/care_stats_page.dart': 1,
      'features/journal/presentation/diary_edit_page.dart': 2,
      'features/journal/presentation/widgets/ins_card.dart': 2,
      'features/journal/presentation/widgets/note_sheets.dart': 1,
      'features/ledger/presentation/ledger_pick_sheets.dart': 1,
      'features/read/presentation/stats/quotes_lib_page.dart': 1,
      'features/settings/presentation/recmg_page.dart': 1,
      'features/settings/presentation/settings_page.dart': 1,
      'features/todo/presentation/widgets/todo_edit_sheet.dart': 1,
      'shared/linkage/stats_providers.dart': 1,
    },
    '模拟': {
      'features/ledger/presentation/ledger_add_page.dart': 1,
      'features/ledger/presentation/ledger_cats_page.dart': 1,
      'features/ledger/presentation/ledger_pick_sheets.dart': 1,
    },
    '黑话': {
      'features/settings/presentation/settings_page.dart': 3,
      // 存量越线登记（阅读模块批2 · 2026-10-14 跑出本红）：命中＝布局弹层副标题里的
      // 「正交」（「结构 × 方向 正交两维」），该句由**思维导图批1**（2026-10-12）写入，
      // 该批门禁未带本闸，故今日现形——本批一行未动 mindmap。清污＝独立文案批
      // （同串在原型侧也有，UI 变更须先过原型门），登记值只许减。
      'features/mindmap/presentation/mindmap_layout_sheet.dart': 1,
    },
    'DropdownButton': {
      'features/calendar/presentation/calendar_page.dart': 1,
      'features/habit/presentation/habit_aux_sheets.dart': 1,
      'features/habit/presentation/habit_edit_sheet.dart': 2,
      'features/habit/presentation/habits_page.dart': 1,
      'features/items/presentation/item_edit_page.dart': 1,
      'features/ledger/presentation/ledger_export_page.dart': 2,
      'features/ledger/presentation/ledger_recur_page.dart': 2,
      'features/ledger/presentation/ledger_search_page.dart': 2,
      'features/read/presentation/read_sheets_b2.dart': 1,
      'features/read/presentation/shelf/book_form_page.dart': 1,
      'features/settings/presentation/notify_settings_page.dart': 1,
      'features/todo/presentation/widgets/todo_add_sheet.dart': 4,
    },
  };

  test('U5 禁词与 DropdownButton 只许减不许增（棘轮面）', () {
    final found = <String, Map<String, List<int>>>{};
    var scannedLines = 0;
    for (final f in Directory(libDir)
        .listSync(recursive: true)
        .whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      final lines = f.readAsStringSync().split(RegExp(r'\r?\n'));
      var inBlock = false;
      for (var i = 0; i < lines.length; i++) {
        final raw = lines[i];
        final t = raw.trim();
        var isComment = false;
        if (inBlock) {
          isComment = true;
          if (t.contains('*/')) inBlock = false;
        } else if (t.startsWith('///') || t.startsWith('//')) {
          isComment = true;
        } else if (t.startsWith('/*')) {
          isComment = true;
          inBlock = true;
        }
        if (isComment) continue;
        final code = codePart(raw);
        if (code.trim().isEmpty) continue;
        scannedLines++;
        for (final e in families.entries) {
          if (!e.value.hasMatch(code)) continue;
          final ok = exempt[rel];
          if (ok != null && ok.hasMatch(code)) continue;
          ((found[e.key] ??= <String, List<int>>{})[rel] ??= <int>[]).add(i + 1);
        }
      }
    }

    if (Platform.environment['U5_GUARD_DUMP'] == '1') {
      for (final fam in families.keys) {
        final m = found[fam] ?? const <String, List<int>>{};
        stdout.writeln('=== $fam 登记面（${m.values.expand((e) => e).length} 处 / ${m.length} 文件）===');
        final keys = m.keys.toList()..sort();
        for (final k in keys) {
          stdout.writeln("    '$k': ${m[k]!.length}, // 行 ${m[k]!.join(',')}");
        }
      }
      stdout.writeln('=== DUMP END（扫描代码行 $scannedLines）===');
      return;
    }

    expect(scannedLines, greaterThan(40000),
        reason: '扫描面骤减（只扫到 $scannedLines 行）＝解析器坏了，守护正在空转。');
    final problems = <String>[];
    for (final fam in families.keys) {
      final now = found[fam] ?? const <String, List<int>>{};
      final reg = baseline[fam] ?? const <String, int>{};
      for (final e in now.entries) {
        final b = reg[e.key];
        if (b == null) {
          problems.add('$fam 未登记：${e.key}（${e.value.length} 处 · 行 ${e.value.join(',')}）');
        } else if (e.value.length > b) {
          problems.add('$fam 上升：${e.key} ${e.value.length} > 登记 $b（行 ${e.value.join(',')}）');
        } else if (e.value.length < b) {
          problems.add('$fam 请收紧：${e.key} ${e.value.length} < 登记 $b（改小或删项）');
        }
      }
      for (final k in reg.keys.where((k) => !now.containsKey(k))) {
        problems.add('$fam 登记空转：$k 已无命中，删掉该登记项');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('顶栏默认值仍＝左标题（防「摘掉页内 override 又把主题默认值翻成 true」）', () {
    final theme = File('lib/core/theme/app_theme.dart').readAsStringSync();
    expect(theme.contains('centerTitle: false'), isTrue,
        reason: 'AppBarTheme 的 centerTitle 必须保持 false（原型 topHead＝左标题）。');
  });
}
