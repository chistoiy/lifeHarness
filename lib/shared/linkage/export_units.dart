/// 备份格式四件套批2 ·「导出单元注册表」（评估件 §8.7 / 工单批2 面板）。
///
/// 职责单一：**模块 → 表清单 → 附件目录 → 投影能力** 的静态映射。
/// 跨模块聚合唯一合法落点＝shared/linkage（R1：features 互不 import；
/// R2：core 不碰 features——本文件只吃 core/schema 常量，零 feature 依赖）。
///
/// 子集排除口径（面板钉子1）：**活库表名差集法**——打包前读 `sqlite_master`
/// 实表，减去所选单元表并集即排除清单。注册表漏列一张表只会让它跟着
/// 「未归属数据」一起留在包里（多备不少备），绝不会误删数据。
library;

import '../../core/database/schema.dart';
// health / care 的表常量未上收 DbSchema 静态（域库 G5 惯例），直引域文件。
import '../../core/database/schema/care.dart' as care;
import '../../core/database/schema/health.dart' as health;
import '../../core/database/schema/media.dart' as media;

/// 一个可导出单元（＝宫格里的一个模块在备份域的投影）。
class ExportUnit {
  const ExportUnit({
    required this.id,
    required this.label,
    required this.tables,
    this.attachDirNames = const [],
    this.noteLike = false,
    this.timeRoots = const [],
    this.timeRules = const [],
  });

  /// 模块 id（ExportSheet chips 与面板状态用）。
  final String id;

  /// 人话标签（UI 逐字）。
  final String label;

  /// 本模块全部表（整组闭包，评估件 §8.6·2）。
  final List<String> tables;

  /// 本模块的附件目录基名（打包/预估体积按此映射；exports/share 等非模块
  /// 数据目录不在此列——只有「全部数据」才进包）。
  final List<String> attachDirNames;

  /// 是否含笔记类数据（md 投影开关的可用性判据，原型 EX_NOTEY 同口径）。
  final bool noteLike;

  /// 时间维度的**根表集合**（该单元所有筛选由这些表的时间列发起）。
  /// 空＝该单元无时间列，时间维度对其不生效（面板须明说而非静默忽略）。
  /// **单元内允许多根**（日记＝`journal_entries.entry_date` ＋ `notes.created_at`
  ///：日记按业务日筛，笔记按创建日筛，两者时间语义本就不同）。
  final List<ExportTimeRoot> timeRoots;

  /// 根表之外的表级规则（子表随主表走＝评估件 §8.6·2 表闭包的延伸）。
  /// 未列出的表＝**恒全量**（维度表/容器表/跨单元悬挂引用，见工单 §1）。
  final List<ExportTimeRule> timeRules;

  /// 该单元是否支持时间筛选（= 至少有一个根表）。
  bool get timeFilterable => timeRoots.isNotEmpty;
}

/// 一张根表与其时间列。
class ExportTimeRoot {
  const ExportTimeRoot(this.table, this.column, {this.textDate = false});

  /// 根表表名。
  final String table;

  /// 时间列。**口径＝优先业务日列（date/day/entry_date/event_date），无业务日
  /// 才用 created_at**——「导出今年账目」按记账 `date`（业务日），不是按
  /// 录入时刻（评估件 §8.5 只写「吃 created_at/date 列」未定哪个，
  /// 工单 §1 Q1/Q4 口径精化）。
  final String column;

  /// 该列是否存 **`YYYY-MM-DD` 文本日**（记账 `ledger_txns.date`、呵护
  /// `care_logs.day`、习惯 `habit_entries.day` 皆此类）而非毫秒时间戳。
  /// 实锤坑：本库两型并存，若一律按 INTEGER 比大小，TEXT 列会因类型亲和
  /// 规则被整列筛空（`'2026-01-01' BETWEEN 1767225600000 AND …` 恒假）。
  final bool textDate;
}

/// 一张表的「随主表走」规则。
class ExportTimeRule {
  const ExportTimeRule(this.table, this.viaTable, this.viaColumn);

