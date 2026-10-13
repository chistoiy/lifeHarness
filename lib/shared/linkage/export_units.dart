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
import '../../core/database/schema/media.dart' as media;

/// 一个可导出单元（＝宫格里的一个模块在备份域的投影）。
class ExportUnit {
  const ExportUnit({
    required this.id,
    required this.label,
    required this.tables,
    this.attachDirNames = const [],
    this.noteLike = false,
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
  ),
  ExportUnit(
    id: 'health',
    label: '健康',
    tables: DbSchema.healthTables,
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
  ),
  ExportUnit(
    id: 'care',
    label: '呵护',
    tables: DbSchema.careTables,
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
  ),
  ExportUnit(
    id: 'media',
    label: '影音游',
    // media 表常量未上收 DbSchema 静态（域库 G5 惯例），直引域文件。
    tables: const [
      media.tMediaItems,
      media.tMediaSessions,
      media.tMediaNotes,
      media.tMediaUnits,
      media.tMediaDict,
      media.tMediaLists,
      media.tMediaListItems,
      media.tMediaGoals,
    ],
  ),
  // X-Ray：可再生解析产物（mention/entity/task）在打包层恒排除
  // （kRegenerableExcluded），可导出的只有词库 xray_userdict——表清单
  // 只列词库，解析产物即便「全选」也照旧排除（评估件 §8.6·6 同口径）。
  ExportUnit(
    id: 'xray',
    label: 'X-Ray',
    tables: [DbSchema.tXrayUserdict],
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
  ),
  ExportUnit(
    id: 'ai',
    label: 'AI 记录',
    tables: [DbSchema.tAiCalls],
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
