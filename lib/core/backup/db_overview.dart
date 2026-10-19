/// B-4 数据库概览数据层（轮7 产品自查诉求：避免「24 vs 6」「60 万行」这类
/// 问题只能靠开发拉包跑脚本才能发现）。
///
/// 口径（工单 §7 钉死）：
/// - 只数行、不取字节（与 F2 同教训——大表全表读入内存是 OOM 源；
///   dbstat 在 sqflite 不一定开启，逐表字节取不到时以行数＋「可再生/占大头」
///   定性标注代替）。
/// - 表清单来自 `sqlite_master` 实表（排 `sqlite_%`），逐表 `COUNT(*)`。
/// - 人话词表 [dbTableLabels] 覆盖全部 schema 实表；机器闸
///   `test/db_overview_guard_test.dart` 钉「每表必有人话名」，新增表未配词即红灯。
/// - 可再生集合复用 [kRegenerableExcluded]（备份恒排除三表，同一事实单一来源）。
/// - 空表不逐条展示，并入「其余 N 张空表」计数。
library;

import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'backup_service.dart' show kRegenerableExcluded;

/// 单表读数（人话标签 + 归属模块 + 行数）。
class DbOverviewRow {
  const DbOverviewRow({
    required this.table,
    required this.label,
    required this.module,
    required this.rows,
  });

  final String table;
  final String label;
  final String module;
  final int rows;
}

/// 一次扫描的结果快照。
class DbOverview {
  const DbOverview({
    required this.rows,
    required this.totalRows,
    required this.regenerableRows,
    required this.byModule,
    required this.emptyTableCount,
  });

  /// 非空表逐行（按行数降序）。
  final List<DbOverviewRow> rows;

  /// 全库记录总行数。
  final int totalRows;

  /// 可再生派生数据行数（[kRegenerableExcluded] 三表合计）。
  final int regenerableRows;

  /// 按模块聚合（仅含行数 > 0 的模块，降序）。
  final List<({String module, int rows, int tables})> byModule;

  /// 空表数量（明细区并成一行「其余 N 张空表」，不逐条展示）。
  final int emptyTableCount;

  /// 可再生占比（0–1；空库=0）。
  double get regenerableRatio =>
      totalRows == 0 ? 0 : regenerableRows / totalRows;
}

/// 活库扫描器：sqlite_master 实表 × 逐表 COUNT(*)。
class DbOverviewScanner {
  const DbOverviewScanner({required this.db});

  final Database db;

  Future<DbOverview> scan() async {
    final found = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name");
    final counts = <String, int>{};
    for (final r in found) {
      final name = r['name'] as String;
      final c = await db.rawQuery('SELECT COUNT(*) AS c FROM "$name"');
      counts[name] = (c.first['c'] as int?) ?? 0;
    }
    return buildOverview(counts);
  }
}

/// 由「表名→行数」组装 [DbOverview]（纯函数，供测试直接喂构造数据）。
DbOverview buildOverview(Map<String, int> counts) {
  var total = 0;
  var regenerable = 0;
  final rows = <DbOverviewRow>[];
  var empty = 0;
  final byModule = <String, ({int rows, int tables})>{};
  for (final e in counts.entries) {
    total += e.value;
    if (kRegenerableExcluded.contains(e.key)) regenerable += e.value;
    final meta = dbTableLabels[e.key];
    // 词表外的表（理论上只可能是运行期新表，守护闸钉 schema 全量）：
    // 原样兜底展示，归「其他」模块，不炸屏。
    final module = meta?.module ?? '其他';
    if (e.value > 0) {
      rows.add(DbOverviewRow(
          table: e.key,
          label: meta?.label ?? e.key,
          module: module,
          rows: e.value));
      final agg = byModule[module];
      byModule[module] =
          (rows: (agg?.rows ?? 0) + e.value, tables: (agg?.tables ?? 0) + 1);
    } else {
      empty++;
    }
  }
  rows.sort((a, b) =>
      b.rows != a.rows ? b.rows.compareTo(a.rows) : a.table.compareTo(b.table));
  final mods = byModule.entries.toList()
    ..sort((a, b) => b.value.rows != a.value.rows
        ? b.value.rows.compareTo(a.value.rows)
        : a.key.compareTo(b.key));
  return DbOverview(
    rows: rows,
    totalRows: total,
    regenerableRows: regenerable,
    byModule: [
      for (final m in mods) (module: m.key, rows: m.value.rows, tables: m.value.tables)
    ],
    emptyTableCount: empty,
  );
}