  /// 本表表名。
  final String table;

  /// 父表表名（须与本表同属一个导出单元；跨单元引用一律不跟，保留原样）。
  final String viaTable;

  /// 本表中指向父表主键的列（多为 `*_id`；容器表用其成员列）。
  final String viaColumn;
}

/// 12 个导出单元（原型 EX_MODULES 逐字对齐；顺序即 chips 展示序）。
const List<ExportUnit> kExportUnits = [
  ExportUnit(
    id: 'read',
    label: '阅读',
    tables: [
      DbSchema.tBooks,
      DbSchema.tBookSessions,
      DbSchema.tBookQuotes,
      DbSchema.tBookTocNodes,
      DbSchema.tBookDict,
      DbSchema.tBookReviews,
      DbSchema.tBookLists,
      DbSchema.tBookListItems,
      DbSchema.tDoubanMeta,
    ],
    attachDirNames: ['book_covers'],
    noteLike: true, // 书摘投影
    // 根表＝books 的 created_at（Q1 拍板＝建档日，非阅读日；阅读日需跨表
    // 子查询，且「导出近 1 年读过的书」与「导出近 1 年建的档」两种语义
    // 择一，取与其它单元一致的「记录创建时间」口径）。
    timeRoots: [ExportTimeRoot(DbSchema.tBooks, 'created_at')],
    timeRules: [
      ExportTimeRule(DbSchema.tBookSessions, DbSchema.tBooks, 'book_id'),
      ExportTimeRule(DbSchema.tBookQuotes, DbSchema.tBooks, 'book_id'),
      ExportTimeRule(DbSchema.tBookTocNodes, DbSchema.tBooks, 'book_id'),
      ExportTimeRule(DbSchema.tBookListItems, DbSchema.tBooks, 'book_id'),
      // reviews 随 quotes（quote_id），quotes 随 books → 递归闭包。
      ExportTimeRule(DbSchema.tBookReviews, DbSchema.tBookQuotes, 'quote_id'),
      // book_lists 是容器表：随其成员走（只留有命中书的清单），避免空壳清单。
      ExportTimeRule(DbSchema.tBookLists, DbSchema.tBookListItems, 'list_id'),
      // book_dict / douban_meta 恒全量（字典与外部元数据缓存）。
    ],
  ),
  ExportUnit(
    id: 'journal',
    label: '日记',
    tables: [
      DbSchema.tJournal,
      DbSchema.tJournalSections,
      DbSchema.tDiaryTemplates,
      DbSchema.tTemplateSections,
      DbSchema.tNotes,
      DbSchema.tNoteSnapshots,
      DbSchema.tNoteFolders,
    ],
    attachDirNames: ['note_images'],
    noteLike: true, // 笔记/日记投影
    // 根＝journal_entries.entry_date（日记业务日，不是 created_at——按
    // created_at 筛会把「去年写的日记」在「导出今年」时漏掉）＋
    // notes.created_at（笔记无业务日，用创建时间）。单元内多根。
    timeRoots: [
      ExportTimeRoot(DbSchema.tJournal, 'entry_date'),
      ExportTimeRoot(DbSchema.tNotes, 'created_at'),
    ],
    timeRules: [
      ExportTimeRule(DbSchema.tJournalSections, DbSchema.tJournal, 'entry_id'),
      ExportTimeRule(DbSchema.tNoteSnapshots, DbSchema.tNotes, 'note_id'),
      // diary_templates / template_sections / note_folders 恒全量
      // （模板与目录是配置，不是时间序列数据）。
    ],
  ),
  ExportUnit(
    id: 'health',
    label: '健康',
    tables: DbSchema.healthTables,
    // 健康是「一模块多根」的最典型：14 张表里 11 张各有自己的业务日 `date`
    // （喝水/睡眠/运动/体重/用药记录/体征/症状/报告/提醒），档案与目标、
    // 报告明细无业务日 → 恒全量。**不设单一根表**（否则九张表会跟着
    // 一张表的日期走，导出结果自相矛盾）。
    timeRoots: [
      ExportTimeRoot(health.tHealthWater, 'date', textDate: true),
      ExportTimeRoot(health.tHealthSleep, 'date', textDate: true),
      ExportTimeRoot(health.tHealthExercise, 'date', textDate: true),
      ExportTimeRoot(health.tHealthBody, 'date', textDate: true),
      ExportTimeRoot(health.tHealthDrugLog, 'date', textDate: true),
      ExportTimeRoot(health.tHealthVital, 'date', textDate: true),
      ExportTimeRoot(health.tHealthSymptom, 'date', textDate: true),
      ExportTimeRoot(health.tHealthReport, 'date', textDate: true),
      ExportTimeRoot(health.tHealthRemind, 'date', textDate: true),
      // 用药主表按开药日（created_at；end_date 是停药日＝未来日期，
      // 用它筛会把「仍在吃的药」全部筛掉）。
      ExportTimeRoot(health.tHealthDrug, 'created_at'),
      // health_profile / health_profile_tag / health_goal /
      // health_report_metric 恒全量（档案/目标态/报告明细）。
    ],
  ),
  ExportUnit(
    id: 'ledger',
    label: '记账',
    tables: [
      DbSchema.tFinance,
      DbSchema.tLedgerBooks,
      DbSchema.tLedgerTxns,
      DbSchema.tLedgerAccounts,
      DbSchema.tLedgerCategories,
      DbSchema.tLedgerBudgets,
      DbSchema.tLedgerFav,
      DbSchema.tLedgerRecur,
      DbSchema.tLedgerWishes,
      DbSchema.tLedgerDebts,
      DbSchema.tLedgerTagGroups,
      DbSchema.tLedgerTags,
      DbSchema.tLedgerWhos,
      DbSchema.tLedgerMerchants,
      DbSchema.tLedgerImportBatches,
    ],
    // 根＝ledger_txns.date（业务日）。**账套/分类/标签/账户/商家/预算/
    // 周期/愿望/债务/常转/导入批次恒全量**＝维度表：筛掉会让流水指向
    // 不存在的分类与账户（评估件 §8.6·3 的悬挂引用坑）。
    timeRoots: [ExportTimeRoot(DbSchema.tLedgerTxns, 'date', textDate: true)],
  ),
  ExportUnit(
    id: 'care',
    label: '呵护',
    tables: DbSchema.careTables,
    // 记录类表按 `day`（业务日，毫秒时间戳）；care_vaccines 的 done_day
    // 是「几号」无年份 → 改按 created_at；care_cycle_pred 是**预测**表
    // （ov_day 几号）→ 恒全量；babies/carers/custom_events/event_order 是
    // 档案与配置 → 恒全量。
    timeRoots: [
      ExportTimeRoot(care.tCareLogs, 'day', textDate: true),
      ExportTimeRoot(care.tCareMeasures, 'day', textDate: true),
      ExportTimeRoot(care.tCareCycleDays, 'day', textDate: true),
      ExportTimeRoot(care.tCareMilestones, 'day', textDate: true),
      ExportTimeRoot(DbSchema.tCareAllergies, 'created_at'),
      ExportTimeRoot(DbSchema.tCareVaccines, 'created_at'),
    ],
  ),
  ExportUnit(
    id: 'habit',
    label: '习惯',
    tables: [
      DbSchema.tHabits,
      DbSchema.tHabitSubs,
      DbSchema.tHabitEntries,
      DbSchema.tHabitEntrySubs,
      DbSchema.tHabitDict,
      DbSchema.tHabitSlips,
      DbSchema.tHabitFreezes,
      DbSchema.tHabitGoalHist,
      DbSchema.tHabitPend,
    ],
    // 根＝habit_entries.day（打卡业务日）。habits 自身恒全量＝**打卡习惯
    // 定义是配置**（筛掉会导致「有记录但习惯不存在」的孤儿行）。
    // slips/freezes/pend 各有自己的 day → 一并作根。
    timeRoots: [
      ExportTimeRoot(DbSchema.tHabitEntries, 'day', textDate: true),
      ExportTimeRoot(DbSchema.tHabitSlips, 'day', textDate: true),
      ExportTimeRoot(DbSchema.tHabitFreezes, 'day', textDate: true),
      ExportTimeRoot(DbSchema.tHabitPend, 'day', textDate: true),
    ],
    timeRules: [
      ExportTimeRule(DbSchema.tHabitEntrySubs, DbSchema.tHabitEntries, 'entry_id'),
    ],
  ),
  ExportUnit(
    id: 'goals',
    label: '目标',
    tables: [
      DbSchema.tGoals,
      DbSchema.tGoalKrs,
      DbSchema.tKrUpdates,
      DbSchema.tGoalReviews,
      DbSchema.tGoalPeriods,
    ],
    // 根＝goals.created_at；kr_updates 有自己的 created_at → 第二根。
    // goal_krs **恒全量**（KR 定义挂在目标下，滤掉即孤儿行）。
    timeRoots: [
      ExportTimeRoot(DbSchema.tGoals, 'created_at'),
      ExportTimeRoot(DbSchema.tKrUpdates, 'created_at'),
    ],
  ),
  ExportUnit(
    id: 'items',
    label: '物品',
    tables: [
      DbSchema.tItems,
      DbSchema.tItemProfiles,
      DbSchema.tItemEvents,
      DbSchema.tItemUsages,
    ],
    // 根＝items.created_at（档案建档日）＋ item_events.event_date（事件
    // 业务日）＋ item_usages.day。item_profiles 恒全量＝物品档案/详情快照。
    timeRoots: [
      ExportTimeRoot(DbSchema.tItems, 'created_at'),
      ExportTimeRoot(DbSchema.tItemEvents, 'event_date', textDate: true),
      ExportTimeRoot(DbSchema.tItemUsages, 'day', textDate: true),
    ],
  ),
  ExportUnit(
    id: 'media',
    label: '影音游',
    // media 表常量未上收 DbSchema 静态（域库 G5 惯例），直引域文件。
    tables: [
      media.tMediaItems,
      media.tMediaSessions,
      media.tMediaNotes,
      media.tMediaUnits,
      media.tMediaDict,
      media.tMediaLists,
      media.tMediaListItems,
      media.tMediaGoals,
    ],
    // 根＝media_items.created_at ＋ media_sessions.started_at（消费记录，
    // 与建档日不同义）＋ media_notes.created_at。units/notes/list_items
    // 随主表；dict 恒全量（词库配置）；lists 随其成员；goals 恒全量。
    timeRoots: [
      ExportTimeRoot(media.tMediaItems, 'created_at'),
      ExportTimeRoot(media.tMediaSessions, 'started_at'),
      ExportTimeRoot(media.tMediaNotes, 'created_at'),
    ],
    timeRules: [
      ExportTimeRule(media.tMediaUnits, media.tMediaItems, 'item_id'),
      ExportTimeRule(media.tMediaListItems, media.tMediaItems, 'item_id'),
      ExportTimeRule(media.tMediaLists, media.tMediaListItems, 'list_id'),
    ],
  ),
  // X-Ray：可再生解析产物（mention/entity/task）在打包层恒排除
  // （kRegenerableExcluded），可导出的只有词库 xray_userdict——表清单
  // 只列词库，解析产物即便「全选」也照旧排除（评估件 §8.6·6 同口径）。
  ExportUnit(
    id: 'xray',
    label: 'X-Ray',
    tables: [DbSchema.tXrayUserdict],
    // 词库按入库时间 create_time 筛（可再生解析产物恒排除，见上注）。
    timeRoots: [ExportTimeRoot(DbSchema.tXrayUserdict, 'create_time')],
  ),
  ExportUnit(
    id: 'mindmap',
    label: '思维导图',
    tables: [
      DbSchema.tMindmaps,
      DbSchema.tMindmapNodes,
      DbSchema.tMindmapFolders,
    ],
    noteLike: true, // 导图大纲投影
    // 根＝mindmaps.created_at ＋ mindmap_nodes.created_at（节点自带）。
    // mindmap_folders 恒全量＝目录配置；node_id 指向笔记属**跨单元**引用
    // （笔记在 journal 单元），按评估件 §8.6·3 取「保留空引用」：不跨单元
    // 带上下文，避免只导导图却拖进整个笔记库。
    timeRoots: [
      ExportTimeRoot(DbSchema.tMindmaps, 'created_at'),
      ExportTimeRoot(DbSchema.tMindmapNodes, 'created_at'),
    ],
  ),
  ExportUnit(
    id: 'ai',
    label: 'AI 记录',
    tables: [DbSchema.tAiCalls],
    // **本单元唯一不按时间筛的单元**（原型 EX_NOTIME 已过门：「AI 记录 无
    // 时间字段，不按时间筛选」）。
    // 明说一处实况差异（不作静默处理）：`ai_calls.ts` 确有值且是**毫秒时间
    // 戳**（写入点 `ai_service.dart:111`＝`DateTime.now().millisecondsSinceEpoch`），
    // 列名不叫 `_at/_date`，初版枚举按命名扫列时漏掉了它。此处**故意不用它
    // 作根**：AI 调用流水是排障日志，用户心智里「按时间筛 AI 记录」无意义，
    // 且面板文案已过产品门。若日后产品要开，只需在 timeRoots 加一行
    // `ExportTimeRoot(DbSchema.tAiCalls, 'ts')` 并去掉原型 EX_NOTIME 一行。
  ),
  ExportUnit(
    id: 'nfc',
    label: 'NFC 卡片',
    tables: [DbSchema.tNfcCards],
    // **本行是 C8-V3「备份三处登记」的第②处**：漏登记 ⇒ 子集备份走差集法时不收本表
    // ⇒ 换机恢复后同一张物理标签不可用（C8「进备份包」的全部意义落空）。
    // 守护＝backup_scope_test 的第②条断言。
    // timeRoots 留空＝该单元无时间筛语义（用户心智是「我的卡片」不是流水），
    // 面板按既有口径明说「不生效」而非静默忽略（同 AI 单元取舍）。
  ),
];

/// 按 id 找单元（未知 id = null，调用方按「未归属」处理）。
ExportUnit? exportUnitById(String id) {
  for (final u in kExportUnits) {
    if (u.id == id) return u;
  }
  return null;
}

/// 所选模块的表并集（空 = 全部数据，调用方不走差集法）。
Set<String> exportTablesForModules(Iterable<String> ids) => {
      for (final id in ids)
        ...?exportUnitById(id)?.tables,
    };

/// 所选模块的附件目录基名并集（子集打包只收这些目录）。
Set<String> exportAttachDirsForModules(Iterable<String> ids) => {
      for (final id in ids)
        ...?exportUnitById(id)?.attachDirNames,
    };

/// 所选范围是否含笔记类数据（md 开关可用性；空 = 全部数据＝可用）。
bool exportMdAvailable(Iterable<String> ids) {
  final list = ids.toList();
  if (list.isEmpty) return true;
  return list.any((id) => exportUnitById(id)?.noteLike ?? false);
}

// ─────────────────────────── 时间维度（余量批3） ───────────────────────────

/// 一张表在给定时间范围下的筛选计划。
class ExportTimeFilter {
  const ExportTimeFilter({
    required this.table,
    required this.whereSql,
    required this.args,
  });

  /// 表名。
  final String table;