/// 备份包体积：读 [exportDir] 下最新（mtime）的 `.lhbak` 字节数；
/// 目录不存在/无包 = null（UI 据此隐藏该格，不编造数字）。
Future<int?> latestBackupSizeBytes(String exportDir) async {
  try {
    final dir = Directory(exportDir);
    if (!await dir.exists()) return null;
    int? bestSize;
    int? bestMtime;
    await for (final f in dir.list()) {
      if (f is! File || !f.path.toLowerCase().endsWith('.lhbak')) continue;
      final stat = await f.stat();
      final mtime = stat.modified.millisecondsSinceEpoch;
      if (bestMtime == null || mtime > bestMtime) {
        bestMtime = mtime;
        bestSize = stat.size;
      }
    }
    return bestSize;
  } catch (_) {
    // catch-ok: 体积只是展示读数——目录被外部清理/权限异常时概览少一格读数即可，
    // 非故障路径（导出/导入自有链路留痕），不惊动日志。
    return null;
  }
}

/// 字节 → 人话（MB 优先，不足 1MB 用 KB）。
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}

/// 表名 → 人话标签 + 归属模块。**必须覆盖全部 DbSchema 实表**
/// （新增表未配词 → `test/db_overview_guard_test.dart` 红灯）。
/// X-Ray 可再生三表 label 必须含「可再生」（同闸钉死）。
const Map<String, ({String label, String module})> dbTableLabels = {
  // —— 待办 / 日程 ——
  'todos': (label: '待办事项', module: '待办'),
  // B10（2026-10-13 裁决）：events 数据已一次性并入 time_blocks 并删行退役，本表恒空仅存壳。
  'events': (label: '日程事件（已并入时间块·退役）', module: '日程'),
  // —— 日记 ——
  'journal_entries': (label: '日记条目', module: '日记'),
  'journal_sections': (label: '日记分节', module: '日记'),
  'diary_templates': (label: '日记模板', module: '日记'),
  'template_sections': (label: '模板分节', module: '日记'),
  // 批2b 标签体系：池本体 + 按 id 关联（日记/笔记/时间共用一份池）。
  'tags': (label: '标签池', module: '日记'),
  'tag_links': (label: '标签引用', module: '日记'),
  // —— 笔记 ——
  'notes': (label: '笔记', module: '笔记'),
  'note_snapshots': (label: '版本快照', module: '笔记'),
  'note_folders': (label: '笔记文件夹', module: '笔记'),
  // —— 收集箱 ——
  'inbox_items': (label: '收集箱条目', module: '收集箱'),
  // —— 阅读 ——
  'books': (label: '书籍在册', module: '阅读'),
  'book_sessions': (label: '阅读计时', module: '阅读'),
  'book_quotes': (label: '划线与书摘', module: '阅读'),
  'book_toc_nodes': (label: '目录节点', module: '阅读'),
  'book_dict': (label: '阅读词条', module: '阅读'),
  'book_reviews': (label: '书评', module: '阅读'),
  'book_lists': (label: '书单', module: '阅读'),
  'book_list_items': (label: '书单成员', module: '阅读'),
  'douban_meta': (label: '豆瓣元数据', module: '阅读'),
  'xray_mention': (label: '全书索引 · 可再生', module: '阅读'),
  'xray_entity': (label: '词条实体 · 可再生', module: '阅读'),
  'xray_task': (label: '索引任务 · 可再生', module: '阅读'),
  'xray_userdict': (label: '用户词库', module: '阅读'),
  // —— NFC 卡片（V1.68）——
  // ⚠ 本行是 C8-V3「备份三处登记」的第③处：漏登记 ⇒ 概览屏不显示该表、
  // 恢复报告里是一串无中文标签的英文表名（用户看不懂导出了什么）。
  'nfc_cards': (label: 'NFC 卡片', module: 'NFC'),
  // —— 记账 ——
  'finance_txns': (label: '早期流水', module: '记账'),
  'ledger_books': (label: '账簿', module: '记账'),
  'ledger_txns': (label: '账单流水', module: '记账'),
  'ledger_accounts': (label: '账户', module: '记账'),
  'ledger_categories': (label: '收支分类', module: '记账'),
  'ledger_budgets': (label: '预算', module: '记账'),
  'ledger_fav': (label: '常用分类', module: '记账'),
  'ledger_recur': (label: '周期账单', module: '记账'),
  'ledger_wishes': (label: '心愿存钱', module: '记账'),
  'ledger_debts': (label: '借欠款', module: '记账'),
  'ledger_tag_groups': (label: '标签组', module: '记账'),
  'ledger_tags': (label: '标签', module: '记账'),
  'ledger_whos': (label: '角色', module: '记账'),
  'ledger_merchants': (label: '商家', module: '记账'),
  'ledger_import_batches': (label: '导入批次', module: '记账'),
  // —— 习惯 ——
  'habits': (label: '习惯定义', module: '习惯'),
  'habit_subs': (label: '子习惯', module: '习惯'),
  'habit_entries': (label: '打卡记录', module: '习惯'),
  'habit_entry_subs': (label: '子习惯打卡', module: '习惯'),
  'habit_dict': (label: '习惯词条', module: '习惯'),
  'habit_slips': (label: '补签条', module: '习惯'),
  'habit_freezes': (label: '冻结卡', module: '习惯'),
  'habit_goal_hist': (label: '目标变更历史', module: '习惯'),
  'habit_pend': (label: '待确认打卡', module: '习惯'),
  // —— 呵护 ——
  'care_babies': (label: '宝宝档案', module: '呵护'),
  'care_carers': (label: '照护人', module: '呵护'),
  'care_logs': (label: '照护日志', module: '呵护'),
  'care_cycle_days': (label: '周期记录', module: '呵护'),
  'care_cycle_pred': (label: '周期预测', module: '呵护'),
  'care_measures': (label: '称重生长记录', module: '呵护'),
  'care_vaccines': (label: '疫苗记录', module: '呵护'),
  'care_milestones': (label: '里程碑记录', module: '呵护'),
  'care_allergies': (label: '过敏记录', module: '呵护'),
  'care_custom_events': (label: '自定义事件', module: '呵护'),
  'care_event_order': (label: '事件排序', module: '呵护'),
  // —— 物品 ——
  'items': (label: '物品在册', module: '物品'),
  'item_profiles': (label: '物品档案', module: '物品'),
  'item_events': (label: '物品事件', module: '物品'),
  'item_usages': (label: '使用记录', module: '物品'),
  // —— 目标 ——
  'goals': (label: '目标', module: '目标'),
  'goal_krs': (label: '关键结果 KR', module: '目标'),
  'kr_updates': (label: 'KR 更新', module: '目标'),
  'goal_reviews': (label: '目标复盘', module: '目标'),
  'goal_periods': (label: '目标周期', module: '目标'),
  // —— 日子 ——
  'days': (label: '日子记录', module: '日子'),
  'day_preps': (label: '筹备清单', module: '日子'),
  'reminder_items': (label: '提醒事项', module: '日子'),
  // —— 时间 ——
  'time_blocks': (label: '时间块', module: '时间'),
  // —— 健康 ——
  'health_records': (label: '健康记录', module: '健康'),
  'health_profile': (label: '健康档案', module: '健康'),
  'health_profile_tag': (label: '档案标签', module: '健康'),
  'health_water': (label: '喝水记录', module: '健康'),
  'health_sleep': (label: '睡眠记录', module: '健康'),
  'health_exercise': (label: '运动记录', module: '健康'),
  'health_body': (label: '身体数据', module: '健康'),
  'health_vital': (label: '体征记录', module: '健康'),
  'health_symptom': (label: '症状记录', module: '健康'),
  'health_drug': (label: '用药档案', module: '健康'),
  'health_drug_log': (label: '用药打卡', module: '健康'),
  'health_goal': (label: '健康目标', module: '健康'),
  'health_remind': (label: '健康提醒', module: '健康'),
  'health_report': (label: '健康报告', module: '健康'),
  'health_report_metric': (label: '报告指标', module: '健康'),
  // —— 影音游 ——
  'media_items': (label: '影音条目在册', module: '影音游'),
  'media_sessions': (label: '影音计时', module: '影音游'),
  'media_notes': (label: '影音笔记', module: '影音游'),
  'media_units': (label: '影音子项', module: '影音游'),
  'media_dict': (label: '影音词条', module: '影音游'),
  'media_lists': (label: '影音单', module: '影音游'),
  'media_list_items': (label: '影音单成员', module: '影音游'),
  'media_goals': (label: '影音目标', module: '影音游'),
  // —— 思维导图 ——
  'mindmaps': (label: '思维导图', module: '思维导图'),
  'mindmap_folders': (label: '导图文件夹', module: '思维导图'),
  'mindmap_nodes': (label: '导图节点', module: '思维导图'),
  // —— AI ——
  'ai_calls': (label: 'AI 调用记录', module: 'AI'),
  // —— 设置 / 系统 ——
  'settings': (label: '应用设置项', module: '设置'),
  'categories': (label: '全局分类', module: '设置'),
  'weather_daily': (label: '天气缓存', module: '天气'),
};