  /// `WHERE` 片段（**不含 `WHERE` 关键字**，参数一律走 [args] 占位符绑定）。
  final String whereSql;

  /// 绑定参数（顺序与 [whereSql] 中 `?` 出现顺序一致）。
  final List<Object> args;
}

/// 解析一张表的筛选谓词：根表按自身时间列直接比；子表走 `IN (父表…)`
/// 递归闭包。返回 null＝该表在所选范围里**恒全量**（维度表/容器表/
/// 跨单元悬挂引用/无规则表）。
///
/// 谓词与绑定参数**同一次遍历产出**（`('col' BETWEEN ? AND ?, [from, to])`
/// 逐层上抛）——两趟分别走会在多层闭包下错位，故不拆。
({String sql, List<Object> args})? _resolvePredicate(
  ExportUnit unit,
  String table,
  DateTime from,
  DateTime to,
  Set<String> visiting,
) {
  for (final root in unit.timeRoots) {
    if (root.table == table) {
      // TEXT 日列按 `YYYY-MM-DD` 字典序比（该格式字典序＝时序，可直接比）；
      // 其余按毫秒时间戳比大小。两型混用会静默筛空（见 textDate 注）。
      return root.textDate
          ? (
              sql: '"${root.column}" BETWEEN ? AND ?',
              args: <Object>[dayKey(from), dayKey(to)],
            )
          : (
              sql: '"${root.column}" BETWEEN ? AND ?',
              args: <Object>[
                // 上下界都归一到「当日整日」：止端点含当日 23:59:59.999，
                // 下界取当日 00:00:00.000（闭区间口径，与 UI 一致）。下界不归一
                // 的话，近 1/3 年档带入的时分秒会让当天零点后的记录被静默漏掉。
                DateTime(from.year, from.month, from.day).millisecondsSinceEpoch,
                DateTime(to.year, to.month, to.day, 23, 59, 59, 999)
                    .millisecondsSinceEpoch,
              ],
            );
    }
  }
  if (!visiting.add(table)) return null; // 环防护（配置错误时退化为恒全量）
  for (final rule in unit.timeRules) {
    if (rule.table != table) continue;
    // 父表必须同属本单元，否则视为跨单元引用＝不跟（评估件 §8.6·3）。
    if (!unit.tables.contains(rule.viaTable)) return null;
    final parent = _resolvePredicate(unit, rule.viaTable, from, to, visiting);
    if (parent == null) return null;
    return (
      sql: '"${rule.viaColumn}" IN '
          '(SELECT "id" FROM "${rule.viaTable}" WHERE ${parent.sql})',
      args: parent.args,
    );
  }
  return null;
}

/// `YYYY-MM-DD` 日键（与 careDayKey / dayKey 同格式，全库 TEXT 日列统一口径）。
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 生成所选模块在时间范围内的筛选计划（表 → 谓词）。
///
/// **恒全量表不进结果**（它们的行数与内容不随时间变）——调用方对不在
/// 结果里的表一律不施加任何 WHERE。空 [ids] ＝ 全部数据＝遍历 12 单元。
Map<String, ExportTimeFilter> exportTimeFilters(
  Iterable<String> ids, {
  required DateTime from,
  required DateTime to,
}) {
  final units = ids.isEmpty
      ? kExportUnits
      : [
          for (final id in ids)
            if (exportUnitById(id) != null) exportUnitById(id)!
        ];
  final out = <String, ExportTimeFilter>{};
  for (final u in units) {
    for (final t in u.tables) {
      if (out.containsKey(t)) continue;
      final r = _resolvePredicate(u, t, from, to, <String>{});
      if (r == null) continue;
      out[t] = ExportTimeFilter(table: t, whereSql: r.sql, args: r.args);
    }
  }
  return out;
}

/// 所选范围里**不可按时间筛选**的单元 label 清单（空 = 全部可筛）。
/// 面板据此出「XX 无时间字段，不按时间筛选」提示行——明说而非静默忽略。
List<String> exportTimeUnfilterableLabels(Iterable<String> ids) => [
      for (final u in (ids.isEmpty
          ? kExportUnits
          : [for (final id in ids) if (exportUnitById(id) != null) exportUnitById(id)!]))
        if (!u.timeFilterable) u.label,
    ];

/// 时间范围内的表清单（恒全量表不在其中；调用方只对这些表施加谓词）。
Set<String> exportTimeFilteredTables(Iterable<String> ids,
        {required DateTime from, required DateTime to}) =>
    exportTimeFilters(ids, from: from, to: to).keys.toSet();

